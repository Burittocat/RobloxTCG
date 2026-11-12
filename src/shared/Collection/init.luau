--[[
	컬렉션과 카드팩 — 누가 무슨 카드를 몇 장 가졌는가, 팩을 까면 무엇이 나오는가.

	Roblox API 를 전혀 쓰지 않는 순수 Luau 다. Campaign 과 같은 이유다 — "이 덱을 저장해도
	되나 · 이 골드로 팩을 살 수 있나 · 무엇이 나왔나" 는 서버가 판정하지만, 판정 자체에
	DataStore 도 Player 도 필요 없다. 그래서 Studio 없이 테스트로 못 박는다
	(tests/specs/collection.luau).

	컬렉션 (DataStore 에 그대로 들어가는 모양)

	    { cards = { { id = "CRE_HAWK", count = 3 }, ... }, spent = 120, opened = 2,
	      receipts = { "8f3c…", ... } }

	  cards     가진 카드. 덱과 같은 **엔트리 모양**이다 — 사람이 읽을 수 있고, Roblox
	            직렬화가 안전하게 다루는 모양이다. 코스트 카드는 적지 않는다(아래)
	  spent     지금까지 팩에 쓴 골드에서 중복 환급을 뺀 값 (순지출).
	            **음수일 수 있다** — Robux 팩은 골드를 안 쓰는데 중복 환급은 준다
	  opened    깐 팩 수. 판정에는 안 쓴다 — 저장된 값을 보고 문제를 짚을 때 단서다
	  receipts  처리한 Robux 영수증 ID (최근 MaxReceipts 개). 없어도 된다 — 아래 "Robux 팩"

	cosmetics 산 테두리와 끼고 있는 것 { owned = { id, ... }, frame = id }. 없어도 된다 —
	          규칙은 src/shared/Cosmetics 에 있다. 골드를 같이 쓰므로 같은 저장값에 둔다

	**새 컬렉션을 만들 때는 Collection.copy 로 통째로 복사한 뒤 고친다.** 칸을 하나씩 옮겨
	적으면, 나중에 붙인 칸(receipts, cosmetics)을 빠뜨린 경로에서 그 칸이 조용히 지워진다.

	--------------------------------------------------------------------------
	골드는 어디에 있나

	골드를 **번 기록**은 캠페인 진행도(`CampaignProgress_v1` 의 gold)에 있고, **쓴 기록**은
	여기(spent)에 있다. 잔액은 둘의 차다.

	    잔액 = progress.gold - collection.spent

	골드를 한 곳에서 빼고 카드를 다른 곳에 넣으면, 둘 중 두 번째 쓰기가 실패했을 때
	골드만 사라진다. 저장소 두 개에 걸친 쓰기는 원자적이지 않다. 이렇게 나누면 팩 하나를
	사는 것이 **이 저장소 한 곳에 한 번 쓰는 것**으로 끝난다 — 카드와 지출이 같이 들어가거나
	같이 안 들어간다. 캠페인 쪽은 번 것만 쌓으므로 손댈 필요가 없다.

	--------------------------------------------------------------------------
	코스트 카드는 무한이다

	`Config.copyLimitExemptTypes` 에 든 종류(코스트 카드)는 가진 것으로 친다. 자원이라
	덱마다 24장 넘게 들어가는데, 그걸 팩에서 모으게 하면 생물 한 장 못 넣은 사람이
	"코스트가 모자라 덱을 못 짠다" 에 걸린다. 팩에도 나오지 않는다.

	--------------------------------------------------------------------------
	처음 받는 것

	스타터 덱에 든 카드를 **스타터 덱에 든 매수만큼** 가지고 시작한다. 그래서 스타터 덱은
	언제나 짤 수 있다 — 스타터로 되돌리기가 거부당하는 일은 없다.

	컬렉션이 생기기 전에 덱을 저장해둔 사람은 그 덱에 든 카드도 받는다(`Collection.new`
	의 base). 안 그러면 업데이트 날 저장된 덱이 "가지지 않은 카드" 로 거부되어 스타터로
	되돌아간다 — 자기가 짠 덱을 업데이트가 빼앗는 것이다.
]]

local Rules = require(script.Parent.Rules)
local Decks = require(script.Parent.Decks)

local Registry = Rules.Registry
local Config = Rules.Config

local Collection = {}

--==========================================================================
-- 팩 · 환급 표 (★ 기획서 미확정 — docs/open-questions.md)
--==========================================================================

--[[
	price   한 팩 가격. 캠페인 1·2번을 깨면(50+80) 첫 팩을 살 수 있게 맞췄다
	size    한 팩에 든 장수
	rares   그중 희귀 칸 수. 희귀 칸은 **반드시** 희귀가 나온다 — 확률로만 두면
	        여러 팩을 까도 희귀가 한 장도 없는 사람이 생기고, 그건 운이 아니라 불만이다
]]
Collection.Pack = table.freeze({
	price = 100,
	size = 5,
	rares = 1,
})

--[[
	이미 최대 매수(4장)를 가진 카드가 또 나오면 그 장은 골드로 돌려준다.
	덱에 5장째는 못 넣으므로 쌓아봐야 쓸 데가 없다. 버리면 팩이 뒤로 갈수록 "꽝" 이 된다.

	환급 합이 팩 가격보다 작아야 한다 — 같거나 크면 다 모은 사람이 팩을 사서 골드를 번다.
	(tests/specs/collection.luau 가 이 부등식을 본다)
]]
Collection.Refund = table.freeze({
	Common = 10,
	Rare = 40,
})

--==========================================================================
-- 카드 풀
--==========================================================================

local function isExempt(def)
	return def ~= nil and Config.copyLimitExemptTypes[def.type] == true
end

local function rarityOf(def)
	return def.rarity == "Rare" and "Rare" or "Common"
end

--[[
	팩에서 나올 수 있는 카드. -> commons, rares (id 배열, id 순)

	Registry.all 은 id 를 키로 쓰는 딕셔너리라 순회 순서가 정해져 있지 않다. 그대로 쓰면
	**같은 시드로 다른 팩이 나온다.** 그래서 id 로 정렬한다.
]]
function Collection.pools()
	local commons, rares = {}, {}

	for id, def in Registry.all() do
		if not isExempt(def) then
			table.insert(rarityOf(def) == "Rare" and rares or commons, id)
		end
	end

	table.sort(commons)
	table.sort(rares)
	return commons, rares
end

--==========================================================================
-- 컬렉션
--==========================================================================

local function countsOf(entries)
	local out = {}
	if type(entries) ~= "table" then
		return out
	end
	for _, entry in entries do
		if type(entry) == "table" and type(entry.id) == "string" and type(entry.count) == "number" then
			out[entry.id] = (out[entry.id] or 0) + entry.count
		end
	end
	return out
end

-- id -> 매수 를 엔트리 배열로. 코스트 카드와 0장은 적지 않는다. id 순이라 저장값이 안정적이다.
local function toEntries(counts)
	local ids = {}
	for id, count in counts do
		local def = Registry.get(id)
		if def and not isExempt(def) and count > 0 then
			table.insert(ids, id)
		end
	end
	table.sort(ids)

	local out = {}
	for _, id in ids do
		table.insert(out, { id = id, count = math.min(counts[id], Decks.maxCopies(id)) })
	end
	return out
end

--[[
	새 컬렉션. -> collection

	base 는 컬렉션이 생기기 전에 저장해둔 덱(엔트리 모양)이다. 주면 스타터와 합쳐서
	**카드마다 더 많은 쪽**을 갖는다 (위 머리말 "처음 받는 것").
]]
function Collection.new(base)
	local counts = countsOf(Decks.starterEntries())

	if base ~= nil and Decks.validateEntries(base) then
		for id, count in countsOf(base) do
			counts[id] = math.max(counts[id] or 0, count)
		end
	end

	return { cards = toEntries(counts), spent = 0, opened = 0 }
end

--[[
	저장소에서 온 값이 쓸 수 있는 모양인가. -> ok, reason

	Campaign.validateProgress 와 같은 태도다 — 카드를 지우거나 이름을 바꾸면 옛 저장에
	없는 id 가 남는다. 그대로 쓰면 덱 편집 화면이 그 id 를 그리다 죽는다.
]]
function Collection.validate(value)
	if type(value) ~= "table" then
		return false, "컬렉션이 테이블이 아닙니다"
	end

	if type(value.opened) ~= "number" or value.opened % 1 ~= 0 or value.opened < 0 then
		return false, "'opened' 가 0 이상의 정수가 아닙니다"
	end

	-- spent 는 음수일 수 있다 (머리말 참조). 정수이기만 하면 된다.
	if type(value.spent) ~= "number" or value.spent % 1 ~= 0 then
		return false, "'spent' 가 정수가 아닙니다"
	end

	if value.receipts ~= nil then
		if type(value.receipts) ~= "table" then
			return false, "receipts 가 배열이 아닙니다"
		end
		for _, id in value.receipts do
			if type(id) ~= "string" then
				return false, "receipts 에 문자열이 아닌 값이 있습니다"
			end
		end
	end

	--[[
		cosmetics 는 모양만 본다. **없는 테두리 id 는 거부하지 않는다** — 테두리를 지운 뒤 옛
		저장값을 읽으면 그렇게 되는데, 그걸로 컬렉션 전체를 못 읽게 하면 카드까지 못 쓴다.
		그리는 쪽이 모르는 id 를 기본 테두리로 바꾼다(Cosmetics.frameOrDefault).
	]]
	if value.cosmetics ~= nil then
		local cosmetics = value.cosmetics
		if type(cosmetics) ~= "table" then
			return false, "cosmetics 가 테이블이 아닙니다"
		end
		if cosmetics.frame ~= nil and type(cosmetics.frame) ~= "string" then
			return false, "cosmetics.frame 이 문자열이 아닙니다"
		end
		if cosmetics.owned ~= nil then
			if type(cosmetics.owned) ~= "table" then
				return false, "cosmetics.owned 가 배열이 아닙니다"
			end
			for _, id in cosmetics.owned do
				if type(id) ~= "string" then
					return false, "cosmetics.owned 에 문자열이 아닌 값이 있습니다"
				end
			end
		end
	end

	if type(value.cards) ~= "table" then
		return false, "cards 가 배열이 아닙니다"
	end

	local seen = {}
	for _, entry in value.cards do
		if type(entry) ~= "table" or type(entry.id) ~= "string" then
			return false, "카드 항목의 모양이 잘못됐습니다"
		end
		if not Registry.get(entry.id) then
			return false, ("없는 카드 '%s'"):format(entry.id)
		end
		if type(entry.count) ~= "number" or entry.count % 1 ~= 0 or entry.count < 0 then
			return false, ("'%s' 의 매수가 잘못됐습니다"):format(entry.id)
		end
		if seen[entry.id] then
			return false, ("'%s' 가 두 번 적혀 있습니다"):format(entry.id)
		end
		seen[entry.id] = true
	end

	return true
end

--[[
	이 카드를 몇 장 가졌나. 코스트 카드는 덱 한 벌을 다 채울 만큼(무한과 같다).
]]
function Collection.countOf(collection, cardId)
	local def = Registry.get(cardId)
	if not def then
		return 0
	end
	if isExempt(def) then
		return Config.deckSize
	end

	for _, entry in collection.cards or {} do
		if entry.id == cardId then
			return entry.count
		end
	end
	return 0
end

--[[
	이 덱을 가진 카드로 짤 수 있나. -> ok, reason

	**덱 규칙(60장 · 4장 제한)은 여기서 안 본다.** 그건 Decks.validateEntries 한 곳이다.
	둘을 합치면 "가졌는가" 를 바꿀 때 덱 규칙까지 같이 건드리게 된다. 서버는 둘 다 부른다.
]]
function Collection.covers(collection, entries)
	-- 리모트로 온 값이 그대로 들어온다. 모양 검사는 validateEntries 몫이지만 여기서 죽으면 안 된다.
	if type(entries) ~= "table" then
		return false, "덱이 배열이 아닙니다"
	end

	for id, count in countsOf(entries) do
		local owned = Collection.countOf(collection, id)
		if count > owned then
			local def = Registry.get(id)
			return false, ("'%s' 는 %d장만 가지고 있습니다"):format(def and def.name or id, owned)
		end
	end
	return true
end

--[[
	컬렉션 통째 사본. -> collection

	팩을 사거나 테두리를 사는 쪽은 이걸 받아서 고친다. 원래 값은 건드리지 않는다 —
	저장이 실패하면 부르는 쪽이 옛 값으로 되돌릴 수 있어야 한다(applyCards 머리말).

	cosmetics 는 언제나 채워서 돌려준다. 고치는 쪽이 "없으면 만들기" 를 매번 안 해도 된다.
]]
function Collection.copy(collection)
	local cards = {}
	for _, entry in collection.cards or {} do
		table.insert(cards, { id = entry.id, count = entry.count })
	end

	local receipts = nil
	if collection.receipts then
		receipts = table.clone(collection.receipts)
	end

	local cosmetics = type(collection.cosmetics) == "table" and collection.cosmetics or {}
	local owned = type(cosmetics.owned) == "table" and table.clone(cosmetics.owned) or {}

	return {
		cards = cards,
		spent = collection.spent or 0,
		opened = collection.opened or 0,
		receipts = receipts,
		cosmetics = { owned = owned, frame = cosmetics.frame },
	}
end

-- 쓸 수 있는 골드. 번 것(캠페인) - 쓴 것(여기).
function Collection.balance(progress, collection)
	return math.max(0, (progress and progress.gold or 0) - (collection and collection.spent or 0))
end

--==========================================================================
-- 카드팩
--==========================================================================

--[[
	팩 한 봉. -> 카드 id 배열 (size 장, 희귀 칸이 뒤에 온다)

	rng 는 Rules.RNG 다. 서버가 시드를 뽑아 넘긴다 — 셔플과 같은 난수기라 같은 시드면
	같은 팩이 나오고, 그래서 테스트가 "무엇이 나왔나" 를 숫자로 확인할 수 있다.

	한 팩 안에서 같은 카드가 겹칠 수 있다. 겹침을 막으면 풀이 작은 지금(희귀 8종)은
	"이 팩에 무엇이 없나" 로 다음 장이 추측된다.
]]
function Collection.rollPack(rng)
	local commons, rares = Collection.pools()
	local out = {}

	for slot = 1, Collection.Pack.size do
		local isRareSlot = slot > Collection.Pack.size - Collection.Pack.rares
		local pool = (isRareSlot and #rares > 0) and rares or commons
		table.insert(out, pool[rng:nextInteger(1, #pool)])
	end

	return out
end

--[[
	나온 카드를 컬렉션에 넣는다. -> 새 컬렉션, 결과, 환급 합

	결과는 한 장에 한 칸: { id, rarity, kept = 넣었나, refund = 돌려준 골드 }.
	화면이 "새 카드 / 중복 → 골드" 를 그대로 그린다.

	**원래 컬렉션을 고치지 않는다.** Campaign.applyClear 와 같은 이유 — 저장이 실패하면
	부르는 쪽이 옛 값으로 되돌릴 수 있어야 한다.
]]
function Collection.applyCards(collection, cards)
	local counts = countsOf(collection.cards)
	local results = {}
	local refund = 0

	for _, id in cards do
		local def = Registry.mustGet(id)
		local rarity = rarityOf(def)
		local have = counts[id] or 0

		if have < Decks.maxCopies(id) then
			counts[id] = have + 1
			table.insert(results, { id = id, rarity = rarity, kept = true, refund = 0 })
		else
			local amount = Collection.Refund[rarity]
			refund += amount
			table.insert(results, { id = id, rarity = rarity, kept = false, refund = amount })
		end
	end

	local updated = Collection.copy(collection)
	updated.cards = toEntries(counts)
	updated.spent = collection.spent - refund -- 음수가 될 수 있다 (머리말)

	return updated, results, refund
end

--[[
	팩을 산다. -> 새 컬렉션, 결과  |  nil, reason

	잔액은 여기서 다시 계산한다. 화면이 "살 수 있다" 고 버튼을 켜뒀어도 서버가 부르는
	이 함수가 마지막 판정이다 — 리모트는 손으로도 부를 수 있다.
]]
function Collection.buyPack(progress, collection, rng)
	local price = Collection.Pack.price
	local balance = Collection.balance(progress, collection)

	if balance < price then
		return nil, ("골드가 모자랍니다 (%d / %d)"):format(balance, price)
	end

	local paid = Collection.copy(collection)
	paid.spent = collection.spent + price
	paid.opened = collection.opened + 1

	local updated, results = Collection.applyCards(paid, Collection.rollPack(rng))
	return updated, results
end

--==========================================================================
-- Robux 팩
--==========================================================================

--[[
	Robux 결제는 **같은 영수증이 여러 번 올 수 있다.** Roblox 는 서버가 "처리했다"
	(PurchaseGranted) 고 답할 때까지 ProcessReceipt 를 다시 부른다 — 답하기 직전에 서버가
	죽거나, 저장은 됐는데 답이 안 갔으면 다음 접속에 같은 영수증이 또 온다. 그때 팩을 또
	주면 한 번 낸 돈으로 두 봉이 나간다.

	그래서 처리한 영수증 ID 를 **카드와 같은 저장값에** 적는다. 카드를 넣는 것과 영수증을
	적는 것이 한 번의 쓰기라, "카드는 들어갔는데 영수증은 안 적힌" 중간이 없다.

	최근 MaxReceipts 개만 들고 있는다. 끝없이 쌓으면 저장값 한도(4MB)에 언젠가 닿는다.
	Roblox 가 다시 보내는 것은 아직 처리 안 된 영수증뿐이라, 백 건 전 것이 다시 올 일은 없다.
]]
Collection.MaxReceipts = 100

function Collection.hasReceipt(collection, purchaseId)
	for _, id in collection.receipts or {} do
		if id == purchaseId then
			return true
		end
	end
	return false
end

--[[
	Robux 로 산 팩 한 봉을 준다. -> 새 컬렉션, 결과  |  nil, reason

	골드는 안 쓴다. 중복 환급은 골드 팩과 똑같이 준다 — 그래서 spent 가 음수가 될 수 있다.
	이미 처리한 영수증이면 아무것도 안 준다(부르는 쪽은 그래도 "처리했다" 고 답해야 한다 —
	Lobby:processReceipt).
]]
function Collection.grantPack(collection, purchaseId, rng)
	if type(purchaseId) ~= "string" or purchaseId == "" then
		return nil, "영수증 ID 가 없습니다"
	end
	if Collection.hasReceipt(collection, purchaseId) then
		return nil, "이미 처리한 영수증입니다"
	end

	local receipts = {}
	for _, id in collection.receipts or {} do
		table.insert(receipts, id)
	end
	table.insert(receipts, purchaseId)
	while #receipts > Collection.MaxReceipts do
		table.remove(receipts, 1)
	end

	local opened = Collection.copy(collection)
	opened.opened = collection.opened + 1
	opened.receipts = receipts

	return Collection.applyCards(opened, Collection.rollPack(rng))
end

--==========================================================================
-- 화면에 내려보낼 모양
--==========================================================================

--[[
	가진 카드 (엔트리 배열). 코스트 카드는 안 들어 있다 — 받는 쪽은 Decks.maxCopies 가
	deckSize 인 종류를 무한으로 본다(덱 편집 화면이 그렇게 한다).
]]
function Collection.owned(collection)
	local out = {}
	for _, entry in collection.cards or {} do
		table.insert(out, { id = entry.id, count = entry.count })
	end
	return out
end

--[[
	모은 정도. -> 가진 장수, 다 모으면 되는 장수

	코스트 카드는 세지 않는다. "카드 4장씩 전부" 가 끝이다.
]]
function Collection.progress(collection)
	local commons, rares = Collection.pools()
	local total = (#commons + #rares) * Config.maxCopiesPerCard
	local have = 0

	for _, entry in collection.cards or {} do
		have += math.min(entry.count, Decks.maxCopies(entry.id))
	end

	return have, total
end

return Collection
