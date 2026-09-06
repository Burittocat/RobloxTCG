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

	코스트 24 / 생물 30 / 마법 6.
	5개 키워드가 전부 들어 있어 룰을 한 판에 다 겪어볼 수 있게 짰다.
]]
function Decks.starter()
	return build({
		{ "COST_BASIC", 24 },

		{ "CRE_SCOUT", 4 }, -- 1코 1/2
		{ "CRE_GUARD", 4 }, -- 2코 2/3
		{ "CRE_HAWK", 4 }, -- 2코 2/1 비행
		{ "CRE_RAIDER", 4 }, -- 3코 3/2 신속
		{ "CRE_BULWARK", 4 }, -- 3코 1/6 도발
		{ "CRE_ARCHER", 4 }, -- 3코 4/2 원거리
		{ "CRE_SKYPIERCER", 2 }, -- 4코 3/4 원거리+도발
		{ "CRE_WYVERN", 2 }, -- 5코 4/4 비행+신속
		{ "CRE_BRUTE", 2 }, -- 5코 6/6

		{ "SPL_SHOCK", 2 }, -- 1코 즉시 2피해
		{ "SPL_FIREBOLT", 2 }, -- 2코 3피해
		{ "SPL_NEGATE", 1 }, -- 2코 즉시 무효화
		{ "SPL_WARCRY", 1 }, -- 1코 +2/+0 및 신속
	})
end

return Decks
