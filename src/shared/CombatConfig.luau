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
	Puffed = "Puffed", -- reserved for the Puff state system
}

CombatConfig.Tags = {
	Dummy = "CombatDummy", -- training dummies: always hittable, even in safe zones
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
table.freeze(CombatConfig)

return CombatConfig
