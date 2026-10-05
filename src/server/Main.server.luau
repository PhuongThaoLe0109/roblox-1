-- Main (server entry point)
-- Order matters: every listener is connected before PlayerData starts
-- loading profiles.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- The world is normally baked in Edit mode (ServerStorage.MapBuilder). Only
-- build it here as a fallback when the place has no Workspace.Map at all.
if not Workspace:FindFirstChild("Map") then
	warn("[Main] Workspace.Map not found; building it now. Bake it in Edit mode to skip this.")
	require(ServerStorage:WaitForChild("MapBuilder")).Build()
end

local Modules = script.Parent:WaitForChild("Modules")
local PlayerData = require(Modules:WaitForChild("PlayerData"))
local RollService = require(Modules:WaitForChild("RollService"))
local Remotes = require(Modules:WaitForChild("Remotes"))
local MovementService = require(Modules:WaitForChild("MovementService"))

RollService.Init()
MovementService.Init()

-- Placeholder until the arena/combat system lands: the Play button works but
-- the arena isn't open yet.
Remotes.RequestPlay.OnServerInvoke = function()
	return false, "ArenaClosed"
end

PlayerData.Init()
