--[[
	PvP 랭크 — 보이는 랭크 점수 · 숨은 MMR · 티어.

	여기서 막고 싶은 것 넷.

	  1. **부계정 농사.** 계정 둘로 붙어 한쪽이 바로 항복하면 점수가 무한히 오른다
	  2. **나가서 손해 피하기.** 질 것 같을 때 나가면 점수가 안 깎이는 것
	  3. **점수가 새는 것.** 0 아래로 내려가거나, 이긴 쪽 · 진 쪽 MMR 변화가 어긋나는 것
	  4. **옛 저장값이 깨지는 것.** 랭크 칸이 없는 진행도도 그대로 읽혀야 한다
]]

return function(t, ctx)
	local Rank, Campaign = ctx.Rank, ctx.Campaign

	local LONG = Campaign.PvpReward.minTurns + 10
	local SHORT = Campaign.PvpReward.minTurns - 1

	local function fresh()
		return Campaign.newProgress()
	end

	--==================================================================
	t:describe("처음 상태", function()
		t:it("랭크 칸이 없는 진행도는 0점 · 처음 MMR 이다", function()
			t:eq(Rank.pointsOf(fresh()), 0)
			t:eq(Rank.mmrOf(fresh()), Rank.Mmr.initial)
			t:allowed(Campaign.validateProgress(fresh()))
		end)

		t:it("0점은 가장 낮은 티어다", function()
			t:eq(Rank.tierOf(0).id, Rank.Tiers[1].id)
		end)
	end)

	--==================================================================
	t:describe("티어", function()
		t:it("경계 점수에서 정확히 오른다", function()
			for index, tier in Rank.Tiers do
				t:eq(Rank.tierOf(tier.points).id, tier.id, ("%d점"):format(tier.points))
				if index > 1 then
					t:eq(Rank.tierOf(tier.points - 1).id, Rank.Tiers[index - 1].id, ("%d점"):format(tier.points - 1))
				end
			end
		end)

		t:it("티어 기준이 오름차순이고 첫 티어는 0점부터다", function()
			t:eq(Rank.Tiers[1].points, 0)
			for index = 2, #Rank.Tiers do
				t:truthy(Rank.Tiers[index].points > Rank.Tiers[index - 1].points, Rank.Tiers[index].id)
			end
		end)

		t:it("다음 티어를 알려주고, 맨 위에는 없다", function()
			local _, nextTier = Rank.tierOf(0)
			t:eq(nextTier.id, Rank.Tiers[2].id)
			local _, none = Rank.tierOf(Rank.Tiers[#Rank.Tiers].points + 5000)
			t:eq(none, nil)
		end)

		t:it("라벨은 티어 이름과 점수다", function()
			t:eq(Rank.label(245), ("%s 245점"):format(Rank.tierOf(245).name))
		end)
	end)

	--==================================================================
	t:describe("MMR", function()
		t:it("비슷한 상대면 k 의 절반쯤 오간다", function()
			t:eq(Rank.mmrDelta(1000, 1000), Rank.Mmr.k / 2)
		end)

		t:it("강한 상대를 이기면 더 많이, 약한 상대를 이기면 더 적게 오른다", function()
			t:truthy(Rank.mmrDelta(1000, 1400) > Rank.mmrDelta(1000, 1000))
			t:truthy(Rank.mmrDelta(1400, 1000) < Rank.mmrDelta(1000, 1000))
		end)

		t:it("아무리 약한 상대를 이겨도 최소 1 은 오른다", function()
			t:eq(Rank.mmrDelta(3000, 100), 1)
		end)

		--[[
			두 사람이 각자 자기 진행도에 적는다. 같은 시작 MMR 로 계산하면 한쪽이 얻은 만큼
			다른 쪽이 잃어야 한다 — 어긋나면 판마다 MMR 총량이 늘거나 준다.
		]]
		t:it("이긴 쪽이 얻은 만큼 진 쪽이 잃는다", function()
			local winner, ws = Rank.applyResult(fresh(), true, 1100, 950, LONG)
			local loser, ls = Rank.applyResult(fresh(), false, 950, 1100, LONG)
			t:truthy(winner and loser)
			t:eq(ws.mmr, -ls.mmr)
		end)

		t:it("바닥 아래로 내려가지 않는다", function()
			local low = fresh()
			low.mmr = Rank.Mmr.floor
			local updated = Rank.applyResult(low, false, Rank.Mmr.floor, 2000, LONG)
			t:eq(updated.mmr, Rank.Mmr.floor)
		end)
	end)

	--==================================================================
	t:describe("랭크 점수", function()
		t:it("이기면 오르고 지면 덜 내린다", function()
			t:truthy(Rank.Points.win > Rank.Points.loss, "반반 이기는 사람도 천천히 올라야 합니다")

			local start = fresh()
			start.rankPoints = 100
			local won = Rank.applyResult(start, true, 1000, 1000, LONG)
			local lost = Rank.applyResult(start, false, 1000, 1000, LONG)
			t:eq(won.rankPoints, 100 + Rank.Points.win)
			t:eq(lost.rankPoints, 100 - Rank.Points.loss)
		end)

		t:it("0 아래로 내려가지 않는다", function()
			local updated, summary = Rank.applyResult(fresh(), false, 1000, 1000, LONG)
			t:eq(updated.rankPoints, 0)
			t:eq(summary.points, 0)
		end)

		t:it("티어 경계를 넘으면 승급으로 알린다", function()
			local start = fresh()
			start.rankPoints = Rank.Tiers[2].points - 1
			local _, summary = Rank.applyResult(start, true, 1000, 1000, LONG)
			t:truthy(summary.promoted)
			t:truthy(Rank.describe(summary):find("승급", 1, true), Rank.describe(summary))
		end)

		t:it("경계 아래로 내려가면 강등으로 알린다", function()
			local start = fresh()
			start.rankPoints = Rank.Tiers[2].points
			local _, summary = Rank.applyResult(start, false, 1000, 1000, LONG)
			t:truthy(summary.demoted)
			t:truthy(Rank.describe(summary):find("강등", 1, true), Rank.describe(summary))
		end)

		t:it("알림에 MMR 을 말하지 않는다", function()
			local _, summary = Rank.applyResult(fresh(), true, 1000, 1000, LONG)
			local text = Rank.describe(summary)
			t:falsy(text:find("MMR", 1, true), text)
			t:falsy(text:find(tostring(Rank.Mmr.initial + summary.mmr), 1, true), "숨은 점수가 새고 있습니다: " .. text)
		end)
	end)

	--==================================================================
	t:describe("짧은 판", function()
		t:it("짧은 판을 이긴 쪽은 아무것도 적지 않는다 — 부계정 농사", function()
			local updated, summary = Rank.applyResult(fresh(), true, 1000, 1000, SHORT)
			t:eq(updated, nil, "적을 것이 없어야 합니다")
			t:eq(summary.points, 0)
			t:truthy(summary.short)
			t:truthy(Rank.describe(summary):find("턴", 1, true), Rank.describe(summary))
		end)

		t:it("짧은 판을 진 쪽은 그대로 내린다 — 나가서 손해 피하기", function()
			local start = fresh()
			start.rankPoints = 100
			local updated = Rank.applyResult(start, false, 1000, 1000, SHORT)
			t:eq(updated.rankPoints, 100 - Rank.Points.loss)
			t:eq(updated.mmr, Rank.Mmr.initial - Rank.mmrDelta(1000, 1000))
			t:eq(updated.rankedLosses, 1, "나가도 패배로 셉니다")
		end)
	end)

	--==================================================================
	t:describe("전적과 저장값", function()
		t:it("승 · 패를 센다", function()
			local progress = fresh()
			progress = Rank.applyResult(progress, true, 1000, 1000, LONG)
			progress = Rank.applyResult(progress, true, 1000, 1000, LONG)
			progress = Rank.applyResult(progress, false, 1000, 1000, LONG)
			t:eq(progress.rankedWins, 2)
			t:eq(progress.rankedLosses, 1)
		end)

		t:it("다른 칸(캠페인 · 골드 · PvP 보상)을 지우지 않는다", function()
			local progress = { cleared = 3, gold = 250, pvpDay = 20404, pvpWins = 2 }
			local updated = Rank.applyResult(progress, true, 1000, 1000, LONG)
			t:eq(updated.cleared, 3)
			t:eq(updated.gold, 250)
			t:eq(updated.pvpWins, 2)
			t:allowed(Campaign.validateProgress(updated))
		end)

		t:it("원래 진행도를 고치지 않는다", function()
			local progress = fresh()
			Rank.applyResult(progress, true, 1000, 1000, LONG)
			t:eq(progress.rankPoints, nil)
		end)

		t:it("랭크 칸 모양이 틀리면 진행도 검사가 거부한다", function()
			for _, field in { "rankPoints", "mmr", "rankedWins", "rankedLosses" } do
				-- 결과를 지역 변수로 받는다. f(g(), x) 는 g 의 첫 값만 넘겨 사유를 잃는다(CLAUDE.md 함정)
				for _, value in { -1, 1.5 } do
					local bad = fresh()
					bad[field] = value
					local ok, reason = Campaign.validateProgress(bad)
					t:denied(ok, reason, field)
				end
			end
		end)
	end)
end
