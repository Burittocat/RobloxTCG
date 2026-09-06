--[[
	AI 자기대국 스모크 테스트.

	이게 있는 이유: 단위 테스트는 룰 하나씩만 본다. 실제 한 판에서만 드러나는
	교착(아무도 둘 수 없는 상태)이나 무한 루프는 끝까지 돌려봐야 잡힌다.
	시드를 여러 개 돌려 룰 엔진이 항상 승부까지 도달하는지 확인한다.
]]

return function(t, ctx)
	local Rules, AI, Decks = ctx.Rules, ctx.AI, ctx.Decks

	--[[
		AI 둘이 끝까지 둔다. -> state
		교착이면 에러를 던져 테스트가 실패한다.
	]]
	local function playOut(seed)
		local state = Rules.newMatch({
			seed = seed,
			startingPlayerId = 1,
			players = {
				{ name = "AI-1", deck = Decks.starter() },
				{ name = "AI-2", deck = Decks.starter() },
			},
		})

		local steps = 0
		while not state.finished do
			steps += 1
			if steps > 20000 then
				error(("시드 %d: 20000수 안에 끝나지 않았습니다 (교착 의심)"):format(seed))
			end

			local mover
			if not Rules.Stack.isEmpty(state) then
				mover = Rules.Stack.responderFor(state)
			elseif state.phase == Rules.Enums.Phase.DefensePrep then
				mover = Rules.GameState.opponentOf(state.activePlayerId)
			else
				mover = state.activePlayerId
			end

			local acted = AI.act(state, mover, AI.Difficulty.Normal)
			if not acted then
				error(("시드 %d: 턴 %d %s 에서 P%d 가 둘 수 있는 수가 없습니다"):format(
					seed,
					state.turn,
					state.phase,
					mover
				))
			end
		end

		return state
	end

	t:describe("스타터 덱", function()
		t:it("정식 규칙(60장, 최대 4장)을 만족한다", function()
			local ok, err = Rules.CardDef.validateDeck(Decks.starter(), Rules.Registry.get, true)
			t:allowed(ok, err)
		end)

		t:it("코스트 카드가 권장 범위 안에 있다", function()
			local count = 0
			for _, cardId in Decks.starter() do
				if Rules.Registry.mustGet(cardId).type == Rules.Enums.CardType.Cost then
					count += 1
				end
			end
			local range = Rules.Config.recommendedCostCardRange
			t:truthy(
				count >= range.min and count <= range.max,
				("코스트 카드 %d장 (권장 %d~%d)"):format(count, range.min, range.max)
			)
		end)
	end)

	t:describe("AI 자기대국", function()
		-- 시드를 바꾸면 완전히 다른 전개가 나온다. 여러 개를 돌려 교착을 넓게 훑는다.
		for _, seed in { 1, 42, 777, 20260906, 31337 } do
			t:it(("시드 %d 에서 승부까지 진행된다"):format(seed), function()
				local state = playOut(seed)

				t:truthy(state.finished, "게임이 끝나야 한다")
				t:truthy(state.winnerId == 1 or state.winnerId == 2, "승자가 정해져야 한다")
				t:truthy(state.turn > 1, "최소 몇 턴은 진행되어야 한다")

				-- 패자는 라이프가 0 이하이거나 덱이 말랐어야 한다
				local loserId = Rules.GameState.opponentOf(state.winnerId)
				local loser = state.players[loserId]
				t:truthy(
					loser.life <= 0 or state.lossReason == Rules.Enums.LossReason.DeckOut,
					("패배 사유가 상태와 맞지 않습니다 (라이프 %d, 사유 %s)"):format(loser.life, tostring(state.lossReason))
				)
			end)
		end

		t:it("같은 시드는 완전히 같은 결과를 낸다", function()
			local a = playOut(555)
			local b = playOut(555)

			t:eq(b.winnerId, a.winnerId, "승자")
			t:eq(b.turn, a.turn, "총 턴 수")
			t:eq(b.players[1].life, a.players[1].life, "P1 최종 라이프")
			t:eq(b.players[2].life, a.players[2].life, "P2 최종 라이프")
		end)
	end)

	t:describe("불변식", function()
		t:it("한 판이 끝나도 카드가 두 존에 동시에 존재하지 않는다", function()
			local state = playOut(2024)

			local seen = {}
			for playerId = 1, 2 do
				local player = state.players[playerId]
				for _, zoneName in { "deck", "hand", "field", "graveyard" } do
					for _, instanceId in player[zoneName] do
						t:falsy(
							seen[instanceId],
							("카드 %d 가 %s 와 %s 에 동시에 있습니다"):format(
								instanceId,
								tostring(seen[instanceId]),
								zoneName
							)
						)
						seen[instanceId] = zoneName
					end
				end
			end
		end)

		t:it("모든 카드 인스턴스의 zone 필드가 실제 위치와 일치한다", function()
			local state = playOut(2025)
			local Zone = Rules.Enums.Zone

			local zoneOf = {}
			for playerId = 1, 2 do
				local player = state.players[playerId]
				for zoneName, zone in
					{ deck = Zone.Deck, hand = Zone.Hand, field = Zone.Field, graveyard = Zone.Graveyard }
				do
					for _, instanceId in player[zoneName] do
						zoneOf[instanceId] = zone
					end
				end
			end

			for instanceId, instance in state.cards do
				-- 스택에 남아 있는 카드는 어느 플레이어 존에도 없다 (게임이 끝났으므로 없어야 정상)
				t:eq(
					zoneOf[instanceId],
					instance.zone,
					("카드 %d (%s) 의 zone 이 어긋납니다"):format(instanceId, instance.defId)
				)
			end
		end)
	end)
end
