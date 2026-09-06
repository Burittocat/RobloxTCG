--[[
	룰 엔진 진입점.

	외부(서버 / AI / 테스트)는 이 모듈의 액션 함수만 호출한다. 상태를 직접 만지지 않는다.
	모든 액션은 같은 모양이다:

	    local ok, reason = Rules.<액션>(state, playerId, ...)

	검증과 적용이 한 함수 안에 있으므로 "클라에서는 됐는데 서버에서 거부됨"이 생기지 않는다.
	클라이언트는 같은 코드로 can* 함수를 불러 버튼을 켜고 끈다.
]]

local Enums = require(script.Enums)
local Config = require(script.Config)
local RNG = require(script.RNG)
local CardDef = require(script.CardDef)
local Registry = require(script.Registry)
local Keywords = require(script.Keywords)
local GameState = require(script.GameState)
local Combat = require(script.Combat)
local Phases = require(script.Phases)
local Effects = require(script.Effects)
local Stack = require(script.Stack)

local Phase = Enums.Phase
local Zone = Enums.Zone
local CardType = Enums.CardType

local Rules = {
	Enums = Enums,
	Config = Config,
	RNG = RNG,
	CardDef = CardDef,
	Registry = Registry,
	Keywords = Keywords,
	GameState = GameState,
	Combat = Combat,
	Phases = Phases,
	Effects = Effects,
	Stack = Stack,
}

--==========================================================================
-- 매치 생명주기
--==========================================================================

function Rules.newMatch(opts)
	local state = GameState.new(opts)
	Phases.beginMatch(state)
	return state
end

function Rules.concede(state, playerId)
	GameState.setLoser(state, playerId, Enums.LossReason.Concede)
	return true
end

--==========================================================================
-- 카드 내기
--==========================================================================

--[[
	이 카드를 지금 낼 수 있는가. -> ok, reason

	스택에 뭔가 올라가 있으면 "대응"만 가능하다(즉시시전 전용).
	비어 있으면 페이즈 권한을 따른다.
]]
function Rules.canPlayCard(state, playerId, instanceId)
	if state.finished then
		return false, "이미 끝난 게임입니다"
	end

	local instance = GameState.getCard(state, instanceId)
	if not instance then
		return false, "존재하지 않는 카드입니다"
	end
	if instance.zone ~= Zone.Hand or instance.controllerId ~= playerId then
		return false, "손에 없는 카드입니다"
	end

	local def = Registry.mustGet(instance.defId)

	--------------------------------------------------------------------
	-- 스택 대응 창
	--------------------------------------------------------------------
	if not Stack.isEmpty(state) then
		if playerId ~= Stack.responderFor(state) then
			return false, "지금 대응권은 상대에게 있습니다"
		end
		if not CardDef.isInstant(def) then
			return false, "대응에는 '즉시시전' 마법만 쓸 수 있습니다"
		end
		if GameState.availableCost(state, playerId) < def.cost then
			return false, "코스트가 부족합니다"
		end
		return true
	end

	--------------------------------------------------------------------
	-- 평시
	--------------------------------------------------------------------
	local perms = Phases.permissions(state, playerId)

	if def.type == CardType.Cost then
		if not perms.playCost then
			local player = state.players[playerId]
			if player.costPlayedThisTurn >= Config.costCardsPerTurn then
				return false, ("코스트 카드는 1턴에 %d 장만 낼 수 있습니다"):format(Config.costCardsPerTurn)
			end
			return false, "지금은 코스트 카드를 낼 수 없습니다"
		end
		return true
	end

	if def.type == CardType.Creature then
		if not perms.summonCreature then
			return false, "지금은 생물을 소환할 수 없습니다"
		end
		if GameState.availableCost(state, playerId) < def.cost then
			return false, "코스트가 부족합니다"
		end
		return true
	end

	-- 마법
	local isInstant = CardDef.isInstant(def)
	if isInstant and not perms.castInstantSpell then
		return false, "지금은 즉시시전 마법을 쓸 수 없습니다"
	end
	if not isInstant and not perms.castNormalSpell then
		return false, "일반 마법은 자신의 메인 페이즈(또는 수비준비)에만 쓸 수 있습니다"
	end
	if state.phase == Phase.DefensePrep and not CardDef.usableInDefensePhase(def) then
		return false, "이 카드는 수비준비 페이즈에 쓸 수 없습니다"
	end
	if GameState.availableCost(state, playerId) < def.cost then
		return false, "코스트가 부족합니다"
	end

	return true
end

--[[
	카드를 낸다. -> ok, reason

	코스트 카드는 스택을 타지 않고 즉시 필드로 간다(자원이라 대응 대상이 아니다).
	생물/마법은 스택에 올라가 상대의 즉시시전 대응을 받는다.

	targets: 마법의 effects 와 같은 길이의 대상 배열. 생물/코스트는 nil.
]]
function Rules.playCard(state, playerId, instanceId, targets)
	local ok, reason = Rules.canPlayCard(state, playerId, instanceId)
	if not ok then
		return false, reason
	end

	local instance = GameState.mustGetCard(state, instanceId)
	local def = Registry.mustGet(instance.defId)

	--------------------------------------------------------------------
	-- 코스트 카드: 즉시 필드로
	--------------------------------------------------------------------
	if def.type == CardType.Cost then
		GameState.moveCard(state, instance, Zone.Field, nil, playerId)
		instance.tapped = not Config.costCardEntersUntapped
		state.players[playerId].costPlayedThisTurn += 1
		GameState.log(state, ("코스트 카드 소환: %s"):format(def.name))
		return true
	end

	--------------------------------------------------------------------
	-- 마법: 대상 검증을 먼저 (코스트를 낸 뒤 거부하면 안 된다)
	--------------------------------------------------------------------
	if def.type == CardType.Spell then
		for index, effect in def.effects do
			local targetOk, targetReason = Effects.validateTarget(state, effect, playerId, targets and targets[index])
			if not targetOk then
				return false, ("대상 오류: %s"):format(targetReason or "?")
			end
		end
	end

	if not GameState.payCost(state, playerId, def.cost) then
		return false, "코스트가 부족합니다"
	end

	Stack.push(state, {
		kind = (def.type == CardType.Creature) and "Summon" or "Spell",
		instanceId = instanceId,
		controllerId = playerId,
		targets = targets,
	})

	return true
end

--[[
	대응하지 않고 넘긴다 → 스택 맨 위가 해결된다. -> ok, reason
]]
function Rules.pass(state, playerId)
	if state.finished then
		return false, "이미 끝난 게임입니다"
	end
	return Stack.pass(state, playerId)
end

--==========================================================================
-- 공격 선언 (공격준비 페이즈)
--==========================================================================

--[[
	target = { kind = "Player", id = playerId } | { kind = "Creature", id = instanceId }
]]
function Rules.declareAttacker(state, playerId, attackerId, target)
	if state.finished then
		return false, "이미 끝난 게임입니다"
	end
	if state.phase ~= Phase.AttackPrep then
		return false, "공격준비 페이즈가 아닙니다"
	end
	if playerId ~= state.activePlayerId then
		return false, "자기 턴이 아닙니다"
	end
	if not Stack.isEmpty(state) then
		return false, "스택을 먼저 해결해야 합니다"
	end

	local attacker = GameState.getCard(state, attackerId)
	if not attacker then
		return false, "존재하지 않는 카드입니다"
	end

	for _, declaration in state.combat.attackers do
		if declaration.id == attackerId then
			return false, "이미 공격을 선언한 생물입니다"
		end
	end

	local ok, reason
	if target and target.kind == "Creature" then
		ok, reason = Combat.canAttackCreature(state, attacker, GameState.getCard(state, target.id))
	else
		target = target or { kind = "Player", id = GameState.opponentOf(playerId) }
		ok, reason = Combat.canAttackPlayer(state, attacker, target.id)
	end

	if not ok then
		return false, reason
	end

	table.insert(state.combat.attackers, {
		id = attackerId,
		targetKind = target.kind,
		targetId = target.id,
	})

	GameState.log(state, ("공격 선언: %s"):format(Registry.mustGet(attacker.defId).name))
	return true
end

function Rules.clearAttackers(state, playerId)
	if state.phase ~= Phase.AttackPrep or playerId ~= state.activePlayerId then
		return false, "지금은 공격 선언을 취소할 수 없습니다"
	end
	state.combat.attackers = {}
	return true
end

--==========================================================================
-- 방어 배정 (수비준비 페이즈)
--==========================================================================

function Rules.declareBlocker(state, playerId, blockerId, attackerId)
	if state.finished then
		return false, "이미 끝난 게임입니다"
	end
	if state.phase ~= Phase.DefensePrep then
		return false, "수비준비 페이즈가 아닙니다"
	end
	if playerId == state.activePlayerId then
		return false, "공격측은 방어를 배정할 수 없습니다"
	end
	if not Stack.isEmpty(state) then
		return false, "스택을 먼저 해결해야 합니다"
	end

	local blocker = GameState.getCard(state, blockerId)
	local attacker = GameState.getCard(state, attackerId)
	if not blocker or not attacker then
		return false, "존재하지 않는 카드입니다"
	end

	local isAttacking = false
	for _, declaration in state.combat.attackers do
		if declaration.id == attackerId then
			isAttacking = true
			break
		end
	end
	if not isAttacking then
		return false, "공격을 선언하지 않은 생물입니다"
	end

	if state.combat.blocks[blockerId] then
		return false, "이미 방어를 배정한 생물입니다"
	end

	local blockersOnAttacker = 0
	for _, assignedAttackerId in state.combat.blocks do
		if assignedAttackerId == attackerId then
			blockersOnAttacker += 1
		end
	end
	if blockersOnAttacker >= Config.maxBlockersPerAttacker then
		return false, ("공격자 하나는 최대 %d 마리까지 막을 수 있습니다"):format(Config.maxBlockersPerAttacker)
	end

	local ok, reason = Combat.canBlock(state, blocker, attacker)
	if not ok then
		return false, reason
	end

	state.combat.blocks[blockerId] = attackerId
	GameState.log(state, ("방어 배정: %s"):format(Registry.mustGet(blocker.defId).name))
	return true
end

function Rules.clearBlockers(state, playerId)
	if state.phase ~= Phase.DefensePrep or playerId == state.activePlayerId then
		return false, "지금은 방어 배정을 취소할 수 없습니다"
	end
	state.combat.blocks = {}
	return true
end

--==========================================================================
-- 페이즈 종료
--==========================================================================

function Rules.endPhase(state, playerId)
	if state.finished then
		return false, "이미 끝난 게임입니다"
	end
	if not Stack.isEmpty(state) then
		return false, "스택을 먼저 해결해야 합니다"
	end

	local perms = Phases.permissions(state, playerId)
	if not perms.endPhase then
		return false, "지금 이 페이즈를 끝낼 권한이 없습니다"
	end

	Phases.advance(state)
	return true
end

--==========================================================================
-- 클라이언트 뷰
--==========================================================================

--[[
	playerId 에게 보여줄 상태만 남긴 사본.

	상대 손패와 양쪽 덱은 카드 id 를 지우고 장수만 남긴다.
	서버가 전체 상태를 그대로 복제하면 클라이언트에서 상대 패를 읽어버린다.
]]
function Rules.viewFor(state, playerId)
	local view = {
		turn = state.turn,
		phase = state.phase,
		activePlayerId = state.activePlayerId,
		priorityPlayerId = state.priorityPlayerId,
		finished = state.finished,
		winnerId = state.winnerId,
		lossReason = state.lossReason,
		viewerId = playerId,
		stack = {},
		combat = state.combat,
		cards = {},
		players = {},
	}

	local function exposeCard(instanceId)
		local instance = state.cards[instanceId]
		view.cards[instanceId] = {
			id = instance.id,
			defId = instance.defId,
			ownerId = instance.ownerId,
			controllerId = instance.controllerId,
			zone = instance.zone,
			tapped = instance.tapped,
			damage = instance.damage,
			powerMod = instance.powerMod,
			toughnessMod = instance.toughnessMod,
			grantedKeywords = instance.grantedKeywords,
			summonedOnTurn = instance.summonedOnTurn,
		}
	end

	for id, player in state.players do
		local isViewer = (id == playerId)

		local publicPlayer = {
			id = id,
			name = player.name,
			life = player.life,
			deckCount = #player.deck,
			handCount = #player.hand,
			field = table.clone(player.field),
			graveyard = table.clone(player.graveyard),
			hand = isViewer and table.clone(player.hand) or nil,
			costPlayedThisTurn = player.costPlayedThisTurn,
		}

		view.players[id] = publicPlayer

		-- 공개 존만 카드 정보를 내려보낸다.
		for _, instanceId in player.field do
			exposeCard(instanceId)
		end
		for _, instanceId in player.graveyard do
			exposeCard(instanceId)
		end
		if isViewer then
			for _, instanceId in player.hand do
				exposeCard(instanceId)
			end
		end
	end

	for index, item in state.stack do
		exposeCard(item.instanceId)
		view.stack[index] = {
			id = item.id,
			kind = item.kind,
			instanceId = item.instanceId,
			controllerId = item.controllerId,
			targets = item.targets,
		}
	end

	return view
end

return Rules
