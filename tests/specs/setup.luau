--[[ 매치 초기화: 라이프/초기 패/덱/결정론 ]]

return function(t, ctx)
	local Rules, Fixture = ctx.Rules, ctx.Fixture
	local Config = Rules.Config

	t:describe("매치 초기화", function()
		t:it("라이프 30 으로 시작한다", function()
			local state = Fixture.match(Rules)
			t:eq(state.players[1].life, 30)
			t:eq(state.players[2].life, 30)
		end)

		t:it("양쪽 모두 7장을 뽑고 시작한다", function()
			local state = Fixture.match(Rules)
			t:eq(#state.players[1].hand, Config.startingHandSize, "P1 초기 패")
			t:eq(#state.players[2].hand, Config.startingHandSize, "P2 초기 패")
		end)

		t:it("선공은 첫 턴 드로우를 건너뛴다", function()
			local state = Fixture.match(Rules, { deckSize = 30, startingPlayerId = 1 })
			-- 선공(P1)은 7장만, 후공(P2)도 아직 자기 턴이 아니므로 7장
			t:eq(#state.players[1].hand, 7, "선공 패")
			t:eq(#state.players[1].deck, 23, "선공 덱 (30 - 7)")
		end)

		t:it("1턴 메인 페이즈에서 멈춘다", function()
			local state = Fixture.match(Rules)
			t:eq(state.turn, 1)
			t:eq(state.phase, Rules.Enums.Phase.Main)
			t:eq(state.activePlayerId, 1)
		end)

		t:it("같은 시드는 같은 셔플 결과를 낸다", function()
			local a = Fixture.match(Rules, { seed = 777 })
			local b = Fixture.match(Rules, { seed = 777 })
			for index, instanceId in a.players[1].deck do
				t:eq(b.players[1].deck[index], instanceId, "덱 " .. index .. "번째")
			end
		end)

		t:it("다른 시드는 다른 셔플 결과를 낸다", function()
			local a = Fixture.match(Rules, { seed = 1 })
			local b = Fixture.match(Rules, { seed = 2 })
			-- 인스턴스 id 순서가 완전히 같을 확률은 사실상 0
			local identical = true
			for index, instanceId in a.players[1].deck do
				if b.players[1].deck[index] ~= instanceId then
					identical = false
					break
				end
			end
			t:falsy(identical, "시드가 달라도 같은 순서가 나왔습니다")
		end)
	end)

	t:describe("카드 DB", function()
		t:it("모든 기본 카드가 스키마 검증을 통과한다", function()
			for _, def in ctx.Cards.list() do
				local ok, err = Rules.CardDef.validate(def)
				t:allowed(ok, err, def.id)
			end
		end)

		t:it("5개 키워드가 모두 카드에 등장한다", function()
			local seen = {}
			for _, def in ctx.Cards.list() do
				for _, kw in def.keywords or {} do
					seen[kw] = true
				end
			end
			for key in Rules.Enums.Keyword do
				t:truthy(seen[key], key .. " 키워드를 가진 카드가 없습니다")
			end
		end)

		t:it("잘못된 카드는 검증에서 걸러진다", function()
			local ok = Rules.CardDef.validate({
				id = "BAD",
				name = "이상한 생물",
				type = "Creature",
				cost = 1,
				power = 1,
				toughness = 1,
				keywords = { "Instant" }, -- 생물에 즉시시전
			})
			t:falsy(ok, "생물에 즉시시전이 붙었는데 통과했습니다")
		end)
	end)
end
