--[[
	룰 엔진 테스트 러너.

	    lune run tests/run

	Studio 없이 src/shared 를 그대로 로드해 돌린다. Rojo 가 Studio 로 밀어넣는 파일과
	여기서 검증하는 파일이 완전히 같으므로, 통과 = 게임 안에서도 같은 룰이 돈다.
]]

local process = require("@lune/process")

local RobloxEnv = require("./lib/RobloxEnv")
local Test = require("./lib/Test")
local RobloxInstance = require("./lib/Roblox/Instance")
local Fixture = require("./lib/Fixture")

local loader = RobloxEnv.newLoader()
local Shared = loader.mount("src/shared", "Shared")
local Client = loader.mount("src/client", "Client")

local Rules = loader.require(Shared.Rules)
local Cards = loader.require(Shared.Cards)
local Decks = loader.require(Shared.Decks)
local Campaign = loader.require(Shared.Campaign)
local Collection = loader.require(Shared.Collection)
local Cosmetics = loader.require(Shared.Cosmetics)
local Rank = loader.require(Shared.Rank)
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

--[[
	때리는 장면의 시간표. 화면 모듈 중 **유일하게** 여기서 로드할 수 있다 —
	순수 계산이라 Color3 도 Instance 도 건드리지 않기 때문이다. 나머지 UI 는
	tests/smoke.luau 가 진짜 트리 위에서 본다.
]]
local CombatTiming = loader.require(Client.UI.CombatTiming)

--[[
	효과음. 화면 위젯을 만들지 않고 Sound 노드만 다루므로 여기서 볼 수 있다 —
	**하네스의 가짜 Instance** 를 전역으로 넣어준다. 소리가 났는지는 그 가짜가
	기록하므로(RobloxInstance.takeSounds), 귀 없이 "언제 울렸나" 를 셀 수 있다.
]]
loader.globals.Instance = RobloxInstance
local Sfx = loader.require(Client.UI.Sfx)


local SPECS = {
	{ name = "setup", run = require("./specs/setup") },
	{ name = "mulligan", run = require("./specs/mulligan") },
	{ name = "deck", run = require("./specs/deck") },
	{ name = "campaign", run = require("./specs/campaign") },
	{ name = "collection", run = require("./specs/collection") },
	{ name = "cosmetics", run = require("./specs/cosmetics") },
	{ name = "rank", run = require("./specs/rank") },
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
	{ name = "strike", run = require("./specs/strike") },
	{ name = "sfx", run = require("./specs/sfx") },
}

local t = Test.new()
local ctx = {
	Rules = Rules,
	Cards = Cards,
	Decks = Decks,
	Campaign = Campaign,
	Collection = Collection,
	Cosmetics = Cosmetics,
	Rank = Rank,
	AI = AI,
	Net = Net,
	Matchmaking = Matchmaking,
	Controller = Controller,
	CombatTiming = CombatTiming,
	Sfx = Sfx,
	Instance = RobloxInstance,
	takeSounds = RobloxInstance.takeSounds,
	Fixture = Fixture,
}

for _, spec in SPECS do
	print(("[%s]"):format(spec.name))
	spec.run(t, ctx)
	print("")
end

process.exit(t:report() and 0 or 1)
