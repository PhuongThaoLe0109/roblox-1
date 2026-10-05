-- Main (client entry point)
-- Starts the world effects, movement, auras and combat, and builds the whole
-- UI in one ScreenGui that survives respawns; a UIScale keeps it readable from
-- phones to 4K monitors.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Auras = require(script.Parent:WaitForChild("Aura"):WaitForChild("Auras"))
local ClientData = require(script.Parent:WaitForChild("ClientData"))
local MapFX = require(script.Parent:WaitForChild("MapFX"))
local MovementController = require(script.Parent:WaitForChild("Movement"):WaitForChild("MovementController"))
local CombatFolder = script.Parent:WaitForChild("Combat")
local BeastFX = require(CombatFolder:WaitForChild("BeastFX"))
local CombatAnim = require(CombatFolder:WaitForChild("CombatAnim"))
local CombatFX = require(CombatFolder:WaitForChild("CombatFX"))
local CombatController = require(CombatFolder:WaitForChild("CombatController"))
local Overheads = require(CombatFolder:WaitForChild("Overheads"))
local UI = script.Parent:WaitForChild("UI")
local RollReveal = require(UI:WaitForChild("RollReveal"))
local Announcements = require(UI:WaitForChild("Announcements"))
local Inventory = require(UI:WaitForChild("Inventory"))
local LobbyHud = require(UI:WaitForChild("LobbyHud"))
local MovementHud = require(UI:WaitForChild("MovementHud"))
local CombatHud = require(UI:WaitForChild("CombatHud"))
local SkillGuide = require(UI:WaitForChild("SkillGuide"))

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
	PreviewAura = Auras.SetPreview, -- try a gem's aura on before equipping it
	ToggleSkillGuide = function(_open: boolean?) end,
	InLobby = function(): boolean
		return true -- the whole world is open: menus work everywhere
	end,
}

MapFX.Start()
MovementController.Start()
ClientData.Start()
Auras.Start()
CombatController.Start()
BeastFX.Start(CombatFX)
CombatAnim.Start()
Overheads.Start()
RollReveal.Init(screen)

for _, entry in {
	{ "Announcements", Announcements },
	{ "Inventory", Inventory },
	{ "LobbyHud", LobbyHud },
	{ "MovementHud", MovementHud },
	{ "CombatHud", CombatHud },
	{ "SkillGuide", SkillGuide },
} do
	local ok, err = pcall(entry[2].Init, screen, context)
	if not ok then
		warn(`[UI] {entry[1]} failed to initialise: {err}`)
	end
end
