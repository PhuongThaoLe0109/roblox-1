-- ActionService
-- Receives CombatAction requests and decides whether they happen. Clients only
-- send intentions ("M1", "Z".."V", "G", "Block", "Unblock", "Dash") plus where
-- they aim; every rule is checked here against the player's gem kit:
--   * only living players outside the safe zone can attack;
--   * a per-player request budget (spam is dropped silently);
--   * stun, wind-ups, end lag and blocking lock out attacks;
--   * cooldowns are server timestamps (a small latency tolerance applies);
--   * the melee combo index is tracked here, never taken from the client;
--   * a key only works if the gem's kit has a skill on it.
-- It also regenerates guard. Walk speed is applied by the owning client from
-- the status attributes (see MovementController), and checked by MovementGuard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemKits = require(ReplicatedStorage:WaitForChild("GemKits"))

local Combat = script.Parent
local BeastService = require(Combat:WaitForChild("BeastService"))
local CombatService = require(Combat:WaitForChild("CombatService"))
local Melee = require(Combat:WaitForChild("Melee"))
local Skills = require(Combat:WaitForChild("Skills"))
local Remotes = require(Combat.Parent:WaitForChild("Remotes"))

local STATUS = CombatConfig.Status
local PA = CombatConfig.PlayerAttributes
local BLOCK = CombatConfig.Block
local DASH = CombatConfig.Dash
local TOLERANCE = CombatConfig.LatencyTolerance

local BUDGET = 16 -- requests per second (holding M1 sends ~5)

-- How long each archetype keeps you from starting another action.
local BUSY: { [string]: (skill: { [string]: any }) -> number } = {
	Rush = function(s) return s.Duration + 0.08 end,
	Slam = function(s) return s.Delay + 0.25 end,
	Spin = function(s) return s.Duration end,
	Flurry = function(s) return s.Hits * 0.07 + 0.1 end,
	Nova = function(s) return s.WindUp + 0.25 end,
	Beam = function(s) return s.Duration end,
	Meteor = function() return 0.45 end,
	Transform = function() return 0.8 end,
	Domain = function() return 1.2 end,
	Grab = function() return 0.45 end,
}

local ActionService = {}

type State = {
	Ready: { [string]: number }, -- slot -> server time it's usable again
	Combo: number,
	ComboStyle: string,
	LastM1: number,
	Tokens: number,
	Refilled: number,
}

local states: { [Player]: State } = {}

local function stateOf(player: Player): State
	local state = states[player]
	if not state then
		state = { Ready = {}, Combo = 0, ComboStyle = "", LastM1 = -math.huge, Tokens = BUDGET, Refilled = os.clock() }
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

local function setReady(player: Player, state: State, slot: string, at: number, extra: any?)
	state.Ready[slot] = at
	Remotes.CombatState:FireClient(player, "Cooldown", slot, at, extra)
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

local function onAction(player: Player, action: unknown, aim: unknown, aimPoint: unknown)
	if typeof(action) ~= "string" then
		return
	end
	local state = stateOf(player)
	if not spend(state) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return
	end
	if character:GetAttribute(STATUS.Shattered) == true then
		return
	end
	local now = CombatService.Now()

	local look = CombatService.FlatUnit(root.CFrame.LookVector)
	local direction = if typeof(aim) == "Vector3" and isFinite(aim) then aim else look
	direction = CombatService.FlatUnit(direction, look)
	local point = if typeof(aimPoint) == "Vector3" and isFinite(aimPoint) then aimPoint else root.Position + direction * 30
	if (point - root.Position).Magnitude > CombatConfig.MaxAimDistance then
		point = root.Position + direction * 30
	end

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
		-- The movement itself is done by the client (MovementController);
		-- the server grants the i-frames.
		if (state.Ready.Dash or 0) > now + TOLERANCE then
			return
		end
		state.Ready.Dash = now + DASH.Cooldown
		character:SetAttribute(STATUS.Blocking, false)
		CombatService.Extend(character, STATUS.InvulnerableUntil, DASH.IFrames)
		CombatService.Extend(character, STATUS.MoveGraceUntil, 0.9)
		return
	end

	-- Everything below is an attack.
	if player:GetAttribute(PA.InSafeZone) == true then
		reject(player, action, "SafeZone")
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

	local kit = CombatService.KitOf(player)
	local context = {
		Player = player,
		Character = character,
		Root = root,
		Aim = direction,
		AimPoint = point,
		Kit = kit,
		Skill = nil :: any,
	}

	if action == "M1" then
		local style = if BeastService.IsBeast(character) then GemKits.Melee.Maul else kit.Melee
		if state.ComboStyle ~= style.Id then
			state.ComboStyle = style.Id
			state.Combo = 0
		end
		if now - state.LastM1 < style.Interval - TOLERANCE then
			reject(player, action, "Busy")
			return
		end
		if state.Combo >= style.Hits and (state.Ready.M1 or 0) > now + TOLERANCE then
			reject(player, action, "Cooldown")
			return
		end
		local combo = if now - state.LastM1 > style.ResetTime or state.Combo >= style.Hits then 1 else state.Combo + 1
		state.Combo = combo
		state.LastM1 = now
		local finisher = combo == style.Hits
		CombatService.Extend(character, STATUS.BusyUntil, if finisher then 0.45 else math.min(0.2, style.Interval * 0.6))
		setReady(player, state, "M1", now + (if finisher then style.EndLag else style.Interval), combo)
		dropSpawnProtection(character)
		task.spawn(Melee.Swing, context, style, combo)
		return
	end

	local skill = GemKits.SkillFor(kit, action)
	if not skill then
		reject(player, action, "NoSkill")
		return
	end
	if (state.Ready[action] or 0) > now + TOLERANCE then
		reject(player, action, "Cooldown")
		return
	end
	if skill.Archetype == "Transform" and BeastService.IsBeast(character) then
		reject(player, action, "Busy")
		return
	end
	local cooldown = skill.Cooldown
	-- Inside your own domain, cooldowns run faster.
	if CombatService.IsActive(character, STATUS.DomainUntil) and skill.Archetype ~= "Domain" then
		cooldown *= 1 - (character:GetAttribute("DomainHaste") or 0) / 100
	end
	setReady(player, state, action, now + cooldown)
	local busy = BUSY[skill.Archetype]
	CombatService.Extend(character, STATUS.BusyUntil, if busy then busy(skill) else 0.3)
	if skill.Archetype == "Rush" then
		CombatService.Extend(character, STATUS.MoveGraceUntil, skill.Duration + 0.7)
	end
	dropSpawnProtection(character)
	context.Skill = skill
	if skill.Archetype == "Transform" then
		task.spawn(BeastService.Transform, context)
	else
		local run = (Skills :: any)[skill.Archetype]
		if run then
			task.spawn(run, context)
		end
	end
end

-- Clears cooldowns and combo (on respawn).
function ActionService.Reset(player: Player)
	states[player] = nil
	Remotes.CombatState:FireClient(player, "Reset")
end

local function upkeep(dt: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character:GetAttribute(STATUS.Blocking) ~= true then
			local guard = character:GetAttribute(STATUS.Guard) or BLOCK.MaxGuard
			if guard < BLOCK.MaxGuard then
				character:SetAttribute(STATUS.Guard, math.min(BLOCK.MaxGuard, guard + BLOCK.GuardRegen * dt))
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
