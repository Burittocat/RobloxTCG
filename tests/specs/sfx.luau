--[[ 효과음 (src/client/UI/Sfx.luau) ]]

return function(t, ctx)
	local Sfx = ctx.Sfx
	local Instance = ctx.Instance
	local takeSounds = ctx.takeSounds

	--[[
		울림 하나를 잠깐 켜고 원래대로 돌려놓는다. 표를 직접 고치면 그 다음 테스트가
		남은 값을 물려받아, 혼자서는 통과하는데 같이 돌리면 깨지는 것이 생긴다.
	]]
	local function withCue(name, id, fn)
		local cue = Sfx.cue[name]
		local before = cue.id
		cue.id = id
		local ok, err = pcall(fn)
		cue.id = before
		if not ok then
			error(err, 0)
		end
	end

	local function freshFolder()
		takeSounds()
		Sfx.muted = false
		return Sfx.attach(Instance.new("Folder"))
	end

	t:describe("효과음", function()
		--[[
			**에셋을 안 올린 상태가 정상이다.** 로블록스는 업로드된 rbxassetid 가
			있어야 소리를 내므로, 비어 있는 동안에도 게임은 멀쩡히 돌아야 한다.
		]]
		t:it("ID 가 비어 있으면 아무 일도 하지 않는다", function()
			freshFolder()

			Sfx.play("click")
			Sfx.play("strike")

			t:eq(#takeSounds(), 0, "에셋이 없는데 소리가 난 것으로 셌습니다")
		end)

		t:it("ID 를 넣으면 그 울림이 난다", function()
			freshFolder()

			withCue("turn", "rbxassetid://1234", function()
				Sfx.play("turn")
			end)

			local sounds = takeSounds()
			t:eq(#sounds, 1, "한 번 울려야 합니다")
			t:eq(sounds[1].id, "rbxassetid://1234", "넣은 에셋이 울려야 합니다")
			t:eq(sounds[1].name, "Sfx_turn", "어느 울림인지 이름에 남아야 합니다")
		end)

		t:it("같은 울림을 두 번 내면 두 번 난다", function()
			local folder = freshFolder()

			withCue("strike", "rbxassetid://7", function()
				Sfx.play("strike")
				Sfx.play("strike")
			end)

			t:eq(#takeSounds(), 2, "연달아 때리면 연달아 울려야 합니다")

			-- 소리마다 Sound 를 새로 만들면 판이 길어질수록 인스턴스가 쌓인다.
			t:eq(#folder:GetChildren(), 1, "같은 울림은 Sound 하나를 돌려 써야 합니다")
		end)

		t:it("꺼 두면 나지 않는다", function()
			freshFolder()

			withCue("win", "rbxassetid://9", function()
				Sfx.muted = true
				Sfx.play("win")
				Sfx.muted = false
			end)

			t:eq(#takeSounds(), 0, "음소거인데 울렸습니다")
		end)

		--[[
			이름을 잘못 적으면 조용히 무음이 된다 — 그게 제일 찾기 어렵다.
			없는 이름은 그 자리에서 드러나야 한다.
		]]
		t:it("없는 울림 이름은 에러다", function()
			freshFolder()

			local ok = pcall(function()
				Sfx.play("없는소리")
			end)

			t:falsy(ok, "없는 이름인데 그냥 넘어갔습니다")
		end)

		--[[
			부모 없는 Sound 는 로블록스에서 울리지 않는다. 화면을 짓기 전에 울리는
			코드가 생기면, 여기서 조용히 사라지는 것이 정상이다.
		]]
		t:it("붙일 자리가 없으면 울리지 않는다", function()
			takeSounds()
			Sfx.attach(nil)

			withCue("death", "rbxassetid://5", function()
				Sfx.play("death")
			end)

			t:eq(#takeSounds(), 0, "자리도 없는데 울렸습니다")
		end)
	end)

	--[[
		언제 우는가. 화면은 갱신마다 다시 그리므로, 같은 상태를 다시 그렸다고
		또 울면 소리가 끊이지 않는다. 울려야 하는 것은 **넘어온 순간**뿐이다.
	]]
	t:describe("울릴 순간", function()
		local function cues(before, after)
			return Sfx.transitionCues(before, after)
		end

		local IDLE = { myMove = false, stackOpen = false, finished = false }

		t:it("내 차례로 넘어오면 운다", function()
			local out = cues(IDLE, { myMove = true, stackOpen = false, finished = false })
			t:eq(#out, 1, "한 번 울려야 합니다")
			t:eq(out[1], "turn", "턴 소리여야 합니다")
		end)

		t:it("내 차례가 이어지는 동안에는 다시 울지 않는다", function()
			local before = { myMove = true, stackOpen = false, finished = false }
			local out = cues(before, { myMove = true, stackOpen = false, finished = false })
			t:eq(#out, 0, ("같은 상태를 다시 그렸는데 울렸습니다 — %s"):format(table.concat(out, ", ")))
		end)

		t:it("스택이 열리는 순간에 운다", function()
			local out = cues(IDLE, { myMove = false, stackOpen = true, finished = false })
			t:eq(#out, 1, "한 번 울려야 합니다")
			t:eq(out[1], "stack", "대응 창 소리여야 합니다")
		end)

		t:it("스택이 쌓여 있는 동안에는 다시 울지 않는다", function()
			local before = { myMove = false, stackOpen = true, finished = false }
			local out = cues(before, { myMove = false, stackOpen = true, finished = false })
			t:eq(#out, 0, "스택이 그대로인데 울렸습니다")
		end)

		t:it("이기면 이긴 소리, 지면 진 소리", function()
			local won = cues(IDLE, { myMove = false, stackOpen = false, finished = true, won = true })
			t:eq(won[1], "win", "이겼는데 다른 소리가 납니다")

			local lost = cues(IDLE, { myMove = false, stackOpen = false, finished = true, won = false })
			t:eq(lost[1], "lose", "졌는데 다른 소리가 납니다")
		end)

		--[[
			판이 끝나는 순간은 내 차례로 돌아오면서 끝나기도 한다. 그때 턴 소리가
			같이 나면 둘 다 뭉개져서, 이긴 건지 진 건지가 안 들린다.
		]]
		t:it("끝나는 순간에는 승패만 운다", function()
			local out = cues(IDLE, { myMove = true, stackOpen = true, finished = true, won = true })
			t:eq(#out, 1, ("승패만 울려야 합니다 — %s"):format(table.concat(out, ", ")))
			t:eq(out[1], "win", "승패 소리여야 합니다")
		end)

		t:it("끝난 뒤 화면을 다시 그려도 울지 않는다", function()
			local before = { myMove = false, stackOpen = false, finished = true }
			local out = cues(before, { myMove = false, stackOpen = false, finished = true, won = true })
			t:eq(#out, 0, "끝난 판을 다시 그렸는데 울렸습니다")
		end)
	end)
end
