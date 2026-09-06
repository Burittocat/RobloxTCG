--[[ 페이즈 상태머신: 순서, 권한, 자동 스킵 ]]

return function(t, ctx)
	local Rules, Fixture = ctx.Rules, ctx.Fixture
	local Phase = Rules.Enums.Phase

	t:describe("페이즈", function()
		t:it("메인 → 공격준비 순으로 넘어간다", function()
			local state = Fixture.match(Rules)
			t:eq(state.phase, Phase.Main)

			t:allowed(Rules.endPhase(state, 1))
			t:eq(state.phase, Phase.AttackPrep)
		end)

		t:it("공격자가 없으면 수비준비와 공수 페이즈를 건너뛴다", function()
			local state = Fixture.match(Rules)

			Rules.endPhase(state, 1) -- Main → AttackPrep
			Rules.endPhase(state, 1) -- 공격자 없음 → 다음 턴으로

			t:eq(state.turn, 2, "턴이 넘어가야 한다")
			t:eq(state.activePlayerId, 2)
			t:eq(state.phase, Phase.Main)
		end)

		t:it("공격자가 있으면 수비준비 페이즈로 간다", function()
			local state = Fixture.match(Rules)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Rules.Enums.Zone.Field)

			Rules.endPhase(state, 1) -- → AttackPrep
			t:allowed(Rules.declareAttacker(state, 1, guard.id))
			Rules.endPhase(state, 1) -- → DefensePrep

			t:eq(state.phase, Phase.DefensePrep)
			t:eq(state.priorityPlayerId, 2, "우선권은 수비측에")
		end)

		t:it("상대는 내 메인 페이즈를 끝낼 수 없다", function()
			local state = Fixture.match(Rules)
			local ok, reason = Rules.endPhase(state, 2)
			t:denied(ok, reason, "권한")
		end)

		t:it("수비준비 페이즈는 수비측만 끝낼 수 있다", function()
			local state = Fixture.match(Rules)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Rules.Enums.Zone.Field)

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, guard.id)
			Rules.endPhase(state, 1)
			t:eq(state.phase, Phase.DefensePrep)

			local ok, reason = Rules.endPhase(state, 1) -- 공격측이 끝내려 시도
			t:denied(ok, reason, "권한")
			t:allowed(Rules.endPhase(state, 2))
		end)

		t:it("한 바퀴 돌면 선공에게 턴이 돌아온다", function()
			local state = Fixture.match(Rules)

			Rules.endPhase(state, 1)
			Rules.endPhase(state, 1)
			t:eq(state.activePlayerId, 2)

			Rules.endPhase(state, 2)
			Rules.endPhase(state, 2)
			t:eq(state.activePlayerId, 1)
			t:eq(state.turn, 3)
		end)

		t:it("후공은 첫 턴에 드로우한다", function()
			local state = Fixture.match(Rules, { deckSize = 30, startingPlayerId = 1 })
			local before = #state.players[2].hand

			Rules.endPhase(state, 1)
			Rules.endPhase(state, 1) -- → P2 턴

			t:eq(#state.players[2].hand, before + 1, "후공은 1턴에 드로우해야 한다")
		end)
	end)

	t:describe("페이즈 권한", function()
		t:it("메인 페이즈: 턴 플레이어는 전부, 상대는 즉시시전만", function()
			local state = Fixture.match(Rules)

			local active = Rules.Phases.permissions(state, 1)
			t:truthy(active.playCost)
			t:truthy(active.summonCreature)
			t:truthy(active.castNormalSpell)
			t:truthy(active.castInstantSpell)

			local waiting = Rules.Phases.permissions(state, 2)
			t:falsy(waiting.playCost)
			t:falsy(waiting.summonCreature)
			t:falsy(waiting.castNormalSpell)
			t:truthy(waiting.castInstantSpell, "상대 메인에 즉시시전은 가능해야 한다")
		end)

		t:it("수비준비 페이즈: 수비측만 소환/마법/방어배정", function()
			local state = Fixture.match(Rules)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Rules.Enums.Zone.Field)

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, guard.id)
			Rules.endPhase(state, 1)

			local defender = Rules.Phases.permissions(state, 2)
			t:truthy(defender.declareBlockers)
			t:truthy(defender.summonCreature)
			t:truthy(defender.summonEntersTapped, "수비턴 소환은 탭 상태로 등장")
			t:truthy(defender.castInstantSpell)
			t:truthy(defender.castNormalSpell)
			t:falsy(defender.playCost, "수비턴에는 코스트 카드를 낼 수 없다")

			local attacker = Rules.Phases.permissions(state, 1)
			t:falsy(attacker.castInstantSpell, "기획서상 공격측은 상대 수비준비에 발동 창이 없다")
			t:falsy(attacker.declareBlockers)
		end)
	end)
end
