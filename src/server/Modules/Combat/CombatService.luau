-- CombatService
-- Server-authoritative combat primitives:
--   * Targets: every living player outside the safe zone (the Dawn Gate plaza).
--   * Queries: sphere, cone, line and moving sweeps over those targets.
--   * Damage: blocking (front arc, guard meter, guard break), i-frames, Aegis
--     shields (absorb + reflect), beast armour, knockback (LinearVelocity),
--     stun, combo counting, kill credit.
--   * Server-simulated projectiles (straight, piercing, homing, returning),
--     mirrored on every client.
--   * FX broadcast. Every effect carries the attacker's gem colours.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local GemKits = require(ReplicatedStorage:WaitForChild("GemKits"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))

local Modules = script.Parent.Parent
local Remotes = require(Modules:WaitForChild("Remotes"))

local STATUS = CombatConfig.Status
local PA = CombatConfig.PlayerAttributes
local BODY_RADIUS = 2

local CombatService = {}

CombatService.Damaged = Signal.new() -- (attacker: Player?, target: Target, amount)

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

function CombatService.KitOf(player: Player): GemKits.Kit
	return GemKits.Get(player:GetAttribute("EquippedGem"))
end

--------------------------------------------------------------------------------
-- Safe zone (Map.Lobby: attributes Center, Radius)
--------------------------------------------------------------------------------

local safeCenter: Vector3? = nil
local safeRadius = 0
local function refreshSafeZone()
	local map = Workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	local center = lobby and lobby:GetAttribute("Center")
	local radius = lobby and lobby:GetAttribute("Radius")
	if typeof(center) == "Vector3" and type(radius) == "number" then
		safeCenter = center
		safeRadius = radius + CombatConfig.SafeZone.ExtraRadius
	else
		safeCenter = nil
	end
end

function CombatService.InSafeZone(position: Vector3): boolean
	if not CombatConfig.SafeZone.Enabled then
		return false
	end
	if not safeCenter then
		refreshSafeZone()
	end
	local center = safeCenter
	if not center then
		return false
	end
	local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	return flat.Magnitude <= safeRadius and math.abs(position.Y - center.Y) < 40
end

--------------------------------------------------------------------------------
-- Targets
--------------------------------------------------------------------------------

-- A living fighter (not shattered, not in the safe zone).
function CombatService.ToTarget(player: Player): Target?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return nil
	end
	if character:GetAttribute(STATUS.Shattered) == true or player:GetAttribute(PA.InSafeZone) == true then
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

-- Beasts are big: hits connect from further away.
local function reachOf(target: Target): number
	local beast = target.Character:GetAttribute(STATUS.Beast)
	return if beast then BODY_RADIUS * 2.5 else BODY_RADIUS
end

function CombatService.QuerySphere(attacker: Player, center: Vector3, radius: number): { Target }
	local result = {}
	for _, target in candidates(attacker) do
		if (target.Root.Position - center).Magnitude <= radius + reachOf(target) then
			table.insert(result, target)
		end
	end
	return result
end

function CombatService.QueryCone(attacker: Player, origin: Vector3, direction: Vector3, range: number, arc: number): { Target }
	local forward = CombatService.FlatUnit(direction)
	local cosHalf = math.cos(math.rad(math.min(arc, 359) / 2))
	local result = {}
	for _, target in candidates(attacker) do
		local offset = target.Root.Position - origin
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude <= range + reachOf(target) and math.abs(offset.Y) < 10 then
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
		if (target.Root.Position - (origin + dir * along)).Magnitude <= width / 2 + reachOf(target) then
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

-- Ground point below a position (parts only; characters and effects ignored).
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
function CombatService.Ground(position: Vector3): Vector3
	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), groundParams)
	return if hit then hit.Position else position - Vector3.new(0, 3, 0)
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
	-- Beasts barely budge.
	if target.Character:GetAttribute(STATUS.Beast) then
		velocity *= 0.35
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
	-- The flight continues after the force ends; let MovementGuard know.
	CombatService.Extend(target.Character, STATUS.MoveGraceUntil, (duration or 0.22) + 1.2)
end

function CombatService.Heal(target: Target, amount: number)
	local humanoid = target.Humanoid
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
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
	NoReflect: boolean?,
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

local function markCombat(player: Player)
	player:SetAttribute(PA.LastCombat, now())
end

-- Applies a hit. Returns the damage actually dealt.
function CombatService.Hit(attacker: Player, target: Target, amount: number, options: HitOptions?): number
	local opts = options or {}
	local character = target.Character
	if CombatService.IsActive(character, STATUS.InvulnerableUntil) or target.Humanoid.Health <= 0 then
		return 0
	end
	local attackerRoot = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	local from = opts.FromPosition or (attackerRoot and (attackerRoot :: BasePart).Position) or target.Root.Position
	local color, accent = CombatService.ColorsOf(attacker)
	markCombat(attacker)
	markCombat(target.Player)

	-- Blocking
	if not opts.Unblockable and isBlockingHit(target, from) then
		local guard = (character:GetAttribute(STATUS.Guard) or CombatConfig.Block.MaxGuard) - amount * CombatConfig.Block.GuardPerDamage
		if guard <= 0 then
			character:SetAttribute(STATUS.Guard, 0)
			CombatService.Stun(target, CombatConfig.Block.BreakStun)
			CombatService.FX("GuardBreak", { Target = character, Color = color, Accent = accent })
		else
			character:SetAttribute(STATUS.Guard, guard)
			CombatService.FX("Block", { Target = character, From = from, Color = color, Accent = accent })
			opts = { FromPosition = from }
		end
		amount *= CombatConfig.Block.DamageTaken
	end

	-- Hex: cursed fighters take extra damage.
	if CombatService.IsActive(character, STATUS.CursedUntil) then
		amount *= 1 + (character:GetAttribute(STATUS.CurseAmp) or 0) / 100
	end

	-- Beast armour
	local beastId = character:GetAttribute(STATUS.Beast)
	local beast = beastId and GemKits.Beasts[beastId]
	if beast then
		amount *= beast.DamageTaken
	end

	-- Aegis shield: absorbs first and reflects part of the hit.
	local shield = character:GetAttribute(STATUS.ShieldHP) or 0
	if shield > 0 and CombatService.IsActive(character, STATUS.ShieldUntil) then
		local absorbed = math.min(shield, amount)
		character:SetAttribute(STATUS.ShieldHP, shield - absorbed)
		amount -= absorbed
		CombatService.FX("ShieldHit", { Target = character, Color = CombatService.ColorsOf(target.Player) })
		local reflect = character:GetAttribute("ShieldReflect") or 0
		if not opts.NoReflect and reflect > 0 and attacker ~= target.Player then
			local back = CombatService.ToTarget(attacker)
			if back then
				task.defer(CombatService.Hit, target.Player, back, absorbed * reflect, { NoReflect = true, Unblockable = true })
			end
		end
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
		Target = character,
		Position = target.Root.Position,
		Amount = math.floor(dealt * 10 + 0.5) / 10,
		Color = color,
		Accent = accent,
		Heavy = opts.Knockback ~= nil and opts.Knockback.Magnitude > 30,
		Attacker = if attacker then attacker.Character else nil, -- for the attacker's impact frame
	})
	CombatService.Damaged:Fire(attacker, target, dealt)
	return dealt
end

-- Who last hurt this player recently (kill credit for falls and the like).
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

export type ProjectileOptions = {
	Speed: number,
	Range: number,
	Radius: number,
	Shape: string?,
	Pierce: boolean?, -- keeps flying through targets (each hit once)
	Homing: boolean?, -- steers toward the nearest foe ahead
	Return: boolean?, -- flies out, then back to the caster (hits again on the way back)
}

local projectileId = 0

-- Simulated on the server; clients draw the same path (with steering updates
-- for homing / returning shots). onHit(target, position) per hit.
function CombatService.Projectile(attacker: Player, origin: Vector3, direction: Vector3, opts: ProjectileOptions, onHit: (Target, Vector3) -> ())
	projectileId += 1
	local id = projectileId
	local dir = direction.Unit
	local position = origin
	local traveled = 0
	local returning = false
	local color, accent = CombatService.ColorsOf(attacker)
	local hitOnce: { [Player]: boolean } = {}
	local steerAt = 0

	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	CombatService.FX("Projectile", {
		Id = id,
		Time = now(),
		Origin = origin,
		Direction = dir,
		Speed = opts.Speed,
		Range = opts.Range * (if opts.Return then 2 else 1),
		Shape = opts.Shape or "Shard",
		Steered = opts.Homing or opts.Return,
		Color = color,
		Accent = accent,
	})

	local connection
	local function finish(at: Vector3)
		connection:Disconnect()
		CombatService.FX("ProjectileEnd", { Id = id, Position = at, Color = color, Accent = accent })
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		local casterRoot = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")

		-- Steering
		if opts.Homing then
			local best, bestDistance = nil, 45
			for _, target in candidates(attacker) do
				local offset = target.Root.Position - position
				if offset.Magnitude < bestDistance and offset.Unit:Dot(dir) > 0.1 then
					best, bestDistance = target, offset.Magnitude
				end
			end
			if best then
				local want = (best.Root.Position - position).Unit
				dir = (dir + (want - dir) * math.min(1, dt * 4)).Unit
			end
		elseif returning and casterRoot then
			local back = (casterRoot :: BasePart).Position - position
			if back.Magnitude < 3 then
				finish(position)
				return
			end
			dir = back.Unit
		end
		if (opts.Homing or opts.Return) and os.clock() >= steerAt then
			steerAt = os.clock() + 0.1
			CombatService.FX("ProjectileSteer", { Id = id, Position = position, Direction = dir })
		end

		local step = opts.Speed * dt
		if not returning then
			step = math.min(step, opts.Range - traveled)
		end
		if step <= 0 then
			if opts.Return and not returning then
				returning = true
				hitOnce = {}
				return
			end
			finish(position)
			return
		end

		local hits = CombatService.QueryLine(attacker, position, dir, step, opts.Radius * 2)
		if #hits > 0 then
			if opts.Pierce or opts.Return then
				for _, target in hits do
					if not hitOnce[target.Player] then
						hitOnce[target.Player] = true
						task.spawn(onHit, target, target.Root.Position)
					end
				end
			else
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
		end
		if not returning then
			local wall = Workspace:Raycast(position, dir * step, params)
			if wall then
				if opts.Return then
					returning = true
					hitOnce = {}
				else
					finish(wall.Position)
					return
				end
			end
		end
		position += dir * step
		traveled += step
		if traveled > opts.Range * 3 then
			finish(position)
		end
	end)
end

--------------------------------------------------------------------------------
-- FX
--------------------------------------------------------------------------------

function CombatService.FX(kind: string, params: { [string]: any })
	Remotes.CombatFX:FireAllClients(kind, params)
end

return CombatService
