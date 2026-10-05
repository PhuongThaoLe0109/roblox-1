-- Temple
-- The Prism Temple (arena) after the reference art: a stratified dark rock
-- island crowned by a pale five-lobed fan. Double channels of cyan light curve
-- from crystal pods on each lobe to a stepped dais, where a pillar of light
-- rises into the sky. A sealed light-gate closes the bridge entrance.
--
-- Exposes Map.Arena with attributes Center, Radius, FloorY, KillY and a
-- Spawns folder (parts tagged "ArenaSpawn").

local G = require(script.Parent:WaitForChild("Geometry"))
local P = require(script.Parent:WaitForChild("Palette"))

local Temple = {}

Temple.Pivot = Vector3.new(0, 62, 55) -- dais centre; the fan opens toward -Z
Temple.FloorY = 62
Temple.FanRadius = 152
Temple.HalfAngle = math.rad(78)
Temple.LobeSpacing = math.rad(31)

-- Rim radius at angle `a` (0 = straight north): five rounded lobes.
local function rimRadius(a: number): number
	local phase = math.cos(a * 2 * math.pi / Temple.LobeSpacing)
	return Temple.FanRadius + 24 * (0.5 + 0.5 * phase)
end

-- World point on the fan floor at angle a (0 = north) and radius r.
local function fanPoint(a: number, r: number, y: number?): Vector3
	return Temple.Pivot + Vector3.new(math.sin(a) * r, (y or Temple.FloorY) - Temple.Pivot.Y, -math.cos(a) * r)
end
Temple.FanPoint = fanPoint

local function quadratic(a: Vector3, c: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(c, t):Lerp(c:Lerp(b, t), t)
end

function Temple.Build(map: Instance, rng: Random)
	local root = G.Model(map, "Temple")
	local floor = Temple.FloorY

	----------------------------------------------------------------------------
	-- Island
	----------------------------------------------------------------------------
	local island = G.Model(root, "Island")
	-- Centred under the fan so the pale floor covers most of the summit.
	G.RockStack(island, "Rock", Vector3.new(0, -6, -32), 228, 172, 66, 6, rng, {
		Rock = P.Rock,
		Rim = P.Rim,
		Streak = P.StreakBlue,
	}, 18)
	-- Secondary shelves breaking up the silhouette.
	for i = 1, 7 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(170, 220)
		local center = Vector3.new(math.cos(a) * r, -4, math.sin(a) * r - 32)
		G.RockStack(island, "Shelf", center, rng:NextNumber(40, 70), rng:NextNumber(26, 44), rng:NextNumber(26, 46), 3, rng, {
			Rock = P.RockLight,
			Rim = P.Rim,
			Streak = if i % 2 == 0 then P.StreakPink else P.StreakBlue,
		}, 9)
	end

	----------------------------------------------------------------------------
	-- Fan floor (faceted, three radial bands)
	----------------------------------------------------------------------------
	local fan = G.Model(root, "Fan")
	local steps = 26
	local bands = { 0.36, 0.7, 1 }
	local function bandPoint(i: number, band: number): Vector3
		local a = -Temple.HalfAngle + (i / steps) * Temple.HalfAngle * 2
		return fanPoint(a, rimRadius(a) * band)
	end
	for i = 0, steps - 1 do
		-- Inner triangle from the pivot
		local shade = rng:NextNumber(-0.035, 0.035)
		G.Triangle(fan, "Floor", Temple.Pivot, bandPoint(i + 1, bands[1]), bandPoint(i, bands[1]), {
			Color = G.Shade(P.Stone, shade),
		}, 2)
		for b = 1, #bands - 1 do
			local a1, a2 = bandPoint(i, bands[b]), bandPoint(i + 1, bands[b])
			local b1, b2 = bandPoint(i, bands[b + 1]), bandPoint(i + 1, bands[b + 1])
			-- Winding chosen so every floor facet faces up (thickness hangs below).
			G.Triangle(fan, "Floor", a1, b2, b1, { Color = G.Shade(P.Stone, rng:NextNumber(-0.04, 0.04)) }, 2)
			G.Triangle(fan, "Floor", a1, a2, b2, { Color = G.Shade(P.Stone, rng:NextNumber(-0.04, 0.04)) }, 2)
		end
	end

	-- Bevelled rim and side edges.
	local rimTop, rimLow = {}, {}
	for i = 0, steps do
		local a = -Temple.HalfAngle + (i / steps) * Temple.HalfAngle * 2
		local r = rimRadius(a)
		table.insert(rimTop, fanPoint(a, r))
		table.insert(rimLow, fanPoint(a, r + 4, floor - 7))
	end
	for i = 1, #rimTop - 1 do
		local st = { Color = G.Shade(P.StoneShade, if i % 2 == 0 then 0.04 else -0.04) }
		G.Triangle(fan, "Bevel", rimTop[i], rimLow[i], rimTop[i + 1], st, 1)
		G.Triangle(fan, "Bevel", rimTop[i + 1], rimLow[i], rimLow[i + 1], st, 1)
	end
	for _, side in { -1, 1 } do
		local a = side * Temple.HalfAngle
		local outerTop = fanPoint(a, rimRadius(a))
		local outerLow = fanPoint(a, rimRadius(a) + 4, floor - 7)
		local innerTop = Temple.Pivot + Vector3.new(side * 6, 0, 8)
		local innerLow = innerTop + Vector3.new(side * 3, -7, 3)
		G.Triangle(fan, "Bevel", innerTop, innerLow, outerTop, { Color = P.StoneShade }, 1)
		G.Triangle(fan, "Bevel", outerTop, innerLow, outerLow, { Color = G.Shade(P.StoneShade, -0.06) }, 1)
	end
	-- Pale trim line just inside the rim.
	for i = 1, #rimTop - 1 do
		local inward1 = Temple.Pivot:Lerp(rimTop[i], 0.97) + Vector3.new(0, 0.25, 0)
		local inward2 = Temple.Pivot:Lerp(rimTop[i + 1], 0.97) + Vector3.new(0, 0.25, 0)
		G.Strip(fan, "Trim", inward1, inward2, 1.2, 0.5, { Color = P.Trim, CanCollide = false })
	end

	-- Faint wave markings etched into the floor (as in the reference art).
	for w = 1, 6 do
		local radius = 30 + w * 17
		local prev: Vector3? = nil
		for i = 0, 18 do
			local a = -Temple.HalfAngle * 0.9 + (i / 18) * Temple.HalfAngle * 1.8
			local wobble = math.sin(i * 0.9 + w) * 4
			local point = fanPoint(a, math.min(radius + wobble, rimRadius(a) - 6), floor + 0.12)
			if prev then
				G.Strip(fan, "Etching", prev, point, 0.9, 0.2, { Color = G.Shade(P.Stone, 0.12), CanCollide = false })
			end
			prev = point
		end
	end

	-- Small crystal clusters along the rim frame the arena.
	for i = 1, 14 do
		local a = -Temple.HalfAngle + (i - 0.5) / 14 * Temple.HalfAngle * 2
		local base = fanPoint(a, rimRadius(a) - 3, floor)
		local color = if i % 2 == 0 then P.Teal else P.Lavender
		for c = 1, 2 do
			local tilt = CFrame.Angles(math.rad(rng:NextNumber(-18, 18)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-18, 18)))
			G.Crystal(fan, "RimCrystal", base + Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5)), rng:NextNumber(1.2, 2), rng:NextNumber(4, 8) * (if c == 1 then 1.3 else 1), tilt, {
				Color = color,
				Material = Enum.Material.Glass,
				Transparency = 0.15,
				CanCollide = false,
			}, { Color = G.Shade(color, 0.3), Material = Enum.Material.Neon, CanCollide = false })
		end
	end

	----------------------------------------------------------------------------
	-- Crystal pods on each lobe + double light channels to the dais
	----------------------------------------------------------------------------
	local lights = G.Model(root, "Channels")
	local lobeAngles = { -2, -1, 0, 1, 2 }
	for _, k in lobeAngles do
		local a = k * Temple.LobeSpacing
		local podCenter = fanPoint(a, rimRadius(a) - 16)
		local pod = G.Model(lights, "Pod")
		G.Cylinder(pod, "PodBase", podCenter, 10, 1.6, { Color = P.StoneShade })
		G.Ring(pod, "PodTrim", CFrame.new(podCenter + Vector3.new(0, 1.7, 0)), 9.6, 0.8, 0.5, 20, { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })
		local dome = G.Ball(pod, "PodDome", podCenter + Vector3.new(0, 1.6, 0), 15, { Color = P.PodGlass, Material = Enum.Material.Glass, Transparency = 0.3 })
		local _ = dome
		local core = G.Ball(pod, "PodCore", podCenter + Vector3.new(0, 3.5, 0), 6, { Color = P.PodCore, Material = Enum.Material.Neon, CanCollide = false })
		G.Tag(core, "MapPulse")
		G.Light(core, P.Channel, 26, 2)

		-- A fall of light spills from each pod over the cliff into the sea.
		local outward = Vector3.new(math.sin(a), 0, -math.cos(a))
		local lip = fanPoint(a, rimRadius(a) + 3, floor - 6)
		local fallTop = lip + outward * 2
		local fallBottom = Vector3.new(fallTop.X, 0.5, fallTop.Z) + outward * 26
		local fall = G.Strip(lights, "LightFall", fallTop, fallBottom, 5, 0.5, {
			Color = P.Channel,
			Material = Enum.Material.Neon,
			Transparency = 0.45,
			CanCollide = false,
		}, outward)
		G.Tag(fall, "MapPulse")
		G.Ring(pod, "Splash", CFrame.new(fallBottom.X, 0.2, fallBottom.Z), 7, 0.6, 0.2, 14, { Color = P.Ripple, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false })

		-- Two parallel channels sweeping in a curve to the dais.
		local inwardDir = (Temple.Pivot - podCenter).Unit
		local side = Vector3.new(-inwardDir.Z, 0, inwardDir.X)
		local daisEdge = Temple.Pivot - inwardDir * 26
		local bend = side * (k * 9 + (if k == 0 then 12 else 0))
		for _, offset in { -2.4, 2.4 } do
			local start = podCenter - inwardDir * 9 + side * offset
			local finish = daisEdge + side * offset * 0.6
			local control = start:Lerp(finish, 0.5) + bend
			local segments = 16
			local prev = start
			for s = 1, segments do
				local point = quadratic(start, control, finish, s / segments)
				local y = Vector3.new(0, floor + 0.35 - prev.Y, 0)
				local a1 = prev + y
				local b1 = Vector3.new(point.X, floor + 0.35, point.Z)
				G.Strip(lights, "ChannelGlow", a1 - Vector3.new(0, 0.12, 0), b1 - Vector3.new(0, 0.12, 0), 3.4, 0.3, {
					Color = P.ChannelGlow,
					Material = Enum.Material.Glass,
					Transparency = 0.3,
					CanCollide = false,
				})
				local line = G.Strip(lights, "Channel", a1, b1, 1.3, 0.35, { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })
				if s % 4 == 0 then
					G.Tag(line, "MapPulse")
				end
				prev = point
			end
		end
	end

	----------------------------------------------------------------------------
	-- Dais + pillar of light
	----------------------------------------------------------------------------
	local dais = G.Model(root, "Dais")
	local pivot = Temple.Pivot
	G.Fan(dais, "DaisStep", pivot + Vector3.new(0, 1.2, 0), G.Loop(pivot + Vector3.new(0, 1.2, 0), 26, 16), { Color = P.StoneShade }, 1.6)
	G.Fan(dais, "DaisTop", pivot + Vector3.new(0, 2.4, 0), G.Loop(pivot + Vector3.new(0, 2.4, 0), 19, 16), { Color = P.Stone }, 1.6)
	G.Ring(dais, "DaisRing", CFrame.new(pivot + Vector3.new(0, 2.6, 0)), 19.4, 0.9, 0.5, 32, { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })
	G.Ring(dais, "DaisRingInner", CFrame.new(pivot + Vector3.new(0, 2.6, 0)), 11, 0.6, 0.4, 24, { Color = P.Trim, Material = Enum.Material.Neon, CanCollide = false })
	local well = G.Cylinder(dais, "Well", pivot + Vector3.new(0, 2.2, 0), 8.5, 0.6, { Color = P.Beam, Material = Enum.Material.Neon, CanCollide = false })
	G.Light(well, P.Beam, 60, 3)

	local beamBase = pivot + Vector3.new(0, 2.8, 0)
	local beamTop = beamBase + Vector3.new(0, 2000, 0)
	G.CylinderBetween(dais, "LightPillar", beamBase, beamTop, 6.5, { Color = P.Beam, Material = Enum.Material.Neon, Transparency = 0.08, CanCollide = false })
	G.CylinderBetween(dais, "LightSheath", beamBase, beamTop, 11, { Color = P.Channel, Material = Enum.Material.Glass, Transparency = 0.72, CanCollide = false })
	-- Halo rings that drift up the pillar (animated by the client).
	for i, height in { 12, 34, 62, 100 } do
		local halo = G.Model(dais, "Halo" .. i)
		G.Ring(halo, "HaloSegment", CFrame.new(beamBase + Vector3.new(0, height, 0)), 13 + i * 1.5, 0.6, 0.6, 28, {
			Color = if i % 2 == 0 then P.Trim else P.Channel,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanCollide = false,
		})
		halo:SetAttribute("RiseHeight", 130)
		halo:SetAttribute("RiseSpeed", 6 + i)
		G.Tag(halo, "MapRise")
	end

	----------------------------------------------------------------------------
	-- Crystal clusters on the island ledges
	----------------------------------------------------------------------------
	local crystals = G.Model(root, "Crystals")
	local palette = { P.Pink, P.Teal, P.Lavender, P.Pearl }
	for i = 1, 18 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(180, 218)
		local base = Vector3.new(math.cos(a) * r, rng:NextNumber(20, 52), math.sin(a) * r - 32)
		local color = palette[rng:NextInteger(1, #palette)]
		for c = 1, rng:NextInteger(2, 4) do
			local tilt = CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-25, 25)))
			G.Crystal(crystals, "Crystal", base + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)), rng:NextNumber(2, 4), rng:NextNumber(8, 20), tilt, {
				Color = color,
				Material = Enum.Material.Glass,
				Transparency = 0.15,
				CanCollide = false,
			}, { Color = G.Shade(color, 0.3), Material = Enum.Material.Neon, CanCollide = false })
		end
	end

	----------------------------------------------------------------------------
	-- Sealed light-gate at the bridge entrance
	----------------------------------------------------------------------------
	local gate = G.Model(root, "SealedGate")
	local gateZ = pivot.Z + 30
	for _, x in { -12, 12 } do
		G.Crystal(gate, "GatePillar", Vector3.new(x, floor - 2, gateZ), 4.5, 30, nil, { Color = P.Stone }, { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })
	end
	local membrane = G.Block(gate, "Membrane", CFrame.new(0, floor + 11, gateZ), Vector3.new(20, 22, 0.4), {
		Color = P.Channel,
		Material = Enum.Material.Neon,
		Transparency = 0.82,
		CanCollide = false,
	})
	G.Tag(membrane, "MapPulse")
	G.Block(gate, "Barrier", CFrame.new(0, floor + 20, gateZ), Vector3.new(26, 44, 2), { Color = P.Channel, Transparency = 1, CanCollide = true })
	G.Gem(gate, "GateGem", CFrame.new(0, floor + 27, gateZ), 2.2, 3.2, { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })

	----------------------------------------------------------------------------
	-- Gameplay contract
	----------------------------------------------------------------------------
	local arena = G.Folder(map, "Arena")
	arena:SetAttribute("Center", pivot)
	arena:SetAttribute("Radius", Temple.FanRadius + 30)
	arena:SetAttribute("FloorY", floor)
	arena:SetAttribute("KillY", floor - 30)
	local spawns = G.Folder(arena, "Spawns")
	local count = 10
	for i = 1, count do
		local a = -Temple.HalfAngle * 0.8 + (i - 1) / (count - 1) * Temple.HalfAngle * 1.6
		local r = if i % 2 == 0 then 70 else 108
		local spot = G.Block(spawns, "Spawn" .. i, CFrame.lookAt(fanPoint(a, r, floor + 0.6), pivot + Vector3.new(0, 0.6, 0)), Vector3.new(4, 1, 4), {
			Color = P.Channel,
			Transparency = 1,
			CanCollide = false,
		})
		G.Tag(spot, "ArenaSpawn")
	end
end

return Temple
