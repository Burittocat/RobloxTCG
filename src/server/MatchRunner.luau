--[[
	한 판을 굴리는 러너. 좌석이 둘이고, 각 좌석은 **사람이거나 AI** 다.

	    MatchRunner.new(remotes, {
	        seats = {
	            [1] = { player = <Player> },
	            [2] = { ai = AI.Difficulty.Normal, name = "훈련용 AI" },
	        },
	        seed = 12345,
	        startingPlayerId = 1,
	    })

	러너는 그 차이를 거의 모른다. 좌석에 player 가 있으면 스냅샷을 쏘고 입력을 기다리고,
	ai 가 있으면 대신 한 수를 둔다. PvP 는 "AI 좌석이 하나도 없는 매치" 일 뿐이라
	PvE 와 코드 경로가 갈라지지 않는다 — 갈라지면 둘 중 하나는 반드시 썩는다.

	서버가 상태의 유일한 주인이다. 클라이언트는 행동을 "요청" 할 뿐이고, 통과 여부는
	여기서 Rules 액션 함수가 정한다. 조작된 값을 보내도 룰 엔진 검증을 다시 통과해야 한다.
	특히 **어느 좌석의 행동인지는 클라이언트가 말하지 않는다** — 보낸 Player 로 서버가
	찾는다. 그래서 상대 좌석의 카드를 내는 요청은 만들 수조차 없다.

	  pump()  차례가 사람에게 돌아올 때까지 AI 수를 소화한다.
	          그 동안 self.thinking 이 켜져 있고, 그 사이에 온 사람의 행동은 거부한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)
local Decks = require(Shared.Decks)
local AI = require(Shared.AI)
local Net = require(Shared.Net)

local Stack = Rules.Stack
local GameState = Rules.GameState

-- AI 가 한 수 두고 쉬는 시간. 0 이면 순식간에 끝나 무슨 일이 일어났는지 안 보인다.
local AI_THINK_TIME = 0.55
local AUTO_PASS_TIME = 0.15

local LOG_TAIL = 40

local MatchRunner = {}
MatchRunner.__index = MatchRunner

--==========================================================================
-- 생성 / 파기
--==========================================================================

function MatchRunner.new(remotes, opts)
	local self = setmetatable({}, MatchRunner)

	self.remotes = remotes
	self.seats = opts.seats
	self.seed = opts.seed
	self.startingPlayerId = opts.startingPlayerId
	self.allowRestart = opts.allowRestart == true
	self.onFinish = opts.onFinish

	self.generation = 0 -- 재시작하면 올라간다. 돌던 AI 루프가 낡은 판을 계속 두는 걸 막는다.
	self.thinking = false
	self.state = nil
	self.readySeats = {}
	self.finishReported = false

	-- Player -> 좌석 번호. 들어온 행동이 누구 것인지 정하는 유일한 근거다.
	self.seatOf = {}
	for seatId, seat in self.seats do
		if seat.player then
			self.seatOf[seat.player] = seatId
		end
	end

	return self
end

function MatchRunner:destroy()
	self.generation += 1
	self.state = nil
end

function MatchRunner:humanSeats()
	local out = {}
	for seatId, seat in self.seats do
		if seat.player then
			out[seatId] = seat.player
		end
	end
	return out
end

function MatchRunner:seatName(seatId)
	local seat = self.seats[seatId]
	if seat.player then
		return seat.player.DisplayName
	end
	return seat.name or "AI"
end

--==========================================================================
-- 준비 / 시작
--==========================================================================

--[[
	클라이언트가 UI 를 다 만들기 전에 첫 스냅샷을 쏘면 그 한 발이 허공으로 사라진다.
	그래서 사람 좌석이 전부 "준비됐다" 를 보낸 뒤에 시작한다.

	이미 시작한 뒤에 다시 오면(재접속·클라 재시도) 현재 상태를 다시 내려보낸다.
]]
function MatchRunner:ready(player)
	local seatId = self.seatOf[player]
	if not seatId then
		return
	end

	self.readySeats[seatId] = true

	if self.state then
		self:syncSeat(seatId)
		return
	end

	for id, seat in self.seats do
		if seat.player and not self.readySeats[id] then
			self:noticeSeat(seatId, "상대를 기다리는 중입니다", "info")
			return
		end
	end

	self:start()
end

function MatchRunner:start(seed)
	self.generation += 1
	self.thinking = false
	self.finishReported = false

	self.seed = seed or self.seed or (os.time() % 2147483647)

	local players = {}
	for seatId = 1, 2 do
		players[seatId] = { name = self:seatName(seatId), deck = Decks.starter() }
	end

	self.state = Rules.newMatch({
		seed = self.seed,
		startingPlayerId = self.startingPlayerId or Rules.startingPlayerFor(self.seed),
		players = players,
	})

	self:sync()

	for seatId in self:humanSeats() do
		local first = (self.state.activePlayerId == seatId)
		self:noticeSeat(
			seatId,
			("%s — %s"):format(first and "선공입니다" or "후공입니다", self:seatName(GameState.opponentOf(seatId))),
			"info"
		)
	end

	self:pump()
end

--==========================================================================
-- 전송
--==========================================================================

function MatchRunner:logTail()
	local log = {}
	local entries = self.state.log
	for index = math.max(1, #entries - LOG_TAIL + 1), #entries do
		table.insert(log, { turn = entries[index].turn, text = entries[index].text })
	end
	return log
end

--[[
	좌석마다 **자기 시점의 뷰** 를 만들어 보낸다.
	상대 손패와 덱은 viewFor 가 지우므로, 한쪽 스냅샷에 다른 쪽 패가 실리는 일이 없다.
]]
function MatchRunner:syncSeat(seatId)
	if not self.state then
		return
	end

	local player = self.seats[seatId].player
	if not player then
		return
	end

	local view = Rules.viewFor(self.state, seatId)
	self.remotes.Sync:FireClient(player, Net.packView(view, self:logTail()))
end

function MatchRunner:sync()
	if not self.state then
		return
	end
	for seatId in self:humanSeats() do
		self:syncSeat(seatId)
	end

	if self.state.finished and not self.finishReported then
		self.finishReported = true
		if self.onFinish then
			task.spawn(self.onFinish, self)
		end
	end
end

function MatchRunner:noticeSeat(seatId, text, kind)
	local player = self.seats[seatId] and self.seats[seatId].player
	if player then
		self.remotes.Notice:FireClient(player, text, kind or "info")
	end
end

function MatchRunner:noticeAll(text, kind)
	for seatId in self:humanSeats() do
		self:noticeSeat(seatId, text, kind)
	end
end

--==========================================================================
-- 차례 판정
--==========================================================================

--[[
	지금 행동해야 하는 좌석.
	스택이 올라가 있으면 대응권자, 수비준비 페이즈면 수비측, 그 외에는 턴 플레이어.
	(터미널 클라이언트 play.luau · 클라이언트 Controller 와 같은 규칙이다)
]]
function MatchRunner:whoActs()
	local state = self.state

	if not Stack.isEmpty(state) then
		return Stack.responderFor(state)
	end
	if state.phase == Rules.Enums.Phase.DefensePrep then
		return GameState.opponentOf(state.activePlayerId)
	end
	return state.activePlayerId
end

--[[
	사람이 결정할 차례가 될 때까지 굴린다.

	AI 좌석이면 한 수 둔다. 사람 좌석인데 **대응할 카드를 하나도 못 내는 스택 창** 이면
	물어보지 않고 자동으로 넘긴다 — 안 그러면 "패스" 버튼만 계속 누르게 된다.
	PvP 매치에서는 AI 가지가 한 번도 안 타므로 사실상 이 자동 패스만 남는다.
]]
function MatchRunner:pump()
	if self.thinking or not self.state then
		return
	end

	self.thinking = true
	local generation = self.generation

	task.spawn(function()
		while true do
			if self.generation ~= generation or not self.state or self.state.finished then
				break
			end

			local mover = self:whoActs()
			local seat = self.seats[mover]

			if seat.player then
				if Stack.isEmpty(self.state) or AI.hasAnyPlayableCard(self.state, mover) then
					break -- 사람이 결정할 게 있다. 여기서 멈춘다.
				end
				task.wait(AUTO_PASS_TIME)
				if self.generation ~= generation or not self.state then
					break
				end
				Rules.pass(self.state, mover)
				self:sync()
			else
				task.wait(AI_THINK_TIME)
				if self.generation ~= generation or not self.state then
					break
				end

				local acted, description = AI.act(self.state, mover, seat.ai)
				if not acted then
					warn("[TCG] AI 가 둘 수 있는 수가 없습니다 — 룰 버그일 수 있습니다")
					break
				end
				if description then
					self:noticeSeat(GameState.opponentOf(mover), ("상대: %s"):format(description), "ai")
				end
				self:sync()
			end
		end

		if self.generation == generation then
			self.thinking = false
			self:sync()
		end
	end)
end

--==========================================================================
-- 이탈 / 몰수
--==========================================================================

--[[
	접속이 끊기거나 서버를 나갔을 때. 남은 쪽의 승리로 판을 닫는다.
	(그냥 방치하면 상대는 영원히 자기 차례가 오지 않는 화면을 본다)
]]
function MatchRunner:forfeit(seatId, reason)
	if not self.state or self.state.finished then
		return
	end

	Rules.concede(self.state, seatId)
	self:noticeAll(reason or ("%s 님이 대전을 떠났습니다"):format(self:seatName(seatId)), "info")
	self:sync()
end

function MatchRunner:playerLeft(player)
	local seatId = self.seatOf[player]
	if not seatId then
		return
	end

	-- 좌석을 비우기 전에 이름을 챙긴다. 비운 뒤에 물으면 seatName 이
	-- "사람이 없는 좌석" = AI 로 답해서 "AI 님이 나갔습니다" 가 된다.
	local reason = ("%s 님이 대전을 떠났습니다"):format(self:seatName(seatId))

	self.seats[seatId].player = nil
	self.seatOf[player] = nil
	self:forfeit(seatId, reason)
end

--==========================================================================
-- 클라이언트 행동 처리
--==========================================================================

--[[
	payload = { kind = string, ... }  — 형태는 src/client/Controller.luau 와 짝이다.
	검증은 전부 Rules 가 한다. 여기서는 payload 모양과 좌석만 확인한다.
]]
function MatchRunner:handle(player, payload)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end

	local seatId = self.seatOf[player]
	if not seatId then
		return -- 이 매치의 사람이 아니다
	end

	if payload.kind == "ready" then
		self:ready(player)
		return
	end

	if payload.kind == "restart" then
		if self.allowRestart then
			self:start(nil)
		end
		return
	end

	if not self.state then
		return
	end
	if self.thinking then
		self:noticeSeat(seatId, "잠시 기다려 주세요", "error")
		return false
	end
	if self.state.finished then
		self:noticeSeat(seatId, "이미 끝난 게임입니다", "error")
		return false
	end

	local state = self.state
	local ok, reason

	if payload.kind == "play" then
		if type(payload.cardId) ~= "number" then
			return
		end
		ok, reason = Rules.playCard(state, seatId, payload.cardId, Net.unpackTargets(payload.targets))
	elseif payload.kind == "attack" then
		if type(payload.attackerId) ~= "number" or type(payload.target) ~= "table" then
			return
		end
		ok, reason = Rules.declareAttacker(state, seatId, payload.attackerId, {
			kind = payload.target.kind,
			id = payload.target.id,
		})
	elseif payload.kind == "block" then
		if type(payload.blockerId) ~= "number" or type(payload.attackerId) ~= "number" then
			return
		end
		ok, reason = Rules.declareBlocker(state, seatId, payload.blockerId, payload.attackerId)
	elseif payload.kind == "clearAttackers" then
		ok, reason = Rules.clearAttackers(state, seatId)
	elseif payload.kind == "clearBlockers" then
		ok, reason = Rules.clearBlockers(state, seatId)
	elseif payload.kind == "endPhase" then
		ok, reason = Rules.endPhase(state, seatId)
	elseif payload.kind == "pass" then
		ok, reason = Rules.pass(state, seatId)
	elseif payload.kind == "concede" then
		ok, reason = Rules.concede(state, seatId)
	else
		return
	end

	if not ok then
		self:sync() -- 클라이언트 화면이 어긋났을 수 있다. 정답을 다시 내려보낸다.
		self:noticeSeat(seatId, tostring(reason or "지금은 할 수 없는 행동입니다"), "error")
		return false
	end

	self:sync()
	self:pump()
	return true
end

return MatchRunner
