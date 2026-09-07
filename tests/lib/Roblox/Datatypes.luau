--[[
	Roblox 데이터타입과 Enum 흉내.

	값을 정확히 계산할 필요는 없다 — 레이아웃이 픽셀 단위로 맞는지는 어차피 눈으로 봐야 한다.
	여기서 잡고 싶은 것은 **존재하지 않는 것을 쓰는 코드** 다.

	    Enum.TextXAlignment.Centre   -- 오타. Studio 에서만 터진다
	    UDim2.fromOffest(10, 10)     -- 오타. Studio 에서만 터진다

	그래서 Enum 은 실제로 쓰는 항목만 적어두고, 없는 이름을 읽으면 그 자리에서 실패시킨다.
	새 Enum 항목을 쓰기 시작하면 여기에도 추가해야 한다 — 귀찮지만, 이 귀찮음이
	"Studio 켜야만 알 수 있는 오타" 를 "테스트가 잡는 오타" 로 바꾼다.
]]

local Datatypes = {}

--==========================================================================
-- Enum
--==========================================================================

local ENUMS = {
	FillDirection = { "Horizontal", "Vertical" },
	HorizontalAlignment = { "Left", "Center", "Right" },
	VerticalAlignment = { "Top", "Center", "Bottom" },
	TextXAlignment = { "Left", "Center", "Right" },
	TextYAlignment = { "Top", "Center", "Bottom" },
	SortOrder = { "Name", "Custom", "LayoutOrder" },
	AutomaticSize = { "None", "X", "Y", "XY" },
	ScrollingDirection = { "X", "Y", "XY" },
	ZIndexBehavior = { "Global", "Sibling" },
	ApplyStrokeMode = { "Contextual", "Border" },
	EasingStyle = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Back", "Bounce" },
	EasingDirection = { "In", "Out", "InOut" },
	CameraType = { "Fixed", "Attach", "Watch", "Track", "Follow", "Custom", "Scriptable" },
	CoreGuiType = { "PlayerList", "Health", "Backpack", "Chat", "All", "EmotesMenu" },
	Font = {
		"Legacy",
		"Arial",
		"SourceSans",
		"SourceSansBold",
		"Gotham",
		"GothamMedium",
		"GothamBold",
		"GothamBlack",
	},
	KeyCode = {
		"E",
		"P",
		"L",
		"R",
		"Q",
		"Escape",
		"Return",
		"Space",
		"One",
		"Two",
		"Three",
		"Four",
	},
	UserInputType = { "MouseButton1", "MouseButton2", "Keyboard", "Touch" },
}

local function makeEnumType(typeName, items)
	local values = {}
	for index, name in items do
		values[name] = setmetatable({
			EnumType = typeName,
			Name = name,
			Value = index - 1,
		}, {
			__tostring = function(self)
				return ("Enum.%s.%s"):format(typeName, self.Name)
			end,
		})
	end

	return setmetatable({}, {
		__index = function(_, key)
			local value = values[key]
			if value == nil then
				error(("Enum.%s.%s 는 없는 항목입니다"):format(typeName, tostring(key)), 2)
			end
			return value
		end,
	})
end

local enumTypes = {}
for typeName, items in ENUMS do
	enumTypes[typeName] = makeEnumType(typeName, items)
end

Datatypes.Enum = setmetatable({}, {
	__index = function(_, key)
		local enumType = enumTypes[key]
		if enumType == nil then
			error(
				("Enum.%s 는 이 하네스가 모르는 Enum 입니다 — tests/lib/Roblox/Datatypes.luau 에 추가하세요"):format(
					tostring(key)
				),
				2
			)
		end
		return enumType
	end,
})

--==========================================================================
-- 값 타입
--==========================================================================

local function valueType(name, fields)
	local meta = {
		__tostring = function(self)
			local parts = {}
			for _, field in fields do
				table.insert(parts, tostring(self[field]))
			end
			return ("%s(%s)"):format(name, table.concat(parts, ", "))
		end,
	}
	meta.__index = meta
	return meta
end

local UDimMeta = valueType("UDim", { "Scale", "Offset" })
local UDim2Meta = valueType("UDim2", { "X", "Y" })
local Vector2Meta = valueType("Vector2", { "X", "Y" })
local Color3Meta = valueType("Color3", { "R", "G", "B" })

Datatypes.UDim = {
	new = function(scale, offset)
		return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDimMeta)
	end,
}

Datatypes.UDim2 = {
	new = function(xScale, xOffset, yScale, yOffset)
		return setmetatable({
			X = Datatypes.UDim.new(xScale, xOffset),
			Y = Datatypes.UDim.new(yScale, yOffset),
		}, UDim2Meta)
	end,

	fromScale = function(x, y)
		return Datatypes.UDim2.new(x, 0, y, 0)
	end,

	fromOffset = function(x, y)
		return Datatypes.UDim2.new(0, x, 0, y)
	end,
}

Datatypes.Vector2 = {
	new = function(x, y)
		return setmetatable({ X = x or 0, Y = y or 0 }, Vector2Meta)
	end,
}

Datatypes.Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Meta)
	end,

	fromRGB = function(r, g, b)
		return Datatypes.Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
	end,
}

Datatypes.ColorSequence = {
	new = function(from, to)
		return { From = from, To = to or from }
	end,
}

Datatypes.TweenInfo = {
	new = function(time, style, direction)
		return { Time = time or 1, Style = style, Direction = direction }
	end,
}

Datatypes.CFrame = {
	new = function(x, y, z)
		return { X = x or 0, Y = y or 0, Z = z or 0 }
	end,
}

--[[
	위 테이블들은 게임 코드가 실수로 늘리지 못하게 얼려둔다.
	(UDim2.fromOffest = ... 같은 오타가 조용히 통과하면 하네스의 의미가 없다)
]]
for _, name in { "UDim", "UDim2", "Vector2", "Color3", "ColorSequence", "TweenInfo", "CFrame" } do
	local original = Datatypes[name]
	Datatypes[name] = setmetatable({}, {
		__index = function(_, key)
			local value = original[key]
			if value == nil then
				error(("%s.%s 는 없는 생성자입니다"):format(name, tostring(key)), 2)
			end
			return value
		end,
		__newindex = function()
			error(("%s 에는 값을 넣을 수 없습니다"):format(name), 2)
		end,
	})
end

return Datatypes
