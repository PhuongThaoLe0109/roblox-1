-- Toon
-- The "anime 3D with a 2D finish" look, faked without shaders:
--   * Ink outlines: Highlights drawn in a dark ink of the gem's colour around
--     weapons, beasts, brooms, high-tier auras and big effects. Roblox renders
--     at most 31 Highlights at once, so every Highlight in the game goes
--     through here: each has a priority, and only the best Budget of them
--     (nearest the camera first, nothing past MaxDistance) are enabled.
--   * Impact frames (a white then black frame), screen-space speed lines and
--     hit-stop for heavy hits that involve you.
--   * Ink(color): the dark outline tone of a colour.
-- Weapons, beasts and brooms are outlined automatically (Toon.Start watches
-- every character for them).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))

local player = Players.LocalPlayer

local Toon = {}

Toon.Budget = 28 -- of the 31 Highlights Roblox renders at once
Toon.MaxDistance = 260 -- studs: outlines further away are switched off

-- Priorities (higher wins a slot first, then distance decides).
Toon.Priority = {
	Aura = 0,
	Gear = 1, -- weapons, brooms
	Effect = 2, -- big effects
	Beast = 3,
	Hit = 4, -- hit flashes
}

type Entry = { Highlight: Highlight, Priority: number, Adornee: Instance? }

local entries: { [Highlight]: Entry } = {}

-- The dark outline tone of a colour: same hue, deeper and darker.
function Toon.Ink(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 0.9 + 0.35), math.max(0.08, v * 0.22))
end

-- A colour's light "highlight" band and dark "shadow" band (for 3-tone
-- shading: white core -> colour -> shadow).
function Toon.Shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	if amount >= 0 then
		return Color3.fromHSV(h, s * (1 - 0.5 * amount), math.min(1, v + (1 - v) * amount))
	end
	return Color3.fromHSV(h, math.min(1, s * (1 - 0.3 * amount)), v * (1 + 0.55 * amount))
end

-- Hands an existing Highlight to the budget (it is enabled when it earns a
-- slot). Released automatically when it is destroyed.
function Toon.Register(highlight: Highlight, priority: number?)
	-- Show it straight away while there is room (short flashes can't wait for
	-- the next allocation); the allocation sorts it out from then on.
	highlight.Enabled = Toon.Active() < Toon.Budget
	entries[highlight] = { Highlight = highlight, Priority = priority or Toon.Priority.Effect, Adornee = highlight.Adornee }
	-- (Destroying, not unparenting: culled models come back.)
	highlight.Destroying:Connect(function()
		entries[highlight] = nil
	end)
end

-- An ink outline around `adornee` (a Model or a part). `fill` (0..1, default
-- 1 = no fill) tints the silhouette. Returns the Highlight (destroy it to
-- remove the outline; it also goes when the adornee does).
function Toon.Outline(adornee: Instance, color: Color3, priority: number?, fill: number?, parent: Instance?): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "ToonOutline"
	highlight.Adornee = adornee
	highlight.OutlineColor = Toon.Ink(color)
	highlight.OutlineTransparency = 0
	highlight.FillColor = color
	highlight.FillTransparency = fill or 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = parent or adornee
	Toon.Register(highlight, priority)
	adornee.Destroying:Connect(function()
		highlight:Destroy()
	end)
	return highlight
end

local function positionOf(adornee: Instance?): Vector3?
	if not adornee or adornee.Parent == nil then
		return nil
	end
	if adornee:IsA("BasePart") then
		return adornee.Position
	elseif adornee:IsA("Model") then
		local root = adornee:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.Position
		end
		return adornee:GetPivot().Position
	end
	return nil
end

-- Picks which Highlights render this moment.
local ranked: { { Entry: Entry, Score: number } } = {}
local function allocate()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	table.clear(ranked)
	for highlight, entry in entries do
		if highlight.Parent == nil then
			highlight.Enabled = false
			continue
		end
		local adornee = highlight.Adornee or highlight.Parent
		local position = positionOf(adornee)
		if not position then
			highlight.Enabled = false
			continue
		end
		local distance = (position - eye).Magnitude
		if distance > Toon.MaxDistance then
			highlight.Enabled = false
			continue
		end
		table.insert(ranked, { Entry = entry, Score = entry.Priority * 1000 - distance })
	end
	table.sort(ranked, function(a, b)
		return a.Score > b.Score
	end)
	for i, item in ranked do
		local on = i <= Toon.Budget
		if item.Entry.Highlight.Enabled ~= on then
			item.Entry.Highlight.Enabled = on
		end
	end
end

-- How many Highlights render right now (for checks and debugging).
function Toon.Active(): number
	local n = 0
	for highlight in entries do
		if highlight.Enabled then
			n += 1
		end
	end
	return n
end

--------------------------------------------------------------------------------
-- Impact: frames, speed lines, hit-stop
--------------------------------------------------------------------------------

local screen: ScreenGui? = nil
local function overlay(): ScreenGui
	if screen and screen.Parent then
		return screen
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ToonImpact"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui
	return gui
end

local lastImpact = 0
-- A two-frame impact: a white flash, then a dark frame, then gone.
function Toon.ImpactFrame(strength: number?)
	local now = os.clock()
	if now - lastImpact < 0.25 then
		return -- never strobe
	end
	lastImpact = now
	local s = math.clamp(strength or 1, 0, 1)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1 - 0.55 * s
	frame.Parent = overlay()
	local frames = 0
	local connection
	connection = RunService.RenderStepped:Connect(function()
		frames += 1
		if frames == 2 then
			frame.BackgroundColor3 = Color3.fromRGB(10, 4, 20)
			frame.BackgroundTransparency = 1 - 0.4 * s
		elseif frames >= 4 then
			connection:Disconnect()
			frame:Destroy()
		end
	end)
end

-- Anime speed lines bursting out from where `world` is on screen.
function Toon.SpeedLines(world: Vector3, color: Color3, count: number?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local point, onScreen = camera:WorldToViewportPoint(world)
	if not onScreen then
		return
	end
	local gui = overlay()
	local center = Vector2.new(point.X, point.Y)
	local lines = {}
	local n = count or 18
	for i = 1, n do
		local angle = (i / n) * math.pi * 2 + math.random() * 0.25
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.BackgroundColor3 = if i % 3 == 0 then color else Color3.new(1, 1, 1)
		line.Rotation = math.deg(angle)
		line.Parent = gui
		table.insert(lines, { Frame = line, Angle = angle, Length = 70 + math.random() * 90, Thick = if i % 4 == 0 then 4 else 2 })
	end
	local started = os.clock()
	local life = 0.2
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local a = math.min(1, (os.clock() - started) / life)
		for _, item in lines do
			local r = 50 + 260 * a
			local dir = Vector2.new(math.cos(item.Angle), math.sin(item.Angle))
			local p = center + dir * r
			item.Frame.Position = UDim2.fromOffset(p.X, p.Y)
			item.Frame.Size = UDim2.fromOffset(item.Length * (1 - 0.4 * a), item.Thick)
			item.Frame.BackgroundTransparency = 0.1 + 0.9 * a
		end
		if a >= 1 then
			connection:Disconnect()
			for _, item in lines do
				item.Frame:Destroy()
			end
		end
	end)
end

-- Set by CombatFX / CombatAnim: freeze effects and animation for a moment.
Toon.OnHitStop = {} :: { (number) -> () }
-- A short freeze-frame on a heavy blow (~50 ms).
function Toon.HitStop(seconds: number?)
	for _, fn in Toon.OnHitStop do
		fn(seconds or 0.05)
	end
end

--------------------------------------------------------------------------------
-- Characters: outline their weapon, beast and broom
--------------------------------------------------------------------------------

local OUTLINED = {
	Weapon = Toon.Priority.Gear,
	Broom = Toon.Priority.Gear,
	Beast = Toon.Priority.Beast,
}

local function colorOf(owner: Player): Color3
	local gem = GemCatalog.Get(owner:GetAttribute("EquippedGem"))
	return if gem then gem.Color else Color3.fromRGB(235, 225, 255)
end

local function watchCharacter(owner: Player, character: Model)
	local function consider(child: Instance)
		local priority = OUTLINED[child.Name]
		if priority and (child:IsA("Model") or child:IsA("BasePart")) and not child:FindFirstChild("ToonOutline") then
			-- Beasts get a faint tint of the gem colour inside the ink.
			Toon.Outline(child, colorOf(owner), priority, if child.Name == "Beast" then 0.9 else 1)
		end
	end
	for _, child in character:GetChildren() do
		consider(child)
	end
	character.ChildAdded:Connect(consider)
end

local function watchPlayer(owner: Player)
	owner.CharacterAdded:Connect(function(character)
		watchCharacter(owner, character)
	end)
	if owner.Character then
		watchCharacter(owner, owner.Character)
	end
end

function Toon.Start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, owner in Players:GetPlayers() do
		task.spawn(watchPlayer, owner)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.15 then
			elapsed = 0
			allocate()
		end
	end)
end

return Toon
