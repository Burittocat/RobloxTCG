--[[
	카드 테두리 목록 (★ 가격은 기획서 미확정 — docs/open-questions.md)

	아무것도 require 하지 않는 순수 테이블이다. Products 와 같은 이유로 — 스모크 테스트가
	Lune 에서 그대로 require 해서 "화면에 이 색이 칠해졌나" 를 이 값과 맞춰 본다.
	규칙(사기 · 끼기)은 옆의 init.luau 에 있다.

	  color      테두리 색 (0~255). Color3 가 아니라 숫자 셋이다 — Roblox 자료형을 쓰면
	             Lune 에서 못 읽는다. 화면이 Color3 로 바꾼다(CardView.frameStyle)
	  thickness  테두리 두께(px). **4 미만이어야 한다.** 선택·대상 하이라이트가 4 라서,
	             테두리가 그만큼 두꺼우면 "누를 수 있는 카드" 와 구별이 안 된다
	             (Theme.outline · tests/specs/cosmetics.luau 가 본다)
	  grade      등급 (Grades.luau 의 id). 일반 · 희귀 · 레어 · 에픽 · 고져스
	  price      골드. **등급의 가격과 같아야 한다**(테스트가 본다). 0 이면 처음부터 가진다

	기본 테두리는 예전 카드 테두리와 똑같은 값이다(Theme.color.stroke, 두께 1).
	색은 하이라이트 색(초록 ok · 금색 accent)과 겹치지 않게 골랐다 — 같은 이유다.
	순서는 화면에 보이는 순서다.
]]

return table.freeze({
	default = "FRAME_BASIC",

	-- grade 는 Grades.luau 의 id. price 는 그 등급의 가격과 같아야 한다.
	list = table.freeze({
		table.freeze({ id = "FRAME_BASIC", name = "기본", grade = "Normal", price = 0, color = { 74, 85, 112 }, thickness = 1 }),
		table.freeze({ id = "FRAME_BRONZE", name = "청동", grade = "Scarce", price = 100, color = { 205, 135, 80 }, thickness = 2 }),
		table.freeze({ id = "FRAME_TIDE", name = "물결", grade = "Rare", price = 150, color = { 64, 176, 204 }, thickness = 2 }),
		table.freeze({ id = "FRAME_FROST", name = "서리", grade = "Rare", price = 150, color = { 214, 232, 252 }, thickness = 2 }),
		table.freeze({ id = "FRAME_CRIMSON", name = "진홍", grade = "Epic", price = 250, color = { 214, 58, 82 }, thickness = 2.5 }),
		table.freeze({ id = "FRAME_AMETHYST", name = "자수정", grade = "Gorgeous", price = 400, color = { 170, 108, 236 }, thickness = 2.5 }),
	}),
})
