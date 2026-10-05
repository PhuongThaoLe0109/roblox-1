-- Tide Wings: splashing water bolts, a soaring wing burst, a pinning riptide
-- and a tidal wave.

local SkillKit = require(script.Parent.Parent:WaitForChild("SkillKit"))

local Combat = SkillKit.Combat

local WATER = Color3.fromRGB(120, 200, 255)

return {
	Basic = function(ctx)
		local basic = ctx.Weapon.Basic
		SkillKit.Swing(ctx, "Cast")
		local function splash(position: Vector3, direct: any?)
			Combat.FX("Burst", { Position = position, Radius = basic.Splash, Color = WATER, Duration = 0.3 })
			for _, target in Combat.QuerySphere(ctx.Attacker, position, basic.Splash) do
				if target ~= direct then
					Combat.Damage(ctx.Attacker, target, basic.Damage * 0.5)
				end
			end
		end
		SkillKit.Shoot(ctx, { Speed = basic.Speed, Range = basic.Range, Radius = basic.Radius, Size = 1.6, Style = "Water" }, function(target, position)
			Combat.Damage(ctx.Attacker, target, basic.Damage)
			splash(position, target)
		end, function(position)
			splash(position)
		end)
	end,

	Q = function(ctx)
		local cfg = ctx.Config
		local origin = ctx.Root.Position
		Combat.FX("Dash", { Caster = ctx.Character, Color = ctx.Weapon.Color, Duration = cfg.SelfMotion.Duration })
		Combat.FX("Ring", { Position = origin - Vector3.new(0, 2.5, 0), Radius = cfg.Radius, Color = WATER, Style = "Water" })
		Combat.FX("Burst", { Position = origin, Radius = cfg.Radius * 0.6, Color = WATER })
		for _, target in Combat.QuerySphere(ctx.Attacker, origin, cfg.Radius) do
			local away = Combat.FlatUnit(target.Root.Position - origin)
			Combat.Damage(ctx.Attacker, target, cfg.Damage, { Knockback = away * cfg.Knockback + Vector3.new(0, 10, 0) })
		end
	end,

	E = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Cast")
		local point = SkillKit.Ground(SkillKit.ClampPoint(ctx, cfg.PlaceRange), { ctx.Character })
		Combat.FX("Ring", { Position = point, Radius = cfg.Radius, Color = WATER, Style = "Telegraph", Duration = cfg.Delay })
		task.wait(cfg.Delay)
		Combat.FX("Spike", { Position = point, Color = WATER, Height = 9, Style = "Hand" })
		Combat.FX("Burst", { Position = point + Vector3.new(0, 3, 0), Radius = cfg.Radius, Color = WATER })
		for _, target in Combat.QuerySphere(ctx.Attacker, point + Vector3.new(0, 2.5, 0), cfg.Radius) do
			Combat.Damage(ctx.Attacker, target, cfg.Damage, { Root = cfg.RootTime, Knockback = Vector3.new(0, 18, 0) })
		end
	end,

	R = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Cast")
		local origin = ctx.Root.Position - ctx.AimFlat * 4
		Combat.FX("Wave", {
			Origin = origin - Vector3.new(0, 2.5, 0),
			Direction = ctx.AimFlat,
			Length = cfg.Length,
			Width = cfg.Width,
			Speed = cfg.Speed,
			Color = ctx.Weapon.Color,
		})
		Combat.MovingSweep(ctx.Attacker, origin, ctx.AimFlat, cfg.Length, cfg.Width, cfg.Speed, function(target)
			Combat.Damage(ctx.Attacker, target, cfg.Damage, { Knockback = ctx.AimFlat * cfg.Knockback + Vector3.new(0, 20, 0), KnockbackTime = 0.35 })
		end)
	end,
}
