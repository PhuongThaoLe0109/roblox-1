-- Main (server entry point)
-- Order matters: every listener is connected before PlayerData starts
-- loading profiles.

local Modules = script.Parent:WaitForChild("Modules")
local PlayerData = require(Modules:WaitForChild("PlayerData"))
local RollService = require(Modules:WaitForChild("RollService"))
local Remotes = require(Modules:WaitForChild("Remotes"))

RollService.Init()

-- Placeholder until the arena/combat system lands: the Play button works but
-- the arena isn't open yet.
Remotes.RequestPlay.OnServerInvoke = function()
	return false, "ArenaClosed"
end

PlayerData.Init()
