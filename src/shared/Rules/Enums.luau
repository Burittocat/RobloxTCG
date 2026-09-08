--[[
	룰 엔진 전역 열거형.

	문자열 상수를 쓰는 이유: 네트워크로 그대로 보낼 수 있고, 세이브 파일에 남겨도
	숫자 ID 처럼 나중에 순서가 밀려 깨지지 않는다.
]]

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
