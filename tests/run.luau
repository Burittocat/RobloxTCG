--[[
	룰 엔진 테스트 러너.

	    lune run tests/run

	Studio 없이 src/shared 를 그대로 로드해 돌린다. Rojo 가 Studio 로 밀어넣는 파일과
	여기서 검증하는 파일이 완전히 같으므로, 통과 = 게임 안에서도 같은 룰이 돈다.
]]

local process = require("@lune/process")

local RobloxEnv = require("./lib/RobloxEnv")
local Test = require("./lib/Test")
local Fixture = require("./lib/Fixture")

local env = RobloxEnv.mount("src/shared", "Shared")
local Rules = env.require(env.root.Rules)
local Cards = env.require(env.root.Cards)

Cards.load()
print(("카드 %d 장 등록됨\n"):format(Rules.Registry.count()))

local SPECS = {
	{ name = "setup", run = require("./specs/setup") },
	{ name = "cost", run = require("./specs/cost") },
	{ name = "phases", run = require("./specs/phases") },
	{ name = "keywords", run = require("./specs/keywords") },
	{ name = "combat", run = require("./specs/combat") },
	{ name = "stack", run = require("./specs/stack") },
	{ name = "winloss", run = require("./specs/winloss") },
}

local t = Test.new()
local ctx = { Rules = Rules, Cards = Cards, Fixture = Fixture }

for _, spec in SPECS do
	print(("[%s]"):format(spec.name))
	spec.run(t, ctx)
	print("")
end

process.exit(t:report() and 0 or 1)
