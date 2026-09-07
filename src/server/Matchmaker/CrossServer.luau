--[[
	서버를 넘나드는 큐 백엔드. 실제 게임에서 도는 것은 이쪽이다.

	세 서비스가 각자 한 가지씩 맡는다.

	  MemoryStoreQueue   모든 서버가 공유하는 대기열. "지금 누가 기다리는가"
	  MessagingService   짝이 지어졌음을 다른 서버에 알린다. "이 사람 태워보내라"
	  TeleportService    예약 서버를 하나 잡고 두 사람을 그리로 보낸다

	왜 세 개가 다 필요한가 — **텔레포트는 자기 서버의 플레이어에게만 걸 수 있다.**
	그래서 짝을 지은 서버가 상대편을 직접 옮길 수 없고, 상대가 붙어 있는 서버에게
	부탁해야 한다. 그 부탁이 다닐 길이 MessagingService 다.

	    A서버(김) ─AddAsync─┐
	                        ├─→ [MemoryStore 큐] ←─ 아무 서버나 ReadAsync 로 훑는다
	    B서버(이) ─AddAsync─┘                          │
	                                                   ├ 짝이 나오면 ReserveServerAsync
	                                                   └ PublishAsync {accessCode, seats}
	                                                        │
	                                        A서버 ─────────┴──────── B서버
	                                     (김을 태움)              (이를 태움)
	                                                │                │
	                                                └─→ 예약 서버 ←──┘  = Arena

	--------------------------------------------------------------------------
	알려진 한계

	1. MemoryStoreQueue 는 개별 항목 삭제를 지원하지 않는다(읽은 배치 단위로만 지운다).
	   그래서 "큐 취소" 는 엔트리를 지우지 못한다. 거름망이 두 겹이다.

	     · 취소를 전 서버에 뿌려 blocked 목록에 넣는다 → 짝짓기 단계에서 걸러진다
	     · 그래도 짝지어졌다면 태우기 직전의 isQueued 검사에서 막는다

	   두 번째만 있으면 **상대가** 아무도 오지 않는 대전 서버로 끌려간다.
	   (취소한 사람 본인은 안 끌려가지만, 짝이 성립해버렸기 때문이다)
	   남은 유령 엔트리는 TTL 로 사라진다.

	2. 배치를 읽은 뒤 RemoveAsync 가 실패하면 같은 엔트리가 다시 보여 이중 매칭이
	   날 수 있다. Arena 가 "두 사람의 텔레포트 데이터가 서로 일치하는가" 를 확인하고
	   어긋나면 판을 시작하지 않으므로, 이상한 판이 굴러가지는 않는다.

	3. Studio 에서는 TeleportService 가 동작하지 않는다. Matchmaker 의 init 이
	   그런 환경에서는 Local 백엔드를 고른다.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)
local Matchmaking = require(Shared.Matchmaking)

local Settings = require(script.Parent.Settings)

local CrossServer = {}
CrossServer.__index = CrossServer

function CrossServer.new(onMatchFound)
	local self = setmetatable({}, CrossServer)

	self.onMatchFound = onMatchFound
	self.queue = MemoryStoreService:GetQueue(Settings.queueName, Settings.invisibilityTimeout)
	self.queued = {} :: { [Player]: any }
	self.blocked = {} :: { [number]: number } -- userId -> 언제까지 거를지
	self.running = false

	-- 매치 시드를 뽑는 난수. os.clock 을 섞어 서버마다 다른 수열에서 시작한다.
	-- (시드를 userId 나 시각에서 유도하면 클라이언트가 셔플을 예측할 수 있다)
	self.seedRng = Rules.RNG.new(os.time() + math.floor(os.clock() * 1e6))

	return self
end

function CrossServer:describe()
	return "크로스서버 (MemoryStore + 텔레포트)"
end

--==========================================================================
-- 등록 / 취소
--==========================================================================

function CrossServer:isQueued(player)
	return self.queued[player] ~= nil
end

function CrossServer:enqueue(player)
	if self.queued[player] then
		return true
	end

	local entry = Matchmaking.newEntry(player.UserId, player.DisplayName, game.JobId, os.time())

	local ok, err = pcall(function()
		self.queue:AddAsync(entry, Settings.entryTtl)
	end)

	if not ok then
		warn(("[TCG] 큐 등록 실패 (%s): %s"):format(player.Name, tostring(err)))
		return false, "매칭 서버에 연결하지 못했습니다"
	end

	self.queued[player] = entry
	return true
end

--[[
	큐 취소.

	엔트리를 지울 수 없으므로 (a) 로컬 표시를 끄고 (b) 다른 서버들에게 알린다.
	(b) 가 없으면 남은 유령이 다른 사람과 짝지어져, **그 사람이** 혼자 대전 서버로
	끌려가 30초를 기다렸다 돌아온다.
]]
function CrossServer:cancel(player)
	if not self.queued[player] then
		return
	end
	self.queued[player] = nil
	self:block(player.UserId)

	local ok, err = pcall(function()
		MessagingService:PublishAsync(Settings.messagingTopic, {
			kind = "cancel",
			origin = game.JobId,
			userId = player.UserId,
		})
	end)
	if not ok then
		warn(("[TCG] 취소 전파 실패: %s"):format(tostring(err)))
	end
end

--[[
	이 userId 를 짝짓기에서 뺀다. 엔트리 수명(TTL)만큼만 기억하면 된다 —
	그 뒤에는 유령 엔트리 자체가 큐에서 사라지므로 더 들고 있을 이유가 없다.
]]
function CrossServer:block(userId)
	self.blocked[userId] = os.time() + Settings.entryTtl
end

function CrossServer:blockList()
	local now = os.time()
	local out = {}

	for userId, expiresAt in self.blocked do
		if expiresAt <= now then
			self.blocked[userId] = nil
		else
			out[userId] = true
		end
	end

	return out
end

function CrossServer:count()
	local n = 0
	for _ in self.queued do
		n += 1
	end
	return n
end

--==========================================================================
-- 폴링 — 짝짓기
--==========================================================================

local function readBatch(self)
	local items, readId
	local ok, err = pcall(function()
		items, readId = self.queue:ReadAsync(Settings.readBatch, false, 0)
	end)

	if not ok then
		warn(("[TCG] 큐 읽기 실패: %s"):format(tostring(err)))
		return nil, nil
	end
	return items, readId
end

local function putBack(self, entries)
	for _, entry in entries do
		-- 남은 수명만큼만 다시 넣는다. 그러지 않으면 되돌릴 때마다 수명이 갱신돼
		-- 주인 없는 엔트리가 영원히 큐를 맴돈다.
		local remaining = Settings.entryTtl - (os.time() - entry.joinedAt)
		if remaining > 1 then
			pcall(function()
				self.queue:AddAsync(entry, math.floor(remaining))
			end)
		end
	end
end

function CrossServer:poll()
	local items, readId = readBatch(self)
	if not items or #items < 2 then
		return -- 배치를 지우지 않는다. 안 보이는 시간이 지나면 다시 나타난다.
	end

	local plan = Matchmaking.plan(items, {
		now = os.time(),
		ttl = Settings.entryTtl,
		seed = self.seedRng:nextInteger(1, 2147483646),
		blocked = self:blockList(),
		startingPlayerFor = Rules.startingPlayerFor,
	})

	--------------------------------------------------------------------
	-- 예약 서버를 먼저 잡는다. 실패한 매치는 없던 일로 하고 큐에 되돌린다.
	--------------------------------------------------------------------
	local ready = {}
	local returned = table.clone(plan.waiting)

	for _, match in plan.matches do
		local accessCode
		local ok, err = pcall(function()
			-- ReserveServer(비Async) 는 deprecated 다. 같은 일을 하지만 이름이 다르다.
			accessCode = TeleportService:ReserveServerAsync(game.PlaceId)
		end)

		if ok and accessCode then
			match.accessCode = accessCode
			table.insert(ready, match)
		else
			warn(("[TCG] 예약 서버 확보 실패: %s"):format(tostring(err)))
			table.insert(returned, match.seats[1])
			table.insert(returned, match.seats[2])
		end
	end

	--------------------------------------------------------------------
	-- 배치를 소비한다. 만료·중복은 여기서 그냥 사라진다.
	--------------------------------------------------------------------
	local removed = pcall(function()
		self.queue:RemoveAsync(readId)
	end)

	if not removed then
		-- 지우지 못했다 = 같은 엔트리가 곧 다시 보인다.
		-- 매치는 그대로 진행하되(사람들은 이미 서버를 잡았다) 되돌리기는 생략한다.
		warn("[TCG] 큐 배치 제거 실패 — 이중 매칭 가능. Arena 가 걸러낸다")
	else
		putBack(self, returned)
	end

	--------------------------------------------------------------------
	-- 모든 서버에 알린다
	--------------------------------------------------------------------
	for _, match in ready do
		self:announce(match)
	end
end

--==========================================================================
-- 서버 간 전달
--==========================================================================

function CrossServer:announce(match)
	local payload = {
		kind = "match",
		origin = game.JobId,
		accessCode = match.accessCode,
		id = match.id,
		seed = match.seed,
		startingPlayerId = match.startingPlayerId,
		seats = match.seats,
	}

	-- 내 서버 몫은 직접 처리한다. 자기 자신에게 오는 배달을 기다리지 않으므로
	-- 게시 지연만큼 빨라지고, 중복 처리도 생기지 않는다(아래에서 origin 을 거른다).
	self:dispatch(payload)

	local ok, err = pcall(function()
		MessagingService:PublishAsync(Settings.messagingTopic, payload)
	end)
	if not ok then
		warn(("[TCG] 매칭 알림 실패: %s"):format(tostring(err)))
	end
end

--[[
	이 서버에 붙어 있는 좌석만 골라 태운다.

	여기가 "취소했는데 끌려가는" 사고를 막는 유일한 지점이다 — 큐에서 엔트리를
	지울 방법이 없으므로, 태우기 직전의 로컬 상태가 최종 판단이다.
]]
function CrossServer:dispatch(payload)
	local match = {
		id = payload.id,
		seed = payload.seed,
		startingPlayerId = payload.startingPlayerId,
		accessCode = payload.accessCode,
		seats = payload.seats,
	}

	local mine = {}
	local any = false

	for seat, entry in payload.seats do
		if entry.serverId == game.JobId then
			local player = Players:GetPlayerByUserId(entry.userId)
			if player and self:isQueued(player) then
				self.queued[player] = nil
				mine[seat] = player
				any = true
			end
		end
	end

	if any then
		self.onMatchFound(match, mine)
	end
end

--==========================================================================
-- 텔레포트
--==========================================================================

--[[
	예약 서버로 보낸다. 실패하면 몇 번 다시 시도하고, 그래도 안 되면 false 를 준다.
	(Roblox 텔레포트는 간헐적으로 실패한다 — 재시도는 선택이 아니라 규정에 가깝다)
]]
function CrossServer.teleport(player, match, seat)
	local opponentName = match.seats[if seat == 1 then 2 else 1].name

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = match.accessCode
	options:SetTeleportData({
		matchId = match.id,
		seed = match.seed,
		startingPlayerId = match.startingPlayerId,
		seat = seat,
		opponentName = opponentName,
	})

	for attempt = 1, Settings.teleportRetries do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, { player }, options)
		end)
		if ok then
			return true
		end

		warn(
			("[TCG] 텔레포트 실패 %d/%d (%s): %s"):format(
				attempt,
				Settings.teleportRetries,
				player.Name,
				tostring(err)
			)
		)
		task.wait(Settings.teleportRetryDelay)

		if player.Parent ~= Players then
			return false
		end
	end

	return false
end

--==========================================================================
-- 시작 / 정지
--==========================================================================

function CrossServer:start()
	if self.running then
		return
	end
	self.running = true

	local ok, connection = pcall(function()
		return MessagingService:SubscribeAsync(Settings.messagingTopic, function(message)
			local payload = message.Data
			if type(payload) ~= "table" or payload.origin == game.JobId then
				return -- 내가 보낸 것은 보내면서 이미 처리했다
			end

			if payload.kind == "cancel" then
				self:block(payload.userId)
			elseif payload.kind == "match" then
				self:dispatch(payload)
			end
		end)
	end)

	if ok then
		self.subscription = connection
	else
		warn(("[TCG] 매칭 채널 구독 실패: %s"):format(tostring(connection)))
	end

	task.spawn(function()
		while self.running do
			local pollOk, err = pcall(function()
				self:poll()
			end)
			if not pollOk then
				warn(("[TCG] 매칭 폴링 실패: %s"):format(tostring(err)))
			end
			task.wait(Settings.pollInterval)
		end
	end)
end

function CrossServer:stop()
	self.running = false
	if self.subscription then
		self.subscription:Disconnect()
		self.subscription = nil
	end
end

return CrossServer
