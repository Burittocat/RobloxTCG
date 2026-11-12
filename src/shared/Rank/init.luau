--[[
	PvP 랭크 — 보이는 랭크 점수와 숨은 MMR.

	Roblox API 를 쓰지 않는 순수 Luau 다(Campaign · Collection 과 같은 이유). 판정은 서버가
	하지만 계산 자체에는 DataStore 도 Player 도 필요 없어서 Studio 없이 테스트로 못 박는다
	(tests/specs/rank.luau).

	--------------------------------------------------------------------------
	점수가 둘인 이유

	  랭크 점수 (rankPoints)  **보인다.** 이기면 오르고 지면 조금 내린다. 티어(브론즈 · 실버 …)가
	                          이 점수로 정해진다. 꾸준히 하면 오르는 "진도" 다
	  MMR (mmr)               **안 보인다.** 실력 추정치(Elo). 매칭에만 쓴다 — 비슷한 MMR 끼리
	                          먼저 붙인다(Matchmaking.plan)

	하나로 합치면 둘 중 하나가 망가진다. 랭크를 Elo 로만 두면 실력이 멈춘 사람은 영원히 같은
	숫자를 보고, 매칭을 랭크 점수로 하면 "많이 한 사람" 이 "잘하는 사람" 과 붙는다.
	(2026-11-12 사용자 방향: "승리로 얻는 점수로 랭크, MMR 기반 매칭")

	--------------------------------------------------------------------------
	짧은 판 (★ docs/open-questions.md)

	Campaign.PvpReward.minTurns(4) 턴이 안 돼 끝난 판 — 사실상 항복이나 이탈이다.

	  이긴 쪽  아무것도 적지 않는다(점수 · MMR · 승 수)  → 부계정으로 바로 져 주는 농사를 막는다
	  진 쪽    **그대로 내린다**        → "질 것 같으면 나가기" 로 손해를 피하는 길을 막는다

	골드 보상의 짧은 판 규칙과 같은 기준을 쓴다. 기준이 둘이면 "골드는 받았는데 점수는
	안 오른" 판이 생겨서 설명이 길어진다.

	--------------------------------------------------------------------------
	저장 — 캠페인 진행도(`CampaignProgress_v1`)에 두 칸을 더한다

	    { cleared, gold, pvpDay, pvpWins, rankPoints = 245, mmr = 1032, rankedWins = 31, rankedLosses = 24 }

	rankedWins · rankedLosses 는 프로필 화면의 전적이다.

	없어도 된다. 옛 저장값은 "아직 랭크전을 안 한 사람"(점수 0, MMR 1000) 이다.
	PvP 골드 보상과 같은 저장값이라 같은 이유(대전 서버가 저장된 값 위에서 고친다)를 따른다.
]]

local Campaign = require(script.Parent.Campaign)

local Rank = {}

--==========================================================================
-- 수치 (★ 기획서 미확정 — docs/open-questions.md)
--==========================================================================

--[[
	win    이기면 오르는 랭크 점수
	loss   지면 내리는 랭크 점수. 이기는 것보다 작다 — 반반 이기는 사람도 천천히 오른다.
	       랭크가 "진도" 로 읽히려면 그래야 한다. 실력은 MMR 이 따로 잰다
	floor  랭크 점수는 이 아래로 안 내려간다
]]
Rank.Points = table.freeze({
	win = 20,
	loss = 10,
	floor = 0,
})

--[[
	티어. points 이상이면 그 티어다. 아래에서 위 순서.
	color 는 화면 글자 색(0~255) — Roblox 자료형을 안 쓰려고 숫자 셋이다.

	간격이 위로 갈수록 넓다. 승률 50% 면 한 판에 평균 +5 라, 브론즈→실버는 40판,
	다이아몬드→마스터는 120판쯤이다.
]]
Rank.Tiers = table.freeze({
	table.freeze({ id = "Bronze", name = "브론즈", points = 0, color = { 205, 135, 80 } }),
	table.freeze({ id = "Silver", name = "실버", points = 200, color = { 196, 206, 222 } }),
	table.freeze({ id = "Gold", name = "골드", points = 500, color = { 247, 206, 112 } }),
	table.freeze({ id = "Platinum", name = "플래티넘", points = 900, color = { 110, 214, 196 } }),
	table.freeze({ id = "Diamond", name = "다이아몬드", points = 1400, color = { 126, 186, 250 } }),
	table.freeze({ id = "Master", name = "마스터", points = 2000, color = { 214, 132, 250 } }),
})

--[[
	MMR (Elo).

	initial  처음 MMR
	k        한 판에 움직일 수 있는 최대치. 비슷한 상대면 그 절반쯤이 오간다
	floor    이 아래로는 안 내려간다 — 너무 낮아지면 다시 올라오는 데 수백 판이 든다
]]
Rank.Mmr = table.freeze({
	initial = 1000,
	k = 32,
	floor = 100,
})

--==========================================================================
-- 읽기
--==========================================================================

function Rank.pointsOf(progress)
	return (progress and tonumber(progress.rankPoints)) or 0
end

function Rank.mmrOf(progress)
	return (progress and tonumber(progress.mmr)) or Rank.Mmr.initial
end

-- 이 점수의 티어. -> tier, 다음 티어(마스터면 nil)
function Rank.tierOf(points)
	local current, nextTier = Rank.Tiers[1], nil
	for index, tier in Rank.Tiers do
		if points >= tier.points then
			current = tier
			nextTier = Rank.Tiers[index + 1]
		end
	end
	return current, nextTier
end

-- "실버 245점" — 시작 화면 · 결과 알림이 같은 글자를 쓴다.
function Rank.label(points)
	return ("%s %d점"):format(Rank.tierOf(points).name, points)
end

--==========================================================================
-- MMR 계산
--==========================================================================

-- a 가 b 를 이길 확률(Elo).
function Rank.expected(a, b)
	return 1 / (1 + 10 ^ ((b - a) / 400))
end

--[[
	이긴 쪽 MMR 변화량. 진 쪽은 같은 만큼 내린다. 최소 1 — 아무리 약한 상대를 이겨도
	0 이 되면 "이겼는데 아무 일도 없는" 판이 생긴다.
]]
function Rank.mmrDelta(winnerMmr, loserMmr)
	local raw = Rank.Mmr.k * (1 - Rank.expected(winnerMmr, loserMmr))
	return math.max(1, math.floor(raw + 0.5))
end

--==========================================================================
-- 한 판 결과 적용
--==========================================================================

local function copy(progress)
	local out = {}
	for key, value in progress or {} do
		out[key] = value
	end
	return out
end

-- 짧은 판인가 (머리말 "짧은 판").
function Rank.isShort(turns)
	return (tonumber(turns) or 0) < Campaign.PvpReward.minTurns
end

--[[
	한 판의 결과를 한 사람의 진행도에 적는다. -> 새 진행도, 요약

	    won           이 사람이 이겼나
	    opponentMmr   **판이 시작될 때** 상대 MMR. 끝난 뒤에 다시 읽지 않는 이유 —
	                  상대 쪽 쓰기가 먼저 끝나면 이미 바뀐 값으로 계산하게 되어,
	                  두 사람의 변화량이 서로 달라진다
	    myMmr         판이 시작될 때 내 MMR. 변화량 계산에만 쓰고, 적는 것은 저장된 값 위다

	요약 = { points = 랭크 점수 변화, mmr = MMR 변화, before = 전 점수, after = 후 점수,
	         promoted = 티어가 올랐나, demoted = 내렸나, short = 짧은 판이었나 }

	**짧은 판을 이긴 쪽은 새 진행도가 nil 이다** — 적을 것이 없다. 전적(승 수)도 안 센다.
	세면 부계정 농사로 프로필의 승 수를 부풀릴 수 있다. 요약은 그래도 돌려준다(알림용).

	원래 진행도는 고치지 않는다(Campaign.applyClear 와 같은 이유).
]]
function Rank.applyResult(progress, won, myMmr, opponentMmr, turns)
	local updated = copy(progress)
	local short = Rank.isShort(turns)

	local beforePoints = Rank.pointsOf(progress)
	local beforeMmr = Rank.mmrOf(progress)

	if won and short then
		return nil,
			{
				points = 0,
				mmr = 0,
				before = beforePoints,
				after = beforePoints,
				promoted = false,
				demoted = false,
				short = true,
			}
	end

	local pointsChange, mmrChange = 0, 0
	local delta = Rank.mmrDelta(won and myMmr or opponentMmr, won and opponentMmr or myMmr)

	if won then
		pointsChange = Rank.Points.win
		mmrChange = delta
	else
		pointsChange = -Rank.Points.loss
		mmrChange = -delta
	end

	local afterPoints = math.max(Rank.Points.floor, beforePoints + pointsChange)
	local afterMmr = math.max(Rank.Mmr.floor, beforeMmr + mmrChange)

	updated.rankPoints = afterPoints
	updated.mmr = afterMmr

	-- 전적. 진 판은 짧아도 센다(나가도 패배다). 짧은 판의 승리는 위에서 이미 걸렀다.
	if won then
		updated.rankedWins = (progress and progress.rankedWins or 0) + 1
	else
		updated.rankedLosses = (progress and progress.rankedLosses or 0) + 1
	end

	local beforeTier = Rank.tierOf(beforePoints)
	local afterTier = Rank.tierOf(afterPoints)

	return updated,
		{
			points = afterPoints - beforePoints,
			mmr = afterMmr - beforeMmr,
			before = beforePoints,
			after = afterPoints,
			promoted = afterTier.points > beforeTier.points,
			demoted = afterTier.points < beforeTier.points,
			short = short,
		}
end

--[[
	결과 알림 한 줄. 화면에는 **MMR 을 말하지 않는다** — 숨은 점수다.
]]
function Rank.describe(summary)
	local tier = Rank.tierOf(summary.after)

	if summary.promoted then
		return ("승급! %s — 랭크 점수 %+d (%d점)"):format(tier.name, summary.points, summary.after)
	end
	if summary.demoted then
		return ("강등 — %s, 랭크 점수 %+d (%d점)"):format(tier.name, summary.points, summary.after)
	end
	if summary.points == 0 and summary.short then
		return ("%d턴 안에 끝난 판은 랭크 점수가 오르지 않습니다 (%s)"):format(
			Campaign.PvpReward.minTurns,
			Rank.label(summary.after)
		)
	end
	return ("랭크 점수 %+d — %s"):format(summary.points, Rank.label(summary.after))
end

--[[
	저장값 모양 검사는 Campaign.validateProgress 가 한다(rankPoints · mmr · rankedWins ·
	rankedLosses 도 거기 목록에 있다). 이 모듈이 Campaign 을 require 하므로 거꾸로 부르면
	순환이 된다.
]]

return Rank
