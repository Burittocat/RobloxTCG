--[[
	Instance 흉내. 이 하네스에서 가장 중요한 파일이다.

	느슨하게 만들면 아무 오타나 통과해서 "테스트는 초록불인데 Studio 는 빨간 줄" 이 된다.
	그래서 두 가지를 엄격하게 본다.

	  1. 없는 클래스로 Instance.new    → 실패
	  2. 그 클래스에 없는 속성에 대입   → 실패

	속성 표는 손으로 적었다. 새 속성을 쓰기 시작하면 여기에도 한 줄 추가해야 하는데,
	그 한 줄이 "Studio 를 켜서 그 화면이 뜰 때까지 아무도 모르는 오타" 를 없앤다.
	Roblox 의 전체 API 를 흉내내는 게 목적이 아니라, **이 저장소가 실제로 쓰는 표면**만
	정확히 흉내내는 게 목적이다.
]]

local Signal = require("./Signal")

local RobloxInstance = {}

--==========================================================================
-- 클래스 계보 (IsA 가 이걸 본다)
--==========================================================================

local PARENT_CLASS = {
	Instance = nil,

	Folder = "Instance",
	RemoteEvent = "Instance",
	TeleportOptions = "Instance",
	Camera = "Instance",

	LayerCollector = "Instance",
	ScreenGui = "LayerCollector",

	GuiObject = "Instance",
	Frame = "GuiObject",
	ScrollingFrame = "Frame",
	GuiButton = "GuiObject",
	TextButton = "GuiButton",
	TextLabel = "GuiObject",
	ImageLabel = "GuiObject",

	UIComponent = "Instance",
	UICorner = "UIComponent",
	UIStroke = "UIComponent",
	UIGradient = "UIComponent",
	UIPadding = "UIComponent",
	UILayout = "UIComponent",
	UIListLayout = "UILayout",
	UIScale = "UIComponent",
	UIGridLayout = "UILayout",
}

--==========================================================================
-- 속성 표
--==========================================================================

local COMMON = { "Name", "Parent", "Archivable" }

local GUI_OBJECT = {
	"Size",
	"Position",
	"AnchorPoint",
	"BackgroundColor3",
	"BackgroundTransparency",
	"BorderColor3",
	"BorderSizePixel",
	"Visible",
	"ZIndex",
	"LayoutOrder",
	"ClipsDescendants",
	"AutomaticSize",
	"Active",
	"Rotation",
	"Transparency",
	"Selectable",
}

local GUI_TEXT = {
	"Text",
	"TextColor3",
	"TextSize",
	"TextScaled",
	"TextWrapped",
	"TextTransparency",
	"TextStrokeTransparency",
	"TextXAlignment",
	"TextYAlignment",
	"Font",
	"FontFace",
	"RichText",
	"LineHeight",
}

local function merge(...)
	local out = {}
	for _, list in { ... } do
		for _, key in list do
			out[key] = true
		end
	end
	return out
end

local PROPERTIES = {
	Folder = merge(COMMON),
	RemoteEvent = merge(COMMON),
	Camera = merge(COMMON, { "CameraType", "CFrame", "FieldOfView", "CameraSubject", "ViewportSize" }),

	TeleportOptions = merge(COMMON, {
		"ReservedServerAccessCode",
		"ShouldReserveServer",
		"ServerInstanceId",
	}),

	ScreenGui = merge(COMMON, {
		"Enabled",
		"ResetOnSpawn",
		"IgnoreGuiInset",
		"ZIndexBehavior",
		"DisplayOrder",
		"ClipToDeviceSafeArea",
	}),

	Frame = merge(COMMON, GUI_OBJECT),
	ScrollingFrame = merge(COMMON, GUI_OBJECT, {
		"CanvasSize",
		"CanvasPosition",
		"AutomaticCanvasSize",
		"ScrollingDirection",
		"ScrollingEnabled",
		"ScrollBarThickness",
		"ScrollBarImageColor3",
		"ScrollBarImageTransparency",
		"ElasticBehavior",
		"VerticalScrollBarInset",
	}),

	TextLabel = merge(COMMON, GUI_OBJECT, GUI_TEXT),
	TextButton = merge(COMMON, GUI_OBJECT, GUI_TEXT, { "AutoButtonColor", "Modal", "Style" }),
	ImageLabel = merge(COMMON, GUI_OBJECT, { "Image", "ImageColor3", "ImageTransparency", "ScaleType" }),

	UICorner = merge(COMMON, { "CornerRadius" }),
	UIStroke = merge(COMMON, {
		"Color",
		"Thickness",
		"Transparency",
		"ApplyStrokeMode",
		"LineJoinMode",
		"Enabled",
	}),
	UIGradient = merge(COMMON, { "Color", "Rotation", "Offset", "Transparency", "Enabled" }),
	UIPadding = merge(COMMON, { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" }),
	UIScale = merge(COMMON, { "Scale" }),
	UIListLayout = merge(COMMON, {
		"FillDirection",
		"Padding",
		"HorizontalAlignment",
		"VerticalAlignment",
		"SortOrder",
		"Wraps",
	}),
}

-- 처음 읽었을 때 nil 이면 곤란한 것들만 기본값을 준다.
local DEFAULTS = {
	Name = "",
	Active = true,
	Visible = true,
	Enabled = true,
	Text = "",
	Transparency = 0,
	BackgroundTransparency = 0,
	TextTransparency = 0,
}

--==========================================================================
-- 노드
--==========================================================================

local Node = {}

local function fields(node)
	return rawget(node, "_fields")
end

local function children(node)
	return rawget(node, "_children")
end

local function detach(node)
	local parent = fields(node).Parent
	if not parent then
		return
	end
	local siblings = children(parent)
	for index, child in siblings do
		if child == node then
			table.remove(siblings, index)
			break
		end
	end
end

--==========================================================================
-- 메서드
--==========================================================================

function Node:GetChildren()
	return table.clone(children(self))
end

function Node:GetDescendants()
	local out = {}
	for _, child in children(self) do
		table.insert(out, child)
		for _, deep in child:GetDescendants() do
			table.insert(out, deep)
		end
	end
	return out
end

function Node:FindFirstChild(name)
	for _, child in children(self) do
		if fields(child).Name == name then
			return child
		end
	end
	return nil
end

--[[
	진짜 WaitForChild 는 기다린다. 여기서는 없으면 그 자리에서 실패시킨다 —
	트리 구성이 틀렸다는 뜻이고, Studio 였다면 "무한 대기 후 경고" 로 조용히 묻혔을 문제다.
]]
function Node:WaitForChild(name)
	local child = self:FindFirstChild(name)
	if not child then
		error(("WaitForChild: %s 아래에 '%s' 가 없습니다"):format(self:GetFullName(), name), 2)
	end
	return child
end

function Node:FindFirstChildOfClass(className)
	for _, child in children(self) do
		if rawget(child, "ClassName") == className then
			return child
		end
	end
	return nil
end

function Node:IsA(className)
	local current = rawget(self, "ClassName")
	while current do
		if current == className then
			return true
		end
		current = PARENT_CLASS[current]
	end
	return false
end

function Node:GetFullName()
	local parts = {}
	local current = self
	while current do
		table.insert(parts, 1, fields(current).Name)
		current = fields(current).Parent
	end
	return table.concat(parts, ".")
end

function Node:Destroy()
	detach(self)
	fields(self).Parent = nil
	rawset(self, "_destroyed", true)
	for _, child in table.clone(children(self)) do
		child:Destroy()
	end
end

--[[
	속성 변경 신호. 진짜와 달리 **대입할 때만** 울린다
	(내부에서 바뀌는 속성 — 예: 실제 ViewportSize — 은 흉내내지 않는다).
]]
function Node:GetPropertyChangedSignal(name)
	local signals = rawget(self, "_propertySignals")
	if not signals[name] then
		signals[name] = Signal.new()
	end
	return signals[name]
end

function Node:ClearAllChildren()
	for _, child in table.clone(children(self)) do
		child:Destroy()
	end
end

--==========================================================================
-- 속성 접근
--==========================================================================

local NodeMeta = {}

NodeMeta.__index = function(self, key)
	local method = Node[key]
	if method then
		return method
	end

	local signals = rawget(self, "_signals")
	if signals[key] then
		return signals[key]
	end

	local values = fields(self)
	if values[key] ~= nil then
		return values[key]
	end

	local className = rawget(self, "ClassName")
	if PROPERTIES[className] and PROPERTIES[className][key] then
		return DEFAULTS[key]
	end

	-- 자식 이름으로도 접근할 수 있다 (workspace.CurrentCamera 처럼)
	local child = self:FindFirstChild(key)
	if child then
		return child
	end

	error(("%s (%s) 에는 '%s' 가 없습니다"):format(self:GetFullName(), className, tostring(key)), 2)
end

NodeMeta.__newindex = function(self, key, value)
	local className = rawget(self, "ClassName")
	local allowed = PROPERTIES[className]

	if not allowed or not allowed[key] then
		error(
			("%s 에는 '%s' 속성이 없습니다 — 오타이거나, tests/lib/Roblox/Instance.luau 의 속성 표에 빠졌습니다"):format(
				className,
				tostring(key)
			),
			2
		)
	end

	if key == "Parent" then
		detach(self)
		fields(self).Parent = value
		if value then
			table.insert(children(value), self)
		end
		return
	end

	local previous = fields(self)[key]
	fields(self)[key] = value

	if previous ~= value then
		local signal = rawget(self, "_propertySignals")[key]
		if signal then
			signal:Fire()
		end
	end
end

NodeMeta.__tostring = function(self)
	return fields(self).Name
end

--==========================================================================
-- 생성
--==========================================================================

local SIGNALS = {
	TextButton = { "Activated", "MouseButton1Click" },
	ScreenGui = {},
}

--[[
	RemoteEvent 은 서버/클라 양쪽 신호를 들고 있다.
	클라이언트 쪽 신호는 플레이어마다 따로다 — FireClient 가 그 사람에게만 가야 한다.
]]
local function attachRemote(node)
	rawset(node, "_serverSignal", Signal.new())
	rawset(node, "_clientSignals", {})

	local function clientSignal(player)
		local signals = rawget(node, "_clientSignals")
		if not signals[player] then
			signals[player] = Signal.new()
		end
		return signals[player]
	end

	rawset(node, "_clientSignalFor", clientSignal)

	local signals = rawget(node, "_signals")
	signals.OnServerEvent = rawget(node, "_serverSignal")

	rawset(node, "FireClient", function(_, player, ...)
		clientSignal(player):Fire(...)
	end)

	rawset(node, "FireAllClients", function(_, ...)
		for _, signal in rawget(node, "_clientSignals") do
			signal:Fire(...)
		end
	end)

	-- 서버 코드가 실수로 FireServer 를 부르면 바로 드러나게 둔다.
	rawset(node, "FireServer", function()
		error("FireServer 는 클라이언트에서만 부를 수 있습니다 (Roblox.client 프록시를 쓰세요)", 2)
	end)
end

function RobloxInstance.new(className, parent)
	if not PROPERTIES[className] then
		error(("Instance.new: '%s' 는 이 하네스가 모르는 클래스입니다"):format(tostring(className)), 2)
	end

	local node = setmetatable({
		ClassName = className,
		_fields = { Name = className, Parent = nil },
		_children = {},
		_signals = {},
		_propertySignals = {},
	}, NodeMeta)

	for _, signalName in SIGNALS[className] or {} do
		rawget(node, "_signals")[signalName] = Signal.new()
	end

	if className == "RemoteEvent" then
		attachRemote(node)
	end

	if className == "TeleportOptions" then
		rawset(node, "SetTeleportData", function(self, data)
			rawset(self, "_teleportData", data)
		end)
		rawset(node, "GetTeleportData", function(self)
			return rawget(self, "_teleportData")
		end)
	end

	if parent then
		node.Parent = parent
	end

	return node
end

--[[
	파일에서 온 모듈 노드(ModuleScript / Script / LocalScript)를 만든다.
	Rojo 가 폴더를 밀어넣은 결과에 해당한다.
]]
function RobloxInstance.newScript(className, name, path, parent)
	local node = setmetatable({
		ClassName = className,
		_fields = { Name = name, Parent = nil },
		_children = {},
		_signals = {},
		_propertySignals = {},
		_path = path,
	}, NodeMeta)

	PROPERTIES[className] = PROPERTIES[className] or merge(COMMON, { "Source", "Disabled" })
	PARENT_CLASS[className] = PARENT_CLASS[className] or "Instance"

	if parent then
		node.Parent = parent
	end
	return node
end

RobloxInstance.PROPERTIES = PROPERTIES
RobloxInstance.isNode = function(value)
	return type(value) == "table" and getmetatable(value) == NodeMeta
end

return RobloxInstance
