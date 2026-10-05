-- Ember Gauntlet: rapid punches, a rocket rush, an overheat buff that burns,
-- and a meteor slam.

local SkillKit = require(script.Parent.Parent:WaitForChild("SkillKit"))

local Combat = SkillKit.Combat
local STATUS = SkillKit.Status

return {
	Basic = function(ctx)
		local heat = ctx.Weapon.Skills.E
		local heated = Combat.IsActive(ctx.Character, STATUS.HeatUntil)
		SkillKit.MeleeBasic(ctx, function()
			return if heated then { Burn = { Dps = heat.BurnDps, Time = heat.BurnTime } } else nil
		end)
	end,

	-- Basic cooldown is divided by this while Heat Up is active.
	AttackSpeed = function(ctx): number
		return if Combat.IsActive(ctx.Character, STATUS.HeatUntil) then ctx.Weapon.Skills.E.AttackSpeed else 1
	end,

	Q = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Punch")
		local launched = false
		SkillKit.DashSweep(ctx, cfg.HitRadius, cfg.SelfMotion.Duration, function(target)
			Combat.Damage(ctx.Attacker, target, cfg.Damage, {
				Knockback = ctx.AimFlat * (if launched then cfg.Knockback * 0.5 else cfg.Knockback) + Vector3.new(0, 30, 0),
				KnockbackTime = 0.3,
			})
			launched = true
			Combat.FX("Burst", { Position = target.Root.Position, Radius = 6, Color = ctx.Weapon.Glow })
		end)
	end,

	E = function(ctx)
		local cfg = ctx.Config
		ctx.Character:SetAttribute(STATUS.HeatUntil, Combat.Now() + cfg.Duration)
		SkillKit.Aura(ctx.Character, ctx.Weapon.Color, cfg.Duration, "Fire")
		Combat.FX("Burst", { Position = ctx.Root.Position, Radius = 7, Color = ctx.Weapon.Glow })
	end,

	R = function(ctx)
		local cfg = ctx.Config
		SkillKit.LeapSlam(ctx, function(position)
			Combat.FX("Ring", { Position = position, Radius = cfg.Radius, Color = ctx.Weapon.Color, Style = "Fire" })
			Combat.FX("Burst", { Position = position, Radius = cfg.Radius * 0.6, Color = ctx.Weapon.Glow })
			for _, target in Combat.QuerySphere(ctx.Attacker, position, cfg.Radius) do
				local away = Combat.FlatUnit(target.Root.Position - position)
				Combat.Damage(ctx.Attacker, target, cfg.Damage, {
					Knockback = away * 20 + Vector3.new(0, cfg.Knockup, 0),
					KnockbackTime = 0.3,
					Burn = { Dps = cfg.BurnDps, Time = cfg.BurnTime },
				})
			end
		end)
	end,
}
