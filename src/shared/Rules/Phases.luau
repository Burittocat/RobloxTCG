--[[
	페이즈 상태머신 + 우선권(누가 이 페이즈에 무엇을 할 수 있는가).

	기획서의 1턴 구조를 그대로 옮겼다. (플레이어1 선공 기준)

	    1: 메인 페이즈 시작 / 행동 / 종료      → Main
	    1: 공격준비 페이즈 시작 / 종료         → AttackPrep
	    2: 수비준비 페이즈 시작 / 종료         → DefensePrep
	    0: 공수 페이즈 시작 / 종료             → Combat
	    0: 1턴 종료                            → EndTurn → 다음 턴

	Untap / Draw 는 기획서에 별도 항목이 없지만 "언탭"과 드로우가 룰 본문에
	전제되어 있어 Main 앞의 자동 스텝으로 분리했다. 플레이어 입력을 받지 않는다.
]]

local Enums = require(script.Parent.Enums)
local Config = require(script.Parent.Config)
local GameState = require(script.Parent.GameState)
local Combat = require(script.Parent.Combat)

local Phase = Enums.Phase
local Zone = Enums.Zone

local Phases = {}

-- 플레이어 입력을 기다리는 페이즈. 나머지는 자동으로 흘러간다.
local INTERACTIVE = {
	[Phase.Main] = true,
	[Phase.AttackPrep] = true,
	[Phase.DefensePrep] = true,
}

--==========================================================================
-- 우선권 / 권한
--==========================================================================

local function blank()
	return {
		playCost = false,
		summonCreature = false,
		summonEntersTapped = false,
		castNormalSpell = false,
		castInstantSpell = false,
		declareAttackers = false,
		declareBlockers = false,
		endPhase = false,
	}
end

--[[
	이 페이즈에 playerId 가 할 수 있는 행동 집합. -> table

	클라이언트 UI 는 이걸로 버튼을 켜고 끄고, 서버는 이걸로 검증한다.
	같은 함수를 쓰므로 UI 와 서버 판정이 어긋날 수 없다.
]]
function Phases.permissions(state, playerId)
	local perms = blank()

	if state.finished then
		return perms
	end

	local isActive = (playerId == state.activePlayerId)

	if state.phase == Phase.Main then
		if isActive then
			-- 기획서: 메인 페이즈에 코스트 소환 / 생물 소환 / 마법 시전
			perms.playCost = state.players[playerId].costPlayedThisTurn < Config.costCardsPerTurn
			perms.summonCreature = true
			perms.summonEntersTapped = false
			perms.castNormalSpell = true
			perms.castInstantSpell = true
			perms.endPhase = true
		else
			-- 기획서: "플레이어1의 메인 페이즈에 플레이어2가 '즉시시전' 태그
			--          마법카드를 가지고 있다면 상대 페이즈의 발동가능"
			perms.castInstantSpell = true
		end
	elseif state.phase == Phase.AttackPrep then
		if isActive then
			perms.declareAttackers = true
			perms.endPhase = true
			perms.castInstantSpell = Config.opponentMayCastInstantDuringAttackPrep
		else
			-- ★ 기획서 미기재. 공격 선언에 대응할 창구가 없으면 즉시시전이 무력해진다.
			perms.castInstantSpell = Config.opponentMayCastInstantDuringAttackPrep
		end
	elseif state.phase == Phase.DefensePrep then
		if isActive then
			-- 기획서상 즉시시전 발동 창은 "상대 메인 / 본인 메인 / 본인 수비"뿐이다.
			-- 공격측 입장에서 지금은 그 어느 것도 아니므로 행동할 수 없다.
			-- (= 방어측이 마지막 발언권을 갖는다)
			perms.endPhase = false
		else
			-- 기획서: "해당 플레이어의 수비턴에는 일반 생물을 언탭하여 소환할 수 없으며
			--          신속 태그가 적용된 생물만 언탭하여 소환할 수 있다.
			--          마법카드는 즉시시전마법이나 일반마법카드를 사용할 수 있다"
			perms.declareBlockers = true
			perms.summonCreature = true
			perms.summonEntersTapped = Config.defensePhaseSummonEntersTapped
			perms.castNormalSpell = true
			perms.castInstantSpell = true
			perms.endPhase = true
		end
	end

	return perms
end

--[[
	기획서: 신속 생물은 수비준비 페이즈에도 언탭 상태로 등장해 즉시 방어할 수 있다.
	그 외 생물은 탭된 채 등장 → 그 턴 방어 불가.
]]
function Phases.summonEntersTapped(state, def)
	if state.phase ~= Phase.DefensePrep then
		return false
	end
	if not Config.defensePhaseSummonEntersTapped then
		return false
	end

	for _, kw in def.keywords or {} do
		if kw == Enums.Keyword.Haste then
			return false
		end
	end

	return true
end

--==========================================================================
-- 페이즈 진입 처리
--==========================================================================

local function onEnterUntap(state)
	-- 턴 플레이어의 모든 퍼미넌트 언탭
	for _, instanceId in state.players[state.activePlayerId].field do
		state.cards[instanceId].tapped = false
	end

	state.players[state.activePlayerId].costPlayedThisTurn = 0
	GameState.log(state, ("--- 턴 %d: 플레이어 %d ---"):format(state.turn, state.activePlayerId))
end

local function onEnterDraw(state)
	-- ★ 선공 1턴 드로우 스킵 (Config)
	local isFirstTurnOfStarter = state.turn == 1 and state.activePlayerId == state.startingPlayerId

	if isFirstTurnOfStarter and Config.firstPlayerSkipsFirstDraw then
		GameState.log(state, "선공 첫 턴 드로우 생략")
		return
	end

	GameState.drawCard(state, state.activePlayerId)
end

--[[
	전투 해결.

	events 를 state 에 남기는 이유는 **화면이 그것을 연출로 재생하기 때문**이다.
	스냅샷만 보면 "누가 누구를 때렸는가" 를 복원할 수 없다 — 도착한 상태에는
	이미 피해가 적용돼 있고 죽은 생물은 무덤에 가 있다. 공격자와 대상을 잇는
	정보는 이 순간에만 있다.

	seq 를 같이 붙인다. 화면은 스냅샷을 여러 번 받을 수 있으므로(다른 이유로도
	렌더가 돈다) **같은 전투를 두 번 재생하지 않으려면** 번호가 필요하다.
]]
local function onEnterCombat(state)
	local events = Combat.resolve(state)
	for _, event in events do
		GameState.log(state, "전투: " .. event.kind)
	end

	state.combatSeq = (state.combatSeq or 0) + 1
	state.lastCombat = { seq = state.combatSeq, events = events }
end

local function onEnterEndTurn(state)
	-- 생물이 받은 피해와 임시 버프는 턴 종료에 사라진다.
	for _, instance in state.cards do
		if instance.zone == Zone.Field then
			instance.damage = 0
			instance.powerMod = 0
			instance.toughnessMod = 0
			instance.grantedKeywords = nil
		end
	end

	state.combat = { attackers = {}, blocks = {} }
end

local ON_ENTER = {
	[Phase.Untap] = onEnterUntap,
	[Phase.Draw] = onEnterDraw,
	[Phase.Combat] = onEnterCombat,
	[Phase.EndTurn] = onEnterEndTurn,
}

--==========================================================================
-- 전이
--==========================================================================

local function indexOfPhase(phase)
	return table.find(Enums.PhaseOrder, phase)
end

--[[
	공격자가 하나도 없으면 수비준비/공수 페이즈는 의미가 없다 → 건너뛴다.
	(기획서 구조는 유지하되, 빈 페이즈에서 "종료" 버튼을 누르게 만들지 않는다)
]]
local function shouldSkip(state, phase)
	if phase == Phase.DefensePrep or phase == Phase.Combat then
		return #state.combat.attackers == 0
	end
	return false
end

local function enterPhase(state, phase)
	state.phase = phase

	if phase == Phase.DefensePrep then
		state.priorityPlayerId = GameState.opponentOf(state.activePlayerId)
	else
		state.priorityPlayerId = state.activePlayerId
	end

	local hook = ON_ENTER[phase]
	if hook then
		hook(state)
	end
end

local function beginTurn(state, playerId)
	state.turn += 1
	state.activePlayerId = playerId
	enterPhase(state, Phase.Untap)
end

--[[
	한 페이즈 앞으로. 자동 페이즈는 연달아 처리하고, 입력이 필요한 페이즈에서 멈춘다.
	게임이 끝나면 즉시 반환한다.
]]
function Phases.advance(state)
	if state.finished then
		return state.phase
	end

	local guard = 0

	while true do
		guard += 1
		if guard > 64 then
			error("Phases.advance: 전이가 끝나지 않습니다 (룰 버그)")
		end

		local index = indexOfPhase(state.phase)

		if state.phase == Phase.EndTurn then
			beginTurn(state, GameState.opponentOf(state.activePlayerId))
		else
			local nextPhase = Enums.PhaseOrder[index + 1]
			if shouldSkip(state, nextPhase) then
				-- 건너뛴 페이즈 다음으로
				local skipIndex = indexOfPhase(nextPhase)
				repeat
					skipIndex += 1
					nextPhase = Enums.PhaseOrder[skipIndex]
				until not nextPhase or not shouldSkip(state, nextPhase)
			end
			enterPhase(state, nextPhase)
		end

		if state.finished then
			return state.phase
		end
		if INTERACTIVE[state.phase] then
			return state.phase
		end
	end
end

--[[
	매치 시작. 선공 플레이어의 1턴 Untap → Draw 를 돌리고 Main 에서 멈춘다.
]]
function Phases.beginMatch(state)
	beginTurn(state, state.startingPlayerId)

	if not INTERACTIVE[state.phase] then
		Phases.advance(state)
	end

	return state.phase
end

return Phases
