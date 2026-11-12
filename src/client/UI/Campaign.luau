--[[
	캠페인 스테이지 목록.

	고를 수 있는 것은 **다음 한 칸**뿐이다. 잠긴 칸을 숨기지 않고 흐리게 남겨두는 이유는
	버튼을 흐리게 두는 이유와 같다(Widgets.setEnabled 주석) — 앞으로 무엇이 남았는지
	보여야 지금 한 판이 어디쯤인지 읽힌다.

	여기에는 판정이 한 줄도 없다. 무엇이 열려 있고 골드를 얼마 받는지는 전부 서버가
	Campaign.list 로 계산해서 내려준다. 클라이언트가 같이 판정하면 둘이 어긋나는 날이 오고,
	그때 사람은 "화면엔 열려 있는데 눌러도 안 되는" 칸을 보게 된다.

	상대 덱은 내려오지 않는다 — 알면 안 되는 정보다. 그래서 이 화면은 note 한 줄로
	"이 상대는 무엇을 하는가" 만 말한다.
]]

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local new = Widgets.new

local Campaign = {}
Campaign.__index = Campaign

local ROW_HEIGHT = 96

function Campaign.new(parent)
	local self = setmetatable({}, Campaign)

	local noop = function() end
	self.callbacks = { start = noop, back = noop }

	self:build(parent)
	return self
end

-- 골드 아이콘은 카드팩 화면과 같은 것을 쓴다 (Widgets.goldIcon).
local goldIcon = Widgets.goldIcon

--==========================================================================
-- 뼈대
--==========================================================================

function Campaign:build(parent)
	local gui = new("ScreenGui", {
		Name = "TCGCampaign",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Enabled = false,
		Parent = parent,
	})
	self.gui = gui

	local root = new("Frame", {
		Name = "Root",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color.bg,
		BorderSizePixel = 0,
	}, {
		new("UIGradient", {
			Color = ColorSequence.new(Theme.color.bgDeep, Theme.color.bg),
			Rotation = 90,
		}),
	})

	Widgets.autoScale(root)

	local column = new("Frame", {
		Name = "Column",
		Parent = root,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(660, 640),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center),
	})

	--------------------------------------------------------------------
	-- 머리 — 제목과 가진 골드
	--------------------------------------------------------------------
	local header = new("Frame", {
		Name = "Header",
		Parent = column,
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
	})

	Widgets.label("캠페인", {
		Parent = header,
		Size = UDim2.new(0.5, 0, 1, 0),
		Font = Theme.font.bold,
		TextSize = 32,
	})

	local purse = new("Frame", {
		Name = "Purse",
		Parent = header,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(160, 28),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right),
	})

	goldIcon({ Parent = purse, LayoutOrder = 1 })

	self.goldLabel = Widgets.label("0", {
		Parent = purse,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(120, 28),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
		TextColor3 = Theme.color.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	--------------------------------------------------------------------
	-- 스테이지 목록
	--------------------------------------------------------------------
	self.list = new("ScrollingFrame", {
		Name = "Stages",
		Parent = column,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 500),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.color.stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})

	--------------------------------------------------------------------
	-- 안내와 뒤로
	--------------------------------------------------------------------
	self.message = Widgets.label("", {
		Parent = column,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = Theme.text.body,
		TextColor3 = Theme.color.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	Widgets.button("뒤로", {
		Parent = column,
		LayoutOrder = 4,
		Size = UDim2.fromOffset(200, 40),
		TextSize = Theme.text.label,
	}, function()
		self.callbacks.back()
	end)
end

--==========================================================================
-- 한 줄
--==========================================================================

--[[
	스테이지 한 칸.

	잠긴 칸은 note 를 안 보여준다. 상대가 무엇을 하는지는 **도전할 수 있게 된 다음**에
	읽을 정보다 — 미리 다 보이면 목록이 공략집이 되고, 한 칸씩 열리는 의미가 없어진다.
]]
function Campaign:addRow(stage)
	local locked = not stage.unlocked

	local row = Widgets.panel({
		Name = ("Stage%d"):format(stage.index),
		Parent = self.list,
		LayoutOrder = stage.index,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		BackgroundTransparency = locked and 0.45 or 0,
	}, {
		Widgets.padding(12),
	})

	Widgets.label(("%d. %s"):format(stage.index, locked and "???" or stage.name), {
		Parent = row,
		Size = UDim2.new(1, -150, 0, 24),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
		TextColor3 = locked and Theme.color.textFaint or Theme.color.text,
	})

	Widgets.label(locked and "앞 스테이지를 깨면 열립니다" or stage.note, {
		Parent = row,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, -150, 0, 32),
		TextSize = Theme.text.small,
		TextColor3 = locked and Theme.color.textFaint or Theme.color.textDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	--[[
		난이도와 상대 라이프는 숨기지 않는다. 잠긴 칸에서도 "뒤로 갈수록 세진다" 는
		곡선이 보여야 목록이 진도로 읽힌다 — 감춰야 하는 것은 공략(note)뿐이다.
	]]
	Widgets.label(("%s · 상대 라이프 %d"):format(stage.difficulty, stage.life), {
		Parent = row,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, -150, 0, 18),
		TextSize = Theme.text.tiny,
		TextColor3 = Theme.color.textFaint,
	})

	--------------------------------------------------------------------
	-- 오른쪽 — 보상과 버튼
	--------------------------------------------------------------------
	local side = new("Frame", {
		Name = "Side",
		Parent = row,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(130, 72),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right),
	})

	local reward = new("Frame", {
		Name = "Reward",
		Parent = side,
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(130, 20),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right),
	})

	goldIcon({ Parent = reward, LayoutOrder = 1, Size = UDim2.fromOffset(16, 16) })

	--[[
		이미 깬 칸은 보상을 **취소선으로** 보여준다. 숫자를 지워버리면 "이 스테이지는
		얼마짜리였나" 를 다시 볼 수 없고, 그냥 두면 또 받을 수 있는 것처럼 읽힌다.
	]]
	local cleared = stage.cleared
	Widgets.label(cleared and ("<s>%d</s>"):format(stage.gold) or tostring(stage.gold), {
		Parent = reward,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(72, 20),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		TextColor3 = cleared and Theme.color.textFaint or Theme.color.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local button = Widgets.button(cleared and "다시" or "도전", {
		Parent = side,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(130, 36),
		BackgroundColor3 = cleared and Theme.color.panelSoft or Theme.color.creature,
		TextSize = Theme.text.label,
	}, function()
		self.callbacks.start(stage.index)
	end)

	Widgets.setEnabled(button, stage.unlocked)

	if cleared then
		Widgets.label("클리어", {
			Parent = row,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -134, 0, 2),
			Size = UDim2.fromOffset(60, 20),
			TextSize = Theme.text.tiny,
			TextColor3 = Theme.color.ok,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
end

--==========================================================================
-- 렌더
--==========================================================================

function Campaign:setVisible(visible)
	self.gui.Enabled = visible
end

--[[
	payload 는 서버가 보낸 그대로다. (Net 의 로비 프로토콜 참조)
]]
function Campaign:render(payload)
	Widgets.clear(self.list)

	self.goldLabel.Text = tostring(payload.gold or 0)
	self.message.Text = payload.text or ""
	self.message.TextColor3 = payload.text and Theme.color.warn or Theme.color.textDim

	for _, stage in payload.stages or {} do
		self:addRow(stage)
	end
end

return Campaign
