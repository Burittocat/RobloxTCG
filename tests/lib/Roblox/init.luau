--!nolint DeprecatedApi
-- getfenv / setfenv 는 deprecated 로 표시돼 있지만, 이 파일의 존재 이유가
-- "모듈에 script 와 require 를 주입한 환경에서 실행하는 것" 이라 대체 수단이 없다.
-- (debug.info 는 환경을 읽을 뿐 바꾸지 못한다)

--[[
	Studio 없이 **서버와 클라이언트를 실제로 실행**하는 하네스.

	tests/run.luau 는 `src/shared` 만 돌린다. 서버·클라이언트 코드는 Roblox API 를 쓰므로
	Lune 에서 실행할 수 없기 때문이다. 그래서 `tests/check.luau` 가 문법만 훑는데,
	문법이 맞아도 `nil` 인덱싱 · 잘못된 require 경로 · 없는 Enum 항목은 그대로 남는다.
	그 셋이 정확히 "Studio 켜니까 출력창이 빨갛다" 의 정체다.

	여기서는 Roblox 표면을 흉내내서 그 코드를 진짜로 굴린다.

	    local world = Roblox.newWorld()
	    local lobby = world:newServer()          -- 공개 서버
	    lobby:boot()                             --   → src/server/Boot.server.luau 실행
	    local kim = lobby:addPlayer("Kim")
	    lobby:startClient(kim)                   --   → src/client/Boot.client.luau 실행
	    world:advance(3)                         -- 3초가 흘렀다

	흉내의 원칙은 하나다 — **모르는 것은 조용히 넘기지 않고 실패시킨다.**
	없는 클래스, 없는 속성, 없는 Enum, 없는 서비스, 없는 자식. 전부 그 자리에서 터진다.
	느슨하게 만들면 이 하네스는 "초록불을 주는 장식" 이 된다.

	--------------------------------------------------------------------------
	흉내내지 않는 것

	  · 픽셀 레이아웃 (UIListLayout 이 실제로 정렬하지 않는다)
	  · 복제(Replication) 지연 — FireClient 는 즉시 도착한다
	  · 속성 변경 신호(Changed / GetPropertyChangedSignal)
	  · 실제 시간 — 시계는 world:advance 로만 흐른다

	그래서 이 테스트가 통과해도 **화면이 예쁜지는 모른다.** 아는 것은
	"스크립트가 죽지 않고, 판이 돌고, 두 사람이 서로 다른 뷰를 받는다" 까지다.
]]

local fs = require("@lune/fs")

local Datatypes = require("@self/Datatypes")
local RobloxInstance = require("@self/Instance")
local Scheduler = require("@self/Scheduler")
local Signal = require("@self/Signal")

local Roblox = {}

local GLOBALS = getfenv(0)

-- 가상 os.time 의 기준점. 실제 값이 중요한 곳은 없고, 사람이 로그에서 알아보기 좋게
-- 그럴듯한 시각 하나를 고정해 둔다.
local VIRTUAL_EPOCH = 1_800_000_000

--==========================================================================
-- 파일 트리 → 인스턴스 트리
--==========================================================================

local function classOf(fileName)
	if fileName:match("%.server%.luau?$") then
		return "Script"
	elseif fileName:match("%.client%.luau?$") then
		return "LocalScript"
	end
	return "ModuleScript"
end

local function instanceNameOf(fileName)
	local base = (fileName:gsub("%.luau?$", ""))
	base = (base:gsub("%.server$", ""))
	base = (base:gsub("%.client$", ""))
	return base
end

local function findInit(dirPath)
	for _, candidate in { "init.luau", "init.lua" } do
		local path = dirPath .. "/" .. candidate
		if fs.isFile(path) then
			return path
		end
	end
	return nil
end

--[[
	디스크를 **딱 한 번** 훑어 트리 설계도와 소스를 캐시한다.

	왜 미리 읽는가: Lune 의 fs 함수는 비동기라 코루틴을 양보한다. 서버를 코루틴 안에서
	만들면(텔레포트가 그렇다) 파일을 읽는 순간 그 코루틴이 Lune 의 이벤트 루프로 넘어가고,
	가상 시계를 감는 우리 스케줄러는 그 사실을 모른 채 앞으로 나아간다. 결과는
	"텔레포트했는데 대전 서버가 프로그램 끝날 때까지 안 뜨는" 유령 버그다.

	그래서 여기서(모듈 로드 시점, 코루틴 밖) 전부 읽어두고, 이후로는 디스크를 건드리지 않는다.
]]
local SOURCE = {} -- 경로 -> 파일 내용

local function describe(dirPath, name)
	local initPath = findInit(dirPath)
	if initPath then
		SOURCE[initPath] = fs.readFile(initPath)
	end

	local node = {
		name = name,
		className = initPath and "ModuleScript" or "Folder",
		path = initPath,
		children = {},
	}

	for _, entry in fs.readDir(dirPath) do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			table.insert(node.children, describe(full, entry))
		elseif entry:match("%.luau?$") and not entry:match("^init%.luau?$") then
			SOURCE[full] = fs.readFile(full)
			table.insert(node.children, {
				name = instanceNameOf(entry),
				className = classOf(entry),
				path = full,
				children = {},
			})
		end
	end

	return node
end

local BLUEPRINT = {
	shared = describe("src/shared", "Shared"),
	server = describe("src/server", "Server"),
	client = describe("src/client", "Client"),
}

--[[
	설계도로 인스턴스 트리를 짓는다. 디스크를 읽지 않으므로 코루틴 안에서도 안전하다.
]]
local function build(node, parent)
	local instance = RobloxInstance.newScript(node.className, node.name, node.path, parent)
	for _, child in node.children do
		build(child, instance)
	end
	return instance
end

--==========================================================================
-- 세계 — 여러 서버가 공유하는 것
--==========================================================================

local World = {}
World.__index = World

--[[
	MemoryStore · MessagingService · 예약 서버는 서버 경계를 넘는다.
	그래서 서버가 아니라 세계가 들고 있다. 크로스서버 매칭을 테스트할 수 있는 이유가 이것이다.
]]
function Roblox.newWorld(opts)
	opts = opts or {}

	local scheduler = Scheduler.new()
	Signal.useScheduler(scheduler)

	local world = setmetatable({
		scheduler = scheduler,
		placeId = opts.placeId or 1234567,
		servers = {},
		nextJobId = 1,
		nextUserId = 100,
		nextAccessCode = 1,
		dataStores = {}, -- 이름 -> { key -> 값 }

		memoryStore = {}, -- 이름 -> 큐
		subscribers = {}, -- 토픽 -> { fn }
		reserved = {}, -- accessCode -> 예약 서버(있으면)
		teleports = {}, -- 기록. 테스트가 들여다본다
		randomCount = 0,
		warnings = {},

		studio = opts.studio ~= false, -- 기본은 Studio (= 같은 서버 매칭)
	}, World)

	return world
end

function World:advance(seconds)
	self.scheduler:advance(seconds)
	return self
end

--[[
	쌓인 런타임 오류. 하나라도 있으면 Studio 였다면 출력창이 빨간 상태다.
]]
function World:errors()
	return self.scheduler:takeErrors()
end

--[[
	쌓인 warn 출력. Studio 라면 출력창의 노란 줄이다.
	(필드 이름 warnings 와 겹치지 않게 이름을 다르게 뒀다)
]]
function World:takeWarnings()
	local out = self.warnings
	self.warnings = {}
	return out
end

--==========================================================================
-- MemoryStore 큐
--==========================================================================

--[[
	MemoryStoreQueue 흉내. 진짜와 같은 두 가지 성질을 지킨다.

	  · ReadAsync 한 항목은 invisibilityTimeout 동안 다른 서버에게 안 보인다
	  · RemoveAsync 는 **읽은 배치 단위** 로만 지운다 (개별 삭제가 없다)

	두 번째 성질이 곧 "큐 취소가 엔트리를 지우지 못하는" 이유이고,
	CrossServer 백엔드가 그걸 로컬 표시로 우회하는 근거다.
]]
--[[
	MemoryStore 와 MessagingService 는 값을 **직렬화해서** 옮긴다. 하네스가 참조를
	그대로 들고 있으면 "큐에 넣은 뒤 로컬 테이블을 고쳤더니 큐 안의 값도 같이 바뀌는"
	일이 여기서만 일어난다 — 실제로는 옛 값이 나가는 코드가 초록불을 받는다.

	담을 수 없는 값(함수·스레드·혼합 키)도 진짜처럼 여기서 거절한다.
]]
local function serialized(value, path)
	local kind = type(value)

	if kind == "table" then
		local copy = {}
		for key, child in pairs(value) do
			local keyKind = type(key)
			if keyKind ~= "string" and keyKind ~= "number" then
				error(("직렬화할 수 없습니다: %s 의 키가 %s"):format(path, keyKind), 2)
			end
			copy[key] = serialized(child, ("%s.%s"):format(path, tostring(key)))
		end
		return copy
	end

	if kind == "function" or kind == "thread" or kind == "userdata" then
		error(("직렬화할 수 없습니다: %s 가 %s"):format(path, kind), 2)
	end

	return value
end

local function makeQueue(world, invisibilityTimeout)
	local queue = {
		items = {}, -- { value, expiresAt, hiddenUntil }
		reads = {}, -- readId -> { item }
		nextReadId = 1,
	}

	function queue:AddAsync(value, expiration)
		table.insert(self.items, {
			value = serialized(value, "AddAsync 값"),
			expiresAt = world.scheduler.clock + (expiration or 30),
			hiddenUntil = 0,
		})
	end

	function queue:ReadAsync(count, allOrNothing, _waitTimeout)
		local now = world.scheduler.clock
		local picked = {}

		for _, item in self.items do
			if item.expiresAt > now and item.hiddenUntil <= now and #picked < count then
				table.insert(picked, item)
			end
		end

		if allOrNothing and #picked < count then
			return nil, nil
		end
		if #picked == 0 then
			return {}, nil
		end

		local readId = ("read-%d"):format(self.nextReadId)
		self.nextReadId += 1
		self.reads[readId] = picked

		local values = {}
		for _, item in picked do
			item.hiddenUntil = now + invisibilityTimeout
			-- 읽는 쪽에도 사본을 준다. 받은 값을 고쳐도 큐 안의 값은 그대로여야 한다.
			table.insert(values, serialized(item.value, "ReadAsync 값"))
		end

		return values, readId
	end

	function queue:RemoveAsync(readId)
		local picked = self.reads[readId]
		if not picked then
			return
		end
		self.reads[readId] = nil

		for _, item in picked do
			for index, existing in self.items do
				if existing == item then
					table.remove(self.items, index)
					break
				end
			end
		end
	end

	return queue
end

--==========================================================================
-- 서버
--==========================================================================

local function makePlayersService(server)
	local service = {}

	service.CharacterAutoLoads = true
	service.PlayerAdded = server.playerAdded
	service.PlayerRemoving = server.playerRemoving

	function service:GetPlayers()
		return table.clone(server.players)
	end

	function service:GetPlayerByUserId(userId)
		for _, player in server.players do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end

	return service
end

local Server = {}
Server.__index = Server

--[[
	opts.reserved = true 면 예약 서버(= 대전 서버)로 만든다.
	Boot.server.luau 가 이 값을 보고 Lobby / Arena 를 고른다.
]]
function World:newServer(opts)
	opts = opts or {}

	local jobId = opts.jobId or ("job-%d"):format(self.nextJobId)
	self.nextJobId += 1

	local server = setmetatable({
		world = self,
		jobId = jobId,
		privateServerId = opts.reserved and (opts.accessCode or "private-" .. jobId) or "",
		privateServerOwnerId = 0,
		accessCode = opts.accessCode,

		players = {},
		playerAdded = Signal.new(),
		playerRemoving = Signal.new(),
		inputBegan = Signal.new(),
		caches = {},
		booted = false,
	}, Server)

	--------------------------------------------------------------------
	-- default.project.json 과 같은 모양의 트리
	--------------------------------------------------------------------
	local root = RobloxInstance.newScript("DataModel", "Game", nil, nil)
	server.tree = root

	local replicated = RobloxInstance.newScript("Folder", "ReplicatedStorage", nil, root)
	build(BLUEPRINT.shared, replicated)

	local remotes = RobloxInstance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = replicated
	for _, name in { "Sync", "Action", "Notice", "Lobby" } do
		local remote = RobloxInstance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remotes
	end
	server.remotes = remotes

	local serverScriptService = RobloxInstance.newScript("Folder", "ServerScriptService", nil, root)
	server.serverScripts = build(BLUEPRINT.server, serverScriptService)

	local starterPlayer = RobloxInstance.newScript("Folder", "StarterPlayer", nil, root)
	local starterScripts = RobloxInstance.newScript("Folder", "StarterPlayerScripts", nil, starterPlayer)
	server.clientScripts = build(BLUEPRINT.client, starterScripts)

	server.camera = RobloxInstance.new("Camera")
	-- 창 크기. Widgets.autoScale 이 이걸 보고 UI 배율을 정한다.
	server.camera.ViewportSize = opts.viewport or Datatypes.Vector2.new(1280, 720)
	server.workspace = { CurrentCamera = server.camera }
	server.playersService = makePlayersService(server)

	table.insert(self.servers, server)
	return server
end

function World:findReserved(accessCode)
	return self.reserved[accessCode]
end

--[[
	공개 서버 하나를 고른다. 텔레포트로 로비에 돌아올 때 어디로 갈지 정하는 데 쓴다.
]]
function World:publicServer()
	for _, server in self.servers do
		if server.privateServerId == "" then
			return server
		end
	end
	return nil
end

--==========================================================================
-- 서비스
--==========================================================================

function Server:service(name, vm)
	local world = self.world

	if name == "ReplicatedStorage" then
		if vm.remotesProxy then
			-- 클라이언트는 자기 신원이 박힌 리모트 프록시를 본다.
			local real = self.tree.ReplicatedStorage
			return {
				WaitForChild = function(_, childName)
					if childName == "Remotes" then
						return vm.remotesProxy
					end
					return real:WaitForChild(childName)
				end,
			}
		end
		return self.tree.ReplicatedStorage
	end

	if name == "Players" then
		if vm.player then
			local base = self.playersService
			return setmetatable({ LocalPlayer = vm.player }, { __index = base })
		end
		return self.playersService
	end

	if name == "RunService" then
		return {
			IsStudio = function()
				return world.studio
			end,
			IsServer = function()
				return vm.kind == "server"
			end,
			IsClient = function()
				return vm.kind == "client"
			end,
		}
	end

	if name == "StarterGui" then
		return {
			SetCoreGuiEnabled = function() end,
		}
	end

	if name == "UserInputService" then
		return { InputBegan = self.inputBegan }
	end

	if name == "TweenService" then
		return {
			Create = function(_, instance, _info, props)
				return {
					Play = function()
						-- 트윈의 끝 상태를 즉시 적용한다. 중간 프레임은 흉내내지 않는다.
						for key, value in props do
							instance[key] = value
						end
					end,
					Cancel = function() end,
				}
			end,
		}
	end

	if name == "MemoryStoreService" then
		return {
			GetQueue = function(_, queueName, invisibilityTimeout)
				local key = queueName
				if not world.memoryStore[key] then
					world.memoryStore[key] = makeQueue(world, invisibilityTimeout or 30)
				end
				return world.memoryStore[key]
			end,
		}
	end

	--[[
		DataStore. 진짜와 같은 성질 세 가지를 지킨다.

		  · 값을 **직렬화해서** 담는다 (참조를 들고 있으면 저장 안 한 변경이 남는다)
		  · UpdateAsync 는 현재 값을 받아 새 값을 돌려주는 함수를 받는다
		  · 서버가 달라도 같은 저장소를 본다 (월드 하나에 저장소 하나)

		흉내내지 않는 것: 호출 한도(throttle), 6분 캐시, 실패. 실패를 흉내내려면
		테스트가 실패를 넣을 수 있어야 하는데, 그건 필요해질 때 만든다.
	]]
	if name == "DataStoreService" then
		return {
			GetDataStore = function(_, storeName)
				world.dataStores[storeName] = world.dataStores[storeName] or {}
				local store = world.dataStores[storeName]

				return {
					GetAsync = function(_, key)
						return serialized(store[key], ("GetAsync(%s)"):format(tostring(key)))
					end,

					SetAsync = function(_, key, value)
						store[key] = serialized(value, ("SetAsync(%s)"):format(tostring(key)))
					end,

					UpdateAsync = function(_, key, transform)
						local current = serialized(store[key], "UpdateAsync 현재값")
						local nextValue = transform(current)
						if nextValue == nil then
							return nil -- 진짜 DataStore 도 nil 을 돌려주면 쓰지 않는다
						end
						store[key] = serialized(nextValue, ("UpdateAsync(%s)"):format(tostring(key)))
						return store[key]
					end,

					RemoveAsync = function(_, key)
						local old = store[key]
						store[key] = nil
						return old
					end,
				}
			end,
		}
	end

	if name == "MessagingService" then
		return {
			--[[
				**게시한 서버 자신에게도 배달한다.** 진짜 MessagingService 가 그렇다.

				예전에는 자기 자신을 건너뛰었다. 그래서 CrossServer 의 `payload.origin`
				에코 가드가 하네스에서 한 번도 실행되지 않았고, 그 가드를 지워도 테스트는
				통과했다 — 실제로는 모든 match/cancel 이 두 번 처리됐을 것이다.
			]]
			PublishAsync = function(_, topic, data)
				local payload = serialized(data, "PublishAsync 데이터")
				for _, entry in world.subscribers[topic] or {} do
					entry.handler({ Data = payload, Sent = world.scheduler.clock })
				end
			end,

			SubscribeAsync = function(_, topic, handler)
				world.subscribers[topic] = world.subscribers[topic] or {}
				local entry = { server = self, handler = handler }
				table.insert(world.subscribers[topic], entry)

				return {
					Disconnect = function()
						for index, existing in world.subscribers[topic] do
							if existing == entry then
								table.remove(world.subscribers[topic], index)
								return
							end
						end
					end,
				}
			end,
		}
	end

	if name == "TeleportService" then
		return {
			ReserveServerAsync = function(_, _placeId)
				-- 세는 값으로 만든다. math.random 으로 만들면 한 월드에서 두 번 예약할 때
				-- 드물게 같은 코드가 나와, 테스트가 이유 없이 깜빡인다.
				world.nextAccessCode += 1
				local code = ("access-%d"):format(world.nextAccessCode)
				world.reserved[code] = false -- 아직 서버가 안 생겼다
				return code, "private-" .. code
			end,

			TeleportAsync = function(_, placeId, players, options)
				local code = options and options.ReservedServerAccessCode
				local data = options and options:GetTeleportData()

				for _, player in players do
					table.insert(world.teleports, {
						player = player,
						placeId = placeId,
						accessCode = code,
						data = data,
						from = self.jobId,
					})
					world:performTeleport(self, player, code, data)
				end
			end,
		}
	end

	error(("game:GetService(\"%s\") 는 이 하네스가 모르는 서비스입니다"):format(tostring(name)), 2)
end

--==========================================================================
-- 텔레포트 — 세계가 실제로 사람을 옮긴다
--==========================================================================

--[[
	진짜 텔레포트처럼 잠깐 걸린다. 그 사이에 원래 서버에서는 PlayerRemoving 이 돌고,
	도착한 서버에서는 PlayerAdded 가 돈다 — 몰수 처리와 도착 데이터 검증이
	실제 순서대로 실행된다.
]]
function World:performTeleport(fromServer, player, accessCode, data)
	self.scheduler:delay(0.2, function()
		-- 그 사이에 나간 사람은 태우지 않는다. 진짜 TeleportAsync 도 이미 떠난 플레이어를
		-- 옮기지 못한다 — 이 검사가 없으면 하네스가 "나갔는데도 대전이 시작되는" 거짓
		-- 결과를 준다.
		if player.Parent ~= fromServer.playersService then
			return
		end

		fromServer:removePlayer(player)

		local target
		if accessCode then
			target = self.reserved[accessCode]
			if not target then
				target = self:newServer({ reserved = true, accessCode = accessCode })
				self.reserved[accessCode] = target
				target:boot()
			end
		else
			target = self:publicServer()
			if not target then
				target = self:newServer()
				target:boot()
			end
		end

		target:addPlayer(player.Name, { player = player, joinData = data })
	end)
end

--==========================================================================
-- 플레이어
--==========================================================================

function Server:addPlayer(name, opts)
	opts = opts or {}

	local player = opts.player
	if not player then
		self.world.nextUserId += 1
		player = {
			Name = name,
			DisplayName = name,
			UserId = self.world.nextUserId,
		}
	end

	-- FireClient 가 "첫 인자가 진짜 Player 인가" 를 볼 수 있게 표식을 단다.
	player._isPlayer = true

	player.Parent = self.playersService
	player._joinData = { TeleportData = opts.joinData }

	local gui = RobloxInstance.new("Folder")
	gui.Name = "PlayerGui"
	player.PlayerGui = gui

	function player:GetJoinData()
		return self._joinData
	end
	function player:WaitForChild(childName)
		if childName == "PlayerGui" then
			return self.PlayerGui
		end
		error(("Player.%s 는 이 하네스에 없습니다"):format(childName), 2)
	end

	table.insert(self.players, player)

	-- 서버의 PlayerAdded 가 먼저 돌고 클라이언트 스크립트가 그 뒤에 뜬다.
	-- 진짜 Roblox 도 이 순서라서, 서버가 먼저 쏜 메시지를 클라이언트가 놓치는
	-- 경쟁 상태가 여기서도 그대로 재현된다 (그래서 hello 재시도가 필요하다).
	self.playerAdded:Fire(player)

	if opts.withClient ~= false and self.booted then
		self:startClient(player)
	end

	return player
end

function Server:removePlayer(player)
	--[[
		**아직 Players 의 자식인 채로** PlayerRemoving 이 돈다. 진짜 Roblox 가 그렇다.
		먼저 떼어내면, 핸들러 안에서 `Players:GetPlayers()` 나 `player.Parent` 를 보는
		코드가 실제와 다른 답을 받는다 — 나가는 사람을 이미 없는 사람으로 세게 된다.
	]]
	self.playerRemoving:Fire(player)

	for index, existing in self.players do
		if existing == player then
			table.remove(self.players, index)
			break
		end
	end
	player.Parent = nil

	--[[
		떠난 사람의 클라이언트 신호를 지운다. 안 지우면 FireAllClients 가 계속
		그 사람에게 쏘고, 하네스에만 있는 유령 수신자가 남는다.

		**PlayerRemoving 이 다 돈 뒤에** 지운다. 그 핸들러들이 아직 그 사람에게
		마지막 메시지를 쏠 수 있고(몰수 안내 등), 먼저 지우면 그 호출이 신호를
		다시 만들어 결국 남는다.
	]]
	for _, remote in self.remotes:GetChildren() do
		local signals = rawget(remote, "_clientSignals")
		if signals then
			signals[player] = nil
		end
	end
end

--==========================================================================
-- VM — 서버 하나, 클라이언트 하나가 각자 자기 모듈 사본을 갖는다
--==========================================================================

--[[
	Roblox 에서 서버와 각 클라이언트는 별도 Lua 상태다. 같은 ModuleScript 라도
	각자 한 번씩 실행되고 서로의 값을 공유하지 않는다. 여기서도 캐시를 나눈다 —
	그러지 않으면 서버가 부른 Cards.load() 를 클라이언트가 건너뛰어, 진짜 게임에서는
	나는 버그가 여기서는 안 나게 된다.
]]
function Server:newVm(kind, player)
	local vm = { kind = kind, player = player, cache = {} }

	if player then
		-- 클라이언트는 자기 신원이 박힌 리모트를 본다.
		local proxies = {}
		for _, remote in self.remotes:GetChildren() do
			proxies[remote.Name] = {
				Name = remote.Name,
				OnClientEvent = assert(rawget(remote, "_clientSignalFor"))(player),
				FireServer = function(_, ...)
					assert(rawget(remote, "_serverSignal")):Fire(player, ...)
				end,
			}
		end

		vm.remotesProxy = {
			WaitForChild = function(_, name)
				local proxy = proxies[name]
				if not proxy then
					error(("Remotes 아래에 '%s' 가 없습니다"):format(name), 2)
				end
				return proxy
			end,
		}
	end

	local world = self.world
	local server = self

	local game = setmetatable({}, {
		__index = function(_, key)
			if key == "GetService" then
				return function(_, name)
					return server:service(name, vm)
				end
			elseif key == "JobId" then
				return server.jobId
			elseif key == "PlaceId" then
				return world.placeId
			elseif key == "PrivateServerId" then
				return server.privateServerId
			elseif key == "PrivateServerOwnerId" then
				return server.privateServerOwnerId
			elseif key == "Workspace" then
				return server.workspace
			end
			error(("game.%s 는 이 하네스가 모르는 항목입니다"):format(tostring(key)), 2)
		end,
	})

	vm.game = game
	vm.workspace = server.workspace

	--------------------------------------------------------------------
	-- require
	--------------------------------------------------------------------
	local requireNode
	local LOADING = newproxy(false)

	requireNode = function(target)
		if not RobloxInstance.isNode(target) then
			error("require: ModuleScript 가 아닙니다 (" .. tostring(target) .. ")", 2)
		end

		local cached = vm.cache[target]
		if cached == LOADING then
			error("require: 순환 참조 - " .. target:GetFullName(), 2)
		elseif cached ~= nil then
			return cached.value
		end

		local path = rawget(target, "_path")
		if not path then
			error("require: '" .. target:GetFullName() .. "' 는 ModuleScript 가 아닙니다", 2)
		end

		vm.cache[target] = LOADING
		local value = server:execute(target, path, vm, requireNode)
		if value == nil then
			error("require: '" .. target:GetFullName() .. "' 가 아무것도 반환하지 않았습니다", 2)
		end

		vm.cache[target] = { value = value }
		return value
	end

	vm.require = requireNode
	return vm
end

--[[
	한 파일을 실행한다. 여기서 주입하는 이름들이 곧 "이 하네스가 흉내내는 Roblox" 다.
]]
function Server:execute(node, path, vm, requireNode)
	local world = self.world

	local env = {
		script = node,
		require = requireNode,
		game = vm.game,
		workspace = vm.workspace,
		Instance = RobloxInstance,
		task = world.scheduler:library(),

		--[[
			os.time 도 가상 시계를 따라야 한다.

			게임 코드는 큐 TTL · 엔트리 갱신 · 대기 시간 표시를 전부 os.time 으로 잰다.
			그게 실제 시계를 보면 world:advance(120) 을 해도 게임 입장에서는 0초라,
			시간에 얽힌 로직이 **테스트에서 아예 실행되지 않는다** — 실제로 그 때문에
			"90초 넘게 기다리면 큐에서 증발" 하는 버그를 하네스가 못 잡았다.
		]]
		--[[
			Random. Arena 가 매치 시드를 여기서 뽑는다 — 클라이언트가 볼 수 있는 값에서
			유도하면 셔플이 예측되기 때문이다. 테스트는 값 자체를 보지 않고 "매번 다른가" 만
			따지므로, 세계 안에서 겹치지 않는 수열이면 충분하다.
		]]
		Random = {
			new = function(seed)
				local counter = seed or 0
				return {
					NextInteger = function(_, min, max)
						world.randomCount += 1
						counter = (counter * 1103515245 + world.randomCount * 12345 + 1013904223) % 2147483647
						return min + (counter % (max - min + 1))
					end,
					NextNumber = function(_, min, max)
						world.randomCount += 1
						return (min or 0) + ((max or 1) - (min or 0)) * ((world.randomCount * 37) % 1000) / 1000
					end,
				}
			end,
		},

		os = setmetatable({
			time = function()
				return VIRTUAL_EPOCH + math.floor(world.scheduler.clock)
			end,
			clock = function()
				return world.scheduler.clock
			end,
		}, { __index = os }),

		warn = function(...)
			local parts = {}
			for index = 1, select("#", ...) do
				table.insert(parts, tostring(select(index, ...)))
			end
			table.insert(world.warnings, table.concat(parts, " "))
		end,
	}

	for name, value in Datatypes do
		env[name] = value
	end

	local source = SOURCE[path] or error("소스를 캐시하지 못했습니다: " .. tostring(path))
	local chunk = assert(loadstring(source, "@" .. path))
	setfenv(chunk :: any, setmetatable(env, { __index = GLOBALS }) :: any)
	return chunk()
end

--==========================================================================
-- 부팅
--==========================================================================

--[[
	src/server 안의 Script 를 전부 실행한다. Rojo 가 ServerScriptService 에
	밀어넣은 것들이 Studio 에서 자동으로 도는 것과 같다.
]]
function Server:boot()
	if self.booted then
		return self
	end
	self.booted = true

	local vm = self:newVm("server")
	self.serverVm = vm

	for _, child in self.serverScripts:GetChildren() do
		if rawget(child, "ClassName") == "Script" then
			local path = rawget(child, "_path")
			self:execute(child, path, vm, vm.require)
		end
	end

	return self
end

--[[
	한 사람 몫의 클라이언트를 띄운다. src/client 의 LocalScript 를 실행한다.
]]
function Server:startClient(player)
	local vm = self:newVm("client", player)
	player._vm = vm

	for _, child in self.clientScripts:GetChildren() do
		if rawget(child, "ClassName") == "LocalScript" then
			local path = rawget(child, "_path")
			self:execute(child, path, vm, vm.require)
		end
	end

	return vm
end

--==========================================================================
-- 화면 들여다보기 — 사람이 Studio 에서 눈으로 하는 일
--==========================================================================

local Screen = {}
Roblox.Screen = Screen

-- 테스트가 Vector2 같은 값을 만들 수 있게 열어둔다 (창 크기 지정 등).
Roblox.Datatypes = Datatypes

local function walk(node, visit)
	visit(node)
	for _, child in node:GetChildren() do
		walk(child, visit)
	end
end

--[[
	보이는 텍스트를 전부 모은다. 부모가 꺼져 있으면(Visible/Enabled=false) 뺀다 —
	"화면에 떠 있다" 를 판정해야 하므로 트리에 존재하는 것만으로는 부족하다.
]]
function Screen.visibleTexts(root)
	local out = {}

	local function recurse(node, shown)
		local className = rawget(node, "ClassName")
		local visible = shown

		if className == "ScreenGui" then
			visible = shown and node.Enabled ~= false
		end

		if node:IsA("GuiObject") then
			visible = visible and node.Visible ~= false
		end

		if visible and (className == "TextLabel" or className == "TextButton") then
			local text = node.Text
			if text and text ~= "" then
				table.insert(out, text)
			end
		end

		for _, child in node:GetChildren() do
			recurse(child, visible)
		end
	end

	recurse(root, true)
	return out
end

function Screen.hasText(root, needle)
	for _, text in Screen.visibleTexts(root) do
		if text:find(needle, 1, true) then
			return true
		end
	end
	return false
end

--[[
	보이는 버튼을 글자로 찾는다. 사람이 화면에서 버튼을 눈으로 찾는 것과 같다.
]]
function Screen.findButton(root, label)
	local found = nil

	local function recurse(node, shown)
		local className = rawget(node, "ClassName")
		local visible = shown

		if className == "ScreenGui" then
			visible = shown and node.Enabled ~= false
		end
		if node:IsA("GuiObject") then
			visible = visible and node.Visible ~= false
		end

		if visible and className == "TextButton" and node.Text == label and not found then
			found = node
		end

		for _, child in node:GetChildren() do
			recurse(child, visible)
		end
	end

	recurse(root, true)
	return found
end

--[[
	이름으로 자손을 찾는다. 화면 구조를 그대로 짚을 때 쓴다.
]]
function Screen.find(root, name)
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = Screen.find(child, name)
		if found then
			return found
		end
	end
	return nil
end

--[[
	버튼을 누른다. 꺼진 버튼(Active=false)은 누를 수 없다 —
	Widgets.setEnabled 가 끈 버튼을 테스트가 눌러버리면 "화면에선 못 누르는데
	테스트는 통과" 가 된다.
]]
--[[
	이름이 prefix 로 시작하는 **보이는** 노드 하나. 카드처럼 이름이 id 로 끝나는 것을
	짚을 때 쓴다 (Card_CRE_HAWK 를 "Card_" 로 찾거나 이름 전체로 찾거나 둘 다 된다).

	안 보이는 것은 건너뛴다 — 꺼진 화면 안의 노드를 눌러놓고 "됐다" 고 하면 안 된다.
]]
function Screen.findNamed(root, prefix)
	local found

	local function recurse(node, shown)
		if found then
			return
		end

		local visible = shown
		if rawget(node, "ClassName") == "ScreenGui" then
			visible = shown and node.Enabled ~= false
		end
		if node:IsA("GuiObject") then
			visible = visible and node.Visible ~= false
		end

		if visible and node.Name:sub(1, #prefix) == prefix then
			found = node
			return
		end

		for _, child in node:GetChildren() do
			recurse(child, visible)
		end
	end

	recurse(root, true)
	return found
end

--[[
	이름이 prefix 로 시작하는 보이는 노드 개수. 카드처럼 이름이 id 로 끝나는 것들을 센다.
]]
function Screen.countNamed(root, prefix)
	local count = 0

	local function recurse(node, shown)
		local visible = shown
		if rawget(node, "ClassName") == "ScreenGui" then
			visible = shown and node.Enabled ~= false
		end
		if node:IsA("GuiObject") then
			visible = visible and node.Visible ~= false
		end

		if visible and node.Name:sub(1, #prefix) == prefix then
			count += 1
		end
		for _, child in node:GetChildren() do
			recurse(child, visible)
		end
	end

	recurse(root, true)
	return count
end

function Screen.click(button)
	if button.Active == false then
		error(("'%s' 버튼은 지금 꺼져 있습니다"):format(tostring(button.Text)), 2)
	end
	assert(rawget(button, "_signals")).Activated:Fire()
end

--[[
	오른쪽 버튼으로 누른다. 카드 상세 보기처럼 "누르는 것과 들여다보는 것" 이
	다른 조작일 때 쓴다.
]]
function Screen.rightClick(button)
	if button.Active == false then
		error(("'%s' 버튼은 지금 꺼져 있습니다"):format(tostring(button.Text)), 2)
	end
	assert(rawget(button, "_signals")).MouseButton2Click:Fire()
end

function Screen.dump(root)
	local lines = {}
	walk(root, function(node)
		local className = rawget(node, "ClassName")
		if className == "TextLabel" or className == "TextButton" then
			table.insert(lines, ("%s: %s"):format(node:GetFullName(), tostring(node.Text)))
		end
	end)
	return table.concat(lines, "\n")
end

return Roblox
