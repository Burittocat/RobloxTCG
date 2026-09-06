--[[
	카드 DB 부팅.

	세트 파일들을 모아 Rules.Registry 에 등록한다.
	서버와 클라이언트 양쪽에서 한 번씩 require 하면 된다(중복 등록은 막혀 있다).
]]

local Rules = require(script.Parent.Rules)

local Cards = {}

local SETS = {
	require(script.Core),
}

local registered = false

function Cards.load()
	if registered then
		return Rules.Registry
	end

	for _, set in SETS do
		Rules.Registry.register(set)
	end

	registered = true
	return Rules.Registry
end

--[[
	덱 빌더/디버그용 조회. type 이 nil 이면 전부.
]]
function Cards.list(cardType)
	Cards.load()

	local out = {}
	for _, def in Rules.Registry.all() do
		if cardType == nil or def.type == cardType then
			table.insert(out, def)
		end
	end

	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

return Cards
