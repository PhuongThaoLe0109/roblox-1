-- BeastModels
-- Sculpts the eight crystal beasts as skeletal rigs. Bodies are modelled from
-- rounded primitives (spheres, tapered capsules, discs and wedges) so they
-- read as living creatures, with crystal growths in the gem's accent colour
-- and glowing neon eyes, claws and veins. No meshes, textures or decals.
--
-- Every creature is a hierarchy of bones: an invisible joint part per bone,
-- welded to its parent bone with a Weld named after the bone. Body parts are
-- welded to their bone. The client animates a beast by changing those welds'
-- C0 (see client BeastFX): walk and run cycles, breathing, roars and attacks.
--
-- Beast space: origin on the ground under the rider, facing -Z, 1 unit = 1
-- stud at scale 1.

local BeastModels = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PLASTIC = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass
local NEON = Enum.Material.Neon

export type Palette = {
	Body: Color3,
	Belly: Color3,
	Dark: Color3,
	Accent: Color3,
	Glow: Color3,
	Eye: Color3,
}

--------------------------------------------------------------------------------
-- Rig helpers
--------------------------------------------------------------------------------

local function newPart(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function newWedge(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = model
	return p
end

local function weld(part0: BasePart, part1: BasePart, c0: CFrame, name: string?)
	part1.CFrame = part0.CFrame * c0
	local w = Instance.new("Weld")
	w.Name = name or "Weld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
end

-- CFrame at `from` whose -Z looks at `to`, safe when the direction is vertical.
local function look(from: Vector3, to: Vector3): CFrame
	local dir = to - from
	if dir.Magnitude < 1e-4 then
		return CFrame.new(from)
	end
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.new(0, 0, -1) else Vector3.yAxis
	return CFrame.lookAt(from, to, up)
end

type Bone = { Part: BasePart, Pivot: CFrame }

export type Rig = {
	Model: Model,
	Scale: number,
	Bones: { [string]: Bone },
	Bone: (self: Rig, name: string, parent: string, pivot: Vector3) -> (),
	Sphere: (self: Rig, bone: string, center: Vector3, radius: number, color: Color3, material: Enum.Material?, transparency: number?) -> Part,
	Capsule: (self: Rig, bone: string, a: Vector3, b: Vector3, r1: number, r2: number, color: Color3, material: Enum.Material?, transparency: number?) -> (),
	Disc: (self: Rig, bone: string, center: Vector3, normal: Vector3, radius: number, thickness: number, color: Color3, material: Enum.Material?, transparency: number?) -> Part,
	Wedge: (self: Rig, bone: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?) -> (),
	Shard: (self: Rig, bone: string, base: Vector3, tip: Vector3, width: number, color: Color3, core: Color3?) -> (),
	Block: (self: Rig, bone: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?) -> Part,
}

local Rig = {}
Rig.__index = Rig

local function newRig(model: Model, core: BasePart, scale: number): Rig
	local self = setmetatable({
		Model = model,
		Scale = scale,
		Bones = { Root = { Part = core, Pivot = CFrame.identity } },
	}, Rig)
	return self :: any
end

local function scaled(rig: Rig, cf: CFrame): CFrame
	return cf - cf.Position + cf.Position * rig.Scale
end

function Rig.Bone(self: Rig, name: string, parent: string, pivot: Vector3)
	local parentBone = self.Bones[parent]
	local cf = CFrame.new(pivot * self.Scale)
	local j = newPart(self.Model, name .. "Bone", Vector3.new(0.2, 0.2, 0.2), WHITE, PLASTIC, 1)
	weld(parentBone.Part, j, parentBone.Pivot:Inverse() * cf, name)
	self.Bones[name] = { Part = j, Pivot = cf }
end

local function attach(rig: Rig, bone: string, p: BasePart, cf: CFrame)
	local b = rig.Bones[bone] or rig.Bones.Root
	weld(b.Part, p, b.Pivot:Inverse() * scaled(rig, cf))
end

function Rig.Sphere(self: Rig, bone: string, center: Vector3, radius: number, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = newPart(self.Model, "Flesh", Vector3.one * radius * 2 * self.Scale, color, material or PLASTIC, transparency or 0, Enum.PartType.Ball)
	attach(self, bone, p, CFrame.new(center))
	return p
end

-- A rounded, tapered limb from a (radius r1) to b (radius r2).
function Rig.Capsule(self: Rig, bone: string, a: Vector3, b: Vector3, r1: number, r2: number, color: Color3, material: Enum.Material?, transparency: number?)
	local segments = if math.abs(r1 - r2) > 0.2 then 2 else 1
	local previous, previousR = a, r1
	self:Sphere(bone, a, r1, color, material, transparency)
	for i = 1, segments do
		local t = i / segments
		local point = a:Lerp(b, t)
		local r = r1 + (r2 - r1) * t
		local length = (point - previous).Magnitude
		if length > 0.05 then
			local radius = (previousR + r) / 2
			local p = newPart(self.Model, "Flesh", Vector3.new(length * self.Scale, radius * 2 * self.Scale, radius * 2 * self.Scale), color, material or PLASTIC, transparency or 0, Enum.PartType.Cylinder)
			-- Cylinders run along their X axis.
			attach(self, bone, p, look((previous + point) / 2, point) * CFrame.Angles(0, math.rad(90), 0))
		end
		self:Sphere(bone, point, r, color, material, transparency)
		previous, previousR = point, r
	end
end

-- A flat round plate (wings, fins, membranes, ears).
function Rig.Disc(self: Rig, bone: string, center: Vector3, normal: Vector3, radius: number, thickness: number, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = newPart(self.Model, "Membrane", Vector3.new(thickness * self.Scale, radius * 2 * self.Scale, radius * 2 * self.Scale), color, material or GLASS, transparency or 0.25, Enum.PartType.Cylinder)
	attach(self, bone, p, look(center, center + normal) * CFrame.Angles(0, math.rad(90), 0))
	return p
end

function Rig.Wedge(self: Rig, bone: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?)
	local p = newWedge(self.Model, "Wedge", size * self.Scale, color, material or PLASTIC, transparency or 0)
	attach(self, bone, p, cf)
end

function Rig.Block(self: Rig, bone: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = newPart(self.Model, "Plate", size * self.Scale, color, material or PLASTIC, transparency or 0)
	attach(self, bone, p, cf)
	return p
end

-- A crystal growth: a faceted glass prism with a glowing core.
function Rig.Shard(self: Rig, bone: string, base: Vector3, tip: Vector3, width: number, color: Color3, core: Color3?)
	local length = (tip - base).Magnitude
	local cf = look(base, tip) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, length / 2, 0) * CFrame.Angles(0, math.rad(45), 0)
	local shell = newPart(self.Model, "Crystal", Vector3.new(width, length, width) * self.Scale, color, GLASS, 0.15)
	attach(self, bone, shell, cf)
	local glow = newPart(self.Model, "CrystalCore", Vector3.new(width * 0.4, length * 0.85, width * 0.4) * self.Scale, core or WHITE, NEON, 0)
	attach(self, bone, glow, cf)
	-- A pointed tip.
	local tipPart = newPart(self.Model, "CrystalTip", Vector3.new(width * 0.72, width * 0.72, width * 0.72) * self.Scale, color, GLASS, 0.15)
	attach(self, bone, tipPart, look(base, tip) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, length, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)))
end

--------------------------------------------------------------------------------
-- Shared anatomy
--------------------------------------------------------------------------------

local function eyes(rig: Rig, bone: string, center: Vector3, spread: number, radius: number, pal: Palette)
	for _, side in { -1, 1 } do
		local p = center + Vector3.new(side * spread, 0, 0)
		rig:Sphere(bone, p, radius * 1.25, pal.Dark)
		rig:Sphere(bone, p + Vector3.new(0, 0, -radius * 0.45), radius, pal.Eye, NEON)
	end
end

local function claws(rig: Rig, bone: string, paw: Vector3, radius: number, pal: Palette)
	for k = -1, 1 do
		local base = paw + Vector3.new(k * radius * 0.55, -radius * 0.35, -radius * 0.7)
		rig:Capsule(bone, base, base + Vector3.new(0, -radius * 0.35, -radius * 0.6), radius * 0.16, radius * 0.06, pal.Glow, NEON)
	end
end

-- A four-legged body. Returns nothing; bones: Hips, Chest, Neck, Head, Jaw,
-- FLUpper/FLLower/FLPaw (and FR, BL, BR), Tail1..TailN.
type Quad = {
	Shoulder: number, -- height of the shoulder joint
	Hip: number,
	Length: number, -- shoulder to hip
	ChestR: number,
	HipR: number,
	LegR: number,
	NeckUp: number,
	NeckOut: number,
	HeadR: number,
	Tail: number, -- segments
	TailR: number,
	TailDroop: number,
	Paw: number,
	NeckR: number?, -- neck thickness as a fraction of ChestR (default 0.62)
}

local function quadruped(rig: Rig, q: Quad, pal: Palette)
	local front = -q.Length / 2
	local back = q.Length / 2
	rig:Bone("Hips", "Root", Vector3.new(0, q.Hip, back))
	rig:Bone("Chest", "Hips", Vector3.new(0, q.Shoulder, front))
	-- Torso: overlapping spheres from chest to rump, lighter belly underneath.
	for i = 0, 8 do
		local t = i / 8
		local z = front + (back - front) * t
		local y = q.Shoulder + (q.Hip - q.Shoulder) * t + 0.3
		local r = q.ChestR + (q.HipR - q.ChestR) * t - math.sin(t * math.pi) * 0.3
		local bone = if t < 0.5 then "Chest" else "Hips"
		rig:Sphere(bone, Vector3.new(0, y, z), r, pal.Body)
		if i % 2 == 0 then
			rig:Sphere(bone, Vector3.new(0, y - r * 0.28, z), r * 0.84, pal.Belly)
		end
	end
	-- Legs
	for _, spec in {
		{ "FL", -1, front + 0.4, q.Shoulder, "Chest" },
		{ "FR", 1, front + 0.4, q.Shoulder, "Chest" },
		{ "BL", -1, back - 0.3, q.Hip, "Hips" },
		{ "BR", 1, back - 0.3, q.Hip, "Hips" },
	} do
		local name, side, z, top, parent = spec[1], spec[2], spec[3], spec[4], spec[5]
		local x = side * (if parent == "Chest" then q.ChestR * 0.55 else q.HipR * 0.55)
		local isBack = parent == "Hips"
		local knee = Vector3.new(x, top * 0.5, z + (if isBack then 0.6 else -0.1))
		local paw = Vector3.new(x, q.Paw * 0.8, z + (if isBack then 0.1 else -0.2))
		rig:Bone(name .. "Upper", parent, Vector3.new(x, top, z))
		rig:Bone(name .. "Lower", name .. "Upper", knee)
		rig:Bone(name .. "Paw", name .. "Lower", paw)
		-- Shoulder blade / haunch, muscled upper leg, slimmer lower leg,
		-- paw with glowing claws.
		if isBack then
			rig:Sphere(name .. "Upper", Vector3.new(x * 0.9, top - 0.2, z + 0.3), q.HipR * 0.72, pal.Body)
		else
			rig:Sphere(name .. "Upper", Vector3.new(x * 0.9, top + 0.1, z - 0.1), q.ChestR * 0.6, pal.Body)
		end
		rig:Capsule(name .. "Upper", Vector3.new(x, top - q.LegR * 0.3, z), knee, q.LegR * 1.35, q.LegR * 0.85, pal.Body)
		rig:Capsule(name .. "Lower", knee, paw, q.LegR * 0.8, q.LegR * 0.6, pal.Body)
		rig:Sphere(name .. "Paw", paw + Vector3.new(0, -q.Paw * 0.15, -q.Paw * 0.25), q.Paw, pal.Belly)
		claws(rig, name .. "Paw", paw + Vector3.new(0, -q.Paw * 0.15, -q.Paw * 0.25), q.Paw, pal)
	end
	-- Neck and head
	local neckBase = Vector3.new(0, q.Shoulder + q.ChestR * 0.4, front - q.ChestR * 0.3)
	local headAt = neckBase + Vector3.new(0, q.NeckUp, -q.NeckOut)
	rig:Bone("Neck", "Chest", neckBase)
	rig:Capsule("Neck", neckBase, headAt + Vector3.new(0, -q.HeadR * 0.3, q.HeadR * 0.3), q.ChestR * (q.NeckR or 0.62), q.HeadR * 0.8, pal.Body)
	rig:Bone("Head", "Neck", headAt)
	rig:Bone("Jaw", "Head", headAt + Vector3.new(0, -q.HeadR * 0.45, -q.HeadR * 0.2))
	-- Tail
	local previous = "Hips"
	local at = Vector3.new(0, q.Hip + q.HipR * 0.3, back + q.HipR * 0.8)
	for i = 1, q.Tail do
		local name = "Tail" .. i
		rig:Bone(name, previous, at)
		local nextAt = at + Vector3.new(0, -q.TailDroop, 1.1)
		local r = q.TailR * (1 - (i - 1) / (q.Tail + 1))
		rig:Capsule(name, at, nextAt, r, r * 0.85, pal.Body)
		previous = name
		at = nextAt
	end
end

--------------------------------------------------------------------------------
-- The creatures
--------------------------------------------------------------------------------

local Builders: { [string]: (rig: Rig, pal: Palette) -> () } = {}

-- A maned lion with a crown of sunlit crystal around its head.
function Builders.SolarLion(rig, pal)
	quadruped(rig, {
		Shoulder = 6.6, Hip = 6.2, Length = 7.4, ChestR = 2.6, HipR = 2.2, LegR = 0.85,
		NeckUp = 1.6, NeckOut = 1.8, HeadR = 1.55, Tail = 5, TailR = 0.36, TailDroop = 0.55, Paw = 0.9,
	}, pal)
	local head = rig.Bones.Head.Pivot.Position / rig.Scale
	-- Skull, cheeks, muzzle, nose, brow
	rig:Sphere("Head", head, 1.55, pal.Body)
	for _, side in { -1, 1 } do
		rig:Sphere("Head", head + Vector3.new(side * 0.75, -0.45, -0.75), 0.95, pal.Belly)
		rig:Sphere("Head", head + Vector3.new(side * 1.05, 1.15, 0.35), 0.45, pal.Body) -- ears
		rig:Sphere("Head", head + Vector3.new(side * 1.05, 1.15, 0.2), 0.28, pal.Belly)
	end
	rig:Capsule("Head", head + Vector3.new(0, -0.15, -1), head + Vector3.new(0, -0.3, -1.9), 0.8, 0.7, pal.Belly)
	rig:Sphere("Head", head + Vector3.new(0, 0.05, -2.45), 0.32, pal.Dark)
	rig:Capsule("Head", head + Vector3.new(-0.7, 0.6, -1.05), head + Vector3.new(0.7, 0.6, -1.05), 0.28, 0.28, pal.Body)
	eyes(rig, "Head", head + Vector3.new(0, 0.38, -1.2), 0.62, 0.22, pal)
	-- Jaw with fangs
	local jaw = rig.Bones.Jaw.Pivot.Position / rig.Scale
	rig:Capsule("Jaw", jaw, jaw + Vector3.new(0, -0.2, -1.6), 0.55, 0.45, pal.Belly)
	for _, side in { -1, 1 } do
		rig:Capsule("Head", head + Vector3.new(side * 0.45, -0.75, -2.1), head + Vector3.new(side * 0.42, -1.25, -2.15), 0.11, 0.04, WHITE, NEON)
	end
	-- The mane: layered tufts and crystal rays.
	for ring = 0, 1 do
		local count = if ring == 0 then 14 else 18
		for i = 1, count do
			local a = (i + ring * 0.5) / count * math.pi * 2
			local r = 1.75 + ring * 0.7
			local p = head + Vector3.new(math.cos(a) * r, math.sin(a) * r * 0.95 - 0.2, 0.6 + ring * 0.45)
			rig:Sphere("Neck", p, 0.75 - ring * 0.12, if (i + ring) % 2 == 0 then pal.Accent else pal.Body)
		end
	end
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		rig:Shard("Neck", head + dir * 2.3 + Vector3.new(0, -0.2, 1.3), head + dir * 3.3 + Vector3.new(0, -0.2, 1.9), 0.3, pal.Accent, pal.Glow)
	end
	-- Tail tuft
	local tip = rig.Bones["Tail5"].Pivot.Position / rig.Scale + Vector3.new(0, -0.55, 1.1)
	rig:Sphere("Tail5", tip, 0.7, pal.Accent)
	rig:Sphere("Tail5", tip + Vector3.new(0, 0.3, 0.45), 0.5, pal.Accent)
	rig:Shard("Tail5", tip, tip + Vector3.new(0, 0.4, 1.2), 0.3, pal.Accent, pal.Glow)
	-- Crystal growths along the spine
	for i = 1, 4 do
		local z = -2.6 + i * 1.4
		local bone = if z < 0 then "Chest" else "Hips"
		rig:Shard(bone, Vector3.new(0, 8.6 - i * 0.12, z), Vector3.new(0, 9.6 - i * 0.12, z + 0.6), 0.4, pal.Accent, pal.Glow)
	end
end

-- A lean shadow wolf: long snout, tall ears, a ridge of void shards.
function Builders.UmbralMaw(rig, pal)
	quadruped(rig, {
		Shoulder = 6.2, Hip = 5.8, Length = 7.8, ChestR = 2.1, HipR = 1.75, LegR = 0.65,
		NeckUp = 1.4, NeckOut = 2.2, HeadR = 1.2, Tail = 5, TailR = 0.75, TailDroop = 0.45, Paw = 0.7,
	}, pal)
	local head = rig.Bones.Head.Pivot.Position / rig.Scale
	rig:Sphere("Head", head, 1.25, pal.Body)
	-- Long snout
	rig:Capsule("Head", head + Vector3.new(0, -0.1, -0.8), head + Vector3.new(0, -0.35, -2.6), 0.75, 0.45, pal.Body)
	rig:Sphere("Head", head + Vector3.new(0, -0.15, -2.95), 0.3, BLACK)
	for _, side in { -1, 1 } do
		-- Tall pointed ears
		rig:Capsule("Head", head + Vector3.new(side * 0.7, 0.9, 0.2), head + Vector3.new(side * 0.9, 2.3, 0.5), 0.38, 0.06, pal.Body)
		rig:Capsule("Head", head + Vector3.new(side * 0.7, 1, 0.05), head + Vector3.new(side * 0.85, 2, 0.3), 0.2, 0.04, pal.Accent, NEON)
		-- Cheek fur
		rig:Sphere("Head", head + Vector3.new(side * 0.9, -0.5, 0.3), 0.6, pal.Body)
	end
	eyes(rig, "Head", head + Vector3.new(0, 0.35, -0.95), 0.5, 0.2, pal)
	local jaw = rig.Bones.Jaw.Pivot.Position / rig.Scale
	rig:Capsule("Jaw", jaw, jaw + Vector3.new(0, -0.25, -2.1), 0.42, 0.28, pal.Body)
	for i = -2, 2 do
		rig:Capsule("Head", head + Vector3.new(i * 0.16, -0.65, -2.2 - math.abs(i) * -0.1), head + Vector3.new(i * 0.16, -1.05, -2.2), 0.06, 0.02, WHITE, NEON)
	end
	-- Shaggy neck ruff
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		rig:Sphere("Neck", rig.Bones.Neck.Pivot.Position / rig.Scale + Vector3.new(math.cos(a) * 1.3, math.sin(a) * 1.2 + 0.4, -0.6), 0.7, pal.Body)
	end
	-- Void-shard ridge along the back
	for i = 0, 6 do
		local z = -3.4 + i * 1.1
		local bone = if z < 0 then "Chest" else "Hips"
		local h = 1.6 - math.abs(i - 3) * 0.25
		rig:Shard(bone, Vector3.new(0, 7.6 - i * 0.05, z), Vector3.new(0, 7.6 + h, z + 0.7), 0.42, pal.Accent, pal.Glow)
	end
	-- Bushy tail
	for i = 2, 5 do
		local at = rig.Bones["Tail" .. i].Pivot.Position / rig.Scale
		rig:Sphere("Tail" .. i, at + Vector3.new(0, 0.05, 0.4), 0.55 + (i - 2) * 0.08, pal.Body)
	end
	local tip = rig.Bones["Tail5"].Pivot.Position / rig.Scale + Vector3.new(0, -0.45, 1.1)
	rig:Sphere("Tail5", tip, 0.75, pal.Body)
	rig:Sphere("Tail5", tip + Vector3.new(0, 0, 0.6), 0.45, pal.Accent, NEON)
end

-- A towering stag with branching ice-crystal antlers.
function Builders.GlacierStag(rig, pal)
	quadruped(rig, {
		Shoulder = 8.2, Hip = 7.8, Length = 6.8, ChestR = 1.9, HipR = 1.75, LegR = 0.45,
		NeckUp = 3.6, NeckOut = 2.2, HeadR = 1.05, Tail = 2, TailR = 0.35, TailDroop = -0.2, Paw = 0.5, NeckR = 0.45,
	}, pal)
	local head = rig.Bones.Head.Pivot.Position / rig.Scale
	rig:Sphere("Head", head, 0.95, pal.Body)
	rig:Capsule("Head", head + Vector3.new(0, -0.1, -0.5), head + Vector3.new(0, -0.55, -2), 0.7, 0.42, pal.Body)
	rig:Sphere("Head", head + Vector3.new(0, -0.55, -2.3), 0.3, pal.Dark)
	eyes(rig, "Head", head + Vector3.new(0, 0.2, -0.7), 0.55, 0.18, pal)
	for _, side in { -1, 1 } do
		-- Ears
		rig:Capsule("Head", head + Vector3.new(side * 0.7, 0.3, 0.3), head + Vector3.new(side * 1.6, 0.6, 0.6), 0.3, 0.12, pal.Body)
		-- Antlers: a main beam with tines, all crystal.
		local base = head + Vector3.new(side * 0.45, 0.8, 0.2)
		local mid = base + Vector3.new(side * 1.2, 2.2, 0.6)
		local top = mid + Vector3.new(side * 0.6, 2.4, -0.4)
		rig:Shard("Head", base, mid, 0.34, pal.Accent, pal.Glow)
		rig:Shard("Head", mid, top, 0.28, pal.Accent, pal.Glow)
		rig:Shard("Head", base + (mid - base) * 0.4, base + (mid - base) * 0.4 + Vector3.new(side * 0.3, 1.2, -1.2), 0.22, pal.Accent, WHITE)
		rig:Shard("Head", mid, mid + Vector3.new(side * 1.5, 0.9, 0.3), 0.22, pal.Accent, WHITE)
		rig:Shard("Head", mid + (top - mid) * 0.5, mid + (top - mid) * 0.5 + Vector3.new(side * 0.2, 1, -1), 0.2, pal.Accent, WHITE)
		rig:Shard("Head", top, top + Vector3.new(side * 0.9, 0.9, 0.5), 0.18, pal.Accent, WHITE)
	end
	-- Chest frost-fur and white tail
	rig:Sphere("Chest", rig.Bones.Chest.Pivot.Position / rig.Scale + Vector3.new(0, -0.3, -1.4), 1.25, pal.Belly)
	local tail = rig.Bones["Tail2"].Pivot.Position / rig.Scale
	rig:Sphere("Tail2", tail + Vector3.new(0, 0.2, 0.6), 0.55, WHITE)
	-- Glowing hooves
	for _, leg in { "FL", "FR", "BL", "BR" } do
		rig:Sphere(leg .. "Paw", rig.Bones[leg .. "Paw"].Pivot.Position / rig.Scale + Vector3.new(0, -0.15, 0), 0.45, pal.Glow, NEON)
	end
end

-- A walking fortress: a crystal-skinned giant with boulder fists.
function Builders.PrismGolem(rig, pal)
	rig:Bone("Hips", "Root", Vector3.new(0, 6.2, 0))
	rig:Bone("Chest", "Hips", Vector3.new(0, 8.4, 0))
	rig:Bone("Head", "Chest", Vector3.new(0, 12.2, -0.6))
	-- Pelvis and belly
	rig:Sphere("Hips", Vector3.new(0, 6.4, 0.1), 2.1, pal.Body)
	rig:Sphere("Hips", Vector3.new(0, 7.4, -0.6), 2, pal.Belly)
	-- Barrel chest, shoulders hunched forward
	rig:Sphere("Chest", Vector3.new(0, 9.6, 0), 3, pal.Body)
	rig:Sphere("Chest", Vector3.new(0, 9.4, -1.2), 2.4, pal.Belly)
	rig:Sphere("Chest", Vector3.new(0, 10.6, 1), 2.6, pal.Body) -- hunched back
	rig:Sphere("Chest", Vector3.new(0, 9.4, -2.9), 0.75, pal.Glow, NEON) -- heart core
	for i = -1, 1 do
		rig:Shard("Chest", Vector3.new(i * 1.3, 11.6, 2), Vector3.new(i * 1.8, 14.2 - math.abs(i) * 0.8, 3.4), 0.7, pal.Accent, pal.Glow)
	end
	-- Head sunk between the shoulders
	rig:Sphere("Head", Vector3.new(0, 12.4, -1), 1.35, pal.Body)
	rig:Capsule("Head", Vector3.new(-0.9, 12.9, -1.9), Vector3.new(0.9, 12.9, -1.9), 0.42, 0.42, pal.Dark) -- brow
	eyes(rig, "Head", Vector3.new(0, 12.45, -2.15), 0.5, 0.2, pal)
	rig:Shard("Head", Vector3.new(0, 13.4, -0.8), Vector3.new(0, 15, -0.2), 0.5, pal.Accent, pal.Glow)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		-- Arm: huge shoulder, long arm, boulder fist with crystal knuckles.
		local shoulder = Vector3.new(side * 3.3, 11, -0.2)
		local elbow = Vector3.new(side * 4.2, 7.6, -0.8)
		local hand = Vector3.new(side * 4.4, 4.4, -1.6)
		rig:Bone("Arm" .. s, "Chest", shoulder)
		rig:Bone("Fore" .. s, "Arm" .. s, elbow)
		rig:Bone("Hand" .. s, "Fore" .. s, hand)
		rig:Sphere("Arm" .. s, shoulder, 1.9, pal.Body)
		rig:Capsule("Arm" .. s, shoulder, elbow, 1.3, 1.05, pal.Body)
		rig:Capsule("Fore" .. s, elbow, hand, 1.15, 1.35, pal.Body)
		rig:Sphere("Hand" .. s, hand + Vector3.new(0, -0.6, -0.2), 1.8, pal.Belly)
		for k = -1, 1 do
			rig:Shard("Hand" .. s, hand + Vector3.new(side * 0.2 + k * 0.7, -0.4, -1.6), hand + Vector3.new(side * 0.2 + k * 0.7, -0.6, -2.6), 0.45, pal.Accent, pal.Glow)
		end
		for k = 1, 2 do
			rig:Shard("Arm" .. s, shoulder + Vector3.new(side * 0.5, 1, k * 0.6 - 0.6), shoulder + Vector3.new(side * (1.4 + k * 0.4), 3 - k * 0.4, k * 0.8 - 0.6), 0.6, pal.Accent, pal.Glow)
		end
		-- Legs: short and massive.
		local hip = Vector3.new(side * 1.5, 5.6, 0.2)
		local knee = Vector3.new(side * 1.8, 3.1, -0.4)
		local foot = Vector3.new(side * 1.9, 0.9, -0.1)
		rig:Bone("Thigh" .. s, "Hips", hip)
		rig:Bone("Shin" .. s, "Thigh" .. s, knee)
		rig:Bone("Foot" .. s, "Shin" .. s, foot)
		rig:Capsule("Thigh" .. s, hip, knee, 1.45, 1.15, pal.Body)
		rig:Capsule("Shin" .. s, knee, foot, 1.1, 1, pal.Body)
		rig:Sphere("Foot" .. s, foot + Vector3.new(0, -0.2, -0.5), 1.15, pal.Belly)
		rig:Sphere("Foot" .. s, foot + Vector3.new(0, -0.2, -1.2), 0.85, pal.Belly)
	end
	-- Glowing veins running from the heart core across the chest
	for _, side in { -1, 1 } do
		rig:Capsule("Chest", Vector3.new(side * 0.6, 9.6, -2.95), Vector3.new(side * 2.2, 10.8, -2.2), 0.08, 0.05, pal.Glow, NEON)
		rig:Capsule("Chest", Vector3.new(side * 0.6, 9.2, -2.95), Vector3.new(side * 1.9, 8.2, -2.3), 0.07, 0.04, pal.Glow, NEON)
	end
end

-- A coiled serpent-dragon rising from the ground on crystal wings.
function Builders.PyreWyrm(rig, pal)
	-- The coil on the ground
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		rig:Sphere("Root", Vector3.new(math.cos(a) * 2.6, 1.1, math.sin(a) * 2.6 + 1.5), 1.25 - i * 0.04, if i % 2 == 0 then pal.Body else pal.Belly)
	end
	-- The rising body: a chain of bones the client undulates.
	local previous = "Root"
	local points = {}
	for i = 1, 8 do
		local t = i / 8
		points[i] = Vector3.new(math.sin(t * 3.4) * 1.3, 1.6 + t * 9.6, 1.6 - t * 3.4 + math.sin(t * 5) * 0.6)
	end
	for i, p in points do
		local name = "Spine" .. i
		rig:Bone(name, previous, p)
		local nextP = points[i + 1] or (p + Vector3.new(0, 0.8, -1.3))
		local r = 1.35 - i * 0.07
		rig:Capsule(name, p, nextP, r, r - 0.07, pal.Body)
		rig:Sphere(name, (p + nextP) / 2 + Vector3.new(0, -0.1, -r * 0.55), r * 0.62, pal.Belly)
		if i % 2 == 0 then
			rig:Shard(name, p + Vector3.new(0, r * 0.6, r * 0.6), p + Vector3.new(0, r * 0.6 + 1.3, r * 0.6 + 0.9), 0.36, pal.Accent, pal.Glow)
		end
		previous = name
	end
	-- Head
	local neckTop = points[8] + Vector3.new(0, 0.8, -1.3)
	rig:Bone("Head", "Spine8", neckTop)
	rig:Bone("Jaw", "Head", neckTop + Vector3.new(0, -0.5, -0.6))
	rig:Sphere("Head", neckTop, 1.2, pal.Body)
	rig:Capsule("Head", neckTop + Vector3.new(0, 0.1, -0.6), neckTop + Vector3.new(0, -0.05, -2.8), 0.85, 0.5, pal.Body)
	rig:Capsule("Head", neckTop + Vector3.new(-0.55, 0.65, -0.9), neckTop + Vector3.new(0.55, 0.65, -0.9), 0.3, 0.3, pal.Dark)
	eyes(rig, "Head", neckTop + Vector3.new(0, 0.55, -1.2), 0.55, 0.2, pal)
	for _, side in { -1, 1 } do
		rig:Sphere("Head", neckTop + Vector3.new(side * 0.3, 0.2, -2.95), 0.12, pal.Glow, NEON) -- nostrils
		rig:Shard("Head", neckTop + Vector3.new(side * 0.5, 0.9, 0), neckTop + Vector3.new(side * 1.2, 2.2, 1.6), 0.32, pal.Accent, pal.Glow)
		rig:Shard("Head", neckTop + Vector3.new(side * 0.8, 0.3, 0.2), neckTop + Vector3.new(side * 1.9, 0.6, 1.4), 0.24, pal.Accent, WHITE)
		-- Whisker-fins along the jaw
		rig:Capsule("Head", neckTop + Vector3.new(side * 0.6, -0.3, -1.8), neckTop + Vector3.new(side * 1.6, -0.9, -1.3), 0.08, 0.03, pal.Glow, NEON)
	end
	local jaw = neckTop + Vector3.new(0, -0.5, -0.6)
	rig:Capsule("Jaw", jaw, jaw + Vector3.new(0, -0.25, -2.1), 0.55, 0.35, pal.Belly)
	for i = 1, 4 do
		for _, side in { -1, 1 } do
			rig:Capsule("Head", neckTop + Vector3.new(side * 0.45, -0.4, -0.9 - i * 0.45), neckTop + Vector3.new(side * 0.45, -0.75, -0.9 - i * 0.45), 0.07, 0.02, WHITE, NEON)
		end
	end
	-- Wings: arm bones with crystal spars and glowing membranes.
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local shoulder = points[5] + Vector3.new(side * 1, 0.2, 0.4)
		rig:Bone("Wing" .. s, "Spine5", shoulder)
		local elbow = shoulder + Vector3.new(side * 3.2, 1.6, 0.6)
		rig:Bone("WingTip" .. s, "Wing" .. s, elbow)
		rig:Capsule("Wing" .. s, shoulder, elbow, 0.38, 0.28, pal.Body)
		for k = 0, 3 do
			local tip = elbow + Vector3.new(side * (2.6 - k * 0.3), 2.2 - k * 1.5, 0.4 + k * 0.6)
			rig:Shard("WingTip" .. s, elbow, tip, 0.18, pal.Accent, pal.Glow)
			rig:Disc("WingTip" .. s, elbow:Lerp(tip, 0.55) + Vector3.new(0, -0.6, 0.4), Vector3.new(0, 0, 1), 1.5 - k * 0.12, 0.12, pal.Accent, GLASS, 0.35)
		end
		rig:Disc("Wing" .. s, shoulder:Lerp(elbow, 0.5) + Vector3.new(0, -0.8, 0.3), Vector3.new(0, 0, 1), 1.6, 0.12, pal.Accent, GLASS, 0.35)
	end
	-- A tail sweeping out behind the coil
	previous = "Root"
	local at = Vector3.new(2, 1, 3.6)
	for i = 1, 4 do
		local name = "Tail" .. i
		rig:Bone(name, previous, at)
		local nextAt = at + Vector3.new(0.6, 0.1, 1.5)
		rig:Capsule(name, at, nextAt, 0.9 - i * 0.15, 0.8 - i * 0.15, pal.Body)
		previous = name
		at = nextAt
	end
	rig:Shard("Tail4", at, at + Vector3.new(0.4, 0.6, 1.8), 0.5, pal.Accent, pal.Glow)
end

-- A storm bird with layered lightning-veined feathers.
function Builders.ThunderRoc(rig, pal)
	rig:Bone("Hips", "Root", Vector3.new(0, 5.4, 0.6))
	rig:Bone("Chest", "Hips", Vector3.new(0, 6.6, -0.8))
	-- Egg-shaped body
	rig:Sphere("Hips", Vector3.new(0, 6, 0.8), 2.1, pal.Body)
	rig:Sphere("Chest", Vector3.new(0, 7, -0.6), 2.3, pal.Body)
	rig:Sphere("Chest", Vector3.new(0, 6.6, -1.6), 1.8, pal.Belly)
	-- Neck curving up to the head
	rig:Bone("Neck", "Chest", Vector3.new(0, 8.4, -1.6))
	rig:Capsule("Neck", Vector3.new(0, 8.2, -1.5), Vector3.new(0, 10, -2.4), 1.05, 0.8, pal.Body)
	rig:Bone("Head", "Neck", Vector3.new(0, 10.4, -2.6))
	rig:Sphere("Head", Vector3.new(0, 10.5, -2.6), 1.05, pal.Body)
	eyes(rig, "Head", Vector3.new(0, 10.75, -3.25), 0.55, 0.2, pal)
	-- Hooked beak
	rig:Capsule("Head", Vector3.new(0, 10.4, -3.4), Vector3.new(0, 10.1, -4.6), 0.45, 0.2, pal.Accent, NEON)
	rig:Capsule("Head", Vector3.new(0, 10.1, -4.6), Vector3.new(0, 9.6, -4.75), 0.2, 0.06, pal.Accent, NEON)
	-- Crest of lightning plumes
	for k = -2, 2 do
		rig:Shard("Head", Vector3.new(k * 0.18, 11.3, -2.4), Vector3.new(k * 0.6, 13 - math.abs(k) * 0.3, -1.2 + math.abs(k) * 0.2), 0.22, pal.Accent, WHITE)
	end
	-- Legs with talons
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local hip = Vector3.new(side * 1, 5, 0.6)
		local ankle = Vector3.new(side * 1.1, 1.2, 0.4)
		rig:Bone("Thigh" .. s, "Hips", hip)
		rig:Bone("Foot" .. s, "Thigh" .. s, ankle)
		rig:Capsule("Thigh" .. s, hip, hip + Vector3.new(0, -1.8, -0.3), 0.8, 0.45, pal.Body)
		rig:Capsule("Thigh" .. s, hip + Vector3.new(0, -1.8, -0.3), ankle, 0.3, 0.25, pal.Accent, NEON)
		for k = -1, 1 do
			rig:Capsule("Foot" .. s, ankle, ankle + Vector3.new(k * 0.6, -1, -1), 0.18, 0.06, pal.Accent, NEON)
		end
		rig:Capsule("Foot" .. s, ankle, ankle + Vector3.new(0, -1, 0.8), 0.15, 0.05, pal.Accent, NEON)
		-- Wings: shoulder, forearm and hand, each carrying a row of feathers.
		local shoulder = Vector3.new(side * 1.8, 8, -0.6)
		local elbow = shoulder + Vector3.new(side * 3, 0.6, 0.6)
		local wrist = elbow + Vector3.new(side * 3, -0.4, 0.4)
		rig:Bone("Wing" .. s, "Chest", shoulder)
		rig:Bone("WingMid" .. s, "Wing" .. s, elbow)
		rig:Bone("WingTip" .. s, "WingMid" .. s, wrist)
		rig:Capsule("Wing" .. s, shoulder, elbow, 0.75, 0.5, pal.Body)
		rig:Capsule("WingMid" .. s, elbow, wrist, 0.5, 0.35, pal.Body)
		local function feathers(bone: string, from: Vector3, to: Vector3, count: number, length: number)
			for k = 0, count - 1 do
				local at = from:Lerp(to, k / math.max(1, count - 1))
				local tip = at + Vector3.new(side * 0.4, -length * 0.35, length)
				rig:Capsule(bone, at, tip, 0.32, 0.12, if k % 2 == 0 then pal.Body else pal.Accent)
				rig:Capsule(bone, at + Vector3.new(0, 0.12, 0), tip + Vector3.new(0, 0.12, 0), 0.07, 0.03, pal.Glow, NEON)
			end
		end
		feathers("Wing" .. s, shoulder + Vector3.new(side * 0.8, 0, 0.3), elbow, 4, 2.4)
		feathers("WingMid" .. s, elbow, wrist, 4, 3)
		feathers("WingTip" .. s, wrist, wrist + Vector3.new(side * 2.4, -0.6, 0.6), 5, 3.6)
	end
	-- Tail fan
	rig:Bone("Tail1", "Hips", Vector3.new(0, 5.8, 2.6))
	for k = -3, 3 do
		local tip = Vector3.new(k * 0.75, 5 - math.abs(k) * 0.15, 6.4 - math.abs(k) * 0.3)
		rig:Capsule("Tail1", Vector3.new(k * 0.15, 5.8, 2.6), tip, 0.35, 0.18, if k % 2 == 0 then pal.Accent else pal.Body)
		rig:Capsule("Tail1", Vector3.new(k * 0.15, 5.95, 2.6), tip + Vector3.new(0, 0.12, 0), 0.07, 0.03, pal.Glow, NEON)
	end
end

-- A vast moth with stained-glass wings and feathered antennae.
function Builders.DreamMoth(rig, pal)
	rig:Bone("Hips", "Root", Vector3.new(0, 7.2, 0))
	rig:Bone("Chest", "Hips", Vector3.new(0, 7.6, -0.6))
	-- Fuzzy thorax and banded abdomen
	rig:Sphere("Chest", Vector3.new(0, 7.6, -0.6), 1.5, pal.Body)
	rig:Sphere("Chest", Vector3.new(0, 7.9, -1.3), 1.25, pal.Belly)
	rig:Bone("Tail1", "Hips", Vector3.new(0, 7.2, 0.6))
	for i = 0, 4 do
		rig:Sphere("Tail1", Vector3.new(0, 7.1 - i * 0.28, 1 + i * 0.85), 1.25 - i * 0.18, if i % 2 == 0 then pal.Body else pal.Accent)
	end
	rig:Sphere("Tail1", Vector3.new(0, 5.8, 5.2), 0.3, pal.Glow, NEON)
	rig:Bone("Head", "Chest", Vector3.new(0, 7.8, -2))
	rig:Sphere("Head", Vector3.new(0, 7.8, -2.3), 1, pal.Body)
	-- Huge compound eyes
	for _, side in { -1, 1 } do
		rig:Sphere("Head", Vector3.new(side * 0.65, 7.95, -2.75), 0.55, pal.Eye, NEON)
		-- Feathered antennae
		local base = Vector3.new(side * 0.35, 8.6, -2.6)
		local tip = base + Vector3.new(side * 1.2, 2.4, -1.4)
		rig:Capsule("Head", base, tip, 0.07, 0.04, pal.Glow, NEON)
		for k = 1, 5 do
			local at = base:Lerp(tip, k / 6)
			rig:Capsule("Head", at, at + Vector3.new(side * 0.5, 0.15, 0.3), 0.05, 0.02, pal.Accent, NEON)
		end
	end
	-- Fluffy collar
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		rig:Sphere("Chest", Vector3.new(math.cos(a) * 1.15, 7.6 + math.sin(a) * 1.1, -1.7), 0.55, WHITE)
	end
	-- Four wings made of overlapping rounded panes with glowing eye-spots and veins.
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		rig:Bone("Wing" .. s, "Chest", Vector3.new(side * 0.9, 8, -0.6))
		rig:Bone("HindWing" .. s, "Chest", Vector3.new(side * 0.9, 7.4, 0.2))
		local function pane(bone: string, center: Vector3, radius: number, color: Color3)
			rig:Disc(bone, center, Vector3.new(0, 0, 1), radius, 0.12, color, GLASS, 0.3)
		end
		local w = Vector3.new(side * 0.9, 8, -0.6)
		pane("Wing" .. s, w + Vector3.new(side * 2.2, 1.6, 0), 2.3, pal.Body)
		pane("Wing" .. s, w + Vector3.new(side * 4.2, 2.6, 0.05), 2, pal.Accent)
		pane("Wing" .. s, w + Vector3.new(side * 5.6, 3.4, 0.1), 1.3, pal.Body)
		rig:Disc("Wing" .. s, w + Vector3.new(side * 3.8, 2.4, -0.05), Vector3.new(0, 0, 1), 0.85, 0.16, pal.Glow, NEON, 0)
		rig:Disc("Wing" .. s, w + Vector3.new(side * 3.8, 2.4, -0.1), Vector3.new(0, 0, 1), 0.45, 0.18, pal.Dark, PLASTIC, 0)
		for k = 0, 3 do
			local tip = w + Vector3.new(side * (3 + k * 0.9), 4.2 - k * 1.5, -0.1)
			rig:Capsule("Wing" .. s, w, tip, 0.07, 0.04, pal.Glow, NEON)
		end
		local h = Vector3.new(side * 0.9, 7.4, 0.2)
		pane("HindWing" .. s, h + Vector3.new(side * 1.8, -1.4, 0.1), 1.8, pal.Accent)
		pane("HindWing" .. s, h + Vector3.new(side * 3, -2.6, 0.15), 1.2, pal.Body)
		rig:Disc("HindWing" .. s, h + Vector3.new(side * 2.3, -1.9, 0), Vector3.new(0, 0, 1), 0.5, 0.16, pal.Glow, NEON, 0)
		-- Slender legs dangling
		for k = 0, 2 do
			rig:Capsule("Chest", Vector3.new(side * 0.6, 6.6, -1.2 + k * 0.6), Vector3.new(side * 1.3, 4.9, -1.6 + k * 0.9), 0.08, 0.05, pal.Dark)
		end
	end
end

-- A giant celestial koi that swims through the air, trailing veil fins.
function Builders.StarKoi(rig, pal)
	local previous = "Root"
	-- A smooth, plump body tapering to the tail (capsules between bones).
	local profile = { 1.55, 1.9, 1.85, 1.6, 1.25, 0.85, 0.55 }
	local points = {}
	for i = 1, #profile do
		points[i] = Vector3.new(0, 7 + math.sin(i * 0.7) * 0.15, -2.6 + (i - 1) * 1.35)
	end
	for i, r in profile do
		local name = "Body" .. i
		rig:Bone(name, previous, points[i])
		local nextP = points[i + 1] or (points[i] + Vector3.new(0, 0, 1))
		local nextR = profile[i + 1] or r * 0.7
		rig:Capsule(name, points[i], nextP, r, nextR, pal.Body)
		-- Pale belly
		rig:Capsule(name, points[i] + Vector3.new(0, -r * 0.4, 0), nextP + Vector3.new(0, -nextR * 0.4, 0), r * 0.68, nextR * 0.68, pal.Belly)
		-- Koi patches on the back and flanks
		if i <= 5 then
			rig:Sphere(name, points[i] + Vector3.new(if i % 2 == 0 then 0.5 else -0.45, r * 0.62, 0.3), r * 0.55, pal.Accent)
			rig:Sphere(name, points[i] + Vector3.new(if i % 2 == 0 then -r * 0.7 else r * 0.7, r * 0.15, 0.5), r * 0.4, pal.Accent)
		end
		previous = name
	end
	-- Head: rounded with a pouty mouth, big glossy eyes and long barbels.
	rig:Bone("Head", "Body1", points[1])
	rig:Sphere("Head", points[1] + Vector3.new(0, 0.05, -0.6), 1.45, pal.Body)
	rig:Capsule("Head", points[1] + Vector3.new(0, -0.15, -1.2), points[1] + Vector3.new(0, -0.25, -1.9), 0.95, 0.6, pal.Belly)
	rig:Disc("Head", points[1] + Vector3.new(0, -0.25, -2.45), Vector3.new(0, 0, -1), 0.42, 0.22, pal.Dark, PLASTIC, 0)
	rig:Sphere("Head", points[1] + Vector3.new(0, 0.85, -0.4), 0.7, pal.Accent)
	eyes(rig, "Head", points[1] + Vector3.new(0, 0.4, -1.45), 0.95, 0.27, pal)
	for _, side in { -1, 1 } do
		local base = points[1] + Vector3.new(side * 0.5, -0.45, -2.2)
		rig:Capsule("Head", base, base + Vector3.new(side * 0.9, -0.7, -1), 0.08, 0.05, pal.Glow, NEON)
		rig:Capsule("Head", base + Vector3.new(side * 0.9, -0.7, -1), base + Vector3.new(side * 1.5, -1.6, -0.6), 0.05, 0.03, pal.Glow, NEON)
		-- Pectoral fins: layered glowing panes
		local s = if side < 0 then "L" else "R"
		rig:Bone("Fin" .. s, "Body2", points[2] + Vector3.new(side * 1.5, -0.8, 0))
		rig:Disc("Fin" .. s, points[2] + Vector3.new(side * 2.5, -1.5, 0.5), Vector3.new(side, 0.7, 0.2), 1.3, 0.1, pal.Accent, GLASS, 0.3)
		rig:Disc("Fin" .. s, points[2] + Vector3.new(side * 3.1, -2, 1), Vector3.new(side, 0.7, 0.2), 0.8, 0.1, pal.Glow, GLASS, 0.4)
		-- Pelvic fins
		rig:Disc("Body4", points[4] + Vector3.new(side * 1.2, -1.5, 0.3), Vector3.new(side, 0.5, 0), 0.75, 0.1, pal.Accent, GLASS, 0.3)
	end
	-- Dorsal fin: a crest of overlapping translucent panes with a glowing ridge
	for k = 0, 3 do
		rig:Disc("Body" .. (k + 2), points[k + 2] + Vector3.new(0, 2 - k * 0.2, 0.3), Vector3.new(1, 0, 0), 1.1 - k * 0.12, 0.1, pal.Accent, GLASS, 0.3)
		rig:Capsule("Body" .. (k + 2), points[k + 2] + Vector3.new(0, 1.7, -0.3), points[k + 2] + Vector3.new(0, 2.9 - k * 0.25, 0.8), 0.07, 0.05, pal.Glow, NEON)
	end
	-- Veil tail: long flowing panes on their own bones so they ripple.
	rig:Bone("Tail1", "Body7", points[7] + Vector3.new(0, 0, 0.6))
	rig:Bone("Tail2", "Tail1", points[7] + Vector3.new(0, 0, 2.8))
	for _, tilt in { -1, 1 } do
		rig:Disc("Tail1", points[7] + Vector3.new(0, tilt * 1.2, 1.9), Vector3.new(1, 0, 0), 1.6, 0.1, pal.Accent, GLASS, 0.3)
		rig:Disc("Tail2", points[7] + Vector3.new(0, tilt * 2.3, 3.8), Vector3.new(1, 0, 0), 1.7, 0.1, pal.Body, GLASS, 0.35)
		rig:Disc("Tail2", points[7] + Vector3.new(0, tilt * 3, 5.1), Vector3.new(1, 0, 0), 1.1, 0.1, pal.Accent, GLASS, 0.4)
		rig:Capsule("Tail1", points[7] + Vector3.new(0, 0, 0.6), points[7] + Vector3.new(0, tilt * 2.4, 2.8), 0.08, 0.05, pal.Glow, NEON)
		rig:Capsule("Tail2", points[7] + Vector3.new(0, tilt * 2.4, 2.8), points[7] + Vector3.new(0, tilt * 3.8, 5.6), 0.06, 0.03, pal.Glow, NEON)
	end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function BeastModels.Palette(color: Color3, accent: Color3): Palette
	local h, s, v = color:ToHSV()
	return {
		Body = Color3.fromHSV(h, math.min(1, s * 0.75), math.max(0.35, v * 0.9)),
		Belly = Color3.fromHSV(h, s * 0.35, math.min(1, v * 0.95 + 0.1)),
		Dark = Color3.fromHSV(h, math.min(1, s * 0.8), v * 0.25),
		Accent = accent,
		Glow = color:Lerp(WHITE, 0.45),
		Eye = accent:Lerp(WHITE, 0.4),
	}
end

-- Builds the creature into `model`, rigged under `core` (beast space origin).
function BeastModels.Build(kind: string, model: Model, core: BasePart, scale: number, color: Color3, accent: Color3): boolean
	local builder = Builders[kind]
	if not builder then
		return false
	end
	local rig = newRig(model, core, scale)
	builder(rig, BeastModels.Palette(color, accent))
	return true
end

BeastModels.Kinds = { "PrismGolem", "PyreWyrm", "GlacierStag", "UmbralMaw", "ThunderRoc", "DreamMoth", "SolarLion", "StarKoi" }


return BeastModels
