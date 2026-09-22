--[[ 때리는 장면의 시간표 (src/client/UI/CombatTiming.luau) ]]

return function(t, ctx)
	local CombatTiming = ctx.CombatTiming

	--[[
		Theme 의 진짜 값이 아니라 **읽기 쉬운 값**을 넣는다. 여기서 재려는 것은
		"0.23 초가 맞는가" 가 아니라 순서와 겹침이다. 진짜 값을 베껴 두면 연출을
		조금만 손봐도 이 테스트가 깨지는데, 그때 깨진 것은 아무것도 아니다.

		  reach = windup + dash          = 0.3   달려가 닿기까지
		  whole = reach + hold + recover = 0.6   한 번의 돌진 전체
		  shake = (times * 2 + 1) * each = 0.25  한 번 흔들리는 시간
	]]
	local STRIKE = { windup = 0.1, dash = 0.2, hold = 0.1, recover = 0.2, stagger = 0.05 }
	local SHAKE = { times = 2, each = 0.05 }

	local function schedule(events)
		return CombatTiming.schedule(events, STRIKE, SHAKE)
	end

	-- 0.1 + 0.2 가 정확히 0.3 이 아니다. 시각은 늘 어림으로 견준다.
	local function near(actual, expected, message)
		local ok = type(actual) == "number" and math.abs(actual - expected) < 1e-6
		t:truthy(ok, ("%s (%s, 기대 %s)"):format(message, tostring(actual), tostring(expected)))
	end

	t:describe("때리는 시간표", function()
		t:it("서로 다른 공격자는 시차만 두고 거의 동시에 간다", function()
			local s = schedule({
				{ kind = "HitPlayer", attackerId = 1, playerId = 2, damage = 2 },
				{ kind = "HitPlayer", attackerId = 2, playerId = 2, damage = 3 },
			})

			near(s.starts[1], 0, "첫 공격은 바로")
			near(s.starts[2], 0.05, "둘째는 stagger 만큼만 늦게")
		end)

		t:it("겹쳐 막기 — 한 공격자의 두 번째 돌진이 사라지지 않는다", function()
			--[[
				이 테스트가 막는 버그: 두 번째 돌진이 "그 카드는 지금 바쁘다" 는
				이유로 통째로 버려졌다. 두 번째 방어자는 맞는 장면도 없이 수치만
				나중에 조용히 깎였다.
			]]
			local s = schedule({
				{ kind = "Blocked", attackerId = 1, blockerId = 10, damageToBlocker = 2, damageToAttacker = 1 },
				{ kind = "Blocked", attackerId = 1, blockerId = 11, damageToBlocker = 1, damageToAttacker = 1 },
			})

			t:truthy(s.starts[1], "첫 돌진이 예약되어야 합니다")
			t:truthy(s.starts[2], "두 번째 돌진도 예약되어야 합니다")
		end)

		t:it("같은 공격자의 돌진은 겹치지 않고 차례로 간다", function()
			local s = schedule({
				{ kind = "Blocked", attackerId = 1, blockerId = 10, damageToBlocker = 2, damageToAttacker = 1 },
				{ kind = "Blocked", attackerId = 1, blockerId = 11, damageToBlocker = 1, damageToAttacker = 1 },
			})

			near(s.starts[1], 0, "첫 돌진")
			near(s.starts[2], 0.6, "앞 돌진이 끝난 뒤에야 — stagger(0.05) 가 아니다")
			near(s.total, 1.2, "둘째 돌진이 끝나는 시각")
		end)

		t:it("공격자가 쓰러지는 시각은 **마지막** 으로 맞는 때다", function()
			--[[
				겹쳐 막기의 반격은 방어자 수만큼 들어온다. 첫 타격 시각에 쓰러뜨리면
				아직 두 번째 방어자에게 달려가는 중인 카드가 사라진다.
			]]
			local s = schedule({
				{ kind = "Blocked", attackerId = 1, blockerId = 10, damageToBlocker = 2, damageToAttacker = 1 },
				{ kind = "Blocked", attackerId = 1, blockerId = 11, damageToBlocker = 1, damageToAttacker = 1 },
			})

			near(s.impact[1], 0.9, "둘째 돌진이 닿는 시각 (0.6 + 0.3)")
			near(s.impact[10], 0.3, "첫 방어자는 첫 돌진에 맞는다")
			near(s.impact[11], 0.9, "둘째 방어자는 둘째 돌진에 맞는다")
		end)

		t:it("맞고 흔들리는 카드는 흔들림이 끝나야 제 차례로 달려간다", function()
			--[[
				1 이 10 을 치고, 그 10 이 이번에는 공격자로 나선다. 흔들리는 중에
				달려가면 돌진 트윈과 흔들림 트윈이 같은 Position 을 두고 싸운다.

				10 이 맞는 시각 0.3 + 흔들림 0.25 = 0.55 부터 갈 수 있다.
			]]
			local s = schedule({
				{ kind = "HitCreature", attackerId = 1, targetId = 10, damageToTarget = 2 },
				{ kind = "HitPlayer", attackerId = 10, playerId = 1, damage = 3 },
			})

			near(s.starts[1], 0, "먼저 1 이 간다")
			near(s.starts[2], 0.55, "10 은 흔들림이 끝나고서야 — stagger(0.05) 가 아니다")
		end)

		t:it("플레이어 라이프 숫자는 그 플레이어가 마지막으로 맞을 때 뜬다", function()
			local s = schedule({
				{ kind = "HitPlayer", attackerId = 1, playerId = 2, damage = 2 },
				{ kind = "HitPlayer", attackerId = 2, playerId = 2, damage = 3 },
			})

			near(s.player[2], 0.35, "둘째 공격이 닿는 시각 (0.05 + 0.3)")
			t:eq(s.player[1], nil, "맞지 않은 쪽은 없다")
		end)

		t:it("움직일 것이 없는 이벤트는 자리를 차지하지 않는다", function()
			--[[
				AttackFizzled 는 공격자가 이미 필드를 떠난 경우다. 이것이 순번을
				차지하면 뒤따르는 진짜 돌진이 이유 없이 밀린다.
			]]
			local s = schedule({
				{ kind = "AttackFizzled", attackerId = 9 },
				{ kind = "HitPlayer", attackerId = 1, playerId = 2, damage = 2 },
			})

			t:eq(s.starts[1], nil, "재생할 것이 없다")
			near(s.starts[2], 0, "뒤따르는 돌진이 밀리지 않는다")
		end)

		t:it("전투가 없으면 시간표도 비어 있다", function()
			local s = schedule({})
			t:eq(s.total, 0, "쓸어담을 것이 없다")
		end)
	end)
end
