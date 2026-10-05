--!strict
-- MovementConfig
-- Shared numbers for getting around the world: sprint, dash, double jump and
-- the crystal hoverboard. Movement is simulated by each player's client (as
-- with every Roblox character); the server owns the hoverboard itself and
-- relays the effects so everyone sees them.

local MovementConfig = {}

MovementConfig.WalkSpeed = 18

MovementConfig.Sprint = {
	Multiplier = 1.65, -- 18 -> ~30
	FieldOfView = 78,
}

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

MovementConfig.Hoverboard = {
	Speed = 46,
	SprintSpeed = 66,
	Lift = 1.3, -- extra hip height while riding
	JumpHeight = 11,
	Cooldown = 0.6, -- between toggles
	FieldOfView = 84,
	AllowedInArena = false,
}

MovementConfig.DefaultFieldOfView = 70

-- Character attribute set by the server while riding.
MovementConfig.HoverboardAttribute = "Hoverboard"

table.freeze(MovementConfig.Sprint)
table.freeze(MovementConfig.Dash)
table.freeze(MovementConfig.DoubleJump)
table.freeze(MovementConfig.Hoverboard)
table.freeze(MovementConfig)

return MovementConfig
