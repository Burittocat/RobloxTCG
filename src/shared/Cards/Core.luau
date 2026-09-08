--[[
	기본 카드셋 — 표(Sheet.luau)를 카드 정의로 바꾼다.

	**수치를 바꾸려면 이 파일이 아니라 `Sheet.luau` 를 연다.** 여기는 그 표를 엔진이
	읽는 모양으로 펴는 곳이고, 카드 한 장이 늘어도 이 파일은 그대로다.

	왜 나눴나: 밸런스는 자주 만지고 변환 규칙은 거의 안 바뀐다. 한 파일에 두면
	숫자 하나 고치러 들어갔다가 스키마 사이를 헤매게 된다.
]]

local Sheet = require(script.Parent.Sheet)

local CardType = { Cost = "Cost", Creature = "Creature", Spell = "Spell" }
local INSTANT = "Instant"

--[[
	"비행,신속" → { "Flying", "Haste" }

	빈 칸이면 nil 을 준다 — 빈 배열을 주면 "키워드가 없다" 와 "빈 목록" 이 달라 보인다.
]]
local function keywordsOf(text, cardId)
	if text == nil or text == "" then
		return nil
	end

	local out = {}
	for name in tostring(text):gmatch("[^,]+") do
		local trimmed = name:match("^%s*(.-)%s*$")
		local keyword = Sheet.tags[trimmed]
		if not keyword then
			error(("%s: 모르는 태그 '%s'"):format(cardId, trimmed), 0)
		end
		table.insert(out, keyword)
	end

	return out
end

local function textOf(value)
	if value == nil or value == "" then
		return nil
	end
	return value
end

local defs = {}

--------------------------------------------------------------------------
-- 코스트 카드
--------------------------------------------------------------------------
for _, row in Sheet.costs do
	local id, name, text = row[1], row[2], row[3]
	table.insert(defs, {
		id = id,
		name = name,
		type = CardType.Cost,
		text = textOf(text),
		rarity = "Common",
	})
end

--------------------------------------------------------------------------
-- 생물
--------------------------------------------------------------------------
for _, row in Sheet.creatures do
	local id, name, cost, power, toughness, tags, text, extra = table.unpack(row, 1, 8)
	extra = extra or {}

	table.insert(defs, {
		id = id,
		name = name,
		type = CardType.Creature,
		cost = cost,
		power = power,
		toughness = toughness,
		keywords = keywordsOf(tags, id),
		text = textOf(text),
		onSummon = extra.onSummon,
		rarity = extra.rare and "Rare" or "Common",
	})
end

--------------------------------------------------------------------------
-- 마법
--------------------------------------------------------------------------
for _, row in Sheet.spells do
	local id, name, cost, tags, text, effects, extra = table.unpack(row, 1, 7)
	extra = extra or {}

	local keywords = keywordsOf(tags, id)

	-- '즉시시전' 태그와 speed 는 같은 사실의 두 표현이다. 표에서는 태그만 적고
	-- speed 는 여기서 맞춰준다 — 둘을 따로 적게 하면 어긋난 카드가 나온다.
	local instant = false
	for _, keyword in keywords or {} do
		if keyword == INSTANT then
			instant = true
		end
	end

	table.insert(defs, {
		id = id,
		name = name,
		type = CardType.Spell,
		cost = cost,
		speed = instant and "Instant" or "Normal",
		keywords = keywords,
		text = textOf(text),
		effects = effects,
		noDefensePhase = extra.noDefensePhase,
		rarity = extra.rare and "Rare" or "Common",
	})
end

return defs
