-- CombatService
-- Server-authoritative combat primitives:
--   * Target queries (sphere, cone, line, moving sweeps) over arena players.
--   * Damage: blocking (front arc, guard meter, guard break), i-frames,
--     knockback via LinearVelocity, stun, combo counting, kill credit.
--   * Server-simulated projectiles, mirrored visually on every client.
--   * FX broadcast. Every effect carries the attacker's gem colours so each
--     player's attacks glow in the colours of the aura they wear.
--
-- Only players standing in the arena (Player.InArena) can hit or be hit.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))

local Modules = script.Parent.Parent
local Remotes = require(Modules:WaitForChild("Remotes"))

local STATUS = CombatConfig.Status
local PA = CombatConfig.PlayerAttributes
local BODY_RADIUS = 2

local CombatService = {}

CombatService.Damaged = Signal.new() -- (attacker: Player?, target: Target, amount)
CombatService.Killed = Signal.new() -- (killer: Player?, victim: Player)

export type Target = {
	Player: Player,
	Character: Model,
	Humanoid: Humanoid,
	Root: BasePart,
}

local DEFAULT_COLOR = Color3.fromRGB(235, 225, 255)
local DEFAULT_ACCENT = Color3.fromRGB(170, 200, 255)

--------------------------------------------------------------------------------
-- Basics
--------------------------------------------------------------------------------

function CombatService.Now(): number
	return Workspace:GetServerTimeNow()
end
local now = CombatService.Now

function CombatService.FlatUnit(v: Vector3, fallback: Vector3?): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-3 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function CombatService.IsActive(model: Instance, attribute: string): boolean
	return (model:GetAttribute(attribute) or 0) > now()
end

function CombatService.Extend(model: Instance, attribute: string, seconds: number)
	model:SetAttribute(attribute, math.max(model:GetAttribute(attribute) or 0, now() + seconds))
end

-- The two colours of the gem a player wears (used by every effect).
function CombatService.ColorsOf(player: Player?): (Color3, Color3)
	local gem = player and GemCatalog.Get(player:GetAttribute("EquippedGem"))
	if gem then
		return gem.Color, gem.Accent
	end
	return DEFAULT_COLOR, DEFAULT_ACCENT
end

function CombatService.ToTarget(player: Player): Target?
	if player:GetAttribute(PA.InArena) ~= true then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return nil
	end
	return { Player = player, Character = character, Humanoid = humanoid, Root = root }
end

local function candidates(attacker: Player): { Target }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player ~= attacker then
			local target = CombatService.ToTarget(player)
			if target and not CombatService.IsActive(target.Character, STATUS.InvulnerableUntil) then
				table.insert(list, target)
			end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Queries (all exclude the attacker and invulnerable targets)
--------------------------------------------------------------------------------

function CombatService.QuerySphere(attacker: Player, center: Vector3, radius: number): { Target }
	local result = {}
	for _, target in candidates(attacker) do
		if (target.Root.Position - center).Magnitude <= radius + BODY_RADIUS then
			table.insert(result, target)
		end
	end
	return result
end

function CombatService.QueryCone(attacker: Player, origin: Vector3, direction: Vector3, range: number, arc: number): { Target }
	local forward = CombatService.FlatUnit(direction)
	local cosHalf = math.cos(math.rad(arc / 2))
	local result = {}
	for _, target in candidates(attacker) do
		local offset = target.Root.Position - origin
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= range + BODY_RADIUS and math.abs(offset.Y) < 9 then
			if flat.Magnitude < 3 or flat.Unit:Dot(forward) >= cosHalf then
				table.insert(result, target)
			end
		end
	end
	return result
end

function CombatService.QueryLine(attacker: Player, origin: Vector3, direction: Vector3, length: number, width: number): { Target }
	local dir = direction.Unit
	local result = {}
	for _, target in candidates(attacker) do
		local along = math.clamp((target.Root.Position - origin):Dot(dir), 0, length)
		if (target.Root.Position - (origin + dir * along)).Magnitude <= width / 2 + BODY_RADIUS then
			table.insert(result, target)
		end
	end
	return result
end

-- Calls onHit once per target that enters a sphere around getCenter() during
-- `duration` seconds.
function CombatService.Sweep(attacker: Player, getCenter: () -> Vector3?, radius: number, duration: number, onHit: (Target) -> ())
	local hit: { [Player]: boolean } = {}
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local center = getCenter()
		if not center or os.clock() - started > duration then
			connection:Disconnect()
			return
		end
		for _, target in CombatService.QuerySphere(attacker, center, radius) do
			if not hit[target.Player] then
				hit[target.Player] = true
				task.spawn(onHit, target)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Status
--------------------------------------------------------------------------------

function CombatService.Stun(target: Target, seconds: number)
	CombatService.Extend(target.Character, STATUS.StunnedUntil, seconds)
	-- A stun interrupts blocking.
	target.Character:SetAttribute(STATUS.Blocking, false)
end

function CombatService.Knockback(target: Target, velocity: Vector3, duration: number?)
	for _, child in target.Root:GetChildren() do
		if child.Name == "Knockback" then
			child:Destroy()
		end
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Knockback"
	attachment.Parent = target.Root
	local force = Instance.new("LinearVelocity")
	force.Name = "Knockback"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	force.MaxForce = math.huge
	force.VectorVelocity = velocity
	force.Parent = target.Root
	Debris:AddItem(force, duration or 0.22)
	Debris:AddItem(attachment, duration or 0.22)
end

--------------------------------------------------------------------------------
-- Combo counter
--------------------------------------------------------------------------------

local comboState: { [Player]: { Count: number, Last: number } } = {}

local function bumpCombo(attacker: Player)
	local state = comboState[attacker]
	local t = os.clock()
	if not state or t - state.Last > CombatConfig.ComboWindow then
		state = { Count = 0, Last = t }
		comboState[attacker] = state
	end
	state.Count += 1
	state.Last = t
	local character = attacker.Character
	if character then
		character:SetAttribute(STATUS.Combo, state.Count)
	end
	-- Clear the counter once the window lapses.
	local count = state.Count
	task.delay(CombatConfig.ComboWindow + 0.05, function()
		if comboState[attacker] == state and state.Count == count and attacker.Character then
			attacker.Character:SetAttribute(STATUS.Combo, 0)
		end
	end)
end

--------------------------------------------------------------------------------
-- Damage
--------------------------------------------------------------------------------

export type HitOptions = {
	Knockback: Vector3?,
	KnockbackTime: number?,
	Stun: number?,
	Unblockable: boolean?,
	FromPosition: Vector3?, -- where the hit came from (for block direction)
}

local lastAttacker: { [Player]: { Player: Player, Time: number } } = {}

local function isBlockingHit(target: Target, from: Vector3): boolean
	if target.Character:GetAttribute(STATUS.Blocking) ~= true then
		return false
	end
	local toAttacker = CombatService.FlatUnit(from - target.Root.Position)
	local facing = CombatService.FlatUnit(target.Root.CFrame.LookVector)
	return facing:Dot(toAttacker) >= math.cos(math.rad(CombatConfig.Block.Arc / 2))
end

-- Applies a hit. Returns the damage actually dealt.
function CombatService.Hit(attacker: Player, target: Target, amount: number, options: HitOptions?): number
	local opts = options or {}
	if CombatService.IsActive(target.Character, STATUS.InvulnerableUntil) then
		return 0
	end
	local attackerRoot = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	local from = opts.FromPosition or (attackerRoot and (attackerRoot :: BasePart).Position) or target.Root.Position

	local color, accent = CombatService.ColorsOf(attacker)

	-- Blocking
	if not opts.Unblockable and isBlockingHit(target, from) then
		local guard = (target.Character:GetAttribute(STATUS.Guard) or CombatConfig.Block.MaxGuard) - amount * CombatConfig.Block.GuardPerDamage
		local chip = amount * CombatConfig.Block.DamageTaken
		if guard <= 0 then
			target.Character:SetAttribute(STATUS.Guard, 0)
			CombatService.Stun(target, CombatConfig.Block.BreakStun)
			CombatService.FX("GuardBreak", { Target = target.Character, Color = color, Accent = accent })
		else
			target.Character:SetAttribute(STATUS.Guard, guard)
			CombatService.FX("Block", { Target = target.Character, From = from, Color = color, Accent = accent })
			-- Blocked hits barely move you.
			opts = { FromPosition = from }
		end
		amount = chip
	end

	local humanoid = target.Humanoid
	local before = humanoid.Health
	local dealt = math.min(before, math.max(0, amount))
	humanoid.Health = before - dealt
	lastAttacker[target.Player] = { Player = attacker, Time = os.clock() }

	if dealt > 0 then
		bumpCombo(attacker)
	end
	if opts.Stun then
		CombatService.Stun(target, opts.Stun)
	end
	if opts.Knockback then
		CombatService.Knockback(target, opts.Knockback, opts.KnockbackTime)
	end

	CombatService.FX("Hit", {
		Target = target.Character,
		Position = target.Root.Position,
		Amount = math.floor(dealt * 10 + 0.5) / 10,
		Color = color,
		Accent = accent,
		Heavy = opts.Knockback ~= nil,
	})
	CombatService.Damaged:Fire(attacker, target, dealt)

	if before > 0 and humanoid.Health <= 0 then
		CombatService.Killed:Fire(attacker, target.Player)
	end
	return dealt
end

-- Who last hurt this player recently (kill credit for void/other deaths).
function CombatService.RecentAttacker(victim: Player, within: number): Player?
	local entry = lastAttacker[victim]
	if entry and os.clock() - entry.Time <= within and entry.Player.Parent == Players then
		return entry.Player
	end
	return nil
end

function CombatService.Forget(player: Player)
	lastAttacker[player] = nil
	comboState[player] = nil
end

--------------------------------------------------------------------------------
-- Projectiles
--------------------------------------------------------------------------------

local projectileId = 0

-- Simulated on the server; clients draw the same path. onHit fires for the
-- first target touched.
function CombatService.Projectile(attacker: Player, origin: Vector3, direction: Vector3, speed: number, range: number, radius: number, onHit: (Target, Vector3) -> ())
	projectileId += 1
	local id = projectileId
	local dir = direction.Unit
	local position = origin
	local traveled = 0
	local color, accent = CombatService.ColorsOf(attacker)

	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	CombatService.FX("Projectile", { Id = id, Origin = origin, Direction = dir, Speed = speed, Range = range, Color = color, Accent = accent })

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local step = math.min(speed * dt, range - traveled)
		local function finish(at: Vector3)
			connection:Disconnect()
			CombatService.FX("ProjectileEnd", { Id = id, Position = at, Color = color, Accent = accent })
		end
		if step <= 0 then
			finish(position)
			return
		end
		local hits = CombatService.QueryLine(attacker, position, dir, step, radius * 2)
		if #hits > 0 then
			local nearest, best = hits[1], math.huge
			for _, target in hits do
				local along = (target.Root.Position - position):Dot(dir)
				if along < best then
					nearest, best = target, along
				end
			end
			finish(nearest.Root.Position)
			task.spawn(onHit, nearest, nearest.Root.Position)
			return
		end
		local wall = Workspace:Raycast(position, dir * step, params)
		if wall then
			finish(wall.Position)
			return
		end
		position += dir * step
		traveled += step
	end)
end

--------------------------------------------------------------------------------
-- FX
--------------------------------------------------------------------------------

function CombatService.FX(kind: string, params: { [string]: any })
	Remotes.CombatFX:FireAllClients(kind, params)
end

return CombatService
