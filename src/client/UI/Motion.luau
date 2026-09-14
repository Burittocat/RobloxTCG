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
	제자리에서 흔들린다. **맞았다**는 표시다.

	Rotation 이 아니라 위치로 흔든다 — 필드 카드는 Rotation 을 "탭됨" 표시에 쓰고
	있어서, 흔들다 끝나면 눕은 카드가 서 버린다.

	왕복이 끝나면 반드시 home 으로 돌아온다. 중간에 판이 갱신돼 카드가 다른 자리로
	가야 하면 호출한 쪽이 onDone 에서 다시 배치한다.
]]
function Motion.shake(frame, distance, times, each, onDone)
	local home = frame.Position
	local homeX, homeY = home.X.Offset, home.Y.Offset

	local function step(index)
		if index > times * 2 then
			Motion.to(frame, each, {
				Position = UDim2.new(home.X.Scale, homeX, home.Y.Scale, homeY),
			})
			task.delay(each, function()
				if onDone then
					onDone()
				end
			end)
			return
		end

		-- 왕복하며 폭이 줄어든다. 같은 폭으로 흔들면 기계가 진동하는 것처럼 보인다.
		local decay = 1 - (index - 1) / (times * 2)
		local side = (index % 2 == 1) and 1 or -1
		local offset = distance * decay * side

		Motion.to(frame, each, {
			Position = UDim2.new(home.X.Scale, homeX + offset, home.Y.Scale, homeY),
		})
		task.delay(each, function()
			step(index + 1)
		end)
	end

	step(1)
end

--[[
	때리러 갔다 돌아온다. 되감고 · 달려들고 · 멎고 · 제자리로.

	dx, dy 는 **여기까지 가라**는 변위다(이미 reach 가 곱해진 값). 호출한 쪽이
	배율을 나눠서 넘긴다 — 이 파일은 화면 좌표를 모른다.

	onImpact 는 가장 멀리 닿은 순간 불린다. 맞는 쪽의 흔들림과 피해 숫자가
	그 박자에 맞아야 부딪힌 것으로 읽힌다 — 먼저 뜨면 맞기도 전에 아파한다.
]]
function Motion.strike(frame, dx, dy, timing, onImpact, onDone)
	local home = frame.Position
	local homeX, homeY = home.X.Offset, home.Y.Offset
	local scaleX, scaleY = home.X.Scale, home.Y.Scale

	local length = math.sqrt(dx * dx + dy * dy)
	local backX, backY = 0, 0
	if length > 0 then
		backX = -dx / length * timing.backswing
		backY = -dy / length * timing.backswing
	end

	-- 되감기. 뒤로 빼는 동안은 천천히 — 그래야 다음의 빠름이 빠르게 느껴진다.
	Motion.to(frame, timing.windup, {
		Position = UDim2.new(scaleX, homeX + backX, scaleY, homeY + backY),
	})

	task.delay(timing.windup, function()
		-- 달려드는 구간만 이징이 In 이다. 끝까지 가속해서 부딪혀야 한다.
		Motion.to(frame, timing.dash, {
			Position = UDim2.new(scaleX, homeX + dx, scaleY, homeY + dy),
		}, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

		task.delay(timing.dash, function()
			if onImpact then
				onImpact()
			end

			task.delay(timing.hold, function()
				Motion.to(frame, timing.recover, {
					Position = UDim2.new(scaleX, homeX, scaleY, homeY),
				})
				task.delay(timing.recover, function()
					if onDone then
						onDone()
					end
				end)
			end)
		end)
	end)
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

--[[
	글자가 잠깐 커졌다 제자리 크기로 돌아온다.

	값이 바뀐 것을 **눈이 따라가게** 하는 데 쓴다. 숫자가 조용히 다른 숫자로
	바뀌면 화면 어딘가가 달라졌다는 것만 알고 어디인지는 모른다.

	커진 상태를 먼저 대입하고 원래 크기로 트윈한다 — 커지는 것까지 트윈하면
	두 트윈이 이어져야 해서, 중간에 값이 또 바뀔 때 크기가 어긋난 채로 남는다.
]]
function Motion.popText(label, grow, seconds)
	if not label then
		return
	end

	local base = label.TextSize
	label.TextSize = base + grow
	Motion.to(label, seconds, { TextSize = base })
end

return Motion
