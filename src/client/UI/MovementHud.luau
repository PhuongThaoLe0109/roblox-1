-- MovementHud
-- Bottom-right controls for getting around: the round hoverboard button,
-- Sprint and Dash pills (tappable on touch screens, with the dash cooldown
-- filling back up) and a double-jump hint. Key hints follow the last input
-- device used.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MovementController = require(script.Parent.Parent:WaitForChild("Movement"):WaitForChild("MovementController"))
local MovementConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("MovementConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors

local MovementHud = {}

local KEYS = {
	Keyboard = { Board = "B", Sprint = "Ctrl", Dash = "Q", Jump = "Space ×2" },
	Gamepad = { Board = "↑", Sprint = "L3", Dash = "B", Jump = "A ×2" },
	Touch = { Board = "", Sprint = "", Dash = "", Jump = "Jump ×2" },
}

local function deviceOf(inputType: Enum.UserInputType): string
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:find("Gamepad") then
		return "Gamepad"
	end
	return "Keyboard"
end

-- The hoverboard drawn from UI frames: a tilted glass deck with a bright core,
-- glowing thrusters and a little wake.
local function boardIcon(parent: Instance): Frame
	local holder = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(60, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Rotation = -18,
		Parent = parent,
	})
	local wake = Theme.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, 10, 0.5, 4),
		Size = UDim2.fromOffset(22, 6),
		Parent = holder,
	})
	Theme.round().Parent = wake
	Theme.new("UIGradient", {
		Color = ColorSequence.new(C.Cyan, C.Pink),
		Transparency = NumberSequence.new(1, 0.1),
		Parent = wake,
	})
	local deck = Theme.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(52, 13),
		Parent = holder,
	})
	Theme.round().Parent = deck
	Theme.shimmer(deck, nil, 0.4, 0)
	Theme.new("UIStroke", { Color = Color3.fromRGB(40, 20, 70), Thickness = 1.5, Transparency = 0.2, Parent = deck })
	local core = Theme.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.75, 0, 0, 3),
		Parent = deck,
	})
	Theme.round().Parent = core
	for _, x in { 0.3, 0.7 } do
		local thruster = Theme.new("Frame", {
			BackgroundColor3 = C.Cyan,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(x, 0, 0.5, 8),
			Size = UDim2.fromOffset(9, 5),
			Parent = holder,
		})
		Theme.round().Parent = thruster
	end
	return holder
end

local function pill(parent: Instance, text: string, order: number): (TextButton, TextLabel, Frame, UIStroke)
	local button = Theme.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(150, 38),
		LayoutOrder = order,
		ClipsDescendants = true,
		Parent = parent,
	})
	Theme.round().Parent = button
	local stroke = Theme.stroke(Color3.new(1, 1, 1), 1.5, 0.45)
	stroke.Parent = button
	Theme.shimmer(stroke, nil, 0.3)
	local fill = Theme.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = button,
	})
	Theme.shimmer(fill, nil, 0.25, 0)
	Theme.label({
		Text = text,
		FontFace = Theme.Faces.Heavy,
		TextSize = 17,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -60, 1, 0),
		ZIndex = 2,
		Parent = button,
	})
	local key = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Odds,
		TextSize = 12,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.new(0, 60, 1, 0),
		ZIndex = 2,
		Parent = button,
	})
	return button, key, fill, stroke
end

function MovementHud.Init(screen: ScreenGui, context)
	local root = Theme.new("Frame", {
		Name = "MovementHud",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -28, 1, -28),
		Size = UDim2.fromOffset(170, 250),
		Parent = screen,
	})
	local layout = Theme.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = root

	-- Hoverboard button
	local board = Theme.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(88, 88),
		LayoutOrder = 1,
		Parent = root,
	})
	Theme.round().Parent = board
	Theme.new("UIGradient", { Color = ColorSequence.new(C.PanelLight, C.Panel), Rotation = 90, Parent = board })
	local boardStroke = Theme.stroke(Color3.new(1, 1, 1), 2.5, 0.2)
	boardStroke.Parent = board
	local boardShimmer = Theme.shimmer(boardStroke, nil, 0.3)
	boardIcon(board)
	local boardLabel = Theme.label({
		Text = "BOARD",
		FontFace = Theme.Faces.Heavy,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = board,
	})
	local boardKey = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Odds,
		TextSize = 11,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 2, 0, -2),
		Size = UDim2.fromOffset(24, 20),
		Parent = board,
	})
	Theme.corner(6).Parent = boardKey
	local boardScale = Theme.new("UIScale", { Parent = board })

	local sprint, sprintKey, sprintFill, sprintStroke = pill(root, "SPRINT", 2)
	local dash, dashKey, dashFill = pill(root, "DASH", 3)
	local jumpHint = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Bold,
		TextSize = 13,
		TextColor3 = C.SubText,
		TextStrokeTransparency = 0.6,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(170, 18),
		LayoutOrder = 4,
		Parent = root,
	})

	local function setDevice(device: string)
		local keys = KEYS[device]
		boardKey.Text = keys.Board
		boardKey.Visible = keys.Board ~= ""
		sprintKey.Text = keys.Sprint
		dashKey.Text = keys.Dash
		jumpHint.Text = `Double jump  {keys.Jump}`
	end
	setDevice(if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Keyboard")
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		setDevice(deviceOf(inputType))
	end)

	local state = MovementController.State
	local function refresh()
		local riding = state.Riding
		board.Visible = MovementController.CanRide() or riding
		boardStroke.Color = if riding then C.Gold else Color3.new(1, 1, 1)
		boardShimmer.Enabled = not riding
		board.BackgroundColor3 = if riding then C.PanelLight else C.Panel
		boardLabel.Text = if riding then "RIDING" else "BOARD"
		sprintFill.Visible = state.Sprinting
		sprintStroke.Transparency = if state.Sprinting then 0 else 0.45
	end
	MovementController.Changed:Connect(refresh)
	refresh()

	-- Dash cooldown refills left to right.
	RunService.RenderStepped:Connect(function()
		local left = state.DashReadyAt - os.clock()
		local alpha = if left <= 0 then 1 else 1 - left / MovementConfig.Dash.Cooldown
		dashFill.Size = UDim2.fromScale(alpha, 1)
		dashFill.BackgroundTransparency = if alpha >= 1 then 0.75 else 0.5
	end)

	board.Activated:Connect(function()
		boardScale.Scale = 0.9
		Theme.tween(boardScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		MovementController.ToggleHoverboard()
	end)
	sprint.Activated:Connect(function()
		MovementController.SetSprint(not state.Sprinting)
	end)
	dash.Activated:Connect(function()
		MovementController.Dash()
	end)
	local _ = context
end

return MovementHud
