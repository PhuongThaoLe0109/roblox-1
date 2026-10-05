-- RollReveal
-- The gem-opening animation:
--   1. A reel of gem cards spins horizontally and decelerates onto the result
--      (longer, tenser spins for rarer results; rare "teaser" cards fly past).
--   2. Reveal: screen flash in the gem's colours, rotating light rays, a glow
--      disc, the gem popping in, its name in a shimmering gradient, "1 in N",
--      and a NEW! badge or ×count.
-- Click anywhere to skip. Fast mode skips the reel.
-- RollReveal.Play(gemId, count, fast) yields until the reveal is done.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local GemArt = require(script.Parent:WaitForChild("GemArt"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Colors

local RollReveal = {}

local CARD_WIDTH = 116
local CARD_GAP = 10
local REEL_CARDS = 44
local RESULT_SLOT = 38

local root: Frame
local skipRequested = false
local busy = false

-- Picks a gem for a filler card, roughly following real odds but with a few
-- rare teasers so the reel looks exciting.
local function fillerGem(rng: Random): GemCatalog.Gem
	local list = GemCatalog.List
	if rng:NextNumber() < 0.12 then
		return list[rng:NextInteger(25, #list)] -- teaser
	end
	local u = rng:NextNumber()
	for i = #list, 1, -1 do
		u -= list[i].Probability * (if i > 1 then 3 else 1)
		if u < 0 then
			return list[i]
		end
	end
	return list[1]
end

local function card(gem: GemCatalog.Gem): Frame
	local frame = Theme.new("Frame", {
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_WIDTH + 24),
		BackgroundColor3 = C.PanelLight,
		BorderSizePixel = 0,
	}, { Theme.corner(12) })
	Theme.new("UIGradient", {
		Color = ColorSequence.new(gem.Color:Lerp(C.Panel, 0.65), C.Panel),
		Rotation = 90,
		Parent = frame,
	})
	local stroke = Theme.stroke(gem.Accent, 2, 0.2)
	stroke.Parent = frame
	local icon = GemArt.Icon(gem, CARD_WIDTH - 20)
	icon.Position = UDim2.fromOffset(10, 4)
	icon.Parent = frame
	Theme.label({
		Text = gem.Name,
		FontFace = Theme.Faces.Title,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 4, 1, -30),
		Size = UDim2.new(1, -8, 0, 16),
		Parent = frame,
	})
	return frame
end

local function waitOrSkip(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline and not skipRequested do
		task.wait()
	end
end

function RollReveal.Init(screen: ScreenGui)
	root = Theme.new("TextButton", {
		Name = "RollReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(18, 10, 36),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 60,
		Parent = screen,
	})
	;(root :: any).Activated:Connect(function()
		skipRequested = true
	end)
end

function RollReveal.IsBusy(): boolean
	return busy
end

function RollReveal.Play(gemId: string, count: number, fast: boolean?)
	local gem = GemCatalog.Get(gemId)
	if not gem or busy then
		return
	end
	busy = true
	skipRequested = false
	local tier = GemArt.Tier(gem)
	local rng = Random.new()

	for _, child in root:GetChildren() do
		child:Destroy()
	end
	root.Visible = true
	root.BackgroundTransparency = 1
	Theme.tween(root, 0.25, { BackgroundTransparency = 0.35 })
	Theme.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(60, 30, 90), Color3.fromRGB(10, 6, 24)),
		Rotation = 90,
		Parent = root,
	})

	----------------------------------------------------------------------------
	-- 1. Reel
	----------------------------------------------------------------------------
	if not fast then
		local window = Theme.panel({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(760, CARD_WIDTH + 52),
			ClipsDescendants = true,
			ZIndex = 61,
			Parent = root,
		})
		local strip = Theme.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 14),
			Size = UDim2.fromOffset(REEL_CARDS * (CARD_WIDTH + CARD_GAP), CARD_WIDTH + 24),
			Parent = window,
		}, { Theme.list(Enum.FillDirection.Horizontal, CARD_GAP) })
		for i = 1, REEL_CARDS do
			local c = card(if i == RESULT_SLOT then gem else fillerGem(rng))
			c.LayoutOrder = i
			c.Parent = strip
		end
		-- Centre marker
		local marker = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0, 4, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 65,
			Parent = window,
		})
		Theme.shimmer(marker, GemArt.Rainbow, 1.2, 90)

		-- Land the result card under the marker (with a small random offset).
		local slotCenter = (RESULT_SLOT - 1) * (CARD_WIDTH + CARD_GAP) + CARD_WIDTH / 2
		local jitter = rng:NextNumber(-CARD_WIDTH * 0.3, CARD_WIDTH * 0.3)
		local finalX = 380 - slotCenter + jitter
		local duration = 2.2 + tier * 0.6
		local spin = Theme.tween(strip, duration, { Position = UDim2.fromOffset(finalX, 14) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

		local started = os.clock()
		while os.clock() - started < duration and not skipRequested do
			task.wait()
		end
		spin:Cancel()
		strip.Position = UDim2.fromOffset(finalX, 14)
		waitOrSkip(0.25)
		Theme.tween(window, 0.2, { BackgroundTransparency = 1 })
		window:Destroy()
	end

	----------------------------------------------------------------------------
	-- 2. Reveal
	----------------------------------------------------------------------------
	skipRequested = false
	local center = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(520, 520),
		BackgroundTransparency = 1,
		ZIndex = 61,
		Parent = root,
	})

	-- Flash
	local flash = Theme.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = if tier >= 3 then 0 else 0.4,
		ZIndex = 70,
		Parent = root,
	})
	Theme.new("UIGradient", { Color = if tier >= 4 then GemArt.Rainbow else GemArt.Gradient(gem), Rotation = 35, Parent = flash })
	Theme.tween(flash, if tier >= 3 then 0.9 else 0.4, { BackgroundTransparency = 1 })

	-- Glow disc
	local glow = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = gem.Color,
		BackgroundTransparency = 0.2,
		ZIndex = 61,
		Parent = center,
	}, { Theme.round() })
	Theme.new("UIGradient", {
		Color = GemArt.Gradient(gem),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.85),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 0.85),
		}),
		Parent = glow,
	})
	Theme.tween(glow, 0.6, { Size = UDim2.fromOffset(200 + tier * 50, 200 + tier * 50) }, Enum.EasingStyle.Back)

	-- Rotating rays (more and longer for rarer gems)
	local rays = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 61,
		Parent = center,
	})
	local rayCount = 6 + tier * 3
	local rayLength = 150 + tier * 45
	for i = 1, rayCount do
		local ray = Theme.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(rayLength, 10 + tier * 2),
			Rotation = i / rayCount * 360,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = rays,
		})
		Theme.new("UIGradient", {
			Color = if tier >= 4 then GemArt.Rainbow else GemArt.Gradient(gem),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
	end
	local spinConnection = RunService.RenderStepped:Connect(function(dt)
		rays.Rotation += dt * (20 + tier * 12)
	end)

	-- The gem
	local icon = GemArt.Icon(gem, 200)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 62
	icon.Parent = center
	local iconScale = Theme.new("UIScale", { Scale = 0.1, Parent = icon })
	Theme.tween(iconScale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)

	-- Text
	Theme.headline({
		Text = gem.Name,
		TextSize = 56 + tier * 4,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.45, 150),
		Size = UDim2.fromOffset(900, 70),
		ZIndex = 63,
		Parent = root,
	}, if tier >= 4 then GemArt.Rainbow else GemArt.Gradient(gem), 0.5)
	Theme.label({
		Text = GemCatalog.FormatOdds(gem.Odds),
		FontFace = Theme.Faces.Odds,
		TextSize = 24,
		TextColor3 = if tier >= 3 then C.Gold else C.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.45, 216),
		Size = UDim2.fromOffset(900, 30),
		ZIndex = 63,
		Parent = root,
	})
	local badge = Theme.new("TextLabel", {
		Text = if count <= 1 then "NEW!" else `×{count}`,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = Color3.fromRGB(40, 25, 60),
		BackgroundColor3 = if count <= 1 then C.Gold else C.Lavender,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.45, 256),
		Size = UDim2.fromOffset(110, 32),
		ZIndex = 63,
		BorderSizePixel = 0,
		Parent = root,
	}, { Theme.round() })
	local badgeScale = Theme.new("UIScale", { Scale = 0, Parent = badge })
	task.delay(0.3, function()
		Theme.tween(badgeScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end)

	waitOrSkip(if fast then 0.7 else 1.2 + tier * 0.5)

	-- Fade out
	Theme.tween(root, 0.3, { BackgroundTransparency = 1 })
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") then
			Theme.tween(d, 0.25, { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 })
		elseif d:IsA("Frame") then
			Theme.tween(d, 0.25, { BackgroundTransparency = 1 })
		elseif d:IsA("UIStroke") then
			Theme.tween(d, 0.25, { Transparency = 1 })
		end
	end
	task.wait(0.3)
	spinConnection:Disconnect()
	root.Visible = false
	for _, child in root:GetChildren() do
		child:Destroy()
	end
	busy = false
end

return RollReveal
