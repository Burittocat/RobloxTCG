--[[
	이 서버에서 돌고 있는 매치들의 명부.

	Action 리모트로 들어온 요청이 **어느 매치의 것인지** 는 보낸 Player 로만 정한다.
	클라이언트가 매치 id 를 실어 보내고 서버가 그걸 믿으면, 남의 판에 행동을 넣는
	요청을 만들 수 있게 된다. 그래서 여기 명부가 유일한 근거다.

	한 사람은 동시에 한 판만 둔다 — 로비의 AI 연습이든, 대전 서버의 PvP 든.
	그 전제 덕에 명부가 Player -> MatchRunner 단순 표로 끝난다.
]]

local Players = game:GetService("Players")

local Host = {}
Host.__index = Host

function Host.new(remotes)
	local self = setmetatable({}, Host)

	self.remotes = remotes
	self.runners = {} :: { [Player]: any }

	-- 수신을 먼저 연다. 클라이언트가 우리보다 빨리 뜨는 경우가 있다.
	remotes.Action.OnServerEvent:Connect(function(player, payload)
		self:onAction(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:playerLeft(player)
	end)

	return self
end

function Host:attach(runner)
	for _, player in runner:humanSeats() do
		self.runners[player] = runner
	end
end

function Host:detach(runner)
	for player, owner in self.runners do
		if owner == runner then
			self.runners[player] = nil
		end
	end
	runner:destroy()
end

function Host:runnerFor(player)
	return self.runners[player]
end

--[[
	이 사람을 판에서 뺀다. 진행 중이었다면 항복과 같다.
	사람이 하나도 안 남은 판은 접는다 — AI 루프가 빈 판을 계속 굴리면 안 된다.
]]
function Host:release(player)
	local runner = self.runners[player]
	self.runners[player] = nil

	if not runner then
		return
	end

	runner:playerLeft(player)
	if next(runner:humanSeats()) == nil then
		runner:destroy()
	end
end

function Host:onAction(player, payload)
	local runner = self.runners[player]
	if not runner then
		return
	end

	local ok, err = pcall(function()
		runner:handle(player, payload)
	end)

	if not ok then
		warn(("[TCG] 행동 처리 실패: %s"):format(tostring(err)))
		runner:sync()
	end
end

--[[
	나간 사람이 두고 있던 판은 남은 쪽의 승리로 닫는다.
	방치하면 상대는 영원히 자기 차례가 오지 않는 화면을 본다.
]]
function Host:playerLeft(player)
	self:release(player)
end

return Host
