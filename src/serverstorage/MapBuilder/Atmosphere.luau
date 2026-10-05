-- Atmosphere
-- Moonlit teal night: cool ambient light, a dense teal-violet atmosphere that
-- fades the distant spires and mountains into silhouettes, a starry sky
-- (engine stars, celestial bodies hidden in favour of our own moon), bloom
-- for the neon, and a gentle colour grade.

local Lighting = game:GetService("Lighting")

local Atmosphere = {}

local function ensure(className: string, name: string): any
	local existing = Lighting:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

function Atmosphere.Apply()
	-- Future lighting makes the neon and point lights glow properly; it can
	-- only be set from Studio (command bar / plugin), so this is best effort.
	pcall(function()
		(Lighting :: any).Technology = Enum.Technology.Future
	end)
	Lighting.ClockTime = 0.2
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(70, 92, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(96, 128, 150)
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35

	local atmosphere = ensure("Atmosphere", "GemWorldAtmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(88, 170, 178)
	atmosphere.Decay = Color3.fromRGB(70, 56, 120)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.8

	local sky = ensure("Sky", "GemWorldSky")
	sky.StarCount = 5000
	sky.CelestialBodiesShown = false

	local bloom = ensure("BloomEffect", "GemWorldBloom")
	bloom.Intensity = 0.9
	bloom.Size = 32
	bloom.Threshold = 1.15

	local grade = ensure("ColorCorrectionEffect", "GemWorldGrade")
	grade.TintColor = Color3.fromRGB(226, 240, 255)
	grade.Saturation = 0.18
	grade.Contrast = 0.1
	grade.Brightness = 0.02

	local rays = ensure("SunRaysEffect", "GemWorldRays")
	rays.Enabled = false
end

return Atmosphere
