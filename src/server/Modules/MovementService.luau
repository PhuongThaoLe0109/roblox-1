-- MovementService
-- Server half of getting around:
--   * SetBroom(on): builds or removes the flying crystal broom (welded to the
--     player's root so everyone sees it) and sets the character's "Broom"
--     attribute, which the owner's client uses to switch to flight. Not while
--     in combat or in beast form, and not again for a moment after getting off.
--     Using a skill, getting stunned, transforming or any hit knocks you off.
--   * MovementFX(kind, direction): relays dash / double-jump effects from a
--     player's client to everyone else (rate limited, kinds whitelisted).
--
-- The broom is plain parts: a slim wooden shaft with a crystal inlay and tip,
-- glowing collar bands and a fanned bristle bundle with gem-tinted ends, a
-- gradient Trail from the bristles and a PointLight, tinted with the gem the
-- player wears. MovementGuard checks the flight speed and height.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local MovementConfig = require(ReplicatedStorage:WaitForChild("MovementConfig"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local BROOM = MovementConfig.Broom
local ATTRIBUTE = MovementConfig.BroomAttribute
local STATUS = CombatConfig.Status
local FX_KINDS = { Dash = true, DoubleJump = true }
local FX_BUDGET = 6 -- per second

local MovementService = {}

local WHITE = Color3.new(1, 1, 1)
local DEFAULT_COLOR = Color3.fromRGB(235, 225, 255)
local DEFAULT_ACCENT = Color3.fromRGB(150, 220, 255)
local WOOD = Color3.fromRGB(96, 62, 40)
local WOOD_DARK = Color3.fromRGB(64, 40, 28)
local STRAW = Color3.fromRGB(206, 170, 104)
local STRAW_DARK = Color3.fromRGB(160, 120, 70)

-- The broom's frame relative to the root: under the hips, pointing forward.
MovementService.Seat = CFrame.new(0, -1.55, 0)

local toggleCooldown = Remotes.CreateCooldown(BROOM.ToggleCooldown)
local remountAt: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function colorsOf(player: Player): (Color3, Color3)
	local gem = GemCatalog.Get(player:GetAttribute("EquippedGem"))
	if gem then
		return gem.Color, gem.Accent
	end
	return DEFAULT_COLOR, DEFAULT_ACCENT
end

local function broomPart(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material, transparency: number?): Part
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

-- Cylinders lie along X: this turns one to run along the broom (-Z forward).
local ALONG = CFrame.Angles(0, math.rad(90), 0)

local function removeBroom(character: Model)
	local old = character:FindFirstChild("Broom")
	if old then
		old:Destroy()
	end
	if character:GetAttribute(ATTRIBUTE) == true then
		character:SetAttribute(ATTRIBUTE, false)
	end
end

-- Builds the broom model on `character`, its frame at root * Seat.
function MovementService.BuildBroom(character: Model, root: BasePart, color: Color3, accent: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Broom"
	local h, s, v = color:ToHSV()
	local inlay = Color3.fromHSV(h, math.min(1, s * 1.1), math.min(1, v * 1.1 + 0.1))

	-- Shaft: a slim, slightly tapered wooden rod (the root of the whole model).
	local shaft = broomPart(model, "Shaft", Vector3.new(4.2, 0.32, 0.32), WOOD, Enum.Material.SmoothPlastic)
	shaft.Shape = Enum.PartType.Cylinder
	weld(root, shaft, MovementService.Seat * CFrame.new(0, 0, 0.7) * ALONG)
	model.PrimaryPart = shaft
	local function at(c0: CFrame): CFrame
		-- Offset in broom space -> weld C0 relative to the shaft.
		return (ALONG:Inverse() * CFrame.new(0, 0, -0.7)) * c0
	end
	local function place(p: BasePart, c0: CFrame)
		weld(shaft, p, at(c0))
	end
	local front = broomPart(model, "ShaftFront", Vector3.new(3.4, 0.26, 0.26), WOOD, Enum.Material.SmoothPlastic)
	front.Shape = Enum.PartType.Cylinder
	place(front, CFrame.new(0, 0, -2.85) * ALONG)
	-- Darker grain bands and a gem inlay running along the top.
	for _, z in { -3.9, -0.9, 1.9 } do
		local band = broomPart(model, "Grain", Vector3.new(0.14, 0.34, 0.34), WOOD_DARK, Enum.Material.SmoothPlastic)
		band.Shape = Enum.PartType.Cylinder
		place(band, CFrame.new(0, 0, z) * ALONG)
	end
	local strip = broomPart(model, "Inlay", Vector3.new(0.07, 0.05, 5.6), inlay, Enum.Material.Neon)
	place(strip, CFrame.new(0, 0.14, -1.6))
	-- Crystal tip: a faceted glass point with a bright core.
	local tip = broomPart(model, "Tip", Vector3.new(0.42, 0.42, 0.7), color, Enum.Material.Glass, 0.1)
	place(tip, CFrame.new(0, 0, -4.75) * CFrame.Angles(0, 0, math.rad(45)))
	local tipPoint = broomPart(model, "TipPoint", Vector3.new(0.26, 0.26, 0.5), color, Enum.Material.Glass, 0.1)
	place(tipPoint, CFrame.new(0, 0, -5.25) * CFrame.Angles(0, 0, math.rad(45)))
	local tipCore = broomPart(model, "TipCore", Vector3.new(0.16, 0.16, 0.9), WHITE, Enum.Material.Neon)
	place(tipCore, CFrame.new(0, 0, -4.95) * CFrame.Angles(0, 0, math.rad(45)))

	-- Collar: two glowing bands binding the bristles.
	for i, z in { 2.75, 3.15 } do
		local collar = broomPart(model, "Collar", Vector3.new(0.18, 0.62 - i * 0.04, 0.62 - i * 0.04), accent, Enum.Material.Neon)
		collar.Shape = Enum.PartType.Cylinder
		place(collar, CFrame.new(0, 0, z) * ALONG)
	end
	local cap = broomPart(model, "Cap", Vector3.new(0.5, 0.5, 0.5), WOOD_DARK, Enum.Material.SmoothPlastic)
	cap.Shape = Enum.PartType.Ball
	place(cap, CFrame.new(0, 0, 2.95))

	-- Bristles: two fanned rings of straw that spread toward the tail, the
	-- outer ring ending in gem-tinted tips.
	local function bristle(angle: number, r0: number, spread: number, length: number, width: number, tint: Color3, tipped: boolean)
		local start = Vector3.new(math.cos(angle) * r0, math.sin(angle) * r0, 3.05)
		local out = Vector3.new(math.cos(angle), math.sin(angle), 0)
		local dir = (Vector3.new(0, 0, 1) + out * math.tan(math.rad(spread))).Unit
		local cf = CFrame.lookAt(start, start + dir) * CFrame.new(0, 0, -length / 2)
		local b = broomPart(model, "Bristle", Vector3.new(width, width, length), tint, Enum.Material.SmoothPlastic)
		place(b, cf)
		if tipped then
			local t = broomPart(model, "BristleTip", Vector3.new(width * 1.1, width * 1.1, 0.6), color, Enum.Material.Neon)
			place(t, cf * CFrame.new(0, 0, -length / 2 + 0.25))
		end
	end
	for i = 1, 9 do
		local a = (i / 9) * math.pi * 2
		bristle(a, 0.12, 9, 2.7, 0.16, STRAW, false)
	end
	for i = 1, 14 do
		local a = (i / 14 + 0.035) * math.pi * 2
		bristle(a, 0.24, 17, 2.9 + (i % 3) * 0.15, 0.13, if i % 2 == 0 then STRAW_DARK else STRAW, i % 2 == 1)
	end

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 11
	light.Brightness = 1.8
	light.Shadows = false
	light.Parent = tipCore

	-- Gradient streak from the bristles while flying.
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.CFrame = at(CFrame.new(0, 0.5, 5.8))
	a0.Parent = shaft
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.CFrame = at(CFrame.new(0, -0.5, 5.8))
	a1.Parent = shaft
	local trail = Instance.new("Trail")
	trail.Name = "Streak"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.MinLength = 0.2
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.25, color),
		ColorSequenceKeypoint.new(1, accent),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.6, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	trail.Parent = shaft

	model.Parent = character
	return model
end

local function buildBroom(player: Player, character: Model, root: BasePart)
	removeBroom(character)
	local color, accent = colorsOf(player)
	MovementService.BuildBroom(character, root, color, accent)
	character:SetAttribute(ATTRIBUTE, true)
end

-- Dealt or took damage in the last few seconds.
local function inCombat(player: Player): boolean
	local last = player:GetAttribute(CombatConfig.PlayerAttributes.LastCombat)
	return type(last) == "number" and now() - last < CombatConfig.InCombatTime
end

local function riding(character: Model?): boolean
	return character ~= nil and character:GetAttribute(ATTRIBUTE) == true
end

-- Takes the player off the broom (keeps their momentum legal for a moment).
function MovementService.Dismount(player: Player)
	local character = player.Character
	if not character or not riding(character) then
		return
	end
	removeBroom(character)
	remountAt[player] = os.clock() + BROOM.Cooldown
	character:SetAttribute(STATUS.MoveGraceUntil, math.max(character:GetAttribute(STATUS.MoveGraceUntil) or 0, now() + BROOM.DismountGrace))
end

-- Why the player can't summon the broom right now (nil when they can).
function MovementService.CannotRide(player: Player): string?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return "Dead"
	end
	if character:GetAttribute(STATUS.Beast) ~= nil or character:GetAttribute(STATUS.Shattered) == true then
		return "Beast"
	end
	if (character:GetAttribute(STATUS.StunnedUntil) or 0) > now() then
		return "Stunned"
	end
	if inCombat(player) and not BROOM.AllowedInCombat then
		return "Combat"
	end
	if os.clock() < (remountAt[player] or 0) then
		return "Cooldown"
	end
	return nil
end

local function onSetBroom(player: Player, on: unknown)
	if type(on) ~= "boolean" then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not (root and root:IsA("BasePart")) then
		return
	end
	if on == riding(character) then
		return
	end
	if not on then
		MovementService.Dismount(player)
		return
	end
	if MovementService.CannotRide(player) then
		return
	end
	if toggleCooldown(player) > 0 then
		return
	end
	buildBroom(player, character, root)
end

-- Relays a movement effect to every other client.
local fxBudget: { [Player]: { Tokens: number, At: number } } = {}
local function onMovementFX(player: Player, kind: unknown, direction: unknown)
	if type(kind) ~= "string" or not FX_KINDS[kind] then
		return
	end
	local budget = fxBudget[player]
	local clock = os.clock()
	if not budget then
		budget = { Tokens = FX_BUDGET, At = clock }
		fxBudget[player] = budget
	end
	budget.Tokens = math.min(FX_BUDGET, budget.Tokens + (clock - budget.At) * FX_BUDGET)
	budget.At = clock
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

-- Statuses that knock a rider off: acting (wind-ups), stuns, beast form.
local KNOCK_OFF = { STATUS.BusyUntil, STATUS.StunnedUntil, STATUS.Beast, STATUS.Shattered }

function MovementService.Init()
	Remotes.SetBroom.OnServerEvent:Connect(onSetBroom)
	Remotes.MovementFX.OnServerEvent:Connect(onMovementFX)

	local function watchCharacter(player: Player, character: Model)
		for _, attribute in KNOCK_OFF do
			character:GetAttributeChangedSignal(attribute):Connect(function()
				local value = character:GetAttribute(attribute)
				local on = if type(value) == "number" then value > now() else value ~= nil and value ~= false
				if on and riding(character) then
					MovementService.Dismount(player)
				end
			end)
		end
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				removeBroom(character)
			end)
		end
	end

	local function watch(player: Player)
		-- Hitting or getting hit knocks you off the broom.
		player:GetAttributeChangedSignal(CombatConfig.PlayerAttributes.LastCombat):Connect(function()
			if not BROOM.AllowedInCombat and riding(player.Character) then
				MovementService.Dismount(player)
			end
		end)
		-- A new gem re-tints the broom.
		player:GetAttributeChangedSignal("EquippedGem"):Connect(function()
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and riding(character) and root and root:IsA("BasePart") then
				buildBroom(player, character, root)
			end
		end)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		fxBudget[player] = nil
		remountAt[player] = nil
	end)
end

return MovementService
