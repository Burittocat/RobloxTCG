--[[
	PvP 한 판이 끝났을 때 이긴 사람에게 골드를 준다.

	판이 열리는 곳이 둘이라 여기에 하나로 모았다.
	  · 게시된 게임 — 예약 서버의 Arena
	  · Studio 같은 서버 매칭 — 로비의 startLocalMatch
	두 곳이 각자 쓰면 한쪽만 고쳐지는 날이 온다 (덱 검증을 한 곳에 둔 것과 같은 이유).

	얼마를 주나 · 오늘 몇 판째인가 · 너무 짧은 판인가는 Campaign.applyPvpWin 이 정한다.
	여기는 그걸 저장소에 적고 결과를 이긴 사람 화면에 알리는 것뿐이다.

	**진 사람에게는 아무것도 안 한다.** 지는 쪽에도 조금 주면 "들어가서 바로 지기" 가
	가장 빠른 수급 경로가 된다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Campaign = require(Shared.Campaign)

local PvpReward = {}

function PvpReward.pay(campaignStore, runner)
	local state = runner.state
	local winnerId = state and state.winnerId
	local seat = winnerId and runner.seats[winnerId]
	local player = seat and seat.player

	-- 이긴 쪽이 이미 나갔으면(또는 AI 좌석이면) 줄 사람이 없다.
	if not player then
		return
	end

	local day = Campaign.dayOf(os.time())
	local ok, gained, reason = campaignStore:update(player, function(progress)
		return Campaign.applyPvpWin(progress, day, state.turn)
	end)

	if not ok then
		runner:noticeSeat(winnerId, ("승리 보상을 저장하지 못했습니다: %s"):format(tostring(reason)), "error")
		return
	end

	if gained > 0 then
		local progress = campaignStore:get(player)
		runner:noticeSeat(
			winnerId,
			("승리 보상 — 골드 %d (오늘 %d / %d판)"):format(
				gained,
				Campaign.pvpWinsToday(progress, day),
				Campaign.PvpReward.perDay
			),
			"info"
		)
	elseif reason then
		runner:noticeSeat(winnerId, reason, "info")
	end
end

return PvpReward
