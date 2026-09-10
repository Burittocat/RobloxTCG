--[[
	룰 엔진 전역 열거형.

	문자열 상수를 쓰는 이유: 네트워크로 그대로 보낼 수 있고, 세이브 파일에 남겨도
	숫자 ID 처럼 나중에 순서가 밀려 깨지지 않는다.
]]

--[[
	태그 설명이 Config 를 읽는다. Config 는 아무것도 require 하지 않으므로 순환은 없다.
]]
local Config = require(script.Parent.Config)

local Enums = {}

--==========================================================================
-- 카드 종류
--==========================================================================

Enums.CardType = table.freeze({
	Cost = "Cost", -- 코스트 카드
	Creature = "Creature", -- 생물 카드
	Spell = "Spell", -- 마법 카드
})

--==========================================================================
-- 키워드(태그) — 기획서 기준 5종
--==========================================================================

Enums.Keyword = table.freeze({
	Haste = "Haste", -- 신속
	Flying = "Flying", -- 비행
	Taunt = "Taunt", -- 도발
	Ranged = "Ranged", -- 원거리
	Instant = "Instant", -- 즉시시전
})

-- UI 표기용. 룰 로직은 절대 이 값을 비교에 쓰지 않는다.
Enums.KeywordDisplay = table.freeze({
	Haste = "신속",
	Flying = "비행",
	Taunt = "도발",
	Ranged = "원거리",
	Instant = "즉시시전",
})

--[[
	태그 한 줄 설명. 카드마다 적힌 설명문(Sheet.luau)과 달리 **태그 자체**의 규칙이다.

	카드 설명은 카드가 손에 있어야 읽을 수 있어서, "도발이 뭔지" 를 물을 자리가 없다.
	튜토리얼 코치가 이걸 읽어준다. 여기 문장이 곧 규칙 설명이므로,
	Config 로 룰을 바꾸면 이 표도 같이 봐야 한다.
]]
--[[
	태그 규칙 설명 — 카드를 오른쪽 클릭하면 여기서 읽어온다.

	**Config 를 읽어서 만든다.** README 의 ★ 표에 있는 값(비행끼리 방어 · 직공 반올림 ·
	도발의 직공 차단)은 사용자가 바꿀 수 있는 것들이고, 바꿨는데 설명이 옛말을 하고
	있으면 그게 제일 나쁜 거짓말이다 — 화면이 규칙을 알려주는 유일한 자리다.

	실제로 도발 설명이 **'원거리'는 무시한다는 예외를 빼먹고** 있었다. 같은 게임 안에서
	공격이 거부될 때는 "('원거리'만 무시 가능)" 이라고 말하면서 태그 설명만 딴소리를 했다.
]]

-- 비행 공격을 막을 수 있는 쪽
local function flyingBlockers()
	if Config.flyingCanBlockFlying then
		return "'비행'과 '원거리'"
	end
	return "'원거리'"
end

-- 원거리가 플레이어를 직접 칠 때 들어가는 몫
local function directShare()
	local divisor = Config.rangedDirectDamageDivisor
	local portion = (divisor == 2) and "절반" or ("%d 분의 1"):format(divisor)
	local rounding = (Config.rangedDirectDamageRounding == "ceil") and "올림" or "내림"
	return ("%s(%s)"):format(portion, rounding)
end

local function flyingText()
	local reach = ("%s만 이 생물을 상대할 수 있다."):format(flyingBlockers())
	if Config.groundCannotAttackFlying then
		return ("지상 생물은 이 생물을 공격할 수 없고, 이 생물의 공격을 막을 수도 없다. %s"):format(reach)
	end
	return ("이 생물의 공격은 %s만 막을 수 있다."):format(flyingBlockers())
end

local function tauntText()
	if not Config.tauntBlocksDirectAttack then
		return "지금 설정에서는 플레이어 직접 공격을 막지 않는다."
	end
	return "이 생물이 전장에 있는 한, 상대는 플레이어를 직접 공격할 수 없다. 다만 '원거리' 생물은 이를 무시한다."
end

Enums.KeywordText = table.freeze({
	Haste = "소환한 턴에 바로 공격할 수 있다. 수비준비 페이즈에도 언탭으로 등장한다.",
	Flying = flyingText(),
	Taunt = tauntText(),
	Ranged = ("'비행'을 상대할 수 있고 '도발'을 무시한다. 플레이어 직접 공격은 데미지 %s."):format(directShare()),
	Instant = "내 턴이 아니어도, 상대의 시전에 대응해서 쓸 수 있다.",
})

--==========================================================================
-- 존
--==========================================================================

Enums.Zone = table.freeze({
	Deck = "Deck", -- 덱
	Hand = "Hand", -- 패
	Field = "Field", -- 필드(전장)
	Graveyard = "Graveyard", -- 더미(무덤)
	Stack = "Stack", -- 시전/소환 대기열
})

--==========================================================================
-- 페이즈
--==========================================================================

--[[
	기획서의 1턴 구조를 그대로 옮긴 것.

	  (Untap/Draw 는 기획서에 명시되지 않았지만 "언탭"과 "드로우"가 룰 본문에
	   전제되어 있어 턴 시작 스텝으로 분리했다.)

	  Untap        - 턴 플레이어의 모든 퍼미넌트 언탭
	  Draw         - 턴 플레이어 1장 드로우
	  Main         - 메인 페이즈       (턴 플레이어 행동 / 상대는 즉시시전만)
	  AttackPrep   - 공격준비 페이즈   (턴 플레이어가 공격자 선언)
	  DefensePrep  - 수비준비 페이즈   (상대가 방어자 배정 + 소환/마법)
	  Combat       - 공수 페이즈       (데미지 동시 해결)
	  EndTurn      - 턴 종료 정리
]]
Enums.Phase = table.freeze({
	-- 판이 시작되기 전 한 번. PhaseOrder 에 넣지 않는다 — 턴 순환의 일부가 아니라
	-- 그 앞의 관문이고, 여기서 Phases.advance 가 돌면 안 되기 때문이다.
	Mulligan = "Mulligan",

	Untap = "Untap",
	Draw = "Draw",
	Main = "Main",
	AttackPrep = "AttackPrep",
	DefensePrep = "DefensePrep",
	Combat = "Combat",
	EndTurn = "EndTurn",
})

Enums.PhaseDisplay = table.freeze({
	Mulligan = "멀리건",
	Untap = "언탭",
	Draw = "드로우",
	Main = "메인 페이즈",
	AttackPrep = "공격준비 페이즈",
	DefensePrep = "수비준비 페이즈",
	Combat = "공수 페이즈",
	EndTurn = "턴 종료",
})

Enums.PhaseOrder = table.freeze({
	"Untap",
	"Draw",
	"Main",
	"AttackPrep",
	"DefensePrep",
	"Combat",
	"EndTurn",
})

--==========================================================================
-- 마법 시전 속도
--==========================================================================

Enums.SpellSpeed = table.freeze({
	Normal = "Normal", -- 일반 마법: 본인 메인 페이즈에만
	Instant = "Instant", -- 즉시시전: 상대 메인 / 본인 메인 / 본인 수비준비
})

--==========================================================================
-- 패배 사유
--==========================================================================

Enums.LossReason = table.freeze({
	LifeDepleted = "LifeDepleted", -- 라이프 0 이하
	DeckOut = "DeckOut", -- 덱이 비었는데 드로우
	Concede = "Concede", -- 항복
})

--==========================================================================
-- 효과 종류 (마법/능력이 하는 일)
--==========================================================================

Enums.EffectKind = table.freeze({
	Damage = "Damage", -- 대상에게 피해
	Heal = "Heal", -- 플레이어 회복
	Destroy = "Destroy", -- 생물을 더미로
	ToDeck = "ToDeck", -- 카드를 덱으로 (기획서: 즉시시전이 소환을 덱으로 되돌림)
	ToHand = "ToHand", -- 카드를 패로
	Draw = "Draw", -- 드로우
	Counter = "Counter", -- 스택 위의 시전/소환을 무효화
	Buff = "Buff", -- 공격력/체력 수정
	GrantKeyword = "GrantKeyword", -- 키워드 부여
})

--==========================================================================
-- 효과 대상 지정
--==========================================================================

Enums.TargetKind = table.freeze({
	None = "None",
	AnyCreature = "AnyCreature",
	AllyCreature = "AllyCreature",
	EnemyCreature = "EnemyCreature",
	AnyPlayer = "AnyPlayer",
	EnemyPlayer = "EnemyPlayer",
	SelfPlayer = "SelfPlayer",
	CreatureOrPlayer = "CreatureOrPlayer",
	StackItem = "StackItem", -- 무효화 대상
})

return table.freeze(Enums)
