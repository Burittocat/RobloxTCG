--[[
	덱 — 목록 ↔ 엔트리 변환과 검증.

	여기서 막고 싶은 것: **클라이언트가 보낸 덱이 그대로 룰 엔진까지 들어가는 것.**
	덱은 사람이 편집하고, 저장소를 거쳐 돌아오고, 그 다음 판이 열린다. 그 경로 어디에서든
	이상한 값이 들어올 수 있으므로 모양부터 검사한다.
]]

return function(t, ctx)
	local Rules, Decks = ctx.Rules, ctx.Decks
	local Config = Rules.Config

	local function starterEntries()
		return Decks.starterEntries()
	end

	--==================================================================
	t:describe("목록과 엔트리", function()
		t:it("서로 되돌릴 수 있다", function()
			local list = Decks.starter()
			local back = Decks.toList(Decks.toEntries(list))

			t:eq(#back, #list)

			local function counts(cards)
				local out = {}
				for _, cardId in cards do
					out[cardId] = (out[cardId] or 0) + 1
				end
				return out
			end

			local before, after = counts(list), counts(back)
			for cardId, count in before do
				t:eq(after[cardId], count, cardId)
			end
		end)

		t:it("엔트리는 카드마다 한 줄이다", function()
			local entries = starterEntries()
			local seen = {}

			for _, entry in entries do
				t:falsy(seen[entry.id], ("%s 가 두 줄입니다"):format(entry.id))
				seen[entry.id] = true
				t:truthy(entry.count > 0)
			end
		end)
	end)

	--==================================================================
	t:describe("덱 검증", function()
		t:it("스타터 덱은 통과한다", function()
			t:allowed(Decks.validateEntries(starterEntries()))
		end)

		t:it("60장이 아니면 거부한다", function()
			local entries = starterEntries()
			entries[1].count -= 1

			local ok, reason = Decks.validateEntries(entries)
			t:denied(ok, reason, tostring(Config.deckSize))
		end)

		t:it("같은 카드 5장은 거부한다", function()
			local entries = { { id = "CRE_HAWK", count = 5 }, { id = "COST_BASIC", count = 55 } }

			local ok, reason = Decks.validateEntries(entries)
			t:denied(ok, reason, "최대")
		end)

		t:it("코스트 카드는 매수 제한이 없다", function()
			-- 기획서가 코스트 24~30장을 넣으라고 한다. 4장 제한을 적용하면 그게 불가능하다.
			t:allowed(Decks.validateEntries({ { id = "COST_BASIC", count = Config.deckSize } }))
		end)

		t:it("없는 카드는 거부한다", function()
			local ok, reason = Decks.validateEntries({
				{ id = "CRE_없는카드", count = 4 },
				{ id = "COST_BASIC", count = 56 },
			})
			t:denied(ok, reason, "존재하지 않는")
		end)

		t:it("모양이 잘못된 값을 거부한다", function()
			--[[
				`t:denied(f(), "배열")` 처럼 쓰면 안 된다 — Lua 는 마지막 자리가 아닌
				다중 반환을 한 값으로 자른다. 그러면 사유가 통째로 사라진 채 통과한다.
			]]
			local function check(value, expected)
				local ok, reason = Decks.validateEntries(value)
				t:denied(ok, reason, expected)
			end

			check("덱", "배열")
			check({ { count = 4 } }, "모양")
			check({ { id = 7, count = 4 } }, "모양")
			check({ { id = "CRE_HAWK", count = -1 } }, "매수")
			check({ { id = "CRE_HAWK", count = 1.5 } }, "매수")
			check({ { id = "CRE_HAWK", count = "네장" } }, "매수")
		end)

		t:it("같은 카드가 두 줄이면 거부한다", function()
			local ok, reason = Decks.validateEntries({
				{ id = "CRE_HAWK", count = 2 },
				{ id = "CRE_HAWK", count = 2 },
				{ id = "COST_BASIC", count = 56 },
			})
			t:denied(ok, reason, "두 번")
		end)
	end)

	--==================================================================
	t:describe("매수 상한", function()
		t:it("보통 카드는 4장", function()
			t:eq(Decks.maxCopies("CRE_HAWK"), Config.maxCopiesPerCard)
		end)

		t:it("코스트 카드는 제한 없음", function()
			t:eq(Decks.maxCopies("COST_BASIC"), Config.deckSize)
		end)

		t:it("없는 카드는 0장", function()
			t:eq(Decks.maxCopies("없는카드"), 0)
		end)
	end)
end
