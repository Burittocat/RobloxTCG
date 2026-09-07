--[[
	서버 부팅.

	같은 플레이스가 두 가지 역할을 한다.

	  공개 서버  = 로비. 시작 화면과 빠른 대전 큐. 카드는 여기서 굴리지 않는다
	  예약 서버  = 대전 서버. 매칭된 두 사람만 들어오고 한 판만 돈다

	플레이스를 둘로 나누지 않은 이유: 나누면 카드 DB·룰 엔진·UI 를 두 곳에 배포해야 하고,
	둘의 버전이 어긋나는 순간을 막을 방법이 없다. 예약 서버는 같은 플레이스를
	ReserveServerAsync 로 잡은 것이라 언제나 같은 코드가 돈다.

	  game.PrivateServerId ~= ""  → 비공개 서버
	  game.PrivateServerOwnerId == 0 → 그중 "예약 서버"(사람이 산 프라이빗 서버가 아니라
	                                   코드로 잡은 것)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)
local Cards = require(Shared.Cards)
local Net = require(Shared.Net)

local Host = require(script.Parent.Host)
local Lobby = require(script.Parent.Lobby)
local Arena = require(script.Parent.Arena)

Cards.load()
print(("[TCG] 카드 %d 장 등록 완료"):format(Rules.Registry.count()))

-- 카드 게임이라 캐릭터가 필요 없다. 스폰되면 카메라와 UI 만 방해한다.
Players.CharacterAutoLoads = false

local remotes = Net.remotes()
local host = Host.new(remotes)

local isReservedServer = (game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0)

if isReservedServer then
	Arena.new(remotes, host)
	print("[TCG] 대전 서버 준비 완료 — 매칭된 두 사람을 기다립니다")
else
	Lobby.new(remotes, host)
	print("[TCG] 로비 서버 준비 완료 — 빠른 대전 큐가 열렸습니다")
end
