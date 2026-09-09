--[[
	전투 판정: 누가 누구를 공격/방어할 수 있는가, 그리고 데미지 해결.

	기획서의 태그 규칙을 여기 한 곳에 모았다. 원문 대응은 각 함수 주석 참조.

	  신속   - 소환 멀미 무시 (canAttack)
	  비행   - 지상 비원거리는 공격도 방어도 못 함 (canAttackCreature / canBlock)
	  도발   - 플레이어 직접 공격 차단 (canAttackPlayer)
	  원거리 - 비행 상대 가능 + 도발 무시, 대신 플레이어 직공 데미지 절반
	  즉시시전 - 마법 전용이라 여기 없음 (Stack 담당)
]]

local Enums = require(script.Parent.Enums)
local Config = require(script.Parent.Config)
local GameState = require(script.Parent.GameState)
local Keywords = require(script.Parent.Keywords)
local Registry = require(script.Parent.Registry)

local Zone = Enums.Zone
local CardType = Enums.CardType

local Combat = {}

--==========================================================================
-- 기본 조건
--==========================================================================

local function isCreatureOnField(instance)
	return instance ~= nil
		and instance.zone == Zone.Field
		and Registry.mustGet(instance.defId).type == CardType.Creature
end

--[[
	소환 멀미: 이번 턴에 소환된 생물은 행동할 수 없다.
	기획서의 "신속 태그가 있는 생물은 ... 탭단 없이 해당 턴에 바로 공격페이즈를 진행"
	이 이 제한의 예외다.
]]
function Combat.hasSummoningSickness(state, instance)
	return instance.summonedOnTurn == state.turn
end

--==========================================================================
-- 공격 선언
--==========================================================================

--[[
	이 생물이 공격 선언 자체를 할 수 있는가. -> ok, reason
	(대상 적법성은 별도 — canAttackPlayer / canAttackCreature)
]]
function Combat.canAttack(state, instance)
	if not isCreatureOnField(instance) then
		return false, "필드 위의 생물이 아닙니다"
	end
	if instance.controllerId ~= state.activePlayerId then
		return false, "자기 턴이 아닙니다"
	end
	if instance.tapped then
		return false, "탭된 생물은 공격할 수 없습니다"
	end
	if Combat.hasSummoningSickness(state, instance) and not Keywords.isHaste(instance) then
		return false, "이번 턴에 소환된 생물입니다 ('신속' 필요)"
	end
	if Keywords.power(instance) <= 0 then
		return false, "공격력이 0 인 생물은 공격할 수 없습니다"
	end
	return true
end

--[[
	플레이어 직접 공격 가능 여부. -> ok, reason

	기획서(도발): "'도발' 태그가 붙어있는 생물체가 전장에 있다면 그 생물체를
	              덱이나 더미로 보내지 않는한 상대 플레이어를 우선하여 공격 할 수 없다"
	기획서(원거리): "'원거리' 태그의 생물체는 '도발' 태그를 무시할 수 있다"
]]
function Combat.canAttackPlayer(state, attacker, defenderId)
	local ok, reason = Combat.canAttack(state, attacker)
	if not ok then
		return false, reason
	end

	if Config.tauntBlocksDirectAttack
		and GameState.hasTaunt(state, defenderId)
		and not Keywords.isRanged(attacker)
	then
		return false, "상대 필드에 '도발' 생물이 있습니다 ('원거리'만 무시 가능)"
	end

	return true
end

--[[
	적 생물을 직접 겨냥할 수 있는가. -> ok, reason

	기획서(비행): "지상의 생물체가 '원거리' 태그가 없다면 '비행' 태그의 적을 공격할 수 없다"
	              → 공격자가 비행이거나 원거리면 비행을 겨냥할 수 있다.
]]
function Combat.canAttackCreature(state, attacker, target)
	local ok, reason = Combat.canAttack(state, attacker)
	if not ok then
		return false, reason
	end

	if not isCreatureOnField(target) then
		return false, "대상이 필드 위의 생물이 아닙니다"
	end
	if target.controllerId == attacker.controllerId then
		return false, "아군 생물은 공격할 수 없습니다"
	end

	if Config.groundCannotAttackFlying and Keywords.isFlying(target) then
		if Keywords.isGround(attacker) and not Keywords.isRanged(attacker) then
			return false, "지상 생물은 '비행' 생물을 공격할 수 없습니다 ('비행' 또는 '원거리' 필요)"
		end
	end

	return true
end

--[[
	이 공격자가 고를 수 있는 합법 대상 전부.
	-> { { kind = "Player", id = playerId } | { kind = "Creature", id = instanceId }, ... }

	클라이언트 UI 가 하이라이트할 대상을 이 함수 하나로 뽑는다.
	서버 검증과 같은 코드를 쓰므로 "눌렀는데 거부당함"이 생기지 않는다.
]]
function Combat.legalAttackTargets(state, attacker)
	local out = {}
	local defenderId = GameState.opponentOf(attacker.controllerId)

	if Combat.canAttackPlayer(state, attacker, defenderId) then
		table.insert(out, { kind = "Player", id = defenderId })
	end

	for _, target in GameState.creaturesOnField(state, defenderId) do
		if Combat.canAttackCreature(state, attacker, target) then
			table.insert(out, { kind = "Creature", id = target.id })
		end
	end

	return out
end

--==========================================================================
-- 방어 배정
--==========================================================================

--[[
	blocker 가 attacker 를 막을 수 있는가. -> ok, reason

	기획서(비행): "'비행' 태그의 적이 공격 페이즈를 진행할때 공격받는 생물이
	              '원거리' 태그를 가지고 있지 않다면 '비행' 태그의 적을 수비 할 수 없다"

	★ 문자 그대로면 비행끼리도 서로 못 막아 비행이 사실상 무적이 된다.
	   Config.flyingCanBlockFlying 로 비행 방어를 허용해뒀다(기본 true).
]]
function Combat.canBlock(state, blocker, attacker)
	if not isCreatureOnField(blocker) then
		return false, "필드 위의 생물이 아닙니다"
	end
	if not isCreatureOnField(attacker) then
		return false, "공격자가 필드에 없습니다"
	end
	if blocker.controllerId == attacker.controllerId then
		return false, "아군 공격을 막을 수 없습니다"
	end
	if blocker.tapped then
		return false, "탭된 생물은 방어할 수 없습니다"
	end

	if Keywords.isFlying(attacker) then
		local canReach = Keywords.isRanged(blocker)
			or (Config.flyingCanBlockFlying and Keywords.isFlying(blocker))
		if not canReach then
			return false, "'비행' 공격자는 '원거리'(또는 '비행')만 방어할 수 있습니다"
		end
	end

	return true
end

-- 이 공격자를 막을 수 있는 방어측 생물 전부
function Combat.legalBlockers(state, attacker)
	local out = {}
	local defenderId = GameState.opponentOf(attacker.controllerId)

	for _, blocker in GameState.creaturesOnField(state, defenderId) do
		if Combat.canBlock(state, blocker, attacker) then
			table.insert(out, blocker)
		end
	end

	return out
end

--==========================================================================
-- 데미지 계산
--==========================================================================

--[[
	기획서(원거리): "'원거리' 태그의 생물체가 플레이어를 직접 공격하면
	                 공격력 수치의 반만 적용되어 데미지가 들어간다"
	★ 반올림 방향 미지정 → Config.rangedDirectDamageRounding (기본 내림)
]]
function Combat.directDamageToPlayer(attacker)
	local power = Keywords.power(attacker)

	if not Keywords.isRanged(attacker) then
		return power
	end

	local halved = power / Config.rangedDirectDamageDivisor
	if Config.rangedDirectDamageRounding == "ceil" then
		return math.ceil(halved)
	end
	return math.floor(halved)
end

--==========================================================================
-- 공수 페이즈 해결
--==========================================================================

--[[
	공격력을 방어자들에게 나눈다. -> { { blocker, damage }, ... }

	**공격자가 자기에게 유리하게 배분한 것으로 친다** — 죽일 수 있는 것부터 치사에
	필요한 만큼만 주고, 남으면 마지막 방어자에게 몰아준다.
	(3 공격력이 1/1 과 1/5 에게 막히면 1/1 을 죽이고 2 가 1/5 에게 간다)

	배분 순서를 사람에게 물어보는 게 정석이지만, 그러려면 수비준비가 끝난 뒤에 공격측
	입력 창이 하나 더 필요하다. 물어보지 않고 정하되 **공격측에 유리한 쪽**으로 고정했다 —
	겹쳐 막을지는 방어측이 이미 고른 것이라, 배분까지 방어측에 유리하게 두면
	겹쳐 막기가 언제나 이득이 된다.

	AI 도 이 함수로 "겹쳐 막으면 몇 마리를 잃는가" 를 미리 재본다. 판정이 두 벌이면
	AI 가 예상한 것과 실제 결과가 어긋난다.
]]
function Combat.splitAmongBlockers(attackerPower, blockers)
	local order = table.clone(blockers)
	table.sort(order, function(a, b)
		local left, right = Keywords.remainingToughness(a), Keywords.remainingToughness(b)
		if left ~= right then
			return left < right
		end
		return a.id < b.id
	end)

	local out = {}
	local remaining = attackerPower

	for index, blocker in order do
		local share = (index == #order) and remaining or math.min(remaining, Keywords.remainingToughness(blocker))
		remaining -= share
		table.insert(out, { blocker = blocker, damage = share })
	end

	return out
end

--[[
	선언된 공격/방어를 전부 해결한다. -> events

	데미지는 "전부 계산한 뒤 한꺼번에 적용"한다. 순차 적용하면
	먼저 죽은 생물이 반격을 못 해서 트레이드 결과가 선언 순서에 좌우된다.
]]
function Combat.resolve(state)
	local events = {}
	local pendingCreatureDamage = {} -- [instanceId] = 누적 피해
	local pendingPlayerDamage = {} -- [playerId] = 누적 피해

	local function addCreatureDamage(instance, amount)
		if amount <= 0 then
			return
		end
		pendingCreatureDamage[instance.id] = (pendingCreatureDamage[instance.id] or 0) + amount
	end

	local function addPlayerDamage(playerId, amount)
		if amount <= 0 then
			return
		end
		pendingPlayerDamage[playerId] = (pendingPlayerDamage[playerId] or 0) + amount
	end

	--[[
		공격자 → 방어자들. 한 공격자를 **여러 마리가 함께 막을 수 있다**
		(Config.maxBlockersPerAttacker).

		순서는 인스턴스 번호로 고정한다. blocks 는 딕셔너리라 순회 순서가 보장되지 않는데,
		아래 배분이 순서를 보므로 그대로 두면 같은 판이 매번 다르게 끝난다.
	]]
	local blockersOf = {}
	for blockerId, attackerId in state.combat.blocks do
		local blocker = GameState.getCard(state, blockerId)
		if isCreatureOnField(blocker) then
			blockersOf[attackerId] = blockersOf[attackerId] or {}
			table.insert(blockersOf[attackerId], blocker)
		end
	end
	for _, blockers in blockersOf do
		table.sort(blockers, function(a, b)
			return a.id < b.id
		end)
	end

	for _, declaration in state.combat.attackers do
		local attacker = GameState.getCard(state, declaration.id)

		-- 즉시시전 등으로 공격 선언 후 필드를 떠났을 수 있다.
		if not isCreatureOnField(attacker) then
			table.insert(events, { kind = "AttackFizzled", attackerId = declaration.id })
			continue
		end

		local attackerPower = Keywords.power(attacker)
		local blockers = blockersOf[attacker.id]

		if blockers and #blockers > 0 then
			----------------------------------------------------------------
			-- 방어당함: 공격자 ↔ 방어자들 상호 피해
			----------------------------------------------------------------

			--[[
				공격력은 splitAmongBlockers 가 나눈다(그 주석 참조).
				방어자는 저마다 공격력을 그대로 공격자에게 돌려준다 — 겹쳐 막으면
				공격자가 죽는다. 그게 겹쳐 막는 이유다.
			]]
			for _, share in Combat.splitAmongBlockers(attackerPower, blockers) do
				addCreatureDamage(share.blocker, share.damage)
				addCreatureDamage(attacker, Keywords.power(share.blocker))

				table.insert(events, {
					kind = "Blocked",
					attackerId = attacker.id,
					blockerId = share.blocker.id,
					damageToBlocker = share.damage,
					damageToAttacker = Keywords.power(share.blocker),
				})
			end
		elseif declaration.targetKind == "Player" then
			----------------------------------------------------------------
			-- 무방비 직접 공격: 원거리는 절반
			----------------------------------------------------------------
			local damage = Combat.directDamageToPlayer(attacker)
			addPlayerDamage(declaration.targetId, damage)

			table.insert(events, {
				kind = "HitPlayer",
				attackerId = attacker.id,
				playerId = declaration.targetId,
				damage = damage,
				halved = Keywords.isRanged(attacker),
			})
		else
			----------------------------------------------------------------
			-- 무방비 생물 겨냥: 서로 때린다(트레이드)
			----------------------------------------------------------------
			local target = GameState.getCard(state, declaration.targetId)

			if not isCreatureOnField(target) then
				table.insert(events, { kind = "AttackFizzled", attackerId = attacker.id })
				continue
			end

			addCreatureDamage(target, attackerPower)
			if Config.tappedCreaturesStrikeBack or not target.tapped then
				addCreatureDamage(attacker, Keywords.power(target))
			end

			table.insert(events, {
				kind = "HitCreature",
				attackerId = attacker.id,
				targetId = target.id,
				damageToTarget = attackerPower,
			})
		end

		if Config.attackingTapsCreature then
			attacker.tapped = true
		end
	end

	--------------------------------------------------------------------
	-- 일괄 적용
	--------------------------------------------------------------------
	for instanceId, amount in pendingCreatureDamage do
		local instance = GameState.getCard(state, instanceId)
		if instance then
			instance.damage += amount
		end
	end

	for playerId, amount in pendingPlayerDamage do
		GameState.dealDamageToPlayer(state, playerId, amount)
	end

	--------------------------------------------------------------------
	-- 치사 피해 정리
	--------------------------------------------------------------------
	for _, destroyed in Combat.destroyLethallyDamaged(state) do
		table.insert(events, { kind = "Destroyed", instanceId = destroyed.id })
	end

	state.combat = { attackers = {}, blocks = {} }
	return events
end

--[[
	체력이 0 이하가 된 생물을 더미로 보낸다. -> 파괴된 인스턴스 배열

	전투 외(마법 피해)에서도 호출한다.
]]
function Combat.destroyLethallyDamaged(state)
	local destroyed = {}

	for playerId = 1, 2 do
		-- 순회 중 필드 배열이 바뀌므로 스냅샷을 뜬다.
		for _, instance in GameState.creaturesOnField(state, playerId) do
			if Keywords.isLethallyDamaged(instance) then
				GameState.moveCard(state, instance, Zone.Graveyard)
				table.insert(destroyed, instance)
			end
		end
	end

	return destroyed
end

return Combat
