--[[
	사람마다 캠페인 진행도와 골드.

	실패를 다루는 방식은 DeckStore 와 같다 — DataStore 는 없을 수도, 실패할 수도 있다.
	못 읽으면 처음부터인 것으로 놀 수 있고, 못 쓰면 알려만 준다. **저장 실패로 판을
	막지 않는다.** 그러면 Studio 에서 캠페인을 한 판도 못 돌려보게 된다.

	다만 덱과 다른 점이 하나 있다: 진행도는 **되돌릴 수 없는 것을 쌓는다.** 덱은 저장이
	실패해도 다시 짜면 그만이지만, 깬 스테이지와 받은 골드는 다시 깨야 한다. 그래서
	캐시에 먼저 넣고 낙관적으로 넘어가지 않고, 쓰기에 실패하면 **캐시도 되돌린다** —
	화면에 "깼다" 가 남았는데 다음 접속에 사라져 있는 쪽이 더 나쁘다.

	키는 UserId 다. 이름은 바뀌지만 UserId 는 안 바뀐다.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Campaign = require(Shared.Campaign)

-- 모양이 바뀌면 새 이름으로 간다. 덮어쓰면 되돌릴 수 없다. (DeckStore 와 같은 규칙)
local STORE_NAME = "CampaignProgress_v1"

local CampaignStore = {}
CampaignStore.__index = CampaignStore

function CampaignStore.new()
	local self = setmetatable({}, CampaignStore)

	self.cache = {} -- userId -> progress
	self.available = true

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)

	if ok then
		self.store = store
	else
		self.available = false
		warn("[TCG] 캠페인 저장소를 열지 못했습니다 — 진행도는 이 서버에서만 유지됩니다: " .. tostring(store))
	end

	return self
end

local function keyFor(player)
	return ("user_%d"):format(player.UserId)
end

--[[
	저장된 진행도. -> progress

	없거나 못 읽으면 처음부터인 진행도를 준다. **nil 을 돌려주지 않는다** —
	부르는 쪽마다 "없으면 처음부터" 를 다시 쓰게 되고, 한 곳이 빠지면 거기서 죽는다.
]]
function CampaignStore:get(player)
	local cached = self.cache[player.UserId]
	if cached then
		return cached
	end

	local progress = nil

	if self.store then
		local ok, stored = pcall(function()
			return self.store:GetAsync(keyFor(player))
		end)

		if not ok then
			warn(("[TCG] 캠페인 진행도를 읽지 못했습니다 (%s): %s"):format(player.Name, tostring(stored)))
		elseif stored ~= nil then
			-- 저장된 값도 믿지 않는다. 스테이지를 줄이면 옛 cleared 가 표 밖을 가리킨다.
			local valid, reason = Campaign.validateProgress(stored)
			if valid then
				progress = stored
			else
				warn(("[TCG] 저장된 캠페인 진행도가 맞지 않아 처음부터로 둡니다 (%s): %s"):format(
					player.Name,
					tostring(reason)
				))
			end
		end
	end

	progress = progress or Campaign.newProgress()
	self.cache[player.UserId] = progress
	return progress
end

--[[
	진행도를 저장한다. -> ok, reason

	실패하면 캐시를 옛 값으로 되돌린다 (위 주석 참조). 부르는 쪽은 돌려받은 ok 를 보고
	사람에게 무엇을 말할지 정한다.
]]
function CampaignStore:save(player, progress)
	local valid, reason = Campaign.validateProgress(progress)
	if not valid then
		return false, reason
	end

	local previous = self.cache[player.UserId]
	self.cache[player.UserId] = progress

	if not self.store then
		return false, "저장소를 쓸 수 없습니다 (이 서버에서만 유지됩니다)"
	end

	local ok, err = pcall(function()
		self.store:UpdateAsync(keyFor(player), function()
			return progress
		end)
	end)

	if not ok then
		warn(("[TCG] 캠페인 진행도를 저장하지 못했습니다 (%s): %s"):format(player.Name, tostring(err)))
		self.cache[player.UserId] = previous
		return false, "저장하지 못했습니다 (잠시 뒤 다시 시도해주세요)"
	end

	return true
end

--[[
	저장된 값 위에서 바꾼다. -> ok, gained, reason

	transform(progress) -> 새 진행도, 받은 골드, 못 받은 이유

	save 와 다른 점: save 는 이 서버의 캐시를 그대로 덮어쓴다. 로비에서는 그래도 된다 —
	한 사람은 한 서버에만 있다. 그런데 **PvP 보상은 대전 서버(예약 서버)가 쓴다.** 그
	서버의 캐시는 도착할 때 읽은 것이라, 그대로 덮으면 그 사이 다른 곳에서 쓴 값을 지운다.
	그래서 UpdateAsync 안에서 **지금 저장된 값**을 받아 그 위에서 계산한다.

	gained 가 0 이면 쓰지 않는다(상한에 걸렸다 등). 저장된 값이 모양이 틀렸으면 손대지
	않는다 — 새 진행도로 덮으면 깬 스테이지가 사라진다.
]]
function CampaignStore:update(player, transform)
	local gained, reason = 0, nil
	local result = nil

	if not self.store then
		result, gained, reason = transform(self:get(player))
		if gained > 0 then
			self.cache[player.UserId] = result
		end
		return true, gained, reason
	end

	local ok, err = pcall(function()
		self.store:UpdateAsync(keyFor(player), function(current)
			local base = current
			if base == nil then
				base = Campaign.newProgress()
			elseif not Campaign.validateProgress(base) then
				reason = "저장된 진행도가 맞지 않아 보상을 적지 못했습니다"
				gained = 0
				return nil
			end

			result, gained, reason = transform(base)
			if gained <= 0 then
				return nil
			end
			return result
		end)
	end)

	if not ok then
		warn(("[TCG] 진행도를 고치지 못했습니다 (%s): %s"):format(player.Name, tostring(err)))
		return false, 0, "저장하지 못했습니다 (잠시 뒤 다시 시도해주세요)"
	end

	if gained > 0 then
		self.cache[player.UserId] = result
	end
	return true, gained, reason
end

-- 접속을 끊은 사람의 캐시는 들고 있을 이유가 없다.
function CampaignStore:forget(player)
	self.cache[player.UserId] = nil
end

return CampaignStore
