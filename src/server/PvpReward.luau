--[[
	PvP 한 판이 끝났을 때 — 두 사람의 랭크를 적고, 이긴 사람에게 골드를 준다.

	판이 열리는 곳이 둘이라 여기에 하나로 모았다.
	  · 게시된 게임 — 예약 서버의 Arena
	  · Studio 같은 서버 매칭 — 로비의 startLocalMatch
	두 곳이 각자 쓰면 한쪽만 고쳐지는 날이 온다 (덱 검증을 한 곳에 둔 것과 같은 이유).

	골드:  얼마를 주나 · 오늘 몇 판째인가 · 너무 짧은 판인가는 Campaign.applyPvpWin 이 정한다.
	       **진 사람에게는 주지 않는다.** 지는 쪽에도 조금 주면 "들어가서 바로 지기" 가
	       가장 빠른 수급 경로가 된다.
	랭크:  랭크 점수와 MMR 은 Rank.applyResult 가 정한다. **진 사람에게도 적는다** — 판을
	       떠난 사람도(좌석의 userId 로). 안 그러면 질 것 같을 때 나가는 것이 이득이 된다.

	알림은 **좌석마다 한 번**에 묶어 보낸다. 전투 화면의 알림 칸은 하나라(Battle:showToast)
	따로 보내면 뒤에 온 골드 알림이 랭크 알림을 덮어서, 이긴 사람은 랭크가 얼마나 올랐는지
	못 본다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Campaign = require(Shared.Campaign)
local Rank = require(Shared.Rank)

local PvpReward = {}

--[[
	두 좌석의 랭크를 적는다. -> { [좌석] = { text, kind } }
	승자가 없는 판(무승부 · 열리다 만 판)은 적지 않는다.

	변화량은 **판이 시작될 때의 MMR** 로 계산한다(좌석의 mmr). 끝난 뒤에 다시 읽으면 먼저
	적힌 쪽의 새 값으로 상대를 계산하게 되어 두 사람의 변화량이 어긋난다.
]]
function PvpReward.rank(campaignStore, runner, leaderboard)
	local notes = {}
	local state = runner.state
	local winnerId = state and state.winnerId
	if not winnerId then
		return notes
	end

	for seatId = 1, 2 do
		local seat = runner.seats[seatId]
		local other = runner.seats[if seatId == 1 then 2 else 1]

		if seat and seat.userId and other then
			local who = seat.player or { UserId = seat.userId, Name = seat.userName or tostring(seat.userId) }
			local won = (seatId == winnerId)
			local myMmr = seat.mmr or Rank.Mmr.initial
			local theirMmr = other.mmr or Rank.Mmr.initial

			local ok, summary = campaignStore:change(who, function(progress)
				return Rank.applyResult(progress, won, myMmr, theirMmr, state.turn)
			end)

			if not ok then
				notes[seatId] = { text = ("랭크를 저장하지 못했습니다: %s"):format(tostring(summary)), kind = "error" }
			elseif summary then
				notes[seatId] = { text = Rank.describe(summary), kind = "info" }
				-- 순위표는 정렬용 사본이다. 실패해도 판 결과는 그대로 둔다(LeaderboardStore 머리말).
				if leaderboard and summary.points ~= 0 then
					leaderboard:record(seat.userId, summary.after)
				end
			end
		end
	end

	return notes
end

--[[
	이긴 사람의 골드. -> 좌석, { text, kind }  |  nil
]]
function PvpReward.gold(campaignStore, runner)
	local state = runner.state
	local winnerId = state and state.winnerId
	local seat = winnerId and runner.seats[winnerId]
	local player = seat and seat.player

	-- 이긴 쪽이 이미 나갔으면(또는 AI 좌석이면) 줄 사람이 없다.
	if not player then
		return nil
	end

	local day = Campaign.dayOf(os.time())
	local ok, gained, reason = campaignStore:update(player, function(progress)
		return Campaign.applyPvpWin(progress, day, state.turn)
	end)

	if not ok then
		return winnerId, { text = ("승리 보상을 저장하지 못했습니다: %s"):format(tostring(reason)), kind = "error" }
	end

	if gained > 0 then
		local progress = campaignStore:get(player)
		return winnerId,
			{
				text = ("골드 %d (오늘 %d / %d판)"):format(
					gained,
					Campaign.pvpWinsToday(progress, day),
					Campaign.PvpReward.perDay
				),
				kind = "info",
			}
	end

	-- 짧은 판이라 못 받은 이유는 랭크 알림이 이미 말한다("N턴 안에 끝난 판은 …"). 같은 말을 두 번 하지 않는다.
	if reason and not Rank.isShort(state.turn) then
		return winnerId, { text = reason, kind = "info" }
	end
	return nil
end

-- 판이 끝나면 부르는 단 하나의 입구. 랭크 먼저 — 진 사람 몫까지 적는 쪽이 더 중요하다.
function PvpReward.pay(campaignStore, runner, leaderboard)
	local notes = PvpReward.rank(campaignStore, runner, leaderboard)

	local goldSeat, goldNote = PvpReward.gold(campaignStore, runner)
	if goldSeat then
		local rankNote = notes[goldSeat]
		if rankNote then
			-- 한 줄로 묶는다. 하나라도 실패면 실패 색으로 — 놓치면 안 되는 쪽이 이긴다.
			notes[goldSeat] = {
				text = ("%s  ·  %s"):format(rankNote.text, goldNote.text),
				kind = (rankNote.kind == "error" or goldNote.kind == "error") and "error" or "info",
			}
		else
			notes[goldSeat] = goldNote
		end
	end

	for seatId, note in notes do
		runner:noticeSeat(seatId, note.text, note.kind)
	end
end

return PvpReward
