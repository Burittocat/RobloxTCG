--[[
	꾸밈 등급 (★ 기획서 미확정 — docs/open-questions.md)

	테두리 · 뒷면 모두 이 다섯 등급 중 하나다. **가격은 등급이 정한다** — 목록 파일
	(Frames · Backs)에도 price 가 적혀 있지만, 그건 이 표의 값과 같아야 한다
	(tests/specs/cosmetics.luau 가 본다). 목록 파일이 이 파일을 require 하지 않는 이유는
	그 파일들을 Lune 테스트가 그대로 읽기 때문이다(Frames 머리말).

	아래로 갈수록 높다. 화면은 이 순서와 색으로 등급을 보여준다.

	  id     저장값 · 목록에 적는 이름. 카드 등급(Common · Rare — Cards/Sheet)과는 **다른 표**다.
	         카드의 "희귀" 와 꾸밈의 "희귀" 는 이름만 같다
	  name   화면 글자
	  price  골드
	  color  등급 글자 색 (0~255). 하이라이트 색과 겹쳐도 괜찮다 — 꾸미기 화면에만 쓰인다

	"희귀" 와 "레어" 는 뜻이 같은 낱말이라, 처음 보는 사람이 어느 쪽이 높은지 헷갈릴 수 있다.
	순서는 사용자가 정한 대로 두고(2026-11-12) **색으로 구분**한다.
]]

return table.freeze({
	list = table.freeze({
		table.freeze({ id = "Normal", name = "일반", price = 0, color = { 180, 189, 208 } }),
		table.freeze({ id = "Scarce", name = "희귀", price = 100, color = { 110, 214, 140 } }),
		table.freeze({ id = "Rare", name = "레어", price = 150, color = { 96, 164, 248 } }),
		table.freeze({ id = "Epic", name = "에픽", price = 250, color = { 194, 124, 246 } }),
		table.freeze({ id = "Gorgeous", name = "고져스", price = 400, color = { 255, 178, 64 } }),
	}),
})
