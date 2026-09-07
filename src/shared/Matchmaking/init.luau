--[[
	매칭의 "판단" 부분. Roblox API 를 전혀 쓰지 않는다.

	큐 백엔드(MemoryStore / 같은 서버 테이블)는 엔트리를 담아두고 꺼내오기만 하고,
	**누구와 누구를 붙일지 · 어느 엔트리를 버릴지 · 누가 몇 번 좌석인지** 는 전부 여기서
	정한다. 그래야 Studio 없이, 네트워크 없이 테스트할 수 있다 — 룰 엔진과 같은 이유다.

	여기서 실제로 사고가 나는 지점은 셋이고, 전부 tests/specs/matchmaking.luau 가 막는다.
	  1. 같은 사람이 두 번 큐에 들어가 자기 자신과 매칭된다
	     (취소 → 재등록이 크로스서버에서는 즉시 반영되지 않는다)
	  2. 서버가 죽어 주인이 사라진 엔트리가 큐에 영원히 남는다      → TTL
	  3. 한 배치에서 같은 엔트리를 두 매치에 넣는다                 → 소비 표시
	  4. 취소한 사람의 유령 엔트리가 **상대를** 아무도 오지 않는 대전 서버로 끌고 간다
	     (MemoryStore 큐는 개별 항목 삭제가 없어서 취소해도 엔트리가 남는다) → blockedTokens
	  5. 취소한 사람이 다시 큐에 섰는데 계속 걸러진다 → 차단은 **사람이 아니라 등록** 단위

	엔트리 하나 = 큐에 서 있는 사람 하나.

	    { userId = 12345, name = "Kim", serverId = <JobId>, joinedAt = <os.time()> }

	serverId 가 필요한 이유: 텔레포트는 자기 서버의 플레이어에게만 걸 수 있다.
	짝을 지은 서버는 상대 서버에 "이 사람 태워보내라" 를 전해야 하고, 그 주소가 JobId 다.
]]

local RNG = require(script.Parent.Rules.RNG)

local Matchmaking = {}

-- 시드가 가질 수 있는 최대값. RNG 의 모듈러스와 같다.
local MAX_SEED = 2147483646

--==========================================================================
-- 엔트리
--==========================================================================

--[[
	token 은 이 **등록 한 건**의 식별자다. 사람(userId)이 아니라 등록을 가리킨다.

	취소를 사람 단위로 기억하면 "취소 → 다시 큐" 가 막힌다. 같은 사람의 새 등록까지
	같이 걸러지기 때문이다. 취소된 등록만 정확히 지목하려면 등록마다 이름표가 필요하다.
]]
function Matchmaking.newEntry(userId, name, serverId, now, token)
	return {
		userId = userId,
		name = name,
		serverId = serverId,
		joinedAt = now,
		token = token,
	}
end

--[[
	TTL 을 넘겼는가.

	joinedAt 이 미래인 경우(서버 간 시계 오차)는 만료가 아니다. 오차 때문에 방금 들어온
	사람을 버리면 그 사람은 영원히 매칭되지 않는다 — 오차는 관대하게, 노화는 엄격하게.
]]
function Matchmaking.isExpired(entry, now, ttl)
	return (now - entry.joinedAt) > ttl
end

--==========================================================================
-- 짝짓기
--==========================================================================

local function byWaitTime(a, b)
	if a.joinedAt ~= b.joinedAt then
		return a.joinedAt < b.joinedAt -- 오래 기다린 사람 먼저
	end
	return a.userId < b.userId -- 동률이면 결정론적으로
end

--[[
	큐에서 꺼내온 엔트리 묶음을 어떻게 처리할지 계획한다.

	    plan(entries, { now = , ttl = , seed = , blockedTokens = , maxMatches = })
	      -> {
	           matches   = { { id, seed, startingPlayerId, seats = { entry, entry } }, ... }
	           expired   = { entry, ... }   버린다 (큐에서 제거)
	           cancelled = { entry, ... }   버린다 (취소한 사람의 유령 엔트리)
	           duplicate = { entry, ... }   버린다 (같은 userId 의 나중 엔트리)
	           waiting   = { entry, ... }   짝이 없다 (큐에 되돌린다)
	         }

	    blockedTokens = { [token] = true }
	        취소된 **등록**. 큐에서 지울 수 없으니 짝짓는 순간에 거른다.
	        userId 가 아니라 token 인 것이 중요하다 — 같은 사람이 다시 큐에 서면
	        새 token 이라 걸리지 않는다.

	호출자는 matches/expired/duplicate 에 든 엔트리만 큐에서 지우고, waiting 은
	그대로 둔다. 계획과 실행을 나눠둔 덕에 "무엇을 지울지" 를 테스트할 수 있다.

	seed 는 반드시 호출자가 준다. 여기서 시각이나 userId 로 만들면 클라이언트가
	셔플 결과를 예측할 수 있게 된다 — 카드 게임에서 그건 곧 치트다.
]]
function Matchmaking.plan(entries, opts)
	local now = opts.now
	local ttl = opts.ttl
	local rng = RNG.new(opts.seed)
	local maxMatches = opts.maxMatches or math.huge

	local blockedTokens = opts.blockedTokens or {}
	local result = { matches = {}, expired = {}, cancelled = {}, duplicate = {}, waiting = {} }

	--------------------------------------------------------------------
	-- 1. 만료 · 취소 · 중복 걸러내기
	--------------------------------------------------------------------
	local sorted = table.clone(entries)
	table.sort(sorted, byWaitTime)

	local seen = {}
	local live = {}

	for _, entry in sorted do
		if Matchmaking.isExpired(entry, now, ttl) then
			table.insert(result.expired, entry)
		elseif entry.token ~= nil and blockedTokens[entry.token] then
			-- 취소된 등록. 이 한 줄이 없으면 그 유령이 상대를 빈 대전 서버로 끌고 간다.
			table.insert(result.cancelled, entry)
		elseif seen[entry.userId] then
			-- 먼저 온 엔트리가 이미 채택됐다. 나중 것은 유령이다.
			table.insert(result.duplicate, entry)
		else
			seen[entry.userId] = true
			table.insert(live, entry)
		end
	end

	--------------------------------------------------------------------
	-- 2. 둘씩 묶기
	--------------------------------------------------------------------
	local index = 1
	while index + 1 <= #live and #result.matches < maxMatches do
		local a, b = live[index], live[index + 1]
		local seed = rng:nextInteger(1, MAX_SEED)

		-- 좌석도 동전을 던진다. 큐에 먼저 들어온 사람이 항상 1번이면
		-- 좌석에 붙은 이점(선공 확률 · UI 방향)이 대기 시간에 따라 편향된다.
		local seats = if rng:nextInteger(1, 2) == 1 then { a, b } else { b, a }

		table.insert(result.matches, {
			id = Matchmaking.matchId(seats),
			seed = seed,
			seats = seats,
			startingPlayerId = opts.startingPlayerFor and opts.startingPlayerFor(seed) or 1,
		})

		index += 2
	end

	for rest = index, #live do
		table.insert(result.waiting, live[rest])
	end

	return result
end

--[[
	로그·중복방지용 식별자. 좌석 순서와 무관하게 같은 두 사람이면 같은 문자열이다.
]]
function Matchmaking.matchId(seats)
	local a, b = seats[1].userId, seats[2].userId
	if a > b then
		a, b = b, a
	end
	return ("%d-%d"):format(a, b)
end

return Matchmaking
