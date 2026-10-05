-- WeaponBuilder
-- Builds each light-weapon from primitives and welds it to the character.
-- Look: a neon core wrapped in a ForceField-material shell (Roblox's animated
-- shimmering gradient), sparkles, a glow light and a swing trail.
--
-- Contract with the client VFX:
--   * Model "SummonedWeapon" under the character, attribute WeaponId.
--   * Weld named "Grip" holds the weapon to its body part; the client animates
--     Grip.C0 locally for swings (attribute RestC0 not needed: it caches it).
--   * Trail named "SwingTrail" (disabled) is switched on during swings.
--   * Welds with attribute Anim = "Orbit" | "Flap" (+ Index/Side) are animated
--     client-side (drones orbiting, wings flapping).
--   * Beam "WhipBeam" + Attachment "WhipTip" for the whip.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))

local WeaponBuilder = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

--------------------------------------------------------------------------------
-- Helpers (all coordinates are in the handle's local space; -Z = blade end)
--------------------------------------------------------------------------------

local function part(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Shape = shape or Enum.PartType.Block
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

-- A neon core plus a slightly larger shimmering ForceField shell.
local function crystal(model: Model, handle: BasePart, name: string, size: Vector3, offset: CFrame, core: Color3, glow: Color3, shape: Enum.PartType?): Part
	local p = part(model, name, size, core, Enum.Material.Neon, shape)
	weld(handle, p, offset)
	local shell = part(model, name .. "Shell", size * 1.18, glow, Enum.Material.ForceField, shape)
	weld(handle, shell, offset)
	return p
end

local function sparkles(attachTo: BasePart, color: Color3, rate: number?, texture: string?)
	local e = Instance.new("ParticleEmitter")
	e.Name = "WeaponSparkles"
	e.Texture = texture or SPARKLE
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 235)),
	})
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Rate = rate or 10
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(0.5, 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Parent = attachTo
	return e
end

local function glowLight(attachTo: BasePart, color: Color3, range: number?)
	local light = Instance.new("PointLight")
	light.Name = "WeaponGlow"
	light.Color = color
	light.Range = range or 12
	light.Brightness = 1.4
	light.Parent = attachTo
end

local function swingTrail(handle: BasePart, a: Vector3, b: Vector3, color: Color3, glow: Color3)
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = a
	a0.Parent = handle
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = b
	a1.Parent = handle

	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.22
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.MinLength = 0.05
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.35, color),
		ColorSequenceKeypoint.new(1, glow),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Enabled = false
	trail.Parent = handle
end

local function bodyPart(character: Model, r15: string, r6: string): BasePart?
	local p = character:FindFirstChild(r15) or character:FindFirstChild(r6)
	return if p and p:IsA("BasePart") then p else nil
end

--------------------------------------------------------------------------------
-- Weapon recipes. Each returns the handle part (or nil on failure).
--------------------------------------------------------------------------------

type Recipe = (model: Model, character: Model, weapon: any) -> BasePart?

local RECIPES: { [string]: Recipe } = {}

RECIPES.EnergySpear = function(model, character, weapon)
	local hand = bodyPart(character, "RightHand", "Right Arm")
	if not hand then
		return nil
	end
	local handle = part(model, "Handle", Vector3.new(0.35, 0.35, 9.5), Color3.fromRGB(240, 245, 255), Enum.Material.Neon)
	-- Held upright at rest: handle -Z (blade end) points up.
	weld(hand, handle, CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, 0, -1.5), "Grip")
	local tip = crystal(model, handle, "Tip", Vector3.new(0.9, 0.9, 2.4), CFrame.new(0, 0, -5.9) * CFrame.Angles(0, 0, math.rad(45)), weapon.Color, weapon.Glow)
	crystal(model, handle, "Guard", Vector3.new(1.4, 0.3, 0.3), CFrame.new(0, 0, -4.6), weapon.Glow, weapon.Color)
	crystal(model, handle, "Pommel", Vector3.new(0.5, 0.5, 0.8), CFrame.new(0, 0, 5) * CFrame.Angles(0, 0, math.rad(45)), weapon.Glow, weapon.Color)
	sparkles(tip, weapon.Color, 12)
	glowLight(tip, weapon.Color)
	swingTrail(handle, Vector3.new(0, 0, -4.5), Vector3.new(0, 0, -7.1), weapon.Color, weapon.Glow)
	return handle
end

RECIPES.LightWhip = function(model, character, weapon)
	local hand = bodyPart(character, "RightHand", "Right Arm")
	if not hand then
		return nil
	end
	local handle = part(model, "Handle", Vector3.new(0.45, 0.45, 1.8), Color3.fromRGB(70, 40, 110), Enum.Material.SmoothPlastic)
	weld(hand, handle, CFrame.new(0, -0.5, -0.3), "Grip")
	local knot = crystal(model, handle, "Knot", Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 0, -1.1) * CFrame.Angles(math.rad(45), math.rad(45), 0), weapon.Color, weapon.Glow)

	local base = Instance.new("Attachment")
	base.Name = "WhipBase"
	base.Position = Vector3.new(0, 0, -1.2)
	base.Parent = handle
	local tip = Instance.new("Attachment")
	tip.Name = "WhipTip"
	tip.Position = Vector3.new(0, -5, -5)
	tip.Parent = handle

	local beam = Instance.new("Beam")
	beam.Name = "WhipBeam"
	beam.Attachment0 = base
	beam.Attachment1 = tip
	beam.Segments = 24
	beam.CurveSize0 = 3
	beam.CurveSize1 = -1
	beam.Width0 = 0.45
	beam.Width1 = 0.12
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, weapon.Color),
		ColorSequenceKeypoint.new(0.6, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, weapon.Glow),
	})
	beam.Transparency = NumberSequence.new(0, 0.2)
	beam.Parent = handle

	sparkles(knot, weapon.Color, 10)
	glowLight(knot, weapon.Color)
	swingTrail(handle, Vector3.new(0, 0, -1.2), Vector3.new(0, -4, -5), weapon.Color, weapon.Glow)
	return handle
end

local function gauntlet(model: Model, character: Model, weapon: any, spikeColor: Color3, emitterTexture: string?): BasePart?
	local hand = bodyPart(character, "RightHand", "Right Arm")
	if not hand then
		return nil
	end
	local handle = part(model, "Handle", Vector3.new(1.5, 1.5, 1.5), weapon.Color, Enum.Material.Glass)
	handle.Transparency = 0.15
	weld(hand, handle, CFrame.new(0, -0.35, 0), "Grip")
	local shell = part(model, "Shell", Vector3.new(1.85, 1.85, 1.85), weapon.Glow, Enum.Material.ForceField)
	weld(handle, shell, CFrame.identity)
	for i = -1, 1 do
		crystal(model, handle, "Knuckle", Vector3.new(0.4, 0.4, 0.7), CFrame.new(i * 0.45, -0.5, -0.85) * CFrame.Angles(0, 0, math.rad(45)), spikeColor, weapon.Glow)
	end
	crystal(model, handle, "Cuff", Vector3.new(1.7, 0.4, 1.7), CFrame.new(0, 0.85, 0), weapon.Glow, weapon.Color)
	sparkles(handle, weapon.Glow, 14)
	if emitterTexture then
		local flame = sparkles(handle, weapon.Color, 18, emitterTexture)
		flame.Name = "Element"
		flame.Size = NumberSequence.new(0.8, 0)
		flame.Acceleration = Vector3.new(0, 6, 0)
	end
	glowLight(handle, weapon.Color, 14)
	swingTrail(handle, Vector3.new(0, 0.4, 0), Vector3.new(0, -0.6, -1), weapon.Color, weapon.Glow)
	return handle
end

RECIPES.PowerGauntlet = function(model, character, weapon)
	return gauntlet(model, character, weapon, Color3.fromRGB(255, 220, 140), FIRE)
end

RECIPES.FrostGauntlet = function(model, character, weapon)
	return gauntlet(model, character, weapon, Color3.fromRGB(230, 250, 255), nil)
end

RECIPES.ForgeHammer = function(model, character, weapon)
	local hand = bodyPart(character, "RightHand", "Right Arm")
	if not hand then
		return nil
	end
	local handle = part(model, "Handle", Vector3.new(0.45, 0.45, 6), Color3.fromRGB(90, 70, 80), Enum.Material.Metal)
	weld(hand, handle, CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, 0, -1.6), "Grip")
	local head = crystal(model, handle, "Head", Vector3.new(3.4, 2, 2), CFrame.new(0, 0, -3.6), weapon.Color, weapon.Glow)
	crystal(model, handle, "Band", Vector3.new(0.5, 2.3, 2.3), CFrame.new(0, 0, -3.6), weapon.Glow, weapon.Color)
	for _, side in { -1, 1 } do
		crystal(model, handle, "Facet", Vector3.new(0.9, 0.9, 0.9), CFrame.new(side * 1.9, 0, -3.6) * CFrame.Angles(math.rad(45), 0, math.rad(45)), weapon.Glow, weapon.Color)
	end
	sparkles(head, weapon.Color, 14)
	glowLight(head, weapon.Color, 16)
	swingTrail(handle, Vector3.new(0, 0, -2.6), Vector3.new(0, 0, -4.6), weapon.Color, weapon.Glow)
	return handle
end

RECIPES.RamCrest = function(model, character, weapon)
	local head = bodyPart(character, "Head", "Head")
	if not head then
		return nil
	end
	local handle = part(model, "Handle", Vector3.new(1.4, 0.35, 1.3), weapon.Color, Enum.Material.Neon)
	weld(head, handle, CFrame.new(0, 0.45, -0.1), "Grip")
	for _, side in { -1, 1 } do
		crystal(model, handle, "HornBase", Vector3.new(0.45, 1.2, 0.45), CFrame.new(side * 0.6, 0.5, -0.2) * CFrame.Angles(math.rad(-20), 0, math.rad(side * -30)), weapon.Color, weapon.Glow)
		crystal(model, handle, "HornTip", Vector3.new(0.35, 1, 0.35), CFrame.new(side * 1.05, 1.15, -0.55) * CFrame.Angles(math.rad(-50), 0, math.rad(side * -55)), weapon.Glow, weapon.Color)
	end
	local fin = crystal(model, handle, "Fin", Vector3.new(0.15, 0.9, 1.4), CFrame.new(0, 0.55, 0.1), weapon.Glow, weapon.Color)
	sparkles(fin, weapon.Color, 10)
	glowLight(fin, weapon.Color)
	swingTrail(handle, Vector3.new(0, 0.3, -0.7), Vector3.new(0, 1.2, -0.7), weapon.Color, weapon.Glow)
	return handle
end

RECIPES.ArcDrones = function(model, character, weapon)
	local root = bodyPart(character, "HumanoidRootPart", "HumanoidRootPart")
	if not root then
		return nil
	end
	local first: BasePart? = nil
	for i = 1, 3 do
		local drone = part(model, "Drone" .. i, Vector3.new(0.9, 0.9, 0.9), weapon.Color, Enum.Material.Neon)
		local a = (i - 1) / 3 * math.pi * 2
		local w = weld(root, drone, CFrame.new(math.cos(a) * 3, 2.2, math.sin(a) * 3) * CFrame.Angles(math.rad(45), 0, math.rad(45)), if i == 1 then "Grip" else "DroneWeld")
		w:SetAttribute("Anim", "Orbit")
		w:SetAttribute("Index", i)
		local shell = part(model, "Drone" .. i .. "Shell", Vector3.new(1.2, 1.2, 1.2), weapon.Glow, Enum.Material.ForceField)
		weld(drone, shell, CFrame.identity)
		sparkles(drone, weapon.Color, 6)
		glowLight(drone, weapon.Color, 8)
		first = first or drone
	end
	return first
end

RECIPES.TideWings = function(model, character, weapon)
	local torso = bodyPart(character, "UpperTorso", "Torso")
	if not torso then
		return nil
	end
	local handle = part(model, "Handle", Vector3.new(0.6, 0.6, 0.3), weapon.Glow, Enum.Material.Neon)
	weld(torso, handle, CFrame.new(0, 0.3, 0.65), "Grip")
	for _, side in { -1, 1 } do
		local root = part(model, "WingRoot", Vector3.new(0.3, 0.3, 0.3), weapon.Color, Enum.Material.Neon)
		local w = weld(handle, root, CFrame.new(side * 0.35, 0, 0.1))
		w:SetAttribute("Anim", "Flap")
		w:SetAttribute("Side", side)
		for f = 1, 4 do
			local length = 4.2 - f * 0.55
			local feather = part(model, "Feather", Vector3.new(length, 0.15, 1.1), weapon.Color, Enum.Material.Glass)
			feather.Transparency = 0.25
			weld(root, feather, CFrame.Angles(0, 0, math.rad(side * (18 - f * 14))) * CFrame.new(side * length / 2, 0, f * 0.15))
			local shell = part(model, "FeatherShell", Vector3.new(length, 0.3, 1.25), weapon.Glow, Enum.Material.ForceField)
			weld(feather, shell, CFrame.identity)
			if f == 1 then
				sparkles(feather, weapon.Glow, 16)
			end
		end
	end
	glowLight(handle, weapon.Color, 14)
	return handle
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function WeaponBuilder.Build(character: Model, weaponId: string): Model?
	local weapon = WeaponConfig.Get(weaponId)
	local recipe = RECIPES[weaponId]
	if not weapon or not recipe then
		warn(`[WeaponBuilder] Unknown weapon '{weaponId}'`)
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "SummonedWeapon"
	model:SetAttribute("WeaponId", weaponId)
	-- Build while parented to the character so welds resolve immediately.
	model.Parent = character

	local ok, handle = pcall(recipe, model, character, weapon)
	if not ok or not handle then
		warn(`[WeaponBuilder] Failed to build {weaponId}: {if ok then "missing body part" else handle}`)
		model:Destroy()
		return nil
	end
	model.PrimaryPart = handle
	return model
end

return WeaponBuilder
