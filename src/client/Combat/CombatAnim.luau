-- CombatAnim
-- Full-body combat animation for R15 fighters, built procedurally from
-- keyframed poses (no animation assets): wind-up, strike and follow-through
-- for every melee style and combo hit, and a cast motion for every skill.
-- Poses layer on top of the walk / idle animation by offsetting each joint's
-- Motor6D.C0 (the Animator only drives Motor6D.Transform), and blend in and
-- out smoothly. Holding block raises a guard pose.
--
-- Played on every client from the combat effects, so everyone sees the same
-- motion; your own swings start instantly (predicted).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))

local STATUS = CombatConfig.Status

local CombatAnim = {}

-- joint -> { part, motor }
local JOINTS = {
	Root = { "LowerTorso", "Root" },
	Waist = { "UpperTorso", "Waist" },
	Neck = { "Head", "Neck" },
	RShoulder = { "RightUpperArm", "RightShoulder" },
	LShoulder = { "LeftUpperArm", "LeftShoulder" },
	RElbow = { "RightLowerArm", "RightElbow" },
	LElbow = { "LeftLowerArm", "LeftElbow" },
	RWrist = { "RightHand", "RightWrist" },
	LWrist = { "LeftHand", "LeftWrist" },
	RHip = { "RightUpperLeg", "RightHip" },
	LHip = { "LeftUpperLeg", "LeftHip" },
	RKnee = { "RightLowerLeg", "RightKnee" },
	LKnee = { "LeftLowerLeg", "LeftKnee" },
	-- The weapon's grip on the hand (WeaponBuilder's "Grip" weld): lets an
	-- animation re-angle the weapon, e.g. levelling a spear to thrust.
	Grip = { "Weapon", "Handle", "Grip" },
}

-- A pose: joint -> { pitch, yaw, roll } in degrees.
--   Shoulders/hips: +pitch swings the limb forward and up; +yaw swings a
--   raised arm toward the left; +roll lifts the right arm out to the side
--   (use -roll for the left arm). Elbows/knees: -pitch bends.
--   Root: -pitch leans the whole body forward. Waist: +yaw twists left.
type Pose = { [string]: { number } }
type Key = { T: number, Pose: Pose }
type Anim = { Duration: number, Keys: { Key } }

local function mirror(pose: Pose): Pose
	local out = {}
	for joint, v in pose do
		local swapped = joint:gsub("^R(%u)", "_L%1"):gsub("^L(%u)", "R%1"):gsub("^_L", "L")
		local yaw = v[2] or 0
		local roll = v[3] or 0
		if joint == "Root" or joint == "Waist" or joint == "Neck" then
			out[joint] = { v[1], -yaw, -roll }
		else
			out[swapped] = { v[1], -yaw, -roll }
		end
	end
	return out
end

-- wind-up -> strike -> settle, with the strike landing at `hit` (0..1).
local function swing(duration: number, wind: Pose, strike: Pose, hit: number?): Anim
	local h = hit or 0.42
	return {
		Duration = duration,
		Keys = {
			{ T = 0, Pose = {} },
			{ T = h * 0.6, Pose = wind },
			{ T = h, Pose = strike },
			{ T = math.min(0.85, h + 0.3), Pose = strike },
			{ T = 1, Pose = {} },
		},
	}
end

local A: { [string]: Anim } = {}

--------------------------------------------------------------------------------
-- Melee
--------------------------------------------------------------------------------

-- Crystal Blade: forehand, backhand, rising diagonal, leaping overhead.
A.Blade1 = swing(0.4, {
	RShoulder = { 75, 70, 15 }, RElbow = { -40 }, Waist = { 0, 40 }, Root = { -4 }, LShoulder = { 25, 0, -20 },
}, {
	RShoulder = { 80, -75 }, RElbow = { -5 }, Waist = { 0, -45 }, Root = { -10 }, LShoulder = { 30, 0, -35 }, RHip = { 18 }, LHip = { -12 }, LKnee = { -10 },
})
A.Blade2 = swing(0.4, {
	RShoulder = { 70, -80 }, RElbow = { -50 }, Waist = { 0, -40 }, Root = { -4 },
}, {
	RShoulder = { 80, 60, 10 }, RElbow = { -5 }, Waist = { 0, 45 }, Root = { -10 }, LShoulder = { 20, 0, -40 }, LHip = { 18 }, RHip = { -12 },
})
A.Blade3 = swing(0.42, {
	RShoulder = { 165, -25 }, RElbow = { -30 }, Waist = { -6, 25 }, Root = { 4 },
}, {
	RShoulder = { 30, 50 }, RElbow = { -10 }, Waist = { 10, -35 }, Root = { -14 }, RHip = { 25 }, RKnee = { -20 }, LHip = { -15 },
})
A.Blade4 = swing(0.55, {
	RShoulder = { 175, 0 }, LShoulder = { 175, 0 }, RElbow = { -40 }, LElbow = { -40 }, Root = { 10 }, Waist = { -12 }, RHip = { 30 }, RKnee = { -50 },
}, {
	RShoulder = { 25, 10 }, LShoulder = { 25, -10 }, Root = { -24 }, Waist = { 12 }, RHip = { 40 }, RKnee = { -45 }, LHip = { -25 }, LKnee = { -20 },
}, 0.5)

-- Prism Greatsword: two-handed, wide and heavy.
A.Greatsword1 = swing(0.55, {
	RShoulder = { 80, 85, 10 }, LShoulder = { 80, 60, 20 }, RElbow = { -50 }, LElbow = { -50 }, Waist = { 0, 60 }, Root = { -6 }, RHip = { -10 },
}, {
	RShoulder = { 85, -85 }, LShoulder = { 85, -60 }, Waist = { 0, -65 }, Root = { -14 }, RHip = { 25 }, LHip = { -15 }, LKnee = { -15 },
}, 0.48)
A.Greatsword2 = swing(0.55, {
	RShoulder = { 80, -85 }, LShoulder = { 80, -60 }, Waist = { 0, -60 }, Root = { -6 },
}, {
	RShoulder = { 85, 85 }, LShoulder = { 85, 60 }, Waist = { 0, 65 }, Root = { -14 }, LHip = { 25 }, RHip = { -15 },
}, 0.48)
A.Greatsword3 = A.Blade4

-- Twin Facets: quick alternating slashes and a cross cut.
A.Daggers1 = swing(0.24, { RShoulder = { 60, 60 }, RElbow = { -70 }, Waist = { 0, 25 } }, { RShoulder = { 85, -55 }, RElbow = { -5 }, Waist = { 0, -25 }, Root = { -8 } })
A.Daggers2 = swing(0.24, mirror({ RShoulder = { 60, 60 }, RElbow = { -70 }, Waist = { 0, 25 } }), mirror({ RShoulder = { 85, -55 }, RElbow = { -5 }, Waist = { 0, -25 }, Root = { -8 } }))
A.Daggers3 = swing(0.26, { RShoulder = { 150, -10 }, RElbow = { -40 }, Waist = { -8, 15 } }, { RShoulder = { 40, 40 }, Waist = { 8, -20 }, Root = { -10 }, RHip = { 15 } })
A.Daggers4 = swing(0.26, mirror({ RShoulder = { 150, -10 }, RElbow = { -40 }, Waist = { -8, 15 } }), mirror({ RShoulder = { 40, 40 }, Waist = { 8, -20 }, Root = { -10 }, RHip = { 15 } }))
A.Daggers5 = swing(0.4, {
	RShoulder = { 120, -50 }, LShoulder = { 120, 50 }, RElbow = { -30 }, LElbow = { -30 }, Root = { 6 },
}, {
	RShoulder = { 70, 70 }, LShoulder = { 70, -70 }, Root = { -16 }, RHip = { 25 }, RKnee = { -25 },
})

-- Geode Fists: jab, cross, hook, uppercut.
A.Gauntlets1 = swing(0.28, { RShoulder = { 50, 10 }, RElbow = { -110 }, Waist = { 0, 25 } }, { RShoulder = { 95, 5 }, RElbow = { -5 }, Waist = { 0, -25 }, Root = { -10 }, RHip = { 15 } })
A.Gauntlets2 = swing(0.28, mirror({ RShoulder = { 50, 10 }, RElbow = { -110 }, Waist = { 0, 25 } }), mirror({ RShoulder = { 95, 5 }, RElbow = { -5 }, Waist = { 0, -25 }, Root = { -10 }, RHip = { 15 } }))
A.Gauntlets3 = swing(0.32, { RShoulder = { 70, -20, 50 }, RElbow = { -90 }, Waist = { 0, 40 } }, { RShoulder = { 85, 60, 20 }, RElbow = { -80 }, Waist = { 0, -45 }, Root = { -8 } })
A.Gauntlets4 = swing(0.45, {
	RShoulder = { 10, 0, 10 }, RElbow = { -100 }, Root = { -10 }, RHip = { 30 }, RKnee = { -50 }, LHip = { 20 }, LKnee = { -45 },
}, {
	RShoulder = { 175, 0 }, RElbow = { -10 }, Root = { 10 }, Waist = { -10 }, LShoulder = { 20, 0, -30 },
}, 0.45)

-- Spire Lance: thrusts.
local thrustWind: Pose = { RShoulder = { 80, 10 }, RElbow = { -95 }, LShoulder = { 60, -20 }, LElbow = { -60 }, Waist = { 0, 35 }, Root = { 2 }, Grip = { -40 } }
local thrustHit: Pose = { RShoulder = { 92, -5 }, RElbow = { 0 }, LShoulder = { 85, -25 }, LElbow = { -20 }, Waist = { 0, -20 }, Root = { -16 }, RHip = { 28 }, RKnee = { -20 }, LHip = { -18 }, Grip = { -130 } }
A.Spear1 = swing(0.38, thrustWind, thrustHit)
A.Spear2 = swing(0.38, thrustWind, thrustHit)
A.Spear3 = swing(0.42, { RShoulder = { 30, 70 }, LShoulder = { 30, 40 }, Waist = { 0, 60 }, Grip = { -110 } }, { RShoulder = { 70, -70 }, LShoulder = { 70, -40 }, Waist = { 0, -60 }, Root = { -10 }, Grip = { -120 } })
A.Spear4 = swing(0.5, { RShoulder = { 160, 0 }, RElbow = { -60 }, Root = { 10 }, RHip = { 35 }, RKnee = { -60 }, Grip = { -60 } }, thrustHit, 0.5)

-- Moon Scythe: great sweeping turns.
A.Scythe1 = swing(0.5, {
	RShoulder = { 70, 90, 20 }, LShoulder = { 70, 70 }, Waist = { 0, 80 }, Root = { -6 }, RHip = { -15 },
}, {
	RShoulder = { 75, -90 }, LShoulder = { 75, -60 }, Waist = { 0, -85 }, Root = { -14 }, RHip = { 25 }, LKnee = { -15 },
}, 0.45)
A.Scythe2 = swing(0.5, mirror(A.Scythe1.Keys[2].Pose), mirror(A.Scythe1.Keys[3].Pose), 0.45)
A.Scythe3 = swing(0.6, {
	RShoulder = { 175, 10 }, LShoulder = { 170, -10 }, Root = { 12 }, Waist = { -15, 30 },
}, {
	RShoulder = { 20, -40 }, LShoulder = { 30, -20 }, Root = { -26 }, Waist = { 15, -40 }, RHip = { 40 }, RKnee = { -45 },
}, 0.5)

-- Monolith Hammer: slow, crushing.
A.Hammer1 = swing(0.6, {
	RShoulder = { 110, 70 }, LShoulder = { 100, 60 }, RElbow = { -40 }, LElbow = { -40 }, Waist = { 0, 50 }, Root = { 4 },
}, {
	RShoulder = { 60, -70 }, LShoulder = { 60, -50 }, Waist = { 0, -55 }, Root = { -14 }, RHip = { 25 },
}, 0.5)
A.Hammer2 = swing(0.6, mirror(A.Hammer1.Keys[2].Pose), mirror(A.Hammer1.Keys[3].Pose), 0.5)
A.Hammer3 = swing(0.75, {
	RShoulder = { 178, 0 }, LShoulder = { 178, 0 }, RElbow = { -60 }, LElbow = { -60 }, Root = { 14 }, Waist = { -15 }, RHip = { 25 }, RKnee = { -40 },
}, {
	RShoulder = { 10, 5 }, LShoulder = { 10, -5 }, Root = { -32 }, Waist = { 18 }, RHip = { 55 }, RKnee = { -65 }, LHip = { -20 }, LKnee = { -35 },
}, 0.55)

-- Ribbon Whip: overhead cracks.
A.Whip1 = swing(0.4, { RShoulder = { 160, -30 }, RElbow = { -70 }, Waist = { 0, 20 }, Root = { 6 } }, { RShoulder = { 60, 30 }, RElbow = { 0 }, Waist = { 0, -25 }, Root = { -10 } })
A.Whip2 = swing(0.4, { RShoulder = { 80, 80 }, RElbow = { -60 }, Waist = { 0, 40 } }, { RShoulder = { 80, -60 }, Waist = { 0, -40 }, Root = { -8 } })
A.Whip3 = swing(0.4, { RShoulder = { 70, -70, 40 }, Waist = { 0, -40 } }, { RShoulder = { 85, 60 }, Waist = { 0, 40 }, Root = { -8 } })
A.Whip4 = swing(0.55, { RShoulder = { 175, 0 }, RElbow = { -40 }, Root = { 10 } }, { RShoulder = { 10, 0 }, Root = { -25 }, RHip = { 30 }, RKnee = { -30 } }, 0.5)

-- Gale Fans: mirrored, dance-like sweeps.
A.Fans1 = swing(0.38, { RShoulder = { 70, 70 }, LShoulder = { 70, -20, -60 }, Waist = { 0, 30 } }, { RShoulder = { 70, -60 }, LShoulder = { 70, 20 }, Waist = { 0, -35 }, Root = { -8 } })
A.Fans2 = swing(0.38, mirror(A.Fans1.Keys[2].Pose), mirror(A.Fans1.Keys[3].Pose))
A.Fans3 = swing(0.4, { RShoulder = { 30, 0, 60 }, LShoulder = { 30, 0, -60 }, Root = { -6 } }, { RShoulder = { 170, 0, 20 }, LShoulder = { 170, 0, -20 }, Root = { 8 }, Waist = { -10 } })
A.Fans4 = swing(0.5, { RShoulder = { 90, 0, 80 }, LShoulder = { 90, 0, -80 }, Waist = { 0, 60 } }, { RShoulder = { 90, 0, 80 }, LShoulder = { 90, 0, -80 }, Waist = { 0, -70 }, Root = { -10 } })

--------------------------------------------------------------------------------
-- Skills
--------------------------------------------------------------------------------

-- Throw the palm forward (projectiles).
A.Cast = swing(0.4, { RShoulder = { 60, 40 }, RElbow = { -90 }, Waist = { 0, 30 }, LShoulder = { 40, -10 } }, { RShoulder = { 95, -5 }, RElbow = { 0 }, Waist = { 0, -25 }, Root = { -10 }, LShoulder = { 20, 0, -30 }, RHip = { 15 } })
-- Both hands push forward (lines, chains, vortexes).
A.Push = swing(0.45, {
	RShoulder = { 50, 20 }, LShoulder = { 50, -20 }, RElbow = { -100 }, LElbow = { -100 }, Root = { 6 }, Waist = { 0, 15 },
}, {
	RShoulder = { 92, -15 }, LShoulder = { 92, 15 }, RElbow = { 0 }, LElbow = { 0 }, Root = { -14 }, RHip = { 25 }, RKnee = { -20 }, LHip = { -15 },
})
-- Raise a hand to the sky (rain, meteors, blooms).
A.SkyCall = swing(0.6, { RShoulder = { 60, 0 }, RElbow = { -80 }, Root = { -4 }, Neck = { -10 } }, { RShoulder = { 175, 0 }, RElbow = { 0 }, LShoulder = { 30, 0, -40 }, Root = { 8 }, Neck = { 25 } }, 0.45)
-- Slam a palm onto the ground (fields, prisons, hexes, spires).
A.Ground = swing(0.55, {
	RShoulder = { 160, 0 }, RElbow = { -40 }, Root = { 4 }, RHip = { 20 }, RKnee = { -30 },
}, {
	RShoulder = { 60, 0 }, RElbow = { 0 }, Root = { -32 }, Waist = { -10 }, RHip = { 70 }, RKnee = { -100 }, LHip = { -10 }, LKnee = { -70 }, Neck = { -15 },
}, 0.5)
A.Launcher = swing(0.45, {
	RShoulder = { 10, 20 }, RElbow = { -20 }, Root = { -18 }, RHip = { 40 }, RKnee = { -60 }, LKnee = { -40 },
}, {
	RShoulder = { 175, -10 }, RElbow = { 0 }, Root = { 10 }, Waist = { -10 }, LShoulder = { 20, 0, -40 },
})
A.Rush = { Duration = 0.5, Keys = {
	{ T = 0, Pose = {} },
	{ T = 0.15, Pose = { Root = { -38 }, RShoulder = { -50, 0, 20 }, LShoulder = { -50, 0, -20 }, RHip = { 45 }, LHip = { -35 }, RKnee = { -30 }, Neck = { 25 } } },
	{ T = 0.7, Pose = { Root = { -38 }, RShoulder = { -50, 0, 20 }, LShoulder = { -50, 0, -20 }, RHip = { 45 }, LHip = { -35 }, RKnee = { -30 }, Neck = { 25 } } },
	{ T = 0.85, Pose = { RShoulder = { 80, -70 }, Waist = { 0, -40 }, Root = { -12 } } },
	{ T = 1, Pose = {} },
} }
A.Spin = { Duration = 1.2, Keys = {
	{ T = 0, Pose = {} },
	{ T = 0.1, Pose = { RShoulder = { 90, 0, 75 }, LShoulder = { 90, 0, -75 }, Root = { -6 }, Waist = { 0, 60 } } },
	{ T = 0.35, Pose = { RShoulder = { 90, 0, 75 }, LShoulder = { 90, 0, -75 }, Root = { -6 }, Waist = { 0, -60 } } },
	{ T = 0.6, Pose = { RShoulder = { 90, 0, 75 }, LShoulder = { 90, 0, -75 }, Root = { -6 }, Waist = { 0, 60 } } },
	{ T = 0.85, Pose = { RShoulder = { 90, 0, 75 }, LShoulder = { 90, 0, -75 }, Root = { -6 }, Waist = { 0, -60 } } },
	{ T = 1, Pose = {} },
} }
A.Flurry = { Duration = 0.7, Keys = {
	{ T = 0, Pose = {} },
	{ T = 0.12, Pose = { RShoulder = { 95, -20 }, LShoulder = { 50, 10 }, Waist = { 0, -25 }, Root = { -10 } } },
	{ T = 0.24, Pose = { LShoulder = { 95, 20 }, RShoulder = { 50, -10 }, Waist = { 0, 25 }, Root = { -10 } } },
	{ T = 0.36, Pose = { RShoulder = { 95, -20 }, LShoulder = { 50, 10 }, Waist = { 0, -25 }, Root = { -10 } } },
	{ T = 0.48, Pose = { LShoulder = { 95, 20 }, RShoulder = { 50, -10 }, Waist = { 0, 25 }, Root = { -10 } } },
	{ T = 0.6, Pose = { RShoulder = { 95, -20 }, LShoulder = { 50, 10 }, Waist = { 0, -25 }, Root = { -10 } } },
	{ T = 0.78, Pose = { RShoulder = { 100, -60 }, LShoulder = { 100, 60 }, Root = { -18 }, RHip = { 25 } } },
	{ T = 1, Pose = {} },
} }
A.SlamLeap = swing(0.65, {
	RShoulder = { 175, 0 }, LShoulder = { 175, 0 }, RHip = { 75 }, LHip = { 60 }, RKnee = { -110 }, LKnee = { -100 }, Root = { 10 },
}, {
	RShoulder = { 30, 0, 30 }, LShoulder = { 30, 0, -30 }, Root = { -30 }, RHip = { 60 }, RKnee = { -90 }, LHip = { -10 }, LKnee = { -60 },
}, 0.75)
A.NovaCharge = { Duration = 0.6, Keys = {
	{ T = 0, Pose = {} },
	{ T = 0.6, Pose = { RShoulder = { 80, 55 }, LShoulder = { 80, -55 }, RElbow = { -90 }, LElbow = { -90 }, Root = { -12 }, RHip = { 35 }, RKnee = { -60 }, LHip = { 30 }, LKnee = { -55 }, Neck = { -15 } } },
	{ T = 1, Pose = { RShoulder = { 80, 55 }, LShoulder = { 80, -55 }, RElbow = { -90 }, LElbow = { -90 }, Root = { -12 }, RHip = { 35 }, RKnee = { -60 }, LHip = { 30 }, LKnee = { -55 }, Neck = { -15 } } },
} }
A.NovaRelease = swing(0.6, {
	RShoulder = { 80, 55 }, LShoulder = { 80, -55 }, RElbow = { -90 }, LElbow = { -90 }, Root = { -12 }, RHip = { 35 }, RKnee = { -60 }, LHip = { 30 }, LKnee = { -55 },
}, {
	RShoulder = { 120, 0, 80 }, LShoulder = { 120, 0, -80 }, Root = { 12 }, Neck = { 25 }, Waist = { -10 },
}, 0.2)
A.Beam = { Duration = 1.3, Keys = {
	{ T = 0, Pose = {} },
	{ T = 0.1, Pose = { RShoulder = { 90, -10 }, LShoulder = { 90, 10 }, Root = { 6 }, RHip = { -15 }, LHip = { 25 }, LKnee = { -25 }, Waist = { 0, 10 } } },
	{ T = 0.9, Pose = { RShoulder = { 92, -10 }, LShoulder = { 92, 10 }, Root = { 8 }, RHip = { -15 }, LHip = { 25 }, LKnee = { -25 }, Waist = { 0, 10 } } },
	{ T = 1, Pose = {} },
} }
A.Grab = swing(0.6, { RShoulder = { 95, 0 }, RElbow = { 0 }, Root = { -12 }, RHip = { 20 } }, { RShoulder = { 40, 30 }, RElbow = { -120 }, Root = { 10 }, Waist = { 0, 30 }, LHip = { 20 } }, 0.55)
A.Blink = swing(0.35, { Root = { -25 }, RHip = { 40 }, RKnee = { -70 }, LHip = { 30 }, LKnee = { -60 }, RShoulder = { -30 }, LShoulder = { -30 } }, { Root = { -10 }, RShoulder = { 80, -60 }, Waist = { 0, -30 } }, 0.5)
A.Guard = swing(0.6, { RShoulder = { 80, 60 }, LShoulder = { 80, -60 }, RElbow = { -100 }, LElbow = { -100 } }, { RShoulder = { 120, 0, 70 }, LShoulder = { 120, 0, -70 }, Neck = { 15 } }, 0.5)
A.Domain = { Duration = 1.4, Keys = {
	{ T = 0, Pose = {} },
	-- A hand sign held before the chest...
	{ T = 0.25, Pose = { RShoulder = { 70, 45 }, LShoulder = { 70, -45 }, RElbow = { -95 }, LElbow = { -95 }, Neck = { -10 } } },
	{ T = 0.6, Pose = { RShoulder = { 72, 45 }, LShoulder = { 72, -45 }, RElbow = { -95 }, LElbow = { -95 }, Neck = { -12 } } },
	-- ...then thrown wide as the dimension opens.
	{ T = 0.75, Pose = { RShoulder = { 110, 0, 85 }, LShoulder = { 110, 0, -85 }, Root = { 10 }, Neck = { 25 } } },
	{ T = 1, Pose = {} },
} }
A.Transform = { Duration = 1.1, Keys = {
	{ T = 0, Pose = {} },
	{ T = 0.35, Pose = { RShoulder = { 60, 50 }, LShoulder = { 60, -50 }, RElbow = { -110 }, LElbow = { -110 }, Root = { -20 }, RHip = { 40 }, RKnee = { -70 }, LHip = { 35 }, LKnee = { -65 }, Neck = { -20 } } },
	{ T = 0.6, Pose = { RShoulder = { 130, 0, 90 }, LShoulder = { 130, 0, -90 }, Root = { 12 }, Neck = { 30 } } },
	{ T = 1, Pose = {} },
} }

-- Raised guard while blocking.
local BLOCK_POSE: Pose = { RShoulder = { 85, 55 }, LShoulder = { 85, -55 }, RElbow = { -100 }, LElbow = { -100 }, Root = { -6 }, RHip = { 15 }, RKnee = { -20 }, LKnee = { -15 }, Neck = { -8 } }

--------------------------------------------------------------------------------
-- Playback
--------------------------------------------------------------------------------

type State = { Anim: Anim?, Start: number, Weight: { [string]: Vector3 }, Block: number }

local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any
local baseC0: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

local function sample(anim: Anim, t: number): { [string]: Vector3 }
	local keys = anim.Keys
	local a = math.clamp(t / anim.Duration, 0, 1)
	local k1, k2 = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if a >= keys[i].T and a <= keys[i + 1].T then
			k1, k2 = keys[i], keys[i + 1]
			break
		end
	end
	local span = math.max(1e-3, k2.T - k1.T)
	local u = ease(math.clamp((a - k1.T) / span, 0, 1))
	local out: { [string]: Vector3 } = {}
	for joint in JOINTS do
		local p1 = k1.Pose[joint]
		local p2 = k2.Pose[joint]
		if p1 or p2 then
			local v1 = if p1 then Vector3.new(p1[1] or 0, p1[2] or 0, p1[3] or 0) else Vector3.zero
			local v2 = if p2 then Vector3.new(p2[1] or 0, p2[2] or 0, p2[3] or 0) else Vector3.zero
			out[joint] = v1:Lerp(v2, u)
		end
	end
	return out
end

-- Plays animation `name` on a character (any client's character).
function CombatAnim.Play(character: Instance?, name: string)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return
	end
	local anim = A[name]
	if not anim then
		return
	end
	local state = states[character]
	if not state then
		state = { Anim = nil, Start = 0, Weight = {}, Block = 0 }
		states[character] = state
	end
	state.Anim = anim
	state.Start = os.clock()
end

function CombatAnim.Has(name: string): boolean
	return A[name] ~= nil
end

local function motorOf(character: Model, joint: string): any
	local spec = JOINTS[joint]
	if spec[3] then
		local weapon = character:FindFirstChild(spec[1])
		local handle = weapon and weapon:FindFirstChild(spec[2])
		local grip = handle and handle:FindFirstChild(spec[3])
		return if grip and grip:IsA("Weld") then grip else nil
	end
	local p = character:FindFirstChild(spec[1])
	local m = p and p:FindFirstChild(spec[2])
	return if m and m:IsA("Motor6D") then m else nil
end

local function apply(character: Model, state: State, dt: number)
	local target: { [string]: Vector3 } = {}
	if state.Anim then
		local t = os.clock() - state.Start
		if t >= state.Anim.Duration then
			state.Anim = nil
		else
			target = sample(state.Anim, t)
		end
	end
	-- Guard layer
	local blocking = character:GetAttribute(STATUS.Blocking) == true
	state.Block += ((if blocking then 1 else 0) - state.Block) * math.min(1, dt * 12)
	if state.Block > 0.01 then
		for joint, v in BLOCK_POSE do
			local current = target[joint] or Vector3.zero
			target[joint] = current:Lerp(Vector3.new(v[1] or 0, v[2] or 0, v[3] or 0), state.Block)
		end
	end
	-- Ease every joint toward its target (smooth in and out).
	local blend = math.min(1, dt * 22)
	for joint in JOINTS do
		local goal = target[joint] or Vector3.zero
		local current = state.Weight[joint] or Vector3.zero
		local nextValue = current:Lerp(goal, blend)
		if nextValue.Magnitude < 0.05 and goal.Magnitude == 0 then
			nextValue = Vector3.zero
		end
		state.Weight[joint] = nextValue
		local motor = motorOf(character, joint)
		if motor then
			local base = baseC0[motor]
			if not base then
				base = motor.C0
				baseC0[motor] = base
			end
			if nextValue == Vector3.zero then
				if motor.C0 ~= base then
					motor.C0 = base
				end
			else
				motor.C0 = base * CFrame.fromEulerAnglesYXZ(math.rad(nextValue.X), math.rad(nextValue.Y), math.rad(nextValue.Z))
			end
		end
	end
end

function CombatAnim.Start()
	RunService.RenderStepped:Connect(function(dt)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				local state = states[character]
				if not state and character:GetAttribute(STATUS.Blocking) == true then
					state = { Anim = nil, Start = 0, Weight = {}, Block = 0 }
					states[character] = state
				end
				if state then
					apply(character, state, dt)
				end
			end
		end
	end)
end

return CombatAnim
