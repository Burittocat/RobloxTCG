--[[
	클릭을 행동으로 옮기는 곳.

	여기서 부르는 판정 함수는 전부 서버가 부르는 것과 **같은 모듈** 이다.
	  Rules.canPlayCard         손패 카드가 지금 낼 수 있는가
	  Combat.legalAttackTargets 이 공격자가 고를 수 있는 대상
	  Combat.canBlock           이 방어자가 저 공격자를 막을 수 있는가
	  Effects.validateTarget    이 마법이 저 대상을 지정할 수 있는가

	그래서 "화면에 켜졌는데 서버가 거부" 가 구조적으로 생기지 않는다.
	서버는 그래도 다시 검증한다 — 클라이언트를 믿어서가 아니라 같은 코드라서 공짜다.

	모드
	  idle    평소. 손패/내 생물을 누르면 그에 맞는 모드로 들어간다
	  target  마법의 대상을 고르는 중 (효과가 여러 개면 순서대로 묻는다)
	  attack  공격자를 골랐고 대상을 고르는 중
	  block   방어자를 골랐고 막을 공격자를 고르는 중
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)
local Net = require(Shared.Net)

local Tutorial = require(script.Parent.Tutorial)
local Sfx = require(script.Parent.UI.Sfx)

local Enums = Rules.Enums
local GameState = Rules.GameState
local Registry = Rules.Registry
local Combat = Rules.Combat
local Phases = Rules.Phases
local Effects = Rules.Effects
local Stack = Rules.Stack

local Phase = Enums.Phase
local CardType = Enums.CardType
local TargetKind = Enums.TargetKind

--[[
	"나" 와 "상대" 좌석. PvP 에서는 내가 1번일 수도 2번일 수도 있고, 그건 서버가
	스냅샷의 viewerId 로 알려준다. 화면과 판정이 전부 이 둘만 본다.

	기본값 1/2 는 첫 스냅샷이 오기 전에만 쓰인다.
]]
local DEFAULT_ME, DEFAULT_FOE = 1, 2

local Controller = {}
Controller.__index = Controller

--==========================================================================
-- 생성
--==========================================================================

function Controller.new(battle, remotes)
	local self = setmetatable({}, Controller)

	self.battle = battle
	self.remotes = remotes
	self.view = nil
	self.mode = { name = "idle" }
	self.confirmPass = false -- 스택 상자를 눌러 되묻는 중
	self.confirmConcede = false -- 항복을 한 번 눌러 "정말 항복?" 으로 바뀐 상태
	self.me, self.foe = DEFAULT_ME, DEFAULT_FOE
	-- App 이 매치 종류에 따라 바꾼다 ("practice" | "pvp" | "tutorial" | "campaign")
	self.matchMode = "practice"
	self.tutorial = Tutorial.new()

	battle.callbacks.handCard = function(id)
		self:onHandCard(id)
	end
	battle.callbacks.fieldCard = function(id)
		self:onFieldCard(id)
	end
	battle.callbacks.player = function(id)
		self:onPlayer(id)
	end
	battle.callbacks.stackItem = function(id)
		self:onStackItem(id)
	end
	battle.callbacks.action = function(key)
		self:onAction(key)
	end

	--[[
		카드를 들여다보는 것은 화면 혼자 하는 일이라 서버로 안 간다.
		여기서 받는 이유는 하나 — 튜토리얼 코치가 "그 손짓 배웠구나" 를 알아야 한다.
	]]
	battle.callbacks.inspect = function()
		self.tutorial:markInspected()
		self:refresh()
	end

	remotes.Sync.OnClientEvent:Connect(function(payload)
		self:onSync(payload)
	end)
	remotes.Notice.OnClientEvent:Connect(function(text, kind)
		battle:showToast(text, kind)
	end)

	return self
end

function Controller:send(payload)
	self.remotes.Action:FireServer(payload)
end

--[[
	한 판이 시작될 때 App 이 부른다. "준비됐다" 를 받은 서버가 첫 스냅샷을 쏜다.

	클라이언트가 서버의 수신 연결보다 먼저 뜨면 그 한 발이 허공으로 사라진다.
	첫 스냅샷이 올 때까지 재시도해서 그 경우를 없앤다.

	PvP 에서는 상대가 아직 도착하지 않았을 수 있다. 그때 서버는 스냅샷 대신
	"상대를 기다리는 중" 알림만 보내므로, 여기 재시도는 조용히 계속 돈다.
]]
function Controller:start()
	-- 지난 판의 뷰가 남아 있으면 새 판의 첫 스냅샷이 오기 전에 옛 판이 그려진다.
	self.view = nil
	self.mode = { name = "idle" }
	self.confirmPass = false
	self.confirmConcede = false
	self.tutorial:reset()

	self.session = (self.session or 0) + 1
	local session = self.session

	task.spawn(function()
		for _ = 1, 40 do
			if self.view or self.session ~= session then
				return
			end
			self:send({ kind = "ready" })
			task.wait(0.5)
		end
		if self.session == session then
			self.battle:showToast("서버에 연결하지 못했습니다", "error")
		end
	end)
end

--==========================================================================
-- 서버 상태 수신
--==========================================================================

function Controller:onSync(payload)
	self.view = Net.unpackView(payload)

	-- 내 좌석은 서버가 정한다. 클라이언트가 "나는 1번" 이라고 가정하면
	-- 2번 자리에 앉은 사람의 화면이 통째로 뒤집힌다.
	self.me = self.view.viewerId or DEFAULT_ME
	self.foe = GameState.opponentOf(self.me)

	-- 서버 상태가 바뀌면 진행 중이던 선택은 의미를 잃는다. 묻던 것도 같이 거둔다 —
	-- 스택에 한 장 더 쌓인 뒤에도 확인이 남아 있으면, 방금 읽은 것과 다른 것을 넘기게 된다.
	self.mode = { name = "idle" }
	self.confirmPass = false
	self.confirmConcede = false
	self:refresh()
end

--[[
	매치 종류. 끝난 뒤 보여줄 버튼이 달라진다.
	  practice  다시 하기 / 로비로
	  pvp       다시 매칭 / 나가기
	  campaign  목록으로
]]
function Controller:setMatchMode(mode)
	self.matchMode = mode
	if self.view then
		self:refresh()
	end
end

--==========================================================================
-- 튜토리얼 코치
--==========================================================================

--[[
	지금 단계. 튜토리얼이 아니면 없다.

	부를 때마다 단계를 진행시킨다(Tutorial:update). 클릭 처리 중에 불러도 되도록
	일부러 그렇게 뒀다 — 화면을 다시 그리기 전에 이미 다음 단계인 경우가 있다.
]]
function Controller:coachStep()
	if self.matchMode ~= "tutorial" or not self.view then
		return nil
	end
	return self.tutorial:update(self.view, self.me)
end

--[[
	지금 누를 수 있는 것. -> 허용표

	**고르는 중(target/attack/block)에는 잠그지 않는다.** 그 순간 누를 수 있는 것은
	이미 룰이 초록으로 좁혀놨고, 거기서 코치가 또 막으면 고르다 만 채로 갇힌다.
]]
function Controller:coachAllow()
	if self.matchMode ~= "tutorial" or not self.view or self.mode.name ~= "idle" then
		return Tutorial.FREE
	end
	return Tutorial.allowOf(self:coachStep(), self.view, self.me)
end

-- 코치가 잠근 손패 카드. 화면은 이걸 보고 "낼 수 없는 카드" 처럼 흐리게 그린다.
function Controller:lockedHand(allow)
	if allow.free then
		return nil
	end

	local locked = {}
	for _, instanceId in self.view.players[self.me].hand or {} do
		if not Tutorial.allowsHand(allow, self.view, self.me, instanceId) then
			locked[instanceId] = true
		end
	end
	return locked
end

function Controller:coachToast()
	self.battle:showToast("지금은 코치가 안내한 것부터 해 보세요", "info")
end

--[[
	결과 화면에 덧붙일 한 줄.

	튜토리얼 한 판에서 카드와 태그를 다 만나지는 못한다. 그래서 끝나는 자리에서
	"나머지는 어디서 보는지" 를 알려준다 — 판 안에서는 오른쪽 클릭, 판 밖에서는 덱 편집.
]]
function Controller:endNote()
	if self.matchMode ~= "tutorial" then
		return nil
	end
	return "카드를 <b>오른쪽 클릭</b> 하면 태그가 무슨 효과인지 볼 수 있어요.\n"
		.. "더 다양한 카드는 시작 화면의 [덱 편집] 에서!"
end

function Controller:endActions()
	if self.matchMode == "pvp" then
		return {
			{ key = "requeue", text = "다시 매칭" },
			{ key = "leave", text = "나가기" },
		}
	end

	--[[
		캠페인에는 "다시 하기" 가 없다. 서버가 재시작을 받지 않기 때문인데
		(Lobby:startCampaignStage 주석 — 보상이 걸린 판을 무한 재시도할 수 있게 된다),
		그래도 버튼을 띄우면 눌러도 아무 일이 일어나지 않는 자리가 생긴다.
		다시 하려면 목록으로 나갔다 들어온다.
	]]
	if self.matchMode == "campaign" then
		return { { key = "leave", text = "목록으로" } }
	end

	return {
		{ key = "restart", text = "다시 하기" },
		{ key = "leave", text = "로비로" },
	}
end

-- 지금 행동해야 하는 쪽. 서버와 **같은 함수**를 부른다 —
-- 그래서 "내 차례인데 버튼이 꺼져 있다" 가 생기지 않는다.
local whoActs = Rules.whoActs

--==========================================================================
-- 하이라이트 / 안내문 계산
--==========================================================================

local function emptyHighlights()
	return { creature = {}, player = {}, stack = {}, hand = {} }
end

--[[
	지금 선언된 공격자 중 이 생물이 하나라도 막을 수 있는가.

	`tapped` 만 보면 안 된다. 비행 공격자만 들어온 턴에는 지상 비원거리 생물을
	Combat.canBlock 이 전부 거부하는데, 그걸 안 보면 초록 테두리는 다 켜지고
	눌러 들어가 봐야 고를 공격자가 없어 '선택 취소' 로만 나오게 된다.
]]
local function canBlockThis(view, blocker, attacker)
	-- canBlock 은 "막을 수 있는 종류인가" 만 본다. 이미 막고 있는 사람이 있으면
	-- 서버가 거부하므로 여기서 같이 본다 (Rules.canAssignBlockerTo 주석 참조).
	return Combat.canBlock(view, blocker, attacker) and Rules.canAssignBlockerTo(view, attacker.id)
end

local function canBlockAnyAttacker(view, blocker)
	for _, declaration in view.combat.attackers do
		local attacker = view.cards[declaration.id]
		if attacker and canBlockThis(view, blocker, attacker) then
			return true
		end
	end
	return false
end

--[[
	지금 모드에서 누를 수 있는 것들. Battle 은 이 표만 보고 테두리를 칠한다.
]]
function Controller:highlights()
	local view = self.view
	local out = emptyHighlights()

	if not view or view.finished then
		return out
	end

	local mode = self.mode

	if mode.name == "target" then
		local step = mode.steps[mode.stepIndex]

		for playerId = 1, 2 do
			if Effects.validateTarget(view, step.effect, self.me, { kind = "Player", id = playerId }) then
				out.player[playerId] = true
			end
		end
		for playerId = 1, 2 do
			for _, instance in GameState.creaturesOnField(view, playerId) do
				if Effects.validateTarget(view, step.effect, self.me, { kind = "Creature", id = instance.id }) then
					out.creature[instance.id] = true
				end
			end
		end
		for _, item in view.stack do
			if Effects.validateTarget(view, step.effect, self.me, { kind = "StackItem", id = item.id }) then
				out.stack[item.id] = true
			end
		end
		return out
	end

	if mode.name == "attack" then
		local attacker = view.cards[mode.attackerId]
		if attacker then
			for _, target in Combat.legalAttackTargets(view, attacker) do
				if target.kind == "Player" then
					out.player[target.id] = true
				else
					out.creature[target.id] = true
				end
			end
		end
		return out
	end

	if mode.name == "block" then
		local blocker = view.cards[mode.blockerId]
		if blocker then
			for _, declaration in view.combat.attackers do
				local attacker = view.cards[declaration.id]
				if attacker and canBlockThis(view, blocker, attacker) then
					out.creature[attacker.id] = true
				end
			end
		end
		return out
	end

	--[[
		idle: 지금 고를 수 있는 내 생물.
		튜토리얼이 잠근 단계에서는 켜지 않는다 — 초록으로 켜두고 눌러도 안 되면
		"고장" 으로 읽힌다.
	]]
	local allow = self:coachAllow()

	local function light(instance)
		if Tutorial.allowsField(allow, view, self.me, instance.id) then
			out.creature[instance.id] = true
		end
	end

	if whoActs(view) == self.me and Stack.isEmpty(view) then
		if view.phase == Phase.AttackPrep and view.activePlayerId == self.me then
			for _, instance in GameState.creaturesOnField(view, self.me) do
				-- 이미 선언한 생물은 끈다. 선언해도 탭되지 않아 canAttack 만으로는 안 걸러진다.
				if Combat.canAttack(view, instance) and not Rules.hasDeclaredAttack(view, instance.id) then
					light(instance)
				end
			end
		elseif view.phase == Phase.DefensePrep and view.activePlayerId == self.foe then
			for _, instance in GameState.creaturesOnField(view, self.me) do
				-- canBlock 이 탭·필드 여부까지 보므로 여기서 또 보지 않는다.
				if not view.combat.blocks[instance.id] and canBlockAnyAttacker(view, instance) then
					light(instance)
				end
			end
		end
	end

	return out
end

function Controller:promptText()
	local mode = self.mode

	local function nameOf(instanceId)
		local instance = self.view.cards[instanceId]
		return instance and Registry.mustGet(instance.defId).name or "?"
	end

	if mode.name == "target" then
		return ("%s — 대상을 고르세요 (%d/%d)"):format(mode.def.name, mode.stepIndex, #mode.steps)
	end
	if mode.name == "attack" then
		return ("%s — 공격할 대상을 고르세요"):format(nameOf(mode.attackerId))
	end
	if mode.name == "block" then
		return ("%s — 막을 공격자를 고르세요"):format(nameOf(mode.blockerId))
	end
	return nil
end

function Controller:hintText()
	local view = self.view

	if view.finished then
		return "게임이 끝났습니다."
	end
	if self.mode.name ~= "idle" then
		return "초록 테두리를 누르세요.\n취소하려면 '선택 취소'."
	end
	if view.phase == Phase.Mulligan and whoActs(view) ~= self.me then
		return "상대가 손패를 고르는 중입니다."
	end
	if whoActs(view) ~= self.me then
		return "상대가 두는 중입니다."
	end

	if view.phase == Phase.Mulligan then
		if view.mulligan and view.mulligan.used[self.me] then
			return "이미 한 번 물렸습니다.\n'이대로 시작' 을 누르세요."
		end
		return "손패가 마음에 안 들면 한 번, 벌칙 없이 통째로 바꿀 수 있습니다."
	end

	if not Stack.isEmpty(view) then
		--[[
			대응할 카드가 없어도 [대응 패스] 를 눌러야 넘어간다
			(Config.autoPassWithNoResponse). 그러면 "왜 멈춰 있지" 가 되므로
			**낼 게 없다는 것**과 **무엇을 눌러야 하는지**를 같이 말해준다.
		]]
		for _, instanceId in view.players[self.me].hand or {} do
			if Rules.canPlayCard(view, self.me, instanceId) then
				return "상대의 시전에 대응할 수 있습니다.\n'즉시시전' 마법만 가능."
			end
		end
		return "대응할 카드가 없습니다.\n가운데 상자를 눌러 넘기세요."
	end
	if view.phase == Phase.Main then
		return "코스트 카드를 내고, 생물을 소환하고, 마법을 씁니다."
	end
	if view.phase == Phase.AttackPrep then
		return "공격할 생물을 누르세요.\n선언이 끝나면 페이즈 종료."
	end
	if view.phase == Phase.DefensePrep then
		return "막을 생물을 누르세요.\n신속 생물은 지금 소환해도 막을 수 있습니다."
	end
	return ""
end

function Controller:buttonStates()
	local view = self.view

	if view.finished then
		return {}
	end

	local acting = (whoActs(view) == self.me)
	local perms = Phases.permissions(view, self.me)
	local stackOpen = not Stack.isEmpty(view)

	local canClear = false
	if not stackOpen and acting then
		if view.phase == Phase.AttackPrep and view.activePlayerId == self.me then
			canClear = #view.combat.attackers > 0
		elseif view.phase == Phase.DefensePrep and view.activePlayerId == self.foe then
			canClear = next(view.combat.blocks) ~= nil
		end
	end

	-- 멀리건 관문에서는 이 두 개 말고는 누를 것이 없다.
	local atMulligan = (view.phase == Phase.Mulligan) and acting
	local usedMulligan = view.mulligan and view.mulligan.used[self.me]

	local states = {
		endPhase = acting and perms.endPhase and not stackOpen,
		pass = acting and stackOpen,
		cancel = self.mode.name ~= "idle",
		clear = canClear,
		mulligan = atMulligan and not usedMulligan,
		keep = atMulligan,
	}

	--[[
		튜토리얼은 시킨 것만 켠다. **판정을 여기 한 곳에 두는 게 요점이다** —
		화면에서만 끄면 단축키(E · P)가 그대로 통해서 코치를 앞질러 갈 수 있다.
		(onAction 이 같은 허용표를 다시 본다)
	]]
	local allow = self:coachAllow()
	if not allow.free then
		for key, on in states do
			states[key] = on and Tutorial.allowsButton(allow, key)
		end
	end

	return states
end

function Controller:refresh()
	if not self.view then
		return
	end

	local allow = self:coachAllow()

	--[[
		묻는 중이라도 그 사이에 패스가 불가능해졌으면(스택이 비었거나 내 차례가 아니게
		됐다) 확인 버튼을 띄우지 않는다. 눌러봐야 거부당할 버튼은 없는 것만 못하다.
	]]
	local buttons = self:buttonStates()

	self.battle:render(self.view, {
		highlights = self:highlights(),
		selectedId = self.mode.cardId or self.mode.attackerId or self.mode.blockerId,
		prompt = self:promptText(),
		hint = self:hintText(),
		coach = self.tutorial:textOf(self:coachStep(), self.view, self.me),
		endNote = self:endNote(),
		lockedHand = self:lockedHand(allow),
		busy = (not self.view.finished) and whoActs(self.view) ~= self.me,
		buttons = buttons,
		confirmPass = self.confirmPass and buttons.pass or false,
		concedeArmed = self.confirmConcede or false,
		endActions = self:endActions(),
	})
end

--==========================================================================
-- 손패
--==========================================================================

--[[
	이 마법이 물어봐야 하는 대상 목록. 대상이 없는 효과는 건너뛴다.
]]
local function targetSteps(def)
	local steps = {}

	if def.type ~= CardType.Spell then
		return steps
	end

	for index, effect in def.effects do
		if (effect.target or TargetKind.None) ~= TargetKind.None then
			table.insert(steps, { index = index, effect = effect })
		end
	end
	return steps
end

function Controller:onHandCard(instanceId)
	local view = self.view
	if not view or view.finished then
		return
	end

	if whoActs(view) ~= self.me then
		self.battle:showToast("상대 차례입니다", "error")
		return
	end

	local instance = view.cards[instanceId]
	if not instance then
		return
	end

	if not Tutorial.allowsHand(self:coachAllow(), view, self.me, instanceId) then
		self:coachToast()
		return
	end

	local ok, reason = Rules.canPlayCard(view, self.me, instanceId)
	if not ok then
		self.battle:showToast(tostring(reason), "error")
		return
	end

	local def = Registry.mustGet(instance.defId)
	local steps = targetSteps(def)

	if #steps == 0 then
		self.mode = { name = "idle" }
		self:send({ kind = "play", cardId = instanceId, targets = {} })
		return
	end

	self.mode = {
		name = "target",
		cardId = instanceId,
		def = def,
		steps = steps,
		stepIndex = 1,
		collected = {},
	}
	self:refresh()
end

--[[
	target 모드에서 대상 하나를 받는다.
]]
function Controller:takeTarget(target)
	local mode = self.mode
	local step = mode.steps[mode.stepIndex]

	local ok, reason = Effects.validateTarget(self.view, step.effect, self.me, target)
	if not ok then
		self.battle:showToast(tostring(reason or "지정할 수 없는 대상입니다"), "error")
		return
	end

	mode.collected[step.index] = target
	mode.stepIndex += 1

	if mode.stepIndex > #mode.steps then
		local cardId = mode.cardId
		local targets = Net.packTargets(mode.collected)
		self.mode = { name = "idle" }
		self:send({ kind = "play", cardId = cardId, targets = targets })
		return
	end

	self:refresh()
end

--==========================================================================
-- 필드 / 플레이어 / 스택 클릭
--==========================================================================

function Controller:onFieldCard(instanceId)
	local view = self.view
	if not view or view.finished then
		return
	end

	local mode = self.mode
	local instance = view.cards[instanceId]
	if not instance then
		return
	end

	if mode.name == "target" then
		self:takeTarget({ kind = "Creature", id = instanceId })
		return
	end

	-- 공격/방어 모드에서 **내 생물**을 누르면 "다른 애로 바꾸겠다" 는 뜻이다.
	-- 서버에 보내봐야 거부당할 요청을 만들지 않고 선택만 갈아끼운다.
	if (mode.name == "attack" or mode.name == "block") and instance.controllerId == self.me then
		self.mode = { name = "idle" }
		self:onFieldCard(instanceId)
		return
	end

	if mode.name == "attack" then
		self.mode = { name = "idle" }
		self:send({
			kind = "attack",
			attackerId = mode.attackerId,
			target = { kind = "Creature", id = instanceId },
		})
		return
	end

	if mode.name == "block" then
		local blockerId = mode.blockerId
		self.mode = { name = "idle" }
		self:send({ kind = "block", blockerId = blockerId, attackerId = instanceId })
		return
	end

	--------------------------------------------------------------------
	-- idle — 내 생물을 골라 공격/방어를 시작한다
	--------------------------------------------------------------------
	if whoActs(view) ~= self.me or instance.controllerId ~= self.me then
		return
	end

	if not Tutorial.allowsField(self:coachAllow(), view, self.me, instanceId) then
		self:coachToast()
		return
	end

	if view.phase == Phase.AttackPrep and view.activePlayerId == self.me then
		local ok, reason = Combat.canAttack(view, instance)
		if not ok then
			self.battle:showToast(tostring(reason), "error")
			return
		end
		if Rules.hasDeclaredAttack(view, instanceId) then
			self.battle:showToast("이미 공격을 선언한 생물입니다", "error")
			return
		end
		if #Combat.legalAttackTargets(view, instance) == 0 then
			self.battle:showToast("공격할 수 있는 대상이 없습니다 (도발/비행 확인)", "error")
			return
		end

		self.mode = { name = "attack", attackerId = instanceId }
		self:refresh()
		return
	end

	if view.phase == Phase.DefensePrep and view.activePlayerId == self.foe then
		if instance.tapped then
			self.battle:showToast("탭된 생물은 방어할 수 없습니다", "error")
			return
		end
		if view.combat.blocks[instanceId] then
			self.battle:showToast("이미 방어를 배정한 생물입니다", "error")
			return
		end
		if not canBlockAnyAttacker(view, instance) then
			self.battle:showToast("이 생물이 막을 수 있는 공격자가 없습니다 (비행 확인)", "error")
			return
		end

		self.mode = { name = "block", blockerId = instanceId }
		self:refresh()
	end
end

function Controller:onPlayer(playerId)
	local view = self.view
	if not view or view.finished then
		return
	end

	if self.mode.name == "target" then
		self:takeTarget({ kind = "Player", id = playerId })
		return
	end

	if self.mode.name == "attack" and playerId == self.foe then
		local attackerId = self.mode.attackerId
		self.mode = { name = "idle" }
		self:send({
			kind = "attack",
			attackerId = attackerId,
			target = { kind = "Player", id = self.foe },
		})
	end
end

--[[
	스택 칩을 누르는 일.

	대상 고르는 중이면 그 칩이 대상이다(즉시시전으로 스택을 되받아치는 경우).
	그게 아니면 **대응 패스를 묻는다** — 대응 창은 보드 한가운데서 열리는데
	[대응 패스] 는 오른쪽 끝에 있어서, 매번 눈과 손이 화면을 가로질러야 했다.

	곧장 넘기지 않고 한 번 묻는 이유는 `Battle:renderCenter` 의 확인 버튼 주석에 있다.
	패스가 지금 가능한지는 `buttonStates` 에 묻는다 — 튜토리얼 잠금까지 거기 들어 있어서,
	코치가 아직 안 켠 패스를 이 지름길로 앞질러 갈 수 없다.
]]
function Controller:onStackItem(stackItemId)
	if self.mode.name == "target" then
		self:takeTarget({ kind = "StackItem", id = stackItemId })
		return
	end

	if not self:buttonStates().pass then
		return
	end

	-- 같은 칩을 다시 누르면 묻기를 거둔다. 물어놓고 빠져나갈 길이 없으면 안 된다.
	self.confirmPass = not self.confirmPass
	self:refresh()
end

--==========================================================================
-- 버튼
--==========================================================================

-- 코치가 통제하는 버튼. 나가기(항복·로그·취소)는 여기 없다.
local COACHED_KEYS = {
	endPhase = true,
	pass = true,
	clear = true,
	mulligan = true,
	keep = true,
}

function Controller:onAction(key)
	local view = self.view

	-- 항복 되묻기는 그 자리에서만 산다. 다른 것을 누른 순간 없던 일이 된다.
	if key ~= "concede" then
		self.confirmConcede = false
	end

	--[[
		눌린 소리. 여기 두는 이유는 **버튼과 단축키가 같은 문으로 들어오기** 때문이다.
		위젯 쪽에 달면 키보드로 넘긴 페이즈는 소리가 안 난다.

		거부당한 경우(코치가 안 켠 버튼 등)는 아래에서 coachToast 가 deny 를 울린다.
	]]
	Sfx.play("click")

	if key == "log" then
		self.battle:toggleLog()
		return
	end
	-- 판 밖으로 나가는 요청은 대전이 아니라 로비가 받는다.
	-- (예약 서버에서는 로비로 텔레포트하는 일이라 매치 러너가 할 수 있는 일이 아니다)
	if key == "leave" or key == "requeue" then
		self.mode = { name = "idle" }
		self.remotes.Lobby:FireServer({ kind = key })
		return
	end
	if key == "restart" then
		self.mode = { name = "idle" }
		self:send({ kind = "restart" })
		return
	end
	if key == "cancel" then
		self.mode = { name = "idle" }
		self.confirmPass = false
		self:refresh()
		return
	end

	if not view or view.finished then
		return
	end

	--[[
		단축키(E · P)는 버튼을 거치지 않으므로 꺼진 버튼을 그냥 지나친다.
		튜토리얼에서는 여기서 한 번 더 본다 — buttonStates 와 **같은 허용표**다.

		항복과 로그는 거르지 않는다. 튜토리얼 도중에 나가려면 항복이 유일한 출구다.
	]]
	if COACHED_KEYS[key] and not Tutorial.allowsButton(self:coachAllow(), key) then
		self:coachToast()
		return
	end

	if key == "mulligan" or key == "keep" then
		self.mode = { name = "idle" }
		self:send({ kind = key })
		return
	end

	if key == "endPhase" then
		self.mode = { name = "idle" }
		self:send({ kind = "endPhase" })
	elseif key == "pass" then
		self.mode = { name = "idle" }
		self.confirmPass = false
		self:send({ kind = "pass" })
	elseif key == "concede" then
		--[[
			**한 번 더 묻는다.** 판을 통째로 끝내는 유일한 버튼인데 지금까지 한 번에
			나갔다. 창을 따로 띄우지 않고 버튼 글자를 "정말 항복?" 으로 바꾸는 것은
			스택 상자와 **같은 약속**으로 만들기 위해서다 — 이 화면에서 되돌릴 수 없는
			일은 두 번 누른다.

			물어둔 것은 다른 버튼을 누르거나 서버 상태가 바뀌면 거둔다(onAction 머리와
			onSync). 눌러놓고 잊은 항복이 남아 있다가 나중에 나가면 안 된다.
		]]
		if not self.confirmConcede then
			self.confirmConcede = true
			self:refresh()
			return
		end
		self.confirmConcede = false
		self:send({ kind = "concede" })
	elseif key == "clear" then
		if view.phase == Phase.DefensePrep then
			self:send({ kind = "clearBlockers" })
		else
			self:send({ kind = "clearAttackers" })
		end
	end
end

return Controller
