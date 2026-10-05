-- GemDataBootstrap
-- Starts GemDataManager and exposes the few client-initiated actions
-- (choosing a faction, moving your gem) through validated, rate-limited remotes.
-- All reads happen client-side via Player attributes; see GemConfig.Attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemDataManager = require(script.Parent:WaitForChild("Modules"):WaitForChild("GemDataManager"))

local REQUEST_COOLDOWN = 1 -- seconds between client requests per player

local remotes = Instance.new("Folder")
remotes.Name = "GemRemotes"

local requestFaction = Instance.new("RemoteFunction")
requestFaction.Name = "RequestFactionChange"
requestFaction.Parent = remotes

local requestPlacement = Instance.new("RemoteFunction")
requestPlacement.Name = "RequestGemPlacement"
requestPlacement.Parent = remotes

remotes.Parent = ReplicatedStorage

local lastRequest: { [Player]: number } = {}

local function throttled(player: Player): boolean
	local now = os.clock()
	local last = lastRequest[player]
	if last and now - last < REQUEST_COOLDOWN then
		return true
	end
	lastRequest[player] = now
	return false
end

Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
end)

requestFaction.OnServerInvoke = function(player: Player, factionId: unknown)
	if throttled(player) then
		return false, "RateLimited"
	end
	if type(factionId) ~= "string" then
		return false, "InvalidFaction"
	end
	-- Remaining cooldown is returned so the UI can show a timer.
	local ok, err = GemDataManager.SetFaction(player, factionId)
	return ok, err, GemDataManager.GetFactionCooldownRemaining(player)
end

requestPlacement.OnServerInvoke = function(player: Player, placement: unknown)
	if throttled(player) then
		return false, "RateLimited"
	end
	if type(placement) ~= "string" then
		return false, "InvalidPlacement"
	end
	return GemDataManager.SetGemPlacement(player, placement)
end

GemDataManager.Init()
