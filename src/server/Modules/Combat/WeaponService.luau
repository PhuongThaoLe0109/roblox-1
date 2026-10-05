-- WeaponService
-- Server side of the weapon system:
--   * Summon / dismiss the player's light-weapon (built by WeaponBuilder).
--   * Validate WeaponAction requests (types, alive, stunned, cooldowns, aim).
--   * Track the basic-attack combo and dispatch to Skills/<WeaponId>.
--   * Tell the caster's client when each slot is ready again (WeaponState).
--
-- WeaponAction payload: (action, aimDirection: Vector3, aimPoint: Vector3)
--   action = "Toggle" | "Summon" | "Dismiss" | "Basic" | "Q" | "E" | "R"
-- WeaponState events to the caster:
--   ("Cooldown", slot, readyAtServerTime)
--   ("Rejected", slot, reason)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local WeaponConfig = require(ReplicatedStorage:WaitForChild("WeaponConfig"))

local Modules = script.Parent.Parent
local GemDataManager = require(Modules:WaitForChild("GemDataManager"))
local Remotes = require(Modules:WaitForChild("Remotes"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local WeaponBuilder = require(script.Parent:WaitForChild("WeaponBuilder"))

local STATUS = CombatConfig.Status
local LATENCY_TOLERANCE = 0.12 -- accept a press slightly before the cooldown ends

local WeaponService = {}

local skillModules: { [string]: any } = {}
for _, module in script.Parent:WaitForChild("Skills"):GetChildren() do
	if module:IsA("ModuleScript") then
		skillModules[module.Name] = require(module)
	end
end

type State = {
	NextReady: { [string]: number },
	Combo: number,
	LastBasic: number,
	LastSummon: number,
}

local states: { [Player]: State } = {}

local VALID_SLOTS = { Basic = true, Q = true, E = true, R = true }

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = { NextReady = {}, Combo = 0, LastBasic = 0, LastSummon = 0 }
		states[player] = state
	end
	return state
end

local function isFinite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

--------------------------------------------------------------------------------
-- Summoning
--------------------------------------------------------------------------------

function WeaponService.IsSummoned(character: Model?): boolean
	return character ~= nil and character:FindFirstChild("SummonedWeapon") ~= nil
end

function WeaponService.Dismiss(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local model = character:FindFirstChild("SummonedWeapon")
	if model then
		CombatService.FX("Dismiss", { Caster = character, WeaponId = model:GetAttribute("WeaponId") })
		task.delay(0.25, function()
			model:Destroy()
		end)
	end
	character:SetAttribute(STATUS.WeaponSummoned, false)
end

function WeaponService.Summon(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or WeaponService.IsSummoned(character) then
		return false
	end
	local weaponId = player:GetAttribute(GemConfig.Attributes.WeaponId)
	if not WeaponConfig.Get(weaponId) then
		return false
	end
	local model = WeaponBuilder.Build(character, weaponId)
	if not model then
		return false
	end
	character:SetAttribute(STATUS.WeaponSummoned, true)
	CombatService.FX("Summon", { Caster = character, WeaponId = weaponId })
	return true
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

local function reject(player: Player, slot: string, reason: string)
	Remotes.WeaponState:FireClient(player, "Rejected", slot, reason)
end

local function onAction(player: Player, action: unknown, aimDirection: unknown, aimPoint: unknown)
	if type(action) ~= "string" then
		return
	end
	if not GemDataManager.IsLoaded(player) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) then
		return
	end
	if character:GetAttribute(STATUS.Puffed) then
		return
	end

	local state = getState(player)

	-- Summon / dismiss
	if action == "Toggle" or action == "Summon" or action == "Dismiss" then
		if os.clock() - state.LastSummon < WeaponConfig.SummonCooldown then
			return
		end
		state.LastSummon = os.clock()
		local summoned = WeaponService.IsSummoned(character)
		if action == "Dismiss" or (action == "Toggle" and summoned) then
			WeaponService.Dismiss(player)
		else
			WeaponService.Summon(player)
		end
		return
	end

	local slot = action
	if not VALID_SLOTS[slot] then
		return
	end
	if typeof(aimDirection) ~= "Vector3" or typeof(aimPoint) ~= "Vector3" then
		return
	end
	local direction = aimDirection :: Vector3
	local point = aimPoint :: Vector3
	if not isFinite(direction) or not isFinite(point) or direction.Magnitude < 1e-3 then
		return
	end

	-- Attacking without a weapon out summons it first (the press is consumed).
	if not WeaponService.IsSummoned(character) then
		if os.clock() - state.LastSummon >= WeaponConfig.SummonCooldown then
			state.LastSummon = os.clock()
			WeaponService.Summon(player)
		end
		reject(player, slot, "Summoning")
		return
	end

	if CombatService.IsActive(character, STATUS.StunnedUntil) then
		reject(player, slot, "Stunned")
		return
	end

	local weaponId = player:GetAttribute(GemConfig.Attributes.WeaponId)
	local weapon = WeaponConfig.Get(weaponId)
	local module = weaponId and skillModules[weaponId]
	local slotConfig = weapon and WeaponConfig.GetSlot(weapon, slot)
	if not weapon or not module or not slotConfig or not module[slot] then
		return
	end

	local t = now()
	if t < (state.NextReady[slot] or 0) - LATENCY_TOLERANCE then
		reject(player, slot, "Cooldown")
		return
	end

	-- Sanitise aim: unit direction, aim point clamped to a sane distance.
	direction = direction.Unit
	local fromRoot = point - root.Position
	if fromRoot.Magnitude > CombatConfig.MaxAimDistance then
		point = root.Position + fromRoot.Unit * CombatConfig.MaxAimDistance
	end
	local flat = CombatService.FlatUnit(direction, root.CFrame.LookVector)

	local combo = 1
	if slot == "Basic" then
		if os.clock() - state.LastBasic <= WeaponConfig.ComboResetTime then
			combo = state.Combo % 3 + 1
		end
		state.Combo = combo
		state.LastBasic = os.clock()
	end

	local ctx = {
		Player = player,
		Character = character,
		Root = root,
		Humanoid = humanoid,
		Attacker = { Player = player, Character = character },
		Weapon = weapon,
		Config = slotConfig,
		Aim = direction,
		AimFlat = flat,
		AimPoint = point,
		Combo = combo,
	}

	local cooldown = slotConfig.Cooldown
	if slot == "Basic" and module.AttackSpeed then
		cooldown /= module.AttackSpeed(ctx)
	end
	state.NextReady[slot] = t + cooldown
	Remotes.WeaponState:FireClient(player, "Cooldown", slot, t + cooldown)

	task.spawn(function()
		local ok, err = pcall(module[slot], ctx)
		if not ok then
			warn(`[WeaponService] {weaponId}.{slot} failed: {err}`)
		end
	end)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function WeaponService.Init()
	Remotes.WeaponAction.OnServerEvent:Connect(onAction)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	-- A different gem means a different weapon: put the old one away.
	GemDataManager.GemChanged:Connect(function(player)
		WeaponService.Dismiss(player)
	end)
end

return WeaponService
