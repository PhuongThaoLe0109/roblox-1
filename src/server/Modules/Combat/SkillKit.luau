-- SkillKit
-- Building blocks shared by the per-weapon skill modules, so each weapon file
-- only describes what makes it unique.
--
-- Every skill function receives a Context:
--   Player, Character, Root, Humanoid  the caster
--   Attacker                            { Player, Character } for CombatService
--   Weapon                              WeaponConfig entry
--   Config                              the slot's config (Basic or Skill)
--   Aim                                 unit 3D aim direction
--   AimFlat                             unit horizontal aim direction
--   AimPoint                            world point under the cursor/crosshair
--   Combo                               1..3 for melee basics

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local STATUS = CombatConfig.Status

local SkillKit = {}

export type Context = {
	Player: Player,
	Character: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Attacker: CombatService.Attacker,
	Weapon: any,
	Config: any,
	Aim: Vector3,
	AimFlat: Vector3,
	AimPoint: Vector3,
	Combo: number,
}

SkillKit.Combat = CombatService
SkillKit.Status = STATUS

function SkillKit.Swing(ctx: Context, style: string?)
	CombatService.FX("Swing", {
		Caster = ctx.Character,
		WeaponId = ctx.Weapon.Id,
		Style = style or ctx.Weapon.Basic.Style,
		Combo = ctx.Combo,
		Direction = ctx.AimFlat,
	})
end

function SkillKit.HitSpark(ctx: Context, target: CombatService.Target, color: Color3?)
	CombatService.FX("Burst", {
		Position = target.Root.Position,
		Radius = 3,
		Color = color or ctx.Weapon.Color,
		Duration = 0.25,
	})
end

-- Melee cone basic with a 3-hit combo (3rd hit is the finisher).
-- extraOptions(target, isFinisher) can add status effects per hit.
function SkillKit.MeleeBasic(ctx: Context, extraOptions: ((any, boolean) -> { [string]: any }?)?, rangeBonus: number?)
	local basic = ctx.Weapon.Basic
	local finisher = ctx.Combo == 3
	SkillKit.Swing(ctx)
	task.wait(0.07) -- land the hit as the swing visually connects

	local targets = CombatService.QueryCone(ctx.Attacker, ctx.Root.Position, ctx.AimFlat, basic.Range + (rangeBonus or 0), basic.Arc or 60)
	for _, target in targets do
		local options = {
			Multiplier = if finisher then basic.ComboFinisher or 1 else 1,
			Knockback = if finisher then ctx.AimFlat * 32 + Vector3.new(0, 14, 0) else nil,
		}
		local extra = extraOptions and extraOptions(target, finisher)
		if extra then
			for key, value in extra do
				(options :: any)[key] = value
			end
		end
		CombatService.Damage(ctx.Attacker, target, basic.Damage, options)
		SkillKit.HitSpark(ctx, target)
	end
	return targets
end

function SkillKit.MuzzlePosition(ctx: Context): Vector3
	return ctx.Root.Position + Vector3.new(0, 1.5, 0) + ctx.AimFlat * 2
end

-- Fires a projectile toward the aim point.
function SkillKit.Shoot(ctx: Context, spec: { [string]: any }, onHit: (any, Vector3) -> (), onImpact: ((Vector3) -> ())?)
	local origin = spec.Origin or SkillKit.MuzzlePosition(ctx)
	local direction = spec.Direction or (ctx.AimPoint - origin)
	if direction.Magnitude < 1e-3 then
		direction = ctx.AimFlat
	end
	CombatService.Projectile(ctx.Attacker, {
		Origin = origin,
		Direction = direction.Unit,
		Speed = spec.Speed,
		Range = spec.Range,
		Radius = spec.Radius or 2.5,
		Color = spec.Color or ctx.Weapon.Color,
		Size = spec.Size,
		Style = spec.Style,
	}, onHit, onImpact)
end

-- Server half of a client-driven dash/roll: sweep around the caster while the
-- client moves them, hitting each target once.
function SkillKit.DashSweep(ctx: Context, radius: number, duration: number, onHit: (any) -> ())
	CombatService.FX("Dash", { Caster = ctx.Character, Color = ctx.Weapon.Color, Duration = duration })
	CombatService.Sweep(ctx.Attacker, function()
		return if ctx.Root.Parent then ctx.Root.Position else nil
	end, radius, duration + 0.1, onHit)
end

-- Server half of a client-driven leap: waits for the landing, then calls onLand.
function SkillKit.LeapSlam(ctx: Context, onLand: (Vector3) -> ())
	CombatService.FX("Dash", { Caster = ctx.Character, Color = ctx.Weapon.Color, Duration = 1 })
	if CombatService.WaitForLanding(ctx.Character, 2.2) and ctx.Root.Parent then
		onLand(ctx.Root.Position - Vector3.new(0, 2.5, 0))
	end
end

function SkillKit.Aura(model: Model, color: Color3, duration: number, style: string?)
	CombatService.FX("Aura", { Target = model, Color = color, Duration = duration, Style = style })
end

-- Clamps an aim point to a maximum horizontal distance from the caster.
function SkillKit.ClampPoint(ctx: Context, maxDistance: number): Vector3
	local offset = ctx.AimPoint - ctx.Root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > maxDistance then
		flat = flat.Unit * maxDistance
	end
	return ctx.Root.Position + flat - Vector3.new(0, 2.5, 0)
end

-- Ground position directly below a point (falls back to the point itself).
function SkillKit.Ground(position: Vector3, exclude: { Instance }?): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude or {}
	local result = workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), params)
	return if result then result.Position else position
end

return SkillKit
