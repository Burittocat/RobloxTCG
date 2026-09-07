--[[
	카드 한 장을 그리는 곳.

	아직 아트가 없으므로 종류별 색 + 코스트 + 스탯 + 키워드 칩으로만 구분한다.
	나중에 이미지가 생기면 가운데 빈 자리에 ImageLabel 을 끼우면 된다.

	모든 카드는 TextButton 이다 — 필드 위 생물도 대상 지정 때 눌러야 하므로
	"누를 수 있는지" 를 나중에 바꾸는 것보다 처음부터 버튼으로 두는 게 단순하다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local new = Widgets.new
local Enums = Rules.Enums
local Registry = Rules.Registry
local Keywords = Rules.Keywords
local CardType = Enums.CardType

local CardView = {}

--==========================================================================
-- 조각
--==========================================================================

local function typeColor(def)
	if def.type == CardType.Cost then
		return Theme.color.cost
	elseif def.type == CardType.Creature then
		return Theme.color.creature
	end
	return Theme.color.spell
end

local TYPE_NAME = {
	Cost = "코스트",
	Creature = "생물",
	Spell = "마법",
}

-- 코스트 카드 자체에는 코스트가 없다(자원이라 내는 데 비용이 안 든다).
local function costChip(cost)
	return new("Frame", {
		Name = "Cost",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Theme.color.bgDeep,
		BorderSizePixel = 0,
	}, {
		new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Widgets.stroke(Theme.color.accent, 2, 0),
		Widgets.label(tostring(cost), {
			Size = UDim2.fromScale(1, 1),
			Font = Theme.font.bold,
			TextSize = Theme.text.label,
			TextColor3 = Theme.color.accent,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

--[[
	키워드 칩 줄. keywords 는 { "Haste", ... } 배열이거나 { [kw] = true } 집합.
	(카드 정의는 배열, 필드 위 인스턴스는 Keywords.effective 가 주는 집합)
]]
local function keywordRow(keywords, height)
	local names = {}
	if #keywords > 0 then
		for _, keyword in keywords do
			table.insert(names, keyword)
		end
	else
		for keyword in keywords do
			table.insert(names, keyword)
		end
	end
	table.sort(names)

	local row = new("Frame", {
		Name = "Keywords",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
	}, {
		Widgets.listLayout(Enum.FillDirection.Horizontal, 3, Enum.HorizontalAlignment.Left),
	})

	for _, keyword in names do
		-- 칩 배경을 어둡게 깔고 글자를 키워드 색으로 얹는다.
		-- 예전처럼 칩 자체를 키워드 색으로 칠하면 카드 배경색과 섞여서
		-- 카드마다 같은 키워드가 다른 색으로 보였다.
		local chip = new("Frame", {
			BackgroundColor3 = Theme.color.bgDeep,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(0, height),
			AutomaticSize = Enum.AutomaticSize.X,
		}, {
			Widgets.corner(4),
			Widgets.padding(0, { PaddingLeft = 5, PaddingRight = 5 }),
			Widgets.label(Enums.KeywordDisplay[keyword] or keyword, {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 1, 0),
				TextSize = Theme.text.tiny,
				Font = Theme.font.bold,
				TextColor3 = Theme.keywordColor[keyword] or Theme.color.text,
			}),
		})
		chip.Parent = row
	end

	return row
end

--[[
	선택/대상 하이라이트. 카드 크기가 바뀌면 줄 전체가 흔들리므로 테두리만 바꾼다.
]]
local function outlineFor(opts)
	if opts.selected then
		return Theme.color.accent, Theme.outline.selected
	end
	if opts.highlighted then
		return Theme.color.ok, Theme.outline.highlighted
	end
	return Theme.color.stroke, Theme.outline.idle
end

--==========================================================================
-- 손패 카드
--==========================================================================

function CardView.handCard(def, opts)
	opts = opts or {}

	local size = Theme.size.handCard
	local color, thickness = outlineFor(opts)
	local dim = (opts.playable == false)

	local button = new("TextButton", {
		Name = "Hand_" .. def.id,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = typeColor(def),
		-- 못 내는 카드는 흐리게. 다만 "무슨 카드인지" 는 계속 읽혀야 한다 —
		-- 다음 턴에 뭘 낼지 계획하는 것도 플레이의 일부다.
		BackgroundTransparency = dim and 0.45 or 0.05,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.layoutOrder or 0,
	}, {
		Widgets.corner(8),
		Widgets.stroke(color, thickness),
		Widgets.padding(7),

		costChip(def.type == CardType.Cost and "-" or (def.cost or 0)),

		Widgets.label(TYPE_NAME[def.type] or def.type, {
			Position = UDim2.new(1, -48, 0, 5),
			Size = UDim2.fromOffset(48, 18),
			TextSize = Theme.text.small,
			TextColor3 = Theme.color.textDim,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),

		Widgets.label(def.name, {
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 0, 36),
			Font = Theme.font.bold,
			TextSize = 15,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextTransparency = dim and 0.25 or 0,
		}),

		-- 생물은 아래에 스탯 줄이 붙으므로 설명 자리가 더 좁다.
		Widgets.label(def.text or "", {
			Position = UDim2.fromOffset(0, 90),
			Size = UDim2.new(1, 0, 0, def.type == CardType.Creature and 32 or 60),
			TextSize = Theme.text.tiny,
			TextColor3 = Theme.color.textDim,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextTransparency = dim and 0.3 or 0,
		}),
	})

	if def.keywords and #def.keywords > 0 then
		local row = keywordRow(def.keywords, 17)
		row.Position = UDim2.fromOffset(0, 70)
		row.Parent = button
	end

	if def.type == CardType.Creature then
		Widgets.label(("%d / %d"):format(def.power, def.toughness), {
			Parent = button,
			Position = UDim2.new(0, 0, 1, -28),
			Size = UDim2.new(1, 0, 0, 26),
			Font = Theme.font.bold,
			TextSize = Theme.text.stat,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTransparency = dim and 0.25 or 0,
		})
	end

	if opts.onClick then
		button.Activated:Connect(opts.onClick)
	end

	return button
end

--==========================================================================
-- 상대 손패 (뒷면)
--==========================================================================

function CardView.cardBack(layoutOrder)
	return new("Frame", {
		Size = UDim2.fromOffset(26, 38),
		BackgroundColor3 = Theme.color.panelSoft,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder or 0,
	}, {
		Widgets.corner(4),
		Widgets.stroke(Theme.color.stroke, 1, 0.3),
	})
end

--==========================================================================
-- 필드 위 생물
--==========================================================================

function CardView.fieldCard(state, instance, opts)
	opts = opts or {}

	local def = Registry.mustGet(instance.defId)
	local size = Theme.size.fieldCard
	local color, thickness = outlineFor(opts)

	local power = Keywords.power(instance)
	local remaining = Keywords.remainingToughness(instance)
	local hurt = remaining < Keywords.toughness(instance)

	--[[
		상태 표시. 예전에는 흐린 글자 한 줄이라 놓치기 쉬웠는데, 이 둘은
		**놓치면 그대로 오조작으로 이어지는** 정보다 — 탭된 생물을 공격자로 고르려다
		거부당하거나, 이번 턴에 나온 생물을 세어놓고 공격 계획을 세우게 된다.
		그래서 배경이 있는 칩으로 바꾸고 색을 나눴다.

		둘은 다른 상태다. 탭된 생물은 공격도 방어도 못 하지만, 이번 턴에 소환된
		생물은 **공격만** 못 하고 방어는 된다. 그래서 같은 글자를 쓰면 안 된다.
		(룰 코드에서는 이 제한을 hasSummoningSickness 라고 부른다 — 화면에는
		 매직 더 개더링 은어 대신 결과를 그대로 적는다)
	]]
	local status, statusColor = nil, Theme.color.textDim
	if instance.tapped then
		status, statusColor = "탭됨", Theme.color.textFaint
	elseif instance.summonedOnTurn == state.turn and not Keywords.isHaste(instance) then
		status, statusColor = "공격 불가", Theme.color.accent
	end

	local button = new("TextButton", {
		Name = "Field_" .. instance.id,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = typeColor(def),
		BackgroundTransparency = instance.tapped and 0.55 or 0.05,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		-- 탭은 기울여서 표시한다. 예전 4도는 사실상 안 보였다.
		-- 90도(진짜 TCG 방식)로 눕히면 옆 카드와 겹쳐서 12도로 타협했다.
		Rotation = instance.tapped and 12 or 0,
		LayoutOrder = opts.layoutOrder or 0,
	}, {
		Widgets.corner(7),
		Widgets.stroke(color, thickness),
		Widgets.padding(6),

		Widgets.label(def.name, {
			Size = UDim2.new(1, 0, 0, 28),
			Font = Theme.font.bold,
			TextSize = Theme.text.small,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),

		Widgets.label(("%d / %d"):format(power, remaining), {
			Position = UDim2.new(0, 0, 1, -26),
			Size = UDim2.new(1, 0, 0, 26),
			Font = Theme.font.bold,
			TextSize = Theme.text.stat,
			TextColor3 = hurt and Theme.color.warn or Theme.color.text,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})

	local row = keywordRow(Keywords.effective(instance), 16)
	row.Position = UDim2.fromOffset(0, 32)
	row.Parent = button

	if status then
		local chip = new("Frame", {
			Name = "Status",
			Parent = button,
			Position = UDim2.new(0, 0, 1, -46),
			Size = UDim2.new(1, 0, 0, 17),
			BackgroundColor3 = Theme.color.bgDeep,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
		}, {
			Widgets.corner(4),
		})

		Widgets.label(status, {
			Parent = chip,
			Size = UDim2.fromScale(1, 1),
			Font = Theme.font.bold,
			TextSize = Theme.text.small,
			TextColor3 = statusColor,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end

	--[[
		공격/방어 배지. 전투가 어떻게 짜였는지는 판단의 핵심이라
		글자 한 줄이 아니라 색 있는 칩으로 띄운다.
	]]
	if opts.badge then
		local badge = new("Frame", {
			Name = "Badge",
			Parent = button,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 2, 0, -4),
			Size = UDim2.fromOffset(40, 19),
			BackgroundColor3 = opts.badge == "공격" and Theme.color.foe or Theme.color.me,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, {
			Widgets.corner(4),
		})

		Widgets.label(opts.badge, {
			Parent = badge,
			Size = UDim2.fromScale(1, 1),
			Font = Theme.font.bold,
			TextSize = Theme.text.small,
			TextColor3 = Theme.color.bgDeep,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
	end

	if opts.onClick then
		button.Activated:Connect(opts.onClick)
	end

	return button
end

--==========================================================================
-- 필드 위 코스트 카드 (작은 칩)
--==========================================================================

function CardView.costCard(instance, layoutOrder)
	local size = Theme.size.costChip

	return new("Frame", {
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Theme.color.cost,
		BackgroundTransparency = instance.tapped and 0.7 or 0.15,
		BorderSizePixel = 0,
		Rotation = instance.tapped and 12 or 0,
		LayoutOrder = layoutOrder or 0,
	}, {
		Widgets.corner(5),
		Widgets.stroke(Theme.color.stroke, 1, instance.tapped and 0.5 or 0),
		Widgets.label(instance.tapped and "○" or "●", {
			Size = UDim2.fromScale(1, 1),
			TextSize = 22,
			TextColor3 = instance.tapped and Theme.color.textFaint or Theme.color.accent,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

return CardView
