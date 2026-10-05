-- PuffService
-- What happens at 0 HP: the body bursts into a puff of light and the gem is
-- left floating in a crystal capsule instead of the character dying.
--
--   * Reform: after CombatConfig.Puff.Duration the gem reforms on the spot at
--     full health with brief spawn protection.
--   * Seal: an enemy holds the capsule's prompt to bubble the gem and send it
--     home (the sealer earns essence).
--   * Revive: an ally holds the prompt to reform the gem immediately.
--   * Return Home: the puffed player may give up and respawn at home.
--
-- Replicated state (CombatConfig.Status) on the character: Puffed,
-- PuffedUntil, PuffAction, ProtectedUntil. Works for training dummies too.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))

local Modules = script.Parent.Parent
local GemDataManager = require(Modules:WaitForChild("GemDataManager"))
local FactionTeams = require(Modules:WaitForChild("FactionTeams"))
local Remotes = require(Modules:WaitForChild("Remotes"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local STATUS = CombatConfig.Status
local PUFF = CombatConfig.Puff
local DUMMY_GEM_COLOR = Color3.fromRGB(215, 195, 245)

local PuffService = {}

type PuffState = {
	Token: number,
	Capsule: Model,
	Hidden: { [Instance]: number }, -- original transparencies
	DisplayDistance: Enum.HumanoidDisplayDistanceType,
}

local puffed: { [Model]: PuffState } = {}
local tokenCounter = 0

local function now(): number
	return CombatService.Now()
end

--------------------------------------------------------------------------------
-- Body visibility
--------------------------------------------------------------------------------

local function hideBody(character: Model): { [Instance]: number }
	local hidden = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			hidden[d] = d.Transparency
			d.Transparency = 1
		elseif d:IsA("Decal") then
			hidden[d] = d.Transparency
			d.Transparency = 1
		elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("PointLight") then
			hidden[d] = if (d :: any).Enabled then 1 else 0
			;(d :: any).Enabled = false
		end
	end
	return hidden
end

local function showBody(hidden: { [Instance]: number })
	for instance, value in hidden do
		if instance.Parent then
			if instance:IsA("BasePart") or instance:IsA("Decal") then
				(instance :: any).Transparency = value
			else
				(instance :: any).Enabled = value == 1
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Capsule
--------------------------------------------------------------------------------

local function gemColorOf(model: Model): Color3
	local gemType = model:GetAttribute(GemConfig.Attributes.GemType)
	local info = gemType and GemConfig.GemTypes[gemType]
	return if info then info.Color else DUMMY_GEM_COLOR
end

local function displayName(model: Model): string
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player.DisplayName
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.DisplayName ~= "" then humanoid.DisplayName else model.Name
end

local function newPrompt(parent: Instance, kind: string, actionText: string, hold: number, ownerUserId: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = kind .. "Prompt"
	prompt.ActionText = actionText
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = PUFF.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = if kind == "Seal" then Enum.KeyCode.G else Enum.KeyCode.H
	prompt.GamepadKeyCode = if kind == "Seal" then Enum.KeyCode.ButtonL1 else Enum.KeyCode.ButtonL2
	prompt:SetAttribute("Kind", kind)
	prompt:SetAttribute("OwnerUserId", ownerUserId)
	CollectionService:AddTag(prompt, CombatConfig.Tags.PuffPrompt)
	prompt.Parent = parent
	return prompt
end

local function buildCapsule(model: Model, root: BasePart, ownerUserId: number): Model
	local color = gemColorOf(model)
	local position = root.Position - Vector3.new(0, 0.5, 0)

	local capsule = Instance.new("Model")
	capsule.Name = "PuffCapsule"

	local gem = Instance.new("Part")
	gem.Name = "CapsuleGem"
	gem.Size = Vector3.new(1.8, 1.8, 1.1)
	gem.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(45))
	gem.Color = color
	gem.Material = Enum.Material.Neon
	gem.Anchored = true
	gem.CanCollide = false
	gem.CanTouch = false
	gem.CanQuery = false
	gem.Parent = capsule
	CollectionService:AddTag(gem, "Spin")

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 14
	light.Brightness = 2
	light.Parent = gem

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.LightEmission = 1
	sparkles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 235)),
	})
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0.1, 1)
	sparkles.Rate = 14
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(0.5, 1.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Parent = gem

	local bubble = Instance.new("Part")
	bubble.Name = "CapsuleBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.one * 5
	bubble.CFrame = CFrame.new(position)
	bubble.Color = Color3.fromRGB(255, 210, 240)
	bubble.Material = Enum.Material.ForceField
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanTouch = false
	bubble.CanQuery = false
	bubble.Parent = capsule

	local name = displayName(model)
	local seal = newPrompt(gem, "Seal", "Seal Gem", PUFF.SealHoldTime, ownerUserId)
	seal.ObjectText = name
	local revive = newPrompt(gem, "Revive", "Revive", PUFF.ReviveHoldTime, ownerUserId)
	revive.ObjectText = name
	revive.UIOffset = Vector2.new(0, 70)

	capsule.Parent = model
	return capsule
end

--------------------------------------------------------------------------------
-- State transitions
--------------------------------------------------------------------------------

local function setAnchored(model: Model, anchored: boolean)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = anchored
	end
end

local function clear(model: Model): PuffState?
	local state = puffed[model]
	if not state then
		return nil
	end
	puffed[model] = nil
	if state.Capsule.Parent then
		state.Capsule:Destroy()
	end
	model:SetAttribute(STATUS.Puffed, false)
	model:SetAttribute(STATUS.PuffedUntil, 0)
	model:SetAttribute(STATUS.PuffAction, "")
	return state
end

-- Reform on the spot (timer expiry or ally revive).
function PuffService.Reform(model: Model)
	local state = clear(model)
	if not state or not model.Parent then
		return
	end
	showBody(state.Hidden)
	setAnchored(model, false)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth * PUFF.ReformHealth
		humanoid.DisplayDistanceType = state.DisplayDistance
	end
	model:SetAttribute(STATUS.ProtectedUntil, now() + PUFF.ProtectTime)

	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		CombatService.FX("Reform", { Target = model, Position = root.Position, Color = gemColorOf(model) })
	end
end

-- Enter the puff state. Called by CombatService for lethal combat damage.
function PuffService.Puff(target: CombatService.Target, attacker: CombatService.Attacker?)
	local model = target.Model
	if puffed[model] or not model.Parent then
		return
	end

	local player = target.Player
	local ownerUserId = if player then player.UserId else 0

	-- Put the weapon away and freeze the body in place.
	local weapon = model:FindFirstChild("SummonedWeapon")
	if weapon then
		weapon:Destroy()
		model:SetAttribute(STATUS.WeaponSummoned, false)
	end
	for _, child in target.Root:GetChildren() do
		if child:IsA("LinearVelocity") or child.Name == "KnockbackAttachment" then
			child:Destroy()
		end
	end
	target.Root.AssemblyLinearVelocity = Vector3.zero
	setAnchored(model, true)

	tokenCounter += 1
	local token = tokenCounter
	local duration = if target.IsDummy then PUFF.DummyDuration else PUFF.Duration

	local hidden = hideBody(model)
	local capsule = buildCapsule(model, target.Root, ownerUserId)
	local displayDistance = target.Humanoid.DisplayDistanceType
	target.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	puffed[model] = {
		Token = token,
		Capsule = capsule,
		Hidden = hidden,
		DisplayDistance = displayDistance,
	}
	model:SetAttribute(STATUS.Puffed, true)
	model:SetAttribute(STATUS.PuffedUntil, now() + duration)
	model:SetAttribute(STATUS.PuffAction, "")

	CombatService.FX("Puff", { Position = target.Root.Position, Color = gemColorOf(model) })

	if attacker and attacker.Player and player then
		GemDataManager.IncrementStat(attacker.Player, "PuffsInflicted")
		GemDataManager.IncrementStat(player, "TimesPuffed")
		Remotes.NotifyPlayer(attacker.Player, `You puffed {player.DisplayName}! Seal their gem before it reforms.`, "Success")
	end
	if player then
		Remotes.NotifyPlayer(player, "Your form was disrupted! Your gem will reform soon.", "Warning")
	end

	task.delay(duration, function()
		local state = puffed[model]
		if state and state.Token == token then
			PuffService.Reform(model)
		end
	end)
end

function PuffService.IsPuffed(model: Model): boolean
	return puffed[model] ~= nil
end

-- Send a puffed gem home (enemy seal, or the owner choosing to return).
local function sendHome(model: Model, sealer: Player?)
	local state = clear(model)
	if not state then
		return
	end
	local owner = Players:GetPlayerFromCharacter(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	CombatService.FX("Seal", {
		Position = if root and root:IsA("BasePart") then root.Position else state.Capsule:GetPivot().Position,
		Color = gemColorOf(model),
	})

	if sealer and owner then
		GemDataManager.IncrementStat(sealer, "GemsSealed")
		GemDataManager.AddEssence(sealer, PUFF.SealReward, "Seal")
		Remotes.NotifyPlayer(sealer, `Sealed {owner.DisplayName}'s gem! +{PUFF.SealReward} essence`, "Success")
		Remotes.NotifyPlayer(owner, `{sealer.DisplayName} sealed your gem. Reforming at home…`, "Warning")
	end

	if owner then
		task.delay(PUFF.SealRespawnDelay, function()
			if owner.Character == model then
				FactionTeams.Respawn(owner)
			end
		end)
	else
		-- Dummies reform where they stand after a short pause (still untouchable).
		puffed[model] = state
		model:SetAttribute(STATUS.Puffed, true)
		task.delay(PUFF.SealRespawnDelay, function()
			if puffed[model] == state then
				PuffService.Reform(model)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Prompts
--------------------------------------------------------------------------------

local function promptOwnerModel(prompt: ProximityPrompt): Model?
	local capsule = prompt:FindFirstAncestor("PuffCapsule")
	local model = capsule and capsule.Parent
	return if model and model:IsA("Model") then model else nil
end

local function canUse(player: Player, prompt: ProximityPrompt): (boolean, Model?)
	local model = promptOwnerModel(prompt)
	if not model or not puffed[model] then
		return false, nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or character == model or not humanoid or humanoid.Health <= 0 or character:GetAttribute(STATUS.Puffed) then
		return false, nil
	end
	local attacker = { Player = player, Character = character }
	local isDummy = CollectionService:HasTag(model, CombatConfig.Tags.Dummy)
	local ally = not isDummy and CombatService.IsAlly(attacker, model)
	local kind = prompt:GetAttribute("Kind")
	if kind == "Seal" then
		return not ally, model
	elseif kind == "Revive" then
		return ally, model
	end
	return false, nil
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if not CollectionService:HasTag(prompt, CombatConfig.Tags.PuffPrompt) then
		return
	end
	local ok, model = canUse(player, prompt)
	if not ok or not model then
		return
	end
	if prompt:GetAttribute("Kind") == "Seal" then
		sendHome(model, player)
	else
		PuffService.Reform(model)
		local owner = Players:GetPlayerFromCharacter(model)
		if owner then
			Remotes.NotifyPlayer(owner, `{player.DisplayName} revived you!`, "Success")
		end
	end
end

local function onHoldChanged(prompt: ProximityPrompt, player: Player, holding: boolean)
	if not CollectionService:HasTag(prompt, CombatConfig.Tags.PuffPrompt) then
		return
	end
	local ok, model = canUse(player, prompt)
	if ok and model then
		local kind = prompt:GetAttribute("Kind")
		model:SetAttribute(STATUS.PuffAction, if holding then (if kind == "Seal" then "Sealing" else "Reviving") else "")
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function PuffService.Init()
	CombatService.LethalHandler = PuffService.Puff

	local ProximityPromptService = game:GetService("ProximityPromptService")
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
		onHoldChanged(prompt, player, true)
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, player)
		onHoldChanged(prompt, player, false)
	end)

	Remotes.PuffAction.OnServerEvent:Connect(function(player, action)
		if action == "ReturnHome" then
			local character = player.Character
			if character and puffed[character] then
				sendHome(character, nil)
			end
		end
	end)

	-- Forget models that disappear (respawn, leave).
	game:GetService("RunService").Heartbeat:Connect(function()
		for model in puffed do
			if not model.Parent then
				puffed[model] = nil
			end
		end
	end)
end

return PuffService
