--[[
	공개 서버(= 로비)에서 도는 것.

	여기서는 카드를 한 장도 내지 않는다. 하는 일은 넷이다.
	  1. 시작 화면 상태를 클라이언트에 알려준다        (Lobby 리모트)
	  2. 빠른 대전 큐 등록/취소                        (Matchmaker)
	  3. AI 연습·튜토리얼·캠페인은 큐를 타지 않고 이 자리에서 한 판 띄운다
	  4. 덱 저장과 카드팩 — 가진 카드(CollectionStore)와 골드를 다룬다

	PvP 매치는 여기서 굴리지 않는다. 짝이 지어지면 두 사람은 예약 서버로 텔레포트되고
	거기서 Arena 가 판을 연다. 로비 서버가 대전까지 맡으면 인원이 많은 서버일수록
	느려져서, 매칭 운이 곧 플레이 품질이 된다.

	(예외: Studio 의 같은 서버 백엔드는 텔레포트가 없으므로 여기서 바로 시작한다.
	 accessCode 가 없는 매치가 그 경우다.)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AI = require(Shared.AI)
local Net = require(Shared.Net)

local Campaign = require(Shared.Campaign)
local Collection = require(Shared.Collection)
local Decks = require(Shared.Decks)
local Products = require(Shared.Products)
local Rules = require(Shared.Rules)

local CampaignStore = require(script.Parent.CampaignStore)
local CollectionStore = require(script.Parent.CollectionStore)
local DeckStore = require(script.Parent.DeckStore)
local MatchRunner = require(script.Parent.MatchRunner)
local Matchmaker = require(script.Parent.Matchmaker)
local PvpReward = require(script.Parent.PvpReward)

local Screen = Net.LobbyScreen

local Lobby = {}
Lobby.__index = Lobby

function Lobby.new(remotes, host)
	local self = setmetatable({}, Lobby)

	self.remotes = remotes
	self.host = host
	self.screens = {} :: { [Player]: any }
	self.deckStore = DeckStore.new()
	self.campaignStore = CampaignStore.new()
	self.collectionStore = CollectionStore.new()

	-- 캠페인 판을 두는 중인 사람 -> 스테이지 번호. 판이 끝나고 어디로 돌려보낼지의 근거다.
	self.campaignStage = {} :: { [Player]: number }

	self.matchmaker = Matchmaker.new({
		onMatchFound = function(player, opponentName)
			self:setScreen(player, { screen = Screen.Found, opponent = opponentName })
		end,

		onMatchReady = function(match, players)
			self:startLocalMatch(match, players)
		end,

		onTeleportFail = function(player)
			self:setScreen(player, {
				screen = Screen.Error,
				text = "대전 서버로 이동하지 못했습니다. 다시 시도해 주세요.",
			})
		end,
	})

	remotes.Lobby.OnServerEvent:Connect(function(player, payload)
		local ok, err = pcall(function()
			self:onMessage(player, payload)
		end)
		if not ok then
			warn(("[TCG] 로비 요청 처리 실패: %s"):format(tostring(err)))
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.matchmaker:cancel(player)
		self.screens[player] = nil
		self.campaignStage[player] = nil
		self.deckStore:forget(player)
		self.campaignStore:forget(player)
		self.collectionStore:forget(player)
	end)

	for _, player in Players:GetPlayers() do
		self:onPlayerAdded(player)
	end

	--[[
		Robux 결제. 콜백은 **플레이스에 하나뿐**이고, 결제한 사람이 있는 서버에서 불린다.
		대전 서버(Arena)는 이걸 걸지 않는다 — 구매 버튼은 로비의 카드팩 화면에만 있고,
		혹시 대전 중에 처리 못 한 영수증이 있으면 Roblox 가 로비에 돌아온 뒤 다시 보낸다.

		pcall 로 감싼다. 콜백이 에러로 죽으면 Roblox 는 아무 답도 못 받은 것으로 치는데,
		그보다 "아직 못 했다" 고 분명히 답하는 쪽이 다시 보내줄 것이 확실하다.
	]]
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, decision = pcall(function()
			return self:processReceipt(receipt)
		end)
		if not ok then
			warn(("[TCG] 영수증 처리 실패: %s"):format(tostring(decision)))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end

	self.matchmaker:start()
	return self
end

--==========================================================================
-- 화면 상태
--==========================================================================

--[[
	화면 전환의 주인은 서버다. 클라이언트가 자기 판단으로 화면을 바꾸면
	"큐에 서 있는데 시작 화면이 보이는" 상태가 만들어진다.
]]
--[[
	클라이언트에게 나갈 모양으로 다듬는다.

	대기 화면은 기준 시각(since) 이 아니라 **경과 초(elapsed)** 를 보낸다.
	since 를 그대로 보내면 클라이언트가 `os.time() - since` 를 계산하게 되는데,
	기기 시계가 어긋난 사람은 0:00 에 멈추거나 처음부터 몇 분이 찍힌다.
	뺄셈은 시계가 하나뿐인 서버에서 한다.

	hello 로 다시 내려줄 때도 이 함수를 거치므로, 화면을 다시 받아도 타이머가
	0 으로 되돌아가지 않는다 — 그때그때 다시 계산되기 때문이다.
]]
function Lobby:outgoing(payload)
	if payload.screen ~= Screen.Queued or not payload.since then
		return payload
	end

	return {
		screen = payload.screen,
		elapsed = math.max(0, os.time() - payload.since),
	}
end

--[[
	이 사람이 이번 판에 쓸 덱(목록 모양). 저장이 없거나 못 읽으면 스타터 덱이다.
]]
function Lobby:deckFor(player)
	if not player then
		return Decks.starter()
	end

	--[[
		저장할 때 이미 "가진 카드로 짰나" 를 봤지만(saveDeck), 판을 열 때 한 번 더 본다.
		저장된 덱은 믿지 않는다는 DeckStore 의 태도와 같다. 걸리는 것은 컬렉션을 못 읽어
		스타터로 놀고 있는 사람 정도라, 그 사람은 스타터로 둔다.
	]]
	local entries = self.deckStore:get(player)
	local covered = Collection.covers(self:collectionFor(player), entries)
	if not covered then
		return Decks.starter()
	end
	return Decks.toList(entries)
end

-- 가진 카드. 컬렉션이 아직 없는 사람은 저장해둔 덱의 카드를 물려받는다(CollectionStore:get).
function Lobby:collectionFor(player)
	return self.collectionStore:get(player, self.deckStore:get(player))
end

-- 쓸 수 있는 골드. 번 것은 캠페인 진행도에, 쓴 것은 컬렉션에 있다(Collection 머리말).
function Lobby:goldFor(player)
	return Collection.balance(self.campaignStore:get(player), self:collectionFor(player))
end

function Lobby:setScreen(player, payload)
	self.screens[player] = payload
	self.remotes.Lobby:FireClient(player, self:outgoing(payload))
end

function Lobby:home(player, text)
	self:setScreen(player, { screen = Screen.Home, text = text })
end

--==========================================================================
-- 접속
--==========================================================================

--[[
	대전이 끝나고 "다시 매칭" 을 누른 사람은 로비로 돌아오면서 autoQueue 를 달고 온다.
	도착하자마자 큐에 넣어주지 않으면 버튼을 한 번 더 눌러야 한다.
]]
function Lobby:onPlayerAdded(player)
	self:home(player)

	local joinData = player:GetJoinData()
	local teleportData = joinData and joinData.TeleportData

	if type(teleportData) == "table" and teleportData.autoQueue then
		self:enqueue(player)
	end
end

--==========================================================================
-- 요청 처리
--==========================================================================

function Lobby:onMessage(player, payload)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end

	if payload.kind == "hello" then
		local current = self.screens[player] or { screen = Screen.Home }
		self.remotes.Lobby:FireClient(player, self:outgoing(current))
	elseif payload.kind == "queue" then
		self:enqueue(player)
	elseif payload.kind == "cancel" then
		self.matchmaker:cancel(player)
		self:home(player)
	elseif payload.kind == "home" then
		--[[
			시작 화면으로. hello 로는 안 된다 — hello 는 "지금 화면을 다시 달라" 라서
			덱 편집 화면이 그대로 다시 온다. 돌아가는 것은 별개의 요청이다.
		]]
		self.matchmaker:cancel(player)
		self:home(player)
	elseif payload.kind == "campaign" then
		self:openCampaign(player)
	elseif payload.kind == "campaignStart" then
		self:startCampaignStage(player, payload.index)
	elseif payload.kind == "deck" then
		self:openDeck(player)
	elseif payload.kind == "deckSave" then
		self:saveDeck(player, payload.entries)
	elseif payload.kind == "deckReset" then
		self:resetDeck(player)
	elseif payload.kind == "shop" then
		self:openShop(player)
	elseif payload.kind == "buyPack" then
		self:buyPack(player)
	elseif payload.kind == "tutorial" then
		self:startTutorial(player)
	elseif payload.kind == "practice" then
		self:startPractice(player)
	elseif payload.kind == "leave" then
		self:leaveMatch(player)
	elseif payload.kind == "requeue" then
		self:leaveMatch(player)
		self:enqueue(player)
	end
end

function Lobby:enqueue(player)
	-- 판을 두는 중에 큐에 서면 두 판이 겹친다.
	if self.host:runnerFor(player) then
		return
	end

	local ok, reason = self.matchmaker:enqueue(player)
	if not ok then
		self:setScreen(player, { screen = Screen.Error, text = reason or "큐에 등록하지 못했습니다" })
		return
	end

	self:setScreen(player, { screen = Screen.Queued, since = os.time() })
end

--==========================================================================
-- 덱 편집
--==========================================================================

--[[
	덱 편집 화면을 연다.

	판을 두는 중에는 열지 않는다 — 덱은 판이 시작될 때 정해지므로, 두는 중에 바꾸면
	"바꿨는데 안 바뀌는" 것처럼 보인다. 큐에 서 있을 때도 막는다(같은 이유).
]]
function Lobby:openDeck(player)
	if self.host:runnerFor(player) then
		return
	end
	self.matchmaker:cancel(player)

	self:setScreen(player, {
		screen = Screen.Deck,
		entries = self.deckStore:get(player),
		owned = Collection.owned(self:collectionFor(player)),
	})
end

function Lobby:saveDeck(player, entries)
	--[[
		가진 카드로 짰는지는 여기서 본다. DeckStore 는 덱 규칙(60장 · 4장 제한)만 안다 —
		저장소마다 서로를 알게 하면 하나를 고칠 때 셋을 같이 고치게 된다.
		화면도 가진 것보다 많이는 못 넣게 막지만(DeckEditor:add), 리모트는 손으로도 부른다.
	]]
	local ok, reason = Collection.covers(self:collectionFor(player), entries)
	if ok then
		ok, reason = self.deckStore:save(player, entries)
	end

	--[[
		실패해도 화면은 덱 편집 그대로 두고 이유만 알려준다. 시작 화면으로 되돌리면
		방금 편집한 것이 통째로 날아간 것처럼 보인다.

		저장에 실패해도 self.deckStore 의 캐시에는 들어가 있다(DeckStore 주석 참조).
		그래서 이 서버에 있는 동안은 그 덱으로 대전할 수 있다.
	]]
	self:setScreen(player, {
		screen = Screen.Deck,
		entries = self.deckStore:get(player),
		owned = Collection.owned(self:collectionFor(player)),
		saved = ok,
		text = ok and "저장했습니다" or tostring(reason or "저장하지 못했습니다"),
	})
end

function Lobby:resetDeck(player)
	-- 스타터 덱은 언제나 가진 카드로 짤 수 있다 (Collection.new 가 스타터 매수만큼 준다).
	local starter = Decks.starterEntries()
	local ok = self.deckStore:save(player, starter)

	self:setScreen(player, {
		screen = Screen.Deck,
		entries = self.deckStore:get(player),
		owned = Collection.owned(self:collectionFor(player)),
		saved = ok,
		text = ok and "스타터 덱으로 되돌렸습니다" or "되돌렸지만 저장하지 못했습니다",
	})
end

--==========================================================================
-- 튜토리얼
--==========================================================================

--[[
	튜토리얼 한 판. 코치(말풍선과 잠금)는 클라이언트가 하고, 여기서는 **판을 어떤
	조건으로 여는가** 만 정한다.

	연습과 다른 점 셋.
	  · 덱이 정해져 있다 — 저장된 덱으로 열면 무엇이 손에 올지 알 수 없어서
	    "이제 생물을 소환하세요" 를 말할 수 없다
	  · 상대 라이프가 낮다 — 30 을 정직하게 깎게 하면 배우는 데 열 턴이 더 든다
	  · 상대는 Easy — 즉시시전으로 대응하지 않는다. 스택은 튜토리얼 밖에서 배운다

	시드를 고정하는 이유는 재현이다. "튜토리얼 어디가 이상하다" 는 제보를 받으면
	같은 판을 그대로 다시 열 수 있다. 다시 하기를 누르면 새 시드로 섞이지만,
	코치는 턴 번호가 아니라 **판 상태**를 보므로 그래도 따라온다.
]]
local TUTORIAL_SEED = 20260909
local TUTORIAL_FOE_LIFE = 12

function Lobby:startTutorial(player)
	if self.host:runnerFor(player) then
		return
	end
	self.matchmaker:cancel(player)

	local runner = MatchRunner.new(self.remotes, {
		seats = {
			[1] = { player = player, deck = Decks.tutorial() },
			[2] = {
				ai = AI.Difficulty.Easy,
				name = "튜토리얼 상대",
				deck = Decks.tutorialFoe(),
				life = TUTORIAL_FOE_LIFE,
			},
		},
		seed = TUTORIAL_SEED,
		-- 배우는 사람이 선공. 처음 보는 화면이 "상대 차례" 면 아무것도 못 하고 기다린다.
		startingPlayerId = 1,
		allowRestart = true,
	})

	self.host:attach(runner)
	self:setScreen(player, { screen = Screen.Battle, mode = "tutorial" })
end

--==========================================================================
-- PvE 캠페인
--==========================================================================

--[[
	스테이지 목록을 연다.

	덱 편집과 같은 이유로 대전 중에는 열지 않는다 — 판이 열릴 때 덱과 상대가 정해지므로,
	두는 중에 목록을 띄우면 "다른 스테이지를 골랐는데 화면은 그대로" 가 된다.
]]
function Lobby:openCampaign(player, text)
	if self.host:runnerFor(player) then
		return
	end
	self.matchmaker:cancel(player)

	local progress = self.campaignStore:get(player)

	--[[
		목록 머리에 뜨는 골드는 **쓸 수 있는 골드**다. progress.gold 는 지금까지 번 합이라,
		팩을 산 사람에게 그대로 보여주면 상점과 숫자가 다르다.
	]]
	self:setScreen(player, {
		screen = Screen.Campaign,
		stages = Campaign.list(progress),
		gold = self:goldFor(player),
		text = text,
	})
end

--[[
	스테이지 한 판.

	**해금 판정은 서버가 한다.** 클라이언트가 보낸 번호를 그대로 믿으면 목록에서 잠긴
	칸을 못 누르게 해둔 것이 아무 의미가 없다 — 리모트는 손으로도 부를 수 있다.

	플레이어는 자기가 저장한 덱으로 둔다. 튜토리얼과 다른 점이다(튜토리얼은 가르칠 것을
	손에 쥐여줘야 해서 덱이 고정이다). 캠페인은 **덱을 고쳐 가며 뚫는 것**이 내용이라
	덱을 뺏으면 남는 게 없다.

	재시작(R)은 막았다. 스테이지에는 보상이 걸려 있어서, 판이 불리할 때 R 로 다시
	돌릴 수 있으면 사실상 무한 재시도가 된다. 다시 하려면 목록으로 나갔다 들어온다.
]]
function Lobby:startCampaignStage(player, index)
	if self.host:runnerFor(player) then
		return
	end

	local stage = Campaign.get(index)
	if not stage then
		self:openCampaign(player, "없는 스테이지입니다")
		return
	end

	local progress = self.campaignStore:get(player)
	if not Campaign.isUnlocked(progress, index) then
		self:openCampaign(player, "앞 스테이지를 먼저 깨야 합니다")
		return
	end

	self.matchmaker:cancel(player)
	self.campaignStage[player] = index

	local runner = MatchRunner.new(self.remotes, {
		seats = {
			[1] = { player = player, deck = self:deckFor(player) },
			[2] = {
				ai = stage.difficulty,
				name = stage.name,
				deck = Campaign.deckFor(index),
				life = stage.life,
			},
		},
		-- 도전하는 쪽이 선공. 후공으로 시작해 손도 못 써보고 지면 스테이지 탓을 못 한다.
		startingPlayerId = 1,
		onFinish = function(finished)
			self:onCampaignFinish(player, index, finished)
		end,
	})

	self.host:attach(runner)
	self:setScreen(player, { screen = Screen.Battle, mode = "campaign" })
end

--[[
	판이 끝났다. 이겼으면 진행도를 올리고 골드를 준다.

	화면은 전투 그대로 둔다 — 결과를 읽기도 전에 목록으로 튕기면 무슨 일이 있었는지
	모른 채 끝난다. 목록으로는 사람이 [나가기] 를 눌러 돌아가고, 그때 갱신된 진행도를
	받는다(leaveMatch 참조).

	저장에 실패하면 **그 사실을 그 자리에서 말한다.** 조용히 넘어가면 다음 접속에
	깬 스테이지가 사라져 있고, 그때는 원인을 짚을 단서가 없다.
]]
function Lobby:onCampaignFinish(player, index, runner)
	if runner.state.winnerId ~= 1 then
		return
	end

	local progress = self.campaignStore:get(player)
	local updated, gained = Campaign.applyClear(progress, index)

	if gained <= 0 then
		runner:noticeSeat(1, "이미 깬 스테이지입니다 — 골드는 처음 깼을 때만 받습니다", "info")
		return
	end

	local ok, reason = self.campaignStore:save(player, updated)
	if ok then
		runner:noticeSeat(1, ("스테이지 클리어 — 골드 %d 획득"):format(gained), "info")
	else
		runner:noticeSeat(1, ("클리어했지만 저장하지 못했습니다: %s"):format(tostring(reason)), "error")
	end
end

--==========================================================================
-- 카드팩
--==========================================================================

--[[
	상점 화면을 연다. pulls 가 있으면 방금 깐 팩의 결과다.

	덱 편집과 같은 이유로 대전 중에는 열지 않는다.

	내려보내는 것은 숫자뿐이다 — 잔액·가격·장수·모은 정도. 살 수 있는지는 화면이
	잔액과 가격을 비교해 버튼을 켜고 끄지만, 판정은 buyPack 이 다시 한다.
]]
function Lobby:openShop(player, pulls, text, failed)
	if self.host:runnerFor(player) then
		return
	end
	self.matchmaker:cancel(player)

	local collection = self:collectionFor(player)
	local have, total = Collection.progress(collection)

	self:setScreen(player, {
		screen = Screen.Shop,
		gold = self:goldFor(player),
		price = Collection.Pack.price,
		size = Collection.Pack.size,
		rares = Collection.Pack.rares,
		collected = have,
		total = total,
		pulls = pulls,
		text = text,
		failed = failed == true,
		-- 0 이면 화면이 Robux 버튼을 숨긴다 (Products 주석)
		robuxProductId = Products.robuxPack,
	})
end

--[[
	Robux 영수증 하나를 처리한다. -> Enum.ProductPurchaseDecision

	답은 둘뿐이다.
	  PurchaseGranted   줬다(또는 이미 줬다). Roblox 는 이 영수증을 다시 안 보낸다
	  NotProcessedYet   아직 못 줬다. Roblox 가 나중에(다음 접속 등) 다시 보낸다

	**저장에 성공한 뒤에만 Granted 라고 답한다.** 먼저 답하고 저장이 실패하면 돈은 나갔는데
	카드는 없다 — 되돌릴 방법이 없다. 반대로 저장은 됐는데 답이 안 가면 같은 영수증이 또
	오지만, 그건 영수증 기록(Collection.grantPack)이 걸러준다.

	이미 처리한 영수증이면 아무것도 안 주고 Granted 라고 답한다 — NotProcessedYet 으로 답하면
	Roblox 가 영원히 다시 보낸다.
]]
function Lobby:processReceipt(receipt)
	local NotYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local Granted = Enum.ProductPurchaseDecision.PurchaseGranted

	-- 우리가 모르는 상품. 상품을 늘리면 여기에 갈래가 생긴다.
	if receipt.ProductId ~= Products.robuxPack then
		return NotYet
	end

	-- 결제한 사람이 이 서버에 없다(그 사이에 나갔다). 저장소를 직접 고칠 수도 있지만,
	-- 그러면 그 사람이 지금 있는 서버의 캐시와 어긋난다. 다음 접속 때 다시 온다.
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return NotYet
	end

	local purchaseId = tostring(receipt.PurchaseId)
	local collection = self:collectionFor(player)

	if Collection.hasReceipt(collection, purchaseId) then
		return Granted
	end

	local rng = Rules.RNG.new(Random.new():NextInteger(1, 2147483646))
	local updated, results = Collection.grantPack(collection, purchaseId, rng)
	if not updated then
		warn(("[TCG] Robux 팩을 만들지 못했습니다 (%s): %s"):format(player.Name, tostring(results)))
		return NotYet
	end

	local ok, reason = self.collectionStore:save(player, updated)
	if not ok then
		warn(("[TCG] Robux 팩을 저장하지 못했습니다 — 다시 받을 때 처리합니다 (%s): %s"):format(
			player.Name,
			tostring(reason)
		))
		return NotYet
	end

	-- 카드팩 화면에 있으면 바로 펼쳐 보여준다. 다른 화면이면 카드는 이미 컬렉션에 있다.
	local current = self.screens[player]
	if current and current.screen == Screen.Shop then
		self:openShop(player, results, "Robux 팩을 열었습니다", false)
	end

	return Granted
end

--[[
	팩 한 봉을 산다.

	난수 시드는 이 서버가 뽑는다. 클라이언트가 보낸 값이나 클라이언트가 볼 수 있는 값에서
	유도하면 무엇이 나올지 미리 계산할 수 있다 (Arena 가 매치 시드를 직접 뽑는 것과 같은 이유).

	**저장에 성공해야 결과를 보여준다.** 저장이 실패하면 CollectionStore 가 캐시를 되돌리고,
	화면에는 카드 대신 "못 샀다" 가 뜬다. 카드를 보여줬는데 다음 접속에 없으면 그게 더 나쁘다.
]]
function Lobby:buyPack(player)
	if self.host:runnerFor(player) then
		return
	end

	local progress = self.campaignStore:get(player)
	local collection = self:collectionFor(player)
	local rng = Rules.RNG.new(Random.new():NextInteger(1, 2147483646))

	local updated, results = Collection.buyPack(progress, collection, rng)
	if not updated then
		self:openShop(player, nil, tostring(results), true)
		return
	end

	local ok, reason = self.collectionStore:save(player, updated)
	if not ok then
		self:openShop(player, nil, ("팩을 열지 못했습니다: %s"):format(tostring(reason)), true)
		return
	end

	local refund = 0
	for _, pull in results do
		refund += pull.refund
	end

	local text = refund > 0 and ("팩을 열었습니다 — 중복 카드는 골드 %d 로 돌려받았습니다"):format(refund)
		or "팩을 열었습니다"
	self:openShop(player, results, text, false)
end

--==========================================================================
-- AI 연습
--==========================================================================

function Lobby:startPractice(player)
	if self.host:runnerFor(player) then
		return
	end
	self.matchmaker:cancel(player)

	local runner = MatchRunner.new(self.remotes, {
		seats = {
			[1] = { player = player, deck = self:deckFor(player) },
			[2] = { ai = AI.Difficulty.Normal, name = "훈련용 AI" },
		},
		allowRestart = true, -- 연습이니까 R 로 계속 새 판을 열 수 있다
	})

	self.host:attach(runner)
	self:setScreen(player, { screen = Screen.Battle, mode = "practice" })
end

--==========================================================================
-- 같은 서버 매칭 (Studio 전용 경로)
--==========================================================================

function Lobby:startLocalMatch(match, players)
	local seats = {}
	for seat = 1, 2 do
		seats[seat] = { player = players[seat], deck = self:deckFor(players[seat]) }
	end

	local runner = MatchRunner.new(self.remotes, {
		seats = seats,
		seed = match.seed,
		startingPlayerId = match.startingPlayerId,
		-- 게시된 게임의 Arena 와 같은 보상. 판이 열리는 곳만 다르다.
		onFinish = function(finished)
			PvpReward.pay(self.campaignStore, finished)
		end,
	})

	self.host:attach(runner)

	for _, player in players do
		self:setScreen(player, { screen = Screen.Battle, mode = "pvp" })
	end
end

--==========================================================================
-- 대전에서 나오기
--==========================================================================

function Lobby:leaveMatch(player)
	-- 진행 중인 판을 두고 나가면 항복과 같다. 끝난 판이면 아무 일도 일어나지 않는다.
	self.host:release(player)

	--[[
		캠페인에서 나온 사람은 시작 화면이 아니라 **목록으로** 돌려보낸다. 방금 깬 칸에
		체크가 붙고 골드가 늘어난 것이 보여야 한 판이 끝난 것으로 읽힌다. 시작 화면으로
		보내면 다음 스테이지를 고르기까지 두 번을 더 눌러야 한다.
	]]
	if self.campaignStage[player] then
		self.campaignStage[player] = nil
		self:openCampaign(player)
		return
	end

	self:home(player)
end

return Lobby
