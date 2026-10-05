--!strict
-- SkyConfig
-- Pastel day/night cycle. Time of day is derived from the shared server clock
-- (workspace:GetServerTimeNow()), so every client sees the same sky without the
-- server replicating lighting every frame.
--
-- Keyframes are sampled by ClockTime (0-24) and linearly blended.

local SkyConfig = {}

SkyConfig.CycleSeconds = 20 * 60 -- one full in-game day
SkyConfig.StartClockTime = 8 -- clock time when server time is 0 mod cycle

export type SkyKeyframe = {
	Time: number,
	Phase: string,
	AtmosphereColor: Color3,
	AtmosphereDecay: Color3,
	Haze: number,
	Density: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	Brightness: number,
	Tint: Color3, -- ColorCorrection tint
	CloudColor: Color3,
	CloudCover: number,
}

local rgb = Color3.fromRGB

SkyConfig.Keyframes = {
	{
		Time = 0,
		Phase = "Night",
		AtmosphereColor = rgb(110, 120, 210),
		AtmosphereDecay = rgb(70, 60, 140),
		Haze = 1.2,
		Density = 0.3,
		Ambient = rgb(70, 75, 130),
		OutdoorAmbient = rgb(90, 95, 160),
		Brightness = 1.2,
		Tint = rgb(205, 210, 255),
		CloudColor = rgb(150, 150, 220),
		CloudCover = 0.55,
	},
	{
		Time = 5,
		Phase = "Dawn",
		AtmosphereColor = rgb(200, 160, 230),
		AtmosphereDecay = rgb(130, 100, 190),
		Haze = 1.6,
		Density = 0.32,
		Ambient = rgb(120, 100, 150),
		OutdoorAmbient = rgb(150, 125, 175),
		Brightness = 1.6,
		Tint = rgb(240, 220, 255),
		CloudColor = rgb(225, 190, 235),
		CloudCover = 0.6,
	},
	{
		Time = 6.5,
		Phase = "Sunrise",
		AtmosphereColor = rgb(255, 190, 200),
		AtmosphereDecay = rgb(240, 170, 200),
		Haze = 1.8,
		Density = 0.33,
		Ambient = rgb(150, 120, 140),
		OutdoorAmbient = rgb(190, 160, 175),
		Brightness = 2,
		Tint = rgb(255, 235, 240),
		CloudColor = rgb(255, 215, 200),
		CloudCover = 0.55,
	},
	{
		Time = 9,
		Phase = "Morning",
		AtmosphereColor = rgb(200, 225, 255),
		AtmosphereDecay = rgb(240, 215, 240),
		Haze = 1.2,
		Density = 0.28,
		Ambient = rgb(140, 140, 160),
		OutdoorAmbient = rgb(175, 175, 195),
		Brightness = 2.6,
		Tint = rgb(250, 248, 255),
		CloudColor = rgb(255, 245, 240),
		CloudCover = 0.5,
	},
	{
		Time = 13,
		Phase = "Day",
		AtmosphereColor = rgb(185, 215, 255),
		AtmosphereDecay = rgb(255, 235, 245),
		Haze = 1,
		Density = 0.26,
		Ambient = rgb(145, 145, 165),
		OutdoorAmbient = rgb(185, 185, 200),
		Brightness = 3,
		Tint = rgb(255, 255, 255),
		CloudColor = rgb(255, 250, 245),
		CloudCover = 0.48,
	},
	{
		Time = 16.5,
		Phase = "Golden Hour",
		AtmosphereColor = rgb(255, 210, 190),
		AtmosphereDecay = rgb(250, 190, 210),
		Haze = 1.5,
		Density = 0.3,
		Ambient = rgb(150, 125, 135),
		OutdoorAmbient = rgb(195, 165, 170),
		Brightness = 2.4,
		Tint = rgb(255, 238, 230),
		CloudColor = rgb(255, 225, 200),
		CloudCover = 0.55,
	},
	{
		Time = 18,
		Phase = "Sunset",
		AtmosphereColor = rgb(250, 160, 205),
		AtmosphereDecay = rgb(170, 110, 200),
		Haze = 2,
		Density = 0.34,
		Ambient = rgb(130, 95, 140),
		OutdoorAmbient = rgb(175, 135, 180),
		Brightness = 1.8,
		Tint = rgb(255, 220, 240),
		CloudColor = rgb(255, 180, 210),
		CloudCover = 0.62,
	},
	{
		Time = 19.5,
		Phase = "Dusk",
		AtmosphereColor = rgb(180, 140, 230),
		AtmosphereDecay = rgb(100, 80, 170),
		Haze = 1.6,
		Density = 0.32,
		Ambient = rgb(95, 85, 140),
		OutdoorAmbient = rgb(125, 110, 170),
		Brightness = 1.4,
		Tint = rgb(225, 210, 255),
		CloudColor = rgb(200, 160, 230),
		CloudCover = 0.58,
	},
} :: { SkyKeyframe }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function SkyConfig.GetClockTime(serverTime: number): number
	local dayFraction = (serverTime % SkyConfig.CycleSeconds) / SkyConfig.CycleSeconds
	return (SkyConfig.StartClockTime + dayFraction * 24) % 24
end

-- Returns a blended keyframe for the given clock time (0-24).
function SkyConfig.Sample(clockTime: number): SkyKeyframe
	local frames = SkyConfig.Keyframes
	local count = #frames

	local prev, nextFrame = frames[count], frames[1]
	for i = 1, count do
		if frames[i].Time > clockTime then
			nextFrame = frames[i]
			prev = frames[if i == 1 then count else i - 1]
			break
		elseif i == count then
			prev = frames[count]
			nextFrame = frames[1]
		end
	end

	local span = (nextFrame.Time - prev.Time) % 24
	local t = if span > 0 then ((clockTime - prev.Time) % 24) / span else 0

	return {
		Time = clockTime,
		Phase = if t < 0.5 then prev.Phase else nextFrame.Phase,
		AtmosphereColor = prev.AtmosphereColor:Lerp(nextFrame.AtmosphereColor, t),
		AtmosphereDecay = prev.AtmosphereDecay:Lerp(nextFrame.AtmosphereDecay, t),
		Haze = lerp(prev.Haze, nextFrame.Haze, t),
		Density = lerp(prev.Density, nextFrame.Density, t),
		Ambient = prev.Ambient:Lerp(nextFrame.Ambient, t),
		OutdoorAmbient = prev.OutdoorAmbient:Lerp(nextFrame.OutdoorAmbient, t),
		Brightness = lerp(prev.Brightness, nextFrame.Brightness, t),
		Tint = prev.Tint:Lerp(nextFrame.Tint, t),
		CloudColor = prev.CloudColor:Lerp(nextFrame.CloudColor, t),
		CloudCover = lerp(prev.CloudCover, nextFrame.CloudCover, t),
	}
end

function SkyConfig.FormatClock(clockTime: number): string
	local hours = math.floor(clockTime)
	local minutes = math.floor((clockTime - hours) * 60)
	return string.format("%02d:%02d", hours, minutes)
end

for i = 2, #SkyConfig.Keyframes do
	assert(SkyConfig.Keyframes[i].Time > SkyConfig.Keyframes[i - 1].Time, "SkyConfig: keyframes must be sorted by Time")
end
table.freeze(SkyConfig.Keyframes)
table.freeze(SkyConfig)

return SkyConfig
