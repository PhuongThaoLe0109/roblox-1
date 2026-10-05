-- CrystalKit
-- Server half of the shared kit. Each function receives a context
--   { Player, Character, Root, Aim (flat unit), Combo (M1 only) }
-- and resolves hits; movement for C is applied by the caster's client, the
-- server sweeps the caster's replicated position.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local M1 = CombatConfig.M1
local SKILLS = CombatConfig.Skills
local STATUS = CombatConfig.Status

local Kit = {}

export type Context = {
	Player: Player,
	Character: Model,
	Root: BasePart,
	Aim: Vector3,
	Combo: number,
}

local function fx(ctx: Context, kind: string, params: { [string]: any })
	local color, accent = CombatService.ColorsOf(ctx.Player)
	params.Caster = ctx.Character
	params.Color = color
	params.Accent = accent
	CombatService.FX(kind, params)
end

function Kit.M1(ctx: Context)
	local finisher = ctx.Combo == 4
	fx(ctx, "Swing", { Combo = ctx.Combo, Direction = ctx.Aim })
	task.wait(0.06) -- land the hit as the slash connects
	if not ctx.Root.Parent then
		return
	end
	for _, target in CombatService.QueryCone(ctx.Player, ctx.Root.Position, ctx.Aim, M1.Range, M1.Arc) do
		CombatService.Hit(ctx.Player, target, M1.Damage[ctx.Combo], {
			Knockback = if finisher then ctx.Aim * M1.FinisherKnockback + Vector3.new(0, 20, 0) else ctx.Aim * 6,
			KnockbackTime = if finisher then 0.25 else 0.1,
			Stun = if finisher then M1.FinisherStun else M1.HitStun,
		})
	end
end

-- Z: three crystal shards in a fan.
function Kit.Z(ctx: Context)
	local cfg = SKILLS.Z
	fx(ctx, "Cast", { Direction = ctx.Aim })
	local origin = ctx.Root.Position + Vector3.new(0, 1.4, 0) + ctx.Aim * 2
	local half = (cfg.Count - 1) / 2
	for i = 0, cfg.Count - 1 do
		local yaw = math.rad((i - half) * cfg.Spread)
		local direction = CFrame.fromAxisAngle(Vector3.yAxis, yaw):VectorToWorldSpace(ctx.Aim)
		CombatService.Projectile(ctx.Player, origin, direction, cfg.Speed, cfg.Range, cfg.Radius, function(target)
			CombatService.Hit(ctx.Player, target, cfg.Damage, { Knockback = direction * 20 + Vector3.new(0, 8, 0), Stun = 0.2 })
		end)
	end
end

-- X: rising slash that launches.
function Kit.X(ctx: Context)
	local cfg = SKILLS.X
	fx(ctx, "Launcher", { Direction = ctx.Aim, Range = cfg.Range })
	task.wait(0.08)
	if not ctx.Root.Parent then
		return
	end
	for _, target in CombatService.QueryCone(ctx.Player, ctx.Root.Position, ctx.Aim, cfg.Range, cfg.Arc) do
		CombatService.Hit(ctx.Player, target, cfg.Damage, {
			Knockback = Vector3.new(0, cfg.Launch, 0) + ctx.Aim * 8,
			KnockbackTime = 0.3,
			Stun = cfg.Stun,
		})
	end
end

-- C: dash slash (the caster's client moves them).
function Kit.C(ctx: Context)
	local cfg = SKILLS.C
	fx(ctx, "Rush", { Direction = ctx.Aim, Duration = cfg.Duration })
	CombatService.Sweep(ctx.Player, function()
		return if ctx.Root.Parent then ctx.Root.Position else nil
	end, cfg.HitRadius, cfg.Duration + 0.12, function(target)
		CombatService.Hit(ctx.Player, target, cfg.Damage, {
			Knockback = ctx.Aim * cfg.Knockback + Vector3.new(0, 16, 0),
			KnockbackTime = 0.2,
			Stun = 0.5,
		})
	end)
end

-- V: wind-up, then a crystal shockwave.
function Kit.V(ctx: Context)
	local cfg = SKILLS.V
	CombatService.Extend(ctx.Character, STATUS.BusyUntil, cfg.WindUp + 0.25)
	fx(ctx, "NovaCharge", { Duration = cfg.WindUp })
	task.wait(cfg.WindUp)
	local humanoid = ctx.Character:FindFirstChildOfClass("Humanoid")
	if not ctx.Root.Parent or not humanoid or humanoid.Health <= 0 or CombatService.IsActive(ctx.Character, STATUS.StunnedUntil) then
		return -- interrupted
	end
	local center = ctx.Root.Position
	fx(ctx, "Nova", { Position = center, Radius = cfg.Radius })
	for _, target in CombatService.QuerySphere(ctx.Player, center, cfg.Radius) do
		local away = CombatService.FlatUnit(target.Root.Position - center)
		CombatService.Hit(ctx.Player, target, cfg.Damage, {
			Knockback = away * cfg.Knockback + Vector3.new(0, cfg.Launch, 0),
			KnockbackTime = 0.3,
			Stun = cfg.Stun,
			FromPosition = center,
		})
	end
end

return Kit
