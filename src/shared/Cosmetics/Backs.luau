--[[
	카드 뒷면 목록 (★ 가격은 기획서 미확정 — docs/open-questions.md)

	Frames.luau 와 같은 순수 테이블이다 — 스모크 테스트가 Lune 에서 그대로 읽는다.
	규칙은 옆의 init.luau 에 있다.

	뒷면은 **상대가 내 손패를 볼 때** 보인다(상대 화면의 내 패널). 진짜 TCG 슬리브와 같다 —
	내 화면에서는 내 손패가 앞면이라 안 보이고, 꾸미기 화면의 미리보기로 본다.

	카드 앞면 바탕은 건드리지 않는다. 앞면 색은 "생물 · 마법 · 코스트" 를 가르는 정보라
	(Theme.color.creature 등) 그걸 꾸밈이 덮으면 판을 읽기 어려워진다.

	  base     뒷면 바탕색 (0~255)
	  accent   테두리와 무늬 색
	  mark     가운데 무늬 한 글자. 빈 문자열이면 무늬 없음.
	           Gotham 이 확실히 그리는 기본 도형만 쓴다(◆ ★ ▲ ●) — 특수 기호는
	           글꼴에 없으면 네모 칸으로 나온다
	  fade     테두리 투명도. 기본 뒷면은 예전과 같은 0.3, 꾸민 뒷면은 또렷하게 0

	기본 뒷면은 예전 뒷면과 똑같은 값이다(Theme.color.panelSoft · stroke).
]]

return table.freeze({
	default = "BACK_BASIC",

	list = table.freeze({
		table.freeze({
			id = "BACK_BASIC",
			name = "기본",
			price = 0,
			base = { 46, 54, 74 },
			accent = { 74, 85, 112 },
			mark = "",
			fade = 0.3,
		}),
		table.freeze({
			id = "BACK_NIGHT",
			name = "밤하늘",
			price = 120,
			base = { 24, 30, 66 },
			accent = { 156, 176, 244 },
			mark = "●",
			fade = 0,
		}),
		table.freeze({
			id = "BACK_EMBER",
			name = "불씨",
			price = 120,
			base = { 78, 32, 26 },
			accent = { 244, 146, 84 },
			mark = "◆",
			fade = 0,
		}),
		table.freeze({
			id = "BACK_GROVE",
			name = "숲",
			price = 120,
			base = { 28, 60, 42 },
			accent = { 136, 206, 124 },
			mark = "▲",
			fade = 0,
		}),
		table.freeze({
			id = "BACK_ROYAL",
			name = "왕실",
			price = 200,
			base = { 60, 28, 76 },
			accent = { 236, 200, 116 },
			mark = "★",
			fade = 0,
		}),
	}),
})
