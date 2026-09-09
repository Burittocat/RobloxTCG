--[[
	전투 화면.

	이 모듈은 "지금 상태를 그린다" 만 한다. 무엇을 눌렀을 때 어떤 행동이 되는지는
	전부 Controller 가 정한다. 그래서 여기에는 룰 판정이 한 줄도 없다 —
	하이라이트할 카드 목록조차 Controller 가 계산해서 넘겨준다.

	렌더링은 매번 전부 다시 그린다. 카드가 수십 장 수준이라 이게 가장 단순하고,
	"서버 상태 = 화면" 이 어긋날 여지가 없다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local CardView = require(script.Parent.CardView)

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

--[[
	가로로 스크롤하는 줄이 **넘칠 때만** 왼쪽으로 붙게 한다.

	UIListLayout 의 가운데 정렬은 내용이 줄보다 넓어지면 양쪽으로 똑같이 넘친다.
	그러면 왼쪽 카드가 잘리고, 캔버스는 0 부터라 스크롤로도 거기까지 못 간다.
	손패는 드로우가 늘면 실제로 줄보다 길어진다.

	그렇다고 늘 왼쪽 정렬로 두면 카드가 두세 장일 때 화면이 왼쪽으로 쏠린다.
	그래서 넓이를 보고 그때그때 바꾼다 — 내용이 넘치면 왼쪽, 아니면 가운데.
]]
local function alignWhenOverflowing(scroll, layout)
	local function update()
		local overflowing = layout.AbsoluteContentSize.X > scroll.AbsoluteSize.X
		layout.HorizontalAlignment = overflowing and Enum.HorizontalAlignment.Left
			or Enum.HorizontalAlignment.Center
	end

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

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
	}

	self.logOpen = false
	self.toastToken = 0
	self.me, self.foe = DEFAULT_ME, DEFAULT_FOE

	self:build(parent)
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
	Widgets.autoScale(root)

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

	local handLayout = Widgets.listLayout(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)

	self.handRow = new("ScrollingFrame", {
		Name = "Hand",
		Parent = handBar,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -24, 1, -16),
		Position = UDim2.fromOffset(12, 8),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.color.stroke,
	}, {
		handLayout,
	})

	alignWhenOverflowing(self.handRow, handLayout)

	--------------------------------------------------------------------
	-- 겹쳐 뜨는 것들
	--------------------------------------------------------------------
	self:makeToast(root)
	self:makeLogPanel(root)
	self:makeEndOverlay(root)
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
	local layout = Widgets.listLayout(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)

	local row = new("ScrollingFrame", {
		Name = name,
		Parent = parent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = position,
		Size = UDim2.new(1, 0, 0, 132),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.color.stroke,
	}, {
		layout,
	})

	-- 필드도 생물이 늘어나면 줄보다 길어진다.
	alignWhenOverflowing(row, layout)

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

function Battle:renderPlayerPanel(panel, state, playerId, opts)
	local player = state.players[playerId]
	local available = GameState.availableCost(state, playerId)
	local total = #GameState.costCardsOnField(state, playerId)

	panel.name.Text = player.name
	panel.life.Text = ("♥ %d"):format(player.life)

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

	-- 코스트 카드 칩 + (상대라면) 손패 뒷면
	Widgets.clear(panel.cards)

	local order = 0
	for _, instance in GameState.costCardsOnField(state, playerId) do
		order += 1
		CardView.costCard(instance, order).Parent = panel.cards
	end

	if playerId ~= self.me then
		for index = 1, math.min(player.handCount, 12) do
			order += 1
			CardView.cardBack(order + index).Parent = panel.cards
		end
	end
end

function Battle:renderField(row, state, playerId, opts)
	Widgets.clear(row)

	local order = 0
	for _, instance in GameState.creaturesOnField(state, playerId) do
		order += 1

		local badge = nil
		for _, declaration in state.combat.attackers do
			if declaration.id == instance.id then
				badge = "공격"
			end
		end
		if state.combat.blocks[instance.id] then
			badge = "방어"
		end

		local card = CardView.fieldCard(state, instance, {
			layoutOrder = order,
			highlighted = opts.highlights.creature[instance.id],
			selected = opts.selectedId == instance.id,
			badge = badge,
			onClick = function()
				self.callbacks.fieldCard(instance.id)
			end,
		})
		card.Parent = row
	end
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

				local blockerName
				for blockerId, attackerId in state.combat.blocks do
					if attackerId == declaration.id then
						blockerName = nameOf(blockerId)
					end
				end

				local text = ("%s  →  %s"):format(nameOf(declaration.id), targetName)
				if blockerName then
					text ..= ("   <font color='#58C48E'>← %s 방어</font>"):format(blockerName)
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
	Widgets.clear(self.handRow)

	local hand = state.players[self.me].hand or {}

	for index, instanceId in hand do
		local instance = state.cards[instanceId]
		if instance then
			local def = Registry.mustGet(instance.defId)
			--[[
				튜토리얼이 잠근 카드는 **낼 수 없는 것처럼** 보여야 한다.
				눌리기만 막고 멀쩡해 보이게 두면 "왜 안 되지" 로 끝난다.
			]]
			local locked = opts.lockedHand and opts.lockedHand[instanceId]
			local playable = (not locked) and Rules.canPlayCard(state, self.me, instanceId)

			local card = CardView.handCard(def, {
				layoutOrder = index,
				playable = playable,
				selected = opts.selectedId == instanceId,
				highlighted = opts.highlights.hand[instanceId],
				onClick = function()
					self.callbacks.handCard(instanceId)
				end,
			})
			card.Parent = self.handRow
		end
	end
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
		self:setEndActions(opts.endActions)
	else
		self.endOverlay.Visible = false
	end
end

return Battle
