--[[
	같은 것은 지우지 말고 찾아서 고친다.

	    Reconcile.children(container, {
	        { key = 카드id, build = function() ... end, paint = function(frame) ... end },
	        ...
	    })

	이 파일이 있는 이유는 **연출** 때문이다.

	예전에는 스냅샷이 올 때마다 `Widgets.clear` 로 줄을 통째로 비우고 다시 그렸다.
	화면 결과는 같지만, 그리면 매번 **다른 인스턴스**가 된다. 그러면 이런 것들이
	원리적으로 불가능하다.

	  · 카드가 덱에서 손으로 날아가는 연출 — 날아가는 도중 다음 스냅샷이 오면
	    그 인스턴스가 Destroy 되어 도중에 증발한다
	  · "방금 뽑은 카드" 강조 — 어느 게 새로 온 것인지 코드가 알 수 없다
	  · 손패 재배치 — 남아 있는 카드가 제자리에서 미끄러져 이동해야 하는데,
	    지우고 다시 그리면 전부 제자리에서 튀어나온다

	그래서 **키(카드 인스턴스 id)로 장부를 들고**, 있으면 고치고 없으면 만들고
	사라진 것만 지운다. 트윈은 살아남은 인스턴스에 붙는다.

	장부는 컨테이너별로 **약한 키**로 들고 있다. 컨테이너가 Destroy 되면 장부도
	같이 사라진다 — 판이 끝나고 화면을 새로 만들 때 손으로 치울 것이 없다.
]]

local Reconcile = {}

local books = setmetatable({}, { __mode = "k" })

--[[
	items 는 순서대로 그릴 것들이다. 배열 순서가 그대로 LayoutOrder 가 된다.

	  key    이 자리의 신원. 같은 key 면 같은 인스턴스를 계속 쓴다
	  build  없을 때 만드는 함수 -> Instance
	  paint  있을 때(그리고 만든 직후) 현재 상태를 입히는 함수 (선택)
	  enter  **새로 생겼을 때만** 한 번 불린다 — 등장 연출 자리 (선택)

	돌려주는 것: 그려진 인스턴스 배열(items 와 같은 순서).
	화살표처럼 "그 카드가 화면 어디에 있나" 를 알아야 하는 쪽이 이걸 쓴다.
]]
function Reconcile.children(container, items)
	local book = books[container]
	if not book then
		book = {}
		books[container] = book
	end

	local seen = {}
	local drawn = table.create(#items)

	for order, item in items do
		local instance = book[item.key]

		--[[
			장부에 있어도 못 믿는 경우가 둘 있다. Destroy 된 것(Parent 가 nil),
			그리고 다른 줄로 옮겨간 것 — 생물이 상대 필드로 넘어가는 효과가 생기면
			같은 카드 id 가 다른 컨테이너에 나타난다. 둘 다 새로 만든다.
		]]
		if instance and instance.Parent ~= container then
			instance = nil
		end

		--[[
			새로 만든 것에는 paint 를 부르지 않는다. build 가 돌려주는 것은
			**이미 현재 상태로 칠해진** 인스턴스다 — 여기서 또 칠하면 방금 만든
			자식들을 지우고 같은 것을 다시 만드는 헛일이 된다.
		]]
		local isNew = instance == nil
		if isNew then
			instance = item.build()
			book[item.key] = instance
		elseif item.paint then
			item.paint(instance)
		end

		--[[
			등장 연출은 **부모에 붙기 전에** 걸어둔다. 붙는 순간이 화면에 처음
			나타나는 순간이라, 그 뒤에 초기값을 넣으면 한 프레임 동안 완성된 모습이
			번쩍였다가 연출이 시작된다.
		]]
		if isNew and item.enter then
			item.enter(instance)
		end

		instance.LayoutOrder = order

		--[[
			Parent 를 매번 다시 넣지 않는다. 하네스도 진짜 로블록스도 Parent 대입은
			"떼었다 붙이기" 라서 자식 목록 끝으로 밀려난다. 순서는 LayoutOrder 가
			정하므로 결과는 같지만, 매 렌더마다 트리를 흔들 이유가 없다.
		]]
		if isNew then
			instance.Parent = container
		end

		seen[item.key] = true
		drawn[order] = instance
	end

	-- 이번에 안 나온 것 = 그 존을 떠난 것. 지운다.
	for key, instance in book do
		if not seen[key] then
			book[key] = nil
			instance:Destroy()
		end
	end

	return drawn
end

--[[
	장부만 비운다(인스턴스는 건드리지 않는다). 컨테이너를 손으로 비운 뒤
	"처음부터 다시" 를 시키고 싶을 때 쓴다.
]]
function Reconcile.forget(container)
	books[container] = nil
end

return Reconcile
