--[[
	화면 두 장을 번갈아 띄우는 얇은 껍데기.

	    Home    시작 화면 · 매칭 대기
	    Battle  전투 화면 (Controller 가 조작을 맡는다)

	어느 쪽을 보여줄지는 **서버가 정한다.** 클라이언트가 스스로 판단하면
	"큐에서 빠졌는데 여전히 찾는 중" 같은 상태가 만들어지고, 그건 화면만 봐서는
	고칠 수도 없다. 서버가 Lobby 리모트로 보내는 screen 값이 유일한 근거다.

	    home / error   시작 화면
	    queued / found / waiting   시작 화면 위의 대기 표시
	    battle         전투 화면 — 여기서 Controller:start() 가 한 판을 연다
]]

local Net = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Net)

local Battle = require(script.Parent.UI.Battle)
local Home = require(script.Parent.UI.Home)
local DeckEditor = require(script.Parent.UI.DeckEditor)
local Controller = require(script.Parent.Controller)

local Screen = Net.LobbyScreen

local App = {}
App.__index = App

function App.new(playerGui, remotes)
	local self = setmetatable({}, App)

	self.remotes = remotes
	self.screen = nil
	self.acked = false

	self.home = Home.new(playerGui)
	self.battle = Battle.new(playerGui)
	self.deck = DeckEditor.new(playerGui)

	--[[
		덱 편집의 세 버튼. 저장·되돌리기는 서버가 판단하고 화면을 다시 내려주므로
		여기서는 보내기만 한다 — 클라이언트가 스스로 "저장됐다" 로 넘어가면,
		거부당한 덱이 저장된 것처럼 보인다.
	]]
	self.deck.callbacks.save = function()
		self:send({ kind = "deckSave", entries = self.deck:entries() })
	end
	self.deck.callbacks.reset = function()
		self:send({ kind = "deckReset" })
	end
	self.deck.callbacks.back = function()
		self:send({ kind = "home" })
	end
	self.controller = Controller.new(self.battle, remotes)

	self.home.callbacks.queue = function()
		self:send({ kind = "queue" })
	end
	self.home.callbacks.cancel = function()
		self:send({ kind = "cancel" })
	end
	self.home.callbacks.tutorial = function()
		self:send({ kind = "tutorial" })
	end
	self.home.callbacks.practice = function()
		self:send({ kind = "practice" })
	end
	self.home.callbacks.deck = function()
		self:send({ kind = "deck" })
	end

	remotes.Lobby.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.screen) == "string" then
			self.acked = true -- 서버가 우리를 안다. hello 재시도를 멈춘다
			self:show(payload)
		end
	end)

	self:show({ screen = Screen.Home })
	return self
end

function App:send(payload)
	self.remotes.Lobby:FireServer(payload)
end

--==========================================================================
-- 화면 전환
--==========================================================================

function App:show(payload)
	local screen = payload.screen
	local wasBattle = (self.screen == Screen.Battle)
	self.screen = screen

	if screen == Screen.Deck then
		self.home:setVisible(false)
		self.battle:setVisible(false)
		self.deck:setVisible(true)
		self.deck:load(payload)
		return
	end

	self.deck:setVisible(false)

	if screen == Screen.Battle then
		self.home:setVisible(false)
		self.battle:setVisible(true)

		-- 같은 판이 계속되는 중이면(재전송) 다시 시작하지 않는다.
		if not wasBattle then
			self.controller:setMatchMode(payload.mode or "pvp")
			self.controller:start()
		end
		return
	end

	self.battle:setVisible(false)
	self.home:setVisible(true)
	self.home:render(payload)
end

--==========================================================================
-- 부팅
--==========================================================================

--[[
	서버가 우리 존재를 알기 전에 우리가 먼저 뜨는 경우가 있다.
	첫 화면 지시가 올 때까지 "hello" 를 다시 보낸다.
]]
function App:start()
	task.spawn(function()
		for _ = 1, 20 do
			if self.acked then
				return
			end
			self:send({ kind = "hello" })
			task.wait(0.5)
		end
	end)
end

return App
