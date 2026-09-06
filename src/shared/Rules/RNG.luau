--[[
	결정론적 난수.

	Roblox 의 Random 대신 직접 구현한 이유:
	  - 같은 시드 → 서버/클라/테스트에서 항상 같은 결과. 리플레이·데싱크 검증에 필요.
	  - 캠페인 세이브에 시드와 호출 횟수만 저장하면 전투 상황을 그대로 복원할 수 있다.

	Park-Miller(Lehmer) MINSTD. 주기 2^31-2 로 카드 게임 한 판에는 차고 넘친다.
	16807 * (2^31-2) ≈ 3.6e13 이라 double 정수 정밀도(2^53) 안에서 안전하다.
]]

local RNG = {}
RNG.__index = RNG

local MODULUS = 2147483647 -- 2^31 - 1
local MULTIPLIER = 16807

--[[
	seed: 임의의 정수. 0 이나 MODULUS 의 배수는 수열이 죽으므로 보정한다.
]]
function RNG.new(seed)
	local s = math.floor(tonumber(seed) or 0) % MODULUS
	if s <= 0 then
		s = s + MODULUS - 1
	end

	return setmetatable({ state = s, calls = 0 }, RNG)
end

-- 세이브/로드용. 상태를 그대로 직렬화한다.
function RNG.restore(snapshot)
	return setmetatable({ state = snapshot.state, calls = snapshot.calls }, RNG)
end

function RNG:snapshot()
	return { state = self.state, calls = self.calls }
end

function RNG:clone()
	return RNG.restore(self:snapshot())
end

-- 다음 원시 난수 (1 .. MODULUS-1)
function RNG:_next()
	self.state = (self.state * MULTIPLIER) % MODULUS
	self.calls += 1
	return self.state
end

-- [0, 1) 실수
function RNG:nextNumber()
	return (self:_next() - 1) / (MODULUS - 1)
end

-- [min, max] 정수. 인자 하나면 [1, n].
function RNG:nextInteger(min, max)
	if max == nil then
		min, max = 1, min
	end

	if max < min then
		error(("nextInteger: max(%d) < min(%d)"):format(max, min), 2)
	end

	local span = max - min + 1
	return min + (self:_next() % span)
end

--[[
	Fisher-Yates. 리스트를 제자리에서 섞고 그대로 돌려준다.
	덱 셔플이 이 함수 하나만 쓰도록 해서 재현성을 보장한다.
]]
function RNG:shuffle(list)
	for i = #list, 2, -1 do
		local j = self:nextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return RNG
