-- Remotes
-- Creates ReplicatedStorage.Remotes. Every client request is validated on the
-- server; clients never send results, only intentions.
--
--   RequestRoll    RemoteFunction  client -> server  () -> (ok, gemId | reason, count | retryIn)
--   RequestEquip   RemoteFunction  client -> server  (gemId) -> (ok, reason?)
--   GetProfile     RemoteFunction  client -> server  () -> { Inventory, Equipped, Rolls }?
--   InventorySync  RemoteEvent     server -> client  ("Full", snapshot) | ("Gem", id, count) | ("Equipped", id)
--   Announce       RemoteEvent     server -> all     (kind, playerName, gemId)  kind = "Server" | "Banner"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local function create(className: string, name: string): any
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

Remotes.RequestRoll = create("RemoteFunction", "RequestRoll") :: RemoteFunction
Remotes.RequestEquip = create("RemoteFunction", "RequestEquip") :: RemoteFunction
Remotes.GetProfile = create("RemoteFunction", "GetProfile") :: RemoteFunction
Remotes.InventorySync = create("RemoteEvent", "InventorySync") :: RemoteEvent
Remotes.Announce = create("RemoteEvent", "Announce") :: RemoteEvent

folder.Parent = ReplicatedStorage

-- Returns a function(player) -> secondsLeft: 0 when the player may act now
-- (and the cooldown restarts), otherwise how long they still have to wait.
function Remotes.CreateCooldown(seconds: number): (Player) -> number
	local last: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
	return function(player: Player): number
		local now = os.clock()
		local previous = last[player]
		if previous and now - previous < seconds then
			return seconds - (now - previous)
		end
		last[player] = now
		return 0
	end
end

return Remotes
