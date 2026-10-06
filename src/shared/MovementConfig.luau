--!strict
-- MovementConfig
-- Shared numbers for getting around the world: running, dash, double jump and
-- the flying crystal broom. Movement is simulated by each player's client (as
-- with every Roblox character); the server owns the broom model, checks that
-- flights stay within these numbers (MovementGuard) and relays the effects so
-- everyone sees them.

local MovementConfig = {}

-- Everyone runs at full speed by default (there is no separate sprint).
MovementConfig.WalkSpeed = 30
-- Beast forms move at their GemKits speed times this (they run too).
MovementConfig.BeastSpeedScale = 1.65

MovementConfig.DefaultFieldOfView = 70
MovementConfig.RunFieldOfView = 76 -- while moving on foot

MovementConfig.Dash = {
	Speed = 95,
	Duration = 0.18,
	Cooldown = 1.1,
	AirDashes = 1, -- dashes allowed before touching the ground again
}

MovementConfig.DoubleJump = {
	Power = 52, -- upward speed (studs/s) of the extra jump
	Extra = 1, -- extra jumps in the air
	MinAirTime = 0.12, -- the first jump has to leave the ground first
}

MovementConfig.Broom = {
	Speed = 84, -- forward, along the camera
	BackSpeed = 32, -- holding S (after braking)
	StrafeSpeed = 54, -- A / D
	ClimbSpeed = 40, -- Space / Ctrl
	Accel = 2.4, -- how fast the broom reaches its target speed (per second)
	Brake = 5, -- how fast it slows down when you let go or hold S
	MaxBank = 38, -- degrees of roll into a turn
	MaxPitch = 26, -- degrees the broom tips up / down with the climb
	MaxHeight = 220, -- studs above the ground below
	CeilingY = 900, -- absolute limit where there is no ground below
	ToggleCooldown = 0.6, -- between requests
	Cooldown = 2.5, -- after getting off (or being knocked off) before riding again
	FieldOfView = 88,
	AllowedInCombat = false, -- can't be summoned for a few seconds after a hit, and dismounts on hit
	DismountGrace = 1.4, -- seconds the movement guard looks away after a dismount (momentum)
}

-- Character attribute set by the server while riding.
MovementConfig.BroomAttribute = "Broom"

table.freeze(MovementConfig.Dash)
table.freeze(MovementConfig.DoubleJump)
table.freeze(MovementConfig.Broom)
table.freeze(MovementConfig)

return MovementConfig
