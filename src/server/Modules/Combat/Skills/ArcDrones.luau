-- Arc Drones: ranged bolts, a tractor beam, a drone shield and a zapping
-- turret.

local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local SkillKit = require(script.Parent.Parent:WaitForChild("SkillKit"))

local Combat = SkillKit.Combat

return {
	Basic = function(ctx)
		local basic = ctx.Weapon.Basic
		SkillKit.Swing(ctx, "Cast")
		SkillKit.Shoot(ctx, { Speed = basic.Speed, Range = basic.Range, Radius = basic.Radius, Size = 1.1, Style = "Bolt" }, function(target)
			Combat.Damage(ctx.Attacker, target, basic.Damage)
		end)
	end,

	Q = function(ctx)
		local cfg = ctx.Config
		SkillKit.Swing(ctx, "Cast")
		local origin = SkillKit.MuzzlePosition(ctx)
		local target = Combat.FirstInLine(ctx.Attacker, ctx.Root.Position, ctx.AimFlat, cfg.Range, cfg.Width)
		local reach = if target then target.Root.Position else origin + ctx.AimFlat * cfg.Range
		Combat.FX("Line", { From = origin, To = reach, Color = ctx.Weapon.Color, Width = 2.2, Duration = cfg.StunTime, Style = "Tractor" })
		if target then
			Combat.Damage(ctx.Attacker, target, cfg.Damage, { Stun = cfg.StunTime })
			Combat.PullTo(target, ctx.Root.Position + ctx.AimFlat * 6 + Vector3.new(0, 4, 0), 2, 45)
		end
	end,

	E = function(ctx)
		local cfg = ctx.Config
		Combat.GiveShield(ctx.Character, cfg.Shield, cfg.Duration)
		SkillKit.Aura(ctx.Character, ctx.Weapon.Color, cfg.Duration, "Shield")
	end,

	R = function(ctx)
		local cfg = ctx.Config
		local base = SkillKit.ClampPoint(ctx, cfg.PlaceRange)
		local ground = SkillKit.Ground(base, { ctx.Character })
		local position = ground + Vector3.new(0, 5, 0)

		local turret = Instance.new("Part")
		turret.Name = "ArcTurret"
		turret.Shape = Enum.PartType.Block
		turret.Size = Vector3.new(2.4, 2.4, 2.4)
		turret.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		turret.Anchored = true
		turret.CanCollide = false
		turret.CanQuery = false
		turret.CanTouch = false
		turret.Color = ctx.Weapon.Color
		turret.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = ctx.Weapon.Color
		light.Range = 18
		light.Brightness = 2
		light.Parent = turret
		turret.Parent = Combat.FXFolder
		CollectionService:AddTag(turret, "Spin")
		Debris:AddItem(turret, cfg.Duration)
		Combat.FX("Burst", { Position = position, Radius = 5, Color = ctx.Weapon.Glow })

		local ends = os.clock() + cfg.Duration
		while os.clock() < ends and turret.Parent do
			local nearest, nearestDistance = nil, math.huge
			for _, target in Combat.QuerySphere(ctx.Attacker, position, cfg.Range) do
				local distance = (target.Root.Position - position).Magnitude
				if distance < nearestDistance then
					nearest, nearestDistance = target, distance
				end
			end
			if nearest then
				Combat.FX("Line", { From = position, To = nearest.Root.Position, Color = ctx.Weapon.Color, Width = 0.8, Duration = 0.15, Style = "Zap" })
				Combat.Damage(ctx.Attacker, nearest, cfg.Damage)
			end
			task.wait(cfg.Interval)
		end
	end,
}
