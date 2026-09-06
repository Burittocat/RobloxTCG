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
