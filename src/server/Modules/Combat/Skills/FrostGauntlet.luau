-- Rime Gauntlet: chilling punches, a racing line of ice spikes, a foresight
-- dodge and a flash freeze.

local SkillKit = require(script.Parent.Parent:WaitForChild("SkillKit"))

local Combat = SkillKit.Combat
local STATUS = SkillKit.Status

return {
	Basic = function(ctx)
		local weapon = ctx.Weapon
		SkillKit.MeleeBasic(ctx, function()
			return { Slow = { Mult = weapon.ChillMult, Time = weapon.ChillTime } }
		end)
	end,

	Q = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Punch")
		local hit: { [Model]: boolean } = {}
		local origin = ctx.Root.Position - Vector3.new(0, 2.5, 0)
		local direction = ctx.AimFlat
		for i = 1, cfg.Count do
			local point = origin + direction * (i * cfg.Spacing)
			Combat.FX("Spike", { Position = point, Color = ctx.Weapon.Color, Height = 4 + i * 0.6 })
			for _, target in Combat.QuerySphere(ctx.Attacker, point + Vector3.new(0, 2.5, 0), cfg.Radius) do
				if not hit[target.Model] then
					hit[target.Model] = true
					Combat.Damage(ctx.Attacker, target, cfg.Damage, {
						Slow = { Mult = cfg.SlowMult, Time = cfg.SlowTime },
						Knockback = Vector3.new(0, 28, 0),
					})
				end
			end
			task.wait(cfg.Delay)
		end
	end,

	E = function(ctx)
		local cfg = ctx.Config
		ctx.Character:SetAttribute("DodgeBlink", cfg.BlinkDistance)
		ctx.Character:SetAttribute(STATUS.DodgeUntil, Combat.Now() + cfg.Duration)
		SkillKit.Aura(ctx.Character, ctx.Weapon.Glow, cfg.Duration, "Foresight")
	end,

	R = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Smash")
		local position = ctx.Root.Position
		Combat.FX("Ring", { Position = position - Vector3.new(0, 2.5, 0), Radius = cfg.Radius, Color = ctx.Weapon.Glow, Style = "Ice" })
		Combat.FX("Burst", { Position = position, Radius = cfg.Radius * 0.7, Color = ctx.Weapon.Color })
		for _, target in Combat.QuerySphere(ctx.Attacker, position, cfg.Radius) do
			Combat.Damage(ctx.Attacker, target, cfg.Damage, { Freeze = cfg.FreezeTime })
		end
	end,
}
