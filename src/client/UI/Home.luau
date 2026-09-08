--[[
	시작 화면. 로비가 아니라 **버튼 두 개짜리 대기실** 이다.

	기획을 로비에서 빠른 대전으로 바꾼 이유가 그대로 화면에 드러난다 —
	돌아다닐 공간도, 방 목록도, 대기실 채팅도 없다. 접속하면 바로 이 화면이고,
	누를 것은 둘뿐이다.

	    [ 빠른 대전 ]   큐에 서서 사람을 찾는다 (크로스서버)
	    [ AI 연습   ]   큐를 타지 않고 이 서버에서 바로 한 판

	큐에 서면 두 버튼이 사라지고 경과 시간과 취소 버튼만 남는다. "찾는 중에도
	연습을 누를 수 있는" 상태를 만들면 연습 도중에 매칭이 잡히는 사고가 난다.

	화면 상태는 서버가 정한다(Net.LobbyScreen). 여기서는 받은 걸 그리기만 한다.
]]

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local new = Widgets.new

local Home = {}
Home.__index = Home

function Home.new(parent)
	local self = setmetatable({}, Home)

	local noop = function() end
	self.callbacks = { queue = noop, cancel = noop, practice = noop }

	self.screen = "home"
	self.queuedSince = nil

	self:build(parent)
	self:startClock()
	return self
end

--==========================================================================
-- 뼈대
--==========================================================================

function Home:build(parent)
	local gui = new("ScreenGui", {
		Name = "TCGHome",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Parent = parent,
	})
	self.gui = gui

	local root = new("Frame", {
		Name = "Root",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color.bg,
		BorderSizePixel = 0,
	}, {
		new("UIGradient", {
			Color = ColorSequence.new(Theme.color.bgDeep, Theme.color.bg),
			Rotation = 90,
		}),
	})

	Widgets.autoScale(root)

	local column = new("Frame", {
		Name = "Column",
		Parent = root,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 420),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center),
	})

	Widgets.label("TCG", {
		Parent = column,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 56),
		Font = Theme.font.bold,
		TextSize = 52,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	self.subtitle = Widgets.label("빠른 대전", {
		Parent = column,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = Theme.text.label,
		TextColor3 = Theme.color.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	--------------------------------------------------------------------
	-- 시작 화면의 버튼 두 개
	--------------------------------------------------------------------
	self.menu = new("Frame", {
		Name = "Menu",
		Parent = column,
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 142),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center),
	})

	self.queueButton = Widgets.button("빠른 대전", {
		Parent = self.menu,
		LayoutOrder = 1,
		Size = UDim2.new(0, 320, 0, 62),
		BackgroundColor3 = Theme.color.creature,
		TextSize = 24,
	}, function()
		self.callbacks.queue()
	end)

	self.practiceButton = Widgets.button("AI 연습", {
		Parent = self.menu,
		LayoutOrder = 2,
		Size = UDim2.new(0, 320, 0, 50),
		TextSize = Theme.text.title,
	}, function()
		self.callbacks.practice()
	end)

	--------------------------------------------------------------------
	-- 큐에 서 있는 동안
	--------------------------------------------------------------------
	self.waitBox = Widgets.panel({
		Name = "Wait",
		Parent = column,
		LayoutOrder = 4,
		Visible = false,
		Size = UDim2.new(0, 340, 0, 150),
	}, {
		Widgets.padding(16),
		Widgets.listLayout(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center),
	})

	self.waitTitle = Widgets.label("", {
		Parent = self.waitBox,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	self.waitTimer = Widgets.label("", {
		Parent = self.waitBox,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 36),
		Font = Theme.font.bold,
		TextSize = 30,
		TextColor3 = Theme.color.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	self.cancelButton = Widgets.button("취소", {
		Parent = self.waitBox,
		LayoutOrder = 3,
		Visible = false,
		Size = UDim2.new(0, 180, 0, 38),
		TextSize = Theme.text.label,
	}, function()
		self.callbacks.cancel()
	end)

	--------------------------------------------------------------------
	-- 안내 / 오류
	--------------------------------------------------------------------
	self.message = Widgets.label("", {
		Parent = column,
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, 44),
		TextSize = Theme.text.body,
		TextColor3 = Theme.color.textDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
end

--==========================================================================
-- 경과 시간
--==========================================================================

local function formatWait(seconds)
	local whole = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(whole // 60, whole % 60)
end

--[[
	1초마다 대기 시간을 다시 그린다. 서버가 매초 알려주게 하면 아무것도 달라지지 않는
	메시지를 인원수만큼 계속 쏘게 된다 — 시계는 클라이언트가 돌린다.

	출발점은 서버가 준 경과 초(elapsed)고, 그 뒤로는 **내 시계로만** 센다.
	서버 시각에서 내 시각을 빼면 기기 시계가 어긋난 사람은 0:00 에 멈추거나
	처음부터 몇 분이 찍힌다. 두 시계를 섞지 않는 게 요점이다.
]]
function Home:startClock()
	task.spawn(function()
		while self.gui.Parent do
			if self.screen == "queued" and self.queuedBase then
				self.waitTimer.Text = formatWait(os.clock() - self.queuedBase)
			end
			task.wait(1)
		end
	end)
end

--==========================================================================
-- 렌더
--==========================================================================

function Home:setVisible(visible)
	self.gui.Enabled = visible
end

--[[
	payload 는 서버가 보낸 그대로다. (Net.LobbyScreen 참조)
]]
function Home:render(payload)
	local screen = payload.screen
	self.screen = screen

	local isHome = (screen == "home" or screen == "error")

	self.menu.Visible = isHome
	self.waitBox.Visible = not isHome
	self.message.Text = ""
	self.message.TextColor3 = Theme.color.textDim

	if screen == "home" then
		self.subtitle.Text = "빠른 대전"
		self.message.Text = payload.text or "상대를 찾아 바로 한 판. 사람이 없으면 AI 연습으로."
	elseif screen == "error" then
		self.subtitle.Text = "빠른 대전"
		self.message.Text = payload.text or "문제가 발생했습니다"
		self.message.TextColor3 = Theme.color.warn
	elseif screen == "queued" then
		-- os.clock 은 기기 시계와 무관한 단조 시계다. 서버 시각과 비교하지 않는다.
		local elapsed = tonumber(payload.elapsed) or 0
		self.queuedBase = os.clock() - math.max(0, elapsed)
		self.subtitle.Text = "매칭 중"
		self.waitTitle.Text = "상대를 찾는 중"
		self.waitTimer.Text = formatWait(elapsed)
		self.cancelButton.Visible = true
	elseif screen == "found" then
		self.subtitle.Text = "매칭 완료"
		self.waitTitle.Text = ("%s 님과 매칭됐습니다"):format(payload.opponent or "상대")
		self.waitTimer.Text = "이동 중…"
		self.cancelButton.Visible = false
	elseif screen == "waiting" then
		self.subtitle.Text = "대전 준비"
		self.waitTitle.Text = payload.text or "상대를 기다리는 중"
		self.waitTimer.Text = "…"
		self.cancelButton.Visible = false
	end
end

return Home
