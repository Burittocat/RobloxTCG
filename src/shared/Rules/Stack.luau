--[[
	시전/소환 스택.

	기획서의 즉시시전이 "상대가 소환할려는 생물을 더미나 덱으로 보내버린다거나
	상대가 사용한 마법을 무효화" 하려면, 카드는 내자마자 효과가 나면 안 된다.
	일단 스택에 올라가고 → 상대에게 대응 창이 열리고 → 아무도 대응하지 않으면 해결된다.

	우선권 규칙(단순화)
	  - 스택 맨 위 항목의 상대가 대응권을 갖는다.
	  - 그 사람이 즉시시전을 쓰면 새 항목이 올라가고 대응권이 다시 넘어간다(체인).
	  - 그 사람이 패스하면 맨 위 항목이 해결된다.
	  나중에 대응할 카드가 손에 없으면 서버가 자동으로 패스를 넣어준다.
]]

local Enums = require(script.Parent.Enums)
local Config = require(script.Parent.Config)
local GameState = require(script.Parent.GameState)
local Effects = require(script.Parent.Effects)
local Phases = require(script.Parent.Phases)
local Registry = require(script.Parent.Registry)

local Zone = Enums.Zone
local CardType = Enums.CardType

local Stack = {}

--==========================================================================
-- 조회
--==========================================================================

function Stack.top(state)
	return state.stack[#state.stack]
end

function Stack.isEmpty(state)
	return #state.stack == 0
end

--[[
	지금 대응권을 가진 플레이어. 스택이 비어 있으면 nil.
]]
function Stack.responderFor(state)
	local top = Stack.top(state)
	if not top then
		return nil
	end
	return GameState.opponentOf(top.controllerId)
end

--==========================================================================
-- 올리기
--==========================================================================

--[[
	item = {
		kind         = "Summon" | "Spell",
		instanceId   = number,
		controllerId = number,
		targets      = { target, ... } | nil,
	}
]]
function Stack.push(state, item)
	state.nextStackItemId = (state.nextStackItemId or 0) + 1
	item.id = state.nextStackItemId
	item.countered = false

	-- 스택은 플레이어별 존이 아니므로 moveCard 는 존에서 빼기만 하고
	-- 카드는 state.stack 배열이 대신 들고 있는다.
	local instance = GameState.mustGetCard(state, item.instanceId)
	GameState.moveCard(state, instance, Zone.Stack)

	table.insert(state.stack, item)
	GameState.log(state, ("스택에 %s 올림: %s"):format(item.kind, Registry.mustGet(instance.defId).name))

	return item
end

--==========================================================================
-- 해결
--==========================================================================

local function resolveSummon(state, item, instance)
	local def = Registry.mustGet(instance.defId)

	GameState.moveCard(state, instance, Zone.Field, nil, item.controllerId)

	instance.summonedOnTurn = state.turn
	instance.tapped = Phases.summonEntersTapped(state, def)

	if def.type == CardType.Cost then
		-- 기획서: 코스트 카드는 언탭 상태로 등장해 그 턴 바로 탭해서 쓸 수 있다.
		instance.tapped = not Config.costCardEntersUntapped
		instance.summonedOnTurn = nil -- 코스트 카드에는 소환 멀미가 없다
	end

	GameState.log(state, ("%s 소환 (탭=%s)"):format(def.name, tostring(instance.tapped)))
end

--[[
	맨 위 항목 하나를 해결한다. -> resolvedItem | nil
]]
function Stack.resolveTop(state)
	local item = table.remove(state.stack)
	if not item then
		return nil
	end

	local instance = GameState.getCard(state, item.instanceId)
	if not instance then
		return item
	end

	local def = Registry.mustGet(instance.defId)

	if item.countered then
		-- 무효화됨: 효과 없이 더미로. (ToDeck/ToHand 는 효과 쪽에서 이미 옮겼다)
		if instance.zone == Zone.Stack then
			GameState.moveCard(state, instance, Zone.Graveyard)
		end
		GameState.log(state, ("%s 무효화됨"):format(def.name))
		return item
	end

	if item.kind == "Summon" then
		resolveSummon(state, item, instance)
	else
		Effects.resolveSpell(state, def, item.controllerId, item.targets)
		if instance.zone == Zone.Stack then
			GameState.moveCard(state, instance, Zone.Graveyard)
		end
		GameState.log(state, ("%s 해결"):format(def.name))
	end

	return item
end

--[[
	대응권자가 패스했다. 맨 위 항목을 해결한다. -> ok, reason
]]
function Stack.pass(state, playerId)
	local responder = Stack.responderFor(state)
	if not responder then
		return false, "스택이 비어 있습니다"
	end
	if playerId ~= responder then
		return false, "지금 대응권은 상대에게 있습니다"
	end

	Stack.resolveTop(state)
	return true
end

--[[
	스택이 빌 때까지 전부 해결한다. AI / 테스트 / 대응 불가 상황용.
]]
function Stack.resolveAll(state)
	local guard = 0
	while #state.stack > 0 do
		guard += 1
		if guard > 128 then
			error("Stack.resolveAll: 스택이 줄지 않습니다 (룰 버그)")
		end
		Stack.resolveTop(state)
	end
end

return Stack
