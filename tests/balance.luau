--[[
	밸런스 계측.

	    lune run tests/balance.luau
	    lune run tests/balance.luau -- --games 200

	AI 둘이 스타터 덱으로 여러 판 두게 하고, "판이 어떻게 흘렀는가" 를 숫자로 뽑는다.
	이게 필요한 이유: 덱 순환·판 길이·손패 고갈은 한 판만 봐서는 알 수 없고,
	고친 뒤에도 "좋아진 것 같다" 로 끝나기 쉽다. 전후를 같은 자로 재려고 만들었다.

	테스트가 아니다 — 통과/실패가 없다. 숫자를 보고 사람이 판단한다.
	그래서 CI 에 넣지 않았다 (돌리는 데 시간이 걸리기도 한다).
]]

local process = require("@lune/process")

local RobloxEnv = require("./lib/RobloxEnv")

local env = RobloxEnv.mount("src/shared", "Shared")
local Rules = env.require(env.root.Rules)
local Cards = env.require(env.root.Cards)
local Decks = env.require(env.root.Decks)
local AI = env.require(env.root.AI)

Cards.load()

local GAMES = 60
do
	local args = process.args
	for index, arg in args do
		if arg == "--games" then
			GAMES = tonumber(args[index + 1]) or GAMES
		end
	end
end

local Phase = Rules.Enums.Phase
local CardDef = Rules.CardDef
local Registry = Rules.Registry
local GameState = Rules.GameState
local Stack = Rules.Stack

--==========================================================================

local function whoActs(state)
	if not Stack.isEmpty(state) then
		return Stack.responderFor(state)
	end
	if state.phase == Phase.DefensePrep then
		return GameState.opponentOf(state.activePlayerId)
	end
	return state.activePlayerId
end

--[[
	한 판을 끝까지 둔다. 매 턴 시작 때 손패 크기를 적어 둔다 —
	"손이 말랐다" 는 끝난 시점만 봐서는 안 보이고, 판 중간이 진짜 모습이다.
]]
local function playOut(seed)
	local state = Rules.newMatch({
		seed = seed,
		startingPlayerId = 1,
		players = {
			{ name = "A", deck = Decks.starter() },
			{ name = "B", deck = Decks.starter() },
		},
	})

	local handSamples, emptyHandTurns, turnSeen = {}, 0, 0
	local steps = 0

	while not state.finished and steps < 20000 do
		steps += 1

		if state.turn > turnSeen and state.phase == Phase.Main then
			turnSeen = state.turn
			local hand = #state.players[state.activePlayerId].hand
			table.insert(handSamples, hand)
			if hand == 0 then
				emptyHandTurns += 1
			end
		end

		if not AI.act(state, whoActs(state), AI.Difficulty.Normal) then
			break
		end
	end

	local mulligans = 0
	for playerId = 1, 2 do
		if state.players[playerId].hasMulliganed then
			mulligans += 1
		end
	end

	return {
		turns = state.turn,
		deckLeft = (#state.players[1].deck + #state.players[2].deck) / 2,
		handSamples = handSamples,
		emptyHandTurns = emptyHandTurns,
		mulligans = mulligans,
		deckOut = state.lossReason == Rules.Enums.LossReason.DeckOut,
	}
end

--==========================================================================

local function mean(list)
	if #list == 0 then
		return 0
	end
	local sum = 0
	for _, value in list do
		sum += value
	end
	return sum / #list
end

local function median(list)
	local copy = table.clone(list)
	table.sort(copy)
	return copy[math.max(1, math.floor(#copy / 2))] or 0
end

local turns, deckLeft, handMeans, emptyTurns = {}, {}, {}, {}
local mulligans, deckOuts = 0, 0

for index = 1, GAMES do
	local result = playOut(index * 977)

	table.insert(turns, result.turns)
	table.insert(deckLeft, result.deckLeft)
	table.insert(handMeans, mean(result.handSamples))
	table.insert(emptyTurns, result.emptyHandTurns)
	mulligans += result.mulligans
	if result.deckOut then
		deckOuts += 1
	end
end

local deckSize = Rules.Config.deckSize
local starter = Decks.starter()
local costCount, drawCount = 0, 0
for _, cardId in starter do
	local def = Registry.mustGet(cardId)
	if CardDef.isCost(def) then
		costCount += 1
	end
	for _, list in { def.effects, def.onSummon } do
		for _, effect in list or {} do
			if effect.kind == "Draw" then
				drawCount += 1
			end
		end
	end
end

print("")
print(("스타터 덱 %d장  ·  코스트 %d장  ·  드로우 효과 %d장  ·  %d판"):format(
	deckSize,
	costCount,
	drawCount,
	GAMES
))
print(("─"):rep(64))
print(("판 길이        평균 %5.1f턴   중앙 %d턴"):format(mean(turns), median(turns)))
print(("남은 덱        평균 %5.1f장   (%d장 중 — 적을수록 덱을 많이 씀)"):format(mean(deckLeft), deckSize))
print(("턴 시작 손패    평균 %5.2f장   (판 전체 평균)"):format(mean(handMeans)))
print(("손패 0 인 턴    평균 %5.2f번   (한 판에서)"):format(mean(emptyTurns)))
print(("멀리건         %d회 / %d명"):format(mulligans, GAMES * 2))
print(("덱아웃으로 끝난 판  %d / %d"):format(deckOuts, GAMES))
print("")
