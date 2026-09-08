--[[
	멀리건 관문 — 판이 시작되기 전 손패를 한 번 물릴 수 있다 (무료 1회 전체 교체).

	여기서 못 박는 것은 두 가지다.
	  · 무료 1회라는 것 (두 번째는 거부, 물리면 그 자리에서 결정이 끝난다)
	  · 관문이 끝나기 전에는 판이 시작되지 않는다는 것
]]

return function(t, ctx)
	local Rules, Decks, Fixture = ctx.Rules, ctx.Decks, ctx.Fixture
	local Phase = Rules.Enums.Phase
	local Config = Rules.Config

	local function newMatch(seed, startingPlayerId)
		return Rules.newMatch({
			seed = seed or 4242,
			startingPlayerId = startingPlayerId or 1,
			players = {
				{ name = "P1", deck = Decks.starter() },
				{ name = "P2", deck = Decks.starter() },
			},
		})
	end

	local function handIds(state, playerId)
		return table.concat(state.players[playerId].hand, ",")
	end

	--==================================================================
	t:describe("관문", function()
		t:it("판은 멀리건 관문에서 시작한다", function()
			local state = newMatch()

			t:eq(state.phase, Phase.Mulligan)
			t:eq(state.turn, 0, "아직 1턴이 시작되지 않았습니다")
			t:eq(state.activePlayerId, state.startingPlayerId, "선공부터 결정합니다")
		end)

		t:it("선공이 결정하면 후공 차례가 된다", function()
			local state = newMatch(4242, 1)

			t:allowed(Rules.keepHand(state, 1))
			t:eq(state.phase, Phase.Mulligan, "아직 관문입니다")
			t:eq(state.activePlayerId, 2)
		end)

		t:it("둘 다 결정하면 판이 시작된다", function()
			local state = newMatch(4242, 2)

			Rules.keepHand(state, 2)
			Rules.keepHand(state, 1)

			t:eq(state.phase, Phase.Main, "선공의 1턴 메인에서 멈춰야 합니다")
			t:eq(state.turn, 1)
			t:eq(state.activePlayerId, 2, "선공이 1턴을 가져갑니다")
		end)

		t:it("자기 차례가 아니면 거부한다", function()
			local state = newMatch(4242, 1)

			local ok, reason = Rules.mulligan(state, 2)
			t:denied(ok, reason, "상대")
		end)

		t:it("판이 시작된 뒤에는 물릴 수 없다", function()
			local state = Fixture.match(Rules) -- 관문을 건너뛴 판

			local ok, reason = Rules.mulligan(state, 1)
			t:denied(ok, reason, "멀리건")
		end)

		t:it("mulligan = false 면 관문 없이 시작한다", function()
			local state = Rules.newMatch({
				seed = 1,
				startingPlayerId = 1,
				mulligan = false,
				players = {
					{ name = "P1", deck = Decks.starter() },
					{ name = "P2", deck = Decks.starter() },
				},
			})

			t:eq(state.phase, Phase.Main)
			t:eq(state.turn, 1)
		end)
	end)

	--==================================================================
	t:describe("무료 1회 전체 교체", function()
		t:it("물리면 손패가 통째로 바뀐다", function()
			local state = newMatch(20260909, 1)
			local before = handIds(state, 1)

			t:allowed(Rules.mulligan(state, 1))

			t:eq(#state.players[1].hand, Config.startingHandSize, "같은 장수를 다시 뽑습니다")
			t:neq(handIds(state, 1), before, "덱을 섞고 다시 뽑았으면 순서가 그대로일 수 없습니다")
		end)

		t:it("카드가 사라지거나 늘지 않는다", function()
			local state = newMatch(777, 1)
			local player = state.players[1]
			local total = #player.deck + #player.hand

			Rules.mulligan(state, 1)

			t:eq(#player.deck + #player.hand, total, "물린 손패는 덱으로 돌아가야 합니다")
			t:eq(#player.deck, Config.deckSize - Config.startingHandSize)
		end)

		t:it("물리면 그 자리에서 결정이 끝난다", function()
			local state = newMatch(777, 1)

			Rules.mulligan(state, 1)
			t:eq(state.activePlayerId, 2, "물린 사람의 차례는 끝나야 합니다")
		end)

		t:it("두 번은 물릴 수 없다", function()
			local state = newMatch(777, 1)

			Rules.mulligan(state, 1)
			Rules.keepHand(state, 2) -- 판 시작

			local ok, reason = Rules.mulligan(state, 1)
			t:denied(ok, reason, "멀리건")
		end)

		t:it("한쪽만 물려도 다른 쪽 손패는 그대로다", function()
			local state = newMatch(31337, 1)
			local foeHand = handIds(state, 2)

			Rules.mulligan(state, 1)

			t:eq(handIds(state, 2), foeHand)
			t:falsy(state.players[2].hasMulliganed)
		end)
	end)
end
