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

--[[
	겉 프레임은 그대로 두고 **속만 다시 칠한다.**

	렌더마다 카드를 새로 만들면 트윈을 걸 대상이 매번 바뀌어 연출이 불가능하다
	(자세한 이유는 Reconcile.luau). 그래서 프레임의 신원은 유지하고 내용만 갱신한다.

	`Widgets.clear` 는 UIComponent(모서리·테두리·여백)를 남기므로, 그 셋은 여기서
	다시 만들지 않고 **값만 고친다.**
]]
function CardView.paintHand(button, def, opts)
	opts = opts or {}

	local color, thickness = outlineFor(opts)
	local dim = (opts.playable == false)

	button.BackgroundColor3 = typeColor(def)
	-- 못 내는 카드는 흐리게. 다만 "무슨 카드인지" 는 계속 읽혀야 한다 —
	-- 다음 턴에 뭘 낼지 계획하는 것도 플레이의 일부다.
	button.BackgroundTransparency = dim and 0.45 or 0.05

	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness
	end

	Widgets.clear(button)

	local kids = {
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
	}

	if def.keywords and #def.keywords > 0 then
		local row = keywordRow(def.keywords, 17)
		row.Position = UDim2.fromOffset(0, 70)
		table.insert(kids, row)
	end

	if def.type == CardType.Creature then
		table.insert(
			kids,
			Widgets.label(("%d / %d"):format(def.power, def.toughness), {
				Position = UDim2.new(0, 0, 1, -28),
				Size = UDim2.new(1, 0, 0, 26),
				Font = Theme.font.bold,
				TextSize = Theme.text.stat,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTransparency = dim and 0.25 or 0,
			})
		)
	end

	for _, kid in kids do
		kid.Parent = button
	end

	return button
end

function CardView.handCard(def, opts)
	opts = opts or {}

	local size = Theme.size.handCard

	--[[
		여기서 만드는 것은 **변하지 않는 것들뿐이다.** 상태에 따라 달라지는 색·투명도·
		테두리는 paintHand 가 매 렌더마다 다시 칠한다.
	]]
	local button = new("TextButton", {
		Name = "Hand_" .. def.id,
		Size = UDim2.fromOffset(size.X, size.Y),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.layoutOrder or 0,
	}, {
		Widgets.corner(8),
		Widgets.stroke(Theme.color.stroke, Theme.outline.idle),
		Widgets.padding(7),
	})

	CardView.paintHand(button, def, opts)

	--[[
		연결은 **만들 때 한 번만** 한다. 콜백이 잡는 것은 카드 인스턴스 id 뿐이고
		그건 이 프레임이 사는 내내 같은 값이라, 다시 칠할 때 갈아끼울 필요가 없다.

		오른쪽 클릭은 "들여다보기" 다. 왼쪽 클릭(내기·고르기)과 섞지 않는다 —
		한 버튼에 섞으면 "보려고 눌렀는데 카드가 나가는" 일이 생긴다.
	]]
	if opts.onInspect then
		button.MouseButton2Click:Connect(opts.onInspect)
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

--[[
	필드 카드도 겉 프레임을 유지하고 속만 다시 칠한다 (이유는 CardView.paintHand).

	필드 카드는 손패보다 상태가 많다 — 탭 여부로 기울기·투명도가 바뀌고, 전투가
	짜이면 배지가 붙었다 떨어진다. 전부 여기서 갱신한다.
]]
function CardView.paintField(button, state, instance, opts)
	opts = opts or {}

	local def = Registry.mustGet(instance.defId)
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

	button.BackgroundColor3 = typeColor(def)
	button.BackgroundTransparency = instance.tapped and 0.55 or 0.05

	-- 탭은 기울여서 표시한다. 예전 4도는 사실상 안 보였다.
	-- 90도(진짜 TCG 방식)로 눕히면 옆 카드와 겹쳐서 12도로 타협했다.
	button.Rotation = instance.tapped and 12 or 0

	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness
	end

	Widgets.clear(button)

	local kids = {
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
	}

	for _, kid in kids do
		kid.Parent = button
	end

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

	return button
end

function CardView.fieldCard(state, instance, opts)
	opts = opts or {}

	local size = Theme.size.fieldCard

	-- 변하지 않는 것만 여기서. 나머지는 paintField 가 매 렌더마다 다시 칠한다.
	local button = new("TextButton", {
		Name = "Field_" .. instance.id,
		Size = UDim2.fromOffset(size.X, size.Y),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = opts.layoutOrder or 0,
	}, {
		Widgets.corner(7),
		Widgets.stroke(Theme.color.stroke, Theme.outline.idle),
		Widgets.padding(6),
	})

	CardView.paintField(button, state, instance, opts)

	-- 연결은 만들 때 한 번만 (이유는 CardView.handCard).
	if opts.onInspect then
		button.MouseButton2Click:Connect(opts.onInspect)
	end

	if opts.onClick then
		button.Activated:Connect(opts.onClick)
	end

	return button
end

--==========================================================================
-- 필드 위 코스트 카드 (작은 칩)
--==========================================================================

--[[
	코스트 칩도 상태가 바뀐다 — 코스트를 쓰면 탭되고, 턴이 넘어오면 풀린다.
	칩 자체는 그대로 두고 그 두 모습만 갈아끼운다.
]]
function CardView.paintCost(chip, instance)
	chip.BackgroundTransparency = instance.tapped and 0.7 or 0.15
	chip.Rotation = instance.tapped and 12 or 0

	local stroke = chip:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = instance.tapped and 0.5 or 0
	end

	local pip = chip:FindFirstChild("Pip")
	if pip then
		pip.Text = instance.tapped and "○" or "●"
		pip.TextColor3 = instance.tapped and Theme.color.textFaint or Theme.color.accent
	end

	return chip
end

function CardView.costCard(instance, layoutOrder)
	local size = Theme.size.costChip

	local chip = new("Frame", {
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Theme.color.cost,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder or 0,
	}, {
		Widgets.corner(5),
		Widgets.stroke(Theme.color.stroke, 1, 0),
		Widgets.label("●", {
			Name = "Pip",
			Size = UDim2.fromScale(1, 1),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})

	return CardView.paintCost(chip, instance)
end

--==========================================================================
-- 카드 상세 — 덱 편집과 전투가 같은 것을 쓴다
--==========================================================================

local TYPE_LONG = {
	Cost = "코스트 카드",
	Creature = "생물",
	Spell = "마법",
}

--[[
	카드 상세 상자. -> { frame, show(def, note), hide() }

	    detail = CardView.detail({ Parent = root, Position = ..., AnchorPoint = ... })
	    detail.show(def, "내 덱에 3장")   note 는 없으면 그 줄이 안 뜬다
	    detail.hide()

	**태그 설명이 여기 붙는다.** 카드에 적힌 설명문은 카드마다 따로 쓰여 있어서,
	같은 태그가 카드마다 다르게 설명되거나(창공의 매 vs 매부리) 아예 빠진다
	(폭풍 비룡은 "비행, 신속" 이 전부다). 태그 자체의 규칙은 Enums.KeywordText
	한 곳에서 읽는다 — 그래야 어느 카드를 열어도 같은 답이 나온다.

	상자 높이는 내용에 맞춰 늘어난다(AutomaticSize). 태그가 둘이면 설명도 두 줄이라
	고정 높이로는 잘리거나 빈 자리가 남는다.
]]
function CardView.detail(props)
	local merged = {
		Name = "Detail",
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		BackgroundColor3 = Theme.color.panel,
	}
	for key, value in props or {} do
		merged[key] = value
	end

	local panel = Widgets.panel(merged, {
		Widgets.padding(16),
		Widgets.listLayout(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top),
	})

	local function line(name, order, height, props2)
		local merged2 = {
			Name = name,
			Parent = panel,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, height),
		}
		for key, value in props2 or {} do
			merged2[key] = value
		end
		return Widgets.label("", merged2)
	end

	local detail = { frame = panel }

	local nameLabel = line("DetailName", 1, 30, { Font = Theme.font.bold, TextSize = 24 })
	local typeLabel = line("DetailType", 2, 20, { TextColor3 = Theme.color.textDim, TextSize = Theme.text.label })
	local statLabel = line("DetailStat", 3, 34, {
		Font = Theme.font.bold,
		TextColor3 = Theme.color.accent,
		TextSize = Theme.text.stat,
	})
	local tagLabel = line("DetailTags", 4, 22, { TextColor3 = Theme.color.stack, TextSize = Theme.text.label })

	-- 태그 설명. 태그 수만큼 늘어나므로 높이를 내용에 맡긴다.
	local tagText = line("DetailTagText", 5, 0, {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Theme.color.textDim,
		TextSize = Theme.text.body,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local textLabel = line("DetailText", 6, 0, {
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Theme.text.body,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local noteLabel = line("DetailNote", 7, 22, { TextColor3 = Theme.color.me, TextSize = Theme.text.label })

	Widgets.button("닫기", {
		Name = "DetailClose",
		Parent = panel,
		LayoutOrder = 8,
		Size = UDim2.new(1, 0, 0, 32),
	}, function()
		detail.hide()
	end)

	function detail.show(def, note)
		nameLabel.Text = def.name
		typeLabel.Text = ("%s%s"):format(TYPE_LONG[def.type] or def.type, def.rarity == "Rare" and "  ·  희귀" or "")

		local parts = {}
		if def.cost then
			table.insert(parts, ("코스트 %d"):format(def.cost))
		end
		if def.power then
			table.insert(parts, ("공격력 %d"):format(def.power))
			table.insert(parts, ("생명력 %d"):format(def.toughness))
		end
		statLabel.Text = table.concat(parts, "   ")

		local names, rules = {}, {}
		for _, keyword in def.keywords or {} do
			table.insert(names, Enums.KeywordDisplay[keyword] or keyword)
			table.insert(rules, ("<b>%s</b> — %s"):format(Enums.KeywordDisplay[keyword] or keyword, Enums.KeywordText[keyword] or ""))
		end

		tagLabel.Text = (#names > 0) and table.concat(names, " · ") or "태그 없음"
		tagText.Text = table.concat(rules, "\n")
		--[[
			카드 고유 설명. 태그 설명은 여기 쓰지 않기로 했으므로(Sheet.luau 주석),
			태그만 있는 카드는 이 줄이 비어 있는 게 정상이다. 그때 "특별한 효과가 없습니다"
			라고 하면 거짓말이 된다 — 비행이라는 효과가 바로 위에 적혀 있다.
		]]
		local text = def.text or ""
		if text == "" and #names == 0 then
			text = "특별한 효과가 없습니다."
		end
		textLabel.Text = text

		noteLabel.Text = note or ""
		panel.Visible = true
	end

	function detail.hide()
		panel.Visible = false
	end

	return detail
end

return CardView
