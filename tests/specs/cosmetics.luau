--[[
	코스메틱(카드 테두리) — 사기 · 끼기 · 저장값.

	여기서 막고 싶은 것 넷.

	  1. **골드가 새는 것.** 잔액보다 비싼 테두리가 팔리거나, 같은 것을 두 번 사는 것.
	  2. **안 산 테두리가 그려지는 것.** 저장소나 리모트로 안 산 id 를 끼워 넣는 것.
	  3. **테두리가 하이라이트를 가리는 것.** 두께가 하이라이트(4)만 하면 "누를 수 있는
	     카드" 와 구별이 안 된다.
	  4. **카드팩이 테두리를 지우는 것 · 테두리가 카드를 지우는 것.** 같은 저장값이라
	     한쪽이 새 값을 만들면서 다른 쪽 칸을 빠뜨리면 조용히 사라진다.
]]

return function(t, ctx)
	local Collection, Cosmetics, Rules = ctx.Collection, ctx.Cosmetics, ctx.Rules

	local rich = { cleared = 5, gold = 1000 }
	local poor = { cleared = 1, gold = 50 }

	local function firstPaid()
		for _, frame in Cosmetics.Frames do
			if frame.price > 0 then
				return frame
			end
		end
		error("돈 내고 사는 테두리가 하나도 없습니다")
	end

	--==================================================================
	t:describe("테두리 목록", function()
		t:it("기본 테두리는 공짜이고 목록에 있다", function()
			local basic = Cosmetics.frame(Cosmetics.DefaultFrame)
			t:truthy(basic, "기본 테두리가 목록에 있어야 합니다")
			t:eq(basic.price, 0)
		end)

		t:it("id 가 겹치지 않는다", function()
			local seen = {}
			for _, frame in Cosmetics.Frames do
				t:falsy(seen[frame.id], ("'%s' 가 두 번 있습니다"):format(frame.id))
				seen[frame.id] = true
			end
		end)

		--[[
			하이라이트(선택·대상)는 두께 4 다(Theme.outline). 테두리가 그만큼 두꺼우면
			꾸민 카드가 전부 "누를 수 있는 카드" 처럼 보인다.
		]]
		t:it("테두리는 하이라이트보다 얇다", function()
			for _, frame in Cosmetics.Frames do
				t:truthy(frame.thickness > 0 and frame.thickness < 4, ("%s 두께 %s"):format(frame.id, tostring(frame.thickness)))
			end
		end)

		t:it("색은 0~255 숫자 셋이다", function()
			for _, frame in Cosmetics.Frames do
				t:eq(#frame.color, 3, frame.id)
				for _, value in frame.color do
					t:truthy(type(value) == "number" and value >= 0 and value <= 255, frame.id)
				end
			end
		end)

		t:it("모르는 id 는 기본 테두리로 그린다", function()
			t:eq(Cosmetics.frameOrDefault("FRAME_NOPE").id, Cosmetics.DefaultFrame)
			t:eq(Cosmetics.frameOrDefault(nil).id, Cosmetics.DefaultFrame)
			t:eq(Cosmetics.frameOrDefault("").id, Cosmetics.DefaultFrame)
		end)
	end)

	--==================================================================
	t:describe("처음 상태", function()
		t:it("새 컬렉션은 기본 테두리를 낀다", function()
			t:eq(Cosmetics.equippedFrame(Collection.new()), Cosmetics.DefaultFrame)
		end)

		t:it("cosmetics 칸이 없는 옛 저장값도 기본 테두리다", function()
			local legacy = { cards = {}, spent = 0, opened = 0 }
			t:allowed(Collection.validate(legacy))
			t:eq(Cosmetics.equippedFrame(legacy), Cosmetics.DefaultFrame)
		end)

		t:it("돈 내는 테두리는 처음에 안 가졌다", function()
			t:falsy(Cosmetics.owns(Collection.new(), firstPaid().id))
		end)
	end)

	--==================================================================
	t:describe("사기", function()
		t:it("사면 가격만큼 쓰고 바로 낀다", function()
			local frame = firstPaid()
			local updated = Cosmetics.buy(rich, Collection.new(), frame.id)

			t:truthy(updated)
			t:eq(updated.spent, frame.price)
			t:truthy(Cosmetics.owns(updated, frame.id))
			t:eq(Cosmetics.equippedFrame(updated), frame.id)
			t:eq(Collection.balance(rich, updated), rich.gold - frame.price)
			t:allowed(Collection.validate(updated))
		end)

		t:it("골드가 모자라면 못 산다", function()
			local updated, reason = Cosmetics.buy(poor, Collection.new(), firstPaid().id)
			t:eq(updated, nil)
			t:truthy(tostring(reason):find("모자랍니다", 1, true), tostring(reason))
		end)

		t:it("이미 쓴 골드는 잔액에서 빠진다", function()
			local spent = Collection.new()
			spent.spent = rich.gold - firstPaid().price + 1
			t:eq(Cosmetics.buy(rich, spent, firstPaid().id), nil)
		end)

		t:it("같은 테두리를 두 번 살 수 없다", function()
			local frame = firstPaid()
			local once = Cosmetics.buy(rich, Collection.new(), frame.id)
			local twice, reason = Cosmetics.buy(rich, once, frame.id)

			t:eq(twice, nil)
			t:truthy(tostring(reason):find("이미", 1, true), tostring(reason))
		end)

		t:it("기본 테두리는 살 것이 없다", function()
			t:eq(Cosmetics.buy(rich, Collection.new(), Cosmetics.DefaultFrame), nil)
		end)

		t:it("없는 테두리는 못 산다", function()
			local updated, reason = Cosmetics.buy(rich, Collection.new(), "FRAME_NOPE")
			t:eq(updated, nil)
			t:truthy(tostring(reason):find("없는", 1, true), tostring(reason))
			t:eq(Cosmetics.buy(rich, Collection.new(), nil), nil)
		end)

		t:it("원래 컬렉션을 고치지 않는다", function()
			local before = Collection.new()
			Cosmetics.buy(rich, before, firstPaid().id)
			t:eq(before.spent, 0)
			t:falsy(Cosmetics.owns(before, firstPaid().id))
		end)

		t:it("다 사도 저장 검사를 통과하고 목록 순서와 무관하게 같은 값이 된다", function()
			local forward, backward = Collection.new(), Collection.new()
			local endless = { cleared = 5, gold = 100000 }

			for index = 1, #Cosmetics.Frames do
				local id = Cosmetics.Frames[index].id
				if Cosmetics.Frames[index].price > 0 then
					forward = Cosmetics.buy(endless, forward, id)
				end
				local reverse = Cosmetics.Frames[#Cosmetics.Frames - index + 1]
				if reverse.price > 0 then
					backward = Cosmetics.buy(endless, backward, reverse.id)
				end
			end

			t:allowed(Collection.validate(forward))
			t:eq(table.concat(forward.cosmetics.owned, ","), table.concat(backward.cosmetics.owned, ","))
		end)
	end)

	--==================================================================
	t:describe("끼기", function()
		t:it("가진 테두리로 갈아 낀다", function()
			local frame = firstPaid()
			local owned = Cosmetics.buy(rich, Collection.new(), frame.id)

			local basic = Cosmetics.equip(owned, Cosmetics.DefaultFrame)
			t:eq(Cosmetics.equippedFrame(basic), Cosmetics.DefaultFrame)

			local back = Cosmetics.equip(basic, frame.id)
			t:eq(Cosmetics.equippedFrame(back), frame.id)
			t:eq(back.spent, owned.spent, "끼는 데 골드를 쓰면 안 됩니다")
		end)

		t:it("안 가진 테두리는 못 낀다", function()
			local updated, reason = Cosmetics.equip(Collection.new(), firstPaid().id)
			t:eq(updated, nil)
			t:truthy(tostring(reason):find("가지지 않은", 1, true), tostring(reason))
		end)

		--[[
			저장소를 손으로 고쳐 frame 에 안 산 id 를 적어도 그건 그려지지 않는다.
		]]
		t:it("저장값이 안 산 테두리를 가리키면 기본으로 그린다", function()
			local forged = Collection.new()
			forged.cosmetics = { owned = {}, frame = firstPaid().id }

			t:allowed(Collection.validate(forged))
			t:eq(Cosmetics.equippedFrame(forged), Cosmetics.DefaultFrame)
		end)

		t:it("저장값이 없어진 테두리를 가리켜도 컬렉션은 읽힌다", function()
			local stale = Collection.new()
			stale.cosmetics = { owned = { "FRAME_REMOVED" }, frame = "FRAME_REMOVED" }

			t:allowed(Collection.validate(stale), nil, "없어진 테두리 하나로 카드까지 못 쓰게 되면 안 됩니다")
			t:eq(Cosmetics.equippedFrame(stale), Cosmetics.DefaultFrame)
		end)
	end)

	--==================================================================
	t:describe("카드팩과 한 저장값", function()
		t:it("팩을 사도 테두리가 남는다", function()
			local frame = firstPaid()
			local collection = Cosmetics.buy(rich, Collection.new(), frame.id)
			collection = Collection.buyPack(rich, collection, Rules.RNG.new(1))

			t:truthy(Cosmetics.owns(collection, frame.id), "골드 팩이 테두리를 지웠습니다")
			t:eq(Cosmetics.equippedFrame(collection), frame.id)
		end)

		t:it("Robux 팩을 받아도 테두리가 남는다", function()
			local frame = firstPaid()
			local collection = Cosmetics.buy(rich, Collection.new(), frame.id)
			collection = Collection.grantPack(collection, "receipt-1", Rules.RNG.new(2))

			t:truthy(Cosmetics.owns(collection, frame.id), "Robux 팩이 테두리를 지웠습니다")
		end)

		t:it("테두리를 사도 카드와 영수증이 남는다", function()
			local function cardsOf(collection)
				local out = {}
				for _, entry in collection.cards do
					table.insert(out, ("%s=%d"):format(entry.id, entry.count))
				end
				return table.concat(out, ",")
			end

			local before = Collection.grantPack(Collection.new(), "keep-me", Rules.RNG.new(3))
			local after = Cosmetics.buy(rich, before, firstPaid().id)

			t:truthy(Collection.hasReceipt(after, "keep-me"), "테두리를 사면서 영수증 기록이 지워졌습니다")
			t:eq(cardsOf(after), cardsOf(before), "테두리를 사면서 카드가 바뀌었습니다")
		end)

		t:it("팩과 테두리가 같은 잔액에서 나간다", function()
			local frame = firstPaid()
			local collection = Cosmetics.buy(rich, Collection.new(), frame.id)
			local afterPack, results = Collection.buyPack(rich, collection, Rules.RNG.new(4))

			local refund = 0
			for _, pull in results do
				refund += pull.refund
			end
			t:eq(Collection.balance(rich, afterPack), rich.gold - frame.price - Collection.Pack.price + refund)
		end)
	end)

	--==================================================================
	t:describe("저장값 검증", function()
		t:it("cosmetics 모양이 틀리면 거부한다", function()
			local function check(cosmetics, expected)
				local ok, reason = Collection.validate({ cards = {}, spent = 0, opened = 0, cosmetics = cosmetics })
				t:denied(ok, reason, expected)
			end

			check("테두리", "cosmetics")
			check({ frame = 3 }, "frame")
			check({ owned = "FRAME_TIDE" }, "owned")
			check({ owned = { 1 } }, "owned")
		end)
	end)

	--==================================================================
	t:describe("화면에 내려보낼 모양", function()
		t:it("목록은 배열이고 끼는 것은 하나뿐이다", function()
			local collection = Cosmetics.buy(rich, Collection.new(), firstPaid().id)
			local list = Cosmetics.list(collection)

			t:eq(#list, #Cosmetics.Frames)
			local equipped = 0
			for key, entry in pairs(list) do
				t:eq(type(key), "number")
				if entry.equipped then
					equipped += 1
					t:truthy(entry.owned, "끼는 것은 가진 것이어야 합니다")
				end
			end
			t:eq(equipped, 1)
		end)
	end)
end
