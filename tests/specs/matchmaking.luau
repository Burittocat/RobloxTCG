--[[
	빠른 대전 짝짓기 검증.

	여기서 잡고 싶은 사고는 넷이다. 전부 "실제로 두 사람이 큐에 서 봐야" 드러나는
	종류라, 순수 함수로 떼어놓지 않으면 게시된 서버에서만 발견된다.

	  1. 자기 자신과 매칭된다      — 취소 후 재등록이 크로스서버에서는 즉시 반영되지 않아
	                                 같은 userId 엔트리가 큐에 둘 이상 남는다
	  2. 유령 엔트리가 안 사라진다 — 서버가 죽으면 그 서버가 넣은 엔트리를 지울 사람이 없다
	  3. 취소한 사람이 상대를 끌고 간다 — MemoryStore 큐는 개별 삭제가 없어 취소해도
	                                 엔트리가 남는다. 그 유령과 짝지어진 상대가 아무도
	                                 오지 않는 대전 서버로 간다
	  4. 좌석이 대기 시간에 편향   — 먼저 온 사람이 항상 1번이면 좌석 이점이 큐 순서를 탄다
]]

return function(t, ctx)
	local Rules, Matchmaking = ctx.Rules, ctx.Matchmaking

	local NOW = 1_000_000
	local TTL = 90

	local nextToken = 0
	local function entry(userId, secondsAgo, serverId)
		nextToken += 1
		return Matchmaking.newEntry(
			userId,
			("P%d"):format(userId),
			serverId or "job-a",
			NOW - (secondsAgo or 0),
			("t%d"):format(nextToken)
		)
	end

	local function plan(entries, opts)
		opts = opts or {}
		return Matchmaking.plan(entries, {
			now = opts.now or NOW,
			ttl = opts.ttl or TTL,
			seed = opts.seed or 1234,
			blockedTokens = opts.blockedTokens,
			maxMatches = opts.maxMatches,
			startingPlayerFor = opts.startingPlayerFor,
		})
	end

	local function userIdsOf(match)
		return { match.seats[1].userId, match.seats[2].userId }
	end

	--==================================================================
	t:describe("짝짓기", function()
		t:it("네 명이면 두 판이 선다", function()
			local result = plan({ entry(1, 40), entry(2, 30), entry(3, 20), entry(4, 10) })

			t:eq(#result.matches, 2)
			t:eq(#result.waiting, 0)
		end)

		t:it("홀수면 가장 늦게 온 사람이 남는다", function()
			local result = plan({ entry(1, 40), entry(2, 30), entry(3, 5) })

			t:eq(#result.matches, 1)
			t:eq(#result.waiting, 1)
			t:eq(result.waiting[1].userId, 3, "가장 늦게 온 사람이 다음 차례를 기다려야 합니다")
		end)

		t:it("혼자면 아무 일도 일어나지 않는다", function()
			local result = plan({ entry(1, 10) })

			t:eq(#result.matches, 0)
			t:eq(#result.waiting, 1)
		end)

		t:it("오래 기다린 사람부터 붙는다", function()
			local result = plan({ entry(3, 5), entry(1, 60), entry(2, 50), entry(4, 1) })

			local first = userIdsOf(result.matches[1])
			table.sort(first)
			t:eq(first[1], 1)
			t:eq(first[2], 2, "가장 오래 기다린 둘이 먼저 붙어야 합니다")
		end)

		t:it("maxMatches 를 넘겨 짝짓지 않는다", function()
			local result =
				plan({ entry(1, 40), entry(2, 30), entry(3, 20), entry(4, 10) }, { maxMatches = 1 })

			t:eq(#result.matches, 1)
			t:eq(#result.waiting, 2, "남은 둘은 큐에 되돌아가야 합니다")
		end)

		t:it("서로 다른 서버의 사람끼리 붙는다", function()
			local result = plan({ entry(1, 20, "job-a"), entry(2, 10, "job-b") })

			t:eq(#result.matches, 1)
			t:neq(
				result.matches[1].seats[1].serverId,
				result.matches[1].seats[2].serverId,
				"크로스서버 매칭이 목적입니다"
			)
		end)
	end)

	--==================================================================
	t:describe("만료", function()
		t:it("TTL 을 넘긴 엔트리는 버려진다", function()
			local result = plan({ entry(1, TTL + 1), entry(2, 10) })

			t:eq(#result.matches, 0, "죽은 서버의 유령과 매칭되면 안 됩니다")
			t:eq(#result.expired, 1)
			t:eq(result.expired[1].userId, 1)
			t:eq(#result.waiting, 1)
		end)

		t:it("TTL 경계는 아직 살아 있다", function()
			local result = plan({ entry(1, TTL), entry(2, 10) })

			t:eq(#result.expired, 0)
			t:eq(#result.matches, 1)
		end)

		t:it("갱신된 엔트리는 오래 기다려도 만료가 아니다", function()
			-- TTL 은 "주인이 살아 있는가" 를 재는 값이지 "얼마나 기다렸는가" 가 아니다.
			-- 이걸 안 나누면 오래 기다린 사람이 큐에서 조용히 사라진다.
			local old = entry(1, 300) -- 5분 전에 줄 섰지만
			old.refreshedAt = NOW - 10 -- 10초 전에 살아 있다고 알렸다

			local result = plan({ old, entry(2, 20) })

			t:eq(#result.expired, 0)
			t:eq(#result.matches, 1)
		end)

		t:it("갱신이 끊긴 엔트리는 만료된다", function()
			-- 주인 서버가 죽으면 아무도 갱신해주지 않는다. 그게 유일한 청소부다.
			local dead = entry(1, 300)
			dead.refreshedAt = NOW - (TTL + 1)

			local result = plan({ dead, entry(2, 20) })

			t:eq(#result.expired, 1)
			t:eq(#result.matches, 0)
		end)

		t:it("같은 사람의 사본이 오면 살아 있다는 소식을 합친다", function()
			--[[
				주인 서버가 "아직 큐에 있다" 며 다시 넣은 사본이 낡은 사본과 함께 읽힌다.
				갱신본을 그냥 버리면 낡은 쪽만 남아 수명이 계속 줄다 만료된다.
			]]
			local stale = entry(7, 80)
			stale.refreshedAt = NOW - 80
			local fresh = entry(7, 80)
			fresh.refreshedAt = NOW - 1

			local result = plan({ stale, fresh })

			t:eq(#result.duplicate, 1)
			t:eq(#result.waiting, 1)
			t:eq(result.waiting[1].refreshedAt, NOW - 1, "남은 쪽이 최신 갱신 시각을 가져야 합니다")
			t:eq(result.waiting[1].joinedAt, NOW - 80, "줄 선 순서는 그대로여야 합니다")
		end)

		t:it("시계가 앞선 서버의 엔트리를 만료로 보지 않는다", function()
			-- 서버 간 시계 오차로 joinedAt 이 미래일 수 있다.
			-- 이걸 만료로 처리하면 그 사람은 영원히 매칭되지 않는다.
			local result = plan({ entry(1, -5), entry(2, 10) })

			t:eq(#result.expired, 0)
			t:eq(#result.matches, 1)
		end)
	end)

	--==================================================================
	t:describe("중복 등록", function()
		t:it("같은 사람이 자기 자신과 매칭되지 않는다", function()
			local result = plan({ entry(7, 30), entry(7, 10) })

			t:eq(#result.matches, 0)
			t:eq(#result.duplicate, 1)
			t:eq(#result.waiting, 1)
		end)

		t:it("중복이 있어도 상대가 있으면 정상 매칭된다", function()
			local result = plan({ entry(7, 30), entry(7, 10), entry(8, 20) })

			t:eq(#result.matches, 1)
			local ids = userIdsOf(result.matches[1])
			table.sort(ids)
			t:eq(ids[1], 7)
			t:eq(ids[2], 8)
			t:eq(#result.duplicate, 1, "나중 엔트리는 유령이므로 큐에서 지워져야 합니다")
		end)

		t:it("먼저 등록한 엔트리가 살아남는다", function()
			local result = plan({ entry(7, 30), entry(7, 10), entry(8, 20) })

			t:eq(result.duplicate[1].joinedAt, NOW - 10)
		end)
	end)

	--==================================================================
	t:describe("큐 취소", function()
		t:it("취소한 등록은 짝짓기에서 빠진다", function()
			local ghost, other = entry(1, 30), entry(2, 20)
			local result = plan({ ghost, other }, { blockedTokens = { [ghost.token] = true } })

			t:eq(#result.matches, 0)
			t:eq(#result.cancelled, 1)
			t:eq(result.cancelled[1].userId, 1)
		end)

		t:it("취소한 사람의 상대는 큐에 남는다", function()
			-- 이게 이 기능의 존재 이유다. 걸러내지 않으면 짝이 성립해버려서,
			-- 취소하지 않은 **상대가** 아무도 오지 않는 대전 서버로 끌려간다.
			local ghost, other = entry(1, 30), entry(2, 20)
			local result = plan({ ghost, other }, { blockedTokens = { [ghost.token] = true } })

			t:eq(#result.waiting, 1)
			t:eq(result.waiting[1].userId, 2, "남은 사람은 계속 기다려야 합니다")
		end)

		t:it("취소하고 다시 큐에 서면 매칭된다", function()
			--[[
				차단이 사람 단위였을 때의 버그. 취소 → 재등록이 TTL(90초) 동안 통째로
				막혀서, 플레이 테스트에서 제일 먼저 해보는 동작이 먹통이 됐다.
				차단은 취소된 **등록** 만 가리켜야 한다.
			]]
			local ghost = entry(1, 30) -- 취소한 등록
			local again = entry(1, 5) -- 같은 사람이 다시 등록
			local other = entry(2, 20)

			local result =
				plan({ ghost, again, other }, { blockedTokens = { [ghost.token] = true } })

			t:eq(#result.matches, 1, "다시 선 사람은 매칭돼야 합니다")
			local ids = userIdsOf(result.matches[1])
			table.sort(ids)
			t:eq(ids[1], 1)
			t:eq(ids[2], 2)
			t:eq(#result.cancelled, 1, "옛 등록만 걸러져야 합니다")
			t:eq(result.cancelled[1].token, ghost.token)
		end)

		t:it("취소하지 않은 셋이면 둘은 정상 매칭된다", function()
			local ghost = entry(1, 40)
			local result = plan({ ghost, entry(2, 30), entry(3, 20) }, {
				blockedTokens = { [ghost.token] = true },
			})

			t:eq(#result.matches, 1)
			local ids = userIdsOf(result.matches[1])
			table.sort(ids)
			t:eq(ids[1], 2)
			t:eq(ids[2], 3)
		end)

		t:it("빈 목록은 아무 영향이 없다", function()
			local result = plan({ entry(1, 30), entry(2, 20) }, { blockedTokens = {} })

			t:eq(#result.matches, 1)
			t:eq(#result.cancelled, 0)
		end)
	end)

	--==================================================================
	t:describe("좌석과 시드", function()
		t:it("같은 시드면 결과가 완전히 같다", function()
			local entries = { entry(1, 40), entry(2, 30), entry(3, 20), entry(4, 10) }

			local a = plan(entries, { seed = 999 })
			local b = plan(entries, { seed = 999 })

			-- 매치가 0 개면 아래 루프가 안 돌아 그냥 통과한다.
			t:eq(#a.matches, 2, "네 명이면 두 판이 나와야 이 검사가 의미가 있습니다")
			t:eq(#b.matches, #a.matches)

			for index, match in a.matches do
				t:eq(match.seed, b.matches[index].seed)
				t:eq(match.seats[1].userId, b.matches[index].seats[1].userId)
				t:eq(match.seats[2].userId, b.matches[index].seats[2].userId)
			end
		end)

		t:it("좌석이 대기 순서에 고정되지 않는다", function()
			-- 먼저 온 사람이 항상 1번이면 좌석 이점이 큐 순서를 그대로 탄다.
			local entries = { entry(1, 40), entry(2, 30) }
			local sawFirst, sawSecond = false, false

			for seed = 1, 40 do
				local match = plan(entries, { seed = seed }).matches[1]
				if match.seats[1].userId == 1 then
					sawFirst = true
				else
					sawSecond = true
				end
			end

			t:truthy(sawFirst and sawSecond, "좌석 배정이 한쪽으로 고정돼 있습니다")
		end)

		t:it("matchId 는 좌석 순서와 무관하다", function()
			local a, b = entry(11, 20), entry(22, 10)

			t:eq(Matchmaking.matchId({ a, b }), Matchmaking.matchId({ b, a }))
		end)

		t:it("매치 시드는 서로 다르다", function()
			local result = plan({ entry(1, 40), entry(2, 30), entry(3, 20), entry(4, 10) })

			t:neq(
				result.matches[1].seed,
				result.matches[2].seed,
				"같은 배치의 두 판이 같은 셔플이면 안 됩니다"
			)
		end)

		t:it("선공은 매치 시드로 정해진다", function()
			local result = plan({ entry(1, 40), entry(2, 30) }, {
				startingPlayerFor = Rules.startingPlayerFor,
			})

			local match = result.matches[1]
			t:eq(match.startingPlayerId, Rules.startingPlayerFor(match.seed))
		end)
	end)

	--==================================================================
	t:describe("선공 결정", function()
		t:it("같은 시드면 같은 선공", function()
			t:eq(Rules.startingPlayerFor(4242), Rules.startingPlayerFor(4242))
		end)

		t:it("1번과 2번이 모두 나온다", function()
			local counts = { 0, 0 }
			for seed = 1, 200 do
				local first = Rules.startingPlayerFor(seed)
				t:truthy(first == 1 or first == 2, ("좌석 번호가 아닙니다: %s"):format(tostring(first)))
				counts[first] += 1
			end

			t:truthy(counts[1] > 0 and counts[2] > 0, "한쪽만 선공이 되고 있습니다")
			t:truthy(
				math.abs(counts[1] - counts[2]) < 60,
				("선공 분포가 치우쳐 있습니다: %d / %d"):format(counts[1], counts[2])
			)
		end)
	end)
end
