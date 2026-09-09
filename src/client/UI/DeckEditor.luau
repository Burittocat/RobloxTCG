--[[
	덱 편집 화면.

	왼쪽에 카드 전부, 오른쪽에 내 덱. 카드를 누르면 한 장 들어가고, 덱 쪽에서 누르면
	한 장 빠진다. 저장은 서버가 다시 검증한다 — 이 화면의 판정은 **거부당할 조작을
	애초에 못 하게 하려는 것**이지, 규칙을 여기서 정하는 게 아니다.
	(규칙은 Decks.validateEntries 한 곳에 있고, 서버와 여기가 같은 함수를 부른다)

	60장을 채우기 전에는 저장 버튼이 꺼져 있고 몇 장인지 숫자로 보여준다.
	"저장을 눌렀더니 거부당하는" 것보다 "아직 못 누른다" 가 낫다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)
local Decks = require(Shared.Decks)

local CardView = require(script.Parent.CardView)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local new = Widgets.new
local Registry = Rules.Registry
local Config = Rules.Config
local CardType = Rules.Enums.CardType

-- 표기는 Enums 한 곳에서 온다. 여기 사본을 두면 이름을 바꿀 때 한쪽만 바뀐다.
local KEYWORD_KR = Rules.Enums.KeywordDisplay

local TYPE_ORDER = { [CardType.Cost] = 1, [CardType.Creature] = 2, [CardType.Spell] = 3 }
local TYPE_KR = { [CardType.Cost] = "코스트", [CardType.Creature] = "생물", [CardType.Spell] = "마법" }

local DeckEditor = {}
DeckEditor.__index = DeckEditor

--==========================================================================
-- 카드 한 줄
--==========================================================================

local function keywordText(def)
	local parts = {}
	for _, keyword in def.keywords or {} do
		table.insert(parts, KEYWORD_KR[keyword] or keyword)
	end
	return table.concat(parts, " · ")
end

--[[
	카드 한 장을 나타내는 줄. 목록에서도 덱에서도 같은 모양을 쓴다 —
	같은 카드가 자리에 따라 달라 보이면 옮겨 다니는 동안 눈이 카드를 놓친다.
]]
local function cardRow(parent, def, order, count, onClick, onInspect)
	local body = def.power and ("%d/%d"):format(def.power, def.toughness) or "—"
	local tags = keywordText(def)

	local button = Widgets.button("", {
		Name = "Card_" .. def.id,
		Parent = parent,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.color.panelSoft,
	}, onClick)

	-- 왼쪽 클릭은 넣고 빼는 것, 오른쪽 클릭은 들여다보는 것. 두 조작이 섞이면
	-- "보려고 눌렀는데 덱이 바뀌는" 일이 생긴다.
	if onInspect then
		button.MouseButton2Click:Connect(onInspect)
	end

	Widgets.label(("%s   %s"):format(def.name, tags), {
		Parent = button,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -120, 1, 0),
		TextSize = Theme.text.label,
	})

	Widgets.label(("%s  %s"):format(def.cost and ("%d코"):format(def.cost) or "—", body), {
		Parent = button,
		Position = UDim2.new(1, -110, 0, 0),
		Size = UDim2.fromOffset(60, 34),
		TextColor3 = Theme.color.textDim,
		TextSize = Theme.text.small,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	if count then
		Widgets.label(("x%d"):format(count), {
			Name = "Count",
			Parent = button,
			Position = UDim2.new(1, -44, 0, 0),
			Size = UDim2.fromOffset(34, 34),
			TextColor3 = Theme.color.accent,
			Font = Theme.font.bold,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end

	return button
end

--==========================================================================
-- 뼈대
--==========================================================================

function DeckEditor.new(parent)
	local self = setmetatable({}, DeckEditor)

	self.counts = {} -- cardId -> 매수
	self.callbacks = {} -- save / reset / back 을 App 이 채운다

	self:build(parent)
	return self
end

function DeckEditor:build(parent)
	local gui = new("ScreenGui", {
		Name = "TCGDeck",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 25,
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
	})
	Widgets.autoScale(root)

	local column = new("Frame", {
		Name = "Column",
		Parent = root,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -80, 1, -60),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})

	--------------------------------------------------------------------
	-- 머리말
	--------------------------------------------------------------------
	local header = new("Frame", {
		Name = "Header",
		Parent = column,
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
	})

	Widgets.label("덱 편집", {
		Parent = header,
		Size = UDim2.fromOffset(200, 40),
		Font = Theme.font.bold,
		TextSize = 30,
	})

	self.countLabel = Widgets.label("", {
		Name = "DeckCount",
		Parent = header,
		Position = UDim2.fromOffset(200, 0),
		Size = UDim2.new(1, -420, 0, 40),
		TextColor3 = Theme.color.textDim,
		TextSize = Theme.text.label,
	})

	self.messageLabel = Widgets.label("", {
		Name = "DeckMessage",
		Parent = header,
		Position = UDim2.new(1, -220, 0, 0),
		Size = UDim2.fromOffset(220, 40),
		TextColor3 = Theme.color.textDim,
		TextSize = Theme.text.small,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	--------------------------------------------------------------------
	-- 목록 두 개
	--------------------------------------------------------------------
	local body = new("Frame", {
		Name = "Body",
		Parent = column,
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -100),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 12),
	})

	local function makeColumn(name, title, order)
		local panel = Widgets.panel({
			Name = name,
			Parent = body,
			LayoutOrder = order,
			Size = UDim2.new(0.5, -6, 1, 0),
		})

		local titleLabel = Widgets.label(title, {
			Name = "Title",
			Parent = panel,
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -24, 0, 24),
			TextColor3 = Theme.color.textDim,
			TextSize = Theme.text.label,
		})

		local scroll = new("ScrollingFrame", {
			Name = "List",
			Parent = panel,
			Position = UDim2.fromOffset(10, 38),
			Size = UDim2.new(1, -20, 1, -48),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, {
			--[[
				**세로 정렬은 Top 이어야 한다.**

				Widgets.listLayout 의 기본값은 Center 다. 내용이 스크롤 영역보다 길어지면
				위아래로 똑같이 넘쳐서 **맨 위가 잘리고, 스크롤로도 거기까지 못 올라간다**
				(캔버스는 0 부터인데 내용이 그 위로 밀려 있다). 카드 32장은 항상 넘친다.
			]]
			Widgets.listLayout(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
		})

		return scroll, titleLabel
	end

	self.catalogList = makeColumn("Catalog", ("카드 %d종 — 누르면 덱에 한 장"):format(Registry.count()), 1)
	self.deckList, self.deckTitle = makeColumn("Deck", "내 덱", 2)

	--------------------------------------------------------------------
	-- 버튼
	--------------------------------------------------------------------
	local footer = new("Frame", {
		Name = "Footer",
		Parent = column,
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 10),
	})

	local function addButton(key, text, order, color)
		local button = Widgets.button(text, {
			Name = "Deck_" .. key,
			Parent = footer,
			LayoutOrder = order,
			Size = UDim2.fromOffset(160, 40),
			BackgroundColor3 = color or Theme.color.panelSoft,
		}, function()
			local handler = self.callbacks[key]
			if handler then
				handler()
			end
		end)

		self[key .. "Button"] = button
		return button
	end

	addButton("save", "저장", 1, Theme.color.creature)
	addButton("reset", "스타터 덱으로", 2)
	addButton("back", "돌아가기", 3)

	Widgets.label("카드를 오른쪽 클릭하면 자세히 볼 수 있습니다", {
		Name = "InspectHint",
		Parent = footer,
		LayoutOrder = 4,
		Size = UDim2.fromOffset(320, 40),
		TextColor3 = Theme.color.textFaint,
		TextSize = Theme.text.small,
	})

	self:buildDetail(root)
end

--==========================================================================
-- 카드 상세 (오른쪽 클릭)
--==========================================================================

--[[
	카드 한 장을 크게 보여준다. 목록의 한 줄은 이름·코스트·공/체까지밖에 못 담는데,
	덱을 짜려면 그 카드가 **무엇을 하는지**를 봐야 한다.

	화면 가운데를 덮지 않고 오른쪽에 띄운다 — 보면서 계속 목록을 만질 수 있어야 한다.
]]
--[[
	상세 상자는 CardView 것을 쓴다. 전투 화면도 같은 상자를 띄운다 —
	같은 카드를 어디서 열든 같은 설명이 나와야 한다.

	여기서만 붙는 것은 마지막 줄("내 덱에 3장")뿐이다. 전투 중에는 덱을 못 고치므로
	그 줄이 의미가 없다.
]]
function DeckEditor:buildDetail(root)
	self.detail = CardView.detail({
		Parent = root,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -50, 0.5, 0),
	})
end

function DeckEditor:showDetail(def)
	self.detailDef = def

	local count = self.counts[def.id] or 0
	local max = Decks.maxCopies(def.id)
	local note = (max >= Config.deckSize) and ("내 덱에 %d장 (매수 제한 없음)"):format(count)
		or ("내 덱에 %d장 / 최대 %d장"):format(count, max)

	self.detail.show(def, note)
end

function DeckEditor:hideDetail()
	self.detail.hide()
	self.detailDef = nil
end

function DeckEditor:setVisible(visible)
	self.gui.Enabled = visible
end

--==========================================================================
-- 편집
--==========================================================================

function DeckEditor:total()
	local total = 0
	for _, count in self.counts do
		total += count
	end
	return total
end

function DeckEditor:add(cardId)
	local max = Decks.maxCopies(cardId)
	local current = self.counts[cardId] or 0

	if self:total() >= Config.deckSize then
		self:setMessage(("덱은 %d장까지입니다"):format(Config.deckSize), false)
		return
	end
	if current >= max then
		self:setMessage(("이 카드는 %d장까지입니다"):format(max), false)
		return
	end

	self.counts[cardId] = current + 1
	self:render()
end

function DeckEditor:remove(cardId)
	local current = self.counts[cardId] or 0
	if current <= 0 then
		return
	end

	self.counts[cardId] = (current > 1) and (current - 1) or nil
	self:render()
end

function DeckEditor:entries()
	local out = {}
	for _, def in Registry.all() do
		local count = self.counts[def.id]
		if count and count > 0 then
			table.insert(out, { id = def.id, count = count })
		end
	end
	return out
end

function DeckEditor:setMessage(text, good)
	self.messageLabel.Text = text or ""
	self.messageLabel.TextColor3 = good and Theme.color.ok or Theme.color.warn
end

--==========================================================================
-- 그리기
--==========================================================================

local function sortedDefs()
	local defs = {}
	for _, def in Registry.all() do
		table.insert(defs, def)
	end

	table.sort(defs, function(a, b)
		local ta, tb = TYPE_ORDER[a.type] or 9, TYPE_ORDER[b.type] or 9
		if ta ~= tb then
			return ta < tb
		end
		if (a.cost or 0) ~= (b.cost or 0) then
			return (a.cost or 0) < (b.cost or 0)
		end
		return a.id < b.id
	end)

	return defs
end

function DeckEditor:render()
	local total = self:total()

	Widgets.clear(self.catalogList)
	Widgets.clear(self.deckList)

	local order = 0
	local lastType

	for _, def in sortedDefs() do
		order += 1

		-- 종류가 바뀌는 자리에 머리글을 넣는다. 32장을 한 줄로 죽 늘어놓으면 못 찾는다.
		if def.type ~= lastType then
			lastType = def.type
			Widgets.label(TYPE_KR[def.type] or def.type, {
				Parent = self.catalogList,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 22),
				TextColor3 = Theme.color.textFaint,
				TextSize = Theme.text.small,
			})
			order += 1
		end

		cardRow(self.catalogList, def, order, self.counts[def.id], function()
			self:add(def.id)
		end, function()
			self:showDetail(def)
		end)
	end

	order = 0
	for _, def in sortedDefs() do
		local count = self.counts[def.id]
		if count and count > 0 then
			order += 1
			cardRow(self.deckList, def, order, count, function()
				self:remove(def.id)
			end, function()
				self:showDetail(def)
			end)
		end
	end

	self.countLabel.Text = ("%d / %d 장"):format(total, Config.deckSize)
	self.countLabel.TextColor3 = (total == Config.deckSize) and Theme.color.ok or Theme.color.textDim
	self.deckTitle.Text = ("내 덱 — 누르면 한 장 뺀다 (%d장)"):format(total)

	-- 60장이 아니면 저장을 아예 못 누른다. 서버가 거부할 것을 미리 막는다.
	Widgets.setEnabled(self.saveButton, total == Config.deckSize)

	-- 열어둔 상세의 "내 덱에 N장" 도 같이 따라가야 한다. 안 그러면 넣고 뺀 직후에
	-- 옛 숫자가 남아 "안 들어갔나?" 하게 된다.
	if self.detailDef then
		self:showDetail(self.detailDef)
	end
end

--[[
	서버가 준 덱으로 화면을 채운다. payload 는 Net.LobbyScreen 의 "deck" 모양.
]]
function DeckEditor:load(payload)
	self.counts = {}
	for _, entry in payload.entries or {} do
		self.counts[entry.id] = entry.count
	end

	self:hideDetail()
	self:render()
	self:setMessage(payload.text, payload.saved == true)
end

return DeckEditor
