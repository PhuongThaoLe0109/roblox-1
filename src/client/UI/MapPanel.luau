-- MapPanel
-- Toggle with M (or the HUD button / gamepad ButtonY). Shows the world as a
-- radial map: hub in the middle, the 12 islands on a ring joined in portal
-- order, faction homes outside. Select an island to read about it and fast
-- travel there if your rank allows.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local TerritoryConfig = require(ReplicatedStorage:WaitForChild("TerritoryConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local ATTR = GemConfig.Attributes
local C = Theme.Colors
local NEUTRAL = Color3.fromRGB(235, 235, 245)
local MAP_SIZE = 440
local NODE_SIZE = 44

local ERROR_TEXT = {
	RankTooLow = "Your rank is too low for that island.",
	Cooldown = "Fast travel is recharging.",
	NotAlive = "You can't travel right now.",
	NoHome = "Rogue Shards have no home base.",
	InvalidDestination = "You can't travel there.",
}

local MapPanel = {}

function MapPanel.Init(screen: ScreenGui, context)
	local player = Players.LocalPlayer
	local remotes = ReplicatedStorage:WaitForChild("GemRemotes")
	local fastTravel = remotes:WaitForChild("RequestFastTravel") :: RemoteFunction

	local panel = Theme.panel({
		Name = "MapPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(MAP_SIZE + 300, MAP_SIZE + 80),
		Visible = false,
		ZIndex = 10,
		Parent = screen,
	})
	local panelScale = Theme.new("UIScale", { Parent = panel })

	Theme.label({
		Text = "World Map",
		Font = Theme.Fonts.Title,
		TextSize = 28,
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.fromOffset(300, 34),
		Parent = panel,
	})
	local close = Theme.button("✕", C.Danger, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(38, 38),
		Parent = panel,
	})

	----------------------------------------------------------------------------
	-- Radial map
	----------------------------------------------------------------------------
	local mapFrame = Theme.new("Frame", {
		Position = UDim2.fromOffset(20, 60),
		Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE),
		BackgroundColor3 = Color3.fromRGB(40, 70, 120),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = panel,
	}, { Theme.round() })
	Theme.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(120, 200, 255), Color3.fromRGB(150, 110, 220)),
		Rotation = 60,
		Parent = mapFrame,
	})

	local center = Vector2.new(MAP_SIZE / 2, MAP_SIZE / 2)
	local worldToMap = (MAP_SIZE / 2 - 30) / TerritoryConfig.HomeRadius

	local function toMap(world: Vector3): Vector2
		return center + Vector2.new(world.X, world.Z) * worldToMap
	end

	local function line(a: Vector2, b: Vector2, color: Color3, thickness: number)
		local delta = b - a
		local frame = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
			Size = UDim2.fromOffset(delta.Magnitude, thickness),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = mapFrame,
		})
		Theme.shimmer(frame, nil, 0.3, 0)
		return frame
	end

	-- Portal chain: hub -> 1 -> 2 -> ... -> 12, and homes <-> hub.
	local positions = {}
	for index in TerritoryConfig.Territories do
		positions[index] = toMap(TerritoryConfig.GetTerritoryCenter(index))
	end
	line(center, positions[1], Color3.new(1, 1, 1), 3)
	for index = 1, #positions - 1 do
		line(positions[index], positions[index + 1], Color3.new(1, 1, 1), 3)
	end

	local selectedId: string? = nil
	local nodes: { [string]: { Button: TextButton, Stroke: UIStroke, Index: number } } = {}

	local function makeNode(id: string, position: Vector2, label: string, color: Color3, size: number)
		local button = Theme.new("TextButton", {
			Name = id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(position.X, position.Y),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			AutoButtonColor = false,
			Text = label,
			Font = Theme.Fonts.Title,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(40, 30, 60),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = mapFrame,
		}, { Theme.round() })
		local stroke = Theme.stroke(Color3.new(1, 1, 1), 3, 0)
		stroke.Parent = button
		return button, stroke
	end

	makeNode("Hub", center, "✦", Color3.fromRGB(255, 220, 245), 54)
	for factionId, home in TerritoryConfig.Homes do
		local pos = toMap(TerritoryConfig.GetHomeCenter(factionId) :: Vector3)
		line(center, pos, GemConfig.Factions[factionId].Color, 2)
		makeNode("Home_" .. factionId, pos, "⌂", GemConfig.Factions[factionId].Color, 34)
		local _ = home
	end
	for index, info in TerritoryConfig.Territories do
		local button, stroke = makeNode(info.Id, positions[index], tostring(index), NEUTRAL, NODE_SIZE)
		stroke.Color = info.Accent
		nodes[info.Id] = { Button = button, Stroke = stroke, Index = index }
	end

	----------------------------------------------------------------------------
	-- Info side panel
	----------------------------------------------------------------------------
	local side = Theme.new("Frame", {
		Position = UDim2.fromOffset(MAP_SIZE + 40, 60),
		Size = UDim2.fromOffset(240, MAP_SIZE),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { Theme.list(Enum.FillDirection.Vertical, 8) })

	local title = Theme.label({ Text = "Select an island", Font = Theme.Fonts.Title, TextSize = 22, TextWrapped = true, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 1, Parent = side })
	local description = Theme.label({ Text = "", TextSize = 14, TextColor3 = C.SubText, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 80), LayoutOrder = 2, Parent = side })
	local ownerLabel = Theme.label({ Text = "", Font = Theme.Fonts.Bold, TextSize = 15, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3, Parent = side })
	local rankLabel = Theme.label({ Text = "", Font = Theme.Fonts.Bold, TextSize = 15, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 4, Parent = side })
	local travel = Theme.button("✨ Travel", C.Pink, { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 5, Visible = false, Parent = side })
	local status = Theme.label({ Text = "", TextSize = 13, TextColor3 = C.Warning, TextWrapped = true, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 6, Parent = side })

	local quick = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 7, Parent = side }, {
		Theme.list(Enum.FillDirection.Horizontal, 8),
	})
	local hubButton = Theme.button("✦ Hub", C.Lavender, { Size = UDim2.fromOffset(116, 38), TextSize = 16, Parent = quick })
	local homeButton = Theme.button("⌂ Home", C.Cyan, { Size = UDim2.fromOffset(116, 38), TextSize = 16, Parent = quick })

	local function territoryModel(id: string): Instance?
		local map = Workspace:FindFirstChild("Map")
		local folder = map and map:FindFirstChild("Territories")
		return folder and folder:FindFirstChild(id)
	end

	local function refresh()
		local rank = player:GetAttribute(ATTR.Rank) or 1
		for id, node in nodes do
			local model = territoryModel(id)
			local owner = model and model:GetAttribute("Owner")
			local faction = owner and owner ~= "" and GemConfig.Factions[owner]
			local locked = rank < node.Index
			node.Button.BackgroundColor3 = if faction then faction.Color else NEUTRAL
			node.Button.BackgroundTransparency = if locked then 0.55 else 0
			node.Button.Text = if locked then "🔒" else tostring(node.Index)
			node.Stroke.Thickness = if id == selectedId then 5 else 3
		end

		local info = selectedId and TerritoryConfig.ById[selectedId]
		if not info then
			return
		end
		local model = territoryModel(info.Id)
		local owner = model and model:GetAttribute("Owner") or ""
		local faction = GemConfig.Factions[owner]
		local required = TerritoryConfig.GetRequiredRank(info.Id)
		local unlocked = rank >= required

		title.Text = info.DisplayName
		description.Text = info.Description
		ownerLabel.Text = if faction then `Held by {faction.DisplayName}` else "Unclaimed"
		ownerLabel.TextColor3 = if faction then faction.Color else C.SubText
		rankLabel.Text = `Requires rank {required} · {GemConfig.Ranks[required].Name}` .. (if unlocked then "  ✓" else "")
		rankLabel.TextColor3 = if unlocked then C.Success else C.Danger
		travel.Visible = unlocked
	end

	for id, node in nodes do
		node.Button.Activated:Connect(function()
			selectedId = id
			status.Text = ""
			refresh()
		end)
	end

	local function requestTravel(destination: string)
		status.Text = "Opening portal…"
		local ok, err, remaining = fastTravel:InvokeServer(destination)
		if ok then
			status.Text = ""
			context.ToggleMap(false)
		else
			local message = ERROR_TEXT[err] or "Travel failed."
			if err == "Cooldown" and remaining then
				message = `Fast travel ready in {math.ceil(remaining)}s.`
			end
			status.Text = message
		end
	end

	travel.Activated:Connect(function()
		if selectedId then
			requestTravel(selectedId)
		end
	end)
	hubButton.Activated:Connect(function()
		requestTravel("Hub")
	end)
	homeButton.Activated:Connect(function()
		requestTravel("Home")
	end)

	----------------------------------------------------------------------------
	-- Open / close
	----------------------------------------------------------------------------
	local open = false
	local function setOpen(value: boolean?)
		if value == nil then
			value = not open
		end
		open = value :: boolean
		if open then
			refresh()
			panel.Visible = true
			panelScale.Scale = 0.85
			Theme.tween(panelScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			Theme.tween(panelScale, 0.15, { Scale = 0.9 })
			task.delay(0.15, function()
				if not open then
					panel.Visible = false
				end
			end)
		end
	end
	context.ToggleMap = setOpen

	close.Activated:Connect(function()
		setOpen(false)
	end)
	ContextActionService:BindAction("GemToggleMap", function(_, state)
		if state == Enum.UserInputState.Begin then
			setOpen()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonY)

	task.spawn(function()
		while panel.Parent do
			if open then
				refresh()
			end
			task.wait(0.5)
		end
	end)
end

return MapPanel
