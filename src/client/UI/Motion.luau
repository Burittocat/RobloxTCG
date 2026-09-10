--[[
	트윈 헬퍼.

	여기에는 **어떻게 움직이는가** 만 있다. 언제 무엇이 움직이는지는 Battle 이 정한다.
	시간 값은 전부 Theme.motion 에서 온다 — 이 파일에 숫자를 박지 않는다.

	--------------------------------------------------------------------------
	위치를 옮기는 연출에는 전제가 있다

	UIListLayout 은 자식의 Position 을 매 프레임 자기가 다시 정한다. 그 줄 안에서는
	위치 트윈이 이겨도 다음 프레임에 덮어써진다 — 카드가 날아가다 제자리로 튄다.

	그래서 손패·필드 줄에서는 레이아웃을 뗐고, Battle:placeRow 가 자리를 직접
	계산한다. 새 줄을 만들 때 카드가 움직여야 한다면 같은 선택을 해야 한다.

	줄 밖에 절대 위치로 얹은 것(배너·떠오르는 숫자)은 원래부터 자유롭고,
	Rotation·색·투명도는 레이아웃 계산에 안 들어가서 어디서든 걸 수 있다.
]]

local TweenService = game:GetService("TweenService")

local Motion = {}

--[[
	기본 이징은 Quad/Out — 빠르게 시작해 부드럽게 멎는다. UI 움직임의 기본값이고,
	화면이 "반응이 빠르다" 고 느껴지는 쪽이다.
]]
function Motion.to(instance, seconds, props, style, direction)
	local info = TweenInfo.new(
		seconds,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)

	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

--[[
	떠오르며 사라지고 스스로 치운다. 피해 숫자처럼 **한 번 보여주고 끝인 것**에 쓴다.

	호출한 쪽이 치울 필요가 없다는 게 요점이다. 라이프가 깎일 때마다 라벨을 만드는데
	그걸 누가 언제 지울지까지 Battle 이 들고 있으면, 판이 끝나 화면이 사라진 뒤에
	지우려 드는 경로가 반드시 생긴다.
]]
function Motion.floatAway(label, distance, seconds)
	--[[
		목표 위치를 UDim2 산술(`from + UDim2.fromOffset(...)`)로 만들지 않는다.
		진짜 로블록스는 되지만 테스트 하네스의 UDim2 에는 그 연산자가 없어서,
		Studio 에서만 도는 코드가 되어버린다. 성분으로 짜면 양쪽에서 똑같이 돈다.
	]]
	local from = label.Position
	local to = UDim2.new(from.X.Scale, from.X.Offset, from.Y.Scale, from.Y.Offset - distance)

	Motion.to(label, seconds, {
		Position = to,
		TextTransparency = 1,
	})

	task.delay(seconds, function()
		label:Destroy()
	end)
end

--[[
	카드가 눕고 서는 것. 탭은 상태가 홱 바뀌는 게 아니라 **동작**이라야 읽힌다 —
	숫자만 바뀌면 "언제 눕었지" 를 놓친다.

	이미 목표 각도면 트윈을 걸지 않는다. 매 렌더마다 0도 -> 0도 트윈을 만들면
	카드 수만큼 쓸데없는 트윈이 쌓인다.
]]
function Motion.rotateTo(frame, degrees, seconds)
	if frame.Rotation == degrees then
		return
	end
	Motion.to(frame, seconds, { Rotation = degrees })
end

--[[
	테두리(UIStroke)가 바뀌는 것. 선택·대상 표시가 홱 바뀌면 눈이 그 변화를 놓친다.
	색과 두께를 같이 트윈해서 "여기가 켜졌다" 가 움직임으로 보이게 한다.
]]
function Motion.strokeTo(stroke, color, thickness, seconds)
	if not stroke then
		return
	end
	if stroke.Color == color and stroke.Thickness == thickness then
		return
	end
	Motion.to(stroke, seconds, { Color = color, Thickness = thickness })
end

return Motion
