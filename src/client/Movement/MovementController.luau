-- MovementController
-- The local player's movement:
--   Sprint      hold Ctrl (gamepad: click the left stick to toggle)
--   Dash        Q (gamepad: B); one more dash is allowed in the air
--   Double jump press jump again in the air
--   Hoverboard  B (gamepad: D-pad up) or the HUD button; not while in combat
--
-- The character is simulated by this client, so speed, dash and double jump
-- apply here directly; the server owns the hoverboard model and relays the
-- effects to everyone else. Combat status (stun, block, wind-ups, beast form)
-- is applied to walk speed here too, since the client owns its character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemKits = require(ReplicatedStorage:WaitForChild("GemKits"))
local MovementConfig = require(ReplicatedStorage:WaitForChild("MovementConfig"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))
local MovementFX = require(script.Parent:WaitForChild("MovementFX"))

local player = Players.LocalPlayer

local SPRINT = MovementConfig.Sprint
local DASH = MovementConfig.Dash
local JUMP = MovementConfig.DoubleJump
local BOARD = MovementConfig.Hoverboard
local ATTRIBUTE = MovementConfig.HoverboardAttribute
local STATUS = CombatConfig.Status
local SPEEDS = CombatConfig.Speeds

local MovementController = {}

-- Fired whenever something the HUD shows changes.
MovementController.Changed = Signal.new()

-- Set by the combat controller: called after every dash (for its i-frames).
MovementController.OnDash = nil :: ((Vector3) -> ())?

MovementController.State = {
	Sprinting = false,
	Riding = false,
	DashReadyAt = 0, -- os.clock()
}
local state = MovementController.State

local remotes: Instance
local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local baseHip = 2
local extraJumps = 0
local airDashes = 0
local leftGroundAt = 0
local lastJumpRequest = 0
local pendingBoard = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Dealt or took damage in the last few seconds.
local function inCombat(): boolean
	local last = player:GetAttribute(CombatConfig.PlayerAttributes.LastCombat)
	return type(last) == "number" and now() - last < CombatConfig.InCombatTime
end

local function active(attribute: string): boolean
	return character ~= nil and (character:GetAttribute(attribute) or 0) > now()
end

local function grounded(): boolean
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

-- Walk speed and jump from movement state and combat status (stun, block,
-- wind-ups, beast form). Applied every frame, written only when it changes.
local lastSpeed, lastJump = -1, -1
local function applySpeed()
	if not humanoid or not character then
		return
	end
	local speed
	local beast = character:GetAttribute(STATUS.Beast)
	if state.Riding then
		speed = if state.Sprinting then BOARD.SprintSpeed else BOARD.Speed
	elseif beast and GemKits.Beasts[beast] then
		speed = GemKits.Beasts[beast].Speed * (if state.Sprinting then SPRINT.Multiplier else 1)
	else
		speed = MovementConfig.WalkSpeed * (if state.Sprinting then SPRINT.Multiplier else 1)
	end
	local jump = if state.Riding then BOARD.JumpHeight else 7.2
	if character:GetAttribute(STATUS.Shattered) == true or active(STATUS.StunnedUntil) then
		speed, jump = SPEEDS.Stunned, 0
	elseif active(STATUS.RootedUntil) then
		speed, jump = SPEEDS.Rooted, 0
	elseif character:GetAttribute(STATUS.Blocking) == true then
		speed, jump = math.min(speed, SPEEDS.Blocking), 0
	elseif active(STATUS.SlowUntil) then
		speed = math.min(speed, SPEEDS.Beam)
	elseif active(STATUS.SlowedUntil) then
		speed = math.min(speed, SPEEDS.Slowed)
	elseif active(STATUS.BusyUntil) then
		speed = math.min(speed, SPEEDS.Busy)
	end
	if speed ~= lastSpeed or humanoid.WalkSpeed ~= speed then
		lastSpeed = speed
		humanoid.WalkSpeed = speed
	end
	if jump ~= lastJump then
		lastJump = jump
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = jump
	end
end

local function changed()
	applySpeed()
	MovementController.Changed:Fire()
end

--------------------------------------------------------------------------------
-- Sprint
--------------------------------------------------------------------------------

function MovementController.SetSprint(on: boolean)
	if state.Sprinting == on then
		return
	end
	state.Sprinting = on
	changed()
end

--------------------------------------------------------------------------------
-- Dash
--------------------------------------------------------------------------------

function MovementController.Dash()
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if now < state.DashReadyAt then
		return
	end
	if character and (character:GetAttribute(STATUS.Shattered) == true or active(STATUS.StunnedUntil) or active(STATUS.RootedUntil)) then
		return
	end
	if not grounded() then
		if airDashes >= DASH.AirDashes then
			return
		end
		airDashes += 1
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		local camera = Workspace.CurrentCamera
		direction = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 1e-3 then
		return
	end
	direction = direction.Unit
	state.DashReadyAt = now + DASH.Cooldown

	-- Face the dash and hold the velocity for its duration (level in the air).
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "DashVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = direction * DASH.Speed
	velocity.Parent = root
	task.delay(DASH.Duration, function()
		velocity:Destroy()
		attachment:Destroy()
		-- Carry a little momentum out of the dash instead of stopping dead.
		if root and root.Parent then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(direction.X * 30, v.Y, direction.Z * 30)
		end
	end)

	if character then
		MovementFX.Dash(character, direction)
	end
	local fxRemote = remotes:WaitForChild("MovementFX") :: RemoteEvent
	fxRemote:FireServer("Dash", direction)
	if MovementController.OnDash then
		MovementController.OnDash(direction)
	end
	MovementController.Changed:Fire()
end

--------------------------------------------------------------------------------
-- Double jump
--------------------------------------------------------------------------------

local function onJumpRequest()
	local now = os.clock()
	-- JumpRequest repeats while the button is held: only a fresh press counts.
	local fresh = now - lastJumpRequest > 0.12
	lastJumpRequest = now
	if not fresh or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if grounded() or now - leftGroundAt < JUMP.MinAirTime or extraJumps >= JUMP.Extra then
		return
	end
	local stateType = humanoid:GetState()
	if stateType ~= Enum.HumanoidStateType.Freefall and stateType ~= Enum.HumanoidStateType.Jumping then
		return
	end
	extraJumps += 1
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, JUMP.Power, v.Z)
	if character then
		MovementFX.DoubleJump(character)
	end
	local fxRemote = remotes:WaitForChild("MovementFX") :: RemoteEvent
	fxRemote:FireServer("DoubleJump")
end

--------------------------------------------------------------------------------
-- Hoverboard
--------------------------------------------------------------------------------

local animateWasEnabled = true

local function setRidingPose(on: boolean)
	if not character or not humanoid then
		return
	end
	local animate = character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		if on then
			animateWasEnabled = animate.Enabled
			animate.Enabled = false
		else
			animate.Enabled = animateWasEnabled
		end
	end
	if on then
		-- Stand still on the deck instead of running in the air.
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0.15)
			end
		end
	end
end

local function applyRiding(on: boolean)
	if not humanoid then
		return
	end
	state.Riding = on
	humanoid.UseJumpPower = false
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		humanoid.HipHeight = baseHip + (if on then BOARD.Lift else 0)
	end
	lastJump = -1
	setRidingPose(on)
	changed()
end

function MovementController.CanRide(): boolean
	if character and character:GetAttribute(STATUS.Beast) then
		return false
	end
	return BOARD.AllowedInCombat or not inCombat()
end

function MovementController.ToggleHoverboard()
	if not character or pendingBoard then
		return
	end
	local want = not state.Riding
	if want and not MovementController.CanRide() then
		return
	end
	pendingBoard = true
	local boardRemote = remotes:WaitForChild("SetHoverboard") :: RemoteEvent
	boardRemote:FireServer(want)
	-- The server answers through the character attribute; unlock either way.
	task.delay(BOARD.Cooldown, function()
		pendingBoard = false
	end)
end

--------------------------------------------------------------------------------
-- Character lifecycle
--------------------------------------------------------------------------------

local function onCharacter(newCharacter: Model)
	character = newCharacter
	local h = newCharacter:WaitForChild("Humanoid", 10)
	local r = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if not h or not h:IsA("Humanoid") or not r or not r:IsA("BasePart") or character ~= newCharacter then
		return
	end
	humanoid = h
	root = r
	baseHip = h.HipHeight
	state.Riding = false
	extraJumps = 0
	airDashes = 0
	applySpeed()
	MovementController.Changed:Fire()

	h.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.Swimming then
			extraJumps = 0
			airDashes = 0
		elseif new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then
			if leftGroundAt < os.clock() - 0.5 or new == Enum.HumanoidStateType.Jumping then
				leftGroundAt = os.clock()
			end
		end
	end)
	h.Died:Connect(function()
		state.Riding = false
		MovementController.Changed:Fire()
	end)
	newCharacter:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		applyRiding(newCharacter:GetAttribute(ATTRIBUTE) == true)
	end)
	if newCharacter:GetAttribute(ATTRIBUTE) == true then
		applyRiding(true)
	end
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local SPRINT_KEYS = { [Enum.KeyCode.LeftControl] = true, [Enum.KeyCode.RightControl] = true }

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local key = input.KeyCode
	if SPRINT_KEYS[key] then
		MovementController.SetSprint(true)
	elseif key == Enum.KeyCode.ButtonL3 then
		MovementController.SetSprint(not state.Sprinting)
	elseif key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonB then
		MovementController.Dash()
	elseif key == Enum.KeyCode.B or key == Enum.KeyCode.DPadUp then
		MovementController.ToggleHoverboard()
	end
end

local function onInputEnded(input: InputObject)
	if SPRINT_KEYS[input.KeyCode] then
		MovementController.SetSprint(false)
	end
end

-- Field of view widens with speed.
local function updateCamera(dt: number)
	applySpeed()
	local camera = Workspace.CurrentCamera
	if not camera or not humanoid then
		return
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local target = MovementConfig.DefaultFieldOfView
	if state.Riding then
		target = if moving then BOARD.FieldOfView else MovementConfig.DefaultFieldOfView + 4
	elseif state.Sprinting and moving then
		target = SPRINT.FieldOfView
	end
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 6)
end

function MovementController.Start()
	remotes = ReplicatedStorage:WaitForChild("Remotes")
	MovementFX.Start()

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.JumpRequest:Connect(onJumpRequest)
	UserInputService.WindowFocusReleased:Connect(function()
		MovementController.SetSprint(false)
	end)
	RunService.RenderStepped:Connect(updateCamera)

	-- Entering or leaving combat changes whether the board can be summoned.
	player:GetAttributeChangedSignal(CombatConfig.PlayerAttributes.LastCombat):Connect(function()
		MovementController.Changed:Fire()
		task.delay(CombatConfig.InCombatTime + 0.1, function()
			MovementController.Changed:Fire()
		end)
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return MovementController
