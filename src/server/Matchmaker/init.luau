--[[
	빠른 대전 매칭. 로비 서버가 쓰는 유일한 진입점이다.

	    local matchmaker = Matchmaker.new({
	        onMatchReady   = function(match, players) end,  -- 이 서버에서 바로 시작
	        onMatchFound   = function(player, opponentName) end,
	        onTeleportFail = function(player) end,
	    })
	    matchmaker:start()
	    matchmaker:enqueue(player)

	큐 백엔드는 두 가지고, 여기서 고른다.

	  CrossServer  실제 게임. MemoryStore 큐 + 예약 서버 텔레포트
	  Local        Studio. 같은 서버 안에서만 짝을 짓는다

	고르는 기준은 "텔레포트가 가능한 환경인가" 하나다. TeleportService 는 Studio 에서
	동작하지 않으므로 Studio 에서는 크로스서버 경로를 아예 실행할 수 없다.
	두 백엔드는 짝짓기 규칙(Shared.Matchmaking)을 공유하므로, Studio 에서 확인한
	"누가 누구와 붙는가" 는 실제 서버에서도 그대로다. 다른 것은 엔트리가 담기는 곳뿐이다.
]]

local RunService = game:GetService("RunService")

local CrossServer = require(script.CrossServer)
local Local = require(script.Local)
local Settings = require(script.Settings)

local Matchmaker = {}
Matchmaker.__index = Matchmaker

Matchmaker.Settings = Settings

--==========================================================================
-- 생성
--==========================================================================

function Matchmaker.new(callbacks)
	local self = setmetatable({}, Matchmaker)

	self.callbacks = callbacks

	local constructor = if RunService:IsStudio() then Local else CrossServer
	self.backend = constructor.new(function(match, players)
		self:onMatchFound(match, players)
	end)

	print(("[TCG] 매칭 백엔드: %s"):format(self.backend:describe()))
	return self
end

--==========================================================================
-- 큐
--==========================================================================

function Matchmaker:enqueue(player)
	return self.backend:enqueue(player)
end

function Matchmaker:cancel(player)
	self.backend:cancel(player)
end

function Matchmaker:isQueued(player)
	return self.backend:isQueued(player)
end

function Matchmaker:start()
	self.backend:start()
end

function Matchmaker:stop()
	self.backend:stop()
end

--==========================================================================
-- 짝이 지어졌을 때
--==========================================================================

local function opponentNameFor(match, seat)
	local other = match.seats[if seat == 1 then 2 else 1]
	return other and other.name or "상대"
end

--[[
	players = { [좌석] = Player } — 이 서버에 붙어 있는 좌석만 들어온다.
	크로스서버면 보통 한 명, 같은 서버 백엔드면 두 명 다.
]]
function Matchmaker:onMatchFound(match, players)
	for seat, player in players do
		self.callbacks.onMatchFound(player, opponentNameFor(match, seat))
	end

	-- 예약 코드가 없다 = 텔레포트할 곳이 없다 = 여기서 시작한다.
	if not match.accessCode then
		self.callbacks.onMatchReady(match, players)
		return
	end

	for seat, player in players do
		task.spawn(function()
			if not CrossServer.teleport(player, match, seat) then
				self.callbacks.onTeleportFail(player)
			end
		end)
	end
end

return Matchmaker
