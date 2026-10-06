-- MovementFX
-- Effects for dashes and double jumps, in the colours of the gem the player
-- wears. Your own effects play instantly; everyone else's arrive through the
-- MovementFX remote. Built from Neon parts and untextured Beams only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local CombatAnim = require(script.Parent.Parent:WaitForChild("Combat"):WaitForChild("CombatAnim"))
local Toon = require(script.Parent.Parent:WaitForChild("Toon"))

local MovementFX = {}

local WHITE = Color3.new(1, 1, 1)
local DEFAULT_COLOR = Color3.fromRGB(235, 225, 255)
local DEFAULT_ACCENT = Color3.fromRGB(150, 220, 255)

local folder: Folder
local host: Part

local function colorsOf(character: Model): (Color3, Color3)
	local player = Players:GetPlayerFromCharacter(character)
	local gem = player and GemCatalog.Get(player:GetAttribute("EquippedGem"))
	if gem then
		return gem.Color, gem.Accent
	end
	return DEFAULT_COLOR, DEFAULT_ACCENT
end

local function part(size: Vector3, cframe: CFrame, color: Color3, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cframe
	p.Transparency = transparency or 0
	p.Parent = folder
	return p
end

local function run(duration: number, step: (number) -> (), done: () -> ())
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local alpha = math.min(1, (os.clock() - started) / duration)
		step(alpha)
		if alpha >= 1 then
			connection:Disconnect()
			done()
		end
	end)
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

-- A flat ring of light growing from r0 to r1 around `center`. With `ink` it
-- is the dark outline band drawn behind a bright ring (cel-shaded look).
local function ring(center: CFrame, r0: number, r1: number, width: number, color: Color3, accent: Color3, duration: number, ink: boolean?)
	local n = 24
	local attachments, beams = {}, {}
	for i = 0, n do
		local a = Instance.new("Attachment")
		a.Parent = host
		attachments[i + 1] = a
	end
	for i = 1, n do
		local beam = Instance.new("Beam")
		beam.Attachment0 = attachments[i]
		beam.Attachment1 = attachments[i + 1]
		local t0 = 0.5 + 0.5 * math.sin((i - 1) / n * math.pi * 4)
		local t1 = 0.5 + 0.5 * math.sin(i / n * math.pi * 4)
		beam.Color = if ink then ColorSequence.new(Toon.Ink(color)) else ColorSequence.new(color:Lerp(accent, t0), color:Lerp(accent, t1))
		beam.LightEmission = if ink then 0 else 1
		beam.ZOffset = if ink then -0.2 else 0
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Parent = host
		beams[i] = beam
	end
	run(duration, function(alpha)
		local r = r0 + (r1 - r0) * easeOut(alpha)
		for i, a in attachments do
			local angle = (i - 1) / n * math.pi * 2
			a.Position = center:PointToWorldSpace(Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r))
		end
		local w = width * (1 - alpha * 0.7)
		-- Fades in hard steps, like anime frames.
		local seq = NumberSequence.new(0.05 + 0.95 * (math.floor(alpha * 4) / 4) ^ 1.2)
		for _, beam in beams do
			beam.Width0 = w
			beam.Width1 = w
			beam.Transparency = seq
		end
	end, function()
		for _, beam in beams do
			beam:Destroy()
		end
		for _, a in attachments do
			a:Destroy()
		end
	end)
end

-- A neon copy of the character's body that fades where it stood, inked
-- around its silhouette.
local function afterimage(character: Model, color: Color3)
	local ghosts = {}
	local group = Instance.new("Model")
	group.Name = "Afterimage"
	group.Parent = folder
	for _, limb in character:GetChildren() do
		if limb:IsA("BasePart") and limb.Name ~= "HumanoidRootPart" and limb.Transparency < 0.9 then
			local ghost = part(limb.Size * 1.02, limb.CFrame, color, 0.35)
			ghost.Parent = group
			table.insert(ghosts, ghost)
		end
	end
	Toon.Outline(group, color, Toon.Priority.Gear, 1, group)
	run(0.32, function(alpha)
		for _, ghost in ghosts do
			ghost.Transparency = 0.35 + 0.65 * alpha
		end
	end, function()
		group:Destroy()
	end)
end

local function feet(root: BasePart): Vector3
	return root.Position - Vector3.new(0, 3, 0)
end

function MovementFX.Dash(character: Model, direction: Vector3?)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	CombatAnim.Play(character, "Dash")
	local color, accent = colorsOf(character)
	local dir = direction or root.CFrame.LookVector
	dir = Vector3.new(dir.X, 0, dir.Z)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1)

	-- A ring standing across the dash, plus afterimages along the path.
	local start = CFrame.lookAt(root.Position, root.Position + dir) * CFrame.Angles(math.rad(90), 0, 0)
	ring(start, 0.8, 4.2, 0.9, color, accent, 0.32, true)
	ring(start, 0.8, 4.2, 0.55, color, accent, 0.32)
	task.spawn(function()
		for i = 1, 4 do
			if character.Parent == nil then
				return
			end
			afterimage(character, if i % 2 == 0 then accent else color)
			task.wait(0.045)
		end
	end)
	-- Speed lines streaming behind.
	for _ = 1, 6 do
		local offset = Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.4) * 4, 0)
		local origin = CFrame.lookAt(root.Position, root.Position + dir) * CFrame.new(offset)
		local line = part(Vector3.new(0.08, 0.08, 5 + math.random() * 3), origin * CFrame.new(0, 0, 3), WHITE:Lerp(color, math.random()), 0.2)
		run(0.25, function(alpha)
			line.CFrame = origin * CFrame.new(0, 0, 3 + alpha * 6)
			line.Transparency = 0.2 + 0.8 * alpha
		end, function()
			line:Destroy()
		end)
	end
end

function MovementFX.DoubleJump(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	CombatAnim.Play(character, "Flip")
	local color, accent = colorsOf(character)
	local base = CFrame.new(feet(root))
	ring(base, 0.6, 4.4, 1, color, accent, 0.4, true)
	ring(base, 0.6, 4.4, 0.6, color, accent, 0.4)
	ring(base * CFrame.new(0, -0.6, 0), 0.4, 2.8, 0.35, accent, color, 0.35)
	-- Crystal shards kicked downward.
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), -0.6, math.sin(angle)).Unit
		local origin = feet(root)
		local shard = part(Vector3.new(0.25, 0.25, 0.9), CFrame.lookAt(origin, origin + dir), if i % 2 == 0 then color else WHITE)
		run(0.35, function(alpha)
			local p = origin + dir * 5 * easeOut(alpha)
			shard.CFrame = CFrame.lookAt(p, p + dir)
			shard.Transparency = alpha
		end, function()
			shard:Destroy()
		end)
	end
end

function MovementFX.Start()
	folder = Instance.new("Folder")
	folder.Name = "MovementFX"
	folder.Parent = Workspace
	host = part(Vector3.new(0.1, 0.1, 0.1), CFrame.new(), WHITE, 1)
	host.Name = "Anchor"

	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MovementFX") :: RemoteEvent
	remote.OnClientEvent:Connect(function(character: Model, kind: string, direction: Vector3?)
		if typeof(character) ~= "Instance" or not character:IsA("Model") then
			return
		end
		if kind == "Dash" then
			MovementFX.Dash(character, direction)
		elseif kind == "DoubleJump" then
			MovementFX.DoubleJump(character)
		end
	end)
end

return MovementFX
