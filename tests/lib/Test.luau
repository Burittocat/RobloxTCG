--[[
	최소 테스트 프레임워크.

	외부 의존성 없이 Lune 만으로 돈다. describe/it 중첩과 몇 가지 단언이면 충분하다.
]]

local Test = {}
Test.__index = Test

local GREEN = "\27[32m"
local RED = "\27[31m"
local DIM = "\27[2m"
local RESET = "\27[0m"

function Test.new()
	return setmetatable({
		passed = 0,
		failed = 0,
		failures = {},
		path = {},
	}, Test)
end

function Test:_label()
	return table.concat(self.path, " › ")
end

function Test:describe(name, fn)
	table.insert(self.path, name)
	fn()
	table.remove(self.path)
end

function Test:it(name, fn)
	table.insert(self.path, name)
	local label = self:_label()

	local ok, err = pcall(fn)
	if ok then
		self.passed += 1
		print(("  %s✓%s %s"):format(GREEN, RESET, label))
	else
		self.failed += 1
		table.insert(self.failures, { label = label, err = tostring(err) })
		print(("  %s✗ %s%s"):format(RED, label, RESET))
		print(("    %s%s%s"):format(DIM, tostring(err), RESET))
	end

	table.remove(self.path)
end

--==========================================================================
-- 단언
--==========================================================================

local function fmt(value)
	if type(value) == "table" then
		return "<table>"
	end
	return tostring(value)
end

function Test:eq(actual, expected, message)
	if actual ~= expected then
		error(("%s: %s 를 기대했지만 %s"):format(message or "값 불일치", fmt(expected), fmt(actual)), 2)
	end
end

function Test:neq(actual, unexpected, message)
	if actual == unexpected then
		error(("%s: %s 가 아니어야 합니다"):format(message or "값 일치", fmt(unexpected)), 2)
	end
end

function Test:truthy(value, message)
	if not value then
		error(("%s: 참을 기대했지만 %s"):format(message or "단언 실패", fmt(value)), 2)
	end
end

function Test:falsy(value, message)
	if value then
		error(("%s: 거짓을 기대했지만 %s"):format(message or "단언 실패", fmt(value)), 2)
	end
end

--[[
	룰 액션은 (ok, reason) 을 돌려준다. 성공을 기대할 때 쓴다 —
	실패하면 엔진이 준 사유가 그대로 에러 메시지에 실린다.
]]
function Test:allowed(ok, reason, message)
	if not ok then
		error(("%s: 허용을 기대했지만 거부됨 — %s"):format(message or "액션 실패", tostring(reason)), 2)
	end
end

-- 거부를 기대할 때. 기대한 사유의 일부 문자열을 함께 확인할 수 있다.
function Test:denied(ok, reason, expectedSubstring, message)
	if ok then
		error(("%s: 거부를 기대했지만 통과함"):format(message or "액션 통과"), 2)
	end
	if expectedSubstring and not tostring(reason):find(expectedSubstring, 1, true) then
		error(
			("%s: 사유에 '%s' 를 기대했지만 '%s'"):format(
				message or "사유 불일치",
				expectedSubstring,
				tostring(reason)
			),
			2
		)
	end
end

function Test:report()
	print("")
	if self.failed == 0 then
		print(("%s%d개 통과, 실패 없음%s"):format(GREEN, self.passed, RESET))
		return true
	end

	print(("%s%d개 실패 / %d개 통과%s"):format(RED, self.failed, self.passed, RESET))
	for _, failure in self.failures do
		print(("  %s✗%s %s"):format(RED, RESET, failure.label))
	end
	return false
end

return Test
