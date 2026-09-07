--[[
	RBXScriptSignal 흉내.

	Roblox 는 핸들러를 각자 별도 스레드에서 돌린다. 여기서도 그렇게 한다 —
	핸들러 안에서 task.wait 를 부르는 코드가 있고(MatchRunner 의 pump 가 그렇다),
	같은 스레드에서 돌리면 신호를 쏜 쪽이 같이 멈춰버린다.

	스케줄러는 신호보다 늦게 만들어지므로 모듈 전역으로 한 번만 꽂는다.
	테스트 프로세스 하나에 세계 하나라는 전제다.
]]

local Signal = {}
Signal.__index = Signal

local scheduler = nil

function Signal.useScheduler(value)
	scheduler = value
end

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(handler)
	table.insert(self.handlers, handler)

	local signal = self
	return {
		Connected = true,
		Disconnect = function(connection)
			connection.Connected = false
			for index, existing in signal.handlers do
				if existing == handler then
					table.remove(signal.handlers, index)
					break
				end
			end
		end,
	}
end

function Signal:Fire(...)
	-- 핸들러가 도중에 연결을 끊을 수 있으므로 사본을 돌린다.
	for _, handler in table.clone(self.handlers) do
		if scheduler then
			scheduler:spawn(handler, ...)
		else
			handler(...)
		end
	end
end

return Signal
