-- Movement
-- Smooth, floaty "gem" movement for the local character:
--   * Speed eases toward its target instead of snapping (accel/decel feel).
--   * Sprint (Shift / L3 / touch button): faster, wider FOV, glowing trail.
--   * Double jump with a sparkle burst.
--   * Gem float: hold jump while falling after a double jump to glide down.
-- Visual extras here are local-only polish; gameplay-relevant VFX that others
-- must see belong to the server-replicated weapon/combat systems.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))

local Movement = {}

local SPRINT_MULTIPLIER = 1.45
local ACCELERATION = 10 -- higher = snappier speed changes
local BASE_FOV = 70
local SPRINT_FOV = 80
local DOUBLE_JUMP_VELOCITY = 52
local GLIDE_FALL_SPEED = 9
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local STATUS = CombatConfig.Status

local player = Players.LocalPlayer
local sprintHeld = false
local lastJumpRequest = 0

local function gemColor(character: Model): Color3
	local gemType = character:GetAttribute(GemConfig.Attributes.GemType) or player:GetAttribute(GemConfig.Attributes.GemType)
	local info = gemType and GemConfig.GemTypes[gemType]
	return if info then info.Color else Color3.fromRGB(255, 180, 230)
end

local function baseSpeed(character: Model): number
	local gemType = character:GetAttribute(GemConfig.Attributes.GemType)
	local info = gemType and GemConfig.GemTypes[gemType]
	return if info then info.BaseStats.WalkSpeed else 16
end

local function makeBurst(root: BasePart, color: Color3): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = "FeetFX"
	attachment.Position = Vector3.new(0, -2.8, 0)
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Enabled = false
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 220, 255)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 20)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Drag = 4
	emitter.Parent = attachment
	return emitter
end

local function makeTrail(root: BasePart, color: Color3): Trail
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, 0.9, 0.4)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -0.9, 0.4)
	a1.Parent = root

	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.4, color),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 160, 255)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Enabled = false
	trail.Parent = root
	return trail
end

-- Status effects set by the server (see CombatConfig.Status).
local function statusOf(character: Model): (boolean, number)
	local t = Workspace:GetServerTimeNow()
	local function active(name: string): boolean
		return (character:GetAttribute(name) or 0) > t
	end
	local immobile = active(STATUS.StunnedUntil) or active(STATUS.FrozenUntil) or active(STATUS.RootedUntil)
		or character:GetAttribute(STATUS.Puffed) == true
	local slow = if active(STATUS.SlowUntil) then character:GetAttribute(STATUS.SlowMult) or 1 else 1
	return immobile, slow
end

local function isJumpHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.Space)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
		or os.clock() - lastJumpRequest < 0.15 -- touch: JumpRequest repeats while held
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end

	local color = gemColor(character)
	local burst = makeBurst(root, color)
	local trail = makeTrail(root, color)
	local camera = Workspace.CurrentCamera

	local canDoubleJump = false
	local gliding = false
	local airborneSince = 0
	local currentSpeed = humanoid.WalkSpeed
	local jumpLocked = false
	local connections: { RBXScriptConnection } = {}

	table.insert(connections, humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Freefall or new == Enum.HumanoidStateType.Jumping then
			if airborneSince == 0 then
				airborneSince = os.clock()
				canDoubleJump = true
			end
		elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			if airborneSince > 0 and os.clock() - airborneSince > 0.9 then
				burst:Emit(10) -- soft landing sparkle after a long fall
			end
			airborneSince = 0
			canDoubleJump = false
			gliding = false
		end
	end))

	table.insert(connections, UserInputService.JumpRequest:Connect(function()
		lastJumpRequest = os.clock()
		if (statusOf(character)) then
			return
		end
		local state = humanoid:GetState()
		local inAir = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
		if inAir and canDoubleJump and os.clock() - airborneSince > 0.18 then
			canDoubleJump = false
			gliding = true
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, DOUBLE_JUMP_VELOCITY, v.Z)
			burst:Emit(28)
		end
	end))

	table.insert(connections, RunService.RenderStepped:Connect(function(dt)
		if humanoid.Health <= 0 then
			return
		end
		local immobile, slow = statusOf(character)
		if immobile ~= jumpLocked then
			jumpLocked = immobile
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not immobile)
		end
		if immobile then
			currentSpeed = 0
			humanoid.WalkSpeed = 0
			trail.Enabled = false
			return
		end

		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local sprinting = sprintHeld and moving
		local target = baseSpeed(character) * (if sprinting then SPRINT_MULTIPLIER else 1) * slow

		-- Exponential ease toward the target speed (frame-rate independent).
		local alpha = 1 - math.exp(-ACCELERATION * dt)
		currentSpeed += (target - currentSpeed) * alpha
		humanoid.WalkSpeed = currentSpeed

		if camera then
			local fov = if sprinting then SPRINT_FOV else BASE_FOV
			camera.FieldOfView += (fov - camera.FieldOfView) * (1 - math.exp(-6 * dt))
		end
		trail.Enabled = sprinting or gliding

		-- Gem float: cap fall speed while jump is held after a double jump.
		if gliding and isJumpHeld() then
			local v = root.AssemblyLinearVelocity
			if v.Y < -GLIDE_FALL_SPEED then
				root.AssemblyLinearVelocity = Vector3.new(v.X, -GLIDE_FALL_SPEED, v.Z)
			end
		end
	end))

	character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end
	end)
	humanoid.Died:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		trail.Enabled = false
	end)
end

function Movement.Start()
	ContextActionService:BindAction("GemSprint", function(_, inputState, input)
		if input.UserInputType == Enum.UserInputType.Touch then
			-- Touch button toggles; keyboard/gamepad is hold-to-sprint.
			if inputState == Enum.UserInputState.Begin then
				sprintHeld = not sprintHeld
			end
		else
			sprintHeld = inputState == Enum.UserInputState.Begin
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("GemSprint", "Sprint")
	ContextActionService:SetPosition("GemSprint", UDim2.new(1, -170, 1, -150))

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return Movement
