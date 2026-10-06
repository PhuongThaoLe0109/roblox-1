-- MovementGuard
-- Basic movement anti-cheat for every fighter. Characters are
-- simulated by their owner's client, so the server samples root positions and
-- pulls a player back to their last valid spot when they cover ground much
-- faster than their walk speed allows (speed hacks, teleports).
--
-- Dashes, Prism Rush, knockback and getting off the broom set the
-- MoveGraceUntil status, during which the guard looks away. On foot, vertical
-- motion is left alone (jumps, launches and falls are all legitimate); on the
-- broom the full 3D speed is judged and the rider must stay within the flight
-- ceiling (MovementConfig.Broom.MaxHeight above the ground).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemKits = require(ReplicatedStorage:WaitForChild("GemKits"))
local MovementConfig = require(ReplicatedStorage:WaitForChild("MovementConfig"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local STATUS = CombatConfig.Status

local SAMPLE = 0.2 -- seconds between samples
local SLACK = 1.5 -- allowed multiple of the top speed (network jitter)
local FLAT_ALLOWANCE = 8 -- studs per second on top of that
local STRIKES = 4 -- consecutive suspicious samples before a pull-back
local TELEPORT = 60 -- studs in one sample: pulled back immediately
local HEIGHT_SLACK = 25 -- studs over the broom's MaxHeight before a pull-back

local MovementGuard = {}

type Track = { Last: Vector3, Valid: Vector3, Strikes: number }

local tracks: { [Player]: Track } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

-- A broom rider above the legal flight ceiling: higher than MaxHeight over the
-- ground below, or above CeilingY where there is no ground at all.
local function tooHigh(character: Model, position: Vector3): boolean
	local b = MovementConfig.Broom
	rayParams.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(position, Vector3.new(0, -(b.MaxHeight + HEIGHT_SLACK), 0), rayParams)
	if hit then
		return false
	end
	-- Nothing below within reach: fine only while under the absolute ceiling
	-- and not far above some ground further down.
	if position.Y > b.CeilingY then
		return true
	end
	local far = Workspace:Raycast(position, Vector3.new(0, -2000, 0), rayParams)
	return far ~= nil
end

-- Back to the last position reached at a legal speed.
local function pullBack(target: any, track: Track)
	local root = target.Root
	local rotation = root.CFrame - root.Position
	target.Character:PivotTo(CFrame.new(track.Valid) * rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	track.Last = track.Valid
	track.Strikes = 0
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function check(player: Player, interval: number)
	local target = CombatService.ToTarget(player)
	if not target then
		tracks[player] = nil
		return
	end
	local root = target.Root
	local position = root.Position
	local track = tracks[player]
	if not track then
		tracks[player] = { Last = position, Valid = position, Strikes = 0 }
		return
	end

	local delta = position - track.Last
	local riding = target.Character:GetAttribute(MovementConfig.BroomAttribute) == true
	-- On foot only ground speed is judged (jumps, launches and falls are all
	-- legitimate); on the broom the whole 3D flight is, plus its height.
	local moved = if riding then delta.Magnitude else flat(delta).Magnitude
	track.Last = position
	if CombatService.IsActive(target.Character, STATUS.MoveGraceUntil) then
		track.Valid = position
		track.Strikes = 0
		return
	end
	if riding and tooHigh(target.Character, position) then
		pullBack(target, track)
		return
	end

	-- Walk speed is applied by the client, so judge against the fastest
	-- legal speed for the player's current state.
	local top = MovementConfig.WalkSpeed
	local beast = target.Character:GetAttribute(STATUS.Beast)
	if riding then
		local b = MovementConfig.Broom
		top = math.sqrt(b.Speed ^ 2 + b.ClimbSpeed ^ 2)
	elseif beast and GemKits.Beasts[beast] then
		top = GemKits.Beasts[beast].Speed * MovementConfig.BeastSpeedScale
	end
	local allowed = (top * SLACK + FLAT_ALLOWANCE) * interval
	if moved > allowed then
		track.Strikes += 1
		if moved > TELEPORT * (if riding then 2 else 1) or track.Strikes >= STRIKES then
			pullBack(target, track)
		end
		return
	end
	track.Strikes = math.max(0, track.Strikes - 1)
	if track.Strikes == 0 then
		track.Valid = position
	end
end

-- Forget the last valid position (after a server teleport).
function MovementGuard.Reset(player: Player)
	tracks[player] = nil
end

function MovementGuard.Init()
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < SAMPLE then
			return
		end
		local interval = elapsed
		elapsed = 0
		for _, player in Players:GetPlayers() do
			check(player, interval)
		end
	end)
end

return MovementGuard
