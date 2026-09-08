--[[
	공개 서버(= 로비)에서 도는 것.

	여기서는 카드를 한 장도 내지 않는다. 하는 일은 셋이다.
	  1. 시작 화면 상태를 클라이언트에 알려준다        (Lobby 리모트)
	  2. 빠른 대전 큐 등록/취소                        (Matchmaker)
	  3. AI 연습은 큐를 타지 않고 이 자리에서 한 판 띄운다

	PvP 매치는 여기서 굴리지 않는다. 짝이 지어지면 두 사람은 예약 서버로 텔레포트되고
	거기서 Arena 가 판을 연다. 로비 서버가 대전까지 맡으면 인원이 많은 서버일수록
	느려져서, 매칭 운이 곧 플레이 품질이 된다.

	(예외: Studio 의 같은 서버 백엔드는 텔레포트가 없으므로 여기서 바로 시작한다.
	 accessCode 가 없는 매치가 그 경우다.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AI = require(Shared.AI)
local Net = require(Shared.Net)

local Decks = require(Shared.Decks)

local DeckStore = require(script.Parent.DeckStore)
local MatchRunner = require(script.Parent.MatchRunner)
local Matchmaker = require(script.Parent.Matchmaker)

local Screen = Net.LobbyScreen

local Lobby = {}
Lobby.__index = Lobby

function Lobby.new(remotes, host)
	local self = setmetatable({}, Lobby)

	self.remotes = remotes
	self.host = host
	self.screens = {} :: { [Player]: any }
	self.deckStore = DeckStore.new()

	self.matchmaker = Matchmaker.new({
		onMatchFound = function(player, opponentName)
			self:setScreen(player, { screen = Screen.Found, opponent = opponentName })
		end,

		onMatchReady = function(match, players)
			self:startLocalMatch(match, players)
		end,

		onTeleportFail = function(player)
			self:setScreen(player, {
				screen = Screen.Error,
				text = "대전 서버로 이동하지 못했습니다. 다시 시도해 주세요.",
			})
		end,
	})

	remotes.Lobby.OnServerEvent:Connect(function(player, payload)
		local ok, err = pcall(function()
			self:onMessage(player, payload)
		end)
		if not ok then
			warn(("[TCG] 로비 요청 처리 실패: %s"):format(tostring(err)))
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.matchmaker:cancel(player)
		self.screens[player] = nil
		self.deckStore:forget(player)
	end)

	for _, player in Players:GetPlayers() do
		self:onPlayerAdded(player)
	end

	self.matchmaker:start()
	return self
end

--==========================================================================
-- 화면 상태
--==========================================================================

--[[
	화면 전환의 주인은 서버다. 클라이언트가 자기 판단으로 화면을 바꾸면
	"큐에 서 있는데 시작 화면이 보이는" 상태가 만들어진다.
]]
--[[
	클라이언트에게 나갈 모양으로 다듬는다.

	대기 화면은 기준 시각(since) 이 아니라 **경과 초(elapsed)** 를 보낸다.
	since 를 그대로 보내면 클라이언트가 `os.time() - since` 를 계산하게 되는데,
	기기 시계가 어긋난 사람은 0:00 에 멈추거나 처음부터 몇 분이 찍힌다.
	뺄셈은 시계가 하나뿐인 서버에서 한다.

	hello 로 다시 내려줄 때도 이 함수를 거치므로, 화면을 다시 받아도 타이머가
	0 으로 되돌아가지 않는다 — 그때그때 다시 계산되기 때문이다.
]]
function Lobby:outgoing(payload)
	if payload.screen ~= Screen.Queued or not payload.since then
		return payload
	end

	return {
		screen = payload.screen,
		elapsed = math.max(0, os.time() - payload.since),
	}
end

--[[
	이 사람이 이번 판에 쓸 덱(목록 모양). 저장이 없거나 못 읽으면 스타터 덱이다.
]]
function Lobby:deckFor(player)
	if not player then
		return Decks.starter()
	end
	return Decks.toList(self.deckStore:get(player))
end

function Lobby:setScreen(player, payload)
	self.screens[player] = payload
	self.remotes.Lobby:FireClient(player, self:outgoing(payload))
end

function Lobby:home(player, text)
	self:setScreen(player, { screen = Screen.Home, text = text })
end

--==========================================================================
-- 접속
--==========================================================================

--[[
	대전이 끝나고 "다시 매칭" 을 누른 사람은 로비로 돌아오면서 autoQueue 를 달고 온다.
	도착하자마자 큐에 넣어주지 않으면 버튼을 한 번 더 눌러야 한다.
]]
function Lobby:onPlayerAdded(player)
	self:home(player)

	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData

	if type(teleportData) == "table" and teleportData.autoQueue then
		self:enqueue(player)
	end
end

--==========================================================================
-- 요청 처리
--==========================================================================

function Lobby:onMessage(player, payload)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end

	if payload.kind == "hello" then
		local current = self.screens[player] or { screen = Screen.Home }
		self.remotes.Lobby:FireClient(player, self:outgoing(current))
	elseif payload.kind == "queue" then
		self:enqueue(player)
	elseif payload.kind == "cancel" then
		self.matchmaker:cancel(player)
		self:home(player)
	elseif payload.kind == "home" then
		--[[
			시작 화면으로. hello 로는 안 된다 — hello 는 "지금 화면을 다시 달라" 라서
			덱 편집 화면이 그대로 다시 온다. 돌아가는 것은 별개의 요청이다.
		]]
		self.matchmaker:cancel(player)
		self:home(player)
	elseif payload.kind == "deck" then
		self:openDeck(player)
	elseif payload.kind == "deckSave" then
		self:saveDeck(player, payload.entries)
	elseif payload.kind == "deckReset" then
		self:resetDeck(player)
	elseif payload.kind == "practice" then
		self:startPractice(player)
	elseif payload.kind == "leave" then
		self:leaveMatch(player)
	elseif payload.kind == "requeue" then
		self:leaveMatch(player)
		self:enqueue(player)
	end
end

function Lobby:enqueue(player)
	-- 판을 두는 중에 큐에 서면 두 판이 겹친다.
	if self.host:runnerFor(player) then
		return
	end

	local ok, reason = self.matchmaker:enqueue(player)
	if not ok then
		self:setScreen(player, { screen = Screen.Error, text = reason or "큐에 등록하지 못했습니다" })
		return
	end

	self:setScreen(player, { screen = Screen.Queued, since = os.time() })
end

--==========================================================================
-- 덱 편집
--==========================================================================

--[[
	덱 편집 화면을 연다.

	판을 두는 중에는 열지 않는다 — 덱은 판이 시작될 때 정해지므로, 두는 중에 바꾸면
	"바꿨는데 안 바뀌는" 것처럼 보인다. 큐에 서 있을 때도 막는다(같은 이유).
]]
function Lobby:openDeck(player)
	if self.host:runnerFor(player) then
		return
	end
	self.matchmaker:cancel(player)

	self:setScreen(player, {
		screen = Screen.Deck,
		entries = self.deckStore:get(player),
	})
end

function Lobby:saveDeck(player, entries)
	local ok, reason = self.deckStore:save(player, entries)

	--[[
		실패해도 화면은 덱 편집 그대로 두고 이유만 알려준다. 시작 화면으로 되돌리면
		방금 편집한 것이 통째로 날아간 것처럼 보인다.

		저장에 실패해도 self.deckStore 의 캐시에는 들어가 있다(DeckStore 주석 참조).
		그래서 이 서버에 있는 동안은 그 덱으로 대전할 수 있다.
	]]
	self:setScreen(player, {
		screen = Screen.Deck,
		entries = self.deckStore:get(player),
		saved = ok,
		text = ok and "저장했습니다" or tostring(reason or "저장하지 못했습니다"),
	})
end

function Lobby:resetDeck(player)
	local starter = Decks.starterEntries()
	local ok = self.deckStore:save(player, starter)

	self:setScreen(player, {
		screen = Screen.Deck,
		entries = self.deckStore:get(player),
		saved = ok,
		text = ok and "스타터 덱으로 되돌렸습니다" or "되돌렸지만 저장하지 못했습니다",
	})
end

--==========================================================================
-- AI 연습
--==========================================================================

function Lobby:startPractice(player)
	if self.host:runnerFor(player) then
		return
	end
	self.matchmaker:cancel(player)

	local runner = MatchRunner.new(self.remotes, {
		seats = {
			[1] = { player = player, deck = self:deckFor(player) },
			[2] = { ai = AI.Difficulty.Normal, name = "훈련용 AI" },
		},
		allowRestart = true, -- 연습이니까 R 로 계속 새 판을 열 수 있다
	})

	self.host:attach(runner)
	self:setScreen(player, { screen = Screen.Battle, mode = "practice" })
end

--==========================================================================
-- 같은 서버 매칭 (Studio 전용 경로)
--==========================================================================

function Lobby:startLocalMatch(match, players)
	local seats = {}
	for seat = 1, 2 do
		seats[seat] = { player = players[seat], deck = self:deckFor(players[seat]) }
	end

	local runner = MatchRunner.new(self.remotes, {
		seats = seats,
		seed = match.seed,
		startingPlayerId = match.startingPlayerId,
	})

	self.host:attach(runner)

	for _, player in players do
		self:setScreen(player, { screen = Screen.Battle, mode = "pvp" })
	end
end

--==========================================================================
-- 대전에서 나오기
--==========================================================================

function Lobby:leaveMatch(player)
	-- 진행 중인 판을 두고 나가면 항복과 같다. 끝난 판이면 아무 일도 일어나지 않는다.
	self.host:release(player)
	self:home(player)
end

return Lobby
