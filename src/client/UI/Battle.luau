--[[
	전투 화면.

	이 모듈은 "지금 상태를 그린다" 만 한다. 무엇을 눌렀을 때 어떤 행동이 되는지는
	전부 Controller 가 정한다. 그래서 여기에는 룰 판정이 한 줄도 없다 —
	하이라이트할 카드 목록조차 Controller 가 계산해서 넘겨준다.

	렌더링은 매번 화면 전체를 훑는다 — "서버 상태 = 화면" 이 어긋날 여지가 없다.
	다만 **카드는 지웠다 다시 만들지 않는다.** 같은 카드는 같은 인스턴스를 계속 쓰고
	내용만 갈아끼운다 (Reconcile.luau). 그래야 카드에 연출을 붙일 수 있다 —
	날아가는 도중에 다음 스냅샷이 와도 그 카드가 사라지지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local CardView = require(script.Parent.CardView)
local Reconcile = require(script.Parent.Reconcile)
local Motion = require(script.Parent.Motion)

local new = Widgets.new
local Enums = Rules.Enums
local GameState = Rules.GameState
local Registry = Rules.Registry
local Phase = Enums.Phase

--[[
	"나" 와 "상대" 는 고정된 번호가 아니다. PvP 에서 나는 1번 좌석일 수도 2번일 수도 있고,
	그건 서버가 스냅샷의 viewerId 로 알려준다. render 가 매번 여기에 채워 넣는다.

	기본값 1/2 는 첫 스냅샷이 오기 전(빈 화면)에만 쓰인다.
]]
local DEFAULT_ME, DEFAULT_FOE = 1, 2

local PHASE_TRACK = { Phase.Main, Phase.AttackPrep, Phase.DefensePrep }

local LOSS_REASON = {
	LifeDepleted = "라이프 소진",
	DeckOut = "덱 아웃",
	Concede = "항복",
}

local Battle = {}
Battle.__index = Battle

--==========================================================================
-- 뼈대
--==========================================================================

function Battle.new(parent)
	local self = setmetatable({}, Battle)

	-- Controller 가 채워 넣는다. 기본값은 아무것도 하지 않는 함수.
	local noop = function() end
	self.callbacks = {
		handCard = noop,
		fieldCard = noop,
		player = noop,
		stackItem = noop,
		action = noop,
		inspect = noop, -- 카드를 들여다봤다 (튜토리얼이 이걸 본다)
	}

	self.logOpen = false
	self.toastToken = 0
	self.flashToken = 0

	--[[
		연출은 "무엇이 **바뀌었는가**" 를 봐야 하는데, 스냅샷은 현재 상태만 온다.
		그래서 직전 값을 여기에 들고 비교한다. 첫 렌더에는 비어 있으므로
		판이 시작하자마자 배너나 피해 숫자가 튀지 않는다.
	]]
	self.lastTurnKey = nil
	self.lastLife = {}
	self.lastStackIds = {}
	self.stackSeeded = false
	self.spotlightToken = 0

	--[[
		줄마다 "지금 무엇이 어떤 차례로 놓여 있나" 를 기억한다. 창 크기가 바뀌면
		렌더를 기다리지 않고 여기 기록으로 다시 배치해야 한다 — 안 그러면 창을
		줄이는 동안 카드가 옛 자리에 남는다.

		freshCards 는 **이번에 새로 생긴 카드** 표시다. 약한 키라 카드가 사라지면
		표시도 같이 사라진다. Reconcile 의 enter 가 찍고 placeRow 가 지운다.
	]]
	self.rows = {}
	self.freshCards = setmetatable({}, { __mode = "k" })
	self.me, self.foe = DEFAULT_ME, DEFAULT_FOE

	self:build(parent)

	--[[
		화살표는 매 프레임 다시 그린다. 렌더 한 번에 그려두면 안 된다 —
		그 시점에는 레이아웃이 아직 안 잡혀 카드의 절대 좌표가 0 이다.
	]]
	task.spawn(function()
		while self.gui.Parent do
			self:drawArrows()
			task.wait()
		end
	end)

	return self
end

--[[
	전투 화면을 켜고 끈다. 시작 화면과 번갈아 뜨므로 App 이 이걸로 전환한다.
	Destroy 하지 않는 이유: 매치마다 UI 를 다시 만들면 첫 프레임이 눈에 띄게 늦다.
]]
function Battle:setVisible(visible)
	self.gui.Enabled = visible
	if not visible then
		self.logPanel.Visible = false
		self.logOpen = false
	end
end

function Battle:build(parent)
	local gui = new("ScreenGui", {
		Name = "TCGBattle",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		Parent = parent,
	})
	self.gui = gui

	local root = new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color.bg,
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		new("UIGradient", {
			Color = ColorSequence.new(Theme.color.bgDeep, Theme.color.bg),
			Rotation = 90,
		}),
	})

	-- 창 크기에 맞춰 화면 전체를 늘렸다 줄인다. (Size 도 여기서 다시 정해진다)
	self.uiScale = Widgets.autoScale(root)

	--------------------------------------------------------------------
	-- 상단 바
	--------------------------------------------------------------------
	local topBar = Widgets.panel({
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, Theme.size.topBar),
		BackgroundColor3 = Theme.color.bgDeep,
		Parent = root,
	}, {
		Widgets.padding(0, { PaddingLeft = 14, PaddingRight = 14 }),
	})

	self.turnLabel = Widgets.label("", {
		Name = "Turn",
		Parent = topBar,
		Size = UDim2.new(0, 240, 1, 0),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
	})

	self.phaseTrack = new("Frame", {
		Name = "PhaseTrack",
		Parent = topBar,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 460, 1, 0),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center),
	})

	-- 단축키 안내. 마우스만으로도 전부 되지만 손이 빨라지면 키가 편하다.
	self.seedLabel = Widgets.label("E 페이즈 종료 · P 패스 · Esc 취소 · L 로그", {
		Name = "Shortcuts",
		Parent = topBar,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 260, 1, 0),
		TextSize = Theme.text.small,
		TextColor3 = Theme.color.textFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	--------------------------------------------------------------------
	-- 본문 (좌: 보드 / 우: 행동 바)
	--------------------------------------------------------------------
	local body = new("Frame", {
		Name = "Body",
		Parent = root,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, Theme.size.topBar),
		Size = UDim2.new(1, 0, 1, -(Theme.size.topBar + Theme.size.handBar)),
	})

	--[[
		보드 테두리가 "지금 누구 차례인가" 를 말한다.

		예전에는 그 정보가 오른쪽 행동 바의 작은 라벨 하나뿐이었다. 카드를 보고 있으면
		시야 밖이라, 상대 차례에 카드를 누르고 나서야 거부 메시지로 알게 됐다.
		화면에서 가장 큰 도형에 색을 입히면 어디를 보고 있어도 주변시로 들어온다.
	]]
	local board = new("Frame", {
		Name = "Board",
		Parent = body,
		BackgroundColor3 = Theme.color.bg,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -Theme.size.actionBar, 1, 0),
	}, {
		Widgets.padding(10),
		Widgets.corner(10),
	})
	self.boardStroke = Widgets.stroke(Theme.color.stroke, 2)
	self.boardStroke.Parent = board

	--[[
		턴이 바뀔 때 보드 한가운데 잠깐 뜨는 글자.

		행동 바의 "내 차례" 라벨과 **다른 것**이다. 저쪽은 지금 상태를 계속 말하고,
		이건 바뀌는 순간에만 한 번 나타난다 — 카드를 보고 있어도 턴이 넘어간 것을
		놓치지 않게 하는 게 목적이라, 화면에서 눈이 가장 자주 가는 자리에 크게 띄운다.

		TextLabel 이라 클릭을 가로채지 않는다. 보드 위에 겹쳐 떠 있어도 그 아래
		카드를 그대로 누를 수 있다.
	]]
	self.turnFlashHome = UDim2.fromScale(0.5, 0.5)
	self.turnFlash = Widgets.label("", {
		Name = "TurnFlash",
		Parent = board,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = self.turnFlashHome,
		Size = UDim2.new(1, 0, 0, 60),
		Font = Theme.font.bold,
		TextSize = Theme.text.flash,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		ZIndex = 20,
	})

	self.board = board

	--[[
		상대가 낸 카드를 크게 보여주는 자리.

		카드 상세(우클릭으로 보는 것)와 **같은 위젯**을 쓴다. 같은 정보를 두 벌로
		만들면 한쪽만 고쳐지는 날이 온다. 저건 버튼이 아니라 패널이라 그 아래
		카드를 가리기만 하고 클릭을 가로채지도 않는다.

		읽을 시간을 주는 게 목적이다 — 대응 패스를 사람이 직접 누르기로 한 것과 같은 이유.
	]]
	self.spotlight = CardView.detail({
		--[[
			이름을 나눠준다. 기본값 그대로 두면 화면 안에 "Detail" 상자가 둘이 되고,
			이름으로 찾는 쪽(테스트·튜토리얼)이 트리에서 앞선 이것을 집어간다.
		]]
		Name = "Spotlight",
		Parent = board,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 22,
	})

	local panelHeight = Theme.size.playerPanel
	local rowHeight = Theme.size.fieldRow
	local half = panelHeight + rowHeight + 8 -- 패널 + 필드 + 사이 여백

	self.foePanel = self:makePlayerPanel(board, "foe", UDim2.fromOffset(0, 0))
	self.foeField = self:makeFieldRow(board, "FoeField", UDim2.new(0, 0, 0, panelHeight + 8))

	self.center = new("Frame", {
		Name = "Center",
		Parent = board,
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, half + 8),
		Size = UDim2.new(1, 0, 1, -(half * 2 + 16)),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Center),
	})

	self.myField = self:makeFieldRow(board, "MyField", UDim2.new(0, 0, 1, -half))
	self.myPanel = self:makePlayerPanel(board, "me", UDim2.new(0, 0, 1, -panelHeight))

	--[[
		전투 화살표를 그리는 판. 보드 위에 겹쳐 놓는다.

		Active 를 켜지 않으므로 입력을 가로채지 않는다 — 화살표 위로도 카드가 눌린다.
		ZIndex 는 카드보다 위, 상세·결과 화면(25 이상)보다 아래다.
	]]
	self.arrows = new("Frame", {
		Name = "Arrows",
		Parent = board,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 15,
	})

	self:makeActionBar(body)

	--------------------------------------------------------------------
	-- 손패
	--------------------------------------------------------------------
	local handBar = Widgets.panel({
		Name = "HandBar",
		Parent = root,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, Theme.size.handBar),
		BackgroundColor3 = Theme.color.bgDeep,
	})

	self.handRow = new("ScrollingFrame", {
		Name = "Hand",
		Parent = handBar,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 1, -16),
		Position = UDim2.fromOffset(12, 8),
		CanvasSize = UDim2.new(),
		--[[
			부채꼴로 기울면 카드 모서리가 줄 높이를 넘는다(116x170 을 5도 기울이면
			세로로 8px 쯤 커진다). 잘라내면 모서리가 싹둑 잘려 보이므로 넘치게 둔다.
			가로 스크롤은 CanvasSize 로 도므로 클리핑을 꺼도 그대로 돈다.
		]]
		ClipsDescendants = false,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.color.stroke,
	}, {
	})

	self:watchRowSize(self.handRow)

	--------------------------------------------------------------------
	-- 겹쳐 뜨는 것들
	--------------------------------------------------------------------
	self:makeToast(root)
	self:makeLogPanel(root)
	self:makeEndOverlay(root)

	--[[
		카드 상세. 덱 편집과 **같은 상자**다 — 같은 카드를 어디서 열든 같은 설명이
		나와야 한다. 태그가 무슨 효과인지도 여기서 읽는다.

		오른쪽에는 행동 바가 있으므로 왼쪽에 띄운다.
	]]
	self.detail = CardView.detail({
		Parent = root,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.5, 0),
		ZIndex = 25,
	})
end

--==========================================================================
-- 뼈대 조각
--==========================================================================

--[[
	slot 은 "me" / "foe" — 화면의 아래칸/위칸이다. 좌석 번호가 아니다.
	누를 때 어느 좌석을 가리키는지는 그 시점의 self.me / self.foe 가 정한다.
]]
function Battle:makePlayerPanel(parent, slot, position)
	local isMe = (slot == "me")
	local accent = isMe and Theme.color.me or Theme.color.foe

	local panel = Widgets.panel({
		Name = isMe and "MyPanel" or "FoePanel",
		Parent = parent,
		Position = position,
		Size = UDim2.new(1, 0, 0, 92),
	}, {
		Widgets.padding(10),
	})

	-- 대상 지정 때 눌러야 하므로 패널 전체가 버튼이다.
	local hit = new("TextButton", {
		Name = "Hit",
		Parent = panel,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
	})
	hit.Activated:Connect(function()
		self.callbacks.player(if isMe then self.me else self.foe)
	end)

	local name = Widgets.label("", {
		Name = "PlayerName",
		Parent = panel,
		Size = UDim2.new(0, 240, 0, 22),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		TextColor3 = accent,
	})

	local life = Widgets.label("", {
		Name = "Life",
		Parent = panel,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(0, 118, 0, 40),
		Font = Theme.font.bold,
		TextSize = Theme.text.life,
	})

	--[[
		쓸 수 있는 코스트는 매 턴 가장 자주 확인하는 숫자인데, 예전에는 오른쪽
		"패 7장 덱 53장 코스트 3/5" 한 줄 안에 12px 로 묻혀 있었다.
		라이프 옆에 따로 떼어내 테두리를 둘렀다.
	]]
	local costBox = Widgets.panel({
		Name = "CostBox",
		Parent = panel,
		Position = UDim2.fromOffset(124, 24),
		Size = UDim2.fromOffset(112, 36),
		BackgroundColor3 = Theme.color.bgDeep,
	})

	local cost = Widgets.label("", {
		Name = "Cost",
		Parent = costBox,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
		TextColor3 = Theme.color.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local info = Widgets.label("", {
		Name = "Info",
		Parent = panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 240, 0, 22),
		TextSize = Theme.text.small,
		TextColor3 = Theme.color.textDim,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local cards = new("Frame", {
		Name = "Cards",
		Parent = panel,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(1, -260, 0, 48),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right),
	})

	return {
		frame = panel,
		stroke = panel:FindFirstChildOfClass("UIStroke"),
		name = name,
		life = life,
		cost = cost,
		costBox = costBox,
		info = info,
		cards = cards,
	}
end

function Battle:makeFieldRow(parent, name, position)
	local row = new("ScrollingFrame", {
		Name = name,
		Parent = parent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = position,
		Size = UDim2.new(1, 0, 0, 132),
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.color.stroke,
	})

	self:watchRowSize(row)

	return row
end

function Battle:makeActionBar(parent)
	local bar = Widgets.panel({
		Name = "ActionBar",
		Parent = parent,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, Theme.size.actionBar - 10, 1, -20),
		BackgroundColor3 = Theme.color.panel,
	}, {
		Widgets.padding(10),
		Widgets.listLayout(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})

	self.turnBanner = Widgets.label("", {
		Name = "TurnBanner",
		Parent = bar,
		Size = UDim2.new(1, 0, 0, 34),
		Font = Theme.font.bold,
		TextSize = Theme.text.banner,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
	})

	self.hintLabel = Widgets.label("", {
		Name = "Hint",
		Parent = bar,
		Size = UDim2.new(1, 0, 0, 88),
		TextSize = Theme.text.body,
		TextColor3 = Theme.color.textDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
	})

	self.buttons = {}

	local function addButton(key, text, order, color)
		local button = Widgets.button(text, {
			Parent = bar,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = order,
			BackgroundColor3 = color or Theme.color.panelSoft,
		}, function()
			self.callbacks.action(key)
		end)
		self.buttons[key] = button
		return button
	end

	-- 멀리건 관문 전용. 관문 밖에서는 buttonStates 가 꺼둔다.
	addButton("mulligan", "손패 물리기", 1, Theme.color.stack)
	addButton("keep", "이대로 시작", 2, Theme.color.creature)

	addButton("endPhase", "페이즈 종료", 3, Theme.color.creature)
	addButton("pass", "대응 패스", 4, Theme.color.stack)
	addButton("cancel", "선택 취소", 5)
	addButton("clear", "선언 취소", 6)
	addButton("log", "로그", 8)
	addButton("concede", "항복", 9, Theme.color.foe)
end

function Battle:makeToast(parent)
	self.toast = Widgets.panel({
		Name = "Toast",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.size.topBar + 8),
		Size = UDim2.new(0, 520, 0, 42),
		BackgroundColor3 = Theme.color.panelSoft,
		BackgroundTransparency = 1,
		ZIndex = 20,
	}, {
		Widgets.padding(0, { PaddingLeft = 12, PaddingRight = 12 }),
	})

	self.toastLabel = Widgets.label("", {
		Parent = self.toast,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		ZIndex = 21,
	})

	for _, child in self.toast:GetChildren() do
		if child:IsA("UIStroke") then
			child.Transparency = 1
			self.toastStroke = child
		end
	end
end

function Battle:makeLogPanel(parent)
	self.logPanel = Widgets.panel({
		Name = "Log",
		Parent = parent,
		Visible = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.size.actionBar - 4, 0, Theme.size.topBar + 8),
		Size = UDim2.new(0, 380, 0, 340),
		BackgroundColor3 = Theme.color.bgDeep,
		ZIndex = 15,
	}, {
		Widgets.padding(10),
	})

	Widgets.label("최근 기록", {
		Parent = self.logPanel,
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		TextColor3 = Theme.color.accent,
		ZIndex = 16,
	})

	self.logList = new("ScrollingFrame", {
		Parent = self.logPanel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -28),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.color.stroke,
		ZIndex = 16,
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})
end

function Battle:makeEndOverlay(parent)
	self.endOverlay = new("Frame", {
		Name = "EndOverlay",
		Parent = parent,
		Visible = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color.bgDeep,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 30,
	})

	local box = Widgets.panel({
		Parent = self.endOverlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 250),
		ZIndex = 31,
	}, {
		Widgets.padding(24),
	})
	self.endBox = box

	self.endTitle = Widgets.label("", {
		Parent = box,
		Size = UDim2.new(1, 0, 0, 50),
		Font = Theme.font.bold,
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 32,
	})

	self.endDetail = Widgets.label("", {
		Parent = box,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 0, 70),
		TextSize = Theme.text.body,
		TextColor3 = Theme.color.textDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 32,
	})

	--[[
		판이 끝난 자리에서 한 번 더 할 말. 지금은 튜토리얼이 "다음엔 여길 보세요" 로 쓴다.
		없으면 자리를 차지하지 않는다 — 평소 결과 화면에 빈 줄이 생기면 안 된다.
	]]
	self.endNote = Widgets.label("", {
		Parent = box,
		Position = UDim2.fromOffset(0, 136),
		Size = UDim2.new(1, 0, 0, 44),
		TextSize = Theme.text.body,
		TextColor3 = Theme.color.accent,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 32,
	})

	--[[
		끝난 뒤 무엇을 할 수 있는지는 매치 종류마다 다르다.
		  AI 연습  다시 하기 / 로비로       (이 서버에서 화면만 바꾼다)
		  PvP      다시 매칭 / 나가기       (로비 서버로 텔레포트한다)
		그래서 버튼을 여기서 정하지 않고 render 가 채운다.
	]]
	local row = new("Frame", {
		Name = "EndActions",
		Parent = box,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 32,
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center),
	})

	self.endButtons = {}
	for index = 1, 2 do
		local button = Widgets.button("", {
			Parent = row,
			Visible = false,
			Size = UDim2.new(0, 168, 1, 0),
			LayoutOrder = index,
			BackgroundColor3 = index == 1 and Theme.color.creature or Theme.color.panelSoft,
			ZIndex = 32,
		}, function()
			local action = self.endActions and self.endActions[index]
			if action then
				self.callbacks.action(action.key)
			end
		end)
		self.endButtons[index] = button
	end
end

--[[
	actions = { { key = "rematch", text = "다시 매칭" }, { key = "leave", text = "나가기" } }
]]
function Battle:setEndActions(actions)
	self.endActions = actions or {}

	for index, button in self.endButtons do
		local action = self.endActions[index]
		button.Visible = action ~= nil
		button.Text = action and action.text or ""
	end
end

--==========================================================================
-- 알림
--==========================================================================

--[[
	카드 상세를 연다. 서버에 물어볼 것이 없으므로 화면이 직접 처리한다.
	같은 카드를 다시 오른쪽 클릭하면 닫힌다 — 열고 닫는 데 마우스를 옮길 필요가 없다.
]]
function Battle:inspect(def)
	if self.detailDef == def then
		self.detailDef = nil
		self.detail.hide()
		return
	end

	self.detailDef = def
	self.detail.show(def)
	self.callbacks.inspect(def)
end

--==========================================================================
-- 전투 화살표
--==========================================================================

--[[
	화살표 하나. from → to (둘 다 화면 절대 좌표), 색은 공격/방어에 따라 다르다.

	Roblox 에는 선을 긋는 위젯이 없다. 가로로 긴 Frame 을 두 점의 중간에 놓고
	각도만큼 돌리면 선이 된다. 화살촉은 끝점에 같은 각도로 돌린 글자를 얹는다.
]]
local ARROW_THICKNESS = 4

--[[
	좌표는 Vector2 가 아니라 숫자 두 개로 다룬다. 벡터 연산(빼기·나누기)을 쓰면
	테스트 하네스의 Vector2 흉내에서 걸린다 — 거기엔 연산자가 없다.

	--------------------------------------------------------------------------
	배율을 나눠야 한다

	AbsolutePosition 은 **진짜 화면 픽셀**이고, 우리가 넣는 Position/Size 의 offset 은
	루트의 UIScale 이 곱해진 뒤에 화면에 닿는다(Widgets.autoScale). 그래서 화면 픽셀로
	잰 거리를 그대로 offset 에 넣으면 배율만큼 어긋난다 — 1080 화면(배율 1.2)에서는
	화살표가 카드에서 20% 씩 밀려나 아무 데도 안 닿는다.

	잰 값을 배율로 나눠서 "루트 안쪽 좌표" 로 바꾼 뒤에 넣는다. 두께(4)와 화살촉 크기(22)는
	원래부터 안쪽 좌표라 그대로 둔다 — 그건 배율과 함께 커져야 맞다.
]]
function Battle:drawArrow(originX, originY, fromX, fromY, toX, toY, color, name)
	local scale = (self.uiScale and self.uiScale.Scale or 1)
	if scale <= 0 then
		scale = 1
	end

	local dx, dy = toX - fromX, toY - fromY
	local length = math.sqrt(dx * dx + dy * dy) / scale
	local angle = math.deg(math.atan2(dy, dx))
	local midX, midY = fromX + dx * 0.5, fromY + dy * 0.5

	new("Frame", {
		Name = name,
		Parent = self.arrows,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((midX - originX) / scale, (midY - originY) / scale),
		Size = UDim2.fromOffset(length, ARROW_THICKNESS),
		Rotation = angle,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		ZIndex = 15,
	}, {
		Widgets.corner(2),
	})

	Widgets.label("▶", {
		Name = name .. "Head",
		Parent = self.arrows,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((toX - originX) / scale, (toY - originY) / scale),
		Size = UDim2.fromOffset(22, 22),
		Rotation = angle,
		TextSize = 20,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 16,
	})
end

local function centerOf(node)
	local position, size = node.AbsolutePosition, node.AbsoluteSize
	return position.X + size.X / 2, position.Y + size.Y / 2
end

--[[
	누가 누구를 공격하고 누가 그것을 막는지 선으로 잇는다.

	    공격  빨강   공격자 → 대상(생물 또는 상대 자신)
	    방어  파랑   방어자 → 막는 공격자

	**매 프레임 다시 그린다.** 카드 위치는 레이아웃이 잡은 뒤에야 정해지고
	(AbsolutePosition), 필드가 넘쳐 스크롤되면 그때그때 움직인다. 한 번 그려놓고
	두면 카드는 옮겨 갔는데 화살표만 남는다.
]]
function Battle:drawArrows()
	local state = self.state
	local combat = state and state.combat

	local wanted = combat and (#combat.attackers > 0 or next(combat.blocks) ~= nil)
	if not wanted then
		-- 그릴 게 없다. 이미 비어 있으면 매 프레임 손대지 않는다.
		if self.arrowsDrawn then
			Widgets.clear(self.arrows)
			self.arrowsDrawn = false
		end
		return
	end

	Widgets.clear(self.arrows)
	self.arrowsDrawn = true

	local origin = self.arrows.AbsolutePosition
	local originX, originY = origin.X, origin.Y
	local index = 0

	for _, declaration in combat.attackers do
		local attacker = self.fieldNodes[declaration.id]
		local target = (declaration.targetKind == "Player")
				and (declaration.targetId == self.me and self.myPanel.frame or self.foePanel.frame)
			or self.fieldNodes[declaration.targetId]

		if attacker and target then
			index += 1
			local fromX, fromY = centerOf(attacker)
			local toX, toY = centerOf(target)
			self:drawArrow(originX, originY, fromX, fromY, toX, toY, Theme.color.arrowAttack, "ArrowAttack" .. index)
		end
	end

	index = 0
	for blockerId, attackerId in combat.blocks do
		local blocker = self.fieldNodes[blockerId]
		local attacker = self.fieldNodes[attackerId]

		if blocker and attacker then
			index += 1
			local fromX, fromY = centerOf(blocker)
			local toX, toY = centerOf(attacker)
			self:drawArrow(originX, originY, fromX, fromY, toX, toY, Theme.color.arrowBlock, "ArrowBlock" .. index)
		end
	end
end

function Battle:showToast(text, kind)
	self.toastToken += 1
	local token = self.toastToken

	local color = Theme.color.text
	if kind == "error" then
		color = Theme.color.warn
	elseif kind == "ai" then
		color = Theme.color.foe
	elseif kind == "info" then
		color = Theme.color.accent
	end

	self.toastLabel.Text = text
	self.toastLabel.TextColor3 = color

	TweenService:Create(self.toast, Theme.tween, { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(self.toastLabel, Theme.tween, { TextTransparency = 0 }):Play()
	if self.toastStroke then
		TweenService:Create(self.toastStroke, Theme.tween, { Transparency = 0 }):Play()
	end

	task.delay(2.4, function()
		if token ~= self.toastToken then
			return
		end
		TweenService:Create(self.toast, Theme.tween, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(self.toastLabel, Theme.tween, { TextTransparency = 1 }):Play()
		if self.toastStroke then
			TweenService:Create(self.toastStroke, Theme.tween, { Transparency = 1 }):Play()
		end
	end)
end

function Battle:toggleLog()
	self.logOpen = not self.logOpen
	self.logPanel.Visible = self.logOpen
end

--==========================================================================
-- 렌더링
--==========================================================================

local function phaseChip(phase, current)
	local active = (phase == current)

	return new("Frame", {
		BackgroundColor3 = active and Theme.color.accent or Theme.color.panel,
		BackgroundTransparency = active and 0 or 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(132, 30),
	}, {
		Widgets.corner(15),
		Widgets.label(Enums.PhaseDisplay[phase], {
			Size = UDim2.fromScale(1, 1),
			TextSize = Theme.text.body,
			Font = active and Theme.font.bold or Theme.font.regular,
			TextColor3 = active and Theme.color.bgDeep or Theme.color.textDim,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

--==========================================================================
-- 줄 배치
--==========================================================================

--[[
	카드 줄은 **UIListLayout 을 쓰지 않는다.**

	레이아웃은 매 프레임 자식의 Position 을 자기가 다시 정한다. 그러면 카드 위치에
	트윈을 걸어도 다음 프레임에 덮어써져서, 카드가 날아가는 연출이 원리적으로 안 된다.
	그래서 자리 계산을 여기로 가져왔다.

	예전 alignWhenOverflowing 이 하던 일도 여기서 같이 한다 — 내용이 줄보다 넓으면
	왼쪽부터, 아니면 가운데. (가운데 정렬로 넘치면 왼쪽 카드가 잘리는데 캔버스는
	0 부터라 스크롤로도 거기까지 못 간다)
]]
function Battle:watchRowSize(row)
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local record = self.rows[row]
		if record then
			-- 창 크기가 바뀌는 중이다. 미끄러지게 두면 따라오다 만 것처럼 보인다.
			self:placeRow(row, record.cards, record.size, record.gap, record.entryFrom, false, record.fan)
		end
	end)
end

--[[
	cards 를 줄에 나란히 놓는다.

	  cardSize   Theme.size 의 카드 치수
	  gap        카드 사이 간격
	  entryFrom  새 카드가 어디서 들어오는가 — "right"(덱에서 뽑아 손으로)
	             또는 "below"(손에서 필드로 나온다)
	  animate    자리를 옮기는 카드를 미끄러뜨릴지. 창 크기 변화 때는 false
	  fan        손패처럼 호를 그리며 쥘지. 필드는 false 다 —
	             필드 카드는 Rotation 을 탭 표시에 쓰고 있어서 겹치면 안 된다

	줄 폭은 **배율로 나눠서** 쓴다. AbsoluteSize 는 진짜 화면 픽셀인데 우리가 넣는
	offset 은 루트 UIScale 이 곱해진 뒤에 화면에 닿기 때문이다 (drawArrow 와 같은 이유).
]]
function Battle:placeRow(row, cards, cardSize, gap, entryFrom, animate, fan)
	self.rows[row] = { cards = cards, size = cardSize, gap = gap, entryFrom = entryFrom, fan = fan }

	local scale = (self.uiScale and self.uiScale.Scale or 1)
	if scale <= 0 then
		scale = 1
	end

	local count = #cards
	local total = count > 0 and (count * cardSize.X + (count - 1) * gap) or 0

	row.CanvasSize = UDim2.fromOffset(total, 0)

	local rowWidth = row.AbsoluteSize.X / scale
	local rowHeight = row.AbsoluteSize.Y / scale

	local startX = math.max(0, (rowWidth - total) / 2)
	-- 세로는 가운데. 하네스처럼 줄 크기를 모르는 곳에서는 0 으로 떨어진다.
	local y = math.max(0, (rowHeight - cardSize.Y) / 2)

	local motion = Theme.motion

	for index, card in cards do
		local x = startX + (index - 1) * (cardSize.X + gap)

		--[[
			부채꼴. 가운데를 0, 양 끝을 -1/+1 로 두고 그 값으로 기울기와 높이를 정한다.
			높이는 제곱이라 가운데가 가장 높고 바깥으로 갈수록 처진다 — 쥔 손 모양이다.
			카드가 한 장이면 기울일 이유가 없다.
		]]
		local tilt, drop = 0, 0
		if fan and #cards > 1 then
			local t = (index - 1) / (#cards - 1) * 2 - 1
			tilt = Theme.motion.fan.angle * t
			drop = Theme.motion.fan.arc * t * t
		end

		local target = UDim2.fromOffset(x, y + drop)

		if self.freshCards[card] then
			self.freshCards[card] = nil

			--[[
				새 카드는 제 자리 **밖에서** 출발한다. 어디서 오는지가 그 카드가
				무엇인지를 말해준다 — 손패는 오른쪽(덱) 에서 들어오고, 필드는
				아래(손패) 에서 올라온다.
			]]
			if entryFrom == "below" then
				card.Position = UDim2.fromOffset(x, y + motion.summonRise)
			else
				card.Position = UDim2.fromOffset(math.max(rowWidth, x + cardSize.X), y)
			end

			Motion.to(card, motion.deal, { Position = target, Rotation = tilt })
		elseif animate then
			Motion.to(card, motion.reflow, { Position = target, Rotation = tilt })
		else
			card.Position = target
			card.Rotation = tilt
		end
	end
end

--==========================================================================
-- 연출
--==========================================================================

--[[
	턴이 넘어간 것을 한 번 크게 알린다.

	토큰을 쓰는 이유는 토스트와 같다 — 배너가 아직 사라지는 중에 다음 턴이 오면
	늦게 도착한 "사라져라" 가 새로 뜬 배너를 지워버린다. 자기 차례가 지났으면
	아무것도 하지 않고 물러난다.
]]
function Battle:flashTurn(myTurn)
	self.flashToken += 1
	local token = self.flashToken

	local motion = Theme.motion.turnBanner
	local label = self.turnFlash

	label.Text = myTurn and "내 턴" or "상대 턴"
	label.TextColor3 = myTurn and Theme.color.me or Theme.color.foe
	label.Position = self.turnFlashHome
	label.TextTransparency = 1

	Motion.to(label, motion.fadeIn, { TextTransparency = 0 })

	task.delay(motion.fadeIn + motion.hold, function()
		if token ~= self.flashToken then
			return
		end
		Motion.to(label, motion.fadeOut, {
			TextTransparency = 1,
			Position = UDim2.new(0.5, 0, 0.5, -motion.rise),
		})
	end)
end

--[[
	라이프가 깎일 때 그 자리에 깎인 만큼을 띄운다.

	로그에도 남지만 로그는 접혀 있는 게 기본이라, **얼마나 맞았는지**를 판 위에서
	바로 읽을 방법이 이것뿐이다. 회복은 띄우지 않는다 — 지금 룰에 회복이 없다.

	패널은 자식을 절대 위치로 놓으므로(UIListLayout 이 없다) 여기에 라벨을 얹어도
	패널 안 다른 것들이 밀리지 않는다.
]]
function Battle:flashDamage(panel, amount)
	local motion = Theme.motion.damage

	local label = Widgets.label(("-%d"):format(amount), {
		Name = "Damage",
		Parent = panel.frame,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 96, 0.5, 0),
		Size = UDim2.fromOffset(80, 40),
		Font = Theme.font.bold,
		TextSize = Theme.text.life,
		TextColor3 = Theme.color.warn,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 20,
	})

	Motion.floatAway(label, motion.rise, motion.travel)
end

--[[
	상대가 낸 카드를 한가운데 크게 띄웠다가 물린다.

	옆에서 들어와 멎고, 읽을 만큼 머물다, 올라가며 사라지고 그 자리에 고리가 퍼진다.
	영상에서 f40~f49 사이에 일어나는 일이다.

	토큰은 배너와 같은 이유다 — 상대가 연달아 두 장을 내면 먼저 것을 물리려던
	호출이 나중 것을 지워버린다.
]]
function Battle:flashSpotlight(def)
	self.spotlightToken += 1
	local token = self.spotlightToken

	local motion = Theme.motion.spotlight
	local frame = self.spotlight.frame

	self.spotlight.show(def, "상대가 냈습니다")

	-- 보드 오른쪽 밖에서 들어온다.
	frame.Position = UDim2.new(1, 200, 0.5, 0)
	Motion.to(frame, motion.travel, { Position = UDim2.fromScale(0.5, 0.5) })

	task.delay(motion.travel + motion.hold, function()
		if token ~= self.spotlightToken then
			return
		end

		Motion.to(frame, motion.exit, { Position = UDim2.new(0.5, 0, 0.5, -motion.rise) })
		self:flashRing()

		task.delay(motion.exit, function()
			if token == self.spotlightToken then
				self.spotlight.hide()
			end
		end)
	end)
end

--[[
	스포트라이트가 물러난 자리에 퍼지는 고리. 테두리 투명도 하나로 사라지므로
	자식 투명도를 일일이 건드릴 필요가 없다.
]]
function Battle:flashRing()
	local motion = Theme.motion.ring

	local ring = new("Frame", {
		Name = "Ring",
		Parent = self.board,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(60, 60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 21,
	}, {
		new("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})

	local stroke = Widgets.stroke(Theme.color.stack, 3, 0)
	stroke.Parent = ring

	Motion.to(ring, motion.grow, { Size = UDim2.fromOffset(motion.size, motion.size) })
	Motion.to(stroke, motion.grow, { Transparency = 1 })

	task.delay(motion.grow, function()
		ring:Destroy()
	end)
end

function Battle:renderPlayerPanel(panel, state, playerId, opts)
	local player = state.players[playerId]
	local available = GameState.availableCost(state, playerId)
	local total = #GameState.costCardsOnField(state, playerId)

	panel.name.Text = player.name
	panel.life.Text = ("♥ %d"):format(player.life)

	--[[
		직전 라이프와 견줘 **깎인 만큼**을 띄운다. 첫 렌더(직전 값 없음)와
		늘어난 경우는 건너뛴다 — 판이 새로 시작해 라이프가 돌아온 것을
		연출로 오해하면 안 된다.
	]]
	local previousLife = self.lastLife[playerId]
	if previousLife and player.life < previousLife then
		self:flashDamage(panel, previousLife - player.life)
	end
	self.lastLife[playerId] = player.life

	-- 라이프가 위험한 구간을 더 일찍(12 이하) 붉게 바꾼다. 30 에서 시작하는 판이라
	-- 8 은 이미 늦다 — 한 번의 공격으로 끝나는 지점부터 눈에 띄어야 한다.
	--
	-- 평소에는 양쪽 다 흰색이다. 내 것을 초록, 상대 것을 붉게 칠해봤더니
	-- 상대 라이프가 늘 "위험" 으로 읽혀서 진짜 경고와 구분되지 않았다.
	-- 내/상대 구분은 위아래 위치와 이름 색이 이미 하고 있다.
	panel.life.TextColor3 = player.life <= 12 and Theme.color.warn or Theme.color.text

	panel.cost.Text = ("◆ %d / %d"):format(available, total)
	panel.cost.TextColor3 = available > 0 and Theme.color.accent or Theme.color.textFaint
	panel.info.Text = ("패 %d장   ·   덱 %d장"):format(player.handCount, player.deckCount)

	if panel.stroke then
		local targeted = opts.highlights.player[playerId]
		panel.stroke.Color = targeted and Theme.color.ok or Theme.color.stroke
		panel.stroke.Thickness = targeted and 2.5 or 1
	end

	--[[
		코스트 카드 칩 + (상대라면) 손패 뒷면.

		한 줄에 성격이 다른 둘이 섞이므로 키에 접두사를 붙인다. 접두사가 없으면
		코스트 카드 id 1 과 뒷면 1번이 같은 키가 되어 서로를 덮어쓴다.
	]]
	local items = {}

	for _, instance in GameState.costCardsOnField(state, playerId) do
		table.insert(items, {
			key = "cost:" .. instance.id,
			build = function()
				return CardView.costCard(instance, 0)
			end,
			paint = function(chip)
				CardView.paintCost(chip, instance)
			end,
		})
	end

	if playerId ~= self.me then
		--[[
			뒷면은 **장수만** 보여준다. 어느 뒷면이 어느 카드인지는 알 수도 없고
			알아서도 안 되므로, 키를 자리 번호로 준다 — 상대가 카드를 내면
			마지막 자리가 사라지는 모습이 된다.
		]]
		for index = 1, math.min(player.handCount, 12) do
			table.insert(items, {
				key = "back:" .. index,
				build = function()
					return CardView.cardBack(0)
				end,
			})
		end
	end

	Reconcile.children(panel.cards, items)
end

function Battle:renderField(row, state, playerId, opts)
	local creatures = GameState.creaturesOnField(state, playerId)
	local items = table.create(#creatures)

	for _, instance in creatures do
		local badge = nil
		for _, declaration in state.combat.attackers do
			if declaration.id == instance.id then
				badge = "공격"
			end
		end
		if state.combat.blocks[instance.id] then
			badge = "방어"
		end

		local cardOpts = {
			highlighted = opts.highlights.creature[instance.id],
			selected = opts.selectedId == instance.id,
			badge = badge,
			onClick = function()
				self.callbacks.fieldCard(instance.id)
			end,
			onInspect = function()
				self:inspect(Registry.mustGet(instance.defId))
			end,
		}

		table.insert(items, {
			key = instance.id,
			build = function()
				return CardView.fieldCard(state, instance, cardOpts)
			end,
			paint = function(card)
				CardView.paintField(card, state, instance, cardOpts)
			end,
			enter = function(card)
				self.freshCards[card] = true
			end,
		})
	end

	-- 화살표가 어디서 어디로 갈지 정하려면 카드 노드를 알아야 한다.
	local drawn = Reconcile.children(row, items)
	for index, card in drawn do
		self.fieldNodes[items[index].key] = card
	end

	-- 생물은 손패에서 나오므로 아래에서 올라온다.
	self:placeRow(row, drawn, Theme.size.fieldCard, 8, "below", true)
end

function Battle:renderCenter(state, opts)
	Widgets.clear(self.center)

	local order = 0
	local function add(instance)
		order += 1
		instance.LayoutOrder = order
		instance.Parent = self.center
	end

	--[[
		튜토리얼 코치.

		보드 한가운데에 둔다 — 손패와 전장 사이라 눈이 어차피 지나가는 자리다.
		행동 바의 hint 자리에 끼우지 않은 이유는, 그쪽은 "지금 페이즈 설명" 이라
		매 판 떠 있어서 **처음 보는 사람이 읽어야 할 글** 과 섞이면 둘 다 안 읽힌다.
	]]
	if opts.coach then
		--[[
			높이 74 는 **세 줄** 예산이다(520 폭에 본문 크기 기준). 코치 문구를 쓸 때
			줄당 35자쯤을 넘기지 않는다 — 넘치면 상자 밖으로 흘러 전장 위에 겹친다.
			보드 가운데는 자리가 좁아서(위아래 패널·필드가 고정 높이다) 상자를 더 키울 수 없다.
		]]
		local box = Widgets.panel({
			Name = "Coach",
			Size = UDim2.new(0, 520, 0, 74),
			BackgroundColor3 = Theme.color.panelSoft,
		}, {
			Widgets.padding(10),
			Widgets.stroke(Theme.color.accent, 2),
		})

		Widgets.label(opts.coach, {
			Parent = box,
			Size = UDim2.fromScale(1, 1),
			TextSize = Theme.text.body,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		})

		add(box)
	end

	-- 지금 무엇을 해야 하는가
	if opts.prompt then
		add(Widgets.label(opts.prompt, {
			-- 이름을 붙여둔다. 코치 말풍선에도 같은 문구가 들어가서,
			-- "화면에 이 글자가 있나" 로는 둘을 구별할 수 없다.
			Name = "Prompt",
			Size = UDim2.new(1, 0, 0, 30),
			Font = Theme.font.bold,
			TextSize = Theme.text.title,
			TextColor3 = Theme.color.accent,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	end

	-- 스택
	if #state.stack > 0 then
		local strip = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
		}, {
			Widgets.listLayout(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center),
		})

		for index = #state.stack, 1, -1 do
			local item = state.stack[index]
			local def = Registry.mustGet(state.cards[item.instanceId].defId)
			local mine = (item.controllerId == self.me)
			local targeted = opts.highlights.stack[item.id]

			local chip = Widgets.button(("%s  (%s)"):format(def.name, mine and "내 것" or "상대"), {
				Size = UDim2.fromOffset(220, 34),
				BackgroundColor3 = Theme.color.stack,
				BackgroundTransparency = 0.1,
				TextColor3 = Theme.color.bgDeep,
				TextSize = Theme.text.body,
				LayoutOrder = #state.stack - index,
			}, function()
				self.callbacks.stackItem(item.id)
			end)

			local stroke = chip:FindFirstChildOfClass("UIStroke")
			if stroke and targeted then
				stroke.Color = Theme.color.ok
				stroke.Thickness = 2.5
			end

			chip.Parent = strip
		end

		add(Widgets.label("스택 — 위에서부터 해결된다", {
			Size = UDim2.new(1, 0, 0, 20),
			Font = Theme.font.bold,
			TextSize = Theme.text.small,
			TextColor3 = Theme.color.stack,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
		add(strip)
	end

	-- 전투 선언 현황
	if #state.combat.attackers > 0 then
		-- 선언 이후 즉시시전으로 대상이 덱으로 돌아가면 뷰에서 사라진다.
		-- (덱은 클라이언트에 안 내려온다) 그래서 이름 조회는 전부 방어적으로 한다.
		local function nameOf(instanceId)
			local instance = instanceId and state.cards[instanceId]
			return instance and Registry.mustGet(instance.defId).name or "?"
		end

		for _, declaration in state.combat.attackers do
			local attacker = state.cards[declaration.id]
			if attacker then
				local targetName = (declaration.targetKind == "Player") and "플레이어 직접 공격"
					or nameOf(declaration.targetId)

				-- 한 공격자를 여러 마리가 함께 막을 수 있다. 이름을 전부 적는다.
				local blockerNames = {}
				for blockerId, attackerId in state.combat.blocks do
					if attackerId == declaration.id then
						table.insert(blockerNames, nameOf(blockerId))
					end
				end
				table.sort(blockerNames)

				local text = ("%s  →  %s"):format(nameOf(declaration.id), targetName)
				if #blockerNames > 0 then
					text ..= ("   <font color='#58C48E'>← %s 방어</font>"):format(
						table.concat(blockerNames, " · ")
					)
				end

				add(Widgets.label(text, {
					Size = UDim2.new(1, 0, 0, 20),
					TextSize = Theme.text.body,
					TextColor3 = Theme.color.text,
					TextXAlignment = Enum.TextXAlignment.Center,
				}))
			end
		end
	end

	if order == 0 then
		add(Widgets.label("— 전장 —", {
			Size = UDim2.new(1, 0, 0, 20),
			TextSize = Theme.text.body,
			TextColor3 = Theme.color.textFaint,
			TextXAlignment = Enum.TextXAlignment.Center,
		}))
	end
end

function Battle:renderHand(state, opts)
	local hand = state.players[self.me].hand or {}
	local items = {}

	for _, instanceId in hand do
		local instance = state.cards[instanceId]
		if instance then
			local def = Registry.mustGet(instance.defId)
			--[[
				튜토리얼이 잠근 카드는 **낼 수 없는 것처럼** 보여야 한다.
				눌리기만 막고 멀쩡해 보이게 두면 "왜 안 되지" 로 끝난다.
			]]
			local locked = opts.lockedHand and opts.lockedHand[instanceId]
			local playable = (not locked) and Rules.canPlayCard(state, self.me, instanceId)

			local cardOpts = {
				playable = playable,
				selected = opts.selectedId == instanceId,
				highlighted = opts.highlights.hand[instanceId],
				onClick = function()
					self.callbacks.handCard(instanceId)
				end,
				onInspect = function()
					self:inspect(def)
				end,
			}

			table.insert(items, {
				--[[
					키는 **카드 정의(defId)가 아니라 인스턴스 id** 다. 같은 카드를
					덱에 4장까지 넣을 수 있으므로 defId 로 잡으면 같은 이름의 카드
					둘이 한 자리를 놓고 싸운다.
				]]
				key = instanceId,
				build = function()
					return CardView.handCard(def, cardOpts)
				end,
				paint = function(card)
					CardView.paintHand(card, def, cardOpts)
				end,
				enter = function(card)
					self.freshCards[card] = true
				end,
			})
		end
	end

	-- 뽑은 카드는 덱 쪽(오른쪽)에서 들어온다.
	local drawn = Reconcile.children(self.handRow, items)
	self:placeRow(self.handRow, drawn, Theme.size.handCard, 8, "right", true, true)
end

function Battle:renderLog(state)
	Widgets.clear(self.logList)

	for index, entry in state.log do
		Widgets.label(("<font color='#929CB2'>[T%d]</font> %s"):format(entry.turn, entry.text), {
			Parent = self.logList,
			Size = UDim2.new(1, -8, 0, 19),
			TextSize = Theme.text.small,
			TextColor3 = Theme.color.text,
			LayoutOrder = index,
		})
	end

	self.logList.CanvasPosition = Vector2.new(0, 1e6)
end

--[[
	opts = {
		highlights = { creature = {}, player = {}, stack = {}, hand = {} },
		selectedId = number?,   -- 지금 고른 카드
		prompt     = string?,   -- 가운데 안내문
		hint       = string?,   -- 행동 바 설명
		coach      = string?,   -- 튜토리얼 말풍선 (없으면 안 뜬다)
		endNote    = string?,   -- 결과 화면에 덧붙일 한 줄
		lockedHand = { [id]: true }?,  -- 튜토리얼이 잠근 손패 카드
		busy       = boolean,   -- 상대가 두는 중
		buttons    = { [key] = boolean },  -- 켜둘 버튼
	}
]]
function Battle:render(state, opts)
	self.state = state

	-- 어느 좌석이 "나" 인지는 서버가 스냅샷에 실어 보낸다. 화면 전체가 이 둘만 본다.
	self.me = state.viewerId or DEFAULT_ME
	self.foe = GameState.opponentOf(self.me)

	--------------------------------------------------------------------
	-- 상단
	--------------------------------------------------------------------
	local myTurn = (state.activePlayerId == self.me)
	local myMove = not opts.busy

	self.turnLabel.Text = ("턴 %d   ·   %s"):format(state.turn, myTurn and "내 턴" or "상대 턴")
	self.turnLabel.TextColor3 = myTurn and Theme.color.me or Theme.color.foe

	--[[
		배너는 **턴 주인이 바뀔 때만** 띄운다. 행동 바의 "내 차례" 와 방아쇠가 다르다 —
		그쪽은 수비준비 페이즈처럼 상대 턴에 내가 두는 경우까지 따라가느라 한 턴에도
		여러 번 뒤집힌다. 그 박자로 배너를 띄우면 화면 한가운데서 글자가 계속 깜빡인다.
	]]
	--[[
		상대가 스택에 올린 카드는 한 번 크게 보여준다. 내가 낸 것은 안 띄운다 —
		내가 뭘 냈는지는 내가 안다.

		첫 스냅샷은 건너뛴다. 판에 들어온 순간 스택에 뭔가 얹혀 있으면(재접속 등)
		방금 낸 것처럼 튀어나오기 때문이다.
	]]
	local seenStack = {}
	for _, item in state.stack do
		seenStack[item.id] = true
		if self.stackSeeded and not self.lastStackIds[item.id] and item.controllerId ~= self.me then
			local instance = state.cards[item.instanceId]
			if instance then
				self:flashSpotlight(Registry.mustGet(instance.defId))
			end
		end
	end
	self.lastStackIds = seenStack
	self.stackSeeded = true

	local turnKey = ("%d:%d"):format(state.turn, state.activePlayerId)
	if self.lastTurnKey and self.lastTurnKey ~= turnKey and not state.finished then
		self:flashTurn(myTurn)
	end
	self.lastTurnKey = turnKey

	Widgets.clear(self.phaseTrack)
	for index, phase in PHASE_TRACK do
		local chip = phaseChip(phase, state.phase)
		chip.LayoutOrder = index
		chip.Parent = self.phaseTrack
	end

	--[[
		배너는 "누구 턴인가" 가 아니라 **"지금 누가 두는가"** 를 말한다.
		수비준비 페이즈에서는 상대 턴인데 내가 둔다 — 예전처럼 턴 주인만 보여주면
		그 순간 화면은 "상대 턴" 이라고 말하면서 내 입력을 기다리게 된다.
	]]
	local moveColor = myMove and Theme.color.me or Theme.color.foe

	self.turnBanner.Text = myMove and "내 차례" or "상대 차례"
	self.turnBanner.TextColor3 = moveColor

	-- 보드 테두리. 카드를 보고 있어도 주변시로 들어오는 유일한 신호다.
	if state.finished then
		self.boardStroke.Color = Theme.color.stroke
		self.boardStroke.Thickness = 2
	else
		self.boardStroke.Color = moveColor
		self.boardStroke.Thickness = myMove and 3 or 2
	end

	self.hintLabel.Text = opts.hint or ""

	--------------------------------------------------------------------
	-- 보드
	--------------------------------------------------------------------
	-- 지난 판(또는 지난 갱신)의 카드 노드는 버린다. 죽은 생물의 화살표가 남으면 안 된다.
	self.fieldNodes = {}

	self:renderPlayerPanel(self.foePanel, state, self.foe, opts)
	self:renderPlayerPanel(self.myPanel, state, self.me, opts)
	self:renderField(self.foeField, state, self.foe, opts)
	self:renderField(self.myField, state, self.me, opts)
	self:renderCenter(state, opts)
	self:renderHand(state, opts)
	self:renderLog(state)

	--------------------------------------------------------------------
	-- 버튼
	--------------------------------------------------------------------
	for key, button in self.buttons do
		if key == "log" or key == "concede" then
			Widgets.setEnabled(button, not state.finished)
		else
			Widgets.setEnabled(button, ((opts.buttons or {})[key] == true) and not opts.busy)
		end
	end

	self.buttons.clear.Text = (state.phase == Phase.DefensePrep) and "방어 취소" or "공격 취소"

	--------------------------------------------------------------------
	-- 결과
	--------------------------------------------------------------------
	if state.finished then
		local won = (state.winnerId == self.me)
		self.endOverlay.Visible = true
		self.endTitle.Text = won and "승리" or "패배"
		self.endTitle.TextColor3 = won and Theme.color.me or Theme.color.foe
		self.endDetail.Text = ("%s   ·   %d턴\n최종 라이프  %s %d  /  %s %d"):format(
			LOSS_REASON[state.lossReason] or tostring(state.lossReason),
			state.turn,
			state.players[self.me].name,
			state.players[self.me].life,
			state.players[self.foe].name,
			state.players[self.foe].life
		)
		--[[
			안내 줄이 있으면 상자를 그만큼 키운다. 250 에 그대로 끼우면
			버튼과 겹쳐서 둘 다 못 읽는다.
		]]
		self.endNote.Text = opts.endNote or ""
		self.endBox.Size = UDim2.fromOffset(420, opts.endNote and 300 or 250)

		self:setEndActions(opts.endActions)
	else
		self.endOverlay.Visible = false
	end
end

return Battle
