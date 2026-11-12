--[[
	꾸미기 화면 — 카드 테두리와 카드 뒷면을 사고 낀다.

	  [테두리]     내가 낸 카드(손패 · 필드)에 둘러진다. 상대 화면에서도 내 생물에 보인다
	  [카드 뒷면]  상대 화면에서 내 손패가 이 뒷면으로 보인다

	판에는 아무 영향이 없다(Cosmetics 머리말).

	카드팩 화면과 같은 태도다 — 여기에는 판정이 없다. 골드가 모자라면 [사기] 를 꺼두는
	것까지만 하고, 진짜 판정(잔액 · 가졌나 · 저장)은 Lobby:buyCosmetic 이 한다. 결과는
	**저장에 성공했을 때만** 화면에 바뀌어 온다.

	칸마다 미리보기가 있다. 말로 설명하는 것보다 그려 보이는 것이 빠르고, 미리보기도
	판과 **같은 함수**(CardView.frameStyle · CardView.cardBack)로 칠한다 — 여기서 본 것과
	판에서 보이는 것이 어긋나지 않게.

	탭은 화면이 들고 있는다. 서버는 두 목록을 늘 같이 내려주고, 무언가를 사서 화면이 다시
	와도 보던 탭이 그대로다 — 뒷면을 샀는데 테두리 탭으로 튕기면 방금 산 것이 안 보인다.
]]

local CardView = require(script.Parent.CardView)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local new = Widgets.new

local Wardrobe = {}
Wardrobe.__index = Wardrobe

local TILE_WIDTH = 204
local TILE_HEIGHT = 150
local PREVIEW = Vector2.new(70, 96)

-- 탭 순서와 글자. key 는 서버 payload 의 목록 이름이다(Net 의 wardrobe 화면).
local TABS = {
	{ key = "frames", label = "테두리", note = "낀 테두리는 내가 낸 카드에 둘러지고, 상대 화면에서도 보입니다." },
	{ key = "backs", label = "카드 뒷면", note = "상대 화면에서 내 손패가 이 뒷면으로 보입니다." },
}

function Wardrobe.new(parent)
	local self = setmetatable({}, Wardrobe)

	local noop = function() end
	self.callbacks = { buy = noop, equip = noop, back = noop }
	self.tab = TABS[1].key
	self.payload = nil

	self:build(parent)
	return self
end

--==========================================================================
-- 뼈대
--==========================================================================

function Wardrobe:build(parent)
	local gui = new("ScreenGui", {
		Name = "TCGWardrobe",
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
		Size = UDim2.fromOffset(660, 560),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center),
	})

	--------------------------------------------------------------------
	-- 머리 — 제목과 쓸 수 있는 골드 (카드팩 화면과 같은 자리 · 같은 모양)
	--------------------------------------------------------------------
	local header = new("Frame", {
		Name = "Header",
		Parent = column,
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
	})

	Widgets.label("꾸미기", {
		Parent = header,
		Size = UDim2.new(0.6, 0, 1, 0),
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

	Widgets.goldIcon({ Parent = purse, LayoutOrder = 1 })

	self.goldLabel = Widgets.label("0", {
		Name = "Gold",
		Parent = purse,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(120, 28),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
		TextColor3 = Theme.color.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	--------------------------------------------------------------------
	-- 탭
	--------------------------------------------------------------------
	local tabRow = new("Frame", {
		Name = "Tabs",
		Parent = column,
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 36),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left),
	})

	self.tabButtons = {}
	for index, tab in TABS do
		self.tabButtons[tab.key] = Widgets.button(tab.label, {
			Name = "Tab_" .. tab.key,
			Parent = tabRow,
			LayoutOrder = index,
			Size = UDim2.fromOffset(130, 36),
			TextSize = Theme.text.label,
		}, function()
			self:selectTab(tab.key)
		end)
	end

	self.note = Widgets.label("", {
		Name = "TabNote",
		Parent = column,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = Theme.text.small,
		TextColor3 = Theme.color.textDim,
	})

	--------------------------------------------------------------------
	-- 칸들 — 세 칸씩 두 줄
	--------------------------------------------------------------------
	local listLayout = Widgets.listLayout(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	listLayout.Wraps = true

	self.grid = new("Frame", {
		Name = "Items",
		Parent = column,
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, TILE_HEIGHT * 2 + 10),
	}, {
		listLayout,
	})

	--------------------------------------------------------------------
	-- 안내와 뒤로
	--------------------------------------------------------------------
	self.message = Widgets.label("", {
		Name = "WardrobeMessage",
		Parent = column,
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = Theme.text.body,
		TextColor3 = Theme.color.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	Widgets.button("뒤로", {
		Parent = column,
		LayoutOrder = 6,
		Size = UDim2.fromOffset(200, 40),
		TextSize = Theme.text.label,
	}, function()
		self.callbacks.back()
	end)
end

--==========================================================================
-- 미리보기
--==========================================================================

--[[
	테두리 미리보기. 진짜 카드처럼 종류 색 바탕에 두른다 — 테두리 색은 바탕과 어울려
	보여야 의미가 있고, 회색 상자 위에서는 실제와 다르게 보인다. 바탕은 생물 색이다 —
	필드에 오래 남아 상대 눈에 가장 많이 띄는 것이 생물이다.
]]
local function framePreview(id)
	local color, thickness = CardView.frameStyle(id)

	return new("Frame", {
		Name = "Preview",
		Size = UDim2.fromOffset(PREVIEW.X, PREVIEW.Y),
		BackgroundColor3 = Theme.color.creature,
		BorderSizePixel = 0,
	}, {
		Widgets.corner(7),
		Widgets.stroke(color, thickness),
		Widgets.label("2 / 3", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, 0, 0, 20),
			Font = Theme.font.bold,
			TextSize = Theme.text.label,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

-- 뒷면 미리보기. 판에서 쓰는 바로 그 함수를 크게 부른다.
local function backPreview(id)
	local card = CardView.cardBack(0, id, PREVIEW)
	card.Name = "Preview"
	return card
end

--==========================================================================
-- 한 칸
--==========================================================================

--[[
	칸 하나. 버튼은 상태에 따라 셋 중 하나다.

	  안 가짐   [사기]   골드가 모자라면 꺼둔다
	  가짐      [끼기]
	  끼는 중   [끼는 중] 꺼둔다 — 무엇을 끼고 있는지 칸 테두리로도 보인다

	버튼 이름은 Act_<id> 다. 글자가 칸마다 같아서("사기") 글자로는 어느 칸인지 못 짚는다.
]]
function Wardrobe:addTile(index, entry, gold)
	local tile = Widgets.panel({
		Name = "Item_" .. entry.id,
		Parent = self.grid,
		LayoutOrder = index,
		Size = UDim2.fromOffset(TILE_WIDTH, TILE_HEIGHT),
		BackgroundColor3 = entry.equipped and Theme.color.panelSoft or Theme.color.panel,
	}, {
		Widgets.padding(10),
	})

	if entry.equipped then
		for _, child in tile:GetChildren() do
			if child:IsA("UIStroke") then
				child.Color = Theme.color.me
				child.Thickness = 2
			end
		end
	end

	local preview = (self.tab == "backs") and backPreview(entry.id) or framePreview(entry.id)
	preview.Parent = tile

	local side = new("Frame", {
		Parent = tile,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(PREVIEW.X + 10, 0),
		Size = UDim2.new(1, -(PREVIEW.X + 10), 1, 0),
	})

	Widgets.label(entry.name, {
		Name = "ItemName",
		Parent = side,
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
	})

	local status
	if entry.equipped then
		status = "끼는 중"
	elseif entry.owned then
		status = "가짐"
	else
		status = ("%d G"):format(entry.price or 0)
	end

	Widgets.label(status, {
		Name = "ItemStatus",
		Parent = side,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		TextColor3 = entry.owned and Theme.color.ok or Theme.color.accent,
	})

	local label, enabled, onClick
	if entry.equipped then
		label, enabled = "끼는 중", false
	elseif entry.owned then
		label, enabled = "끼기", true
		onClick = function()
			self.callbacks.equip(entry.id)
		end
	else
		label, enabled = "사기", gold >= (entry.price or 0)
		onClick = function()
			self.callbacks.buy(entry.id)
		end
	end

	local button = Widgets.button(label, {
		Name = "Act_" .. entry.id,
		Parent = side,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = entry.owned and Theme.color.panelSoft or Theme.color.creature,
		TextSize = Theme.text.label,
	}, onClick)

	Widgets.setEnabled(button, enabled)
end

--==========================================================================
-- 렌더
--==========================================================================

function Wardrobe:setVisible(visible)
	self.gui.Enabled = visible
end

function Wardrobe:selectTab(key)
	self.tab = key
	if self.payload then
		self:paint()
	end
end

--[[
	payload 는 서버가 보낸 그대로다. (Net 의 로비 프로토콜 — wardrobe 화면)
]]
function Wardrobe:render(payload)
	self.payload = payload
	self:paint()

	self.message.Text = payload.text or "골드는 캠페인 스테이지를 처음 깰 때와 빠른 대전에서 이길 때 받습니다"
	self.message.TextColor3 = payload.failed and Theme.color.warn or Theme.color.textDim
end

-- 지금 탭의 칸들을 다시 그린다. 탭을 바꿀 때는 서버를 거치지 않는다 — 두 목록이 이미 와 있다.
function Wardrobe:paint()
	local payload = self.payload
	local gold = tonumber(payload.gold) or 0
	self.goldLabel.Text = tostring(gold)

	for _, tab in TABS do
		local selected = (tab.key == self.tab)
		local button = self.tabButtons[tab.key]
		button.BackgroundColor3 = selected and Theme.color.creature or Theme.color.panelSoft
		button.TextColor3 = selected and Theme.color.text or Theme.color.textDim
		if selected then
			self.note.Text = tab.note
		end
	end

	Widgets.clear(self.grid)
	for index, entry in payload[self.tab] or {} do
		if type(entry) == "table" and type(entry.id) == "string" then
			self:addTile(index, entry, gold)
		end
	end
end

return Wardrobe
