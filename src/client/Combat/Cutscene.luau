-- Cutscene
-- Cinematic intros for ultimates, seen by the player who casts them (everyone
-- else watches the transformation happen in the world, without losing their
-- camera, and feels a shake when close):
--   * Transformation (G), CombatConfig.Cutscene.Transform seconds: a close-up
--     on the face, an orbit while the body cracks into crystal, a flash in the
--     gem colour as the beast takes shape (BeastAt) and roars, then the camera
--     pulls back out and hands control back.
--   * Domain (T), CombatConfig.Cutscene.Domain seconds: the camera rises high
--     above the caster to watch the dome come down, the domain's name across
--     the screen, then back down.
-- Both get letterbox bars, a cinematic title and slow-motion effects
-- (Cutscene.TimeScale, read by CombatFX). The caster is held still and the
-- server keeps them untouchable for the same time. Cutscene.Enabled (on by
-- default) is switched from the skills guide.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local MovementController = require(script.Parent.Parent:WaitForChild("Movement"):WaitForChild("MovementController"))

local player = Players.LocalPlayer
local CUT = CombatConfig.Cutscene

local Cutscene = {}

Cutscene.Enabled = true
Cutscene.Changed = Signal.new()
-- Speed of combat effects (1 = normal); slowed during the big moments.
Cutscene.TimeScale = 1
-- Set by CombatFX: shakes the camera (amount).
Cutscene.OnShake = nil :: ((number) -> ())?

local playing = false

function Cutscene.SetEnabled(on: boolean)
	if Cutscene.Enabled ~= on then
		Cutscene.Enabled = on
		Cutscene.Changed:Fire(on)
	end
end

function Cutscene.Playing(): boolean
	return playing
end

local function ease(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function flatUnit(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

--------------------------------------------------------------------------------
-- Screen: letterbox, title, flash
--------------------------------------------------------------------------------

type Screen = {
	Gui: ScreenGui,
	Top: Frame,
	Bottom: Frame,
	Flash: Frame,
	Title: Frame,
	Kicker: TextLabel,
	Name: TextLabel,
	Line: Frame,
	Gradient: UIGradient,
	Hidden: { ScreenGui },
}

local function buildScreen(): Screen
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Theme.new("ScreenGui", {
		Name = "Cutscene",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	-- Same readable size on every screen as the main UI.
	local scale = Theme.new("UIScale", { Parent = gui })
	local camera = Workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min(size.X / 1366, size.Y / 768), 0.55, 1.3)
	end
	local function bar(anchorY: number): Frame
		return Theme.new("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, anchorY),
			Position = UDim2.fromScale(0, anchorY),
			Size = UDim2.fromScale(1, 0),
			ZIndex = 2,
			Parent = gui,
		})
	end
	local top = bar(0)
	local bottom = bar(1)
	local flash = Theme.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = gui,
	})
	local title = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.new(0.9, 0, 0, 130),
		ZIndex = 3,
		Parent = gui,
	})
	local kicker = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Odds,
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		ZIndex = 4,
		Parent = title,
	})
	local name = Theme.label({
		Text = "",
		FontFace = Theme.Faces.Display,
		TextSize = 62,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = false,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 74),
		ZIndex = 4,
		Parent = title,
	})
	local nameStroke = Theme.new("UIStroke", { Color = Color3.fromRGB(14, 6, 26), Thickness = 2.5, Transparency = 1, Parent = name })
	local gradient = Theme.new("UIGradient", { Parent = name })
	local line = Theme.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.fromOffset(0, 3),
		ZIndex = 4,
		Parent = title,
	})
	Theme.round().Parent = line
	gui.Parent = playerGui
	local _ = nameStroke
	return {
		Gui = gui,
		Top = top,
		Bottom = bottom,
		Flash = flash,
		Title = title,
		Kicker = kicker,
		Name = name,
		Line = line,
		Gradient = gradient,
		Hidden = {},
	}
end

-- Letterbox in, the rest of the HUD out of the way.
local function openScreen(): Screen
	local s = buildScreen()
	for _, other in (player:WaitForChild("PlayerGui")):GetChildren() do
		if other:IsA("ScreenGui") and other ~= s.Gui and other.Enabled then
			other.Enabled = false
			table.insert(s.Hidden, other)
		end
	end
	Theme.tween(s.Top, 0.3, { Size = UDim2.fromScale(1, 0.11) }, Enum.EasingStyle.Quart)
	Theme.tween(s.Bottom, 0.3, { Size = UDim2.fromScale(1, 0.11) }, Enum.EasingStyle.Quart)
	return s
end

local function closeScreen(s: Screen)
	for _, other in s.Hidden do
		if other.Parent then
			other.Enabled = true
		end
	end
	Theme.tween(s.Top, 0.3, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quart)
	Theme.tween(s.Bottom, 0.3, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quart)
	Theme.tween(s.Kicker, 0.25, { TextTransparency = 1 })
	Theme.tween(s.Name, 0.25, { TextTransparency = 1 })
	Theme.tween(s.Line, 0.25, { BackgroundTransparency = 1 })
	task.delay(0.35, function()
		s.Gui:Destroy()
	end)
end

-- The title slides in: kicker, then the name in the gem's colours, then the
-- underline grows.
local function showTitle(s: Screen, kicker: string, name: string, color: Color3, accent: Color3, position: UDim2?)
	if position then
		s.Title.Position = position
	end
	s.Kicker.Text = kicker
	s.Name.Text = name
	s.Gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.35, color:Lerp(Color3.new(1, 1, 1), 0.25)),
		ColorSequenceKeypoint.new(1, accent),
	})
	s.Gradient.Rotation = 90
	s.Line.BackgroundColor3 = color
	s.Name.Position = UDim2.fromOffset(-40, 24)
	Theme.tween(s.Kicker, 0.3, { TextTransparency = 0.1 })
	task.delay(0.08, function()
		Theme.tween(s.Name, 0.4, { TextTransparency = 0, Position = UDim2.fromOffset(0, 24) }, Enum.EasingStyle.Quart)
		local stroke = s.Name:FindFirstChildOfClass("UIStroke")
		if stroke then
			Theme.tween(stroke, 0.4, { Transparency = 0.1 })
		end
		Theme.tween(s.Line, 0.5, { Size = UDim2.new(0.5, 0, 0, 3) }, Enum.EasingStyle.Quart)
	end)
end

local function flash(s: Screen, color: Color3, strength: number)
	s.Flash.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	s.Flash.BackgroundTransparency = 1 - strength
	Theme.tween(s.Flash, 0.45, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
end

--------------------------------------------------------------------------------
-- Camera
--------------------------------------------------------------------------------

type Shot = (t: number) -> (CFrame, number) -- camera frame and field of view

-- Runs a camera shot for `duration`, then gives the camera back. `events`
-- fire once at their time. Ends early if the caster dies.
local function roll(caster: Model, duration: number, shot: Shot, events: { { At: number, Run: () -> () } }, done: () -> ())
	local camera = Workspace.CurrentCamera
	local humanoid = caster:FindFirstChildOfClass("Humanoid")
	if not camera or not humanoid then
		done()
		return
	end
	local savedType = camera.CameraType
	local savedFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	local start = os.clock()
	local fired = {}
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		RunService:UnbindFromRenderStep("UltimateCutscene")
		camera.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
		camera.FieldOfView = savedFov
		done()
	end
	RunService:BindToRenderStep("UltimateCutscene", Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - start
		if t >= duration or humanoid.Health <= 0 or caster.Parent == nil then
			finish()
			return
		end
		for i, event in events do
			if not fired[i] and t >= event.At then
				fired[i] = true
				task.spawn(event.Run)
			end
		end
		local ok, cf, fov = pcall(shot, t)
		if ok then
			camera.CFrame = cf
			camera.FieldOfView = fov
		else
			finish()
		end
	end)
end

--------------------------------------------------------------------------------
-- Ultimates
--------------------------------------------------------------------------------

-- The transformation intro. Returns false when it doesn't play (disabled, or
-- another one is running).
function Cutscene.Transform(caster: Model, title: string, color: Color3, accent: Color3): boolean
	if playing or not Cutscene.Enabled then
		return false
	end
	local root = caster:FindFirstChild("HumanoidRootPart")
	local head = caster:FindFirstChild("Head")
	local camera = Workspace.CurrentCamera
	if not root or not root:IsA("BasePart") or not camera then
		return false
	end
	playing = true
	local total = CUT.Transform
	MovementController.Freeze(total)
	local saved = camera.CFrame
	local savedFov = camera.FieldOfView
	local screen = openScreen()
	local look = flatUnit(root.CFrame.LookVector)
	local right = look:Cross(Vector3.yAxis)
	local function around(angle: number): Vector3
		-- `angle` degrees around the caster, starting in front of them.
		local a = math.rad(angle)
		return look * math.cos(a) + right * math.sin(a)
	end
	local function headPosition(): Vector3
		return if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.6, 0)
	end
	-- Shot list: close-up -> orbit as the body cracks -> pull back on the
	-- beast -> back to the player's own camera.
	local function pullBack(u: number): (CFrame, number)
		local center = root.Position
		local r = 11 + 10 * ease(u)
		local h = 3 + 7 * ease(u)
		local eye = center + around(175 + 60 * ease(u)) * r + Vector3.new(0, h, 0)
		return CFrame.lookAt(eye, center + Vector3.new(0, 3 + 2 * u, 0)), 55 + 13 * ease(u)
	end
	local function shot(t: number): (CFrame, number)
		local center = root.Position
		if t < 0.8 then
			local u = t / 0.8
			local face = headPosition()
			local eye = face + look * (4.6 - 1.1 * ease(u)) + right * 1.1 + Vector3.new(0, 0.25, 0)
			return CFrame.lookAt(eye, face + Vector3.new(0, 0.05, 0)), 44
		elseif t < 1.5 then
			local u = (t - 0.8) / 0.7
			local r = 7 + 4 * u
			local eye = center + around(25 + 150 * ease(u)) * r + Vector3.new(0, 1.5 + 1.5 * u, 0)
			return CFrame.lookAt(eye, center + Vector3.new(0, 1.2 + 1.8 * u, 0)), 45 + 10 * u
		elseif t < 2.2 then
			return pullBack((t - 1.5) / 0.7)
		end
		local u = ease((t - 2.2) / math.max(0.05, total - 2.2))
		local from, fov = pullBack(1)
		return from:Lerp(saved, u), fov + (savedFov - fov) * u
	end
	task.delay(0.35, function()
		showTitle(screen, "U L T I M A T E   ·   T R A N S F O R M A T I O N", string.upper(title), color, accent)
	end)
	roll(caster, total, shot, {
		{ At = 0.85, Run = function()
			Cutscene.TimeScale = 0.35
		end },
		{ At = CUT.BeastAt, Run = function()
			flash(screen, color, 0.85)
			if Cutscene.OnShake then
				Cutscene.OnShake(0.9)
			end
		end },
		{ At = 1.6, Run = function()
			Cutscene.TimeScale = 1
		end },
	}, function()
		Cutscene.TimeScale = 1
		closeScreen(screen)
		playing = false
	end)
	return true
end

-- The domain intro.
function Cutscene.Domain(caster: Model, center: Vector3, radius: number, name: string, color: Color3, accent: Color3): boolean
	if playing or not Cutscene.Enabled then
		return false
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	playing = true
	local total = CUT.Domain
	MovementController.Freeze(total)
	local saved = camera.CFrame
	local savedFov = camera.FieldOfView
	local screen = openScreen()
	local back = -flatUnit(saved.LookVector)
	local function high(u: number): CFrame
		-- High above, a little behind, drifting slowly round.
		local spin = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-18 * u))
		local eye = center + spin:VectorToWorldSpace(back) * radius * 0.6 + Vector3.new(0, radius * 1.05 + 10, 0)
		return CFrame.lookAt(eye, center)
	end
	local function shot(t: number): (CFrame, number)
		if t < 0.45 then
			local u = ease(t / 0.45)
			return saved:Lerp(high(0), u), savedFov + (60 - savedFov) * u
		elseif t < 1.1 then
			return high((t - 0.45) / 0.65), 60
		end
		local u = ease((t - 1.1) / math.max(0.05, total - 1.1))
		return high(1):Lerp(saved, u), 60 + (savedFov - 60) * u
	end
	showTitle(screen, "D O M A I N   E X P A N S I O N", string.upper(name), color, accent, UDim2.fromScale(0.5, 0.5))
	roll(caster, total, shot, {
		{ At = 0.4, Run = function()
			flash(screen, color, 0.5)
			Cutscene.TimeScale = 0.5
			if Cutscene.OnShake then
				Cutscene.OnShake(0.6)
			end
		end },
		{ At = 1.05, Run = function()
			Cutscene.TimeScale = 1
		end },
	}, function()
		Cutscene.TimeScale = 1
		closeScreen(screen)
		playing = false
	end)
	return true
end

return Cutscene
