-- Main (client entry point)
-- Starts world visuals (sky, ambient motion), movement, and builds the HUD.
-- All UI lives in one ScreenGui that survives respawns; a UIScale keeps it
-- readable from phones to 4K monitors.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SkyCycle = require(script.Parent:WaitForChild("SkyCycle"))
local AmbientFX = require(script.Parent:WaitForChild("AmbientFX"))
local Movement = require(script.Parent:WaitForChild("Movement"))
local VFX = require(script.Parent:WaitForChild("VFX"))
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))

local UI = script.Parent:WaitForChild("UI")
local LoadingScreen = require(UI:WaitForChild("LoadingScreen"))
local Hud = require(UI:WaitForChild("Hud"))
local TerritoryBar = require(UI:WaitForChild("TerritoryBar"))
local MapPanel = require(UI:WaitForChild("MapPanel"))
local FactionSelect = require(UI:WaitForChild("FactionSelect"))
local Toasts = require(UI:WaitForChild("Toasts"))
local PortalLabels = require(UI:WaitForChild("PortalLabels"))
local SkillBar = require(UI:WaitForChild("SkillBar"))
local PuffOverlay = require(UI:WaitForChild("PuffOverlay"))

local screen = Instance.new("ScreenGui")
screen.Name = "GemHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = screen

local function rescale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), 0.6, 1.25)
end
rescale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

-- Shared hooks between UI modules (filled in by the modules that own them).
local context = {
	SkyCycle = SkyCycle,
	WeaponController = WeaponController,
	ToggleMap = function(_open: boolean?) end,
	OpenFactionSelect = function() end,
	Toast = function(_text: string, _kind: string?) end,
}

LoadingScreen.Init(screen)
SkyCycle.Start()
AmbientFX.Start()
Movement.Start()
VFX.Start()
WeaponController.Start()

-- Each module is isolated so one failure doesn't take down the whole HUD.
for name, module in {
	Toasts = Toasts,
	Hud = Hud,
	TerritoryBar = TerritoryBar,
	MapPanel = MapPanel,
	FactionSelect = FactionSelect,
	PortalLabels = PortalLabels,
	SkillBar = SkillBar,
	PuffOverlay = PuffOverlay,
} do
	task.spawn(function()
		local ok, err = pcall(module.Init, screen, context)
		if not ok then
			warn(`[UI] {name} failed to initialise: {err}`)
		end
	end)
end
