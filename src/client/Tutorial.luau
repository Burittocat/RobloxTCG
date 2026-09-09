--[[
	튜토리얼 코치.

	"가이드 붙은 한 판" 이다. 진짜 판을 진짜 룰로 두면서 두 가지를 한다.
	  · 지금 무엇을 하면 되는지 말풍선으로 알려준다
	  · 시킨 것 말고는 못 누르게 잠근다

	판을 어떤 조건으로 여는지(덱·시드·상대 라이프)는 서버가 정한다 — `Lobby:startTutorial`.
	여기는 **화면 쪽 코치**만 맡는다. 룰 판정은 한 줄도 새로 쓰지 않고 Rules 를 그대로 부른다.

	--------------------------------------------------------------------------
	왜 대본이 아니라 조건인가

	"1턴에 코스트, 2턴에 소환" 같은 턴 번호 대본은 처음 한 번만 맞는다. 다시 하기를
	누르면 덱이 새로 섞이고, `Sheet.luau` 에서 카드 수치를 고치면 AI 가 다른 수를 두고,
	사람이 예상 밖의 순서로 눌러도 어긋난다. 그래서 각 단계는 **판 상태를 보고**
	끝났는지(done)와 이 판에서는 가르칠 수 없는지(skip)를 스스로 판단한다.

	단계는 되돌아가지 않는다. 한 번 통과한 단계는 다시 안 뜬다 — 조건만으로 매번
	다시 고르면 "필드에 생물이 있다" 같은 조건이 생물이 죽는 순간 거짓이 되면서
	이미 배운 단계로 되돌아간다.

	--------------------------------------------------------------------------
	잠금은 idle 일 때만

	카드를 고르기 시작한 뒤(대상 지정 · 공격 대상 · 방어 대상)에는 잠그지 않는다.
	그 순간 누를 수 있는 것은 이미 룰이 초록으로 좁혀놨고, 거기서 코치가 또 막으면
	고르다 만 상태로 갇힌다. 코치가 통제하는 것은 **무엇을 시작할 수 있나** 뿐이다.

	그리고 뒤로 갈수록 잠금을 푼다. 기본을 배운 뒤에도 계속 손을 잡고 있으면
	그건 튜토리얼이 아니라 시연이다.

	--------------------------------------------------------------------------
	단계 하나

	    key    이름. 테스트가 "지금 몇 단계인가" 를 이걸로 가리킨다
	    text   말풍선. 함수면 (view, me, 코치) 를 받아 만든다
	    done   (view, me) -> boolean    끝났으면 다음 단계로
	    skip   (view, me) -> boolean?   이 판에서는 가르칠 수 없다 (선택)
	    allow  (view, me) -> 허용표     무엇을 누를 수 있나

	허용표
	    { free = true }                       잠그지 않는다
	    { buttons = { endPhase = true },      켤 버튼 (적은 것만 켜진다)
	      hand = (view, me, id) -> boolean,   누를 수 있는 손패 카드 (없으면 전부 잠김)
	      field = (view, me, id) -> boolean } 누를 수 있는 내 생물
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rules = require(Shared.Rules)

local Enums = Rules.Enums
local GameState = Rules.GameState
local Registry = Rules.Registry
local Combat = Rules.Combat

local Phase = Enums.Phase
local CardType = Enums.CardType
local Keyword = Enums.Keyword
local Zone = Enums.Zone

local FREE = { free = true }
local NOTHING = { buttons = {} }

--==========================================================================
-- 판 읽기
--==========================================================================

local function myTurn(view, me)
	return view.activePlayerId == me
end

-- "내 턴" 과 "내 차례" 는 다르다. 수비준비에서는 상대 턴인데 내가 둔다.
local function acting(view, me)
	return Rules.whoActs(view) == me
end

local function defOf(view, instanceId)
	local instance = view.cards[instanceId]
	return instance and Registry.get(instance.defId) or nil
end

-- 지금 낼 수 있는 손패 카드. cardType 을 주면 그 종류만.
local function playableIds(view, me, cardType)
	local out = {}
	for _, instanceId in view.players[me].hand or {} do
		local def = defOf(view, instanceId)
		if def and (cardType == nil or def.type == cardType) and Rules.canPlayCard(view, me, instanceId) then
			table.insert(out, instanceId)
		end
	end
	return out
end

-- 지금 공격을 선언할 수 있는 내 생물.
local function attackerIds(view, me)
	local out = {}
	for _, instance in GameState.creaturesOnField(view, me) do
		if Combat.canAttack(view, instance) then
			table.insert(out, instance.id)
		end
	end
	return out
end

-- 내 전장에 탭된 카드가 있는가. (코스트를 뽑으면 그 카드가 탭된다)
local function hasTappedCard(view, me)
	for _, instanceId in view.players[me].field or {} do
		local instance = view.cards[instanceId]
		if instance and instance.tapped then
			return true
		end
	end
	return false
end

--[[
	태그는 코치가 읊지 않는다. **찾아보는 법**을 가르친다.

	처음에는 말풍선으로 태그를 하나씩 설명했다. 화면에 나와 있는 것만 고르면 한 판에
	두 종밖에 못 만나고, 그게 아쉬워서 다섯을 무조건 돌렸더니 비행 생물이 한 마리도
	없는 판에서 비행 설명이 떴다 — 읽는 사람은 화면에서 그걸 찾다가 못 찾는다.

	어느 쪽도 맞지 않았다. 말풍선은 세 줄짜리라 다섯 종을 담을 수 없고, 판은 그중
	몇 종만 보여준다. 그래서 카드를 **오른쪽 클릭**하면 태그 효과까지 나오게 하고
	(`CardView.detail`), 코치는 그 손짓 하나만 가르친다. 그러면 궁금할 때 궁금한
	카드를 열어보면 된다 — 코치가 그 태그를 마침 골라줬는지에 기대지 않는다.

	아래는 "예를 들면 이 카드" 를 고르는 데만 쓴다.
]]
local TAG_ORDER = { Keyword.Taunt, Keyword.Flying, Keyword.Ranged, Keyword.Haste, Keyword.Instant }

local PHASE_STEP = {
	[Phase.Main] = 0,
	[Phase.AttackPrep] = 1,
	[Phase.DefensePrep] = 2,
}

--[[
	지금 화면에 나와 있는 태그. -> { { keyword = ..., card = "창공의 매" }, ... }

	즉시시전은 전장에 나오지 않는 태그라, 손패를 안 보면 영영 소개되지 않는다.
	카드 순서는 인스턴스 번호로 고정한다 — 테이블 순회 순서에 맡기면 같은 판에서도
	설명에 붙는 카드 이름이 바뀐다.
]]
local function visibleTags(view, me)
	local cardFor = {}

	local ids = {}
	for instanceId in view.cards do
		table.insert(ids, instanceId)
	end
	table.sort(ids)

	for _, instanceId in ids do
		local instance = view.cards[instanceId]
		local onField = instance.zone == Zone.Field
		local inMyHand = instance.zone == Zone.Hand and instance.controllerId == me

		if onField or inMyHand then
			local def = Registry.get(instance.defId)
			local name = def and def.name or "?"

			for _, keyword in (def and def.keywords) or {} do
				cardFor[keyword] = cardFor[keyword] or name
			end
			for _, keyword in instance.grantedKeywords or {} do
				cardFor[keyword] = cardFor[keyword] or name
			end
		end
	end

	local out = {}
	for _, keyword in TAG_ORDER do
		if cardFor[keyword] then
			table.insert(out, { keyword = keyword, card = cardFor[keyword] })
		end
	end
	return out
end

--[[
	"예를 들면 이 카드" — 지금 화면에 있는 태그 달린 카드 하나. -> { keyword, card } | nil

	손짓을 가르칠 때 가리킬 대상이다. 화면에 없는 카드를 예로 들면 그걸 찾다가 만다.
]]
local function tagExample(view, me)
	return visibleTags(view, me)[1]
end

local function contains(list, value)
	for _, entry in list do
		if entry == value then
			return true
		end
	end
	return false
end

-- 손패 술어: 이 종류의 "지금 낼 수 있는" 카드만 누를 수 있다.
local function onlyPlayable(cardType)
	return function(view, me, instanceId)
		return contains(playableIds(view, me, cardType), instanceId)
	end
end

--==========================================================================
-- 단계
--==========================================================================

local STEPS = {
	{
		key = "mulligan",
		text = "손패 7장으로 시작해요.\n"
			.. "마음에 안 들면 딱 한 번, 벌칙 없이 통째로 바꿀 수 있어요.\n"
			.. "[이대로 시작] 을 눌러 볼까요.",
		done = function(view)
			return view.phase ~= Phase.Mulligan
		end,
		-- 물려보는 것도 배우는 것이라 둘 다 열어둔다. 어느 쪽을 눌러도 다음은 같다.
		allow = function()
			return { buttons = { keep = true, mulligan = true } }
		end,
	},

	{
		key = "cost",
		text = "카드를 내려면 <b>코스트</b> 가 필요해요.\n"
			.. "손패에서 [에너지 코어] 를 눌러 전장에 내세요.\n"
			.. "코스트 카드는 한 턴에 한 장만 낼 수 있어요.",
		done = function(view, me)
			return #GameState.costCardsOnField(view, me) > 0
		end,
		allow = function()
			return { buttons = {}, hand = onlyPlayable(CardType.Cost) }
		end,
	},

	{
		key = "summon",
		--[[
			1코 생물이 손에 없을 수 있다. 그때는 이 단계를 건너뛴다 —
			낼 수 없는 카드를 가리키며 "소환하세요" 라고 하면 거기서 막힌다.
		]]
		text = "전장의 코스트 카드를 <b>탭</b> 하면 코스트 1 이 나와요.\n"
			.. "이제 생물을 소환해 보세요. 지금 낼 수 있는 카드가 밝게 켜져 있어요.",
		skip = function(view, me)
			return #playableIds(view, me, CardType.Creature) == 0
		end,
		done = function(view, me)
			return #GameState.creaturesOnField(view, me) > 0
		end,
		allow = function()
			return { buttons = {}, hand = onlyPlayable(CardType.Creature) }
		end,
	},

	{
		--[[
			탭이 뭔지 여기서 말한다. 소환하면서 코스트 카드가 방금 눕는 것을 봤을 때가
			제일 좋은 자리다 — 화면에 "탭됨" 표시가 떠 있는 상태라 글자와 그림이 붙는다.

			생물을 못 낸 판(코스트가 안 탭된 판)에서는 건너뛴다. 그러면 바로 아래
			endMain 이 같은 일(페이즈 종료)을 맡는다.
		]]
		key = "tap",
		text = "코스트 카드가 <b>탭</b> 됐어요 — 옆으로 누운 카드예요.\n"
			.. "이번 턴엔 다시 못 쓰고, 내 턴이 시작할 때 <b>언탭</b> 돼요.\n"
			.. "[페이즈 종료] 로 공격준비로 넘어가세요.",
		skip = function(view, me)
			return not myTurn(view, me) or not hasTappedCard(view, me)
		end,
		done = function(view, me)
			return not myTurn(view, me) or view.phase ~= Phase.Main
		end,
		allow = function()
			return { buttons = { endPhase = true } }
		end,
	},

	{
		key = "endMain",
		text = "이번 턴에 할 것은 다 했어요.\n"
			.. "[페이즈 종료] 를 누르면 <b>공격준비</b> 로 넘어가요.\n"
			.. "턴은 메인 → 공격준비 → 수비준비 순서로 흘러요.",
		done = function(view, me)
			return not myTurn(view, me) or view.phase ~= Phase.Main
		end,
		allow = function()
			return { buttons = { endPhase = true } }
		end,
	},

	{
		key = "sick",
		--[[
			신속 생물을 냈다면 이 설명은 거짓말이 된다(그 생물은 지금 공격할 수 있다).
			그때는 건너뛰고 공격 단계에서 만난다.
		]]
		text = "방금 소환한 생물은 이번 턴에 공격할 수 없어요 — <b>소환 멀미</b> 예요.\n"
			.. "(신속 태그가 있으면 예외예요)\n"
			.. "[페이즈 종료] 로 턴을 넘기세요.",
		skip = function(view, me)
			return not myTurn(view, me) or #attackerIds(view, me) > 0
		end,
		done = function(view, me)
			return not myTurn(view, me)
		end,
		allow = function()
			return { buttons = { endPhase = true } }
		end,
	},

	{
		key = "foeTurn",
		-- 대응 창과 방어는 단계가 아니라 **상황 안내**가 맡는다 (Tutorial:textOf).
		text = "상대 차례예요. 무엇을 하는지 지켜보세요.\n오른쪽 로그에 무슨 일이 있었는지 남아요.",
		done = function(view, me)
			return myTurn(view, me) and view.phase == Phase.Main
		end,
		--[[
			상대 턴이라도 **수비준비에서는 내가 둔다.** 여기서 잠그면 막을 수가 없다.
			(즉시시전 대응 창도 같은 경우다)
		]]
		allow = function(view, me)
			return acting(view, me) and FREE or NOTHING
		end,
	},

	{
		key = "secondMain",
		text = "다시 내 차례예요.\n"
			.. "코스트를 한 장 더 내고 생물을 소환하세요.\n"
			.. "준비가 되면 [페이즈 종료] — 이번엔 공격까지 가 볼게요.",
		done = function(view, me)
			return myTurn(view, me) and view.phase ~= Phase.Main
		end,
		allow = function()
			return { buttons = { endPhase = true }, hand = onlyPlayable(nil) }
		end,
	},

	{
		--[[
			여기서부터 잠그지 않는다. 공격은 몇 턴 뒤에 성립할 수도 있고
			(소환 멀미가 안 풀렸거나 생물이 없거나), 그동안 사람은 자기 판단으로
			코스트를 내고 생물을 소환할 수 있어야 한다.
		]]
		key = "attack",
		text = function(view, me)
			if not myTurn(view, me) then
				return "상대 차례예요.\n내 차례가 오면 생물로 공격해 볼게요."
			end
			if view.phase == Phase.AttackPrep then
				if #attackerIds(view, me) == 0 then
					return "이번 턴엔 공격할 수 있는 생물이 없어요.\n"
						.. "소환 멀미는 다음 턴에 풀려요. [페이즈 종료] 로 넘기세요."
				end
				return "공격할 수 있는 생물이 초록으로 켜졌어요.\n"
					.. "생물을 누르고 공격할 대상을 고르세요. 상대 자신도 돼요.\n"
					.. "공격을 선언한 생물은 <b>탭</b> 돼요."
			end
			return "코스트를 내고 생물을 소환한 뒤,\n[페이즈 종료] 로 <b>공격준비</b> 까지 가 보세요."
		end,
		done = function(view)
			return #view.combat.attackers > 0
		end,
		allow = function()
			return FREE
		end,
	},

	{
		key = "win",
		text = function(view, me, coach)
			if view.phase == Phase.AttackPrep and #view.combat.attackers > 0 then
				return "공격을 선언했어요. <font color='#E8423E'>빨간 화살표</font>가 대상이에요.\n"
					.. "[페이즈 종료] 를 누르면 상대가 막을 차례예요.\n"
					.. "막히지 않은 공격만 상대 라이프로 들어가요."
			end

			local foe = view.players[GameState.opponentOf(me)]
			local goal = ("상대 라이프를 0 으로 만들면 승리예요. (남은 라이프 %d)"):format(foe.life)

			--[[
				이제 잠금이 없으니 말풍선은 **태그 교실**로 쓴다. 지금 판에 나와 있는
				태그를 턴마다 하나씩 소개한다 — 화면에 그 카드가 실제로 있을 때 읽어야
				"이게 그거구나" 가 된다. 튜토리얼 덱에 태그 5종이 다 들어 있는 이유다.
			]]
			--[[
				손짓을 아직 안 써봤으면 그것부터 알려준다. 한 번 써보면 잔소리를 멈춘다 —
				배운 것을 계속 시키면 말풍선이 배경이 된다.
			]]
			if not (coach and coach.inspected) then
				local example = coach and tagExample(view, me)
				if example then
					return "궁금한 카드는 <b>오른쪽 클릭</b> — 태그가 무슨 효과인지 나와요.\n"
						.. ("%s의 <b>%s</b> 로 해보세요.\n"):format(
							example.card,
							Enums.KeywordDisplay[example.keyword]
						)
						.. goal
				end
				return "궁금한 카드는 <b>오른쪽 클릭</b> — 자세한 설명이 나와요.\n" .. goal
			end

			return "기본은 다 배웠어요 — 이제 자유롭게 두세요.\n" .. goal
		end,
		done = function(view)
			return view.finished == true
		end,
		allow = function()
			return FREE
		end,
	},
}

--==========================================================================

local Tutorial = {}
Tutorial.__index = Tutorial

function Tutorial.new()
	local self = setmetatable({}, Tutorial)
	self:reset()
	return self
end

-- 판이 새로 열리면 처음부터. (다시 하기 · 튜토리얼 재입장)
function Tutorial:reset()
	self.index = 1
	self.inspected = false -- 카드를 오른쪽 클릭해 봤는가
	self.lastTurn = nil
end

--[[
	판이 새로 열렸으면 코치도 처음으로 되돌린다.

	**"다시 하기" 는 Controller:start 를 거치지 않는다.** 같은 러너가 같은 자리에서
	새 판을 열고 스냅샷만 새로 오기 때문이다. 그래서 항복하고 다시 하기를 누르면
	코치가 지난 판의 마지막 단계에 머문 채 새 판을 맞았다 — 멀리건 관문인데
	"코스트 카드를 내세요" 라고 하는 식이다.

	턴이 뒤로 갔으면 새 판이다. 멀리건 관문은 턴 0 이라, 멀리건을 켜든 끄든 걸린다.
	(둘째 조건은 1턴에 끝난 판까지 챙긴다)
]]
function Tutorial:noticeNewMatch(view)
	local turn = view.turn or 0

	if (self.lastTurn and turn < self.lastTurn) or (view.phase == Phase.Mulligan and self.index > 1) then
		self:reset()
	end

	self.lastTurn = turn
end

--[[
	판 상태를 보고 단계를 진행시킨다. -> 지금 단계 (없으면 nil)

	끝난 단계와 이 판에서 가르칠 수 없는 단계를 연달아 넘긴다. 한 번에 여러 단계가
	넘어갈 수 있다 — 사람이 코치보다 빨리 두는 경우가 그렇다.
]]
function Tutorial:update(view, me)
	if not view or not view.players[me] then
		return nil
	end

	self:noticeNewMatch(view)

	while self.index <= #STEPS do
		local step = STEPS[self.index]
		if step.done(view, me) or (step.skip and step.skip(view, me)) then
			self.index += 1
		else
			break
		end
	end

	return STEPS[self.index]
end

--[[
	단계보다 먼저 봐야 하는 상황. -> 말풍선 | nil

	지금 눌러야 할 것이 정해져 있는 순간이 둘 있다. 어느 단계에 있든 그게 먼저다.

	  대응 창   상대가 카드를 내는 중이고 내가 대응권자다
	  수비준비  상대가 공격했고 내가 막을 차례다

	단계로 만들지 않은 이유: **언제 올지 모른다.** 방어를 "상대 첫 턴" 단계에 넣었더니
	한 번도 안 떴다 — 소환 멀미 때문에 상대의 첫 공격은 그 뒤에 온다. 상황은 상황으로
	다뤄야 어느 턴에 오든 맞는 말을 한다.
]]
function Tutorial.situationText(view, me)
	if not acting(view, me) then
		return nil
	end

	if #view.stack > 0 then
		return "상대가 카드를 내는 중이에요.\n"
			.. "지금 대응할 수 있는 건 <b>즉시시전</b> 마법뿐이에요.\n"
			.. "낼 게 없으면 [대응 패스] 로 넘기세요."
	end

	if view.phase == Phase.DefensePrep then
		return "상대가 공격했어요!\n"
			.. "막을 생물을 누른 다음, 막을 공격자를 고르세요.\n"
			.. "여러 마리로 함께 막아도 돼요. 안 막으면 라이프가 깎여요."
	end

	return nil
end

-- 지금 단계의 말풍선. 단계가 다 끝났으면 nil (코치가 사라진다).
function Tutorial:textOf(step, view, me)
	if not step then
		return nil
	end

	local situation = Tutorial.situationText(view, me)
	if situation then
		return situation
	end

	if type(step.text) == "function" then
		return step.text(view, me, self)
	end
	return step.text
end

-- 카드를 한 번이라도 들여다봤다. (Controller 가 오른쪽 클릭을 받으면 알려준다)
function Tutorial:markInspected()
	self.inspected = true
end

--[[
	지금 단계가 허용하는 것. -> 허용표

	단계가 없으면(다 배웠으면) 잠그지 않는다.
]]
function Tutorial.allowOf(step, view, me)
	if not step then
		return FREE
	end
	return step.allow(view, me)
end

--==========================================================================
-- 잠금 판정 — Controller 가 클릭마다 물어본다
--==========================================================================

function Tutorial.allowsButton(allow, key)
	if allow.free then
		return true
	end

	--[[
		대응 창은 어느 단계에서든 닫을 수 있어야 한다.

		상대가 카드를 낼 때마다 열리는데(Config.autoPassWithNoResponse = false),
		그때 코치가 [대응 패스] 를 잠그고 있으면 사람은 아무것도 못 하고 갇힌다.
		버튼 자체는 대응권이 있을 때만 켜지므로(buttonStates), 여기서 열어둬도
		"아무 때나 눌리는" 일은 없다.
	]]
	if key == "pass" then
		return true
	end

	return (allow.buttons or {})[key] == true
end

function Tutorial.allowsHand(allow, view, me, instanceId)
	if allow.free then
		return true
	end
	return allow.hand ~= nil and allow.hand(view, me, instanceId)
end

function Tutorial.allowsField(allow, view, me, instanceId)
	if allow.free then
		return true
	end
	return allow.field ~= nil and allow.field(view, me, instanceId)
end

-- 잠그지 않는 허용표. 튜토리얼이 아닌 판은 언제나 이것이다.
Tutorial.FREE = FREE
Tutorial.STEPS = STEPS

return Tutorial
