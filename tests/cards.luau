--[[
	카드 표 확인 도구.

	    lune run tests/cards.luau            전부 보여준다
	    lune run tests/cards.luau -- 비행     이름·태그·설명에 '비행' 이 든 카드만

	Sheet.luau 에서 수치를 고친 뒤 이걸 돌리면, 지금 게임이 읽고 있는 값이 그대로
	표로 나온다. 잘못된 값(모르는 태그, 체력 0, 마법인데 효과 없음 등)은 여기서 잡힌다 —
	Studio 를 켜서 그 카드가 손에 잡힐 때까지 기다릴 필요가 없다.

	테스트가 아니다. 통과/실패가 아니라 사람이 보라고 만든 표다.
]]

local process = require("@lune/process")

local RobloxEnv = require("./lib/RobloxEnv")

local GREEN, DIM, BOLD, RED, RESET = "[32m", "[2m", "[1m", "[31m", "[0m"

local env = RobloxEnv.mount("src/shared", "Shared")
local Rules = env.require(env.root.Rules)
--[[
	표를 읽는 것 자체가 실패할 수 있다 — 모르는 태그, 빠진 칸, 잘못된 대상 이름.
	그 경우 Lune 의 스택 추적이 아니라 **무엇이 잘못됐는지 한 줄**을 보여준다.
	이 도구를 쓰는 이유가 그거다.
]]
local Decks
local ok, err = pcall(function()
	local Cards = env.require(env.root.Cards)
	Cards.load()
	Decks = env.require(env.root.Decks)
end)

if not ok then
	local message = tostring(err):gsub("\n.*", "")
	print("")
	print(("%s카드 표(src/shared/Cards/Sheet.luau)에 문제가 있습니다%s"):format(RED, RESET))
	print(("  %s"):format(message))
	print("")
	process.exit(1)
end

--[[
	`lune run tests/cards.luau -- GUARD` 로 부르면 "--" 가 첫 인자로 같이 들어온다.
	두 형태를 다 받는다.

	(한글로 거를 수도 있지만 윈도우 터미널의 코드페이지에 따라 인자가 깨질 수 있다 —
	 확실한 건 id 조각이다: GUARD, SPL_, CRE_)
]]
local filter
for _, arg in process.args do
	if arg ~= "--" then
		filter = arg
		break
	end
end

local KW_KR = {
	Haste = "신속",
	Flying = "비행",
	Taunt = "도발",
	Ranged = "원거리",
	Instant = "즉시시전",
}

--[[
	한글은 터미널에서 두 칸을 차지한다. 그걸 세지 않으면 표가 어긋나서
	"보라고 만든 표" 가 못 읽는 표가 된다.
]]
local function displayWidth(text)
	local width = 0
	for _, code in utf8.codes(text) do
		width += (code >= 0x1100 and (code <= 0x115F or (code >= 0xAC00 and code <= 0xD7A3) or (code >= 0x3000 and code <= 0x303F))) and 2 or 1
	end
	return width
end

local function pad(text, width)
	local gap = width - displayWidth(text)
	return text .. string.rep(" ", math.max(0, gap))
end

-- 스타터 덱에 몇 장 들어 있는가. 수치를 만질 때 "이 카드가 실제로 쓰이나" 를 같이 본다.
local inDeck = {}
for _, cardId in Decks.starter() do
	inDeck[cardId] = (inDeck[cardId] or 0) + 1
end

local function keywordText(def)
	local parts = {}
	for _, keyword in def.keywords or {} do
		table.insert(parts, KW_KR[keyword] or keyword)
	end
	return table.concat(parts, ",")
end

local function effectText(def)
	local parts = {}
	for _, effect in def.effects or {} do
		local piece = effect.kind
		if effect.amount then
			piece ..= " " .. tostring(effect.amount)
		end
		if effect.power or effect.toughness then
			piece ..= (" %+d/%+d"):format(effect.power or 0, effect.toughness or 0)
		end
		table.insert(parts, piece)
	end
	for _, effect in def.onSummon or {} do
		table.insert(parts, ("소환시 %s %s"):format(effect.kind, tostring(effect.amount or "")))
	end
	return table.concat(parts, " · ")
end

local rows = {}
for _, def in Rules.Registry.all() do
	local haystack = ("%s %s %s"):format(def.name, keywordText(def), def.text or "")
	if not filter or haystack:find(filter, 1, true) or def.id:find(filter:upper(), 1, true) then
		table.insert(rows, def)
	end
end

table.sort(rows, function(a, b)
	if a.type ~= b.type then
		return a.type < b.type
	end
	if (a.cost or 0) ~= (b.cost or 0) then
		return (a.cost or 0) < (b.cost or 0)
	end
	return a.id < b.id
end)

print("")
print(("%s%s  %s  %s  %s  %s  %s%s"):format(
	BOLD,
	pad("id", 16),
	pad("이름", 16),
	pad("코스트", 7),
	pad("공/체", 7),
	pad("태그", 14),
	"효과 · 덱",
	RESET
))
print(("─"):rep(96))

local TYPE_KR = { Cost = "코스트", Creature = "생물", Spell = "마법" }
local lastType

for _, def in rows do
	if def.type ~= lastType then
		lastType = def.type
		print(("%s%s%s"):format(DIM, TYPE_KR[def.type] or def.type, RESET))
	end

	local body = def.power and ("%d/%d"):format(def.power, def.toughness) or "—"
	local deckCount = inDeck[def.id]

	print(("%s  %s  %s  %s  %s  %s%s%s"):format(
		pad(def.id, 16),
		pad(def.name, 16),
		pad(def.cost and tostring(def.cost) or "—", 7),
		pad(body, 7),
		pad(keywordText(def), 14),
		effectText(def),
		deckCount and ("%s   [스타터 %d장]%s"):format(GREEN, deckCount, RESET) or "",
		RESET
	))
end

print("")
print(("%s카드 %d장 · 스타터 덱 %d장 · 전부 스키마 검증 통과%s"):format(
	GREEN,
	Rules.Registry.count(),
	#Decks.starter(),
	RESET
))
print("")
