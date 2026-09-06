--[[ 즉시시전 · 스택 · 마법 효과 ]]

return function(t, ctx)
	local Rules, Fixture = ctx.Rules, ctx.Fixture
	local Zone = Rules.Enums.Zone
	local Field = Zone.Field

	t:describe("즉시시전 타이밍", function()
		t:it("상대 메인 페이즈에 즉시시전을 쓸 수 있다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 2, 3)
			local shock = Fixture.giveHand(Rules, state, 2, "SPL_SHOCK")

			t:allowed(Rules.playCard(state, 2, shock.id, { { kind = "Player", id = 1 } }))
		end)

		t:it("상대 메인 페이즈에 일반 마법은 쓸 수 없다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 2, 3)
			local firebolt = Fixture.giveHand(Rules, state, 2, "SPL_FIREBOLT")

			local ok, reason = Rules.playCard(state, 2, firebolt.id, { { kind = "Player", id = 1 } })
			t:denied(ok, reason, "일반 마법")
		end)

		t:it("수비준비 페이즈에 수비측은 일반 마법도 쓸 수 있다", function()
			local state = Fixture.match(Rules)
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			Fixture.giveCost(Rules, state, 2, 3)
			local firebolt = Fixture.giveHand(Rules, state, 2, "SPL_FIREBOLT")

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, attacker.id)
			Rules.endPhase(state, 1) -- → DefensePrep

			t:allowed(Rules.playCard(state, 2, firebolt.id, { { kind = "Creature", id = attacker.id } }))
		end)

		t:it("수비준비 금지 카드는 수비준비에 거부된다", function()
			local state = Fixture.match(Rules)
			local attacker = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			Fixture.giveCost(Rules, state, 2, 5)
			local execute = Fixture.giveHand(Rules, state, 2, "SPL_EXECUTE") -- noDefensePhase

			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, attacker.id)
			Rules.endPhase(state, 1)

			local ok, reason = Rules.playCard(state, 2, execute.id, { { kind = "Creature", id = attacker.id } })
			t:denied(ok, reason, "수비준비")
		end)
	end)

	t:describe("스택", function()
		t:it("마법은 즉시 해결되지 않고 스택에 올라간다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			local firebolt = Fixture.giveHand(Rules, state, 1, "SPL_FIREBOLT")

			t:allowed(Rules.playCard(state, 1, firebolt.id, { { kind = "Player", id = 2 } }))
			t:eq(#state.stack, 1, "스택에 올라가야 한다")
			t:eq(state.players[2].life, 30, "아직 피해가 들어가면 안 된다")
			t:eq(Rules.Stack.responderFor(state), 2, "대응권은 상대에게")

			t:allowed(Rules.pass(state, 2))
			t:eq(#state.stack, 0)
			t:eq(state.players[2].life, 27, "30 - 3")
		end)

		t:it("대응권이 없는 쪽은 패스할 수 없다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			local firebolt = Fixture.giveHand(Rules, state, 1, "SPL_FIREBOLT")

			Rules.playCard(state, 1, firebolt.id, { { kind = "Player", id = 2 } })
			local ok, reason = Rules.pass(state, 1)
			t:denied(ok, reason, "대응권")
		end)

		t:it("즉시시전으로 상대 마법을 무효화한다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			Fixture.giveCost(Rules, state, 2, 3)
			local firebolt = Fixture.giveHand(Rules, state, 1, "SPL_FIREBOLT")
			local negate = Fixture.giveHand(Rules, state, 2, "SPL_NEGATE")

			Rules.playCard(state, 1, firebolt.id, { { kind = "Player", id = 2 } })
			local firebolItem = Rules.Stack.top(state)

			t:allowed(Rules.playCard(state, 2, negate.id, { { kind = "StackItem", id = firebolItem.id } }))
			t:eq(#state.stack, 2)

			t:allowed(Rules.pass(state, 1)) -- 주문 파쇄 해결
			t:allowed(Rules.pass(state, 2)) -- 무효화된 화염 화살 해결

			t:eq(state.players[2].life, 30, "무효화되어 피해가 없어야 한다")
			t:eq(firebolt.zone, Zone.Graveyard, "무효화된 마법은 더미로")
			t:eq(negate.zone, Zone.Graveyard)
		end)

		t:it("즉시시전으로 소환 중인 생물을 덱으로 되돌린다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 5)
			Fixture.giveCost(Rules, state, 2, 3)
			local brute = Fixture.giveHand(Rules, state, 1, "CRE_BRUTE")
			local recall = Fixture.giveHand(Rules, state, 2, "SPL_RECALL")

			t:allowed(Rules.playCard(state, 1, brute.id))
			local summonItem = Rules.Stack.top(state)
			t:eq(summonItem.kind, "Summon")

			t:allowed(Rules.playCard(state, 2, recall.id, { { kind = "StackItem", id = summonItem.id } }))
			t:allowed(Rules.pass(state, 1)) -- 귀환의 소용돌이 해결
			t:allowed(Rules.pass(state, 2)) -- 무효화된 소환 해결

			t:eq(brute.zone, Zone.Deck, "덱으로 돌아가야 한다")
			t:eq(state.players[1].deck[1], brute.id, "덱 맨 위에 있어야 한다")
			t:falsy(table.find(state.players[1].field, brute.id), "필드에 남아 있으면 안 된다")
		end)

		t:it("무효화당해도 지불한 코스트는 돌아오지 않는다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			Fixture.giveCost(Rules, state, 2, 3)
			local firebolt = Fixture.giveHand(Rules, state, 1, "SPL_FIREBOLT")
			local negate = Fixture.giveHand(Rules, state, 2, "SPL_NEGATE")

			Rules.playCard(state, 1, firebolt.id, { { kind = "Player", id = 2 } })
			t:eq(Rules.GameState.availableCost(state, 1), 1, "3 - 2")

			Rules.playCard(state, 2, negate.id, { { kind = "StackItem", id = Rules.Stack.top(state).id } })
			Rules.pass(state, 1)
			Rules.pass(state, 2)

			t:eq(Rules.GameState.availableCost(state, 1), 1, "코스트는 환불되지 않는다")
		end)

		t:it("스택이 남아 있으면 페이즈를 넘길 수 없다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			local firebolt = Fixture.giveHand(Rules, state, 1, "SPL_FIREBOLT")

			Rules.playCard(state, 1, firebolt.id, { { kind = "Player", id = 2 } })
			local ok, reason = Rules.endPhase(state, 1)
			t:denied(ok, reason, "스택")
		end)
	end)

	t:describe("마법 효과", function()
		t:it("피해 마법으로 생물을 죽인다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			local hawk = Fixture.spawn(Rules, state, 2, "CRE_HAWK", Field) -- 2/1
			local firebolt = Fixture.giveHand(Rules, state, 1, "SPL_FIREBOLT")

			t:allowed(Fixture.playAndSettle(Rules, state, 1, firebolt.id, { { kind = "Creature", id = hawk.id } }))
			t:eq(hawk.zone, Zone.Graveyard)
		end)

		t:it("버프와 키워드 부여가 함께 적용된다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field, true) -- 소환 멀미 상태
			local warcry = Fixture.giveHand(Rules, state, 1, "SPL_WARCRY")

			local target = { kind = "Creature", id = guard.id }
			t:allowed(Fixture.playAndSettle(Rules, state, 1, warcry.id, { target, target }))

			t:eq(Rules.Keywords.power(guard), 4, "2 + 2")
			t:truthy(Rules.Keywords.isHaste(guard), "신속을 얻어야 한다")

			Rules.endPhase(state, 1)
			t:allowed(Rules.declareAttacker(state, 1, guard.id), "신속을 얻었으니 공격 가능")
		end)

		t:it("적 생물만 지정하는 마법은 아군을 대상으로 못 잡는다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 5)
			local ally = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			local execute = Fixture.giveHand(Rules, state, 1, "SPL_EXECUTE")

			local ok, reason = Rules.playCard(state, 1, execute.id, { { kind = "Creature", id = ally.id } })
			t:denied(ok, reason, "적 생물")
		end)

		t:it("드로우 마법이 카드를 뽑는다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 3)
			local rally = Fixture.giveHand(Rules, state, 1, "SPL_RALLY")
			local before = #state.players[1].hand

			t:allowed(Fixture.playAndSettle(Rules, state, 1, rally.id))
			-- 자기 자신은 손에서 빠져나갔으므로 before - 1 + 2
			t:eq(#state.players[1].hand, before + 1)
		end)
	end)
end
