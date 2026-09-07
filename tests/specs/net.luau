--[[
	서버 → 클라이언트 스냅샷 검증.

	여기서 잡고 싶은 사고는 하나다: Roblox 의 RemoteEvent 직렬화는 "1 부터 이어지는
	배열" 과 "문자열 키 딕셔너리" 만 안전하게 옮긴다. state.cards[instanceId] 처럼
	비연속 숫자 키를 쓰는 테이블을 그대로 실으면 **에러 없이 조용히** 모양이 바뀐다.

	Studio 를 켜야만 드러나는 종류의 버그라서, 전송 직전 모양을 여기서 못 박아둔다.
]]

return function(t, ctx)
	local Rules, Net, Fixture = ctx.Rules, ctx.Net, ctx.Fixture
	local Zone = Rules.Enums.Zone
	local Phase = Rules.Enums.Phase

	--==================================================================
	-- 전송 가능한 모양인가
	--==================================================================

	--[[
		모든 테이블이 (a) 빈 테이블 (b) 1..n 배열 (c) 문자열 키 딕셔너리 중 하나인지.
		섞여 있거나 숫자 키가 비어 있으면 실패시킨다.
	]]
	local function assertTransferable(value, path)
		if type(value) ~= "table" then
			return
		end

		local numberKeys, stringKeys, maxIndex = 0, 0, 0

		for key, child in pairs(value) do
			if type(key) == "number" then
				numberKeys += 1
				maxIndex = math.max(maxIndex, key)
			elseif type(key) == "string" then
				stringKeys += 1
			else
				error(("%s: %s 타입의 키는 전송할 수 없습니다"):format(path, type(key)))
			end

			assertTransferable(child, ("%s.%s"):format(path, tostring(key)))
		end

		if numberKeys > 0 and stringKeys > 0 then
			error(("%s: 숫자 키와 문자열 키가 섞여 있습니다"):format(path))
		end
		if numberKeys > 0 and maxIndex ~= numberKeys then
			error(("%s: 비연속 숫자 키 (개수 %d, 최대 %d)"):format(path, numberKeys, maxIndex))
		end
	end

	--==================================================================
	-- 상황: 양쪽 필드에 생물, 스택에 마법, 방어 배정까지 있는 판
	--==================================================================

	local function scenario()
		local state = Fixture.match(Rules)
		Fixture.setPhase(state, Phase.Main, 1)
		Fixture.giveCost(Rules, state, 1, 5)

		local mine = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Zone.Field)
		local theirs = Fixture.spawn(Rules, state, 2, "CRE_HAWK", Zone.Field)

		local bolt = Fixture.giveHand(Rules, state, 1, "SPL_FIREBOLT")
		Fixture.giveHand(Rules, state, 1, "CRE_BRUTE")
		Fixture.giveHand(Rules, state, 2, "CRE_SCOUT") -- 상대 손패 (새면 안 된다)

		-- 마법을 스택에 올린다 → 스택 항목 + 대상 지정이 스냅샷에 실린다
		t:allowed(Rules.playCard(state, 1, bolt.id, { { kind = "Creature", id = theirs.id } }))

		-- 비연속 숫자 키를 쓰는 전투 배정
		state.combat.attackers = { { id = theirs.id, targetKind = "Player", targetId = 1 } }
		state.combat.blocks[mine.id] = theirs.id

		return state, mine, theirs, bolt
	end

	t:describe("스냅샷 전송 모양", function()
		t:it("숫자 키 딕셔너리가 하나도 남지 않는다", function()
			local state = scenario()
			local payload = Net.packView(Rules.viewFor(state, 1), state.log)
			assertTransferable(payload, "payload")
		end)

		t:it("빈 판도 전송 가능하다", function()
			local state = Fixture.match(Rules)
			local payload = Net.packView(Rules.viewFor(state, 1), state.log)
			assertTransferable(payload, "payload")
		end)
	end)

	t:describe("스냅샷 왕복", function()
		t:it("카드가 인스턴스 id 로 다시 조회된다", function()
			local state, mine, theirs = scenario()
			local view = Net.unpackView(Net.packView(Rules.viewFor(state, 1), state.log))

			t:truthy(view.cards[mine.id], "내 생물이 사라졌습니다")
			t:truthy(view.cards[theirs.id], "상대 생물이 사라졌습니다")
			t:eq(view.cards[mine.id].defId, "CRE_GUARD")
		end)

		t:it("방어 배정이 blocker id 를 키로 복원된다", function()
			local state, mine, theirs = scenario()
			local view = Net.unpackView(Net.packView(Rules.viewFor(state, 1), state.log))

			t:eq(view.combat.blocks[mine.id], theirs.id)
			t:eq(#view.combat.attackers, 1)
		end)

		t:it("스택 항목과 대상이 그대로 온다", function()
			local state, _, theirs = scenario()
			local view = Net.unpackView(Net.packView(Rules.viewFor(state, 1), state.log))

			t:eq(#view.stack, 1)
			t:eq(view.stack[1].targets[1].kind, "Creature")
			t:eq(view.stack[1].targets[1].id, theirs.id)
		end)

		t:it("구멍 뚫린 대상 배열의 인덱스가 유지된다", function()
			-- 대상을 안 쓰는 효과가 섞이면 targets 는 { [2] = ... } 처럼 비어 있게 된다.
			local targets = { [2] = { kind = "Player", id = 2 } }
			local restored = Net.unpackTargets(Net.packTargets(targets))

			t:eq(restored[1], nil)
			t:eq(restored[2].id, 2)
			t:eq(restored[2].kind, "Player")
		end)

		t:it("상대 손패는 왕복 후에도 장수만 남는다", function()
			local state = scenario()
			local view = Net.unpackView(Net.packView(Rules.viewFor(state, 1), state.log))

			t:eq(view.players[2].hand, nil, "상대 손패가 새어나갔습니다")
			t:truthy(view.players[2].handCount > 0)
			t:truthy(view.players[1].hand ~= nil, "내 손패는 보여야 합니다")
		end)
	end)

	--==================================================================
	-- 클라이언트가 이 뷰로 서버와 같은 판정을 내는가
	--==================================================================

	t:describe("뷰 위에서의 룰 판정", function()
		t:it("손패 카드의 낼 수 있음 여부가 서버와 일치한다", function()
			local state = Fixture.match(Rules)
			Fixture.setPhase(state, Phase.Main, 1)
			Fixture.giveCost(Rules, state, 1, 2)

			local cheap = Fixture.giveHand(Rules, state, 1, "CRE_GUARD") -- 2코 → 가능
			local pricey = Fixture.giveHand(Rules, state, 1, "CRE_BRUTE") -- 5코 → 불가

			local view = Net.unpackView(Net.packView(Rules.viewFor(state, 1), state.log))

			t:eq(Rules.canPlayCard(view, 1, cheap.id), Rules.canPlayCard(state, 1, cheap.id))
			t:eq(Rules.canPlayCard(view, 1, pricey.id), Rules.canPlayCard(state, 1, pricey.id))
			t:truthy(Rules.canPlayCard(view, 1, cheap.id))
			t:falsy(Rules.canPlayCard(view, 1, pricey.id))
		end)

		t:it("공격 가능 대상이 서버와 일치한다", function()
			local state = Fixture.match(Rules)
			Fixture.setPhase(state, Phase.AttackPrep, 1)

			local attacker = Fixture.spawn(Rules, state, 1, "CRE_RAIDER", Zone.Field)
			Fixture.spawn(Rules, state, 2, "CRE_BULWARK", Zone.Field) -- 도발 → 직공 차단

			local view = Net.unpackView(Net.packView(Rules.viewFor(state, 1), state.log))

			local serverTargets = Rules.Combat.legalAttackTargets(state, attacker)
			local clientTargets = Rules.Combat.legalAttackTargets(view, view.cards[attacker.id])

			t:eq(#clientTargets, #serverTargets)
			t:eq(#clientTargets, 1, "도발이 있으므로 생물 하나만 겨냥할 수 있어야 합니다")
			t:eq(clientTargets[1].kind, "Creature")
		end)

		t:it("페이즈 권한이 서버와 일치한다", function()
			local state = Fixture.match(Rules)
			Fixture.setPhase(state, Phase.Main, 1)

			local view = Net.unpackView(Net.packView(Rules.viewFor(state, 1), state.log))

			local serverPerms = Rules.Phases.permissions(state, 1)
			local clientPerms = Rules.Phases.permissions(view, 1)

			for key, value in serverPerms do
				t:eq(clientPerms[key], value, ("권한 '%s' 불일치"):format(key))
			end
		end)
	end)

	--==================================================================
	-- 2번 좌석 시점
	--
	-- PvP 에서는 내가 1번일 수도 2번일 수도 있다. 클라이언트가 "나는 1번" 이라고
	-- 가정하고 있으면 2번 자리에 앉은 사람은 상대 패를 자기 손패로 보고, 자기 생물을
	-- 상대 필드에서 찾는다. 뷰가 좌석 대칭인지 여기서 못 박는다.
	--==================================================================

	t:describe("2번 좌석 시점", function()
		local function bothViews(state)
			return Net.unpackView(Net.packView(Rules.viewFor(state, 1), state.log)),
				Net.unpackView(Net.packView(Rules.viewFor(state, 2), state.log))
		end

		t:it("스냅샷이 자기 좌석 번호를 담고 온다", function()
			local state = Fixture.match(Rules)
			local first, second = bothViews(state)

			t:eq(first.viewerId, 1)
			t:eq(second.viewerId, 2, "이 값이 없으면 클라이언트는 자기 좌석을 알 수 없습니다")
		end)

		t:it("각자 자기 손패만 본다", function()
			local state = Fixture.match(Rules)
			Fixture.setPhase(state, Phase.Main, 1)

			local mine = Fixture.giveHand(Rules, state, 2, "CRE_GUARD")
			local theirs = Fixture.giveHand(Rules, state, 1, "CRE_BRUTE")

			local _, second = bothViews(state)

			t:truthy(second.cards[mine.id], "2번의 손패 카드가 2번에게 보여야 합니다")
			t:falsy(second.cards[theirs.id], "1번의 손패가 2번에게 새고 있습니다")
			t:eq(#second.players[2].hand, #state.players[2].hand, "내 손패는 전부 와야 합니다")
			t:falsy(second.players[1].hand, "상대 손패는 장수만 와야 합니다")
			t:eq(second.players[1].handCount, #state.players[1].hand)
		end)

		t:it("2번 좌석의 판정이 서버와 일치한다", function()
			local state = Fixture.match(Rules)
			Fixture.setPhase(state, Phase.Main, 2)
			Fixture.giveCost(Rules, state, 2, 2)

			local cheap = Fixture.giveHand(Rules, state, 2, "CRE_GUARD") -- 2코 → 가능
			local pricey = Fixture.giveHand(Rules, state, 2, "CRE_BRUTE") -- 5코 → 불가

			local _, second = bothViews(state)

			t:eq(Rules.canPlayCard(second, 2, cheap.id), Rules.canPlayCard(state, 2, cheap.id))
			t:truthy(Rules.canPlayCard(second, 2, cheap.id))
			t:falsy(Rules.canPlayCard(second, 2, pricey.id))
		end)

		t:it("2번 좌석의 공격 대상이 서버와 일치한다", function()
			local state = Fixture.match(Rules)
			Fixture.setPhase(state, Phase.AttackPrep, 2)

			local attacker = Fixture.spawn(Rules, state, 2, "CRE_RAIDER", Zone.Field)
			Fixture.spawn(Rules, state, 1, "CRE_BULWARK", Zone.Field) -- 도발 → 직공 차단

			local _, second = bothViews(state)

			local serverTargets = Rules.Combat.legalAttackTargets(state, attacker)
			local clientTargets =
				Rules.Combat.legalAttackTargets(second, second.cards[attacker.id])

			t:eq(#clientTargets, #serverTargets)
			t:eq(#clientTargets, 1, "도발이 있으므로 생물 하나만 겨냥할 수 있어야 합니다")
			t:eq(clientTargets[1].kind, "Creature")
		end)

		t:it("두 좌석이 같은 공개 정보를 본다", function()
			local state = Fixture.match(Rules)
			Fixture.setPhase(state, Phase.Main, 1)

			local mine = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Zone.Field)
			local theirs = Fixture.spawn(Rules, state, 2, "CRE_RAIDER", Zone.Field)

			local first, second = bothViews(state)

			for _, instanceId in { mine.id, theirs.id } do
				t:truthy(first.cards[instanceId], "필드는 양쪽 모두에게 보여야 합니다")
				t:eq(first.cards[instanceId].controllerId, second.cards[instanceId].controllerId)
			end

			t:eq(first.players[1].life, second.players[1].life)
			t:eq(first.turn, second.turn)
			t:eq(first.phase, second.phase)
		end)
	end)
end
