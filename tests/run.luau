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

local loader = RobloxEnv.newLoader()
local Shared = loader.mount("src/shared", "Shared")
local Client = loader.mount("src/client", "Client")

local Rules = loader.require(Shared.Rules)
local Cards = loader.require(Shared.Cards)
local Decks = loader.require(Shared.Decks)
local AI = loader.require(Shared.AI)
local Net = loader.require(Shared.Net)
local Matchmaking = loader.require(Shared.Matchmaking)

Cards.load()
print(("카드 %d 장 등록됨\n"):format(Rules.Registry.count()))

--[[
	클라이언트 모듈이 룰을 찾아가는 길만 흉내낸다.

		game:GetService("ReplicatedStorage"):WaitForChild("Shared")

	Studio 에서는 Rojo 가 src/shared 를 거기에 복제한다. 여기서 돌려주는 것은 위에서
	이미 로드한 **바로 그 트리**다 — 사본을 주면 카드 등록이 갈려서, 클라이언트 쪽
	Registry.mustGet 이 "등록되지 않은 카드" 로 죽는다.

	화면(UI)까지 흉내내지는 않는다. 그건 tests/smoke.luau 가 진짜 트리 위에서 한다.
	여기서 돌리는 것은 클릭을 판정으로 옮기는 Controller 다.
]]
loader.globals.game = {
	GetService = function(_, name)
		if name ~= "ReplicatedStorage" then
			error(("이 로더는 GetService('%s') 를 흉내내지 않습니다"):format(tostring(name)), 2)
		end
		return {
			WaitForChild = function(_, childName)
				if childName == "Shared" then
					return Shared
				end
				error(("ReplicatedStorage 아래에 '%s' 가 없습니다"):format(tostring(childName)), 2)
			end,
		}
	end,
}

local Controller = loader.require(Client.Controller)


local SPECS = {
	{ name = "setup", run = require("./specs/setup") },
	{ name = "mulligan", run = require("./specs/mulligan") },
	{ name = "deck", run = require("./specs/deck") },
	{ name = "cost", run = require("./specs/cost") },
	{ name = "phases", run = require("./specs/phases") },
	{ name = "keywords", run = require("./specs/keywords") },
	{ name = "combat", run = require("./specs/combat") },
	{ name = "stack", run = require("./specs/stack") },
	{ name = "winloss", run = require("./specs/winloss") },
	{ name = "ai", run = require("./specs/ai") },
	{ name = "net", run = require("./specs/net") },
	{ name = "matchmaking", run = require("./specs/matchmaking") },
	{ name = "controller", run = require("./specs/controller") },
}

local t = Test.new()
local ctx = {
	Rules = Rules,
	Cards = Cards,
	Decks = Decks,
	AI = AI,
	Net = Net,
	Matchmaking = Matchmaking,
	Controller = Controller,
	Fixture = Fixture,
}

for _, spec in SPECS do
	print(("[%s]"):format(spec.name))
	spec.run(t, ctx)
	print("")
end

process.exit(t:report() and 0 or 1)
