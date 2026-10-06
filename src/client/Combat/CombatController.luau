-- CombatController
-- The local player's fighting inputs, for whatever gem they wear:
--
--   M1        left mouse (hold to keep the combo going) / R2 / ATTACK button
--   Z X C V   skills (gamepad R1, L1, D-pad left, D-pad right)
--   G         ultimate: beast transformation (gamepad D-pad down)
--   T         domain (gamepad R3)
--   F         hold to block (gamepad L2)
--   Q         dash (MovementController) also grants i-frames
--
-- Aims at the mouse (or straight ahead on touch / gamepad), predicts the
-- melee swing so it feels instant, moves the character for self-moving skills
-- (Rush, Quake), tracks cooldowns for the HUD and gates every press locally
-- with the same rules the server enforces (ActionService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local GemKits = require(ReplicatedStorage:WaitForChild("GemKits"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))
local CombatFX = require(script.Parent:WaitForChild("CombatFX"))
local MovementController = require(script.Parent.Parent:WaitForChild("Movement"):WaitForChild("MovementController"))

local player = Players.LocalPlayer

local STATUS = CombatConfig.Status
local PA = CombatConfig.PlayerAttributes
local TOLERANCE = CombatConfig.LatencyTolerance

local CombatController = {}

CombatController.CooldownChanged = Signal.new() -- (slot)
CombatController.KitChanged = Signal.new() -- (kit)
CombatController.Notice = Signal.new() -- (text, kind) short hints for the HUD

-- slot ("M1", "Z".."V", "G", "T") -> { ReadyAt: server time, Duration }
CombatController.Cooldowns = {} :: { [string]: { ReadyAt: number, Duration: number } }

local remotes: Instance
local actionRemote: RemoteEvent
local kit: GemKits.Kit = GemKits.Get(nil)
local combo = 0
local comboStyle = ""
local lastM1 = -math.huge
local m1Held = false
local blocking = false
local lastNotice = 0

local KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Z] = "Z",
	[Enum.KeyCode.X] = "X",
	[Enum.KeyCode.C] = "C",
	[Enum.KeyCode.V] = "V",
	[Enum.KeyCode.G] = "G",
	[Enum.KeyCode.T] = "T",
	[Enum.KeyCode.ButtonR1] = "Z",
	[Enum.KeyCode.ButtonL1] = "X",
	[Enum.KeyCode.DPadLeft] = "C",
	[Enum.KeyCode.DPadRight] = "V",
	[Enum.KeyCode.DPadDown] = "G",
	[Enum.KeyCode.ButtonR3] = "T",
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function character(): Model?
	return player.Character
end

local function rootPart(): BasePart?
	local c = character()
	local root = c and c:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function active(attribute: string): boolean
	local c = character()
	return c ~= nil and (c:GetAttribute(attribute) or 0) > now()
end

local function notice(text: string, kind: string?)
	if os.clock() - lastNotice > 1.2 then
		lastNotice = os.clock()
		CombatController.Notice:Fire(text, kind or "Warning")
	end
end

function CombatController.GetKit(): GemKits.Kit
	return kit
end

function CombatController.IsBeast(): boolean
	local c = character()
	return c ~= nil and c:GetAttribute(STATUS.Beast) ~= nil
end

function CombatController.MeleeStyle(): GemKits.Melee
	return if CombatController.IsBeast() then GemKits.Melee.Maul else kit.Melee
end

local function setCooldown(slot: string, readyAt: number, duration: number?)
	local current = CombatController.Cooldowns[slot]
	CombatController.Cooldowns[slot] = {
		ReadyAt = readyAt,
		Duration = duration or (if current then current.Duration else math.max(0.1, readyAt - now())),
	}
	CombatController.CooldownChanged:Fire(slot)
end

function CombatController.ReadyIn(slot: string): number
	local entry = CombatController.Cooldowns[slot]
	return if entry then math.max(0, entry.ReadyAt - now()) else 0
end

--------------------------------------------------------------------------------
-- Aim
--------------------------------------------------------------------------------

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

-- Flat aim direction and the world point under the cursor.
local function aim(): (Vector3, Vector3)
	local root = rootPart()
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return Vector3.new(0, 0, -1), Vector3.zero
	end
	local origin = root.Position
	local point: Vector3
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local exclude: { Instance } = { character() :: any }
		for _, name in { "CombatFX", "Auras", "MovementFX" } do
			local f = Workspace:FindFirstChild(name)
			if f then
				table.insert(exclude, f)
			end
		end
		aimParams.FilterDescendantsInstances = exclude
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * CombatConfig.MaxAimDistance, aimParams)
		point = if hit then hit.Position else ray.Origin + ray.Direction * 60
	else
		local look = camera.CFrame.LookVector
		point = origin + Vector3.new(look.X, 0, look.Z).Unit * 35
	end
	local flat = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	if flat.Magnitude < 0.5 then
		flat = root.CFrame.LookVector
	end
	return Vector3.new(flat.X, 0, flat.Z).Unit, point
end

-- Turn to face the aim for a moment.
local faceToken = 0
local function face(direction: Vector3, hold: number)
	local root = rootPart()
	local humanoid = character() and (character() :: Model):FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	humanoid.AutoRotate = false
	faceToken += 1
	local token = faceToken
	task.delay(hold, function()
		if faceToken == token and humanoid.Parent then
			humanoid.AutoRotate = true
		end
	end)
end

-- A short burst of velocity on our own character.
local function push(velocity: Vector3, duration: number)
	local root = rootPart()
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local force = Instance.new("LinearVelocity")
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	force.MaxForce = math.huge
	force.VectorVelocity = velocity
	force.Parent = root
	task.delay(duration, function()
		force:Destroy()
		attachment:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Gating
--------------------------------------------------------------------------------

local function canAct(): boolean
	local c = character()
	local humanoid = c and c:FindFirstChildOfClass("Humanoid")
	if not c or not humanoid or humanoid.Health <= 0 or c:GetAttribute(STATUS.Shattered) == true then
		return false
	end
	if active(STATUS.StunnedUntil) or c:GetAttribute(STATUS.Blocking) == true then
		return false
	end
	if (c:GetAttribute(STATUS.BusyUntil) or 0) > now() + TOLERANCE then
		return false
	end
	if player:GetAttribute(PA.InSafeZone) == true then
		notice("Safe zone: step off the plaza to fight", "Info")
		return false
	end
	-- Attacking knocks you off the broom.
	if MovementController.State.Riding then
		MovementController.ToggleBroom()
	end
	return true
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

function CombatController.Attack()
	if not canAct() then
		return
	end
	local style = CombatController.MeleeStyle()
	if comboStyle ~= style.Id then
		comboStyle = style.Id
		combo = 0
	end
	local t = now()
	if t - lastM1 < style.Interval - TOLERANCE then
		return
	end
	if combo >= style.Hits and CombatController.ReadyIn("M1") > TOLERANCE then
		return
	end
	combo = if t - lastM1 > style.ResetTime or combo >= style.Hits then 1 else combo + 1
	lastM1 = t
	local finisher = combo == style.Hits
	setCooldown("M1", t + (if finisher then style.EndLag else style.Interval))

	local direction, point = aim()
	face(direction, 0.35)
	local c = character() :: Model
	local gem = GemCatalog.Get(player:GetAttribute("EquippedGem"))
	CombatFX.Play("Swing", {
		Caster = c,
		Style = style.Id,
		Combo = combo,
		Hits = style.Hits,
		Direction = direction,
		Color = gem and gem.Color or nil,
		Accent = gem and gem.Accent or nil,
	})
	-- A small lunge with each swing.
	local root = rootPart()
	if root then
		push(direction * (if finisher then 26 else 12), 0.08)
	end
	actionRemote:FireServer("M1", direction, point)
end

function CombatController.UseSkill(key: string)
	local skill = GemKits.SkillFor(kit, key)
	if not skill then
		if key == GemKits.UltimateKey or key == GemKits.DomainKey then
			notice(if key == GemKits.UltimateKey then "Transformations belong to gems rarer than 1 in 750,000,000" else "Domains belong to gems rarer than 1 in 400,000,000,000", "Info")
		end
		return
	end
	if CombatController.ReadyIn(key) > TOLERANCE then
		return
	end
	if skill.Archetype == "Transform" and CombatController.IsBeast() then
		return
	end
	if not canAct() then
		return
	end
	setCooldown(key, now() + skill.Cooldown, skill.Cooldown)
	local direction, point = aim()
	face(direction, if skill.Archetype == "Beam" then skill.Duration else 0.4)

	-- Skills that move us: the client owns its character's physics.
	if skill.Archetype == "Rush" then
		push(direction * skill.Speed, skill.Duration)
	elseif skill.Archetype == "Slam" then
		push(direction * 22 + Vector3.new(0, 48, 0), 0.3)
		task.delay(math.max(0.1, skill.Delay - 0.22), function()
			push(Vector3.new(0, -130, 0), 0.18)
		end)
	end
	actionRemote:FireServer(key, direction, point)
end

local function setBlock(on: boolean)
	if on == blocking then
		return
	end
	blocking = on
	actionRemote:FireServer(if on then "Block" else "Unblock")
end

--------------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------------

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		m1Held = true
		CombatController.Attack()
		return
	end
	if input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL2 then
		setBlock(true)
		return
	end
	local key = KEYS[input.KeyCode]
	if key then
		CombatController.UseSkill(key)
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		m1Held = false
	elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonL2 then
		setBlock(false)
	end
end

function CombatController.SetBlock(on: boolean)
	setBlock(on)
end

function CombatController.SetAttackHeld(on: boolean)
	m1Held = on
	if on then
		CombatController.Attack()
	end
end

local function refreshKit()
	kit = GemKits.Get(player:GetAttribute("EquippedGem"))
	combo = 0
	table.clear(CombatController.Cooldowns)
	CombatController.KitChanged:Fire(kit)
end

function CombatController.Start()
	remotes = ReplicatedStorage:WaitForChild("Remotes")
	actionRemote = remotes:WaitForChild("CombatAction") :: RemoteEvent
	CombatFX.Start()

	refreshKit()
	player:GetAttributeChangedSignal("EquippedGem"):Connect(refreshKit)

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.WindowFocusReleased:Connect(function()
		m1Held = false
		setBlock(false)
	end)

	-- Holding M1 keeps the combo going.
	task.spawn(function()
		while true do
			task.wait(0.05)
			if m1Held then
				CombatController.Attack()
			end
		end
	end)

	-- Dashing grants i-frames on the server.
	MovementController.OnDash = function(direction: Vector3)
		local root = rootPart()
		actionRemote:FireServer("Dash", direction, if root then root.Position else Vector3.zero)
	end

	local stateRemote = remotes:WaitForChild("CombatState") :: RemoteEvent
	stateRemote.OnClientEvent:Connect(function(kind: string, slot: string?, value: any, extra: any)
		if kind == "Cooldown" and slot and type(value) == "number" then
			setCooldown(slot, value)
			if slot == "M1" and type(extra) == "number" then
				combo = extra
			end
		elseif kind == "Rejected" and slot then
			if value == "Cooldown" or value == "Busy" or value == "Stunned" or value == "Blocking" then
				-- Our prediction was early; the server's cooldown stands.
				return
			end
			if CombatController.Cooldowns[slot] then
				setCooldown(slot, now())
			end
			if value == "SafeZone" then
				notice("Safe zone: step off the plaza to fight", "Info")
			end
		elseif kind == "Reset" then
			combo = 0
			blocking = false
			table.clear(CombatController.Cooldowns)
			CombatController.CooldownChanged:Fire("*")
		end
	end)

	player.CharacterAdded:Connect(function()
		blocking = false
		m1Held = false
	end)
end

return CombatController
