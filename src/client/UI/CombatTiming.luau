--[[
	때리는 장면의 **시간표**.

	화면도 로블록스도 모르는 순수 계산이다. Theme 의 숫자를 인자로 받는 것이
	그래서다 — 여기서 Theme 를 require 하면 Color3 가 딸려 와서 룰 엔진 테스트가
	이 파일을 못 읽는다. 연출 중 유일하게 테스트로 못 박을 수 있는 부분이라
	굳이 떼어냈다 (tests/specs/strike.luau).
]]

local CombatTiming = {}

--[[
	이번 전투의 시간표를 미리 짠다.

	한 공격자가 여럿을 때리면(겹쳐 막기) 돌진은 **차례로** 일어난다 — 카드 하나가
	동시에 두 곳에 달려갈 수는 없다. 그래서 "몇 번째 이벤트인가" 만으로는 언제 닿는지
	알 수 없고, 같은 공격자가 앞 돌진을 끝내기를 기다린 시간까지 더해야 한다.

	이 표 하나를 셋이 같이 본다 — 실제 돌진(playCombat) · 죽는 카드를 붙잡아 두는
	시간(playDeath) · 플레이어 라이프 숫자(renderPlayerPanel). 계산이 두 벌이 되면
	그중 하나가 조용히 거짓말을 시작한다. rangedDirectDamage 에서 배운 것과 같다.

	  starts[i]   i 번째 이벤트의 돌진이 시작하는 시각
	  impact[id]  그 카드가 **마지막으로** 맞는 시각. 쓰러지는 연출을 여기까지 미룬다
	  player[id]  그 플레이어가 마지막으로 맞는 시각
	  total       전부 끝나는 시각. 남은 홀드를 쓸어담는 시점이다

	여기서 재는 것은 예정이지 실측이 아니다. 노드가 없어 돌진이 걸러지면 실제로는
	더 일찍 끝난다 — 그래도 늦게 쓸어담는 쪽이 안전하다(settleStats 참조).
]]
function CombatTiming.schedule(events, strike, shake)
	-- 달려가 닿기까지 / 한 번의 돌진 전체 / 한 번 흔들리는 데 걸리는 시간.
	local reachTime = strike.windup + strike.dash
	local wholeStrike = reachTime + strike.hold + strike.recover
	local shakeTime = (shake.times * 2 + 1) * shake.each

	local schedule = { starts = {}, impact = {}, player = {}, total = 0 }
	local freeAt = {}
	local order = 0

	local function lastHit(map, id, at)
		if id and (map[id] == nil or map[id] < at) then
			map[id] = at
		end
	end

	for index, event in events do
		local targetId = nil
		if event.kind == "Blocked" then
			targetId = event.blockerId
		elseif event.kind == "HitCreature" then
			targetId = event.targetId
		end

		if event.attackerId and (targetId or event.kind == "HitPlayer") then
			order += 1

			local start = math.max((order - 1) * strike.stagger, freeAt[event.attackerId] or 0)
			local at = start + reachTime

			schedule.starts[index] = start
			freeAt[event.attackerId] = start + wholeStrike

			-- 공격자도 맞을 수 있다(겹쳐 막기의 반격). 쓰러질 시각을 위해 같이 적는다.
			lastHit(schedule.impact, event.attackerId, at)
			lastHit(schedule.impact, targetId, at)

			if event.kind == "HitPlayer" then
				lastHit(schedule.player, event.playerId, at)
			end

			--[[
				맞은 쪽은 흔들리는 동안 제자리가 아니다. 그 카드가 곧 제 차례로
				공격한다면 흔들림이 끝나야 달려갈 수 있다. 지금 이미 바쁜 카드라면
				흔들림은 실제로도 건너뛰므로(shakeCard) 시간을 늘리지 않는다.
			]]
			if targetId and (freeAt[targetId] or 0) <= at then
				freeAt[targetId] = at + shakeTime
			end

			schedule.total = math.max(schedule.total, start + wholeStrike)
		end
	end

	return schedule
end

return CombatTiming
