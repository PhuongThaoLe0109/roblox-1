-- LoadingScreen
-- Prism-gradient title card shown until the player's gem data has loaded and
-- their character exists, then dissolves into the world.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local ATTR = GemConfig.Attributes
local C = Theme.Colors

local LoadingScreen = {}

local TIPS = {
	"Stand on an island's glowing pad to capture it for your faction.",
	"Each rank unlocks the portal to the next island.",
	"Double jump, then hold jump to float down like a feather.",
	"Hold Shift to sprint and leave a trail of light.",
	"Press M to open the world map and fast travel.",
	"The sky turns pink at sunset. Stop and look sometimes.",
}

function LoadingScreen.Init(screen: ScreenGui)
	local player = Players.LocalPlayer

	local root = Theme.new("Frame", {
		Name = "LoadingScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 100,
		Parent = screen,
	})
	Theme.shimmer(root, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 210)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(190, 160, 255)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(120, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 210)),
	}), 0.06, 30)

	local title = Theme.label({
		Text = Theme.GameTitle,
		Font = Theme.Fonts.Title,
		TextSize = 84,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Color3.fromRGB(110, 60, 140),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(1, 0, 0, 96),
		ZIndex = 101,
		Parent = root,
	})
	local status = Theme.label({
		Text = "Forming your gem…",
		Font = Theme.Fonts.Bold,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.42, 60),
		Size = UDim2.new(1, 0, 0, 26),
		ZIndex = 101,
		Parent = root,
	})
	local tip = Theme.label({
		Text = TIPS[math.random(#TIPS)],
		TextSize = 16,
		TextColor3 = Color3.fromRGB(70, 50, 100),
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(0.8, 0, 0, 24),
		ZIndex = 101,
		Parent = root,
	})

	-- Pulsing gem in the middle
	local gem = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.fromOffset(56, 56),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 101,
		Parent = root,
	}, { Theme.corner(10) })
	Theme.shimmer(gem, nil, 0.8, 45)
	local gemScale = Theme.new("UIScale", { Parent = gem })

	local done = false
	task.spawn(function()
		local tipTimer = 0
		while not done do
			local t = os.clock()
			gemScale.Scale = 1 + math.sin(t * 3) * 0.12
			gem.Rotation = 45 + math.sin(t * 1.5) * 10
			tipTimer += task.wait()
			if tipTimer > 4 then
				tipTimer = 0
				tip.Text = TIPS[math.random(#TIPS)]
			end
		end
	end)

	local function isReady(): boolean
		return player:GetAttribute(ATTR.DataLoaded) == true and player.Character ~= nil
	end

	task.spawn(function()
		local waited = 0
		while not isReady() do
			waited += task.wait(0.2)
			if waited > 20 then
				status.Text = "Still forming… the crystal is being stubborn."
			end
		end
		status.Text = "Welcome."
		task.wait(0.6)
		done = true
		for _, item in { title, status, tip } do
			Theme.tween(item, 0.8, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
		Theme.tween(gem, 0.6, { BackgroundTransparency = 1 })
		Theme.tween(root, 1.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
		task.wait(1.3)
		root:Destroy()
	end)

	local _ = C
end

return LoadingScreen
