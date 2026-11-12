--[[
	서버 ↔ 클라이언트 경계.

	룰 엔진의 상태 테이블을 그대로 RemoteEvent 에 실을 수 없다.
	Roblox 직렬화가 안전하게 다루는 건 "1 부터 이어지는 배열" 과 "문자열 키 딕셔너리" 뿐인데,
	상태에는 카드 인스턴스 id(숫자, 비연속)를 키로 쓰는 테이블이 여럿 있다.
	  state.cards[instanceId]          카드 조회
	  state.combat.blocks[blockerId]   방어 배정
	  spell targets[effectIndex]       구멍 뚫린 배열

	그래서 보내기 직전에 전부 배열로 펴고, 받는 쪽에서 딕셔너리로 되돌린다.

	되돌린 결과는 룰 엔진 함수에 그대로 넣을 수 있는 모양이다 —
	클라이언트가 Rules.canPlayCard / Combat.legalAttackTargets 를 서버와 **같은 코드**로
	부를 수 있고, 그래서 "버튼은 켜져 있었는데 서버가 거부" 가 생기지 않는다.
]]

local Net = {}

--[[
	default.project.json 이 만들어 두는 RemoteEvent 3 개.

	  Sync   서버 → 클라  전체 상태 스냅샷 (뷰 + 로그)
	  Action 클라 → 서버  플레이어 행동 한 건
	  Notice 서버 → 클라  짧은 알림 (행동 거부 사유 / AI 가 한 일)
	  Lobby  양방향       매칭 큐. 대전 밖의 모든 대화가 여기로 다닌다

	런타임에 만들지 않고 프로젝트 파일에 박아둔 이유: 클라이언트가 WaitForChild 로
	무한정 기다리는 상황을 없애려고. 플레이스에 항상 존재한다.
]]
function Net.remotes()
	-- game:GetService 를 함수 안에서 부르는 이유: 이 모듈을 Roblox 밖(테스트)에서도
	-- require 할 수 있게 하려고. pack/unpack 은 Roblox API 를 전혀 쓰지 않는다.
	local folder = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	return {
		Sync = folder:WaitForChild("Sync"),
		Action = folder:WaitForChild("Action"),
		Notice = folder:WaitForChild("Notice"),
		Lobby = folder:WaitForChild("Lobby"),
	}
end

--==========================================================================
-- 로비 프로토콜
--==========================================================================

--[[
	클라 → 서버 (Lobby:FireServer)

	  { kind = "hello" }     화면이 준비됐다. 서버가 현재 상태를 내려준다
	  { kind = "queue" }     빠른 대전 큐 등록
	  { kind = "cancel" }    큐 취소
	  { kind = "practice" }  AI 연습 한 판 (큐를 타지 않고 이 서버에서 바로)
	  { kind = "home" }      시작 화면으로 (hello 는 '지금 화면을 다시' 라서 이것과 다르다)
	  { kind = "campaign" }  캠페인 스테이지 목록을 연다
	  { kind = "campaignStart", index = <스테이지 번호> }  그 스테이지를 시작한다
	  { kind = "deck" }      덱 편집 화면을 연다 (서버가 저장된 덱을 내려준다)
	  { kind = "deckSave", entries = { { id, count }, ... } }  덱 저장
	  { kind = "deckReset" } 스타터 덱으로 되돌린다
	  { kind = "shop" }      카드팩 화면을 연다
	  { kind = "buyPack" }   팩 한 봉을 산다 (가격·잔액 판정은 서버가 한다)
	  { kind = "profile" }   내 프로필 화면을 연다 (보기만 한다)
	  { kind = "wardrobe" }  꾸미기(카드 테두리 · 뒷면) 화면을 연다
	  { kind = "buyCosmetic", id = <꾸밈 id> }    사고 그 종류에 바로 낀다
	  { kind = "equipCosmetic", id = <꾸밈 id> }  가진 것으로 갈아 낀다 (종류는 id 가 정한다)
	  { kind = "leave" }     대전 종료 후 로비로
	  { kind = "requeue" }   대전 종료 후 로비로 돌아가 곧장 다시 큐

	서버 → 클라 (Lobby:FireClient)

	  { screen = "home",    text = ?, rankPoints = ? }  시작 화면. rankPoints 는 보이는 랭크 점수
	                          (MMR 은 어느 화면에도 싣지 않는다 — 숨은 점수다. Rank 머리말)
	  { screen = "profile", name, rankPoints, wins, losses, deck = { { id, count }, ... },
	                        deckPlayable, frame, back, collected, total, cleared, stages, gold }
	                          내 프로필. deck 은 저장해 둔 덱, deckPlayable 은 가진 카드로 짜지나
	  { screen = "queued",  elapsed = <이미 기다린 초> }
	                          시각이 아니라 경과 초다. 클라이언트 시계와 서버 시계를
	                          빼면 시계가 어긋난 사람의 타이머가 망가진다.
	  { screen = "found",   opponent = "이름" }        곧 대전 서버로 이동
	  { screen = "waiting", text = "상대를 기다리는 중" }  예약 서버에 먼저 도착
	  { screen = "deck",    entries = { { id, count }, ... }, owned = { { id, count }, ... },
	                        text = ?, saved = ? }
	                          덱 편집 화면. entries 는 지금 저장된 덱, owned 는 가진 카드
	                          (코스트 카드는 안 들어 있다 — 무한이다. Collection.owned)
	  { screen = "shop",    gold, price, size, rares, collected, total,
	                        pulls = { { id, rarity, kept, refund }, ... }?, text = ?, failed = ?,
	                        robuxProductId }
	                          robuxProductId 가 0 이면 Robux 버튼을 숨긴다(Products 주석).
	                          Robux 결제는 이 리모트를 타지 않는다 — 클라이언트가 구매 창을 띄우고,
	                          Roblox 가 서버에 영수증을 보내면 서버가 이 화면을 다시 내려준다
	                          카드팩 화면. gold 는 쓸 수 있는 골드, collected/total 은 모은 정도.
	                          pulls 는 방금 깐 팩 — **저장에 성공했을 때만** 실린다
	  { screen = "campaign", stages = { { index, name, note, difficulty, life, gold,
	                                     unlocked, cleared }, ... }, gold = <쓸 수 있는 골드>, text = ? }
	                          캠페인 목록. stages 는 Campaign.list 가 만든 그대로다 —
	                          **상대 덱은 들어 있지 않다** (플레이어가 알면 안 되는 정보)
	  { screen = "wardrobe", gold, frames = { { id, name, price, owned, equipped }, ... },
	                        backs = { 같은 모양 }, text = ?, failed = ? }
	                          꾸미기 화면. frames · backs 는 Cosmetics.list 그대로 — 색은 싣지 않는다
	                          (클라이언트도 Cosmetics 를 읽는다)
	  { screen = "battle" }                            전투 화면으로
	  { screen = "error",   text = "..." }             큐 실패 등

	화면 전환의 주인은 서버다. 클라이언트가 자기 판단으로 화면을 바꾸면
	"큐에 남아 있는데 시작 화면이 보이는" 상태가 생긴다.
]]
Net.LobbyScreen = table.freeze({
	Home = "home",
	Queued = "queued",
	Found = "found",
	Waiting = "waiting",
	Battle = "battle",
	Deck = "deck",
	Campaign = "campaign",
	Shop = "shop",
	Wardrobe = "wardrobe",
	Profile = "profile",
	Error = "error",
})

--==========================================================================
-- 대상 지정 (마법의 effects 와 같은 인덱스에 붙는다)
--==========================================================================

--[[
	targets 는 { [1] = target, [3] = target } 처럼 구멍이 뚫릴 수 있다.
	(대상이 없는 효과는 건너뛰므로) 그대로 보내면 뒤쪽이 잘린다. -> 배열로 편다.
]]
function Net.packTargets(targets)
	local out = {}
	if type(targets) ~= "table" then
		return out
	end

	for index, target in pairs(targets) do
		table.insert(out, {
			index = index,
			kind = target.kind,
			id = target.id,
		})
	end
	return out
end

function Net.unpackTargets(list)
	local out = {}
	if type(list) ~= "table" then
		return out
	end

	for _, entry in list do
		if type(entry) == "table" and type(entry.index) == "number" then
			out[entry.index] = { kind = entry.kind, id = entry.id }
		end
	end
	return out
end

--==========================================================================
-- 뷰 스냅샷
--==========================================================================

--[[
	Rules.viewFor 의 결과 + 로그 꼬리를 전송 가능한 순수 배열 구조로 만든다.

	looks 는 좌석마다 낀 꾸밈이다(Cosmetics 머리말). 룰 상태에 없는 겉모습이라 뷰 밖에서
	따로 받는다. 안 주면 전부 기본으로 그린다.

	    looks = { frames = { [1] = id, [2] = id }, backs = { [1] = id, [2] = id } }
]]
local function seatPair(pair)
	-- 1..2 배열이라 그대로 실어도 모양이 안 바뀐다. 비면 nil 대신 빈 문자열을 넣어 구멍을 막는다.
	return {
		pair and pair[1] or "",
		pair and pair[2] or "",
	}
end

function Net.packView(view, logTail, looks)
	local cards = {}
	for _, card in pairs(view.cards) do
		table.insert(cards, card)
	end

	local blocks = {}
	for blockerId, attackerId in pairs(view.combat.blocks) do
		table.insert(blocks, { blockerId = blockerId, attackerId = attackerId })
	end

	local stack = {}
	for index, item in view.stack do
		stack[index] = {
			id = item.id,
			kind = item.kind,
			instanceId = item.instanceId,
			controllerId = item.controllerId,
			targets = Net.packTargets(item.targets),
		}
	end

	return {
		turn = view.turn,
		phase = view.phase,
		activePlayerId = view.activePlayerId,
		priorityPlayerId = view.priorityPlayerId,
		finished = view.finished,
		winnerId = view.winnerId,
		lossReason = view.lossReason,
		viewerId = view.viewerId,

		players = { view.players[1], view.players[2] },
		cards = cards,
		stack = stack,
		attackers = view.combat.attackers,
		blocks = blocks,
		mulligan = view.mulligan,
		log = logTail or {},

		--[[
			직전 전투의 결과. 화면이 돌진·충격 연출을 재생하는 데 쓴다.

			이미 순수 데이터다 — Combat.resolve 가 만드는 이벤트는 숫자와 문자열만
			들고 있어서 손볼 것이 없다.
		]]
		lastCombat = view.lastCombat,

		-- 꾸밈 (Cosmetics). 테두리는 낸 카드에, 뒷면은 상대 손패에 쓰인다.
		frames = seatPair(looks and looks.frames),
		backs = seatPair(looks and looks.backs),
	}
end

--[[
	받은 스냅샷을 룰 엔진이 읽을 수 있는 state 모양으로 되돌린다.

	덱과 상대 손패는 애초에 내려오지 않는다(장수만 온다). 룰 함수들이 그 둘을
	건드리는 경로는 클라이언트에서 부를 일이 없다 — 판정 함수는 필드/손패/스택만 본다.
]]
function Net.unpackView(payload)
	local view = {
		turn = payload.turn,
		phase = payload.phase,
		activePlayerId = payload.activePlayerId,
		priorityPlayerId = payload.priorityPlayerId,
		finished = payload.finished,
		winnerId = payload.winnerId,
		lossReason = payload.lossReason,
		viewerId = payload.viewerId,

		players = {},
		cards = {},
		stack = {},
		combat = { attackers = payload.attackers or {}, blocks = {} },
		mulligan = payload.mulligan,
		log = payload.log or {},
		lastCombat = payload.lastCombat,
		frames = payload.frames or {},
		backs = payload.backs or {},
	}

	for _, player in payload.players do
		view.players[player.id] = player
	end

	for _, card in payload.cards do
		view.cards[card.id] = card
	end

	for index, item in payload.stack do
		view.stack[index] = {
			id = item.id,
			kind = item.kind,
			instanceId = item.instanceId,
			controllerId = item.controllerId,
			targets = Net.unpackTargets(item.targets),
		}
	end

	for _, block in payload.blocks do
		view.combat.blocks[block.blockerId] = block.attackerId
	end

	return view
end

return Net
