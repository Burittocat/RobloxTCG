--[[
	휴리스틱 AI. PvE 캠페인 상대이자, UI 없이 룰을 굴려보는 스파링 상대.

	설계
	  - 상태를 직접 만지지 않는다. 사람 플레이어와 똑같이 Rules 액션만 호출한다.
	    → AI 가 할 수 있는 일은 정의상 사람도 할 수 있는 일이고, 룰 위반이 불가능하다.
	  - act() 는 "한 번에 한 가지"만 하고 true 를 돌려준다. 호출자가 루프를 돈다.
	    → 각 행동 사이에 연출/딜레이를 끼워넣을 수 있다.

	난이도는 Difficulty 로 조절한다. 지금은 두 단계.
]]

local Rules = require(script.Parent.Rules)

local Enums = Rules.Enums
local Config = Rules.Config
local GameState = Rules.GameState
local Keywords = Rules.Keywords
local Combat = Rules.Combat
local Phases = Rules.Phases
local Registry = Rules.Registry
local CardDef = Rules.CardDef
local Stack = Rules.Stack

local Phase = Enums.Phase

local AI = {}

AI.Difficulty = table.freeze({
	Easy = "Easy", -- 대응(즉시시전)을 쓰지 않는다
	Normal = "Normal", -- 위협적인 주문에 대응한다
})

--==========================================================================
-- 손패 조회
--==========================================================================

local function handCards(state, playerId)
	local out = {}
	for _, instanceId in state.players[playerId].hand do
		local instance = state.cards[instanceId]
		table.insert(out, { instance = instance, def = Registry.mustGet(instance.defId) })
	end
	return out
end

-- 지금 낼 수 있는 카드 중 filter 를 통과하는 것들. 비싼 순.
local function playableCards(state, playerId, filter)
	local out = {}
	for _, entry in handCards(state, playerId) do
		if filter(entry.def) and Rules.canPlayCard(state, playerId, entry.instance.id) then
			table.insert(out, entry)
		end
	end
	table.sort(out, function(a, b)
		return (a.def.cost or 0) > (b.def.cost or 0)
	end)
	return out
end

--==========================================================================
-- 대상 고르기
--==========================================================================

--[[
	마법 한 장의 effects 에 맞는 대상을 자동으로 고른다. -> targets | nil

	"적에게 나쁜 일"은 상대의 가장 위협적인 생물에게, "아군에게 좋은 일"은
	내 가장 좋은 생물에게 건다. 대상을 못 찾으면 nil → 그 카드는 쓰지 않는다.
]]
local function chooseTargets(state, playerId, def)
	local opponentId = GameState.opponentOf(playerId)

	-- 위협도 = 공격력 우선, 동률이면 남은 체력
	local function threat(instance)
		return Keywords.power(instance) * 10 + Keywords.remainingToughness(instance)
	end

	local function pickCreature(ownerId)
		local best, bestScore
		for _, instance in GameState.creaturesOnField(state, ownerId) do
			local score = threat(instance)
			if not bestScore or score > bestScore then
				best, bestScore = instance, score
			end
		end
		return best
	end

	local targets = {}

	for index, effect in def.effects do
		local want = effect.target or Enums.TargetKind.None
		local chosen

		if want == Enums.TargetKind.None then
			chosen = nil
		elseif want == Enums.TargetKind.SelfPlayer then
			chosen = { kind = "Player", id = playerId }
		elseif want == Enums.TargetKind.EnemyPlayer then
			chosen = { kind = "Player", id = opponentId }
		elseif want == Enums.TargetKind.EnemyCreature then
			local creature = pickCreature(opponentId)
			if not creature then
				return nil
			end
			chosen = { kind = "Creature", id = creature.id }
		elseif want == Enums.TargetKind.AllyCreature then
			local creature = pickCreature(playerId)
			if not creature then
				return nil
			end
			chosen = { kind = "Creature", id = creature.id }
		elseif want == Enums.TargetKind.AnyCreature then
			local creature = pickCreature(opponentId) or pickCreature(playerId)
			if not creature then
				return nil
			end
			chosen = { kind = "Creature", id = creature.id }
		elseif want == Enums.TargetKind.CreatureOrPlayer then
			-- 확실히 죽일 수 있는 생물이 있으면 그쪽, 없으면 얼굴
			local creature = pickCreature(opponentId)
			local amount = effect.amount or 0
			if creature and Keywords.remainingToughness(creature) <= amount then
				chosen = { kind = "Creature", id = creature.id }
			else
				chosen = { kind = "Player", id = opponentId }
			end
		elseif want == Enums.TargetKind.StackItem then
			local top = Stack.top(state)
			if not top or top.controllerId == playerId then
				return nil
			end
			chosen = { kind = "StackItem", id = top.id }
		else
			return nil
		end

		targets[index] = chosen
	end

	return targets
end

--==========================================================================
-- 공격 판단
--==========================================================================

--[[
	이 생물로 무엇을 칠지 고른다. -> target | nil (공격하지 않음)

	1순위: 플레이어 직접 공격 (게임을 끝내는 유일한 길)
	2순위: 내가 죽지 않으면서 잡을 수 있는 생물
	그 외: 공격하지 않고 방어에 남긴다
]]
local function chooseAttack(state, attacker)
	local options = Combat.legalAttackTargets(state, attacker)

	for _, option in options do
		if option.kind == "Player" then
			return option
		end
	end

	local myPower = Keywords.power(attacker)
	local myLife = Keywords.remainingToughness(attacker)

	local best, bestScore
	for _, option in options do
		local target = GameState.getCard(state, option.id)
		if target then
			local kills = myPower >= Keywords.remainingToughness(target)
			local dies = Config.tappedCreaturesStrikeBack or not target.tapped
			dies = dies and Keywords.power(target) >= myLife

			local score
			if kills and not dies then
				score = 3 -- 일방적으로 잡는다
			elseif kills and dies then
				score = 1 -- 트레이드
			else
				score = -1 -- 손해
			end

			if score > 0 and (not bestScore or score > bestScore) then
				best, bestScore = option, score
			end
		end
	end

	return best
end

--==========================================================================
-- 방어 판단
--==========================================================================

--[[
	아직 방어를 배정하지 않은 공격자 하나를 막는다. -> ok

	살아남으면서 잡을 수 있으면 최우선. 라이프가 위험하면 몸빵도 한다.
]]
local function assignOneBlock(state, playerId)
	local myLife = state.players[playerId].life

	-- 이번 전투로 들어올 총 피해
	local incoming = 0
	for _, declaration in state.combat.attackers do
		if not state.combat.blocks[declaration.id] and declaration.targetKind == "Player" then
			local attacker = GameState.getCard(state, declaration.id)
			if attacker then
				incoming += Combat.directDamageToPlayer(attacker)
			end
		end
	end
	local desperate = incoming >= myLife

	for _, declaration in state.combat.attackers do
		local attacker = GameState.getCard(state, declaration.id)
		if attacker then
			-- 이 공격자가 이미 막혀 있는가
			local alreadyBlocked = false
			for _, attackerId in state.combat.blocks do
				if attackerId == declaration.id then
					alreadyBlocked = true
					break
				end
			end

			if not alreadyBlocked then
				local attackerPower = Keywords.power(attacker)
				local best, bestScore

				for _, blocker in Combat.legalBlockers(state, attacker) do
					if not state.combat.blocks[blocker.id] then
						local survives = attackerPower < Keywords.remainingToughness(blocker)
						local kills = Keywords.power(blocker) >= Keywords.remainingToughness(attacker)

						local score
						if survives and kills then
							score = 4
						elseif kills then
							score = 3 -- 트레이드
						elseif survives then
							score = 2 -- 막기만
						elseif desperate then
							score = 1 -- 몸빵
						else
							score = -1
						end

						if score > 0 and (not bestScore or score > bestScore) then
							best, bestScore = blocker, score
						end
					end
				end

				if best then
					local ok = Rules.declareBlocker(state, playerId, best.id, declaration.id)
					if ok then
						return true
					end
				end
			end
		end
	end

	return false
end

--==========================================================================
-- 한 수 두기
--==========================================================================

--[[
	AI 가 지금 할 수 있는 일 한 가지를 한다. -> acted: boolean, 설명: string?

	호출자는 acted 가 false 가 되거나 차례가 넘어갈 때까지 반복하면 된다.
]]
--[[
	이 손패를 물릴 것인가.

	사람이 실제로 물리는 손패만 물린다 — **코스트가 너무 적거나 너무 많은 패**다.
	코스트가 0~1 장이면 몇 턴 동안 아무것도 못 내고, 5 장 넘게 잡으면 낼 것이 없다.
	그 사이는 어떻게든 판이 굴러가므로 건드리지 않는다.

	(카드 풀이 넓어지고 덱 구성이 생기면 여기도 덱을 보고 판단해야 한다.
	 지금은 스타터 덱 하나뿐이라 코스트 장수만으로 충분하다.)
]]
function AI.shouldMulligan(state, playerId)
	local costCards = 0
	for _, instanceId in state.players[playerId].hand do
		if CardDef.isCost(Registry.mustGet(state.cards[instanceId].defId)) then
			costCards += 1
		end
	end

	return costCards <= Config.aiMulliganMinCost or costCards >= Config.aiMulliganMaxCost
end

function AI.act(state, playerId, difficulty)
	difficulty = difficulty or AI.Difficulty.Normal

	if state.finished then
		return false
	end

	--------------------------------------------------------------------
	-- 멀리건 관문
	--------------------------------------------------------------------
	if state.phase == Phase.Mulligan then
		if playerId ~= state.activePlayerId then
			return false
		end

		if not state.players[playerId].hasMulliganed and AI.shouldMulligan(state, playerId) then
			Rules.mulligan(state, playerId)
			return true, "손패를 물렸다"
		end

		Rules.keepHand(state, playerId)
		return true, "이 손패로 시작"
	end

	--------------------------------------------------------------------
	-- 스택 대응
	--------------------------------------------------------------------
	if not Stack.isEmpty(state) then
		if Stack.responderFor(state) ~= playerId then
			return false
		end

		if difficulty == AI.Difficulty.Normal then
			-- 상대의 소환/마법이 스택에 있으면 무효화 계열을 고려한다
			for _, entry in playableCards(state, playerId, CardDef.isInstant) do
				local targets = chooseTargets(state, playerId, entry.def)
				if targets and Rules.playCard(state, playerId, entry.instance.id, targets) then
					return true, ("대응 — %s"):format(entry.def.name)
				end
			end
		end

		Rules.pass(state, playerId)
		return true, "대응하지 않음"
	end

	local perms = Phases.permissions(state, playerId)

	--------------------------------------------------------------------
	-- 자기 메인 페이즈: 코스트 → 생물 → 마법
	--------------------------------------------------------------------
	if state.phase == Phase.Main and playerId == state.activePlayerId then
		if perms.playCost then
			local costCards = playableCards(state, playerId, CardDef.isCost)
			if costCards[1] then
				Rules.playCard(state, playerId, costCards[1].instance.id)
				return true, ("%s 를 냈다"):format(costCards[1].def.name)
			end
		end

		if perms.summonCreature then
			local creatures = playableCards(state, playerId, CardDef.isCreature)
			if creatures[1] then
				Rules.playCard(state, playerId, creatures[1].instance.id)
				return true, ("%s 소환"):format(creatures[1].def.name)
			end
		end

		-- 즉시시전은 대응용으로 아껴둔다 → 일반 마법만 메인에서 쓴다
		for _, entry in playableCards(state, playerId, function(def)
			return CardDef.isSpell(def) and not CardDef.isInstant(def)
		end) do
			local targets = chooseTargets(state, playerId, entry.def)
			if targets and Rules.playCard(state, playerId, entry.instance.id, targets) then
				return true, ("%s 시전"):format(entry.def.name)
			end
		end
	end

	--------------------------------------------------------------------
	-- 공격 선언
	--------------------------------------------------------------------
	if perms.declareAttackers then
		for _, attacker in GameState.creaturesOnField(state, playerId) do
			local alreadyDeclared = false
			for _, declaration in state.combat.attackers do
				if declaration.id == attacker.id then
					alreadyDeclared = true
					break
				end
			end

			if not alreadyDeclared and Combat.canAttack(state, attacker) then
				local target = chooseAttack(state, attacker)
				if target and Rules.declareAttacker(state, playerId, attacker.id, target) then
					local what = (target.kind == "Player") and "플레이어"
						or Registry.mustGet(GameState.mustGetCard(state, target.id).defId).name
					return true, ("%s → %s 공격"):format(Registry.mustGet(attacker.defId).name, what)
				end
			end
		end
	end

	--------------------------------------------------------------------
	-- 방어 배정
	--------------------------------------------------------------------
	if perms.declareBlockers then
		if assignOneBlock(state, playerId) then
			return true, "방어 배정"
		end
	end

	--------------------------------------------------------------------
	-- 더 할 게 없으면 페이즈 종료
	--------------------------------------------------------------------
	if perms.endPhase then
		-- endPhase 는 즉시 다음 페이즈로 넘어가므로 이름을 먼저 찍어둔다.
		local ended = Enums.PhaseDisplay[state.phase] or "페이즈"
		Rules.endPhase(state, playerId)
		return true, ("%s 종료"):format(ended)
	end

	return false
end

--[[
	AI 차례가 끝날 때까지 계속 둔다.

	onAction(설명) 이 주어지면 수마다 불러준다 — 로그/연출용.
]]
function AI.playUntilStuck(state, playerId, difficulty, onAction)
	local guard = 0

	while not state.finished do
		guard += 1
		if guard > 256 then
			error("AI.playUntilStuck: 수가 끝나지 않습니다 (AI 또는 룰 버그)")
		end

		local acted, description = AI.act(state, playerId, difficulty)
		if not acted then
			break
		end
		if onAction and description then
			onAction(description)
		end
	end
end

--[[
	이 플레이어가 지금 둘 수 있는 수가 하나라도 있는가.

	사람 플레이어에게 "대응할 카드가 없으니 자동 패스" 를 해줄 때 쓴다.
]]
function AI.hasAnyPlayableCard(state, playerId)
	for _, instanceId in state.players[playerId].hand do
		if Rules.canPlayCard(state, playerId, instanceId) then
			return true
		end
	end
	return false
end

return AI
