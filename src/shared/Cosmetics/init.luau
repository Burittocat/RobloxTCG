--[[
	코스메틱 — 카드 테두리와 카드 뒷면. 판에 아무 영향도 없는 **겉모습 레이어**다.

	Roblox API 를 쓰지 않는 순수 Luau 다(Collection · Campaign 과 같은 이유). "살 수 있나 ·
	가졌나 · 무엇을 끼고 있나" 판정에 DataStore 도 Player 도 필요 없어서, Studio 없이
	테스트로 못 박는다(tests/specs/cosmetics.luau).

	--------------------------------------------------------------------------
	종류 (Kind)

	  frame  테두리 — 내가 낸 카드(손패 · 필드)에 둘러진다. 목록은 Frames.luau
	  back   뒷면   — 상대가 내 손패를 볼 때 보인다. 목록은 Backs.luau

	종류마다 **하나씩** 낀다. 종류를 늘리려면 목록 파일을 하나 더 두고 아래 KINDS 에 한 줄을
	더하면 된다 — 사기 · 끼기 · 저장 · 검증은 종류를 가리지 않는다.

	id 는 종류를 넘어 겹치지 않는다(FRAME_ · BACK_ 머리). 그래서 "가진 것" 은 종류 구분
	없이 한 배열에 적는다.

	--------------------------------------------------------------------------
	카드 데이터와 왜 떼어 두나

	꾸밈은 **카드가 아니라 사람에게** 붙는다. 같은 `방패병` 이라도 누가 냈느냐에 따라
	테두리가 다르다. 그래서 카드 정의(Cards/Sheet)에도, 룰 상태(GameState)에도 들어가지
	않는다. 룰 엔진은 꾸밈을 모르고, 몰라야 한다 — 겉모습이 판정에 닿는 길이 아예 없다.

	흐름은 이렇다.
	  저장   컬렉션 저장값의 `cosmetics = { owned = { id, ... }, frame = id, back = id }`
	  판     MatchRunner 의 좌석이 frame · back 을 들고 있다가 스냅샷에 `frames` · `backs` 로 싣는다
	  화면   CardView 가 그 좌석의 것으로 칠한다

	--------------------------------------------------------------------------
	왜 컬렉션과 같은 저장값인가

	꾸밈은 골드로 산다. 골드의 **쓴 기록**(spent)은 컬렉션에 있다(Collection 머리말).
	다른 저장소에 적으면 "골드는 빠졌는데 꾸밈은 안 들어간" 중간이 생긴다.
	같은 값에 적으면 사는 것이 **한 번의 쓰기**로 끝난다 — 카드팩과 같은 원리다.

	cosmetics 칸은 없어도 된다. 옛 저장값은 "기본만 가진 사람" 이다.
]]

local Collection = require(script.Parent.Collection)
local FrameTable = require(script.Frames)
local BackTable = require(script.Backs)

local Cosmetics = {}

Cosmetics.Kind = table.freeze({
	Frame = "frame",
	Back = "back",
})

-- 종류 → 목록. 저장값의 칸 이름도 종류 이름 그대로다(cosmetics.frame, cosmetics.back).
local KINDS = {
	frame = FrameTable,
	back = BackTable,
}

local KIND_NAME = {
	frame = "테두리",
	back = "카드 뒷면",
}

-- 예전 이름. 화면 · 테스트가 테두리만 다룰 때 쓴다.
Cosmetics.DefaultFrame = FrameTable.default
Cosmetics.Frames = FrameTable.list
Cosmetics.DefaultBack = BackTable.default
Cosmetics.Backs = BackTable.list

local byId = {} -- id -> { def, kind }
for kind, table_ in KINDS do
	for _, def in table_.list do
		assert(byId[def.id] == nil, ("꾸밈 id '%s' 가 겹칩니다"):format(def.id))
		byId[def.id] = { def = def, kind = kind }
	end
end

--==========================================================================
-- 목록 조회
--==========================================================================

-- 꾸밈 하나. -> def, kind  |  nil
function Cosmetics.item(id)
	local entry = byId[id]
	if not entry then
		return nil
	end
	return entry.def, entry.kind
end

function Cosmetics.kindName(kind)
	return KIND_NAME[kind] or tostring(kind)
end

function Cosmetics.defaultOf(kind)
	local table_ = KINDS[kind]
	return table_ and table_.default
end

-- 그 종류의 정의. 없는 id 거나 다른 종류면 nil.
local function ofKind(id, kind)
	local entry = byId[id]
	if entry and entry.kind == kind then
		return entry.def
	end
	return nil
end

function Cosmetics.frame(id)
	return ofKind(id, Cosmetics.Kind.Frame)
end

function Cosmetics.back(id)
	return ofKind(id, Cosmetics.Kind.Back)
end

--[[
	그릴 것. 없는 id 거나 nil 이면 기본이다.

	화면은 이것만 부른다. 꾸밈을 지우거나 이름을 바꾼 뒤 옛 저장값이 오면 그 사람의
	카드가 깨져 그려지는 대신 기본으로 돌아간다.
]]
function Cosmetics.frameOrDefault(id)
	return Cosmetics.frame(id) or Cosmetics.frame(Cosmetics.DefaultFrame)
end

function Cosmetics.backOrDefault(id)
	return Cosmetics.back(id) or Cosmetics.back(Cosmetics.DefaultBack)
end

--==========================================================================
-- 가진 것 · 끼고 있는 것
--==========================================================================

local function ownedList(collection)
	local cosmetics = collection and collection.cosmetics
	return (type(cosmetics) == "table" and type(cosmetics.owned) == "table") and cosmetics.owned or {}
end

-- 이 꾸밈을 가졌나. 값이 0 인 것은 모두가 가진다.
function Cosmetics.owns(collection, id)
	local def = Cosmetics.item(id)
	if not def then
		return false
	end
	if def.price <= 0 then
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
	그 종류에서 지금 끼고 있는 id. 저장값이 가리키는 것이 없어졌거나, 가지지 않았거나,
	다른 종류면 기본이다 — 저장소를 손으로 고쳐 안 산 것을 적어도 그려지지 않는다.
]]
function Cosmetics.equipped(collection, kind)
	local cosmetics = collection and collection.cosmetics
	local id = type(cosmetics) == "table" and cosmetics[kind] or nil
	if type(id) == "string" and ofKind(id, kind) and Cosmetics.owns(collection, id) then
		return id
	end
	return Cosmetics.defaultOf(kind)
end

function Cosmetics.equippedFrame(collection)
	return Cosmetics.equipped(collection, Cosmetics.Kind.Frame)
end

function Cosmetics.equippedBack(collection)
	return Cosmetics.equipped(collection, Cosmetics.Kind.Back)
end

--==========================================================================
-- 사기 · 끼기
--==========================================================================

--[[
	꾸밈을 산다. -> 새 컬렉션  |  nil, reason

	산 것은 **그 종류에 바로 낀다.** 사놓고 한 번 더 눌러야 끼워지면 "샀는데 왜 안 바뀌지"
	가 된다. 다른 종류에 낀 것은 그대로다 — 뒷면을 샀다고 테두리가 바뀌면 안 된다.

	잔액은 여기서 다시 본다. 화면이 버튼을 꺼뒀어도 리모트는 손으로 부를 수 있다
	(Collection.buyPack 과 같은 태도). 원래 컬렉션은 고치지 않는다.
]]
function Cosmetics.buy(progress, collection, id)
	local def, kind = Cosmetics.item(id)
	if not def then
		return nil, "없는 꾸밈입니다"
	end
	if Cosmetics.owns(collection, id) then
		return nil, ("이미 가진 %s입니다"):format(Cosmetics.kindName(kind))
	end

	local balance = Collection.balance(progress, collection)
	if balance < def.price then
		return nil, ("골드가 모자랍니다 (%d / %d)"):format(balance, def.price)
	end

	local updated = Collection.copy(collection)
	updated.spent += def.price

	local owned = updated.cosmetics.owned
	table.insert(owned, id)
	table.sort(owned) -- 저장값이 사는 순서에 따라 흔들리지 않게
	updated.cosmetics[kind] = id

	return updated
end

--[[
	가진 꾸밈으로 갈아 낀다. -> 새 컬렉션  |  nil, reason
]]
function Cosmetics.equip(collection, id)
	local def, kind = Cosmetics.item(id)
	if not def then
		return nil, "없는 꾸밈입니다"
	end
	if not Cosmetics.owns(collection, id) then
		return nil, ("가지지 않은 %s입니다"):format(Cosmetics.kindName(kind))
	end

	local updated = Collection.copy(collection)
	updated.cosmetics[kind] = id
	return updated
end

--==========================================================================
-- 화면에 내려보낼 모양
--==========================================================================

--[[
	꾸미기 화면의 한 종류 목록. -> { { id, name, price, owned, equipped }, ... }
	kind 를 안 주면 테두리다.

	색은 싣지 않는다. 클라이언트도 이 모듈을 읽으므로 id 만 있으면 된다 — 색을 두 곳에서
	내려주면 둘이 어긋난다.
]]
function Cosmetics.list(collection, kind)
	kind = kind or Cosmetics.Kind.Frame
	local table_ = KINDS[kind]
	if not table_ then
		return {}
	end

	local equipped = Cosmetics.equipped(collection, kind)
	local out = {}
	for _, def in table_.list do
		table.insert(out, {
			id = def.id,
			name = def.name,
			price = def.price,
			owned = Cosmetics.owns(collection, def.id),
			equipped = def.id == equipped,
		})
	end
	return out
end

return Cosmetics
