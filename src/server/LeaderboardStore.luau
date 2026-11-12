--[[
	랭크 순위표 — 랭크 점수가 높은 순으로 위 몇 명.

	OrderedDataStore 를 쓴다. 보통 DataStore 는 "점수 순으로 위 50명" 을 물을 방법이 없다.
	OrderedDataStore 는 **정수 하나만** 담는 대신 정렬해서 꺼내 준다(GetSortedAsync).

	    키 = user_<UserId>,  값 = 랭크 점수

	진짜 기록은 캠페인 진행도(`rankPoints`)에 있고, 여기는 **정렬용 사본**이다. 둘이 어긋나면
	(여기 쓰기만 실패) 그 사람의 순위표 점수가 한 판 늦다 — 다음 판에 다시 적히며 맞춰진다.
	그래서 여기 쓰기가 실패해도 판 결과는 그대로 둔다.

	--------------------------------------------------------------------------
	이름

	OrderedDataStore 에는 이름을 못 담는다(정수뿐). 이름은 UserId 로 찾는다 —
	이 서버에 있으면 Player.Name, 없으면 Players:GetNameFromUserIdAsync(웹 요청, 실패할 수
	있다). 찾은 이름은 들고 있는다. 끝내 못 찾으면 "플레이어 #id" 로 그린다 — 이름 하나
	때문에 순위표가 안 뜨면 안 된다.

	--------------------------------------------------------------------------
	요청 아끼기

	GetSortedAsync 는 DataStore 요청 한도를 먹는다. 사람마다 순위표를 열 때마다 부르면
	인원이 많은 서버에서 한도에 닿는다. 그래서 위 목록을 CACHE_SECONDS 동안 들고 있고,
	이 서버에서 점수를 새로 적으면 바로 버린다(방금 끝난 판이 순위표에 안 보이면 이상하다).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local STORE_NAME = "RankLeaderboard_v1"

local LeaderboardStore = {}
LeaderboardStore.__index = LeaderboardStore

LeaderboardStore.Size = 50 -- 순위표에 보이는 사람 수
LeaderboardStore.CacheSeconds = 30

function LeaderboardStore.new()
	local self = setmetatable({}, LeaderboardStore)

	self.names = {} -- UserId -> 이름
	self.rows = nil -- 마지막으로 읽은 위 목록
	self.readAt = -math.huge

	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	if ok then
		self.store = store
	else
		warn("[TCG] 순위표 저장소를 열지 못했습니다 — 순위표가 비어 보입니다: " .. tostring(store))
	end

	return self
end

local function keyFor(userId)
	return ("user_%d"):format(userId)
end

local function userIdOf(key)
	return tonumber(tostring(key):match("^user_(%d+)$"))
end

--[[
	이 사람의 랭크 점수를 순위표에 적는다. -> ok
	실패해도 판 결과는 그대로다(머리말). 경고만 남긴다.
]]
function LeaderboardStore:record(userId, points)
	if not self.store or type(userId) ~= "number" or type(points) ~= "number" then
		return false
	end

	local ok, err = pcall(function()
		self.store:SetAsync(keyFor(userId), math.max(0, math.floor(points)))
	end)
	if not ok then
		warn(("[TCG] 순위표에 적지 못했습니다 (%d): %s"):format(userId, tostring(err)))
		return false
	end

	self.readAt = -math.huge -- 방금 끝난 판이 바로 보이게
	return true
end

-- UserId → 이름. 못 찾으면 "플레이어 #id" (머리말).
function LeaderboardStore:nameOf(userId)
	local cached = self.names[userId]
	if cached then
		return cached
	end

	local here = Players:GetPlayerByUserId(userId)
	if here then
		self.names[userId] = here.Name
		return here.Name
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		self.names[userId] = name
		return name
	end

	return ("플레이어 #%d"):format(userId)
end

--[[
	위 Size 명. -> { { place, userId, name, points }, ... }  (1등부터)

	동점은 같은 순위가 아니라 **나열된 순서**대로 번호를 붙인다. 같은 순위를 주면 "공동 3위"
	다음이 5위가 되는데, 50명짜리 목록에서는 그게 더 헷갈린다.
	못 읽으면 직전에 읽은 것을, 그것도 없으면 빈 목록을 준다.
]]
function LeaderboardStore:top()
	if self.rows and os.clock() - self.readAt < LeaderboardStore.CacheSeconds then
		return self.rows
	end
	if not self.store then
		return self.rows or {}
	end

	local ok, page = pcall(function()
		return self.store:GetSortedAsync(false, LeaderboardStore.Size):GetCurrentPage()
	end)
	if not ok then
		warn(("[TCG] 순위표를 읽지 못했습니다: %s"):format(tostring(page)))
		return self.rows or {}
	end

	local rows = {}
	for _, item in page do
		local userId = userIdOf(item.key)
		if userId then
			table.insert(rows, {
				place = #rows + 1,
				userId = userId,
				name = self:nameOf(userId),
				points = item.value,
			})
		end
	end

	self.rows = rows
	self.readAt = os.clock()
	return rows
end

-- 위 목록에서 이 사람의 순위. 목록 밖이면 nil.
function LeaderboardStore.placeIn(rows, userId)
	for _, row in rows do
		if row.userId == userId then
			return row.place
		end
	end
	return nil
end

return LeaderboardStore
