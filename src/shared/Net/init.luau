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
	  { kind = "leave" }     대전 종료 후 로비로
	  { kind = "requeue" }   대전 종료 후 로비로 돌아가 곧장 다시 큐

	서버 → 클라 (Lobby:FireClient)

	  { screen = "home",    text = ? }                 시작 화면
	  { screen = "queued",  elapsed = <이미 기다린 초> }
	                          시각이 아니라 경과 초다. 클라이언트 시계와 서버 시계를
	                          빼면 시계가 어긋난 사람의 타이머가 망가진다.
	  { screen = "found",   opponent = "이름" }        곧 대전 서버로 이동
	  { screen = "waiting", text = "상대를 기다리는 중" }  예약 서버에 먼저 도착
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
]]
function Net.packView(view, logTail)
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
