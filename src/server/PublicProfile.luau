--[[
	**다른 사람의** 프로필 화면 값을 만든다. 두 곳이 쓴다.

	    순위표에서 이름을 눌렀을 때       Lobby:viewProfile
	    판이 끝난 화면의 [상대 프로필]    Lobby:foeProfile · Arena:foeProfile

	로비와 대전 서버가 각자 조립하면 "무엇을 숨기나" 가 두 곳에 생기고, 한쪽만 고치면
	대전 서버에서만 상대 덱이 새는 식의 구멍이 난다. 그래서 여기 한 곳에 둔다.

	보이는 것: 이름 · 티어 · 순위 · 전적 · 낀 꾸밈 · 모은 정도 · 캠페인 진도.
	**안 보이는 것: 덱 · 골드 · MMR.** 덱은 대전 상대에게 전략이 그대로 새는 정보고, 골드는
	남이 알 이유가 없다. MMR 은 내 프로필에서도 안 보인다(숨은 점수 — Rank 머리말).

	읽기만 한다 — 남의 캐시를 만들지도, 저장값을 만들지도 않는다(CampaignStore:read ·
	CollectionStore:read).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Campaign = require(Shared.Campaign)
local Collection = require(Shared.Collection)
local Cosmetics = require(Shared.Cosmetics)
local Net = require(Shared.Net)
local Rank = require(Shared.Rank)

local LeaderboardStore = require(script.Parent.LeaderboardStore)

local PublicProfile = {}

--[[
	한 사람이 남의 프로필을 여는 간격(초). 아무 id 나 보내도 공개 정보만 나가므로 막을
	이유는 없지만, 한 번 열 때마다 저장소를 두 번 읽고 이름도 물어서 요청 한도를 먹는다.
]]
PublicProfile.Cooldown = 1

--[[
	지금 열어도 되나. 되면 시각을 적고 true. -> boolean
	lastLookup 은 부르는 쪽이 들고 있는 { [Player]: os.clock() } 표다 — 나간 사람은 부르는 쪽이 지운다.
]]
function PublicProfile.allow(lastLookup, player)
	local now = os.clock()
	local last = lastLookup[player]
	if last and now - last < PublicProfile.Cooldown then
		return false
	end
	lastLookup[player] = now
	return true
end

--[[
	stores = { campaign = CampaignStore, collection = CollectionStore, leaderboard = LeaderboardStore }
	backTo = 프로필의 [뒤로] 가 갈 곳 ("leaderboard" | "battle")
	-> Net 의 profile 화면 값 (mine = false)
]]
function PublicProfile.build(stores, userId, backTo)
	local progress = stores.campaign:read(userId)
	local collection = stores.collection:read(userId)
	local have, total = Collection.progress(collection)

	return {
		screen = Net.LobbyScreen.Profile,
		mine = false,
		backTo = backTo,
		name = stores.leaderboard:nameOf(userId),
		rankPoints = Rank.pointsOf(progress),
		place = LeaderboardStore.placeIn(stores.leaderboard:top(), userId),
		wins = progress.rankedWins or 0,
		losses = progress.rankedLosses or 0,
		frame = Cosmetics.equippedFrame(collection),
		back = Cosmetics.equippedBack(collection),
		collected = have,
		total = total,
		cleared = progress.cleared or 0,
		stages = Campaign.count(),
	}
end

--[[
	이 사람이 방금 끝낸 판의 **상대** UserId. 없으면 nil.

	  · 판이 끝나야 한다 — 버튼은 결과 화면에만 있다. 두는 중에 프로필이 판을 덮으면 안 된다
	  · 상대가 사람이어야 한다 — AI 좌석에는 UserId 가 없다
	  · 상대가 이미 나갔어도 된다 — 좌석은 나간 사람의 UserId 를 남긴다(MatchRunner.new)
]]
function PublicProfile.foeOf(runner, player)
	if not runner or not runner.state or not runner.state.finished then
		return nil
	end
	local seatId = runner.seatOf[player]
	if not seatId then
		return nil
	end
	local foe = runner.seats[(seatId == 1) and 2 or 1]
	return foe and foe.userId or nil
end

return PublicProfile
