-- Remotes
-- Creates ReplicatedStorage.GemRemotes and offers small helpers for
-- server -> client notifications and per-player request throttling.
--
--   RequestFactionChange (RemoteFunction)  client -> server
--   RequestGemPlacement  (RemoteFunction)  client -> server
--   RequestFastTravel    (RemoteFunction)  client -> server
--   Notify               (RemoteEvent)     server -> client (text, kind)
--   WeaponAction         (RemoteEvent)     client -> server (action, aimDir, aimPoint)
--   WeaponState          (RemoteEvent)     server -> client (event, slot, value)
--   WeaponFX             (RemoteEvent)     server -> clients (kind, params)
--
-- Notify kinds the client understands: "Info", "Success", "Warning",
-- "Capture", "RankUp", "Travel".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "GemRemotes"

local function remoteFunction(name: string): RemoteFunction
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function remoteEvent(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

Remotes.RequestFactionChange = remoteFunction("RequestFactionChange")
Remotes.RequestGemPlacement = remoteFunction("RequestGemPlacement")
Remotes.RequestFastTravel = remoteFunction("RequestFastTravel")
Remotes.Notify = remoteEvent("Notify")
Remotes.WeaponAction = remoteEvent("WeaponAction")
Remotes.WeaponState = remoteEvent("WeaponState")
Remotes.WeaponFX = remoteEvent("WeaponFX")

folder.Parent = ReplicatedStorage

function Remotes.NotifyPlayer(player: Player, text: string, kind: string?)
	if player.Parent == Players then
		Remotes.Notify:FireClient(player, text, kind or "Info")
	end
end

function Remotes.NotifyAll(text: string, kind: string?)
	Remotes.Notify:FireAllClients(text, kind or "Info")
end

-- Returns a function(player) -> boolean that is true when the player must wait.
function Remotes.CreateThrottle(cooldown: number): (Player) -> boolean
	local last: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
	end)
	return function(player: Player): boolean
		local now = os.clock()
		local previous = last[player]
		if previous and now - previous < cooldown then
			return true
		end
		last[player] = now
		return false
	end
end

return Remotes
