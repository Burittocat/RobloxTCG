--[[
	Instance 생성 헬퍼.

	UI 를 코드로 짜는 이유: .rbxmx 안에 UI 가 들어가면 VS Code 에서 diff 가 안 되고
	머지도 안 된다. 전부 Luau 파일이면 화면 구조가 git 히스토리에 남는다.
]]

local Theme = require(script.Parent.Theme)

local Widgets = {}

--[[
	new("Frame", { Size = ... }, { 자식들 }) -> Instance

	자식은 배열로 넘긴다. 값이 nil 이면 조용히 건너뛴다 —
	조건부 자식을 `cond and widget or nil` 로 쓸 수 있게 하려고.
]]
function Widgets.new(className, props, children)
	local instance = Instance.new(className)

	for key, value in props or {} do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end

	for _, child in children or {} do
		if child then
			child.Parent = instance
		end
	end

	if props and props.Parent then
		instance.Parent = props.Parent
	end

	return instance
end

local new = Widgets.new

function Widgets.corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function Widgets.stroke(color, thickness, transparency)
	return new("UIStroke", {
		Color = color or Theme.color.stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Widgets.padding(all, extra)
	local props = {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
	}
	for key, value in extra or {} do
		props[key] = UDim.new(0, value)
	end
	return new("UIPadding", props)
end

function Widgets.listLayout(direction, padding, alignX, alignY)
	return new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, padding or 6),
		HorizontalAlignment = alignX or Enum.HorizontalAlignment.Center,
		VerticalAlignment = alignY or Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

--[[
	배경 패널. 이 게임의 모든 상자는 같은 모양이다.
]]
function Widgets.panel(props, children)
	local merged = {
		BackgroundColor3 = Theme.color.panel,
		BorderSizePixel = 0,
	}
	for key, value in props or {} do
		merged[key] = value
	end

	local kids = { Widgets.corner(8), Widgets.stroke() }
	for _, child in children or {} do
		table.insert(kids, child)
	end

	return new("Frame", merged, kids)
end

function Widgets.label(text, props)
	local merged = {
		BackgroundTransparency = 1,
		Font = Theme.font.regular,
		Text = text,
		TextColor3 = Theme.color.text,
		TextSize = Theme.text.body,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return new("TextLabel", merged)
end

--[[
	눌리는 버튼. enabled=false 면 흐려지고 클릭도 먹지 않는다.
	(비활성 버튼을 아예 숨기지 않는 이유: 위치가 매번 바뀌면 누르기 힘들다)
]]
function Widgets.button(text, props, onClick)
	local merged = {
		BackgroundColor3 = Theme.color.panelSoft,
		BorderSizePixel = 0,
		Font = Theme.font.bold,
		Text = text,
		TextColor3 = Theme.color.text,
		TextSize = Theme.text.label,
		AutoButtonColor = true,
	}
	for key, value in props or {} do
		merged[key] = value
	end

	local button = new("TextButton", merged, { Widgets.corner(6), Widgets.stroke() })

	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

--[[
	꺼진 버튼도 **무엇인지는 읽혀야 한다.** 예전 값(글자 0.55)은 거의 사라져서
	"버튼이 없어진 줄" 알게 됐다. 배경을 더 죽이고 글자는 덜 죽이는 쪽이
	"여기 있지만 지금은 못 누른다" 를 더 정확히 말한다.
]]
function Widgets.setEnabled(button, enabled)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = enabled and 0 or 0.35
	button.BackgroundTransparency = enabled and 0 or 0.65
	button.TextColor3 = enabled and Theme.color.text or Theme.color.textDim
end

--[[
	골드 동전 한 칸. 캠페인 목록 · 카드팩 · 꾸미기가 같은 것을 쓴다.

	`Theme.image.gold` 가 비어 있으면 **동전을 그린다.** 에셋을 아직 안 올렸다고 화면이
	비면 그때까지 그 화면을 못 보게 되므로, 빈 값이 정상 경로다. ID 를 채우는 순간
	같은 자리에 그림이 들어온다 — 이 함수 말고 고칠 곳은 없다.

	예전에는 **투명한 칸에 글자 "G" 하나**였다. 어두운 바탕 위의 어두운 칸에서는 숫자
	옆의 장식처럼 묻혀 "이게 내 골드" 로 읽히지 않았다(2026-11-13 사용자 지적).
	지금은 **채운 원 + 그 안의 어두운 글자**다 — 원이 배경을 가리므로 무엇 위에 얹어도
	동전으로 보인다.
]]
function Widgets.goldIcon(props)
	local merged = {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(18, 18),
	}
	for key, value in props or {} do
		merged[key] = value
	end

	if Theme.image.gold ~= "" then
		merged.Image = Theme.image.gold
		return new("ImageLabel", merged)
	end

	merged.BackgroundColor3 = Theme.color.accent
	merged.BackgroundTransparency = 0
	merged.BorderSizePixel = 0

	return new("Frame", merged, {
		-- CornerRadius 를 (1, 0) 으로 주면 짧은 변의 절반 — 칸이 커지든 작아지든 원이다.
		new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Widgets.label("G", {
			Name = "GoldMark",
			--[[
				**1px 올린다.** 로블록스는 글자를 글리프가 아니라 줄 상자(line box)로
				가운데 맞추고, 그 상자에는 g · y 처럼 밑으로 내려가는 글자 자리가 들어
				있다. "G" 는 그 자리를 안 쓰므로 동전 안에서 아래로 내려가 보인다
				(2026-11-13 사용자 지적). 눈으로 맞추는 값이니 고칠 곳은 이 숫자 하나다.
			]]
			Position = UDim2.fromOffset(0, -1),
			Size = UDim2.fromScale(1, 1),
			Font = Theme.font.bold,
			-- 동전 위의 글자다. 밝은 금색 바탕이므로 글자는 가장 어두운 색이어야 읽힌다.
			TextColor3 = Theme.color.bgDeep,
			TextSize = Theme.text.small,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		}),
	})
end

--[[
	화면 머리의 "가진 골드" 칩. -> frame, label

	캠페인 · 카드팩 · 꾸미기 셋이 같은 자리에 같은 모양으로 쓴다. 예전에는 셋이 각자
	같은 코드를 베껴 적어뒀고, 그래서 한 곳을 고치면 둘이 뒤처졌다.

	**바탕을 깐다.** 투명한 칸에 숫자만 띄워두면 어두운 배경과 한 덩어리로 보여서 어디까지가
	내 돈인지 읽히지 않는다 — 패널 색과 금색 테두리로 한 칸을 만들면 그 자리가 생긴다.

	이름 둘은 **테스트가 붙잡고 있다** — 칩은 `Purse`, 숫자 칸은 `Gold`.
	숫자 칸의 Text 는 숫자만 둔다(테스트가 잔액과 그대로 비교한다).
]]
function Widgets.goldChip(props)
	local merged = {
		Name = "Purse",
		BackgroundColor3 = Theme.color.panelSoft,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(152, 34),
	}
	for key, value in props or {} do
		merged[key] = value
	end

	local frame = new("Frame", merged, {
		Widgets.corner(17),
		Widgets.stroke(Theme.color.accent, 1, 0.5),
		Widgets.padding(0, { PaddingLeft = 12, PaddingRight = 12 }),
		Widgets.listLayout(Enum.FillDirection.Horizontal, 7, Enum.HorizontalAlignment.Right),
	})

	Widgets.goldIcon({ Parent = frame, LayoutOrder = 1 })

	local label = Widgets.label("0", {
		Name = "Gold",
		Parent = frame,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(96, 24),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
		TextColor3 = Theme.color.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	return frame, label
end

--[[
	화면 전체 배율을 창 크기에 맞춘다. 전체 화면을 채우는 root 프레임에 건다.

	    Widgets.autoScale(root)

	UIScale 은 자식의 **scale 성분까지** 곱한다. 그래서 UIScale 만 걸면
	`UDim2.new(1, 0, ...)` 짜리 가로 전체 위젯이 화면 밖으로 삐져나간다.
	root 를 1/배율 크기로 잡아 그 곱을 되돌린다.

	결과가 이 설계의 핵심이다 — root 안쪽은 **창 크기와 무관하게 항상 세로 900 짜리
	화면**이 된다. 고정 레이아웃의 세로 예산이 창 크기에 따라 무너지던 문제가 사라지고,
	큰 모니터에서는 같은 배치가 그냥 크게 보인다.

	(배율 상·하한을 벗어나면 가상 높이가 900 이 아니게 되지만, 그 구간에서는
	 넘치는 쪽이 여백이라 안전하다)
]]
function Widgets.autoScale(root)
	local scale = new("UIScale", { Parent = root })
	local camera = workspace.CurrentCamera

	local function apply()
		local height = Theme.uiScale.referenceHeight
		if camera then
			height = camera.ViewportSize.Y
		end
		if height <= 0 then
			height = Theme.uiScale.referenceHeight
		end

		local factor = math.clamp(
			height / Theme.uiScale.referenceHeight,
			Theme.uiScale.min,
			Theme.uiScale.max
		)

		scale.Scale = factor
		root.Size = UDim2.fromScale(1 / factor, 1 / factor)
	end

	apply()

	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end

	return scale
end

--[[
	자식을 전부 지운다. UIListLayout / UIPadding / UICorner 같은 꾸밈 객체는 남긴다
	(전부 UIComponent 를 상속한다) — 매 렌더마다 레이아웃까지 다시 만들면 한 프레임씩 튄다.
]]
function Widgets.clear(container)
	for _, child in container:GetChildren() do
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

return Widgets
