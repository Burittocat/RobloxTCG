--[[
	문서가 코드를 따라오는지 검사한다.

	    lune run tests/docs.luau

	왜 필요한가:
	문서가 틀리는 방식은 대개 하나다 — 코드에서 파일을 옮기거나 지웠는데 문서는
	옛 경로를 계속 가리킨다. 읽는 사람은 그 경로를 열어보고 나서야 안다.
	이건 사람이 판단할 일이 아니라 기계가 확인할 일이다.

	보는 것 셋:

	  1. 문서 안의 저장소 경로(`src/...` 같은 백틱 안의 것)가 실제로 있는가
	  2. 문서끼리의 링크와 루트 README 의 링크가 실제 파일을 가리키는가
	  3. docs/ 안에 목차(docs/README.md)에서 링크되지 않은 고아 문서가 있는가

	"코드는 바뀌었는데 문서는 안 바뀌었다" 는 여기서 안 본다. 그건 정답이 없어서
	막으면 안 되는 종류라 커밋 훅이 경고만 한다 — scripts/docs-sync.sh.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local GREEN = "\27[32m"
local RED = "\27[31m"
local DIM = "\27[2m"
local RESET = "\27[0m"

-- 백틱 안에서 "저장소 경로" 로 칠 접두사. 이 앞에 걸린 것만 존재 여부를 따진다.
-- (`Rules/GameState.luau` 처럼 줄인 이름은 문서 안에서 흔해서 검사 대상이 아니다)
local PATH_PREFIXES = { "src/", "tests/", "scripts/", "docs/", ".github/", ".githooks/" }

local INDEX = "docs/README.md"

local problems = {}
local checkedPaths = 0
local checkedLinks = 0

local function report(file, line, message)
	table.insert(problems, { file = file, line = line, message = message })
end

local function exists(path)
	return fs.isFile(path) or fs.isDir(path)
end

local function isRepoPath(token)
	for _, prefix in PATH_PREFIXES do
		if token:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- 문서 한 줄에서 백틱 안의 토큰을 뽑아 저장소 경로만 확인한다.
local function checkBacktickPaths(file, lineNumber, line)
	for span in line:gmatch("`([^`]+)`") do
		for token in span:gmatch("%S+") do
			-- 문장 부호가 붙어 오는 경우가 많다: `scripts/ci.sh`, / `docs/rules.md`)
			token = token:gsub("[,%)%(%]:;]+$", "")

			-- 와일드카드나 자리표시자는 실제 경로가 아니다
			if isRepoPath(token) and not token:find("[%*<>]") then
				checkedPaths += 1
				if not exists(token) then
					report(file, lineNumber, ("`%s` 가 없다"):format(token))
				end
			end
		end
	end
end

-- 마크다운 링크. 같은 폴더 기준의 상대 경로로 푼다.
local function checkLinks(file, lineNumber, line, baseDir)
	for target in line:gmatch("%]%(([^%)]+)%)") do
		local isExternal = target:find("^https?://") or target:sub(1, 1) == "#"
		if not isExternal then
			-- 앵커(#…)는 떼고 파일만 본다
			local path = target:gsub("#.*$", "")
			if path ~= "" then
				checkedLinks += 1
				local resolved = if baseDir == "" then path else baseDir .. "/" .. path
				if not exists(resolved) then
					report(file, lineNumber, ("링크 %s 가 가리키는 곳이 없다"):format(target))
				end
			end
		end
	end
end

local function checkDoc(file, baseDir)
	local lineNumber = 0
	local inComment = false

	for line in (fs.readFile(file) .. "\n"):gmatch("([^\n]*)\n") do
		lineNumber += 1

		-- HTML 주석 안은 건너뛴다. 아직 없는 파일을 가리키는 "나중에 풀 자리" 가
		-- 거기 들어 있다 (README 의 스크린샷 자리가 그렇다).
		if line:find("<!%-%-") then
			inComment = true
		end

		if not inComment then
			checkBacktickPaths(file, lineNumber, line)
			checkLinks(file, lineNumber, line, baseDir)
		end

		if line:find("%-%->") then
			inComment = false
		end
	end
end

checkDoc("README.md", "")

local docFiles = {}
for _, entry in fs.readDir("docs") do
	local path = "docs/" .. entry
	if fs.isFile(path) and entry:match("%.md$") then
		table.insert(docFiles, entry)
		checkDoc(path, "docs")
	end
end

-- 목차에 없는 문서는 아무도 못 찾는다. 있으나 마나 한 문서가 되는 것을 막는다.
local index = fs.readFile(INDEX)
for _, entry in docFiles do
	if entry ~= "README.md" and not index:find(entry, 1, true) then
		report(INDEX, 0, ("docs/%s 가 목차에 없다"):format(entry))
	end
end

print("")
if #problems == 0 then
	print(
		("%s문서 검사 통과%s %s(문서 %d개 · 경로 %d개 · 링크 %d개)%s"):format(
			GREEN,
			RESET,
			DIM,
			#docFiles + 1,
			checkedPaths,
			checkedLinks,
			RESET
		)
	)
	process.exit(0)
end

for _, problem in problems do
	print(("%s✗ %s:%d%s %s"):format(RED, problem.file, problem.line, RESET, problem.message))
end
print(("\n%s문서 %d곳이 어긋나 있다%s"):format(RED, #problems, RESET))
process.exit(1)
