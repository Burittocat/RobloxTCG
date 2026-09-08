--!nolint DeprecatedApi
-- getfenv / setfenv 는 deprecated 로 표시돼 있지만, 이 파일의 존재 이유가
-- "모듈에 script 와 require 를 주입한 환경에서 실행하는 것" 이라 대체 수단이 없다.
-- (debug.info 는 환경을 읽을 뿐 바꾸지 못한다)

--[[
	Lune에서 Roblox ModuleScript 트리를 흉내내는 로더.

	src/shared 같은 폴더를 읽어 Instance 비슷한 노드 트리를 만들고, 각 모듈을
	`script` / `require` 가 주입된 환경에서 loadstring + setfenv 로 실행한다.

	덕분에 룰 엔진 코드는 Roblox 관용구(`require(script.Parent.Enums)`)를 그대로 쓰면서
	Studio 를 켜지 않고도 테스트할 수 있다. 변환 단계가 없으므로 테스트가 통과한 파일이
	곧 Rojo 가 Studio 로 밀어넣는 파일이다.
]]

local fs = require("@lune/fs")

local RobloxEnv = {}

--==========================================================================
-- 노드 (Instance 흉내)
--==========================================================================

local Node = {}

local function kids(node)
	return rawget(node, "_children")
end

-- Name/Parent/ClassName/_children/_path 는 rawset 되어 있으므로 __index 를 타지 않는다.
-- 그 외의 이름 접근은 전부 자식 조회로 넘긴다 → `script.Parent.Enums` 가 동작.
Node.__index = function(self, key)
	local method = rawget(Node, key)
	if method ~= nil then
		return method
	end
	return kids(self)[key]
end

Node.__tostring = function(self)
	return rawget(self, "Name")
end

function Node:FindFirstChild(name)
	return kids(self)[name]
end

function Node:WaitForChild(name)
	local child = kids(self)[name]
	if not child then
		error(("WaitForChild: '%s' 아래에 '%s' 가 없습니다"):format(tostring(self), name), 2)
	end
	return child
end

function Node:GetChildren()
	local out = {}
	for _, child in kids(self) do
		table.insert(out, child)
	end
	table.sort(out, function(a, b)
		return rawget(a, "Name") < rawget(b, "Name")
	end)
	return out
end

function Node:IsA(className)
	return rawget(self, "ClassName") == className
end

function Node:GetFullName()
	local parts = {}
	local cur = self
	while cur do
		table.insert(parts, 1, rawget(cur, "Name"))
		cur = rawget(cur, "Parent")
	end
	return table.concat(parts, ".")
end

local function newNode(name, parent, modulePath)
	local node = setmetatable({
		Name = name,
		Parent = parent,
		ClassName = modulePath and "ModuleScript" or "Folder",
		_children = {},
		_path = modulePath,
	}, Node)

	if parent then
		kids(parent)[name] = node
	end

	return node
end

--==========================================================================
-- 디렉터리 → 노드 트리
--==========================================================================

local function findInit(dirPath)
	for _, candidate in { "init.luau", "init.lua" } do
		local p = dirPath .. "/" .. candidate
		if fs.isFile(p) then
			return p
		end
	end
	return nil
end

-- Rojo 파일명 규칙(`Foo.server.luau` 등)에서 인스턴스 이름만 뽑아낸다.
local function instanceNameOf(fileName)
	local base = (fileName:gsub("%.luau?$", ""))
	base = (base:gsub("%.server$", ""))
	base = (base:gsub("%.client$", ""))
	return base
end

local function buildTree(dirPath, name, parent)
	local node = newNode(name, parent, findInit(dirPath))

	for _, entry in fs.readDir(dirPath) do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			buildTree(full, entry, node)
		elseif entry:match("%.luau?$") and not entry:match("^init%.luau?$") then
			newNode(instanceNameOf(entry), node, full)
		end
	end

	return node
end

--==========================================================================
-- require
--==========================================================================

local LOADING = newproxy(false)

-- Lune 의 빌트인(table.freeze 등)은 _G 가 아니라 실제 전역 환경에 있다.
local GLOBALS = getfenv(0)

local function makeRequire(cache, globals)
	local requireNode

	requireNode = function(target)
		if type(target) ~= "table" or getmetatable(target) ~= Node then
			error("require: ModuleScript 노드가 아닙니다 (" .. tostring(target) .. ")", 2)
		end

		local cached = cache[target]
		if cached == LOADING then
			error("require: 순환 참조 - " .. target:GetFullName(), 2)
		elseif cached ~= nil then
			return cached.value
		end

		local path = rawget(target, "_path")
		if not path then
			error("require: '" .. target:GetFullName() .. "' 는 ModuleScript 가 아닙니다", 2)
		end

		cache[target] = LOADING

		local chunk = assert(loadstring(fs.readFile(path), "@" .. path))
		-- globals 는 로더가 넣어주는 것들(game 스텁 등). 없으면 Lune 빌트인만 보인다.
		local env = setmetatable({ script = target, require = requireNode }, {
			__index = function(_, key)
				local injected = globals[key]
				if injected ~= nil then
					return injected
				end
				return GLOBALS[key]
			end,
		})
		setfenv(chunk :: any, env :: any)

		local value = chunk()
		if value == nil then
			error("require: '" .. target:GetFullName() .. "' 가 아무것도 반환하지 않았습니다", 2)
		end

		cache[target] = { value = value }
		return value
	end

	return requireNode
end

--==========================================================================
-- 공개 API
--==========================================================================

--[[
	폴더를 로드해 { root = <노드>, require = <함수> } 를 돌려준다.

		local env = RobloxEnv.mount("src/shared", "Shared")
		local Rules = env.require(env.root.Rules)
]]
--[[
	폴더 여러 개를 **한 캐시로** 로드하는 로더.

		local loader = RobloxEnv.newLoader()
		local shared = loader.mount("src/shared", "Shared")
		local client = loader.mount("src/client", "Client")

	캐시를 나누면 안 된다. src/client 가 자기 require 로 Rules 를 다시 로드하면
	카드 등록(Cards.load)이 한쪽 사본에만 남아, 클라이언트 쪽 Registry.mustGet 이
	"등록되지 않은 카드" 로 죽는다. Roblox 에서는 ReplicatedStorage 의 같은
	ModuleScript 를 공유하므로, 여기서도 한 벌만 있어야 실제와 같다.

	loader.globals 는 모듈에 주입할 전역이다. 나중에 채워도 된다 — 모듈은
	require 하는 순간에 읽는다. 클라이언트 코드에 `game` 스텁을 넣는 용도다.
]]
function RobloxEnv.newLoader(globals)
	local resolved = globals or {}
	local loader = { globals = resolved }

	loader.require = makeRequire({}, resolved)

	function loader.mount(dirPath, rootName)
		assert(fs.isDir(dirPath), "폴더를 찾을 수 없습니다: " .. dirPath)
		return buildTree(dirPath, rootName or "Shared", nil)
	end

	return loader
end

-- 폴더 하나만 로드하는 지름길. (play.luau 처럼 룰만 쓰는 곳)
function RobloxEnv.mount(dirPath, rootName)
	local loader = RobloxEnv.newLoader()

	return {
		root = loader.mount(dirPath, rootName or "Shared"),
		require = loader.require,
	}
end

return RobloxEnv
