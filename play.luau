--[[
	터미널 싱글플레이 클라이언트.

	    lune run play              사람(P1) vs AI(P2)
	    lune run play -- --auto    AI vs AI 자동 대전 (룰 검증용)
	    lune run play -- --seed 42 시드 고정

	Studio 없이 실제 한 판을 끝까지 돌려보기 위한 도구다. 서버가 쓸 룰 엔진과
	완전히 같은 코드를 호출하므로, 여기서 이상하면 게임 안에서도 이상하다.
]]

local process = require("@lune/process")
local stdio = require("@lune/stdio")

local RobloxEnv = require("./tests/lib/RobloxEnv")

local env = RobloxEnv.mount("src/shared", "Shared")
local Rules = env.require(env.root.Rules)
local Cards = env.require(env.root.Cards)
local Decks = env.require(env.root.Decks)
local AI = env.require(env.root.AI)

Cards.load()

local Enums = Rules.Enums
local GameState = Rules.GameState
local Keywords = Rules.Keywords
local Combat = Rules.Combat
local Phases = Rules.Phases
local Registry = Rules.Registry
local CardDef = Rules.CardDef
local Stack = Rules.Stack

local Phase = Enums.Phase
local CardType = Enums.CardType

--==========================================================================
-- 인자
--==========================================================================

local options = { auto = false, seed = nil }

do
	local args = process.args
	local index = 1
	while index <= #args do
		local arg = args[index]
		if arg == "--auto" then
			options.auto = true
		elseif arg == "--seed" then
			index += 1
			options.seed = tonumber(args[index])
		end
		index += 1
	end
end

local HUMAN = 1
local ENEMY = 2

--==========================================================================
-- 출력 꾸미기
--==========================================================================

local C = {
	reset = "\27[0m",
	dim = "\27[2m",
	bold = "\27[1m",
	red = "\27[31m",
	green = "\27[32m",
	yellow = "\27[33m",
	blue = "\27[34m",
	magenta = "\27[35m",
	cyan = "\27[36m",
}

local function say(text)
	print(text or "")
end

local RULE = string.rep("─", 62)
local THICK = string.rep("═", 62)

--[[
	터미널에서 차지하는 칸 수. 한글·한자는 한 글자가 2칸이라
	string.format 의 %-16s(바이트 기준)로는 열이 어긋난다.
]]
local function displayWidth(text)
	local width = 0
	for _, code in utf8.codes(text) do
		local wide = (code >= 0x1100 and code <= 0x115F) -- 한글 자모
			or (code >= 0x2E80 and code <= 0xA4CF) -- CJK
			or (code >= 0xAC00 and code <= 0xD7A3) -- 한글 완성형
			or (code >= 0xF900 and code <= 0xFAFF)
			or (code >= 0xFF00 and code <= 0xFF60) -- 전각
			or (code >= 0xFFE0 and code <= 0xFFE6)
		width += wide and 2 or 1
	end
	return width
end

local function pad(text, width)
	local gap = width - displayWidth(text)
	return gap > 0 and (text .. string.rep(" ", gap)) or text
end

--==========================================================================
-- 카드 묘사
--==========================================================================

local function keywordText(instance)
	local parts = {}
	for keyword in Keywords.effective(instance) do
		table.insert(parts, Enums.KeywordDisplay[keyword] or keyword)
	end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, "·") or nil
end

-- 필드 위 카드 한 줄
local function describeField(state, instance)
	local def = Registry.mustGet(instance.defId)

	if def.type == CardType.Cost then
		return ("%s%s%s"):format(
			instance.tapped and C.dim or "",
			def.name .. (instance.tapped and " (탭)" or ""),
			C.reset
		)
	end

	local stats = ("%d/%d"):format(Keywords.power(instance), Keywords.remainingToughness(instance))
	local tags = keywordText(instance)

	local line = ("%s %s"):format(pad(def.name, 18), pad(stats, 6))
	if tags then
		line ..= (" %s[%s]%s"):format(C.cyan, tags, C.reset)
	end
	if instance.tapped then
		line = C.dim .. line .. " (탭)" .. C.reset
	end
	if instance.summonedOnTurn == state.turn and not Keywords.isHaste(instance) then
		line ..= C.dim .. " (소환 멀미)" .. C.reset
	end
	return line
end

--[[
	손패 한 줄. plain=true 면 색을 넣지 않는다 —
	낼 수 없는 카드는 줄 전체를 흐리게 칠하므로 중간에 리셋이 끼면 안 된다.
]]
local function describeHand(instance, plain)
	local def = Registry.mustGet(instance.defId)
	local name = pad(def.name, 18)

	local function tint(color, text)
		return plain and text or (color .. text .. C.reset)
	end

	if def.type == CardType.Cost then
		return name .. tint(C.dim, "코스트 카드")
	end

	if def.type == CardType.Creature then
		local tags = {}
		for _, keyword in def.keywords or {} do
			table.insert(tags, Enums.KeywordDisplay[keyword])
		end

		local line = ("%s%s  %s"):format(name, pad(def.cost .. "코", 5), pad(def.power .. "/" .. def.toughness, 6))
		if #tags > 0 then
			line ..= tint(C.cyan, "[" .. table.concat(tags, "·") .. "]")
		end
		return line
	end

	local prefix = CardDef.isInstant(def) and tint(C.magenta, "[즉시시전] ") or ""
	return ("%s%s  %s%s"):format(name, pad(def.cost .. "코", 5), prefix, tint(C.dim, def.text or "마법"))
end

--==========================================================================
-- 화면
--==========================================================================

--[[
	페이즈마다 "숫자"가 가리키는 대상이 달라진다. 그 목록을 만들어 돌려준다.
	  Main / 대응  → 손패
	  공격준비     → 공격 가능한 내 생물
	  수비준비     → 방어 가능한 내 생물
]]
local function contextList(state, playerId)
	if not Stack.isEmpty(state) then
		return "hand", state.players[playerId].hand
	end

	if state.phase == Phase.AttackPrep and playerId == state.activePlayerId then
		local out = {}
		for _, instance in GameState.creaturesOnField(state, playerId) do
			if Combat.canAttack(state, instance) then
				table.insert(out, instance.id)
			end
		end
		return "attack", out
	end

	if state.phase == Phase.DefensePrep and playerId ~= state.activePlayerId then
		local out = {}
		for _, instance in GameState.creaturesOnField(state, playerId) do
			if not instance.tapped and not state.combat.blocks[instance.id] then
				table.insert(out, instance.id)
			end
		end
		return "block", out
	end

	return "hand", state.players[playerId].hand
end

local function renderBoard(state, playerId)
	local me = state.players[playerId]
	local foe = state.players[GameState.opponentOf(playerId)]

	say()
	say(C.bold .. THICK .. C.reset)
	say((" 턴 %d   %s%s%s   %s")
		:format(
			state.turn,
			C.yellow,
			Enums.PhaseDisplay[state.phase],
			C.reset,
			state.activePlayerId == playerId and (C.green .. "내 턴" .. C.reset) or (C.red .. "상대 턴" .. C.reset)
		))
	say(C.bold .. THICK .. C.reset)

	-- 상대
	say((" %s%s%s   라이프 %s%d%s   패 %d장   덱 %d장")
		:format(C.red, foe.name, C.reset, C.bold, foe.life, C.reset, #foe.hand, #foe.deck))
	local foeField = GameState.creaturesOnField(state, foe.id)
	if #foeField == 0 then
		say("   " .. C.dim .. "(생물 없음)" .. C.reset)
	end
	for _, instance in foeField do
		say("   " .. describeField(state, instance))
	end
	say(("   %s코스트 %d/%d%s"):format(
		C.dim,
		GameState.availableCost(state, foe.id),
		#GameState.costCardsOnField(state, foe.id),
		C.reset
	))

	say(RULE)

	-- 스택
	if not Stack.isEmpty(state) then
		say(" " .. C.magenta .. "스택 (위에서부터 해결)" .. C.reset)
		for index = #state.stack, 1, -1 do
			local item = state.stack[index]
			local def = Registry.mustGet(GameState.mustGetCard(state, item.instanceId).defId)
			say(("   %s%s%s  (P%d)"):format(C.magenta, def.name, C.reset, item.controllerId))
		end
		say(RULE)
	end

	-- 전투 상황
	if #state.combat.attackers > 0 then
		say(" " .. C.yellow .. "전투" .. C.reset)
		for _, declaration in state.combat.attackers do
			local attacker = GameState.getCard(state, declaration.id)
			if attacker then
				local targetName = (declaration.targetKind == "Player") and "플레이어"
					or Registry.mustGet(GameState.mustGetCard(state, declaration.targetId).defId).name

				local blockerName
				for blockerId, attackerId in state.combat.blocks do
					if attackerId == declaration.id then
						blockerName = Registry.mustGet(GameState.mustGetCard(state, blockerId).defId).name
					end
				end

				say(("   %s → %s%s"):format(
					Registry.mustGet(attacker.defId).name,
					targetName,
					blockerName and (C.green .. "  ← " .. blockerName .. " 방어" .. C.reset) or ""
				))
			end
		end
		say(RULE)
	end

	-- 나
	local myField = GameState.creaturesOnField(state, playerId)
	if #myField == 0 then
		say("   " .. C.dim .. "(생물 없음)" .. C.reset)
	end
	for _, instance in myField do
		say("   " .. describeField(state, instance))
	end
	say((" %s%s%s   라이프 %s%d%s   덱 %d장   코스트 %s%d/%d%s")
		:format(
			C.green,
			me.name,
			C.reset,
			C.bold,
			me.life,
			C.reset,
			#me.deck,
			C.bold,
			GameState.availableCost(state, playerId),
			#GameState.costCardsOnField(state, playerId),
			C.reset
		))

	say(RULE)

	-- 문맥 목록
	local kind, ids = contextList(state, playerId)
	local heading = ({
		hand = "내 패  " .. C.dim .. "(숫자 = 그 카드 내기)" .. C.reset,
		attack = "공격 가능  " .. C.dim .. "(숫자 = 공격 선언)" .. C.reset,
		block = "방어 가능  " .. C.dim .. "(숫자 = 방어 배정)" .. C.reset,
	})[kind]

	say(" " .. heading)
	if #ids == 0 then
		say("   " .. C.dim .. "(없음)" .. C.reset)
	end

	for index, instanceId in ids do
		local instance = state.cards[instanceId]
		local playable = (kind ~= "hand") or Rules.canPlayCard(state, playerId, instanceId)

		if playable then
			local text = (kind == "hand") and describeHand(instance, false)
				or describeField(state, instance)
			say(("  %s[%d]%s %s"):format(C.bold, index, C.reset, text))
		else
			-- 지금 낼 수 없는 카드는 줄 전체를 흐리게 (중간에 색 리셋이 끼면 안 된다)
			say(("  %s[%d] %s%s"):format(C.dim, index, describeHand(instance, true), C.reset))
		end
	end

	say(RULE)
end

--==========================================================================
-- 입력
--==========================================================================

--[[
	한 줄 입력. -> 문자열 | nil (입력 끝)

	Lune 의 readLine 은 EOF 에서 nil 이 아니라 빈 문자열을 끝없이 돌려준다.
	그냥 두면 파이프 입력이 떨어졌을 때 무한 루프가 난다.
	사용자가 그냥 Enter 를 친 경우엔 개행 문자가 들어 있으므로,
	"길이가 0" 인 경우만 EOF 로 판정해 둘을 구분한다.
]]
local function readCommand(prompt)
	stdio.write(prompt)

	local raw = stdio.readLine()
	if raw == nil or raw == "" then
		return nil
	end

	local line = raw:gsub("^\239\187\191", "") -- UTF-8 BOM (파이프 입력에서 붙는다)
	line = line:gsub("[\r\n]", "")
	line = line:gsub("^%s+", "")
	line = line:gsub("%s+$", "")
	return line
end

--[[
	번호 목록을 보여주고 하나 고르게 한다. -> 선택된 항목 | nil (취소)
	options = { { label = string, value = any }, ... }
]]
local function chooseFrom(title, choices)
	if #choices == 0 then
		return nil
	end
	if #choices == 1 then
		return choices[1].value
	end

	say(" " .. C.yellow .. title .. C.reset)
	for index, choice in choices do
		say(("  %s[%d]%s %s"):format(C.bold, index, C.reset, choice.label))
	end
	say(("  %s[0]%s 취소"):format(C.dim, C.reset))

	while true do
		local input = readCommand("  선택> ")
		if input == nil or input == "0" then
			return nil
		end
		local index = tonumber(input)
		if index and choices[index] then
			return choices[index].value
		end
		say("  " .. C.red .. "잘못된 번호입니다." .. C.reset)
	end
end

--==========================================================================
-- 대상 고르기
--==========================================================================

local function playerLabel(state, id, viewerId)
	return ("%s (라이프 %d)"):format(id == viewerId and "나" or "상대", state.players[id].life)
end

-- 이 효과가 지정할 수 있는 모든 대상
local function targetChoices(state, playerId, effect)
	local out = {}

	local function tryAdd(target, label)
		if Rules.Effects.validateTarget(state, effect, playerId, target) then
			table.insert(out, { label = label, value = target })
		end
	end

	for id = 1, 2 do
		tryAdd({ kind = "Player", id = id }, playerLabel(state, id, playerId))
	end

	for id = 1, 2 do
		for _, instance in GameState.creaturesOnField(state, id) do
			tryAdd(
				{ kind = "Creature", id = instance.id },
				("%s %s"):format(id == playerId and "[아군]" or "[적]", describeField(state, instance))
			)
		end
	end

	for _, item in state.stack do
		local def = Registry.mustGet(GameState.mustGetCard(state, item.instanceId).defId)
		tryAdd({ kind = "StackItem", id = item.id }, ("스택: %s (P%d)"):format(def.name, item.controllerId))
	end

	return out
end

--[[
	마법의 모든 effect 에 대해 대상을 물어본다. -> targets | nil (취소)
]]
local function promptTargets(state, playerId, def)
	if def.type ~= CardType.Spell then
		return {}
	end

	local targets = {}

	for index, effect in def.effects do
		if (effect.target or Enums.TargetKind.None) ~= Enums.TargetKind.None then
			local choices = targetChoices(state, playerId, effect)
			if #choices == 0 then
				say(" " .. C.red .. "지정할 수 있는 대상이 없습니다." .. C.reset)
				return nil
			end

			local chosen = chooseFrom(("%s — 대상 %d"):format(def.name, index), choices)
			if chosen == nil then
				return nil
			end
			targets[index] = chosen
		end
	end

	return targets
end

--==========================================================================
-- 사람 행동
--==========================================================================

local HELP = [[
  숫자      문맥에 맞는 기본 행동 (패 내기 / 공격 선언 / 방어 배정)
  h <번호>  손패에서 카드 내기 (어느 페이즈든)
  e         페이즈 종료
  p         스택 대응 패스 (해결 진행)
  l         최근 로그 보기
  ?         도움말
  q         종료
]]

local function playHandCard(state, playerId, instanceId)
	local def = Registry.mustGet(GameState.mustGetCard(state, instanceId).defId)

	local ok, reason = Rules.canPlayCard(state, playerId, instanceId)
	if not ok then
		say(" " .. C.red .. "불가: " .. tostring(reason) .. C.reset)
		return
	end

	local targets = promptTargets(state, playerId, def)
	if targets == nil then
		say(" " .. C.dim .. "취소했습니다." .. C.reset)
		return
	end

	local played, why = Rules.playCard(state, playerId, instanceId, targets)
	if not played then
		say(" " .. C.red .. "불가: " .. tostring(why) .. C.reset)
	else
		say((" %s%s%s"):format(C.green, def.name .. " 를 냈습니다.", C.reset))
	end
end

local function declareAttackFor(state, playerId, attackerId)
	local attacker = GameState.mustGetCard(state, attackerId)
	local options = Combat.legalAttackTargets(state, attacker)

	if #options == 0 then
		say(" " .. C.red .. "공격할 수 있는 대상이 없습니다. (도발/비행 확인)" .. C.reset)
		return
	end

	local choices = {}
	for _, option in options do
		if option.kind == "Player" then
			table.insert(choices, {
				label = C.red .. "상대 플레이어 직접 공격" .. C.reset,
				value = option,
			})
		else
			table.insert(choices, {
				label = describeField(state, GameState.mustGetCard(state, option.id)),
				value = option,
			})
		end
	end

	local target = chooseFrom(
		("%s 로 무엇을 공격할까요?"):format(Registry.mustGet(attacker.defId).name),
		choices
	)
	if not target then
		return
	end

	local ok, reason = Rules.declareAttacker(state, playerId, attackerId, target)
	if not ok then
		say(" " .. C.red .. "불가: " .. tostring(reason) .. C.reset)
	end
end

local function declareBlockFor(state, playerId, blockerId)
	local blocker = GameState.mustGetCard(state, blockerId)

	local choices = {}
	for _, declaration in state.combat.attackers do
		local attacker = GameState.getCard(state, declaration.id)
		if attacker and Combat.canBlock(state, blocker, attacker) then
			table.insert(choices, {
				label = describeField(state, attacker),
				value = declaration.id,
			})
		end
	end

	if #choices == 0 then
		say(" " .. C.red .. "이 생물이 막을 수 있는 공격자가 없습니다. (비행 확인)" .. C.reset)
		return
	end

	local attackerId = chooseFrom(
		("%s 로 누구를 막을까요?"):format(Registry.mustGet(blocker.defId).name),
		choices
	)
	if not attackerId then
		return
	end

	local ok, reason = Rules.declareBlocker(state, playerId, blockerId, attackerId)
	if not ok then
		say(" " .. C.red .. "불가: " .. tostring(reason) .. C.reset)
	end
end

--[[
	멀리건 관문. 판이 시작되기 전 한 번, 손패를 통째로 바꿀 수 있다 (무료 1회).
	-> "continue" | "quit"
]]
local function humanMulligan(state, playerId)
	renderBoard(state, playerId)

	local used = state.players[playerId].hasMulliganed
	say((" %s이 손패로 시작할까요? %sy = 시작%s%s"):format(
		C.bold,
		C.reset,
		used and "" or ("   %sm = 손패 물리기 (무료 1회)%s"):format(C.magenta, C.reset),
		C.reset
	))

	local input = readCommand(C.bold .. " 명령> " .. C.reset)
	if input == nil or input == "q" then
		return "quit"
	end

	if input == "m" and not used then
		local ok, reason = Rules.mulligan(state, playerId)
		if not ok then
			say(C.red .. tostring(reason) .. C.reset)
		else
			say(C.dim .. "  손패를 물렸습니다" .. C.reset)
		end
		return "continue"
	end

	local ok, reason = Rules.keepHand(state, playerId)
	if not ok then
		say(C.red .. tostring(reason) .. C.reset)
	end
	return "continue"
end

-- -> "continue" | "quit"
local function humanTurn(state, playerId)
	renderBoard(state, playerId)

	local kind, ids = contextList(state, playerId)
	local perms = Phases.permissions(state, playerId)

	-- 힌트 줄
	local hints = {}
	if not Stack.isEmpty(state) then
		table.insert(hints, C.magenta .. "스택 대응 중 — p 로 패스" .. C.reset)
	end
	if perms.endPhase then
		table.insert(hints, "e = " .. Enums.PhaseDisplay[state.phase] .. " 종료")
	end
	table.insert(hints, "? = 도움말")
	say(" " .. table.concat(hints, "   ") .. "\n")

	local input = readCommand(C.bold .. " 명령> " .. C.reset)
	if input == nil or input == "q" then
		return "quit"
	end

	if input == "" then
		return "continue"
	elseif input == "?" then
		say(HELP)
	elseif input == "l" then
		local log = state.log
		for index = math.max(1, #log - 14), #log do
			say(("  %s[T%d] %s%s"):format(C.dim, log[index].turn, log[index].text, C.reset))
		end
	elseif input == "e" then
		local ok, reason = Rules.endPhase(state, playerId)
		if not ok then
			say(" " .. C.red .. "불가: " .. tostring(reason) .. C.reset)
		end
	elseif input == "p" then
		local ok, reason = Rules.pass(state, playerId)
		if not ok then
			say(" " .. C.red .. "불가: " .. tostring(reason) .. C.reset)
		end
	elseif input:match("^h%s*%d+$") then
		local index = tonumber(input:match("%d+"))
		local instanceId = state.players[playerId].hand[index]
		if instanceId then
			playHandCard(state, playerId, instanceId)
		else
			say(" " .. C.red .. "그런 번호의 카드가 없습니다." .. C.reset)
		end
	elseif tonumber(input) then
		local instanceId = ids[tonumber(input)]
		if not instanceId then
			say(" " .. C.red .. "그런 번호가 없습니다." .. C.reset)
		elseif kind == "hand" then
			playHandCard(state, playerId, instanceId)
		elseif kind == "attack" then
			declareAttackFor(state, playerId, instanceId)
		else
			declareBlockFor(state, playerId, instanceId)
		end
	else
		say(" " .. C.red .. "알 수 없는 명령입니다. ? 로 도움말." .. C.reset)
	end

	return "continue"
end

--==========================================================================
-- 진행 루프
--==========================================================================

--[[
	지금 행동해야 하는 플레이어. 스택이 있으면 대응권자, 수비준비면 수비측,
	그 외에는 턴 플레이어.
]]
local function whoActs(state)
	if not Stack.isEmpty(state) then
		return Stack.responderFor(state)
	end
	if state.phase == Phase.DefensePrep then
		return GameState.opponentOf(state.activePlayerId)
	end
	return state.activePlayerId
end

local function main()
	local seed = options.seed or os.time()

	local state = Rules.newMatch({
		seed = seed,
		startingPlayerId = 1,
		players = {
			{ name = options.auto and "AI-1" or "나", deck = Decks.starter() },
			{ name = options.auto and "AI-2" or "적 AI", deck = Decks.starter() },
		},
	})

	say(("%s로블록스 TCG — 싱글플레이%s   (시드 %d)"):format(C.bold, C.reset, seed))
	say(C.dim .. "덱 60장 · 라이프 30 · 선공 첫 턴 드로우 없음" .. C.reset)

	local turnGuard = 0

	while not state.finished do
		turnGuard += 1
		if turnGuard > 5000 then
			say(C.red .. "진행이 멈췄습니다 (룰 버그 가능성)" .. C.reset)
			break
		end

		local mover = whoActs(state)

		if options.auto or mover == ENEMY then
			local acted, description = AI.act(state, mover, AI.Difficulty.Normal)
			if description and (options.auto or mover == ENEMY) then
				local who = state.players[mover].name
				say(("  %s%s: %s%s"):format(C.dim, who, description, C.reset))
			end
			if not acted then
				say(C.red .. "AI 가 둘 수 있는 수가 없습니다 (버그)" .. C.reset)
				break
			end
		else
			-- 대응할 카드가 하나도 없으면 물어보지 않고 자동 패스
			if not Stack.isEmpty(state) and not AI.hasAnyPlayableCard(state, mover) then
				Rules.pass(state, mover)
			elseif state.phase == Phase.Mulligan then
				if humanMulligan(state, mover) == "quit" then
					say("\n종료합니다.")
					return
				end
			else
				if humanTurn(state, mover) == "quit" then
					say("\n종료합니다.")
					return
				end
			end
		end
	end

	--------------------------------------------------------------------
	-- 결과
	--------------------------------------------------------------------
	say()
	say(C.bold .. THICK .. C.reset)
	if state.finished then
		local winner = state.players[state.winnerId]
		local reasonText = ({
			LifeDepleted = "라이프 소진",
			DeckOut = "덱 아웃",
			Concede = "항복",
		})[state.lossReason] or state.lossReason

		local color = (state.winnerId == HUMAN and not options.auto) and C.green or C.red
		say((" %s%s 승리%s   (%s)   %d턴"):format(color, winner.name, C.reset, reasonText, state.turn))
		say((" 최종 라이프  %s %d  /  %s %d"):format(
			state.players[1].name,
			state.players[1].life,
			state.players[2].name,
			state.players[2].life
		))
	end
	say(C.bold .. THICK .. C.reset)
end

main()
