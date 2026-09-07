--[[
	같은 서버 안에서만 짝을 짓는 큐 백엔드.

	**Studio / 텔레포트를 쓸 수 없는 환경 전용이다.** 실제 게임에서는 CrossServer 가 돈다
	(Matchmaker.init 이 고른다). 이게 필요한 이유는 하나뿐이다 — TeleportService 는
	Studio 에서 아예 동작하지 않아서, 이게 없으면 매칭 코드를 한 줄도 실행해볼 수 없다.

	Studio 의 "플레이어 2명" 테스트로 큐 → 매칭 → 대전까지 전부 확인할 수 있고,
	CrossServer 와 **같은 Matchmaking.plan** 을 부르므로 짝짓기 규칙은 완전히 같다.
	다른 것은 엔트리가 어디에 담기느냐(로컬 테이블 vs MemoryStore)뿐이다.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)
local Matchmaking = require(Shared.Matchmaking)

local Settings = require(script.Parent.Settings)

local Local = {}
Local.__index = Local

function Local.new(onMatchFound)
	local self = setmetatable({}, Local)

	self.onMatchFound = onMatchFound
	self.entries = {} :: { [Player]: any }
	self.running = false
	self.seedRng = Rules.RNG.new(os.time() + math.floor(os.clock() * 1e6))

	return self
end

function Local:describe()
	return "같은 서버 (Studio 테스트용)"
end

function Local:isQueued(player)
	return self.entries[player] ~= nil
end

function Local:enqueue(player)
	if self.entries[player] then
		return true
	end
	self.tokenCount = (self.tokenCount or 0) + 1
	self.entries[player] = Matchmaking.newEntry(
		player.UserId,
		player.DisplayName,
		game.JobId,
		os.time(),
		("local-%d"):format(self.tokenCount)
	)
	return true
end

function Local:cancel(player)
	self.entries[player] = nil
end

function Local:count()
	local n = 0
	for _ in self.entries do
		n += 1
	end
	return n
end

--[[
	큐를 한 번 훑는다. 짝이 지어지면 그 자리에서 onMatchFound 를 부른다.
	accessCode 가 nil 이므로 호출자는 "이 서버에서 바로 시작" 으로 처리한다.
]]
function Local:poll()
	local byUserId = {}
	local entries = {}

	for player, entry in self.entries do
		if player.Parent == Players then
			-- 접속해 있는 동안은 계속 살아 있다고 표시한다. 이게 없으면 TTL 이 지난 뒤
			-- 큐에서 조용히 빠지는데 화면은 "상대를 찾는 중" 그대로다.
			entry.refreshedAt = os.time()
			byUserId[entry.userId] = player
			table.insert(entries, entry)
		else
			self.entries[player] = nil -- 나간 사람
		end
	end

	if #entries < 2 then
		return
	end

	local plan = Matchmaking.plan(entries, {
		now = os.time(),
		ttl = Settings.entryTtl,
		seed = self.seedRng:nextInteger(1, 2147483646),
		startingPlayerFor = Rules.startingPlayerFor,
	})

	for _, entry in plan.expired do
		local player = byUserId[entry.userId]
		if player then
			self.entries[player] = nil
		end
	end

	for _, match in plan.matches do
		-- 먼저 큐에서 빼야 한다. onMatchFound 안에서 다시 poll 이 돌 일은 없지만,
		-- 매치 생성이 실패해도 두 사람이 큐에 남아 다른 매치에 또 들어가면 안 된다.
		local players = {}
		for seat, entry in match.seats do
			local player = byUserId[entry.userId]
			self.entries[player] = nil
			players[seat] = player
		end

		-- accessCode 가 없다 = 텔레포트 없이 이 서버에서 바로 시작한다는 뜻
		self.onMatchFound(match, players)
	end
end

function Local:start()
	if self.running then
		return
	end
	self.running = true

	task.spawn(function()
		while self.running do
			local ok, err = pcall(function()
				self:poll()
			end)
			if not ok then
				warn(("[TCG] 로컬 매칭 폴링 실패: %s"):format(tostring(err)))
			end
			task.wait(Settings.pollInterval)
		end
	end)
end

function Local:stop()
	self.running = false
end

return Local
