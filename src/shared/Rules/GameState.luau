--[[
	게임 상태의 생성 · 조회 · 저수준 조작.

	설계 원칙
	  1. 상태는 순수 데이터다. 함수도 Instance 도 담지 않는다(RNG 만 예외이고,
	     직렬화할 때 snapshot 으로 바뀐다). 그래야 캠페인 세이브와 리플레이가 공짜로 된다.
	  2. 카드 인스턴스는 state.cards[instanceId] 한 곳에만 산다.
	     각 존(deck/hand/field/graveyard)은 id 배열만 들고 있다.
	     같은 카드가 두 존에 동시에 존재하는 버그를 구조적으로 막는다.
	  3. 이 모듈은 "규칙"을 모른다. 합법성 판정은 Combat/Phases/Actions 담당.
]]

local Enums = require(script.Parent.Enums)
local Config = require(script.Parent.Config)
local Registry = require(script.Parent.Registry)
local Keywords = require(script.Parent.Keywords)
local CardDef = require(script.Parent.CardDef)
local RNG = require(script.Parent.RNG)

local Zone = Enums.Zone
local CardType = Enums.CardType

local GameState = {}

local STATE_VERSION = 1

--==========================================================================
-- 생성
--==========================================================================

local function newPlayer(id, name)
	return {
		id = id,
		name = name or ("플레이어 " .. id),
		life = Config.startingLife,

		deck = {}, -- [1] 이 맨 위
		hand = {},
		field = {},
		graveyard = {},

		costPlayedThisTurn = 0, -- 이번 턴 코스트 카드 소환 횟수
		hasMulliganed = false,
	}
end

--[[
	새 매치를 만든다.

	opts = {
		seed        = number,
		players     = { { name = string, deck = { cardId, ... } }, ... },  -- 2명
		startingPlayerId = 1 | 2 | nil,   -- nil 이면 시드로 결정
		strictDeck  = boolean?,           -- false 면 60장 규칙 생략(테스트/캠페인용)
	}
]]
--[[
	선공 좌석. -> 1 | 2

	같은 시드면 항상 같은 결과다. 매치의 셔플 RNG 와는 **별개 인스턴스**를 쓴다 —
	동전을 던지느라 셔플이 한 칸 밀리면 "같은 시드 → 같은 판" 이 깨지고,
	선공을 넘겨받았는지 여부에 따라 덱 순서가 갈린다.

	Rules.startingPlayerFor 가 이걸 그대로 부른다. 판정이 두 벌 있으면
	둘 중 하나만 Config 를 보는 상태로 어긋난다.
]]
function GameState.startingPlayerFor(seed)
	if not Config.randomFirstPlayer then
		return 1
	end
	return RNG.new((tonumber(seed) or 0) + 1):nextInteger(1, 2)
end

function GameState.new(opts)
	assert(type(opts) == "table", "GameState.new: opts 테이블이 필요합니다")
	assert(#opts.players == 2, "GameState.new: 현재는 2인전만 지원합니다")

	-- 시드를 안 받았으면 여기서 정해 **상태에 남긴다**. 남기지 않으면 그 판은
	-- 다시 재현할 수 없고, 선공 결정도 시드 없이(=늘 같은 값으로) 돌게 된다.
	local seed = opts.seed or os.time()
	local rng = RNG.new(seed)

	local state = {
		version = STATE_VERSION,
		seed = seed,
		rng = rng,

		turn = 0, -- beginTurn 에서 1 이 된다
		activePlayerId = 0,
		phase = Enums.Phase.Untap,
		priorityPlayerId = nil,

		finished = false,
		winnerId = nil,
		lossReason = nil,

		nextInstanceId = 1,
		cards = {},
		players = {},

		stack = {}, -- 마지막 요소가 스택 맨 위
		combat = { attackers = {}, blocks = {} },
		log = {},
	}

	for index, playerOpts in opts.players do
		local player = newPlayer(index, playerOpts.name)
		state.players[index] = player

		local ok, err = CardDef.validateDeck(playerOpts.deck, Registry.get, opts.strictDeck)
		if not ok then
			error(("플레이어 %d 덱 오류: %s"):format(index, err), 2)
		end

		for _, cardId in playerOpts.deck do
			local instance = GameState.createCard(state, cardId, index)
			table.insert(player.deck, instance.id)
		end

		rng:shuffle(player.deck)
	end

	-- 셔플 RNG 를 쓰지 않는다(위 주석 참조). Config.randomFirstPlayer 도 여기 한 곳에서 본다.
	state.startingPlayerId = opts.startingPlayerId or GameState.startingPlayerFor(seed)

	-- 초기 패
	for _, player in state.players do
		for _ = 1, Config.startingHandSize do
			GameState.drawCard(state, player.id)
		end
	end

	return state
end

--==========================================================================
-- 카드 인스턴스
--==========================================================================

function GameState.createCard(state, cardId, ownerId)
	-- 결과를 쓰지 않는 호출이지만 지우면 안 된다 — mustGet 은 등록되지 않은 카드 id 면
	-- 여기서 에러를 낸다. 이 줄이 없으면 오타난 id 가 필드에 올라간 뒤에야 터진다.
	Registry.mustGet(cardId)

	local instance = {
		id = state.nextInstanceId,
		defId = cardId,
		ownerId = ownerId,
		controllerId = ownerId, -- 컨트롤 탈취 카드를 대비해 소유자와 분리해둔다
		zone = Zone.Deck,

		tapped = false,
		summonedOnTurn = nil, -- 소환 멀미 판정용
		damage = 0,
		powerMod = 0,
		toughnessMod = 0,
		grantedKeywords = nil,
	}

	state.nextInstanceId += 1
	state.cards[instance.id] = instance

	-- def 를 여기서 안 들고 있는 이유: 직렬화 대상에서 빼기 위해. 필요하면 Registry 로.
	return instance
end

function GameState.getCard(state, instanceId)
	return state.cards[instanceId]
end

function GameState.mustGetCard(state, instanceId)
	local instance = state.cards[instanceId]
	if not instance then
		error(("존재하지 않는 카드 인스턴스: %s"):format(tostring(instanceId)), 2)
	end
	return instance
end

function GameState.getDef(instance)
	return Registry.mustGet(instance.defId)
end

--==========================================================================
-- 존 조작
--==========================================================================

local ZONE_FIELD = {
	[Zone.Deck] = "deck",
	[Zone.Hand] = "hand",
	[Zone.Field] = "field",
	[Zone.Graveyard] = "graveyard",
}

function GameState.getZoneList(state, playerId, zone)
	local key = ZONE_FIELD[zone]
	if not key then
		return nil
	end
	return state.players[playerId][key]
end

local function removeFromZone(state, instance)
	local list = GameState.getZoneList(state, instance.controllerId, instance.zone)
	if not list then
		return -- 스택 등 플레이어 존이 아닌 경우
	end
	local index = table.find(list, instance.id)
	if index then
		table.remove(list, index)
	end
end

--[[
	카드를 다른 존으로 옮긴다.

	position: "top" | "bottom" (덱으로 보낼 때만 의미가 있다. 기본 top)
	newControllerId: 존을 옮기면서 컨트롤러가 바뀌는 경우 (더미는 소유자에게 간다)
]]
function GameState.moveCard(state, instance, toZone, position, newControllerId)
	removeFromZone(state, instance)

	-- 필드를 떠나면 그 턴 한정 상태는 전부 초기화된다.
	if instance.zone == Zone.Field and toZone ~= Zone.Field then
		instance.tapped = false
		instance.damage = 0
		instance.powerMod = 0
		instance.toughnessMod = 0
		instance.grantedKeywords = nil
		instance.summonedOnTurn = nil
	end

	-- 더미/덱/패로 돌아가면 소유자 소유로 복귀한다.
	instance.controllerId = newControllerId
		or (toZone == Zone.Field and instance.controllerId)
		or instance.ownerId

	instance.zone = toZone

	local list = GameState.getZoneList(state, instance.controllerId, toZone)
	if list then
		if toZone == Zone.Deck and position == "bottom" then
			table.insert(list, instance.id)
		elseif toZone == Zone.Deck then
			table.insert(list, 1, instance.id)
		else
			table.insert(list, instance.id)
		end
	end

	return instance
end

--==========================================================================
-- 드로우
--==========================================================================

--[[
	1장 뽑는다. -> instance | nil

	덱이 비면 nil 을 돌려주고, Config.deckOutCausesLoss 면 패배 처리한다.
	(기획서에 없어서 Config 로 뺐다.)
]]
function GameState.drawCard(state, playerId)
	local player = state.players[playerId]
	local topId = player.deck[1]

	if not topId then
		if Config.deckOutCausesLoss then
			GameState.setLoser(state, playerId, Enums.LossReason.DeckOut)
		end
		return nil
	end

	local instance = state.cards[topId]
	GameState.moveCard(state, instance, Zone.Hand)
	return instance
end

--==========================================================================
-- 라이프 / 승패
--==========================================================================

function GameState.dealDamageToPlayer(state, playerId, amount)
	if amount <= 0 then
		return 0
	end

	local player = state.players[playerId]
	player.life -= amount

	GameState.log(state, ("플레이어 %d 가 %d 피해 (남은 라이프 %d)"):format(playerId, amount, player.life))

	if player.life <= 0 then
		GameState.setLoser(state, playerId, Enums.LossReason.LifeDepleted)
	end

	return amount
end

function GameState.healPlayer(state, playerId, amount)
	if amount <= 0 then
		return 0
	end
	state.players[playerId].life += amount
	return amount
end

function GameState.setLoser(state, loserId, reason)
	if state.finished then
		return -- 먼저 확정된 결과를 덮어쓰지 않는다
	end

	state.finished = true
	state.lossReason = reason
	state.winnerId = (loserId == 1) and 2 or 1

	GameState.log(state, ("게임 종료: 플레이어 %d 승 (사유 %s)"):format(state.winnerId, reason))
end

function GameState.opponentOf(playerId)
	return (playerId == 1) and 2 or 1
end

--==========================================================================
-- 필드 조회
--==========================================================================

-- 해당 플레이어 필드의 생물 인스턴스 배열
function GameState.creaturesOnField(state, playerId)
	local out = {}
	for _, instanceId in state.players[playerId].field do
		local instance = state.cards[instanceId]
		if Registry.mustGet(instance.defId).type == CardType.Creature then
			table.insert(out, instance)
		end
	end
	return out
end

-- 해당 플레이어 필드의 코스트 카드 인스턴스 배열
function GameState.costCardsOnField(state, playerId)
	local out = {}
	for _, instanceId in state.players[playerId].field do
		local instance = state.cards[instanceId]
		if Registry.mustGet(instance.defId).type == CardType.Cost then
			table.insert(out, instance)
		end
	end
	return out
end

-- 지금 지불 가능한 코스트 총량 = 언탭된 코스트 카드가 만들어내는 양의 합
function GameState.availableCost(state, playerId)
	local total = 0
	for _, instance in GameState.costCardsOnField(state, playerId) do
		if not instance.tapped then
			total += CardDef.costProduced(Registry.mustGet(instance.defId))
		end
	end
	return total
end

--[[
	코스트를 지불한다. 부족하면 아무것도 하지 않고 false.
	어떤 코스트 카드를 탭할지는 배열 순서대로(= 필드에 낸 순서) 고른다.
]]
function GameState.payCost(state, playerId, amount)
	if amount <= 0 then
		return true
	end
	if GameState.availableCost(state, playerId) < amount then
		return false
	end

	local remaining = amount

	for _, instance in GameState.costCardsOnField(state, playerId) do
		if remaining <= 0 then
			break
		end
		if not instance.tapped then
			instance.tapped = true
			remaining -= CardDef.costProduced(Registry.mustGet(instance.defId))
		end
	end

	return true
end

--[[
	기획서: "'도발' 태그가 붙어있는 생물체가 전장에 있다면"
	→ 탭 여부와 무관하게 존재만으로 직접 공격을 막는다.
]]
function GameState.hasTaunt(state, playerId)
	for _, instance in GameState.creaturesOnField(state, playerId) do
		if Keywords.isTaunt(instance) then
			return true
		end
	end
	return false
end

--==========================================================================
-- 로그
--==========================================================================

function GameState.log(state, message)
	table.insert(state.log, { turn = state.turn, phase = state.phase, text = message })
end

--==========================================================================
-- 직렬화 (캠페인 세이브 / 리플레이)
--==========================================================================

--[[
	JSON 으로 바로 나갈 수 있는 순수 테이블을 만든다.
	RNG 인스턴스만 snapshot 으로 바꾸면 나머지는 이미 순수 데이터다.
]]
function GameState.serialize(state)
	local copy = table.clone(state)
	copy.rng = state.rng:snapshot()
	return copy
end

function GameState.deserialize(data)
	local state = table.clone(data)
	state.rng = RNG.restore(data.rng)
	return state
end

return GameState
