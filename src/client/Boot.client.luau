--[[
	클라이언트 부팅.

	아직 UI 가 없다. 룰 모듈이 클라이언트에서도 로드되는지만 확인한다.
	(클라이언트가 같은 룰 코드를 갖고 있어야 버튼 활성/비활성 판정을 서버와
	 똑같은 함수로 할 수 있다 — Rules.canPlayCard / Combat.legalAttackTargets)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)
local Cards = require(Shared.Cards)

Cards.load()
print(("[TCG] 클라이언트 룰 로드 완료 (카드 %d장)"):format(Rules.Registry.count()))
