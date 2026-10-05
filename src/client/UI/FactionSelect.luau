-- FactionSelect
-- Full-screen allegiance picker. Opens automatically the first time a Rogue
-- (Neutral) player's data loads, and on demand from the HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local TerritoryConfig = require(ReplicatedStorage:WaitForChild("TerritoryConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local ATTR = GemConfig.Attributes
local C = Theme.Colors

local FactionSelect = {}

local BLURBS = {
	Guardians = "Rebels who protect the planet's surface and every life on it. Fight to keep the islands free.",
	Dominion = "The empire that grew gems from this world. Reclaim the islands for the Crown.",
}

local ERROR_TEXT = {
	Cooldown = "You switched sides recently.",
	AlreadyInFaction = "You're already sworn to this faction.",
	RateLimited = "One moment…",
	NotLoaded = "Still loading your gem…",
	InvalidFaction = "That faction doesn't exist.",
}

function FactionSelect.Init(screen: ScreenGui, context)
	local player = Players.LocalPlayer
	local remote = ReplicatedStorage:WaitForChild("GemRemotes"):WaitForChild("RequestFactionChange") :: RemoteFunction

	local overlay = Theme.new("Frame", {
		Name = "FactionSelect",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 12, 40),
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 20,
		Parent = screen,
	})
	Theme.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 60, 150)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 25, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 70, 130)),
		}),
		Rotation = 30,
		Parent = overlay,
	})

	local content = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 520),
		BackgroundTransparency = 1,
		Parent = overlay,
	})
	local contentScale = Theme.new("UIScale", { Parent = content })

	local heading = Theme.label({
		Text = "Choose Your Allegiance",
		Font = Theme.Fonts.Title,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = content,
	})
	Theme.shimmer(heading, nil, 0.25, 0)
	Theme.label({
		Text = "Your faction decides where you spawn and which islands you fight for.",
		TextSize = 16,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = content,
	})

	local cards = Theme.new("Frame", {
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, 330),
		BackgroundTransparency = 1,
		Parent = content,
	}, { Theme.list(Enum.FillDirection.Horizontal, 28, Enum.HorizontalAlignment.Center) })

	local status = Theme.label({
		Text = "",
		TextSize = 16,
		TextColor3 = C.Warning,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 438),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = content,
	})

	local stay = Theme.button("Stay a Rogue Shard for now", C.Muted, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 468),
		Size = UDim2.fromOffset(280, 40),
		TextSize = 16,
		Parent = content,
	})

	local open = false
	local busy = false

	local function setOpen(value: boolean)
		open = value
		if value then
			status.Text = ""
			overlay.Visible = true
			overlay.BackgroundTransparency = 1
			contentScale.Scale = 0.9
			Theme.tween(overlay, 0.4, { BackgroundTransparency = 0.25 })
			Theme.tween(contentScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			Theme.tween(overlay, 0.25, { BackgroundTransparency = 1 })
			Theme.tween(contentScale, 0.25, { Scale = 0.9 })
			task.delay(0.25, function()
				if not open then
					overlay.Visible = false
				end
			end)
		end
	end
	context.OpenFactionSelect = function()
		setOpen(true)
	end

	local function choose(factionId: string)
		if busy then
			return
		end
		busy = true
		status.Text = "Swearing allegiance…"
		local ok, err, remaining = remote:InvokeServer(factionId)
		busy = false
		if ok then
			setOpen(false)
		else
			local message = ERROR_TEXT[err] or "Couldn't join that faction."
			if err == "Cooldown" and remaining and remaining > 0 then
				message ..= ` You can switch again in {Theme.formatDuration(remaining)}.`
			end
			status.Text = message
		end
	end

	for _, factionId in { "Guardians", "Dominion" } do
		local faction = GemConfig.Factions[factionId]
		local home = TerritoryConfig.Homes[factionId]

		local card = Theme.panel({
			Size = UDim2.fromOffset(300, 330),
			Parent = cards,
		})
		local cardScale = Theme.new("UIScale", { Parent = card })

		local header = Theme.new("Frame", {
			Size = UDim2.new(1, 0, 0, 96),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = card,
		}, { Theme.corner(14) })
		local h, s = faction.Color:ToHSV()
		Theme.shimmer(header, ColorSequence.new({
			ColorSequenceKeypoint.new(0, faction.Color),
			ColorSequenceKeypoint.new(0.5, Color3.fromHSV(h, s * 0.3, 1)),
			ColorSequenceKeypoint.new(1, faction.Color),
		}), 0.3, 25)

		-- Emblem: a glowing rhombus
		local emblem = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(44, 44),
			Rotation = 45,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = header,
		}, { Theme.corner(6) })
		local emblemStroke = Theme.stroke(faction.Color, 4, 0)
		emblemStroke.Parent = emblem

		Theme.label({
			Text = faction.DisplayName,
			Font = Theme.Fonts.Title,
			TextSize = 28,
			TextColor3 = faction.Color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 108),
			Size = UDim2.new(1, 0, 0, 32),
			Parent = card,
		})
		Theme.label({
			Text = BLURBS[factionId],
			TextSize = 15,
			TextColor3 = C.SubText,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(18, 146),
			Size = UDim2.new(1, -36, 0, 80),
			Parent = card,
		})
		Theme.label({
			Text = `Home base: {home.DisplayName}`,
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 230),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = card,
		})
		local join = Theme.button("Join", faction.Color, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -18),
			Size = UDim2.new(1, -48, 0, 46),
			TextSize = 22,
			Parent = card,
		})
		join.Activated:Connect(function()
			choose(factionId)
		end)

		card.MouseEnter:Connect(function()
			Theme.tween(cardScale, 0.2, { Scale = 1.03 }, Enum.EasingStyle.Back)
		end)
		card.MouseLeave:Connect(function()
			Theme.tween(cardScale, 0.2, { Scale = 1 })
		end)
	end

	stay.Activated:Connect(function()
		setOpen(false)
	end)

	-- Auto-open once for Rogues when their data first arrives.
	local prompted = false
	local function maybePrompt()
		if prompted or not player:GetAttribute(ATTR.DataLoaded) then
			return
		end
		prompted = true
		if player:GetAttribute(ATTR.Faction) == "Neutral" then
			task.delay(1.5, setOpen, true) -- let the loading screen fade first
		end
	end
	player:GetAttributeChangedSignal(ATTR.DataLoaded):Connect(maybePrompt)
	maybePrompt()
end

return FactionSelect
