--[[
	전체 .luau 파일 문법 검사.

	    lune run tests/check.luau

	왜 따로 필요한가:
	tests/run.luau 는 `src/shared` 만 로드한다. 서버/클라이언트 코드는 Roblox API 를
	쓰므로 Lune 안에서 실행할 수 없기 때문이다. 그래서 src/client/UI/Battle.luau 의
	오타는 Studio 를 켜서 그 화면이 뜨기 전까지 아무도 모른다 — 이 검사가 그 구멍을 메운다.

	하는 일은 컴파일뿐이다. 문법 오류는 전부 걸리고, 런타임 오류(nil 인덱싱 등)는 안 걸린다.
	그래도 "Studio 켰더니 스크립트가 아예 안 뜸" 은 여기서 끝난다.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local GREEN = "\27[32m"
local RED = "\27[31m"
local DIM = "\27[2m"
local RESET = "\27[0m"

-- 검사 대상. 폴더면 하위 전체, 파일이면 그 파일.
local TARGETS = { "src", "tests", "play.luau" }

local checked = 0
local failures = {}

local function checkFile(path)
	checked += 1

	local ok, err = pcall(function()
		luau.compile(fs.readFile(path))
	end)

	if not ok then
		-- 컴파일 오류에는 Lune 내부 스택이 딸려 온다. 쓸모 있는 첫 줄만 남긴다.
		local message = tostring(err):split("\n")[1] or tostring(err)
		table.insert(failures, { path = path, err = message })
	end
end

local function walk(dir)
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path)
		elseif entry:match("%.luau?$") then
			checkFile(path)
		end
	end
end

for _, target in TARGETS do
	if fs.isDir(target) then
		walk(target)
	elseif fs.isFile(target) then
		checkFile(target)
	else
		print(("%s경고: '%s' 를 찾을 수 없습니다%s"):format(RED, target, RESET))
	end
end

print("")
if #failures == 0 then
	print(("%s%d개 파일 문법 검사 통과%s"):format(GREEN, checked, RESET))
	process.exit(0)
end

for _, failure in failures do
	print(("%s✗ %s%s"):format(RED, failure.path, RESET))
	print(("  %s%s%s"):format(DIM, failure.err, RESET))
end
print(("\n%s%d개 파일 중 %d개 실패%s"):format(RED, checked, #failures, RESET))
process.exit(1)
