--[[
	테스트용 상황 구성 도우미.

	실제 게임처럼 7장 뽑고 시작하면 무엇이 손에 오는지 통제할 수 없다.
	여기서는 원하는 카드를 원하는 존에 직접 놓아 상황을 만든 뒤 룰만 검증한다.
]]

local Fixture = {}

--[[
	빈 판을 만든다. 덱은 코스트 카드로만 채워 드로우가 룰 검증을 방해하지 않게 한다.

	opts = { seed?, startingPlayerId?, deckSize? }
]]
function Fixture.match(Rules, opts)
	opts = opts or {}

	local deck = {}
	for _ = 1, opts.deckSize or 30 do
		table.insert(deck, "COST_BASIC")
	end

	return Rules.newMatch({
		seed = opts.seed or 12345,
		startingPlayerId = opts.startingPlayerId or 1,
		strictDeck = false,
		-- 픽스처는 "판이 이미 시작된 상태" 를 원한다. 멀리건 관문 자체는
		-- tests/specs/mulligan.luau 가 본다.
		mulligan = opts.mulligan or false,
		players = {
			{ name = "P1", deck = table.clone(deck) },
			{ name = "P2", deck = table.clone(deck) },
		},
	})
end

--[[
	카드를 만들어 원하는 존에 놓는다. -> instance

	zone 이 Field 면 소환 멀미가 없는 상태(이전 턴에 나온 것처럼)로 놓는다.
	소환 멀미를 테스트하려면 sick = true 를 준다.
]]
function Fixture.spawn(Rules, state, playerId, cardId, zone, sick)
	local instance = Rules.GameState.createCard(state, cardId, playerId)
	Rules.GameState.moveCard(state, instance, zone, nil, playerId)

	if zone == Rules.Enums.Zone.Field then
		instance.tapped = false
		instance.summonedOnTurn = sick and state.turn or nil
	end

	return instance
end

-- 언탭된 코스트 카드 n 장을 필드에 깔아준다.
function Fixture.giveCost(Rules, state, playerId, count)
	local out = {}
	for _ = 1, count do
		local instance = Fixture.spawn(Rules, state, playerId, "COST_BASIC", Rules.Enums.Zone.Field)
		instance.tapped = false
		table.insert(out, instance)
	end
	return out
end

-- 손에 카드를 쥐어준다. -> instance
function Fixture.giveHand(Rules, state, playerId, cardId)
	return Fixture.spawn(Rules, state, playerId, cardId, Rules.Enums.Zone.Hand)
end

--[[
	페이즈를 직접 세팅한다. 진입 훅(언탭/드로우/전투)은 돌지 않는다 —
	특정 페이즈의 권한만 보고 싶을 때 쓴다.
]]
function Fixture.setPhase(state, phase, activePlayerId)
	state.phase = phase
	if activePlayerId then
		state.activePlayerId = activePlayerId
	end
	state.priorityPlayerId = state.activePlayerId
	return state
end

--[[
	스택이 빌 때까지 양쪽이 패스한 것으로 처리한다.
	대응을 테스트하지 않는 케이스에서 소환/시전을 즉시 굳힐 때 쓴다.
]]
function Fixture.settle(Rules, state)
	Rules.Stack.resolveAll(state)
	return state
end

-- 손패에서 카드를 내고 곧바로 스택까지 해결한다. -> ok, reason
function Fixture.playAndSettle(Rules, state, playerId, instanceId, targets)
	local ok, reason = Rules.playCard(state, playerId, instanceId, targets)
	if not ok then
		return false, reason
	end
	Fixture.settle(Rules, state)
	return true
end

return Fixture
