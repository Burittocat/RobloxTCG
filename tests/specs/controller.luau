--[[
	클릭 → 판정 (src/client/Controller.luau).

	여기서 잡고 싶은 사고는 하나다: **화면에 켜졌는데 고를 게 없는 것.**
	룰이 거부하는 선택을 초록 테두리로 권하면, 눌러 들어간 사람은 이유도 못 듣고
	"선택 취소" 로만 빠져나온다. 룰 자체는 tests/specs/keywords.luau 가 본다 —
	여기서는 클라이언트가 그 룰을 **보고 있는지**를 본다.

	Controller 는 서버가 보낸 스냅샷(Net.packView)만 먹으므로, 화면 없이 돌릴 수 있다.
	tests/run.luau 가 src/client 를 src/shared 와 같은 캐시로 마운트해준다.
]]

return function(t, ctx)
	local Rules, Net, Controller, Fixture = ctx.Rules, ctx.Net, ctx.Controller, ctx.Fixture
	local Field = Rules.Enums.Zone.Field

	--==================================================================
	-- 화면과 리모트 흉내 (Controller 가 생성자에서 요구하는 것만)
	--==================================================================

	local function fakeSignal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end

	local function fakeBattle()
		local battle = { callbacks = {}, toasts = {}, renders = 0 }

		function battle:showToast(text, kind)
			table.insert(self.toasts, { text = text, kind = kind })
		end

		function battle:render()
			self.renders += 1
		end

		return battle
	end

	--[[
		그 좌석의 사람이 실제로 받는 것과 **같은 스냅샷**을 태운다.
		서버가 보내는 경로(viewFor → packView)와 클라이언트가 푸는 경로(unpackView)를
		그대로 지나므로, 전송 과정에서 모양이 바뀌면 여기서도 드러난다.
	]]
	local function controllerFor(state, playerId)
		local battle = fakeBattle()
		local sent = {}
		local remotes = {
			Sync = { OnClientEvent = fakeSignal() },
			Notice = { OnClientEvent = fakeSignal() },
			Action = {
				FireServer = function(_, payload)
					table.insert(sent, payload)
				end,
			},
		}

		local controller = Controller.new(battle, remotes)
		controller:onSync(Net.packView(Rules.viewFor(state, playerId)))

		return controller, battle, sent
	end

	--[[
		1번이 비행 생물로 공격을 선언하고 수비준비까지 넘긴 판.
		2번 필드에는 지상 생물(방어 불가)과 원거리 생물(방어 가능)이 있다.
	]]
	local function flyingAttack()
		local state = Fixture.match(Rules)
		Rules.endPhase(state, 1) -- → 공격준비

		local hawk = Fixture.spawn(Rules, state, 1, "CRE_HAWK", Field)
		local guard = Fixture.spawn(Rules, state, 2, "CRE_GUARD", Field)
		local archer = Fixture.spawn(Rules, state, 2, "CRE_ARCHER", Field)

		Rules.declareAttacker(state, 1, hawk.id)
		Rules.endPhase(state, 1) -- → 수비준비

		return state, hawk, guard, archer
	end

	--==================================================================
	t:describe("수비준비 하이라이트", function()
		t:it("비행 공격자만 있으면 지상 생물은 켜지지 않는다", function()
			local state, _, guard = flyingAttack()
			local controller = controllerFor(state, 2)

			t:falsy(
				controller:highlights().creature[guard.id],
				"막을 수 없는 생물을 권하면 눌러 들어가서 '선택 취소' 로만 나온다"
			)
		end)

		t:it("원거리 생물은 켜진다", function()
			local state, _, _, archer = flyingAttack()
			local controller = controllerFor(state, 2)

			t:truthy(controller:highlights().creature[archer.id], "원거리는 비행을 막을 수 있습니다")
		end)

		t:it("켜지지 않은 생물을 눌러도 방어 모드로 들어가지 않는다", function()
			local state, _, guard = flyingAttack()
			local controller, battle, sent = controllerFor(state, 2)

			controller:onFieldCard(guard.id)

			t:eq(controller.mode.name, "idle", "고를 게 없는 모드에 들어가면 안 됩니다")
			t:eq(#sent, 0, "서버가 거부할 요청을 만들지 않습니다")
			t:truthy(#battle.toasts > 0, "왜 안 되는지는 말해줘야 합니다")
			t:truthy(
				tostring(battle.toasts[1].text):find("비행"),
				("이유가 안 담겼습니다: %s"):format(tostring(battle.toasts[1].text))
			)
		end)

		t:it("이미 방어를 배정한 생물은 다시 켜지지 않는다", function()
			local state, hawk, _, archer = flyingAttack()

			t:allowed(Rules.declareBlocker(state, 2, archer.id, hawk.id))
			local controller = controllerFor(state, 2)

			t:falsy(controller:highlights().creature[archer.id])
		end)

		t:it("탭된 생물은 켜지지 않는다", function()
			local state, _, _, archer = flyingAttack()
			state.cards[archer.id].tapped = true

			local controller = controllerFor(state, 2)
			t:falsy(controller:highlights().creature[archer.id])
		end)

		t:it("공격자를 고르는 중에는 막을 수 있는 공격자만 켜진다", function()
			local state = Fixture.match(Rules)
			Rules.endPhase(state, 1)

			local hawk = Fixture.spawn(Rules, state, 1, "CRE_HAWK", Field)
			local brute = Fixture.spawn(Rules, state, 1, "CRE_BRUTE", Field)
			local guard = Fixture.spawn(Rules, state, 2, "CRE_GUARD", Field)

			Rules.declareAttacker(state, 1, hawk.id)
			Rules.declareAttacker(state, 1, brute.id)
			Rules.endPhase(state, 1)

			local controller = controllerFor(state, 2)
			controller:onFieldCard(guard.id) -- 지상 생물 → 지상 공격자만 막을 수 있다

			t:eq(controller.mode.name, "block", "막을 상대가 있으니 방어 모드로 들어가야 합니다")

			local highlights = controller:highlights()
			t:truthy(highlights.creature[brute.id], "지상 공격자는 막을 수 있습니다")
			t:falsy(highlights.creature[hawk.id], "비행 공격자는 못 막습니다")
		end)
	end)

	--==================================================================
	t:describe("공격준비 하이라이트", function()
		t:it("소환 멀미 중인 생물은 켜지지 않는다", function()
			local state = Fixture.match(Rules)
			Rules.endPhase(state, 1) -- → 공격준비

			local ready = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)
			local sick = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field, true)

			local controller = controllerFor(state, 1)
			local highlights = controller:highlights()

			t:truthy(highlights.creature[ready.id], "지난 턴에 나온 생물은 공격할 수 있습니다")
			t:falsy(highlights.creature[sick.id], "이번 턴에 나온 생물은 못 합니다")
		end)

		t:it("상대 턴에는 내 생물이 켜지지 않는다", function()
			local state = Fixture.match(Rules)
			Rules.endPhase(state, 1)
			local guard = Fixture.spawn(Rules, state, 1, "CRE_GUARD", Field)

			-- 같은 판을 상대(2번) 눈으로 본다.
			local controller = controllerFor(state, 2)
			t:falsy(controller:highlights().creature[guard.id])
		end)
	end)
end
