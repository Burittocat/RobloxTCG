--[[
	순위표 — 랭크 점수 위 50명. 이름을 누르면 그 사람의 프로필을 연다.

	여기에도 판정이 없다. 목록과 순위는 서버가 만들어 내려준다(LeaderboardStore). 화면은
	티어 색과 글자만 정한다 — 티어는 점수에서 Rank.tierOf 로 바로 나오므로 서버가 따로
	싣지 않는다.

	내가 목록 안에 있으면 그 줄을 초록 테두리로 짚고, 밖이면 아래에 내 점수만 따로 띄운다.
	"내가 어디쯤인가" 가 순위표를 여는 이유의 절반이다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rank = require(ReplicatedStorage:WaitForChild("Shared").Rank)

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

local new = Widgets.new

local Leaderboard = {}
Leaderboard.__index = Leaderboard

local ROW_HEIGHT = 36
local ROW_GAP = 4

local function tierColor(points)
	local tier = Rank.tierOf(points)
	return Color3.fromRGB(tier.color[1], tier.color[2], tier.color[3])
end

-- 위 셋은 메달 색. 그 아래는 평범한 글자다.
local MEDAL = {
	Color3.fromRGB(247, 206, 112),
	Color3.fromRGB(206, 214, 228),
	Color3.fromRGB(214, 150, 96),
}

function Leaderboard.new(parent)
	local self = setmetatable({}, Leaderboard)

	local noop = function() end
	self.callbacks = { view = noop, back = noop }

	self:build(parent)
	return self
end

function Leaderboard:build(parent)
	local gui = new("ScreenGui", {
		Name = "TCGLeaderboard",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 20,
		Enabled = false,
		Parent = parent,
	})
	self.gui = gui

	local root = new("Frame", {
		Name = "Root",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.color.bg,
		BorderSizePixel = 0,
	}, {
		new("UIGradient", {
			Color = ColorSequence.new(Theme.color.bgDeep, Theme.color.bg),
			Rotation = 90,
		}),
	})

	Widgets.autoScale(root)

	local column = new("Frame", {
		Name = "Column",
		Parent = root,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 600),
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center),
	})

	Widgets.label("순위표", {
		Parent = column,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.font.bold,
		TextSize = 32,
	})

	Widgets.label("랭크 점수 순 · 이름을 누르면 프로필을 봅니다", {
		Parent = column,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = Theme.text.small,
		TextColor3 = Theme.color.textDim,
	})

	self.list = new("ScrollingFrame", {
		Name = "Rows",
		Parent = column,
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 400),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 6,
	}, {
		Widgets.listLayout(Enum.FillDirection.Vertical, ROW_GAP, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})

	self.empty = Widgets.label("아직 순위표에 아무도 없습니다 — 빠른 대전에서 이기면 올라갑니다", {
		Name = "Empty",
		Parent = self.list,
		Size = UDim2.new(1, 0, 0, 40),
		TextColor3 = Theme.color.textDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})

	self.meLabel = Widgets.label("", {
		Name = "Me",
		Parent = column,
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	Widgets.button("뒤로", {
		Parent = column,
		LayoutOrder = 5,
		Size = UDim2.fromOffset(200, 40),
		TextSize = Theme.text.label,
	}, function()
		self.callbacks.back()
	end)
end

--[[
	한 줄. 줄 전체가 버튼이다 — 이름 글자만 누르게 하면 누를 곳이 너무 작다.
	이름은 Row_<순위>. 테스트와 사람이 "3등" 을 같은 방법으로 짚는다.
]]
function Leaderboard:addRow(row, mine)
	local button = new("TextButton", {
		Name = ("Row_%d"):format(row.place),
		Parent = self.list,
		LayoutOrder = row.place,
		Size = UDim2.new(1, -10, 0, ROW_HEIGHT),
		BackgroundColor3 = mine and Theme.color.panelSoft or Theme.color.panel,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = "",
	}, {
		Widgets.corner(6),
		Widgets.stroke(mine and Theme.color.me or Theme.color.stroke, mine and 2 or 1),
		Widgets.padding(0, { PaddingLeft = 12, PaddingRight = 12 }),
	})

	button.Activated:Connect(function()
		self.callbacks.view(row.userId)
	end)

	Widgets.label(("%d"):format(row.place), {
		Parent = button,
		Size = UDim2.new(0, 40, 1, 0),
		Font = Theme.font.bold,
		TextSize = Theme.text.title,
		TextColor3 = MEDAL[row.place] or Theme.color.textDim,
	})

	Widgets.label(tostring(row.name), {
		Name = "RowName",
		Parent = button,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -230, 1, 0),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		-- 잘라내기(TextTruncate)는 안 건다. Roblox 사용자 이름은 20자까지라 이 폭에 들어간다.
	})

	Widgets.label(Rank.label(row.points), {
		Name = "RowRank",
		Parent = button,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 180, 1, 0),
		Font = Theme.font.bold,
		TextSize = Theme.text.label,
		TextColor3 = tierColor(row.points),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
end

function Leaderboard:setVisible(visible)
	self.gui.Enabled = visible
end

--[[
	payload 는 서버가 보낸 그대로다. (Net 의 로비 프로토콜 — leaderboard 화면)
]]
function Leaderboard:render(payload)
	for _, child in self.list:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	local rows = payload.rows or {}
	local me = payload.me or {}

	for _, row in rows do
		if type(row) == "table" and type(row.place) == "number" then
			self:addRow(row, row.userId == me.userId)
		end
	end

	self.empty.Visible = (#rows == 0)
	self.list.CanvasSize = UDim2.fromOffset(0, math.max(1, #rows) * (ROW_HEIGHT + ROW_GAP))

	local points = tonumber(me.points) or 0
	if me.place then
		self.meLabel.Text = ("내 순위 %d위 · %s"):format(me.place, Rank.label(points))
	else
		self.meLabel.Text = ("내 순위 %d위 밖 · %s"):format(tonumber(payload.size) or 50, Rank.label(points))
	end
	self.meLabel.TextColor3 = tierColor(points)
end

return Leaderboard
