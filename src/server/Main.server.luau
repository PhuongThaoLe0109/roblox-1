-- Main (server entry point)
-- Order matters: every listener is connected before PlayerData starts
-- loading profiles.

local Modules = script.Parent:WaitForChild("Modules")
local PlayerData = require(Modules:WaitForChild("PlayerData"))
local RollService = require(Modules:WaitForChild("RollService"))

RollService.Init()
PlayerData.Init()
