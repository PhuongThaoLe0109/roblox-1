-- WeaponController
-- Local input + prediction for the weapon system.
--   F / D-pad Up / touch "Weapon"   summon or dismiss
--   Mouse1 / R2 / touch "Attack"    basic attack (hold to keep attacking)
--   Q / X, E / B, R / R1            skills
-- Aim: mouse cursor on desktop, screen centre on touch/gamepad.
-- Self-motion skills (dash, roll, leap) move the character immediately on
-- this client; the server resolves hits from the replicated position.
-- Cooldowns are predicted locally and corrected by WeaponState from the server.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))
local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))

local STATUS = CombatConfig.Status

local WeaponController = {}

WeaponController.ReadyAt = { Basic = 0, Q = 0, E = 0, R = 0 } -- server time
WeaponController.Duration = { Basic = 1, Q = 1, E = 1, R = 1 } -- for UI sweeps
WeaponController.Changed = Signal.new() -- (slot?) cooldowns or weapon changed
WeaponController.Pressed = Signal.new() -- (slot) for UI feedback
WeaponController.Rejected = Signal.new() -- (slot, reason)

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("GemRemotes")
local actionRemote = remotes:WaitForChild("WeaponAction") :: RemoteEvent
local stateRemote = remotes:WaitForChild("WeaponState") :: RemoteEvent

local attackHeld = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

function WeaponController.GetWeapon()
	return WeaponConfig.Get(player:GetAttribute(GemConfig.Attributes.WeaponId))
end

local function getCharacter(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function isActive(model: Model, attribute: string): boolean
	return (model:GetAttribute(attribute) or 0) > now()
end

--------------------------------------------------------------------------------
-- Aim
--------------------------------------------------------------------------------

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function getAim(root: BasePart): (Vector3, Vector3)
	local camera = Workspace.CurrentCamera
	local screenPoint: Vector2
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		screenPoint = UserInputService:GetMouseLocation()
	else
		screenPoint = camera.ViewportSize / 2
	end
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)

	local exclude: { Instance } = { player.Character :: Instance }
	for _, name in { "LocalFX", "CombatFX" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	aimParams.FilterDescendantsInstances = exclude

	local result = Workspace:Raycast(ray.Origin, ray.Direction * CombatConfig.MaxAimDistance, aimParams)
	local point = if result then result.Position else ray.Origin + ray.Direction * CombatConfig.MaxAimDistance
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local direction = point - origin
	if direction.Magnitude < 1 then
		direction = root.CFrame.LookVector
	end
	return direction.Unit, point
end

local function faceDirection(root: BasePart, direction: Vector3)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	end
end

--------------------------------------------------------------------------------
-- Self motion
--------------------------------------------------------------------------------

local function applyMotion(root: BasePart, humanoid: Humanoid, motion: any, aim: Vector3)
	local flat = Vector3.new(aim.X, 0, aim.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else root.CFrame.LookVector

	if motion.Type == "Leap" then
		root.AssemblyLinearVelocity = flat * (motion.Forward or 30) + Vector3.new(0, motion.Up or 60, 0)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "SkillMotion"
	attachment.Parent = root
	local force = Instance.new("LinearVelocity")
	force.Name = "SkillMotion"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	force.MaxForce = 1e6
	force.VectorVelocity = flat * (motion.Speed or 90) + Vector3.new(0, motion.Lift or 0, 0)
	force.Parent = root

	local duration = motion.Duration or 0.3
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if os.clock() - started >= duration or humanoid.Health <= 0 or not force.Parent then
			connection:Disconnect()
			force:Destroy()
			attachment:Destroy()
			return
		end
		if motion.Type == "Roll" then
			-- Steer with the camera; keep a little downward pull so it hugs the ground.
			local look = Workspace.CurrentCamera.CFrame.LookVector
			local steer = Vector3.new(look.X, 0, look.Z)
			if steer.Magnitude > 1e-3 then
				force.VectorVelocity = steer.Unit * (motion.Speed or 70) + Vector3.new(0, -10, 0)
				faceDirection(root, steer)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local function tryUse(slot: string)
	local character, humanoid, root = getCharacter()
	if not character or not humanoid or not root then
		return
	end
	if character:GetAttribute(STATUS.Puffed) or isActive(character, STATUS.StunnedUntil) then
		return
	end
	local weapon = WeaponController.GetWeapon()
	if not weapon then
		return
	end
	if now() < WeaponController.ReadyAt[slot] then
		return
	end

	local aim, point = getAim(root)
	local summoned = character:GetAttribute(STATUS.WeaponSummoned) == true

	actionRemote:FireServer(slot, aim, point)
	WeaponController.Pressed:Fire(slot)

	if not summoned then
		-- The server summons instead; give it a moment before accepting presses.
		WeaponController.ReadyAt[slot] = now() + 0.4
		return
	end

	local config = WeaponConfig.GetSlot(weapon, slot) :: any
	-- Predict the cooldown (mirroring the server's attack-speed buffs); the
	-- server's WeaponState will correct it.
	local cooldown = config.Cooldown
	local heat = weapon.Skills.E.AttackSpeed
	if slot == "Basic" and heat and isActive(character, STATUS.HeatUntil) then
		cooldown /= heat
	end
	WeaponController.ReadyAt[slot] = now() + cooldown
	WeaponController.Duration[slot] = cooldown
	WeaponController.Changed:Fire(slot)

	faceDirection(root, aim)
	if config.SelfMotion and not isActive(character, STATUS.RootedUntil) then
		applyMotion(root, humanoid, config.SelfMotion, aim)
	end
end

local function toggleWeapon()
	actionRemote:FireServer("Toggle", Vector3.zAxis, Vector3.zero)
end

function WeaponController.Use(slot: string)
	tryUse(slot)
end

function WeaponController.Toggle()
	toggleWeapon()
end

function WeaponController.Start()
	stateRemote.OnClientEvent:Connect(function(event: string, slot: string, value: any)
		if event == "Cooldown" and type(value) == "number" then
			WeaponController.ReadyAt[slot] = value
			WeaponController.Duration[slot] = math.max(0.05, value - now())
			WeaponController.Changed:Fire(slot)
		elseif event == "Rejected" then
			if value ~= "Cooldown" then
				WeaponController.ReadyAt[slot] = 0
			end
			WeaponController.Rejected:Fire(slot, value)
			WeaponController.Changed:Fire(slot)
		end
	end)

	ContextActionService:BindAction("GemWeaponToggle", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggleWeapon()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.F, Enum.KeyCode.DPadUp)
	ContextActionService:SetTitle("GemWeaponToggle", "Weapon")
	ContextActionService:SetPosition("GemWeaponToggle", UDim2.new(1, -260, 1, -150))

	ContextActionService:BindAction("GemAttack", function(_, state)
		attackHeld = state == Enum.UserInputState.Begin
		if attackHeld then
			tryUse("Basic")
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("GemAttack", "Attack")
	ContextActionService:SetPosition("GemAttack", UDim2.new(1, -110, 1, -210))

	local skillBindings = {
		Q = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX, UDim2.new(1, -200, 1, -260) },
		E = { Enum.KeyCode.E, Enum.KeyCode.ButtonB, UDim2.new(1, -140, 1, -300) },
		R = { Enum.KeyCode.R, Enum.KeyCode.ButtonR1, UDim2.new(1, -70, 1, -290) },
	}
	for slot, binding in skillBindings do
		local actionName = "GemSkill" .. slot
		ContextActionService:BindAction(actionName, function(_, state)
			if state == Enum.UserInputState.Begin then
				tryUse(slot)
			end
			return Enum.ContextActionResult.Sink
		end, true, binding[1], binding[2])
		ContextActionService:SetTitle(actionName, slot)
		ContextActionService:SetPosition(actionName, binding[3])
	end

	-- Hold-to-attack.
	RunService.Heartbeat:Connect(function()
		if attackHeld then
			tryUse("Basic")
		end
	end)

	-- New gem/weapon or respawn: reset predicted cooldowns.
	local function reset()
		for slot in WeaponController.ReadyAt do
			WeaponController.ReadyAt[slot] = 0
		end
		attackHeld = false
		WeaponController.Changed:Fire(nil)
	end
	player:GetAttributeChangedSignal(GemConfig.Attributes.WeaponId):Connect(reset)
	player.CharacterAdded:Connect(reset)
end

return WeaponController
