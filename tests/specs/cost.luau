--[[ 코스트 카드: 턴당 1장, 언탭 등장, 지불 ]]

return function(t, ctx)
	local Rules, Fixture = ctx.Rules, ctx.Fixture
	local Zone = Rules.Enums.Zone

	t:describe("코스트", function()
		t:it("메인 페이즈에 코스트 카드를 낼 수 있다", function()
			local state = Fixture.match(Rules)
			local card = Fixture.giveHand(Rules, state, 1, "COST_BASIC")

			t:allowed(Rules.playCard(state, 1, card.id))
			t:eq(card.zone, Zone.Field, "필드로 갔는가")
			t:eq(state.players[1].costPlayedThisTurn, 1)
		end)

		t:it("코스트 카드는 언탭 상태로 등장해 그 턴 바로 쓸 수 있다", function()
			local state = Fixture.match(Rules)
			local card = Fixture.giveHand(Rules, state, 1, "COST_BASIC")

			Rules.playCard(state, 1, card.id)
			t:falsy(card.tapped, "탭된 채로 등장했습니다")
			t:eq(Rules.GameState.availableCost(state, 1), 1)
		end)

		t:it("한 턴에 두 장째는 거부된다", function()
			local state = Fixture.match(Rules)
			local first = Fixture.giveHand(Rules, state, 1, "COST_BASIC")
			local second = Fixture.giveHand(Rules, state, 1, "COST_BASIC")

			t:allowed(Rules.playCard(state, 1, first.id))
			local ok, reason = Rules.playCard(state, 1, second.id)
			t:denied(ok, reason, "1턴에")
		end)

		t:it("코스트가 모자라면 소환이 거부된다", function()
			local state = Fixture.match(Rules)
			Fixture.giveCost(Rules, state, 1, 2)
			local brute = Fixture.giveHand(Rules, state, 1, "CRE_BRUTE") -- 5 코스트

			local ok, reason = Rules.playCard(state, 1, brute.id)
			t:denied(ok, reason, "코스트")
		end)

		t:it("소환하면 코스트 카드가 그만큼 탭된다", function()
			local state = Fixture.match(Rules)
			local costCards = Fixture.giveCost(Rules, state, 1, 4)
			local guard = Fixture.giveHand(Rules, state, 1, "CRE_GUARD") -- 2 코스트

			t:eq(Rules.GameState.availableCost(state, 1), 4)
			t:allowed(Rules.playCard(state, 1, guard.id))
			t:eq(Rules.GameState.availableCost(state, 1), 2, "2 를 쓰고 2 가 남아야 한다")

			local tappedCount = 0
			for _, card in costCards do
				if card.tapped then
					tappedCount += 1
				end
			end
			t:eq(tappedCount, 2, "탭된 코스트 카드 수")
		end)

		t:it("자기 턴 시작에 코스트 카드가 언탭된다", function()
			local state = Fixture.match(Rules)
			local costCards = Fixture.giveCost(Rules, state, 1, 2)
			for _, card in costCards do
				card.tapped = true
			end

			-- P1 턴 종료 → P2 턴 → P1 턴 시작까지 진행
			Rules.endPhase(state, 1) -- Main → AttackPrep
			Rules.endPhase(state, 1) -- 공격자 없음 → P2 턴 Main
			t:eq(state.activePlayerId, 2)
			t:truthy(costCards[1].tapped, "상대 턴에는 아직 탭 상태여야 한다")

			Rules.endPhase(state, 2)
			Rules.endPhase(state, 2) -- → P1 턴
			t:eq(state.activePlayerId, 1)
			t:falsy(costCards[1].tapped, "자기 턴 시작에 언탭되어야 한다")
		end)

		t:it("상대 턴에는 코스트 카드를 낼 수 없다", function()
			local state = Fixture.match(Rules)
			local card = Fixture.giveHand(Rules, state, 2, "COST_BASIC")

			local ok, reason = Rules.playCard(state, 2, card.id)
			t:denied(ok, reason)
		end)
	end)
end
