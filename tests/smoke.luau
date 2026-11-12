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
--[[
	기다리는 동안 대응 창이 열리면 넘긴다.

	상대가 카드를 낼 때마다 스택이 올라가고, **서버는 사람이 [대응 패스] 를 누를 때까지
	기다린다**(Config.autoPassWithNoResponse = false). 화면 앞에 앉은 사람은 그걸 보고
	누르므로, 여기 학생도 그렇게 한다. 안 그러면 어떤 테스트도 두 턴을 못 넘긴다.
]]
--[[
	이름이 prefix 로 시작하는 노드 전부. Screen.findNamed 는 첫 하나만 준다.
]]
local function allNamedIn(root, prefix)
	local out = {}
	local function walk(node)
		if node.Name:sub(1, #prefix) == prefix then
			table.insert(out, node)
		end
		for _, child in node:GetChildren() do
			walk(child)
		end
	end
	walk(root)
	return out
end

--[[
	지금 낼 수 있어 보이는 손패 카드. **흐린 카드는 세지 않는다** —
	코치가 잠근 카드와 코스트가 모자란 카드가 그렇게 그려진다(CardView 의 dim).
]]
local function brightHandCard(player)
	for _, node in allNamedIn(guiOf(player), "Hand_") do
		if node.BackgroundTransparency < 0.4 then
			return node
		end
	end
	return nil
end

--[[
	이 태그를 단 카드가 지금 화면에 있는가.

	카드 위의 태그 칩은 이름만 딱 적혀 있다(CardView 의 keywordRow). 그래서
	**정확히 일치**로 찾는다 — 카드 설명문에도 "비행 — 지상 생물은…" 처럼 그 낱말이
	들어 있어서, 부분 일치로 찾으면 설명문만 보고도 있다고 착각한다.
]]
local function hasKeywordChip(player, name)
	for _, text in Screen.visibleTexts(guiOf(player)) do
		if text == name then
			return true
		end
	end
	return false
end

--[[
	내 생물을 눌러 보고, 화면이 대상을 물으면 골라준다.
	공격이면 상대 자신을, 방어면 아무 공격자나 고른다. -> 눌렀나
]]
--[[
	화면 가운데 안내문. **코치 말풍선과 구별해서** 읽어야 한다 —
	코치도 "막을 공격자를 고르세요" 라고 말하기 때문에, 화면 전체에서 글자를 찾으면
	아무것도 안 고르고 있을 때도 고르는 중이라고 착각한다.
]]
local function promptText(player)
	local node = Screen.find(guiOf(player), "Prompt")
	return node and node.Text or ""
end

--[[
	초록으로 켜진 카드인가. (CardView.outlineFor — 켜진 카드만 테두리가 두껍다)

	**여기가 이 테스트의 핵심이다.** 학생은 화면에서 켜진 것만 누른다. 켜졌는데
	눌러보니 서버가 거부하면 그건 화면이 거짓말을 한 것이고, 학생은 그 자리에서
	맴돌다 "진도가 안 나갔습니다" 로 실패한다.
]]
local function isLit(node)
	local stroke = node:FindFirstChildOfClass("UIStroke")
	return stroke ~= nil and stroke.Thickness >= 4
end

-- 플레이어 패널은 테두리가 2.5 로 켜진다 (renderPlayerPanel)
local function isPanelLit(panel)
	local stroke = panel and panel:FindFirstChildOfClass("UIStroke")
	return stroke ~= nil and stroke.Thickness > 1
end

local function litCards(root)
	local out = {}
	for _, node in allNamedIn(root, "Field_") do
		if isLit(node) then
			table.insert(out, node)
		end
	end
	return out
end

--[[
	판이 끝났는가. -> "승리" | "패배" | nil

	화면 전체에서 "승리" 를 찾으면 안 된다 — 코치 말풍선이 "상대 라이프를 0 으로
	만들면 승리예요" 라고 말하는 순간 이겼다고 착각한다. 결과 오버레이 안에서만 본다.
]]
local function outcome(player)
	local overlay = Screen.find(guiOf(player), "EndOverlay")
	if not overlay or not overlay.Visible then
		return nil
	end
	return Screen.hasText(overlay, "승리") and "승리" or "패배"
end

local function activeButton(player, text)
	local button = Screen.findButton(guiOf(player), text)
	if button and button.Active then
		return button
	end
	return nil
end

--[[
	마법을 내면 화면이 대상을 물어본다. 켜진 것 중 아무거나 골라준다.
	고를 게 없으면 선택을 되돌린다 — 여기서 안 빠져나오면 그 다음 클릭이 전부
	"대상 고르기" 로 먹혀서, 학생이 조용히 굳는다.
]]
local function answerTargetPrompt(world, player)
	local gui = guiOf(player)

	--[[
		**창이 닫힐 때까지** 고른다. 한 번만 고르고 나오면 안 된다 — 효과가 둘인 마법은
		대상도 둘을 묻기 때문이다(돌격 나팔 = +2/+0 과 신속 부여, "(2/2)" 로 표시된다).
		열린 채로 두면 그 다음 클릭이 전부 대상 고르기로 먹혀서, 자동 조작은 같은 카드를
		무한히 다시 내고 판은 영영 안 끝난다 — 캠페인 재도전 테스트가 3000번을 눌러도
		끝나지 않던 것이 이것이었다. 사람이라면 당연히 두 번째도 골랐을 자리다.
	]]
	for _ = 1, 6 do
		if not promptText(player):find("대상을 고르세요") then
			return
		end

		local picked = false

		for _, field in { "MyField", "FoeField" } do
			local node = litCards(Screen.find(gui, field))[1]
			if node then
				Screen.click(node)
				world:advance(0.4)
				picked = true
				break
			end
		end

		if not picked then
			local foePanel = Screen.find(gui, "FoePanel")
			if isPanelLit(foePanel) then
				Screen.click(foePanel:FindFirstChild("Hit"))
				world:advance(0.4)
				picked = true
			end
		end

		-- 고를 것이 없다. 되돌리지 않으면 여기서 굳는다.
		if not picked then
			local cancel = activeButton(player, "선택 취소")
			if cancel then
				Screen.click(cancel)
				world:advance(0.2)
			end
			return
		end
	end
end


--[[
	항복은 **두 번** 눌러야 나간다. 판을 통째로 끝내는 유일한 버튼이라 글자가
	"정말 항복?" 으로 바뀌고, 그 상태에서 다시 눌러야 실제로 나간다.
]]
local function concede(world, player)
	local first = Screen.findButton(guiOf(player), "항복")
	t:truthy(first, "[항복] 버튼이 있어야 합니다")
	Screen.click(first)
	world:advance(0.2)

	local again = Screen.findButton(guiOf(player), "정말 항복?")
	t:truthy(again, "항복을 한 번 누르면 되물어야 합니다")
	Screen.click(again)
end

--[[
	대응 패스 버튼은 없앴다. 대응 창은 보드 가운데 스택 상자에서 넘긴다 —
	한 번 눌러 확인을 띄우고, 다시 눌러야 넘어간다.
]]
-- 지금 대응을 넘길 수 있는 상자. 못 넘기는 동안에는 상자가 꺼져 있다.
local function respondBox(player)
	local box = Screen.findNamed(guiOf(player), "StackBox")
	if box and box.Active ~= false then
		return box
	end
	return nil
end

-- 상대가 무언가 낼 때까지 턴을 굴린다.
local function openResponse(world, player)
	for _ = 1, 40 do
		if respondBox(player) then
			return true
		end
		local endPhase = activeButton(player, "페이즈 종료")
		if endPhase then
			Screen.click(endPhase)
		end
		world:advance(1)
	end
	return false
end

local function passIfResponding(world, player)
	local box = Screen.findNamed(guiOf(player), "StackBox")
	if not box or box.Active == false then
		return false
	end

	Screen.click(box)
	world:advance(0.3)

	local asking = Screen.findNamed(guiOf(player), "StackBox")
	if asking and asking.Active ~= false then
		Screen.click(asking)
		world:advance(0.3)
	end
	return true
end

local function waitForButton(world, player, text, budget)
	local waited = 0
	while waited <= (budget or 30) do
		local button = Screen.findButton(guiOf(player), text)
		if button and button.Active then
			return button
		end
		passIfResponding(world, player)
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
--[[
	켜진 내 생물을 눌러, 화면이 대상을 물으면 골라준다. -> 눌렀나
	공격이면 상대 자신을, 방어면 켜진 공격자를 고른다.
]]
local function tryCreature(world, player)
	local gui = guiOf(player)
	local myField = Screen.find(gui, "MyField")
	if not myField then
		return false
	end

	for _, node in litCards(myField) do
		Screen.click(node)
		world:advance(0.3)

		if promptText(player):find("공격할 대상") then
			local hit = Screen.find(gui, "FoePanel"):FindFirstChild("Hit")
			Screen.click(hit)
			world:advance(0.6)
			return true
		end

		if promptText(player):find("막을 공격자") then
			local attacker = litCards(Screen.find(gui, "FoeField"))[1]
			if attacker then
				Screen.click(attacker)
				world:advance(0.6)
				return true
			end
		end

		local cancel = activeButton(player, "선택 취소")
		if cancel then
			Screen.click(cancel)
			world:advance(0.2)
		end
	end

	return false
end

--[[
	"지금 눌리는 것" 을 하나 누른다. -> 눌렀나

	순서는 사람이 할 법한 순서다 — 손패를 내고, 공격하고, 페이즈를 넘긴다.
]]
local function pressSomething(world, player)
	local keep = activeButton(player, "이대로 시작")
	if keep then
		Screen.click(keep)
		world:advance(0.6)
		return true
	end

	-- 상대가 카드를 내면 대응 창이 열린다. 넘기지 않으면 판이 거기서 멈춘다.
	if passIfResponding(world, player) then
		return true
	end

	local card = brightHandCard(player)
	if card then
		Screen.click(card)
		world:advance(0.6)
		answerTargetPrompt(world, player)
		return true
	end

	if tryCreature(world, player) then
		return true
	end

	local endPhase = activeButton(player, "페이즈 종료")
	if endPhase then
		Screen.click(endPhase)
		world:advance(0.8)
		return true
	end

	world:advance(0.6) -- 상대가 두는 중
	return false
end

local TAG_NAMES = { "도발", "비행", "원거리", "신속", "즉시시전" }


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
			-- 상대가 소환할 때마다 대응 창이 열린다. 넘기지 않으면 판이 멈춘다.
			passIfResponding(world, kim)

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

	--[[
		상대가 카드를 내면 스택에 올라가고 나에게 대응 창이 열린다.
		**대응할 카드가 하나도 없어도 사람이 직접 넘겨야 넘어간다.**

		예전에는 서버가 대신 눌러줬다. 버튼만 누르게 하지 말자는 뜻이었는데, 실제로는
		상대가 무엇을 시전했는지 읽기도 전에 화면이 지나갔다.
	]]
	t:it("넘기기 전에는 대응 창이 저 혼자 닫히지 않는다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		t:truthy(passMulligan(world, kim), "멀리건 관문을 통과하지 못했습니다")
		t:truthy(openResponse(world, kim), "상대가 카드를 내면 대응 창이 열려야 합니다")
		assertNoErrors(world, "대응 창")

		-- 가만히 둬도 저 혼자 넘어가면 안 된다.
		world:advance(10)
		t:truthy(respondBox(kim), "누르기 전에 넘어갔습니다")
		t:falsy(activeButton(kim, "페이즈 종료"), "대응 창이 열린 동안에는 페이즈를 넘길 수 없어야 합니다")

		t:truthy(passIfResponding(world, kim), "상자를 눌러 넘길 수 있어야 합니다")
		world:advance(2)
		assertNoErrors(world, "대응 넘기기")
		t:falsy(respondBox(kim), "넘기면 대응 창이 닫혀야 합니다")
	end)

	--[[
		대응 창은 보드 한가운데서 열리는데 [대응 패스] 는 행동 바(오른쪽 끝)에 있다.
		매번 눈과 손이 화면을 가로지르는 것이라, **스택 칩 자체를 눌러도** 넘어갈 수 있다.

		다만 곧장 넘기지는 않는다. 그 칩은 상대가 무엇을 냈는지 읽는 유일한 자리라,
		읽으려고 누른 사람이 대응 기회를 잃으면 자동 패스를 끈 이유가 사라진다.
	]]
	t:it("스택 상자를 눌러도 대응을 넘길 수 있다 — 확인을 한 번 거친다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		t:truthy(passMulligan(world, kim), "멀리건 관문을 통과하지 못했습니다")
		t:truthy(openResponse(world, kim), "상대가 카드를 내면 대응 창이 열려야 합니다")

		local box = Screen.findNamed(guiOf(kim), "StackBox")
		t:truthy(box, "스택에 올라간 카드가 상자로 그려져야 합니다")
		t:truthy(box.Text:find("누르면 대응을 넘깁니다"), "무엇을 하는 상자인지 적혀 있어야 합니다")

		Screen.click(box)
		world:advance(1)
		assertNoErrors(world, "스택 상자 누르기")

		local asking = Screen.findNamed(guiOf(kim), "StackBox")
		t:truthy(asking and asking.Text:find("다시 누르면"), "한 번 누르면 확인을 물어야 합니다")
		t:truthy(respondBox(kim), "확인하기 전에 넘어가면 안 됩니다")

		Screen.click(Screen.findNamed(guiOf(kim), "StackBox"))
		world:advance(2)
		assertNoErrors(world, "확인 누르기")
		t:falsy(respondBox(kim), "확인을 누르면 대응 창이 닫혀야 합니다")
	end)

	--[[
		상자가 상대가 무엇을 냈는지 읽는 유일한 자리다. 확인을 물으면서 이름을
		지우면, 읽으려던 사람이 무엇을 넘기는지 모르는 채 누르게 된다.
	]]
	t:it("확인을 묻는 중에도 무엇이 올라와 있는지 보인다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		t:truthy(passMulligan(world, kim), "멀리건 관문을 통과하지 못했습니다")
		t:truthy(openResponse(world, kim), "상대가 카드를 내면 대응 창이 열려야 합니다")

		local before = Screen.findNamed(guiOf(kim), "StackBox").Text
		local name = before:match("^(.-) %(")
		t:truthy(name and #name > 0, ("상자에 카드 이름이 있어야 합니다 — %s"):format(before))

		Screen.click(Screen.findNamed(guiOf(kim), "StackBox"))
		world:advance(1)

		local after = Screen.findNamed(guiOf(kim), "StackBox").Text
		t:truthy(after:find(name, 1, true), ("확인 중에도 이름이 남아야 합니다 — %s"):format(after))
		t:truthy(after:find("(상대)", 1, true), "누가 낸 것인지도 남아야 합니다")
	end)

	t:it("항복하면 결과 화면이 뜬다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)

		concede(world, kim)
		world:advance(2)
		assertNoErrors(world, "항복")

		local gui = guiOf(kim)
		t:truthy(Screen.hasText(gui, "패배"), "결과 화면이 떠야 합니다")
		t:truthy(Screen.findButton(gui, "다시 하기"), "연습이므로 '다시 하기' 가 있어야 합니다")
		t:truthy(Screen.findButton(gui, "로비로"), "연습이므로 '로비로' 가 있어야 합니다")
	end)

	--[[
		항복은 되돌릴 수 없는 유일한 버튼이다. 한 번 누르는 것으로 판이 끝나면
		손이 미끄러진 한 번과 정말 그만두려는 한 번을 화면이 구별하지 못한다.
	]]
	t:it("항복은 한 번 눌러서는 나가지 않는다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)

		Screen.click(Screen.findButton(guiOf(kim), "항복"))
		world:advance(2)
		assertNoErrors(world, "항복 한 번")

		t:falsy(outcome(kim), "한 번 눌렀다고 판이 끝나면 안 됩니다")
		t:truthy(Screen.findButton(guiOf(kim), "정말 항복?"), "되묻는 글자로 바뀌어야 합니다")

		-- 다른 것을 누르면 물어둔 것은 없던 일이 된다.
		local endPhase = activeButton(kim, "페이즈 종료")
		if endPhase then
			Screen.click(endPhase)
			world:advance(1)
			t:truthy(Screen.findButton(guiOf(kim), "항복"), "다른 것을 누르면 되묻기가 풀려야 합니다")
			t:falsy(outcome(kim), "페이즈를 넘겼는데 판이 끝났습니다")
		end
	end)

	--[[
		전체 기록은 [로그] 를 눌러야 열리는 덮개다. 그런데 코치는 "오른쪽 로그에
		무슨 일이 있었는지 남아요" 라고 말한다 — 열지 않아도 최근 두 줄은 보여야
		그 말이 참이 된다.
	]]
	t:it("행동 바에 최근 기록이 흐른다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		t:truthy(passMulligan(world, kim), "멀리건 관문을 통과하지 못했습니다")

		-- 몇 턴 굴려서 기록이 쌓이게 한다.
		for _ = 1, 6 do
			pressSomething(world, kim)
			local endPhase = activeButton(kim, "페이즈 종료")
			if endPhase then
				Screen.click(endPhase)
			end
			passIfResponding(world, kim)
			world:advance(1)
		end

		local mini = Screen.findNamed(guiOf(kim), "MiniLog")
		t:truthy(mini, "행동 바에 최근 기록 자리가 있어야 합니다")
		t:falsy(mini.Text:find("기록이 아직 없어요"), ("기록이 흘러야 합니다 — %s"):format(mini.Text))
		t:truthy(mini.Text:find("·", 1, true), "기록 줄이 적혀 있어야 합니다")

		-- 없앤 버튼이 되살아나지 않게 못 박는다.
		t:falsy(Screen.findButton(guiOf(kim), "대응 패스"), "대응 패스 버튼은 스택 상자로 옮겼습니다")
	end)

	--[[
		효과음은 업로드된 rbxassetid 가 있어야 난다. **비어 있는 것이 지금의 정상값**
		이므로, 소리가 없다고 판이 멈추거나 에러가 나면 안 된다.
		(무엇이 언제 울리는지는 tests/specs/sfx.luau 가 본다)
	]]
	t:it("소리를 안 올려도 판은 그대로 돈다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Roblox.takeSounds()

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		t:truthy(passMulligan(world, kim), "멀리건 관문을 통과하지 못했습니다")

		for _ = 1, 8 do
			pressSomething(world, kim)
			world:advance(1)
		end

		assertNoErrors(world, "무음 판")
		t:truthy(Screen.find(guiOf(kim), "Sfx"), "소리가 붙어 살 자리가 있어야 합니다")

		local rang = Roblox.takeSounds()
		t:eq(#rang, 0, ("에셋이 비어 있는데 소리가 났습니다 — %d건"):format(#rang))
	end)

	t:it("로비로 돌아가면 시작 화면이 다시 뜬다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		concede(world, kim)
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

		concede(world, kim)
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

	--------------------------------------------------------------------
	-- 승리 보상 (규칙은 tests/specs/campaign.luau 의 "PvP 승리 보상")
	--------------------------------------------------------------------

	local function progressOf(world, player)
		return world.dataStores["CampaignProgress_v1"][("user_%d"):format(player.UserId)]
	end

	t:it("들어오자마자 항복받은 승리는 보상이 없다", function()
		local world, _, kim, lee = matchTwo()

		concede(world, kim)
		world:advance(2)
		assertNoErrors(world, "바로 항복")

		t:truthy(Screen.hasText(guiOf(lee), "승리"))
		t:eq(progressOf(world, lee), nil, "부계정 농사를 막으려면 짧은 판은 아무것도 적지 않아야 합니다")
	end)

	t:it("몇 턴을 둔 판을 이기면 골드가 저장된다", function()
		local world, _, kim, lee = matchTwo()

		-- 양쪽이 페이즈만 넘기며 턴을 돌린다. 4 = Campaign.PvpReward.minTurns
		for _ = 1, 300 do
			if Screen.hasText(guiOf(kim), "턴 4") then
				break
			end
			local acted = false
			for _, player in { kim, lee } do
				passIfResponding(world, player)
				local endPhase = activeButton(player, "페이즈 종료")
				if endPhase then
					Screen.click(endPhase)
					world:advance(0.8)
					acted = true
				end
			end
			if not acted then
				world:advance(0.5)
			end
		end
		t:truthy(Screen.hasText(guiOf(kim), "턴 4"), "4턴까지 가야 합니다")

		concede(world, kim)
		world:advance(2)
		assertNoErrors(world, "4턴 뒤 항복")

		local stored = progressOf(world, lee)
		t:truthy(stored, "이긴 사람의 진행도가 저장돼야 합니다")
		t:eq(stored.gold, 25, "Campaign.PvpReward.gold")
		t:eq(stored.pvpWins, 1)
		t:eq(stored.cleared, 0, "캠페인 진도는 건드리지 않습니다")

		-- 랭크 (규칙은 tests/specs/rank.luau). 진 사람에게는 골드는 없고 랭크는 적힌다.
		t:eq(stored.rankPoints, 20, "이긴 사람의 랭크 점수가 올라야 합니다 (Rank.Points.win)")
		t:eq(stored.mmr, 1016, "같은 MMR 끼리면 k/2 = 16 이 오릅니다")
		t:eq(stored.rankedWins, 1)

		-- 순위표(정렬용 사본)에도 올라간다. 점수가 안 바뀐 쪽(0점에서 진 Kim)은 안 적는다.
		local board = world.orderedStores["RankLeaderboard_v1"] or {}
		t:eq(board[("user_%d"):format(lee.UserId)], 20, "이긴 사람이 순위표에 올라야 합니다")
		t:eq(board[("user_%d"):format(kim.UserId)], nil)

		local lost = progressOf(world, kim)
		t:truthy(lost, "진 사람에게도 랭크는 적혀야 합니다")
		t:eq(lost.gold, 0, "진 사람에게 골드는 없습니다")
		t:eq(lost.rankPoints, 0, "0점 아래로는 안 내려갑니다")
		t:eq(lost.mmr, 984)
		t:eq(lost.rankedLosses, 1)
	end)

	t:it("들어오자마자 항복해도 진 쪽 MMR 은 내려간다", function()
		local world, _, kim, lee = matchTwo()

		concede(world, kim)
		world:advance(2)
		assertNoErrors(world, "바로 항복 — 랭크")

		local lost = progressOf(world, kim)
		t:truthy(lost, "나가서 손해를 피하면 안 됩니다")
		t:eq(lost.mmr, 984)
		t:eq(lost.rankedLosses, 1)
		t:eq(progressOf(world, lee), nil, "이긴 쪽은 아무것도 적지 않습니다 (부계정 농사)")
		t:truthy(Screen.hasText(guiOf(lee), "랭크 점수가 오르지 않습니다"), "왜 안 올랐는지 알려줘야 합니다")
	end)

	t:it("판을 떠난 사람에게도 패배가 적힌다", function()
		local world, lobby, kim, lee = matchTwo()

		lobby:removePlayer(lee)
		world:advance(2)
		assertNoErrors(world, "이탈 — 랭크")

		local lost = progressOf(world, lee)
		t:truthy(lost, "나간 사람의 진행도에도 패배가 적혀야 합니다")
		t:eq(lost.rankedLosses, 1)
	end)
end)

--==========================================================================
-- 랭크 · 프로필
--==========================================================================

t:describe("랭크 · 프로필", function()
	local PROGRESS = "CampaignProgress_v1"

	local function storeProgress(world, player, progress)
		world.dataStores[PROGRESS] = world.dataStores[PROGRESS] or {}
		world.dataStores[PROGRESS][("user_%d"):format(player.UserId)] = progress
	end

	t:it("시작 화면에 티어와 랭크 점수가 뜬다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		storeProgress(world, kim, { cleared = 0, gold = 0, rankPoints = 245, mmr = 1100 })
		world:advance(2)
		assertNoErrors(world, "랭크 시작 화면")

		t:truthy(Screen.hasText(guiOf(kim), "실버 245점"), "시작 화면에 랭크가 떠야 합니다")
		t:falsy(Screen.hasText(guiOf(kim), "1100"), "MMR 은 숨은 점수입니다")
	end)

	t:it("프로필에 랭크 · 전적 · 덱 · 꾸밈이 보인다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		storeProgress(world, kim, {
			cleared = 2,
			gold = 300,
			rankPoints = 510,
			mmr = 1234,
			rankedWins = 3,
			rankedLosses = 1,
		})
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "프로필"))
		world:advance(1)
		assertNoErrors(world, "프로필 열기")

		local profile = Screen.find(guiOf(kim), "TCGProfile")
		t:truthy(profile and profile.Enabled, "프로필 화면이 떠야 합니다")
		t:truthy(Screen.hasText(profile, "Kim"), "이름")
		t:truthy(Screen.hasText(profile, "골드"), "티어 (510점 = 골드)")
		t:truthy(Screen.hasText(profile, "플래티넘까지 390점"), "다음 티어까지 남은 점수")
		t:truthy(Screen.hasText(profile, "3승 1패 · 승률 75%"), "전적")
		t:truthy(Screen.hasText(profile, "60장"), "덱 장수")
		t:truthy(Screen.countNamed(profile, "DeckCard_") > 0, "덱 카드가 칩으로 보여야 합니다")
		t:truthy(Screen.find(profile, "FramePreview"), "테두리 미리보기")
		t:truthy(Screen.find(profile, "CardBack"), "뒷면 미리보기")
		t:truthy(Screen.hasText(profile, "캠페인 2 / 5"), "캠페인 진도")
		t:falsy(Screen.hasText(profile, "1234"), "MMR 은 숨은 점수입니다")

		Screen.click(Screen.findButton(guiOf(kim), "뒤로"))
		world:advance(1)
		t:truthy(Screen.findButton(guiOf(kim), "빠른 대전"), "뒤로 가면 시작 화면이어야 합니다")
	end)

	t:it("기록이 없으면 없다고 말한다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "프로필"))
		world:advance(1)
		assertNoErrors(world, "빈 프로필")

		local profile = Screen.find(guiOf(kim), "TCGProfile")
		t:truthy(Screen.hasText(profile, "아직 랭크전 기록이 없습니다"))
		t:truthy(Screen.hasText(profile, "브론즈"))
	end)

	--------------------------------------------------------------------
	-- 순위표 (src/server/LeaderboardStore.luau)
	--------------------------------------------------------------------

	local BOARD = "RankLeaderboard_v1"

	--[[
		순위표에 남 셋을 미리 올려 둔다. 이 월드에 접속한 적 없는 사람들이라 이름은
		knownNames 에 직접 넣는다 — 하나(9003)는 일부러 안 넣는다(이름을 못 찾는 경우).
	]]
	local function seedBoard(world)
		world.orderedStores[BOARD] = {
			user_9001 = 2100,
			user_9002 = 640,
			user_9003 = 230,
		}
		world.knownNames[9001] = "Champion"
		world.knownNames[9002] = "Runner"
		storeProgress(world, { UserId = 9001 }, {
			cleared = 5,
			gold = 900,
			rankPoints = 2100,
			mmr = 1777,
			rankedWins = 120,
			rankedLosses = 40,
		})
	end

	local function openBoard()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		seedBoard(world)
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "순위표"))
		world:advance(1)
		assertNoErrors(world, "순위표 열기")
		return world, lobby, kim, Screen.find(guiOf(kim), "TCGLeaderboard")
	end

	t:it("순위표가 점수 순으로 뜨고, 이름을 못 찾아도 뜬다", function()
		local _, _, _, board = openBoard()

		t:truthy(board and board.Enabled, "순위표 화면이 떠야 합니다")
		t:eq(Screen.countNamed(board, "Row_"), 3)
		t:truthy(Screen.hasText(Screen.find(board, "Row_1"), "Champion"), "1등은 가장 높은 점수")
		t:truthy(Screen.hasText(Screen.find(board, "Row_1"), "마스터 2100점"))
		t:truthy(Screen.hasText(Screen.find(board, "Row_2"), "Runner"))
		t:truthy(Screen.hasText(Screen.find(board, "Row_3"), "플레이어 #9003"), "이름을 못 찾으면 번호로 그린다")
		t:truthy(Screen.hasText(board, "위 밖"), "목록 밖이면 내 점수만 따로 보여줘야 합니다")
	end)

	t:it("이름을 누르면 그 사람의 프로필 — 덱 · 골드 · MMR 은 안 보인다", function()
		local world, _, kim, board = openBoard()

		Screen.click(Screen.find(board, "Row_1"))
		world:advance(1)
		assertNoErrors(world, "남의 프로필")

		local profile = Screen.find(guiOf(kim), "TCGProfile")
		t:truthy(profile and profile.Enabled, "프로필이 떠야 합니다")
		t:truthy(Screen.hasText(profile, "Champion"))
		t:truthy(Screen.hasText(profile, "마스터"))
		t:truthy(Screen.hasText(profile, "순위 1위"))
		t:truthy(Screen.hasText(profile, "120승 40패"))
		t:truthy(Screen.hasText(profile, "다른 사람의 덱은 볼 수 없습니다"))
		t:eq(Screen.countNamed(profile, "DeckCard_"), 0, "남의 덱 카드가 보이면 안 됩니다")
		t:falsy(Screen.hasText(profile, "골드"), "남의 골드는 안 보여야 합니다")
		t:falsy(Screen.hasText(profile, "1777"), "MMR 은 숨은 점수입니다")

		-- 남의 프로필을 연 것이 그 사람 저장값을 만들거나 바꾸면 안 된다
		-- (COLLECTION_STORE 상수는 이 파일 아래쪽에 선언돼 여기서는 안 보인다 — 이름을 그대로 쓴다)
		local collections = world.dataStores["PlayerCollection_v1"] or {}
		t:eq(collections.user_9001, nil, "남의 컬렉션을 만들어 저장하면 안 됩니다")

		Screen.click(Screen.findButton(guiOf(kim), "뒤로"))
		world:advance(1)
		t:truthy(Screen.find(guiOf(kim), "TCGLeaderboard").Enabled, "순위표에서 왔으면 순위표로 돌아가야 합니다")
	end)

	t:it("내 줄을 누르면 내 프로필이 열린다", function()
		local world, lobby, kim = openBoard()
		-- 순위표의 줄은 userId 를 보낸다. 내 id 면 남의 프로필이 아니라 내 프로필(덱 포함)이어야 한다
		lobby.remotes.Lobby._serverSignal:Fire(kim, { kind = "viewProfile", userId = kim.UserId })
		world:advance(1)
		assertNoErrors(world, "내 줄")

		local profile = Screen.find(guiOf(kim), "TCGProfile")
		t:truthy(Screen.hasText(profile, "내 덱"), "내 프로필이면 덱이 보여야 합니다")
	end)

	t:it("모양이 틀린 userId 는 무시한다", function()
		local world, lobby, kim = openBoard()
		for _, bad in { "9001", -1, 1.5, {} } do
			lobby.remotes.Lobby._serverSignal:Fire(kim, { kind = "viewProfile", userId = bad })
		end
		world:advance(1)
		assertNoErrors(world, "틀린 userId")
		t:truthy(Screen.find(guiOf(kim), "TCGLeaderboard").Enabled, "화면이 그대로여야 합니다")
	end)

	t:it("큐에 서 있는 동안은 프로필 버튼이 숨는다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		clickQueue(kim)
		world:advance(1)
		t:falsy(Screen.findButton(guiOf(kim), "프로필"), "큐에 선 채로 다른 화면에 가면 안 됩니다")
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
-- 튜토리얼
--==========================================================================

--[[
	튜토리얼의 약속은 하나다. **코치가 켜준 것만 눌러도 끝까지 갈 수 있다.**

	그래서 여기 테스트는 대본을 따라가지 않는다. 화면에서 "지금 눌리는 것" 만 골라
	누르는 학생을 하나 만들어 놓고, 그 학생이 판을 이기는지 본다. 코치가 어느 단계에서든
	아무것도 안 켜주면 학생은 거기서 멈추고, 테스트는 "진도가 안 나갔다" 로 실패한다.

	흐린 카드와 꺼진 버튼은 건드리지 않는다 — 그게 잠금이 실제로 걸려 있다는 뜻이다.
]]
t:describe("튜토리얼", function()
	local function openTutorial()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "튜토리얼"))
		world:advance(2)
		assertNoErrors(world, "튜토리얼 시작")

		return world, kim
	end

	local function coachText(player)
		local box = Screen.find(guiOf(player), "Coach")
		if not box then
			return nil
		end
		for _, child in box:GetChildren() do
			if child.Name ~= "UICorner" and child.Name ~= "UIStroke" and child.Name ~= "UIPadding" then
				return child.Text
			end
		end
		return nil
	end

	local allNamed = allNamedIn

	t:it("시작 화면에서 튜토리얼을 열 수 있다", function()
		local _, kim = openTutorial()
		local gui = guiOf(kim)

		t:truthy(Screen.hasText(gui, "턴 "), "전투 화면이 떠야 합니다")
		t:truthy(coachText(kim), "코치 말풍선이 떠야 합니다")
		t:truthy(Screen.hasText(gui, "튜토리얼 상대"), "튜토리얼 상대와 붙어야 합니다")
	end)

	t:it("시키지 않은 것은 잠겨 있다", function()
		local world, kim = openTutorial()

		-- 첫 단계는 멀리건이다. 여기서 페이즈를 넘길 수는 없어야 한다.
		t:falsy(activeButton(kim, "페이즈 종료"), "멀리건 관문에서 페이즈 종료가 켜져 있습니다")
		t:truthy(activeButton(kim, "이대로 시작"), "'이대로 시작' 은 켜져 있어야 합니다")

		Screen.click(Screen.findButton(guiOf(kim), "이대로 시작"))
		world:advance(1)

		--[[
			이제 코스트 단계다. 코스트 카드만 밝아야 한다 —
			생물을 낼 코스트도 아직 없지만, 그건 코치의 잠금과 우연히 같은 결과일 뿐이라
			**코스트 카드가 실제로 밝은지** 까지 같이 본다.
		]]
		local bright = brightHandCard(kim)
		t:truthy(bright, "코스트 카드는 낼 수 있어야 합니다")
		t:eq(bright.Name, "Hand_COST_BASIC", "코스트 카드 말고는 밝으면 안 됩니다")
		t:falsy(activeButton(kim, "페이즈 종료"), "코스트를 내기 전에는 페이즈를 넘길 수 없어야 합니다")
	end)

	--[[
		전투 중에도 카드를 들여다볼 수 있어야 한다. 태그가 무슨 효과인지는 여기서 읽는다 —
		코치 말풍선은 세 줄이라 다섯 종을 담을 수 없다.
	]]
	t:it("전투 중에 카드를 오른쪽 클릭하면 태그 효과가 나온다", function()
		local world, kim = openTutorial()
		local gui = guiOf(kim)

		-- 태그가 붙은 손패 카드를 찾는다. 없으면 이 판에서는 확인할 수 없다.
		local tagged, tagName
		for _, node in allNamed(gui, "Hand_") do
			for _, name in TAG_NAMES do
				if not tagged and Screen.hasText(node, name) then
					tagged, tagName = node, name
				end
			end
		end
		t:truthy(tagged, "튜토리얼 첫 손패에 태그 달린 카드가 있어야 합니다")

		Screen.rightClick(tagged)
		world:advance(0.3)
		assertNoErrors(world, "전투 중 카드 상세")

		-- 덱 편집 화면에도 같은 이름의 상자가 있다. 전투 화면 안에서 찾는다.
		local detail = Screen.find(Screen.find(gui, "TCGBattle"), "Detail")
		t:truthy(detail and detail.Visible, "상세 상자가 떠야 합니다")

		local rule = Screen.find(detail, "DetailTagText")
		t:truthy(rule and rule.Text:find(tagName), ("%s 효과가 적혀 있어야 합니다"):format(tagName))
		t:truthy(#rule.Text > #tagName + 5, "태그 이름만 있고 설명이 없습니다")

		-- 같은 카드를 다시 누르면 닫힌다.
		Screen.rightClick(tagged)
		world:advance(0.3)
		t:falsy(detail.Visible, "다시 누르면 닫혀야 합니다")
	end)

	--[[
		"다시 하기" 는 같은 러너에서 새 판을 여는 것이라 Controller:start 를 거치지 않는다.
		코치가 지난 판의 마지막 단계에 머문 채 새 판을 맞으면 안내가 통째로 어긋난다.
	]]
	t:it("항복하고 다시 하기를 눌러도 처음부터 안내한다", function()
		local world, kim = openTutorial()
		local gui = guiOf(kim)

		local function line()
			return coachText(kim) or ""
		end

		t:truthy(line():find("손패 7장"), "첫 안내는 멀리건이어야 합니다")

		-- 코치를 다음 단계로 밀어둔다.
		Screen.click(Screen.findButton(gui, "이대로 시작"))
		world:advance(1)
		t:truthy(line():find("코스트"), "코스트 단계로 넘어가야 합니다")

		concede(world, kim)
		world:advance(2)
		t:truthy(outcome(kim), "항복하면 판이 끝나야 합니다")

		Screen.click(Screen.findButton(gui, "다시 하기"))
		world:advance(3)
		assertNoErrors(world, "튜토리얼 다시 하기")

		t:truthy(line():find("손패 7장"), ("새 판인데 안내가 %s 에 머물러 있습니다"):format(line()))
	end)

	t:it("코치가 켜준 것만 눌러도 이길 수 있다", function()
		local world, kim = openTutorial()
		local gui = guiOf(kim)

		local pressed = 0
		local said = {} -- 판 내내 코치가 한 말 전부
		local inspected = false

		for _ = 1, 600 do
			if outcome(kim) then
				break
			end
			local line = coachText(kim)
			if line then
				said[line] = true

				--[[
					코치가 "이 카드로 해보세요" 라고 예를 들면, 그 카드가 화면에 있어야 한다.
					없는 카드를 가리키면 읽는 사람은 그걸 찾다가 만다.
				]]
				for _, name in TAG_NAMES do
					if line:find("의 <b>" .. name .. "</b> 로 해보세요") then
						t:truthy(
							hasKeywordChip(kim, name),
							("화면에 %s 카드가 없는데 %s 로 해보라고 했습니다"):format(name, name)
						)
					end
				end

				--[[
					"상대가 공격했어요" 는 **진짜 공격이 선언됐을 때만** 해야 한다.
					상대가 생물을 소환하기만 해도 대응 창이 열리는데(대응 패스를 직접
					누르게 되면서 매번 열린다), 그걸 방어 상황으로 착각하면 코치가
					매번 없는 공격을 알린다 — 실제로 그랬다.
				]]
				if line:find("상대가 공격했어요") then
					local attackBadges = 0
					for _, text in Screen.visibleTexts(gui) do
						if text == "공격" then
							attackBadges += 1
						end
					end
					t:truthy(attackBadges > 0, "공격 선언이 없는데 공격했다고 알렸습니다")
				end

				-- 오른쪽 클릭을 배우라고 하면 한 번 해본다. 학생은 시킨 대로 한다.
				if not inspected and line:find("오른쪽 클릭") then
					local card = allNamed(gui, "Hand_")[1]
					if card then
						Screen.rightClick(card)
						world:advance(0.3)
						inspected = true
					end
				end
			end
			if pressSomething(world, kim) then
				pressed += 1
			end
		end

		assertNoErrors(world, "튜토리얼 진행")
		t:truthy(pressed > 8, ("진도가 안 나갔습니다 (%d 번만 눌렸습니다)"):format(pressed))
		t:eq(outcome(kim), "승리", "코치가 켜준 것만 눌러도 이겨야 합니다")
		t:falsy(coachText(kim), "다 배웠으면 말풍선은 사라져야 합니다")
		t:truthy(Screen.hasText(gui, "다시 하기"), "끝나면 다시 할 수 있어야 합니다")
		t:truthy(Screen.hasText(gui, "덱 편집"), "끝나는 자리에서 다음에 볼 곳을 알려줘야 합니다")
		t:truthy(Screen.hasText(gui, "오른쪽 클릭"), "끝나는 자리에서 들여다보는 법을 알려줘야 합니다")

		--[[
			용어와 태그를 실제로 가르쳤는가.

			판이 어떻게 흘렀든 탭·언탭은 반드시 나온다(생물을 한 마리도 못 내면
			건너뛰지만, 그 판은 애초에 이기지 못한다). 태그는 판에 나온 것만 소개하므로
			"둘 이상" 으로 본다 — 다섯 종을 다 요구하면 판마다 깜빡인다.
		]]
		local function saidAny(needle)
			for line in said do
				if line:find(needle) then
					return true
				end
			end
			return false
		end

		-- "언탭" 만 찾으면 안 된다. 신속 태그 설명에도 그 낱말이 들어 있어서,
		-- 탭 단계를 통째로 지워도 통과한다. 탭 단계에만 있는 문장으로 본다.
		t:truthy(saidAny("노란색 점"), "탭이 무엇인지 설명해야 합니다")
		t:truthy(saidAny("내 턴이 시작할 때"), "언탭이 언제 되는지 설명해야 합니다")

		--[[
			태그는 코치가 읊지 않는다. 말풍선은 세 줄이라 다섯 종을 담을 수 없고, 판은
			그중 몇 종만 보여준다. 대신 **찾아보는 법**을 가르쳤는지 본다.
		]]
		t:truthy(saidAny("오른쪽 클릭"), "카드를 들여다보는 법을 알려줘야 합니다")

		--[[
			한 판을 끝까지 두면 상대는 반드시 공격해 오고, 카드를 낼 때마다 대응 창도 열린다.
			둘 다 사람이 눌러야 넘어가는 순간이라, 코치가 그때 무슨 상황인지 말해줘야 한다.

			방어를 "상대 첫 턴" 단계에 넣었을 때는 한 번도 안 떴다 — 소환 멀미 때문에
			상대의 첫 공격은 그 뒤에 온다. 그래서 상황 안내로 옮겼고, 여기서 그걸 지킨다.
		]]
		t:truthy(saidAny("상대가 공격했어요"), "막을 차례가 오면 알려줘야 합니다")
		t:truthy(saidAny("보라색 상자"), "대응 창이 열리면 무엇을 눌러야 하는지 알려줘야 합니다")
		t:truthy(inspected, "말만 하고 실제로 눌러볼 카드가 없었습니다")
		t:truthy(saidAny("기본은 다 배웠어요"), "손짓을 배운 뒤에는 잔소리를 멈춰야 합니다")
	end)
end)

--==========================================================================
-- 저장한 덱으로 대전
--==========================================================================

--[[
	덱 편집은 로비 서버에서 하고, 실제 PvP 는 **예약 서버**에서 열린다.
	그 사이를 잇는 것은 텔레포트가 아니라 DataStore 다 — 대전 서버가 도착한 사람의
	UserId 로 직접 읽는다(Arena:loadDeck).

	여기서 보는 것은 하나다. **각자 자기가 저장한 덱으로 판이 열리는가.**

	손패를 읽어서 판정한다. 클라이언트에게 덱 내용은 안 내려가므로(viewFor 가 지운다)
	화면에서 덱을 직접 셀 방법이 없다. 대신 "손에 들어온 카드가 전부 내 덱에 있는
	카드인가" 를 본다 — 스타터로 열렸다면 내 덱에 없는 카드가 섞여 나온다.
]]
t:describe("저장한 덱으로 대전", function()
	--[[
		스타터에 한 장도 없는 카드로만 짠 덱 두 벌. 서로 겹치지 않게 나눠 놨다 —
		좌석이 뒤바뀌어 상대 덱으로 열리는 경우도 같이 걸린다.
	]]
	local KIM_CARDS =
		{ "CRE_SCOUT", "CRE_SENTRY", "CRE_HERALD", "CRE_FALCONER", "SPL_MEND", "SPL_RALLY", "SPL_RECALL" }
	local LEE_CARDS =
		{ "CRE_WYVERN", "CRE_SKYPIERCER", "CRE_TITAN", "SPL_BANISH", "SPL_EXECUTE", "SPL_REINFORCE", "SPL_BULWARK_UP" }

	-- 같은 카드는 4장까지라, 나머지는 코스트 카드로 채운다(코스트는 매수 제한이 없다).
	local function deckOf(cards)
		local entries = { { id = "COST_BASIC", count = 60 - #cards * 4 } }
		for _, id in cards do
			table.insert(entries, { id = id, count = 4 })
		end
		return entries
	end

	--[[
		편집 화면에서 60번 누르는 대신, 이미 저장해둔 상태에서 시작한다.
		(눌러서 저장하는 경로는 위 "덱 편집" 절이 본다)
	]]
	local function storeDeck(world, player, cards)
		local store = world.dataStores["PlayerDecks_v1"] or {}
		world.dataStores["PlayerDecks_v1"] = store
		store[("user_%d"):format(player.UserId)] = deckOf(cards)
	end

	--[[
		손패가 전부 이 덱에서 나왔는가. -> ok, 설명

		이름을 하나씩 훑는 대신 개수를 맞춘다 — "내 덱 id 로 센 합" 과 "손패 전체" 가
		같으면 남의 카드가 한 장도 없다는 뜻이다.
	]]
	local function handIsFrom(player, cards)
		local gui = guiOf(player)
		local total = Screen.countNamed(gui, "Hand_")
		local mine = Screen.countNamed(gui, "Hand_COST_BASIC")

		for _, id in cards do
			mine += Screen.countNamed(gui, "Hand_" .. id)
		end

		return total > 0 and total == mine,
			("%s 의 손패 %d 장 중 %d 장만 자기 덱 카드입니다"):format(player.Name, total, mine)
	end

	t:it("예약 서버에서 각자 자기 덱으로 열린다", function()
		local world = Roblox.newWorld({ studio = false })

		local alpha = world:newServer({ jobId = "job-alpha" }):boot()
		local beta = world:newServer({ jobId = "job-beta" }):boot()

		local kim = alpha:addPlayer("Kim")
		local lee = beta:addPlayer("Lee")
		storeDeck(world, kim, KIM_CARDS)
		storeDeck(world, lee, LEE_CARDS)
		world:advance(2)

		clickQueue(kim)
		clickQueue(lee)
		world:advance(10)
		assertNoErrors(world, "저장한 덱으로 크로스서버 매칭")

		t:truthy(Screen.hasText(guiOf(kim), "턴 "), "판이 열려야 합니다")
		t:truthy(handIsFrom(kim, KIM_CARDS))
		t:truthy(handIsFrom(lee, LEE_CARDS))
	end)

	t:it("AI 연습도 저장한 덱으로 열린다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()

		local kim = lobby:addPlayer("Kim")
		storeDeck(world, kim, KIM_CARDS)
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		assertNoErrors(world, "저장한 덱으로 AI 연습")

		t:truthy(handIsFrom(kim, KIM_CARDS))
	end)
end)

--==========================================================================
-- 전투 화살표
--==========================================================================

t:describe("전투 화살표", function()
	--[[
		공격과 방어를 화살표로 보여준다. 빨강은 공격, 파랑은 방어.

		하네스는 레이아웃을 계산하지 않으므로(모든 절대 좌표가 0) **선이 어디로 가는지는
		여기서 못 본다.** 볼 수 있는 것은 "선언한 만큼 그려졌는가 · 색이 맞는가 ·
		선언을 취소하면 사라지는가" 다. 각도와 길이는 Studio 에서 눈으로 본다.
	]]
	--[[
		공격과 방어를 화살표로 보여준다. 빨강은 공격, 파랑은 방어.

		**사람 둘로 본다.** AI 연습으로는 "상대가 공격하고 내가 막는" 상황을 언제 만나는지
		운에 맡기게 된다 — 실제로 그렇게 짰다가 80턴을 굴려도 방어 한 번을 못 봤다.
		두 사람을 다 조종하면 공격도 방어도 원할 때 만든다.

		하네스는 레이아웃을 계산하지 않으므로(절대 좌표가 전부 0) **선이 어디로 가는지는
		여기서 못 본다.** 볼 수 있는 것은 "선언한 만큼 그려졌는가 · 색이 맞는가 ·
		양쪽 화면에 다 보이는가" 다. 각도와 길이는 Studio 에서 눈으로 본다.
	]]
	t:it("공격은 빨간 화살표, 방어는 파란 화살표로 그린다", function()
		local world = Roblox.newWorld({ studio = false })

		local alpha = world:newServer({ jobId = "job-alpha" }):boot()
		local beta = world:newServer({ jobId = "job-beta" }):boot()

		local kim = alpha:addPlayer("Kim")
		local lee = beta:addPlayer("Lee")
		world:advance(2)

		clickQueue(kim)
		clickQueue(lee)
		world:advance(10)
		assertNoErrors(world, "화살표 테스트 매칭")

		local both = { kim, lee }

		-- 카드 위의 "공격" · "방어" 배지 개수. 배지는 글자가 딱 그것뿐이라 정확히 일치로 센다
		-- ("공격력 2" · "공격 취소" 와 섞이면 안 된다).
		local function badges(player, word)
			local count = 0
			for _, text in Screen.visibleTexts(guiOf(player)) do
				if text == word then
					count += 1
				end
			end
			return count
		end

		--[[
			화살표는 곡선이라 **선 하나가 조각 여럿**이다(Battle.drawArrow). 그래서
			조각을 세면 화살표 개수가 안 나온다 — 화살촉으로 센다. 화살촉은 곡선
			하나에 정확히 하나다.

			조각은 풀에서 돌려 쓴다. 안 쓰는 것은 지우지 않고 숨기므로 Visible 을
			봐야 한다 — 안 보면 "한때 화살표가 셋이었다" 가 계속 셋으로 읽힌다.
		]]
		local function piecesNamed(player, prefix)
			local out = {}
			for _, node in Screen.find(guiOf(player), "Arrows"):GetChildren() do
				if node.Visible and node.Name:sub(1, #prefix) == prefix then
					table.insert(out, node)
				end
			end
			return out
		end

		--[[
			공격이냐 방어냐는 **색으로** 가린다. 풀을 돌려 쓰므로 이름의 번호는
			그리는 순서일 뿐이고, 그 번호가 공격인지 방어인지는 말해주지 않는다.

			팔레트 값을 여기 베껴 두면 색을 조금만 손봐도 테스트가 깨진다.
			"붉은 계열인가 · 푸른 계열인가" 만 본다.
		]]
		local function arrowHeads(player, attacking)
			local out = {}
			for _, node in piecesNamed(player, "ArrowHeadTip") do
				local color = node.TextColor3
				local isAttack = color.R > color.B
				if isAttack == attacking then
					table.insert(out, node)
				end
			end
			return out
		end

		for _, player in both do
			t:eq(#piecesNamed(player, "Arrow"), 0, "전투 전에는 화살표가 없어야 합니다")
		end

		-- 둘 다 학생처럼 둔다. 공격이 선언될 때까지.
		local attacked = false
		for _ = 1, 200 do
			if badges(kim, "공격") > 0 then
				attacked = true
				break
			end
			pressSomething(world, kim)
			pressSomething(world, lee)
		end

		t:truthy(attacked, "공격 선언이 한 번은 나와야 합니다")
		assertNoErrors(world, "공격 선언")

		for _, player in both do
			local heads = arrowHeads(player, true)
			t:eq(#heads, badges(player, "공격"), ("%s 화면: 공격 선언 수만큼 화살표"):format(player.Name))
			t:truthy(#heads > 0, ("%s 화면에도 공격 화살표가 보여야 합니다"):format(player.Name))
		end

		-- 이어서 방어. 막은 쪽이 누구든 상관없다.
		local blocked = false
		for _ = 1, 60 do
			if badges(kim, "방어") > 0 then
				blocked = true
				break
			end
			pressSomething(world, kim)
			pressSomething(world, lee)
		end

		t:truthy(blocked, "방어 배정이 한 번은 나와야 합니다")
		assertNoErrors(world, "방어 배정")

		for _, player in both do
			local heads = arrowHeads(player, false)
			t:eq(#heads, badges(player, "방어"), ("%s 화면: 방어 배정 수만큼 화살표"):format(player.Name))
			t:truthy(#heads > 0, ("%s 화면에도 방어 화살표가 보여야 합니다"):format(player.Name))
		end

		--[[
			**선이 실제로 두 카드를 잇는가.**

			하네스는 레이아웃을 안 굴리므로 절대 좌표가 전부 0 이다. 그래서 여기서는
			좌표를 직접 넣어 놓고 한 프레임 뒤에 계산 결과를 읽는다.

			이 단언이 잡는 것: 화면 픽셀로 잰 거리를 그대로 offset 에 넣는 실수.
			루트에 UIScale 이 걸려 있어서(Widgets.autoScale) 배율로 나누지 않으면
			1080 화면에서 화살표가 카드에서 20% 씩 밀려난다.

			곡선이라 **중점·길이·각도로는 못 잡는다** — 그 값들은 휜 정도(Theme.arrow.bow)
			에 따라 변한다. 대신 화살촉을 본다. 화살촉은 곡선이 어떻게 휘든 정확히
			대상의 한가운데 있어야 하는 유일한 조각이다.
		]]
		do
			local gui = guiOf(kim)
			local arrowsFrame = Screen.find(gui, "Arrows")
			local uiScale = Screen.find(gui, "Root"):FindFirstChildOfClass("UIScale")
			local scale = uiScale.Scale

			t:truthy(#arrowHeads(kim, true) > 0, "공격 화살표가 있어야 합니다")

			local attackerCard = litCards(Screen.find(gui, "MyField"))[1]
				or allNamedIn(Screen.find(gui, "MyField"), "Field_")[1]
			t:truthy(attackerCard, "내 생물이 화면에 있어야 합니다")

			local V2 = Roblox.Datatypes.Vector2
			arrowsFrame.AbsolutePosition = V2.new(100, 100)
			attackerCard.AbsolutePosition = V2.new(200, 500)
			attackerCard.AbsoluteSize = V2.new(100, 100)

			local foePanel = Screen.find(gui, "FoePanel")
			foePanel.AbsolutePosition = V2.new(200, 100)
			foePanel.AbsoluteSize = V2.new(100, 100)

			for _, node in allNamedIn(Screen.find(gui, "FoeField"), "Field_") do
				node.AbsolutePosition = V2.new(200, 100)
				node.AbsoluteSize = V2.new(100, 100)
			end

			world:advance(0.2) -- 한 프레임 이상. 화살표는 매 프레임 다시 그린다

			--[[
				공격자 가운데 (250, 550) → 대상 가운데 (250, 150).
				판이 (100, 100) 에서 시작하므로 대상은 판 기준 (150, 50),
				배율로 나누면 그 값 / scale.
			]]
			local head = arrowHeads(kim, true)[1]
			t:truthy(head, "다시 그린 뒤에도 공격 화살표가 있어야 합니다")

			t:eq(head.Position.X.Offset, 150 / scale, "화살촉은 대상 한가운데 X")
			t:eq(head.Position.Y.Offset, 50 / scale, "화살촉은 대상 한가운데 Y")

			--[[
				위를 향하는가. 대상이 공격자보다 위에 있으니 화살촉은 위쪽 반원을
				가리켜야 한다. 정확한 각도를 박지 않는 이유는 bow 를 바꾸면 달라지기
				때문이다 — 바꿔도 **위를 향한다**는 것은 변하지 않는다.
			]]
			t:truthy(head.Rotation < 0 and head.Rotation > -180, "화살촉이 대상 쪽을 향해야 합니다")

			--[[
				곡선인가. 조각이 둘뿐이면 그냥 꺾인 직선이다.
				(조각 수는 Theme.arrow.segment 가 정한다)
			]]
			local lines = piecesNamed(kim, "ArrowLine")
			t:truthy(#lines >= 3, "곡선은 조각 셋 이상으로 그려져야 합니다")

			--[[
				조각이 공격자에서 대상까지 **걸쳐 있는가.** 화살촉만 맞고 몸통이
				엉뚱한 데 있으면 선이 두 카드를 잇지 않는다.
			]]
			local top, bottom = math.huge, -math.huge
			for _, node in lines do
				top = math.min(top, node.Position.Y.Offset)
				bottom = math.max(bottom, node.Position.Y.Offset)
			end

			t:truthy(top < 150 / scale, "선의 윗끝이 대상에 닿아야 합니다")
			t:truthy(bottom > 350 / scale, "선의 아랫끝이 공격자에 닿아야 합니다")
		end

		--[[
			화살촉마다 윤곽이 하나씩. 조각도 마찬가지다 — 색 선 밑에는 반드시
			더 굵은 어두운 선이 깔려 있어야 카드 위에서 묻히지 않는다.
		]]
		t:eq(
			#piecesNamed(kim, "ArrowHeadTip"),
			#piecesNamed(kim, "ArrowHeadShade"),
			"화살촉마다 윤곽이 하나씩 있어야 합니다"
		)
		t:eq(
			#piecesNamed(kim, "ArrowLine"),
			#piecesNamed(kim, "ArrowShade"),
			"선 조각마다 윤곽이 하나씩 있어야 합니다"
		)

		--[[
			**화살표가 줄어들면 남은 것은 숨겨져야 한다.**

			조각은 지우지 않고 숨겨서 돌려 쓴다(hideRest). 안 숨기면 전투가 끝난
			뒤에도 화살표가 화면에 남는다.

			위의 단언들만으로는 이걸 못 잡는다 — 화살표가 **늘어나는** 동안만 보기
			때문이다. 실제로 hideRest 가 아무것도 안 숨기게 고쳐도 전부 초록불이었다.
		]]
		local cleared = false
		for _ = 1, 400 do
			if badges(kim, "공격") == 0 and badges(kim, "방어") == 0 then
				cleared = true
				break
			end
			pressSomething(world, kim)
			pressSomething(world, lee)
		end

		t:truthy(cleared, "전투가 한 번은 끝나야 합니다")
		assertNoErrors(world, "전투 종료")
		world:advance(0.2) -- 화살표는 매 프레임 다시 그린다

		for _, player in both do
			t:eq(
				#piecesNamed(player, "Arrow"),
				0,
				("%s 화면: 전투가 끝나면 화살표가 남으면 안 됩니다"):format(player.Name)
			)
		end
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
--[[
	카드를 전부 4장씩 가진 사람으로 만든다 (코스트 카드는 원래 무한이라 안 적는다).

	덱 편집 테스트 몇 개는 스타터에 없는 카드를 넣어 본다. 컬렉션이 생긴 뒤로 새로 온
	사람은 스타터 카드만 가지므로, 그 테스트들은 "다 모은 사람" 으로 시작한다.
	서버가 처음 읽기 전에 저장소에 넣어둬야 한다 — 한 번 읽으면 캐시에서 준다.
]]
local COLLECTION_STORE = "PlayerCollection_v1"
local ALL_CARDS = {
	"CRE_SCOUT", "CRE_GUARD", "CRE_BRUTE", "CRE_RAIDER", "CRE_HAWK", "CRE_WYVERN",
	"CRE_BULWARK", "CRE_ARCHER", "CRE_SKYPIERCER", "CRE_SCRIBE", "CRE_HERALD", "CRE_SQUIRE",
	"CRE_SENTRY", "CRE_FALCONER", "CRE_LANCER", "CRE_BERSERKER", "CRE_TITAN",
	"SPL_FIREBOLT", "SPL_RALLY", "SPL_WARCRY", "SPL_EXECUTE", "SPL_NEGATE", "SPL_RECALL",
	"SPL_SHOCK", "SPL_BULWARK_UP", "SPL_MEND", "SPL_INSIGHT", "SPL_ARCHIVE", "SPL_SNIPE",
	"SPL_BANISH", "SPL_REINFORCE",
}

local function collectionOf(world, player)
	local store = world.dataStores[COLLECTION_STORE]
	return store and store[("user_%d"):format(player.UserId)]
end

local function ownEverything(world, player)
	local cards = {}
	for _, id in ALL_CARDS do
		table.insert(cards, { id = id, count = 4 })
	end

	world.dataStores[COLLECTION_STORE] = world.dataStores[COLLECTION_STORE] or {}
	world.dataStores[COLLECTION_STORE][("user_%d"):format(player.UserId)] =
		{ cards = cards, spent = 0, opened = 0 }
end

t:describe("덱 편집", function()
	local function openEditor(ownAll)
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		if ownAll then
			ownEverything(world, kim)
		end
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
		local world, _, kim = openEditor(true)

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
		local world, _, kim = openEditor(true)

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

		--[[
			태그 이름만으로는 무슨 효과인지 알 수 없다. 규칙 문장이 같이 나와야 한다
			(Enums.KeywordText). 카드에 적힌 설명문은 카드마다 따로 쓰여 있어서
			같은 태그가 카드마다 다르게 설명되거나 아예 빠진다.
		]]
		--[[
			**어느 화면의 상세인지 좁혀서 찾는다.** 전투 화면에도 같은 상자가 있고
			(이름도 같다), Screen.find 는 트리에서 먼저 만난 것을 준다 —
			범위를 안 좁히면 비어 있는 전투 쪽 상자를 읽고 "설명이 없다" 가 된다.
		]]
		local rule = Screen.find(Screen.find(gui, "TCGDeck"), "DetailTagText")
		t:truthy(rule and rule.Text:find("지상 생물은"), "비행이 무슨 효과인지 적혀 있어야 합니다")
	end)

	t:it("상세를 열어둔 채 카드를 넣으면 숫자가 따라간다", function()
		local world, _, kim = openEditor(true)
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

	--------------------------------------------------------------------
	-- 가진 카드로만 짠다
	--------------------------------------------------------------------

	t:it("가지지 않은 카드는 넣을 수 없다", function()
		local world, _, kim = openEditor()
		local gui = guiOf(kim)

		-- 자리를 하나 만들고, 스타터에 없는 초소병을 넣어 본다.
		Screen.click(Screen.findNamed(Screen.find(gui, "Deck"), "Card_COST_BASIC"))
		world:advance(0.2)
		Screen.click(Screen.findNamed(Screen.find(gui, "Catalog"), "Card_CRE_SENTRY"))
		world:advance(0.2)

		t:truthy(Screen.hasText(gui, "59 / 60 장"), "안 들어가야 합니다")
		t:truthy(Screen.hasText(gui, "가지지 않은 카드"), "왜 안 되는지 말해줘야 합니다")
		t:falsy(Screen.findNamed(Screen.find(gui, "Deck"), "Card_CRE_SENTRY"), "덱 쪽에 생기면 안 됩니다")
	end)

	t:it("목록에 '덱/가진 것' 이 적힌다", function()
		local _, _, kim = openEditor()
		local catalog = Screen.find(guiOf(kim), "Catalog")

		-- 창공의 매: 스타터에 3장, 가진 것도 3장
		local hawk = Screen.find(Screen.findNamed(catalog, "Card_CRE_HAWK"), "Count")
		t:eq(hawk and hawk.Text, "3/3")

		local sentry = Screen.find(Screen.findNamed(catalog, "Card_CRE_SENTRY"), "Count")
		t:eq(sentry and sentry.Text, "0/0", "가지지 않은 카드도 목록에는 남아야 합니다")
	end)

	--[[
		화면이 막아도 리모트는 손으로 부를 수 있다. 서버가 다시 봐야 한다 (Lobby:saveDeck).
		덱 규칙(60장 · 4장 제한)은 통과하는 덱이라, 걸리는 것은 "가졌나" 하나뿐이다.
	]]
	t:it("가지지 않은 카드로 짠 덱은 리모트로 보내도 저장되지 않는다", function()
		local world, lobby, kim = openEditor()

		local cheat = { { id = "COST_BASIC", count = 52 }, { id = "CRE_TITAN", count = 4 }, { id = "SPL_EXECUTE", count = 4 } }
		lobby.remotes.Lobby._serverSignal:Fire(kim, { kind = "deckSave", entries = cheat })
		world:advance(1)
		assertNoErrors(world, "가지지 않은 카드로 저장")

		t:truthy(Screen.hasText(guiOf(kim), "가지고 있습니다"), "왜 안 되는지 말해줘야 합니다")

		local stored = world.dataStores["PlayerDecks_v1"][("user_%d"):format(kim.UserId)]
		t:eq(stored, nil, "저장소에 들어가면 안 됩니다")
	end)

	--[[
		컬렉션이 생기기 전에 덱을 저장해둔 사람. 업데이트 날 그 덱이 "가지지 않은 카드" 로
		거부되면 자기가 짠 덱을 빼앗기는 것이다 — 덱의 카드를 물려받아야 한다.
	]]
	t:it("컬렉션 전에 짜둔 덱은 그대로 쓸 수 있다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")

		local legacy = { { id = "COST_BASIC", count = 52 }, { id = "CRE_TITAN", count = 4 }, { id = "SPL_EXECUTE", count = 4 } }
		world.dataStores["PlayerDecks_v1"][("user_%d"):format(kim.UserId)] = legacy
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "덱 편집"))
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "저장"))
		world:advance(1)
		assertNoErrors(world, "옛 덱 다시 저장")

		t:truthy(Screen.hasText(guiOf(kim), "저장했습니다"), "옛 덱을 그대로 저장할 수 있어야 합니다")

		local collection = collectionOf(world, kim)
		t:truthy(collection, "처음 읽을 때 컬렉션이 저장돼야 합니다")

		local titans = 0
		for _, entry in collection.cards do
			if entry.id == "CRE_TITAN" then
				titans = entry.count
			end
		end
		t:eq(titans, 4, "옛 덱의 카드를 물려받아야 합니다")
	end)
end)

--==========================================================================
-- PvE 캠페인
--==========================================================================

--[[
	해금과 보상 계산 자체는 tests/specs/campaign.luau 가 본다. 여기서 보는 것은 **배선**이다 —
	목록이 실제로 뜨는가, 고른 번호로 판이 열리는가, 그리고 판 결과가 DataStore 까지
	가는가. 셋 다 Studio 를 켜야만 드러나는 종류라 여기서 잡아야 한다.
]]
t:describe("캠페인", function()
	local STORE = "CampaignProgress_v1"

	local function openCampaign()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "캠페인"))
		world:advance(1)
		assertNoErrors(world, "캠페인 열기")

		return world, lobby, kim
	end

	local function progressOf(world, player)
		local store = world.dataStores[STORE]
		if not store then
			return nil
		end
		return store[("user_%d"):format(player.UserId)]
	end

	t:it("목록이 뜨고 첫 칸만 도전할 수 있다", function()
		local _, _, kim = openCampaign()
		local gui = guiOf(kim)

		t:truthy(Screen.hasText(gui, "훈련병"), "1번 스테이지가 보여야 합니다")

		local first = Screen.findButton(Screen.find(gui, "Stage1"), "도전")
		local second = Screen.findButton(Screen.find(gui, "Stage2"), "도전")

		t:truthy(first and first.Active, "1번은 처음부터 열려 있어야 합니다")
		t:truthy(second, "잠긴 칸도 보이긴 해야 합니다")
		t:falsy(second.Active, "2번은 아직 잠겨 있어야 합니다")
	end)

	--[[
		잠긴 칸의 이름과 설명은 가린다. 난이도와 상대 라이프는 가리지 않는다 —
		"뒤로 갈수록 세진다" 가 안 보이면 목록이 진도로 안 읽힌다 (UI/Campaign 주석).
	]]
	t:it("잠긴 칸은 이름과 공략을 가린다", function()
		local _, _, kim = openCampaign()
		local locked = Screen.find(guiOf(kim), "Stage5")

		t:falsy(Screen.hasText(locked, "주문 파쇄자"), "잠긴 칸의 이름이 보이면 안 됩니다")
		t:truthy(Screen.hasText(locked, "???"), "가려져 있다는 것은 보여야 합니다")
	end)

	t:it("첫 칸을 누르면 그 상대와 판이 열린다", function()
		local world, _, kim = openCampaign()

		Screen.click(Screen.findButton(Screen.find(guiOf(kim), "Stage1"), "도전"))
		world:advance(3)
		assertNoErrors(world, "캠페인 1번 시작")

		t:truthy(passMulligan(world, kim), "멀리건 관문을 통과하지 못했습니다")
		t:truthy(waitForButton(world, kim, "페이즈 종료"), "판이 시작돼야 합니다")
		t:truthy(Screen.hasText(guiOf(kim), "훈련병"), "상대 이름이 스테이지 이름이어야 합니다")
	end)

	--[[
		목록에서 잠긴 칸을 못 누르게 해둔 것은 **화면의 편의**일 뿐이다. 리모트는 손으로도
		부를 수 있으므로 서버가 다시 봐야 한다 (Lobby:startCampaignStage 주석).
	]]
	t:it("잠긴 번호는 리모트로 직접 보내도 거부한다", function()
		local world, lobby, kim = openCampaign()

		lobby.remotes.Lobby._serverSignal:Fire(kim, { kind = "campaignStart", index = 4 })
		world:advance(3)
		assertNoErrors(world, "잠긴 스테이지 요청")

		local gui = guiOf(kim)
		t:falsy(Screen.findButton(gui, "페이즈 종료"), "전투 화면이 열리면 안 됩니다")
		t:truthy(Screen.hasText(gui, "앞 스테이지를 먼저"), "왜 안 되는지 말해줘야 합니다")
	end)

	t:it("없는 번호를 보내도 죽지 않는다", function()
		local world, lobby, kim = openCampaign()

		for _, index in { 0, 99, -1, 1.5, "1", nil } do
			lobby.remotes.Lobby._serverSignal:Fire(kim, { kind = "campaignStart", index = index })
			world:advance(0.5)
		end

		assertNoErrors(world, "이상한 스테이지 번호")
		t:falsy(Screen.findButton(guiOf(kim), "페이즈 종료"), "전투 화면이 열리면 안 됩니다")
	end)

	t:it("지면 진행도가 저장되지 않는다", function()
		local world, _, kim = openCampaign()

		Screen.click(Screen.findButton(Screen.find(guiOf(kim), "Stage1"), "도전"))
		world:advance(3)
		passMulligan(world, kim)
		waitForButton(world, kim, "페이즈 종료")

		concede(world, kim)
		world:advance(2)
		assertNoErrors(world, "캠페인 항복")

		t:eq(outcome(kim), "패배", "항복하면 지는 것입니다")
		t:eq(progressOf(world, kim), nil, "진 판으로 진행도가 저장되면 안 됩니다")
	end)

	t:it("끝난 판에는 '다시 하기' 가 없다", function()
		local world, _, kim = openCampaign()

		Screen.click(Screen.findButton(Screen.find(guiOf(kim), "Stage1"), "도전"))
		world:advance(3)
		passMulligan(world, kim)
		waitForButton(world, kim, "페이즈 종료")
		concede(world, kim)
		world:advance(2)

		--[[
			서버가 재시작을 안 받으므로(보상이 걸린 판이다) 버튼도 없어야 한다.
			띄워두면 눌러도 아무 일이 안 일어나는 자리가 된다.
		]]
		t:falsy(Screen.findButton(guiOf(kim), "다시 하기"), "캠페인에는 다시 하기가 없어야 합니다")
		t:truthy(Screen.findButton(guiOf(kim), "목록으로"), "목록으로 돌아갈 길은 있어야 합니다")
	end)

	t:it("판에서 나오면 시작 화면이 아니라 목록으로 돌아온다", function()
		local world, _, kim = openCampaign()

		Screen.click(Screen.findButton(Screen.find(guiOf(kim), "Stage1"), "도전"))
		world:advance(3)
		passMulligan(world, kim)
		waitForButton(world, kim, "페이즈 종료")
		concede(world, kim)
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "목록으로"))
		world:advance(2)
		assertNoErrors(world, "캠페인 목록으로")

		local gui = guiOf(kim)
		t:truthy(Screen.hasText(gui, "훈련병"), "목록이 다시 떠야 합니다")
		t:falsy(Screen.findButton(gui, "빠른 대전"), "시작 화면으로 가면 안 됩니다")
	end)

	--[[
		한 판을 끝까지 둬서 **클리어가 저장소까지 가는지** 본다.

		여기서 쓰는 자동 조작(pressSomething)은 켜져 있는 것을 아무거나 누르는 수준이다.
		그걸로 이겨야 한다는 것이 1번 스테이지의 설계다 — 처음 오는 사람이 막히면
		캠페인이 시작되지도 않는다. 그래서 "이긴다" 를 단언한다. 이게 깨지면 테스트가
		서툰 게 아니라 **1번이 너무 세진 것**이다 (Campaign.stages 의 1번 주석 참조).

		시드를 안 잡으므로 판마다 셔플이 다르다. 이 단언을 넣기 전에 13판을 돌려
		13판 다 이기는 것을 보고 걸었다.
	]]
	t:it("이기면 진행도와 골드가 저장된다", function()
		local world, _, kim = openCampaign()
		local stageGold = 50 -- Campaign.stages[1].gold

		Screen.click(Screen.findButton(Screen.find(guiOf(kim), "Stage1"), "도전"))
		world:advance(3)

		for _ = 1, 400 do
			if outcome(kim) then
				break
			end
			pressSomething(world, kim)
		end

		assertNoErrors(world, "캠페인 한 판")
		t:eq(outcome(kim), "승리", "1번은 아무 버튼이나 눌러도 이길 수 있어야 합니다")

		--[[
			화면 문구만 보면 "받았다고 말하는 것" 까지밖에 확인이 안 된다.
			덱 저장과 같은 이유로 저장된 값을 직접 본다.
		]]
		local stored = progressOf(world, kim)
		t:truthy(stored, "이겼으면 진행도가 저장돼야 합니다")
		t:eq(stored.cleared, 1)
		t:eq(stored.gold, stageGold)
		t:truthy(Screen.hasText(guiOf(kim), "골드"), "얼마를 받았는지 알려줘야 합니다")

		--------------------------------------------------------------
		-- 깬 결과가 목록까지 돌아오는가
		--------------------------------------------------------------
		Screen.click(Screen.findButton(guiOf(kim), "목록으로"))
		world:advance(2)
		assertNoErrors(world, "클리어 뒤 목록")

		local gui = guiOf(kim)
		local first, second = Screen.find(gui, "Stage1"), Screen.find(gui, "Stage2")

		t:truthy(Screen.hasText(first, "클리어"), "깬 칸에 표시가 붙어야 합니다")
		t:truthy(Screen.findButton(first, "다시"), "깬 칸의 버튼은 '다시' 가 돼야 합니다")
		t:truthy(Screen.hasText(second, "매사냥꾼"), "다음 칸이 이름을 드러내야 합니다")

		local nextStage = Screen.findButton(second, "도전")
		t:truthy(nextStage and nextStage.Active, "다음 스테이지가 열려야 합니다")
	end)

	--[[
		재도전으로 골드가 또 들어오지 않는 것은 tests/specs/campaign.luau 가 본다.

		여기서 한 판을 더 두지 않는 이유는 그 규칙이 못 미더워서가 아니라, **판마다
		셔플이 달라 두 판을 연달아 이기는 것을 보장할 수 없기** 때문이다 — 실제로 재도전
		판을 지면서 테스트가 흔들렸다. 서버가 부르는 계산은 Campaign.applyClear 하나이고,
		그 결과가 저장소까지 가는 배선은 위 테스트가 이미 지나간다.
	]]
end)

--==========================================================================
-- 카드팩
--==========================================================================

--[[
	무엇이 나오는지 · 골드 계산 · 4장 넘는 장의 환급은 tests/specs/collection.luau 가 본다.
	여기서 보는 것은 배선이다 — 버튼이 잔액을 따라 켜지고 꺼지는가, 산 결과가 저장소까지
	가는가, 서버가 잔액을 다시 보는가, 산 카드가 덱 편집에 실제로 나타나는가.

	골드는 캠페인을 깨서 버는 것이라, 여기서는 진행도를 저장소에 미리 넣어두고 시작한다.
	(이겨서 골드가 쌓이는 경로는 위 "캠페인" 절이 본다)
]]
t:describe("카드팩", function()
	local PROGRESS = "CampaignProgress_v1"

	local function openShop(gold)
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")

		if gold then
			world.dataStores[PROGRESS][("user_%d"):format(kim.UserId)] = { cleared = 2, gold = gold }
		end
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "카드팩"))
		world:advance(1)
		assertNoErrors(world, "카드팩 열기")

		return world, lobby, kim
	end

	local function shopGold(player)
		local label = Screen.find(Screen.find(guiOf(player), "TCGShop"), "Gold")
		return label and label.Text
	end

	t:it("골드가 없으면 팩 열기가 꺼져 있고 어디서 버는지 알려준다", function()
		local _, _, kim = openShop()
		local gui = guiOf(kim)

		local buy = Screen.findButton(gui, "팩 열기")
		t:truthy(buy, "팩 열기 버튼이 보여야 합니다")
		t:falsy(buy.Active, "골드가 모자라면 꺼져 있어야 합니다")
		t:truthy(Screen.hasText(gui, "캠페인"), "골드를 어디서 버는지 말해줘야 합니다")
		t:truthy(Screen.hasText(gui, "모은 카드"), "모은 정도가 보여야 합니다")
	end)

	t:it("사면 다섯 장이 펼쳐지고 저장소까지 간다", function()
		local world, _, kim = openShop(130)
		t:eq(shopGold(kim), "130")

		Screen.click(Screen.findButton(guiOf(kim), "팩 열기"))
		world:advance(1)
		assertNoErrors(world, "팩 사기")

		t:eq(Screen.countNamed(guiOf(kim), "Pull_"), 5, "나온 카드가 다섯 장 펼쳐져야 합니다")

		--[[
			화면 문구만 보면 "샀다고 말하는 것" 까지밖에 확인이 안 된다. 저장된 값을 본다.
			spent 는 가격에서 중복 환급을 뺀 순지출이라 100 이하다.
		]]
		local stored = collectionOf(world, kim)
		t:truthy(stored, "컬렉션이 저장돼야 합니다")
		t:eq(stored.opened, 1)
		t:truthy(stored.spent > 0 and stored.spent <= 100, ("순지출 %s"):format(tostring(stored.spent)))
		t:eq(shopGold(kim), tostring(130 - stored.spent), "잔액이 줄어 있어야 합니다")
	end)

	--[[
		버튼을 꺼둔 것은 화면의 편의다. 서버가 잔액을 다시 본다 (Lobby:buyPack).
	]]
	t:it("골드가 모자란데 리모트로 사려 해도 거부한다", function()
		local world, lobby, kim = openShop(40)

		lobby.remotes.Lobby._serverSignal:Fire(kim, { kind = "buyPack" })
		world:advance(1)
		assertNoErrors(world, "모자란 골드로 사기")

		t:truthy(Screen.hasText(guiOf(kim), "모자랍니다"), "왜 안 되는지 말해줘야 합니다")
		t:eq(Screen.countNamed(guiOf(kim), "Pull_"), 0, "카드가 나오면 안 됩니다")
		t:eq(collectionOf(world, kim).opened, 0, "저장소에 산 기록이 남으면 안 됩니다")
	end)

	t:it("산 카드는 덱 편집에 바로 나타난다", function()
		local world, _, kim = openShop(1000)

		for _ = 1, 3 do
			Screen.click(Screen.findButton(guiOf(kim), "팩 열기"))
			world:advance(1)
		end
		assertNoErrors(world, "팩 세 봉")

		Screen.click(Screen.findButton(guiOf(kim), "뒤로"))
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "덱 편집"))
		world:advance(1)
		assertNoErrors(world, "산 뒤 덱 편집")

		-- 저장된 컬렉션의 매수가 목록의 "덱/가진 것" 에 그대로 나와야 한다.
		local catalog = Screen.find(guiOf(kim), "Catalog")
		for _, entry in collectionOf(world, kim).cards do
			local count = Screen.find(Screen.findNamed(catalog, "Card_" .. entry.id), "Count")
			t:truthy(
				count and count.Text:sub(-#tostring(entry.count) - 1) == "/" .. entry.count,
				("%s 는 %d장 가졌는데 목록에는 '%s'"):format(entry.id, entry.count, tostring(count and count.Text))
			)
		end
	end)

	--[[
		캠페인 목록 머리의 골드도 **쓸 수 있는 골드**여야 한다. 번 합을 그대로 보여주면
		상점과 숫자가 달라서 "골드가 어디 갔나" 가 된다.
	]]
	t:it("캠페인 목록의 골드도 쓴 만큼 줄어 있다", function()
		local world, _, kim = openShop(130)

		Screen.click(Screen.findButton(guiOf(kim), "팩 열기"))
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "뒤로"))
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "캠페인"))
		world:advance(1)
		assertNoErrors(world, "산 뒤 캠페인 목록")

		local purse = Screen.find(Screen.find(guiOf(kim), "TCGCampaign"), "Purse")
		local balance = tostring(130 - collectionOf(world, kim).spent)
		t:truthy(Screen.hasText(purse, balance), ("캠페인 목록에 잔액 %s 가 떠야 합니다"):format(balance))
	end)

	--------------------------------------------------------------------
	-- Robux 팩 (규칙은 tests/specs/collection.luau 의 "Robux 팩")
	--------------------------------------------------------------------

	--[[
		영수증은 진짜로는 Roblox 가 보낸다. 여기서는 서버가 꽂아둔 ProcessReceipt 를
		테스트가 직접 부른다. 상품 ID 는 설정 파일의 값을 그대로 쓴다 — 0(아직 상품 없음)
		이어도 서버는 "그 ID 의 영수증" 으로 처리한다. 진짜 영수증에 0 이 올 일은 없다.
	]]
	local Products = require("../src/shared/Products")

	local function receipt(lobby, player, purchaseId, productId)
		local handler = lobby.marketplace and lobby.marketplace.ProcessReceipt
		assert(handler, "로비가 MarketplaceService.ProcessReceipt 를 걸어야 합니다")
		return tostring(handler({
			PlayerId = player.UserId,
			ProductId = productId or Products.robuxPack,
			PurchaseId = purchaseId,
			CurrencySpent = 99,
		}))
	end

	local GRANTED = "Enum.ProductPurchaseDecision.PurchaseGranted"
	local NOT_YET = "Enum.ProductPurchaseDecision.NotProcessedYet"

	t:it("상품 ID 가 비어 있으면 Robux 버튼이 없다", function()
		local _, _, kim = openShop()
		local button = Screen.findButton(guiOf(kim), "Robux로 열기")

		if Products.robuxPack == 0 then
			t:falsy(button, "상품을 만들기 전에는 버튼이 보이면 안 됩니다")
		else
			t:truthy(button, "상품 ID 가 있으면 버튼이 보여야 합니다")
		end
	end)

	t:it("영수증이 오면 팩이 들어가고 화면에 펼쳐진다", function()
		local world, lobby, kim = openShop()

		t:eq(receipt(lobby, kim, "purchase-1"), GRANTED)
		world:advance(1)
		assertNoErrors(world, "Robux 영수증")

		t:eq(Screen.countNamed(guiOf(kim), "Pull_"), 5, "카드팩 화면에 있으면 바로 펼쳐져야 합니다")

		local stored = collectionOf(world, kim)
		t:eq(stored.opened, 1)
		t:truthy(stored.spent <= 0, "골드를 쓰면 안 됩니다")
		t:eq(stored.receipts and stored.receipts[1], "purchase-1", "영수증이 카드와 같이 저장돼야 합니다")
	end)

	--[[
		Roblox 는 "처리했다" 를 못 받으면 같은 영수증을 다시 보낸다. 두 번 주면 안 되고,
		두 번째에도 **처리했다고 답해야** 한다 — 아니면 영원히 다시 온다.
	]]
	t:it("같은 영수증이 다시 와도 한 번만 준다", function()
		local world, lobby, kim = openShop()

		t:eq(receipt(lobby, kim, "purchase-1"), GRANTED)
		world:advance(1)
		t:eq(receipt(lobby, kim, "purchase-1"), GRANTED, "다시 온 영수증에도 처리했다고 답해야 합니다")
		world:advance(1)
		assertNoErrors(world, "같은 영수증 두 번")

		t:eq(collectionOf(world, kim).opened, 1, "팩은 한 봉만 들어가야 합니다")
	end)

	--[[
		서버가 바뀌어도(다른 로비로 재접속) 저장소의 영수증 기록이 막아야 한다.
		캐시만 보고 판단하면 새 서버에서 또 준다.
	]]
	t:it("다른 서버로 다시 와도 같은 영수증은 주지 않는다", function()
		local world, lobby, kim = openShop()
		t:eq(receipt(lobby, kim, "purchase-1"), GRANTED)
		world:advance(1)

		-- 같은 사람이 다른 로비로 옮겨 간다 (하네스의 텔레포트가 사람을 옮기는 방식과 같다).
		local other = world:newServer():boot()
		lobby:removePlayer(kim)
		other:addPlayer(kim.Name, { player = kim })
		world:advance(2)

		t:eq(receipt(other, kim, "purchase-1"), GRANTED)
		world:advance(1)
		assertNoErrors(world, "다른 서버에서 같은 영수증")

		t:eq(collectionOf(world, kim).opened, 1, "다른 서버에서도 한 봉만이어야 합니다")
	end)

	t:it("모르는 상품과 접속해 있지 않은 사람의 영수증은 미룬다", function()
		local world, lobby, kim = openShop()

		t:eq(receipt(lobby, kim, "other-product", Products.robuxPack + 987654), NOT_YET)
		t:eq(receipt(lobby, { UserId = 424242 }, "someone-else"), NOT_YET, "나간 사람 것은 다음 접속에 처리합니다")
		world:advance(1)
		assertNoErrors(world, "미루는 영수증")

		t:eq(collectionOf(world, kim).opened, 0)
	end)
end)

--==========================================================================
-- 꾸미기 (카드 테두리) — 규칙은 tests/specs/cosmetics.luau
--==========================================================================

t:describe("꾸미기", function()
	local PROGRESS = "CampaignProgress_v1"
	-- 순수 테이블만 읽는다 (Cosmetics/init 은 script.Parent 를 써서 Lune 에서 바로 못 읽는다).
	local FrameTable = require("../src/shared/Cosmetics/Frames")
	local DEFAULT, BASIC = FrameTable.default, nil

	-- 처음 사는 테두리. 테스트가 목록 순서에 묶이지 않게 "가격이 있는 첫 칸" 으로 고른다.
	local PAID
	for _, frame in FrameTable.list do
		if frame.id == DEFAULT then
			BASIC = frame
		elseif frame.price > 0 and not PAID then
			PAID = frame
		end
	end

	local function giveGold(world, player, gold)
		world.dataStores[PROGRESS] = world.dataStores[PROGRESS] or {}
		world.dataStores[PROGRESS][("user_%d"):format(player.UserId)] = { cleared = 2, gold = gold }
	end

	local function openWardrobe(gold)
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		if gold then
			giveGold(world, kim, gold)
		end
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "꾸미기"))
		world:advance(1)
		assertNoErrors(world, "꾸미기 열기")
		return world, lobby, kim
	end

	local function act(player, id)
		return Screen.find(Screen.find(guiOf(player), "TCGWardrobe"), "Act_" .. id)
	end

	-- 같은 색인가. 하네스의 Color3 는 0~1 실수라 반올림해서 비교한다.
	local function sameColor(color, rgb)
		return math.round(color.R * 255) == rgb[1]
			and math.round(color.G * 255) == rgb[2]
			and math.round(color.B * 255) == rgb[3]
	end

	-- 내 손패 카드가 전부 이 테두리로 둘러져 있는가 (하이라이트가 켜진 카드는 뺀다).
	local function handFramedWith(world, player, frame)
		local cards = allNamedIn(guiOf(player), "Hand_")
		if #cards == 0 then
			return false, "손패가 없습니다"
		end
		for _, card in cards do
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke and stroke.Thickness < 4 then
				if not sameColor(stroke.Color, frame.color) or stroke.Thickness ~= frame.thickness then
					return false, ("%s 의 테두리가 %s 가 아닙니다"):format(card.Name, frame.id)
				end
			end
		end
		return true
	end

	t:it("시작 화면에서 열리고 기본 테두리를 끼고 있다", function()
		local _, _, kim = openWardrobe()
		local gui = guiOf(kim)

		t:eq(Screen.countNamed(gui, "Item_FRAME_"), #FrameTable.list, "테두리마다 한 칸씩 있어야 합니다")
		t:eq(Screen.countNamed(gui, "Item_BACK_"), 0, "처음에는 테두리 탭만 보여야 합니다")
		t:eq(act(kim, DEFAULT).Text, "끼는 중")
		t:falsy(act(kim, PAID.id).Active, "골드가 없으면 [사기] 가 꺼져 있어야 합니다")
	end)

	t:it("사면 바로 끼워지고 저장소까지 간다", function()
		local world, _, kim = openWardrobe(500)

		Screen.click(act(kim, PAID.id))
		world:advance(1)
		assertNoErrors(world, "테두리 사기")

		t:eq(act(kim, PAID.id).Text, "끼는 중")
		t:eq(act(kim, DEFAULT).Text, "끼기", "기본 테두리는 다시 낄 수 있어야 합니다")

		local stored = collectionOf(world, kim)
		t:truthy(stored and stored.cosmetics, "테두리가 컬렉션에 저장돼야 합니다")
		t:eq(stored.cosmetics.frame, PAID.id)
		t:eq(stored.spent, PAID.price)

		local gold = Screen.find(Screen.find(guiOf(kim), "TCGWardrobe"), "Gold")
		t:eq(gold.Text, tostring(500 - PAID.price), "잔액이 줄어 있어야 합니다")
	end)

	t:it("골드가 모자란데 리모트로 사려 해도 거부한다", function()
		local world, lobby, kim = openWardrobe(10)

		lobby.remotes.Lobby._serverSignal:Fire(kim, { kind = "buyCosmetic", id = PAID.id })
		world:advance(1)
		assertNoErrors(world, "모자란 골드로 테두리 사기")

		t:truthy(Screen.hasText(guiOf(kim), "모자랍니다"), "왜 안 되는지 말해줘야 합니다")
		local stored = collectionOf(world, kim)
		t:falsy(stored and stored.cosmetics and stored.cosmetics.frame == PAID.id, "안 산 테두리가 저장되면 안 됩니다")
	end)

	t:it("안 산 테두리를 리모트로 끼려 해도 거부한다", function()
		local world, lobby, kim = openWardrobe(1000)

		lobby.remotes.Lobby._serverSignal:Fire(kim, { kind = "equipCosmetic", id = PAID.id })
		world:advance(1)
		assertNoErrors(world, "안 산 테두리 끼기")

		t:truthy(Screen.hasText(guiOf(kim), "가지지 않은"), "왜 안 되는지 말해줘야 합니다")
		t:eq(act(kim, DEFAULT).Text, "끼는 중")
	end)

	t:it("낀 테두리가 AI 연습의 내 손패에 둘러진다", function()
		local world, _, kim = openWardrobe(500)
		Screen.click(act(kim, PAID.id))
		world:advance(1)

		Screen.click(Screen.findButton(guiOf(kim), "뒤로"))
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		assertNoErrors(world, "테두리 끼고 AI 연습")

		t:truthy(handFramedWith(world, kim, PAID))
	end)

	--[[
		테두리는 사람에 붙는다. 같은 판의 두 사람이 서로 다른 테두리로 보여야 한다 —
		좌석이 뒤바뀌면 내 카드가 상대 테두리로 그려진다.
	]]
	t:it("같은 판의 두 사람은 각자 자기 테두리로 그려진다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		local lee = lobby:addPlayer("Lee")
		giveGold(world, kim, 500)
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "꾸미기"))
		world:advance(1)
		Screen.click(act(kim, PAID.id))
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "뒤로"))
		world:advance(1)

		clickQueue(kim)
		clickQueue(lee)
		world:advance(6)
		assert(passMulligan(world, kim, lee), "멀리건 관문을 통과하지 못했습니다")
		assertNoErrors(world, "테두리 끼고 PvP")

		t:truthy(handFramedWith(world, kim, PAID))
		t:truthy(handFramedWith(world, lee, BASIC))
	end)

	--------------------------------------------------------------------
	-- 카드 뒷면
	--------------------------------------------------------------------

	local BackTable = require("../src/shared/Cosmetics/Backs")
	local PAID_BACK, BASIC_BACK
	for _, back in BackTable.list do
		if back.id == BackTable.default then
			BASIC_BACK = back
		elseif back.price > 0 and not PAID_BACK then
			PAID_BACK = back
		end
	end

	local function openBackTab(world, player)
		Screen.click(Screen.find(Screen.find(guiOf(player), "TCGWardrobe"), "Tab_backs"))
		world:advance(0.5)
	end

	-- 이 패널의 뒷면 카드가 전부 이 뒷면 바탕인가.
	local function backsIn(panel, back)
		local cards = allNamedIn(panel, "CardBack")
		if #cards == 0 then
			return false, "뒷면 카드가 없습니다"
		end
		for _, card in cards do
			if not sameColor(card.BackgroundColor3, back.base) then
				return false, ("뒷면이 %s 가 아닙니다"):format(back.id)
			end
		end
		return true
	end

	t:it("뒷면 탭으로 바꾸면 뒷면 칸이 보인다", function()
		local world, _, kim = openWardrobe()
		openBackTab(world, kim)
		assertNoErrors(world, "뒷면 탭")

		local gui = guiOf(kim)
		t:eq(Screen.countNamed(gui, "Item_BACK_"), #BackTable.list, "뒷면마다 한 칸씩 있어야 합니다")
		t:eq(Screen.countNamed(gui, "Item_FRAME_"), 0, "테두리 칸은 숨어야 합니다")
		t:eq(act(kim, BackTable.default).Text, "끼는 중")

		-- 칸마다 등급 글자가 붙는다 (Grades.luau)
		local GradeTable = require("../src/shared/Cosmetics/Grades")
		local gradeName = {}
		for _, grade in GradeTable.list do
			gradeName[grade.id] = grade.name
		end
		for _, back in BackTable.list do
			local tag = Screen.find(Screen.find(gui, "Item_" .. back.id), "ItemGrade")
			t:eq(tag and tag.Text, gradeName[back.grade], back.id .. " 의 등급 글자")
		end
	end)

	t:it("뒷면을 사도 보던 탭에 그대로 있고 테두리는 안 바뀐다", function()
		local world, _, kim = openWardrobe(500)
		Screen.click(act(kim, PAID.id))
		world:advance(1)

		openBackTab(world, kim)
		Screen.click(act(kim, PAID_BACK.id))
		world:advance(1)
		assertNoErrors(world, "뒷면 사기")

		t:eq(act(kim, PAID_BACK.id).Text, "끼는 중", "산 뒷면이 바로 끼워져야 합니다")
		t:eq(Screen.countNamed(guiOf(kim), "Item_BACK_"), #BackTable.list, "사고 나서도 뒷면 탭이어야 합니다")

		local stored = collectionOf(world, kim)
		t:eq(stored.cosmetics.back, PAID_BACK.id)
		t:eq(stored.cosmetics.frame, PAID.id, "뒷면을 샀다고 테두리가 바뀌면 안 됩니다")
		t:eq(stored.spent, PAID.price + PAID_BACK.price)
	end)

	--[[
		뒷면은 **상대 화면에서** 보인다. 내 화면의 상대 패널에는 상대 뒷면이 뜬다.
		좌석이 뒤바뀌면 내 뒷면이 내 화면에 뜨는데, 그건 아무 의미가 없는 꾸밈이 된다.
	]]
	t:it("상대 화면에서 내 손패가 내 뒷면으로 보인다", function()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		local lee = lobby:addPlayer("Lee")
		giveGold(world, kim, 500)
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "꾸미기"))
		world:advance(1)
		openBackTab(world, kim)
		Screen.click(act(kim, PAID_BACK.id))
		world:advance(1)
		Screen.click(Screen.findButton(guiOf(kim), "뒤로"))
		world:advance(1)

		clickQueue(kim)
		clickQueue(lee)
		world:advance(6)
		assert(passMulligan(world, kim, lee), "멀리건 관문을 통과하지 못했습니다")
		assertNoErrors(world, "뒷면 끼고 PvP")

		t:truthy(backsIn(Screen.find(guiOf(lee), "FoePanel"), PAID_BACK))
		t:truthy(backsIn(Screen.find(guiOf(kim), "FoePanel"), BASIC_BACK))
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
-- 넘치는 줄
--==========================================================================

--[[
	가로로 스크롤하는 줄(손패·필드)은 **넘칠 때만** 왼쪽으로 붙어야 한다.

	가운데 정렬은 내용이 줄보다 넓어지면 양쪽으로 똑같이 넘쳐서 왼쪽 카드가 잘리고,
	캔버스는 0 부터라 스크롤로도 거기까지 못 간다. 그렇다고 늘 왼쪽이면 카드가
	두세 장일 때 화면이 왼쪽으로 쏠린다.

	예전에는 UIListLayout 의 HorizontalAlignment 를 갈아끼워서 이걸 했다. 지금은
	줄에 레이아웃이 없다 — 카드에 위치 트윈을 걸려면 레이아웃이 없어야 해서,
	Battle:placeRow 가 자리를 직접 계산한다. 그래서 **재는 대상도 카드의 실제 x 좌표**다.
	요구사항은 그대로고 확인하는 방법만 바뀌었다.

	이 하네스는 레이아웃을 계산하지 않으므로(AbsoluteSize 는 항상 0) 줄 넓이를 직접
	넣어 상황을 만든다. 카드 장수는 판이 정하므로 좌표를 숫자로 못 박지 않고,
	"왼쪽 끝인가(0) / 안쪽으로 들어왔는가(>0)" 만 본다.
]]
t:describe("넘치는 줄", function()
	local function handRow()
		local world = Roblox.newWorld()
		local lobby = world:newServer():boot()
		local kim = lobby:addPlayer("Kim")
		world:advance(2)

		Screen.click(Screen.findButton(guiOf(kim), "AI 연습"))
		world:advance(3)
		t:truthy(passMulligan(world, kim), "멀리건 관문을 통과하지 못했습니다")

		return world, kim, Screen.find(guiOf(kim), "Hand")
	end

	-- 줄에서 가장 왼쪽 카드의 x. 카드가 한 장도 없으면 실패시킨다.
	local function leftmostX(row)
		local best
		for _, child in row:GetChildren() do
			if child.ClassName == "TextButton" then
				if not best or child.LayoutOrder < best.LayoutOrder then
					best = child
				end
			end
		end
		t:truthy(best, "손패에 카드가 없습니다")
		return best.Position.X.Offset
	end

	local function setWidth(world, row, width)
		row.AbsoluteSize = Roblox.Datatypes.Vector2.new(width, 190)
		world:advance(0.2)
	end

	t:it("평소에는 가운데로 모은다", function()
		local world, _, row = handRow()

		setWidth(world, row, 4000)

		t:truthy(leftmostX(row) > 0, "카드가 몇 장 없을 때 왼쪽으로 쏠리면 안 됩니다")
	end)

	t:it("줄보다 길어지면 왼쪽으로 붙는다", function()
		local world, _, row = handRow()

		setWidth(world, row, 100)

		t:eq(leftmostX(row), 0, "넘치는데 가운데로 두면 왼쪽 카드가 잘리고 스크롤로도 못 간다")
	end)

	t:it("다시 줄어들면 가운데로 돌아온다", function()
		local world, _, row = handRow()

		setWidth(world, row, 100)
		t:eq(leftmostX(row), 0, "먼저 넘치는 상황을 만들지 못했습니다")

		setWidth(world, row, 4000)

		t:truthy(leftmostX(row) > 0, "줄이 넓어졌으면 다시 가운데로 모여야 합니다")
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
