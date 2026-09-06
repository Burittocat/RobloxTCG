--[[
	서버 부팅.

	지금은 카드 DB 를 등록하고 룰 엔진이 실제로 도는지 확인하는 것까지만 한다.
	매칭 / 매치 러너 / RemoteEvent 배선은 다음 단계.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)
local Cards = require(Shared.Cards)

Cards.load()
print(("[TCG] 카드 %d 장 등록 완료"):format(Rules.Registry.count()))

--==========================================================================
-- 연기 테스트: 엔진이 Studio 안에서도 도는지 확인
--==========================================================================

local function smokeTest()
	local deck = {}
	for _ = 1, 30 do
		table.insert(deck, "COST_BASIC")
	end

	local state = Rules.newMatch({
		seed = 1234,
		startingPlayerId = 1,
		strictDeck = false,
		players = {
			{ name = "P1", deck = table.clone(deck) },
			{ name = "P2", deck = table.clone(deck) },
		},
	})

	print(("[TCG] 턴 %d / %s / 선공 P%d"):format(
		state.turn,
		Rules.Enums.PhaseDisplay[state.phase],
		state.activePlayerId
	))
	print(("[TCG] 라이프 %d vs %d, 손패 %d장 vs %d장"):format(
		state.players[1].life,
		state.players[2].life,
		#state.players[1].hand,
		#state.players[2].hand
	))
end

local ok, err = pcall(smokeTest)
if not ok then
	warn("[TCG] 연기 테스트 실패: " .. tostring(err))
else
	print("[TCG] 연기 테스트 통과 — 룰 엔진 정상")
end
