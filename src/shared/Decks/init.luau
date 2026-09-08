--[[
	덱 프리셋.

	캠페인 상대 덱, 튜토리얼 덱, 테스트용 덱을 여기에 모은다.
	모두 정식 규칙(60장, 같은 카드 최대 4장)을 지키므로 strictDeck 검증을 통과한다.
]]

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

return Decks
