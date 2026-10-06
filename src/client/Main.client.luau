-- Main (client entry point)
-- Starts the world effects, movement, auras and combat, and builds the whole
-- UI in one ScreenGui that survives respawns; a UIScale keeps it readable from
-- phones to 4K monitors.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Every module is loaded and started on its own: if one of them fails, the
-- error names it in the Output and the rest of the game (and the UI) still
-- comes up instead of the whole client stopping.
local function load(...: string): any
	local path = { ... }
	local ok, result = pcall(function()
		local node: Instance = script.Parent
		for _, name in path do
			node = node:WaitForChild(name, 15) :: Instance
			assert(node, `missing {name}`)
		end
		return require(node :: ModuleScript)
	end)
	if not ok then
		warn(`[Main] could not load {table.concat(path, ".")}: {result}`)
		return nil
	end
	return result
end

local function safe(label: string, fn: any, ...)
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(`[Main] {label} failed: {err}`)
	end
end

local Toon = load("Toon")
local Auras = load("Aura", "Auras")
local ClientData = load("ClientData")
local MapFX = load("MapFX")
local MovementController = load("Movement", "MovementController")
local BeastFX = load("Combat", "BeastFX")
local CombatAnim = load("Combat", "CombatAnim")
local CombatFX = load("Combat", "CombatFX")
local CombatController = load("Combat", "CombatController")
local Overheads = load("Combat", "Overheads")
local RollReveal = load("UI", "RollReveal")
local Announcements = load("UI", "Announcements")
local Inventory = load("UI", "Inventory")
local LobbyHud = load("UI", "LobbyHud")
local MovementHud = load("UI", "MovementHud")
local CombatHud = load("UI", "CombatHud")
local SkillGuide = load("UI", "SkillGuide")

local screen = Instance.new("ScreenGui")
screen.Name = "PrismUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = screen
local function rescale()
	local camera = Workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min(size.X / 1366, size.Y / 768), 0.55, 1.3)
	end
end
rescale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

-- Hooks shared between UI modules (filled in by their owners).
local context = {
	Toast = function(_text: string, _kind: string?) end,
	ToggleInventory = function(_open: boolean?) end,
	SetLobbyVisible = function(_visible: boolean) end,
	PreviewAura = if Auras then Auras.SetPreview else function(_gemId: string?) end, -- try a gem's aura on before equipping it
	ToggleSkillGuide = function(_open: boolean?) end,
	InLobby = function(): boolean
		return true -- the whole world is open: menus work everywhere
	end,
}

safe("Toon.Start", Toon and Toon.Start)
safe("MapFX.Start", MapFX and MapFX.Start)
safe("MovementController.Start", MovementController and MovementController.Start)
safe("ClientData.Start", ClientData and ClientData.Start)
safe("Auras.Start", Auras and Auras.Start)
safe("CombatController.Start", CombatController and CombatController.Start)
safe("BeastFX.Start", BeastFX and BeastFX.Start, CombatFX)
safe("CombatAnim.Start", CombatAnim and CombatAnim.Start)
safe("Overheads.Start", Overheads and Overheads.Start)
safe("RollReveal.Init", RollReveal and RollReveal.Init, screen)

for _, entry in {
	{ "Announcements", Announcements },
	{ "Inventory", Inventory },
	{ "LobbyHud", LobbyHud },
	{ "MovementHud", MovementHud },
	{ "CombatHud", CombatHud },
	{ "SkillGuide", SkillGuide },
} do
	if entry[2] then
		local ok, err = pcall(entry[2].Init, screen, context)
		if not ok then
			warn(`[UI] {entry[1]} failed to initialise: {err}`)
		end
	end
end
