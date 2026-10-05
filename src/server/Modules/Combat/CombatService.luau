-- CombatService
-- Server-authoritative combat primitives shared by every weapon skill:
--   * Target queries: sphere, cone, line, first-in-line, moving sweeps.
--   * Damage with gem Power/Defense scaling, buffs, shields and dodges.
--   * Status effects (stun, freeze, root, slow, burn) as replicated
--     timestamp attributes (CombatConfig.Status) the client honours.
--   * Knockback via LinearVelocity (works on client-owned characters).
--   * Server-simulated projectiles, mirrored visually on clients.
--   * FX broadcast to clients (rendered by the client VFX module).
--
-- Rules: allies can't hurt each other, nobody takes PvP damage in safe zones
-- (hub, homes), training dummies are always hittable.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))
local TerritoryConfig = require(ReplicatedStorage:WaitForChild("TerritoryConfig"))

local Modules = script.Parent.Parent
local GemDataManager = require(Modules:WaitForChild("GemDataManager"))
local Remotes = require(Modules:WaitForChild("Remotes"))

local STATUS = CombatConfig.Status
local BODY_RADIUS = 2 -- treat characters as ~2 stud radius for hit tests

local CombatService = {}

CombatService.Damaged = Signal.new() -- (attackerPlayer?, target, amount)
CombatService.Defeated = Signal.new() -- (attackerPlayer?, target)

export type Attacker = {
	Player: Player?,
	Character: Model,
}

export type Target = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Player: Player?,
	IsDummy: boolean,
}

--------------------------------------------------------------------------------
-- Folders for server-made combat objects
--------------------------------------------------------------------------------

local function folder(name: string): Folder
	local existing = Workspace:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = Workspace
	return f
end

CombatService.WallsFolder = folder("CombatWalls") -- solid: blocks bodies + projectiles
CombatService.FXFolder = folder("CombatFX") -- non-solid server objects (turrets)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end
CombatService.Now = now

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatUnit(v: Vector3, fallback: Vector3?): Vector3
	local f = flat(v)
	if f.Magnitude < 1e-3 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return f.Unit
end
CombatService.FlatUnit = flatUnit

function CombatService.ToTarget(model: Instance?): Target?
	if not model or not model:IsA("Model") then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return nil
	end
	return {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Player = Players:GetPlayerFromCharacter(model),
		IsDummy = CollectionService:HasTag(model, CombatConfig.Tags.Dummy),
	}
end

local function candidates(): { Target }
	local list = {}
	for _, player in Players:GetPlayers() do
		local target = CombatService.ToTarget(player.Character)
		if target then
			table.insert(list, target)
		end
	end
	for _, dummy in CollectionService:GetTagged(CombatConfig.Tags.Dummy) do
		local target = CombatService.ToTarget(dummy)
		if target then
			table.insert(list, target)
		end
	end
	return list
end

local function inSafeZone(position: Vector3): boolean
	local location = TerritoryConfig.GetLocationAt(position)
	return location ~= nil and CombatConfig.SafeZones[location] == true
end

function CombatService.CanHit(attacker: Attacker, target: Target): boolean
	if target.Model == attacker.Character or target.Humanoid.Health <= 0 then
		return false
	end
	if target.Model:GetAttribute(STATUS.Puffed) then
		return false
	end
	if target.IsDummy then
		return true
	end
	if attacker.Player and target.Player and GemDataManager.AreAllies(attacker.Player, target.Player) then
		return false
	end
	local attackerRoot = attacker.Character:FindFirstChild("HumanoidRootPart")
	if inSafeZone(target.Root.Position) or (attackerRoot and inSafeZone(attackerRoot.Position)) then
		return false
	end
	return true
end

function CombatService.IsAlly(attacker: Attacker, model: Model): boolean
	local player = Players:GetPlayerFromCharacter(model)
	if model == attacker.Character then
		return true
	end
	return attacker.Player ~= nil and player ~= nil and GemDataManager.AreAllies(attacker.Player, player)
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function CombatService.QuerySphere(attacker: Attacker, center: Vector3, radius: number): { Target }
	local result = {}
	for _, target in candidates() do
		if (target.Root.Position - center).Magnitude <= radius + BODY_RADIUS and CombatService.CanHit(attacker, target) then
			table.insert(result, target)
		end
	end
	return result
end

-- Horizontal cone in front of origin.
function CombatService.QueryCone(attacker: Attacker, origin: Vector3, direction: Vector3, range: number, arcDegrees: number): { Target }
	local forward = flatUnit(direction)
	local cosHalf = math.cos(math.rad(arcDegrees / 2))
	local result = {}
	for _, target in candidates() do
		local offset = target.Root.Position - origin
		local horizontal = flat(offset)
		local distance = horizontal.Magnitude
		if distance <= range + BODY_RADIUS and math.abs(offset.Y) < 10 then
			-- Point-blank targets always count; otherwise check the angle.
			local inArc = distance < 3 or horizontal.Unit:Dot(forward) >= cosHalf
			if inArc and CombatService.CanHit(attacker, target) then
				table.insert(result, target)
			end
		end
	end
	return result
end

-- Capsule from origin along direction.
function CombatService.QueryLine(attacker: Attacker, origin: Vector3, direction: Vector3, length: number, width: number): { Target }
	local dir = direction.Unit
	local result = {}
	for _, target in candidates() do
		local offset = target.Root.Position - origin
		local along = math.clamp(offset:Dot(dir), 0, length)
		local closest = origin + dir * along
		if (target.Root.Position - closest).Magnitude <= width / 2 + BODY_RADIUS and CombatService.CanHit(attacker, target) then
			table.insert(result, target)
		end
	end
	return result
end

function CombatService.FirstInLine(attacker: Attacker, origin: Vector3, direction: Vector3, length: number, width: number): Target?
	local dir = direction.Unit
	local best, bestAlong = nil, math.huge
	for _, target in CombatService.QueryLine(attacker, origin, direction, length, width) do
		local along = (target.Root.Position - origin):Dot(dir)
		if along < bestAlong then
			best, bestAlong = target, along
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Status effects
--------------------------------------------------------------------------------

local function extend(model: Model, attribute: string, duration: number)
	local current = model:GetAttribute(attribute) or 0
	model:SetAttribute(attribute, math.max(current, now() + duration))
end

function CombatService.IsActive(model: Model, attribute: string): boolean
	return (model:GetAttribute(attribute) or 0) > now()
end

function CombatService.Stun(target: Target, duration: number)
	extend(target.Model, STATUS.StunnedUntil, duration)
end

function CombatService.Freeze(target: Target, duration: number)
	extend(target.Model, STATUS.FrozenUntil, duration)
	extend(target.Model, STATUS.StunnedUntil, duration)
	CombatService.FX("Freeze", { Target = target.Model, Duration = duration })
end

function CombatService.Root(target: Target, duration: number)
	extend(target.Model, STATUS.RootedUntil, duration)
end

function CombatService.Slow(target: Target, multiplier: number, duration: number)
	local model = target.Model
	local active = CombatService.IsActive(model, STATUS.SlowUntil)
	local current = if active then model:GetAttribute(STATUS.SlowMult) or 1 else 1
	model:SetAttribute(STATUS.SlowMult, math.min(current, multiplier))
	extend(model, STATUS.SlowUntil, duration)
end

function CombatService.GiveShield(model: Model, amount: number, duration: number)
	model:SetAttribute(STATUS.Shield, math.max(model:GetAttribute(STATUS.Shield) or 0, amount))
	model:SetAttribute(STATUS.ShieldUntil, now() + duration)
end

function CombatService.GiveDamageBuff(model: Model, multiplier: number, duration: number)
	model:SetAttribute(STATUS.DamageMult, multiplier)
	model:SetAttribute(STATUS.DamageMultUntil, now() + duration)
end

function CombatService.Knockback(target: Target, velocity: Vector3, duration: number?)
	local attachment = Instance.new("Attachment")
	attachment.Name = "KnockbackAttachment"
	attachment.Parent = target.Root

	local force = Instance.new("LinearVelocity")
	force.Name = "Knockback"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	force.MaxForce = math.huge
	force.VectorVelocity = velocity
	force.Parent = target.Root

	Debris:AddItem(force, duration or 0.25)
	Debris:AddItem(attachment, duration or 0.25)
end

-- Pull toward a point, stopping `stopDistance` short of it.
function CombatService.PullTo(target: Target, point: Vector3, stopDistance: number, speed: number)
	local offset = point - target.Root.Position
	local distance = offset.Magnitude - stopDistance
	if distance <= 1 then
		return
	end
	CombatService.Knockback(target, offset.Unit * speed + Vector3.new(0, 6, 0), distance / speed)
end

local burning: { [Model]: { EndsAt: number, Dps: number, Attacker: Attacker } } = {}

function CombatService.Burn(attacker: Attacker, target: Target, dps: number, duration: number)
	local model = target.Model
	local existing = burning[model]
	if existing then
		existing.EndsAt = math.max(existing.EndsAt, now() + duration)
		existing.Dps = math.max(existing.Dps, dps)
		return
	end
	local entry = { EndsAt = now() + duration, Dps = dps, Attacker = attacker }
	burning[model] = entry
	CombatService.FX("Aura", { Target = model, Color = Color3.fromRGB(255, 140, 60), Duration = duration, Style = "Fire" })
	task.spawn(function()
		while now() < entry.EndsAt and model.Parent do
			task.wait(0.5)
			local current = CombatService.ToTarget(model)
			if not current then
				break
			end
			CombatService.Damage(entry.Attacker, current, entry.Dps * 0.5, { Silent = true, IgnoreDodge = true })
		end
		burning[model] = nil
	end)
end

--------------------------------------------------------------------------------
-- Damage
--------------------------------------------------------------------------------

local function gemStats(model: Model)
	local gemType = model:GetAttribute(GemConfig.Attributes.GemType)
	local info = gemType and GemConfig.GemTypes[gemType]
	return if info then info.BaseStats else nil
end

export type DamageOptions = {
	Multiplier: number?,
	Knockback: Vector3?,
	KnockbackTime: number?,
	Stun: number?,
	Freeze: number?,
	Root: number?,
	Slow: { Mult: number, Time: number }?,
	Burn: { Dps: number, Time: number }?,
	Silent: boolean?, -- no damage number
	IgnoreDodge: boolean?,
	Color: Color3?,
}

function CombatService.Damage(attacker: Attacker, target: Target, base: number, options: DamageOptions?): number
	local opts = options or {}
	if not CombatService.CanHit(attacker, target) then
		return 0
	end
	local model = target.Model

	-- Foresight-style dodge: consume it and blink away from the attacker.
	if not opts.IgnoreDodge and CombatService.IsActive(model, STATUS.DodgeUntil) then
		model:SetAttribute(STATUS.DodgeUntil, 0)
		local attackerRoot = attacker.Character:FindFirstChild("HumanoidRootPart")
		local away = if attackerRoot then flatUnit(target.Root.Position - attackerRoot.Position) else -target.Root.CFrame.LookVector
		local distance = model:GetAttribute("DodgeBlink") or 12
		local from = target.Root.Position
		model:PivotTo(model:GetPivot() + away * distance)
		CombatService.FX("Line", { From = from, To = from + away * distance, Color = Color3.fromRGB(200, 240, 255), Width = 3, Duration = 0.4 })
		CombatService.FX("Burst", { Position = from, Radius = 5, Color = Color3.fromRGB(200, 240, 255) })
		CombatService.FXTo({ attacker.Player, target.Player }, "Damage", { Target = model, Text = "DODGE", Color = Color3.fromRGB(200, 240, 255) })
		return 0
	end

	-- Scaling
	local amount = base * (opts.Multiplier or 1)
	local attackerStats = gemStats(attacker.Character)
	if attackerStats then
		amount *= 1 + (attackerStats.Power - CombatConfig.PowerBaseline) * CombatConfig.PowerPerPoint
	end
	if CombatService.IsActive(attacker.Character, STATUS.DamageMultUntil) then
		amount *= attacker.Character:GetAttribute(STATUS.DamageMult) or 1
	end
	local targetStats = gemStats(model)
	if targetStats then
		amount *= math.max(CombatConfig.MinDefenseScale, 1 - (targetStats.Defense - CombatConfig.DefenseBaseline) * CombatConfig.DefensePerPoint)
	end
	amount = math.max(1, math.floor(amount + 0.5))

	-- Shield absorbs first
	local absorbed = 0
	if CombatService.IsActive(model, STATUS.ShieldUntil) then
		local shield = model:GetAttribute(STATUS.Shield) or 0
		absorbed = math.min(shield, amount)
		model:SetAttribute(STATUS.Shield, shield - absorbed)
		if shield - absorbed <= 0 then
			model:SetAttribute(STATUS.ShieldUntil, 0)
		end
	end
	local dealt = amount - absorbed

	local humanoid = target.Humanoid
	local before = humanoid.Health
	humanoid.Health = math.max(0, before - dealt)
	if attacker.Player then
		model:SetAttribute("LastAttackerId", attacker.Player.UserId)
	end

	if not opts.Silent or dealt > 0 then
		CombatService.FXTo({ attacker.Player, target.Player }, "Damage", {
			Target = model,
			Amount = dealt,
			Absorbed = absorbed,
			Color = opts.Color,
		})
	end

	-- Effects
	if opts.Knockback then
		CombatService.Knockback(target, opts.Knockback, opts.KnockbackTime)
	end
	if opts.Stun then
		CombatService.Stun(target, opts.Stun)
	end
	if opts.Freeze then
		CombatService.Freeze(target, opts.Freeze)
	end
	if opts.Root then
		CombatService.Root(target, opts.Root)
	end
	if opts.Slow then
		CombatService.Slow(target, opts.Slow.Mult, opts.Slow.Time)
	end
	if opts.Burn then
		CombatService.Burn(attacker, target, opts.Burn.Dps, opts.Burn.Time)
	end

	CombatService.Damaged:Fire(attacker.Player, target, dealt)
	if before > 0 and humanoid.Health <= 0 then
		if attacker.Player and target.Player then
			GemDataManager.IncrementStat(attacker.Player, "PuffsInflicted")
			GemDataManager.IncrementStat(target.Player, "TimesPuffed")
		end
		CombatService.Defeated:Fire(attacker.Player, target)
	end
	return dealt
end

--------------------------------------------------------------------------------
-- Sweeps
--------------------------------------------------------------------------------

-- Repeatedly tests a sphere around getCenter() for `duration`, calling onHit
-- once per target (or every rehitInterval seconds if given).
function CombatService.Sweep(attacker: Attacker, getCenter: () -> Vector3?, radius: number, duration: number, onHit: (Target) -> (), rehitInterval: number?)
	local lastHit: { [Model]: number } = {}
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local center = getCenter()
		if not center or os.clock() - started > duration or not attacker.Character.Parent then
			connection:Disconnect()
			return
		end
		for _, target in CombatService.QuerySphere(attacker, center, radius) do
			local last = lastHit[target.Model]
			if not last or (rehitInterval and os.clock() - last >= rehitInterval) then
				lastHit[target.Model] = os.clock()
				task.spawn(onHit, target)
			end
		end
	end)
end

-- A wall of effect moving along a lane (e.g. a tidal wave). Hits each target once.
function CombatService.MovingSweep(attacker: Attacker, origin: Vector3, direction: Vector3, length: number, width: number, speed: number, onHit: (Target) -> ())
	local dir = flatUnit(direction)
	local right = dir:Cross(Vector3.yAxis)
	local hit: { [Model]: boolean } = {}
	local traveled = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		traveled += speed * dt
		if traveled > length then
			connection:Disconnect()
			return
		end
		for _, target in candidates() do
			if not hit[target.Model] then
				local offset = target.Root.Position - origin
				local along = offset:Dot(dir)
				local lateral = math.abs(offset:Dot(right))
				if math.abs(along - traveled) <= 6 and lateral <= width / 2 + BODY_RADIUS and math.abs(offset.Y) < 14 and CombatService.CanHit(attacker, target) then
					hit[target.Model] = true
					task.spawn(onHit, target)
				end
			end
		end
	end)
end

-- Yields until the character is back on the ground (or maxTime passes).
function CombatService.WaitForLanding(character: Model, maxTime: number): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	local started = os.clock()
	task.wait(0.3) -- let the leap leave the ground first
	while os.clock() - started < maxTime do
		if humanoid.Health <= 0 or not character.Parent then
			return false
		end
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			return true
		end
		task.wait()
	end
	return true
end

--------------------------------------------------------------------------------
-- Projectiles
--------------------------------------------------------------------------------

export type ProjectileSpec = {
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Range: number,
	Radius: number,
	Color: Color3,
	Size: number?,
	Style: string?,
}

local projectileId = 0

-- Simulates a projectile on the server; clients draw the same path.
-- onHit(target, position) for the first valid target; onImpact(position) when
-- it hits world geometry or expires.
function CombatService.Projectile(attacker: Attacker, spec: ProjectileSpec, onHit: (Target, Vector3) -> (), onImpact: ((Vector3) -> ())?)
	projectileId += 1
	local id = projectileId
	local dir = spec.Direction.Unit
	local position = spec.Origin
	local traveled = 0

	local exclude: { Instance } = { attacker.Character, CombatService.FXFolder }
	for _, target in candidates() do
		table.insert(exclude, target.Model)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true

	CombatService.FX("Projectile", {
		Id = id,
		Origin = spec.Origin,
		Direction = dir,
		Speed = spec.Speed,
		Range = spec.Range,
		Color = spec.Color,
		Size = spec.Size or 1.6,
		Style = spec.Style,
	})

	local function finish(at: Vector3)
		CombatService.FX("ProjectileEnd", { Id = id, Position = at, Color = spec.Color })
	end

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local step = math.min(spec.Speed * dt, spec.Range - traveled)
		if step <= 0 then
			connection:Disconnect()
			finish(position)
			if onImpact then
				task.spawn(onImpact, position)
			end
			return
		end

		local target = CombatService.FirstInLine(attacker, position, dir, step, spec.Radius * 2)
		if target then
			connection:Disconnect()
			finish(target.Root.Position)
			task.spawn(onHit, target, target.Root.Position)
			return
		end

		local result = Workspace:Raycast(position, dir * step, params)
		if result then
			connection:Disconnect()
			finish(result.Position)
			if onImpact then
				task.spawn(onImpact, result.Position)
			end
			return
		end

		position += dir * step
		traveled += step
	end)
end

--------------------------------------------------------------------------------
-- FX broadcast
--------------------------------------------------------------------------------

function CombatService.FX(kind: string, params: { [string]: any })
	Remotes.WeaponFX:FireAllClients(kind, params)
end

function CombatService.FXTo(players: { Player? }, kind: string, params: { [string]: any })
	local sent: { [Player]: boolean } = {}
	for i = 1, 2 do
		local player = players[i]
		if player and not sent[player] and player.Parent == Players then
			sent[player] = true
			Remotes.WeaponFX:FireClient(player, kind, params)
		end
	end
end

return CombatService
