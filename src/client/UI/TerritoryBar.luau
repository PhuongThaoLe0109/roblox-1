-- TerritoryBar
--   * Top-centre row of 12 pips: colour = owning faction, dimmed + lock when
--     the island is above your rank, pulsing while contested.
--   * Capture meter under the pips while you stand on a capture pad.
--   * Cinematic zone banner when you arrive on a new island.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local TerritoryConfig = require(ReplicatedStorage:WaitForChild("TerritoryConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local ATTR = GemConfig.Attributes
local C = Theme.Colors
local NEUTRAL = Color3.fromRGB(235, 235, 245)

local TerritoryBar = {}

local function factionColor(factionId: string?): Color3
	local faction = factionId and GemConfig.Factions[factionId]
	return if faction then faction.Color else NEUTRAL
end

function TerritoryBar.Init(screen: ScreenGui)
	local player = Players.LocalPlayer
	local territoriesFolder: Instance? = nil

	----------------------------------------------------------------------------
	-- Pips
	----------------------------------------------------------------------------
	local bar = Theme.panel({
		Name = "TerritoryBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(12 * 30 + 24, 44),
		Parent = screen,
	})
	Theme.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = bar

	type Pip = { Frame: Frame, Stroke: UIStroke, Lock: TextLabel, Id: string }
	local pips: { Pip } = {}
	for index, info in TerritoryConfig.Territories do
		local frame = Theme.new("Frame", {
			Name = info.Id,
			LayoutOrder = index,
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = NEUTRAL,
			BorderSizePixel = 0,
			Parent = bar,
		}, { Theme.round() })
		local stroke = Theme.stroke(info.Accent, 2, 0)
		stroke.Parent = frame
		Theme.label({
			Text = tostring(index),
			Font = Theme.Fonts.Title,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(40, 30, 60),
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		})
		local lock = Theme.label({
			Text = "🔒",
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 2,
			Parent = frame,
		})
		pips[index] = { Frame = frame, Stroke = stroke, Lock = lock, Id = info.Id }
	end

	----------------------------------------------------------------------------
	-- Capture meter
	----------------------------------------------------------------------------
	local meter = Theme.panel({
		Name = "CaptureMeter",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(360, 60),
		Visible = false,
		Parent = screen,
	})
	Theme.padding(10, 14).Parent = meter
	local meterTitle = Theme.label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = meter,
	})
	local _, setMeter = Theme.progressBar({
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 12),
		Parent = meter,
	})

	----------------------------------------------------------------------------
	-- Zone banner
	----------------------------------------------------------------------------
	local banner = Theme.new("Frame", {
		Name = "ZoneBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.fromOffset(700, 110),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	local bannerTitle = Theme.label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 52,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 60),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		TextStrokeColor3 = Color3.fromRGB(60, 30, 80),
		Parent = banner,
	})
	local bannerGradient = Theme.shimmer(bannerTitle, nil, 0.3, 0)
	local bannerSub = Theme.label({
		Text = "",
		TextSize = 18,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, 24),
		TextTransparency = 1,
		TextWrapped = true,
		Parent = banner,
	})
	local _ = bannerGradient
	local bannerToken = 0

	local function showBanner(title: string, subtitle: string)
		bannerToken += 1
		local token = bannerToken
		bannerTitle.Text = string.upper(title)
		bannerSub.Text = subtitle
		bannerTitle.Position = UDim2.fromOffset(0, 12)
		Theme.tween(bannerTitle, 0.8, { TextTransparency = 0, TextStrokeTransparency = 0.5, Position = UDim2.fromOffset(0, 0) })
		Theme.tween(bannerSub, 1.2, { TextTransparency = 0.1 })
		task.delay(3.2, function()
			if token == bannerToken then
				Theme.tween(bannerTitle, 1, { TextTransparency = 1, TextStrokeTransparency = 1 })
				Theme.tween(bannerSub, 1, { TextTransparency = 1 })
			end
		end)
	end

	----------------------------------------------------------------------------
	-- Updates
	----------------------------------------------------------------------------
	local function territoryModel(id: string): Instance?
		if not territoriesFolder then
			local map = Workspace:FindFirstChild("Map")
			territoriesFolder = map and map:FindFirstChild("Territories")
		end
		return territoriesFolder and territoriesFolder:FindFirstChild(id)
	end

	local function refreshPips()
		local rank = player:GetAttribute(ATTR.Rank) or 1
		for index, pip in pips do
			local model = territoryModel(pip.Id)
			local owner = model and model:GetAttribute("Owner")
			local locked = rank < index
			pip.Frame.BackgroundColor3 = factionColor(if owner ~= "" then owner else nil)
			pip.Frame.BackgroundTransparency = if locked then 0.6 else 0
			pip.Lock.Visible = locked
		end
	end

	local function refreshMeter()
		local id = player:GetAttribute(ATTR.CaptureTerritory)
		local model = type(id) == "string" and id ~= "" and territoryModel(id)
		if not model then
			meter.Visible = false
			return
		end
		meter.Visible = true

		local myFaction = player:GetAttribute(ATTR.Faction)
		local owner = model:GetAttribute("Owner") or ""
		local capturer = model:GetAttribute("Capturer") or ""
		local progress = model:GetAttribute("Progress") or 0
		local contested = model:GetAttribute("Contested")
		local name = TerritoryConfig.ById[id].DisplayName

		local text
		if contested then
			text = `⚔ {name} is CONTESTED!`
		elseif owner == myFaction and capturer == myFaction and progress >= 100 then
			text = `💎 {name} is secured`
		elseif capturer == myFaction then
			text = `Capturing {name}… {math.floor(progress)}%`
		else
			text = `Neutralising {name}… {math.floor(progress)}%`
		end
		meterTitle.Text = text
		meterTitle.TextColor3 = if contested then C.Danger else C.Text
		setMeter(progress / 100, factionColor(if capturer ~= "" then capturer else nil))
	end

	-- Territory attributes change often; refresh on a light 10 Hz poll rather
	-- than wiring 48 attribute signals (and survive map streaming in late).
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		refreshPips()
		refreshMeter()

		-- Contested pips pulse
		local pulse = (math.sin(os.clock() * 8) + 1) / 2
		for _, pip in pips do
			local model = territoryModel(pip.Id)
			pip.Stroke.Thickness = if model and model:GetAttribute("Contested") then 2 + pulse * 2 else 2
		end
	end)

	local lastLocation = nil
	player:GetAttributeChangedSignal(ATTR.CurrentIsland):Connect(function()
		local location = player:GetAttribute(ATTR.CurrentIsland)
		if location == lastLocation or location == "" or location == nil then
			return
		end
		lastLocation = location
		local info = TerritoryConfig.ById[location]
		if info then
			showBanner(info.DisplayName, info.Description)
		elseif location == "Hub" then
			showBanner(TerritoryConfig.HubName, "The crossroads of every portal.")
		elseif location == "Home" then
			local faction = player:GetAttribute(ATTR.Faction)
			local home = faction and TerritoryConfig.Homes[faction]
			showBanner(home and home.DisplayName or "Home", "Safe ground. Rest, regroup, return.")
		end
	end)
end

return TerritoryBar
