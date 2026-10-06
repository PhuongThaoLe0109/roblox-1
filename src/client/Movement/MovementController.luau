-- MovementController
-- The local player's movement:
--   Run         always on (there is no separate sprint)
--   Dash        Q (gamepad: B); one more dash is allowed in the air
--   Double jump press jump again in the air
--   Broom       B (gamepad: D-pad up) or the HUD button; not while in combat
--     flying:   W along the camera, S brake / back, A / D glide sideways,
--               Space climb, Ctrl dive (gamepad: A / hold L3; touch: jump
--               button / hold DESCEND)
--
-- The character is simulated by this client, so speed, dash, double jump and
-- flight apply here directly; the server owns the broom model, knocks riders
-- off when they fight or get hit, checks the flight (MovementGuard) and relays
-- the effects to everyone else. Combat status (stun, block, wind-ups, beast
-- form) is applied to walk speed here too, since the client owns its character.

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

local DASH = MovementConfig.Dash
local JUMP = MovementConfig.DoubleJump
local BROOM = MovementConfig.Broom
local ATTRIBUTE = MovementConfig.BroomAttribute
local STATUS = CombatConfig.Status
local SPEEDS = CombatConfig.Speeds

local MovementController = {}

-- Fired whenever something the HUD shows changes.
MovementController.Changed = Signal.new()

-- Set by the combat controller: called after every dash (for its i-frames).
MovementController.OnDash = nil :: ((Vector3) -> ())?

MovementController.State = {
	Riding = false,
	DashReadyAt = 0, -- os.clock()
	BroomReadyAt = 0, -- os.clock(): when the broom can be summoned again
	Descending = false, -- held DESCEND (touch / gamepad)
}
local state = MovementController.State

local remotes: Instance
local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local extraJumps = 0
local airDashes = 0
local leftGroundAt = 0
local lastJumpRequest = 0
local pendingBroom = false

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

-- Walk speed and jump from combat status (stun, block, wind-ups, beast form).
-- Applied every frame, written only when it changes.
local lastSpeed, lastJump = -1, -1
local function applySpeed()
	if not humanoid or not character then
		return
	end
	local speed = MovementConfig.WalkSpeed
	local beast = character:GetAttribute(STATUS.Beast)
	if beast and GemKits.Beasts[beast] then
		speed = GemKits.Beasts[beast].Speed * MovementConfig.BeastSpeedScale
	end
	local jump = 7.2
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
-- Dash
--------------------------------------------------------------------------------

function MovementController.Dash()
	if not humanoid or not root or humanoid.Health <= 0 or state.Riding then
		return
	end
	local clock = os.clock()
	if clock < state.DashReadyAt then
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
	state.DashReadyAt = clock + DASH.Cooldown

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
	local clock = os.clock()
	-- JumpRequest repeats while the button is held: only a fresh press counts.
	local fresh = clock - lastJumpRequest > 0.12
	lastJumpRequest = clock
	if not fresh or not humanoid or not root or humanoid.Health <= 0 or state.Riding then
		return
	end
	if grounded() or clock - leftGroundAt < JUMP.MinAirTime or extraJumps >= JUMP.Extra then
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
-- Broom flight
--------------------------------------------------------------------------------

type Flight = {
	Attachment: Attachment,
	Velocity: LinearVelocity,
	Align: AlignOrientation,
	Current: Vector3,
	Yaw: number,
	Bank: number,
	Pitch: number,
	CeilingCheckAt: number,
	TooHigh: boolean,
}
local flight: Flight? = nil
local animateWasEnabled = true

local controls: any = nil
local function moveVector(): Vector3
	-- x: right, z: back (-1 = forward), from the default control module so
	-- keyboard, thumbsticks and the touch joystick all work.
	if controls == nil then
		local ok, module = pcall(function()
			local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
			return playerModule and (require :: any)(playerModule):GetControls()
		end)
		controls = if ok and module then module else false
	end
	if controls then
		local ok, v = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(v) == "Vector3" then
			return v
		end
	end
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		z += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		x += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		x -= 1
	end
	return Vector3.new(x, 0, z)
end

local function climbInput(): number
	local up = UserInputService:IsKeyDown(Enum.KeyCode.Space) or (humanoid ~= nil and humanoid.Jump)
	if humanoid then
		humanoid.Jump = false
	end
	local down = state.Descending
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	return (if up then 1 else 0) - (if down then 1 else 0)
end

local ceilingParams = RaycastParams.new()
ceilingParams.FilterType = Enum.RaycastFilterType.Exclude

-- Mirrors MovementGuard: no higher than MaxHeight over the ground below (or
-- CeilingY where there is no ground at all).
local function aboveCeiling(position: Vector3): boolean
	if not character then
		return false
	end
	ceilingParams.FilterDescendantsInstances = { character }
	if Workspace:Raycast(position, Vector3.new(0, -BROOM.MaxHeight, 0), ceilingParams) then
		return false
	end
	if position.Y > BROOM.CeilingY - 10 then
		return true
	end
	return Workspace:Raycast(position, Vector3.new(0, -2000, 0), ceilingParams) ~= nil
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else fallback
end

local function startFlight()
	if flight or not humanoid or not root then
		return
	end
	local animate = character and character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animateWasEnabled = animate.Enabled
		animate.Enabled = false
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0.2)
		end
	end
	humanoid.PlatformStand = true

	local attachment = Instance.new("Attachment")
	attachment.Name = "BroomFlight"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "BroomVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "BroomAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = 22
	align.CFrame = root.CFrame.Rotation
	align.Parent = root

	local look = flatUnit(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	local v = root.AssemblyLinearVelocity
	flight = {
		Attachment = attachment,
		Velocity = velocity,
		Align = align,
		-- Start with a small lift so mounting on the ground hops into the air.
		Current = Vector3.new(v.X, math.max(v.Y, 0) + 14, v.Z),
		Yaw = math.atan2(-look.X, -look.Z),
		Bank = 0,
		Pitch = 0,
		CeilingCheckAt = 0,
		TooHigh = false,
	}
end

local function stopFlight()
	local f = flight
	if not f then
		return
	end
	flight = nil
	f.Velocity:Destroy()
	f.Align:Destroy()
	f.Attachment:Destroy()
	if humanoid then
		humanoid.PlatformStand = false
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
	if root and root.Parent then
		-- Keep some momentum, at a speed a runner could have.
		local v = f.Current
		local flatV = Vector3.new(v.X, 0, v.Z)
		if flatV.Magnitude > MovementConfig.WalkSpeed * 1.3 then
			flatV = flatV.Unit * MovementConfig.WalkSpeed * 1.3
		end
		root.AssemblyLinearVelocity = Vector3.new(flatV.X, math.clamp(v.Y, -40, 30), flatV.Z)
		-- Stand back upright.
		local look = flatUnit(root.CFrame.LookVector, Vector3.new(0, 0, -1))
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end
	local animate = character and character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animate.Enabled = animateWasEnabled
	end
	extraJumps = JUMP.Extra -- no double jump straight off the broom
end

local function stepFlight(dt: number)
	local f = flight
	if not f or not root or not humanoid then
		return
	end
	if not humanoid.PlatformStand then
		humanoid.PlatformStand = true
	end
	local camera = Workspace.CurrentCamera
	local camCF = if camera then camera.CFrame else root.CFrame
	local look = camCF.LookVector
	local right = flatUnit(camCF.RightVector, root.CFrame.RightVector)
	local move = moveVector()
	local forward = -move.Z
	local strafe = move.X
	local climb = climbInput()

	-- Target velocity: W along the camera (climbing or diving with it), S
	-- brakes then backs off, A / D glide sideways, Space / Ctrl climb / dive.
	local target = Vector3.zero
	if forward > 0.05 then
		target += look * BROOM.Speed * forward
	elseif forward < -0.05 then
		target += flatUnit(look, root.CFrame.LookVector) * BROOM.BackSpeed * forward
	end
	target += right * BROOM.StrafeSpeed * strafe
	target += Vector3.yAxis * BROOM.ClimbSpeed * climb
	local top = math.sqrt(BROOM.Speed ^ 2 + BROOM.ClimbSpeed ^ 2)
	if target.Magnitude > top then
		target = target.Unit * top
	end

	-- Flight ceiling (checked a few times a second).
	local clock = os.clock()
	if clock >= f.CeilingCheckAt then
		f.CeilingCheckAt = clock + 0.15
		f.TooHigh = aboveCeiling(root.Position)
	end
	if f.TooHigh and target.Y > -6 then
		target = Vector3.new(target.X, -6, target.Z)
	end

	-- Ease toward the target: quick to brake, smooth to build up speed.
	local slowing = target.Magnitude < f.Current.Magnitude - 1 or target:Dot(f.Current) < 0
	local rate = if slowing then BROOM.Brake else BROOM.Accel
	f.Current = f.Current:Lerp(target, 1 - math.exp(-rate * dt))
	-- A gentle bob while hovering.
	local hover = math.clamp(1 - f.Current.Magnitude / 12, 0, 1)
	local bob = Vector3.new(0, math.sin(clock * 2.4) * 1.6 * hover, 0)
	f.Velocity.VectorVelocity = f.Current + bob

	-- Face the camera's heading; bank into turns and strafes, tip with the climb.
	local heading = flatUnit(look, root.CFrame.LookVector)
	local yaw = math.atan2(-heading.X, -heading.Z)
	local turn = yaw - f.Yaw
	turn = (turn + math.pi) % (2 * math.pi) - math.pi
	f.Yaw = yaw
	local speedFactor = math.clamp(f.Current.Magnitude / BROOM.Speed, 0, 1)
	local yawRate = turn / math.max(dt, 1 / 240)
	local bankGoal = math.clamp(math.deg(yawRate) * 0.22 * (0.3 + speedFactor) - strafe * 18, -BROOM.MaxBank, BROOM.MaxBank)
	f.Bank += (bankGoal - f.Bank) * (1 - math.exp(-6 * dt))
	local horizontal = Vector3.new(f.Current.X, 0, f.Current.Z).Magnitude
	local pitchGoal = math.clamp(math.deg(math.atan2(f.Current.Y, math.max(horizontal, 18))), -BROOM.MaxPitch, BROOM.MaxPitch)
	f.Pitch += (pitchGoal - f.Pitch) * (1 - math.exp(-5 * dt))
	f.Align.CFrame = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(f.Pitch), 0, 0) * CFrame.Angles(0, 0, math.rad(f.Bank))
end

-- How fast the broom is going, 0..1 (for the camera and effects).
function MovementController.FlightSpeed(): number
	local f = flight
	return if f then math.clamp(f.Current.Magnitude / BROOM.Speed, 0, 1.2) else 0
end

local function applyRiding(on: boolean)
	if not humanoid then
		return
	end
	if state.Riding == on then
		return
	end
	state.Riding = on
	if on then
		startFlight()
	else
		stopFlight()
		state.BroomReadyAt = os.clock() + BROOM.Cooldown
		state.Descending = false
	end
	lastJump = -1
	changed()
end

function MovementController.CanRide(): boolean
	if not character then
		return false
	end
	if character:GetAttribute(STATUS.Beast) or character:GetAttribute(STATUS.Shattered) == true then
		return false
	end
	return BROOM.AllowedInCombat or not inCombat()
end

-- Seconds until the broom can be summoned again (0 = ready).
function MovementController.BroomCooldown(): number
	return math.max(0, state.BroomReadyAt - os.clock())
end

function MovementController.ToggleBroom()
	if not character or pendingBroom then
		return
	end
	local want = not state.Riding
	if want and (not MovementController.CanRide() or MovementController.BroomCooldown() > 0) then
		return
	end
	pendingBroom = true
	local broomRemote = remotes:WaitForChild("SetBroom") :: RemoteEvent
	broomRemote:FireServer(want)
	-- The server answers through the character attribute; unlock either way.
	task.delay(BROOM.ToggleCooldown, function()
		pendingBroom = false
	end)
end

-- Hold to dive while riding (touch / gamepad).
function MovementController.SetDescending(on: boolean)
	state.Descending = on and state.Riding
end

--------------------------------------------------------------------------------
-- Character lifecycle
--------------------------------------------------------------------------------

local function onCharacter(newCharacter: Model)
	if flight then
		flight = nil
	end
	character = newCharacter
	local h = newCharacter:WaitForChild("Humanoid", 10)
	local r = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if not h or not h:IsA("Humanoid") or not r or not r:IsA("BasePart") or character ~= newCharacter then
		return
	end
	humanoid = h
	root = r
	state.Riding = false
	state.Descending = false
	extraJumps = 0
	airDashes = 0
	lastSpeed, lastJump = -1, -1
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
		if character == newCharacter then
			stopFlight()
			state.Riding = false
			MovementController.Changed:Fire()
		end
	end)
	newCharacter:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		if character == newCharacter then
			applyRiding(newCharacter:GetAttribute(ATTRIBUTE) == true)
		end
	end)
	if newCharacter:GetAttribute(ATTRIBUTE) == true then
		applyRiding(true)
	end
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local function onInputBegan(input: InputObject, processed: boolean)
	if input.KeyCode == Enum.KeyCode.ButtonL3 then
		MovementController.SetDescending(true)
	end
	if processed then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonB then
		MovementController.Dash()
	elseif key == Enum.KeyCode.B or key == Enum.KeyCode.DPadUp then
		MovementController.ToggleBroom()
	end
end

local function onInputEnded(input: InputObject)
	if input.KeyCode == Enum.KeyCode.ButtonL3 then
		MovementController.SetDescending(false)
	end
end

-- Field of view widens with speed.
local function onRenderStep(dt: number)
	applySpeed()
	stepFlight(dt)
	local camera = Workspace.CurrentCamera
	if not camera or not humanoid then
		return
	end
	local target = MovementConfig.DefaultFieldOfView
	if state.Riding then
		target = MovementConfig.DefaultFieldOfView + (BROOM.FieldOfView - MovementConfig.DefaultFieldOfView) * MovementController.FlightSpeed()
	elseif humanoid.MoveDirection.Magnitude > 0.1 and humanoid.WalkSpeed >= MovementConfig.WalkSpeed * 0.9 then
		target = MovementConfig.RunFieldOfView
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
		MovementController.SetDescending(false)
	end)
	RunService.RenderStepped:Connect(onRenderStep)

	-- Entering or leaving combat changes whether the broom can be summoned.
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
