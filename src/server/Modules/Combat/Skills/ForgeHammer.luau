-- Forge Hammer: heavy smashes, a wound-up crater strike, a crystal wall and
-- three expanding shockwaves.

local Debris = game:GetService("Debris")

local SkillKit = require(script.Parent.Parent:WaitForChild("SkillKit"))

local Combat = SkillKit.Combat
local STATUS = SkillKit.Status

return {
	Basic = function(ctx)
		SkillKit.MeleeBasic(ctx)
	end,

	Q = function(ctx)
		local cfg = ctx.Config
		-- Wind-up: the caster is briefly rooted while the hammer rises.
		ctx.Character:SetAttribute(STATUS.RootedUntil, Combat.Now() + cfg.WindUp)
		SkillKit.Swing(ctx, "WindUp")
		task.wait(cfg.WindUp)
		if not ctx.Root.Parent then
			return
		end
		SkillKit.Swing(ctx, "Smash")
		local impact = ctx.Root.Position + ctx.AimFlat * (cfg.Range * 0.5) - Vector3.new(0, 2.5, 0)
		Combat.FX("Ring", { Position = impact, Radius = cfg.Range * 0.8, Color = ctx.Weapon.Color })
		Combat.FX("Burst", { Position = impact, Radius = 7, Color = ctx.Weapon.Glow })
		for _, target in Combat.QueryCone(ctx.Attacker, ctx.Root.Position, ctx.AimFlat, cfg.Range, cfg.Arc) do
			Combat.Damage(ctx.Attacker, target, cfg.Damage, { Knockback = ctx.AimFlat * 25 + Vector3.new(0, cfg.Knockup, 0), KnockbackTime = 0.3 })
		end
	end,

	E = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Smash")
		local center = ctx.Root.Position + ctx.AimFlat * cfg.Distance
		local ground = SkillKit.Ground(center, { ctx.Character })
		local facing = CFrame.lookAt(ground, ground + ctx.AimFlat)

		local wall = Instance.new("Model")
		wall.Name = "ForgeWall"
		local segments = 5
		local segmentWidth = cfg.Width / segments
		for i = 1, segments do
			local x = (i - (segments + 1) / 2) * segmentWidth
			local height = cfg.Height * (if i == 1 or i == segments then 0.75 else 1)
			local crystal = Instance.new("Part")
			crystal.Name = "WallCrystal"
			crystal.Anchored = true
			crystal.Size = Vector3.new(segmentWidth + 0.3, height, 2.4)
			crystal.CFrame = facing * CFrame.new(x, height / 2 - 0.5, 0)
			crystal.Color = ctx.Weapon.Color
			crystal.Material = Enum.Material.Glass
			crystal.Transparency = 0.25
			crystal.Parent = wall
			local shell = crystal:Clone()
			shell.Name = "WallShell"
			shell.Size += Vector3.new(0.2, 0.2, 0.6)
			shell.Material = Enum.Material.ForceField
			shell.Color = ctx.Weapon.Glow
			shell.Transparency = 0
			shell.CanCollide = false
			shell.CanQuery = false
			shell.Parent = wall
		end
		wall:SetAttribute("Owner", ctx.Player.UserId)
		wall.Parent = Combat.WallsFolder
		Combat.FX("Burst", { Position = ground + Vector3.new(0, cfg.Height / 2, 0), Radius = cfg.Width / 2, Color = ctx.Weapon.Glow })
		Debris:AddItem(wall, cfg.Duration)
	end,

	R = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Smash")
		local origin = ctx.Root.Position
		local previous = 0
		for _, radius in cfg.Radii do
			if not ctx.Root.Parent then
				return
			end
			Combat.FX("Ring", { Position = origin - Vector3.new(0, 2.5, 0), Radius = radius, Color = ctx.Weapon.Color })
			for _, target in Combat.QuerySphere(ctx.Attacker, origin, radius) do
				-- Each wave hits the band between the previous radius and this one.
				local distance = (target.Root.Position - origin).Magnitude
				if distance >= previous - 2 then
					local away = Combat.FlatUnit(target.Root.Position - origin)
					Combat.Damage(ctx.Attacker, target, cfg.Damage, { Knockback = away * 15 + Vector3.new(0, cfg.Knockup, 0) })
				end
			end
			previous = radius
			task.wait(cfg.Interval)
		end
	end,
}
