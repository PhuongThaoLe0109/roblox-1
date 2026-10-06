-- WeaponBuilder
-- Builds the crystal weapon each fighter carries, coloured with the gem they
-- wear and shaped by their kit's melee style: blade, greatsword, twin
-- daggers, gauntlets, spear, scythe, hammer, whip or fans. Neon cores inside
-- tinted glass, faceted guards, a PointLight and a gradient swing trail.
-- Plain materials only (Neon / Glass / SmoothPlastic), no textures.
--
-- Client contract: Model "Weapon" in the character; its "Handle" part holds
-- the Trail "SwingTrail" (enabled by the client during swings).

local WeaponBuilder = {}

-- Weapons are built at this size: big, readable crystal arms.
WeaponBuilder.Scale = 1.45

local WHITE = Color3.new(1, 1, 1)
local GRIP_DARK = Color3.fromRGB(70, 50, 90)

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

local function hand(character: Model, side: string): BasePart?
	local names = if side == "Right" then { "RightHand", "Right Arm" } else { "LeftHand", "Left Arm" }
	for _, name in names do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			-- R6 arms are 2 studs long: grip at the bottom.
			return p
		end
	end
	return nil
end

local function gripOffset(handPart: BasePart): CFrame
	return if handPart.Size.Y > 1.5 then CFrame.new(0, -1, 0) else CFrame.new(0, -0.25, 0)
end

local function trail(handle: BasePart, from: number, to: number, color: Color3, accent: Color3, lifetime: number?)
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = Vector3.new(0, 0, from)
	a0.Parent = handle
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = Vector3.new(0, 0, to)
	a1.Parent = handle
	local t = Instance.new("Trail")
	t.Name = "SwingTrail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = lifetime or 0.2
	t.MinLength = 0.05
	t.LightEmission = 1
	t.LightInfluence = 0
	t.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.4, color),
		ColorSequenceKeypoint.new(1, accent),
	})
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.Enabled = false
	t.Parent = handle
end

local function glow(p: BasePart, color: Color3, range: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 9
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = p
end

-- A neon core inside a tinted glass sheath, along -Z from `at` on the handle.
local function bladeAlong(model: Model, handle: BasePart, at: number, length: number, width: number, color: Color3, tip: boolean?)
	local core = part(model, "Core", Vector3.new(width * 0.25, width * 0.5, length), WHITE, Enum.Material.Neon)
	weld(handle, core, CFrame.new(0, 0, at - length / 2))
	local edge = part(model, "Edge", Vector3.new(width * 0.4, width, length + 0.2), color, Enum.Material.Glass, 0.25)
	weld(handle, edge, CFrame.new(0, 0, at - length / 2))
	if tip ~= false then
		local point = part(model, "Tip", Vector3.new(width * 0.4, width * 0.72, width * 0.72), color, Enum.Material.Glass, 0.25)
		weld(handle, point, CFrame.new(0, 0, at - length - 0.1) * CFrame.Angles(math.rad(45), 0, 0))
	end
	glow(core, color)
	return core
end

local function guard(model: Model, handle: BasePart, z: number, width: number, color: Color3, accent: Color3)
	local bar = part(model, "Guard", Vector3.new(width, 0.28, 0.42), color, Enum.Material.Neon)
	weld(handle, bar, CFrame.new(0, 0, z))
	for _, side in { -1, 1 } do
		local gem = part(model, "GuardGem", Vector3.new(0.42, 0.42, 0.42), accent, Enum.Material.Glass, 0.1)
		weld(handle, gem, CFrame.new(side * width * 0.55, 0, z) * CFrame.Angles(0, math.rad(45), math.rad(45)))
	end
end

-- The handle runs along -Z toward the business end. `tilt` (degrees) angles
-- it down the line of the arm, so blades extend forward-and-out from the
-- fist and slashes follow the arm's arc.
local function newHandle(model: Model, handPart: BasePart, length: number, grip: CFrame?, name: string?, tilt: number?): Part
	local handle = part(model, name or "Handle", Vector3.new(0.32, 0.32, length), GRIP_DARK, Enum.Material.SmoothPlastic)
	weld(handPart, handle, gripOffset(handPart) * CFrame.Angles(math.rad(tilt or -50), 0, 0) * (grip or CFrame.identity), "Grip")
	return handle
end

local Builders: { [string]: (Model, Model, Color3, Color3) -> () } = {}

function Builders.Blade(model, character, color, accent)
	local right = hand(character, "Right")
	if not right then
		return
	end
	local handle = newHandle(model, right, 1.4)
	guard(model, handle, -0.8, 1.5, color, accent)
	bladeAlong(model, handle, -1, 3.8, 0.62, color)
	local pommel = part(model, "Pommel", Vector3.new(0.42, 0.42, 0.42), accent, Enum.Material.Neon)
	weld(handle, pommel, CFrame.new(0, 0, 0.85) * CFrame.Angles(math.rad(45), 0, math.rad(45)))
	trail(handle, -1.2, -4.9, color, accent)
end

function Builders.Greatsword(model, character, color, accent)
	local right = hand(character, "Right")
	if not right then
		return
	end
	local handle = newHandle(model, right, 1.8)
	guard(model, handle, -1, 2.4, color, accent)
	bladeAlong(model, handle, -1.2, 6.2, 1.15, color)
	-- Fuller gems along the flat of the blade.
	for i = 1, 3 do
		local gem = part(model, "Fuller", Vector3.new(0.5, 0.36, 0.36), accent, Enum.Material.Neon)
		weld(handle, gem, CFrame.new(0, 0, -1.8 - i * 1.4) * CFrame.Angles(math.rad(45), 0, 0))
	end
	trail(handle, -1.4, -7.6, color, accent, 0.26)
end

function Builders.Daggers(model, character, color, accent)
	for _, side in { "Right", "Left" } do
		local h = hand(character, side)
		if h then
			local handle = newHandle(model, h, 0.9, nil, if side == "Right" then "Handle" else "OffHandle")
			guard(model, handle, -0.5, 0.9, color, accent)
			bladeAlong(model, handle, -0.6, 2.2, 0.48, if side == "Right" then color else accent)
			trail(handle, -0.7, -3, color, accent, 0.15)
		end
	end
end

function Builders.Gauntlets(model, character, color, accent)
	for _, side in { "Right", "Left" } do
		local h = hand(character, side)
		if h then
			local fist = part(model, if side == "Right" then "Handle" else "OffHandle", Vector3.new(1.15, 1.15, 1.15), color, Enum.Material.Glass, 0.2)
			weld(h, fist, gripOffset(h) * CFrame.new(0, 0.1, 0))
			local core = part(model, "Core", Vector3.new(0.6, 0.6, 0.6), WHITE, Enum.Material.Neon)
			weld(fist, core, CFrame.Angles(math.rad(45), math.rad(45), 0))
			for k = -1, 1 do
				local spike = part(model, "Knuckle", Vector3.new(0.22, 0.22, 0.9), accent, Enum.Material.Neon)
				weld(fist, spike, CFrame.new(k * 0.35, 0, -0.75) * CFrame.Angles(0, 0, math.rad(45)))
			end
			glow(core, color, 8)
			trail(fist, 0.3, -1, color, accent, 0.18)
		end
	end
end

function Builders.Spear(model, character, color, accent)
	local right = hand(character, "Right")
	if not right then
		return
	end
	-- Held upright and tilted forward at rest; CombatAnim levels it to thrust.
	local handle = newHandle(model, right, 8, CFrame.new(0, 0, -1.4), nil, 40)
	for _, z in { -2.5, 0, 2.5 } do
		local ring = part(model, "Band", Vector3.new(0.45, 0.45, 0.25), accent, Enum.Material.Neon)
		weld(handle, ring, CFrame.new(0, 0, z))
	end
	bladeAlong(model, handle, -4, 2.4, 0.75, color)
	local wing = part(model, "Wing", Vector3.new(1.6, 0.2, 0.5), color, Enum.Material.Neon)
	weld(handle, wing, CFrame.new(0, 0, -4.1))
	trail(handle, -3.2, -6.6, color, accent)
end

function Builders.Scythe(model, character, color, accent)
	local right = hand(character, "Right")
	if not right then
		return
	end
	local handle = newHandle(model, right, 6.5, CFrame.new(0, 0, -1.2), nil, -62)
	-- The curved blade: a fan of shards sweeping back from the top.
	local top = -3.25
	for i = 0, 5 do
		local a = math.rad(10 + i * 16)
		local length = 1.4 - i * 0.12
		local shard = part(model, "Blade", Vector3.new(0.16, 0.7 - i * 0.07, length), if i % 2 == 0 then color else accent, Enum.Material.Glass, 0.2)
		local x = math.sin(a) * 1.6
		local z = top - math.cos(a) * 0.4 + i * 0.05
		weld(handle, shard, CFrame.new(x * 0.9 + 0.4, 0, z + 0.2) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -length / 2))
	end
	local core = part(model, "Core", Vector3.new(2.6, 0.2, 0.18), WHITE, Enum.Material.Neon)
	weld(handle, core, CFrame.new(1.3, 0, top + 0.05))
	glow(core, color)
	local gem = part(model, "Gem", Vector3.new(0.6, 0.6, 0.6), accent, Enum.Material.Neon)
	weld(handle, gem, CFrame.new(0, 0, top) * CFrame.Angles(math.rad(45), 0, math.rad(45)))
	trail(handle, -2.6, -3.4, color, accent, 0.25)
end

function Builders.Hammer(model, character, color, accent)
	local right = hand(character, "Right")
	if not right then
		return
	end
	local handle = newHandle(model, right, 4.4, CFrame.new(0, 0, -1), nil, -62)
	local head = part(model, "Head", Vector3.new(2.6, 1.6, 1.6), color, Enum.Material.Glass, 0.15)
	weld(handle, head, CFrame.new(0, 0, -2.6))
	local core = part(model, "Core", Vector3.new(2.7, 0.7, 0.7), WHITE, Enum.Material.Neon)
	weld(head, core, CFrame.identity)
	for _, side in { -1, 1 } do
		local face = part(model, "Face", Vector3.new(0.3, 1.2, 1.2), accent, Enum.Material.Neon)
		weld(head, face, CFrame.new(side * 1.35, 0, 0) * CFrame.Angles(math.rad(45), 0, 0))
	end
	glow(core, color, 11)
	trail(handle, -1.8, -3.4, color, accent, 0.25)
end

function Builders.Whip(model, character, color, accent)
	local right = hand(character, "Right")
	if not right then
		return
	end
	local handle = newHandle(model, right, 1.3)
	local previous: BasePart = handle
	-- A chain of crystal links hanging in a lazy curve.
	for i = 1, 9 do
		local link = part(model, "Link", Vector3.new(0.28, 0.28, 0.7), if i % 2 == 0 then color else accent, Enum.Material.Neon)
		weld(previous, link, CFrame.new(0, 0, -(if i == 1 then 0.9 else 0.65)) * CFrame.Angles(math.rad(-9), math.rad(4), 0))
		previous = link
	end
	local tip = part(model, "Tip", Vector3.new(0.5, 0.5, 0.5), WHITE, Enum.Material.Neon)
	weld(previous, tip, CFrame.new(0, 0, -0.5) * CFrame.Angles(math.rad(45), 0, math.rad(45)))
	glow(tip, color, 7)
	trail(handle, -0.8, -4.5, color, accent, 0.25)
end

function Builders.Fans(model, character, color, accent)
	for _, side in { "Right", "Left" } do
		local h = hand(character, side)
		if h then
			local handle = newHandle(model, h, 0.8, nil, if side == "Right" then "Handle" else "OffHandle")
			for i = -3, 3 do
				local rib = part(model, "Rib", Vector3.new(0.1, 0.12, 2.2), if i % 2 == 0 then color else accent, Enum.Material.Glass, 0.15)
				weld(handle, rib, CFrame.new(0, 0, -0.3) * CFrame.Angles(0, math.rad(i * 14), 0) * CFrame.new(0, 0, -1.1))
			end
			local edge = part(model, "Edge", Vector3.new(2.4, 0.14, 0.12), WHITE, Enum.Material.Neon)
			weld(handle, edge, CFrame.new(0, 0, -2.3))
			trail(handle, -1.2, -2.6, color, accent, 0.2)
		end
	end
end

-- Builds and welds the weapon for a melee style; returns the model.
function WeaponBuilder.Build(character: Model, style: string, color: Color3, accent: Color3): Model?
	local old = character:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	local builder = Builders[style]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Weapon"
	model:SetAttribute("Style", style)
	builder(model, character, color, accent)
	-- Scale the whole weapon about the hand: parts, welds (except the grip on
	-- the hand itself) and the trail attachments.
	local scale = WeaponBuilder.Scale
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size *= scale
		elseif d:IsA("Weld") and d.Name ~= "Grip" then
			d.C0 = d.C0 - d.C0.Position + d.C0.Position * scale
		elseif d:IsA("Attachment") then
			d.Position *= scale
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") and d.Part0 and d.Part1 then
			d.Part1.CFrame = d.Part0.CFrame * d.C0
		end
	end
	model.Parent = character
	return model
end

function WeaponBuilder.Remove(character: Model)
	local old = character:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
end

return WeaponBuilder
