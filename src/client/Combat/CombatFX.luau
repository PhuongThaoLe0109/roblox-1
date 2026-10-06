-- CombatFX
-- Every combat effect, drawn locally on each client from CombatFX events.
-- Nothing here uses textures, decals, ParticleEmitters or meshes: effects are
-- built from Neon / Glass parts, untextured Beams and Trails (whose colour and
-- transparency sequences give the show's soft gradients), PointLights and
-- Highlights. Every effect uses the caster's gem colours.
--
-- The look is cel-shaded anime: effects are built in bands (a white-hot core,
-- the gem colour, then a dark ink edge, Toon.Ink), slashes and shock rings
-- carry an ink outline behind their glow and fade in hard steps, big pieces
-- get Highlight ink outlines (through Toon's budget), and heavy blows that
-- involve you add an impact frame, speed lines and a short hit-stop.
--
-- The local player's own swings / casts are drawn immediately by
-- CombatController (CombatFX.Play) and the server echo is skipped, so attacks
-- feel instant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Auras = require(script.Parent.Parent:WaitForChild("Aura"):WaitForChild("Auras"))
local CombatAnim = require(script.Parent:WaitForChild("CombatAnim"))
local Cutscene = require(script.Parent:WaitForChild("Cutscene"))
local Toon = require(script.Parent.Parent:WaitForChild("Toon"))

local player = Players.LocalPlayer

local CombatFX = {}

-- Set by BeastFX: plays a beast's maul attack (character, combo).
CombatFX.OnBeastAttack = nil :: ((Instance, number) -> ())?

-- The body motion that goes with each effect (played on its caster). Casts
-- use their skill's own archetype motion (Volley, Lance, Orbs, Boomerang).
local MOTION: { [string]: string } = {
	Launcher = "Launcher",
	Rush = "Rush",
	SlamLeap = "SlamLeap",
	Flurry = "Flurry",
	Nova = "NovaRelease",
	Rain = "Rain",
	Bloom = "Bloom",
	Vortex = "Vortex",
	Chain = "Chain",
	Bind = "Bind",
	Trap = "Trap",
	Frostbite = "Frostbite",
	Curse = "Curse",
	Pillars = "Pillars",
	Grab = "Grab",
	Blink = "Blink",
	Shield = "Shield",
	Domain = "Domain",
	Transform = "Transform",
	TransformEnd = "Reform",
}

-- Motion name, how long to hold its charge, and a duration to stretch it to.
local function motionFor(kind: string, params: { [string]: any }): (string?, number?, number?)
	if kind == "Cast" then
		local archetype = params.Archetype
		return if type(archetype) == "string" and CombatAnim.Has(archetype) then archetype else "Cast"
	elseif kind == "NovaCharge" then
		return "NovaCharge", params.Duration or 0.55
	elseif kind == "Meteor" then
		-- Hand held to the sky until the star is about to land, then dragged down.
		return "Meteor", math.max(0, (params.Delay or 1) - 0.56)
	elseif kind == "Beam" then
		return "Beam", math.max(0, (params.Duration or 1.2) - 0.42)
	elseif kind == "Spin" then
		return "Spin", nil, params.Duration
	end
	return MOTION[kind]
end

local WHITE = Color3.new(1, 1, 1)

-- Effects the local player predicts (the server echo for their own character
-- is ignored).
local PREDICTED = {
	Swing = true,
}

local folder: Folder
local host: Part -- anchored at the origin; owns every world-space attachment

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------

local function lerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- White-hot at 0, the gem colour in the middle, the accent at 1.
local function grad(color: Color3, accent: Color3, t: number): Color3
	if t < 0.35 then
		return lerp(WHITE, color, t / 0.35)
	end
	return lerp(color, accent, (t - 0.35) / 0.65)
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

local function part(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0
	p.Size = size
	p.CFrame = cframe
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function attachment(position: Vector3, parent: Instance?): Attachment
	local a = Instance.new("Attachment")
	a.Position = position
	a.Parent = parent or host
	return a
end

-- Runs step(alpha, elapsed) every frame for `duration`, then cleanup().
-- Animates an effect over `duration` seconds of effect time (slowed down
-- during ultimate cutscenes). `step` may return true to end early.
local frozenUntil = 0 -- hit-stop: effects hold still until then
local function run(duration: number, step: (number, number) -> boolean?, cleanup: (() -> ())?)
	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if os.clock() >= frozenUntil then
			elapsed += dt * Cutscene.TimeScale
		end
		local alpha = math.min(1, elapsed / duration)
		local ok, err = pcall(step, alpha, elapsed)
		if not ok or alpha >= 1 or err == true then
			connection:Disconnect()
			if cleanup then
				cleanup()
			end
			if not ok then
				warn("[CombatFX] " .. tostring(err))
			end
		end
	end)
end

local function light(position: Vector3, color: Color3, range: number, brightness: number, duration: number)
	local holder = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), color, Enum.Material.SmoothPlastic, 1)
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Range = range
	pl.Brightness = brightness
	pl.Shadows = false
	pl.Parent = holder
	run(duration, function(alpha)
		pl.Brightness = brightness * (1 - alpha) ^ 2
	end, function()
		holder:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Ribbons: chains of untextured Beams with a colour gradient along them.
--------------------------------------------------------------------------------

type Ribbon = { Attachments: { Attachment }, Beams: { Beam } }

local function ribbon(points: { Vector3 }, widths: { number }, colors: { Color3 }, faceCamera: boolean?): Ribbon
	local r: Ribbon = { Attachments = {}, Beams = {} }
	for i, point in points do
		r.Attachments[i] = attachment(point)
	end
	for i = 1, #points - 1 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = r.Attachments[i]
		beam.Attachment1 = r.Attachments[i + 1]
		beam.Width0 = widths[i]
		beam.Width1 = widths[i + 1]
		beam.Color = ColorSequence.new(colors[i], colors[i + 1])
		beam.Transparency = NumberSequence.new(1)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = if faceCamera == nil then true else faceCamera
		beam.Segments = 1
		beam.Parent = host
		r.Beams[i] = beam
	end
	return r
end

local function ribbonMove(r: Ribbon, points: { Vector3 })
	for i, point in points do
		local a = r.Attachments[i]
		if a then
			a.Position = point
		end
	end
end

local function ribbonWidths(r: Ribbon, widths: { number })
	for i, beam in r.Beams do
		beam.Width0 = widths[i]
		beam.Width1 = widths[i + 1]
	end
end

-- transparency(i) for each point; beams blend between their two ends.
local function ribbonFade(r: Ribbon, transparency: (number) -> number)
	local values = {}
	for i = 1, #r.Attachments do
		values[i] = math.clamp(transparency(i), 0, 1)
	end
	for i, beam in r.Beams do
		beam.Transparency = NumberSequence.new(values[i], values[i + 1])
	end
end

local function ribbonDestroy(r: Ribbon)
	for _, beam in r.Beams do
		beam:Destroy()
	end
	for _, a in r.Attachments do
		a:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Shapes
--------------------------------------------------------------------------------

-- A crescent slash sweeping from angle a0 to a1 (degrees) in the XZ plane of
-- `frame` (forward = -Z), rolled about the forward axis by `roll` degrees.
-- Drawn like an anime smear: a dark ink outline, the saturated gem colour, a
-- white-hot core and a faint bloom; thick in the middle, thin at the ends,
-- fading out in hard steps rather than a soft blur.
local function slash(frame: CFrame, radius: number, a0: number, a1: number, roll: number, width: number, color: Color3, accent: Color3, duration: number)
	local n = 12
	local plane = frame * CFrame.Angles(0, 0, math.rad(roll))
	local function pointsAt(scale: number): { Vector3 }
		local list = {}
		for i = 0, n do
			local a = math.rad(a0 + (a1 - a0) * i / n)
			list[i + 1] = plane:PointToWorldSpace(Vector3.new(math.sin(a), 0, -math.cos(a)) * radius * scale)
		end
		return list
	end
	local function widthsOf(w: number): { number }
		local list = {}
		for i = 0, n do
			local t = i / n
			-- Crescent: thin tail, thick just behind the head, sharp tip.
			list[i + 1] = w * (0.06 + 0.94 * math.sin(math.pi * math.min(1, t * 0.85 + 0.08)) * t ^ 0.6)
		end
		return list
	end
	local inkColor = Toon.Ink(color)
	local colorsBody, colorsCore, colorsGlow, colorsInk = {}, {}, {}, {}
	for i = 0, n do
		local t = 1 - i / n
		colorsBody[i + 1] = grad(color, accent, t * 0.8)
		colorsCore[i + 1] = lerp(WHITE, Toon.Shade(color, 0.6), t * 0.5)
		colorsGlow[i + 1] = grad(color, accent, 0.3 + t * 0.7)
		colorsInk[i + 1] = inkColor
	end
	local start = pointsAt(1)
	local glow = ribbon(start, widthsOf(width * 2.2), colorsGlow)
	local ink = ribbon(start, widthsOf(width * 1.4), colorsInk)
	local body = ribbon(start, widthsOf(width), colorsBody)
	local core = ribbon(start, widthsOf(width * 0.42), colorsCore)
	for _, beam in ink.Beams do
		beam.LightEmission = 0
		beam.ZOffset = -0.2
	end
	for _, beam in body.Beams do
		beam.LightEmission = 0.45
	end
	for _, beam in core.Beams do
		beam.ZOffset = 0.2
	end
	local layers = { { glow, 0.78 }, { ink, 0.05 }, { body, 0 }, { core, 0 } }
	local sweep = duration * 0.3
	run(duration, function(_, elapsed)
		local head = math.min(1, elapsed / sweep)
		local scale = 1 + 0.16 * easeOut(math.min(1, elapsed / duration))
		local points = pointsAt(scale)
		local fadeSpan = duration - sweep
		for _, layer in layers do
			local r, base = layer[1], layer[2]
			ribbonMove(r, points)
			ribbonFade(r, function(i: number): number
				local t = (i - 1) / n
				if t > head + 1e-3 then
					return 1
				end
				-- Hard steps (anime frames) instead of a smooth fade.
				local since = math.clamp((elapsed - t * sweep) / fadeSpan, 0, 1)
				local stepped = math.floor(since * 4) / 4
				return base + (1 - base) * stepped ^ 1.2
			end)
		end
		return nil
	end, function()
		for _, layer in layers do
			ribbonDestroy(layer[1])
		end
	end)
end

-- Angular crystal fragments (wedges) tumbling out of `position`.
local function shards(position: Vector3, color: Color3, accent: Color3, count: number, speed: number, size: number, life: number, bias: Vector3?)
	for i = 1, count do
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 - 0.1, math.random() - 0.5)
		if bias then
			dir += bias
		end
		dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
		local s = size * (0.5 + math.random() * 0.8)
		local wedge = Instance.new("WedgePart")
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.CanTouch = false
		wedge.CastShadow = false
		wedge.Material = if i % 3 == 0 then Enum.Material.Neon else Enum.Material.Glass
		wedge.Color = if i % 3 == 0 then WHITE elseif i % 2 == 0 then color else Toon.Shade(accent, -0.35)
		wedge.Transparency = if wedge.Material == Enum.Material.Glass then 0.1 else 0
		wedge.Size = Vector3.new(s * 0.4, s, s * 0.7)
		wedge.CFrame = CFrame.new(position)
		wedge.Parent = folder
		local v = dir * speed * (0.6 + math.random() * 0.6)
		local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 16
		local base = wedge.Transparency
		run(life * (0.7 + math.random() * 0.5), function(alpha, elapsed)
			local p = position + v * elapsed + Vector3.new(0, -28 * elapsed * elapsed, 0)
			wedge.CFrame = CFrame.new(p) * CFrame.Angles(spin.X * elapsed, spin.Y * elapsed, spin.Z * elapsed)
			wedge.Transparency = base + (1 - base) * alpha ^ 2
			return nil
		end, function()
			wedge:Destroy()
		end)
	end
end

-- A heavy blow that involves you: impact frame, speed lines, hit-stop.
local function impact(position: Vector3, color: Color3, strength: number)
	Toon.ImpactFrame(strength)
	Toon.SpeedLines(position, color, math.floor(14 + 8 * strength))
	Toon.HitStop(0.05)
end

-- With `ink`, it is the dark outline band drawn behind a bright ring.
local function ring(frame: CFrame, r0: number, r1: number, w0: number, w1: number, color: Color3, accent: Color3, duration: number, sides: number?, startTransparency: number?, ink: boolean?)
	local n = sides or 28
	local function pointsAt(radius: number): { Vector3 }
		local list = {}
		for i = 0, n do
			local a = i / n * math.pi * 2
			list[i + 1] = frame:PointToWorldSpace(Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
		end
		return list
	end
	local colors, widths = {}, {}
	for i = 0, n do
		colors[i + 1] = grad(color, accent, 0.25 + 0.6 * (0.5 + 0.5 * math.sin(i / n * math.pi * 4)))
		widths[i + 1] = w0
	end
	local r = ribbon(pointsAt(r0), widths, colors)
	if ink then
		local dark = Toon.Ink(color)
		for _, beam in r.Beams do
			beam.Color = ColorSequence.new(dark)
			beam.LightEmission = 0
			beam.ZOffset = -0.2
		end
	end
	local base = startTransparency or 0.05
	run(duration, function(alpha)
		local e = easeOut(alpha)
		ribbonMove(r, pointsAt(r0 + (r1 - r0) * e))
		local w = w0 + (w1 - w0) * e
		local list = table.create(n + 1, w)
		ribbonWidths(r, list)
		ribbonFade(r, function()
			return base + (1 - base) * alpha ^ 1.6
		end)
	end, function()
		ribbonDestroy(r)
	end)
end

-- Neon diamond sparks flying out of `position`.
local function burst(position: Vector3, color: Color3, accent: Color3, count: number, speed: number, size: number, life: number, bias: Vector3?)
	for i = 1, count do
		local dir = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5)
		if bias then
			dir += bias
		end
		dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
		local tint = if i % 3 == 0 then WHITE elseif i % 3 == 1 then color else accent
		local s = size * (0.6 + math.random() * 0.6)
		local spark = part(Vector3.new(s * 0.5, s * 0.5, s * 2.2), CFrame.lookAt(position, position + dir), tint)
		local v = speed * (0.6 + math.random() * 0.7)
		local p = position
		run(life * (0.7 + math.random() * 0.5), function(alpha)
			p += dir * v * (1 - alpha) * (1 / 60)
			local k = 1 - alpha
			spark.Size = Vector3.new(s * 0.5 * k + 0.05, s * 0.5 * k + 0.05, s * 2.2 * k + 0.05)
			spark.CFrame = CFrame.lookAt(p, p + dir)
			spark.Transparency = alpha ^ 2
		end, function()
			spark:Destroy()
		end)
	end
end

-- A soft glowing sphere flash.
local function flash(position: Vector3, color: Color3, size0: number, size1: number, life: number, transparency: number?)
	local ball = part(Vector3.one * size0, CFrame.new(position), color)
	ball.Shape = Enum.PartType.Ball
	local base = transparency or 0.35
	run(life, function(alpha)
		local s = size0 + (size1 - size0) * easeOut(alpha)
		ball.Size = Vector3.one * s
		ball.Transparency = base + (1 - base) * alpha
	end, function()
		ball:Destroy()
	end)
end

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(position: Vector3): Vector3?
	local exclude: { Instance } = { folder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	castParams.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), castParams)
	return hit and hit.Position
end

-- Faceted crystal spikes erupting from the ground in a circle.
local function spikes(center: Vector3, count: number, radius: number, height: number, color: Color3, accent: Color3, life: number, delay: number?)
	local ground = groundBelow(center)
	if not ground then
		return
	end
	task.delay(delay or 0, function()
		-- One ink outline around the whole crown of spikes.
		local group = Instance.new("Model")
		group.Name = "Spikes"
		group.Parent = folder
		Toon.Outline(group, color, Toon.Priority.Effect, 1, group)
		task.delay(life + 0.1, function()
			group:Destroy()
		end)
		for i = 1, count do
			local a = (i / count + math.random() * 0.04) * math.pi * 2
			local h = height * (0.7 + math.random() * 0.5)
			local w = h * 0.28
			local base = ground + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			local outward = Vector3.new(math.cos(a), 0, math.sin(a))
			local tilt = CFrame.fromAxisAngle(outward:Cross(Vector3.yAxis), -math.rad(18 + math.random() * 14))
			local shell = part(Vector3.new(w, h, w), CFrame.new(), if i % 2 == 0 then color else accent, Enum.Material.Glass, 0.15)
			local core = part(Vector3.new(w * 0.45, h * 0.92, w * 0.45), CFrame.new(), WHITE)
			shell.Parent = group
			core.Parent = group
			local spin = CFrame.Angles(0, math.rad(45), 0)
			local function place(rise: number)
				local cf = CFrame.new(base) * tilt * CFrame.new(0, h / 2 - h * (1 - rise), 0) * spin
				shell.CFrame = cf
				core.CFrame = cf
			end
			place(0)
			run(life, function(alpha)
				if alpha < 0.12 then
					place(easeOut(alpha / 0.12))
				elseif alpha > 0.7 then
					local k = (alpha - 0.7) / 0.3
					place(1 - k)
					shell.Transparency = 0.15 + 0.85 * k
					core.Transparency = k
				else
					place(1)
				end
			end, function()
				shell:Destroy()
				core:Destroy()
			end)
		end
	end)
end

-- The shared "detonation" layer for big AoE hits: a white-hot core, a glass
-- shockwave dome that races out to the edge of the hit area, a scorched ground
-- disc, rising embers and a ground crack ring. `power` (0..1+) scales it all.
local function explosion(center: Vector3, radius: number, color: Color3, accent: Color3, power: number?)
	local k = power or 1
	local ground = groundBelow(center + Vector3.new(0, 2, 0)) or (center - Vector3.new(0, 3, 0))

	-- Core: a blinding white ball that pops then sinks into the colour.
	flash(center, WHITE, 1.5, radius * 0.55 * k, 0.16, 0.05)
	flash(center, accent, 2, radius * 0.9, 0.3, 0.3)

	-- Shockwave dome: a hollow glass sphere sweeping to the edge of the area,
	-- inked around its rim.
	local dome = part(Vector3.one, CFrame.new(ground), color, Enum.Material.Glass, 0.4)
	dome.Shape = Enum.PartType.Ball
	Toon.Outline(dome, color, Toon.Priority.Effect, 1, folder)
	run(0.42, function(alpha)
		local d = radius * 2.1 * easeOut(alpha)
		dome.Size = Vector3.new(d, d * 0.55, d)
		dome.CFrame = CFrame.new(ground)
		dome.Transparency = 0.4 + 0.6 * alpha ^ 0.8
	end, function()
		dome:Destroy()
	end)

	-- Two shock rings on the floor: a fast thin one and a slow heavy one.
	local floor = CFrame.new(ground + Vector3.new(0, 0.25, 0))
	ring(floor, radius * 0.2, radius * 1.15, 1.2 * k, 0.15, WHITE, accent, 0.3, 44, 0)
	task.delay(0.05, function()
		ring(floor * CFrame.new(0, 0.05, 0), radius * 0.1, radius, 4.8 * k, 0.8, color, accent, 0.65, 44, 0.05, true)
		ring(floor * CFrame.new(0, 0.1, 0), radius * 0.1, radius, 3.2 * k, 0.5, color, accent, 0.65, 44)
	end)
	shards(center, color, accent, math.floor(8 + 6 * k), 40, 1.6, 0.8, Vector3.new(0, 0.6, 0))
	-- Felt up close: impact frame, speed lines, hit-stop.
	local own = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if own and own:IsA("BasePart") and (own.Position - center).Magnitude < radius * 1.6 then
		impact(center, color, math.min(1, 0.6 + 0.3 * k))
	end

	-- Scorch: a dark glossy disc that lingers and fades, so the hit leaves a mark.
	local scorch = part(Vector3.new(0.15, 1, 1), CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), lerp(color, Color3.new(0.05, 0.03, 0.08), 0.7), Enum.Material.Glass, 0.25)
	scorch.Shape = Enum.PartType.Cylinder
	run(1.6, function(alpha)
		local d = radius * 1.5 * easeOut(math.min(1, alpha * 6))
		scorch.Size = Vector3.new(0.15, d, d)
		scorch.Transparency = 0.25 + 0.75 * math.max(0, alpha - 0.4) / 0.6
	end, function()
		scorch:Destroy()
	end)

	-- Embers rising from the whole area, then a ring of sparks along the edge.
	for i = 1, math.floor(10 * k + 0.5) do
		local a = math.random() * math.pi * 2
		local r = math.sqrt(math.random()) * radius
		local p = ground + Vector3.new(math.cos(a) * r, 0.5, math.sin(a) * r)
		task.delay(math.random() * 0.15, function()
			burst(p, color, accent, 2, 26, 0.8, 0.55, Vector3.new(0, 2.2, 0))
		end)
	end
	burst(center, color, accent, math.floor(14 * k + 0.5), 55, 1.2, 0.5, Vector3.new(0, 0.35, 0))
	light(center + Vector3.new(0, 4, 0), WHITE, radius * 2.4, 9 * k, 0.25)
	light(center, color, radius * 3, 6 * k, 0.8)
end

-- Short trail on a character's root.
local function rootTrail(character: Model, color: Color3, accent: Color3, duration: number, height: number?)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local h = height or 2.2
	local a0 = attachment(Vector3.new(0, h, 0), root)
	local a1 = attachment(Vector3.new(0, -h, 0), root)
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.28
	trail.MinLength = 0.05
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.35, color),
		ColorSequenceKeypoint.new(1, accent),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	trail.Parent = root
	task.delay(duration, function()
		trail.Enabled = false
		task.wait(0.35)
		trail:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- Fading neon silhouettes left behind a fast-moving character.
local function afterimages(character: Model, color: Color3, accent: Color3, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	task.spawn(function()
		local count = math.max(2, math.floor(duration / 0.05))
		for i = 1, count do
			if not root.Parent then
				return
			end
			local cf = (root :: BasePart).CFrame
			local ghost = part(Vector3.new(2.2, 4.6, 0.25), cf * CFrame.Angles(0, 0, math.rad(45)) * CFrame.new(0, 0, 0), lerp(color, accent, i / count), Enum.Material.Neon, 0.45)
			ghost.Size = Vector3.new(3.2, 3.2, 0.2)
			run(0.3, function(alpha)
				ghost.Transparency = 0.45 + 0.55 * alpha
				ghost.Size = Vector3.new(3.2, 3.2, 0.2) * (1 - 0.6 * alpha)
			end, function()
				ghost:Destroy()
			end)
			task.wait(0.05)
		end
	end)
end

local function damageNumber(position: Vector3, amount: number, color: Color3, accent: Color3, heavy: boolean)
	local anchor = attachment(position + Vector3.new((math.random() - 0.5) * 2, 2.2, (math.random() - 0.5) * 2))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 60)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Parent = anchor
	local text = if amount < 1 and amount > 0 then string.format("%.1f", amount) else tostring(math.floor(amount + 0.5))
	local label = Theme.label({
		Text = text,
		FontFace = Theme.Faces.Display,
		TextSize = if heavy then 40 else 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	Theme.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(0.55, if heavy then Theme.Colors.Gold else color),
			ColorSequenceKeypoint.new(1, accent),
		}),
		Rotation = 90,
		Parent = label,
	})
	local stroke = Theme.new("UIStroke", {
		Color = Color3.fromRGB(40, 16, 60),
		Thickness = 2.5,
		Transparency = 0.1,
		Parent = label,
	})
	local scale = Theme.new("UIScale", { Scale = 1.8, Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local start = anchor.Position
	run(0.9, function(alpha)
		anchor.Position = start + Vector3.new(0, easeOut(alpha) * 2.4, 0)
		if alpha > 0.55 then
			local k = (alpha - 0.55) / 0.45
			label.TextTransparency = k
			stroke.Transparency = 0.1 + 0.9 * k
		end
	end, function()
		anchor:Destroy()
	end)
end

local function hitFlash(character: Instance, color: Color3)
	if not character:IsA("Model") then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.25
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = folder
	Toon.Register(highlight, Toon.Priority.Hit)
	run(0.18, function(alpha)
		highlight.FillTransparency = 0.25 + 0.75 * alpha
		highlight.OutlineTransparency = alpha
	end, function()
		highlight:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Camera shake
--------------------------------------------------------------------------------

local trauma = 0

function CombatFX.Shake(amount: number)
	trauma = math.min(1, trauma + amount)
end

local function startShake()
	RunService:BindToRenderStep("PrismShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if trauma <= 0 then
			return
		end
		local camera = Workspace.CurrentCamera
		if camera then
			local t = os.clock() * 28
			local s = trauma * trauma
			camera.CFrame *= CFrame.Angles(
				math.rad(math.noise(t, 0.3) * 2.2 * s),
				math.rad(math.noise(0.7, t) * 2.2 * s),
				math.rad(math.noise(t, 1.9) * 1.4 * s)
			)
		end
		trauma = math.max(0, trauma - dt * 2.4)
	end)
end

--------------------------------------------------------------------------------
-- Weapon trails
--------------------------------------------------------------------------------



-- Poses are (pitch, yaw) in degrees from the arm hanging at rest:
-- pitch raises the arm forward, positive yaw swings it across to the left.

local function bladeTrail(character: Model, duration: number, offHand: boolean?)
	local weapon = character:FindFirstChild("Weapon")
	local handle = weapon and weapon:FindFirstChild(if offHand then "OffHandle" else "Handle")
	local trail = handle and handle:FindFirstChild("SwingTrail")
	if trail and trail:IsA("Trail") then
		trail.Enabled = true
		task.delay(duration, function()
			trail.Enabled = false
		end)
	end
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

local function rootOf(character: any): BasePart?
	if typeof(character) ~= "Instance" then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function aimFrame(root: BasePart, direction: Vector3?, height: number?): CFrame
	local dir = direction or root.CFrame.LookVector
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(0, 0, -1)
	end
	local origin = root.Position + Vector3.new(0, height or 0.4, 0)
	return CFrame.lookAt(origin, origin + dir.Unit)
end

local function isLocal(character: any): boolean
	return character ~= nil and character == player.Character
end

-- Arcs per melee style: { a0, a1, roll } for each hit of the combo.
local ARCS: { [string]: { { number } } } = {
	Blade = { { -80, 85, -12 }, { 85, -80, 14 }, { -85, 80, 52 }, { 95, -55, 90 } },
	Greatsword = { { -100, 100, -8 }, { 100, -100, 12 }, { 105, -60, 90 } },
	Daggers = { { -60, 60, -20 }, { 60, -60, 20 }, { -70, 50, 45 }, { 70, -50, -45 }, { -95, 95, 0 } },
	Scythe = { { -160, 160, -5 }, { 160, -160, 8 }, { -175, 175, 0 } },
	Hammer = { { -80, 80, -10 }, { 80, -80, 10 }, { 100, -40, 90 } },
	Whip = { { -40, 40, -5 }, { 40, -40, 5 }, { -50, 30, 30 }, { 60, -60, 0 } },
	Fans = { { -70, 70, -10 }, { 70, -70, 10 }, { -80, 80, 40 }, { -105, 105, 0 } },
	Maul = { { -60, 60, 70 }, { 60, -60, -70 }, { 90, -70, 90 } },
}
-- radius, width, duration per style
local SWING_SIZE: { [string]: { number } } = {
	Blade = { 7.2, 1.9, 0.32 },
	Greatsword = { 10, 3.2, 0.44 },
	Daggers = { 5.4, 1.2, 0.22 },
	Scythe = { 10.2, 2.6, 0.4 },
	Hammer = { 8, 3.2, 0.42 },
	Whip = { 16, 0.8, 0.32 },
	Fans = { 9, 2, 0.36 },
	Maul = { 13, 2.4, 0.38 },
}

local Effects: { [string]: (params: { [string]: any }) -> () } = {}

-- A straight streak of light (thrusts, beams, chains).
local function streak(from: Vector3, to: Vector3, width: number, color: Color3, accent: Color3, duration: number)
	local r = ribbon({ from, from:Lerp(to, 0.5), to }, { width * 0.3, width, width * 0.15 }, { WHITE, color, accent })
	run(duration, function(alpha)
		ribbonFade(r, function()
			return alpha ^ 1.4
		end)
	end, function()
		ribbonDestroy(r)
	end)
end

function Effects.Swing(params)
	local character = params.Caster
	local root = rootOf(character)
	if not root then
		return
	end
	local style = params.Style or "Blade"
	local combo = params.Combo or 1
	local finisher = combo == (params.Hits or 4)
	-- The trail is drawn as the strike starts, so it follows the arm.
	local strikeAt = 0.12
	if style == "Maul" then
		if CombatFX.OnBeastAttack then
			CombatFX.OnBeastAttack(character, combo)
		end
	else
		local motion = if CombatAnim.Has(style .. combo) then style .. combo else "Blade" .. ((combo - 1) % 4 + 1)
		CombatAnim.Play(character, motion)
		strikeAt = math.clamp(CombatAnim.StrikeTime(motion), 0.03, 0.3)
	end
	local frame = aimFrame(root, params.Direction, 0.5)
	local color, accent = params.Color, params.Accent

	-- Thrusts: spear and fists strike straight ahead.
	if style == "Spear" or style == "Gauntlets" then
		task.delay(strikeAt, function()
			if not root.Parent then
				return
			end
			local aim = aimFrame(root, params.Direction, 0.5)
			local reach = if style == "Spear" then 16 else 8
			local side = if combo % 2 == 0 then -0.6 else 0.6
			bladeTrail(character, 0.2, style == "Gauntlets" and combo % 2 == 0)
			local from = aim:PointToWorldSpace(Vector3.new(side, 0.4, -1.5))
			local to = aim:PointToWorldSpace(Vector3.new(side * 0.3, 0.4, -reach))
			streak(from, to, if finisher then 2.6 else 1.4, color, accent, if finisher then 0.35 else 0.22)
			ring(CFrame.lookAt(to, to + aim.LookVector) * CFrame.Angles(math.rad(90), 0, 0), 0.5, if finisher then 4 else 2.2, 0.5, 0.05, color, accent, 0.25, 18)
			if finisher then
				flash(to, WHITE, 1, 5, 0.2, 0.3)
				burst(to, color, accent, 10, 30, 0.9, 0.35, aim.LookVector)
			end
		end)
		return
	end

	local arcs = ARCS[style] or ARCS.Blade
	local arc = arcs[(combo - 1) % #arcs + 1]
	local size = SWING_SIZE[style] or SWING_SIZE.Blade
	local radius, width, duration = size[1], size[2], size[3]
	if finisher then
		radius *= 1.15
		width *= 1.35
		duration *= 1.25
	end
	bladeTrail(character, duration * 0.8, style == "Daggers" and combo % 2 == 0)
	if style == "Daggers" or style == "Fans" then
		bladeTrail(character, duration * 0.8, true)
	end
	local center = if style == "Fans" then frame * CFrame.new(0, 0, -2.5) else frame
	task.delay(strikeAt, function()
		if style == "Maul" then
			-- Three claw marks.
			for k = -1, 1 do
				slash(center * CFrame.new(k * 1.4, k * 0.4, 0), radius - math.abs(k), arc[1], arc[2], arc[3], width, color, accent, duration)
			end
		else
			slash(center, radius, arc[1], arc[2], arc[3], width, color, accent, duration)
		end
		if finisher then
			slash(center * CFrame.new(0, 0, 0.6), radius * 0.8, arc[1], arc[2], arc[3], width * 0.6, accent, color, duration * 0.9)
			local ahead = frame:PointToWorldSpace(Vector3.new(0, -1, -radius * 0.7))
			local ground = groundBelow(ahead)
			if ground then
				ring(CFrame.new(ground + Vector3.new(0, 0.15, 0)), 0.8, radius * 1.2, 0.9, 0.2, color, accent, 0.4)
			end
		end
		if style == "Fans" then
			for _ = 1, 4 do
				local o = frame:PointToWorldSpace(Vector3.new((math.random() - 0.5) * 4, (math.random() - 0.3) * 2, -2))
				streak(o, o + frame.LookVector * 9, 0.25, WHITE, color, 0.25)
			end
		end
	end)
	if style == "Maul" and isLocal(character) then
		CombatFX.Shake(if finisher then 0.4 else 0.15)
	end
end

function Effects.Cast(params)
	local root = rootOf(params.Caster)
	if not root then
		return
	end
	local frame = aimFrame(root, params.Direction, 1.4)
	local sigil = frame * CFrame.new(0, 0, -2.4) * CFrame.Angles(math.rad(90), 0, 0)
	ring(sigil, 0.6, 2.6, 0.45, 0.15, params.Color, params.Accent, 0.32, 6)
	ring(sigil * CFrame.Angles(0, math.rad(30), 0), 1.6, 3.2, 0.25, 0.05, params.Accent, params.Color, 0.36, 6, 0.3)
	flash(sigil.Position, params.Color, 0.6, 3.2, 0.2)
	light(sigil.Position, params.Color, 14, 3, 0.3)
end

type Flight = { Stop: (Vector3?) -> (), Steer: (Vector3, Vector3) -> () }
local projectiles: { [number]: Flight } = {}
local beams: { [Instance]: () -> () } = {}

-- Builds the visible body of a projectile; returns its parts (first = the
-- one carrying the trail) and how it spins.
local function projectileBody(shape: string, color: Color3, accent: Color3): ({ BasePart }, (number) -> CFrame)
	if shape == "Lance" then
		local shell = part(Vector3.new(1.1, 1.1, 7), CFrame.new(), color, Enum.Material.Glass, 0.2)
		local core = part(Vector3.new(0.45, 0.45, 6.4), CFrame.new(), WHITE)
		local tip = part(Vector3.new(0.9, 0.9, 0.9), CFrame.new(), accent)
		return { core, shell, tip }, function(t)
			return CFrame.Angles(0, 0, t * 10)
		end
	elseif shape == "Orb" then
		local shell = part(Vector3.one * 1.8, CFrame.new(), color, Enum.Material.Glass, 0.3)
		shell.Shape = Enum.PartType.Ball
		local core = part(Vector3.one * 0.9, CFrame.new(), lerp(WHITE, accent, 0.3))
		core.Shape = Enum.PartType.Ball
		return { core, shell }, function(t)
			return CFrame.Angles(t * 3, t * 4, 0)
		end
	elseif shape == "Disc" then
		local disc = part(Vector3.new(0.35, 3.4, 3.4), CFrame.new(), color, Enum.Material.Glass, 0.15)
		disc.Shape = Enum.PartType.Cylinder
		local core = part(Vector3.new(0.4, 1.6, 1.6), CFrame.new(), WHITE)
		core.Shape = Enum.PartType.Cylinder
		local rim = part(Vector3.new(0.3, 3.8, 0.3), CFrame.new(), accent)
		return { core, disc, rim }, function(t)
			-- Lie flat and spin fast.
			return CFrame.Angles(0, t * 30, math.rad(90))
		end
	end
	local shell = part(Vector3.new(0.9, 0.9, 3), CFrame.new(), color, Enum.Material.Glass, 0.2)
	local core = part(Vector3.new(0.35, 0.35, 2.4), CFrame.new(), WHITE)
	return { core, shell }, function(t)
		return CFrame.Angles(0, 0, t * 14)
	end
end

function Effects.Projectile(params)
	local origin: Vector3 = params.Origin
	local dir: Vector3 = params.Direction
	local speed: number = params.Speed
	local range: number = params.Range
	local steered = params.Steered == true
	local color, accent = params.Color, params.Accent
	-- Catch up with the server for network latency.
	local offset = math.clamp(Workspace:GetServerTimeNow() - (params.Time or Workspace:GetServerTimeNow()), 0, 0.3)

	local parts, spinOf = projectileBody(params.Shape or "Shard", color, accent)
	local core = parts[1]
	Toon.Outline(parts[2] or core, color, Toon.Priority.Effect, 1, folder)
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Range = if params.Shape == "Lance" then 16 else 10
	pl.Brightness = 2.5
	pl.Parent = core
	local width = if params.Shape == "Lance" then 1.2 elseif params.Shape == "Disc" then 1.4 else 0.5
	local a0 = attachment(Vector3.new(width, 0, 0.5), core)
	local a1 = attachment(Vector3.new(-width, 0, 0.5), core)
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = if params.Shape == "Orb" then 0.4 else 0.22
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	-- Banded like a cel-shaded smear: white-hot, the gem colour, the accent.
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.18, WHITE),
		ColorSequenceKeypoint.new(0.2, color),
		ColorSequenceKeypoint.new(0.6, color),
		ColorSequenceKeypoint.new(0.62, accent),
		ColorSequenceKeypoint.new(1, accent),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.6, 0.05),
		NumberSequenceKeypoint.new(0.62, 0.45),
		NumberSequenceKeypoint.new(0.86, 0.45),
		NumberSequenceKeypoint.new(0.88, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.1)
	trail.Parent = core

	local started = os.clock() - offset
	local stopped = false
	local connection
	local function stop(at: Vector3?)
		if stopped then
			return
		end
		stopped = true
		connection:Disconnect()
		projectiles[params.Id] = nil
		local position = at or core.Position
		burst(position, color, accent, if params.Shape == "Lance" then 12 else 7, 22, 0.8, 0.3)
		flash(position, color, 0.8, if params.Shape == "Lance" then 6 else 3.5, 0.18)
		for i = 2, #parts do
			parts[i]:Destroy()
		end
		core.Transparency = 1
		task.delay(0.45, function()
			core:Destroy()
		end)
	end
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - started
		local traveled = elapsed * speed
		if not steered then
			traveled = math.min(range, traveled)
		end
		local position = origin + dir * traveled
		local cf = CFrame.lookAt(position, position + dir) * spinOf(os.clock())
		for _, p in parts do
			p.CFrame = cf
		end
		if not steered and traveled >= range then
			stop(position)
		end
	end)
	projectiles[params.Id] = {
		Stop = stop,
		Steer = function(position: Vector3, direction: Vector3)
			origin = position
			dir = direction
			started = os.clock() - 0.05
		end,
	}
	-- Safety net if the end event never arrives.
	task.delay(range / speed * (if steered then 3 else 1) + 1.5, function()
		stop(nil)
	end)
end

function Effects.ProjectileSteer(params)
	local entry = projectiles[params.Id]
	if entry and typeof(params.Position) == "Vector3" and typeof(params.Direction) == "Vector3" then
		entry.Steer(params.Position, params.Direction)
	end
end

function Effects.ProjectileEnd(params)
	local entry = projectiles[params.Id]
	if entry then
		entry.Stop(params.Position)
	end
end

function Effects.Launcher(params)
	local root = rootOf(params.Caster)
	if not root then
		return
	end
	local frame = aimFrame(root, params.Direction, 0)
	bladeTrail(params.Caster, 0.3)
	slash(frame, 6.2, -75, 100, 90, 1.8, params.Color, params.Accent, 0.4)
	slash(frame * CFrame.new(0.8, 0, 0), 5, -70, 95, 82, 0.8, params.Accent, params.Color, 0.34)
	local ahead = frame:PointToWorldSpace(Vector3.new(0, 0, -(params.Range or 10) * 0.55))
	spikes(ahead, 5, 2.2, 6, params.Color, params.Accent, 0.8)
	light(ahead, params.Color, 18, 3, 0.4)
end

function Effects.Rush(params)
	local character = params.Caster
	local root = rootOf(character)
	if not root then
		return
	end
	local duration = params.Duration or 0.28
	bladeTrail(character, duration + 0.1)
	rootTrail(character, params.Color, params.Accent, duration + 0.05, 2.6)
	afterimages(character, params.Color, params.Accent, duration)
	local start = aimFrame(root, params.Direction, 0)
	ring(start * CFrame.Angles(math.rad(90), 0, 0), 1, 4.5, 0.6, 0.1, params.Color, params.Accent, 0.35, 20)
	task.delay(duration, function()
		local finish = rootOf(character)
		if finish then
			local frame = aimFrame(finish, params.Direction, 0.5)
			slash(frame, 5.4, -70, 70, 45, 1.4, params.Color, params.Accent, 0.32)
			slash(frame, 5.4, 70, -70, -45, 1.4, params.Accent, params.Color, 0.32)
		end
	end)
end

function Effects.Dash(params)
	local character = params.Caster
	local root = rootOf(character)
	if not root then
		return
	end
	local frame = aimFrame(root, params.Direction, 0)
	ring(frame * CFrame.Angles(math.rad(90), 0, 0), 0.6, 3.6, 0.5, 0.05, params.Color, params.Accent, 0.3, 16)
	rootTrail(character, params.Color, params.Accent, params.Duration or 0.22, 1.6)
	local ground = groundBelow(root.Position)
	if ground then
		ring(CFrame.new(ground + Vector3.new(0, 0.12, 0)), 0.5, 4, 0.4, 0.05, params.Color, params.Accent, 0.3, 18)
	end
end

-- Charging up: light motes and speed lines drawn into the body, rings
-- tightening at the feet, a growing glow at the chest, the aura surging and,
-- for your own charge, the screen trembling. Everything stops the moment the
-- caster is stunned, shattered or gone. `power` scales it (1 = a normal charge).
local function gather(character: Instance?, duration: number, color: Color3, accent: Color3, power: number)
	local root = rootOf(character)
	if not root or duration <= 0 then
		return
	end
	local model = character :: Model
	local function interrupted(): boolean
		if root.Parent == nil or model:GetAttribute("Shattered") == true then
			return true
		end
		return (model:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow()
	end
	Auras.Surge(model, duration, power)
	local chest = function(): Vector3
		return root.Position + Vector3.new(0, 0.8, 0)
	end
	-- Motes and streaks rushing inward, spread over the charge.
	local count = math.floor(10 + 12 * power)
	for i = 1, count do
		task.delay((i / count) * duration * 0.7, function()
			if interrupted() then
				return
			end
			local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9 - 0.25, math.random() - 0.5)
			dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
			local distance = 6 + math.random() * 5 * power
			local streakLine = i % 3 == 0
			local size = if streakLine then Vector3.new(0.12, 0.12, 2.4) else Vector3.new(0.3, 0.3, 0.3)
			local mote = part(size, CFrame.new(chest() + dir * distance), if i % 2 == 0 then color else accent)
			local life = 0.35 + math.random() * 0.25
			run(life, function(alpha)
				if interrupted() then
					return true
				end
				local e = alpha ^ 2
				local p = chest() + dir * distance * (1 - e)
				mote.CFrame = if streakLine then CFrame.lookAt(p, chest()) else CFrame.new(p) * CFrame.Angles(alpha * 6, alpha * 4, 0)
				mote.Transparency = alpha ^ 3
				return nil
			end, function()
				mote:Destroy()
			end)
		end)
	end
	-- Rings tightening at the feet.
	for k = 0, 1 do
		task.delay(k * duration * 0.35, function()
			if root.Parent and not interrupted() then
				ring(CFrame.new(root.Position - Vector3.new(0, 2.8, 0)), 7 + 3 * power, 1.2, 0.15, 0.8, color, accent, duration * 0.6, 26, 0.35)
			end
		end)
	end
	-- Glow at the chest: a white core inside the gem colour.
	local shell = part(Vector3.one * 0.5, CFrame.new(chest()), color, Enum.Material.Neon, 0.7)
	shell.Shape = Enum.PartType.Ball
	local core = part(Vector3.one * 0.3, CFrame.new(chest()), WHITE, Enum.Material.Neon, 0.4)
	core.Shape = Enum.PartType.Ball
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Range = 14 + 6 * power
	pl.Brightness = 0
	pl.Shadows = false
	pl.Parent = core
	local own = isLocal(character)
	local nextShake = 0
	run(duration, function(alpha, elapsed)
		if interrupted() then
			return true
		end
		local pulse = 1 + math.sin(elapsed * 22) * 0.08
		shell.Size = Vector3.one * (0.5 + 2 * power * alpha) * pulse
		core.Size = Vector3.one * (0.3 + 0.9 * power * alpha) * pulse
		shell.CFrame = CFrame.new(chest())
		core.CFrame = CFrame.new(chest())
		shell.Transparency = 0.7 - 0.3 * alpha
		pl.Brightness = 5 * power * alpha
		if own and elapsed >= nextShake then
			nextShake = elapsed + 0.22
			CombatFX.Shake(0.08 + 0.1 * power * alpha)
		end
		return nil
	end, function()
		shell:Destroy()
		core:Destroy()
	end)
end

function Effects.NovaCharge(params)
	gather(params.Caster, params.Duration or 0.55, params.Color, params.Accent, 1)
end

function Effects.Nova(params)
	local center: Vector3 = params.Position
	local radius: number = params.Radius or 19
	local color, accent = params.Color, params.Accent
	local ground = groundBelow(center) or (center - Vector3.new(0, 3, 0))
	local floor = CFrame.new(ground + Vector3.new(0, 0.2, 0))
	ring(floor, 2, radius, 3.2, 0.6, color, accent, 0.55, 40)
	task.delay(0.08, function()
		ring(floor * CFrame.new(0, 0.1, 0), 1, radius * 0.75, 1.6, 0.2, accent, color, 0.6, 36, 0.2)
	end)
	ring(CFrame.new(center) * CFrame.Angles(math.rad(90), 0, 0), 1, radius * 0.6, 1.2, 0.1, color, accent, 0.45, 32, 0.3)
	flash(center, color, 2, radius * 1.1, 0.4, 0.45)
	flash(center, WHITE, 1, radius * 0.45, 0.22, 0.2)
	spikes(center, 9, radius * 0.5, 7, color, accent, 0.9)
	spikes(center, 14, radius * 0.9, 9, accent, color, 0.9, 0.06)
	burst(center, color, accent, 18, 40, 1.1, 0.5, Vector3.new(0, 0.6, 0))
	light(center, color, 40, 6, 0.6)
	explosion(center, radius, color, accent, 1.1)

	-- A column of light up through the caster.
	local column = part(Vector3.new(60, 3, 3), CFrame.new(center + Vector3.new(0, 26, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, 0.2)
	column.Shape = Enum.PartType.Cylinder
	run(0.5, function(alpha)
		local w = 3 + 4 * alpha
		column.Size = Vector3.new(60, w * (1 - alpha) + 0.1, w * (1 - alpha) + 0.1)
		column.Transparency = 0.2 + 0.8 * alpha
	end, function()
		column:Destroy()
	end)

	local own = rootOf(player.Character)
	if own and (own.Position - center).Magnitude < radius * 1.7 then
		CombatFX.Shake(0.95)
	end
end

function Effects.Hit(params)
	local target = params.Target
	local position: Vector3 = params.Position or (rootOf(target) and (rootOf(target) :: BasePart).Position)
	if not position then
		return
	end
	local heavy = params.Heavy == true
	local color, accent = params.Color, params.Accent
	local camera = Workspace.CurrentCamera
	local facing = if camera then CFrame.lookAt(position, camera.CFrame.Position) * CFrame.Angles(math.rad(90), 0, 0) else CFrame.new(position)
	if heavy then
		ring(facing, 0.5, 5.5, 1.3, 0.1, color, accent, 0.32, 18, 0.05, true)
	end
	ring(facing, 0.5, if heavy then 5.5 else 3.2, if heavy then 0.8 else 0.5, 0.05, color, accent, if heavy then 0.32 else 0.22, 18)
	burst(position, color, accent, if heavy then 12 else 7, if heavy then 34 else 22, if heavy then 1 else 0.7, 0.3)
	shards(position, color, accent, if heavy then 7 else 3, if heavy then 26 else 16, if heavy then 0.9 else 0.6, 0.45)
	flash(position, WHITE, 0.6, if heavy then 4.5 else 2.6, 0.14, 0.25)
	light(position, color, if heavy then 18 else 10, 3, 0.25)
	if typeof(target) == "Instance" then
		hitFlash(target, color)
	end
	if (params.Amount or 0) > 0 then
		damageNumber(position, params.Amount, color, accent, heavy)
	end
	if isLocal(target) then
		CombatFX.Shake(if heavy then 0.55 else 0.22)
	elseif heavy then
		CombatFX.Shake(0.12)
	end
	-- Heavy blows you land or take: impact frame, speed lines, hit-stop.
	if heavy and (isLocal(target) or isLocal(params.Attacker)) then
		impact(position, color, 0.8)
	end
end

function Effects.Block(params)
	local root = rootOf(params.Target)
	if not root then
		return
	end
	local from: Vector3 = params.From or (root.Position + root.CFrame.LookVector)
	local toward = Vector3.new(from.X - root.Position.X, 0, from.Z - root.Position.Z)
	toward = if toward.Magnitude > 1e-3 then toward.Unit else root.CFrame.LookVector
	local center = root.Position + toward * 2.4 + Vector3.new(0, 0.6, 0)
	local shield = CFrame.lookAt(center, center + toward) * CFrame.Angles(math.rad(90), 0, 0)
	local cyan = Theme.Colors.Cyan
	ring(shield, 2.4, 3, 0.5, 0.2, WHITE, cyan, 0.3, 6)
	ring(shield * CFrame.Angles(0, math.rad(30), 0), 1.2, 2, 0.3, 0.05, cyan, WHITE, 0.26, 6, 0.3)
	burst(center, cyan, WHITE, 5, 16, 0.5, 0.22, toward)
	light(center, cyan, 10, 2.5, 0.2)
end

function Effects.GuardBreak(params)
	local root = rootOf(params.Target)
	if not root then
		return
	end
	local center = root.Position + Vector3.new(0, 0.5, 0)
	local cyan = Theme.Colors.Cyan
	for i = 1, 10 do
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
		local shard = part(Vector3.new(0.15, 1.2, 0.9), CFrame.new(center), if i % 2 == 0 then cyan else WHITE, Enum.Material.Glass, 0.1)
		local spin = Vector3.new(math.random() * 12, math.random() * 12, 0)
		run(0.6, function(alpha)
			local p = center + dir * 9 * easeOut(alpha) - Vector3.new(0, 6 * alpha * alpha, 0)
			shard.CFrame = CFrame.new(p) * CFrame.Angles(spin.X * alpha, spin.Y * alpha, 0)
			shard.Transparency = 0.1 + 0.9 * alpha
		end, function()
			shard:Destroy()
		end)
	end
	ring(CFrame.new(center), 1, 7, 0.8, 0.1, cyan, WHITE, 0.4, 24)
	flash(center, cyan, 1, 6, 0.25)
	if isLocal(params.Target) then
		CombatFX.Shake(0.6)
	end
end

function Effects.Spawn(params)
	local position: Vector3 = params.Position
	local color, accent = params.Color, params.Accent
	local ground = groundBelow(position) or (position - Vector3.new(0, 3, 0))
	local column = part(Vector3.new(120, 7, 7), CFrame.new(ground + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, 0.1)
	column.Shape = Enum.PartType.Cylinder
	run(0.8, function(alpha)
		local w = 7 * (1 - easeOut(alpha)) + 0.1
		column.Size = Vector3.new(120, w, w)
		column.Transparency = 0.1 + 0.9 * alpha
	end, function()
		column:Destroy()
	end)
	ring(CFrame.new(ground + Vector3.new(0, 0.15, 0)), 1, 10, 1.4, 0.2, color, accent, 0.7, 32)
	ring(CFrame.new(ground + Vector3.new(0, 0.2, 0)), 6, 2, 0.4, 0.8, accent, color, 0.6, 6, 0.2)
	burst(ground + Vector3.new(0, 1, 0), color, accent, 14, 26, 0.9, 0.6, Vector3.new(0, 1.2, 0))
	light(ground + Vector3.new(0, 3, 0), color, 24, 4, 0.8)
end

--------------------------------------------------------------------------------
-- More building blocks
--------------------------------------------------------------------------------

-- Runs step(alpha, root) while the character exists, for `duration`.
local function follow(character: any, duration: number, step: (number, BasePart) -> (), done: (() -> ())?)
	run(duration, function(alpha)
		local root = rootOf(character)
		if root then
			step(alpha, root)
		end
	end, done)
end

-- A jagged bolt of lightning between two points.
local function bolt(from: Vector3, to: Vector3, color: Color3, accent: Color3, width: number, duration: number)
	local points = { from }
	local n = 7
	for i = 1, n - 1 do
		local p = from:Lerp(to, i / n)
		points[i + 1] = p + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.2
	end
	table.insert(points, to)
	local widths, colors = {}, {}
	for i = 1, #points do
		widths[i] = width
		colors[i] = if i % 2 == 0 then WHITE else color:Lerp(accent, i / #points)
	end
	local r = ribbon(points, widths, colors)
	run(duration, function(alpha)
		ribbonFade(r, function()
			return alpha ^ 1.2
		end)
	end, function()
		ribbonDestroy(r)
	end)
end

-- A flat glowing disc on the ground (frost fields, domain floors).
local function groundDisc(center: Vector3, radius: number, color: Color3, transparency: number): Part
	local disc = part(Vector3.new(0.2, radius * 2, radius * 2), CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, transparency)
	disc.Shape = Enum.PartType.Cylinder
	return disc
end

-- A star-and-circle sigil on the ground that lasts `duration`.
local function sigil(center: Vector3, radius: number, color: Color3, accent: Color3, duration: number, points: number?)
	local n = points or 5
	local frame = CFrame.new(center + Vector3.new(0, 0.2, 0))
	local outer, star = {}, {}
	for i = 0, 36 do
		local a = i / 36 * math.pi * 2
		outer[i + 1] = frame:PointToWorldSpace(Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
	end
	for i = 0, n do
		local a = (i * 2 % n) / n * math.pi * 2 - math.pi / 2
		star[i + 1] = frame:PointToWorldSpace(Vector3.new(math.cos(a) * radius * 0.92, 0, math.sin(a) * radius * 0.92))
	end
	local ringRibbon = ribbon(outer, table.create(#outer, 0.45), table.create(#outer, color))
	local starRibbon = ribbon(star, table.create(#star, 0.3), table.create(#star, accent))
	run(duration, function(alpha)
		local fade = if alpha < 0.1 then 1 - alpha / 0.1 elseif alpha > 0.8 then (alpha - 0.8) / 0.2 else 0
		ribbonFade(ringRibbon, function()
			return 0.1 + 0.9 * fade
		end)
		ribbonFade(starRibbon, function()
			return 0.2 + 0.8 * fade
		end)
	end, function()
		ribbonDestroy(ringRibbon)
		ribbonDestroy(starRibbon)
	end)
end

-- A big title across the screen for everyone close enough to see it.
local function screenBanner(position: Vector3, range: number, title: string, subtitle: string, color: Color3, accent: Color3, duration: number)
	local camera = Workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - position).Magnitude > range then
		return
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatBanner"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = playerGui
	local holder = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(900, 140),
		Parent = gui,
	})
	local scale = Theme.new("UIScale", { Scale = 1.6, Parent = holder })
	local headline = Theme.headline({
		Text = title,
		TextSize = 64,
		Size = UDim2.new(1, 0, 0, 80),
		Parent = holder,
	}, ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.4, color),
		ColorSequenceKeypoint.new(1, accent),
	}), 0.6)
	local sub = Theme.label({
		Text = subtitle,
		FontFace = Theme.Faces.Odds,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = holder,
	})
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(duration, function()
		TweenService:Create(headline, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(sub, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.45)
		gui:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Areas
--------------------------------------------------------------------------------

function Effects.Rain(params)
	local center: Vector3 = params.Center
	local radius: number = params.Radius
	local rng = Random.new(params.Seed or 1)
	local color, accent = params.Color, params.Accent
	sigil(center, radius, color, accent, (params.Duration or 1.4) + 0.8, 6)
	for i = 1, params.Count or 10 do
		local a = rng:NextNumber() * math.pi * 2
		local r = math.sqrt(rng:NextNumber()) * radius
		local at = (i - 1) / (params.Count or 10) * (params.Duration or 1.4)
		local landing = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		task.delay(at, function()
			ring(CFrame.new(landing + Vector3.new(0, 0.2, 0)), 2.6, 0.6, 0.15, 0.5, color, accent, 0.45, 16, 0.4)
			local top = landing + Vector3.new(-3, 32, -3)
			local shell = part(Vector3.new(0.9, 3.6, 0.9), CFrame.new(top), color, Enum.Material.Glass, 0.15)
			local core = part(Vector3.new(0.4, 3, 0.4), CFrame.new(top), WHITE)
			run(0.45, function(alpha)
				local p = top:Lerp(landing + Vector3.new(0, 1.8, 0), alpha ^ 2)
				local cf = CFrame.lookAt(p, landing) * CFrame.Angles(math.rad(90), 0, 0)
				shell.CFrame = cf
				core.CFrame = cf
			end, function()
				shell:Destroy()
				core:Destroy()
				burst(landing, color, accent, 5, 18, 0.6, 0.3, Vector3.new(0, 1, 0))
				flash(landing, color, 0.6, 3, 0.15)
			end)
		end)
	end
end

function Effects.Meteor(params)
	local center: Vector3 = params.Center
	local radius: number = params.Radius
	local delay: number = params.Delay or 1
	local color, accent = params.Color, params.Accent
	gather(params.Caster, math.min(delay * 0.8, 1.4), color, accent, 0.8)
	-- Warning circle that tightens until impact.
	sigil(center, radius, color, accent, delay + 0.3, 7)
	ring(CFrame.new(center + Vector3.new(0, 0.3, 0)), radius, radius * 0.2, 0.3, 1.2, accent, color, delay, 40, 0.2)
	local from = center + Vector3.new(30, 90, 30)
	local shell = part(Vector3.one * 7, CFrame.new(from), color, Enum.Material.Glass, 0.1)
	local core = part(Vector3.one * 4, CFrame.new(from), WHITE)
	Toon.Outline(shell, color, Toon.Priority.Effect, 1, folder)
	local a0 = attachment(Vector3.new(3, 0, 0), core)
	local a1 = attachment(Vector3.new(-3, 0, 0), core)
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(WHITE, accent)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = core
	run(delay, function(alpha)
		local p = from:Lerp(center + Vector3.new(0, 3, 0), alpha ^ 2.2)
		local cf = CFrame.new(p) * CFrame.Angles(alpha * 8, alpha * 6, 0)
		shell.CFrame = cf
		core.CFrame = cf
	end, function()
		shell:Destroy()
		core:Destroy()
		flash(center, WHITE, 2, radius * 1.4, 0.35, 0.2)
		flash(center, color, 3, radius * 2, 0.5, 0.45)
		ring(CFrame.new(center + Vector3.new(0, 0.3, 0)), 2, radius * 1.4, 3, 0.4, color, accent, 0.6, 40)
		spikes(center, 12, radius * 0.7, 9, color, accent, 1.2)
		burst(center, color, accent, 22, 45, 1.3, 0.6, Vector3.new(0, 0.8, 0))
		light(center, color, 50, 7, 0.7)
		explosion(center, radius, color, accent, 1.3)
		local camera = Workspace.CurrentCamera
		if camera and (camera.CFrame.Position - center).Magnitude < radius * 5 then
			CombatFX.Shake(1)
		end
	end)
end

function Effects.Vortex(params)
	local center: Vector3 = params.Center
	local radius: number = params.Radius
	local duration: number = params.Duration or 1.5
	local color, accent = params.Color, params.Accent
	sigil(center - Vector3.new(0, 1.8, 0), radius, color, accent, duration + 0.4, 8)
	-- Spiral arms turning inward.
	local arms = {}
	for k = 1, 4 do
		local points, widths, colors = {}, {}, {}
		for i = 0, 10 do
			points[i + 1] = center
			widths[i + 1] = 0.9 * (1 - i / 10) + 0.1
			colors[i + 1] = grad(color, accent, i / 10)
		end
		arms[k] = ribbon(points, widths, colors)
	end
	run(duration, function(alpha, elapsed)
		for k, arm in arms do
			local list = {}
			for i = 0, 10 do
				local u = i / 10
				local a = elapsed * 5 + k * math.pi / 2 + u * 4
				local r = radius * (1 - u) * (1 - alpha * 0.3)
				list[i + 1] = center + Vector3.new(math.cos(a) * r, u * 3 - 1, math.sin(a) * r)
			end
			ribbonMove(arm, list)
			ribbonFade(arm, function()
				return 0.1 + 0.6 * alpha
			end)
		end
	end, function()
		for _, arm in arms do
			ribbonDestroy(arm)
		end
	end)
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local start = center + Vector3.new(math.cos(a) * radius, math.random() * 4 - 1, math.sin(a) * radius)
		local mote = part(Vector3.new(0.3, 0.3, 0.9), CFrame.new(start), if i % 2 == 0 then color else WHITE)
		run(duration, function(alpha)
			local p = start:Lerp(center, alpha)
			mote.CFrame = CFrame.lookAt(p, center)
			mote.Transparency = alpha
		end, function()
			mote:Destroy()
		end)
	end
	flash(center, color, 1, 4, duration, 0.6)
end

function Effects.VortexBurst(params)
	local center: Vector3 = params.Center
	flash(center, WHITE, 1, params.Radius, 0.3, 0.25)
	ring(CFrame.new(center), 1, params.Radius * 1.3, 2.4, 0.3, params.Color, params.Accent, 0.5, 36)
	burst(center, params.Color, params.Accent, 18, 40, 1, 0.5)
	light(center, params.Color, 30, 5, 0.5)
	explosion(center, params.Radius, params.Color, params.Accent, 0.8)
end

function Effects.Trap(params)
	local center: Vector3 = params.Center
	local radius: number = params.Radius
	local delay: number = params.Delay or 0.45
	local color, accent = params.Color, params.Accent
	sigil(center, radius, color, accent, delay + (params.Stun or 1.6), 6)
	ring(CFrame.new(center + Vector3.new(0, 0.3, 0)), radius, radius, 0.6, 0.6, accent, color, delay, 6, 0.3)
	task.delay(delay, function()
		spikes(center, 10, radius * 0.95, 8, color, accent, params.Stun or 1.6)
		flash(center + Vector3.new(0, 3, 0), color, 2, radius * 1.6, 0.3, 0.55)
		light(center, color, 24, 4, 0.4)
	end)
end

-- An ice-crystal block around a frozen fighter.
function Effects.Frozen(params)
	local character = params.Target
	local block = part(Vector3.new(4.4, 6, 4.4), CFrame.new(), params.Color, Enum.Material.Glass, 0.45)
	follow(character, params.Duration or 1.5, function(alpha, root)
		block.CFrame = root.CFrame * CFrame.new(0, -0.4, 0)
		block.Transparency = if alpha > 0.85 then 0.45 + (alpha - 0.85) / 0.15 * 0.55 else 0.45
	end, function()
		block:Destroy()
		local root = rootOf(character)
		if root then
			burst(root.Position, params.Color, WHITE, 10, 25, 0.8, 0.4)
		end
	end)
end

function Effects.Frostbite(params)
	local center: Vector3 = params.Center
	local radius: number = params.Radius
	local duration: number = params.Duration or 2.5
	local color = params.Color:Lerp(WHITE, 0.4)
	local disc = groundDisc(center, radius, color, 0.7)
	sigil(center, radius, color, params.Accent, duration, 6)
	spikes(center, 8, radius * 0.6, 3.5, color, params.Accent, duration)
	run(duration, function(alpha)
		disc.Transparency = 0.7 + 0.3 * alpha ^ 3
	end, function()
		disc:Destroy()
	end)
	for _ = 1, 14 do
		local a = math.random() * math.pi * 2
		local r = math.random() * radius
		local start = center + Vector3.new(math.cos(a) * r, 0.5, math.sin(a) * r)
		local flake = part(Vector3.new(0.3, 0.3, 0.3), CFrame.new(start), WHITE)
		run(duration * (0.5 + math.random() * 0.5), function(alpha)
			flake.CFrame = CFrame.new(start + Vector3.new(0, alpha * 5, 0)) * CFrame.Angles(alpha * 5, alpha * 3, 0)
			flake.Transparency = alpha
		end, function()
			flake:Destroy()
		end)
	end
end

function Effects.Curse(params)
	local center: Vector3 = params.Center
	local dark = params.Color:Lerp(Color3.new(0, 0, 0), 0.5)
	sigil(center, params.Radius, dark, params.Accent, 1.2, 7)
	ring(CFrame.new(center + Vector3.new(0, 0.3, 0)), params.Radius, 1, 0.4, 1, params.Accent, dark, 0.4, 7)
	task.delay(0.35, function()
		flash(center + Vector3.new(0, 2, 0), params.Accent, 1, params.Radius, 0.3, 0.5)
		burst(center, dark, params.Accent, 12, 22, 0.7, 0.5, Vector3.new(0, 1.5, 0))
	end)
end

-- A spinning dark diamond over a hexed fighter's head.
function Effects.Cursed(params)
	local character = params.Target
	local mark = part(Vector3.new(0.9, 0.9, 0.9), CFrame.new(), params.Accent)
	local shell = part(Vector3.new(1.4, 1.4, 1.4), CFrame.new(), params.Color:Lerp(Color3.new(0, 0, 0), 0.5), Enum.Material.Glass, 0.3)
	follow(character, params.Duration or 5, function(alpha, root)
		local cf = root.CFrame * CFrame.new(0, 4.2 + math.sin(alpha * 20) * 0.2, 0) * CFrame.Angles(0, alpha * 30, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		mark.CFrame = cf
		shell.CFrame = cf
	end, function()
		mark:Destroy()
		shell:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Close range
--------------------------------------------------------------------------------

function Effects.Spin(params)
	local character = params.Caster
	local duration: number = params.Duration or 1.2
	local radius: number = params.Radius or 9
	bladeTrail(character, duration)
	bladeTrail(character, duration, true)
	local turns = math.floor(duration / 0.12)
	task.spawn(function()
		for i = 1, turns do
			local root = rootOf(character)
			if not root then
				return
			end
			local frame = CFrame.new(root.Position + Vector3.new(0, (i % 3 - 1) * 0.8, 0)) * CFrame.Angles(0, i * 1.3, 0)
			slash(frame, radius * 0.85, -170, 170, (i % 2) * 20 - 10, 1.2, params.Color, params.Accent, 0.22)
			task.wait(0.12)
		end
	end)
end

function Effects.SlamLeap(params)
	local character = params.Caster
	local root = rootOf(character)
	if not root then
		return
	end
	rootTrail(character, params.Color, params.Accent, params.Delay or 0.55, 2.6)
	ring(CFrame.new(root.Position - Vector3.new(0, 2.8, 0)), 0.8, 5, 0.8, 0.1, params.Color, params.Accent, 0.35)
end

function Effects.Slam(params)
	local center: Vector3 = params.Position
	local radius: number = params.Radius or 12
	ring(CFrame.new(center + Vector3.new(0, 0.2, 0)), 1, radius * 1.3, 2.6, 0.3, params.Color, params.Accent, 0.55, 40)
	ring(CFrame.new(center + Vector3.new(0, 0.3, 0)), 0.5, radius * 0.8, 1.2, 0.1, params.Accent, params.Color, 0.45, 36, 0.2)
	spikes(center, 10, radius * 0.75, 6, params.Color, params.Accent, 0.9)
	flash(center, WHITE, 1, radius, 0.25, 0.3)
	burst(center, params.Color, params.Accent, 16, 35, 1, 0.5, Vector3.new(0, 1, 0))
	light(center, params.Color, 30, 5, 0.5)
	explosion(center, radius, params.Color, params.Accent, 0.9)
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - center).Magnitude < radius * 4 then
		CombatFX.Shake(0.65)
	end
end

function Effects.Flurry(params)
	local character = params.Caster
	local hits: number = params.Hits or 8
	local range: number = params.Range or 9
	bladeTrail(character, hits * 0.07 + 0.1)
	bladeTrail(character, hits * 0.07 + 0.1, true)
	task.spawn(function()
		for i = 1, hits do
			local root = rootOf(character)
			if not root then
				return
			end
			local frame = aimFrame(root, params.Direction, 0.5)
			local a = math.random(-40, 40)
			slash(frame * CFrame.new(0, (math.random() - 0.5) * 1.5, -1), range * 0.6, a - 60, a + 60, math.random(-70, 70), 0.8, params.Color, params.Accent, 0.18)
			if i == hits then
				slash(frame, range * 0.8, -90, 90, 0, 2, params.Accent, params.Color, 0.35)
			end
			task.wait(0.07)
		end
	end)
end

function Effects.Pillars(params)
	local origin: Vector3 = params.Origin
	local dir: Vector3 = params.Direction
	for i = 1, params.Count or 9 do
		task.delay(i * (params.Interval or 0.05), function()
			local point = origin + dir * (i * (params.Spacing or 4.5))
			spikes(point, 3, 0.9, 5.5 + i * 0.25, params.Color, params.Accent, 0.9)
			flash(point, params.Color, 0.5, 3, 0.15)
			if i == (params.Count or 9) then
				explosion(point, (params.Spacing or 4.5) * 1.6, params.Color, params.Accent, 0.6)
			end
		end)
	end
end

function Effects.Beam(params)
	local character = params.Caster
	local duration: number = params.Duration or 1.2
	local length: number = params.Length or 70
	local width: number = params.Width or 4
	local color, accent = params.Color, params.Accent
	local function points(root: BasePart): { Vector3 }
		local frame = aimFrame(root, root.CFrame.LookVector, 1)
		local from = frame:PointToWorldSpace(Vector3.new(0, 0, -1.5))
		local to = frame:PointToWorldSpace(Vector3.new(0, 0, -length))
		return { from, from:Lerp(to, 0.1), from:Lerp(to, 0.5), to }
	end
	local root = rootOf(character)
	if not root then
		return
	end
	gather(character, 0.3, color, accent, 0.7)
	local start = points(root)
	local glow = ribbon(start, { width * 0.8, width * 1.9, width * 1.7, width * 1.2 }, { color, color, accent, accent })
	local body = ribbon(start, { width * 0.4, width, width * 0.9, width * 0.6 }, { WHITE, color, color, accent })
	local core = ribbon(start, { width * 0.15, width * 0.35, width * 0.3, width * 0.2 }, { WHITE, WHITE, WHITE, lerp(WHITE, color, 0.4) })
	local tipLight = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(start[4]), color, Enum.Material.SmoothPlastic, 1)
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Range = 20
	pl.Brightness = 4
	pl.Parent = tipLight
	local stopped = false
	beams[character] = function()
		stopped = true
	end
	run(duration, function(alpha, elapsed)
		local r = rootOf(character)
		if not r or stopped then
			return
		end
		local list = points(r)
		ribbonMove(glow, list)
		ribbonMove(body, list)
		ribbonMove(core, list)
		tipLight.CFrame = CFrame.new(list[4])
		local flicker = 0.08 * math.sin(elapsed * 40)
		local fade = if alpha > 0.85 then (alpha - 0.85) / 0.15 else 0
		ribbonFade(glow, function()
			return 0.55 + flicker + 0.45 * fade
		end)
		ribbonFade(body, function()
			return 0.1 + flicker + 0.9 * fade
		end)
		ribbonFade(core, function()
			return fade
		end)
	end, function()
		ribbonDestroy(glow)
		ribbonDestroy(body)
		ribbonDestroy(core)
		tipLight:Destroy()
		beams[character] = nil
	end)
	if isLocal(character) then
		CombatFX.Shake(0.2)
	end
end

function Effects.BeamEnd(params)
	local stop = beams[params.Caster]
	if stop then
		stop()
	end
end

function Effects.Chain(params)
	local points = params.Points
	if type(points) ~= "table" or #points < 2 then
		return
	end
	for _ = 1, 3 do
		for i = 1, #points - 1 do
			bolt(points[i], points[i + 1], params.Color, params.Accent, 0.5, 0.2)
		end
		task.wait(0.06)
	end
	for i = 2, #points do
		flash(points[i], WHITE, 0.5, 3.5, 0.2, 0.2)
		burst(points[i], params.Color, params.Accent, 6, 20, 0.5, 0.25)
	end
end

function Effects.Bind(params)
	local origin: Vector3 = params.Origin
	local dir: Vector3 = params.Direction
	local length: number = params.Length or 40
	for i = 1, math.floor(length / 2.2) do
		task.delay(i * 0.012, function()
			local p = origin + dir * (i * 2.2) + Vector3.new(0, 0.6 + math.sin(i) * 0.3, 0)
			local link = part(Vector3.new(0.35, 0.9, 1.4), CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, if i % 2 == 0 then 0 else math.rad(90)), if i % 2 == 0 then params.Color else params.Accent)
			run(0.5, function(alpha)
				link.Transparency = alpha ^ 2
			end, function()
				link:Destroy()
			end)
		end)
	end
end

-- Shackle rings locked around a rooted fighter.
function Effects.Bound(params)
	local character = params.Target
	local rings = {}
	for k = 1, 3 do
		local r = part(Vector3.new(0.3, 3.6 - k * 0.4, 3.6 - k * 0.4), CFrame.new(), if k == 2 then params.Accent else params.Color)
		r.Shape = Enum.PartType.Cylinder
		r.Transparency = 0.2
		rings[k] = r
	end
	follow(character, params.Duration or 2, function(alpha, root)
		for k, r in rings do
			r.CFrame = root.CFrame * CFrame.new(0, -2.6 + k * 0.9, 0) * CFrame.Angles(0, alpha * 10 * (if k % 2 == 0 then -1 else 1), math.rad(90))
			r.Transparency = 0.2 + 0.8 * math.max(0, alpha - 0.85) / 0.15
		end
	end, function()
		for _, r in rings do
			r:Destroy()
		end
	end)
end

function Effects.Grab(params)
	local origin: Vector3 = params.Origin
	local to: Vector3 = params.To
	local hooked = params.Hooked
	local color, accent = params.Color, params.Accent
	local hook = part(Vector3.new(1, 1, 1), CFrame.new(origin), accent)
	local line = ribbon({ origin, origin }, { 0.35, 0.35 }, { color, accent })
	ribbonFade(line, function()
		return 0.1
	end)
	local tipOf = function(alpha: number): Vector3
		if alpha < 0.45 then
			return origin:Lerp(to, alpha / 0.45)
		end
		local held = rootOf(hooked)
		local back = if held then held.Position else to
		return back:Lerp(origin, (alpha - 0.45) / 0.55 * (if held then 0 else 1))
	end
	run(0.55, function(alpha)
		local caster = rootOf(params.Caster)
		local start = if caster then caster.Position + Vector3.new(0, 1, 0) else origin
		local tip = tipOf(alpha)
		hook.CFrame = CFrame.lookAt(tip, tip + (tip - start)) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		ribbonMove(line, { start, tip })
	end, function()
		hook:Destroy()
		ribbonDestroy(line)
	end)
	if hooked then
		task.delay(0.18, function()
			local held = rootOf(hooked)
			if held then
				flash(held.Position, WHITE, 0.8, 4, 0.2, 0.3)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

function Effects.Blink(params)
	local from: Vector3 = params.From
	local to: Vector3 = params.To
	local character = params.Caster
	if typeof(character) == "Instance" and character:IsA("Model") then
		afterimages(character, params.Color, params.Accent, 0.1)
	end
	flash(from, params.Color, 1, 5, 0.25, 0.3)
	streak(from, to, 2.4, params.Color, params.Accent, 0.3)
	task.delay(0.05, function()
		flash(to, WHITE, 1, 7, 0.3, 0.2)
		ring(CFrame.new(to - Vector3.new(0, 2.6, 0)), 1, 9, 1.2, 0.1, params.Color, params.Accent, 0.4, 28)
		burst(to, params.Color, params.Accent, 12, 30, 0.8, 0.4)
	end)
end

local shields: { [Instance]: Part } = {}

function Effects.Shield(params)
	local character = params.Caster
	local shell = part(Vector3.one * 7.5, CFrame.new(), params.Color, Enum.Material.Glass, 0.75)
	shell.Shape = Enum.PartType.Ball
	shields[character] = shell
	local duration: number = params.Duration or 5
	follow(character, duration, function(alpha, root)
		shell.CFrame = root.CFrame
		local fade = if alpha > 0.9 then (alpha - 0.9) / 0.1 else 0
		shell.Transparency = 0.75 + 0.25 * fade
	end, function()
		shell:Destroy()
		if shields[character] == shell then
			shields[character] = nil
		end
	end)
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < duration - 0.3 do
			local root = rootOf(character)
			if not root then
				return
			end
			ring(CFrame.new(root.Position) * CFrame.Angles(math.random() * 3, math.random() * 3, 0), 3.7, 3.9, 0.25, 0.25, params.Color, params.Accent, 0.6, 6, 0.4)
			task.wait(0.5)
		end
	end)
end

function Effects.ShieldHit(params)
	local shell = shields[params.Target]
	if shell then
		local base = shell.Transparency
		shell.Transparency = 0.35
		task.delay(0.08, function()
			if shell.Parent then
				shell.Transparency = base
			end
		end)
	end
end

function Effects.Bloom(params)
	local character = params.Caster
	local duration: number = params.Duration or 3
	local root = rootOf(character)
	if not root then
		return
	end
	ring(CFrame.new(root.Position - Vector3.new(0, 2.8, 0)), 0.5, 6, 1, 0.1, params.Color, params.Accent, 0.6)
	for i = 1, 18 do
		local a = i / 18 * math.pi * 2
		local petal = part(Vector3.new(0.7, 0.12, 0.4), CFrame.new(), if i % 2 == 0 then params.Color else WHITE)
		follow(character, duration * (0.6 + (i % 4) * 0.1), function(alpha, r)
			local angle = a + alpha * 6
			local rad = 3 * (1 - alpha * 0.5)
			petal.CFrame = r.CFrame * CFrame.new(math.cos(angle) * rad, -2.6 + alpha * 6, math.sin(angle) * rad) * CFrame.Angles(0, -angle, alpha * 4)
			petal.Transparency = alpha ^ 2
		end, function()
			petal:Destroy()
		end)
	end
	light(root.Position, params.Color, 16, 3, duration)
end

--------------------------------------------------------------------------------
-- Domain
--------------------------------------------------------------------------------

local domains: { [Instance]: () -> () } = {}

function Effects.Domain(params)
	local center: Vector3 = params.Center
	local radius: number = params.Radius or 34
	local duration: number = (params.Duration or 8) + 1
	local color, accent = params.Color, params.Accent
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.75)
	local caster = params.Caster
	local cinematic = isLocal(caster) and typeof(caster) == "Instance" and Cutscene.Domain(caster :: Model, center, radius, params.Name or "Dimension", color, accent)
	if not cinematic then
		screenBanner(center, radius * 4, "DOMAIN EXPANSION", string.upper(params.Name or "Dimension"), color, accent, 2.6)
	end
	gather(caster, 0.8, color, accent, 1.3)

	local pieces: { BasePart } = {}
	-- Floor of the dimension
	local floor = groundDisc(center, radius, dark, 0.35)
	table.insert(pieces, floor)
	local glowFloor = groundDisc(center + Vector3.new(0, 0.05, 0), radius * 0.98, color, 0.85)
	table.insert(pieces, glowFloor)
	-- Walls: a ring of tall glass panels with neon seams, visible from inside.
	local panels = 28
	local height = math.max(26, radius * 0.9)
	for i = 1, panels do
		local a = (i - 0.5) / panels * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * radius, height / 2, math.sin(a) * radius)
		local width = 2 * math.pi * radius / panels + 0.3
		local panel = part(Vector3.new(width, height, 0.4), CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)), if i % 2 == 0 then color else accent, Enum.Material.Glass, 0.55)
		table.insert(pieces, panel)
		local seam = part(Vector3.new(0.3, height, 0.5), CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z)) * CFrame.new(width / 2, 0, 0), WHITE)
		table.insert(pieces, seam)
	end
	-- A crown of light overhead.
	local halo = part(Vector3.new(1, radius * 2.1, radius * 2.1), CFrame.new(center + Vector3.new(0, height, 0)) * CFrame.Angles(0, 0, math.rad(90)), accent, Enum.Material.Neon, 0.5)
	halo.Shape = Enum.PartType.Cylinder
	table.insert(pieces, halo)
	sigil(center, radius * 0.9, color, accent, duration, 8)
	sigil(center, radius * 0.5, accent, color, duration, 5)
	spikes(center, 16, radius * 0.75, 10, color, accent, duration)

	-- Unfold: rise from the ground.
	local finals = {}
	for i, p in pieces do
		finals[i] = { CFrame = p.CFrame, Transparency = p.Transparency }
		p.Transparency = 1
	end
	run(1, function(alpha)
		local e = easeOut(alpha)
		for i, p in pieces do
			local final = finals[i]
			p.CFrame = final.CFrame - Vector3.new(0, (1 - e) * height * 0.5, 0)
			p.Transparency = final.Transparency + (1 - final.Transparency) * (1 - e)
		end
	end)
	flash(center + Vector3.new(0, 4, 0), WHITE, 4, radius * 1.4, 0.6, 0.2)
	light(center + Vector3.new(0, 8, 0), color, 60, 6, duration)

	-- Inside the dimension the world takes its colour.
	local tint = Instance.new("ColorCorrectionEffect")
	tint.TintColor = color:Lerp(WHITE, 0.55)
	tint.Contrast = 0.15
	tint.Saturation = -0.2
	tint.Enabled = false
	tint.Parent = game:GetService("Lighting")
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		tint:Destroy()
		for _, p in pieces do
			burst(p.Position, color, accent, 1, 20, 1.2, 0.5)
		end
		run(0.4, function(alpha)
			for _, p in pieces do
				p.Transparency = math.max(p.Transparency, alpha)
			end
		end, function()
			for _, p in pieces do
				p:Destroy()
			end
		end)
		domains[params.Caster] = nil
	end
	domains[params.Caster] = close
	run(duration, function()
		local camera = Workspace.CurrentCamera
		if camera then
			local offset = camera.CFrame.Position - center
			tint.Enabled = Vector3.new(offset.X, 0, offset.Z).Magnitude < radius and offset.Y < height
		end
	end, close)
end

function Effects.DomainEnd(params)
	local close = domains[params.Caster]
	if close then
		close()
	end
end

--------------------------------------------------------------------------------
-- Transformation
--------------------------------------------------------------------------------

-- Cracks of crystal spreading over a body: glass shards that grow out of
-- the limbs until `breakAt`, then burst off as the beast takes shape.
local function crackBody(character: Instance?, color: Color3, accent: Color3, breakAt: number)
	if typeof(character) ~= "Instance" then
		return
	end
	local limbs = {}
	for _, d in character:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 then
			table.insert(limbs, d)
		end
	end
	local spawned = os.clock()
	for _, limb in limbs do
		for k = 1, if limb.Size.Magnitude > 2 then 3 else 2 do
			task.delay(breakAt * (0.2 + 0.6 * math.random()), function()
				if not limb.Parent then
					return
				end
				-- A point on the limb's surface, pointing outward.
				local half = limb.Size / 2
				local local_ = Vector3.new((math.random() * 2 - 1) * half.X, (math.random() * 2 - 1) * half.Y, (math.random() * 2 - 1) * half.Z)
				local axis = math.random(1, 3)
				local sign = if math.random() < 0.5 then -1 else 1
				local normal = if axis == 1 then Vector3.new(sign, 0, 0) elseif axis == 2 then Vector3.new(0, sign, 0) else Vector3.new(0, 0, sign)
				local_ = Vector3.new(if axis == 1 then sign * half.X else local_.X, if axis == 2 then sign * half.Y else local_.Y, if axis == 3 then sign * half.Z else local_.Z)
				local size = 0.35 + math.random() * 0.4
				local shard = part(Vector3.new(size, size, 0.1), CFrame.new(), if k % 2 == 0 then accent else color, Enum.Material.Glass, 0.1)
				local glint = part(Vector3.new(size * 0.4, size * 0.4, 0.1), CFrame.new(), WHITE)
				-- Grows out of the limb until the break, then flies off.
				local born = os.clock()
				local life = math.max(0.15, breakAt - (born - spawned))
				local flyFrom: CFrame? = nil
				local flyVelocity = Vector3.zero
				run(life + 0.6, function(_, elapsed)
					if not limb.Parent and not flyFrom then
						return true
					end
					if elapsed < life then
						local base = limb.CFrame * CFrame.new(local_)
						local out = limb.CFrame:VectorToWorldSpace(normal)
						local grown = math.min(1, elapsed / 0.3)
						local length = 0.1 + 1.1 * grown * size
						shard.Size = Vector3.new(size * 0.6, size * 0.6, length)
						glint.Size = Vector3.new(size * 0.25, size * 0.25, length * 0.9)
						shard.CFrame = CFrame.lookAt(base.Position, base.Position + out) * CFrame.Angles(0, 0, k) * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, 0, math.rad(45))
						glint.CFrame = shard.CFrame
						flyVelocity = out * (14 + math.random() * 10) + Vector3.new(0, 8, 0)
					else
						flyFrom = flyFrom or shard.CFrame
						local t = elapsed - life
						shard.CFrame = (flyFrom :: CFrame) + flyVelocity * t + Vector3.new(0, -20 * t * t, 0)
						glint.CFrame = shard.CFrame
						local fade = math.clamp(t / 0.5, 0, 1)
						shard.Transparency = 0.1 + 0.9 * fade
						glint.Transparency = fade
					end
					return nil
				end, function()
					shard:Destroy()
					glint:Destroy()
				end)
			end)
		end
	end
end

function Effects.Transform(params)
	local caster = params.Caster
	local center: Vector3 = params.Position
	local color, accent = params.Color, params.Accent
	local cut = CombatConfig.Cutscene
	-- The caster sees it as a cutscene; everyone else in the world.
	local cinematic = isLocal(caster) and typeof(caster) == "Instance" and Cutscene.Transform(caster :: Model, params.Name or "Transformation", color, accent)
	if not cinematic then
		screenBanner(center, 220, string.upper(params.Name or "Transformation"), "TRANSFORMATION", color, accent, 2.6)
	end
	-- Gathering power while the body cracks into crystal...
	gather(caster, cut.BeastAt, color, accent, 1.5)
	crackBody(caster, color, accent, cut.BeastAt)
	-- ...then the beast bursts out of the light.
	task.delay(cut.BeastAt, function()
		local root = rootOf(caster)
		local at = if root then root.Position else center
		local column = part(Vector3.new(80, 10, 10), CFrame.new(at + Vector3.new(0, 38, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, 0.1)
		column.Shape = Enum.PartType.Cylinder
		run(1, function(alpha)
			local w = 10 * (1 - easeOut(alpha)) + 0.2
			column.Size = Vector3.new(80, w, w)
			column.Transparency = 0.1 + 0.9 * alpha
			return nil
		end, function()
			column:Destroy()
		end)
		for k = 1, 3 do
			task.delay(k * 0.12, function()
				ring(CFrame.new(at + Vector3.new(0, k * 3 - 3, 0)), 1, 14 + k * 3, 1.6, 0.2, color, accent, 0.6, 36)
			end)
		end
		flash(at, WHITE, 2, 18, 0.45, 0.2)
		burst(at, color, accent, 28, 50, 1.3, 0.8, Vector3.new(0, 1.2, 0))
		spikes(at, 12, 7, 8, color, accent, 1)
		light(at, color, 60, 8, 1)
		local camera = Workspace.CurrentCamera
		if not cinematic and camera and (camera.CFrame.Position - at).Magnitude < 80 then
			CombatFX.Shake(0.6)
		end
	end)
end

function Effects.TransformEnd(params)
	local center: Vector3 = params.Position
	local color, accent = params.Color, params.Accent
	flash(center, WHITE, 2, 12, 0.35, 0.3)
	burst(center, color, accent, 18, 35, 1, 0.6)
	-- The body reforms in a column of light and lands with a ring.
	local ground = groundBelow(center) or (center - Vector3.new(0, 3, 0))
	ring(CFrame.new(ground + Vector3.new(0, 0.2, 0)), 1, 9, 1.4, 0.2, color, accent, 0.5, 32)
	local column = part(Vector3.new(14, 3.2, 3.2), CFrame.new(ground + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, 0.3)
	column.Shape = Enum.PartType.Cylinder
	run(0.45, function(alpha)
		local w = 3.2 * (1 - alpha) + 0.1
		column.Size = Vector3.new(14, w, w)
		column.Transparency = 0.3 + 0.7 * alpha
		return nil
	end, function()
		column:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Defeat: the fighter poofs into their gem, which cracks and shatters.
--------------------------------------------------------------------------------

function Effects.Shatter(params)
	local position: Vector3 = params.Position
	local ground: Vector3 = params.Ground or (position - Vector3.new(0, 3, 0))
	local color, accent = params.Color, params.Accent
	local linger: number = math.max(1.5, (params.RespawnTime or 4.5) - 0.6)
	flash(position, WHITE, 2, 8, 0.25, 0.2)
	ring(CFrame.new(ground + Vector3.new(0, 0.2, 0)), 1, 8, 1.2, 0.1, color, accent, 0.5)

	-- 1. The gem forms and rises, cracks glowing across it.
	local tilt = CFrame.Angles(math.rad(45), 0, math.rad(35.26))
	local shell = part(Vector3.one * 2.6, CFrame.new(position), color, Enum.Material.Glass, 0.1)
	local core = part(Vector3.one * 1.4, CFrame.new(position), lerp(color, WHITE, 0.5))
	local cracks = {}
	for k = 1, 4 do
		cracks[k] = part(Vector3.new(0.08, 2.9, 0.08), CFrame.new(position), WHITE, Enum.Material.Neon, 1)
	end
	local top = position + Vector3.new(0, 1.5, 0)
	run(0.9, function(alpha, elapsed)
		local p = position:Lerp(top, easeOut(alpha))
		local cf = CFrame.new(p) * CFrame.Angles(0, elapsed * 4, 0) * tilt
		shell.CFrame = cf
		core.CFrame = cf
		for k, crack in cracks do
			crack.CFrame = cf * CFrame.Angles(k * 0.8, k * 1.3, k * 0.5)
			crack.Transparency = if alpha > k * 0.18 then 0 else 1
		end
	end, function()
		shell:Destroy()
		core:Destroy()
		for _, crack in cracks do
			crack:Destroy()
		end
		-- 2. It bursts into pieces that fall and lie on the ground.
		flash(top, WHITE, 1, 7, 0.3, 0.15)
		burst(top, color, accent, 12, 28, 0.8, 0.4)
		light(top, color, 22, 5, 0.6)
		for i = 1, 14 do
			local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9 + 0.2, math.random() - 0.5).Unit
			local size = 0.4 + math.random() * 0.7
			local shard = part(Vector3.new(size, size * 1.6, size * 0.7), CFrame.new(top), if i % 3 == 0 then accent else color, Enum.Material.Glass, 0.1)
			local spin = Vector3.new(math.random() * 10, math.random() * 10, math.random() * 10)
			local velocity = dir * (14 + math.random() * 10)
			local p = top
			local landed = false
			local rest = ground + Vector3.new(0, size * 0.3, 0)
			run(linger, function(alpha, elapsed)
				if not landed then
					velocity -= Vector3.new(0, 70 * (1 / 60), 0)
					p += velocity * (1 / 60)
					if p.Y <= rest.Y then
						p = Vector3.new(p.X, rest.Y, p.Z)
						landed = true
					end
					shard.CFrame = CFrame.new(p) * CFrame.Angles(spin.X * elapsed, spin.Y * elapsed, spin.Z * elapsed)
				end
				if alpha > 0.8 then
					shard.Transparency = 0.1 + 0.9 * (alpha - 0.8) / 0.2
				end
			end, function()
				shard:Destroy()
			end)
		end
	end)
	if isLocal(params.Caster) then
		CombatFX.Shake(0.5)
	end
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

local function play(kind: string, params: { [string]: any })
	if type(params) == "table" and params.Caster then
		if kind == "BeamEnd" then
			CombatAnim.Stop(params.Caster)
		else
			local motion, hold, duration = motionFor(kind, params)
			if motion then
				CombatAnim.Play(params.Caster, motion, hold, duration)
			end
		end
	end
	local effect = Effects[kind]
	if effect and type(params) == "table" then
		params.Color = if typeof(params.Color) == "Color3" then params.Color else WHITE
		params.Accent = if typeof(params.Accent) == "Color3" then params.Accent else Theme.Colors.Lavender
		local ok, err = pcall(effect, params)
		if not ok then
			warn(`[CombatFX] {kind}: {err}`)
		end
	end
end

-- Local prediction (own attacks).
function CombatFX.Play(kind: string, params: { [string]: any })
	play(kind, params)
end

function CombatFX.Start()
	folder = Instance.new("Folder")
	folder.Name = "CombatFX"
	folder.Parent = Workspace
	host = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(), WHITE, Enum.Material.SmoothPlastic, 1)
	host.Name = "Anchor"
	startShake()
	Cutscene.OnShake = CombatFX.Shake
	table.insert(Toon.OnHitStop, function(seconds: number)
		frozenUntil = math.max(frozenUntil, os.clock() + seconds)
	end)
	table.insert(Toon.OnHitStop, CombatAnim.HitStop)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("CombatFX") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: string, params: { [string]: any })
		if type(params) ~= "table" then
			return
		end
		if PREDICTED[kind] and isLocal(params.Caster) then
			return
		end
		play(kind, params)
	end)
end

return CombatFX
