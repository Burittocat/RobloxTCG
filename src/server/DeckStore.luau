--[[
	사람마다 저장된 덱.

	DataStore 는 **없을 수도, 실패할 수도 있다.**
	  · Studio 에서 "API 서비스 접근 허용" 이 꺼져 있으면 호출 자체가 에러다
	  · 게시된 서버에서도 호출 한도에 걸리거나 잠깐 실패한다

	그래서 여기서는 실패를 정상 경로로 취급한다 — 못 읽으면 스타터 덱으로 놀 수 있고,
	못 쓰면 "저장하지 못했습니다" 를 돌려준다. **저장 실패로 대전을 막지 않는다.**
	Studio 에서 덱 편집을 못 눌러 테스트가 막히는 쪽이 더 나쁘다.

	키는 UserId 다. 이름은 바뀌지만 UserId 는 안 바뀐다.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Decks = require(Shared.Decks)

--[[
	이름에 버전을 박아둔다. 저장 모양이 바뀌면 새 이름으로 가고, 옛 저장은 그대로 둔다 —
	덮어쓰면 되돌릴 수 없다.
]]
local STORE_NAME = "PlayerDecks_v1"

local DeckStore = {}
DeckStore.__index = DeckStore

function DeckStore.new()
	local self = setmetatable({}, DeckStore)

	self.cache = {} -- userId -> entries
	self.available = true

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)

	if ok then
		self.store = store
	else
		self.available = false
		warn("[TCG] DataStore 를 열지 못했습니다 — 덱은 이 서버에서만 유지됩니다: " .. tostring(store))
	end

	return self
end

local function keyFor(player)
	return ("user_%d"):format(player.UserId)
end

--[[
	저장된 덱. -> entries

	저장이 없거나 못 읽으면 스타터 덱을 준다. **nil 을 돌려주지 않는다** —
	부르는 쪽마다 "없으면 스타터" 를 다시 쓰게 되고, 한 곳이 빠지면 덱 없이 대전이 열린다.
]]
function DeckStore:get(player)
	local cached = self.cache[player.UserId]
	if cached then
		return cached
	end

	local entries = nil

	if self.store then
		local ok, stored = pcall(function()
			return self.store:GetAsync(keyFor(player))
		end)

		if not ok then
			warn(("[TCG] 덱을 읽지 못했습니다 (%s): %s"):format(player.Name, tostring(stored)))
		elseif stored ~= nil then
			-- 저장된 값도 믿지 않는다. 규칙이 바뀌었거나 손으로 고쳤을 수 있다.
			local valid, reason = Decks.validateEntries(stored)
			if valid then
				entries = stored
			else
				warn(("[TCG] 저장된 덱이 규칙에 맞지 않아 스타터로 되돌립니다 (%s): %s"):format(
					player.Name,
					tostring(reason)
				))
			end
		end
	end

	entries = entries or Decks.starterEntries()
	self.cache[player.UserId] = entries
	return entries
end

--[[
	덱을 저장한다. -> ok, reason

	검증을 통과한 것만 저장한다. 클라이언트가 보낸 값을 그대로 담으면 다음 접속 때
	그 값으로 판이 열린다 — 저장소는 신뢰 경계 안쪽이 아니다.
]]
function DeckStore:save(player, entries)
	local valid, reason = Decks.validateEntries(entries)
	if not valid then
		return false, reason
	end

	-- 화면에는 저장된 것으로 보이게 두고(캐시), 실제 기록은 아래에서 시도한다.
	self.cache[player.UserId] = entries

	if not self.store then
		return false, "저장소를 쓸 수 없습니다 (이 서버에서만 유지됩니다)"
	end

	local ok, err = pcall(function()
		self.store:UpdateAsync(keyFor(player), function()
			return entries
		end)
	end)

	if not ok then
		warn(("[TCG] 덱을 저장하지 못했습니다 (%s): %s"):format(player.Name, tostring(err)))
		return false, "저장하지 못했습니다 (잠시 뒤 다시 시도해주세요)"
	end

	return true
end

-- 접속을 끊은 사람의 캐시는 들고 있을 이유가 없다.
function DeckStore:forget(player)
	self.cache[player.UserId] = nil
end

return DeckStore
