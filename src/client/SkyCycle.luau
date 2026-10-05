-- SkyCycle
-- Animates the pastel day/night cycle locally from the shared server clock, so
-- every player sees the same sky with zero replication cost.
-- Exposes the current clock/phase for the HUD.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SkyConfig = require(ReplicatedStorage:WaitForChild("SkyConfig"))

local SkyCycle = {}

SkyCycle.ClockTime = SkyConfig.StartClockTime
SkyCycle.Phase = "Day"

local UPDATE_INTERVAL = 1 / 20 -- lighting changes slowly; 20 Hz is plenty

local function ensure(parent: Instance, className: string, name: string?): any
	local existing = if name then parent:FindFirstChild(name) else parent:FindFirstChildOfClass(className)
	if existing and existing:IsA(className) then
		return existing
	end
	local instance = Instance.new(className)
	if name then
		instance.Name = name
	end
	instance.Parent = parent
	return instance
end

function SkyCycle.Start()
	-- Create anything the baked map didn't provide (client-local copies are fine).
	local atmosphere = ensure(Lighting, "Atmosphere") :: Atmosphere
	local tint = ensure(Lighting, "ColorCorrectionEffect", "SkyTint") :: ColorCorrectionEffect
	local clouds = ensure(Workspace.Terrain, "Clouds") :: Clouds
	local sky = ensure(Lighting, "Sky") :: Sky
	sky.StarCount = math.max(sky.StarCount, 3000)

	local elapsed = UPDATE_INTERVAL
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0

		local clock = SkyConfig.GetClockTime(Workspace:GetServerTimeNow())
		local s = SkyConfig.Sample(clock)
		SkyCycle.ClockTime = clock
		SkyCycle.Phase = s.Phase

		Lighting.ClockTime = clock
		Lighting.Brightness = s.Brightness
		Lighting.Ambient = s.Ambient
		Lighting.OutdoorAmbient = s.OutdoorAmbient

		atmosphere.Color = s.AtmosphereColor
		atmosphere.Decay = s.AtmosphereDecay
		atmosphere.Haze = s.Haze
		atmosphere.Density = s.Density

		tint.TintColor = s.Tint
		tint.Saturation = 0.12 -- slightly richer, storybook colours
		tint.Contrast = 0.04

		clouds.Color = s.CloudColor
		clouds.Cover = s.CloudCover
	end)
end

function SkyCycle.IsNight(): boolean
	return SkyCycle.ClockTime < 5.5 or SkyCycle.ClockTime >= 19.5
end

return SkyCycle
