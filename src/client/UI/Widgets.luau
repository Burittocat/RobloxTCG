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
