--[[
	덱 — 프리셋과, 사람이 편집한 덱을 다루는 공통 함수들.

	덱의 두 가지 모양
	  목록(list)     { "COST_BASIC", "COST_BASIC", "CRE_HAWK", ... }  60개 — 룰 엔진이 먹는 모양
	  엔트리(entries) { { id = "COST_BASIC", count = 24 }, ... }      — 저장·전송하는 모양

	엔트리로 저장하고 전송하는 이유: 60칸 배열을 매번 실어 나르면 낭비이기도 하지만,
	무엇보다 **사람이 읽을 수 있어야** 저장된 값을 보고 문제를 짚을 수 있다.
	엔트리는 Roblox 직렬화가 안전하게 다루는 모양이기도 하다(문자열 키 딕셔너리의 배열).

	검증은 한 곳(CardDef.validateDeck)에서 한다 — 편집 화면·저장·매치 시작이 각자
	검사하면 "화면에서는 됐는데 저장이 거부" 같은 것이 생긴다.
]]

local Rules = require(script.Parent.Rules)

local Decks = {}

-- { cardId, 매수 } 목록을 평평한 배열로 편다.
local function build(entries)
	local out = {}
	for _, entry in entries do
		for _ = 1, entry[2] do
			table.insert(out, entry[1])
		end
	end
	return out
end

--[[
	스타터 덱 (60장)

	코스트 24 / 생물 24 / 마법 12.

	2026-09-09 개편. 이전 덱은 드로우가 **한 장도 없어서**, AI 자기대국 60판 기준
	판이 평균 30턴인데 덱은 21장밖에 쓰이지 않았다. 카드를 못 보니 손이 마르고,
	마른 손으로 톱덱만 하다 보니 판이 길어지는 구조였다.

	그래서 드로우를 8장 넣었다(통찰 4 · 종군 서기 4). 코스트 24장은 그대로 두었다 —
	기획서의 권장 범위(24~30)라서 여기서 임의로 줄일 자리가 아니다. 대신 생물의
	고코스트 쪽을 덜어 그 자리를 만들었다.

	숫자는 `lune run tests/balance.luau` 로 잰다. 결과는 README "덱 순환" 절.
	5개 키워드는 여전히 전부 들어 있다(신속·비행·도발·원거리·즉시시전).
]]
--==========================================================================
-- 목록 ↔ 엔트리
--==========================================================================

-- 목록 -> 엔트리 (카드 등장 순서를 유지한다)
function Decks.toEntries(list)
	local order, counts = {}, {}

	for _, cardId in list do
		if counts[cardId] == nil then
			counts[cardId] = 0
			table.insert(order, cardId)
		end
		counts[cardId] += 1
	end

	local out = {}
	for _, cardId in order do
		table.insert(out, { id = cardId, count = counts[cardId] })
	end
	return out
end

-- 엔트리 -> 목록
function Decks.toList(entries)
	local out = {}
	for _, entry in entries or {} do
		for _ = 1, entry.count or 0 do
			table.insert(out, entry.id)
		end
	end
	return out
end

--[[
	사람이 편집한 덱이 규칙에 맞는가. -> ok, reason

	모양부터 본다. 저장된 값이나 클라이언트가 보낸 값은 **무엇이든 들어올 수 있다** —
	숫자가 아닌 매수, 음수, 없는 카드 id, 배열이 아닌 것. 여기서 걸러내지 않으면
	그 값이 룰 엔진까지 들어가 판 한가운데서 터진다.
]]
function Decks.validateEntries(entries)
	if type(entries) ~= "table" then
		return false, "덱이 배열이 아닙니다"
	end

	local seen = {}
	for _, entry in entries do
		if type(entry) ~= "table" or type(entry.id) ~= "string" then
			return false, "덱 항목의 모양이 잘못됐습니다"
		end
		if type(entry.count) ~= "number" or entry.count < 0 or entry.count % 1 ~= 0 then
			return false, ("'%s' 의 매수가 잘못됐습니다"):format(entry.id)
		end
		if seen[entry.id] then
			return false, ("'%s' 가 두 번 적혀 있습니다"):format(entry.id)
		end
		seen[entry.id] = true
	end

	return Rules.CardDef.validateDeck(Decks.toList(entries), Rules.Registry.get, true)
end

-- 이 카드를 몇 장까지 넣을 수 있는가 (코스트 카드는 제한 없음).
function Decks.maxCopies(cardId)
	local def = Rules.Registry.get(cardId)
	if not def then
		return 0
	end
	if Rules.Config.copyLimitExemptTypes[def.type] then
		return Rules.Config.deckSize
	end
	return Rules.Config.maxCopiesPerCard
end

--==========================================================================
-- 프리셋
--==========================================================================

function Decks.starter()
	return build({
		{ "COST_BASIC", 24 },

		-- 드로우 — 덱이 도는 속도
		{ "SPL_INSIGHT", 4 }, -- 1코 즉시 1장
		{ "CRE_SCRIBE", 4 }, -- 2코 1/2, 소환 시 1장

		-- 생물
		{ "CRE_SQUIRE", 3 }, -- 1코 2/1
		{ "CRE_GUARD", 3 }, -- 2코 2/3
		{ "CRE_HAWK", 3 }, -- 2코 2/1 비행
		{ "CRE_RAIDER", 3 }, -- 3코 3/2 신속
		{ "CRE_ARCHER", 3 }, -- 3코 4/2 원거리
		{ "CRE_BULWARK", 2 }, -- 3코 1/6 도발
		{ "CRE_LANCER", 1 }, -- 4코 4/4
		{ "CRE_BERSERKER", 1 }, -- 4코 5/3 신속
		{ "CRE_BRUTE", 1 }, -- 5코 6/6

		-- 마법
		{ "SPL_SHOCK", 2 }, -- 1코 즉시 2피해
		{ "SPL_SNIPE", 2 }, -- 2코 즉시 생물 2피해
		{ "SPL_FIREBOLT", 1 }, -- 2코 3피해
		{ "SPL_WARCRY", 1 }, -- 1코 +2/+0 및 신속
		{ "SPL_NEGATE", 1 }, -- 2코 즉시 무효화
		{ "SPL_ARCHIVE", 1 }, -- 4코 3장 드로우
	})
end

-- 새 사람이 처음 받는 덱 (엔트리 모양)
function Decks.starterEntries()
	return Decks.toEntries(Decks.starter())
end

return Decks
