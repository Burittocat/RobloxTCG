--[[
	사람마다 가진 카드와 팩에 쓴 골드.

	실패를 다루는 방식은 CampaignStore 와 같다 — 컬렉션도 **되돌릴 수 없는 것을 쌓는다**
	(산 팩, 쓴 골드). 쓰기에 실패하면 캐시도 옛 값으로 되돌리고, 부르는 쪽이 그 자리에서
	"저장하지 못했습니다" 를 말한다.

	CampaignStore 에 없는 규칙이 하나 있다.

	**읽기에 실패한 사람의 컬렉션은 쓰지 않는다.** 못 읽었을 때 새 컬렉션(스타터)으로
	놀게 해주는 것까지는 덱·캠페인과 같다. 그런데 그 상태로 팩을 사서 저장하면, 실제로
	저장돼 있던 컬렉션(모아둔 카드 전부)을 스타터 + 한 팩으로 **덮어쓴다.** 그래서 읽기가
	실패한 사람은 이 서버에 있는 동안 팩을 못 산다 — 덱은 짤 수 있다.

	컬렉션이 저장돼 있지 않은 사람(처음 온 사람, 컬렉션이 생기기 전부터 있던 사람)은
	처음 읽을 때 만들어서 **바로 저장한다.** 미뤄두면 그 사이에 덱을 스타터로 되돌린 사람은
	다음 접속에 옛 덱에서 물려받을 카드를 잃는다 (Collection.new 의 base 참조).

	키는 UserId 다.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Collection = require(Shared.Collection)

-- 모양이 바뀌면 새 이름으로 간다. 덮어쓰면 되돌릴 수 없다. (DeckStore 와 같은 규칙)
local STORE_NAME = "PlayerCollection_v1"

local CollectionStore = {}
CollectionStore.__index = CollectionStore

function CollectionStore.new()
	local self = setmetatable({}, CollectionStore)

	self.cache = {} -- userId -> collection
	self.unreadable = {} -- userId -> true : 읽기에 실패했다. 이 사람 것은 쓰지 않는다

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)

	if ok then
		self.store = store
	else
		warn("[TCG] 컬렉션 저장소를 열지 못했습니다 — 컬렉션은 이 서버에서만 유지됩니다: " .. tostring(store))
	end

	return self
end

local function keyFor(player)
	return ("user_%d"):format(player.UserId)
end

--[[
	가진 카드. -> collection

	baseDeck 은 이 사람이 저장해둔 덱(엔트리 모양)이다. 컬렉션이 아직 없을 때만 쓰인다 —
	그 덱의 카드를 물려받는다 (Collection.new 참조).

	없거나 못 읽으면 새 컬렉션을 준다. **nil 을 돌려주지 않는다.**
]]
function CollectionStore:get(player, baseDeck)
	local cached = self.cache[player.UserId]
	if cached then
		return cached
	end

	local collection = nil
	local missing = false

	if self.store then
		local ok, stored = pcall(function()
			return self.store:GetAsync(keyFor(player))
		end)

		if not ok then
			warn(("[TCG] 컬렉션을 읽지 못했습니다 (%s): %s"):format(player.Name, tostring(stored)))
			self.unreadable[player.UserId] = true
		elseif stored == nil then
			missing = true
		else
			local valid, reason = Collection.validate(stored)
			if valid then
				collection = stored
			else
				--[[
					모양이 틀린 저장값은 새로 만든 것으로 **덮어쓰지 않는다.** 카드를 지운 뒤
					옛 저장을 읽으면 이렇게 되는데, 그 사람의 나머지 카드는 여전히 거기 있다.
					고칠 사람이 볼 수 있게 남겨두고, 이 서버에서는 읽기 실패처럼 다룬다.
				]]
				warn(("[TCG] 저장된 컬렉션이 맞지 않습니다 — 이번 접속에서는 쓰지 않습니다 (%s): %s"):format(
					player.Name,
					tostring(reason)
				))
				self.unreadable[player.UserId] = true
			end
		end
	end

	collection = collection or Collection.new(baseDeck)
	self.cache[player.UserId] = collection

	if missing then
		self:write(player, collection)
	end

	return collection
end

function CollectionStore:write(player, collection)
	local ok, err = pcall(function()
		self.store:UpdateAsync(keyFor(player), function()
			return collection
		end)
	end)

	if not ok then
		warn(("[TCG] 컬렉션을 저장하지 못했습니다 (%s): %s"):format(player.Name, tostring(err)))
	end
	return ok
end

--[[
	컬렉션을 저장한다. -> ok, reason

	실패하면 캐시를 옛 값으로 되돌린다. 팩을 산 결과가 화면에 남았는데 다음 접속에
	사라져 있는 쪽이 더 나쁘다 — 그럴 바에는 그 자리에서 "못 샀다" 고 말한다.

	저장소가 아예 없는 서버(Studio 에서 API 접근이 꺼져 있다)에서는 캐시에만 넣고
	ok 를 돌려준다. 그 서버에서는 무엇도 남지 않는다는 것을 이미 부팅 때 알렸고,
	Studio 에서 팩 화면을 한 번도 못 눌러보게 되는 쪽이 더 나쁘다.
]]
function CollectionStore:save(player, collection)
	local valid, reason = Collection.validate(collection)
	if not valid then
		return false, reason
	end

	if not self.store then
		self.cache[player.UserId] = collection
		return true
	end

	if self.unreadable[player.UserId] then
		return false, "가진 카드를 불러오지 못해 지금은 저장할 수 없습니다 (다시 접속해 주세요)"
	end

	local previous = self.cache[player.UserId]
	self.cache[player.UserId] = collection

	if not self:write(player, collection) then
		self.cache[player.UserId] = previous
		return false, "저장하지 못했습니다 (잠시 뒤 다시 시도해주세요)"
	end

	return true
end

--[[
	**다른 사람의** 컬렉션을 읽기만 한다. -> collection (못 읽으면 새 컬렉션)

	프로필 보기가 쓴다(낀 꾸밈 · 모은 정도). get 과 달리 캐시에 넣지 않고, **없어도 만들어
	저장하지 않는다** — 남의 저장값을 이 서버가 처음 만드는 일은 없어야 한다.
]]
function CollectionStore:read(userId)
	local cached = self.cache[userId]
	if cached then
		return cached
	end
	if not self.store then
		return Collection.new()
	end

	local ok, stored = pcall(function()
		return self.store:GetAsync(("user_%d"):format(userId))
	end)
	if ok and stored ~= nil and Collection.validate(stored) then
		return stored
	end
	return Collection.new()
end

-- 접속을 끊은 사람의 캐시는 들고 있을 이유가 없다.
function CollectionStore:forget(player)
	self.cache[player.UserId] = nil
	self.unreadable[player.UserId] = nil
end

return CollectionStore
