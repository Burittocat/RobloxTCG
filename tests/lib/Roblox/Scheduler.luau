--[[
	가상 시계와 task 라이브러리.

	진짜로 기다리면 스모크 테스트 한 번이 분 단위가 된다 — AI 는 한 수에 0.55초를 쉬고,
	매칭 폴링은 2초 주기이며, 클라이언트는 0.5초마다 재시도한다.
	여기서는 시계를 테스트가 직접 감는다.

	    scheduler:advance(5)   -- 5초가 "흘렀다"

	코루틴 기반이라 게임 코드는 자기가 가상 시간 위에서 도는 줄 모른다.
	task.wait 는 진짜 Roblox 처럼 코루틴을 양보하고, 깨어날 시각이 되면 이어서 돈다.
]]

local Scheduler = {}
Scheduler.__index = Scheduler

-- 한 번 advance 할 때 쪼개는 간격. Roblox 의 프레임에 해당한다.
-- 이보다 짧은 wait 들이 순서대로 깨어나게 하려면 쪼개서 진행해야 한다.
local STEP = 1 / 30

function Scheduler.new()
	return setmetatable({
		clock = 0,
		sleepers = {}, -- { thread, wakeAt } — 자고 있는 코루틴
		pending = {}, -- 다음 스텝에 처음 돌 코루틴
		owned = {}, -- 우리가 만든 코루틴. 이것만 재운다
		errors = {},
	}, Scheduler)
end

--==========================================================================
-- task 라이브러리
--==========================================================================

--[[
	게임 코드에 주입할 task 테이블. 진짜 Roblox 의 task 와 같은 이름/의미다.
]]
function Scheduler:library()
	local scheduler = self

	return {
		spawn = function(fn, ...)
			return scheduler:spawn(fn, ...)
		end,

		defer = function(fn, ...)
			-- defer 는 "이번 프레임 끝에" 다. 여기서는 다음 스텝으로 미룬다.
			local thread = coroutine.create(fn)
			scheduler.owned[thread] = true
			table.insert(scheduler.pending, { thread = thread, args = table.pack(...) })
			return thread
		end,

		delay = function(seconds, fn, ...)
			local args = table.pack(...)
			return scheduler:spawn(function()
				scheduler:wait(seconds)
				fn(table.unpack(args, 1, args.n))
			end)
		end,

		wait = function(seconds)
			return scheduler:wait(seconds)
		end,

		cancel = function(thread)
			for index, sleeper in scheduler.sleepers do
				if sleeper.thread == thread then
					table.remove(scheduler.sleepers, index)
					return
				end
			end
		end,
	}
end

--==========================================================================
-- 내부
--==========================================================================

--[[
	코루틴 하나를 굴리다 죽으면 오류를 모아둔다.

	여기서 오류를 삼키지 않는 것이 이 하네스의 핵심이다 — Studio 라면 출력창에 빨간 줄로
	뜨고 끝났을 오류가, 테스트에서는 실패로 잡혀야 한다.
]]
function Scheduler:resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		table.insert(self.errors, tostring(err))
	end
end

function Scheduler:spawn(fn, ...)
	local thread = coroutine.create(fn)
	self.owned[thread] = true
	self:resume(thread, ...) -- Roblox 의 task.spawn 은 즉시 한 번 돌린다
	return thread
end

--[[
	seconds 뒤에 한 번 돌린다. 하네스 자신이 쓰는 지연(텔레포트 등)에 필요하다.
]]
function Scheduler:delay(seconds, fn, ...)
	local args = table.pack(...)
	return self:spawn(function()
		self:wait(seconds)
		fn(table.unpack(args, 1, args.n))
	end)
end

--[[
	호출한 코루틴을 재운다.

	우리가 만들지 않은 코루틴(= 테스트 본문)에서 부르면 재우는 대신 시계만 감는다.
	테스트 본문을 재우면 깨워줄 사람이 없어서 그대로 멈춘다.
]]
function Scheduler:wait(seconds)
	seconds = seconds or STEP

	local thread = coroutine.running()
	if not thread or not self.owned[thread] then
		self:advance(seconds)
		return seconds
	end

	table.insert(self.sleepers, { thread = thread, wakeAt = self.clock + seconds })
	coroutine.yield()
	return seconds
end

--==========================================================================
-- 시계 감기
--==========================================================================

function Scheduler:step(delta)
	self.clock += delta

	-- 이번 스텝에 처음 도는 코루틴
	local starting = self.pending
	self.pending = {}
	for _, entry in starting do
		self:resume(entry.thread, table.unpack(entry.args, 1, entry.args.n))
	end

	-- 깨어날 시각이 지난 코루틴. 깨우는 중에 또 재우는 경우가 있으므로
	-- 목록을 먼저 갈라놓고 돈다.
	local due, remaining = {}, {}
	for _, sleeper in self.sleepers do
		if sleeper.wakeAt <= self.clock then
			table.insert(due, sleeper)
		else
			table.insert(remaining, sleeper)
		end
	end
	self.sleepers = remaining

	table.sort(due, function(a, b)
		return a.wakeAt < b.wakeAt
	end)

	for _, sleeper in due do
		self:resume(sleeper.thread)
	end
end

--[[
	seconds 만큼 시간을 흘린다. STEP 단위로 쪼개므로 그 사이에 여러 번 깨어나는
	코루틴도 순서대로 돈다.
]]
function Scheduler:advance(seconds)
	local steps = math.max(1, math.ceil(seconds / STEP))
	local delta = seconds / steps

	for _ = 1, steps do
		self:step(delta)
	end
end

--[[
	쌓인 오류를 돌려주고 비운다. 테스트가 매 단계 뒤에 확인한다.
]]
function Scheduler:takeErrors()
	local errors = self.errors
	self.errors = {}
	return errors
end

return Scheduler
