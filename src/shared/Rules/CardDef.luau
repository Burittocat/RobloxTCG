--[[
	카드 "정의"(원본 데이터) 스키마와 검증.

	정의(CardDef)와 인스턴스(GameState.cards 안의 개별 카드)를 엄격히 구분한다.
	  - 정의: 불변. "고블린 척후병"이라는 카드가 무엇인가.
	  - 인스턴스: 가변. 이 판에서 3번째로 뽑힌 그 고블린이 탭됐는가, 피해를 얼마 입었는가.

	덱에 같은 카드가 4장 들어가도 정의는 하나, 인스턴스는 4개다.
]]

local Enums = require(script.Parent.Enums)
local Config = require(script.Parent.Config)

local CardType = Enums.CardType
local Keyword = Enums.Keyword
local SpellSpeed = Enums.SpellSpeed

local CardDef = {}

--==========================================================================
-- 검증
--==========================================================================

local function isKeyword(value)
	return Keyword[value] ~= nil
end

local function fail(id, message)
	return false, ("카드 '%s': %s"):format(tostring(id), message)
end

--[[
	카드 정의 하나를 검증한다. -> ok: boolean, err: string?

	카드 DB 를 손으로 쓰다 보면 오타(cost 누락, 존재하지 않는 키워드)가 반드시 난다.
	런타임에 nil 산술로 터지는 대신 여기서 잡는다.
]]
function CardDef.validate(def)
	if type(def) ~= "table" then
		return false, "카드 정의가 테이블이 아닙니다"
	end

	local id = def.id

	if type(id) ~= "string" or id == "" then
		return fail(id, "id 는 비어있지 않은 문자열이어야 합니다")
	end
	if type(def.name) ~= "string" or def.name == "" then
		return fail(id, "name 이 없습니다")
	end
	if CardType[def.type] == nil then
		return fail(id, ("알 수 없는 type '%s'"):format(tostring(def.type)))
	end

	-- 키워드
	if def.keywords ~= nil then
		if type(def.keywords) ~= "table" then
			return fail(id, "keywords 는 배열이어야 합니다")
		end
		for _, kw in def.keywords do
			if not isKeyword(kw) then
				return fail(id, ("알 수 없는 키워드 '%s'"):format(tostring(kw)))
			end
		end
	end

	--------------------------------------------------------------------
	-- 코스트 카드
	--------------------------------------------------------------------
	if def.type == CardType.Cost then
		-- 코스트 카드 자체는 비용이 없다(내는 쪽이므로).
		if def.cost ~= nil and def.cost ~= 0 then
			return fail(id, "코스트 카드의 cost 는 0 이거나 없어야 합니다")
		end
		if def.produces ~= nil and (type(def.produces) ~= "number" or def.produces < 1) then
			return fail(id, "produces 는 1 이상의 정수여야 합니다")
		end
		return true
	end

	--------------------------------------------------------------------
	-- 공통: 비용
	--------------------------------------------------------------------
	if type(def.cost) ~= "number" or def.cost < 0 or def.cost % 1 ~= 0 then
		return fail(id, "cost 는 0 이상의 정수여야 합니다")
	end

	--------------------------------------------------------------------
	-- 생물 카드
	--------------------------------------------------------------------
	if def.type == CardType.Creature then
		if type(def.power) ~= "number" or def.power < 0 then
			return fail(id, "power(공격력) 는 0 이상이어야 합니다")
		end
		if type(def.toughness) ~= "number" or def.toughness < 1 then
			return fail(id, "toughness(체력) 는 1 이상이어야 합니다")
		end
		-- 즉시시전은 마법 전용 키워드다.
		for _, kw in def.keywords or {} do
			if kw == Keyword.Instant then
				return fail(id, "생물은 '즉시시전' 키워드를 가질 수 없습니다")
			end
		end

		--[[
			소환 시 효과(onSummon). **대상을 고르지 않는 효과만** 허용한다.

			대상을 고르는 소환 시 효과를 허용하면 "소환 버튼을 눌렀는데 대상 선택창이
			뜨는" 흐름이 생기고, 그건 클라이언트·스택·AI 세 곳을 다 건드려야 한다.
			대상 없는 효과(드로우, 양쪽 고정 피해)만으로도 카드 다양성은 충분히 나온다.
		]]
		for index, effect in def.onSummon or {} do
			if Enums.EffectKind[effect.kind] == nil then
				return fail(id, ("onSummon[%d]: 알 수 없는 kind '%s'"):format(index, tostring(effect.kind)))
			end
			if effect.target ~= nil and effect.target ~= Enums.TargetKind.None then
				return fail(id, ("onSummon[%d]: 소환 시 효과는 대상을 고를 수 없습니다"):format(index))
			end
		end

		return true
	end

	--------------------------------------------------------------------
	-- 마법 카드
	--------------------------------------------------------------------
	if def.type == CardType.Spell then
		local speed = def.speed or SpellSpeed.Normal
		if SpellSpeed[speed] == nil then
			return fail(id, ("알 수 없는 speed '%s'"):format(tostring(speed)))
		end

		-- 마법에는 생물 전용 키워드가 붙으면 안 된다.
		for _, kw in def.keywords or {} do
			if kw ~= Keyword.Instant then
				return fail(id, ("마법에 생물 전용 키워드 '%s' 가 붙었습니다"):format(kw))
			end
		end

		-- '즉시시전' 키워드와 speed 는 같은 사실의 두 표현이라 어긋나면 안 된다.
		local taggedInstant = CardDef.hasKeyword(def, Keyword.Instant)
		if taggedInstant ~= (speed == SpellSpeed.Instant) then
			return fail(id, "'즉시시전' 키워드와 speed 가 일치하지 않습니다")
		end

		if def.effects == nil or #def.effects == 0 then
			return fail(id, "마법에 effects 가 없습니다")
		end
		for index, effect in def.effects do
			if Enums.EffectKind[effect.kind] == nil then
				return fail(id, ("effects[%d]: 알 수 없는 kind '%s'"):format(index, tostring(effect.kind)))
			end
			if effect.target ~= nil and Enums.TargetKind[effect.target] == nil then
				return fail(id, ("effects[%d]: 알 수 없는 target '%s'"):format(index, tostring(effect.target)))
			end
		end
		return true
	end

	return fail(id, "검증 규칙이 없는 type 입니다")
end

--==========================================================================
-- 조회 헬퍼
--==========================================================================

function CardDef.hasKeyword(def, keyword)
	for _, kw in def.keywords or {} do
		if kw == keyword then
			return true
		end
	end
	return false
end

function CardDef.isCost(def)
	return def.type == CardType.Cost
end

function CardDef.isCreature(def)
	return def.type == CardType.Creature
end

function CardDef.isSpell(def)
	return def.type == CardType.Spell
end

function CardDef.isInstant(def)
	return def.type == CardType.Spell and (def.speed or SpellSpeed.Normal) == SpellSpeed.Instant
end

--[[
	기획서: 수비준비 페이즈에는 "즉시시전마법이나 일반마법카드(수비턴에 사용할 수
	없는 카드를 제외한 카드)"를 쓸 수 있다.
	→ 일반 마법은 기본적으로 수비준비에 사용 가능하되, 카드가 명시적으로 막을 수 있다.
]]
function CardDef.usableInDefensePhase(def)
	if def.type ~= CardType.Spell then
		return false
	end
	if def.noDefensePhase then
		return false
	end
	return true
end

--[[
	코스트 카드 한 장이 만들어내는 코스트 양. 기본 1.
]]
function CardDef.costProduced(def)
	return def.produces or 1
end

--==========================================================================
-- 덱 검증
--==========================================================================

--[[
	덱리스트(카드 id 배열)를 검증한다. -> ok, err

	strict=false 로 부르면 매수 규칙만 보고 60장 제한은 건너뛴다.
	(테스트/캠페인 프리셋에서 작은 덱을 쓰려고)
]]
function CardDef.validateDeck(cardIds, lookup, strict)
	if type(cardIds) ~= "table" then
		return false, "덱리스트가 배열이 아닙니다"
	end

	if strict ~= false and #cardIds ~= Config.deckSize then
		return false, ("덱은 정확히 %d 장이어야 합니다 (현재 %d 장)"):format(Config.deckSize, #cardIds)
	end

	local counts = {}
	for _, cardId in cardIds do
		local def = lookup(cardId)
		if not def then
			return false, ("덱에 존재하지 않는 카드 id '%s' 가 있습니다"):format(tostring(cardId))
		end

		counts[cardId] = (counts[cardId] or 0) + 1

		if not Config.copyLimitExemptTypes[def.type] and counts[cardId] > Config.maxCopiesPerCard then
			return false, ("'%s' 가 %d 장입니다 (최대 %d 장)"):format(def.name, counts[cardId], Config.maxCopiesPerCard)
		end
	end

	return true
end

return CardDef
