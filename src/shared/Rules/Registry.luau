--[[
	카드 정의 레지스트리.

	룰 엔진은 카드 DB 를 직접 require 하지 않는다. 부팅하는 쪽(서버 / 테스트)이
	여기에 정의를 등록하고, 엔진은 id 로만 조회한다.
	  - 테스트에서 가짜 카드 몇 장으로 룰을 검증할 수 있다.
	  - GameState 에는 defId 문자열만 남아 그대로 직렬화된다.
]]

local CardDef = require(script.Parent.CardDef)

local Registry = {}

local defs = {}
local count = 0

--[[
	카드 정의 배열을 등록한다. 검증에 실패하면 즉시 에러를 낸다 —
	잘못된 카드가 게임 중에 nil 산술로 터지는 것보다 부팅 때 죽는 편이 낫다.
]]
function Registry.register(list)
	for _, def in list do
		local ok, err = CardDef.validate(def)
		if not ok then
			error("카드 정의 검증 실패 - " .. err, 2)
		end
		if defs[def.id] then
			error(("카드 id 중복: '%s'"):format(def.id), 2)
		end

		defs[def.id] = table.freeze(def)
		count += 1
	end
end

function Registry.get(cardId)
	return defs[cardId]
end

function Registry.mustGet(cardId)
	local def = defs[cardId]
	if not def then
		error(("등록되지 않은 카드 id: '%s'"):format(tostring(cardId)), 2)
	end
	return def
end

function Registry.all()
	return defs
end

function Registry.count()
	return count
end

-- 테스트에서 카드셋을 갈아끼울 때만 쓴다.
function Registry.reset()
	defs = {}
	count = 0
end

return Registry
