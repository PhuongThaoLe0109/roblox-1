-- World
-- Everything around the temple and the lobby that makes it feel like a whole
-- gem world rather than a level:
--   * a calm teal sea with glowing ripple rings and wave glints
--   * scattered stratified islets, some crowned with crystal clusters
--   * the Sunken Colossus: two giant stone hands rising from the sea,
--     cradling a glowing gem
--   * giant crystal spires on the horizon
--   * floating sky islands with waterfalls of light
--   * a ring of faceted low-poly mountains
--   * crystal shards drifting over the water, a moon and aurora ribbons
-- Plain Parts only: SmoothPlastic / Neon / Glass, plus untextured Beams.

local G = require(script.Parent:WaitForChild("Geometry"))
local P = require(script.Parent:WaitForChild("Palette"))

local World = {}

-- Keep clear: the temple, the lobby and the corridor of the bridge.
local function blocked(x: number, z: number, margin: number): boolean
	if Vector3.new(x, 0, z + 32).Magnitude < 262 + margin then
		return true
	end
	if Vector3.new(x, 0, z - 470).Magnitude < 150 + margin then
		return true
	end
	if math.abs(x) < 40 + margin and z > 60 and z < 520 then
		return true
	end
	return false
end

local function scatter(rng: Random, minR: number, maxR: number, margin: number): (number, number)
	for _ = 1, 60 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(minR, maxR)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if not blocked(x, z, margin) then
			return x, z
		end
	end
	return minR, 0
end

local CRYSTAL_COLORS = { P.Pink, P.Teal, P.Lavender, P.Pearl, P.Gold }

local function crystalCluster(parent: Instance, base: Vector3, rng: Random, scale: number, count: number)
	local color = CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)]
	for _ = 1, count do
		local tilt = CFrame.Angles(math.rad(rng:NextNumber(-22, 22)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-22, 22)))
		local offset = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * scale * 0.6
		G.Crystal(parent, "Crystal", base + offset, scale * rng:NextNumber(0.35, 0.6), scale * rng:NextNumber(1.2, 2.6), tilt, {
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
			CanCollide = false,
		}, { Color = G.Shade(color, 0.3), Material = Enum.Material.Neon, CanCollide = false })
	end
end

local function rippleRings(parent: Instance, center: Vector3, radius: number, rng: Random, rings: number?)
	for i = 1, rings or 2 do
		local ring = G.Model(parent, "Ripple")
		G.Ring(ring, "RippleSegment", CFrame.new(center.X, 0.15, center.Z), radius + i * radius * 0.2 + rng:NextNumber(-2, 2), 0.6, 0.2, math.clamp(math.floor(radius / 4), 12, 36), {
			Color = P.Ripple,
			Material = Enum.Material.Neon,
			Transparency = 0.45 + i * 0.15,
			CanCollide = false,
		})
	end
end

--------------------------------------------------------------------------------

local function buildSea(world: Instance)
	local sea = G.Model(world, "Sea")
	local tile = 2048
	for x = -2, 2 do
		for z = -2, 2 do
			G.Block(sea, "Water", CFrame.new(x * tile, -2, z * tile), Vector3.new(tile, 4, tile), {
				Color = P.Sea,
				Material = Enum.Material.SmoothPlastic,
			}).Reflectance = 0.06
		end
	end
	-- Shimmering wave glints across the water.
	local glints = G.Model(sea, "Glints")
	local rng = Random.new(4242)
	for _ = 1, 170 do
		local x, z = scatter(rng, 220, 1500, -60)
		local length = rng:NextNumber(4, 14)
		local yaw = rng:NextNumber(-0.35, 0.35)
		local glint = G.Block(glints, "Glint", CFrame.new(x, 0.12, z) * CFrame.Angles(0, yaw, 0), Vector3.new(length, 0.1, 0.5), {
			Color = P.Ripple,
			Material = Enum.Material.Neon,
			Transparency = rng:NextNumber(0.35, 0.7),
			CanCollide = false,
		})
		if rng:NextNumber() < 0.3 then
			G.Tag(glint, "MapPulse")
		end
	end
	-- Rings around the temple and the lobby.
	rippleRings(sea, Vector3.new(0, 0, -32), 254, rng)
	rippleRings(sea, Vector3.new(0, 0, 470), 140, rng)
end

local function buildIslets(world: Instance, rng: Random)
	local islets = G.Model(world, "Islets")
	for i = 1, 22 do
		local x, z = scatter(rng, 280, 1000, 30)
		local radius = rng:NextNumber(10, 42)
		local height = rng:NextNumber(5, 30)
		local model = G.Model(islets, "Islet")
		local _, top = G.RockStack(model, "Rock", Vector3.new(x, -3, z), radius, radius * rng:NextNumber(0.55, 0.8), height, rng:NextInteger(2, 3), rng, {
			Rock = if i % 3 == 0 then P.RockLight else P.Rock,
			Rim = P.Rim,
			Streak = if i % 2 == 0 then P.StreakBlue else nil,
		}, rng:NextInteger(7, 9), false, radius < 28)
		if radius > 22 and rng:NextNumber() < 0.6 then
			crystalCluster(model, Vector3.new(x, top, z), rng, radius * 0.22, rng:NextInteger(3, 5))
		end
		rippleRings(model, Vector3.new(x, 0, z), radius * 1.05, rng, 1)
	end
end

-- Two colossal hands rising from the sea, palms turned toward each other,
-- fingers curling in to cradle a glowing gem.
local function buildColossus(world: Instance)
	local root = G.Model(world, "SunkenColossus")
	local center = Vector3.new(-560, 0, -420)
	local stone = G.Shade(P.StoneShade, -0.1)
	local stoneDark = G.Shade(stone, -0.12)
	local moss = G.Shade(P.Teal, -0.3)
	for _, side in { -1, 1 } do
		-- Upright frame for this hand; it leans slightly outward so the palms
		-- open around the gem like a cupped offering.
		local hand = CFrame.new(center + Vector3.new(side * 26, 0, 0)) * CFrame.Angles(0, 0, math.rad(-side * 9))
		local inward = -side -- palm faces the other hand along local X

		G.Block(root, "Forearm", hand * CFrame.new(0, 20, 0), Vector3.new(17, 62, 15), { Color = stone })
		G.Block(root, "Bracer", hand * CFrame.new(0, 40, 0), Vector3.new(19, 6, 17), { Color = P.Rim })
		G.Block(root, "BracerGem", hand * CFrame.new(inward * 9.7, 40, 0) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.6, 3.4, 3.4), {
			Color = P.Pink,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		G.Block(root, "Moss", hand * CFrame.new(-inward * 7.6, 22, 0), Vector3.new(0.6, 18, 11), { Color = moss })

		-- Palm: thickness along X, broad along Z.
		G.Block(root, "Palm", hand * CFrame.new(0, 62, 0), Vector3.new(11, 26, 27), { Color = stone })
		for c = 1, 3 do
			G.Block(root, "PalmLine", hand * CFrame.new(inward * 5.6, 58 + c * 3, (c - 2) * 5) * CFrame.Angles(math.rad(25 * (c - 2)), 0, 0), Vector3.new(0.2, 10, 0.5), {
				Color = P.StreakPink,
				Material = Enum.Material.Neon,
				Transparency = 0.2,
				CanCollide = false,
			})
		end

		-- Four fingers, each in two segments curling toward the gem.
		for f = 0, 3 do
			local z = (f - 1.5) * 6.8
			local length = if f == 1 or f == 2 then 1 else 0.85
			local base = hand * CFrame.new(0, 75, z)
			local bend1 = base * CFrame.Angles(0, 0, math.rad(inward * -18))
			G.Block(root, "Finger", bend1 * CFrame.new(0, 6.5 * length, 0), Vector3.new(7, 13 * length, 6), { Color = stone })
			local bend2 = bend1 * CFrame.new(0, 13 * length, 0) * CFrame.Angles(0, 0, math.rad(inward * -32))
			G.Block(root, "Fingertip", bend2 * CFrame.new(0, 5 * length, 0), Vector3.new(6.2, 10 * length, 5.4), { Color = stoneDark })
		end
		-- Thumb on the near edge, angled up and in.
		local thumb = hand * CFrame.new(inward * 2, 58, 15) * CFrame.Angles(math.rad(-25), 0, math.rad(inward * -30))
		G.Block(root, "Thumb", thumb * CFrame.new(0, 8, 0), Vector3.new(7, 16, 7), { Color = stone })
	end

	-- The cradled gem, hovering between the palms.
	local gem = G.Model(root, "CradledGem")
	local gemPosition = center + Vector3.new(0, 78, 0)
	G.Gem(gem, "Facet", CFrame.new(gemPosition), 10, 15, { Color = P.Lavender, Material = Enum.Material.Glass, Transparency = 0.1, CanCollide = false })
	local core = G.Ball(gem, "Core", gemPosition, 9, { Color = G.Shade(P.Lavender, 0.3), Material = Enum.Material.Neon, CanCollide = false })
	G.Light(core, P.Lavender, 90, 3)
	gem:SetAttribute("SpinSpeed", 0.25)
	gem:SetAttribute("FloatHeight", 3)
	G.Tag(gem, "MapSpin")
	rippleRings(root, center, 60, Random.new(77))
end

local function buildSpires(world: Instance, rng: Random)
	local spires = G.Model(world, "CrystalSpires")
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = rng:NextNumber(1150, 1550)
		local base = Vector3.new(math.cos(a) * r, -2, math.sin(a) * r)
		local model = G.Model(spires, "Spire")
		G.RockStack(model, "Base", base - Vector3.new(0, 2, 0), rng:NextNumber(70, 110), rng:NextNumber(40, 60), rng:NextNumber(20, 40), 3, rng, {
			Rock = P.Rock,
			Rim = P.Rim,
		}, 10, false, true)
		local color = CRYSTAL_COLORS[(i % #CRYSTAL_COLORS) + 1]
		local count = rng:NextInteger(4, 7)
		for c = 1, count do
			local height = if c == 1 then rng:NextNumber(330, 520) else rng:NextNumber(110, 300)
			local width = height * rng:NextNumber(0.1, 0.15)
			local tilt = if c == 1 then CFrame.identity else CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-20, 20)))
			G.Crystal(model, "Spire", base + Vector3.new(rng:NextNumber(-30, 30), 20, rng:NextNumber(-30, 30)), width, height, tilt, {
				Color = color,
				Material = Enum.Material.Glass,
				Transparency = 0.12,
				CanCollide = false,
			}, { Color = G.Shade(color, 0.35), Material = Enum.Material.Neon, CanCollide = false })
		end
	end
end

local function buildSkyIslands(world: Instance, rng: Random)
	local sky = G.Model(world, "SkyIslands")
	for i = 1, 6 do
		local x, z = scatter(rng, 420, 900, 80)
		local y = rng:NextNumber(220, 380)
		local radius = rng:NextNumber(30, 60)
		local model = G.Model(sky, "SkyIsland")
		-- Inverted stack: wide on top, tapering down to a point.
		G.RockStack(model, "Rock", Vector3.new(x, y, z), radius, radius * 0.25, radius * 1.4, 4, rng, {
			Rock = P.Rock,
			Rim = P.Rim,
			Streak = P.StreakBlue,
		}, 10, true, true)
		G.Fan(model, "Meadow", Vector3.new(x, y + 0.6, z), G.Loop(Vector3.new(x, y + 0.6, z), radius * 0.92, 10, rng, 0.08), { Color = G.Shade(P.Teal, -0.25) }, 1)
		crystalCluster(model, Vector3.new(x, y, z), rng, radius * 0.18, rng:NextInteger(3, 6))
		-- Waterfall of light pouring over the edge.
		local a = rng:NextNumber(0, math.pi * 2)
		local lip = Vector3.new(x + math.cos(a) * radius * 0.85, y, z + math.sin(a) * radius * 0.85)
		local fall = G.Block(model, "LightFall", CFrame.lookAt(lip - Vector3.new(0, 90, 0), lip - Vector3.new(0, 90, 0) + Vector3.new(math.cos(a), 0, math.sin(a))), Vector3.new(radius * 0.25, 180, 0.6), {
			Color = P.Channel,
			Material = Enum.Material.Neon,
			Transparency = 0.45,
			CanCollide = false,
		})
		G.Tag(fall, "MapPulse")
		local mist = G.Model(model, "Mist")
		G.Ring(mist, "MistRing", CFrame.new(lip.X, 0.2, lip.Z), radius * 0.25, 0.6, 0.2, 16, { Color = P.Ripple, Material = Enum.Material.Neon, Transparency = 0.4, CanCollide = false })
	end
end

local function buildMountains(world: Instance, rng: Random)
	local mountains = G.Model(world, "Mountains")
	local count = 28
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + rng:NextNumber(-0.06, 0.06)
		local r = rng:NextNumber(2300, 2700)
		local center = Vector3.new(math.cos(a) * r, -2, math.sin(a) * r)
		local height = rng:NextNumber(380, 820)
		local base = G.Loop(center, rng:NextNumber(260, 420), 7, rng, 0.2)
		local peak = center + Vector3.new(rng:NextNumber(-40, 40), height, rng:NextNumber(-40, 40))
		-- Snowy (lavender) cap: split each face at 70% height.
		for f = 1, #base do
			local p1, p2 = base[f], base[f % #base + 1]
			local m1, m2 = p1:Lerp(peak, 0.7), p2:Lerp(peak, 0.7)
			local shade = if f % 2 == 0 then 0.06 else -0.06
			G.Triangle(mountains, "Slope", p1, p2, m1, { Color = G.Shade(P.Mountain, shade), CanCollide = false }, 2)
			G.Triangle(mountains, "Slope", m1, p2, m2, { Color = G.Shade(P.Mountain, shade - 0.03), CanCollide = false }, 2)
			G.Triangle(mountains, "Cap", m1, m2, peak, { Color = G.Shade(P.MountainCap, shade), CanCollide = false }, 2)
		end
	end
end

local function buildShards(world: Instance, rng: Random)
	local shards = G.Model(world, "DriftingShards")
	for _ = 1, 160 do
		local x, z = scatter(rng, 200, 1100, -40)
		local size = rng:NextNumber(0.6, 2.2)
		local color = CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)]
		local shard = G.Block(shards, "Shard", CFrame.new(x, rng:NextNumber(3, 40), z) * CFrame.Angles(math.rad(45), rng:NextNumber(0, 3), math.rad(45)), Vector3.one * size, {
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = rng:NextNumber(0.05, 0.35),
			CanCollide = false,
		})
		G.Tag(shard, "MapFloat")
	end
end

local function buildSky(world: Instance)
	local sky = G.Model(world, "Sky")
	-- Moon with a soft glass halo.
	local moonPos = Vector3.new(700, 820, -1250)
	G.Ball(sky, "Moon", moonPos, 170, { Color = Color3.fromRGB(232, 240, 255), Material = Enum.Material.Neon, CanCollide = false })
	G.Ball(sky, "MoonHalo", moonPos, 260, { Color = P.Channel, Material = Enum.Material.Glass, Transparency = 0.86, CanCollide = false })

	-- Aurora ribbons: untextured gradient Beams strung between anchors.
	local ribbons = {
		{ Start = Vector3.new(-1600, 620, -1300), Finish = Vector3.new(1500, 700, -900), Width = 260 },
		{ Start = Vector3.new(-1400, 720, -600), Finish = Vector3.new(1300, 640, -1500), Width = 180 },
		{ Start = Vector3.new(-900, 560, 1300), Finish = Vector3.new(1600, 660, 700), Width = 220 },
	}
	for index, ribbon in ribbons do
		local anchor = G.Block(sky, "AuroraAnchor", CFrame.new(ribbon.Start), Vector3.one, { Color = P.Teal, Transparency = 1, CanCollide = false })
		local segments = 6
		local previous: Attachment? = nil
		for s = 0, segments do
			local t = s / segments
			local point = ribbon.Start:Lerp(ribbon.Finish, t) + Vector3.new(0, math.sin(t * math.pi * 2 + index) * 60, 0)
			local attachment = Instance.new("Attachment")
			attachment.Position = anchor.CFrame:PointToObjectSpace(point)
			attachment.Parent = anchor
			if previous then
				local beam = Instance.new("Beam")
				beam.Attachment0 = previous
				beam.Attachment1 = attachment
				beam.Width0 = ribbon.Width
				beam.Width1 = ribbon.Width
				beam.FaceCamera = false
				beam.LightEmission = 1
				beam.LightInfluence = 0
				beam.Segments = 20
				beam.CurveSize0 = 80
				beam.CurveSize1 = -80
				beam.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 255, 205)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 140, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 220)),
				})
				beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.55),
					NumberSequenceKeypoint.new(0.5, 0.35),
					NumberSequenceKeypoint.new(1, 0.6),
				})
				beam.Parent = anchor
			end
			previous = attachment
		end
	end
end

function World.Build(map: Instance, rng: Random)
	local world = G.Model(map, "World")
	buildSea(world)
	buildIslets(world, rng)
	buildColossus(world)
	buildSpires(world, rng)
	buildSkyIslands(world, rng)
	buildMountains(world, rng)
	buildShards(world, rng)
	buildSky(world)
end

return World
