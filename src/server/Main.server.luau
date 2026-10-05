-- Main (server entry point)
-- Wires every server system together. Order matters: all listeners must be
-- connected before GemDataManager.Init() starts loading profiles.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Modules = script.Parent:WaitForChild("Modules")
local GemDataManager = require(Modules:WaitForChild("GemDataManager"))
local Remotes = require(Modules:WaitForChild("Remotes"))
local FactionTeams = require(Modules:WaitForChild("FactionTeams"))
local PortalService = require(Modules:WaitForChild("PortalService"))
local TerritoryService = require(Modules:WaitForChild("TerritoryService"))

-- The map is normally baked in Edit mode (see ServerStorage.MapBuilder).
-- Only build it here as a fallback when the place has no Workspace.Map.
local map = Workspace:FindFirstChild("Map")
if not map then
	warn("[Main] Workspace.Map not found; generating it now. Bake it in Edit mode to skip this step.")
	map = require(ServerStorage:WaitForChild("MapBuilder")).Build()
end

--------------------------------------------------------------------------------
-- Client requests
--------------------------------------------------------------------------------

local throttled = Remotes.CreateThrottle(1)

Remotes.RequestFactionChange.OnServerInvoke = function(player: Player, factionId: unknown)
	if throttled(player) then
		return false, "RateLimited", 0
	end
	if type(factionId) ~= "string" then
		return false, "InvalidFaction", 0
	end
	local ok, err = GemDataManager.SetFaction(player, factionId)
	-- Remaining cooldown is returned so the UI can show a timer.
	return ok, err, GemDataManager.GetFactionCooldownRemaining(player)
end

Remotes.RequestGemPlacement.OnServerInvoke = function(player: Player, placement: unknown)
	if throttled(player) then
		return false, "RateLimited"
	end
	if type(placement) ~= "string" then
		return false, "InvalidPlacement"
	end
	return GemDataManager.SetGemPlacement(player, placement)
end

--------------------------------------------------------------------------------
-- Systems
--------------------------------------------------------------------------------

FactionTeams.Init()
PortalService.Init(map)
TerritoryService.Init(map)
GemDataManager.Init()
