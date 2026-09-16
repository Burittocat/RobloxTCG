--[[
	PvE 캠페인 — 스테이지 표와 진행도 규칙.

	여기서 막고 싶은 것 둘.

	  1. **스테이지 덱이 룰에 안 맞는 것.** 상대 덱은 사람이 손으로 적는 표라
	     59장이나 같은 카드 5장이 그대로 들어갈 수 있다. 그러면 그 스테이지를 누른
	     사람만 판이 안 열리는데, 덱 편집기는 멀쩡하니 원인을 엉뚱한 데서 찾게 된다.
	     그래서 **덱 편집기와 같은 함수**(Decks.validateEntries)로 검사한다.

	  2. **골드를 두 번 주는 것.** 되돌릴 수 없는 값이라 한 번 새면 저장소에 남는다.
]]

return function(t, ctx)
	local Campaign, Decks, AI = ctx.Campaign, ctx.Decks, ctx.AI

	local function fresh()
		return Campaign.newProgress()
	end

	--==================================================================
	t:describe("스테이지 표", function()
		t:it("스테이지가 있다", function()
			t:truthy(Campaign.count() > 0)
			t:eq(Campaign.count(), #Campaign.stages)
		end)

		t:it("모든 덱이 덱 편집기와 같은 검사를 통과한다", function()
			for index, stage in Campaign.stages do
				local ok, reason = Decks.validateEntries(stage.deck)
				t:allowed(ok, reason, ("%d번 '%s' 의 덱"):format(index, stage.name))
			end
		end)

		t:it("난이도가 실제로 있는 값이다", function()
			for index, stage in Campaign.stages do
				t:truthy(
					AI.Difficulty[stage.difficulty],
					("%d번 난이도 '%s' 는 AI.Difficulty 에 없습니다"):format(index, tostring(stage.difficulty))
				)
			end
		end)

		t:it("이름이 겹치지 않는다", function()
			local seen = {}
			for index, stage in Campaign.stages do
				t:falsy(seen[stage.name], ("%d번 이름 '%s' 가 앞에 또 있습니다"):format(index, stage.name))
				seen[stage.name] = true
			end
		end)

		t:it("보상과 상대 라이프가 0 보다 큰 정수다", function()
			for index, stage in Campaign.stages do
				for field, value in { gold = stage.gold, life = stage.life } do
					t:truthy(
						type(value) == "number" and value > 0 and value % 1 == 0,
						("%d번 %s 가 %s"):format(index, field, tostring(value))
					)
				end
			end
		end)

		t:it("설명이 비어 있지 않다", function()
			for index, stage in Campaign.stages do
				t:truthy(type(stage.note) == "string" and #stage.note > 0, ("%d번 note"):format(index))
			end
		end)

		--[[
			곡선이 뒤로 갈수록 올라가야 한다. 목록은 위에서 아래로 읽히므로, 보상이
			중간에 꺾이면 "여기가 더 쉬운가?" 로 읽힌다 — 실제로는 앞을 깨야만 열린다.
		]]
		t:it("보상이 뒤로 갈수록 커진다", function()
			for index = 2, Campaign.count() do
				t:truthy(
					Campaign.stages[index].gold > Campaign.stages[index - 1].gold,
					("%d번 보상이 앞 스테이지보다 크지 않습니다"):format(index)
				)
			end
		end)
	end)

	--==================================================================
	t:describe("덱 꺼내기", function()
		t:it("목록 모양으로 60장이 나온다", function()
			local list = Campaign.deckFor(1)
			t:eq(#list, ctx.Rules.Config.deckSize)
		end)

		t:it("없는 번호는 nil", function()
			t:eq(Campaign.deckFor(0), nil)
			t:eq(Campaign.deckFor(Campaign.count() + 1), nil)
			t:eq(Campaign.deckFor(1.5), nil)
			t:eq(Campaign.deckFor("1"), nil)
		end)
	end)

	--==================================================================
	t:describe("해금", function()
		t:it("처음에는 1번만 열려 있다", function()
			local progress = fresh()
			t:truthy(Campaign.isUnlocked(progress, 1))
			t:falsy(Campaign.isUnlocked(progress, 2))
		end)

		t:it("앞을 깨면 다음이 열린다", function()
			local progress = { cleared = 1, gold = 0 }
			t:truthy(Campaign.isUnlocked(progress, 2))
			t:falsy(Campaign.isUnlocked(progress, 3))
		end)

		t:it("이미 깬 것도 계속 열려 있다", function()
			t:truthy(Campaign.isUnlocked({ cleared = 2, gold = 0 }, 1))
		end)

		t:it("표 밖 번호는 열리지 않는다", function()
			-- 다 깬 사람도 없는 스테이지는 못 고른다. 이게 없으면 마지막을 깬 순간
			-- count()+1 이 "열린 것" 으로 판정되어 서버가 nil 덱으로 판을 연다.
			local progress = { cleared = Campaign.count(), gold = 0 }
			t:falsy(Campaign.isUnlocked(progress, Campaign.count() + 1))
			t:falsy(Campaign.isUnlocked(progress, 0))
		end)
	end)

	--==================================================================
	t:describe("보상", function()
		t:it("첫 클리어에 그 스테이지의 골드를 준다", function()
			local updated, gained = Campaign.applyClear(fresh(), 1)

			t:eq(gained, Campaign.stages[1].gold)
			t:eq(updated.gold, Campaign.stages[1].gold)
			t:eq(updated.cleared, 1)
		end)

		t:it("두 번째로 깨면 골드가 없다", function()
			local once = Campaign.applyClear(fresh(), 1)
			local twice, gained = Campaign.applyClear(once, 1)

			t:eq(gained, 0)
			t:eq(twice.gold, once.gold)
			t:eq(twice.cleared, 1)
		end)

		t:it("골드가 쌓인다", function()
			local progress = fresh()
			local total = 0

			for index = 1, Campaign.count() do
				local gained
				progress, gained = Campaign.applyClear(progress, index)
				total += gained
			end

			t:eq(progress.cleared, Campaign.count())
			t:eq(progress.gold, total)
		end)

		t:it("잠긴 번호를 깼다고 해도 아무 일이 없다", function()
			-- 서버가 먼저 막지만(Lobby:startCampaignStage), 여기가 마지막 방어선이다.
			local updated, gained = Campaign.applyClear(fresh(), 3)

			t:eq(gained, 0)
			t:eq(updated.cleared, 0)
			t:eq(updated.gold, 0)
		end)

		t:it("원래 진행도를 고치지 않는다", function()
			-- 저장에 실패했을 때 부르는 쪽이 옛 값으로 되돌릴 수 있어야 한다.
			local before = fresh()
			Campaign.applyClear(before, 1)

			t:eq(before.cleared, 0)
			t:eq(before.gold, 0)
		end)
	end)

	--==================================================================
	t:describe("진행도 검증", function()
		t:it("새 진행도는 통과한다", function()
			t:allowed(Campaign.validateProgress(fresh()))
		end)

		t:it("다 깬 진행도도 통과한다", function()
			t:allowed(Campaign.validateProgress({ cleared = Campaign.count(), gold = 9999 }))
		end)

		t:it("표보다 많이 깬 값은 거부한다", function()
			-- 스테이지를 줄인 뒤 옛 저장을 읽으면 이 모양이 된다.
			local ok, reason = Campaign.validateProgress({ cleared = Campaign.count() + 1, gold = 0 })
			t:denied(ok, reason, "표에는")
		end)

		t:it("모양이 잘못된 값을 거부한다", function()
			local function check(value, expected)
				local ok, reason = Campaign.validateProgress(value)
				t:denied(ok, reason, expected)
			end

			check("진행도", "테이블")
			check({ gold = 0 }, "cleared")
			check({ cleared = 0 }, "gold")
			check({ cleared = -1, gold = 0 }, "cleared")
			check({ cleared = 1.5, gold = 0 }, "cleared")
			check({ cleared = 0, gold = -5 }, "gold")
			check({ cleared = 0, gold = "많이" }, "gold")
		end)
	end)

	--==================================================================
	t:describe("화면에 내려보낼 목록", function()
		t:it("스테이지 수만큼 나온다", function()
			t:eq(#Campaign.list(fresh()), Campaign.count())
		end)

		t:it("잠김과 클리어를 표시한다", function()
			local rows = Campaign.list({ cleared = 1, gold = 0 })

			t:truthy(rows[1].cleared)
			t:truthy(rows[1].unlocked)
			t:falsy(rows[2].cleared)
			t:truthy(rows[2].unlocked)
			t:falsy(rows[3].unlocked)
		end)

		--[[
			상대 덱이 실리면 클라이언트가 상대 손패를 미리 아는 것과 같다.
			viewFor 가 상대 손패를 지우는 것과 같은 이유로 여기서 못 박는다.
		]]
		t:it("상대 덱이 실려 있지 않다", function()
			for _, row in Campaign.list(fresh()) do
				t:eq(row.deck, nil, ("%d번에 덱이 실렸습니다"):format(row.index))
			end
		end)

		--[[
			Net 주석 참조 — 숫자 키 딕셔너리는 RemoteEvent 에서 조용히 모양이 바뀐다.
			list 는 Net.packView 를 거치지 않고 그대로 실려 나가므로 여기서 확인한다.
		]]
		t:it("배열이라 그대로 실어 보낼 수 있다", function()
			local rows = Campaign.list(fresh())
			local count = 0

			for key in pairs(rows) do
				t:eq(type(key), "number")
				count += 1
			end
			t:eq(count, #rows)
		end)
	end)
end
