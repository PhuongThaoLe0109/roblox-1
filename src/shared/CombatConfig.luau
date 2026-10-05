--!strict
-- CombatConfig
-- Every number of the shared "Crystal Blade" kit plus the status attribute
-- names. Shared so the client can show cooldowns and predict movement; the
-- server is authoritative for all of it.
--
-- Status attributes hold workspace:GetServerTimeNow() timestamps so server
-- and clients agree on when effects end.

local CombatConfig = {}

CombatConfig.MaxHealth = 100
CombatConfig.WalkSpeed = 20
CombatConfig.JumpPower = 50
CombatConfig.SpawnProtection = 2.5 -- seconds of invulnerability after entering the arena
CombatConfig.ReturnToLobbyDelay = 3 -- seconds after defeat before respawning in the lobby
CombatConfig.ComboWindow = 1.6 -- hits within this window keep the combo counter going
CombatConfig.AssistWindow = 8 -- damage within this window before a kill earns nothing extra (reserved)
CombatConfig.LatencyTolerance = 0.12 -- accept presses slightly before a cooldown ends
CombatConfig.MaxAimDistance = 400
CombatConfig.KillHeal = 25 -- health restored to the killer
CombatConfig.KillCreditWindow = 12 -- falling off after a hit still credits the attacker
CombatConfig.StreakMilestones = { 3, 5, 8, 12, 20 } -- announced to the server
CombatConfig.MovingAttackSpeed = 12 -- walk speed while an attack plays out

--------------------------------------------------------------------------------
-- M1: four-hit crystal blade combo
--------------------------------------------------------------------------------

CombatConfig.M1 = {
	Damage = { 6, 6, 7, 11 },
	Range = 8,
	Arc = 110,
	Interval = 0.32, -- minimum time between hits
	ResetTime = 1.0, -- combo restarts if you wait longer than this
	EndLag = 0.85, -- pause after the 4th hit
	FinisherKnockback = 55,
	FinisherStun = 0.55,
	HitStun = 0.25, -- tiny stagger on hits 1-3
}

--------------------------------------------------------------------------------
-- Skills
--------------------------------------------------------------------------------

export type Skill = {
	Name: string,
	Description: string,
	Key: string,
	Icon: string,
	Cooldown: number,
	[string]: any,
}

CombatConfig.Skills = {
	Z = {
		Name = "Shard Volley",
		Description = "Fling a fan of three crystal shards.",
		Key = "Z",
		Icon = "⋔",
		Cooldown = 6,
		Busy = 0.3,
		Damage = 8,
		Count = 3,
		Spread = 11,
		Speed = 150,
		Range = 85,
		Radius = 2.5,
	},
	X = {
		Name = "Rising Facet",
		Description = "An upward slash that launches everyone in front of you.",
		Key = "X",
		Icon = "⤒",
		Cooldown = 8,
		Busy = 0.4,
		Damage = 12,
		Range = 10,
		Arc = 120,
		Launch = 62,
		Stun = 0.9,
	},
	C = {
		Name = "Prism Rush",
		Description = "Dash forward, slicing through everything in your path.",
		Key = "C",
		Icon = "➶",
		Cooldown = 9,
		Busy = 0.36,
		Damage = 14,
		HitRadius = 7,
		Speed = 120,
		Duration = 0.28,
		Knockback = 35,
	},
	V = {
		Name = "Gem Nova",
		Description = "Gather light, then release a crystal shockwave around you.",
		Key = "V",
		Icon = "✷",
		Cooldown = 22,
		Busy = 0.8, -- wind-up plus recovery
		Damage = 28,
		Radius = 19,
		WindUp = 0.55,
		Knockback = 75,
		Launch = 35,
		Stun = 0.8,
	},
} :: { [string]: Skill }

CombatConfig.SkillOrder = { "Z", "X", "C", "V" }

--------------------------------------------------------------------------------
-- Defence & movement
--------------------------------------------------------------------------------

CombatConfig.Block = {
	DamageTaken = 0.15, -- fraction of damage that gets through a block
	Arc = 150, -- only blocks hits from the front
	MaxGuard = 100,
	GuardPerDamage = 3.2, -- guard lost per point of blocked damage
	GuardRegen = 22, -- per second while not blocking
	BreakStun = 1.4,
	WalkSpeed = 9,
	StartLag = 0.12, -- can't attack for this long after raising your guard
}

CombatConfig.Dash = {
	Cooldown = 2.2,
	Speed = 88,
	Duration = 0.22,
	IFrames = 0.26,
}

--------------------------------------------------------------------------------
-- Status attributes (on characters)
--------------------------------------------------------------------------------

CombatConfig.Status = {
	StunnedUntil = "StunnedUntil",
	InvulnerableUntil = "InvulnerableUntil", -- i-frames and spawn protection
	Blocking = "Blocking",
	Guard = "Guard",
	BusyUntil = "BusyUntil", -- end lag / wind-ups: no new actions
	Combo = "Combo", -- current combo count (on the attacker)
	SpawnProtected = "SpawnProtected", -- cleared as soon as you attack
	MoveGraceUntil = "MoveGraceUntil", -- dashes and knockback: MovementGuard looks away
}

-- Player attributes
CombatConfig.PlayerAttributes = {
	InArena = "InArena",
	Streak = "Streak",
}

table.freeze(CombatConfig.StreakMilestones)
table.freeze(CombatConfig.M1.Damage)
table.freeze(CombatConfig.M1)
for _, skill in CombatConfig.Skills do
	table.freeze(skill)
end
table.freeze(CombatConfig.Skills)
table.freeze(CombatConfig.SkillOrder)
table.freeze(CombatConfig.Block)
table.freeze(CombatConfig.Dash)
table.freeze(CombatConfig.Status)
table.freeze(CombatConfig.PlayerAttributes)
table.freeze(CombatConfig)

return CombatConfig
