-- Inventory
-- The gem collection: all 100 gems in a grid (unowned ones as "???"
-- silhouettes), filter to owned, sort by rarity, and a detail pane to inspect
-- and equip a gem's aura.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local ClientData = require(script.Parent.Parent:WaitForChild("ClientData"))
local GemArt = require(script.Parent:WaitForChild("GemArt"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors

local Inventory = {}

local CELL = 92

local ERROR_TEXT = {
	NotOwned = "You don't own that gem yet.",
	Cooldown = "One moment…",
	NotLoaded = "Still loading your data…",
}

function Inventory.Init(screen: ScreenGui, context)
	local equipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestEquip") :: RemoteFunction

	local panel = Theme.panel({
		Name = "Inventory",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 560),
		Visible = false,
		ZIndex = 20,
		Parent = screen,
	})
	local panelScale = Theme.new("UIScale", { Parent = panel })

	local title = Theme.headline({
		Text = "Collection",
		FontFace = Theme.Faces.Title,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.fromOffset(400, 36),
		Parent = panel,
	}, nil, 0.25)
	local close = Theme.button("✕", C.Danger, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(40, 40),
		Parent = panel,
	})

	-- Filters
	local filters = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 56),
		Size = UDim2.fromOffset(560, 34),
		Parent = panel,
	}, { Theme.list(Enum.FillDirection.Horizontal, 8) })
	local ownedOnly = false
	local rarestFirst = false
	local ownedButton = Theme.button("Owned only: Off", C.Lavender, { Size = UDim2.fromOffset(170, 32), TextSize = 15, Parent = filters })
	local sortButton = Theme.button("Sort: Common first", C.Cyan, { Size = UDim2.fromOffset(190, 32), TextSize = 15, Parent = filters })

	-- Grid
	local grid = Theme.new("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 98),
		Size = UDim2.fromOffset(580, 444),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Pink,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	})
	Theme.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL, CELL + 22),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	Theme.padding(4).Parent = grid

	-- Detail pane
	local detail = Theme.new("Frame", {
		Position = UDim2.fromOffset(616, 60),
		Size = UDim2.fromOffset(264, 482),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = panel,
	}, { Theme.corner(14) })
	local detailIconHolder = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(32, 16),
		Size = UDim2.fromOffset(200, 200),
		Parent = detail,
	})
	local detailName = Theme.headline({
		Text = "Pick a gem",
		TextSize = 28,
		TextWrapped = true,
		Position = UDim2.fromOffset(10, 224),
		Size = UDim2.new(1, -20, 0, 64),
		Parent = detail,
	}, nil, 0.4)
	local detailGradient = detailName:FindFirstChildOfClass("UIGradient") :: UIGradient
	local detailOdds = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Odds,
		TextSize = 14,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(10, 290),
		Size = UDim2.new(1, -20, 0, 22),
		Parent = detail,
	})
	local detailCount = Theme.label({
		Text = "",
		TextSize = 15,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(10, 316),
		Size = UDim2.new(1, -20, 0, 20),
		Parent = detail,
	})
	local equipButton = Theme.button("Equip aura", C.Pink, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(1, -40, 0, 48),
		TextSize = 20,
		Visible = false,
		Parent = detail,
	})
	local status = Theme.label({
		Text = "",
		TextSize = 13,
		TextColor3 = C.Warning,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -74),
		Size = UDim2.new(1, -20, 0, 36),
		Parent = detail,
	})

	local selectedId: string? = nil
	local cells: { [string]: { Frame: Frame, Count: TextLabel, Stroke: UIStroke } } = {}

	local function refreshDetail()
		for _, child in detailIconHolder:GetChildren() do
			child:Destroy()
		end
		local gem = selectedId and GemCatalog.Get(selectedId)
		if not gem then
			detailName.Text = "Pick a gem"
			detailOdds.Text = ""
			detailCount.Text = ""
			equipButton.Visible = false
			return
		end
		local owned = ClientData.Count(gem.Id)
		GemArt.Icon(gem, 200, owned > 0).Parent = detailIconHolder
		detailName.Text = if owned > 0 then gem.Name else "???"
		detailGradient.Color = if GemArt.Tier(gem) >= 4 then GemArt.Rainbow else GemArt.Gradient(gem)
		detailOdds.Text = GemCatalog.FormatOdds(gem.Odds)
		detailCount.Text = if owned > 0 then `Owned ×{Theme.formatNumber(owned)}` else "Not found yet"
		equipButton.Visible = owned > 0
		local equipped = ClientData.Equipped == gem.Id
		equipButton.Text = if equipped then "Equipped ✓" else "Equip aura"
		equipButton.AutoButtonColor = not equipped
	end

	local function refreshCell(gem: GemCatalog.Gem)
		local entry = cells[gem.Id]
		if not entry then
			return
		end
		local owned = ClientData.Count(gem.Id)
		local holder = entry.Frame:FindFirstChild("IconHolder") :: Frame
		for _, child in holder:GetChildren() do
			child:Destroy()
		end
		GemArt.Icon(gem, CELL - 18, owned > 0).Parent = holder
		entry.Count.Text = if owned > 0 then `×{Theme.formatNumber(owned)}` else ""
		local nameLabel = entry.Frame:FindFirstChild("Name") :: TextLabel
		nameLabel.Text = if owned > 0 then gem.Name else GemCatalog.FormatOdds(gem.Odds)
		entry.Stroke.Color = if ClientData.Equipped == gem.Id then C.Gold elseif selectedId == gem.Id then Color3.new(1, 1, 1) else gem.Accent
		entry.Stroke.Thickness = if ClientData.Equipped == gem.Id or selectedId == gem.Id then 3 else 1
		entry.Stroke.Transparency = if owned > 0 then 0.2 else 0.7
		entry.Frame.Visible = not ownedOnly or owned > 0
		entry.Frame.LayoutOrder = if rarestFirst then -gem.Index else gem.Index
	end

	local function refreshAll()
		for _, gem in GemCatalog.List do
			refreshCell(gem)
		end
		title.Text = `Collection  {ClientData.UniqueOwned()}/{#GemCatalog.List}`
		refreshDetail()
	end

	for _, gem in GemCatalog.List do
		local cell = Theme.new("TextButton", {
			Name = gem.Id,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			LayoutOrder = gem.Index,
			Parent = grid,
		}, { Theme.corner(12) })
		local stroke = Theme.stroke(gem.Accent, 1, 0.2)
		stroke.Parent = cell
		Theme.new("Frame", {
			Name = "IconHolder",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(9, 4),
			Size = UDim2.fromOffset(CELL - 18, CELL - 18),
			Parent = cell,
		})
		local count = Theme.label({
			Name = "Count",
			Text = "",
			Font = Theme.Fonts.Title,
			TextSize = 13,
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(0, 2),
			Size = UDim2.new(1, -6, 0, 16),
			ZIndex = 3,
			Parent = cell,
		})
		Theme.label({
			Name = "Name",
			Text = "",
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.new(0, 3, 1, -22),
			Size = UDim2.new(1, -6, 0, 16),
			Parent = cell,
		})
		cells[gem.Id] = { Frame = cell, Count = count, Stroke = stroke }
		cell.Activated:Connect(function()
			local previous = selectedId and GemCatalog.Get(selectedId)
			selectedId = gem.Id
			status.Text = ""
			if previous then
				refreshCell(previous)
			end
			refreshCell(gem)
			refreshDetail()
		end)
	end

	ownedButton.Activated:Connect(function()
		ownedOnly = not ownedOnly
		ownedButton.Text = if ownedOnly then "Owned only: On" else "Owned only: Off"
		refreshAll()
	end)
	sortButton.Activated:Connect(function()
		rarestFirst = not rarestFirst
		sortButton.Text = if rarestFirst then "Sort: Rarest first" else "Sort: Common first"
		refreshAll()
	end)

	equipButton.Activated:Connect(function()
		if not selectedId or ClientData.Equipped == selectedId then
			return
		end
		local ok, err = equipRemote:InvokeServer(selectedId)
		status.Text = if ok then "" else ERROR_TEXT[err] or "Couldn't equip that gem."
	end)

	ClientData.Changed:Connect(function(kind, gemId)
		if not panel.Visible then
			return
		end
		if kind == "Gem" and gemId then
			local gem = GemCatalog.Get(gemId)
			if gem then
				refreshCell(gem)
			end
			title.Text = `Collection  {ClientData.UniqueOwned()}/{#GemCatalog.List}`
			if gemId == selectedId then
				refreshDetail()
			end
		else
			refreshAll()
		end
	end)

	local open = false
	local function setOpen(value: boolean?)
		if value == nil then
			value = not open
		end
		open = value :: boolean
		if open then
			refreshAll()
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
	context.ToggleInventory = setOpen
	close.Activated:Connect(function()
		setOpen(false)
	end)
	ContextActionService:BindAction("GemToggleInventory", function(_, state)
		if state == Enum.UserInputState.Begin and context.InLobby() then
			setOpen()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.I, Enum.KeyCode.ButtonY)
end

return Inventory
