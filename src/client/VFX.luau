-- VFX
-- Client renderer for everything weapon-related. The server only sends
-- lightweight WeaponFX events; all parts, tweens and particles are created
-- locally, so effects are smooth and cost nothing on the network.
--
-- Look: neon cores, ForceField-material shells (Roblox's animated shimmering
-- gradient), gradient beams/trails and sparkle bursts.
--
-- Also animates summoned weapons: swing poses (Grip weld C0), whip lashes,
-- orbiting drones and flapping wings.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))

local VFX = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local WHITE = Color3.new(1, 1, 1)

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalFX"
fxFolder.Parent = Workspace

VFX.Folder = fxFolder

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

local function tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
	t:Play()
	return t
end

local function fxPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = fxFolder
	return part
end

local function gradient(color: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, WHITE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 235)),
	})
end

local function emitter(parent: Instance, color: Color3, props: { [string]: any }?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Color = gradient(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0, 1)
	e.Lifetime = NumberRange.new(0.4, 0.9)
	e.Speed = NumberRange.new(6, 18)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Drag = 3
	e.Enabled = false
	for key, value in props or {} do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- One-shot sparkle burst at a position.
local function sparkleBurst(position: Vector3, color: Color3, count: number, speed: number?)
	local holder = fxPart({ Size = Vector3.one * 0.1, Transparency = 1, CFrame = CFrame.new(position) })
	local e = emitter(holder, color, { Speed = NumberRange.new((speed or 14) * 0.5, speed or 14) })
	e:Emit(count)
	Debris:AddItem(holder, 1.5)
end

local function rootOf(model: Instance?): BasePart?
	if not model or not model:IsA("Model") then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

local Effects: { [string]: (params: any) -> () } = {}

Effects.Burst = function(p)
	local radius = p.Radius or 4
	local duration = p.Duration or 0.45
	local shell = fxPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1,
		CFrame = CFrame.new(p.Position),
		Color = p.Color,
		Material = Enum.Material.ForceField,
	})
	local core = fxPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.5,
		CFrame = CFrame.new(p.Position),
		Color = WHITE,
		Transparency = 0.1,
	})
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = radius * 3
	light.Brightness = 3
	light.Parent = core
	tween(shell, duration, { Size = Vector3.one * radius * 2, Transparency = 1 })
	tween(core, duration * 0.7, { Size = Vector3.one * radius * 1.2, Transparency = 1 })
	tween(light, duration, { Brightness = 0 })
	sparkleBurst(p.Position, p.Color, math.clamp(math.floor(radius * 4), 8, 40), radius * 3)
	Debris:AddItem(shell, duration)
	Debris:AddItem(core, duration)
end

Effects.Ring = function(p)
	local radius = p.Radius or 10
	local position = p.Position
	if p.Style == "Telegraph" then
		-- Warning circle that pulses until the effect lands.
		local disc = fxPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, radius * 2, radius * 2),
			CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = p.Color,
			Material = Enum.Material.ForceField,
			Transparency = 0.2,
		})
		Debris:AddItem(disc, p.Duration or 0.5)
		return
	end
	local color = if p.Style == "Fire" then Color3.fromRGB(255, 140, 60) else p.Color
	local duration = 0.55
	local wave = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 2, 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.ForceField,
	})
	local edge = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = wave.CFrame,
		Color = WHITE,
		Transparency = 0.3,
	})
	tween(wave, duration, { Size = Vector3.new(1.2, radius * 2, radius * 2), Transparency = 1 })
	tween(edge, duration, { Size = Vector3.new(0.3, radius * 2.05, radius * 2.05), Transparency = 1 })
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		sparkleBurst(position + Vector3.new(math.cos(a) * radius * 0.8, 1, math.sin(a) * radius * 0.8), color, 3, 8)
	end
	if p.Style == "Fire" then
		local holder = fxPart({ Size = Vector3.new(radius * 2, 1, radius * 2), CFrame = CFrame.new(position), Transparency = 1 })
		local flames = emitter(holder, color, {
			Texture = FIRE,
			Shape = Enum.ParticleEmitterShape.Box,
			Speed = NumberRange.new(2, 6),
			Acceleration = Vector3.new(0, 10, 0),
			Size = NumberSequence.new(2, 0),
		})
		flames:Emit(60)
		Debris:AddItem(holder, 1.5)
	end
	Debris:AddItem(wave, duration)
	Debris:AddItem(edge, duration)
end

Effects.Line = function(p)
	local duration = p.Duration or 0.3
	local holder = fxPart({ Size = Vector3.one * 0.1, Transparency = 1, CFrame = CFrame.new(p.From) })
	local a0 = Instance.new("Attachment")
	a0.Position = holder.CFrame:PointToObjectSpace(p.From)
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Position = holder.CFrame:PointToObjectSpace(p.To)
	a1.Parent = holder

	local width = p.Width or 1
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 20
	beam.Width0 = width
	beam.Width1 = width * 0.6
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.3, p.Color),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 235)),
	})
	beam.Transparency = NumberSequence.new(0)
	beam.Parent = holder
	if p.Style == "Lasso" then
		beam.CurveSize0 = 4
		beam.CurveSize1 = -3
	end

	sparkleBurst(p.To, p.Color, 10, 10)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / duration
		if t >= 1 or not holder.Parent then
			connection:Disconnect()
			holder:Destroy()
			return
		end
		if p.Style == "Zap" then
			beam.CurveSize0 = math.random(-4, 4)
			beam.CurveSize1 = math.random(-4, 4)
		elseif p.Style == "Tractor" then
			beam.Width0 = width * (1 + math.sin(os.clock() * 30) * 0.25)
		end
		beam.Transparency = NumberSequence.new(math.max(0, t * 1.2 - 0.2))
	end)
end

-- Live projectiles keyed by server id.
local projectiles: { [number]: { Part: BasePart, Ended: boolean } } = {}

Effects.Projectile = function(p)
	local size = p.Size or 1.5
	local part: BasePart
	if p.Style == "Spear" then
		part = fxPart({ Size = Vector3.new(0.4, 0.4, size * 3), Color = p.Color })
	else
		part = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, Color = if p.Style == "Water" then Color3.fromRGB(150, 220, 255) else p.Color })
	end
	local shell = fxPart({
		Shape = part.Shape,
		Size = part.Size * 1.5,
		Color = p.Color,
		Material = Enum.Material.ForceField,
	})
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.4, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.4, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = gradient(p.Color)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = part
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = 10
	light.Brightness = 2
	light.Parent = part
	local sparkles = emitter(part, p.Color, { Enabled = true, Rate = 40, Speed = NumberRange.new(0.5, 2), Lifetime = NumberRange.new(0.2, 0.5) })
	local _ = sparkles

	local entry = { Part = part, Ended = false }
	projectiles[p.Id] = entry

	local dir = p.Direction.Unit
	local orientation = CFrame.lookAt(Vector3.zero, dir)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local traveled = math.min((os.clock() - started) * p.Speed, p.Range)
		if entry.Ended or traveled >= p.Range then
			connection:Disconnect()
			projectiles[p.Id] = nil
			part:Destroy()
			shell:Destroy()
			return
		end
		local cf = orientation + (p.Origin + dir * traveled)
		part.CFrame = cf
		shell.CFrame = cf
	end)
end

Effects.ProjectileEnd = function(p)
	local entry = projectiles[p.Id]
	if entry then
		entry.Ended = true
	end
	Effects.Burst({ Position = p.Position, Radius = 2.5, Color = p.Color, Duration = 0.3 })
end

-- Status/buff auras attached to a character for a duration.
Effects.Aura = function(p)
	local root = rootOf(p.Target)
	if not root then
		return
	end
	local duration = p.Duration or 3
	local attachment = Instance.new("Attachment")
	attachment.Name = "AuraFX"
	attachment.Parent = root

	local e = emitter(attachment, p.Color, {
		Enabled = true,
		Rate = 24,
		Speed = NumberRange.new(1, 4),
		Lifetime = NumberRange.new(0.6, 1.2),
		Acceleration = Vector3.new(0, 4, 0),
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
	if p.Style == "Fire" then
		e.Texture = FIRE
		e.Size = NumberSequence.new(1.6, 0)
		e.Rate = 30
	end
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = attachment

	local extras: { Instance } = { attachment }
	if p.Style == "Shield" or p.Style == "Foresight" or p.Style == "Buff" or p.Style == "Echo" then
		local bubble = Instance.new("Part")
		bubble.Name = "AuraBubble"
		bubble.Shape = Enum.PartType.Ball
		bubble.Size = Vector3.one * (if p.Style == "Shield" then 8 else 7)
		bubble.Color = p.Color
		bubble.Material = Enum.Material.ForceField
		bubble.CanCollide = false
		bubble.CanQuery = false
		bubble.CanTouch = false
		bubble.Massless = true
		bubble.CastShadow = false
		bubble.Transparency = if p.Style == "Shield" then 0 else 0.4
		bubble.CFrame = root.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = bubble
		weld.Parent = bubble
		bubble.Parent = fxFolder
		table.insert(extras, bubble)
	end
	if p.Style == "Comet" then
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * 7
		ball.Color = p.Color
		ball.Material = Enum.Material.ForceField
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.Massless = true
		ball.CFrame = root.CFrame
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = ball
		weld.Parent = ball
		ball.Parent = fxFolder
		table.insert(extras, ball)
		e.Rate = 80
	end

	task.delay(duration, function()
		e.Enabled = false
		for _, instance in extras do
			if instance:IsA("BasePart") then
				tween(instance, 0.3, { Transparency = 1 })
			end
		end
		task.wait(1)
		for _, instance in extras do
			instance:Destroy()
		end
	end)
end

Effects.Freeze = function(p)
	local root = rootOf(p.Target)
	if not root then
		return
	end
	local ice = Instance.new("Part")
	ice.Name = "FreezeBlock"
	ice.Size = Vector3.new(5, 7, 5)
	ice.Color = Color3.fromRGB(190, 235, 255)
	ice.Material = Enum.Material.Glass
	ice.Transparency = 0.35
	ice.CanCollide = false
	ice.CanQuery = false
	ice.CanTouch = false
	ice.Massless = true
	ice.CFrame = root.CFrame * CFrame.new(0, -0.5, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = ice
	weld.Parent = ice
	local shell = ice:Clone()
	shell.Size += Vector3.one * 0.4
	shell.Material = Enum.Material.ForceField
	shell.Transparency = 0
	shell:FindFirstChildOfClass("WeldConstraint"):Destroy()
	local shellWeld = Instance.new("WeldConstraint")
	shellWeld.Part0 = root
	shellWeld.Part1 = shell
	shellWeld.Parent = shell
	ice.Parent = fxFolder
	shell.Parent = fxFolder
	sparkleBurst(root.Position, Color3.fromRGB(200, 240, 255), 30, 12)
	task.delay(p.Duration or 2, function()
		sparkleBurst(ice.Position, Color3.fromRGB(200, 240, 255), 24, 16)
		ice:Destroy()
		shell:Destroy()
	end)
end

Effects.Spike = function(p)
	local height = p.Height or 5
	local isHand = p.Style == "Hand"
	local spike = fxPart({
		Size = if isHand then Vector3.new(4, height, 4) else Vector3.new(1.8, height, 1.8),
		Color = p.Color,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
	})
	local tilt = if isHand then CFrame.identity else CFrame.Angles(math.rad(math.random(-15, 15)), math.random() * math.pi, math.rad(math.random(-15, 15)))
	local up = CFrame.new(p.Position + Vector3.new(0, height / 2 - 0.5, 0)) * tilt * CFrame.Angles(0, math.rad(45), 0)
	local down = up - Vector3.new(0, height, 0)
	spike.CFrame = down
	local shell = fxPart({
		Size = spike.Size * 1.15,
		CFrame = down,
		Color = WHITE,
		Material = Enum.Material.ForceField,
	})
	tween(spike, 0.12, { CFrame = up }, Enum.EasingStyle.Back)
	tween(shell, 0.12, { CFrame = up }, Enum.EasingStyle.Back)
	sparkleBurst(p.Position + Vector3.new(0, 1, 0), p.Color, 8, 10)
	task.delay(0.9, function()
		tween(spike, 0.35, { CFrame = down, Transparency = 1 })
		tween(shell, 0.35, { CFrame = down, Transparency = 1 })
		Debris:AddItem(spike, 0.4)
		Debris:AddItem(shell, 0.4)
	end)
end

Effects.Wave = function(p)
	local dir = p.Direction.Unit
	local orientation = CFrame.lookAt(Vector3.zero, dir)
	local wave = fxPart({
		Size = Vector3.new(p.Width, 12, 5),
		Color = Color3.fromRGB(110, 190, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
	})
	local crest = fxPart({
		Size = Vector3.new(p.Width + 1, 13, 6),
		Color = p.Color,
		Material = Enum.Material.ForceField,
	})
	local foam = emitter(crest, WHITE, {
		Enabled = true,
		Rate = 120,
		Shape = Enum.ParticleEmitterShape.Box,
		Speed = NumberRange.new(4, 10),
		Lifetime = NumberRange.new(0.4, 0.8),
		Acceleration = Vector3.new(0, -10, 0),
	})
	local _ = foam
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local traveled = (os.clock() - started) * p.Speed
		if traveled >= p.Length then
			connection:Disconnect()
			tween(wave, 0.4, { Transparency = 1 })
			tween(crest, 0.4, { Transparency = 1 })
			Debris:AddItem(wave, 0.45)
			Debris:AddItem(crest, 0.45)
			return
		end
		-- Rises quickly, then rolls forward.
		local rise = math.min(1, traveled / 10)
		local cf = orientation + (p.Origin + dir * traveled + Vector3.new(0, 6 * rise, 0))
		wave.CFrame = cf
		crest.CFrame = cf
	end)
end

-- Short burst of speed lines + sparkles following a dashing character.
Effects.Dash = function(p)
	local root = rootOf(p.Caster)
	if not root then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.6, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.6, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = gradient(p.Color)
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = root
	local e = emitter(a0, p.Color, { Enabled = true, Rate = 60, Speed = NumberRange.new(1, 3) })
	sparkleBurst(root.Position, p.Color, 16, 12)
	task.delay(p.Duration or 0.4, function()
		e.Enabled = false
		trail.Enabled = false
		task.wait(0.5)
		a0:Destroy()
		a1:Destroy()
		trail:Destroy()
	end)
end

Effects.Damage = function(p)
	local model = p.Target
	local root = rootOf(model)
	if not root then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(math.random(-15, 15) / 10, 3.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = root
	billboard.Parent = fxFolder

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(60, 30, 80)
	if p.Text then
		label.Text = p.Text
	else
		label.Text = tostring(p.Amount or 0) .. (if (p.Absorbed or 0) > 0 then `  ⬡{p.Absorbed}` else "")
	end
	label.TextColor3 = p.Color or (if (p.Absorbed or 0) > 0 and (p.Amount or 0) == 0 then Color3.fromRGB(150, 230, 255) else WHITE)
	label.Parent = billboard
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new(WHITE, Color3.fromRGB(255, 200, 240))
	shine.Rotation = 90
	shine.Parent = label

	tween(billboard, 0.8, { StudsOffsetWorldSpace = billboard.StudsOffsetWorldSpace + Vector3.new(0, 3, 0) })
	task.delay(0.35, function()
		tween(label, 0.45, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(billboard, 0.85)
end

--------------------------------------------------------------------------------
-- Weapon animation
--------------------------------------------------------------------------------

local restC0: { [Weld]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local swingTokens: { [Weld]: number } = setmetatable({}, { __mode = "k" }) :: any

local function getWeapon(character: Instance?): Model?
	local model = character and character:FindFirstChild("SummonedWeapon")
	return if model and model:IsA("Model") then model else nil
end

local function getGrip(weapon: Model): Weld?
	for _, d in weapon:GetDescendants() do
		if d:IsA("Weld") and d.Name == "Grip" then
			return d
		end
	end
	return nil
end

local function rest(weld: Weld): CFrame
	local c0 = restC0[weld]
	if not c0 then
		c0 = weld.C0
		restC0[weld] = c0
	end
	return c0
end

-- Pose transforms are applied in the body part's space on top of the rest C0.
local R = math.rad
local POSES: { [string]: { { CFrame | number } } } = {
	Thrust = {
		{ CFrame.new(0, 0, 1) * CFrame.Angles(R(-80), 0, 0), 0.06 },
		{ CFrame.new(0, 0, -3) * CFrame.Angles(R(-90), 0, 0), 0.07 },
		{ CFrame.new(0, 0, -3) * CFrame.Angles(R(-90), 0, 0), 0.08 },
	},
	Slash = {
		{ CFrame.Angles(0, R(80), 0) * CFrame.Angles(R(-90), 0, 0), 0.07 },
		{ CFrame.Angles(0, R(-80), 0) * CFrame.Angles(R(-90), 0, 0), 0.1 },
	},
	Smash = {
		{ CFrame.Angles(R(35), 0, 0), 0.1 },
		{ CFrame.new(0, 0, -1) * CFrame.Angles(R(-110), 0, 0), 0.09 },
		{ CFrame.new(0, 0, -1) * CFrame.Angles(R(-110), 0, 0), 0.12 },
	},
	WindUp = {
		{ CFrame.Angles(R(45), 0, 0), 0.25 },
	},
	Punch = {
		{ CFrame.new(0, 0.2, 0.6), 0.04 },
		{ CFrame.new(0, 0.2, -2.6), 0.06 },
		{ CFrame.new(0, 0.2, -2.6), 0.05 },
	},
	Headbutt = {
		{ CFrame.new(0, 0.2, 0.5), 0.06 },
		{ CFrame.new(0, -0.2, -1.4), 0.07 },
	},
	Lash = {
		{ CFrame.Angles(R(30), R(50), 0), 0.07 },
		{ CFrame.Angles(R(-40), R(-50), 0), 0.1 },
	},
	Spin = {
		{ CFrame.Angles(0, R(120), 0), 0.1 },
		{ CFrame.Angles(0, R(240), 0), 0.1 },
		{ CFrame.Angles(0, R(360), 0), 0.1 },
	},
}

local function playPoses(weld: Weld, poses: { { CFrame | number } }, mirror: boolean)
	local base = rest(weld)
	local token = (swingTokens[weld] or 0) + 1
	swingTokens[weld] = token
	task.spawn(function()
		for _, step in poses do
			if swingTokens[weld] ~= token or not weld.Parent then
				return
			end
			local transform = step[1] :: CFrame
			if mirror then
				local x, y, z = transform:ToEulerAnglesXYZ()
				transform = CFrame.new(-transform.X, transform.Y, transform.Z) * CFrame.Angles(x, -y, -z)
			end
			local seconds = step[2] :: number
			tween(weld, seconds, { C0 = transform * base }, Enum.EasingStyle.Quad)
			task.wait(seconds)
		end
		if swingTokens[weld] == token and weld.Parent then
			tween(weld, 0.25, { C0 = base }, Enum.EasingStyle.Sine)
		end
	end)
end

local function flashTrail(weapon: Model, duration: number)
	for _, d in weapon:GetDescendants() do
		if d:IsA("Trail") and d.Name == "SwingTrail" then
			d.Enabled = true
			task.delay(duration, function()
				d.Enabled = false
			end)
		end
	end
end

local function lashWhip(weapon: Model)
	local beam: Beam? = nil
	local tip: Attachment? = nil
	for _, d in weapon:GetDescendants() do
		if d:IsA("Beam") and d.Name == "WhipBeam" then
			beam = d
		elseif d:IsA("Attachment") and d.Name == "WhipTip" then
			tip = d
		end
	end
	if not beam or not tip then
		return
	end
	local restPosition = tip:GetAttribute("RestPosition") or tip.Position
	tip:SetAttribute("RestPosition", restPosition)
	tween(tip, 0.08, { Position = Vector3.new(0, 1, -14) })
	tween(beam, 0.08, { CurveSize0 = -5 })
	task.delay(0.16, function()
		tween(tip, 0.3, { Position = restPosition }, Enum.EasingStyle.Back)
		tween(beam, 0.3, { CurveSize0 = 3 })
	end)
end

Effects.Swing = function(p)
	local weapon = getWeapon(p.Caster)
	if not weapon then
		return
	end
	local style = p.Style
	local weaponId = weapon:GetAttribute("WeaponId")
	if weaponId == "LightWhip" and (style == "Lash" or style == "Spin") then
		lashWhip(weapon)
	end
	if weaponId == "ForgeHammer" and style == "Thrust" then
		style = "Smash"
	end
	if weaponId == "EnergySpear" and style == "Lash" then
		style = "Slash"
	end

	local poses = POSES[style]
	local grip = getGrip(weapon)
	if poses and grip and weaponId ~= "ArcDrones" and weaponId ~= "TideWings" then
		-- Alternate direction on combo hits for variety.
		playPoses(grip, poses, (p.Combo or 1) == 2)
		flashTrail(weapon, 0.3)
	end
	if style == "Cast" then
		local handle = weapon.PrimaryPart
		if handle then
			local config = WeaponConfig.Get(weaponId)
			sparkleBurst(handle.Position, if config then config.Color else WHITE, 10, 8)
		end
	end
end

Effects.Summon = function(p)
	local character = p.Caster
	local config = WeaponConfig.Get(p.WeaponId)
	local color = if config then config.Color else WHITE
	-- The weapon may arrive a frame after the event; wait briefly for it.
	local weapon = getWeapon(character)
	local waited = 0
	while not weapon and waited < 1 do
		waited += task.wait()
		weapon = getWeapon(character)
	end
	if not weapon then
		return
	end

	-- Light pours from the gemstone into the weapon.
	local gem: BasePart? = nil
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Gemstone" then
			gem = child
		end
	end
	local handle = weapon.PrimaryPart
	if gem and handle then
		Effects.Line({ From = gem.Position, To = handle.Position, Color = color, Width = 1.2, Duration = 0.35 })
		sparkleBurst(gem.Position, color, 20, 8)
	end

	-- Materialise: every part fades in from fully transparent.
	for _, d in weapon:GetDescendants() do
		if d:IsA("BasePart") then
			local target = d.Transparency
			d.Transparency = 1
			tween(d, 0.4 + math.random() * 0.2, { Transparency = target }, Enum.EasingStyle.Sine)
		end
	end
	if handle then
		Effects.Burst({ Position = handle.Position, Radius = 3, Color = color, Duration = 0.4 })
	end
end

Effects.Dismiss = function(p)
	local weapon = getWeapon(p.Caster)
	if not weapon then
		return
	end
	local config = WeaponConfig.Get(p.WeaponId)
	for _, d in weapon:GetDescendants() do
		if d:IsA("BasePart") then
			tween(d, 0.2, { Transparency = 1 })
		end
	end
	if weapon.PrimaryPart then
		sparkleBurst(weapon.PrimaryPart.Position, if config then config.Color else WHITE, 16, 10)
	end
end

-- Orbiting drones and flapping wings for every summoned weapon in view.
local function animateIdle()
	local t = os.clock()
	for _, player in Players:GetPlayers() do
		local weapon = getWeapon(player.Character)
		if weapon then
			for _, d in weapon:GetDescendants() do
				if d:IsA("Weld") then
					local anim = d:GetAttribute("Anim")
					if anim == "Orbit" then
						local i = d:GetAttribute("Index") or 1
						local a = t * 1.6 + (i - 1) / 3 * math.pi * 2
						d.C0 = CFrame.new(math.cos(a) * 3, 2.2 + math.sin(t * 2.4 + i) * 0.35, math.sin(a) * 3)
							* CFrame.Angles(t * 2 + i, t * 3, 0)
					elseif anim == "Flap" then
						local side = d:GetAttribute("Side") or 1
						d.C0 = rest(d) * CFrame.Angles(0, side * math.sin(t * 3.2) * 0.25, side * (0.15 + math.sin(t * 3.2) * 0.2))
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------

function VFX.Play(kind: string, params: any)
	local effect = Effects[kind]
	if effect then
		task.spawn(effect, params)
	end
end

function VFX.Start()
	local remote = ReplicatedStorage:WaitForChild("GemRemotes"):WaitForChild("WeaponFX") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: string, params: any)
		if type(kind) == "string" and type(params) == "table" then
			VFX.Play(kind, params)
		end
	end)
	RunService.RenderStepped:Connect(animateIdle)

	local _ = CombatConfig
end

return VFX
