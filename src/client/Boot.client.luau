--[[
	클라이언트 부팅.

	하는 일은 넷뿐이다.
	  1. 카드 DB 를 로드한다 (판정 함수가 카드 정의를 봐야 하므로 클라도 갖고 있어야 한다)
	  2. 시작 화면과 전투 화면을 만들어 App 에 맡긴다
	  3. 서버에 "왔다" 를 알린다 → 서버가 어느 화면을 보여줄지 정해준다
	  4. 단축키를 연결한다

	카드 게임이라 캐릭터가 필요 없다. 카메라를 고정하고 코어 UI 를 끈다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)
local Cards = require(Shared.Cards)
local Net = require(Shared.Net)

local App = require(script.Parent.App)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

Cards.load()
print(("[TCG] 클라이언트 룰 로드 완료 (카드 %d장)"):format(Rules.Registry.count()))

--==========================================================================
-- 화면 정리
--==========================================================================

local camera = workspace.CurrentCamera
if camera then
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(0, 8, 0)
end

-- 코어 UI 는 스튜디오 첫 프레임에 아직 준비가 안 돼 실패할 수 있다.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		if ok then
			break
		end
		task.wait(0.2)
	end
end)

--==========================================================================
-- 조립
--==========================================================================

local remotes = Net.remotes()
local app = App.new(playerGui, remotes)

--==========================================================================
-- 단축키 (마우스만으로도 전부 되지만, 반복 조작은 키가 빠르다)
--==========================================================================

local SHORTCUTS = {
	[Enum.KeyCode.E] = "endPhase",
	[Enum.KeyCode.P] = "pass",
	[Enum.KeyCode.L] = "log",
	[Enum.KeyCode.Escape] = "cancel",
	[Enum.KeyCode.R] = "restart",
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	local action = SHORTCUTS[input.KeyCode]
	if not action then
		return
	end

	-- 전투 화면이 아닐 때는 아무 키도 먹지 않는다. 시작 화면에서 E 를 눌러
	-- 페이즈가 넘어가면 안 된다.
	if app.screen ~= Net.LobbyScreen.Battle then
		return
	end

	local controller = app.controller

	-- 새 판은 게임이 끝났을 때만. 진행 중에 R 을 잘못 눌러 판이 날아가면 안 된다.
	-- PvP 에는 "새 판" 자체가 없다 (매칭을 다시 타야 한다).
	if action == "restart" then
		if controller.matchMode ~= "practice" then
			return
		end
		if not (controller.view and controller.view.finished) then
			return
		end
	end

	controller:onAction(action)
end)

app:start()
