--[[
	카드 인스턴스의 "현재" 키워드/스탯 질의.

	원본 정의의 키워드에 더해, 마법으로 부여된(grantedKeywords) 것까지 합쳐서 본다.
	룰 로직은 def.keywords 를 직접 읽지 말고 반드시 이 모듈을 거칠 것.
]]

local Enums = require(script.Parent.Enums)
local Registry = require(script.Parent.Registry)
local CardDef = require(script.Parent.CardDef)

local Keyword = Enums.Keyword

local Keywords = {}

--==========================================================================
-- 키워드
--==========================================================================

function Keywords.has(instance, keyword)
	if instance.grantedKeywords and instance.grantedKeywords[keyword] then
		return true
	end
	return CardDef.hasKeyword(Registry.mustGet(instance.defId), keyword)
end

function Keywords.grant(instance, keyword)
	instance.grantedKeywords = instance.grantedKeywords or {}
	instance.grantedKeywords[keyword] = true
end

function Keywords.revoke(instance, keyword)
	if instance.grantedKeywords then
		instance.grantedKeywords[keyword] = nil
	end
end

-- 현재 유효 키워드 집합 -> { [keyword] = true }
function Keywords.effective(instance)
	local out = {}
	for _, kw in Registry.mustGet(instance.defId).keywords or {} do
		out[kw] = true
	end
	for kw in instance.grantedKeywords or {} do
		out[kw] = true
	end
	return out
end

--==========================================================================
-- 편의 질의 (전투 코드 가독성용)
--==========================================================================

function Keywords.isHaste(instance)
	return Keywords.has(instance, Keyword.Haste)
end

function Keywords.isFlying(instance)
	return Keywords.has(instance, Keyword.Flying)
end

function Keywords.isTaunt(instance)
	return Keywords.has(instance, Keyword.Taunt)
end

function Keywords.isRanged(instance)
	return Keywords.has(instance, Keyword.Ranged)
end

--[[
	"지상 생물" = 비행이 없는 생물.
	기획서의 "지상의 생물체가 '원거리' 태그가 없다면 '비행' 태그의 적을 공격할 수 없다"
	에서 쓰이는 개념.
]]
function Keywords.isGround(instance)
	return not Keywords.isFlying(instance)
end

--==========================================================================
-- 스탯
--==========================================================================

-- 현재 공격력 = 원본 + 버프. 음수로 내려가지 않게 잘라낸다.
function Keywords.power(instance)
	local def = Registry.mustGet(instance.defId)
	return math.max(0, (def.power or 0) + (instance.powerMod or 0))
end

-- 현재 체력 = 원본 + 버프.
function Keywords.toughness(instance)
	local def = Registry.mustGet(instance.defId)
	return math.max(0, (def.toughness or 0) + (instance.toughnessMod or 0))
end

--[[
	남은 체력. 0 이하면 파괴된다.

	damageOverride 는 화면이 쓴다. 전투 결과는 스냅샷으로 한꺼번에 오는데,
	때리는 장면은 그보다 늦게 재생되므로 그 사이에는 **예전 피해량으로** 같은
	수치를 그려야 한다. 빼기를 화면에서 따로 하면 계산이 두 벌이 된다.
]]
function Keywords.remainingToughness(instance, damageOverride)
	local damage = damageOverride
	if damage == nil then
		damage = instance.damage or 0
	end

	return Keywords.toughness(instance) - damage
end

function Keywords.isLethallyDamaged(instance)
	return Keywords.remainingToughness(instance) <= 0
end

return Keywords
