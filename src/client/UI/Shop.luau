--[[
	카드팩 화면.

	골드로 팩을 사서 까면, 나온 카드가 한 줄로 펼쳐진다. 새 카드는 컬렉션에 들어가고
	덱 편집에서 바로 쓸 수 있다. 이미 4장 가진 카드는 골드로 돌려받는다.

	여기에도 판정이 없다. 살 수 있는지는 서버가 내려준 잔액과 가격을 비교해 **버튼을
	켜고 끄는 것**까지만 한다 — 거부당할 조작을 애초에 못 하게 하려는 것이다. 진짜 판정
	(잔액 · 무엇이 나오나 · 저장)은 Lobby:buyPack 이 한다. 무엇이 나올지도 서버가 정한다 —
	클라이언트가 뽑으면 원하는 것이 나올 때까지 다시 뽑을 수 있다.

	결과는 **저장에 성공했을 때만** 온다(Net 의 shop 화면). 그래서 여기 펼쳐진 카드는
	다음 접속에도 있다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local new = Widgets.new
local Registry = Rules.Registry
local CardType = Rules.Enums.CardType

local Shop = {}
Shop.__index = Shop

local TILE_WIDTH = 116
local TILE_HEIGHT = 150

function Shop.new(parent)
	local self = setmetatable({}, Shop)

	local noop = function() end
	self.callbacks = { buy = noop, buyRobux = noop, back = noop }
	self.robuxProductId = 0

	self:build(parent)
	return self
end

--==========================================================================
-- 뼈대
--==========================================================================

function Shop:build(parent)
	local gui = new("ScreenGui", {
		Name = "TCGShop",
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
		Size = UDim2.fromOffset(660, 520),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center),
	})

	--------------------------------------------------------------------
	-- 머리 — 제목과 쓸 수 있는 골드 (캠페인 목록과 같은 자리 · 같은 모양)
	--------------------------------------------------------------------
	local header = new("Frame", {
		Name = "Header",
		Parent = column,
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
	})

	Widgets.label("카드팩", {
		Parent = header,
		Size = UDim2.new(0.5, 0, 1, 0),
		Font = Theme.font.bold,
		TextSize = 32,
	})

	-- 칩의 모양과 이름(Purse · Gold)은 Widgets.goldChip 한 곳에 있다.
	local _, goldLabel = Widgets.goldChip({ Parent = header })
	self.goldLabel = goldLabel

	--------------------------------------------------------------------
	-- 팩 — 무엇이 들었나 · 가격 · 사기
	--------------------------------------------------------------------
	local pack = Widgets.panel({
		Name = "Pack",
		Parent = column,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 150),
	}, {
		Widgets.padding(14),
	})

	self.packTitle = Widgets.label("", {
		Parent = pack,
		Size = UDim2.new(1, -190, 0, 24),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
	})

	self.packNote = Widgets.label("", {
		Parent = pack,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, -190, 0, 20),
		TextSize = Theme.text.small,
		TextColor3 = Theme.color.textDim,
	})

	--[[
		모은 정도. "아직 무엇이 남았나" 가 숫자로라도 보여야 팩을 사는 것이 진도로 읽힌다.
		캠페인 목록이 잠긴 칸을 숨기지 않는 것과 같은 이유다.
	]]
	self.collectedLabel = Widgets.label("", {
		Name = "Collected",
		Parent = pack,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, -190, 0, 20),
		TextSize = Theme.text.small,
		TextColor3 = Theme.color.textFaint,
	})

	local side = new("Frame", {
		Name = "Side",
		Parent = pack,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(170, 122),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right),
	})

	local price = new("Frame", {
		Name = "Price",
		Parent = side,
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(170, 22),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right),
	})

	Widgets.goldIcon({ Parent = price, LayoutOrder = 1, Size = UDim2.fromOffset(16, 16) })

	self.priceLabel = Widgets.label("", {
		Parent = price,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(72, 22),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		TextColor3 = Theme.color.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	self.buyButton = Widgets.button("팩 열기", {
		Name = "Buy",
		Parent = side,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(170, 44),
		BackgroundColor3 = Theme.color.creature,
		TextSize = Theme.text.title,
	}, function()
		self.callbacks.buy()
	end)

	--[[
		Robux 로 사기. 상품 ID 가 0 이면(아직 안 만들었다) **숨긴다** — 꺼둔 채 보이면
		"언젠가 눌리는 버튼" 으로 읽히는데, 그건 이 화면이 아니라 운영이 정할 일이다.

		누르면 Roblox 의 구매 창이 뜬다. 결제가 끝나면 서버가 영수증을 받아 팩을 넣고
		이 화면을 다시 내려준다(Lobby:processReceipt) — 여기서는 기다리기만 한다.
	]]
	self.robuxButton = Widgets.button("Robux로 열기", {
		Name = "BuyRobux",
		Parent = side,
		LayoutOrder = 3,
		Visible = false,
		Size = UDim2.fromOffset(170, 40),
		BackgroundColor3 = Theme.color.cost,
		TextSize = Theme.text.label,
	}, function()
		self.callbacks.buyRobux(self.robuxProductId)
	end)

	--------------------------------------------------------------------
	-- 방금 깐 팩
	--------------------------------------------------------------------
	self.pulls = new("Frame", {
		Name = "Pulls",
		Parent = column,
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, TILE_HEIGHT),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center),
	})

	--------------------------------------------------------------------
	-- 안내와 뒤로
	--------------------------------------------------------------------
	self.message = Widgets.label("", {
		Name = "ShopMessage",
		Parent = column,
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = Theme.text.body,
		TextColor3 = Theme.color.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	Widgets.button("뒤로", {
		Parent = column,
		LayoutOrder = 5,
		Size = UDim2.fromOffset(200, 40),
		TextSize = Theme.text.label,
	}, function()
		self.callbacks.back()
	end)
end

--==========================================================================
-- 나온 카드 한 장
--==========================================================================

local function statLine(def)
	if def.type == CardType.Creature then
		return ("%d코  %d/%d"):format(def.cost or 0, def.power or 0, def.toughness or 0)
	end
	if def.type == CardType.Spell then
		return ("%d코  마법"):format(def.cost or 0)
	end
	return ""
end

--[[
	희귀는 테두리를 금색으로 칠한다. 다섯 장 중 무엇이 "좋은 것" 인지가 글자를 읽기 전에
	보여야 팩을 까는 순간이 산다.

	중복으로 돌려받은 장은 흐리게 둔다 — 컬렉션에 안 들어갔다는 것이 한눈에 보여야
	"이 카드 왜 덱 편집에 안 늘었지" 를 안 묻는다.
]]
function Shop:addTile(index, pull)
	local def = Registry.get(pull.id)
	if not def then
		return
	end

	local rare = pull.rarity == "Rare"

	local tile = Widgets.panel({
		Name = ("Pull_%d"):format(index),
		Parent = self.pulls,
		LayoutOrder = index,
		Size = UDim2.fromOffset(TILE_WIDTH, TILE_HEIGHT),
		BackgroundColor3 = rare and Theme.color.panelSoft or Theme.color.panel,
		BackgroundTransparency = pull.kept and 0 or 0.45,
	}, {
		Widgets.padding(8),
	})

	if rare then
		for _, child in tile:GetChildren() do
			if child:IsA("UIStroke") then
				child.Color = Theme.color.accent
				child.Thickness = 2
			end
		end
	end

	Widgets.label(rare and "희귀" or "일반", {
		Parent = tile,
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = Theme.text.tiny,
		TextColor3 = rare and Theme.color.accent or Theme.color.textFaint,
	})

	Widgets.label(def.name, {
		Name = "PullName",
		Parent = tile,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 44),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	Widgets.label(statLine(def), {
		Parent = tile,
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.small,
		TextColor3 = Theme.color.textDim,
	})

	Widgets.label(pull.kept and "새 카드" or ("중복 · %d G"):format(pull.refund or 0), {
		Name = "PullStatus",
		Parent = tile,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Theme.font.bold,
		TextSize = Theme.text.small,
		TextColor3 = pull.kept and Theme.color.ok or Theme.color.textFaint,
	})
end

--==========================================================================
-- 렌더
--==========================================================================

function Shop:setVisible(visible)
	self.gui.Enabled = visible
end

--[[
	payload 는 서버가 보낸 그대로다. (Net 의 로비 프로토콜 참조)
]]
function Shop:render(payload)
	local gold = tonumber(payload.gold) or 0
	local price = tonumber(payload.price) or 0

	self.goldLabel.Text = tostring(gold)
	self.priceLabel.Text = tostring(price)
	self.packTitle.Text = ("기본 팩 — %d장"):format(tonumber(payload.size) or 0)
	self.packNote.Text = ("희귀 %d장 확정 · 이미 4장 가진 카드는 골드로 돌려받습니다"):format(
		tonumber(payload.rares) or 0
	)
	self.collectedLabel.Text = ("모은 카드 %d / %d"):format(tonumber(payload.collected) or 0, tonumber(payload.total) or 0)

	-- 모자라면 꺼둔다. 눌렀다가 거부당하는 것보다 "아직 못 누른다" 가 낫다(덱 편집의 저장과 같다).
	Widgets.setEnabled(self.buyButton, price > 0 and gold >= price)

	self.robuxProductId = tonumber(payload.robuxProductId) or 0
	self.robuxButton.Visible = self.robuxProductId ~= 0

	Widgets.clear(self.pulls)
	for index, pull in payload.pulls or {} do
		self:addTile(index, pull)
	end

	local text = payload.text
	if not text and price > 0 and gold < price then
		text = "골드는 캠페인 스테이지를 처음 깰 때와 빠른 대전에서 이길 때 받습니다"
	end

	self.message.Text = text or ""
	self.message.TextColor3 = payload.failed and Theme.color.warn or Theme.color.textDim
end

return Shop
