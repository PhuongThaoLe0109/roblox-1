-- MovementService
-- Server half of getting around:
--   * SetHoverboard(on): builds or removes the crystal hoverboard under the
--     player's feet (welded to the root so everyone sees it) and sets the
--     character's "Hoverboard" attribute, which the owner's client uses to
--     switch to board speed. Not allowed in the arena.
--   * MovementFX(kind, direction): relays dash / double-jump effects from a
--     player's client to everyone else (rate limited, kinds whitelisted).
--
-- The board is plain parts (Glass deck, Neon rails and thrusters), a gradient
-- Trail and a PointLight, tinted with the gem the player wears.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local MovementConfig = require(ReplicatedStorage:WaitForChild("MovementConfig"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local BOARD = MovementConfig.Hoverboard
local ATTRIBUTE = MovementConfig.HoverboardAttribute
local FX_KINDS = { Dash = true, DoubleJump = true }
local FX_BUDGET = 6 -- per second

local MovementService = {}

local WHITE = Color3.new(1, 1, 1)
local DEFAULT_COLOR = Color3.fromRGB(235, 225, 255)
local DEFAULT_ACCENT = Color3.fromRGB(150, 220, 255)

local toggleCooldown = Remotes.CreateCooldown(BOARD.Cooldown)

local function colorsOf(player: Player): (Color3, Color3)
	local gem = GemCatalog.Get(player:GetAttribute("EquippedGem"))
	if gem then
		return gem.Color, gem.Accent
	end
	return DEFAULT_COLOR, DEFAULT_ACCENT
end

local function boardPart(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number?): Part
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
	p.Parent = model
	return p
end

local function weld(part0: BasePart, part1: BasePart, c0: CFrame)
	part1.CFrame = part0.CFrame * c0
	local w = Instance.new("Weld")
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
end

-- Distance from the root's centre down to the soles of the feet.
local function feetOffset(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hip = 2
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		hip = humanoid.HipHeight
	end
	return hip + root.Size.Y / 2
end

local function removeBoard(character: Model)
	local old = character:FindFirstChild("Hoverboard")
	if old then
		old:Destroy()
	end
	character:SetAttribute(ATTRIBUTE, false)
end

local function buildBoard(player: Player, character: Model, root: BasePart)
	removeBoard(character)
	local color, accent = colorsOf(player)
	local h, s, v = color:ToHSV()
	local deckColor = Color3.fromHSV(h, s * 0.55, math.min(1, v * 1.05))

	local model = Instance.new("Model")
	model.Name = "Hoverboard"

	-- Deck: tinted glass with a bright core, pointed nose and tail.
	local deck = boardPart(model, "Deck", Vector3.new(2.6, 0.28, 5.6), deckColor, Enum.Material.Glass, 0.15)
	local below = feetOffset(character, root) + BOARD.Lift + 0.14
	weld(root, deck, CFrame.new(0, -below, 0))
	model.PrimaryPart = deck

	for _, z in { -2.8, 2.8 } do
		local tip = boardPart(model, "Tip", Vector3.new(1.84, 0.28, 1.84), deckColor, Enum.Material.Glass, 0.15)
		weld(deck, tip, CFrame.new(0, 0, z) * CFrame.Angles(0, math.rad(45), 0))
		local tipCore = boardPart(model, "TipCore", Vector3.new(0.9, 0.3, 0.9), accent, Enum.Material.Neon)
		weld(deck, tipCore, CFrame.new(0, 0.01, z) * CFrame.Angles(0, math.rad(45), 0))
	end
	local core = boardPart(model, "Core", Vector3.new(0.42, 0.3, 5.2), color:Lerp(WHITE, 0.45), Enum.Material.Neon)
	weld(deck, core, CFrame.new(0, 0.01, 0))
	for _, x in { -1.24, 1.24 } do
		local rail = boardPart(model, "Rail", Vector3.new(0.14, 0.34, 5.2), accent, Enum.Material.Neon)
		weld(deck, rail, CFrame.new(x, 0, 0))
	end
	-- Crossbars like the facets of a cut gem.
	for _, z in { -1.4, 0, 1.4 } do
		local bar = boardPart(model, "Facet", Vector3.new(2.3, 0.3, 0.1), color, Enum.Material.Neon, 0.2)
		weld(deck, bar, CFrame.new(0, 0.01, z))
	end

	-- Thrusters: glowing discs underneath.
	for _, z in { -1.7, 1.7 } do
		local thruster = boardPart(model, "Thruster", Vector3.new(0.18, 1.2, 1.2), WHITE, Enum.Material.Neon)
		thruster.Shape = Enum.PartType.Cylinder
		weld(deck, thruster, CFrame.new(0, -0.2, z) * CFrame.Angles(0, 0, math.rad(90)))
		local ring = boardPart(model, "ThrusterRing", Vector3.new(0.12, 1.6, 1.6), accent, Enum.Material.Neon, 0.35)
		ring.Shape = Enum.PartType.Cylinder
		weld(deck, ring, CFrame.new(0, -0.22, z) * CFrame.Angles(0, 0, math.rad(90)))
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 2.2
	light.Shadows = false
	light.Parent = core

	-- Gradient wake from the tail.
	local a0 = Instance.new("Attachment")
	a0.Name = "WakeLeft"
	a0.Position = Vector3.new(-1.2, -0.1, 2.9)
	a0.Parent = deck
	local a1 = Instance.new("Attachment")
	a1.Name = "WakeRight"
	a1.Position = Vector3.new(1.2, -0.1, 2.9)
	a1.Parent = deck
	local trail = Instance.new("Trail")
	trail.Name = "Wake"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.45
	trail.MinLength = 0.1
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.3, color),
		ColorSequenceKeypoint.new(1, accent),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	trail.Parent = deck

	model.Parent = character
	character:SetAttribute(ATTRIBUTE, true)
end

local function riding(character: Model?): boolean
	return character ~= nil and character:GetAttribute(ATTRIBUTE) == true
end

local function onSetHoverboard(player: Player, on: unknown)
	if type(on) ~= "boolean" then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return
	end
	if on == riding(character) then
		return
	end
	if not on then
		removeBoard(character)
		return
	end
	if player:GetAttribute("InArena") == true and not BOARD.AllowedInArena then
		return
	end
	if toggleCooldown(player) > 0 then
		return
	end
	buildBoard(player, character, root)
end

-- Relays a movement effect to every other client.
local fxBudget: { [Player]: { Tokens: number, At: number } } = {}
local function onMovementFX(player: Player, kind: unknown, direction: unknown)
	if type(kind) ~= "string" or not FX_KINDS[kind] then
		return
	end
	local budget = fxBudget[player]
	local now = os.clock()
	if not budget then
		budget = { Tokens = FX_BUDGET, At = now }
		fxBudget[player] = budget
	end
	budget.Tokens = math.min(FX_BUDGET, budget.Tokens + (now - budget.At) * FX_BUDGET)
	budget.At = now
	if budget.Tokens < 1 then
		return
	end
	budget.Tokens -= 1
	local character = player.Character
	if not character then
		return
	end
	local dir = if typeof(direction) == "Vector3" and direction.Magnitude < 1e4 and direction == direction then direction else nil
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.MovementFX:FireClient(other, character, kind, dir)
		end
	end
end

function MovementService.Init()
	Remotes.SetHoverboard.OnServerEvent:Connect(onSetHoverboard)
	Remotes.MovementFX.OnServerEvent:Connect(onMovementFX)

	local function watch(player: Player)
		-- Entering the arena puts the board away.
		player:GetAttributeChangedSignal("InArena"):Connect(function()
			if player:GetAttribute("InArena") == true and not BOARD.AllowedInArena and player.Character then
				removeBoard(player.Character)
			end
		end)
		-- A new gem re-tints the board.
		player:GetAttributeChangedSignal("EquippedGem"):Connect(function()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and riding(character) and root and root:IsA("BasePart") then
				buildBoard(player, character, root)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		fxBudget[player] = nil
	end)
end

return MovementService
