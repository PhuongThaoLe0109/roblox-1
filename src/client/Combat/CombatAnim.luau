-- CombatAnim
-- Full-body procedural animation for every fighter, built from keyframed
-- poses (no animation assets), in three layers:
--   * movement: riding the broom, the airborne rise / fall and a landing
--     squash, worked out from each character's state on every client;
--   * actions: wind-up, strike and follow-through for every melee style and
--     combo hit, a motion for every skill, charges that hold until released,
--     the dash lunge and the double-jump flip; a stun cuts them short;
--   * the guard pose while blocking.
-- Poses layer on top of the walk / idle animation by offsetting each joint's
-- Motor6D.C0 (the Animator only drives Motor6D.Transform), and blend in and
-- out smoothly. R15 rigs get every joint; R6 rigs get the same poses folded
-- onto their six joints.
--
-- Played on every client from the combat / movement effects, so everyone sees
-- the same motion; your own actions start instantly (predicted).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local MovementConfig = require(ReplicatedStorage:WaitForChild("MovementConfig"))

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
type Anim = { Duration: number, Keys: { Key }, HoldAt: number?, Spin: { Turns: number, From: number, To: number }? }

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
A.NovaCharge = { Duration = 0.6, HoldAt = 0.6, Keys = {
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
-- Movement
--------------------------------------------------------------------------------

-- Dash (Q): throw the body forward with the arms swept back, hold the lunge
-- through the burst, then brake on a planted front foot.
local DASH_LUNGE: Pose = {
	Root = { -40 }, Waist = { -8 }, Neck = { 24 },
	RShoulder = { -65, 0, 28 }, LShoulder = { -65, 0, -28 }, RElbow = { -20 }, LElbow = { -20 },
	RHip = { 55 }, RKnee = { -45 }, LHip = { -45 }, LKnee = { -30 },
}
A.Dash = { Duration = 0.55, Keys = {
	{ T = 0, Pose = {} },
	{ T = 0.1, Pose = DASH_LUNGE },
	{ T = 0.42, Pose = DASH_LUNGE },
	{ T = 0.62, Pose = {
		Root = { 16 }, Waist = { 6 }, Neck = { -8 }, Drop = { 0.35 },
		RShoulder = { 45, 0, 35 }, LShoulder = { 25, 0, -40 }, RElbow = { -30 }, LElbow = { -40 },
		RHip = { 60 }, RKnee = { -25 }, LHip = { -18 }, LKnee = { -55 },
	} },
	{ T = 1, Pose = {} },
} }

-- Double jump: tuck into a forward flip (the spin is added on top, see Spin).
local TUCK: Pose = {
	RHip = { 105 }, LHip = { 105 }, RKnee = { -125 }, LKnee = { -125 },
	RShoulder = { 70, 0, 20 }, LShoulder = { 70, 0, -20 }, RElbow = { -70 }, LElbow = { -70 },
	Neck = { -20 }, Waist = { -12 },
}
A.Flip = { Duration = 0.55, Spin = { Turns = 1, From = 0.05, To = 0.85 }, Keys = {
	{ T = 0, Pose = {} },
	{ T = 0.15, Pose = TUCK },
	{ T = 0.7, Pose = TUCK },
	{ T = 1, Pose = { RShoulder = { 40, 0, 50 }, LShoulder = { 40, 0, -50 }, RHip = { 20 }, LHip = { 10 }, RKnee = { -30 }, LKnee = { -20 } } },
} }

-- Airborne layer (blended by vertical speed): a knees-up rise, a spread fall.
local RISE_POSE: Pose = {
	RHip = { 55 }, RKnee = { -80 }, LHip = { 20 }, LKnee = { -35 },
	RShoulder = { 35, 0, 25 }, LShoulder = { 25, 0, -30 }, RElbow = { -30 }, LElbow = { -30 }, Neck = { 6 },
}
local FALL_POSE: Pose = {
	RHip = { 18, 0, 10 }, LHip = { -10, 0, -12 }, RKnee = { -35 }, LKnee = { -15 },
	RShoulder = { 30, 0, 70 }, LShoulder = { 30, 0, -70 }, RElbow = { -25 }, LElbow = { -25 }, Neck = { -12 }, Root = { -6 },
}
-- Landing: a quick knee-bend that soaks up the fall.
local LAND_POSE: Pose = {
	Drop = { 0.9 }, Root = { -16 }, Waist = { -6 }, Neck = { 10 },
	RHip = { 55 }, RKnee = { -85 }, LHip = { 45 }, LKnee = { -75 },
	RShoulder = { 20, 0, 35 }, LShoulder = { 20, 0, -35 }, RElbow = { -30 }, LElbow = { -30 },
}

-- Riding the broom, the classic way: astride the shaft facing where it flies,
-- legs either side with the shins tucked back, both hands on the shaft ahead
-- and the body leaning into the flight.
local BROOM_POSE: Pose = {
	Root = { -20 }, Waist = { -6 }, Neck = { 22 },
	RHip = { 82, -14, 16 }, LHip = { 82, 14, -16 }, RKnee = { -100 }, LKnee = { -100 },
	RShoulder = { 58, 26 }, LShoulder = { 58, -26 }, RElbow = { -22 }, LElbow = { -22 },
}

--------------------------------------------------------------------------------
-- Playback
--------------------------------------------------------------------------------

-- R6 fallback: the six R6 joints (the waist, elbows and knees fold into them).
local R6_JOINTS = {
	Root = { "HumanoidRootPart", "RootJoint" },
	Neck = { "Torso", "Neck" },
	RShoulder = { "Torso", "Right Shoulder" },
	LShoulder = { "Torso", "Left Shoulder" },
	RHip = { "Torso", "Right Hip" },
	LHip = { "Torso", "Left Hip" },
	Grip = JOINTS.Grip,
}
-- joint -> { R6 joint, how much of its pitch to fold in }
local R6_FOLD = {
	Waist = { "Root", 1 },
	RElbow = { "RShoulder", -0.45 },
	LElbow = { "LShoulder", -0.45 },
	RKnee = { "RHip", 0.35 },
	LKnee = { "LHip", 0.35 },
}

-- Pose channels: every joint plus "Drop" (studs the body sinks, landings).
local CHANNELS: { string } = { "Drop" }
for joint in JOINTS do
	table.insert(CHANNELS, joint)
end

type State = {
	Anim: Anim?,
	Start: number,
	HoldUntil: number, -- the anim freezes at its HoldAt key until then
	Weight: { [string]: Vector3 },
	Block: number,
	Air: number, -- airborne layer weight
	Ride: number, -- broom layer weight
	WasAirborne: boolean,
	AirSince: number,
	LastFall: number, -- vertical speed while airborne (for landings)
	LandStart: number,
	LandPower: number,
	R6: boolean?,
}

local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any
local baseC0: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

local function vec(p: { number }?): Vector3
	return if p then Vector3.new(p[1] or 0, p[2] or 0, p[3] or 0) else Vector3.zero
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
	for _, joint in CHANNELS do
		local p1 = k1.Pose[joint]
		local p2 = k2.Pose[joint]
		if p1 or p2 then
			out[joint] = vec(p1):Lerp(vec(p2), u)
		end
	end
	return out
end

local function newState(): State
	return {
		Anim = nil,
		Start = 0,
		HoldUntil = 0,
		Weight = {},
		Block = 0,
		Air = 0,
		Ride = 0,
		WasAirborne = false,
		AirSince = 0,
		LastFall = 0,
		LandStart = -10,
		LandPower = 0,
	}
end

local function stateOf(character: Model): State
	local state = states[character]
	if not state then
		state = newState()
		states[character] = state
	end
	return state
end

-- Plays animation `name` on a character (any client's character). With
-- `hold` (seconds), an anim that has a HoldAt key freezes there that long
-- (charging) before finishing; CombatAnim.Stop cuts it short.
function CombatAnim.Play(character: Instance?, name: string, hold: number?)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return
	end
	local anim = A[name]
	if not anim then
		return
	end
	local state = stateOf(character)
	state.Anim = anim
	state.Start = os.clock()
	state.HoldUntil = if hold then os.clock() + hold else 0
end

-- Ends whatever action is playing; the body eases back to normal.
function CombatAnim.Stop(character: Instance?)
	if typeof(character) == "Instance" and character:IsA("Model") then
		local state = states[character]
		if state then
			state.Anim = nil
		end
	end
end

function CombatAnim.Has(name: string): boolean
	return A[name] ~= nil
end

-- Every animation name (for tools/anim-check.sh).
function CombatAnim.List(): { string }
	local names = {}
	for name in A do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Playing time of the anim, freezing at its HoldAt key while held.
local function animTime(state: State, anim: Anim, clock: number): number
	local t = clock - state.Start
	local holdAt = (anim :: any).HoldAt
	if holdAt and state.HoldUntil > 0 then
		local at = holdAt * anim.Duration
		if t > at then
			if clock < state.HoldUntil then
				return at
			end
			-- Resume from the hold point once it is over.
			local resumed = at + (clock - state.HoldUntil)
			state.Start = clock - resumed
			state.HoldUntil = 0
			return resumed
		end
	end
	return t
end

local function motorOf(character: Model, joint: string, r6: boolean): any
	local spec = if r6 then R6_JOINTS[joint] else JOINTS[joint]
	if not spec then
		return nil
	end
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

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function addPose(target: { [string]: Vector3 }, pose: Pose, weight: number)
	if weight <= 0.001 then
		return
	end
	for joint, v in pose do
		target[joint] = (target[joint] or Vector3.zero) + vec(v) * weight
	end
end

-- The movement layer: broom seat, airborne rise / fall, landing squash.
local function locomotion(character: Model, state: State, dt: number, clock: number): { [string]: Vector3 }
	local out: { [string]: Vector3 } = {}
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return out
	end
	local riding = character:GetAttribute(MovementConfig.BroomAttribute) == true
	local beast = character:GetAttribute(STATUS.Beast) ~= nil
	state.Ride += ((if riding then 1 else 0) - state.Ride) * math.min(1, dt * 10)
	addPose(out, BROOM_POSE, state.Ride)

	-- Airborne: nothing under the feet (a short ray; works for everyone's
	-- characters, not only the local one).
	local airborne = false
	local vy = root.AssemblyLinearVelocity.Y
	if not riding and not beast and humanoid.Health > 0 then
		local legs = if humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight else 2
		rayParams.FilterDescendantsInstances = { character }
		local hit = Workspace:Raycast(root.Position, Vector3.new(0, -(root.Size.Y / 2 + legs + 1.2), 0), rayParams)
		airborne = hit == nil and math.abs(vy) > 1.5
	end
	if airborne and not state.WasAirborne then
		state.AirSince = clock
	end
	if airborne then
		state.LastFall = vy
	elseif state.WasAirborne then
		-- Touched down after a real fall: squash.
		local airTime = clock - state.AirSince
		if state.LastFall < -22 or airTime > 0.55 then
			state.LandStart = clock
			state.LandPower = math.clamp(-state.LastFall / 75, 0.45, 1)
		end
	end
	state.WasAirborne = airborne
	state.Air += ((if airborne then 1 else 0) - state.Air) * math.min(1, dt * 9)
	if state.Air > 0.01 then
		-- Rising -> tucked knees; falling -> spread arms and legs.
		local fall = math.clamp((-vy + 6) / 30, 0, 1)
		addPose(out, RISE_POSE, state.Air * (1 - fall) * 0.85)
		addPose(out, FALL_POSE, state.Air * fall)
	end
	local land = (clock - state.LandStart) / 0.34
	if land >= 0 and land < 1 then
		addPose(out, LAND_POSE, math.sin(land * math.pi) * state.LandPower)
	end
	return out
end

local function apply(character: Model, state: State, dt: number)
	local clock = os.clock()
	local action: { [string]: Vector3 } = {}
	local spin = 0
	local anim = state.Anim
	-- A stun (or shattering) cuts any action short.
	if anim and (character:GetAttribute(STATUS.Shattered) == true or (character:GetAttribute(STATUS.StunnedUntil) or 0) > Workspace:GetServerTimeNow()) then
		state.Anim = nil
		anim = nil
	end
	if anim then
		local t = animTime(state, anim, clock)
		if t >= anim.Duration then
			state.Anim = nil
		else
			action = sample(anim, t)
			local s = (anim :: any).Spin
			if s then
				local u = math.clamp((t / anim.Duration - s.From) / (s.To - s.From), 0, 1)
				spin = -math.pi * 2 * s.Turns * ease(u)
			end
		end
	end

	-- Layers: movement underneath, the action on top (it owns the joints it
	-- poses), the guard while blocking.
	local target = locomotion(character, state, dt, clock)
	for joint, v in action do
		target[joint] = v
	end
	local blocking = character:GetAttribute(STATUS.Blocking) == true
	state.Block += ((if blocking then 1 else 0) - state.Block) * math.min(1, dt * 12)
	if state.Block > 0.01 then
		for joint, v in BLOCK_POSE do
			local current = target[joint] or Vector3.zero
			target[joint] = current:Lerp(vec(v), state.Block)
		end
	end

	-- R6: fold the joints it lacks into the ones it has.
	local r6 = state.R6
	if r6 == nil then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		r6 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
		state.R6 = r6
	end
	if r6 then
		for joint, fold in R6_FOLD do
			local v = target[joint]
			if v then
				local into = fold[1]
				local amount = if joint == "Waist" then v else Vector3.new(v.X * fold[2], 0, 0)
				target[into] = (target[into] or Vector3.zero) + amount
				target[joint] = nil
			end
		end
	end

	-- Ease every channel toward its target (smooth in and out).
	local blend = math.min(1, dt * 22)
	for _, joint in CHANNELS do
		local goal = target[joint] or Vector3.zero
		local current = state.Weight[joint] or Vector3.zero
		local nextValue = current:Lerp(goal, blend)
		if nextValue.Magnitude < 0.05 and goal.Magnitude == 0 then
			nextValue = Vector3.zero
		end
		state.Weight[joint] = nextValue
	end

	for _, joint in CHANNELS do
		if joint == "Drop" then
			continue
		end
		local motor = motorOf(character, joint, r6)
		if motor then
			local base = baseC0[motor]
			if not base then
				base = motor.C0
				baseC0[motor] = base
			end
			local v = state.Weight[joint] or Vector3.zero
			local drop = if joint == "Root" then (state.Weight.Drop or Vector3.zero).X else 0
			local spinning = joint == "Root" and spin ~= 0
			if v == Vector3.zero and drop == 0 and not spinning then
				if motor.C0 ~= base then
					motor.C0 = base
				end
			else
				-- Rotate in the parent part's space about the joint, so the same
				-- pose reads the same on R15 and R6 joints. Elbows hinge forward.
				local pitch = if joint == "RElbow" or joint == "LElbow" then -v.X else v.X
				local rotation = CFrame.fromEulerAnglesYXZ(math.rad(pitch), math.rad(v.Y), math.rad(v.Z))
				local c0 = CFrame.new(base.Position) * rotation * base.Rotation
				if drop ~= 0 then
					c0 = CFrame.new(0, -drop, 0) * c0
				end
				if spinning then
					-- The flip turns the whole body about the root's centre.
					c0 = CFrame.Angles(spin, 0, 0) * c0
				end
				motor.C0 = c0
			end
		end
	end
end

-- Characters with something to show: an action, a guard, or movement.
local function wantsState(character: Model): boolean
	return character:GetAttribute(STATUS.Blocking) == true or character:FindFirstChild("HumanoidRootPart") ~= nil
end

function CombatAnim.Start()
	RunService.RenderStepped:Connect(function(dt)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				local state = states[character]
				if not state and wantsState(character) then
					state = stateOf(character)
				end
				if state then
					apply(character, state, dt)
				end
			end
		end
	end)
end

return CombatAnim
