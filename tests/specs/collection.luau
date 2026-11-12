--[[
	컬렉션과 카드팩 — 가진 카드, 팩 내용물, 골드 계산.

	여기서 막고 싶은 것 넷.

	  1. **스타터 덱을 못 짜는 것.** 새로 온 사람은 컬렉션이 스타터뿐인데, 그걸로 스타터
	     덱이 안 짜이면 "스타터 덱으로" 버튼이 거부당하고 판이 안 열린다.
	  2. **골드가 새는 것.** 잔액보다 비싼 팩이 팔리거나, 중복 환급으로 골드가 불어나는 것.
	     되돌릴 수 없는 값이라 한 번 새면 저장소에 남는다.
	  3. **같은 시드로 다른 팩이 나오는 것.** 카드 풀을 딕셔너리 순서로 만들면 그렇게 된다.
	  4. **업데이트가 덱을 빼앗는 것.** 컬렉션 전에 짜둔 덱이 "가지지 않은 카드" 로 거부되면
	     자기가 짠 덱이 스타터로 되돌아간다.
]]

return function(t, ctx)
	local Collection, Decks, Rules = ctx.Collection, ctx.Decks, ctx.Rules
	local Config = Rules.Config

	local function rng(seed)
		return Rules.RNG.new(seed)
	end

	local function countIn(list, id)
		local n = 0
		for _, value in list do
			if value == id then
				n += 1
			end
		end
		return n
	end

	--==================================================================
	t:describe("처음 받는 것", function()
		t:it("새 컬렉션으로 스타터 덱을 짤 수 있다", function()
			t:allowed(Collection.covers(Collection.new(), Decks.starterEntries()))
		end)

		t:it("새 컬렉션은 저장 검사를 통과한다", function()
			t:allowed(Collection.validate(Collection.new()))
		end)

		t:it("코스트 카드는 적지 않는다 — 무한이다", function()
			local collection = Collection.new()
			for _, entry in collection.cards do
				t:truthy(entry.id ~= "COST_BASIC", "코스트 카드가 컬렉션에 적혀 있습니다")
			end
			t:eq(Collection.countOf(collection, "COST_BASIC"), Config.deckSize)
		end)

		t:it("스타터에 없는 카드는 가지지 않는다", function()
			-- 초소병은 스타터에 없다. 이게 0 이 아니면 카드팩이 의미가 없다.
			t:eq(Collection.countOf(Collection.new(), "CRE_SENTRY"), 0)
		end)

		t:it("컬렉션 전에 짜둔 덱의 카드를 물려받는다", function()
			local legacy = {
				{ id = "COST_BASIC", count = 44 },
				{ id = "CRE_TITAN", count = 4 },
				{ id = "CRE_SENTRY", count = 4 },
				{ id = "SPL_EXECUTE", count = 4 },
				{ id = "CRE_HAWK", count = 4 },
			}
			local collection = Collection.new(legacy)

			t:allowed(Collection.covers(collection, legacy))
			-- 스타터도 그대로 짤 수 있어야 한다 — 물려받는 것은 더하는 것이지 바꾸는 것이 아니다
			t:allowed(Collection.covers(collection, Decks.starterEntries()))
			t:eq(Collection.countOf(collection, "CRE_HAWK"), 4)
		end)

		t:it("규칙에 안 맞는 옛 덱은 물려받지 않는다", function()
			-- 같은 카드 9장 — 저장소를 손으로 고쳐 넣은 값. 그걸 근거로 카드를 주면 안 된다.
			local broken = { { id = "COST_BASIC", count = 51 }, { id = "CRE_TITAN", count = 9 } }
			t:eq(Collection.countOf(Collection.new(broken), "CRE_TITAN"), 0)
		end)
	end)

	--==================================================================
	t:describe("덱을 짤 수 있나", function()
		t:it("가진 것보다 많이 넣으면 거부한다", function()
			local deck = Decks.starterEntries()
			table.insert(deck, { id = "CRE_TITAN", count = 1 })

			local ok, reason = Collection.covers(Collection.new(), deck)
			t:denied(ok, reason, "가지고 있습니다")
		end)

		t:it("이유에 카드 이름이 들어간다", function()
			local ok, reason = Collection.covers(Collection.new(), { { id = "CRE_TITAN", count = 1 } })
			t:denied(ok, reason, Rules.Registry.get("CRE_TITAN").name)
		end)

		t:it("코스트 카드는 몇 장이든 된다", function()
			t:allowed(Collection.covers(Collection.new(), { { id = "COST_BASIC", count = 60 } }))
		end)
	end)

	--==================================================================
	t:describe("카드 풀", function()
		t:it("코스트 카드는 팩에서 나오지 않는다", function()
			local commons, rares = Collection.pools()
			t:eq(countIn(commons, "COST_BASIC") + countIn(rares, "COST_BASIC"), 0)
		end)

		t:it("등급대로 나뉘고 빠진 카드가 없다", function()
			local commons, rares = Collection.pools()

			for _, id in commons do
				t:eq(Rules.Registry.get(id).rarity, "Common", id)
			end
			for _, id in rares do
				t:eq(Rules.Registry.get(id).rarity, "Rare", id)
			end

			local costs = 0
			for _, def in Rules.Registry.all() do
				if Config.copyLimitExemptTypes[def.type] then
					costs += 1
				end
			end
			t:eq(#commons + #rares + costs, Rules.Registry.count())
			t:truthy(#rares > 0, "희귀가 하나도 없으면 희귀 칸을 채울 수 없습니다")
		end)
	end)

	--==================================================================
	t:describe("팩 한 봉", function()
		t:it("정해진 장수가 나온다", function()
			t:eq(#Collection.rollPack(rng(1)), Collection.Pack.size)
		end)

		t:it("희귀 칸에는 반드시 희귀가 나온다", function()
			for seed = 1, 50 do
				local pack = Collection.rollPack(rng(seed))
				for slot = Collection.Pack.size - Collection.Pack.rares + 1, Collection.Pack.size do
					t:eq(Rules.Registry.get(pack[slot]).rarity, "Rare", ("시드 %d · %d번째 칸"):format(seed, slot))
				end
			end
		end)

		t:it("같은 시드면 같은 팩이 나온다", function()
			local a, b = Collection.rollPack(rng(777)), Collection.rollPack(rng(777))
			t:eq(table.concat(a, ","), table.concat(b, ","))
		end)

		t:it("시드가 다르면 대개 다른 팩이 나온다", function()
			local seen = {}
			local distinct = 0
			for seed = 1, 20 do
				local key = table.concat(Collection.rollPack(rng(seed)), ",")
				if not seen[key] then
					seen[key] = true
					distinct += 1
				end
			end
			t:truthy(distinct > 15, ("20개 시드에서 서로 다른 팩이 %d 개뿐입니다"):format(distinct))
		end)
	end)

	--==================================================================
	t:describe("넣기와 환급", function()
		t:it("새 카드는 컬렉션에 들어간다", function()
			local updated, results, refund = Collection.applyCards(Collection.new(), { "CRE_SENTRY" })

			t:eq(Collection.countOf(updated, "CRE_SENTRY"), 1)
			t:truthy(results[1].kept)
			t:eq(refund, 0)
		end)

		t:it("4장을 넘는 장은 골드로 돌려준다", function()
			local cards = { "CRE_SENTRY", "CRE_SENTRY", "CRE_SENTRY", "CRE_SENTRY", "CRE_SENTRY" }
			local base = { cards = {}, spent = 100, opened = 1 }
			local updated, results, refund = Collection.applyCards(base, cards)

			t:eq(Collection.countOf(updated, "CRE_SENTRY"), Config.maxCopiesPerCard)
			t:falsy(results[5].kept)
			t:eq(refund, Collection.Refund.Common)
			t:eq(updated.spent, 100 - Collection.Refund.Common)
		end)

		t:it("희귀 중복은 더 많이 돌려준다", function()
			local full = { cards = { { id = "CRE_TITAN", count = 4 } }, spent = 100, opened = 1 }
			local _, results = Collection.applyCards(full, { "CRE_TITAN" })
			t:eq(results[1].refund, Collection.Refund.Rare)
		end)

		--[[
			다 모은 사람이 팩을 사서 골드를 벌면 안 된다. 한 팩이 전부 희귀 중복이어도
			돌려받는 것이 가격보다 작아야 한다.
		]]
		t:it("한 팩을 전부 돌려받아도 가격보다 적다", function()
			local commonSlots = Collection.Pack.size - Collection.Pack.rares
			local most = Collection.Refund.Common * commonSlots + Collection.Refund.Rare * Collection.Pack.rares
			t:truthy(
				most < Collection.Pack.price,
				("전부 희귀 중복이면 %d 를 돌려받는데 팩은 %d 입니다"):format(most, Collection.Pack.price)
			)
		end)

		t:it("원래 컬렉션을 고치지 않는다", function()
			local before = Collection.new()
			local sentries = Collection.countOf(before, "CRE_SENTRY")
			Collection.applyCards(before, { "CRE_SENTRY" })
			t:eq(Collection.countOf(before, "CRE_SENTRY"), sentries)
		end)
	end)

	--==================================================================
	t:describe("사기", function()
		local rich = { cleared = 5, gold = 1000 }

		t:it("골드가 모자라면 못 산다", function()
			local updated, reason = Collection.buyPack({ cleared = 1, gold = 50 }, Collection.new(), rng(1))
			t:eq(updated, nil)
			t:truthy(tostring(reason):find("모자랍니다", 1, true), tostring(reason))
		end)

		t:it("이미 쓴 골드는 잔액에서 빠진다", function()
			-- 1000 을 벌었어도 950 을 썼으면 50 뿐이다.
			local spent = Collection.new()
			spent.spent = 950
			t:eq(Collection.balance(rich, spent), 50)
			t:eq(Collection.buyPack(rich, spent, rng(1)), nil)
		end)

		t:it("사면 가격만큼 쓰고 장수만큼 받는다", function()
			local before = Collection.new()
			local updated, results = Collection.buyPack(rich, before, rng(42))

			t:truthy(updated)
			t:eq(#results, Collection.Pack.size)
			t:eq(updated.opened, 1)

			local refund = 0
			for _, pull in results do
				refund += pull.refund
			end
			t:eq(updated.spent, Collection.Pack.price - refund)
			t:eq(Collection.balance(rich, updated), rich.gold - Collection.Pack.price + refund)
		end)

		t:it("산 결과는 저장 검사를 통과한다", function()
			local collection = Collection.new()
			for seed = 1, 9 do
				collection = Collection.buyPack(rich, collection, rng(seed))
				t:allowed(Collection.validate(collection))
			end
		end)

		t:it("아무리 사도 4장을 넘지 않는다", function()
			local collection = Collection.new()
			local endless = { cleared = 5, gold = 1000000 }
			for seed = 1, 200 do
				collection = Collection.buyPack(endless, collection, rng(seed))
			end
			for _, entry in collection.cards do
				t:truthy(entry.count <= Config.maxCopiesPerCard, ("%s 가 %d장"):format(entry.id, entry.count))
			end

			local have, total = Collection.progress(collection)
			t:eq(have, total, "200팩이면 다 모아야 합니다")
		end)
	end)

	--==================================================================
	t:describe("저장값 검증", function()
		t:it("모양이 잘못된 값을 거부한다", function()
			local function check(value, expected)
				local ok, reason = Collection.validate(value)
				t:denied(ok, reason, expected)
			end

			check("컬렉션", "테이블")
			check({ cards = {}, opened = 0 }, "spent")
			check({ cards = {}, spent = -1, opened = 0 }, "spent")
			check({ cards = {}, spent = 0, opened = 1.5 }, "opened")
			check({ cards = "많이", spent = 0, opened = 0 }, "cards")
			check({ cards = { { id = "CRE_NOPE", count = 1 } }, spent = 0, opened = 0 }, "없는 카드")
			check({ cards = { { id = "CRE_HAWK", count = -1 } }, spent = 0, opened = 0 }, "매수")
			check({
				cards = { { id = "CRE_HAWK", count = 1 }, { id = "CRE_HAWK", count = 1 } },
				spent = 0,
				opened = 0,
			}, "두 번")
		end)
	end)

	--==================================================================
	t:describe("화면에 내려보낼 모양", function()
		t:it("배열이라 그대로 실어 보낼 수 있다", function()
			-- Net 주석 참조 — 숫자 키 딕셔너리는 RemoteEvent 에서 조용히 모양이 바뀐다.
			local owned = Collection.owned(Collection.new())
			local count = 0
			for key in pairs(owned) do
				t:eq(type(key), "number")
				count += 1
			end
			t:eq(count, #owned)
		end)

		t:it("모은 정도는 0 보다 크고 전체보다 작다", function()
			local have, total = Collection.progress(Collection.new())
			t:truthy(have > 0 and have < total, ("%d / %d"):format(have, total))
		end)
	end)
end
