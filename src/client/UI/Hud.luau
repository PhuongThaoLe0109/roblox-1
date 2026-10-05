-- Hud
-- Top-left gem card (gem, faction, rank, essence, rank progress), quick
-- buttons (Faction / Map), and the top-right sky clock.
-- Everything is driven by Player attributes replicated by GemDataManager.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local ATTR = GemConfig.Attributes
local C = Theme.Colors

local Hud = {}

local PHASE_ICONS = {
	Night = "🌙",
	Dawn = "🌸",
	Sunrise = "🌅",
	Morning = "☀️",
	Day = "☀️",
	["Golden Hour"] = "✨",
	Sunset = "🌇",
	Dusk = "🌌",
}

function Hud.Init(screen: ScreenGui, context)
	local player = Players.LocalPlayer

	----------------------------------------------------------------------------
	-- Gem card
	----------------------------------------------------------------------------
	local card = Theme.panel({
		Name = "GemCard",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(330, 118),
		Parent = screen,
	})
	Theme.padding(12).Parent = card

	-- Diamond-shaped gem swatch with a sweeping highlight
	local swatchHolder = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.fromOffset(4, 6),
		Parent = card,
	})
	local swatch = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(42, 42),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = swatchHolder,
	}, { Theme.corner(8) })
	local swatchGradient = Theme.shimmer(swatch, nil, 0.5, 45)
	local swatchStroke = Theme.stroke(Color3.new(1, 1, 1), 2, 0)
	swatchStroke.Parent = swatch
	Theme.shimmer(swatchStroke, nil, 0.8)

	local info = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(80, 0),
		Size = UDim2.new(1, -80, 1, 0),
		Parent = card,
	}, { Theme.list(Enum.FillDirection.Vertical, 2) })

	local gemName = Theme.label({ Text = "…", Font = Theme.Fonts.Title, TextSize = 22, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = info })
	local factionLabel = Theme.label({ Text = "", Font = Theme.Fonts.Bold, TextSize = 14, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 2, Parent = info })
	local rankLabel = Theme.label({ Text = "", TextSize = 14, TextColor3 = C.SubText, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 3, Parent = info })
	local essenceLabel = Theme.label({ Text = "✦ 0", Font = Theme.Fonts.Title, TextSize = 18, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 4, Parent = info })

	local progressBar, setProgress = Theme.progressBar({ Size = UDim2.new(1, -4, 0, 8), LayoutOrder = 5, Parent = info })
	local progressText = Theme.label({
		Text = "",
		TextSize = 11,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, 0, 0, 12),
		LayoutOrder = 6,
		Parent = info,
	})
	local _ = progressBar

	----------------------------------------------------------------------------
	-- Quick buttons
	----------------------------------------------------------------------------
	local buttons = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 142),
		Size = UDim2.fromOffset(330, 40),
		Parent = screen,
	}, { Theme.list(Enum.FillDirection.Horizontal, 10) })

	local factionButton = Theme.button("⚑ Faction", C.Lavender, { Size = UDim2.fromOffset(150, 38), TextSize = 17, Parent = buttons })
	local mapButton = Theme.button("🗺 Map  [M]", C.Cyan, { Size = UDim2.fromOffset(150, 38), TextSize = 17, Parent = buttons })
	factionButton.Activated:Connect(function()
		context.OpenFactionSelect()
	end)
	mapButton.Activated:Connect(function()
		context.ToggleMap()
	end)

	----------------------------------------------------------------------------
	-- Sky clock (top right)
	----------------------------------------------------------------------------
	local clock = Theme.panel({
		Name = "Clock",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(190, 44),
		Parent = screen,
	})
	local clockLabel = Theme.label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = clock,
	})

	task.spawn(function()
		local SkyConfig = require(ReplicatedStorage:WaitForChild("SkyConfig"))
		while clock.Parent do
			local sky = context.SkyCycle
			local icon = PHASE_ICONS[sky.Phase] or "✨"
			clockLabel.Text = `{icon}  {SkyConfig.FormatClock(sky.ClockTime)} · {sky.Phase}`
			task.wait(0.5)
		end
	end)

	----------------------------------------------------------------------------
	-- Data binding
	----------------------------------------------------------------------------
	local shownEssence = 0
	local essenceTarget = 0
	local counting = false

	local function animateEssence()
		if counting then
			return
		end
		counting = true
		task.spawn(function()
			while math.abs(shownEssence - essenceTarget) >= 1 do
				shownEssence += (essenceTarget - shownEssence) * 0.25
				essenceLabel.Text = "✦ " .. Theme.formatNumber(shownEssence)
				task.wait(1 / 30)
			end
			shownEssence = essenceTarget
			essenceLabel.Text = "✦ " .. Theme.formatNumber(shownEssence)
			counting = false
		end)
	end

	local function refresh()
		local gemType = player:GetAttribute(ATTR.GemType)
		local gem = gemType and GemConfig.GemTypes[gemType]
		gemName.Text = if gem then gem.DisplayName else "Awakening…"
		if gem then
			local h, s, v = gem.Color:ToHSV()
			swatchGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, gem.Color),
				ColorSequenceKeypoint.new(0.45, Color3.fromHSV(h, s * 0.25, 1)),
				ColorSequenceKeypoint.new(0.55, Color3.fromHSV(h, s * 0.25, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromHSV(h, s, v * 0.75)),
			})
		end

		local factionId = player:GetAttribute(ATTR.Faction)
		local faction = factionId and GemConfig.Factions[factionId]
		factionLabel.Text = if faction then faction.DisplayName else ""
		factionLabel.TextColor3 = if faction then faction.Color else C.SubText

		local rank = player:GetAttribute(ATTR.Rank) or 1
		local rankInfo = GemConfig.Ranks[rank]
		rankLabel.Text = `Rank {rank}/{#GemConfig.Ranks} · {rankInfo and rankInfo.Name or "?"}`

		local lifetime = player:GetAttribute(ATTR.LifetimeEssence) or 0
		local nextRank = GemConfig.Ranks[rank + 1]
		if nextRank and rankInfo then
			local span = nextRank.EssenceRequired - rankInfo.EssenceRequired
			setProgress((lifetime - rankInfo.EssenceRequired) / span, faction and faction.Color or C.Pink)
			progressText.Text = `{Theme.formatNumber(lifetime)} / {Theme.formatNumber(nextRank.EssenceRequired)} to {nextRank.Name}`
		else
			setProgress(1, C.Gold)
			progressText.Text = "Maximum rank reached!"
		end

		essenceTarget = player:GetAttribute(ATTR.CrystalEssence) or 0
		animateEssence()
	end

	for _, name in { ATTR.GemType, ATTR.Faction, ATTR.Rank, ATTR.CrystalEssence, ATTR.LifetimeEssence } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()
end

return Hud
