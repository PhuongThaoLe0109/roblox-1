--!strict
-- CombatConfig
-- General combat numbers and status attribute names, shared so the client can
-- predict and display them; the server is authoritative for all of it.
-- Per-gem kits (melee style, skills, beast form) live in GemKits.
--
-- The whole world is a battlefield: everyone fights with their gem's kit as
-- soon as they spawn. Only the Dawn Gate plaza is a safe zone (SafeZone).
--
-- Status attributes hold workspace:GetServerTimeNow() timestamps so server
-- and clients agree on when effects end.

local CombatConfig = {}

CombatConfig.MaxHealth = 100
CombatConfig.SpawnProtection = 3 -- seconds of invulnerability after (re)spawning
CombatConfig.RespawnTime = 4.5 -- shattered gem -> reformed in the lobby
CombatConfig.ComboWindow = 1.6 -- hits within this window keep the combo counter going
CombatConfig.LatencyTolerance = 0.12 -- accept presses slightly before a cooldown ends
CombatConfig.KillHeal = 25 -- health restored to the killer
CombatConfig.KillCreditWindow = 12 -- falling off the world after a hit still credits the attacker
CombatConfig.StreakMilestones = { 3, 5, 8, 12, 20 } -- announced to the server
CombatConfig.InCombatTime = 8 -- seconds after dealing/taking damage you count as "in combat"
CombatConfig.MaxAimDistance = 400

-- The lobby plaza is a safe zone: nobody inside can attack or be hit.
CombatConfig.SafeZone = {
	Enabled = true,
	ExtraRadius = 0, -- added to Map.Lobby's Radius attribute
}

-- Movement speeds while fighting (the client applies them; see MovementController).
CombatConfig.Speeds = {
	Stunned = 0,
	Blocking = 9,
	Busy = 12, -- while an attack or wind-up plays out
	Beam = 6, -- while channelling a beam
	Slowed = 8,
	Rooted = 0,
}

CombatConfig.Block = {
	DamageTaken = 0.15, -- fraction of damage that gets through a block
	Arc = 150, -- only blocks hits from the front
	MaxGuard = 100,
	GuardPerDamage = 3.2, -- guard lost per point of blocked damage
	GuardRegen = 22, -- per second while not blocking
	BreakStun = 1.4,
	StartLag = 0.12, -- can't attack for this long after raising your guard
}

-- Dash (Q) grants i-frames; the movement itself is MovementConfig.Dash.
CombatConfig.Dash = {
	Cooldown = 1.1,
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
	SlowUntil = "SlowUntil", -- channelling: walk at Speeds.Beam
	SlowedUntil = "SlowedUntil", -- frostbite / domain: walk at Speeds.Slowed
	RootedUntil = "RootedUntil", -- shackled: can't walk or jump, can still fight
	CursedUntil = "CursedUntil", -- hexed: takes CurseAmp % more damage
	CurseAmp = "CurseAmp",
	DomainUntil = "DomainUntil", -- your domain is open: faster cooldowns
	Combo = "Combo", -- current combo count (on the attacker)
	SpawnProtected = "SpawnProtected", -- cleared as soon as you attack
	MoveGraceUntil = "MoveGraceUntil", -- dashes and knockback: MovementGuard looks away
	ShieldHP = "ShieldHP", -- Aegis: damage absorbed before health
	ShieldUntil = "ShieldUntil",
	Beast = "Beast", -- beast id while transformed
	BeastUntil = "BeastUntil",
	Shattered = "Shattered", -- dead and in pieces, waiting to reform
}

-- Player attributes
CombatConfig.PlayerAttributes = {
	Streak = "Streak",
	InSafeZone = "InSafeZone",
	LastCombat = "LastCombat", -- server time of the last hit dealt or taken
}

table.freeze(CombatConfig.StreakMilestones)
table.freeze(CombatConfig.SafeZone)
table.freeze(CombatConfig.Speeds)
table.freeze(CombatConfig.Block)
table.freeze(CombatConfig.Dash)
table.freeze(CombatConfig.Status)
table.freeze(CombatConfig.PlayerAttributes)
table.freeze(CombatConfig)

return CombatConfig
