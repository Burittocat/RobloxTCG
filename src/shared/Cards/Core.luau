--[[
	기본 카드셋 (Core).

	5개 키워드(신속/비행/도발/원거리/즉시시전)를 전부 굴려보기 위한 초기 세트다.
	이름은 자리표시자 — Roblox IP 를 붙이는 건 별도 작업이다.

	카드 스키마
	  공통    id, name, type, cost, keywords?, text?, rarity?
	  생물    power(공격력), toughness(체력)
	  마법    speed("Normal"|"Instant"), effects[], noDefensePhase?
	  코스트  produces? (기본 1)
]]

local CardType = { Cost = "Cost", Creature = "Creature", Spell = "Spell" }
local KW = {
	Haste = "Haste",
	Flying = "Flying",
	Taunt = "Taunt",
	Ranged = "Ranged",
	Instant = "Instant",
}

return {
	--======================================================================
	-- 코스트
	--======================================================================
	{
		id = "COST_BASIC",
		name = "에너지 코어",
		type = CardType.Cost,
		text = "탭하여 코스트 1 을 얻는다.",
		rarity = "Common",
	},

	--======================================================================
	-- 생물 — 바닐라 커브
	--======================================================================
	{
		id = "CRE_SCOUT",
		name = "신참 정찰병",
		type = CardType.Creature,
		cost = 1,
		power = 1,
		toughness = 2,
		rarity = "Common",
	},
	{
		id = "CRE_GUARD",
		name = "성문 경비병",
		type = CardType.Creature,
		cost = 2,
		power = 2,
		toughness = 3,
		rarity = "Common",
	},
	{
		id = "CRE_BRUTE",
		name = "돌주먹 거인",
		type = CardType.Creature,
		cost = 5,
		power = 6,
		toughness = 6,
		rarity = "Rare",
	},

	--======================================================================
	-- 생물 — 신속
	--======================================================================
	{
		id = "CRE_RAIDER",
		name = "질풍 습격자",
		type = CardType.Creature,
		cost = 3,
		power = 3,
		toughness = 2,
		keywords = { KW.Haste },
		text = "신속 — 소환한 턴에 바로 공격할 수 있고, 수비준비 페이즈에도 언탭으로 등장한다.",
		rarity = "Uncommon",
	},

	--======================================================================
	-- 생물 — 비행
	--======================================================================
	{
		id = "CRE_HAWK",
		name = "창공의 매",
		type = CardType.Creature,
		cost = 2,
		power = 2,
		toughness = 1,
		keywords = { KW.Flying },
		text = "비행 — 지상 생물은 이 생물을 공격하거나 방어할 수 없다.",
		rarity = "Common",
	},
	{
		id = "CRE_WYVERN",
		name = "폭풍 비룡",
		type = CardType.Creature,
		cost = 5,
		power = 4,
		toughness = 4,
		keywords = { KW.Flying, KW.Haste },
		text = "비행, 신속",
		rarity = "Epic",
	},

	--======================================================================
	-- 생물 — 도발
	--======================================================================
	{
		id = "CRE_BULWARK",
		name = "강철 방벽",
		type = CardType.Creature,
		cost = 3,
		power = 1,
		toughness = 6,
		keywords = { KW.Taunt },
		text = "도발 — 이 생물이 전장에 있는 한 상대는 플레이어를 직접 공격할 수 없다.",
		rarity = "Uncommon",
	},

	--======================================================================
	-- 생물 — 원거리
	--======================================================================
	{
		id = "CRE_ARCHER",
		name = "장궁 사수",
		type = CardType.Creature,
		cost = 3,
		power = 4,
		toughness = 2,
		keywords = { KW.Ranged },
		text = "원거리 — 비행을 상대할 수 있고 도발을 무시한다. 플레이어 직접 공격 시 데미지 절반.",
		rarity = "Uncommon",
	},
	{
		id = "CRE_SKYPIERCER",
		name = "하늘꿰뚫이",
		type = CardType.Creature,
		cost = 4,
		power = 3,
		toughness = 4,
		keywords = { KW.Ranged, KW.Taunt },
		text = "원거리, 도발",
		rarity = "Rare",
	},

	--======================================================================
	-- 마법 — 일반
	--======================================================================
	{
		id = "SPL_FIREBOLT",
		name = "화염 화살",
		type = CardType.Spell,
		cost = 2,
		speed = "Normal",
		text = "생물 하나 또는 플레이어에게 3 피해.",
		effects = {
			{ kind = "Damage", amount = 3, target = "CreatureOrPlayer" },
		},
		rarity = "Common",
	},
	{
		id = "SPL_RALLY",
		name = "전열 정비",
		type = CardType.Spell,
		cost = 2,
		speed = "Normal",
		text = "카드 2 장을 뽑는다.",
		effects = {
			{ kind = "Draw", amount = 2 },
		},
		rarity = "Common",
	},
	{
		id = "SPL_WARCRY",
		name = "돌격 나팔",
		type = CardType.Spell,
		cost = 1,
		speed = "Normal",
		text = "아군 생물 하나가 +2/+0 과 신속을 얻는다.",
		effects = {
			{ kind = "Buff", power = 2, toughness = 0, target = "AllyCreature" },
			{ kind = "GrantKeyword", keyword = "Haste", target = "AllyCreature" },
		},
		rarity = "Common",
	},
	{
		id = "SPL_EXECUTE",
		name = "처형 명령",
		type = CardType.Spell,
		cost = 4,
		speed = "Normal",
		text = "적 생물 하나를 파괴한다.",
		noDefensePhase = true,
		effects = {
			{ kind = "Destroy", target = "EnemyCreature" },
		},
		rarity = "Rare",
	},

	--======================================================================
	-- 마법 — 즉시시전
	--======================================================================
	{
		id = "SPL_NEGATE",
		name = "주문 파쇄",
		type = CardType.Spell,
		cost = 2,
		speed = "Instant",
		keywords = { KW.Instant },
		text = "즉시시전 — 시전 중인 마법이나 소환을 무효화한다.",
		effects = {
			{ kind = "Counter", target = "StackItem" },
		},
		rarity = "Rare",
	},
	{
		id = "SPL_RECALL",
		name = "귀환의 소용돌이",
		type = CardType.Spell,
		cost = 3,
		speed = "Instant",
		keywords = { KW.Instant },
		text = "즉시시전 — 소환 중인 생물을 덱 맨 위로 되돌린다.",
		effects = {
			{ kind = "ToDeck", position = "top", target = "StackItem" },
		},
		rarity = "Epic",
	},
	{
		id = "SPL_SHOCK",
		name = "감전",
		type = CardType.Spell,
		cost = 1,
		speed = "Instant",
		keywords = { KW.Instant },
		text = "즉시시전 — 생물 하나 또는 플레이어에게 2 피해.",
		effects = {
			{ kind = "Damage", amount = 2, target = "CreatureOrPlayer" },
		},
		rarity = "Common",
	},
	{
		id = "SPL_BULWARK_UP",
		name = "긴급 방벽",
		type = CardType.Spell,
		cost = 1,
		speed = "Instant",
		keywords = { KW.Instant },
		text = "즉시시전 — 아군 생물 하나가 +0/+3 을 얻는다.",
		effects = {
			{ kind = "Buff", power = 0, toughness = 3, target = "AllyCreature" },
		},
		rarity = "Common",
	},
	{
		id = "SPL_MEND",
		name = "응급 치료",
		type = CardType.Spell,
		cost = 2,
		speed = "Instant",
		keywords = { KW.Instant },
		text = "즉시시전 — 라이프 5 회복.",
		effects = {
			{ kind = "Heal", amount = 5, target = "SelfPlayer" },
		},
		rarity = "Common",
	},
}
