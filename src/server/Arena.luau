--[[
	예약 서버(= 대전 서버)에서 도는 것. 한 서버에 한 판, 두 사람.

	로비 서버가 짝을 짓고 예약 서버를 하나 잡아 두 사람을 이리로 보낸다. 각자는
	텔레포트 데이터에 어느 판인지와 자기 좌석을 달고 도착한다.

	    { matchId, seat, opponentName }

	시드는 여기 없다. 클라이언트가 읽을 수 있는 값이라 실어 보내면 셔플이 통째로 노출된다.
	이 서버가 직접 뽑는다.

	--------------------------------------------------------------------------
	왜 도착 데이터를 그대로 믿지 않는가

	텔레포트 데이터는 서버가 실어 보내지만, 판정에 쓰기 전에 **두 사람의 데이터가 서로
	맞는지** 를 본다. 같은 판을 가리키지 않거나 좌석이 겹치면(둘 다 1번) 판을 열지 않고
	둘 다 로비로 돌려보낸다. 큐 배치 제거가 실패해 같은 사람이 두 판에 배정되는 드문 경우가
	여기서 걸린다 — 어긋난 채로 시작하면 두 사람이 서로 다른 게임을 보게 된다.

	--------------------------------------------------------------------------
	덱

	덱은 텔레포트 데이터로 나르지 않는다. 클라이언트가 읽고 고칠 수 있는 값이라,
	실어 보내면 "아무 카드나 60장" 으로 판을 열 수 있다. 대신 도착한 사람의 UserId 로
	이 서버가 DataStore 에서 직접 읽는다 — 사람마다 덱은 하나뿐이라 "어느 덱인지" 를
	가리킬 것도 없다.

	읽기는 도착할 때마다 한 번, 상대를 기다리는 동안 한다. 두 사람 덱이 다 들어온
	뒤에 판이 열린다.

	--------------------------------------------------------------------------
	안 온 사람

	먼저 도착한 쪽은 arenaWaitTimeout 만큼만 기다린다. 넘기면 부전승이 아니라 로비로
	돌려보낸다. 텔레포트는 간헐적으로 실패하므로, 안 온 것을 패배로 처리하면
	네트워크 사고가 그대로 전적이 된다.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Decks = require(Shared.Decks)
local Net = require(Shared.Net)

local DeckStore = require(script.Parent.DeckStore)
local MatchRunner = require(script.Parent.MatchRunner)
local Settings = require(script.Parent.Matchmaker.Settings)

local Screen = Net.LobbyScreen

local Arena = {}
Arena.__index = Arena

function Arena.new(remotes, host)
	local self = setmetatable({}, Arena)

	self.remotes = remotes
	self.host = host
	self.arrivals = {} :: { [Player]: any }
	self.decks = {} :: { [Player]: { string } }
	self.runner = nil
	self.closed = false
	self.deckStore = DeckStore.new()

	remotes.Lobby.OnServerEvent:Connect(function(player, payload)
		local ok, err = pcall(function()
			self:onMessage(player, payload)
		end)
		if not ok then
			warn(("[TCG] 대전 서버 요청 처리 실패: %s"):format(tostring(err)))
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:onPlayerAdded(player)
	end)

	for _, player in Players:GetPlayers() do
		self:onPlayerAdded(player)
	end

	return self
end

--==========================================================================
-- 로비로 돌려보내기
--==========================================================================

--[[
	예약 코드 없이 같은 플레이스로 텔레포트하면 공개 서버(= 로비)로 간다.
	autoQueue 를 실어 보내면 도착하자마자 다시 큐에 선다 — "다시 매칭" 이 그것이다.
]]
local function sendToLobby(player, autoQueue)
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({ autoQueue = autoQueue == true })

	for attempt = 1, Settings.teleportRetries do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, { player }, options)
		end)
		if ok then
			return true
		end
		warn(("[TCG] 로비 복귀 실패 %d회차: %s"):format(attempt, tostring(err)))
		task.wait(Settings.teleportRetryDelay)

		if player.Parent ~= Players then
			return false
		end
	end
	return false
end

function Arena:dismiss(player, text, autoQueue)
	if text then
		self.remotes.Lobby:FireClient(player, { screen = Screen.Error, text = text })
	end
	task.spawn(sendToLobby, player, autoQueue)
end

function Arena:dismissAll(text)
	for _, player in Players:GetPlayers() do
		self:dismiss(player, text, false)
	end
end

--==========================================================================
-- 도착
--==========================================================================

local function readArrival(player)
	local joinData = player:GetJoinData()
	local data = joinData and joinData.TeleportData

	if type(data) ~= "table" then
		return nil
	end
	if type(data.seat) ~= "number" or (data.seat ~= 1 and data.seat ~= 2) then
		return nil
	end
	if type(data.matchId) ~= "string" then
		return nil
	end
	return data
end

function Arena:onPlayerAdded(player)
	if self.closed then
		self:dismiss(player, "이 대전은 이미 끝났습니다", false)
		return
	end

	local arrival = readArrival(player)
	if not arrival then
		-- 매칭을 거치지 않고 들어온 사람(예약 서버 링크 직접 입장 등)
		self:dismiss(player, "매칭을 통해 입장해 주세요", false)
		return
	end

	self.arrivals[player] = arrival
	self:startWaitTimer()

	self.remotes.Lobby:FireClient(player, {
		screen = Screen.Waiting,
		text = ("%s 님을 기다리는 중"):format(arrival.opponentName or "상대"),
	})

	self:loadDeck(player)
end

--[[
	이 사람이 이번 판에 쓸 덱을 읽어둔다.

	읽기는 yield 하므로 도착 처리와 분리한다 — 여기서 기다리면 먼저 온 사람의
	대기 화면이 저장소 응답만큼 늦게 뜬다.

	DeckStore:get 은 실패해도 스타터 덱을 돌려준다(nil 이 아니다). 그래서 "덱을 못 읽어서
	판이 안 열리는" 경우는 없다 — 저장소가 죽어 있으면 두 사람 다 스타터로 둔다.
]]
function Arena:loadDeck(player)
	task.spawn(function()
		local deck = Decks.toList(self.deckStore:get(player))

		-- 읽는 사이에 나갔으면 남길 것이 없다.
		if not self.arrivals[player] then
			return
		end

		self.decks[player] = deck
		self:tryStart()
	end)
end

--==========================================================================
-- 시작
--==========================================================================

--[[
	두 도착 데이터가 같은 판을 가리키는가.
	어긋나면 시작하지 않는다 — 두 사람이 서로 다른 게임을 보는 것보다 낫다.
]]
local function agree(a, b)
	return a.matchId == b.matchId and a.seat ~= b.seat
end

function Arena:tryStart()
	if self.runner or self.closed then
		return
	end

	local waiting = {}
	for player, arrival in self.arrivals do
		if player.Parent ~= Players then
			self.arrivals[player] = nil
			self.decks[player] = nil
		elseif self.decks[player] then
			-- 덱이 아직 안 읽힌 사람은 세지 않는다. 다 읽히면 loadDeck 이 다시 부른다.
			table.insert(waiting, { player = player, arrival = arrival, deck = self.decks[player] })
		end
	end

	if #waiting < 2 then
		return
	end

	local a, b = waiting[1], waiting[2]
	if not agree(a.arrival, b.arrival) then
		warn("[TCG] 도착 데이터 불일치 — 판을 열지 않습니다")
		self:dismissAll("매칭 정보가 어긋났습니다. 다시 시도해 주세요.")
		self.closed = true
		return
	end

	local seats = {}
	seats[a.arrival.seat] = { player = a.player, deck = a.deck }
	seats[b.arrival.seat] = { player = b.player, deck = b.deck }

	--[[
		시드는 여기서 뽑는다. 두 사람이 이미 모였으므로 서버끼리 합의할 필요가 없고,
		클라이언트가 볼 수 있는 어떤 값에서도 유도되지 않는다.
		Random.new 는 예측 가능한 시각이 아니라 시스템 엔트로피에서 씨앗을 얻는다.
	]]
	local seed = Random.new():NextInteger(1, 2147483646)

	self.runner = MatchRunner.new(self.remotes, {
		seats = seats,
		seed = seed,
		onFinish = function()
			self:onMatchFinished()
		end,
	})

	self.host:attach(self.runner)

	for _, entry in waiting do
		self.remotes.Lobby:FireClient(entry.player, { screen = Screen.Battle, mode = "pvp" })
	end

	print(("[TCG] 대전 시작 — %s"):format(a.arrival.matchId))
end

--==========================================================================
-- 대기 시간 초과
--==========================================================================

--[[
	상대를 기다리는 시계. **첫 사람이 도착한 시점부터** 잰다.

	서버가 뜬 시점부터 재면 안 된다 — 예약 서버 기동이 느려 첫 사람이 25초에 도착하면
	5초만 기다리고 둘 다 쫓아내게 된다. 기다리는 사람이 생겼을 때 시작해야 맞다.
]]
function Arena:startWaitTimer()
	if self.waitTimerStarted then
		return
	end
	self.waitTimerStarted = true

	task.spawn(function()
		task.wait(Settings.arenaWaitTimeout)
		if self.runner or self.closed then
			return
		end

		self.closed = true
		-- 상대가 안 왔을 뿐이니 다시 큐에 세워준다. 여기서 홈으로 돌려보내면
		-- 텔레포트가 한 번 실패했을 때 사용자가 처음부터 다시 눌러야 한다.
		for _, player in Players:GetPlayers() do
			self:dismiss(player, "상대가 접속하지 않았습니다. 다시 찾습니다.", true)
		end
	end)
end

--==========================================================================
-- 종료
--==========================================================================

--[[
	판이 끝나면 결과 화면을 잠시 보여주고 로비로 돌려보낸다.
	그 전에 사용자가 "다시 매칭" / "나가기" 를 누르면 그쪽이 먼저 처리된다.
]]
function Arena:onMatchFinished()
	self.closed = true

	task.delay(Settings.arenaLingerAfterMatch, function()
		for _, player in Players:GetPlayers() do
			self:dismiss(player, nil, false)
		end
	end)
end

function Arena:onMessage(player, payload)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end

	if payload.kind == "hello" then
		if self.runner then
			self.remotes.Lobby:FireClient(player, { screen = Screen.Battle, mode = "pvp" })
		else
			local arrival = self.arrivals[player]
			self.remotes.Lobby:FireClient(player, {
				screen = Screen.Waiting,
				text = ("%s 님을 기다리는 중"):format(arrival and arrival.opponentName or "상대"),
			})
		end
	elseif payload.kind == "leave" then
		self:dismiss(player, nil, false)
	elseif payload.kind == "requeue" then
		self:dismiss(player, nil, true)
	end
end

return Arena
