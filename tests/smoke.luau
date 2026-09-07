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
	Studio 라면 출력창에 빨간 줄로 떴을 오류를 테스트 실패로 바꾼다.
	이게 이 파일의 존재 이유다.
]]
local function assertNoErrors(world, label)
	local errors = world:errors()
	if #errors > 0 then
		error(("%s — 런타임 오류 %d건:\n  %s"):format(label, #errors, table.concat(errors, "\n  ")), 2)
	end
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

	t:it("같은 매치 시드를 들고 도착한다", function()
		local world = select(1, matchAcrossServers())

		t:eq(
			world.teleports[1].data.seed,
			world.teleports[2].data.seed,
			"시드가 다르면 두 사람이 서로 다른 셔플을 보게 됩니다"
		)
		t:eq(world.teleports[1].data.matchId, world.teleports[2].data.matchId)
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

	t:it("대전 서버는 매칭 없이 들어온 사람을 돌려보낸다", function()
		local world = Roblox.newWorld({ studio = false })
		world:newServer({ jobId = "job-alpha" }):boot() -- 돌아갈 공개 서버

		local arena = world:newServer({ reserved = true, jobId = "job-arena" }):boot()
		local stranger = arena:addPlayer("Stranger")
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

print("")
process.exit(t:report() and 0 or 1)
