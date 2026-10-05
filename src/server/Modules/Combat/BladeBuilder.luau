-- BladeBuilder
-- Builds the Crystal Blade every fighter carries, coloured with the gem they
-- wear: a neon core inside a tinted glass edge, a faceted guard and pommel,
-- and a gradient swing trail. Plain materials only (Neon / Glass /
-- SmoothPlastic), no textures.
--
-- Client contract: Model "CrystalBlade" in the character, Weld "Grip" (the
-- client animates Grip.C0 locally for swings) and Trail "SwingTrail".

local CombatBlade = {}

local function part(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(part0: BasePart, part1: BasePart, c0: CFrame, name: string?): Weld
	part1.CFrame = part0.CFrame * c0
	local w = Instance.new("Weld")
	w.Name = name or "Weld"
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
	return w
end

-- Builds and welds the blade; returns the model (or nil without a right hand).
function CombatBlade.Build(character: Model, color: Color3, accent: Color3): Model?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return nil
	end
	local old = character:FindFirstChild("CrystalBlade")
	if old then
		old:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "CrystalBlade"
	model.Parent = character

	-- Handle along -Z (blade end); held upright at rest.
	local handle = part(model, "Handle", Vector3.new(0.32, 0.32, 1.4), Color3.fromRGB(70, 50, 90), Enum.Material.SmoothPlastic)
	weld(hand, handle, CFrame.new(0, -0.25, 0) * CFrame.Angles(math.rad(90), 0, 0), "Grip")
	model.PrimaryPart = handle

	part(model, "Wrap", Vector3.new(0.36, 0.36, 0.25), accent, Enum.Material.SmoothPlastic)
	weld(handle, model.Wrap :: BasePart, CFrame.new(0, 0, 0.2))

	local pommel = part(model, "Pommel", Vector3.new(0.42, 0.42, 0.42), accent, Enum.Material.Neon)
	weld(handle, pommel, CFrame.new(0, 0, 0.85) * CFrame.Angles(math.rad(45), 0, math.rad(45)))

	-- Faceted guard: two crossed diamonds.
	local guard = part(model, "Guard", Vector3.new(1.5, 0.28, 0.42), color, Enum.Material.Neon)
	weld(handle, guard, CFrame.new(0, 0, -0.8))
	for _, side in { -1, 1 } do
		local gem = part(model, "GuardGem", Vector3.new(0.42, 0.42, 0.42), accent, Enum.Material.Glass, 0.1)
		weld(handle, gem, CFrame.new(side * 0.85, 0, -0.8) * CFrame.Angles(0, math.rad(45), math.rad(45)))
	end

	-- Blade: neon core + glass edge + tip.
	local core = part(model, "BladeCore", Vector3.new(0.14, 0.32, 3.6), Color3.new(1, 1, 1), Enum.Material.Neon)
	weld(handle, core, CFrame.new(0, 0, -2.85))
	local edge = part(model, "BladeEdge", Vector3.new(0.22, 0.62, 3.8), color, Enum.Material.Glass, 0.25)
	weld(handle, edge, CFrame.new(0, 0, -2.85))
	local tip = part(model, "BladeTip", Vector3.new(0.22, 0.44, 0.44), color, Enum.Material.Glass, 0.25)
	weld(handle, tip, CFrame.new(0, 0, -4.75) * CFrame.Angles(math.rad(45), 0, 0))

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 9
	light.Brightness = 1.6
	light.Parent = core

	-- Gradient swing trail along the blade.
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = Vector3.new(0, 0, -1.2)
	a0.Parent = handle
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = Vector3.new(0, 0, -4.9)
	a1.Parent = handle
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.2
	trail.MinLength = 0.05
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.4, color),
		ColorSequenceKeypoint.new(1, accent),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Enabled = false
	trail.Parent = handle

	return model
end

return CombatBlade
