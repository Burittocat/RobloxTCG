--[[
	코스메틱 — 카드 테두리. 판에 아무 영향도 없는 **겉모습 레이어**다.

	Roblox API 를 쓰지 않는 순수 Luau 다(Collection · Campaign 과 같은 이유). "살 수 있나 ·
	가졌나 · 무엇을 끼고 있나" 판정에 DataStore 도 Player 도 필요 없어서, Studio 없이
	테스트로 못 박는다(tests/specs/cosmetics.luau).

	--------------------------------------------------------------------------
	카드 데이터와 왜 떼어 두나

	테두리는 **카드가 아니라 사람에게** 붙는다. 같은 `방패병` 이라도 누가 냈느냐에 따라
	테두리가 다르다. 그래서 카드 정의(Cards/Sheet)에도, 룰 상태(GameState)에도 들어가지
	않는다. 룰 엔진은 테두리를 모르고, 몰라야 한다 — 겉모습이 판정에 닿는 길이 아예 없다.

	흐름은 이렇다.
	  저장   컬렉션 저장값의 `cosmetics = { owned = { id, ... }, frame = id }`
	  판     MatchRunner 의 좌석이 frame 을 들고 있다가 스냅샷에 `frames` 로 싣는다
	  화면   CardView 가 카드를 낸 사람(controllerId)의 테두리로 칠한다

	--------------------------------------------------------------------------
	왜 컬렉션과 같은 저장값인가

	테두리는 골드로 산다. 골드의 **쓴 기록**(spent)은 컬렉션에 있다(Collection 머리말).
	테두리를 다른 저장소에 적으면 "골드는 빠졌는데 테두리는 안 들어간" 중간이 생긴다.
	같은 값에 적으면 사는 것이 **한 번의 쓰기**로 끝난다 — 카드팩과 같은 원리다.

	cosmetics 칸은 없어도 된다. 옛 저장값은 "기본 테두리만 가진 사람" 이다.
]]

local Collection = require(script.Parent.Collection)
local FrameTable = require(script.Frames)

local Cosmetics = {}

--==========================================================================
-- 테두리 목록 — 값은 Frames.luau (색 · 두께 · 가격의 뜻도 거기 적혀 있다)
--==========================================================================

Cosmetics.DefaultFrame = FrameTable.default
Cosmetics.Frames = FrameTable.list

local byId = {}
for _, frame in Cosmetics.Frames do
	byId[frame.id] = frame
end

-- 테두리 정의. 없는 id 면 nil.
function Cosmetics.frame(id)
	return byId[id]
end

--[[
	그릴 테두리. 없는 id 거나 nil 이면 기본 테두리다.

	화면은 이것만 부른다. 테두리를 지우거나 이름을 바꾼 뒤 옛 저장값이 오면 그 사람의
	카드가 테두리 없이(또는 에러로) 그려지는 대신 기본으로 돌아간다.
]]
function Cosmetics.frameOrDefault(id)
	return byId[id] or byId[Cosmetics.DefaultFrame]
end

--==========================================================================
-- 가진 것 · 끼고 있는 것
--==========================================================================

local function ownedList(collection)
	local cosmetics = collection and collection.cosmetics
	return (type(cosmetics) == "table" and type(cosmetics.owned) == "table") and cosmetics.owned or {}
end

-- 이 테두리를 가졌나. 값이 0 인 것은 모두가 가진다.
function Cosmetics.owns(collection, id)
	local frame = byId[id]
	if not frame then
		return false
	end
	if frame.price <= 0 then
		return true
	end
	for _, owned in ownedList(collection) do
		if owned == id then
			return true
		end
	end
	return false
end

--[[
	지금 끼고 있는 테두리 id. 저장값이 가리키는 것이 없어졌거나 가지지 않은 것이면
	기본이다 — 저장소를 손으로 고쳐 안 산 테두리를 적어도 그려지지 않는다.
]]
function Cosmetics.equippedFrame(collection)
	local cosmetics = collection and collection.cosmetics
	local id = type(cosmetics) == "table" and cosmetics.frame or nil
	if type(id) == "string" and Cosmetics.owns(collection, id) then
		return id
	end
	return Cosmetics.DefaultFrame
end

--==========================================================================
-- 사기 · 끼기
--==========================================================================

--[[
	테두리를 산다. -> 새 컬렉션  |  nil, reason

	산 테두리는 **바로 낀다.** 사놓고 한 번 더 눌러야 끼워지면 "샀는데 왜 안 바뀌지" 가 된다.

	잔액은 여기서 다시 본다. 화면이 버튼을 꺼뒀어도 리모트는 손으로 부를 수 있다
	(Collection.buyPack 과 같은 태도). 원래 컬렉션은 고치지 않는다.
]]
function Cosmetics.buy(progress, collection, id)
	local frame = byId[id]
	if not frame then
		return nil, "없는 테두리입니다"
	end
	if Cosmetics.owns(collection, id) then
		return nil, "이미 가진 테두리입니다"
	end

	local balance = Collection.balance(progress, collection)
	if balance < frame.price then
		return nil, ("골드가 모자랍니다 (%d / %d)"):format(balance, frame.price)
	end

	local updated = Collection.copy(collection)
	updated.spent += frame.price

	local owned = updated.cosmetics.owned
	table.insert(owned, id)
	table.sort(owned) -- 저장값이 사는 순서에 따라 흔들리지 않게
	updated.cosmetics.frame = id

	return updated
end

--[[
	가진 테두리로 갈아 낀다. -> 새 컬렉션  |  nil, reason
]]
function Cosmetics.equip(collection, id)
	if not byId[id] then
		return nil, "없는 테두리입니다"
	end
	if not Cosmetics.owns(collection, id) then
		return nil, "가지지 않은 테두리입니다"
	end

	local updated = Collection.copy(collection)
	updated.cosmetics.frame = id
	return updated
end

--==========================================================================
-- 화면에 내려보낼 모양
--==========================================================================

--[[
	꾸미기 화면의 목록. -> { { id, name, price, owned, equipped }, ... }

	색은 싣지 않는다. 클라이언트도 이 모듈을 읽으므로 id 만 있으면 된다 — 색을 두 곳에서
	내려주면 둘이 어긋난다.
]]
function Cosmetics.list(collection)
	local equipped = Cosmetics.equippedFrame(collection)
	local out = {}
	for _, frame in Cosmetics.Frames do
		table.insert(out, {
			id = frame.id,
			name = frame.name,
			price = frame.price,
			owned = Cosmetics.owns(collection, frame.id),
			equipped = frame.id == equipped,
		})
	end
	return out
end

return Cosmetics
