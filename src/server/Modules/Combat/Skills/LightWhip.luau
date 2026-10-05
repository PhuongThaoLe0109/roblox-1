-- Amethyst Lash: wide sweeping lashes, a lasso pull, a double spin and a
-- rolling comet.

local SkillKit = require(script.Parent.Parent:WaitForChild("SkillKit"))

local Combat = SkillKit.Combat

return {
	Basic = function(ctx)
		SkillKit.MeleeBasic(ctx)
	end,

	Q = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Lash")
		local origin = ctx.Root.Position
		local target = Combat.FirstInLine(ctx.Attacker, origin, ctx.AimFlat, cfg.Range, cfg.Width)
		local reach = if target then target.Root.Position else origin + ctx.AimFlat * cfg.Range
		Combat.FX("Line", { From = origin + Vector3.new(0, 1, 0), To = reach, Color = ctx.Weapon.Color, Width = 0.6, Duration = 0.45, Style = "Lasso" })
		if target then
			Combat.Damage(ctx.Attacker, target, cfg.Damage, { Stun = cfg.StunTime })
			Combat.PullTo(target, ctx.Root.Position, 5, 90)
		end
	end,

	E = function(ctx)
		local cfg = ctx.Config
		for hit = 1, cfg.Hits do
			SkillKit.Swing(ctx, "Spin")
			Combat.FX("Ring", { Position = ctx.Root.Position - Vector3.new(0, 2.5, 0), Radius = cfg.Radius, Color = ctx.Weapon.Color })
			for _, target in Combat.QuerySphere(ctx.Attacker, ctx.Root.Position, cfg.Radius) do
				local away = Combat.FlatUnit(target.Root.Position - ctx.Root.Position)
				Combat.Damage(ctx.Attacker, target, cfg.Damage, { Knockback = away * cfg.Knockback + Vector3.new(0, 15, 0) })
			end
			if hit < cfg.Hits then
				task.wait(cfg.Interval)
			end
		end
	end,

	R = function(ctx)
		local cfg = ctx.Config
		Combat.FX("Aura", { Target = ctx.Character, Color = ctx.Weapon.Color, Duration = cfg.SelfMotion.Duration, Style = "Comet" })
		SkillKit.DashSweep(ctx, cfg.HitRadius, cfg.SelfMotion.Duration, function(target)
			local away = Combat.FlatUnit(target.Root.Position - ctx.Root.Position)
			Combat.Damage(ctx.Attacker, target, cfg.Damage, { Knockback = away * cfg.Knockback + Vector3.new(0, 25, 0) })
			SkillKit.HitSpark(ctx, target)
		end)
	end,
}
