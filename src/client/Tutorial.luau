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
	    text   말풍선. 함수면 판 상태를 받아 만든다
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
	태그 5종을 차례로 소개한다.

	처음에는 "지금 화면에 나와 있는 태그" 만 골라 설명했다. 카드를 보면서 읽는 게 낫다고
	봤는데, 실제로 재보니 한 판에 **두 종밖에** 안 나왔다 — 손에 잡히는 카드는 판마다
	다르고, 자유롭게 두는 구간은 열댓 턴 중 절반도 안 된다. 그래서 다섯을 고정 순서로
	돌린다. 튜토리얼 덱에 다섯이 전부 들어 있으므로, 여기 설명은 곧 그 판에서 만나게 될
	카드 이야기다.

	넘어가는 단위는 **페이즈**다. 매 렌더마다 돌리면 읽는 중에 글이 바뀌고,
	턴마다 돌리면 한 판에 서너 개밖에 못 보여준다.
]]
local TAG_ORDER = { Keyword.Taunt, Keyword.Flying, Keyword.Ranged, Keyword.Haste, Keyword.Instant }

local PHASE_STEP = {
	[Phase.Main] = 0,
	[Phase.AttackPrep] = 1,
	[Phase.DefensePrep] = 2,
}

local function tagForNow(view)
	local step = view.turn * 3 + (PHASE_STEP[view.phase] or 0)
	return TAG_ORDER[(step % #TAG_ORDER) + 1]
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
		text = "생물을 내면서 코스트 카드가 <b>탭</b> 됐어요 — 옆으로 누운 카드예요.\n"
			.. "탭된 카드는 이번 턴에 다시 못 써요. 내 턴이 시작할 때 <b>언탭</b> 돼서 다시 서요.\n"
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
		text = function(view, me)
			if acting(view, me) then
				return "상대가 공격했어요!\n"
					.. "막을 생물을 누르고, 막을 공격자를 고르세요.\n"
					.. "안 막으면 그 공격력만큼 내 라이프가 깎여요."
			end
			return "상대 차례예요. 무엇을 하는지 지켜보세요.\n" .. "오른쪽 로그에 무슨 일이 있었는지 남아요."
		end,
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
					.. "생물을 누른 다음, 공격할 대상을 고르세요 — 상대 생물도, 상대 자신도 돼요.\n"
					.. "공격을 선언한 생물은 <b>탭</b> 돼요. 다음 내 턴에 언탭돼요."
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
		text = function(view, me)
			if view.phase == Phase.AttackPrep and #view.combat.attackers > 0 then
				return "공격을 선언했어요.\n"
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
			local tag = tagForNow(view)
			if tag then
				return ("<b>%s</b> — %s\n"):format(Enums.KeywordDisplay[tag], Enums.KeywordText[tag]) .. goal
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
	return setmetatable({ index = 1 }, Tutorial)
end

-- 판이 새로 열리면 처음부터. (다시 하기 · 튜토리얼 재입장)
function Tutorial:reset()
	self.index = 1
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

-- 지금 단계의 말풍선. 단계가 다 끝났으면 nil (코치가 사라진다).
function Tutorial.textOf(step, view, me)
	if not step then
		return nil
	end
	if type(step.text) == "function" then
		return step.text(view, me)
	end
	return step.text
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
