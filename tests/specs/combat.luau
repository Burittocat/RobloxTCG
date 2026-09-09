--[[ 공수 페이즈 데미지 해결 ]]

return function(t, ctx)
	local Rules, Fixture = ctx.Rules, ctx.Fixture
	local Zone = Rules.Enums.Zone
	local Field = Zone.Field

	t:describe("전투 해결", function()
		t:it("방어당하지 않은 공격은 플레이어에게 그대로 들어간다", function()
			local state = Fixture.match(Rules)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field) -- 2/3

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, guard.id)
			Rules.endPhase(state, 1) -- → DefensePrep
			Rules.endPhase(state, 2) -- → Combat

			t:eq(state.players[2].life, 28, "30 - 2")
		end)

		t:it("원거리의 직접 공격은 절반만 들어간다", function()
			local state = Fixture.match(Rules)
			local archer = Fixture.spawn(Rules, state, 1, "CRE_ARCHER", Field) -- 4/2

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, archer.id)
			Rules.endPhase(state, 1)
			Rules.endPhase(state, 2)

			t:eq(state.players[2].life, 28, "30 - floor(4/2)")
		end)

		t:it("방어당하면 서로 피해를 주고받는다", function()
			local state = Fixture.match(Rules)
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field) -- 2/3
			local blocker = Fixture.spawn(Rules, state, 2, "CRE_SCOUT", Field) -- 1/2

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, attacker.id)
			Rules.endPhase(state, 1)
			t:allowed(Rules.declareBlocker(state, 2, blocker.id, attacker.id))
			Rules.endPhase(state, 2)

			t:eq(state.players[2].life, 30, "방어했으므로 플레이어는 무피해")
			t:eq(blocker.zone, Zone.Graveyard, "2 피해로 1/2 방어자는 죽는다")
			t:eq(attacker.zone, Field, "1 피해로 2/3 공격자는 산다")
		end)

		--[[
			겹쳐 막기 (Config.maxBlockersPerAttacker = 2)

			방어측이 여러 마리로 한 공격자를 막을 수 있다. 공격자는 방어자들의 공격력을
			**전부** 맞고, 자기 공격력은 나눠서 준다 — 죽일 수 있는 것부터.
		]]
		t:it("두 마리가 함께 막으면 공격자가 둘의 공격력을 다 맞는다", function()
			local state = Fixture.match(Rules)
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_LANCER", Field) -- 4/4
			local first = Fixture.spawn(Rules, state, 2, "CRE_SQUIRE", Field) -- 2/1
			local second = Fixture.spawn(Rules, state, 2, "CRE_GUARD", Field) -- 2/3

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, attacker.id)
			Rules.endPhase(state, 1)
			t:allowed(Rules.declareBlocker(state, 2, first.id, attacker.id))
			t:allowed(Rules.declareBlocker(state, 2, second.id, attacker.id))
			Rules.endPhase(state, 2)

			t:eq(attacker.zone, Zone.Graveyard, "2 + 2 = 4 를 맞아 4/4 공격자가 죽는다")
			t:eq(state.players[2].life, 30, "막았으므로 플레이어는 무피해")
		end)

		t:it("공격력은 죽일 수 있는 방어자부터 배분된다", function()
			local state = Fixture.match(Rules)
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_ARCHER", Field) -- 4/2

			--[[
				**큰 놈을 먼저 만든다.** 작은 놈이 먼저면 "번호순 배분" 이라는 잘못된 규칙도
				같은 결과를 내서, 테스트가 아무것도 구별하지 못한다.
			]]
			local big = Fixture.spawn(Rules, state, 2, "CRE_BULWARK", Field) -- 1/6
			local small = Fixture.spawn(Rules, state, 2, "CRE_SQUIRE", Field) -- 2/1

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, attacker.id)
			Rules.endPhase(state, 1)
			t:allowed(Rules.declareBlocker(state, 2, big.id, attacker.id))
			t:allowed(Rules.declareBlocker(state, 2, small.id, attacker.id))
			Rules.endPhase(state, 2)

			--[[
				4 공격력을 1 생명력 종자에게 1, 남은 3 을 6 생명력 방벽에게 준다.
				**배정한 순서(방벽 먼저)가 아니라 죽일 수 있는 것부터** 간다 —
				순서대로 줬다면 방벽이 4 를 다 받고 종자는 멀쩡했을 것이다.
				(맞은 피해는 턴이 끝나면서 지워지므로 생사로 확인한다)
			]]
			t:eq(small.zone, Zone.Graveyard, "작은 방어자부터 죽는다")
			t:eq(big.zone, Field, "3 피해로는 1/6 이 죽지 않는다")
			t:eq(attacker.zone, Zone.Graveyard, "2 + 1 = 3 을 맞아 4/2 공격자가 죽는다")
		end)

		t:it("셋 이상도 함께 막을 수 있다", function()
			local state = Fixture.match(Rules)
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_TITAN", Field) -- 7/7
			-- 도발 생물은 넣지 않는다. 있으면 플레이어 직접 공격 자체가 막혀서
			-- 이 테스트가 재려는 것(겹쳐 막기)에 닿지도 못한다.
			local blockers = {
				Fixture.spawn(Rules, state, 2, "CRE_SCOUT", Field), -- 1/2
				Fixture.spawn(Rules, state, 2, "CRE_SQUIRE", Field), -- 2/1
				Fixture.spawn(Rules, state, 2, "CRE_GUARD", Field), -- 2/3
				Fixture.spawn(Rules, state, 2, "CRE_SCRIBE", Field), -- 1/2
			}

			Rules.endPhase(state, 1)
			t:allowed(Rules.declareAttacker(state, 1, attacker.id))
			Rules.endPhase(state, 1)

			-- 인원 제한이 없다. 막을 생물이 있으면 다 던질 수 있다.
			for _, blocker in blockers do
				t:allowed(Rules.declareBlocker(state, 2, blocker.id, attacker.id))
			end

			Rules.endPhase(state, 2)

			-- 1 + 2 + 2 + 1 = 6 은 7/7 을 못 잡는다. 그래도 라이프는 지켰다.
			t:eq(state.players[2].life, 30, "막았으므로 플레이어는 무피해")
			t:eq(attacker.zone, Field, "6 피해로는 7/7 이 죽지 않는다")
		end)

		t:it("치사 피해를 서로 주면 동시에 죽는다", function()
			local state = Fixture.match(Rules)
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_ARCHER", Field) -- 4/2
			local blocker = Fixture.spawn(Rules, state, 2, "CRE_GUARD", Field) -- 2/3

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, attacker.id)
			Rules.endPhase(state, 1)
			Rules.declareBlocker(state, 2, blocker.id, attacker.id)
			Rules.endPhase(state, 2)

			t:eq(attacker.zone, Zone.Graveyard, "4/2 는 2 피해로 죽는다")
			t:eq(blocker.zone, Zone.Graveyard, "2/3 은 4 피해로 죽는다")
		end)

		t:it("공격한 생물은 탭된다", function()
			local state = Fixture.match(Rules)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, guard.id)
			Rules.endPhase(state, 1)
			Rules.endPhase(state, 2)

			t:eq(guard.zone, Field)
			t:truthy(guard.tapped, "공격 후 탭되어야 한다")
		end)

		t:it("탭된 생물은 공격할 수 없다", function()
			local state = Fixture.match(Rules)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			guard.tapped = true

			Rules.endPhase(state, 1)
			local ok, reason = Rules.declareAttacker(state, 1, guard.id)
			t:denied(ok, reason, "탭")
		end)

		t:it("같은 생물로 두 번 공격 선언할 수 없다", function()
			local state = Fixture.match(Rules)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)

			Rules.endPhase(state, 1)
			t:allowed(Rules.declareAttacker(state, 1, guard.id))
			local ok, reason = Rules.declareAttacker(state, 1, guard.id)
			t:denied(ok, reason, "이미")
		end)

		t:it("같은 생물로 두 공격자를 막을 수 없다", function()
			local state = Fixture.match(Rules)
			local a1 = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			local a2 = Fixture.spawn(Rules, state, 1, "CRE_SCOUT", Field)
			local blocker = Fixture.spawn(Rules, state, 2, "CRE_BULWARK", Field)

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, a1.id, { kind = "Creature", id = blocker.id })
			Rules.declareAttacker(state, 1, a2.id, { kind = "Creature", id = blocker.id })
			Rules.endPhase(state, 1)

			t:allowed(Rules.declareBlocker(state, 2, blocker.id, a1.id))
			local ok, reason = Rules.declareBlocker(state, 2, blocker.id, a2.id)
			t:denied(ok, reason, "이미")
		end)

		t:it("전투 후 생물이 받은 피해는 턴 종료에 사라진다", function()
			local state = Fixture.match(Rules)
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_SCOUT", Field) -- 1/2
			local blocker = Fixture.spawn(Rules, state, 2, "CRE_BULWARK", Field) -- 1/6

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, attacker.id, { kind = "Creature", id = blocker.id })
			Rules.endPhase(state, 1)
			Rules.endPhase(state, 2) -- Combat → EndTurn → P2 턴

			t:eq(blocker.zone, Field, "1 피해로는 죽지 않는다")
			t:eq(blocker.damage, 0, "턴이 끝나면 피해가 회복된다")
		end)
	end)
end
