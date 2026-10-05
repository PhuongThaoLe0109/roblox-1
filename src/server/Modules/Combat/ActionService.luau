-- ActionService
-- Receives CombatAction requests and decides whether they happen. Clients only
-- send intentions ("M1", "Z", "Block", ...) plus an aim direction; every rule
-- is checked here:
--   * only living players inside the arena can act;
--   * per-player request budget (spam is dropped silently);
--   * stun, wind-ups, end lag and blocking lock out attacks;
--   * cooldowns are server timestamps (a small latency tolerance applies);
--   * the M1 combo index is tracked here, never taken from the client.
-- It also owns the per-frame status upkeep: guard regeneration and walk speed
-- / jump height derived from stun, block and busy states.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))

local Combat = script.Parent
local CombatService = require(Combat:WaitForChild("CombatService"))
local CrystalKit = require(Combat:WaitForChild("CrystalKit"))
local Remotes = require(Combat.Parent:WaitForChild("Remotes"))

local STATUS = CombatConfig.Status
local M1 = CombatConfig.M1
local SKILLS = CombatConfig.Skills
local BLOCK = CombatConfig.Block
local DASH = CombatConfig.Dash
local TOLERANCE = CombatConfig.LatencyTolerance

local BUDGET = 14 -- requests per second (holding M1 sends ~4)
local DEFAULT_JUMP_HEIGHT = 7.2

local ActionService = {}

type State = {
	Ready: { [string]: number }, -- slot -> server time it's usable again
	Combo: number,
	LastM1: number,
	Tokens: number,
	Refilled: number,
}

local states: { [Player]: State } = {}

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = { Ready = {}, Combo = 0, LastM1 = -math.huge, Tokens = BUDGET, Refilled = os.clock() }
		states[player] = state
	end
	return state
end

local function spend(state: State): boolean
	local t = os.clock()
	state.Tokens = math.min(BUDGET, state.Tokens + (t - state.Refilled) * BUDGET)
	state.Refilled = t
	if state.Tokens < 1 then
		return false
	end
	state.Tokens -= 1
	return true
end

local function reject(player: Player, slot: string, reason: string)
	Remotes.CombatState:FireClient(player, "Rejected", slot, reason)
end

local function setReady(player: Player, state: State, slot: string, at: number)
	state.Ready[slot] = at
	Remotes.CombatState:FireClient(player, "Cooldown", slot, at)
end

local function isFinite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e7
end

-- Attacking (or dashing) ends spawn protection early.
local function dropSpawnProtection(character: Model)
	if character:GetAttribute(STATUS.SpawnProtected) then
		character:SetAttribute(STATUS.SpawnProtected, false)
		character:SetAttribute(STATUS.InvulnerableUntil, CombatService.Now())
	end
end

local function onAction(player: Player, action: unknown, aim: unknown)
	if typeof(action) ~= "string" then
		return
	end
	local state = stateOf(player)
	if not spend(state) then
		return
	end
	local target = CombatService.ToTarget(player)
	if not target then
		return
	end
	local character = target.Character
	local root = target.Root
	local now = CombatService.Now()

	local direction = if typeof(aim) == "Vector3" and isFinite(aim) then aim else root.CFrame.LookVector
	direction = CombatService.FlatUnit(direction, CombatService.FlatUnit(root.CFrame.LookVector))

	if action == "Unblock" then
		character:SetAttribute(STATUS.Blocking, false)
		return
	end

	if CombatService.IsActive(character, STATUS.StunnedUntil) then
		reject(player, action, "Stunned")
		return
	end

	if action == "Block" then
		if (character:GetAttribute(STATUS.Guard) or BLOCK.MaxGuard) < BLOCK.MaxGuard * 0.15 then
			reject(player, action, "GuardBroken")
			return
		end
		character:SetAttribute(STATUS.Blocking, true)
		CombatService.Extend(character, STATUS.BusyUntil, BLOCK.StartLag)
		return
	end

	if action == "Dash" then
		if (state.Ready.Dash or 0) > now + TOLERANCE then
			reject(player, action, "Cooldown")
			return
		end
		setReady(player, state, "Dash", now + DASH.Cooldown)
		character:SetAttribute(STATUS.Blocking, false)
		dropSpawnProtection(character)
		CombatService.Extend(character, STATUS.InvulnerableUntil, DASH.IFrames)
		CombatService.Extend(character, STATUS.MoveGraceUntil, DASH.Duration + 0.6)
		local color, accent = CombatService.ColorsOf(player)
		CombatService.FX("Dash", { Caster = character, Direction = direction, Duration = DASH.Duration, Color = color, Accent = accent })
		return
	end

	local isM1 = action == "M1"
	local skill = SKILLS[action]
	if not isM1 and not skill then
		return
	end
	if character:GetAttribute(STATUS.Blocking) == true then
		reject(player, action, "Blocking")
		return
	end
	if (character:GetAttribute(STATUS.BusyUntil) or 0) > now + TOLERANCE then
		reject(player, action, "Busy")
		return
	end

	local context = {
		Player = player,
		Character = character,
		Root = root,
		Aim = direction,
		Combo = 0,
	}

	if isM1 then
		if now - state.LastM1 < M1.Interval - TOLERANCE then
			reject(player, action, "Busy")
			return
		end
		local combo = if now - state.LastM1 > M1.ResetTime or state.Combo >= 4 then 1 else state.Combo + 1
		if state.Combo >= 4 and (state.Ready.M1 or 0) > now + TOLERANCE then
			reject(player, action, "Cooldown")
			return
		end
		state.Combo = combo
		state.LastM1 = now
		context.Combo = combo
		local lag = if combo == 4 then M1.EndLag else M1.Interval
		CombatService.Extend(character, STATUS.BusyUntil, if combo == 4 then 0.45 else 0.18)
		setReady(player, state, "M1", now + lag)
		dropSpawnProtection(character)
		task.spawn(CrystalKit.M1, context)
		return
	end

	if (state.Ready[action] or 0) > now + TOLERANCE then
		reject(player, action, "Cooldown")
		return
	end
	setReady(player, state, action, now + skill.Cooldown)
	CombatService.Extend(character, STATUS.BusyUntil, skill.Busy or 0.3)
	if action == "C" then
		CombatService.Extend(character, STATUS.MoveGraceUntil, skill.Duration + 0.7)
	end
	dropSpawnProtection(character)
	task.spawn((CrystalKit :: any)[action], context)
end

-- Clears cooldowns and combo (called when a player enters the arena).
function ActionService.Reset(player: Player)
	states[player] = nil
	Remotes.CombatState:FireClient(player, "Reset")
end

--------------------------------------------------------------------------------
-- Status upkeep
--------------------------------------------------------------------------------

local function upkeep(dt: number)
	local now = CombatService.Now()
	for _, player in Players:GetPlayers() do
		local target = CombatService.ToTarget(player)
		if target then
			local character = target.Character
			local humanoid = target.Humanoid
			local blocking = character:GetAttribute(STATUS.Blocking) == true
			local stunned = (character:GetAttribute(STATUS.StunnedUntil) or 0) > now
			local busy = (character:GetAttribute(STATUS.BusyUntil) or 0) > now

			if not blocking then
				local guard = character:GetAttribute(STATUS.Guard) or BLOCK.MaxGuard
				if guard < BLOCK.MaxGuard then
					character:SetAttribute(STATUS.Guard, math.min(BLOCK.MaxGuard, guard + BLOCK.GuardRegen * dt))
				end
			end

			local speed = if stunned
				then 0
				elseif blocking then BLOCK.WalkSpeed
				elseif busy then CombatConfig.MovingAttackSpeed
				else CombatConfig.WalkSpeed
			if humanoid.WalkSpeed ~= speed then
				humanoid.WalkSpeed = speed
			end
			local jump = if stunned or blocking then 0 else DEFAULT_JUMP_HEIGHT
			if humanoid.JumpHeight ~= jump then
				humanoid.JumpHeight = jump
			end
		end
	end
end

function ActionService.Init()
	Remotes.CombatAction.OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	RunService.Heartbeat:Connect(upkeep)
end

return ActionService
