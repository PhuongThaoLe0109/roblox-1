--!strict
-- CombatConfig
-- Status-effect attribute names (set on characters by the server, read by the
-- client for movement and VFX), damage formula constants and remote names.
-- All "...Until" attributes hold workspace:GetServerTimeNow() timestamps, so
-- server and clients agree on when an effect ends.

local CombatConfig = {}

CombatConfig.Status = {
	StunnedUntil = "StunnedUntil", -- no moving, jumping or attacking
	FrozenUntil = "FrozenUntil", -- stun + encased in ice
	RootedUntil = "RootedUntil", -- no moving/jumping, can still attack
	SlowUntil = "SlowUntil",
	SlowMult = "SlowMult", -- walk speed multiplier while slowed
	Shield = "Shield", -- remaining absorb amount
	ShieldUntil = "ShieldUntil",
	DamageMult = "DamageMult", -- outgoing damage multiplier (buffs)
	DamageMultUntil = "DamageMultUntil",
	DodgeUntil = "DodgeUntil", -- next incoming hit is dodged
	EchoUntil = "EchoUntil", -- Prism Spear R
	HeatUntil = "HeatUntil", -- Ember Gauntlet E
	WeaponSummoned = "WeaponSummoned",
	Puffed = "Puffed", -- body gone, gem in a capsule (PuffService)
	PuffedUntil = "PuffedUntil", -- when the gem reforms on its own
	PuffAction = "PuffAction", -- "" | "Sealing" | "Reviving" while a prompt is held
	ProtectedUntil = "ProtectedUntil", -- spawn protection after reforming
}

CombatConfig.Tags = {
	Dummy = "CombatDummy", -- training dummies: always hittable, even in safe zones
	PuffPrompt = "PuffPrompt", -- Seal / Revive prompts on gem capsules
}

-- Puff state: what happens at 0 HP instead of dying.
CombatConfig.Puff = {
	Duration = 8, -- seconds before the gem reforms on the spot
	DummyDuration = 4,
	ReformHealth = 1, -- fraction of max health after reforming
	ProtectTime = 2.5, -- invulnerability after reforming
	SealHoldTime = 1.5, -- enemies hold to seal (send home)
	ReviveHoldTime = 1.5, -- allies hold to revive on the spot
	PromptDistance = 10,
	SealReward = 40, -- essence for sealing an enemy gem
	SealRespawnDelay = 1.2,
}

-- Damage = base * powerScale * buffs * defenseScale
CombatConfig.PowerBaseline = 10
CombatConfig.PowerPerPoint = 0.04 -- +4% damage per Power above baseline
CombatConfig.DefenseBaseline = 8
CombatConfig.DefensePerPoint = 0.03 -- -3% damage taken per Defense above baseline
CombatConfig.MinDefenseScale = 0.6

-- No PvP damage in these locations (TerritoryConfig.GetLocationAt values).
CombatConfig.SafeZones = { Hub = true, Home = true }

CombatConfig.MaxAimDistance = 400 -- server rejects aim points further than this

table.freeze(CombatConfig.Status)
table.freeze(CombatConfig.Tags)
table.freeze(CombatConfig.SafeZones)
table.freeze(CombatConfig.Puff)
table.freeze(CombatConfig)

return CombatConfig
