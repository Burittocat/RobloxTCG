--[[
	화면 전체가 참조하는 색/치수/글자 크기 한 곳.

	여기 숫자만 바꾸면 전체 톤이 바뀐다. 카드 아트가 아직 없으므로
	"카드 종류 = 색" 이 유일한 시각적 구분이다 — 그래서 색을 상수로 묶어뒀다.

	--------------------------------------------------------------------------
	가시성 기준

	글자 크기는 개별 위젯에서 정하지 않고 아래 Theme.text 척도에서 고른다.
	그러지 않으면 "여기만 10, 저기만 11" 이 쌓여서 전체를 키울 방법이 없어진다.

	가장 작은 글자를 12 로 잡았다. 로블록스는 창 크기가 제각각이고 텔레비전으로도
	보는데, 10~11 은 그 조건에서 읽으라고 두기 어렵다.

	흐린 글자(textDim / textFaint)는 어두운 배경 위에서 대비를 재서 정했다.
	특히 textFaint 는 카드 위의 "탭됨" · "공격 불가" 처럼 **놓치면 오조작으로 이어지는**
	정보에 쓰이므로, 장식용으로 흐리게 두면 안 된다.
]]

local Theme = {}

Theme.color = {
	-- 바탕. 카드와 패널이 떠 보이도록 가장 어둡게 둔다.
	bg = Color3.fromRGB(18, 21, 31),
	bgDeep = Color3.fromRGB(10, 12, 18),

	-- 패널은 바탕보다 확실히 밝아야 경계가 보인다.
	panel = Color3.fromRGB(33, 39, 55),
	panelSoft = Color3.fromRGB(46, 54, 74),
	stroke = Color3.fromRGB(74, 85, 112),

	text = Color3.fromRGB(240, 244, 252),
	textDim = Color3.fromRGB(180, 189, 208),
	textFaint = Color3.fromRGB(146, 156, 178),

	me = Color3.fromRGB(94, 214, 155),
	foe = Color3.fromRGB(242, 112, 108),
	accent = Color3.fromRGB(247, 206, 112),
	stack = Color3.fromRGB(190, 144, 242),
	ok = Color3.fromRGB(94, 214, 155),
	warn = Color3.fromRGB(242, 112, 108),

	-- 카드 종류
	cost = Color3.fromRGB(78, 132, 100),
	creature = Color3.fromRGB(72, 106, 162),
	spell = Color3.fromRGB(128, 86, 162),
}

-- 키워드 칩 색. 룰 로직은 절대 색을 보지 않는다 — 표기 전용.
-- 어두운 칩 배경 위에 얹히므로 전부 밝은 쪽으로 잡았다.
Theme.keywordColor = {
	Haste = Color3.fromRGB(246, 182, 96),
	Flying = Color3.fromRGB(126, 198, 244),
	Taunt = Color3.fromRGB(224, 140, 112),
	Ranged = Color3.fromRGB(158, 212, 138),
	Instant = Color3.fromRGB(200, 156, 244),
}

Theme.font = {
	regular = Enum.Font.GothamMedium,
	bold = Enum.Font.GothamBold,
}

--[[
	글자 크기 척도. 위젯은 여기서만 고른다.

	  tiny   키워드 칩처럼 한두 글자짜리 표식
	  small  부가 정보 (카드 설명 · 상태 · 로그)
	  body   본문 기본값
	  label  버튼 · 이름처럼 눈이 먼저 가야 하는 것
	  stat   카드의 공격력/체력
	  title  화면 제목
	  life   라이프 — 판에서 가장 자주 보는 숫자
]]
Theme.text = {
	tiny = 12,
	small = 13,
	body = 14,
	label = 16,
	stat = 22,
	title = 20,
	life = 34,
	banner = 22,
}

--[[
	치수는 **일부러 안 키웠다.**

	레이아웃이 고정이라 세로 예산이 빠듯하다 — 카드를 10px 키우면 위아래로 20,
	보드 절반마다 그만큼이라 768px 창에서 가운데 영역이 음수가 된다.
	대신 아래 uiScale 이 창 크기에 맞춰 화면 전체를 늘리고 줄인다.
	그래서 큰 모니터에서는 이 숫자들보다 실제로 크게 보인다.
]]
Theme.size = {
	handCard = Vector2.new(116, 170),
	fieldCard = Vector2.new(96, 124),
	costChip = Vector2.new(34, 46),
	topBar = 46,
	handBar = 192,
	actionBar = 172,
	playerPanel = 92,
	fieldRow = 132,
}

--[[
	화면 전체 배율.

	위 치수는 세로 900px 창을 기준으로 잡혀 있다. 1440p·4K 모니터에서 그대로 두면
	글자가 손톱만 해지고, 768px 창에서는 보드가 잘린다. 뷰포트 높이에 비례해
	전체를 늘렸다 줄인다 — 카드 한 장의 정보량은 그대로 두고 "크게 보이게" 만 한다.

	상한을 1.5 로 둔 이유: 그 이상 키우면 손패가 화면 밖으로 밀린다.
	하한 0.8 은 그 아래로 줄이면 글자가 다시 안 읽히는 지점이다.
]]
Theme.uiScale = {
	referenceHeight = 900,
	min = 0.8,
	max = 1.5,
}

--[[
	하이라이트 두께. 카드가 나란히 붙어 있으면 얇은 테두리는 서로 묻힌다.
	"누를 수 있는 것" 은 한눈에 세어질 만큼 굵어야 한다.
]]
Theme.outline = {
	idle = 1,
	selected = 4,
	highlighted = 4,
}

Theme.tween = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

return Theme
