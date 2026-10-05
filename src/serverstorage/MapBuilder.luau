-- MapBuilder (ServerStorage)
-- Procedurally builds the world from TerritoryConfig. Intended to be run ONCE
-- in Edit mode to bake the map into the place file:
--
--   Studio command bar:
--     require(game.ServerStorage.MapBuilder).Build()
--   To throw away the current map and regenerate:
--     require(game.ServerStorage.MapBuilder).Build({ Rebuild = true })
--
-- At game start the server only calls Build() as a fallback when Workspace.Map
-- is missing (e.g. an unbaked test place); an existing map is never touched.
--
-- Creates:
--   Workspace.Map
--     Hub                 neutral plaza, Rogue spawn, portals to island 1 / home
--     Homes/<FactionId>   faction home islands, team spawns, portal to hub
--     Territories/<Id>    big island: themed landmarks, scenery, CapturePoint,
--                         Beacon, Arrival point, ReturnPortal, ForwardPortal
-- plus Terrain water/sea floor, Terrain clouds and base lighting effects
-- (the client's SkyCycle animates them).
--
-- If Workspace.Map already exists (a hand-built map), Build() leaves it alone,
-- so artists can replace this greybox without touching code. A hand-built map
-- must keep the same names: Territories/<Id>/{CapturePoint, Arrival}, Hub/Arrival,
-- Homes/<FactionId>/Arrival, and portal parts tagged "Portal" with the
-- attributes described in buildPortal().

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local TerritoryConfig = require(ReplicatedStorage:WaitForChild("TerritoryConfig"))

local MapBuilder = {}

local NEUTRAL_COLOR = Color3.fromRGB(235, 235, 245)
local SAND = Color3.fromRGB(240, 225, 185)
local GREEN = Color3.fromRGB(70, 140, 80)
local DARK_GREEN = Color3.fromRGB(45, 105, 70)
local BASE_RADIUS = 70 -- prop layouts are authored for this radius and scaled up
local DENSITY = 2.5 -- prop count multiplier for the larger islands

--------------------------------------------------------------------------------
-- Primitive helpers (all parts anchored)
--------------------------------------------------------------------------------

local function newPart(parent: Instance, name: string, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

local function block(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	return newPart(parent, name, {
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function wedge(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

-- Flat disc whose top face is at topCenter.Y.
local function disc(parent: Instance, name: string, topCenter: Vector3, radius: number, height: number, color: Color3, material: Enum.Material?): Part
	return newPart(parent, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(topCenter - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

-- Upright cylinder standing on basePosition.
local function column(parent: Instance, name: string, basePosition: Vector3, radius: number, height: number, color: Color3, material: Enum.Material?): Part
	return disc(parent, name, basePosition + Vector3.new(0, height, 0), radius, height, color, material)
end

local function ball(parent: Instance, name: string, position: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	return newPart(parent, name, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(position),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function addLight(part: BasePart, color: Color3, range: number, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1
	light.Parent = part
end

-- Built-in engine texture (no external asset needed).
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- Glittering gradient sparkles: accent -> white -> soft pink, fading out.
local function sparkle(part: BasePart, color: Color3, rate: number?, size: number?, spread: number?)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = SPARKLE_TEXTURE
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 230)),
	})
	local s = size or 0.8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, s),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rate = rate or 6
	emitter.Lifetime = NumberRange.new(1.2, 2.4)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.SpreadAngle = Vector2.new(spread or 180, spread or 180)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Parent = part
	return emitter
end

-- Decorative motion is animated client-side (AmbientFX) so it is perfectly
-- smooth and costs no replication. Only use on non-collidable parts.
local function animate(part: BasePart, kind: "Spin" | "Float")
	part.CanCollide = false
	CollectionService:AddTag(part, kind)
end

local function newModel(parent: Instance?, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function newFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function shade(color: Color3, factor: number): Color3
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

local function count(n: number): number
	return math.max(1, math.round(n * DENSITY))
end

--------------------------------------------------------------------------------
-- Local placement frame
-- Origin at island centre (ground level), -Z points at the hub.
-- Polar(r, deg): r in BASE_RADIUS units (scaled to the real island),
-- deg 0 = toward hub (return portal lane), 180 = away (forward portal lane).
--------------------------------------------------------------------------------

local FREE_ARCS = { { 20, 160 }, { 200, 340 } }

type Frame = {
	Center: Vector3,
	Scale: number,
	Polar: (r: number, deg: number, y: number?) -> CFrame,
	Absolute: (r: number, deg: number, y: number?) -> CFrame,
	RandomFree: (rng: Random, rMin: number, rMax: number) -> CFrame,
}

local function makeFrame(center: Vector3, radius: number): Frame
	local towardHub = if center.Magnitude > 1 then CFrame.lookAt(center, Vector3.zero) else CFrame.new(center)
	local scale = radius / BASE_RADIUS
	local frame = {} :: Frame
	frame.Center = center
	frame.Scale = scale
	frame.Absolute = function(r: number, deg: number, y: number?): CFrame
		local a = math.rad(deg)
		local offset = Vector3.new(math.sin(a) * r, y or 0, -math.cos(a) * r)
		-- Each placed CFrame faces the island centre (-Z inward, +Z out to sea).
		return towardHub * CFrame.new(offset) * CFrame.Angles(0, math.pi - a, 0)
	end
	frame.Polar = function(r: number, deg: number, y: number?): CFrame
		return frame.Absolute(r * scale, deg, y)
	end
	frame.RandomFree = function(rng: Random, rMin: number, rMax: number): CFrame
		local arc = FREE_ARCS[rng:NextInteger(1, #FREE_ARCS)]
		return frame.Polar(rng:NextNumber(rMin, rMax), rng:NextNumber(arc[1], arc[2]))
	end
	return frame
end

--------------------------------------------------------------------------------
-- Island body: sandy beach skirt reaching the sea floor, raised ground on top.
--------------------------------------------------------------------------------

local function buildIsland(parent: Instance, center: Vector3, radius: number, ground: Color3, material: Enum.Material)
	local beach = disc(parent, "Beach", center + Vector3.new(0, -2.5, 0), radius + 22, 28, SAND, Enum.Material.Sand)
	beach:SetAttribute("IsGround", true)
	local top = disc(parent, "Ground", center, radius, 3, ground, material)
	top:SetAttribute("IsGround", true)
	disc(parent, "Rim", center + Vector3.new(0, -0.4, 0), radius + 1.2, 2.4, shade(ground, 0.78), material)
end

--------------------------------------------------------------------------------
-- Scenery: palms / bushes for lush islands, rocks for barren ones, rim hills.
--------------------------------------------------------------------------------

local function palm(parent: Instance, base: Vector3, height: number, rng: Random)
	local root = CFrame.new(base)
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		* CFrame.Angles(math.rad(rng:NextNumber(4, 14)), 0, 0)
	local segment = height / 4
	local cf = root
	for s = 0, 3 do
		local width = 1.8 - s * 0.25
		block(parent, "PalmTrunk", cf * CFrame.new(0, segment / 2, 0), Vector3.new(width, segment + 0.2, width), Color3.fromRGB(120, 90, 70), Enum.Material.Wood)
		cf = cf * CFrame.new(0, segment, 0) * CFrame.Angles(math.rad(5), 0, 0)
	end
	for leaf = 0, 6 do
		local leafCf = cf * CFrame.Angles(0, leaf * math.pi * 2 / 7, 0) * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0, -4.5)
		block(parent, "PalmLeaf", leafCf, Vector3.new(2.6, 0.4, 9), DARK_GREEN, Enum.Material.Grass)
	end
	ball(parent, "Coconuts", (cf * CFrame.new(0, -0.6, 0)).Position, 2, Color3.fromRGB(110, 80, 50))
end

local function scenery(model: Model, frame: Frame, info: any, rng: Random)
	-- Rolling hills hugging the rim.
	for i = 1, count(4) do
		local cf = frame.RandomFree(rng, 56, 68)
		ball(model, "Hill", cf.Position - Vector3.new(0, rng:NextNumber(8, 14), 0), rng:NextNumber(26, 46), shade(info.Ground, rng:NextNumber(0.82, 0.95)), info.GroundMaterial)
	end

	if info.Lush then
		for i = 1, count(6) do
			local cf = frame.RandomFree(rng, 34, 68)
			palm(model, cf.Position, rng:NextNumber(14, 24), rng)
		end
		for i = 1, count(8) do
			local cf = frame.RandomFree(rng, 25, 66)
			ball(model, "Bush", cf.Position + Vector3.new(0, 1, 0), rng:NextNumber(4, 8), if rng:NextNumber() < 0.5 then GREEN else DARK_GREEN, Enum.Material.Grass)
		end
	else
		for i = 1, count(7) do
			local cf = frame.RandomFree(rng, 25, 68)
			local s = rng:NextNumber(3, 9)
			block(model, "Rock", cf * CFrame.new(0, s * 0.3, 0) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 3), rng:NextNumber(0, 1)), Vector3.new(s, s * 0.7, s * 0.9), shade(info.Ground, 0.7), Enum.Material.Rock)
		end
	end

	-- Sea stacks just off the beach.
	for i = 1, 3 do
		local cf = frame.RandomFree(rng, 82, 88)
		local h = rng:NextNumber(14, 26)
		block(model, "SeaStack", cf * CFrame.new(0, h / 2 - 6, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-10, 10))), Vector3.new(6, h, 7), Color3.fromRGB(190, 135, 130), Enum.Material.Rock)
	end
end

--------------------------------------------------------------------------------
-- Themed landmarks
--------------------------------------------------------------------------------

type PropBuilder = (model: Model, frame: Frame, info: any, rng: Random) -> ()

local PROPS: { [string]: PropBuilder } = {}

-- Tidecrest Sanctum: a pink cliff with a giant seated guardian carved in its
-- face (arms resting on knees, not holding anything), a lighthouse on top and a
-- stilt house on a ledge beside it.
PROPS.Temple = function(model, frame, info, rng)
	local cliff = Color3.fromRGB(205, 150, 145)
	local cliffDark = shade(cliff, 0.8)
	local moss = Color3.fromRGB(110, 150, 80)
	local anchor = frame.Polar(48, 140)

	-- Cliff mass (stepped so it reads as a slope from the side)
	block(model, "Cliff", anchor * CFrame.new(0, 22, 18), Vector3.new(90, 44, 50), cliffDark, Enum.Material.Rock)
	block(model, "CliffUpper", anchor * CFrame.new(-8, 52, 26), Vector3.new(70, 20, 36), cliffDark, Enum.Material.Rock)
	wedge(model, "CliffSlope", anchor * CFrame.new(-30, 52, -6) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(36, 20, 30), cliffDark, Enum.Material.Rock)
	block(model, "CliffMoss", anchor * CFrame.new(-8, 62.4, 26), Vector3.new(70, 1, 36), moss, Enum.Material.Grass)

	-- Seated guardian carved into the front face
	local body = anchor * CFrame.new(10, 0, -8)
	block(model, "GuardianLegs", body * CFrame.new(0, 7, -6), Vector3.new(26, 14, 18), cliff, Enum.Material.Rock)
	block(model, "GuardianTorso", body * CFrame.new(0, 28, 2), Vector3.new(22, 30, 14), cliff, Enum.Material.Rock)
	ball(model, "GuardianHead", (body * CFrame.new(0, 50, 2)).Position, 18, cliff, Enum.Material.Rock)
	for _, side in { -1, 1 } do
		block(model, "GuardianArm", body * CFrame.new(side * 14, 22, -4) * CFrame.Angles(math.rad(-35), 0, 0), Vector3.new(6, 22, 6), cliff, Enum.Material.Rock)
		ball(model, "GuardianHair", (body * CFrame.new(side * 9, 52, 6)).Position, 13, cliffDark, Enum.Material.Rock)
	end
	ball(model, "GuardianHairTop", (body * CFrame.new(0, 58, 6)).Position, 14, cliffDark, Enum.Material.Rock)
	-- Rhombus mark on the forehead (deliberately not a star)
	sparkle(block(model, "GuardianMark", body * CFrame.new(0, 53, -6.6) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(3, 3, 0.6), info.Accent, Enum.Material.Neon), info.Accent, 8)
	-- Temple door between the guardian's feet
	sparkle(block(model, "TempleDoor", body * CFrame.new(0, 7, -15.2) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(8, 8, 0.4), info.Accent, Enum.Material.Neon), info.Accent, 10, 1.2)

	-- Lighthouse on the cliff top
	local lighthouseBase = (anchor * CFrame.new(-25, 62.4, 30)).Position
	column(model, "Lighthouse", lighthouseBase, 3.5, 24, Color3.fromRGB(245, 245, 240), Enum.Material.Concrete)
	column(model, "LighthouseBand", lighthouseBase + Vector3.new(0, 10, 0), 3.6, 3, Color3.fromRGB(80, 110, 160), Enum.Material.Concrete)
	local lamp = column(model, "LighthouseLamp", lighthouseBase + Vector3.new(0, 24, 0), 3, 4, Color3.fromRGB(255, 240, 180), Enum.Material.Neon)
	addLight(lamp, Color3.fromRGB(255, 235, 170), 60, 2)
	block(model, "Cottage", CFrame.new(lighthouseBase) * CFrame.new(10, 4, 0), Vector3.new(12, 8, 9), Color3.fromRGB(235, 230, 220), Enum.Material.WoodPlanks)

	-- Stilt house on a ledge to the guardian's right
	local ledge = anchor * CFrame.new(-34, 0, -14)
	block(model, "Ledge", ledge * CFrame.new(0, 9, 0), Vector3.new(22, 18, 18), cliffDark, Enum.Material.Rock)
	for _, x in { -8, 8 } do
		block(model, "Stilt", ledge * CFrame.new(x, 21, -6), Vector3.new(1, 6, 1), Color3.fromRGB(110, 80, 60), Enum.Material.Wood)
	end
	block(model, "HouseDeck", ledge * CFrame.new(0, 24.5, -3), Vector3.new(22, 1, 18), Color3.fromRGB(150, 110, 80), Enum.Material.WoodPlanks)
	block(model, "House", ledge * CFrame.new(0, 30, 0), Vector3.new(16, 10, 12), Color3.fromRGB(245, 240, 230), Enum.Material.WoodPlanks)
	wedge(model, "HouseRoof", ledge * CFrame.new(0, 37, 0), Vector3.new(18, 4, 14), Color3.fromRGB(90, 70, 70), Enum.Material.Slate)
	local window = block(model, "HouseWindow", ledge * CFrame.new(0, 30, -6.1), Vector3.new(6, 3, 0.2), Color3.fromRGB(255, 220, 150), Enum.Material.Neon)
	addLight(window, Color3.fromRGB(255, 210, 150), 16)
	-- Stairs down from the deck
	for step = 0, 11 do
		block(model, "Stair", ledge * CFrame.new(12 + step * 1.6, 23 - step * 2, -8), Vector3.new(1.6, 0.6, 4), Color3.fromRGB(150, 110, 80), Enum.Material.WoodPlanks)
	end

	-- A-frame rock arch on the beach (sea stack pair)
	local arch = frame.Polar(64, 230)
	block(model, "ArchRockL", arch * CFrame.new(-4, 10, 0) * CFrame.Angles(0, 0, math.rad(-14)), Vector3.new(6, 22, 6), cliff, Enum.Material.Rock)
	block(model, "ArchRockR", arch * CFrame.new(4, 10, 0) * CFrame.Angles(0, 0, math.rad(14)), Vector3.new(6, 22, 6), cliff, Enum.Material.Rock)
end

PROPS.Town = function(model, frame, info, rng)
	local palette = {
		Color3.fromRGB(250, 200, 120),
		Color3.fromRGB(140, 200, 230),
		Color3.fromRGB(240, 150, 150),
		Color3.fromRGB(180, 230, 160),
		Color3.fromRGB(230, 220, 250),
	}
	for i = 1, count(6) do
		local cf = frame.RandomFree(rng, 34, 60)
		local w, d, h = rng:NextNumber(12, 18), rng:NextNumber(12, 16), rng:NextNumber(10, 18)
		local color = palette[(i - 1) % #palette + 1]
		block(model, "House", cf * CFrame.new(0, h / 2, 0), Vector3.new(w, h, d), color, Enum.Material.WoodPlanks)
		wedge(model, "Roof", cf * CFrame.new(0, h + 2.5, -d / 4), Vector3.new(w + 1, 5, d / 2 + 0.5), shade(color, 0.6))
		wedge(model, "Roof", cf * CFrame.new(0, h + 2.5, d / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(w + 1, 5, d / 2 + 0.5), shade(color, 0.6))
		block(model, "Door", cf * CFrame.new(0, 3, -d / 2 - 0.05), Vector3.new(3, 6, 0.2), shade(color, 0.5), Enum.Material.Wood)
	end
	-- Boardwalk ring around the plaza
	for deg = 0, 345, 15 do
		block(model, "Boardwalk", frame.Polar(26, deg) * CFrame.new(0, 0.3, 0), Vector3.new(16, 0.6, 7), Color3.fromRGB(150, 110, 75), Enum.Material.WoodPlanks)
	end
	-- Pier out into the sea
	local pier = frame.Polar(70, 110)
	block(model, "Pier", pier * CFrame.new(0, -1, 18), Vector3.new(10, 1, 50), Color3.fromRGB(150, 110, 75), Enum.Material.WoodPlanks)
	for i = 1, count(3) do
		local cf = frame.RandomFree(rng, 22, 32)
		column(model, "LampPost", cf.Position, 0.4, 10, Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
		local lamp = ball(model, "Lamp", cf.Position + Vector3.new(0, 10.8, 0), 1.8, info.Accent, Enum.Material.Neon)
		addLight(lamp, info.Accent, 18)
	end
	-- Ferris wheel landmark
	local wheel = frame.Polar(55, 250)
	for spoke = 0, 11 do
		local a = spoke * math.pi / 6
		block(model, "WheelSpoke", wheel * CFrame.new(0, 32, 0) * CFrame.Angles(0, 0, a) * CFrame.new(0, 12, 0), Vector3.new(0.8, 24, 0.8), Color3.fromRGB(240, 240, 250), Enum.Material.Metal)
		ball(model, "WheelCar", (wheel * CFrame.new(math.cos(a) * 24, 32 + math.sin(a) * 24, 0)).Position, 4, palette[spoke % #palette + 1])
	end
	block(model, "WheelLegs", wheel * CFrame.new(0, 16, 0), Vector3.new(4, 32, 4), Color3.fromRGB(200, 200, 215), Enum.Material.Metal)
end

PROPS.Garden = function(model, frame, info, rng)
	local hedge = Color3.fromRGB(60, 120, 60)
	local marble = Color3.fromRGB(225, 215, 220)
	-- Walled garden: hedge ring with gaps on both portal lanes
	for _, arc in FREE_ARCS do
		for deg = arc[1], arc[2], 4 do
			block(model, "Hedge", frame.Polar(50, deg) * CFrame.new(0, 4, 0), Vector3.new(10, 8, 4), hedge, Enum.Material.Grass)
		end
	end
	local f = frame.Polar(35, 120).Position
	column(model, "FountainBasin", f, 14, 3, marble, Enum.Material.Marble)
	disc(model, "FountainWater", f + Vector3.new(0, 3.1, 0), 12.5, 0.5, Color3.fromRGB(150, 220, 255), Enum.Material.Glass).Transparency = 0.3
	column(model, "FountainTier", f, 6, 9, marble, Enum.Material.Marble)
	local spout = ball(model, "FountainSpout", f + Vector3.new(0, 11, 0), 5, info.Accent, Enum.Material.Glass)
	addLight(spout, info.Accent, 30)
	sparkle(spout, info.Accent, 14, 1.2)
	animate(spout, "Float")
	for i = 1, count(10) do
		local cf = frame.RandomFree(rng, 24, 66)
		ball(model, "Thorns", cf.Position + Vector3.new(0, 2, 0), rng:NextNumber(5, 9), Color3.fromRGB(70, 110, 60), Enum.Material.Grass)
		ball(model, "Blossom", cf.Position + Vector3.new(rng:NextNumber(-2, 2), 5.5, rng:NextNumber(-2, 2)), 2.4, info.Accent)
	end
	for _, deg in { 0, 180 } do
		local arch = frame.Polar(50, deg)
		block(model, "ArchL", arch * CFrame.new(-8, 8, 0), Vector3.new(3, 16, 3), marble, Enum.Material.Marble)
		block(model, "ArchR", arch * CFrame.new(8, 8, 0), Vector3.new(3, 16, 3), marble, Enum.Material.Marble)
		block(model, "ArchTop", arch * CFrame.new(0, 17, 0), Vector3.new(19, 3, 3), marble, Enum.Material.Marble)
	end
end

PROPS.Battlefield = function(model, frame, info, rng)
	for i = 1, count(6) do
		local cf = frame.RandomFree(rng, 30, 64)
		local size = rng:NextNumber(10, 22)
		ball(model, "GiantBerry", cf.Position + Vector3.new(0, size * 0.4, 0), size, info.Accent)
		ball(model, "BerryLeaf", cf.Position + Vector3.new(0, size * 0.9, 0), size * 0.45, Color3.fromRGB(70, 150, 60), Enum.Material.Grass)
	end
	for i = 1, count(14) do
		local cf = frame.RandomFree(rng, 22, 66)
		local tilt = CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-25, 25)))
		block(model, "Blade", cf * tilt * CFrame.new(0, 3, 0), Vector3.new(0.5, 7, 1.4), Color3.fromRGB(190, 195, 205), Enum.Material.Metal)
		block(model, "Hilt", cf * tilt * CFrame.new(0, 6.6, 0), Vector3.new(0.6, 0.6, 3), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	end
	-- Crumbled stone stairway at the back
	local stairs = frame.Polar(55, 220)
	for step = 0, 9 do
		block(model, "RuinStep", stairs * CFrame.new(0, step * 1.5 + 0.75, step * 3), Vector3.new(20, 1.5, 3), Color3.fromRGB(200, 195, 185), Enum.Material.Cobblestone)
	end
	column(model, "RuinPillar", (stairs * CFrame.new(-11, 15, 28)).Position, 2, 14, Color3.fromRGB(200, 195, 185), Enum.Material.Cobblestone)
end

PROPS.Jungle = function(model, frame, info, rng)
	local rock = Color3.fromRGB(60, 90, 100)
	local base = frame.Polar(40, 140)
	-- Three terraces, each smaller and higher
	local tiers = { { 34, 12 }, { 25, 24 }, { 16, 38 } }
	for i, tier in tiers do
		local radius, top = tier[1], tier[2]
		disc(model, "Terrace" .. i, base.Position + Vector3.new(0, top, 0), radius, top, rock, Enum.Material.Rock)
		disc(model, "TerraceMoss" .. i, base.Position + Vector3.new(0, top + 0.6, 0), radius - 0.5, 0.6, DARK_GREEN, Enum.Material.Grass)
		-- Glowing crystal arch windows set into each terrace face (facing the island centre)
		for _, offset in { -25, 0, 25 } do
			local face = CFrame.new(base.Position) * CFrame.Angles(0, math.rad(offset), 0)
			local towardCenter = CFrame.lookAt(base.Position, frame.Center) * CFrame.Angles(0, math.rad(offset), 0)
			local window = towardCenter * CFrame.new(0, top - 6, -radius + 0.6)
			local glass = block(model, "CrystalWindow", window, Vector3.new(7, 9, 1), info.Accent, Enum.Material.Glass)
			glass.Transparency = 0.15
			ball(model, "CrystalWindowTop", (window * CFrame.new(0, 4.5, 0)).Position, 7, info.Accent, Enum.Material.Glass).Transparency = 0.15
			addLight(glass, info.Accent, 14)
			sparkle(glass, info.Accent, 3)
			local _ = face
		end
	end
	-- Waterfall of light pouring from the top terrace into a pool
	local towardCenter = CFrame.lookAt(base.Position, frame.Center)
	local fall = block(model, "Waterfall", towardCenter * CFrame.new(10, 19, -33), Vector3.new(6, 38, 1.5), Color3.fromRGB(120, 230, 255), Enum.Material.Neon)
	fall.Transparency = 0.25
	fall.CanCollide = false
	sparkle(fall, Color3.fromRGB(160, 240, 255), 30, 1, 40)
	local poolPos = (towardCenter * CFrame.new(10, 0, -40)).Position
	disc(model, "Pool", poolPos + Vector3.new(0, 0.3, 0), 10, 0.5, Color3.fromRGB(110, 210, 240), Enum.Material.Glass).Transparency = 0.2
	-- Crystal arches over the paths
	for i = 1, count(2) do
		local cf = frame.RandomFree(rng, 30, 60)
		for seg = 0, 8 do
			local a = seg / 8 * math.pi
			block(model, "CrystalArch", cf * CFrame.new(math.cos(a) * 9, math.sin(a) * 9, 0) * CFrame.Angles(0, 0, a), Vector3.new(1.6, 3.6, 2), info.Accent, Enum.Material.Glass)
		end
	end
end

-- Cloud Colosseum: broken amphitheatre with tiered seating, a sloped canopy
-- with a hexagonal window, crystal obelisks and pink clouds below. The
-- amphitheatre sits on the side arc so both portal lanes stay open.
PROPS.Colosseum = function(model, frame, info, rng)
	local stone = Color3.fromRGB(150, 110, 125)
	local seat = Color3.fromRGB(120, 85, 100)
	-- Tiered seating along the back arc
	for row = 0, 7 do
		local r = 46 + row * 2.2
		for deg = 215, 325, 7 do
			block(model, "Seating", frame.Polar(r, deg) * CFrame.new(0, row * 2.4 + 1.2, 0), Vector3.new(14, 2.4, 5), if row % 2 == 0 then seat else stone, Enum.Material.Slate)
		end
	end
	-- Canopy: two sloped panels meeting at a ridge, hexagonal window
	local canopy = frame.Polar(60, 270)
	wedge(model, "CanopyL", canopy * CFrame.new(-14, 30, 0) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(26, 20, 28), Color3.fromRGB(130, 120, 125), Enum.Material.Slate)
	wedge(model, "CanopyR", canopy * CFrame.new(14, 30, 0) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(26, 20, 28), Color3.fromRGB(130, 120, 125), Enum.Material.Slate)
	local hex = newPart(model, "HexWindow", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 10, 10),
		CFrame = canopy * CFrame.new(0, 26, -2.5) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(255, 225, 235),
		Material = Enum.Material.Neon,
	})
	addLight(hex, info.Accent, 30)
	-- Hexagon emblem hovering over the ridge
	local emblem = block(model, "Emblem", canopy * CFrame.new(0, 46, 0) * CFrame.Angles(0, 0, math.rad(30)), Vector3.new(6, 6, 1), shade(info.Accent, 0.7), Enum.Material.Neon)
	sparkle(emblem, info.Accent, 10, 1.4)
	animate(emblem, "Spin")
	-- Crystal obelisks
	for _, deg in { 120, 150, 210, 240 } do
		local base = frame.Polar(42, deg)
		block(model, "Obelisk", base * CFrame.new(0, 14, 0), Vector3.new(3, 28, 3), Color3.fromRGB(235, 225, 235), Enum.Material.Marble)
		local tip = block(model, "ObeliskTip", base * CFrame.new(0, 31, 0) * CFrame.Angles(0, math.rad(45), math.rad(45)), Vector3.new(3, 3, 3), info.Accent, Enum.Material.Neon)
		sparkle(tip, info.Accent, 5)
		animate(tip, "Spin")
	end
	-- Glassy floor tiles around the capture pad
	for x = -3, 3 do
		for z = -3, 3 do
			if (x + z) % 2 == 0 then
				local tile = block(model, "FloorTile", CFrame.new(frame.Center + Vector3.new(x * 12, 0.15, z * 12)), Vector3.new(11.6, 0.3, 11.6), Color3.fromRGB(235, 200, 210), Enum.Material.Glass)
				tile.Transparency = 0.3
			end
		end
	end
	-- Broken edge: floating rubble and a row of hexagonal pillars
	for i = 1, count(8) do
		local cf = frame.RandomFree(rng, 60, 80)
		animate(block(model, "Rubble", cf * CFrame.new(0, rng:NextNumber(4, 30), 0) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), Vector3.new(rng:NextNumber(3, 8), rng:NextNumber(2, 5), rng:NextNumber(3, 8)), stone, Enum.Material.Rock), "Float")
	end
	for deg = 30, 90, 8 do
		column(model, "HexPillar", frame.Polar(70, deg, -10).Position, 3, 10, Color3.fromRGB(200, 165, 175), Enum.Material.Slate)
	end
	-- Pink clouds swallowing the island's base and drifting above
	for i = 1, count(10) do
		local deg = rng:NextNumber(0, 360)
		ball(model, "Cloud", frame.Polar(rng:NextNumber(66, 84), deg, -rng:NextNumber(0, 10)).Position, rng:NextNumber(20, 36), Color3.fromRGB(245, 190, 200))
	end
end

PROPS.Outpost = function(model, frame, info, rng)
	local domePos = frame.Polar(42, 140).Position
	local dome = ball(model, "Dome", domePos, 56, Color3.fromRGB(200, 215, 230), Enum.Material.Glass)
	dome.Transparency = 0.35
	column(model, "DomeBase", domePos, 28.5, 1.5, Color3.fromRGB(110, 110, 120), Enum.Material.DiamondPlate)
	local antennaPos = frame.Polar(50, 225).Position
	column(model, "Antenna", antennaPos, 0.8, 40, Color3.fromRGB(120, 120, 130), Enum.Material.Metal)
	local tip = ball(model, "AntennaTip", antennaPos + Vector3.new(0, 41, 0), 3, info.Accent, Enum.Material.Neon)
	addLight(tip, info.Accent, 40)
	for i = 1, count(6) do
		local cf = frame.RandomFree(rng, 26, 62)
		block(model, "Crate", cf * CFrame.new(0, 2, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Vector3.new(4, 4, 4), Color3.fromRGB(140, 140, 150), Enum.Material.DiamondPlate)
	end
	for i = 1, count(5) do
		local cf = frame.RandomFree(rng, 28, 64)
		disc(model, "Crater", cf.Position + Vector3.new(0, 0.1, 0), rng:NextNumber(4, 9), 0.2, Color3.fromRGB(110, 110, 120), Enum.Material.Slate)
	end
end

PROPS.Throne = function(model, frame, info, rng)
	local white = Color3.fromRGB(245, 240, 230)
	for _, deg in { 140, 220 } do
		local base = frame.Polar(46, deg)
		local height = 0
		for tier = 1, 6 do
			local w = 20 - tier * 2.5
			local h = 12
			block(model, "SpireTier", base * CFrame.new(0, height + h / 2, 0), Vector3.new(w, h, w), white, Enum.Material.Marble)
			height += h
		end
		local crown = block(model, "SpireCrown", base * CFrame.new(0, height + 4, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Vector3.new(5, 5, 5), info.Accent, Enum.Material.Neon)
		addLight(crown, info.Accent, 50, 2)
		sparkle(crown, info.Accent, 10, 1.4)
		animate(crown, "Spin")
	end
	local dais = frame.Polar(36, 180)
	block(model, "Dais", dais * CFrame.new(0, 2, 0), Vector3.new(24, 4, 18), white, Enum.Material.Marble)
	block(model, "ThroneSeat", dais * CFrame.new(0, 7, 3), Vector3.new(9, 6, 7), info.Accent, Enum.Material.Foil)
	block(model, "ThroneBack", dais * CFrame.new(0, 15, 6), Vector3.new(9, 18, 1.5), info.Accent, Enum.Material.Foil)
	for i = 1, count(4) do
		local cf = frame.RandomFree(rng, 28, 62)
		block(model, "Banner", cf * CFrame.new(0, 7, 0), Vector3.new(5, 14, 0.3), info.Accent, Enum.Material.Fabric)
	end
end

PROPS.Canyon = function(model, frame, info, rng)
	local rock = info.Ground
	for _, arc in FREE_ARCS do
		for deg = arc[1], arc[2], 4 do
			local h = rng:NextNumber(24, 40)
			local wall = frame.Polar(62, deg)
			block(model, "CliffWall", wall * CFrame.new(0, h / 2, 0), Vector3.new(11, h, 10), shade(rock, rng:NextNumber(0.8, 1)), Enum.Material.Rock)
			for _ = 1, 2 do
				if rng:NextNumber() < 0.6 then
					block(model, "EmergenceHole", wall * CFrame.new(rng:NextNumber(-3, 3), rng:NextNumber(3, h - 6), -5.05), Vector3.new(2.5, 5, 0.2), Color3.fromRGB(20, 15, 20))
				end
			end
		end
	end
	for i = 1, count(3) do
		local cf = frame.RandomFree(rng, 28, 50)
		local drill = column(model, "InjectorShaft", cf.Position, 1.6, 18, Color3.fromRGB(230, 200, 170), Enum.Material.Metal)
		local tip = ball(model, "InjectorLight", drill.Position + Vector3.new(0, 10, 0), 3, info.Accent, Enum.Material.Neon)
		addLight(tip, info.Accent, 18)
	end
end

PROPS.Crystal = function(model, frame, info, rng)
	for i = 1, count(14) do
		local cf = frame.RandomFree(rng, 24, 66)
		local h = rng:NextNumber(8, 34)
		local tilt = CFrame.Angles(math.rad(rng:NextNumber(-30, 30)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-30, 30)))
		local shard = block(model, "Shard", cf * tilt * CFrame.new(0, h / 2 - 1, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(h / 4, h, h / 4), info.Accent, Enum.Material.Glass)
		shard.Transparency = 0.15
		if i % 5 == 0 then
			addLight(shard, info.Accent, 18)
		end
		if i % 3 == 0 then
			sparkle(shard, info.Accent, 3)
		end
	end
	for i = 1, count(2) do
		local cf = frame.RandomFree(rng, 40, 60)
		block(model, "MineCart", cf * CFrame.new(0, 2, 0), Vector3.new(4, 3, 6), Color3.fromRGB(90, 70, 60), Enum.Material.Metal)
	end
end

PROPS.Warp = function(model, frame, info, rng)
	local stone = Color3.fromRGB(150, 150, 175)
	for _, arc in FREE_ARCS do
		for deg = arc[1], arc[2], 9 do
			column(model, "BrokenPillar", frame.Polar(36, deg).Position, 3, rng:NextNumber(6, 30), stone, Enum.Material.Slate)
		end
	end
	for i = 1, count(8) do
		local cf = frame.RandomFree(rng, 28, 64)
		animate(block(model, "Debris", cf * CFrame.new(0, rng:NextNumber(12, 40), 0) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), Vector3.new(4, 3, 3.5), stone, Enum.Material.Slate), "Float")
	end
	for _, deg in { 90, 270 } do
		local pad = disc(model, "MiniPad", frame.Polar(56, deg).Position + Vector3.new(0, 0.8, 0), 9, 0.8, Color3.fromRGB(220, 220, 235), Enum.Material.Marble)
		sparkle(disc(model, "MiniPadGlow", pad.Position + Vector3.new(0, 0.45, 0), 7, 0.1, info.Accent, Enum.Material.Neon), info.Accent, 6, 0.8, 20)
	end
end

PROPS.Citadel = function(model, frame, info, rng)
	local sand = Color3.fromRGB(225, 185, 120)
	for _, deg in { 45, 120, 240, 315 } do
		local p = frame.Polar(55, deg).Position
		column(model, "Tower", p, 9, 36, sand, Enum.Material.Sandstone)
		for c = 0, 7 do
			local a = c * math.pi / 4
			block(model, "Crenel", CFrame.new(p + Vector3.new(math.cos(a) * 8, 37.5, math.sin(a) * 8)), Vector3.new(3, 3, 3), sand, Enum.Material.Sandstone)
		end
	end
	local hg = frame.Polar(40, 180).Position
	column(model, "HourglassBase", hg, 8, 3, sand, Enum.Material.Sandstone)
	ball(model, "HourglassBottom", hg + Vector3.new(0, 10, 0), 14, info.Accent, Enum.Material.Glass).Transparency = 0.3
	ball(model, "HourglassTop", hg + Vector3.new(0, 22, 0), 14, info.Accent, Enum.Material.Glass).Transparency = 0.3
	column(model, "HourglassCap", hg + Vector3.new(0, 28, 0), 8, 2, sand, Enum.Material.Sandstone)
	for _, x in { -7, 7 } do
		column(model, "HourglassRod", hg + Vector3.new(x, 0, 0), 0.8, 30, sand, Enum.Material.Sandstone)
	end
	for i = 1, count(6) do
		local cf = frame.RandomFree(rng, 26, 64)
		ball(model, "Dune", cf.Position - Vector3.new(0, 2, 0), rng:NextNumber(10, 20), shade(sand, 1.05), Enum.Material.Sand)
	end
end

--------------------------------------------------------------------------------
-- Portals, arrival points, capture point
--------------------------------------------------------------------------------

-- Builds a ring portal standing at groundCf (facing groundCf.LookVector).
-- The returned surface part carries the attributes PortalService reads:
--   PortalKind   "Territory" | "Hub" | "Home"
--   TargetId     territory id when PortalKind == "Territory"
--   TargetName   display name for labels
--   RequiredRank rank index needed to pass
local function buildPortal(parent: Instance, name: string, groundCf: CFrame, color: Color3, attributes: { [string]: any }): Part
	local model = newModel(parent, name)
	local radius = 10
	local center = groundCf * CFrame.new(0, radius + 2, 0)

	block(model, "Base", groundCf * CFrame.new(0, 0.6, 0), Vector3.new(radius * 2 + 8, 1.2, 8), Color3.fromRGB(235, 230, 240), Enum.Material.Marble)
	local segments = 22
	for i = 0, segments - 1 do
		local a = i / segments * math.pi * 2
		block(model, "Frame", center * CFrame.new(math.cos(a) * (radius + 0.8), math.sin(a) * (radius + 0.8), 0) * CFrame.Angles(0, 0, a), Vector3.new(1.8, 3.4, 2), shade(color, 0.75), Enum.Material.Marble)
	end
	local gem = block(model, "Keystone", center * CFrame.new(0, radius + 2.4, 0) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(2.6, 2.6, 2.4), color, Enum.Material.Neon)
	animate(gem, "Spin")
	sparkle(gem, color, 6)

	local surface = newPart(model, "Surface", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, radius * 2, radius * 2),
		CFrame = center * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
	})
	addLight(surface, color, 28, 2)
	local swirl = sparkle(surface, color, 40, 1.1, 10)
	swirl.Speed = NumberRange.new(2, 5)
	swirl.Lifetime = NumberRange.new(0.8, 1.6)
	swirl.Acceleration = Vector3.new(0, 2, 0)
	for key, value in attributes do
		surface:SetAttribute(key, value)
	end
	CollectionService:AddTag(surface, GemConfig.Tags.Portal)
	return surface
end

local function arrivalPoint(parent: Instance, cf: CFrame)
	local part = newPart(parent, "Arrival", {
		Size = Vector3.new(6, 1, 6),
		CFrame = cf * CFrame.new(0, 0.5, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	return part
end

local function buildCapturePoint(model: Model, center: Vector3, info: any)
	local pad = disc(model, "CapturePoint", center + Vector3.new(0, 0.45, 0), TerritoryConfig.CaptureRadius, 0.3, NEUTRAL_COLOR, Enum.Material.Neon)
	pad.Transparency = 0.55
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false

	local beacon = block(model, "Beacon", CFrame.new(center + Vector3.new(0, 20, 0)) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(4, 16, 4), NEUTRAL_COLOR, Enum.Material.Neon)
	beacon.CanCollide = false
	beacon.CanQuery = false
	addLight(beacon, NEUTRAL_COLOR, 50, 1.5)
	sparkle(beacon, NEUTRAL_COLOR, 12, 1.4)
	animate(beacon, "Spin")

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.fromOffset(280, 54)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 13, 0)
	billboard.MaxDistance = 900
	billboard.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = info.DisplayName
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard
	billboard.Parent = beacon
end

--------------------------------------------------------------------------------
-- Hub & homes
--------------------------------------------------------------------------------

local function newSpawn(parent: Instance, name: string, position: Vector3, teamColor: BrickColor, color: Color3)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = name
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0))
	spawn.Color = color
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.3
	spawn.Neutral = false
	spawn.AllowTeamChangeOnTouch = false
	spawn.TeamColor = teamColor
	spawn.Duration = 3
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = parent
	return spawn
end

local function buildHub(map: Instance)
	local hub = newModel(map, "Hub")
	hub:SetAttribute("DisplayName", TerritoryConfig.HubName)
	local radius = TerritoryConfig.HubRadius
	buildIsland(hub, Vector3.zero, radius, Color3.fromRGB(235, 225, 240), Enum.Material.Marble)

	local rogue = GemConfig.Factions.Neutral
	newSpawn(hub, "RogueSpawn", Vector3.new(0, 0, 0), rogue.TeamColor, rogue.Color)
	arrivalPoint(hub, CFrame.new(0, 0, -20))

	-- Twelve lamps, one per island in its compass direction, tinted with its accent.
	for index, info in TerritoryConfig.Territories do
		local dir = TerritoryConfig.GetTerritoryCenter(index).Unit
		local base = dir * (radius - 10)
		column(hub, "LampPost", base, 0.7, 10, Color3.fromRGB(200, 195, 210), Enum.Material.Marble)
		local orb = ball(hub, "Lamp_" .. info.Id, base + Vector3.new(0, 11, 0), 3, info.Accent, Enum.Material.Neon)
		addLight(orb, info.Accent, 18)
		sparkle(orb, info.Accent, 3)
	end

	-- Central monument
	local monument = block(hub, "Monument", CFrame.new(0, 40, 0) * CFrame.Angles(0, math.rad(45), math.rad(45)), Vector3.new(14, 14, 14), Color3.fromRGB(255, 220, 245), Enum.Material.Glass)
	monument.Transparency = 0.2
	monument.CanCollide = false
	addLight(monument, Color3.fromRGB(255, 200, 240), 80, 2)
	sparkle(monument, Color3.fromRGB(255, 180, 230), 25, 2, 180)
	animate(monument, "Spin")
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		column(hub, "Plinth", Vector3.new(math.cos(a) * 26, 0, math.sin(a) * 26), 3, 8, Color3.fromRGB(215, 205, 225), Enum.Material.Marble)
	end

	-- Portal to island 1 (in its direction) and to your faction's home (opposite).
	local first = TerritoryConfig.Territories[1]
	local towardFirst = TerritoryConfig.GetTerritoryCenter(1).Unit
	local p1 = towardFirst * (radius * 0.75)
	buildPortal(hub, "Portal_" .. first.Id, CFrame.lookAt(p1, Vector3.zero), first.Accent, {
		PortalKind = "Territory",
		TargetId = first.Id,
		TargetName = first.DisplayName,
		RequiredRank = TerritoryConfig.GetRequiredRank(first.Id),
	})
	local p2 = -towardFirst * (radius * 0.75)
	buildPortal(hub, "Portal_Home", CFrame.lookAt(p2, Vector3.zero), Color3.fromRGB(255, 255, 255), {
		PortalKind = "Home",
		TargetName = "Your Home Base",
		RequiredRank = 1,
	})
end

local function buildHome(homes: Instance, factionId: string)
	local faction = GemConfig.Factions[factionId]
	local home = TerritoryConfig.Homes[factionId]
	local center = TerritoryConfig.GetHomeCenter(factionId) :: Vector3
	local radius = TerritoryConfig.HomeIslandRadius

	local model = newModel(homes, factionId)
	model:SetAttribute("DisplayName", home.DisplayName)
	model:SetAttribute("Faction", factionId)

	buildIsland(model, center, radius, shade(faction.Color, 0.55), Enum.Material.Marble)
	local frame = makeFrame(center, radius)

	for i, deg in { -30, 0, 30 } do
		newSpawn(model, "Spawn" .. i, frame.Absolute(18, 180 + deg).Position, faction.TeamColor, faction.Color)
	end
	arrivalPoint(model, frame.Absolute(radius * 0.45, 0))

	for _, deg in { 60, 120, 240, 300 } do
		local p = frame.Absolute(radius * 0.7, deg).Position
		column(model, "Pylon", p, 2.5, 28, Color3.fromRGB(235, 235, 240), Enum.Material.Marble)
		local orb = ball(model, "PylonOrb", p + Vector3.new(0, 30, 0), 5, faction.Color, Enum.Material.Neon)
		addLight(orb, faction.Color, 36, 1.5)
		sparkle(orb, faction.Color, 6, 1.2)
		animate(orb, "Float")
	end
	local banner = block(model, "Banner", frame.Absolute(radius * 0.8, 180) * CFrame.new(0, 16, 0), Vector3.new(18, 26, 0.4), faction.Color, Enum.Material.Fabric)
	local emblem = block(model, "Emblem", banner.CFrame * CFrame.new(0, 3, -0.35) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(7, 7, 0.3), Color3.new(1, 1, 1), Enum.Material.Neon)
	emblem.CanCollide = false

	-- Portal back to the hub at the hub-facing edge.
	local portalPos = frame.Absolute(radius * 0.78, 0).Position
	buildPortal(model, "Portal_Hub", CFrame.lookAt(portalPos, center), faction.Color, {
		PortalKind = "Hub",
		TargetName = TerritoryConfig.HubName,
		RequiredRank = 1,
	})
end

--------------------------------------------------------------------------------
-- Territories
--------------------------------------------------------------------------------

local function buildTerritory(folder: Instance, index: number, info: any)
	local center = TerritoryConfig.GetTerritoryCenter(index)
	local radius = TerritoryConfig.IslandRadius
	local model = newModel(folder, info.Id)
	model:SetAttribute("TerritoryId", info.Id)

	buildIsland(model, center, radius, info.Ground, info.GroundMaterial)
	local frame = makeFrame(center, radius)
	local rng = Random.new(index * 7919)

	local props = newModel(model, "Props")
	local builder = PROPS[info.Theme]
	if builder then
		builder(props, frame, info, rng)
	end
	scenery(newModel(model, "Scenery"), frame, info, rng)

	-- Drifting light motes over the whole island (glow most at night).
	local motes = newPart(model, "Motes", {
		Size = Vector3.new(radius * 1.8, 30, radius * 1.8),
		CFrame = CFrame.new(center + Vector3.new(0, 18, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local moteEmitter = sparkle(motes, info.Accent, 18, 0.6)
	moteEmitter.Lifetime = NumberRange.new(4, 7)
	moteEmitter.Speed = NumberRange.new(0.2, 0.8)
	moteEmitter.Shape = Enum.ParticleEmitterShape.Box
	moteEmitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume

	buildCapturePoint(model, center, info)

	-- Arrival spot faces the island centre, between return portal and capture pad.
	arrivalPoint(model, frame.Absolute(radius * TerritoryConfig.ArrivalDistance, 0))

	local returnPos = frame.Absolute(radius * TerritoryConfig.ReturnPortalDistance, 0).Position
	buildPortal(model, "ReturnPortal", CFrame.lookAt(returnPos, center), Color3.fromRGB(255, 235, 250), {
		PortalKind = "Hub",
		TargetName = TerritoryConfig.HubName,
		RequiredRank = 1,
	})

	local nextInfo = TerritoryConfig.Territories[index + 1]
	if nextInfo then
		local forwardPos = frame.Absolute(radius * TerritoryConfig.ForwardPortalDistance, 180).Position
		buildPortal(model, "ForwardPortal", CFrame.lookAt(forwardPos, center), nextInfo.Accent, {
			PortalKind = "Territory",
			TargetId = nextInfo.Id,
			TargetName = nextInfo.DisplayName,
			RequiredRank = TerritoryConfig.GetRequiredRank(nextInfo.Id),
		})
	end
end

--------------------------------------------------------------------------------
-- Sea, clouds and base lighting
--------------------------------------------------------------------------------

local function buildSea()
	local terrain = Workspace.Terrain
	local extent = TerritoryConfig.WorldExtent
	local surface = TerritoryConfig.SeaLevel
	local depth = 24
	local tile = 900

	-- FillBlock in tiles to keep each write small.
	for x = -extent, extent - 1, tile do
		for z = -extent, extent - 1, tile do
			local cx, cz = x + tile / 2, z + tile / 2
			terrain:FillBlock(CFrame.new(cx, surface - depth / 2, cz), Vector3.new(tile, depth, tile), Enum.Material.Water)
			terrain:FillBlock(CFrame.new(cx, surface - depth - 2, cz), Vector3.new(tile, 4, tile), Enum.Material.Sand)
		end
	end

	terrain.WaterColor = Color3.fromRGB(70, 160, 210)
	terrain.WaterTransparency = 0.35
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
end

local function ensureChild(parent: Instance, className: string, name: string?): Instance
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	if name then
		instance.Name = name
	end
	instance.Parent = parent
	return instance
end

-- Creates the objects SkyCycle animates; initial values match midday.
local function applyEnvironment()
	local clouds = ensureChild(Workspace.Terrain, "Clouds") :: Clouds
	clouds.Cover = 0.5
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(255, 245, 245)

	local atmosphere = ensureChild(Lighting, "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Glare = 0.4

	local sky = ensureChild(Lighting, "Sky") :: Sky
	sky.StarCount = 4000
	sky.CelestialBodiesShown = true

	local bloom = ensureChild(Lighting, "BloomEffect") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6

	ensureChild(Lighting, "ColorCorrectionEffect", "SkyTint")

	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

export type BuildOptions = {
	Rebuild: boolean?, -- destroy an existing Workspace.Map and build fresh
	SkipSea: boolean?, -- leave Terrain untouched
}

local function setWaypoint(name: string)
	-- Makes the bake undoable with Ctrl+Z in Studio; unavailable at runtime.
	pcall(function()
		game:GetService("ChangeHistoryService"):SetWaypoint(name)
	end)
end

-- Builds Workspace.Map (and sea, clouds, lighting effects) and returns it.
-- If Workspace.Map already exists it is returned untouched unless
-- options.Rebuild is set. Safe to call from the Edit-mode command bar.
function MapBuilder.Build(options: BuildOptions?): Instance
	local opts = options or {}
	local existing = Workspace:FindFirstChild("Map")
	if existing and not opts.Rebuild then
		return existing
	end

	setWaypoint("Before MapBuilder.Build")
	local started = os.clock()

	if existing then
		existing:Destroy()
	end

	applyEnvironment()
	if not opts.SkipSea then
		buildSea()
	end

	-- Assemble off-tree and parent once at the end (one replication burst).
	local map = newModel(nil, "Map")
	buildHub(map)

	local territories = newFolder(map, "Territories")
	for index, info in TerritoryConfig.Territories do
		buildTerritory(territories, index, info)
	end

	local homes = newFolder(map, "Homes")
	for factionId in TerritoryConfig.Homes do
		buildHome(homes, factionId)
	end

	Workspace.FallenPartsDestroyHeight = TerritoryConfig.SeaLevel - 120
	map.Parent = Workspace

	setWaypoint("MapBuilder.Build")
	print(string.format("[MapBuilder] Built Workspace.Map (%d instances) in %.2fs", #map:GetDescendants(), os.clock() - started))
	return map
end

return MapBuilder
