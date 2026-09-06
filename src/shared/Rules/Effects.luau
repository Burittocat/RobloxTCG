--[[
	마법 효과 해결.

	카드는 코드가 아니라 데이터다. 카드 정의에 effects 배열을 적으면 여기서 해석한다.
	  - 카드를 추가할 때 룰 엔진을 건드리지 않아도 된다.
	  - 카드 데이터를 그대로 직렬화해 밸런스 패치를 데이터로 내릴 수 있다.
	새 효과 종류가 필요할 때만 Enums.EffectKind 와 이 파일의 HANDLERS 에 추가한다.
]]

local Enums = require(script.Parent.Enums)
local GameState = require(script.Parent.GameState)
local Keywords = require(script.Parent.Keywords)
local Combat = require(script.Parent.Combat)

local EffectKind = Enums.EffectKind
local TargetKind = Enums.TargetKind
local Zone = Enums.Zone

local Effects = {}

--==========================================================================
-- 대상 해석
--==========================================================================

--[[
	선언된 대상이 이 효과에 적법한가. -> ok, reason

	target = { kind = "Creature" | "Player" | "StackItem", id = number }
]]
function Effects.validateTarget(state, effect, controllerId, target)
	local want = effect.target or TargetKind.None

	if want == TargetKind.None then
		return true
	end
	if type(target) ~= "table" then
		return false, "대상이 필요합니다"
	end

	local opponentId = GameState.opponentOf(controllerId)

	if want == TargetKind.StackItem then
		if target.kind ~= "StackItem" then
			return false, "스택 위의 대상이 필요합니다"
		end
		for _, item in state.stack do
			if item.id == target.id then
				return true
			end
		end
		return false, "이미 사라진 대상입니다"
	end

	if target.kind == "Player" then
		if want == TargetKind.AnyPlayer or want == TargetKind.CreatureOrPlayer then
			return true
		end
		if want == TargetKind.EnemyPlayer then
			return target.id == opponentId, "상대 플레이어만 지정할 수 있습니다"
		end
		if want == TargetKind.SelfPlayer then
			return target.id == controllerId, "자신만 지정할 수 있습니다"
		end
		return false, "플레이어는 대상이 될 수 없습니다"
	end

	if target.kind == "Creature" then
		local instance = GameState.getCard(state, target.id)
		if not instance or instance.zone ~= Zone.Field then
			return false, "필드에 없는 생물입니다"
		end

		if want == TargetKind.AnyCreature or want == TargetKind.CreatureOrPlayer then
			return true
		end
		if want == TargetKind.AllyCreature then
			return instance.controllerId == controllerId, "아군 생물만 지정할 수 있습니다"
		end
		if want == TargetKind.EnemyCreature then
			return instance.controllerId == opponentId, "적 생물만 지정할 수 있습니다"
		end
		return false, "생물은 대상이 될 수 없습니다"
	end

	return false, "알 수 없는 대상 종류입니다"
end

--==========================================================================
-- 효과 처리기
--==========================================================================

local HANDLERS = {}

HANDLERS[EffectKind.Damage] = function(state, effect, ctx)
	local target = ctx.target

	if target.kind == "Player" then
		GameState.dealDamageToPlayer(state, target.id, effect.amount)
	else
		local instance = GameState.getCard(state, target.id)
		if instance and instance.zone == Zone.Field then
			instance.damage += effect.amount
		end
	end
end

HANDLERS[EffectKind.Heal] = function(state, effect, ctx)
	local playerId = (ctx.target and ctx.target.kind == "Player") and ctx.target.id or ctx.controllerId
	GameState.healPlayer(state, playerId, effect.amount)
end

HANDLERS[EffectKind.Destroy] = function(state, _effect, ctx)
	local instance = GameState.getCard(state, ctx.target.id)
	if instance and instance.zone == Zone.Field then
		GameState.moveCard(state, instance, Zone.Graveyard)
	end
end

--[[
	기획서: 즉시시전으로 "상대가 소환할려는 생물을 더미나 덱으로 보내버린다"
	→ 스택 위의 소환도, 필드 위의 생물도 덱으로 되돌릴 수 있다.
]]
HANDLERS[EffectKind.ToDeck] = function(state, effect, ctx)
	local instance
	if ctx.target.kind == "StackItem" then
		local item = ctx.stackItem
		if item then
			item.countered = true
			instance = GameState.getCard(state, item.instanceId)
		end
	else
		instance = GameState.getCard(state, ctx.target.id)
	end

	if instance then
		GameState.moveCard(state, instance, Zone.Deck, effect.position or "top")
	end
end

HANDLERS[EffectKind.ToHand] = function(state, _effect, ctx)
	local instance
	if ctx.target.kind == "StackItem" then
		local item = ctx.stackItem
		if item then
			item.countered = true
			instance = GameState.getCard(state, item.instanceId)
		end
	else
		instance = GameState.getCard(state, ctx.target.id)
	end

	if instance then
		GameState.moveCard(state, instance, Zone.Hand)
	end
end

HANDLERS[EffectKind.Draw] = function(state, effect, ctx)
	local playerId = (ctx.target and ctx.target.kind == "Player") and ctx.target.id or ctx.controllerId
	for _ = 1, (effect.amount or 1) do
		GameState.drawCard(state, playerId)
	end
end

--[[
	기획서: 즉시시전으로 "상대가 사용한 마법을 무효화"
	무효화된 항목은 효과 없이 더미로 간다.
]]
HANDLERS[EffectKind.Counter] = function(state, _effect, ctx)
	local item = ctx.stackItem
	if item then
		item.countered = true
	end
end

HANDLERS[EffectKind.Buff] = function(state, effect, ctx)
	local instance = GameState.getCard(state, ctx.target.id)
	if instance and instance.zone == Zone.Field then
		instance.powerMod = (instance.powerMod or 0) + (effect.power or 0)
		instance.toughnessMod = (instance.toughnessMod or 0) + (effect.toughness or 0)
	end
end

HANDLERS[EffectKind.GrantKeyword] = function(state, effect, ctx)
	local instance = GameState.getCard(state, ctx.target.id)
	if instance and instance.zone == Zone.Field then
		Keywords.grant(instance, effect.keyword)
	end
end

--==========================================================================
-- 실행
--==========================================================================

--[[
	마법 한 장의 효과를 전부 적용한다.

	targets: effects 와 같은 길이의 배열. targets[i] 가 effects[i] 의 대상.
	         대상이 없는 효과는 nil.
]]
function Effects.resolveSpell(state, def, controllerId, targets)
	for index, effect in def.effects do
		local target = targets and targets[index]

		local ctx = {
			controllerId = controllerId,
			target = target,
			stackItem = nil,
		}

		-- 무효화/되돌리기 계열은 스택 위 항목을 잡아야 한다.
		if target and target.kind == "StackItem" then
			for _, item in state.stack do
				if item.id == target.id then
					ctx.stackItem = item
					break
				end
			end
		end

		local handler = HANDLERS[effect.kind]
		if handler then
			handler(state, effect, ctx)
		end
	end

	-- 마법 피해로 죽은 생물 정리
	Combat.destroyLethallyDamaged(state)
end

return Effects
