--[[
	프로필 — 랭크 · 순위 · 전적 · 지금 덱 · 낀 꾸밈 · 모은 정도.

	내 것은 시작 화면 [프로필] 에서, **남의 것**은 순위표에서 이름을 눌러 연다(mine = false).
	남의 것에는 덱과 골드가 없다 — 서버가 아예 안 보낸다(Lobby:viewProfile).

	**보기만 하는 화면이다.** 덱은 덱 편집에서, 꾸밈은 꾸미기에서 고친다. 여기서도 고치게
	하면 같은 판정이 두 곳에 생긴다(Lobby:openProfile).

	MMR 은 여기 오지 않는다 — 숨은 점수다(Rank 머리말). 보이는 것은 랭크 점수와 티어뿐이다.

	꾸밈 미리보기는 전투 · 꾸미기와 **같은 함수**(CardView.frameStyle · CardView.cardBack)로
	그린다. 세 곳이 각자 칠하면 셋이 서로 다르게 보인다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rank = require(Shared.Rank)
local Rules = require(Shared.Rules)
local Cosmetics = require(Shared.Cosmetics)

local CardView = require(script.Parent.CardView)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local new = Widgets.new
local Registry = Rules.Registry
local Config = Rules.Config

local Profile = {}
Profile.__index = Profile

local PREVIEW = Vector2.new(56, 78)

local function rgb(triple)
	return Color3.fromRGB(triple[1], triple[2], triple[3])
end

function Profile.new(parent)
	local self = setmetatable({}, Profile)

	local noop = function() end
	self.callbacks = { back = noop }
	self.backTo = "home"

	self:build(parent)
	return self
end

--==========================================================================
-- 뼈대
--==========================================================================

function Profile:build(parent)
	local gui = new("ScreenGui", {
		Name = "TCGProfile",
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
		Size = UDim2.fromOffset(700, 580),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center),
	})

	self.nameLabel = Widgets.label("", {
		Name = "ProfileName",
		Parent = column,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.font.bold,
		TextSize = 30,
	})

	--------------------------------------------------------------------
	-- 위 줄 — 랭크 · 꾸밈
	--------------------------------------------------------------------
	local top = new("Frame", {
		Name = "Top",
		Parent = column,
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 140),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left),
	})

	local rankPanel = Widgets.panel({
		Name = "RankPanel",
		Parent = top,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(400, 140),
	}, {
		Widgets.padding(14),
		Widgets.listLayout(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})

	self.tierLabel = Widgets.label("", {
		Name = "Tier",
		Parent = rankPanel,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 36),
		Font = Theme.font.bold,
		TextSize = 30,
	})

	self.nextLabel = Widgets.label("", {
		Name = "NextTier",
		Parent = rankPanel,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = Theme.text.body,
		TextColor3 = Theme.color.textDim,
	})

	self.recordLabel = Widgets.label("", {
		Name = "Record",
		Parent = rankPanel,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
	})

	self.looksPanel = Widgets.panel({
		Name = "LooksPanel",
		Parent = top,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(290, 140),
	}, {
		Widgets.padding(12),
		Widgets.listLayout(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center),
	})

	--------------------------------------------------------------------
	-- 덱
	--------------------------------------------------------------------
	local deckPanel = Widgets.panel({
		Name = "DeckPanel",
		Parent = column,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 250),
	}, {
		Widgets.padding(14),
	})

	self.deckTitle = Widgets.label("", {
		Name = "DeckTitle",
		Parent = deckPanel,
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
	})

	self.deckNote = Widgets.label("", {
		Name = "DeckNote",
		Parent = deckPanel,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.small,
		TextColor3 = Theme.color.textDim,
	})

	local chipLayout = Widgets.listLayout(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	chipLayout.Wraps = true

	self.deckList = new("Frame", {
		Name = "DeckList",
		Parent = deckPanel,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
	}, {
		chipLayout,
	})

	--------------------------------------------------------------------
	-- 아래 — 모은 정도 · 뒤로
	--------------------------------------------------------------------
	self.statsLabel = Widgets.label("", {
		Name = "Stats",
		Parent = column,
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = Theme.text.body,
		TextColor3 = Theme.color.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- 어디로 돌아갈지는 서버가 정해 보낸다(backTo) — 순위표에서 왔으면 순위표로.
	Widgets.button("뒤로", {
		Parent = column,
		LayoutOrder = 5,
		Size = UDim2.fromOffset(200, 40),
		TextSize = Theme.text.label,
	}, function()
		self.callbacks.back(self.backTo)
	end)
end

--==========================================================================
-- 조각
--==========================================================================

-- 꾸밈 하나 — 미리보기 위, 이름 아래.
local function lookSlot(parent, order, caption, preview, name)
	local slot = new("Frame", {
		Parent = parent,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(110, 116),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})

	preview.LayoutOrder = 1
	preview.Parent = slot

	Widgets.label(("%s · %s"):format(caption, name), {
		Parent = slot,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.small,
		TextColor3 = Theme.color.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
end

local function framePreview(frameId)
	local color, thickness = CardView.frameStyle(frameId)
	return new("Frame", {
		Name = "FramePreview",
		Size = UDim2.fromOffset(PREVIEW.X, PREVIEW.Y),
		BackgroundColor3 = Theme.color.creature,
		BorderSizePixel = 0,
	}, {
		Widgets.corner(6),
		Widgets.stroke(color, thickness),
	})
end

--[[
	덱 목록. 코스트 카드는 한 줄 요약으로 빼고 나머지를 코스트 · 이름 순 칩으로.
	코스트 카드 24장을 칩 하나로 세우면 덱이 무엇인지 안 보인다.
	-> 카드 장수 합, 코스트 카드 장수
]]
function Profile:paintDeck(entries)
	Widgets.clear(self.deckList)

	local cards, total, costs = {}, 0, 0
	for _, entry in entries or {} do
		local def = type(entry) == "table" and Registry.get(entry.id)
		if def and type(entry.count) == "number" then
			total += entry.count
			if Config.copyLimitExemptTypes[def.type] then
				costs += entry.count
			else
				table.insert(cards, { def = def, count = entry.count })
			end
		end
	end

	table.sort(cards, function(a, b)
		if (a.def.cost or 0) ~= (b.def.cost or 0) then
			return (a.def.cost or 0) < (b.def.cost or 0)
		end
		return a.def.name < b.def.name
	end)

	for index, card in cards do
		local chip = new("Frame", {
			Name = "DeckCard_" .. card.def.id,
			Parent = self.deckList,
			LayoutOrder = index,
			BackgroundColor3 = Theme.color.panelSoft,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
		}, {
			Widgets.corner(5),
			Widgets.padding(0, { PaddingLeft = 8, PaddingRight = 8 }),
		})

		local rare = card.def.rarity == "Rare"
		Widgets.label(("%d  %s  ×%d"):format(card.def.cost or 0, card.def.name, card.count), {
			Parent = chip,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextSize = Theme.text.small,
			Font = rare and Theme.font.bold or Theme.font.regular,
			TextColor3 = rare and Theme.color.accent or Theme.color.text,
		})
	end

	return total, costs
end

--==========================================================================
-- 렌더
--==========================================================================

function Profile:setVisible(visible)
	self.gui.Enabled = visible
end

--[[
	payload 는 서버가 보낸 그대로다. (Net 의 로비 프로토콜 — profile 화면)
]]
function Profile:render(payload)
	local mine = payload.mine ~= false
	self.backTo = (payload.backTo == "leaderboard") and "leaderboard" or "home"
	self.nameLabel.Text = tostring(payload.name or "")

	-- 랭크 ---------------------------------------------------------------
	local points = tonumber(payload.rankPoints) or 0
	local tier, nextTier = Rank.tierOf(points)

	self.tierLabel.Text = ("%s  <font size=\"20\">%d점</font>"):format(tier.name, points)
	self.tierLabel.TextColor3 = rgb(tier.color)

	local nextText = nextTier and ("%s까지 %d점"):format(nextTier.name, nextTier.points - points)
		or "가장 높은 티어입니다"
	-- 순위표(위 50명) 안이면 순위를 붙인다. 밖이면 말하지 않는다 — 몇 등인지 알 길이 없다(LeaderboardStore).
	if tonumber(payload.place) then
		nextText = ("순위 %d위 · %s"):format(payload.place, nextText)
	end
	self.nextLabel.Text = nextText

	local wins, losses = tonumber(payload.wins) or 0, tonumber(payload.losses) or 0
	local games = wins + losses
	if games > 0 then
		self.recordLabel.Text = ("%d승 %d패 · 승률 %d%%"):format(wins, losses, math.floor(wins / games * 100 + 0.5))
	else
		self.recordLabel.Text = "아직 랭크전 기록이 없습니다"
	end

	-- 꾸밈 ---------------------------------------------------------------
	Widgets.clear(self.looksPanel)
	local frame = Cosmetics.frameOrDefault(payload.frame)
	local back = Cosmetics.backOrDefault(payload.back)
	lookSlot(self.looksPanel, 1, "테두리", framePreview(frame.id), frame.name)
	lookSlot(self.looksPanel, 2, "뒷면", CardView.cardBack(0, back.id, PREVIEW), back.name)

	-- 덱 -----------------------------------------------------------------
	if not mine then
		-- 남의 덱은 서버가 아예 안 보낸다(Lobby:viewProfile). 대전 상대에게 전략이 새는 정보다.
		self:paintDeck({})
		self.deckTitle.Text = "덱"
		self.deckNote.Text = "다른 사람의 덱은 볼 수 없습니다"
		self.deckNote.TextColor3 = Theme.color.textDim
		self.statsLabel.Text = ("모은 카드 %d / %d   ·   캠페인 %d / %d"):format(
			tonumber(payload.collected) or 0,
			tonumber(payload.total) or 0,
			tonumber(payload.cleared) or 0,
			tonumber(payload.stages) or 0
		)
		return
	end

	local total, costs = self:paintDeck(payload.deck)
	self.deckTitle.Text = ("내 덱 — %d장"):format(total)

	if payload.deckPlayable == false then
		-- 가진 카드로 안 짜지는 덱은 판이 열릴 때 스타터 덱으로 바뀐다(Lobby:deckFor). 그걸 미리 말한다.
		self.deckNote.Text = "가진 카드로 짤 수 없는 덱이라, 지금은 스타터 덱으로 대전합니다"
		self.deckNote.TextColor3 = Theme.color.warn
	else
		self.deckNote.Text = ("코스트 카드 %d장 · 나머지 %d장"):format(costs, total - costs)
		self.deckNote.TextColor3 = Theme.color.textDim
	end

	--[[
		모은 정도. **골드만 금색으로 띄운다** — 한 줄에 셋을 흐린 글씨로 나열하면 돈이
		얼마인지가 나머지와 같은 무게로 묻힌다(2026-11-13). 색은 Theme.color.accent
		(247, 206, 112) 와 같은 값이다 — 리치텍스트는 Color3 를 못 받아 글자로 적는다.
	]]
	self.statsLabel.Text = ("모은 카드 %d / %d   ·   캠페인 %d / %d   ·   <font color='#F7CE70'>골드 %d</font>"):format(
		tonumber(payload.collected) or 0,
		tonumber(payload.total) or 0,
		tonumber(payload.cleared) or 0,
		tonumber(payload.stages) or 0,
		tonumber(payload.gold) or 0
	)
end

return Profile
