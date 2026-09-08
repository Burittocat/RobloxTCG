--[[
	"Studio 를 켜면 실제로 돌아가는가" 를 Studio 없이 확인한다.

	    lune run tests/smoke.luau

	tests/run.luau 는 `src/shared` 만 돌리고, tests/check.luau 는 문법만 본다.
	그래서 서버·클라이언트 코드는 **아무도 실행해본 적이 없는 상태**로 커밋된다 —
	nil 인덱싱, 잘못된 require 경로, 없는 Enum 항목, 오타난 속성은 Studio 를 켜서
	그 화면이 뜰 때까지 아무도 모른다.

	여기서는 tests/lib/Roblox 하네스 위에서 그 코드를 진짜로 굴린다.
	서버를 부팅하고, 사람을 접속시키고, **화면의 버튼을 눌러서** 매칭과 대전을 시킨다.
	판정도 화면을 읽어서 한다 — 내부 변수를 들여다보지 않는다.

	통과하면 아는 것: 스크립트가 죽지 않고, 매칭이 성사되고, 두 사람이 각자 자기 좌석의
	화면을 받고, 판이 끝까지 닫힌다.
	통과해도 모르는 것: 레이아웃이 예쁜지, 실제 MemoryStore/텔레포트가 답하는지.
]]

local process = require("@lune/process")

local Roblox = require("./lib/Roblox")
local Test = require("./lib/Test")

local Screen = Roblox.Screen

local t = Test.new()

--==========================================================================
-- 공용 도우미
--==========================================================================

--[[
	Studio 라면 출력창에 떴을 것을 테스트 실패로 바꾼다. 이게 이 파일의 존재 이유다.

	**warn 도 같이 본다.** 서버 코드는 거의 모든 실패를 pcall 로 잡아 warn 으로 흘린다 —
	큐 등록 실패, 예약 서버 확보 실패, 텔레포트 실패, 행동 처리 예외가 전부 그렇다.
	빨간 줄(error)만 보면 그 경로가 통째로 안 보여서, 실제로는 아무것도 동작하지 않는데
	테스트는 초록불인 상태가 만들어진다.
]]
local function assertNoErrors(world, label)
	local errors = world:errors()
	local warnings = world:takeWarnings()

	if #errors == 0 and #warnings == 0 then
		return
	end

	local parts = {}
	for _, entry in errors do
		table.insert(parts, "오류: " .. entry)
	end
	for _, entry in warnings do
		table.insert(parts, "경고: " .. entry)
	end

	error(("%s — %d건\n  %s"):format(label, #parts, table.concat(parts, "\n  ")), 2)
end

local function guiOf(player)
	return player.PlayerGui
end

local function panelName(player, panel)
	local node = Screen.find(guiOf(player), panel)
	if not node then
		return nil
	end
	local label = node:FindFirstChild("PlayerName")
	return label and label.Text or nil
end

--[[
	빠른 대전 버튼을 누르고 매칭이 붙을 만큼 시간을 흘린다.
	폴링 주기가 2초라 넉넉히 감는다.
]]
local function clickQueue(player)
	local button = Screen.findButton(guiOf(player), "빠른 대전")
	assert(button, ("%s 화면에 '빠른 대전' 버튼이 없습니다"):format(player.Name))
	Screen.click(button)
end

--[[
	멀리건 관문을 통과한다. 판은 여기서부터 시작한다 —
	관문에 서 있는 동안에는 '페이즈 종료' 가 꺼져 있어서 아무것도 굴러가지 않는다.
	(관문 자체가 제대로 뜨는지는 아래 "멀리건 관문" 절이 본다)
]]
--[[
	그 버튼이 눌릴 수 있게 될 때까지 시간을 감는다.

	AI 는 한 수에 0.55초씩 쓰므로 "몇 초 감고 확인" 은 AI 가 얼마나 둘 게 많은지에
	따라 깜빡인다. 조건이 만족될 때까지 기다리고, 못 기다리면 nil 을 돌려준다.
]]
local function waitForButton(world, player, text, budget)
	local waited = 0
	while waited <= (budget or 30) do
		local button = Screen.findButton(guiOf(player), text)
		if button and button.Active then
			return button
		end
		world:advance(0.5)
		waited += 0.5
	end
	return nil
end

--[[
	멀리건 관문을 통과시킨다. 판은 여기서부터 시작한다 —
	관문에 서 있는 동안에는 '페이즈 종료' 가 꺼져 있어서 아무것도 굴러가지 않는다.

	**차례가 올 때까지 기다려야 한다.** 관문은 선공부터 차례로 묻고, 자기 차례가
	아닌 사람의 버튼은 꺼져 있다. 그냥 한 번 보고 지나가면 아무도 안 누른 채로
	관문에 머무는데, 화면에는 아무 오류도 안 뜬다.
]]
local function passMulligan(world, ...)
	local players = { ... }
	local kept = {}
	local waited = 0

	while waited <= 30 do
		local done = true

		for _, player in players do
			if not kept[player] then
				local button = Screen.findButton(guiOf(player), "이대로 시작")
				if button and button.Active then
					Screen.click(button)
					kept[player] = true
				else
					done = false
				end
			end
		end

		if done then
			world:advance(1)
			return true
		end

		world:advance(0.5)
		waited += 0.5
	end

	return false
end

--==========================================================================
t:describe("로비 부팅", function()
	t:it("접속하면 시작 화면이 뜬다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()

		world:advance(0.5)
		assertNoErrors(world, "서버 부팅")

		local kim = lobby:addPlayer("Kim")
		world:advance(2)
		assertNoErrors(world, "클라이언트 부팅")

		local gui = guiOf(kim)
		t:truthy(Screen.findButton(gui, "빠른 대전"), "'빠른 대전' 버튼이 보여야 합니다")
		t:truthy(Screen.findButton(gui, "AI 연습"), "'AI 연습' 버튼이 보여야 합니다")
		t:falsy(Screen.hasText(gui, "턴 "), "아직 전투 화면이 뜨면 안 됩니다")
	end)

	t:it("큐에 섰다가 취소하면 시작 화면으로 돌아온다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		clickQueue(kim)
		world:advance(1)
		assertNoErrors(world, "큐 등록")

		local gui = guiOf(kim)
		t:truthy(Screen.hasText(gui, "상대를 찾는 중"), "대기 표시가 떠야 합니다")
		t:falsy(Screen.findButton(gui, "빠른 대전"), "큐에 서 있는 동안은 다시 누를 수 없어야 합니다")

		Screen.click(Screen.findButton(gui, "취소"))
		world:advance(1)
		assertNoErrors(world, "큐 취소")

		t:truthy(Screen.findButton(gui, "빠른 대전"), "취소하면 시작 화면으로 돌아와야 합니다")
	end)

	t:it("혼자면 매칭되지 않는다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		clickQueue(kim)
		world:advance(15)
		assertNoErrors(world, "혼자 대기")

		t:truthy(Screen.hasText(guiOf(kim), "상대를 찾는 중"), "계속 기다려야 합니다")
	end)
end)

--==========================================================================
t:describe("AI 연습", function()
	t:it("버튼을 누르면 한 판이 시작된다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		assertNoErrors(world, "AI 연습 시작")

		local gui = guiOf(kim)
		t:truthy(Screen.hasText(gui, "턴 "), "전투 화면이 떠야 합니다")
		t:eq(panelName(kim, "MyPanel"), "Kim")
		t:eq(panelName(kim, "FoePanel"), "훈련용 AI")
	end)

	t:it("여러 턴을 진행해도 화면이 죽지 않는다", function()
		--[[
			판을 1턴에 세워두면 필드가 비어 있어서 CardView.fieldCard 가 **한 번도
			실행되지 않는다.** 생물 카드 · 키워드 칩 · 탭 표시 · 공격/방어 배지가 전부
			그 안에 있으므로, 여기 오타는 Studio 를 켜서 생물이 나올 때까지 안 잡힌다.

			페이즈 종료를 반복해서 턴을 굴리면 AI 가 필드를 채운다.
		]]
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		t:truthy(passMulligan(world, kim), "멀리건 관문을 통과하지 못했습니다")

		for turn = 1, 30 do
			local button = Screen.findButton(guiOf(kim), "페이즈 종료")
			if button and button.Active then
				Screen.click(button)
			end
			world:advance(1.5)
			assertNoErrors(world, ("%d 번째 페이즈 종료"):format(turn))

			if Screen.countNamed(guiOf(kim), "Field_") > 0 then
				break
			end
		end

		t:truthy(
			Screen.countNamed(guiOf(kim), "Field_") > 0,
			"턴을 굴렸는데도 필드에 생물이 한 마리도 그려지지 않았습니다"
		)
		t:truthy(Screen.hasText(guiOf(kim), "♥ "), "라이프 표시가 살아 있어야 합니다")
	end)

	t:it("항복하면 결과 화면이 뜬다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)

		Screen.click(Screen.findButton(guiOf(kim), "항복"))
		world:advance(2)
		assertNoErrors(world, "항복")

		local gui = guiOf(kim)
		t:truthy(Screen.hasText(gui, "패배"), "결과 화면이 떠야 합니다")
		t:truthy(Screen.findButton(gui, "다시 하기"), "연습이므로 '다시 하기' 가 있어야 합니다")
		t:truthy(Screen.findButton(gui, "로비로"), "연습이므로 '로비로' 가 있어야 합니다")
	end)

	t:it("로비로 돌아가면 시작 화면이 다시 뜬다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		Screen.click(Screen.findButton(guiOf(kim), "항복"))
		world:advance(2)
		Screen.click(Screen.findButton(guiOf(kim), "로비로"))
		world:advance(2)
		assertNoErrors(world, "로비 복귀")

		t:truthy(Screen.findButton(guiOf(kim), "빠른 대전"), "시작 화면으로 돌아와야 합니다")
	end)
end)

--==========================================================================
-- 같은 서버 매칭 (Studio 에서 2인 테스트했을 때의 경로)
--==========================================================================

t:describe("같은 서버 매칭", function()
	local function matchTwo()
		local world = Roblox.newWorld() -- studio = true → Local 백엔드
		local lobby = world:newServer():boot()

		local kim = lobby:addPlayer("Kim")
		local lee = lobby:addPlayer("Lee")
		world:advance(2)

		clickQueue(kim)
		clickQueue(lee)
		world:advance(6) -- 폴링 2초 + 준비 왕복
		assertNoErrors(world, "같은 서버 매칭")

		assert(passMulligan(world, kim, lee), "멀리건 관문을 통과하지 못했습니다")
		assertNoErrors(world, "멀리건 관문")

		return world, lobby, kim, lee
	end

	t:it("두 사람이 붙어 판이 시작된다", function()
		local world, _, kim, lee = matchTwo()

		t:truthy(Screen.hasText(guiOf(kim), "턴 "), "Kim 에게 전투 화면이 떠야 합니다")
		t:truthy(Screen.hasText(guiOf(lee), "턴 "), "Lee 에게 전투 화면이 떠야 합니다")
		assertNoErrors(world, "판 시작")
	end)

	t:it("각자 자기가 아래칸에 앉는다", function()
		local _, _, kim, lee = matchTwo()

		-- 이 검사가 좌석 일반화의 핵심이다. 클라이언트가 "나는 1번" 이라고 가정하면
		-- 둘 중 한 명은 상대를 자기 자리에서 보게 된다.
		t:eq(panelName(kim, "MyPanel"), "Kim")
		t:eq(panelName(kim, "FoePanel"), "Lee")
		t:eq(panelName(lee, "MyPanel"), "Lee")
		t:eq(panelName(lee, "FoePanel"), "Kim")
	end)

	t:it("한 명만 선공이다", function()
		local _, _, kim, lee = matchTwo()

		local kimBanner = Screen.find(guiOf(kim), "TurnBanner").Text
		local leeBanner = Screen.find(guiOf(lee), "TurnBanner").Text

		t:neq(kimBanner, leeBanner, "둘 다 '내 턴' 이거나 둘 다 '상대 턴' 이면 안 됩니다")
	end)

	t:it("PvP 결과 화면에는 '다시 매칭' 이 뜬다", function()
		local world, _, kim, lee = matchTwo()

		Screen.click(Screen.findButton(guiOf(kim), "항복"))
		world:advance(2)
		assertNoErrors(world, "PvP 항복")

		t:truthy(Screen.hasText(guiOf(kim), "패배"))
		t:truthy(Screen.hasText(guiOf(lee), "승리"), "상대에게는 승리가 떠야 합니다")
		t:truthy(Screen.findButton(guiOf(kim), "다시 매칭"), "PvP 이므로 '다시 매칭' 이어야 합니다")
		t:falsy(Screen.findButton(guiOf(kim), "다시 하기"), "PvP 에는 '다시 하기' 가 없어야 합니다")
	end)

	t:it("상대가 나가면 남은 쪽이 이긴다", function()
		local world, lobby, kim, lee = matchTwo()

		lobby:removePlayer(lee)
		world:advance(2)
		assertNoErrors(world, "이탈 몰수")

		t:truthy(Screen.hasText(guiOf(kim), "승리"), "남은 쪽이 이겨야 합니다")
	end)
end)

--==========================================================================
-- 크로스서버 매칭 (게시된 게임에서 도는 경로)
--==========================================================================

t:describe("크로스서버 매칭", function()
	--[[
		서버를 두 개 띄우고 각각에 한 명씩 둔다. 두 사람은 서로 다른 서버에 있으므로
		MemoryStore 큐 → MessagingService → 예약 서버 텔레포트를 전부 거쳐야 만난다.
		Studio 에서는 한 줄도 실행되지 않는 경로다.
	]]
	local function matchAcrossServers()
		local world = Roblox.newWorld({ studio = false })

		local alpha = world:newServer({ jobId = "job-alpha" }):boot()
		local beta = world:newServer({ jobId = "job-beta" }):boot()

		local kim = alpha:addPlayer("Kim")
		local lee = beta:addPlayer("Lee")
		world:advance(2)
		assertNoErrors(world, "두 서버 부팅")

		clickQueue(kim)
		clickQueue(lee)
		world:advance(10) -- 폴링 + 텔레포트 + 도착 + 준비
		assertNoErrors(world, "크로스서버 매칭")

		return world, kim, lee
	end

	t:it("서로 다른 서버의 두 사람이 예약 서버에서 만난다", function()
		local world, kim, lee = matchAcrossServers()

		t:eq(#world.teleports, 2, "두 사람 모두 텔레포트돼야 합니다")
		t:truthy(world.teleports[1].accessCode, "예약 서버 코드가 실려야 합니다")
		t:eq(
			world.teleports[1].accessCode,
			world.teleports[2].accessCode,
			"둘이 같은 예약 서버로 가야 합니다"
		)
		t:neq(
			world.teleports[1].from,
			world.teleports[2].from,
			"서로 다른 서버에서 출발해야 합니다 (크로스서버가 목적입니다)"
		)

		t:truthy(Screen.hasText(guiOf(kim), "턴 "), "Kim 에게 전투 화면이 떠야 합니다")
		t:truthy(Screen.hasText(guiOf(lee), "턴 "), "Lee 에게 전투 화면이 떠야 합니다")
	end)

	t:it("도착 데이터의 좌석이 서로 다르다", function()
		local world, kim, lee = matchAcrossServers()

		local seats = {}
		for _, teleport in world.teleports do
			table.insert(seats, teleport.data.seat)
		end
		table.sort(seats)

		t:eq(seats[1], 1)
		t:eq(seats[2], 2, "두 사람이 같은 좌석을 받으면 판이 열리면 안 됩니다")

		t:eq(panelName(kim, "MyPanel"), "Kim")
		t:eq(panelName(lee, "MyPanel"), "Lee")
	end)

	t:it("같은 판을 가리키며 도착한다", function()
		local world = select(1, matchAcrossServers())

		t:truthy(world.teleports[1].data.matchId, "어느 판인지는 실려야 합니다")
		t:eq(world.teleports[1].data.matchId, world.teleports[2].data.matchId)
	end)

	t:it("매치 시드가 클라이언트로 새지 않는다", function()
		--[[
			텔레포트 데이터는 클라이언트가 GetLocalPlayerTeleportData() 로 읽는다.
			룰 엔진과 Decks.starter() 가 ReplicatedStorage 에 복제돼 있으므로, 시드 하나면
			Rules.newMatch 를 재현해 **양쪽 덱 순서와 상대 손패 전부**를 계산할 수 있다.
			카드 게임에서 그건 곧 게임 종료다. 시드는 대전 서버가 직접 뽑아야 한다.
		]]
		local world = select(1, matchAcrossServers())

		for index, teleport in world.teleports do
			for key in teleport.data do
				t:truthy(
					key == "matchId" or key == "seat" or key == "opponentName",
					("텔레포트 데이터 %d 에 예상 못 한 항목 '%s' 가 있습니다"):format(index, key)
				)
			end
			t:falsy(teleport.data.seed, "시드가 실려 있습니다")
			t:falsy(teleport.data.startingPlayerId, "선공은 시드에서 유도되므로 같이 새면 안 됩니다")
		end
	end)

	t:it("취소한 사람은 태우지 않는다", function()
		local world = Roblox.newWorld({ studio = false })

		local alpha = world:newServer({ jobId = "job-alpha" }):boot()
		local beta = world:newServer({ jobId = "job-beta" }):boot()

		local kim = alpha:addPlayer("Kim")
		local lee = beta:addPlayer("Lee")
		world:advance(2)

		clickQueue(kim)
		clickQueue(lee)

		-- 폴링이 돌기 전에 Kim 이 취소한다. MemoryStore 큐에서는 엔트리를 지울 수 없으므로
		-- 태우기 직전의 로컬 검사가 유일한 거름망이다.
		Screen.click(Screen.findButton(guiOf(kim), "취소"))
		world:advance(10)
		assertNoErrors(world, "취소 후 매칭")

		t:eq(#world.teleports, 0, "취소한 사람이 끼어 있으면 아무도 태우면 안 됩니다")
		t:truthy(Screen.findButton(guiOf(kim), "빠른 대전"), "Kim 은 시작 화면이어야 합니다")
		t:truthy(Screen.hasText(guiOf(lee), "상대를 찾는 중"), "Lee 는 계속 기다려야 합니다")
	end)

	t:it("취소하고 다시 큐에 서면 정상 매칭된다", function()
		--[[
			취소를 사람 단위로 기억했더니 재등록이 TTL(90초) 동안 통째로 막혔다.
			플레이 테스트에서 제일 먼저 해보는 동작이라, 여기서 못 잡으면
			게시하고 나서 "큐가 안 잡힌다" 로 만나게 된다.
		]]
		local world = Roblox.newWorld({ studio = false })

		local alpha = world:newServer({ jobId = "job-alpha" }):boot()
		local beta = world:newServer({ jobId = "job-beta" }):boot()

		local kim = alpha:addPlayer("Kim")
		local lee = beta:addPlayer("Lee")
		world:advance(2)

		clickQueue(kim)
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "취소"))
		world:advance(1)

		clickQueue(kim) -- 마음이 바뀌었다
		clickQueue(lee)
		world:advance(10)
		assertNoErrors(world, "취소 후 재등록")

		t:eq(#world.teleports, 2, "다시 선 사람도 매칭돼야 합니다")
		t:truthy(Screen.hasText(guiOf(kim), "턴 "), "Kim 에게 전투 화면이 떠야 합니다")
		t:truthy(Screen.hasText(guiOf(lee), "턴 "), "Lee 에게 전투 화면이 떠야 합니다")
	end)

	t:it("오래 기다려도 큐에서 사라지지 않는다", function()
		--[[
			엔트리 TTL(90초)은 "주인 서버가 죽었는가" 를 재는 값이지 "얼마나 기다렸는가" 가
			아니다. 그 둘을 안 나눴을 때, 90초 넘게 기다린 사람은 큐에서 조용히 증발하고
			화면에는 "상대를 찾는 중" 만 남았다 — 본인은 이유를 알 수 없고, 나중에 들어온
			상대와도 영영 안 붙는다.

			친구가 먼저 큐를 누르고 내가 2분 뒤에 들어오면 바로 이 상황이다.
		]]
		local world = Roblox.newWorld({ studio = false })

		local alpha = world:newServer({ jobId = "job-alpha" }):boot()
		local kim = alpha:addPlayer("Kim")
		world:advance(2)

		clickQueue(kim)
		world:advance(150) -- TTL 의 한참 뒤

		local beta = world:newServer({ jobId = "job-beta" }):boot()
		local lee = beta:addPlayer("Lee")
		world:advance(2)
		clickQueue(lee)
		world:advance(10)
		assertNoErrors(world, "오래 기다린 뒤 매칭")

		t:eq(#world.teleports, 2, "먼저 와서 오래 기다린 사람이 매칭돼야 합니다")
		t:truthy(Screen.hasText(guiOf(kim), "턴 "), "Kim 에게 전투 화면이 떠야 합니다")
		t:truthy(Screen.hasText(guiOf(lee), "턴 "), "Lee 에게 전투 화면이 떠야 합니다")
	end)

	t:it("짝이 성사된 직후 한 명이 나가면 남은 쪽은 큐로 돌아온다", function()
		local world = Roblox.newWorld({ studio = false })

		local alpha = world:newServer({ jobId = "job-alpha" }):boot()
		local beta = world:newServer({ jobId = "job-beta" }):boot()

		local kim = alpha:addPlayer("Kim")
		local lee = beta:addPlayer("Lee")
		world:advance(2)

		clickQueue(kim)
		clickQueue(lee)

		world:advance(2.1) -- 짝은 지어졌고 텔레포트가 걸리기 직전
		alpha:removePlayer(kim)

		world:advance(40) -- 대전 서버 대기 한도(30초)를 넘긴다
		assertNoErrors(world, "짝 상대 이탈")

		-- 부전승을 주지 않는다. 텔레포트 실패와 구분할 방법이 없기 때문이다.
		t:falsy(Screen.hasText(guiOf(lee), "승리"), "안 온 상대에게 이겼다고 하면 안 됩니다")
		t:truthy(Screen.hasText(guiOf(lee), "상대를 찾는 중"), "다시 큐에 서 있어야 합니다")
	end)

	t:it("대전 서버는 매칭 없이 들어온 사람을 돌려보낸다", function()
		local world = Roblox.newWorld({ studio = false })
		world:newServer({ jobId = "job-alpha" }):boot() -- 돌아갈 공개 서버

		local arena = world:newServer({ reserved = true, jobId = "job-arena" }):boot()
		arena:addPlayer("Stranger")
		world:advance(2)
		assertNoErrors(world, "예약 서버 직접 입장")

		t:eq(#arena.players, 0, "도착 데이터 없이 들어온 사람은 로비로 돌려보내야 합니다")
	end)
end)

--==========================================================================
-- 화면 배율
--==========================================================================

t:describe("화면 배율", function()
	--[[
		레이아웃이 고정 픽셀이라 창 높이에 따라 예산이 무너진다. UIScale 로 root 안쪽을
		항상 "세로 900 짜리 화면" 으로 만들어 그 문제를 없앴다 — 여기서 그게 실제로
		걸리는지 본다. Studio 를 켜서 창을 줄여봐야만 알 수 있던 종류다.
	]]
	local function scaleFor(height)
		local world = Roblox.newWorld()
		local lobby = world:newServer({
			viewport = Roblox.Datatypes.Vector2.new(math.floor(height * 16 / 9), height),
		}):boot()

		local kim = lobby:addPlayer("Kim")
		world:advance(2)
		assertNoErrors(world, ("배율 %d"):format(height))

		local root = Screen.find(guiOf(kim), "Root")
		local scale = root:FindFirstChildOfClass("UIScale")
		return scale, root
	end

	t:it("작은 창은 화면을 줄여 배치를 지킨다", function()
		local scale = scaleFor(720)

		t:truthy(scale, "root 에 UIScale 이 붙어 있어야 합니다")
		t:eq(scale.Scale, 0.8, "720 / 900 = 0.8")
	end)

	t:it("기준 크기에서는 배율이 1 이다", function()
		local scale = scaleFor(900)
		t:eq(scale.Scale, 1)
	end)

	t:it("큰 모니터에서는 화면을 키운다", function()
		local scale = scaleFor(1440)
		t:eq(scale.Scale, 1.5, "상한 1.5 에 걸려야 합니다")
	end)

	t:it("root 크기가 배율을 되돌린다", function()
		-- UIScale 은 자식의 scale 성분까지 곱한다. root 를 1/배율로 잡지 않으면
		-- 가로 전체 위젯이 화면 밖으로 삐져나간다.
		local scale, root = scaleFor(720)

		t:eq(root.Size.X.Scale, 1 / scale.Scale)
		t:eq(root.Size.Y.Scale, 1 / scale.Scale)
	end)
end)

--==========================================================================
-- 덱 편집 · 저장
--==========================================================================

--[[
	덱은 DataStore 에 저장되고, 다음 판은 그 덱으로 열린다.
	Studio 에서는 API 접근이 꺼져 있으면 저장 자체가 안 되므로, 게시하기 전에
	여기서 "눌러서 저장되고 그 덱으로 판이 열리는가" 까지 확인해둔다.
]]
t:describe("덱 편집", function()
	local function openEditor()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "덱 편집"))
		world:advance(1)
		assertNoErrors(world, "덱 편집 열기")

		return world, lobby, kim
	end

	t:it("시작 화면에서 덱 편집을 열 수 있다", function()
		local _, _, kim = openEditor()
		local gui = guiOf(kim)

		t:truthy(Screen.hasText(gui, "덱 편집"), "덱 편집 화면이 떠야 합니다")
		t:truthy(Screen.hasText(gui, "60 / 60 장"), "저장된 덱(스타터 60장)이 채워져 있어야 합니다")
		t:truthy(Screen.countNamed(gui, "Card_") > 30, "카드 목록이 그려져야 합니다")
	end)

	t:it("60장이 아니면 저장할 수 없다", function()
		local world, _, kim = openEditor()

		-- 덱 쪽 목록에서 한 장 뺀다.
		local deckList = Screen.find(guiOf(kim), "Deck")
		local row = Screen.findNamed(deckList, "Card_")
		Screen.click(row)
		world:advance(0.5)

		t:truthy(Screen.hasText(guiOf(kim), "59 / 60 장"), "한 장 빠져야 합니다")

		local save = Screen.findButton(guiOf(kim), "저장")
		t:falsy(save and save.Active, "60장이 아니면 저장이 꺼져 있어야 합니다")
	end)

	t:it("저장한 덱으로 다음 판이 열린다", function()
		local world, _, kim = openEditor()

		-- 스타터에 없는 카드(초소병)를 넣고 그만큼 코스트를 뺀다.
		local catalog = Screen.find(guiOf(kim), "Catalog")
		local deckList = Screen.find(guiOf(kim), "Deck")

		Screen.click(Screen.findNamed(deckList, "Card_COST_BASIC"))
		world:advance(0.2)
		Screen.click(Screen.findNamed(catalog, "Card_CRE_SENTRY"))
		world:advance(0.2)

		t:truthy(Screen.hasText(guiOf(kim), "60 / 60 장"), "다시 60장이어야 합니다")

		Screen.click(Screen.findButton(guiOf(kim), "저장"))
		world:advance(1)
		assertNoErrors(world, "덱 저장")
		t:truthy(Screen.hasText(guiOf(kim), "저장했습니다"), "저장 결과를 알려줘야 합니다")

		--[[
			화면 문구만 보면 "저장했다고 말하는 것" 까지밖에 확인이 안 된다.
			실제로 저장소에 들어갔는지를 저장된 값에서 직접 본다.
		]]
		local stored = world.dataStores["PlayerDecks_v1"][("user_%d"):format(kim.UserId)]
		t:truthy(stored, "DataStore 에 덱이 들어가야 합니다")

		local savedSentry
		for _, entry in stored do
			if entry.id == "CRE_SENTRY" then
				savedSentry = entry.count
			end
		end
		t:eq(savedSentry, 1, "방금 넣은 카드가 저장돼야 합니다")

		Screen.click(Screen.findButton(guiOf(kim), "돌아가기"))
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		assertNoErrors(world, "저장한 덱으로 대전")

		t:truthy(passMulligan(world, kim), "멀리건 관문을 통과하지 못했습니다")
		t:truthy(waitForButton(world, kim, "페이즈 종료"), "판이 시작돼야 합니다")
	end)

	t:it("다시 열면 저장한 덱이 그대로 있다", function()
		local world, _, kim = openEditor()

		local catalog = Screen.find(guiOf(kim), "Catalog")
		local deckList = Screen.find(guiOf(kim), "Deck")
		Screen.click(Screen.findNamed(deckList, "Card_COST_BASIC"))
		world:advance(0.2)
		Screen.click(Screen.findNamed(catalog, "Card_CRE_SENTRY"))
		world:advance(0.2)
		Screen.click(Screen.findButton(guiOf(kim), "저장"))
		world:advance(1)

		Screen.click(Screen.findButton(guiOf(kim), "돌아가기"))
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "덱 편집"))
		world:advance(1)

		local deckAgain = Screen.find(guiOf(kim), "Deck")
		t:truthy(
			Screen.findNamed(deckAgain, "Card_CRE_SENTRY"),
			"저장한 카드가 다시 열었을 때도 있어야 합니다"
		)
	end)

	--[[
		목록은 스크롤 영역보다 길다(카드 32종). UIListLayout 이 세로 가운데 정렬이면
		내용이 위아래로 똑같이 넘쳐서 **맨 위가 잘리고 스크롤로도 못 올라간다.**
		실제로 그렇게 나와 있었다 — 생물 목록의 첫 줄이 안 보였다.

		잘림 자체는 이 하네스가 레이아웃을 계산하지 않아 못 잰다. 대신 원인이었던
		설정을 못 박는다.
	]]
	t:it("목록은 위에서부터 쌓인다", function()
		local _, _, kim = openEditor()

		for _, panelName in { "Catalog", "Deck" } do
			local list = Screen.find(Screen.find(guiOf(kim), panelName), "List")
			local layout

			for _, child in list:GetChildren() do
				if child.ClassName == "UIListLayout" then
					layout = child
				end
			end

			t:truthy(layout, ("%s 목록에 UIListLayout 이 없습니다"):format(panelName))
			t:eq(
				tostring(layout.VerticalAlignment),
				tostring(Roblox.Datatypes.Enum.VerticalAlignment.Top),
				("%s 목록이 가운데 정렬이면 맨 위가 잘린다"):format(panelName)
			)
		end
	end)

	t:it("카드를 오른쪽 클릭하면 자세히 보여준다", function()
		local world, _, kim = openEditor()
		local gui = guiOf(kim)

		local hawk = Screen.findNamed(Screen.find(gui, "Catalog"), "Card_CRE_HAWK")
		t:truthy(hawk, "카드 목록에 창공의 매가 있어야 합니다")

		Screen.rightClick(hawk)
		world:advance(0.2)
		assertNoErrors(world, "카드 상세")

		-- 창공의 매: 2코 2/1 비행
		t:truthy(Screen.hasText(gui, "창공의 매"), "카드 이름")
		t:truthy(Screen.hasText(gui, "공격력 2"), "공격력")
		t:truthy(Screen.hasText(gui, "생명력 1"), "생명력")
		t:truthy(Screen.hasText(gui, "코스트 2"), "코스트")
		t:truthy(Screen.hasText(gui, "비행"), "태그")
		t:truthy(Screen.hasText(gui, "내 덱에 3장"), "내 덱에 몇 장인지")
	end)

	t:it("상세를 열어둔 채 카드를 넣으면 숫자가 따라간다", function()
		local world, _, kim = openEditor()
		local gui = guiOf(kim)

		local catalog = Screen.find(gui, "Catalog")
		Screen.rightClick(Screen.findNamed(catalog, "Card_CRE_HAWK"))
		world:advance(0.2)
		t:truthy(Screen.hasText(gui, "내 덱에 3장"))

		-- 한 장 빼서 자리를 만들고 매를 한 장 더 넣는다.
		Screen.click(Screen.findNamed(Screen.find(gui, "Deck"), "Card_COST_BASIC"))
		world:advance(0.2)
		Screen.click(Screen.findNamed(Screen.find(gui, "Catalog"), "Card_CRE_HAWK"))
		world:advance(0.2)

		t:truthy(Screen.hasText(gui, "내 덱에 4장"), "열어둔 상세도 같이 갱신돼야 합니다")
	end)

	t:it("상세는 닫을 수 있고, 화면을 다시 열면 닫혀 있다", function()
		local world, _, kim = openEditor()
		local gui = guiOf(kim)

		Screen.rightClick(Screen.findNamed(Screen.find(gui, "Catalog"), "Card_CRE_HAWK"))
		world:advance(0.2)
		t:truthy(Screen.hasText(gui, "창공의 매"))

		Screen.click(Screen.findButton(gui, "닫기"))
		world:advance(0.2)
		t:falsy(Screen.hasText(gui, "공격력 2"), "닫으면 안 보여야 합니다")
	end)

	t:it("스타터 덱으로 되돌릴 수 있다", function()
		local world, _, kim = openEditor()

		local deckList = Screen.find(guiOf(kim), "Deck")
		Screen.click(Screen.findNamed(deckList, "Card_COST_BASIC"))
		world:advance(0.2)

		Screen.click(Screen.findButton(guiOf(kim), "스타터 덱으로"))
		world:advance(1)
		assertNoErrors(world, "스타터 덱으로")

		t:truthy(Screen.hasText(guiOf(kim), "60 / 60 장"))
		t:truthy(Screen.hasText(guiOf(kim), "되돌"), "결과를 알려줘야 합니다")
	end)
end)

--==========================================================================
-- 멀리건 관문
--==========================================================================

--[[
	무료 1회 전체 교체. 룰 자체는 tests/specs/mulligan.luau 가 보고,
	여기서는 "화면에 실제로 뜨고 눌리는가" 만 본다.
]]
t:describe("멀리건 관문", function()
	local function practice()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		assertNoErrors(world, "AI 연습 시작")

		return world, kim
	end

	t:it("판이 시작되기 전에 손패와 두 버튼이 뜬다", function()
		local world, kim = practice()
		local gui = guiOf(kim)

		t:eq(Screen.countNamed(gui, "Hand_"), 7, "관문에서도 손패가 보여야 고를 수 있습니다")

		local mulliganButton = Screen.findButton(gui, "손패 물리기")
		local keepButton = Screen.findButton(gui, "이대로 시작")
		t:truthy(mulliganButton and mulliganButton.Active, "'손패 물리기' 가 눌려야 합니다")
		t:truthy(keepButton and keepButton.Active, "'이대로 시작' 이 눌려야 합니다")

		local endPhase = Screen.findButton(gui, "페이즈 종료")
		t:falsy(endPhase and endPhase.Active, "관문에서는 판이 굴러가면 안 됩니다")
		t:eq(world:errors()[1], nil)
	end)

	t:it("이대로 시작을 누르면 판이 굴러간다", function()
		local world, kim = practice()

		t:truthy(passMulligan(world, kim), "'이대로 시작' 이 눌려야 합니다")
		assertNoErrors(world, "관문 통과")

		-- 선공이 AI 면 AI 가 1턴을 다 두고 나서야 내 차례가 온다.
		t:truthy(
			waitForButton(world, kim, "페이즈 종료"),
			"판이 시작되면 언젠가는 내 차례가 와야 합니다"
		)

		-- 후공이면 자기 턴 드로우로 한 장 늘어 있다.
		local hand = Screen.countNamed(guiOf(kim), "Hand_")
		t:truthy(hand == 7 or hand == 8, ("손패가 %d 장입니다"):format(hand))
	end)

	t:it("물리면 손패가 새로 오고 판이 시작된다", function()
		local world, kim = practice()

		Screen.click(Screen.findButton(guiOf(kim), "손패 물리기"))
		world:advance(1.5)
		assertNoErrors(world, "손패 물리기")

		t:eq(Screen.countNamed(guiOf(kim), "Hand_"), 7, "같은 장수를 다시 뽑습니다")

		-- 무료 1회다 — 물린 자리에서 결정이 끝나므로 관문 버튼은 더 이상 눌리지 않는다.
		local mulliganButton = Screen.findButton(guiOf(kim), "손패 물리기")
		t:falsy(mulliganButton and mulliganButton.Active, "두 번째 물리기는 없습니다")

		t:truthy(waitForButton(world, kim, "페이즈 종료"), "물린 뒤에는 판이 시작돼야 합니다")
	end)
end)

--==========================================================================
-- 대기 타이머
--==========================================================================

--[[
	타이머가 클라이언트 시계를 서버 시각과 빼면, 기기 시계가 어긋난 사람은
	0:00 에 멈추거나 처음부터 몇 분이 찍힌다. 하네스는 두 시계가 같으므로 그 증상을
	직접 재현할 수 없다 — 대신 **애초에 뺄 수 없게 되어 있는가**(시각이 아니라 경과 초를
	보내는가)를 못 박는다.
]]
t:describe("대기 타이머", function()
	local function queuedPayloads()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		local seen = {}
		lobby.remotes.Lobby._clientSignalFor(kim):Connect(function(payload)
			if type(payload) == "table" and payload.screen == "queued" then
				table.insert(seen, payload)
			end
		end)

		clickQueue(kim)
		world:advance(2)

		return world, lobby, kim, seen
	end

	t:it("서버는 시각이 아니라 경과 초를 보낸다", function()
		local world, _, _, seen = queuedPayloads()
		assertNoErrors(world, "큐 등록")

		t:truthy(#seen > 0, "대기 화면 payload 를 받지 못했습니다")
		t:eq(seen[1].since, nil, "시각을 보내면 클라이언트가 두 시계를 빼게 된다")
		t:eq(seen[1].elapsed, 0, "막 등록했으니 0 초")
	end)

	t:it("기다린 만큼 화면에 찍힌다", function()
		local world, _, kim = queuedPayloads()

		world:advance(65)
		assertNoErrors(world, "대기 중")

		t:truthy(Screen.hasText(guiOf(kim), "1:0"), "1분 넘게 기다렸으면 1:0x 가 보여야 합니다")
	end)

	t:it("화면을 다시 받아도 0:00 으로 돌아가지 않는다", function()
		local world, lobby, kim, seen = queuedPayloads()

		world:advance(65)
		-- 클라이언트가 다시 뜬 것처럼 hello 를 보낸다 (서버가 현재 화면을 다시 내려준다).
		lobby.remotes.Lobby._serverSignal:Fire(kim, { kind = "hello" })
		world:advance(1)
		assertNoErrors(world, "hello 재전송")

		local last = seen[#seen]
		t:truthy(last.elapsed >= 65, ("이미 기다린 시간을 잃었습니다: %s"):format(tostring(last.elapsed)))
	end)
end)

--==========================================================================
-- 하네스 자체 검증
--==========================================================================

--[[
	위의 테스트들이 믿을 만한지는 하네스가 진짜처럼 답하는지에 달려 있다.
	세 가지는 실제로 어긋나 있었고, 전부 **초록불을 잘못 주는** 쪽이었다 —
	그래서 게임 코드보다 여기가 더 위험하다. 다시 어긋나지 않게 못 박아둔다.
]]
t:describe("하네스가 진짜처럼 답하는가", function()
	t:it("PublishAsync 는 게시한 서버 자신에게도 배달한다", function()
		local world = Roblox.newWorld({ studio = false })
		local alpha = world:newServer({ jobId = "job-alpha" }):boot()
		local beta = world:newServer({ jobId = "job-beta" }):boot()

		local heard = {}
		for _, server in { alpha, beta } do
			local messaging = server:service("MessagingService", server.serverVm)
			messaging:SubscribeAsync("probe", function(message)
				table.insert(heard, ("%s:%s"):format(server.jobId, tostring(message.Data.from)))
			end)
		end

		local messaging = alpha:service("MessagingService", alpha.serverVm)
		messaging:PublishAsync("probe", { from = "alpha" })
		world:advance(1)

		t:truthy(
			table.find(heard, "job-alpha:alpha"),
			"게시한 서버 자신이 못 받으면 CrossServer 의 origin 에코 가드가 한 번도 안 돈다"
		)
		t:truthy(table.find(heard, "job-beta:alpha"), "다른 서버도 받아야 합니다")
	end)

	t:it("MemoryStore 큐는 값을 복사해 담는다", function()
		local world = Roblox.newWorld({ studio = false })
		local server = world:newServer():boot()

		local queue = server:service("MemoryStoreService", server.serverVm):GetQueue("probe", 30)
		local entry = { token = "t1", name = "Kim" }
		queue:AddAsync(entry, 30)

		-- 넣은 뒤 로컬 사본을 고친다. 진짜 MemoryStore 는 직렬화해서 담으므로
		-- 큐 안의 값은 그대로여야 한다.
		entry.name = "고쳐짐"

		local values = queue:ReadAsync(1, false, 0)
		t:eq(values[1].name, "Kim", "큐가 참조를 들고 있으면 여기서 '고쳐짐' 이 나온다")

		values[1].name = "또 고쳐짐"
		local again = server:service("MemoryStoreService", server.serverVm):GetQueue("probe", 30)
		t:eq(again.items[1].value.name, "Kim", "읽어간 값을 고쳐도 큐 안은 그대로여야 합니다")
	end)

	t:it("담을 수 없는 값은 거절한다", function()
		local world = Roblox.newWorld({ studio = false })
		local server = world:newServer():boot()

		local queue = server:service("MemoryStoreService", server.serverVm):GetQueue("probe", 30)
		local ok = pcall(function()
			queue:AddAsync({ callback = function() end }, 30)
		end)

		t:falsy(ok, "함수가 든 값은 진짜 MemoryStore 도 거절합니다")
	end)

	t:it("FireClient 는 첫 인자가 Player 가 아니면 에러", function()
		local world = Roblox.newWorld({ studio = false })
		local server = world:newServer():boot()

		-- `Notice:FireClient(text, kind)` 처럼 player 를 빠뜨린 호출.
		local ok, err = pcall(function()
			server.remotes.Notice:FireClient("상대가 나갔습니다", "warn")
		end)

		t:falsy(ok, "player 를 빠뜨린 호출이 조용히 통과하면 안 됩니다")
		t:truthy(tostring(err):find("Player"), "무엇이 잘못됐는지 말해줘야 합니다")
	end)

	t:it("PlayerRemoving 은 아직 Players 에 있는 채로 돈다", function()
		local world = Roblox.newWorld({ studio = false })
		local server = world:newServer():boot()

		local kim = server:addPlayer("Kim")
		world:advance(1)

		local sawInList, sawParent = false, false
		server.playersService.PlayerRemoving:Connect(function(player)
			sawParent = player.Parent == server.playersService
			for _, existing in server.playersService:GetPlayers() do
				if existing == player then
					sawInList = true
				end
			end
		end)

		server:removePlayer(kim)

		t:truthy(sawParent, "핸들러 안에서는 아직 Players 의 자식이어야 합니다")
		t:truthy(sawInList, "GetPlayers 에도 아직 있어야 합니다 (나가는 사람을 세는 코드가 있다)")
	end)

	t:it("예약 서버 코드는 겹치지 않는다", function()
		local world = Roblox.newWorld({ studio = false })
		local server = world:newServer():boot()
		local teleport = server:service("TeleportService", server.serverVm)

		local seen = {}
		for _ = 1, 200 do
			local code = teleport:ReserveServerAsync(0)
			t:falsy(seen[code], ("접근 코드가 겹쳤습니다: %s"):format(tostring(code)))
			seen[code] = true
		end
	end)

	t:it("나간 사람에게는 FireAllClients 가 가지 않는다", function()
		local world = Roblox.newWorld({ studio = false })
		local server = world:newServer():boot()

		local kim = server:addPlayer("Kim")
		world:advance(1)

		-- 클라이언트 프록시가 OnClientEvent 를 얻는 것과 같은 경로다.
		local got = 0
		server.remotes.Notice._clientSignalFor(kim):Connect(function()
			got += 1
		end)

		server.remotes.Notice:FireAllClients("hello")
		t:eq(got, 1, "있는 사람은 받아야 합니다")

		server:removePlayer(kim)
		server.remotes.Notice:FireAllClients("hello")
		t:eq(got, 1, "나간 사람에게 계속 쏘면 하네스에만 있는 유령 수신자가 남는다")
	end)
end)

--==========================================================================

print("")
process.exit(t:report() and 0 or 1)
