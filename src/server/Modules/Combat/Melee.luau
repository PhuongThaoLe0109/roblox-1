-- Melee
-- Server half of the M1 combo for every melee style in GemKits (blade,
-- greatsword, daggers, gauntlets, spear, scythe, hammer, whip, fans and the
-- beast maul). ActionService decides which hit of the combo this is; here the
-- hit is resolved in a cone in front of the attacker.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemKits = require(ReplicatedStorage:WaitForChild("GemKits"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local Melee = {}

-- ctx = { Player, Character, Root, Aim, Kit }
function Melee.Swing(ctx, style: GemKits.Melee, combo: number)
	local finisher = combo == style.Hits
	local color, accent = CombatService.ColorsOf(ctx.Player)
	CombatService.FX("Swing", {
		Caster = ctx.Character,
		Style = style.Id,
		Combo = combo,
		Hits = style.Hits,
		Direction = ctx.Aim,
		Color = color,
		Accent = accent,
		Element = ctx.Kit.Element,
	})
	task.wait(if style.Interval >= 0.45 then 0.12 else 0.06) -- land the hit as the swing connects
	if not ctx.Root.Parent then
		return
	end
	local damage = GemKits.MeleeDamage(ctx.Kit, style, combo)
	for _, target in CombatService.QueryCone(ctx.Player, ctx.Root.Position, ctx.Aim, style.Range, style.Arc) do
		CombatService.Hit(ctx.Player, target, damage, {
			Knockback = if finisher then ctx.Aim * style.FinisherKnockback + Vector3.new(0, style.FinisherLaunch, 0) else ctx.Aim * 6,
			KnockbackTime = if finisher then 0.25 else 0.1,
			Stun = if finisher then style.FinisherStun else style.HitStun,
		})
	end
	-- Hammer / beast finishers shake the ground around the impact.
	if finisher and style.FinisherRadius then
		local center = CombatService.Ground(ctx.Root.Position + ctx.Aim * (style.Range * 0.5))
		CombatService.FX("Slam", { Caster = ctx.Character, Position = center, Radius = style.FinisherRadius, Color = color, Accent = accent, Element = ctx.Kit.Element })
		for _, target in CombatService.QuerySphere(ctx.Player, center, style.FinisherRadius) do
			local away = CombatService.FlatUnit(target.Root.Position - center)
			CombatService.Hit(ctx.Player, target, damage * 0.5, { Knockback = away * 30 + Vector3.new(0, 30, 0), Stun = 0.5, FromPosition = center })
		end
	end
end

return Melee
