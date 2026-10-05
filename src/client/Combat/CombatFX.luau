-- CombatFX
-- Every combat effect, drawn locally on each client from CombatFX events.
-- Nothing here uses textures, decals, ParticleEmitters or meshes: effects are
-- built from Neon / Glass parts, untextured Beams and Trails (whose colour and
-- transparency sequences give the show's soft gradients), PointLights and
-- Highlights. Every effect uses the caster's gem colours.
--
-- The local player's own swings / casts are drawn immediately by
-- CombatController (CombatFX.Play) and the server echo is skipped, so attacks
-- feel instant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local player = Players.LocalPlayer

local CombatFX = {}

local WHITE = Color3.new(1, 1, 1)

-- Effects the local player predicts (the server echo for their own character
-- is ignored).
local PREDICTED = {
	Swing = true,
	Cast = true,
	Launcher = true,
	Rush = true,
	Dash = true,
	NovaCharge = true,
}

local folder: Folder
local host: Part -- anchored at the origin; owns every world-space attachment

--------------------------------------------------------------------------------
-- Building blocks
--------------------------------------------------------------------------------

local function lerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- White-hot at 0, the gem colour in the middle, the accent at 1.
local function grad(color: Color3, accent: Color3, t: number): Color3
	if t < 0.35 then
		return lerp(WHITE, color, t / 0.35)
	end
	return lerp(color, accent, (t - 0.35) / 0.65)
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

local function part(size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0
	p.Size = size
	p.CFrame = cframe
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function attachment(position: Vector3, parent: Instance?): Attachment
	local a = Instance.new("Attachment")
	a.Position = position
	a.Parent = parent or host
	return a
end

-- Runs step(alpha, elapsed) every frame for `duration`, then cleanup().
local function run(duration: number, step: (number, number) -> (), cleanup: (() -> ())?)
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - started
		local alpha = math.min(1, elapsed / duration)
		local ok, err = pcall(step, alpha, elapsed)
		if not ok or alpha >= 1 then
			connection:Disconnect()
			if cleanup then
				cleanup()
			end
			if not ok then
				warn("[CombatFX] " .. tostring(err))
			end
		end
	end)
end

local function light(position: Vector3, color: Color3, range: number, brightness: number, duration: number)
	local holder = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), color, Enum.Material.SmoothPlastic, 1)
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Range = range
	pl.Brightness = brightness
	pl.Shadows = false
	pl.Parent = holder
	run(duration, function(alpha)
		pl.Brightness = brightness * (1 - alpha) ^ 2
	end, function()
		holder:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Ribbons: chains of untextured Beams with a colour gradient along them.
--------------------------------------------------------------------------------

type Ribbon = { Attachments: { Attachment }, Beams: { Beam } }

local function ribbon(points: { Vector3 }, widths: { number }, colors: { Color3 }, faceCamera: boolean?): Ribbon
	local r: Ribbon = { Attachments = {}, Beams = {} }
	for i, point in points do
		r.Attachments[i] = attachment(point)
	end
	for i = 1, #points - 1 do
		local beam = Instance.new("Beam")
		beam.Attachment0 = r.Attachments[i]
		beam.Attachment1 = r.Attachments[i + 1]
		beam.Width0 = widths[i]
		beam.Width1 = widths[i + 1]
		beam.Color = ColorSequence.new(colors[i], colors[i + 1])
		beam.Transparency = NumberSequence.new(1)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = if faceCamera == nil then true else faceCamera
		beam.Segments = 1
		beam.Parent = host
		r.Beams[i] = beam
	end
	return r
end

local function ribbonMove(r: Ribbon, points: { Vector3 })
	for i, point in points do
		local a = r.Attachments[i]
		if a then
			a.Position = point
		end
	end
end

local function ribbonWidths(r: Ribbon, widths: { number })
	for i, beam in r.Beams do
		beam.Width0 = widths[i]
		beam.Width1 = widths[i + 1]
	end
end

-- transparency(i) for each point; beams blend between their two ends.
local function ribbonFade(r: Ribbon, transparency: (number) -> number)
	local values = {}
	for i = 1, #r.Attachments do
		values[i] = math.clamp(transparency(i), 0, 1)
	end
	for i, beam in r.Beams do
		beam.Transparency = NumberSequence.new(values[i], values[i + 1])
	end
end

local function ribbonDestroy(r: Ribbon)
	for _, beam in r.Beams do
		beam:Destroy()
	end
	for _, a in r.Attachments do
		a:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Shapes
--------------------------------------------------------------------------------

-- A crescent slash sweeping from angle a0 to a1 (degrees) in the XZ plane of
-- `frame` (forward = -Z), rolled about the forward axis by `roll` degrees.
local function slash(frame: CFrame, radius: number, a0: number, a1: number, roll: number, width: number, color: Color3, accent: Color3, duration: number)
	local n = 16
	local plane = frame * CFrame.Angles(0, 0, math.rad(roll))
	local function pointsAt(scale: number): { Vector3 }
		local list = {}
		for i = 0, n do
			local a = math.rad(a0 + (a1 - a0) * i / n)
			list[i + 1] = plane:PointToWorldSpace(Vector3.new(math.sin(a), 0, -math.cos(a)) * radius * scale)
		end
		return list
	end
	local function widthsOf(w: number): { number }
		local list = {}
		for i = 0, n do
			local t = i / n
			-- Crescent: thin tail, thick just behind the head, sharp tip.
			list[i + 1] = w * (0.08 + 0.92 * math.sin(math.pi * math.min(1, t * 0.85 + 0.08)) * t ^ 0.6)
		end
		return list
	end
	local colorsCore, colorsGlow = {}, {}
	for i = 0, n do
		local t = 1 - i / n
		colorsCore[i + 1] = grad(color, accent, t * 0.8)
		colorsGlow[i + 1] = grad(color, accent, 0.3 + t * 0.7)
	end
	local glow = ribbon(pointsAt(1), widthsOf(width * 2.3), colorsGlow)
	local core = ribbon(pointsAt(1), widthsOf(width), colorsCore)
	local sweep = duration * 0.32
	run(duration, function(_, elapsed)
		local head = math.min(1, elapsed / sweep)
		local scale = 1 + 0.18 * easeOut(math.min(1, elapsed / duration))
		local points = pointsAt(scale)
		ribbonMove(glow, points)
		ribbonMove(core, points)
		local fadeSpan = duration - sweep
		local function fade(base: number)
			return function(i: number): number
				local t = (i - 1) / n
				if t > head + 1e-3 then
					return 1
				end
				local since = elapsed - t * sweep
				return base + (1 - base) * math.clamp(since / fadeSpan, 0, 1) ^ 1.5
			end
		end
		ribbonFade(glow, fade(0.55))
		ribbonFade(core, fade(0))
	end, function()
		ribbonDestroy(glow)
		ribbonDestroy(core)
	end)
end

-- A glowing ring in the XZ plane of `frame` growing from r0 to r1.
local function ring(frame: CFrame, r0: number, r1: number, w0: number, w1: number, color: Color3, accent: Color3, duration: number, sides: number?, startTransparency: number?)
	local n = sides or 28
	local function pointsAt(radius: number): { Vector3 }
		local list = {}
		for i = 0, n do
			local a = i / n * math.pi * 2
			list[i + 1] = frame:PointToWorldSpace(Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
		end
		return list
	end
	local colors, widths = {}, {}
	for i = 0, n do
		colors[i + 1] = grad(color, accent, 0.25 + 0.6 * (0.5 + 0.5 * math.sin(i / n * math.pi * 4)))
		widths[i + 1] = w0
	end
	local r = ribbon(pointsAt(r0), widths, colors, false)
	-- Lie flat in the ring's plane: point each attachment's axes along the ring.
	local up = frame.UpVector
	local function orient()
		for i, a in r.Attachments do
			local outward = (a.Position - frame.Position)
			if outward.Magnitude > 1e-3 then
				a.CFrame = CFrame.fromMatrix(a.Position, up:Cross(outward.Unit), up)
			end
			local _ = i
		end
	end
	orient()
	local base = startTransparency or 0.05
	run(duration, function(alpha)
		local e = easeOut(alpha)
		ribbonMove(r, pointsAt(r0 + (r1 - r0) * e))
		orient()
		local w = w0 + (w1 - w0) * e
		local list = table.create(n + 1, w)
		ribbonWidths(r, list)
		ribbonFade(r, function()
			return base + (1 - base) * alpha ^ 1.6
		end)
	end, function()
		ribbonDestroy(r)
	end)
end

-- Neon diamond sparks flying out of `position`.
local function burst(position: Vector3, color: Color3, accent: Color3, count: number, speed: number, size: number, life: number, bias: Vector3?)
	for i = 1, count do
		local dir = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5)
		if bias then
			dir += bias
		end
		dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
		local tint = if i % 3 == 0 then WHITE elseif i % 3 == 1 then color else accent
		local s = size * (0.6 + math.random() * 0.6)
		local spark = part(Vector3.new(s * 0.5, s * 0.5, s * 2.2), CFrame.lookAt(position, position + dir), tint)
		local v = speed * (0.6 + math.random() * 0.7)
		local p = position
		run(life * (0.7 + math.random() * 0.5), function(alpha)
			p += dir * v * (1 - alpha) * (1 / 60)
			local k = 1 - alpha
			spark.Size = Vector3.new(s * 0.5 * k + 0.05, s * 0.5 * k + 0.05, s * 2.2 * k + 0.05)
			spark.CFrame = CFrame.lookAt(p, p + dir)
			spark.Transparency = alpha ^ 2
		end, function()
			spark:Destroy()
		end)
	end
end

-- A soft glowing sphere flash.
local function flash(position: Vector3, color: Color3, size0: number, size1: number, life: number, transparency: number?)
	local ball = part(Vector3.one * size0, CFrame.new(position), color)
	ball.Shape = Enum.PartType.Ball
	local base = transparency or 0.35
	run(life, function(alpha)
		local s = size0 + (size1 - size0) * easeOut(alpha)
		ball.Size = Vector3.one * s
		ball.Transparency = base + (1 - base) * alpha
	end, function()
		ball:Destroy()
	end)
end

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(position: Vector3): Vector3?
	local exclude: { Instance } = { folder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	castParams.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), castParams)
	return hit and hit.Position
end

-- Faceted crystal spikes erupting from the ground in a circle.
local function spikes(center: Vector3, count: number, radius: number, height: number, color: Color3, accent: Color3, life: number, delay: number?)
	local ground = groundBelow(center)
	if not ground then
		return
	end
	task.delay(delay or 0, function()
		for i = 1, count do
			local a = (i / count + math.random() * 0.04) * math.pi * 2
			local h = height * (0.7 + math.random() * 0.5)
			local w = h * 0.28
			local base = ground + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			local outward = Vector3.new(math.cos(a), 0, math.sin(a))
			local tilt = CFrame.fromAxisAngle(outward:Cross(Vector3.yAxis), -math.rad(18 + math.random() * 14))
			local shell = part(Vector3.new(w, h, w), CFrame.new(), if i % 2 == 0 then color else accent, Enum.Material.Glass, 0.15)
			local core = part(Vector3.new(w * 0.45, h * 0.92, w * 0.45), CFrame.new(), WHITE)
			local spin = CFrame.Angles(0, math.rad(45), 0)
			local function place(rise: number)
				local cf = CFrame.new(base) * tilt * CFrame.new(0, h / 2 - h * (1 - rise), 0) * spin
				shell.CFrame = cf
				core.CFrame = cf
			end
			place(0)
			run(life, function(alpha)
				if alpha < 0.12 then
					place(easeOut(alpha / 0.12))
				elseif alpha > 0.7 then
					local k = (alpha - 0.7) / 0.3
					place(1 - k)
					shell.Transparency = 0.15 + 0.85 * k
					core.Transparency = k
				else
					place(1)
				end
			end, function()
				shell:Destroy()
				core:Destroy()
			end)
		end
	end)
end

-- Short trail on a character's root.
local function rootTrail(character: Model, color: Color3, accent: Color3, duration: number, height: number?)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local h = height or 2.2
	local a0 = attachment(Vector3.new(0, h, 0), root)
	local a1 = attachment(Vector3.new(0, -h, 0), root)
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.28
	trail.MinLength = 0.05
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.35, color),
		ColorSequenceKeypoint.new(1, accent),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	trail.Parent = root
	task.delay(duration, function()
		trail.Enabled = false
		task.wait(0.35)
		trail:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
end

-- Fading neon silhouettes left behind a fast-moving character.
local function afterimages(character: Model, color: Color3, accent: Color3, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	task.spawn(function()
		local count = math.max(2, math.floor(duration / 0.05))
		for i = 1, count do
			if not root.Parent then
				return
			end
			local cf = (root :: BasePart).CFrame
			local ghost = part(Vector3.new(2.2, 4.6, 0.25), cf * CFrame.Angles(0, 0, math.rad(45)) * CFrame.new(0, 0, 0), lerp(color, accent, i / count), Enum.Material.Neon, 0.45)
			ghost.Size = Vector3.new(3.2, 3.2, 0.2)
			run(0.3, function(alpha)
				ghost.Transparency = 0.45 + 0.55 * alpha
				ghost.Size = Vector3.new(3.2, 3.2, 0.2) * (1 - 0.6 * alpha)
			end, function()
				ghost:Destroy()
			end)
			task.wait(0.05)
		end
	end)
end

local function damageNumber(position: Vector3, amount: number, color: Color3, accent: Color3, heavy: boolean)
	local anchor = attachment(position + Vector3.new((math.random() - 0.5) * 2, 2.2, (math.random() - 0.5) * 2))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 60)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Parent = anchor
	local text = if amount < 1 and amount > 0 then string.format("%.1f", amount) else tostring(math.floor(amount + 0.5))
	local label = Theme.label({
		Text = text,
		FontFace = Theme.Faces.Display,
		TextSize = if heavy then 40 else 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	Theme.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(0.55, if heavy then Theme.Colors.Gold else color),
			ColorSequenceKeypoint.new(1, accent),
		}),
		Rotation = 90,
		Parent = label,
	})
	local stroke = Theme.new("UIStroke", {
		Color = Color3.fromRGB(40, 16, 60),
		Thickness = 2.5,
		Transparency = 0.1,
		Parent = label,
	})
	local scale = Theme.new("UIScale", { Scale = 1.8, Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local start = anchor.Position
	run(0.9, function(alpha)
		anchor.Position = start + Vector3.new(0, easeOut(alpha) * 2.4, 0)
		if alpha > 0.55 then
			local k = (alpha - 0.55) / 0.45
			label.TextTransparency = k
			stroke.Transparency = 0.1 + 0.9 * k
		end
	end, function()
		anchor:Destroy()
	end)
end

local function hitFlash(character: Instance, color: Color3)
	if not character:IsA("Model") then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = WHITE
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.25
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = folder
	run(0.18, function(alpha)
		highlight.FillTransparency = 0.25 + 0.75 * alpha
		highlight.OutlineTransparency = alpha
	end, function()
		highlight:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Camera shake
--------------------------------------------------------------------------------

local trauma = 0

function CombatFX.Shake(amount: number)
	trauma = math.min(1, trauma + amount)
end

local function startShake()
	RunService:BindToRenderStep("PrismShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if trauma <= 0 then
			return
		end
		local camera = Workspace.CurrentCamera
		if camera then
			local t = os.clock() * 28
			local s = trauma * trauma
			camera.CFrame *= CFrame.Angles(
				math.rad(math.noise(t, 0.3) * 2.2 * s),
				math.rad(math.noise(0.7, t) * 2.2 * s),
				math.rad(math.noise(t, 1.9) * 1.4 * s)
			)
		end
		trauma = math.max(0, trauma - dt * 2.4)
	end)
end

--------------------------------------------------------------------------------
-- Arm & blade motion (Motor6D C0 only, so it layers over the idle animation)
--------------------------------------------------------------------------------

local baseC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local motionToken: { [Motor6D]: number } = setmetatable({}, { __mode = "k" }) :: any

local function shoulder(character: Model): Motor6D?
	local arm = character:FindFirstChild("RightUpperArm")
	local motor = arm and arm:FindFirstChild("RightShoulder")
	return if motor and motor:IsA("Motor6D") then motor else nil
end

-- Poses are (pitch, yaw) in degrees from the arm hanging at rest:
-- pitch raises the arm forward, positive yaw swings it across to the left.
local function armMotion(character: Model, wind: { number }, strike: { number }, windTime: number, strikeTime: number, hold: number)
	local motor = shoulder(character)
	if not motor then
		return
	end
	local base = baseC0[motor] or motor.C0
	baseC0[motor] = base
	local token = (motionToken[motor] or 0) + 1
	motionToken[motor] = token
	local function poseOf(p: { number }): CFrame
		return base * CFrame.fromEulerAnglesYXZ(math.rad(p[1]), math.rad(p[2]), math.rad(p[3] or 0))
	end
	local function tween(goal: CFrame, time: number, style: Enum.EasingStyle)
		TweenService:Create(motor, TweenInfo.new(time, style, Enum.EasingDirection.Out), { C0 = goal }):Play()
	end
	tween(poseOf(wind), windTime, Enum.EasingStyle.Quad)
	task.delay(windTime, function()
		if motionToken[motor] ~= token then
			return
		end
		tween(poseOf(strike), strikeTime, Enum.EasingStyle.Quint)
		task.delay(strikeTime + hold, function()
			if motionToken[motor] == token then
				tween(base, 0.25, Enum.EasingStyle.Sine)
			end
		end)
	end)
end

local function bladeTrail(character: Model, duration: number)
	local blade = character:FindFirstChild("CrystalBlade")
	local handle = blade and blade:FindFirstChild("Handle")
	local trail = handle and handle:FindFirstChild("SwingTrail")
	if trail and trail:IsA("Trail") then
		trail.Enabled = true
		task.delay(duration, function()
			trail.Enabled = false
		end)
	end
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

local function rootOf(character: any): BasePart?
	if typeof(character) ~= "Instance" then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function aimFrame(root: BasePart, direction: Vector3?, height: number?): CFrame
	local dir = direction or root.CFrame.LookVector
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(0, 0, -1)
	end
	local origin = root.Position + Vector3.new(0, height or 0.4, 0)
	return CFrame.lookAt(origin, origin + dir.Unit)
end

local function isLocal(character: any): boolean
	return character ~= nil and character == player.Character
end

local SWINGS = {
	-- a0, a1, roll, radius, width; arm wind / strike poses
	{ -80, 85, -12, 5.2, 1.3, { 70, 55 }, { 75, -70 } },
	{ 85, -80, 14, 5.2, 1.3, { 70, -70 }, { 75, 55 } },
	{ -85, 80, 52, 5.6, 1.5, { 150, -25 }, { 35, 40 } },
	{ 95, -55, 90, 6.6, 2.3, { 175, 0 }, { 25, 0 } },
}

local Effects: { [string]: (params: { [string]: any }) -> () } = {}

function Effects.Swing(params)
	local character = params.Caster
	local root = rootOf(character)
	if not root then
		return
	end
	local swing = SWINGS[params.Combo] or SWINGS[1]
	local frame = aimFrame(root, params.Direction, 0.5)
	local heavy = params.Combo == 4
	armMotion(character, swing[6], swing[7], 0.05, 0.1, if heavy then 0.2 else 0.08)
	bladeTrail(character, 0.24)
	task.delay(0.04, function()
		slash(frame, swing[4], swing[1], swing[2], swing[3], swing[5], params.Color, params.Accent, if heavy then 0.42 else 0.3)
		if heavy then
			slash(frame * CFrame.new(0, 0, 0.6), swing[4] * 0.8, swing[1], swing[2], swing[3], swing[5] * 0.6, params.Accent, params.Color, 0.36)
			local ahead = frame:PointToWorldSpace(Vector3.new(0, -1, -4))
			local ground = groundBelow(ahead)
			if ground then
				ring(CFrame.new(ground + Vector3.new(0, 0.15, 0)), 0.8, 7, 0.9, 0.2, params.Color, params.Accent, 0.4)
			end
		end
	end)
end

function Effects.Cast(params)
	local root = rootOf(params.Caster)
	if not root then
		return
	end
	local frame = aimFrame(root, params.Direction, 1.4)
	armMotion(params.Caster, { 60, 40 }, { 95, -10 }, 0.06, 0.1, 0.15)
	local sigil = frame * CFrame.new(0, 0, -2.4) * CFrame.Angles(math.rad(90), 0, 0)
	ring(sigil, 0.6, 2.6, 0.45, 0.15, params.Color, params.Accent, 0.32, 6)
	ring(sigil * CFrame.Angles(0, math.rad(30), 0), 1.6, 3.2, 0.25, 0.05, params.Accent, params.Color, 0.36, 6, 0.3)
	flash(sigil.Position, params.Color, 0.6, 3.2, 0.2)
	light(sigil.Position, params.Color, 14, 3, 0.3)
end

local projectiles: { [number]: { Stop: (Vector3?) -> () } } = {}

function Effects.Projectile(params)
	local origin: Vector3 = params.Origin
	local dir: Vector3 = params.Direction
	local speed: number = params.Speed
	local range: number = params.Range
	local color, accent = params.Color, params.Accent
	-- Catch up with the server for network latency.
	local offset = math.clamp(Workspace:GetServerTimeNow() - (params.Time or Workspace:GetServerTimeNow()), 0, 0.3)

	local shell = part(Vector3.new(0.9, 0.9, 3), CFrame.new(), color, Enum.Material.Glass, 0.2)
	local core = part(Vector3.new(0.35, 0.35, 2.4), CFrame.new(), WHITE)
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Range = 10
	pl.Brightness = 2.5
	pl.Parent = core
	local a0 = attachment(Vector3.new(0.4, 0, 1), core)
	local a1 = attachment(Vector3.new(-0.4, 0, 1), core)
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.22
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.3, color),
		ColorSequenceKeypoint.new(1, accent),
	})
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.1)
	trail.Parent = core

	local started = os.clock() - offset
	local stopped = false
	local connection
	local function stop(at: Vector3?)
		if stopped then
			return
		end
		stopped = true
		connection:Disconnect()
		projectiles[params.Id] = nil
		local position = at or core.Position
		burst(position, color, accent, 7, 22, 0.8, 0.3)
		flash(position, color, 0.8, 3.5, 0.18)
		shell:Destroy()
		core.Transparency = 1
		task.delay(0.25, function()
			core:Destroy()
		end)
	end
	connection = RunService.Heartbeat:Connect(function()
		local traveled = math.min(range, (os.clock() - started) * speed)
		local position = origin + dir * traveled
		local spin = CFrame.Angles(0, 0, os.clock() * 14)
		local cf = CFrame.lookAt(position, position + dir) * spin
		shell.CFrame = cf
		core.CFrame = cf
		if traveled >= range then
			stop(position)
		end
	end)
	projectiles[params.Id] = { Stop = stop }
	-- Safety net if the end event never arrives.
	task.delay(range / speed + 1, function()
		stop(nil)
	end)
end

function Effects.ProjectileEnd(params)
	local entry = projectiles[params.Id]
	if entry then
		entry.Stop(params.Position)
	end
end

function Effects.Launcher(params)
	local root = rootOf(params.Caster)
	if not root then
		return
	end
	local frame = aimFrame(root, params.Direction, 0)
	armMotion(params.Caster, { 15, -20 }, { 170, 10 }, 0.06, 0.12, 0.2)
	bladeTrail(params.Caster, 0.3)
	slash(frame, 6.2, -75, 100, 90, 1.8, params.Color, params.Accent, 0.4)
	slash(frame * CFrame.new(0.8, 0, 0), 5, -70, 95, 82, 0.8, params.Accent, params.Color, 0.34)
	local ahead = frame:PointToWorldSpace(Vector3.new(0, 0, -(params.Range or 10) * 0.55))
	spikes(ahead, 5, 2.2, 6, params.Color, params.Accent, 0.8)
	light(ahead, params.Color, 18, 3, 0.4)
end

function Effects.Rush(params)
	local character = params.Caster
	local root = rootOf(character)
	if not root then
		return
	end
	local duration = params.Duration or 0.28
	armMotion(character, { 90, -25 }, { 85, 30 }, 0.04, duration, 0.1)
	bladeTrail(character, duration + 0.1)
	rootTrail(character, params.Color, params.Accent, duration + 0.05, 2.6)
	afterimages(character, params.Color, params.Accent, duration)
	local start = aimFrame(root, params.Direction, 0)
	ring(start * CFrame.Angles(math.rad(90), 0, 0), 1, 4.5, 0.6, 0.1, params.Color, params.Accent, 0.35, 20)
	task.delay(duration, function()
		local finish = rootOf(character)
		if finish then
			local frame = aimFrame(finish, params.Direction, 0.5)
			slash(frame, 5.4, -70, 70, 45, 1.4, params.Color, params.Accent, 0.32)
			slash(frame, 5.4, 70, -70, -45, 1.4, params.Accent, params.Color, 0.32)
		end
	end)
end

function Effects.Dash(params)
	local character = params.Caster
	local root = rootOf(character)
	if not root then
		return
	end
	local frame = aimFrame(root, params.Direction, 0)
	ring(frame * CFrame.Angles(math.rad(90), 0, 0), 0.6, 3.6, 0.5, 0.05, params.Color, params.Accent, 0.3, 16)
	rootTrail(character, params.Color, params.Accent, params.Duration or 0.22, 1.6)
	local ground = groundBelow(root.Position)
	if ground then
		ring(CFrame.new(ground + Vector3.new(0, 0.12, 0)), 0.5, 4, 0.4, 0.05, params.Color, params.Accent, 0.3, 18)
	end
end

local charging: { [Instance]: boolean } = {}

function Effects.NovaCharge(params)
	local character = params.Caster
	local root = rootOf(character)
	if not root then
		return
	end
	local duration = params.Duration or 0.55
	charging[character] = true
	armMotion(character, { 120, 0 }, { 175, 0 }, 0.1, duration - 0.1, 0.05)
	for i, height in { -2.4, 0, 2.4 } do
		task.delay((i - 1) * 0.06, function()
			if root.Parent then
				ring(CFrame.new(root.Position + Vector3.new(0, height, 0)), 10, 1.4, 0.15, 0.7, params.Color, params.Accent, duration - (i - 1) * 0.06, 24, 0.4)
			end
		end)
	end
	-- Light motes converging on the caster.
	for i = 1, 16 do
		local offset = Vector3.new(math.random() - 0.5, math.random() * 0.8 - 0.2, math.random() - 0.5).Unit * (7 + math.random() * 4)
		local mote = part(Vector3.new(0.35, 0.35, 0.35), CFrame.new(root.Position + offset), if i % 2 == 0 then params.Color else params.Accent)
		run(duration * (0.75 + math.random() * 0.25), function(alpha)
			local e = alpha ^ 2
			local target = if root.Parent then root.Position else mote.Position
			mote.CFrame = CFrame.new(target + offset * (1 - e)) * CFrame.Angles(alpha * 6, alpha * 4, 0)
			mote.Transparency = alpha ^ 3
		end, function()
			mote:Destroy()
		end)
	end
	local pl = Instance.new("PointLight")
	pl.Color = params.Color
	pl.Range = 16
	pl.Brightness = 0
	pl.Parent = root
	run(duration, function(alpha)
		pl.Brightness = 4 * alpha
	end, function()
		pl:Destroy()
		charging[character] = nil
	end)
end

function Effects.Nova(params)
	local center: Vector3 = params.Position
	local radius: number = params.Radius or 19
	local color, accent = params.Color, params.Accent
	local ground = groundBelow(center) or (center - Vector3.new(0, 3, 0))
	local floor = CFrame.new(ground + Vector3.new(0, 0.2, 0))
	ring(floor, 2, radius, 3.2, 0.6, color, accent, 0.55, 40)
	task.delay(0.08, function()
		ring(floor * CFrame.new(0, 0.1, 0), 1, radius * 0.75, 1.6, 0.2, accent, color, 0.6, 36, 0.2)
	end)
	ring(CFrame.new(center) * CFrame.Angles(math.rad(90), 0, 0), 1, radius * 0.6, 1.2, 0.1, color, accent, 0.45, 32, 0.3)
	flash(center, color, 2, radius * 1.1, 0.4, 0.45)
	flash(center, WHITE, 1, radius * 0.45, 0.22, 0.2)
	spikes(center, 9, radius * 0.5, 7, color, accent, 0.9)
	spikes(center, 14, radius * 0.9, 9, accent, color, 0.9, 0.06)
	burst(center, color, accent, 18, 40, 1.1, 0.5, Vector3.new(0, 0.6, 0))
	light(center, color, 40, 6, 0.6)

	-- A column of light up through the caster.
	local column = part(Vector3.new(60, 3, 3), CFrame.new(center + Vector3.new(0, 26, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, 0.2)
	column.Shape = Enum.PartType.Cylinder
	run(0.5, function(alpha)
		local w = 3 + 4 * alpha
		column.Size = Vector3.new(60, w * (1 - alpha) + 0.1, w * (1 - alpha) + 0.1)
		column.Transparency = 0.2 + 0.8 * alpha
	end, function()
		column:Destroy()
	end)

	local own = rootOf(player.Character)
	if own and (own.Position - center).Magnitude < radius * 1.7 then
		CombatFX.Shake(0.75)
	end
end

function Effects.Hit(params)
	local target = params.Target
	local position: Vector3 = params.Position or (rootOf(target) and (rootOf(target) :: BasePart).Position)
	if not position then
		return
	end
	local heavy = params.Heavy == true
	local color, accent = params.Color, params.Accent
	local camera = Workspace.CurrentCamera
	local facing = if camera then CFrame.lookAt(position, camera.CFrame.Position) * CFrame.Angles(math.rad(90), 0, 0) else CFrame.new(position)
	ring(facing, 0.5, if heavy then 5.5 else 3.2, if heavy then 0.8 else 0.5, 0.05, color, accent, if heavy then 0.32 else 0.22, 18)
	burst(position, color, accent, if heavy then 12 else 7, if heavy then 34 else 22, if heavy then 1 else 0.7, 0.3)
	flash(position, WHITE, 0.6, if heavy then 4.5 else 2.6, 0.14, 0.25)
	light(position, color, if heavy then 18 else 10, 3, 0.25)
	if typeof(target) == "Instance" then
		hitFlash(target, color)
	end
	if (params.Amount or 0) > 0 then
		damageNumber(position, params.Amount, color, accent, heavy)
	end
	if isLocal(target) then
		CombatFX.Shake(if heavy then 0.55 else 0.22)
	elseif heavy then
		CombatFX.Shake(0.12)
	end
end

function Effects.Block(params)
	local root = rootOf(params.Target)
	if not root then
		return
	end
	local from: Vector3 = params.From or (root.Position + root.CFrame.LookVector)
	local toward = Vector3.new(from.X - root.Position.X, 0, from.Z - root.Position.Z)
	toward = if toward.Magnitude > 1e-3 then toward.Unit else root.CFrame.LookVector
	local center = root.Position + toward * 2.4 + Vector3.new(0, 0.6, 0)
	local shield = CFrame.lookAt(center, center + toward) * CFrame.Angles(math.rad(90), 0, 0)
	local cyan = Theme.Colors.Cyan
	ring(shield, 2.4, 3, 0.5, 0.2, WHITE, cyan, 0.3, 6)
	ring(shield * CFrame.Angles(0, math.rad(30), 0), 1.2, 2, 0.3, 0.05, cyan, WHITE, 0.26, 6, 0.3)
	burst(center, cyan, WHITE, 5, 16, 0.5, 0.22, toward)
	light(center, cyan, 10, 2.5, 0.2)
end

function Effects.GuardBreak(params)
	local root = rootOf(params.Target)
	if not root then
		return
	end
	local center = root.Position + Vector3.new(0, 0.5, 0)
	local cyan = Theme.Colors.Cyan
	for i = 1, 10 do
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
		local shard = part(Vector3.new(0.15, 1.2, 0.9), CFrame.new(center), if i % 2 == 0 then cyan else WHITE, Enum.Material.Glass, 0.1)
		local spin = Vector3.new(math.random() * 12, math.random() * 12, 0)
		run(0.6, function(alpha)
			local p = center + dir * 9 * easeOut(alpha) - Vector3.new(0, 6 * alpha * alpha, 0)
			shard.CFrame = CFrame.new(p) * CFrame.Angles(spin.X * alpha, spin.Y * alpha, 0)
			shard.Transparency = 0.1 + 0.9 * alpha
		end, function()
			shard:Destroy()
		end)
	end
	ring(CFrame.new(center), 1, 7, 0.8, 0.1, cyan, WHITE, 0.4, 24)
	flash(center, cyan, 1, 6, 0.25)
	if isLocal(params.Target) then
		CombatFX.Shake(0.6)
	end
end

function Effects.Spawn(params)
	local position: Vector3 = params.Position
	local color, accent = params.Color, params.Accent
	local ground = groundBelow(position) or (position - Vector3.new(0, 3, 0))
	local column = part(Vector3.new(120, 7, 7), CFrame.new(ground + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, 0.1)
	column.Shape = Enum.PartType.Cylinder
	run(0.8, function(alpha)
		local w = 7 * (1 - easeOut(alpha)) + 0.1
		column.Size = Vector3.new(120, w, w)
		column.Transparency = 0.1 + 0.9 * alpha
	end, function()
		column:Destroy()
	end)
	ring(CFrame.new(ground + Vector3.new(0, 0.15, 0)), 1, 10, 1.4, 0.2, color, accent, 0.7, 32)
	ring(CFrame.new(ground + Vector3.new(0, 0.2, 0)), 6, 2, 0.4, 0.8, accent, color, 0.6, 6, 0.2)
	burst(ground + Vector3.new(0, 1, 0), color, accent, 14, 26, 0.9, 0.6, Vector3.new(0, 1.2, 0))
	light(ground + Vector3.new(0, 3, 0), color, 24, 4, 0.8)
end

-- Defeated: the fighter retreats into their gem, which rises and shatters
-- into light.
function Effects.Defeat(params)
	local position: Vector3 = params.Position
	local color, accent = params.Color, params.Accent
	local gemShell = part(Vector3.new(2.4, 2.4, 2.4), CFrame.new(position), color, Enum.Material.Glass, 0.15)
	local gemCore = part(Vector3.new(1.3, 1.3, 1.3), CFrame.new(position), WHITE)
	local pl = Instance.new("PointLight")
	pl.Color = color
	pl.Range = 16
	pl.Brightness = 3
	pl.Parent = gemCore
	local tilt = CFrame.Angles(math.rad(45), 0, math.rad(35.26))
	run(1.3, function(alpha, elapsed)
		local p = position + Vector3.new(0, 6 * easeOut(alpha), 0)
		local cf = CFrame.new(p) * CFrame.Angles(0, elapsed * 5, 0) * tilt
		gemShell.CFrame = cf
		gemCore.CFrame = cf
		local pulse = 1 + 0.12 * math.sin(elapsed * 20)
		gemShell.Size = Vector3.one * 2.4 * pulse
	end, function()
		local top = position + Vector3.new(0, 6, 0)
		gemShell:Destroy()
		gemCore:Destroy()
		flash(top, WHITE, 1, 9, 0.35, 0.2)
		burst(top, color, accent, 16, 30, 1, 0.6)
		ring(CFrame.new(top), 1, 9, 0.9, 0.1, color, accent, 0.5, 28)
		ring(CFrame.new(top) * CFrame.Angles(math.rad(90), 0, 0), 1, 7, 0.6, 0.1, accent, color, 0.5, 28)
		light(top, color, 26, 5, 0.6)
	end)
	ring(CFrame.new(position - Vector3.new(0, 2.5, 0)), 4, 0.5, 0.2, 0.9, color, accent, 0.8, 24, 0.3)
end

--------------------------------------------------------------------------------
-- Entry points
--------------------------------------------------------------------------------

local function play(kind: string, params: { [string]: any })
	local effect = Effects[kind]
	if effect and type(params) == "table" then
		params.Color = if typeof(params.Color) == "Color3" then params.Color else WHITE
		params.Accent = if typeof(params.Accent) == "Color3" then params.Accent else Theme.Colors.Lavender
		local ok, err = pcall(effect, params)
		if not ok then
			warn(`[CombatFX] {kind}: {err}`)
		end
	end
end

-- Local prediction (own attacks).
function CombatFX.Play(kind: string, params: { [string]: any })
	play(kind, params)
end

function CombatFX.Start()
	folder = Instance.new("Folder")
	folder.Name = "CombatFX"
	folder.Parent = Workspace
	host = part(Vector3.new(0.2, 0.2, 0.2), CFrame.new(), WHITE, Enum.Material.SmoothPlastic, 1)
	host.Name = "Anchor"
	startShake()

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:WaitForChild("CombatFX") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: string, params: { [string]: any })
		if type(params) ~= "table" then
			return
		end
		if PREDICTED[kind] and isLocal(params.Caster) then
			return
		end
		play(kind, params)
	end)
end

return CombatFX
