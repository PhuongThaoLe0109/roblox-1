-- Skills
-- Server logic for every skill archetype in GemKits. Each function receives
-- a context and resolves hits; the visuals are broadcast as CombatFX events
-- (drawn by the client's CombatFX in the caster's gem colours and element).
-- Self-movement (Rush, Quake leap) is applied by the caster's own client; the
-- server sweeps the caster's replicated position. Blink is done here.
--
--   ctx = { Player, Character, Root, Aim (flat unit), AimPoint, Skill, Kit }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local STATUS = CombatConfig.Status

local Skills = {}

export type Context = {
	Player: Player,
	Character: Model,
	Root: BasePart,
	Aim: Vector3,
	AimPoint: Vector3,
	Skill: { [string]: any },
	Kit: any,
}

local function fx(ctx: Context, kind: string, params: { [string]: any })
	local color, accent = CombatService.ColorsOf(ctx.Player)
	params.Caster = ctx.Character
	params.Color = color
	params.Accent = accent
	params.Element = ctx.Kit.Element
	CombatService.FX(kind, params)
end

local function alive(ctx: Context): boolean
	local humanoid = ctx.Character:FindFirstChildOfClass("Humanoid")
	return ctx.Root.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0 and not CombatService.IsActive(ctx.Character, STATUS.StunnedUntil)
end

local function chest(ctx: Context): Vector3
	return ctx.Root.Position + Vector3.new(0, 1.2, 0) + ctx.Aim * 2
end

-- Target point on the ground, clamped to the skill's range.
local function targetPoint(ctx: Context, range: number): Vector3
	local offset = ctx.AimPoint - ctx.Root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > range then
		flat = flat.Unit * range
	end
	return CombatService.Ground(ctx.Root.Position + flat + Vector3.new(0, 4, 0))
end

local function rotate(dir: Vector3, degrees: number): Vector3
	return CFrame.fromAxisAngle(Vector3.yAxis, math.rad(degrees)):VectorToWorldSpace(dir)
end

--------------------------------------------------------------------------------
-- Projectiles
--------------------------------------------------------------------------------

function Skills.Volley(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "Cast", { Direction = ctx.Aim })
	local half = (s.Count - 1) / 2
	for i = 0, s.Count - 1 do
		local direction = rotate(ctx.Aim, (i - half) * s.Spread)
		CombatService.Projectile(ctx.Player, chest(ctx), direction, { Speed = s.Speed, Range = s.Range, Radius = s.Radius, Shape = s.Shape }, function(target)
			CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = direction * 20 + Vector3.new(0, 8, 0), Stun = 0.2 })
		end)
	end
end

function Skills.Lance(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "Cast", { Direction = ctx.Aim, Heavy = true })
	task.wait(0.12)
	if not alive(ctx) then
		return
	end
	CombatService.Projectile(ctx.Player, chest(ctx), ctx.Aim, { Speed = s.Speed, Range = s.Range, Radius = s.Radius, Shape = "Lance", Pierce = true }, function(target)
		CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = ctx.Aim * 40 + Vector3.new(0, 12, 0), Stun = 0.4 })
	end)
end

function Skills.Orbs(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "Cast", { Direction = ctx.Aim })
	for i = 1, s.Count do
		local direction = rotate(ctx.Aim, (i - (s.Count + 1) / 2) * 30) + Vector3.new(0, 0.25, 0)
		CombatService.Projectile(ctx.Player, chest(ctx) + Vector3.new(0, 1, 0), direction, { Speed = s.Speed, Range = s.Range, Radius = s.Radius, Shape = "Orb", Homing = true }, function(target)
			CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = Vector3.new(0, 14, 0), Stun = 0.25 })
		end)
		task.wait(0.08)
	end
end

function Skills.Boomerang(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "Cast", { Direction = ctx.Aim })
	CombatService.Projectile(ctx.Player, chest(ctx), ctx.Aim, { Speed = s.Speed, Range = s.Range, Radius = s.Radius, Shape = "Disc", Return = true }, function(target)
		CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = ctx.Aim * 18 + Vector3.new(0, 10, 0), Stun = 0.3 })
	end)
end

--------------------------------------------------------------------------------
-- Area attacks at a point
--------------------------------------------------------------------------------

function Skills.Rain(ctx: Context)
	local s = ctx.Skill
	local center = targetPoint(ctx, s.Range)
	local seed = math.random(1, 2 ^ 30)
	local rng = Random.new(seed)
	local drops = {}
	for i = 1, s.Count do
		local a = rng:NextNumber() * math.pi * 2
		local r = math.sqrt(rng:NextNumber()) * s.Radius
		drops[i] = { Offset = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), At = (i - 1) / s.Count * s.Duration }
	end
	fx(ctx, "Rain", { Center = center, Radius = s.Radius, Count = s.Count, Duration = s.Duration, Seed = seed })
	local hits: { [Player]: number } = {}
	for _, drop in drops do
		task.delay(0.45 + drop.At, function()
			for _, target in CombatService.QuerySphere(ctx.Player, center + drop.Offset, 4) do
				local n = hits[target.Player] or 0
				if n < 4 then
					hits[target.Player] = n + 1
					CombatService.Hit(ctx.Player, target, s.Damage, { Stun = 0.2, FromPosition = center })
				end
			end
		end)
	end
end

function Skills.Meteor(ctx: Context)
	local s = ctx.Skill
	local center = targetPoint(ctx, s.Range)
	fx(ctx, "Meteor", { Center = center, Radius = s.Radius, Delay = s.Delay })
	task.wait(s.Delay)
	for _, target in CombatService.QuerySphere(ctx.Player, center, s.Radius) do
		local away = CombatService.FlatUnit(target.Root.Position - center)
		CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = away * 80 + Vector3.new(0, 45, 0), KnockbackTime = 0.3, Stun = 0.9, FromPosition = center })
	end
end

function Skills.Vortex(ctx: Context)
	local s = ctx.Skill
	local center = targetPoint(ctx, s.Range) + Vector3.new(0, 2, 0)
	fx(ctx, "Vortex", { Center = center, Radius = s.Radius, Duration = s.Duration })
	for _ = 1, s.Ticks do
		task.wait(s.Duration / s.Ticks)
		for _, target in CombatService.QuerySphere(ctx.Player, center, s.Radius) do
			local inward = center - target.Root.Position
			local pull = if inward.Magnitude > 1 then inward.Unit * math.min(30, inward.Magnitude * 3) else Vector3.zero
			CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = pull + Vector3.new(0, 6, 0), KnockbackTime = 0.18, Stun = 0.3, FromPosition = center })
		end
	end
	fx(ctx, "VortexBurst", { Center = center, Radius = s.Radius })
	for _, target in CombatService.QuerySphere(ctx.Player, center, s.Radius) do
		local away = CombatService.FlatUnit(target.Root.Position - center)
		CombatService.Hit(ctx.Player, target, s.Burst, { Knockback = away * 60 + Vector3.new(0, 40, 0), KnockbackTime = 0.3, Stun = 0.6, FromPosition = center })
	end
end

function Skills.Trap(ctx: Context)
	local s = ctx.Skill
	local center = targetPoint(ctx, s.Range)
	fx(ctx, "Trap", { Center = center, Radius = s.Radius, Delay = s.Delay, Stun = s.Stun })
	task.wait(s.Delay)
	for _, target in CombatService.QuerySphere(ctx.Player, center, s.Radius) do
		CombatService.Hit(ctx.Player, target, s.Damage, { Stun = s.Stun, FromPosition = center, Unblockable = true })
		target.Root.AssemblyLinearVelocity = Vector3.zero
		fx(ctx, "Frozen", { Target = target.Character, Duration = s.Stun })
	end
end

--------------------------------------------------------------------------------
-- Close range
--------------------------------------------------------------------------------

function Skills.Launcher(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "Launcher", { Direction = ctx.Aim, Range = s.Range })
	task.wait(0.08)
	if not alive(ctx) then
		return
	end
	for _, target in CombatService.QueryCone(ctx.Player, ctx.Root.Position, ctx.Aim, s.Range, s.Arc) do
		CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = Vector3.new(0, s.Launch, 0) + ctx.Aim * 8, KnockbackTime = 0.3, Stun = s.Stun })
	end
end

function Skills.Rush(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "Rush", { Direction = ctx.Aim, Duration = s.Duration })
	CombatService.Sweep(ctx.Player, function()
		return if ctx.Root.Parent then ctx.Root.Position else nil
	end, s.Radius, s.Duration + 0.12, function(target)
		CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = ctx.Aim * s.Knockback + Vector3.new(0, 16, 0), KnockbackTime = 0.2, Stun = 0.5 })
	end)
end

function Skills.Spin(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "Spin", { Duration = s.Duration, Radius = s.Radius })
	for i = 1, s.Hits do
		task.wait(s.Duration / s.Hits)
		if not alive(ctx) then
			return
		end
		for _, target in CombatService.QuerySphere(ctx.Player, ctx.Root.Position, s.Radius) do
			local last = i == s.Hits
			local away = CombatService.FlatUnit(target.Root.Position - ctx.Root.Position)
			CombatService.Hit(ctx.Player, target, s.Damage, {
				Knockback = if last then away * 45 + Vector3.new(0, 20, 0) else away * 4,
				Stun = if last then 0.5 else 0.25,
			})
		end
	end
end

function Skills.Slam(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "SlamLeap", { Direction = ctx.Aim, Delay = s.Delay })
	CombatService.Extend(ctx.Character, STATUS.MoveGraceUntil, s.Delay + 0.8)
	task.wait(s.Delay)
	if not alive(ctx) then
		return
	end
	local center = CombatService.Ground(ctx.Root.Position)
	fx(ctx, "Slam", { Position = center, Radius = s.Radius })
	for _, target in CombatService.QuerySphere(ctx.Player, center, s.Radius) do
		local away = CombatService.FlatUnit(target.Root.Position - center)
		CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = away * 50 + Vector3.new(0, 40, 0), KnockbackTime = 0.3, Stun = 0.7, FromPosition = center })
	end
end

function Skills.Flurry(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "Flurry", { Direction = ctx.Aim, Hits = s.Hits, Range = s.Range })
	for i = 1, s.Hits do
		task.wait(0.07)
		if not alive(ctx) then
			return
		end
		for _, target in CombatService.QueryCone(ctx.Player, ctx.Root.Position, ctx.Aim, s.Range, s.Arc) do
			local last = i == s.Hits
			CombatService.Hit(ctx.Player, target, s.Damage, {
				Knockback = if last then ctx.Aim * 50 + Vector3.new(0, 18, 0) else ctx.Aim * 3,
				Stun = if last then 0.5 else 0.2,
			})
		end
	end
end

function Skills.Nova(ctx: Context)
	local s = ctx.Skill
	CombatService.Extend(ctx.Character, STATUS.BusyUntil, s.WindUp + 0.25)
	fx(ctx, "NovaCharge", { Duration = s.WindUp })
	task.wait(s.WindUp)
	if not alive(ctx) then
		return -- interrupted
	end
	local center = ctx.Root.Position
	fx(ctx, "Nova", { Position = center, Radius = s.Radius })
	for _, target in CombatService.QuerySphere(ctx.Player, center, s.Radius) do
		local away = CombatService.FlatUnit(target.Root.Position - center)
		CombatService.Hit(ctx.Player, target, s.Damage, {
			Knockback = away * s.Knockback + Vector3.new(0, s.Launch, 0),
			KnockbackTime = 0.3,
			Stun = s.Stun,
			FromPosition = center,
		})
	end
end

function Skills.Pillars(ctx: Context)
	local s = ctx.Skill
	local origin = ctx.Root.Position
	local dir = ctx.Aim
	fx(ctx, "Pillars", { Origin = origin, Direction = dir, Count = s.Count, Spacing = s.Spacing, Interval = s.Interval })
	local hit: { [Player]: boolean } = {}
	for i = 1, s.Count do
		task.wait(s.Interval)
		local point = origin + dir * (i * s.Spacing)
		for _, target in CombatService.QuerySphere(ctx.Player, point, 4) do
			if not hit[target.Player] then
				hit[target.Player] = true
				CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = Vector3.new(0, 55, 0) + dir * 10, KnockbackTime = 0.3, Stun = 0.8, FromPosition = point - dir })
			end
		end
	end
end

function Skills.Beam(ctx: Context)
	local s = ctx.Skill
	CombatService.Extend(ctx.Character, STATUS.SlowUntil, s.Duration)
	CombatService.Extend(ctx.Character, STATUS.BusyUntil, s.Duration)
	fx(ctx, "Beam", { Direction = ctx.Aim, Length = s.Length, Width = s.Width, Duration = s.Duration })
	for i = 1, s.Ticks do
		task.wait(s.Duration / s.Ticks)
		if not alive(ctx) then
			fx(ctx, "BeamEnd", {})
			return
		end
		-- The ray follows the caster's facing.
		local dir = CombatService.FlatUnit(ctx.Root.CFrame.LookVector, ctx.Aim)
		for _, target in CombatService.QueryLine(ctx.Player, ctx.Root.Position + Vector3.new(0, 1, 0), dir, s.Length, s.Width) do
			CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = dir * (if i == s.Ticks then 40 else 6), Stun = 0.25 })
		end
	end
end

function Skills.Chain(ctx: Context)
	local s = ctx.Skill
	local first = CombatService.QueryCone(ctx.Player, ctx.Root.Position, ctx.Aim, s.Range, 70)
	local points = { chest(ctx) }
	if #first == 0 then
		fx(ctx, "Chain", { Points = { points[1], points[1] + ctx.Aim * s.Range * 0.6 } })
		return
	end
	table.sort(first, function(a, b)
		return (a.Root.Position - ctx.Root.Position).Magnitude < (b.Root.Position - ctx.Root.Position).Magnitude
	end)
	local hit: { [Player]: boolean } = {}
	local current = first[1]
	local damage = s.Damage
	local targets = {}
	for _ = 1, s.Jumps do
		if not current then
			break
		end
		hit[current.Player] = true
		table.insert(points, current.Root.Position)
		table.insert(targets, { Target = current, Damage = damage })
		damage *= 0.8
		local nextTarget, best = nil, s.JumpRange
		for _, other in CombatService.QuerySphere(ctx.Player, current.Root.Position, s.JumpRange) do
			local d = (other.Root.Position - current.Root.Position).Magnitude
			if not hit[other.Player] and d < best then
				nextTarget, best = other, d
			end
		end
		current = nextTarget
	end
	fx(ctx, "Chain", { Points = points })
	for i, entry in targets do
		task.delay(i * 0.06, function()
			CombatService.Hit(ctx.Player, entry.Target, entry.Damage, { Stun = 0.45, Knockback = Vector3.new(0, 10, 0) })
		end)
	end
end

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

local blinkParams = RaycastParams.new()
blinkParams.FilterType = Enum.RaycastFilterType.Exclude

function Skills.Blink(ctx: Context)
	local s = ctx.Skill
	local from = ctx.Root.Position
	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	blinkParams.FilterDescendantsInstances = exclude
	local distance = s.Distance
	local wall = Workspace:Raycast(from, ctx.Aim * distance, blinkParams)
	if wall then
		distance = math.max(0, (wall.Position - from).Magnitude - 3)
	end
	local to = from + ctx.Aim * distance
	CombatService.Extend(ctx.Character, STATUS.MoveGraceUntil, 1)
	CombatService.Extend(ctx.Character, STATUS.InvulnerableUntil, 0.25)
	fx(ctx, "Blink", { From = from, To = to })
	ctx.Character:PivotTo(CFrame.lookAt(to, to + ctx.Aim))
	ctx.Root.AssemblyLinearVelocity = Vector3.zero
	for _, target in CombatService.QuerySphere(ctx.Player, to, s.Radius) do
		local away = CombatService.FlatUnit(target.Root.Position - to)
		CombatService.Hit(ctx.Player, target, s.Damage, { Knockback = away * 35 + Vector3.new(0, 18, 0), Stun = 0.45, FromPosition = to })
	end
end

function Skills.Shield(ctx: Context)
	local s = ctx.Skill
	ctx.Character:SetAttribute(STATUS.ShieldHP, s.Absorb)
	ctx.Character:SetAttribute("ShieldReflect", s.Reflect)
	ctx.Character:SetAttribute(STATUS.ShieldUntil, CombatService.Now() + s.Duration)
	fx(ctx, "Shield", { Duration = s.Duration })
	task.delay(s.Duration, function()
		if (ctx.Character:GetAttribute(STATUS.ShieldUntil) or 0) <= CombatService.Now() + 0.05 then
			ctx.Character:SetAttribute(STATUS.ShieldHP, 0)
		end
	end)
end

function Skills.Bloom(ctx: Context)
	local s = ctx.Skill
	fx(ctx, "Bloom", { Duration = s.Duration })
	local ticks = 6
	for _ = 1, ticks do
		task.wait(s.Duration / ticks)
		local humanoid = ctx.Character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or ctx.Root.Parent == nil then
			return
		end
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + s.Heal / ticks)
	end
end

--------------------------------------------------------------------------------
-- Crowd control
--------------------------------------------------------------------------------

local function slow(target: CombatService.Target, seconds: number)
	CombatService.Extend(target.Character, STATUS.SlowedUntil, seconds)
end

function Skills.Frostbite(ctx: Context)
	local s = ctx.Skill
	local center = targetPoint(ctx, s.Range)
	fx(ctx, "Frostbite", { Center = center, Radius = s.Radius, Duration = s.Duration })
	for _ = 1, s.Ticks do
		for _, target in CombatService.QuerySphere(ctx.Player, center, s.Radius) do
			slow(target, s.Slow)
			CombatService.Hit(ctx.Player, target, s.Damage, { FromPosition = center, Unblockable = true })
		end
		task.wait(s.Duration / s.Ticks)
	end
end

function Skills.Bind(ctx: Context)
	local s = ctx.Skill
	local origin = ctx.Root.Position
	fx(ctx, "Bind", { Origin = origin, Direction = ctx.Aim, Length = s.Range, Width = s.Width })
	task.wait(0.15)
	for _, target in CombatService.QueryLine(ctx.Player, origin, ctx.Aim, s.Range, s.Width) do
		CombatService.Extend(target.Character, STATUS.RootedUntil, s.Root)
		target.Root.AssemblyLinearVelocity = Vector3.zero
		CombatService.Hit(ctx.Player, target, s.Damage, { FromPosition = origin })
		fx(ctx, "Bound", { Target = target.Character, Duration = s.Root })
	end
end

function Skills.Grab(ctx: Context)
	local s = ctx.Skill
	local origin = ctx.Root.Position
	local hits = CombatService.QueryLine(ctx.Player, origin, ctx.Aim, s.Range, s.Width)
	local nearest, best = nil, math.huge
	for _, target in hits do
		local d = (target.Root.Position - origin).Magnitude
		if d < best then
			nearest, best = target, d
		end
	end
	local reach = if nearest then nearest.Root.Position else origin + ctx.Aim * s.Range
	fx(ctx, "Grab", { Origin = origin + Vector3.new(0, 1, 0), To = reach, Hooked = nearest and nearest.Character or nil })
	if not nearest then
		return
	end
	task.wait(0.18)
	if not alive(ctx) then
		return
	end
	-- Yank them to just in front of the caster.
	local landing = ctx.Root.Position + ctx.Aim * 4
	local pull = landing - nearest.Root.Position
	CombatService.Hit(ctx.Player, nearest, s.Damage, { Stun = s.Stun, Knockback = pull * 4 + Vector3.new(0, 12, 0), KnockbackTime = 0.25, Unblockable = true })
end

function Skills.Curse(ctx: Context)
	local s = ctx.Skill
	local center = targetPoint(ctx, s.Range)
	fx(ctx, "Curse", { Center = center, Radius = s.Radius })
	task.wait(0.35)
	for _, target in CombatService.QuerySphere(ctx.Player, center, s.Radius) do
		target.Character:SetAttribute(STATUS.CurseAmp, s.Amplify)
		CombatService.Extend(target.Character, STATUS.CursedUntil, s.Duration)
		CombatService.Hit(ctx.Player, target, s.Damage, { FromPosition = center, Unblockable = true })
		fx(ctx, "Cursed", { Target = target.Character, Duration = s.Duration })
	end
end

--------------------------------------------------------------------------------
-- Domain: a dimension around the caster that traps everyone inside.
--------------------------------------------------------------------------------

function Skills.Domain(ctx: Context)
	local s = ctx.Skill
	local center = CombatService.Ground(ctx.Root.Position)
	local character = ctx.Character
	character:SetAttribute("DomainHaste", s.Haste)
	CombatService.Extend(character, STATUS.DomainUntil, s.Duration + 1)
	CombatService.Extend(character, STATUS.InvulnerableUntil, 1)
	fx(ctx, "Domain", { Center = center, Radius = s.Radius, Duration = s.Duration, Name = s.DomainName })
	task.wait(1) -- the dimension unfolds
	local ends = os.clock() + s.Duration
	while os.clock() < ends do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or character.Parent == nil then
			break
		end
		for _, target in CombatService.QuerySphere(ctx.Player, center, s.Radius + 6) do
			local offset = target.Root.Position - center
			local flat = Vector3.new(offset.X, 0, offset.Z)
			-- The barrier: nobody walks out.
			if flat.Magnitude > s.Radius - 3 then
				CombatService.Knockback(target, -flat.Unit * 45 + Vector3.new(0, 10, 0), 0.2)
			end
			slow(target, s.Slow + s.Tick)
			CombatService.Hit(ctx.Player, target, s.Damage, { FromPosition = center, Unblockable = true })
		end
		task.wait(s.Tick)
	end
	character:SetAttribute(STATUS.DomainUntil, 0)
	fx(ctx, "DomainEnd", { Center = center, Radius = s.Radius })
end

return Skills
