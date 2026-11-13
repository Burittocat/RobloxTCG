--[[
	PvE 캠페인 — 스테이지 표와 진행도 규칙.

	Roblox API 를 전혀 쓰지 않는 순수 Luau 다. Matchmaking 과 같은 이유로 그렇게 뒀다 —
	"몇 번까지 열려 있나 · 이번 판으로 골드를 얼마 받나" 는 서버가 판정하는 것이지만,
	판정 자체에 DataStore 도 Player 도 필요 없다. 그래서 Studio 없이 테스트로 못 박는다
	(tests/specs/campaign.luau).

	덱은 **엔트리 모양**으로 적는다. 덱 편집·저장이 쓰는 모양과 같아서 Decks.validateEntries
	가 그대로 검사해 준다 — 스테이지 덱만 따로 검사하는 코드를 만들면 "편집기는 거부하는데
	캠페인은 통과하는" 덱이 생긴다.

	진행도 (DataStore 에 그대로 들어가는 모양)

	    { cleared = 3, gold = 250, pvpDay = 20404, pvpWins = 2 }

	pvpDay · pvpWins 는 PvP 승리 보상의 하루 상한을 세는 칸이다(아래 PvpReward).
	rankPoints · mmr · rankedWins · rankedLosses 는 PvP 랭크다(src/shared/Rank).
	없어도 된다 — 그 전부터 있던 저장값과 같은 모양이라 저장소 이름을 바꾸지 않았다.

	cleared 는 **깬 스테이지 중 가장 큰 번호**다. 목록이 아닌 이유: 스테이지는 순서대로만
	열리므로 3 을 깼다는 것은 1·2 도 깼다는 뜻이고, 그러면 목록은 같은 사실을 더 비싸게
	적는 것이 된다. 골드도 "번호 ≤ cleared 면 이미 받았다" 로 판정되어 따로 들 것이 없다.
]]

local Decks = require(script.Parent.Decks)
local AI = require(script.Parent.AI)

local Campaign = {}

--==========================================================================
-- 스테이지 표
--==========================================================================

--[[
	한 줄이 스테이지 하나다.

	  name        목록에 뜨는 이름
	  note        "이 상대는 무엇을 하는가" 한 줄. 덱을 고쳐 갈 단서를 주는 자리다
	  difficulty  AI.Difficulty — Easy 는 즉시시전으로 대응하지 않는다
	  life        상대 시작 라이프 (안 주면 Config.startingLife)
	  gold        **첫 클리어에만** 주는 보상
	  deck        60장. 엔트리 모양이라 덱 편집기와 같은 검사를 받는다

	난이도 곡선의 설계: 앞의 둘은 Easy 라 대응이 없다 — 즉시시전을 배우기 전에
	기본 전투를 끝까지 해 보는 구간이다. 3번부터 Normal 로 올린다. 상대 라이프는
	3번 25(Normal 로 처음 올라가는 칸이라 덜 줬다), 4번 30 이다. 마지막만 35 인데,
	카운터 덱은 판을 길게 끌기 때문에
	라이프를 더 주지 않으면 "대응당하다 보니 이미 끝나 있는" 판이 된다.

	플레이어 쪽 라이프는 손대지 않는다. 캠페인이 어려워야 하는 것은 상대가
	강해서지, 내 시작점이 깎여서가 아니다.
]]
Campaign.stages = {
	--[[
		1번은 **연습 상대**다. 여기서 막히면 캠페인이 시작되지도 않는다.

		처음에는 거석상(7/7)·거인(6/6)까지 넣었다가 뺐다. 스모크 테스트의 자동 조작
		(아무 켜진 것이나 누르는 수준)으로 세 판을 돌려 세 판 다 졌는데, 그건 테스트가
		서툰 게 아니라 **1번 스테이지가 처음 오는 사람에게 너무 세다**는 뜻이었다.
		튜토리얼 상대(Decks.tutorialFoe)와 같은 모양 — 코스트가 많고 생물이 작다 — 으로
		낮췄다. 태그는 하나도 없다. 태그 상대는 2번부터다.
	]]
	{
		name = "훈련병",
		note = "태그 없는 생물만 나온다. 소환하고 공격하는 것만으로 이긴다.",
		difficulty = AI.Difficulty.Easy,
		life = 20,
		gold = 50,
		deck = {
			{ id = "COST_BASIC", count = 40 },
			{ id = "CRE_SCOUT", count = 4 },
			{ id = "CRE_SQUIRE", count = 4 },
			{ id = "CRE_GUARD", count = 4 },
			{ id = "CRE_SCRIBE", count = 4 },
			{ id = "CRE_LANCER", count = 4 },
		},
	},
	{
		name = "매사냥꾼",
		note = "비행이 절반이다. 지상 생물로는 막을 수 없으니 원거리나 비행을 챙긴다.",
		difficulty = AI.Difficulty.Easy,
		life = 25,
		gold = 80,
		deck = {
			{ id = "COST_BASIC", count = 28 },
			{ id = "CRE_HAWK", count = 4 },
			{ id = "CRE_FALCONER", count = 4 },
			{ id = "CRE_WYVERN", count = 4 },
			{ id = "CRE_SCOUT", count = 4 },
			{ id = "CRE_SQUIRE", count = 4 },
			{ id = "CRE_SCRIBE", count = 4 },
			{ id = "SPL_INSIGHT", count = 4 },
			{ id = "SPL_WARCRY", count = 4 },
		},
	},
	{
		name = "방벽 수비대",
		note = "도발과 높은 생명력으로 버틴다. 때려서는 못 뚫으니 원거리로 무시하거나 제거한다.",
		difficulty = AI.Difficulty.Normal,
		--[[
			2026-11-13 낮췄다 — 거석상 4 → 2(그 자리에 코스트 2), 라이프 30 → 25.
			스타터 덱 · 보통 AI 의 도전자 승률이 51% 로, 4번(68%) · 5번(56%)보다 어려웠다.
			지금 70% — 2번(77%)과 4번 사이. 거석상 한 장이 승률을 10% 넘게 움직이므로
			(1장 80% · 0장 96%) 장수로만 맞추지 않고 라이프로 나머지를 맞췄다.
			재는 법: lune run tests/balance.luau -- --games 2000 --stage 3
		]]
		life = 25,
		gold = 120,
		deck = {
			{ id = "COST_BASIC", count = 28 },
			{ id = "CRE_BULWARK", count = 4 },
			{ id = "CRE_SENTRY", count = 4 },
			{ id = "CRE_SKYPIERCER", count = 4 },
			{ id = "CRE_GUARD", count = 4 },
			{ id = "CRE_TITAN", count = 2 },
			{ id = "CRE_SCRIBE", count = 4 },
			{ id = "SPL_BULWARK_UP", count = 4 },
			{ id = "SPL_MEND", count = 4 },
			{ id = "SPL_REINFORCE", count = 2 },
		},
	},
	{
		name = "장궁 부대",
		note = "원거리가 도발을 무시하고 생물을 골라 죽인다. 방패 뒤에 숨는 전략이 통하지 않는다.",
		difficulty = AI.Difficulty.Normal,
		life = 30,
		gold = 160,
		deck = {
			{ id = "COST_BASIC", count = 26 },
			{ id = "CRE_ARCHER", count = 4 },
			{ id = "CRE_SKYPIERCER", count = 4 },
			{ id = "CRE_SCOUT", count = 4 },
			{ id = "CRE_HERALD", count = 4 },
			{ id = "CRE_SCRIBE", count = 4 },
			{ id = "SPL_SNIPE", count = 4 },
			{ id = "SPL_FIREBOLT", count = 4 },
			{ id = "SPL_EXECUTE", count = 2 },
			{ id = "SPL_INSIGHT", count = 4 },
		},
	},
	{
		name = "주문 파쇄자",
		note = "즉시시전으로 대응한다. 중요한 카드를 먼저 내서 대응을 뽑아낸 뒤에 본진을 낸다.",
		difficulty = AI.Difficulty.Normal,
		life = 35,
		gold = 250,
		deck = {
			{ id = "COST_BASIC", count = 26 },
			{ id = "CRE_SCRIBE", count = 4 },
			{ id = "CRE_HERALD", count = 4 },
			{ id = "CRE_RAIDER", count = 4 },
			{ id = "CRE_BERSERKER", count = 4 },
			{ id = "CRE_WYVERN", count = 2 },
			{ id = "SPL_NEGATE", count = 4 },
			{ id = "SPL_RECALL", count = 4 },
			{ id = "SPL_SHOCK", count = 4 },
			{ id = "SPL_SNIPE", count = 2 },
			{ id = "SPL_ARCHIVE", count = 2 },
		},
	},
}

function Campaign.count()
	return #Campaign.stages
end

function Campaign.get(index)
	if type(index) ~= "number" or index % 1 ~= 0 then
		return nil
	end
	return Campaign.stages[index]
end

-- 이 스테이지에서 AI 가 쥘 덱 (목록 모양). 없는 번호면 nil.
function Campaign.deckFor(index)
	local stage = Campaign.get(index)
	if not stage then
		return nil
	end
	return Decks.toList(stage.deck)
end

--==========================================================================
-- 진행도
--==========================================================================

function Campaign.newProgress()
	return { cleared = 0, gold = 0 }
end

--[[
	진행도 사본. **필드를 하나씩 옮겨 적지 않는다** — 그러면 필드가 늘어날 때마다
	(pvpDay · pvpWins 가 그랬다) 옮겨 적는 곳마다 빠뜨려서 조용히 지워진다.
]]
local function copy(progress)
	local out = {}
	for key, value in progress do
		out[key] = value
	end
	out.cleared = out.cleared or 0
	out.gold = out.gold or 0
	return out
end

--[[
	저장소에서 온 값이 쓸 수 있는 모양인가. -> ok, reason

	저장된 값을 믿지 않는 이유는 DeckStore 와 같다 — 스테이지를 지우거나 줄이면
	옛 저장의 cleared 가 표 길이를 넘는다. 그대로 쓰면 목록을 그리다가 nil 에서 죽는다.
]]
function Campaign.validateProgress(value)
	if type(value) ~= "table" then
		return false, "진행도가 테이블이 아닙니다"
	end

	for _, field in { "cleared", "gold" } do
		local number = value[field]
		if type(number) ~= "number" or number % 1 ~= 0 or number < 0 then
			return false, ("'%s' 가 0 이상의 정수가 아닙니다"):format(field)
		end
	end

	if value.cleared > Campaign.count() then
		return false, ("깬 스테이지가 %d 인데 표에는 %d 개뿐입니다"):format(value.cleared, Campaign.count())
	end

	--[[
		PvP 보상 기록과 랭크(Rank 모듈)는 없어도 된다(그 전부터 있던 저장값). 있으면 모양은
		맞아야 한다. 랭크 칸 검사를 Rank 에 두지 않은 것은 Rank 가 이 모듈을 require 해서다.
	]]
	for _, field in { "pvpDay", "pvpWins", "rankPoints", "mmr", "rankedWins", "rankedLosses" } do
		local number = value[field]
		if number ~= nil and (type(number) ~= "number" or number % 1 ~= 0 or number < 0) then
			return false, ("'%s' 가 0 이상의 정수가 아닙니다"):format(field)
		end
	end

	return true
end

-- 이 번호를 지금 고를 수 있는가. 1번은 항상 열려 있고, 그 뒤는 앞을 깨야 열린다.
function Campaign.isUnlocked(progress, index)
	local stage = Campaign.get(index)
	if not stage then
		return false
	end
	return index <= (progress.cleared or 0) + 1
end

--[[
	이 스테이지를 깼다. -> 새 진행도, 이번에 받은 골드

	**원래 진행도를 고치지 않고 새 테이블을 돌려준다.** 저장에 실패했을 때 부르는 쪽이
	옛 값으로 되돌릴 수 있어야 하는데, 제자리에서 고쳐버리면 되돌릴 것이 남지 않는다.

	골드는 첫 클리어에만 준다. 재도전으로 같은 스테이지를 계속 도는 것이 가장 빠른
	수급 경로가 되면, 캠페인은 진도가 아니라 노가다가 된다.
]]
function Campaign.applyClear(progress, index)
	local stage = Campaign.get(index)
	local updated = copy(progress)

	if not stage or index > updated.cleared + 1 then
		-- 열리지도 않은 번호. 부르는 쪽이 막았어야 하는 것이라 진행도는 그대로 둔다.
		return updated, 0
	end

	if index <= updated.cleared then
		return updated, 0 -- 이미 깬 곳. 다시 깨도 보상은 없다
	end

	updated.cleared = index
	updated.gold += stage.gold
	return updated, stage.gold
end

--==========================================================================
-- PvP 승리 보상 (★ 기획서 미확정 — docs/open-questions.md)
--==========================================================================

--[[
	캠페인 골드는 첫 클리어에만 나와서 다 합쳐도 팩 여섯 봉이다. 그 뒤로 컬렉션이 멈추지
	않게 하는 수급처가 PvP 승리다.

	  gold      한 판 이기면 받는 골드
	  perDay    하루에 보상받는 승리 수. 4 × 25 = 100 = 하루 팩 한 봉
	  minTurns  이 턴 수(양쪽 턴을 합친 state.turn)가 안 된 판은 보상이 없다

	제한이 둘인 이유는 **부계정 농사** 다. 계정 둘로 큐에 서서 한쪽이 바로 항복하면
	보상이 무한히 나온다. 하루 상한이 총량을 막고, 최소 턴이 "들어오자마자 항복" 을 막는다.
	정상적으로 이긴 판이 일찍 끝나서(상대가 2턴 만에 나감) 못 받는 것은 감수한다.

	골드는 진행도의 gold(= 번 합)에 더한다. 화폐를 새로 만들지 않는다 — 팩은 이미
	"번 합 − 쓴 합" 으로 잔액을 계산하고 있다(Collection 머리말).

	날짜는 UTC 기준 `os.time() // 86400`. 서버마다 시계 기준이 같아야 하고, 사람마다
	시간대를 따지면 시간대를 바꿔 하루를 두 번 사는 길이 생긴다.
]]
Campaign.PvpReward = table.freeze({
	gold = 25,
	perDay = 4,
	minTurns = 4,
})

function Campaign.dayOf(unixTime)
	return math.floor(unixTime / 86400)
end

-- 오늘 이미 보상받은 승리 수. 날짜가 바뀌었으면 0 이다.
function Campaign.pvpWinsToday(progress, day)
	if progress.pvpDay ~= day then
		return 0
	end
	return progress.pvpWins or 0
end

--[[
	PvP 한 판을 이겼다. -> 새 진행도, 받은 골드, 못 받았다면 이유

	applyClear 와 같이 원래 진행도를 고치지 않는다.
]]
function Campaign.applyPvpWin(progress, day, turns)
	local updated = copy(progress)
	local reward = Campaign.PvpReward

	if (tonumber(turns) or 0) < reward.minTurns then
		return updated, 0, ("%d턴 안에 끝난 판은 보상이 없습니다"):format(reward.minTurns)
	end

	local wins = Campaign.pvpWinsToday(progress, day)
	if wins >= reward.perDay then
		return updated, 0, ("오늘 받을 수 있는 승리 보상(%d판)을 다 받았습니다"):format(reward.perDay)
	end

	updated.pvpDay = day
	updated.pvpWins = wins + 1
	updated.gold += reward.gold
	return updated, reward.gold
end

--==========================================================================
-- 화면에 내려보낼 모양
--==========================================================================

--[[
	목록 화면이 그릴 것. 배열이고 각 칸은 문자열 키 딕셔너리라 그대로 실어 보낼 수 있다
	(Net 주석의 "숫자 키 딕셔너리는 조용히 모양이 바뀐다" 참조).

	덱은 싣지 않는다. 60장 배열 다섯 개를 매번 보내는 것도 낭비지만, 무엇보다
	**상대 덱은 플레이어가 알면 안 되는 정보**다.
]]
function Campaign.list(progress)
	local out = {}

	for index, stage in Campaign.stages do
		table.insert(out, {
			index = index,
			name = stage.name,
			note = stage.note,
			difficulty = stage.difficulty,
			life = stage.life,
			gold = stage.gold,
			unlocked = Campaign.isUnlocked(progress, index),
			cleared = index <= (progress.cleared or 0),
		})
	end

	return out
end

return Campaign
