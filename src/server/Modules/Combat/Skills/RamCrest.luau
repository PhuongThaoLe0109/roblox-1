-- Ram Crest: headbutts, a stunning horn charge, a rallying war cry and a
-- quake leap.

local Players = game:GetService("Players")

local SkillKit = require(script.Parent.Parent:WaitForChild("SkillKit"))

local Combat = SkillKit.Combat

return {
	Basic = function(ctx)
		SkillKit.MeleeBasic(ctx)
	end,

	Q = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Headbutt")
		SkillKit.DashSweep(ctx, cfg.HitRadius, cfg.SelfMotion.Duration, function(target)
			Combat.Damage(ctx.Attacker, target, cfg.Damage, {
				Knockback = ctx.AimFlat * cfg.Knockback + Vector3.new(0, 25, 0),
				KnockbackTime = 0.3,
				Stun = cfg.StunTime,
			})
			Combat.FX("Burst", { Position = target.Root.Position, Radius = 5, Color = ctx.Weapon.Glow })
		end)
	end,

	E = function(ctx)
		local cfg = ctx.Config
		Combat.FX("Ring", { Position = ctx.Root.Position - Vector3.new(0, 2.5, 0), Radius = cfg.Radius, Color = ctx.Weapon.Color, Style = "Shout" })
		-- Buff the caster and every ally in range.
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - ctx.Root.Position).Magnitude <= cfg.Radius and Combat.IsAlly(ctx.Attacker, character) then
				Combat.GiveDamageBuff(character, cfg.DamageMult, cfg.Duration)
				SkillKit.Aura(character, ctx.Weapon.Color, cfg.Duration, "Buff")
			end
		end
		Combat.GiveShield(ctx.Character, cfg.Shield, cfg.Duration)
	end,

	R = function(ctx)
		local cfg = ctx.Config
		SkillKit.LeapSlam(ctx, function(position)
			Combat.FX("Ring", { Position = position, Radius = cfg.Radius, Color = ctx.Weapon.Color })
			Combat.FX("Burst", { Position = position, Radius = cfg.Radius * 0.5, Color = ctx.Weapon.Glow })
			for _, target in Combat.QuerySphere(ctx.Attacker, position, cfg.Radius) do
				Combat.Damage(ctx.Attacker, target, cfg.Damage, { Stun = cfg.StunTime, Knockback = Vector3.new(0, 35, 0) })
			end
		end)
	end,
}
