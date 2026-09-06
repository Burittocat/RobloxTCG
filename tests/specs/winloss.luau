--[[ 승패 판정 ]]

return function(t, ctx)
	local Rules, Fixture = ctx.Rules, ctx.Fixture
	local Field = Rules.Enums.Zone.Field

	t:describe("승패", function()
		t:it("라이프가 0 이하가 되면 상대가 승리한다", function()
			local state = Fixture.match(Rules)
			state.players[2].life = 2

			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field) -- 2 공격력
			Rules.endPhase(state, 1)
			Rules.declareAttacker(state, 1, guard.id)
			Rules.endPhase(state, 1)
			Rules.endPhase(state, 2)

			t:truthy(state.finished, "게임이 끝나야 한다")
			t:eq(state.winnerId, 1)
			t:eq(state.lossReason, Rules.Enums.LossReason.LifeDepleted)
		end)

		t:it("마법 피해로도 이길 수 있다", function()
			local state = Fixture.match(Rules)
			state.players[2].life = 3
			Fixture.giveCost(Rules, state, 1, 3)
			local firebolt = Fixture.giveHand(Rules, state, 1, "SPL_FIREBOLT")

			Fixture.playAndSettle(Rules, state, 1, firebolt.id, { { kind = "Player", id = 2 } })

			t:truthy(state.finished)
			t:eq(state.winnerId, 1)
		end)

		t:it("게임이 끝나면 더 이상 행동할 수 없다", function()
			local state = Fixture.match(Rules)
			Rules.concede(state, 1)

			t:truthy(state.finished)
			t:eq(state.winnerId, 2)

			local card = Fixture.giveHand(Rules, state, 2, "COST_BASIC")
			local ok, reason = Rules.playCard(state, 2, card.id)
			t:denied(ok, reason, "끝난")
		end)

		t:it("빈 덱에서 드로우하면 패배한다", function()
			local state = Fixture.match(Rules)

			-- P2 의 덱을 비우고 P2 턴을 시작시킨다.
			state.players[2].deck = {}

			Rules.endPhase(state, 1)
			Rules.endPhase(state, 1) -- → P2 턴 시작 → 드로우 시도

			t:truthy(state.finished, "덱 아웃으로 끝나야 한다")
			t:eq(state.winnerId, 1)
			t:eq(state.lossReason, Rules.Enums.LossReason.DeckOut)
		end)
	end)

	t:describe("직렬화", function()
		t:it("직렬화 후 복원해도 상태가 유지된다", function()
			local state = Fixture.match(Rules, { seed = 4242 })
			Fixture.giveCost(Rules, state, 1, 2)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)

			local saved = Rules.GameState.serialize(state)
			local restored = Rules.GameState.deserialize(saved)

			t:eq(restored.turn, state.turn)
			t:eq(restored.phase, state.phase)
			t:eq(restored.players[1].life, state.players[1].life)
			t:eq(restored.cards[guard.id].defId, "CRE_GUARD")
			t:eq(restored.rng.state, state.rng.state, "RNG 상태가 보존되어야 한다")
		end)

		t:it("복원한 RNG 는 같은 수열을 이어간다", function()
			local original = Rules.RNG.new(999)
			for _ = 1, 5 do
				original:nextInteger(100)
			end

			local restored = Rules.RNG.restore(original:snapshot())
			for index = 1, 10 do
				t:eq(restored:nextInteger(100), original:nextInteger(100), index .. "번째 난수")
			end
		end)
	end)

	t:describe("클라이언트 뷰", function()
		t:it("상대 손패는 장수만 보인다", function()
			local state = Fixture.match(Rules)
			local view = Rules.viewFor(state, 1)

			t:eq(view.players[2].handCount, 7, "장수는 보여야 한다")
			t:falsy(view.players[2].hand, "상대 손패 내용은 감춰야 한다")
			t:truthy(view.players[1].hand, "자기 손패는 보여야 한다")
		end)

		t:it("상대 손패의 카드 정보가 새어나가지 않는다", function()
			local state = Fixture.match(Rules)
			local secret = Fixture.giveHand(Rules, state, 2, "CRE_BRUTE")
			local view = Rules.viewFor(state, 1)

			t:falsy(view.cards[secret.id], "상대 손패 카드가 뷰에 포함되면 안 된다")
		end)

		t:it("필드 카드는 양쪽 모두에게 보인다", function()
			local state = Fixture.match(Rules)
			local guard = Fixture.spawn(Rules, state, 2, "CRE_GUARD", Field)
			local view = Rules.viewFor(state, 1)

			t:truthy(view.cards[guard.id], "필드 카드는 공개")
			t:eq(view.cards[guard.id].defId, "CRE_GUARD")
		end)
	end)
end
