--[[
	Robux 로 파는 상품(Developer Product) 의 ID.

	**0 은 "아직 안 만들었다" 는 정상값이다.** 0 이면 화면에 Robux 버튼이 뜨지 않는다 —
	`Theme.image.gold` 를 비워두면 글자로 그리는 것과 같은 태도다. 상품을 만들기 전까지
	게임이 막히면 안 된다.

	상품 만드는 법
	  1. 크리에이터 대시보드 → 이 경험 → 수익 창출(Monetization) → Developer Products → 만들기
	  2. 이름 "기본 팩", 가격은 정하기 나름(★ docs/open-questions.md), 아이콘은 선택
	  3. 만들어진 **Product ID**(숫자)를 아래에 넣는다
	  4. Studio 에서 게임 설정 → 보안 → "API 서비스 접근 허용" 이 켜져 있어야 저장된다

	Studio 에서 테스트 구매를 하면 실제 Robux 는 빠지지 않는다.

	서버와 클라이언트가 같이 읽는다. 클라이언트는 구매 창을 띄울 ID 로, 서버는 받은
	영수증이 어느 상품인지 가리는 데 쓴다(Lobby:processReceipt).

	Roblox API 를 쓰지 않는 순수 테이블이라 테스트가 Lune 에서 그대로 require 한다.
]]

return table.freeze({
	robuxPack = 0, -- 카드팩 한 봉 (Collection.Pack 과 같은 5장, 희귀 1 확정)
})
