--[[
	효과음 한 곳.

	**에셋 ID 는 비어 있다.** 로블록스는 소리도 파일이나 URL 로 못 읽는다 — 업로드돼
	모더레이션을 통과한 `rbxassetid://` 가 있어야 난다(`Theme.image.gold` 와 같은 사정).
	비어 있으면 **아무 일도 하지 않는다.** 소리가 없다고 판이 멈추면, 에셋을 붙이기
	전까지 게임을 못 하게 되기 때문이다.

	ID 넣는 법:
	  · Studio → 보기 → 도구상자 → 오디오에서 무료 음원을 찾아 ID 를 복사
	    (로블록스가 올린 공식 음원은 누구나 쓸 수 있다. 남이 올린 것은 소유자만 쓸 수
	     있게 막혀 있는 경우가 많으니, 넣고 Studio 에서 한 번 들어봐야 한다)
	  · 직접 만든 소리는 크리에이터 대시보드 → 오디오로 업로드
	  · `"rbxassetid://123456"` 형태로 아래 표에 붙여넣는다

	여기 이름은 **무엇이 일어났는가**로 짓는다("버튼2" 가 아니라 `deny`). 소리를
	바꾸는 일은 잦지만 "무슨 일이 일어났는가" 는 잘 안 바뀌기 때문이다.
]]

local Sfx = {}

--[[
	울림 목록. volume 은 0~1.

	세기를 나눠 둔 이유: 자주 나는 소리(click)가 드물게 나는 소리(win)와 같은 크기면
	귀가 금방 지친다. 자주 날수록 작게.
]]
Sfx.cue = {
	click = { id = "", volume = 0.3 }, -- 행동 바 버튼
	deny = { id = "", volume = 0.4 }, -- 거부당했을 때 (빨간 토스트)
	turn = { id = "", volume = 0.45 }, -- 내 차례가 왔다
	stack = { id = "", volume = 0.45 }, -- 상대가 카드를 냈다 (대응 창)
	strike = { id = "", volume = 0.55 }, -- 카드가 부딪히는 순간
	death = { id = "", volume = 0.5 }, -- 생물이 쓰러진다
	win = { id = "", volume = 0.6 },
	lose = { id = "", volume = 0.6 },
}

--[[
	소리를 끈 상태. 설정 화면이 생기면 여기에 붙인다.
	(지금은 코드에서만 끌 수 있다 — 테스트가 쓴다)
]]
Sfx.muted = false

local folder = nil
local pool = {}

--[[
	소리가 붙어 살 자리를 만든다. 부모 없는 Sound 는 로블록스에서 울리지 않는다.

	전투 화면을 다시 지으면(판을 새로 열면) 예전 폴더는 화면과 함께 사라지므로
	풀도 같이 버린다 — 안 버리면 죽은 인스턴스에 Play 를 걸게 된다.
]]
function Sfx.attach(parent)
	-- 자리를 없애는 쪽으로도 쓴다(테스트). 부모 없는 폴더에 매달아 두면 진짜
	-- 로블록스에서는 울리지 않으면서 여기서만 우는 코드가 된다.
	if not parent then
		folder = nil
		pool = {}
		return nil
	end

	folder = Instance.new("Folder")
	folder.Name = "Sfx"
	folder.Parent = parent
	pool = {}
	return folder
end

local function soundFor(name)
	local cue = Sfx.cue[name]

	-- 오타는 조용히 무음이 되면 안 된다. 없는 이름은 그 자리에서 드러낸다.
	if not cue then
		error(("Sfx.play: '%s' 는 없는 울림입니다"):format(tostring(name)), 3)
	end

	if cue.id == "" or not folder then
		return nil
	end

	local sound = pool[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "Sfx_" .. name
		sound.SoundId = cue.id
		sound.Volume = cue.volume or 0.5
		sound.Parent = folder
		pool[name] = sound
	end
	return sound
end

--[[
	한 번 울린다. 같은 울림이 겹치면 처음부터 다시 난다 — 연달아 때릴 때
	소리가 하나로 뭉치지 않게.
]]
function Sfx.play(name)
	if Sfx.muted then
		return
	end

	local sound = soundFor(name)
	if not sound then
		return
	end

	sound.TimePosition = 0
	sound:Play()
end

--[[
	**언제 우는가** 를 정하는 순수 계산.

	화면은 갱신마다 통째로 다시 그린다. 그래서 "지금 내 차례다" 같은 상태를 볼 때마다
	울리면 같은 소리가 끝없이 난다 — 울려야 하는 것은 상태가 아니라 **넘어온 순간**이다.

	화면도 Instance 도 안 건드리므로 룰 러너에서 그대로 테스트할 수 있다.
	(때리는 시간표 CombatTiming 과 같은 이유로 떼어냈다)

	  before / after = { myMove, stackOpen, finished, won }
]]
function Sfx.transitionCues(before, after)
	local out = {}

	-- 판이 끝나는 순간은 승패만 울린다. 거기 턴 소리가 겹치면 둘 다 안 들린다.
	if after.finished then
		if not before.finished then
			table.insert(out, after.won and "win" or "lose")
		end
		return out
	end

	if after.myMove and not before.myMove then
		table.insert(out, "turn")
	end

	if after.stackOpen and not before.stackOpen then
		table.insert(out, "stack")
	end

	return out
end

return Sfx
