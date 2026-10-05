-- GemArt
-- Draws gems entirely from UI frames and gradients (no image assets):
-- a faceted diamond in the gem's two colours with a shine, plus a glow ring
-- whose intensity follows rarity. Also provides the visual "tier" used to
-- scale effects (internal only — players just see "1 in N").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local GemArt = {}

GemArt.Rainbow = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 160)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 120)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(180, 255, 150)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(120, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(200, 150, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 160)),
})

-- 1..5 from odds: <1k, <100k, <10M, <1B, rarer.
function GemArt.Tier(gem: GemCatalog.Gem): number
	local odds = gem.Odds
	if odds < 1_000 then
		return 1
	elseif odds < 100_000 then
		return 2
	elseif odds < 10_000_000 then
		return 3
	elseif odds < 1_000_000_000 then
		return 4
	end
	return 5
end

function GemArt.Gradient(gem: GemCatalog.Gem): ColorSequence
	local h, s = gem.Color:ToHSV()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, gem.Color),
		ColorSequenceKeypoint.new(0.45, Color3.fromHSV(h, s * 0.35, 1)),
		ColorSequenceKeypoint.new(1, gem.Accent),
	})
end

-- Builds a gem icon inside a square holder. `owned = false` draws a
-- silhouette with a question mark.
function GemArt.Icon(gem: GemCatalog.Gem, size: number, owned: boolean?): Frame
	local isOwned = owned ~= false
	local tier = GemArt.Tier(gem)

	local holder = Theme.new("Frame", {
		Name = "GemIcon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
	})

	-- Soft glow behind the gem (stronger for rarer gems).
	if isOwned and tier >= 2 then
		local glow = Theme.new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.95, 0.95),
			BackgroundColor3 = gem.Color,
			BackgroundTransparency = 0.55 - tier * 0.06,
			BorderSizePixel = 0,
			Parent = holder,
		}, { Theme.round() })
		Theme.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 90,
			Parent = glow,
		})
	end

	local body = Theme.new("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.58, 0.58),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = holder,
	}, { Theme.corner(math.max(2, math.floor(size * 0.06))) })

	local fill = Theme.new("UIGradient", {
		Color = if isOwned then GemArt.Gradient(gem) else ColorSequence.new(Color3.fromRGB(70, 60, 95), Color3.fromRGB(45, 38, 65)),
		Rotation = 0,
		Parent = body,
	})
	local _ = fill

	-- Inner facet: a smaller, lighter diamond gives the cut-gem look.
	local facet = Theme.new("Frame", {
		Name = "Facet",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.55, 0.55),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = if isOwned then 0.55 else 0.85,
		BorderSizePixel = 0,
		Parent = body,
	}, { Theme.corner(math.max(1, math.floor(size * 0.03))) })
	Theme.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 0.9),
		}),
		Rotation = -45,
		Parent = facet,
	})

	-- Shine dot.
	if isOwned then
		Theme.new("Frame", {
			Name = "Shine",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.38, 0.32),
			Size = UDim2.fromScale(0.09, 0.09),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = holder,
		}, { Theme.round() })
	end

	local stroke = Theme.stroke(if isOwned then gem.Accent else Color3.fromRGB(110, 100, 140), math.max(1, size / 40) + (if isOwned then tier * 0.4 else 0), 0)
	stroke.Parent = body
	if isOwned and tier >= 4 then
		stroke.Color = Color3.new(1, 1, 1)
		Theme.shimmer(stroke, GemArt.Rainbow, 0.4)
	elseif isOwned and tier >= 3 then
		Theme.shimmer(stroke, GemArt.Gradient(gem), 0.35)
	end

	if not isOwned then
		Theme.label({
			Text = "?",
			Font = Theme.Fonts.Title,
			TextSize = math.floor(size * 0.32),
			TextColor3 = Color3.fromRGB(160, 150, 190),
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = holder,
		})
	end

	return holder
end

return GemArt
