-- MovementGuard
-- Basic movement anti-cheat for players in the arena. Characters are
-- simulated by their owner's client, so the server samples root positions and
-- pulls a player back to their last valid spot when they cover ground much
-- faster than their walk speed allows (speed hacks, teleports).
--
-- Dashes, Prism Rush and knockback set the MoveGraceUntil status, during which
-- the guard looks away. Vertical motion is left alone (jumps, launches and
-- falls are all legitimate), and falling out of the arena is handled by
-- MatchService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local STATUS = CombatConfig.Status

local SAMPLE = 0.2 -- seconds between samples
local SLACK = 1.5 -- allowed multiple of the walk speed (network jitter)
local FLAT_ALLOWANCE = 8 -- studs per second on top of that
local STRIKES = 3 -- consecutive suspicious samples before a pull-back
local TELEPORT = 60 -- studs in one sample: pulled back immediately

local MovementGuard = {}

type Track = { Last: Vector3, Valid: Vector3, Strikes: number }

local tracks: { [Player]: Track } = {}

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

	local moved = flat(position - track.Last).Magnitude
	track.Last = position
	if CombatService.IsActive(target.Character, STATUS.MoveGraceUntil) then
		track.Valid = position
		track.Strikes = 0
		return
	end

	local allowed = (math.max(target.Humanoid.WalkSpeed, CombatConfig.WalkSpeed) * SLACK + FLAT_ALLOWANCE) * interval
	if moved > allowed then
		track.Strikes += 1
		if moved > TELEPORT or track.Strikes >= STRIKES then
			-- Back to the last position reached at a legal speed.
			local rotation = root.CFrame - root.Position
			target.Character:PivotTo(CFrame.new(track.Valid) * rotation)
			root.AssemblyLinearVelocity = Vector3.zero
			track.Last = track.Valid
			track.Strikes = 0
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
