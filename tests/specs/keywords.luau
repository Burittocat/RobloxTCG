--[[ 태그(키워드) 규칙: 신속 · 비행 · 도발 · 원거리 ]]

return function(t, ctx)
	local Rules, Fixture = ctx.Rules, ctx.Fixture
	local Zone = Rules.Enums.Zone
	local Field = Zone.Field

	-- 공격준비 페이즈까지 진행시킨 판을 만든다.
	local function attackPrep(seedOpts)
		local state = Fixture.match(Rules, seedOpts)
		Rules.endPhase(state, 1)
		return state
	end

	--======================================================================
	t:describe("신속", function()
		t:it("신속 생물은 소환한 턴에 공격할 수 있다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			local raider = Fixture.giveHand(Rules, state, 1, "CRE_RAIDER")

			t:allowed(Fixture.playAndSettle(Rules, state, 1, raider.id))
			t:eq(raider.zone, Field)
			t:eq(raider.summonedOnTurn, state.turn, "이번 턴에 소환됨")

			Rules.endPhase(state, 1) -- → AttackPrep
			t:allowed(Rules.declareAttacker(state, 1, raider.id))
		end)

		t:it("신속이 없으면 소환한 턴에 공격할 수 없다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			local guard = Fixture.giveHand(Rules, state, 1, "CRE_GUARD")

			t:allowed(Fixture.playAndSettle(Rules, state, 1, guard.id))
			Rules.endPhase(state, 1)

			local ok, reason = Rules.declareAttacker(state, 1, guard.id)
			t:denied(ok, reason, "신속")
		end)

		t:it("수비준비 페이즈 소환: 일반 생물은 탭, 신속은 언탭", function()
			local state = Fixture.match(Rules)
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			Fixture.giveCost(Rules, state, 2, 6)
			local normal = Fixture.giveHand(Rules, state, 2, "CRE_GUARD")
			local hasty = Fixture.giveHand(Rules, state, 2, "CRE_RAIDER")

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, attacker.id)
			Rules.endPhase(state, 1) -- → DefensePrep

			t:allowed(Fixture.playAndSettle(Rules, state, 2, normal.id))
			t:truthy(normal.tapped, "일반 생물은 탭된 채 등장해야 한다")

			t:allowed(Fixture.playAndSettle(Rules, state, 2, hasty.id))
			t:falsy(hasty.tapped, "신속 생물은 언탭으로 등장해야 한다")

			-- 탭된 생물은 방어할 수 없고, 신속 생물은 바로 방어할 수 있다.
			local ok, reason = Rules.declareBlocker(state, 2, normal.id, attacker.id)
			t:denied(ok, reason, "탭")
			t:allowed(Rules.declareBlocker(state, 2, hasty.id, attacker.id))
		end)
	end)

	--======================================================================
	t:describe("비행", function()
		t:it("지상 생물은 비행 생물을 공격할 수 없다", function()
			local state = attackPrep()
			local ground = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			local hawk = Fixture.spawn(Rules, state, 2, "CRE_HAWK", Field)

			local ok, reason = Rules.declareAttacker(state, 1, ground.id, { kind = "Creature", id = hawk.id })
			t:denied(ok, reason, "비행")
		end)

		t:it("비행 생물은 비행 생물을 공격할 수 있다", function()
			local state = attackPrep()
			local wyvern = Fixture.spawn(Rules, state, 1, "CRE_WYVERN", Field)
			local hawk = Fixture.spawn(Rules, state, 2, "CRE_HAWK", Field)

			t:allowed(Rules.declareAttacker(state, 1, wyvern.id, { kind = "Creature", id = hawk.id }))
		end)

		t:it("원거리 생물은 비행 생물을 공격할 수 있다", function()
			local state = attackPrep()
			local archer = Fixture.spawn(Rules, state, 1, "CRE_ARCHER", Field)
			local hawk = Fixture.spawn(Rules, state, 2, "CRE_HAWK", Field)

			t:allowed(Rules.declareAttacker(state, 1, archer.id, { kind = "Creature", id = hawk.id }))
		end)

		t:it("지상 생물은 비행 공격자를 방어할 수 없다", function()
			local state = attackPrep()
			local hawk = Fixture.spawn(Rules, state, 1, "CRE_HAWK", Field)
			local ground = Fixture.spawn(Rules, state, 2, "CRE_GUARD", Field)

			Rules.declareAttacker(state, 1, hawk.id)
			Rules.endPhase(state, 1)

			local ok, reason = Rules.declareBlocker(state, 2, ground.id, hawk.id)
			t:denied(ok, reason, "비행")
		end)

		t:it("원거리 생물은 비행 공격자를 방어할 수 있다", function()
			local state = attackPrep()
			local hawk = Fixture.spawn(Rules, state, 1, "CRE_HAWK", Field)
			local archer = Fixture.spawn(Rules, state, 2, "CRE_ARCHER", Field)

			Rules.declareAttacker(state, 1, hawk.id)
			Rules.endPhase(state, 1)

			t:allowed(Rules.declareBlocker(state, 2, archer.id, hawk.id))
		end)

		t:it("비행 생물은 비행 공격자를 방어할 수 있다 (Config)", function()
			local state = attackPrep()
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_WYVERN", Field)
			local blocker = Fixture.spawn(Rules, state, 2, "CRE_HAWK", Field)

			Rules.declareAttacker(state, 1, attacker.id)
			Rules.endPhase(state, 1)

			local ok, reason = Rules.declareBlocker(state, 2, blocker.id, attacker.id)
			if Rules.Config.flyingCanBlockFlying then
				t:allowed(ok, reason)
			else
				t:denied(ok, reason, "비행")
			end
		end)
	end)

	--======================================================================
	t:describe("도발", function()
		t:it("도발이 있으면 플레이어를 직접 공격할 수 없다", function()
			local state = attackPrep()
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			Fixture.spawn(Rules, state, 2, "CRE_BULWARK", Field)

			local ok, reason = Rules.declareAttacker(state, 1, guard.id, { kind = "Player", id = 2 })
			t:denied(ok, reason, "도발")
		end)

		t:it("도발 생물 자체는 공격할 수 있다", function()
			local state = attackPrep()
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			local bulwark = Fixture.spawn(Rules, state, 2, "CRE_BULWARK", Field)

			t:allowed(Rules.declareAttacker(state, 1, guard.id, { kind = "Creature", id = bulwark.id }))
		end)

		t:it("원거리 생물은 도발을 무시하고 플레이어를 친다", function()
			local state = attackPrep()
			local archer = Fixture.spawn(Rules, state, 1, "CRE_ARCHER", Field)
			Fixture.spawn(Rules, state, 2, "CRE_BULWARK", Field)

			t:allowed(Rules.declareAttacker(state, 1, archer.id, { kind = "Player", id = 2 }))
		end)

		t:it("비행 생물은 도발을 무시하지 못한다", function()
			local state = attackPrep()
			local hawk = Fixture.spawn(Rules, state, 1, "CRE_HAWK", Field)
			Fixture.spawn(Rules, state, 2, "CRE_BULWARK", Field)

			local ok, reason = Rules.declareAttacker(state, 1, hawk.id, { kind = "Player", id = 2 })
			t:denied(ok, reason, "도발")
		end)

		t:it("도발 생물이 사라지면 다시 직접 공격할 수 있다", function()
			local state = attackPrep()
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			local bulwark = Fixture.spawn(Rules, state, 2, "CRE_BULWARK", Field)

			t:denied(Rules.declareAttacker(state, 1, guard.id, { kind = "Player", id = 2 }))

			Rules.GameState.moveCard(state, bulwark, Zone.Graveyard)
			t:allowed(Rules.declareAttacker(state, 1, guard.id, { kind = "Player", id = 2 }))
		end)
	end)

	--======================================================================
	t:describe("원거리", function()
		t:it("플레이어 직접 공격은 공격력의 절반만 들어간다", function()
			local state = Fixture.match(Rules)
			local archer = Fixture.spawn(Rules, state, 1, "CRE_ARCHER", Field) -- 4/2
			t:eq(Rules.Keywords.power(archer), 4)
			t:eq(Rules.Combat.directDamageToPlayer(archer), 2, "4 의 절반")
		end)

		t:it("원거리가 아니면 절반 규칙이 적용되지 않는다", function()
			local state = Fixture.match(Rules)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field) -- 2/3
			t:eq(Rules.Combat.directDamageToPlayer(guard), 2, "감산 없음")
		end)

		t:it("홀수 공격력은 Config 반올림 규칙을 따른다", function()
			local state = Fixture.match(Rules)
			local archer = Fixture.spawn(Rules, state, 1, "CRE_ARCHER", Field)
			archer.powerMod = 1 -- 5

			local expected = Rules.Config.rangedDirectDamageRounding == "ceil" and 3 or 2
			t:eq(Rules.Combat.directDamageToPlayer(archer), expected)
		end)

		t:it("생물 전투에서는 절반 규칙이 없다", function()
			local state = Fixture.match(Rules)
			local archer = Fixture.spawn(Rules, state, 1, "CRE_ARCHER", Field) -- 4/2
			local target = Fixture.spawn(Rules, state, 2, "CRE_GUARD", Field) -- 2/3

			Rules.endPhase(state, 1)
			t:allowed(Rules.declareAttacker(state, 1, archer.id, { kind = "Creature", id = target.id }))
			Rules.endPhase(state, 1) -- → DefensePrep
			Rules.endPhase(state, 2) -- → Combat → 다음 턴

			t:eq(target.zone, Zone.Graveyard, "4 피해를 그대로 받아 죽어야 한다")
		end)
	end)
end
