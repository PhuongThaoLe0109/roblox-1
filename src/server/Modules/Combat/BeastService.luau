-- BeastService
-- The ultimate (G) of the rarest gems: the fighter transforms into a giant
-- crystal beast for a while. Their body is hidden inside a beast model welded
-- to the root (so everyone sees it); their strikes become the beast maul,
-- they take less damage and move at the beast's speed. Built from plain
-- Glass / Neon parts in the gem's colours, no meshes or textures.
--
-- Beasts: Prism Golem, Pyre Wyrm, Glacier Stag, Umbral Maw, Thunder Roc,
-- Dream Moth, Solar Lion, Star Koi.
--
-- Client contract: Model "Beast" tagged "BeastForm" (attribute Kind). Joint
-- welds named WingL / WingR / Tail / Head / ArmL / ArmR / FinL / FinR are
-- animated locally by the client (it only changes their C0).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local STATUS = CombatConfig.Status
local WHITE = Color3.new(1, 1, 1)

local BeastService = {}

type Add = (name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, transparency: number?, group: string?, shape: Enum.PartType?) -> Part
type Joint = (name: string, pivot: CFrame) -> ()

local GLASS = Enum.Material.Glass
local NEON = Enum.Material.Neon
local BALL = Enum.PartType.Ball

local function rad(d: number): number
	return math.rad(d)
end

-- Every builder works in "beast space": origin on the ground under the
-- fighter, facing -Z, 1 unit = 1 stud at scale 1.
local Builders: { [string]: (add: Add, joint: Joint, c: Color3, a: Color3) -> () } = {}

function Builders.PrismGolem(add, joint, c, a)
	for _, x in { -1.6, 1.6 } do
		add("Leg", Vector3.new(2.2, 4, 2.2), CFrame.new(x, 2.4, 0), c, GLASS, 0.15)
		add("Foot", Vector3.new(2.6, 1, 3.2), CFrame.new(x, 0.5, -0.3), a, GLASS, 0.1)
	end
	add("Pelvis", Vector3.new(4.4, 1.6, 2.6), CFrame.new(0, 5, 0), a, GLASS, 0.1)
	add("Torso", Vector3.new(5.8, 4.4, 3.4), CFrame.new(0, 7.8, 0), c, GLASS, 0.15)
	add("TorsoCore", Vector3.new(3.4, 2.6, 2.2), CFrame.new(0, 7.8, 0), WHITE, NEON, 0.35)
	add("Heart", Vector3.new(1.6, 1.6, 0.8), CFrame.new(0, 8.1, -1.8) * CFrame.Angles(0, 0, rad(45)), WHITE, NEON)
	for _, side in { -1, 1 } do
		for k = 1, 3 do
			add("Pauldron", Vector3.new(1.1, 2.4 + k * 0.5, 1.1), CFrame.new(side * (3.2 + k * 0.3), 10 + k * 0.2, (k - 2) * 0.6) * CFrame.Angles(0, rad(45), -side * rad(10 + k * 12)), if k == 2 then a else c, GLASS, 0.1)
		end
		local arm = if side < 0 then "ArmL" else "ArmR"
		joint(arm, CFrame.new(side * 3.7, 9.4, 0))
		add("UpperArm", Vector3.new(1.9, 3.6, 1.9), CFrame.new(side * 3.7, 7.4, 0), c, GLASS, 0.15, arm)
		add("Fist", Vector3.new(2.8, 2.8, 2.8), CFrame.new(side * 3.8, 4.6, -0.4), a, GLASS, 0.1, arm)
		add("FistCore", Vector3.new(1.4, 1.4, 1.4), CFrame.new(side * 3.8, 4.6, -0.4) * CFrame.Angles(rad(45), rad(45), 0), WHITE, NEON, 0, arm)
	end
	joint("Head", CFrame.new(0, 10, 0))
	add("Head", Vector3.new(2.3, 2.1, 2.3), CFrame.new(0, 11.2, -0.2) * CFrame.Angles(0, rad(45), 0), c, GLASS, 0.1, "Head")
	for _, x in { -0.45, 0.45 } do
		add("Eye", Vector3.new(0.5, 0.25, 0.2), CFrame.new(x, 11.4, -1.45), WHITE, NEON, 0, "Head")
	end
	for k = -1, 1 do
		add("Crest", Vector3.new(0.5, 1.8 - math.abs(k) * 0.5, 0.5), CFrame.new(k * 0.6, 12.8, 0.2) * CFrame.Angles(0, rad(45), -k * 0.4), a, NEON, 0, "Head")
	end
	for k = -1, 1 do
		add("BackCrystal", Vector3.new(1, 3.4 - math.abs(k), 1), CFrame.new(k * 1.4, 10, 1.6) * CFrame.Angles(rad(30), rad(45), -k * 0.3), c, GLASS, 0.1)
	end
end

function Builders.PyreWyrm(add, joint, c, a)
	-- A coiled body rising in an S-curve.
	local previous = Vector3.new(0, 1.4, 2)
	for i = 0, 7 do
		local t = i / 7
		local p = Vector3.new(math.sin(t * 5) * 1.8, 1.4 + t * 8.5, 2 - t * 3 + math.cos(t * 4) * 1.2)
		local size = 3.4 - t * 1.4
		add("Coil", Vector3.one * size, CFrame.new(p), if i % 2 == 0 then c else a, GLASS, 0.15, nil, BALL)
		add("Belly", Vector3.new(size * 0.5, size * 0.5, size * 0.5), CFrame.new(p + Vector3.new(0, 0, -size * 0.35)), WHITE, NEON, 0.2, nil, BALL)
		if i > 0 and i % 2 == 0 then
			add("Spine", Vector3.new(0.5, 1.6, 0.5), CFrame.lookAt(p, previous) * CFrame.new(0, size * 0.55, 0) * CFrame.Angles(rad(-20), rad(45), 0), a, NEON)
		end
		previous = p
	end
	local neck = Vector3.new(math.sin(5) * 1.8, 9.9, -1 + math.cos(4) * 1.2)
	joint("Head", CFrame.new(neck))
	add("Head", Vector3.new(2.4, 1.8, 3.8), CFrame.new(neck + Vector3.new(0, 0.6, -1.6)) * CFrame.Angles(rad(-10), 0, 0), c, GLASS, 0.1, "Head")
	add("Jaw", Vector3.new(2, 0.6, 3), CFrame.new(neck + Vector3.new(0, -0.5, -1.8)) * CFrame.Angles(rad(12), 0, 0), a, NEON, 0.1, "Head")
	for _, x in { -0.7, 0.7 } do
		add("Eye", Vector3.new(0.4, 0.3, 0.4), CFrame.new(neck + Vector3.new(x, 1, -2.9)), WHITE, NEON, 0, "Head")
		add("Horn", Vector3.new(0.45, 2.6, 0.45), CFrame.new(neck + Vector3.new(x, 1.9, -0.2)) * CFrame.Angles(rad(-45), rad(45), x * 0.3), a, NEON, 0, "Head")
	end
	for _, side in { -1, 1 } do
		local wing = if side < 0 then "WingL" else "WingR"
		local root = Vector3.new(side * 1.4, 7, 0.8)
		joint(wing, CFrame.new(root))
		for k = 1, 4 do
			local angle = rad(15 + k * 20)
			local length = 7.5 - k * 0.9
			local spar = CFrame.new(root) * CFrame.Angles(0, 0, -side * angle) * CFrame.new(0, length / 2, 0)
			add("Spar", Vector3.new(0.3, length, 0.3), spar, a, NEON, 0, wing)
			add("Membrane", Vector3.new(0.12, length * 0.9, 2.2), spar * CFrame.new(0, 0, 1.1), c, GLASS, 0.35, wing)
		end
	end
	joint("Tail", CFrame.new(0, 1.2, 3.2))
	for i = 1, 5 do
		add("Tail", Vector3.one * (1.8 - i * 0.25), CFrame.new(i * 0.4, 0.9, 3.2 + i * 1.3), if i % 2 == 0 then c else a, GLASS, 0.15, "Tail", BALL)
	end
	add("TailBlade", Vector3.new(0.3, 1.6, 2.2), CFrame.new(2.4, 1, 10.4) * CFrame.Angles(0, rad(20), 0), WHITE, NEON, 0, "Tail")
end

function Builders.GlacierStag(add, joint, c, a)
	add("Body", Vector3.new(3, 3, 6.4), CFrame.new(0, 6, 0), c, GLASS, 0.15)
	add("BodyCore", Vector3.new(1.6, 1.6, 4.4), CFrame.new(0, 6, 0), WHITE, NEON, 0.4)
	for _, x in { -1, 1 } do
		for _, z in { -2.4, 2.4 } do
			add("Leg", Vector3.new(0.9, 4.8, 0.9), CFrame.new(x, 2.4, z), c, GLASS, 0.15)
			add("Hoof", Vector3.new(1.1, 0.6, 1.1), CFrame.new(x, 0.3, z) * CFrame.Angles(0, rad(45), 0), a, NEON)
		end
	end
	add("Neck", Vector3.new(1.4, 4, 1.4), CFrame.new(0, 8.6, -2.8) * CFrame.Angles(rad(-25), 0, 0), c, GLASS, 0.15)
	joint("Head", CFrame.new(0, 10.4, -3.6))
	add("Head", Vector3.new(1.6, 1.6, 3.2), CFrame.new(0, 10.6, -4.6) * CFrame.Angles(rad(15), 0, 0), c, GLASS, 0.1, "Head")
	for _, x in { -0.5, 0.5 } do
		add("Eye", Vector3.new(0.3, 0.3, 0.3), CFrame.new(x, 11, -5.4), WHITE, NEON, 0, "Head")
	end
	-- Branching ice-crystal antlers.
	for _, side in { -1, 1 } do
		local base = Vector3.new(side * 0.6, 11.4, -4.2)
		add("Antler", Vector3.new(0.4, 4.4, 0.4), CFrame.new(base) * CFrame.Angles(rad(-15), 0, -side * rad(25)) * CFrame.new(0, 2.2, 0), a, NEON, 0, "Head")
		for k = 1, 4 do
			local along = CFrame.new(base) * CFrame.Angles(rad(-15), 0, -side * rad(25)) * CFrame.new(0, k * 1, 0)
			add("Tine", Vector3.new(0.3, 2.2 - k * 0.25, 0.3), along * CFrame.Angles(rad(if k % 2 == 0 then 30 else -30), 0, -side * rad(40)) * CFrame.new(0, 1, 0), if k % 2 == 0 then c else WHITE, if k % 2 == 0 then GLASS else NEON, 0.1, "Head")
		end
	end
	joint("Tail", CFrame.new(0, 7, 3.2))
	add("Tail", Vector3.new(0.8, 0.8, 1.6), CFrame.new(0, 7.2, 3.8) * CFrame.Angles(rad(30), 0, 0), WHITE, NEON, 0, "Tail")
end

function Builders.UmbralMaw(add, joint, c, a)
	local dark = c:Lerp(Color3.new(0, 0, 0), 0.55)
	add("Body", Vector3.new(3.4, 3, 7.4), CFrame.new(0, 4.8, 0), dark, GLASS, 0.1)
	add("Ribs", Vector3.new(2.6, 1.6, 5), CFrame.new(0, 4.4, 0), a, NEON, 0.45)
	for i = -2, 2 do
		add("Spike", Vector3.new(0.6, 2.4 - math.abs(i) * 0.3, 0.6), CFrame.new(0, 6.6, i * 1.3) * CFrame.Angles(rad(25), rad(45), 0), a, NEON)
	end
	for _, x in { -1.2, 1.2 } do
		for _, z in { -2.6, 2.6 } do
			add("Leg", Vector3.new(1.2, 3.6, 1.2), CFrame.new(x, 1.8, z), dark, GLASS, 0.1)
			add("Claw", Vector3.new(1.4, 0.5, 1.6), CFrame.new(x, 0.25, z - 0.3), c, NEON)
		end
	end
	joint("Head", CFrame.new(0, 6, -3.8))
	add("Head", Vector3.new(2.6, 2.2, 3.2), CFrame.new(0, 6.2, -5.2), dark, GLASS, 0.1, "Head")
	add("Snout", Vector3.new(1.6, 1.2, 2), CFrame.new(0, 5.8, -7.2), dark, GLASS, 0.1, "Head")
	add("Jaw", Vector3.new(1.8, 0.6, 2.8), CFrame.new(0, 4.8, -6.6) * CFrame.Angles(rad(12), 0, 0), c, NEON, 0.1, "Head")
	for i = -2, 2 do
		add("Fang", Vector3.new(0.25, 0.8, 0.25), CFrame.new(i * 0.35, 5.2, -7.9), WHITE, NEON, 0, "Head")
	end
	for _, x in { -0.7, 0.7 } do
		add("Eye", Vector3.new(0.5, 0.3, 0.2), CFrame.new(x, 6.7, -6.8), a, NEON, 0, "Head")
		add("Ear", Vector3.new(0.5, 1.8, 0.8), CFrame.new(x, 7.8, -4.8) * CFrame.Angles(rad(-15), 0, x * 0.3), c, NEON, 0, "Head")
	end
	joint("Tail", CFrame.new(0, 5.4, 3.7))
	add("Tail", Vector3.new(1, 1, 4.4), CFrame.new(0, 6, 5.8) * CFrame.Angles(rad(25), 0, 0), dark, GLASS, 0.1, "Tail")
	add("TailFlame", Vector3.new(0.9, 0.9, 2), CFrame.new(0, 7, 7.9) * CFrame.Angles(rad(25), 0, 0), a, NEON, 0, "Tail")
end

function Builders.ThunderRoc(add, joint, c, a)
	add("Body", Vector3.new(3, 3.6, 5), CFrame.new(0, 6.4, 0), c, GLASS, 0.15)
	add("Breast", Vector3.new(2.2, 2.6, 1.4), CFrame.new(0, 6.4, -2.2), WHITE, NEON, 0.3)
	for _, x in { -0.8, 0.8 } do
		add("Leg", Vector3.new(0.6, 3.6, 0.6), CFrame.new(x, 2.6, 0.4), a, NEON)
		for k = -1, 1 do
			add("Talon", Vector3.new(0.3, 0.3, 1.4), CFrame.new(x + k * 0.35, 0.4, -0.2) * CFrame.Angles(0, k * 0.4, 0), c, NEON)
		end
	end
	joint("Head", CFrame.new(0, 8.4, -2))
	add("Head", Vector3.new(1.8, 1.8, 2.2), CFrame.new(0, 9.2, -2.8), c, GLASS, 0.1, "Head")
	add("Beak", Vector3.new(0.7, 0.7, 2.2), CFrame.new(0, 8.9, -4.6) * CFrame.Angles(rad(15), 0, rad(45)), a, NEON, 0, "Head")
	for _, x in { -0.55, 0.55 } do
		add("Eye", Vector3.new(0.3, 0.3, 0.3), CFrame.new(x, 9.5, -3.8), WHITE, NEON, 0, "Head")
	end
	add("Crest", Vector3.new(0.3, 2, 1.6), CFrame.new(0, 10.6, -2.4) * CFrame.Angles(rad(-30), 0, 0), a, NEON, 0, "Head")
	for _, side in { -1, 1 } do
		local wing = if side < 0 then "WingL" else "WingR"
		local root = Vector3.new(side * 1.4, 7.6, -0.4)
		joint(wing, CFrame.new(root))
		for k = 1, 6 do
			local length = 3 + k * 0.9
			local feather = CFrame.new(root) * CFrame.Angles(0, 0, -side * rad(72 - k * 6)) * CFrame.new(0, length / 2, k * 0.5 - 1)
			add("Feather", Vector3.new(0.18, length, 1.1), feather, if k % 2 == 0 then c else a, GLASS, 0.15, wing)
			add("Bolt", Vector3.new(0.12, length * 0.9, 0.12), feather * CFrame.new(0, 0, -0.55), WHITE, NEON, 0, wing)
		end
	end
	joint("Tail", CFrame.new(0, 6, 2.4))
	for k = -2, 2 do
		add("TailFeather", Vector3.new(0.6, 0.15, 4), CFrame.new(0, 6, 2.4) * CFrame.Angles(rad(-15), k * 0.25, 0) * CFrame.new(0, 0, 2), if k % 2 == 0 then a else c, NEON, 0.1, "Tail")
	end
end

function Builders.DreamMoth(add, joint, c, a)
	add("Thorax", Vector3.new(2, 2.2, 2.6), CFrame.new(0, 7.4, 0), c, GLASS, 0.1)
	add("Abdomen", Vector3.new(1.8, 1.8, 4.4), CFrame.new(0, 6.8, 3.2) * CFrame.Angles(rad(-12), 0, 0), a, GLASS, 0.1)
	for i = 1, 3 do
		add("Band", Vector3.new(1.9, 1.9, 0.3), CFrame.new(0, 6.9 - i * 0.18, 1.8 + i * 1.1) * CFrame.Angles(rad(-12), 0, 0), WHITE, NEON, 0.2)
	end
	joint("Head", CFrame.new(0, 7.6, -1.4))
	add("Head", Vector3.one * 1.7, CFrame.new(0, 7.8, -2.2), c, GLASS, 0.1, "Head", BALL)
	for _, x in { -0.5, 0.5 } do
		add("Eye", Vector3.one * 0.6, CFrame.new(x, 7.9, -2.8), a, NEON, 0, "Head", BALL)
		add("Antenna", Vector3.new(0.15, 3, 0.15), CFrame.new(x * 1.6, 9.6, -2.6) * CFrame.Angles(rad(-30), 0, x * 0.6), WHITE, NEON, 0, "Head")
	end
	for _, side in { -1, 1 } do
		local wing = if side < 0 then "WingL" else "WingR"
		local root = Vector3.new(side * 0.9, 7.8, 0)
		joint(wing, CFrame.new(root))
		local upper = CFrame.new(root) * CFrame.Angles(0, 0, -side * rad(55)) * CFrame.new(0, 3.6, -0.8)
		add("UpperWing", Vector3.new(0.14, 7.2, 5), upper, c, GLASS, 0.35, wing)
		add("UpperVein", Vector3.new(0.18, 6.4, 0.2), upper, WHITE, NEON, 0, wing)
		add("UpperEye", Vector3.new(0.2, 1.8, 1.8), upper * CFrame.new(0, 1.2, 0.6) * CFrame.Angles(rad(45), 0, 0), a, NEON, 0, wing)
		local lower = CFrame.new(root) * CFrame.Angles(0, 0, -side * rad(110)) * CFrame.new(0, 2.6, 1.2)
		add("LowerWing", Vector3.new(0.14, 5.2, 3.6), lower, a, GLASS, 0.35, wing)
		add("LowerVein", Vector3.new(0.18, 4.6, 0.2), lower, WHITE, NEON, 0, wing)
	end
	for _, x in { -0.8, 0.8 } do
		for _, z in { -0.6, 0.6 } do
			add("Leg", Vector3.new(0.15, 4.6, 0.15), CFrame.new(x, 4.6, z) * CFrame.Angles(0, 0, x * 0.25), c, NEON)
		end
	end
end

function Builders.SolarLion(add, joint, c, a)
	add("Body", Vector3.new(3.4, 3.2, 6.6), CFrame.new(0, 5, 0), c, GLASS, 0.15)
	add("BodyCore", Vector3.new(1.8, 1.8, 4.4), CFrame.new(0, 5, 0), WHITE, NEON, 0.4)
	for _, x in { -1.2, 1.2 } do
		for _, z in { -2.4, 2.4 } do
			add("Leg", Vector3.new(1.2, 3.6, 1.2), CFrame.new(x, 1.8, z), c, GLASS, 0.15)
			add("Paw", Vector3.new(1.5, 0.7, 1.7), CFrame.new(x, 0.35, z - 0.2), a, NEON)
		end
	end
	joint("Head", CFrame.new(0, 6.6, -3.4))
	add("Head", Vector3.new(2.4, 2.4, 2.6), CFrame.new(0, 7, -4.6), c, GLASS, 0.1, "Head")
	add("Muzzle", Vector3.new(1.4, 1, 1.2), CFrame.new(0, 6.4, -6), a, NEON, 0.2, "Head")
	for _, x in { -0.55, 0.55 } do
		add("Eye", Vector3.new(0.4, 0.25, 0.2), CFrame.new(x, 7.4, -5.95), WHITE, NEON, 0, "Head")
	end
	-- The mane: a crown of sunlit shards radiating around the head.
	for i = 1, 16 do
		local angle = i / 16 * math.pi * 2
		local length = if i % 2 == 0 then 3.2 else 2.4
		add("Mane", Vector3.new(0.5, length, 0.5), CFrame.new(0, 7, -4.2) * CFrame.Angles(0, 0, angle) * CFrame.new(0, 1.6 + length / 2, 0) * CFrame.Angles(0, rad(45), 0), if i % 2 == 0 then a else WHITE, NEON, 0, "Head")
	end
	joint("Tail", CFrame.new(0, 5.8, 3.3))
	add("Tail", Vector3.new(0.6, 0.6, 4.4), CFrame.new(0, 6.6, 5.4) * CFrame.Angles(rad(30), 0, 0), c, GLASS, 0.1, "Tail")
	add("Tuft", Vector3.one * 1.2, CFrame.new(0, 7.8, 7.4) * CFrame.Angles(rad(45), 0, rad(45)), a, NEON, 0, "Tail")
end

function Builders.StarKoi(add, joint, c, a)
	-- Swims upright in the air beside its rider.
	for i, size in { 3.4, 3.8, 3.2, 2.4 } do
		add("Body", Vector3.new(size * 0.8, size, size), CFrame.new(0, 7, -2 + i * 1.6), if i % 2 == 0 then a else c, GLASS, 0.15, nil, BALL)
		add("Scales", Vector3.new(size * 0.5, size * 0.5, size * 0.5), CFrame.new(0, 7.4, -2 + i * 1.6), WHITE, NEON, 0.5, nil, BALL)
	end
	joint("Head", CFrame.new(0, 7, -2))
	add("Head", Vector3.new(2.6, 2.8, 2.6), CFrame.new(0, 7, -3.4), c, GLASS, 0.1, "Head", BALL)
	for _, x in { -0.9, 0.9 } do
		add("Eye", Vector3.one * 0.6, CFrame.new(x, 7.5, -4.4), WHITE, NEON, 0, "Head", BALL)
		add("Whisker", Vector3.new(0.12, 0.12, 4), CFrame.new(x * 1.2, 6.4, -6) * CFrame.Angles(rad(15), x * 0.35, 0), a, NEON, 0, "Head")
	end
	add("Dorsal", Vector3.new(0.2, 3, 4), CFrame.new(0, 9.4, 0.6) * CFrame.Angles(rad(-15), 0, 0), a, GLASS, 0.3)
	for _, side in { -1, 1 } do
		local fin = if side < 0 then "FinL" else "FinR"
		joint(fin, CFrame.new(side * 1.4, 6.2, -1))
		add("Fin", Vector3.new(0.15, 2.8, 2.4), CFrame.new(side * 2.4, 5.6, -0.6) * CFrame.Angles(0, 0, side * rad(50)), a, GLASS, 0.3, fin)
	end
	joint("Tail", CFrame.new(0, 7, 4.8))
	for _, tilt in { -35, 35 } do
		local spread = CFrame.new(0, 7, 5.2) * CFrame.Angles(rad(tilt), 0, 0) * CFrame.new(0, 0, 2.2)
		add("TailFin", Vector3.new(0.15, 2.6, 4.4), spread, c, GLASS, 0.3, "Tail")
		add("TailVein", Vector3.new(0.2, 0.2, 4), spread, WHITE, NEON, 0, "Tail")
	end
end

--------------------------------------------------------------------------------
-- Building and transforming
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

local function weld(part0: BasePart, part1: BasePart, c0: CFrame, name: string?)
	part1.CFrame = part0.CFrame * c0
	local w = Instance.new("Weld")
	w.Name = name or "Weld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
end

-- Builds a beast around `root` (nil root: built in place for offline checks).
function BeastService.Build(kind: string, color: Color3, accent: Color3, scale: number, root: BasePart?, groundOffset: number?): Model?
	local builder = Builders[kind]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Beast"
	model:SetAttribute("Kind", kind)

	local core = newPart(model, "Core", Vector3.new(0.2, 0.2, 0.2), WHITE, Enum.Material.SmoothPlastic, 1)
	model.PrimaryPart = core
	if root then
		weld(root, core, CFrame.new(0, -(groundOffset or 3), 0), "Mount")
	else
		core.CFrame = CFrame.new()
	end

	local joints: { [string]: BasePart } = {}
	local pivots: { [string]: CFrame } = {}
	local function joint(name: string, pivot: CFrame)
		local j = newPart(model, name .. "Joint", Vector3.new(0.2, 0.2, 0.2), WHITE, Enum.Material.SmoothPlastic, 1)
		local scaled = pivot - pivot.Position + pivot.Position * scale
		weld(core, j, scaled, name)
		joints[name] = j
		pivots[name] = scaled
	end
	local function add(name: string, size: Vector3, cf: CFrame, c: Color3, material: Enum.Material?, transparency: number?, group: string?, shape: Enum.PartType?): Part
		local p = newPart(model, name, size * scale, c, material or GLASS, transparency or 0, shape)
		local scaled = cf - cf.Position + cf.Position * scale
		local parent = group and joints[group]
		if parent and group then
			-- Relative to the joint so animating the joint moves the group.
			weld(parent, p, pivots[group]:Inverse() * scaled)
		else
			weld(core, p, scaled)
		end
		return p
	end
	builder(add, joint, color, accent)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 2.5
	light.Shadows = false
	light.Parent = core

	CollectionService:AddTag(model, "BeastForm")
	return model
end

local hidden: { [Model]: { [Instance]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function hideBody(character: Model)
	local saved = {}
	for _, d in character:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.Name ~= "HumanoidRootPart" then
			local item: any = d
			saved[d] = item.Transparency
			item.Transparency = 1
		end
	end
	hidden[character] = saved
end

local function showBody(character: Model)
	local saved = hidden[character]
	if not saved then
		return
	end
	for d, transparency in saved do
		if d.Parent then
			local item: any = d
			item.Transparency = transparency
		end
	end
	hidden[character] = nil
end

function BeastService.IsBeast(character: Model): boolean
	return character:GetAttribute(STATUS.Beast) ~= nil
end

-- Ends a transformation (time up, death or respawn).
function BeastService.Revert(character: Model)
	if not BeastService.IsBeast(character) then
		return
	end
	local beast = character:FindFirstChild("Beast")
	if beast then
		beast:Destroy()
	end
	character:SetAttribute(STATUS.Beast, nil)
	character:SetAttribute(STATUS.BeastUntil, 0)
	showBody(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		CombatService.FX("TransformEnd", { Caster = character, Position = root.Position })
	end
end

-- ctx = { Player, Character, Root, Skill, Kit }
function BeastService.Transform(ctx)
	local character: Model = ctx.Character
	if BeastService.IsBeast(character) then
		return
	end
	local skill = ctx.Skill
	local color, accent = CombatService.ColorsOf(ctx.Player)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ground = humanoid.HipHeight + ctx.Root.Size.Y / 2
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		ground = 3
	end

	CombatService.FX("Transform", { Caster = character, Beast = skill.Beast, Name = skill.BeastName, Position = ctx.Root.Position, Color = color, Accent = accent, Element = ctx.Kit.Element })
	CombatService.Extend(character, STATUS.InvulnerableUntil, 0.8)
	CombatService.Extend(character, STATUS.BusyUntil, 0.8)
	task.wait(0.45)
	if humanoid.Health <= 0 or character.Parent == nil then
		return
	end

	local model = BeastService.Build(skill.Beast, color, accent, 1.6 * (skill.Scale or 1), ctx.Root, ground)
	if not model then
		return
	end
	hideBody(character)
	model.Parent = character
	character:SetAttribute(STATUS.Beast, skill.Beast)
	character:SetAttribute(STATUS.BeastUntil, CombatService.Now() + skill.Duration)
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 25)

	task.delay(skill.Duration, function()
		if character.Parent and character:GetAttribute(STATUS.Beast) == skill.Beast then
			BeastService.Revert(character)
		end
	end)
end

return BeastService
