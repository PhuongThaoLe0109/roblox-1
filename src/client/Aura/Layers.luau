-- Aura layers
-- The building blocks every aura is composed from. A layer is created once
-- (parts, beams, lights) and then animated every frame relative to the
-- wearer's root:
--
--   Layers[kind](ctx, spec) -> (t: number, root: CFrame) -> ()
--
-- ctx.Place(part, cframe) queues a move (the renderer flushes all moves with
-- one Workspace:BulkMoveTo per frame). Ribbons are untextured Beams between
-- attachments on an invisible "host" part, so moving or spinning a whole
-- ring costs a single CFrame. Only Neon / Glass / SmoothPlastic parts,
-- Beams, Trails and PointLights: no textures, decals, meshes or particles.

local Layers = {}

export type Context = {
	Parent: Instance,
	Color: Color3,
	Accent: Color3,
	Seed: number,
	Ground: number, -- offset from the root down to the feet (negative)
	Place: (BasePart, CFrame) -> (),
	Rng: Random,
}

export type Update = (t: number, root: CFrame) -> ()

local WHITE = Color3.new(1, 1, 1)
local TAU = math.pi * 2
local GEM_TILT = CFrame.Angles(math.rad(45), 0, math.rad(35.264))

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function lerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- 0 = white-hot, 0.35 = gem colour, 1 = accent.
local function grad(ctx: Context, t: number): Color3
	if t < 0.35 then
		return lerp(WHITE, ctx.Color, t / 0.35)
	end
	return lerp(ctx.Color, ctx.Accent, (t - 0.35) / 0.65)
end
Layers.Grad = grad

local function rainbow(t: number, s: number?, v: number?): Color3
	return Color3.fromHSV(t % 1, s or 0.45, v or 1)
end

local function part(ctx: Context, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.Parent
	return p
end

local function host(ctx: Context): Part
	local h = part(ctx, Vector3.new(0.1, 0.1, 0.1), WHITE, Enum.Material.SmoothPlastic, 1)
	h.Name = "Host"
	return h
end

-- A faceted gem: neon heart inside a tinted glass shell. Returns both parts.
local function gemPair(ctx: Context, size: number, color: Color3): (Part, Part)
	local shell = part(ctx, Vector3.one * size, color, Enum.Material.Glass, 0.2)
	local core = part(ctx, Vector3.one * size * 0.55, lerp(color, WHITE, 0.6))
	return shell, core
end

-- A slim crystal shard (square prism turned 45 degrees).
local function shard(ctx: Context, width: number, length: number, color: Color3, glass: boolean?): Part
	local p = part(ctx, Vector3.new(width, length, width), color, if glass then Enum.Material.Glass else Enum.Material.Neon, if glass then 0.15 else 0)
	return p
end

-- Beam ribbon through local points on `h`. Returns the beams.
local function ribbon(ctx: Context, h: BasePart, points: { Vector3 }, width: number | { number }, color: (number) -> Color3, transparency: number?): { Beam }
	local attachments = {}
	for i, point in points do
		local a = Instance.new("Attachment")
		a.Position = point
		a.Parent = h
		attachments[i] = a
	end
	local beams = {}
	local n = #points
	for i = 1, n - 1 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = attachments[i]
		beam.Attachment1 = attachments[i + 1]
		beam.Width0 = if type(width) == "table" then width[i] else width
		beam.Width1 = if type(width) == "table" then width[i + 1] else width
		beam.Color = ColorSequence.new(color((i - 1) / (n - 1)), color(i / (n - 1)))
		beam.Transparency = NumberSequence.new(transparency or 0.1)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = h
		beams[i] = beam
	end
	return beams
end

local function circle(radius: number, sides: number, y: number?, step: number?): { Vector3 }
	local list = {}
	local k = step or 1
	for i = 0, sides do
		local a = (i * k % sides) / sides * TAU
		list[i + 1] = Vector3.new(math.cos(a) * radius, y or 0, math.sin(a) * radius)
	end
	return list
end

local function fadeBeams(beams: { Beam }, transparency: number)
	local seq = NumberSequence.new(math.clamp(transparency, 0, 1))
	for _, beam in beams do
		beam.Transparency = seq
	end
end

--------------------------------------------------------------------------------
-- Layers
--------------------------------------------------------------------------------

-- Soft light that breathes.
-- { Range, Brightness, Speed }
function Layers.Glow(ctx: Context, spec): Update
	local h = host(ctx)
	local light = Instance.new("PointLight")
	light.Color = ctx.Color
	light.Range = spec.Range or 10
	light.Brightness = spec.Brightness or 1.2
	light.Shadows = false
	light.Parent = h
	local base = light.Brightness
	local speed = spec.Speed or 1.5
	return function(t, root)
		ctx.Place(h, root)
		light.Brightness = base * (0.8 + 0.2 * math.sin(t * speed))
	end
end

-- A glowing ring (polygon or star) at height Y, spinning and tilted.
-- { Y, Radius, Sides, Step (star skip), Width, Speed, Tilt, Wobble, Rainbow,
--   Ground (true = Y is measured from the feet), Transparency, Pulse }
function Layers.Ring(ctx: Context, spec): Update
	local h = host(ctx)
	local sides = spec.Sides or 32
	local beams = ribbon(ctx, h, circle(spec.Radius or 3, sides, 0, spec.Step), spec.Width or 0.25, function(u)
		if spec.Rainbow then
			return rainbow(u)
		end
		return grad(ctx, 0.2 + 0.7 * (0.5 + 0.5 * math.sin(u * TAU * 2)))
	end, spec.Transparency)
	local y = (spec.Y or 0) + (if spec.Ground then ctx.Ground else 0)
	local tilt = CFrame.Angles(math.rad(spec.Tilt or 0), 0, math.rad(spec.Roll or 0))
	local speed = spec.Speed or 0.6
	local wobble = spec.Wobble or 0
	local phase = ctx.Rng:NextNumber() * TAU
	local base = spec.Transparency or 0.1
	return function(t, root)
		local w = if wobble > 0 then CFrame.Angles(math.sin(t * 1.3 + phase) * wobble, 0, math.cos(t * 1.1 + phase) * wobble) else CFrame.identity
		ctx.Place(h, root * CFrame.new(0, y, 0) * tilt * w * CFrame.Angles(0, t * speed + phase, 0))
		if spec.Pulse then
			fadeBeams(beams, base + (1 - base) * (0.5 - 0.5 * math.sin(t * spec.Pulse)) * 0.6)
		end
	end
end

-- Gems, shards or orbs circling the wearer.
-- { Count, Radius, Y, Speed, Bob, Size, Tilt, Shape ("Gem"|"Shard"|"Orb"),
--   Trail, Mode ("Circle"|"Figure8"|"Atom"), Rainbow, Spin }
function Layers.Orbit(ctx: Context, spec): Update
	local count = spec.Count or 3
	local radius = spec.Radius or 3
	local y = spec.Y or 0
	local speed = spec.Speed or 1.2
	local bob = spec.Bob or 0.4
	local size = spec.Size or 0.6
	local shape = spec.Shape or "Gem"
	local mode = spec.Mode or "Circle"
	local tilt = CFrame.Angles(math.rad(spec.Tilt or 0), 0, 0)
	local spin = spec.Spin or 2

	type Body = { Parts: { BasePart }, Phase: number, Plane: CFrame }
	local bodies: { Body } = {}
	for i = 1, count do
		local color = if i % 2 == 0 then ctx.Accent else ctx.Color
		local parts: { BasePart } = {}
		if shape == "Gem" then
			local shell, core = gemPair(ctx, size, color)
			parts = { shell, core }
		elseif shape == "Shard" then
			parts = { shard(ctx, size * 0.45, size * 2.2, color), shard(ctx, size * 0.7, size * 2.6, color, true) }
		else
			local orb = part(ctx, Vector3.one * size, lerp(color, WHITE, 0.3))
			orb.Shape = Enum.PartType.Ball
			parts = { orb }
		end
		if spec.Trail then
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, size * 0.4, 0)
			a0.Parent = parts[1]
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -size * 0.4, 0)
			a1.Parent = parts[1]
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = spec.TrailLife or 0.45
			trail.MinLength = 0.05
			trail.FaceCamera = true
			trail.LightEmission = 1
			trail.LightInfluence = 0
			trail.Color = ColorSequence.new(lerp(color, WHITE, 0.5), if color == ctx.Color then ctx.Accent else ctx.Color)
			trail.Transparency = NumberSequence.new(0.15, 1)
			trail.WidthScale = NumberSequence.new(1, 0)
			trail.Parent = parts[1]
		end
		-- Atom mode: each body gets its own orbital plane.
		local plane = if mode == "Atom" then CFrame.Angles(math.rad(60), (i - 1) / count * math.pi, 0) else CFrame.identity
		table.insert(bodies, { Parts = parts, Phase = (i - 1) / count * TAU, Plane = plane })
	end

	return function(t, root)
		for i, body in bodies do
			local a = t * speed + body.Phase
			local offset
			if mode == "Figure8" then
				local d = 1 + math.sin(a) ^ 2
				offset = Vector3.new(radius * math.cos(a) / d, y + math.sin(t * 2 + i) * bob, radius * math.sin(a) * math.cos(a) / d * 1.6)
			else
				offset = Vector3.new(math.cos(a) * radius, y + math.sin(t * 2.2 + i * 1.7) * bob, math.sin(a) * radius)
			end
			local cf = root * tilt * body.Plane * CFrame.new(offset) * CFrame.Angles(0, t * spin + i, 0)
			for j, p in body.Parts do
				if shape == "Gem" then
					ctx.Place(p, cf * GEM_TILT)
				else
					ctx.Place(p, cf * CFrame.Angles(0, math.rad(45), 0))
				end
				if spec.Rainbow then
					p.Color = rainbow(t * 0.15 + i / count, if j == 2 then 0.2 else 0.5)
				end
			end
		end
	end
end

-- Sparks rising from the feet (or falling from above with Direction = -1).
-- { Count, Radius, Height, Speed, Size, Direction, Swirl, Flicker, Rainbow, Shape }
function Layers.Motes(ctx: Context, spec): Update
	local count = spec.Count or 10
	local radius = spec.Radius or 2.6
	local height = spec.Height or 7
	local speed = spec.Speed or 0.35
	local size = spec.Size or 0.25
	local direction = spec.Direction or 1
	local swirl = spec.Swirl or 0.6
	type Mote = { Part: BasePart, Phase: number, Angle: number, R: number }
	local motes: { Mote } = {}
	for i = 1, count do
		local color = if i % 3 == 0 then WHITE elseif i % 3 == 1 then ctx.Color else ctx.Accent
		local p
		if spec.Shape == "Petal" then
			p = part(ctx, Vector3.new(size * 2.2, size * 0.25, size * 1.3), color)
		else
			p = part(ctx, Vector3.new(size, size * 2, size), color)
		end
		table.insert(motes, {
			Part = p,
			Phase = ctx.Rng:NextNumber(),
			Angle = ctx.Rng:NextNumber() * TAU,
			R = radius * (0.4 + 0.6 * ctx.Rng:NextNumber()),
		})
	end
	return function(t, root)
		for i, m in motes do
			local life = (t * speed + m.Phase) % 1
			local h = if direction > 0 then life * height else (1 - life) * height
			local a = m.Angle + t * swirl + life * 2
			local offset = Vector3.new(math.cos(a) * m.R, ctx.Ground + h, math.sin(a) * m.R)
			local spin = CFrame.Angles(t * 2 + i, t * 3 + i, 0)
			ctx.Place(m.Part, root * CFrame.new(offset) * spin)
			local fade = math.sin(life * math.pi)
			local flicker = if spec.Flicker then 0.5 + 0.5 * math.sin(t * 17 + i * 3) else 1
			m.Part.Transparency = 1 - fade * flicker * 0.95
			if spec.Rainbow then
				m.Part.Color = rainbow(life + i / count)
			end
		end
	end
end

-- Crystal wings on the back.
-- { Feathers, Span, Size, Flap, Glass, Rainbow, Y }
function Layers.Wings(ctx: Context, spec): Update
	local feathers = spec.Feathers or 4
	local span = spec.Span or 4
	local size = spec.Size or 1
	local flap = spec.Flap or 0.25
	local y = spec.Y or 0.8
	type Feather = { Parts: { BasePart }, Side: number, Index: number }
	local list: { Feather } = {}
	for side = -1, 1, 2 do
		for i = 1, feathers do
			local length = size * (2.6 + (feathers - i) * 0.55)
			local color = grad(ctx, 0.4 + 0.6 * i / feathers)
			local parts = { shard(ctx, size * 0.32, length, color) }
			if spec.Glass ~= false then
				table.insert(parts, shard(ctx, size * 0.55, length * 1.06, color, true))
			end
			table.insert(list, { Parts = parts, Side = side, Index = i })
		end
	end
	return function(t, root)
		local beat = math.sin(t * 2.4) * flap
		for _, f in list do
			local fan = math.rad(25 + (f.Index - 1) * (80 / math.max(1, feathers - 1)))
			local reach = span * (0.35 + 0.65 * f.Index / feathers) * 0.5
			local cf = root
				* CFrame.new(f.Side * 0.6, y, 0.75)
				* CFrame.Angles(0, f.Side * (0.35 + beat), 0)
				* CFrame.Angles(0, 0, -f.Side * fan)
				* CFrame.new(0, reach, 0)
			for _, p in f.Parts do
				ctx.Place(p, cf * CFrame.Angles(0, math.rad(45), 0))
			end
			if spec.Rainbow then
				f.Parts[1].Color = rainbow(t * 0.2 + f.Index / feathers)
			end
		end
	end
end

-- Spikes standing in a circle above the head.
-- { Count, Radius, Y, Height, Speed, Tall (every other spike longer) }
function Layers.Crown(ctx: Context, spec): Update
	local count = spec.Count or 7
	local radius = spec.Radius or 1.1
	local y = spec.Y or 3
	local height = spec.Height or 1
	local speed = spec.Speed or 0.4
	local spikes = {}
	for i = 1, count do
		local h = height * (if spec.Tall and i % 2 == 0 then 1.6 else 1)
		table.insert(spikes, { Part = shard(ctx, 0.28, h, if i % 2 == 0 then ctx.Accent else ctx.Color), Height = h })
	end
	local jewel: { BasePart } = {}
	if spec.Jewel then
		local shell, core = gemPair(ctx, 0.5, ctx.Color)
		jewel = { shell, core }
	end
	return function(t, root)
		local bob = math.sin(t * 1.5) * 0.12
		for i, s in spikes do
			local a = (i - 1) / count * TAU + t * speed
			local cf = root * CFrame.new(math.cos(a) * radius, y + bob + s.Height / 2, math.sin(a) * radius) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-12))
			ctx.Place(s.Part, cf * CFrame.Angles(0, math.rad(45), 0))
		end
		for _, p in jewel do
			ctx.Place(p, root * CFrame.new(0, y + bob + height * 1.4, 0) * CFrame.Angles(0, t * 2, 0) * GEM_TILT)
		end
	end
end

-- Ribbons spiralling up around the body.
-- { Strands, Radius, Height, Turns, Speed, Width, Rainbow }
function Layers.Helix(ctx: Context, spec): Update
	local strands = spec.Strands or 2
	local radius = spec.Radius or 2.2
	local height = spec.Height or 7
	local turns = spec.Turns or 1.5
	local h = host(ctx)
	local samples = math.floor(10 * turns + 4)
	for s = 1, strands do
		local points, widths = {}, {}
		for i = 0, samples do
			local u = i / samples
			local a = u * turns * TAU + (s - 1) / strands * TAU
			points[i + 1] = Vector3.new(math.cos(a) * radius, ctx.Ground + u * height, math.sin(a) * radius)
			widths[i + 1] = (spec.Width or 0.3) * math.sin(math.pi * u)
		end
		ribbon(ctx, h, points, widths, function(u)
			if spec.Rainbow then
				return rainbow(u + s / strands)
			end
			return grad(ctx, if s % 2 == 0 then 1 - u * 0.8 else 0.2 + u * 0.8)
		end, spec.Transparency or 0.15)
	end
	local speed = spec.Speed or 1.4
	return function(t, root)
		ctx.Place(h, root * CFrame.Angles(0, t * speed, 0))
	end
end

-- A wheel of shards standing behind the wearer.
-- { Count, Radius, Y, Size, Speed, Rings }
function Layers.Mandala(ctx: Context, spec): Update
	local count = spec.Count or 10
	local radius = spec.Radius or 2.6
	local y = spec.Y or 1
	local size = spec.Size or 0.9
	local speed = spec.Speed or 0.5
	local h = host(ctx)
	ribbon(ctx, h, circle(radius * 0.62, 24), 0.18, function(u)
		return grad(ctx, 0.3 + 0.6 * u)
	end, 0.2)
	if spec.Rings and spec.Rings > 1 then
		ribbon(ctx, h, circle(radius * 1.12, 6, 0, 1), 0.12, function(u)
			return grad(ctx, 0.9 - 0.6 * u)
		end, 0.3)
	end
	local shards = {}
	for i = 1, count do
		table.insert(shards, shard(ctx, size * 0.35, size * 1.8, grad(ctx, 0.2 + 0.8 * ((i % 3) / 2))))
	end
	return function(t, root)
		local frame = root * CFrame.new(0, y, 1.3) * CFrame.Angles(math.rad(90), 0, 0)
		ctx.Place(h, frame * CFrame.Angles(0, -t * speed * 0.6, 0))
		for i, p in shards do
			local a = (i - 1) / count * TAU + t * speed
			ctx.Place(p, frame * CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(90)))
		end
	end
end

-- Vertical beams of light standing around the body, shimmering.
-- { Count, Radius, Height, Width, Speed }
function Layers.Pillars(ctx: Context, spec): Update
	local count = spec.Count or 6
	local radius = spec.Radius or 2.4
	local height = spec.Height or 9
	local h = host(ctx)
	local beams = {}
	for i = 1, count do
		local a = (i - 1) / count * TAU
		local base = Vector3.new(math.cos(a) * radius, ctx.Ground, math.sin(a) * radius)
		local list = ribbon(ctx, h, { base, base + Vector3.new(0, height * 0.5, 0), base + Vector3.new(0, height, 0) }, { spec.Width or 0.5, (spec.Width or 0.5) * 0.6, 0 }, function(u)
			return grad(ctx, 0.15 + 0.85 * u)
		end, 0.4)
		table.insert(beams, list)
	end
	local speed = spec.Speed or 0.3
	return function(t, root)
		ctx.Place(h, root * CFrame.Angles(0, t * speed, 0))
		for i, list in beams do
			fadeBeams(list, 0.35 + 0.5 * (0.5 + 0.5 * math.sin(t * 3 + i * 1.9)))
		end
	end
end

-- The gem itself floating above the head.
-- { Size, Y, Speed, Rainbow, Satellites }
function Layers.Crest(ctx: Context, spec): Update
	local size = spec.Size or 1
	local y = spec.Y or 4
	local shell, core = gemPair(ctx, size, ctx.Color)
	local light = Instance.new("PointLight")
	light.Color = ctx.Color
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = core
	local h = host(ctx)
	ribbon(ctx, h, circle(size * 1.25, 20), 0.12, function(u)
		return grad(ctx, 0.3 + 0.6 * u)
	end, 0.2)
	local speed = spec.Speed or 1.6
	return function(t, root)
		local cf = root * CFrame.new(0, y + math.sin(t * 1.7) * 0.25, 0)
		local turn = CFrame.Angles(0, t * speed, 0)
		ctx.Place(shell, cf * turn * GEM_TILT)
		ctx.Place(core, cf * turn * GEM_TILT)
		ctx.Place(h, cf * CFrame.Angles(math.rad(70), t * 0.8, 0))
		if spec.Rainbow then
			shell.Color = rainbow(t * 0.1)
		end
	end
end

-- Tiny stars twinkling in a sphere around the wearer.
-- { Count, Radius, Size, Speed }
function Layers.Stars(ctx: Context, spec): Update
	local count = spec.Count or 18
	local radius = spec.Radius or 4.5
	local size = spec.Size or 0.18
	local stars = {}
	for i = 1, count do
		local dir = Vector3.new(ctx.Rng:NextNumber(-1, 1), ctx.Rng:NextNumber(-0.6, 1), ctx.Rng:NextNumber(-1, 1))
		dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
		local p = part(ctx, Vector3.one * size * (0.6 + ctx.Rng:NextNumber()), if i % 4 == 0 then ctx.Accent elseif i % 4 == 1 then ctx.Color else WHITE)
		table.insert(stars, { Part = p, Offset = dir * radius * (0.55 + 0.45 * ctx.Rng:NextNumber()), Phase = ctx.Rng:NextNumber() * TAU, Rate = 2 + ctx.Rng:NextNumber() * 4 })
	end
	local speed = spec.Speed or 0.15
	return function(t, root)
		local turn = root * CFrame.Angles(0, t * speed, 0)
		for _, s in stars do
			ctx.Place(s.Part, turn * CFrame.new(s.Offset) * CFrame.Angles(0, 0, math.rad(45)))
			s.Part.Transparency = 0.15 + 0.85 * (0.5 + 0.5 * math.sin(t * s.Rate + s.Phase)) ^ 3
		end
	end
end

-- Jagged arcs of energy crackling around the body.
-- { Arcs, Radius, Height, Rate, Width }
function Layers.Lightning(ctx: Context, spec): Update
	local arcs = spec.Arcs or 3
	local radius = spec.Radius or 2.6
	local height = spec.Height or 6
	local rate = spec.Rate or 0.09
	local h = host(ctx)
	local SEG = 6
	type Arc = { Attachments: { Attachment }, Beams: { Beam } }
	local list: { Arc } = {}
	for _ = 1, arcs do
		local points = table.create(SEG + 1, Vector3.zero)
		local beams = ribbon(ctx, h, points, spec.Width or 0.18, function(u)
			return grad(ctx, u * 0.6)
		end, 0)
		local attachments = {}
		for _, beam in beams do
			table.insert(attachments, beam.Attachment0 :: Attachment)
		end
		table.insert(attachments, beams[#beams].Attachment1 :: Attachment)
		table.insert(list, { Attachments = attachments, Beams = beams })
	end
	local nextStrike = 0
	return function(t, root)
		ctx.Place(h, root)
		if t < nextStrike then
			return
		end
		nextStrike = t + rate
		for _, arc in list do
			local a0 = ctx.Rng:NextNumber() * TAU
			local a1 = a0 + ctx.Rng:NextNumber(0.6, 2.2)
			local y0 = ctx.Ground + ctx.Rng:NextNumber() * height
			local y1 = ctx.Ground + ctx.Rng:NextNumber() * height
			local visible = ctx.Rng:NextNumber() < 0.75
			for i, a in arc.Attachments do
				local u = (i - 1) / SEG
				local ang = a0 + (a1 - a0) * u
				local r = radius + ctx.Rng:NextNumber(-0.5, 0.5)
				a.Position = Vector3.new(math.cos(ang) * r, y0 + (y1 - y0) * u + ctx.Rng:NextNumber(-0.4, 0.4), math.sin(ang) * r)
			end
			fadeBeams(arc.Beams, if visible then 0 else 1)
		end
	end
end

-- A dark disc ringed with light behind the head, with a flaring corona.
-- { Radius, Y, Rays }
function Layers.Eclipse(ctx: Context, spec): Update
	local radius = spec.Radius or 1.6
	local y = spec.Y or 2.4
	local disc = part(ctx, Vector3.one * radius * 2, Color3.fromRGB(12, 6, 24), Enum.Material.SmoothPlastic, 0)
	disc.Shape = Enum.PartType.Ball
	local h = host(ctx)
	ribbon(ctx, h, circle(radius * 1.05, 32), 0.35, function(u)
		return grad(ctx, 0.1 + 0.5 * (0.5 + 0.5 * math.sin(u * TAU * 3)))
	end, 0)
	ribbon(ctx, h, circle(radius * 1.35, 32), 0.6, function(u)
		return grad(ctx, 0.6 + 0.4 * u)
	end, 0.6)
	local rays = {}
	for i = 1, spec.Rays or 12 do
		table.insert(rays, shard(ctx, 0.14, radius * 0.9, if i % 2 == 0 then ctx.Color else ctx.Accent))
	end
	return function(t, root)
		local center = root * CFrame.new(0, y, 1.6)
		ctx.Place(disc, center)
		ctx.Place(h, center * CFrame.Angles(math.rad(90), t * 0.4, 0))
		for i, ray in rays do
			local a = (i - 1) / #rays * TAU + t * 0.25
			local reach = radius * (1.75 + 0.25 * math.sin(t * 3 + i))
			ctx.Place(ray, center * CFrame.Angles(0, 0, a) * CFrame.new(0, reach, 0))
		end
	end
end

-- Rings of light rolling out from the feet at an interval.
-- { Interval, Radius, Width, Sides }
function Layers.Pulse(ctx: Context, spec): Update
	local interval = spec.Interval or 1.8
	local radius = spec.Radius or 6
	local sides = spec.Sides or 32
	local h = host(ctx)
	local unit = circle(1, sides)
	local beams = ribbon(ctx, h, unit, spec.Width or 0.4, function(u)
		return grad(ctx, 0.2 + 0.7 * (0.5 + 0.5 * math.sin(u * TAU * 3)))
	end, 1)
	local attachments = {}
	for _, beam in beams do
		table.insert(attachments, beam.Attachment0 :: Attachment)
	end
	table.insert(attachments, beams[#beams].Attachment1 :: Attachment)
	return function(t, root)
		local life = (t / interval) % 1
		local r = 0.5 + radius * (1 - (1 - life) ^ 3)
		ctx.Place(h, root * CFrame.new(0, ctx.Ground + 0.15, 0))
		for i, a in attachments do
			a.Position = unit[i] * r
		end
		fadeBeams(beams, 0.1 + 0.9 * life ^ 1.5)
	end
end

-- Large crystal shards floating upright around the wearer.
-- { Count, Radius, Height, Size, Speed }
function Layers.Monoliths(ctx: Context, spec): Update
	local count = spec.Count or 4
	local radius = spec.Radius or 3.4
	local size = spec.Size or 1
	local speed = spec.Speed or 0.35
	local list = {}
	for i = 1, count do
		local length = size * (2.4 + ctx.Rng:NextNumber() * 1.4)
		local color = if i % 2 == 0 then ctx.Accent else ctx.Color
		table.insert(list, {
			Shell = shard(ctx, size * 0.9, length, color, true),
			Core = shard(ctx, size * 0.4, length * 0.85, lerp(color, WHITE, 0.4)),
			Phase = (i - 1) / count * TAU,
			Y = (spec.Height or 0.5) + ctx.Rng:NextNumber() * 1.2,
		})
	end
	return function(t, root)
		for i, m in list do
			local a = m.Phase + t * speed
			local cf = root * CFrame.new(math.cos(a) * radius, m.Y + math.sin(t * 1.4 + i) * 0.35, math.sin(a) * radius) * CFrame.Angles(0, t * 0.8 + i, 0) * CFrame.Angles(0, math.rad(45), 0)
			ctx.Place(m.Shell, cf)
			ctx.Place(m.Core, cf)
		end
	end
end

return Layers
