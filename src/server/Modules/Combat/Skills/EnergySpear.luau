-- Prism Spear: precise thrusts, a skewering dash, a spear volley and a
-- phantom echo that repeats every thrust.

local SkillKit = require(script.Parent.Parent:WaitForChild("SkillKit"))

local Combat = SkillKit.Combat
local STATUS = SkillKit.Status

return {
	Basic = function(ctx)
		SkillKit.MeleeBasic(ctx)

		-- Mirror Echo: a phantom thrust follows with longer reach.
		if Combat.IsActive(ctx.Character, STATUS.EchoUntil) then
			local echo = ctx.Weapon.Skills.R
			task.wait(0.15)
			local from = ctx.Root.Position + Vector3.new(0, 1, 0)
			Combat.FX("Line", { From = from, To = from + ctx.AimFlat * echo.EchoRange, Color = ctx.Weapon.Glow, Width = 1.6, Duration = 0.25 })
			for _, target in Combat.QueryLine(ctx.Attacker, ctx.Root.Position, ctx.AimFlat, echo.EchoRange, 4) do
				Combat.Damage(ctx.Attacker, target, echo.EchoDamage, { Color = ctx.Weapon.Glow })
			end
		end
	end,

	Q = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Thrust")
		SkillKit.DashSweep(ctx, cfg.HitRadius, cfg.SelfMotion.Duration, function(target)
			Combat.Damage(ctx.Attacker, target, cfg.Damage, { Knockback = ctx.AimFlat * 40 + Vector3.new(0, 18, 0) })
			SkillKit.HitSpark(ctx, target)
		end)
	end,

	E = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Cast")
		local origin = SkillKit.MuzzlePosition(ctx)
		local baseDirection = ctx.AimPoint - origin
		if baseDirection.Magnitude < 1e-3 then
			baseDirection = ctx.AimFlat
		end
		local half = (cfg.Count - 1) / 2
		for i = 0, cfg.Count - 1 do
			local yaw = math.rad((i - half) * cfg.Spread)
			local direction = CFrame.fromAxisAngle(Vector3.yAxis, yaw):VectorToWorldSpace(baseDirection.Unit)
			SkillKit.Shoot(ctx, { Origin = origin, Direction = direction, Speed = cfg.Speed, Range = cfg.Range, Size = 1.4, Style = "Spear" }, function(target)
				Combat.Damage(ctx.Attacker, target, cfg.Damage, { Knockback = direction * 25 })
			end)
		end
	end,

	R = function(ctx)
		local cfg = ctx.Config
		ctx.Character:SetAttribute(STATUS.EchoUntil, Combat.Now() + cfg.Duration)
		SkillKit.Aura(ctx.Character, ctx.Weapon.Glow, cfg.Duration, "Echo")
		Combat.FX("Burst", { Position = ctx.Root.Position, Radius = 8, Color = ctx.Weapon.Glow })
	end,
}
