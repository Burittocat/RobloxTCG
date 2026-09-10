--!nolint FunctionUnused
-- 아래 효과 함수들(damage·draw·toHand …)은 **표에서 쓰라고 둔 것**이다.
-- 지금 어떤 카드도 안 쓰는 함수가 있을 수 있는데, 그건 지울 이유가 아니라
-- 아직 그런 카드를 안 만들었다는 뜻이다.

--[[
	카드 표 — **수치는 여기서 바꾼다.**

	한 줄이 카드 한 장이다. 이름·코스트·공격력·생명력·태그·설명을 그 자리에서 고치면
	그대로 게임에 반영된다. 다른 파일은 건드릴 필요가 없다.

	고친 뒤:
	    lune run tests/cards.luau     표로 다시 보여주고 잘못된 값을 잡아준다
	    lune run tests/balance.luau   AI 자기대국으로 판이 어떻게 달라졌는지 잰다

	칸
	  코스트 카드   { id, 이름, 설명 }
	  생물          { id, 이름, 코스트, 공격력, 생명력, 태그, 설명, 추가? }
	  마법          { id, 이름, 코스트, 태그, 설명, 효과, 추가? }

	태그 — 쉼표로 여러 개, 빈 칸이면 없음
	  신속      소환한 턴에 바로 공격 / 수비준비에 언탭으로 등장
	  비행      지상 비원거리는 공격도 방어도 못 함
	  도발      살아 있는 동안 플레이어 직접 공격 차단
	  원거리    비행 상대 가능 + 도발 무시, 대신 플레이어 직공은 절반
	  즉시시전  마법 전용 — 상대 턴에도 쓸 수 있다

	효과 — 마법의 '효과' 칸. 여러 개면 순서대로 해결된다
	  damage(양, 대상)             피해
	  heal(양)                     내 라이프 회복
	  destroy(대상)                생물 파괴
	  toDeck(대상) / toHand(대상)  덱으로 / 손으로 되돌리기
	  draw(장수)                   카드를 뽑는다
	  counter()                    스택 위의 시전/소환을 무효화 (즉시시전에서만 의미가 있다)
	  buff(공, 체, 대상)           공격력/생명력 수정 (영구)
	  grant("태그", 대상)          태그 부여

	대상
	  "아무생물" · "아군생물" · "적생물" · "생물또는플레이어" · "나" · "상대" · "스택"

	추가 칸 — 선택
	  { onSummon = { draw(1) } }   생물 — 소환하면 일어나는 일. **대상을 고르는 효과는 못 넣는다**
	  { rare = true }              희귀 등급
	  { noDefensePhase = true }    마법 — 해결되면 수비준비 페이즈를 건너뛴다

	설명 칸에 **태그 설명을 다시 쓰지 않는다.** "비행 — 지상 생물은…" 은 태그 자체의
	규칙이라 `Enums.KeywordText` 한 곳에 있고, 카드를 오른쪽 클릭하면 거기서 읽어온다.
	여기 또 쓰면 상세 화면에 같은 문장이 두 번 뜬다(실제로 그랬다). 이 칸에는 그 카드만의
	이야기(소환 효과·마법 효과·분위기 글)를 쓰고, 태그밖에 없는 카드는 비워둔다.
	`lune run tests/run.luau` 가 태그 이름으로 시작하는 설명을 걸러낸다.

	태그 규칙은 **Config 를 읽어서** 만들어진다. 손으로 여기 옮겨 적으면 Config 를 바꾼 날
	카드만 옛말을 하게 된다 — 실제로 도발의 '원거리' 예외와 원거리 직공의 반올림이
	그렇게 어긋났었다.

	칸 이름이 영어인 이유: Luau 식별자에 한글을 쓸 수 없다. 값(태그·설명)은 한글 그대로다.
	**이름과 설명은 자리표시자다.** Roblox IP 를 붙이는 건 별도 작업이다.
]]

--==========================================================================
-- 표에서 쓰는 것들
--==========================================================================

local TAG = {
	["신속"] = "Haste",
	["비행"] = "Flying",
	["도발"] = "Taunt",
	["원거리"] = "Ranged",
	["즉시시전"] = "Instant",
}

local TARGET = {
	["아무생물"] = "AnyCreature",
	["아군생물"] = "AllyCreature",
	["적생물"] = "EnemyCreature",
	["생물또는플레이어"] = "CreatureOrPlayer",
	["아무플레이어"] = "AnyPlayer",
	["나"] = "SelfPlayer",
	["상대"] = "EnemyPlayer",
	["스택"] = "StackItem",
}

-- 오타는 게임이 뜬 뒤가 아니라 여기서 걸린다.
local function target(name)
	if name == nil then
		return nil
	end
	return TARGET[name] or error(("모르는 대상: '%s'"):format(tostring(name)), 3)
end

local function tag(name)
	return TAG[name] or error(("모르는 태그: '%s'"):format(tostring(name)), 3)
end

local function damage(amount, at)
	return { kind = "Damage", amount = amount, target = target(at) }
end
local function heal(amount)
	return { kind = "Heal", amount = amount, target = target("나") }
end
local function destroy(at)
	return { kind = "Destroy", target = target(at) }
end
local function toDeck(at)
	return { kind = "ToDeck", target = target(at) }
end
local function toHand(at)
	return { kind = "ToHand", target = target(at) }
end
local function draw(amount)
	return { kind = "Draw", amount = amount }
end
local function counter()
	return { kind = "Counter", target = target("스택") }
end
local function buff(power, toughness, at)
	return { kind = "Buff", power = power, toughness = toughness, target = target(at) }
end
local function grant(name, at)
	return { kind = "GrantKeyword", keyword = tag(name), target = target(at) }
end

--==========================================================================
-- 표
--==========================================================================

return {
	tags = TAG,

	--======================================================================
	--   id             이름            설명
	--======================================================================
	costs = {
		{ "COST_BASIC", "에너지 코어", "탭하여 코스트 1 을 얻는다." },
	},

	--======================================================================
	--   id             이름          코스트 공격력 생명력  태그       설명
	--======================================================================
	creatures = {
		{ "CRE_SCOUT",      "정찰병", 1, 1, 2, "",            "" },
		{ "CRE_GUARD",      "성문 경비병", 2, 2, 3, "",            "" },
		{ "CRE_BRUTE",      "돌주먹 거인", 5, 6, 6, "",            "", { rare = true } },
		{ "CRE_RAIDER",     "질풍 습격자", 3, 3, 2, "신속",        "" },
		{ "CRE_HAWK",       "창공의 매",   2, 2, 1, "비행",        "" },
		{ "CRE_WYVERN",     "와이번",   5, 4, 4, "비행,신속",   "" },
		{ "CRE_BULWARK",    "방패병",   4, 1, 6, "도발",        "" },
		{ "CRE_ARCHER",     "장궁 사수",   3, 4, 2, "원거리",      "" },
		{ "CRE_SKYPIERCER", "하늘꿰뚫이",  4, 3, 4, "원거리,도발", "", { rare = true } },
		{ "CRE_SCRIBE",     "고블린 서기",   2, 1, 2, "",            "소환하면 카드 1 장을 뽑는다.", { onSummon = { draw(1) } } },
		{ "CRE_HERALD",     "전령",        4, 3, 3, "신속",        "소환하면 카드 1 장을 뽑는다.", { onSummon = { draw(1) }, rare = true } },
		{ "CRE_SQUIRE",     "고블린",        1, 2, 1, "",            "" },
		{ "CRE_SENTRY",     "방벽",      2, 0, 4, "도발",        "" },
		{ "CRE_FALCONER",   "드론",      3, 2, 3, "비행",        "" },
		{ "CRE_LANCER",     "창기병",      4, 4, 4, "",            "" },
		{ "CRE_BERSERKER",  "광전사",      4, 5, 3, "신속",        "", { rare = true } },
		{ "CRE_TITAN",      "태고의 거석상", 6, 7, 7, "",            "", { rare = true } },
	},

	--======================================================================
	--   id             이름         코스트  태그      설명 / 효과
	--======================================================================
	spells = {
		{ "SPL_FIREBOLT",   "화염 화살",       2, "",         "생물 하나 또는 플레이어에게 3 피해.", { damage(3, "생물또는플레이어") } },
		{ "SPL_RALLY",      "전열 정비",       2, "",         "카드 2 장을 뽑는다.", { draw(2) } },
		{ "SPL_WARCRY",     "돌격 나팔",       2, "",         "아군 생물 하나가 +2/+0 과 신속을 얻는다.", { buff(2, 0, "아군생물"), grant("신속", "아군생물") } },
		{ "SPL_EXECUTE",    "처형 명령",       4, "",         "적 생물 하나를 파괴한다.", { destroy("적생물") }, { noDefensePhase = true, rare = true } },
		{ "SPL_NEGATE",     "주문 파쇄",       3, "즉시시전", "시전 중인 마법이나 소환을 무효화한다.", { counter() }, { rare = true } },
		{ "SPL_RECALL",     "귀환의 소용돌이", 3, "즉시시전", "소환 중인 생물을 덱 맨 위로 되돌린다.", { toDeck("스택") } },
		{ "SPL_SHOCK",      "감전",            1, "즉시시전", "생물 하나 또는 플레이어에게 2 피해.", { damage(2, "생물또는플레이어") } },
		{ "SPL_BULWARK_UP", "긴급 방벽",       4, "즉시시전", "아군 생물 하나가 +0/+3 을 얻는다.", { buff(0, 3, "아군생물") } },
		{ "SPL_MEND",       "응급 치료",       2, "즉시시전", "라이프 3 회복.", { heal(3) } },
		{ "SPL_INSIGHT",    "통찰",            1, "",         "카드 1 장을 뽑는다.", { draw(1) } },
		{ "SPL_ARCHIVE",    "서고 개방",       4, "",         "카드 3 장을 뽑는다.", { draw(3) }, { rare = true } },
		{ "SPL_SNIPE",      "저격",            3, "즉시시전", "생물 하나에게 2 피해.", { damage(2, "아무생물") } },
		{ "SPL_BANISH",     "추방",            3, "",         "적 생물 하나를 덱으로 돌려보낸다.", { toDeck("적생물") } },
		{ "SPL_REINFORCE",  "증원",            3, "",         "아군 생물 하나가 +2/+2 를 얻는다.", { buff(2, 2, "아군생물") } },
	},
}
