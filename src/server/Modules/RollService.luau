-- RollService
-- Handles RequestRoll / RequestEquip. Rolls are free and unlimited with a
-- short cooldown. The server picks the gem (with hidden pity), stores it, and
-- tells the client which gem it got so the client can play the reveal.
-- Very rare pulls are announced to the whole server and saved immediately.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local RollConfig = require(script.Parent:WaitForChild("RollConfig"))
local RollEngine = require(script.Parent:WaitForChild("RollEngine"))

local RollService = {}

local rng = Random.new()
local function nextUInt32(): number
	return rng:NextInteger(0, 4294967295)
end

local rollCooldown = Remotes.CreateCooldown(RollConfig.Cooldown)
local equipCooldown = Remotes.CreateCooldown(0.25)

-- Rolls once for a player. Returns the gem and its new stack count.
function RollService.Roll(player: Player): (GemCatalog.Gem?, number?)
	local pity = PlayerData.GetPity(player)
	if not pity then
		return nil, nil
	end

	local result, newPity = RollEngine.Roll(GemCatalog.List, pity, RollConfig, RollEngine.Uniform64(nextUInt32))
	local gem = result :: GemCatalog.Gem
	PlayerData.SetPity(player, newPity)
	PlayerData.IncrementStat(player, "Rolls")
	local count = PlayerData.AddGem(player, gem.Id)

	-- First gem ever: wear it straight away.
	if PlayerData.GetEquipped(player) == nil then
		PlayerData.Equip(player, gem.Id)
	end

	if gem.Odds >= RollConfig.AnnounceBannerOdds then
		Remotes.Announce:FireAllClients("Banner", player.DisplayName, gem.Id)
	elseif gem.Odds >= RollConfig.AnnounceServerOdds then
		Remotes.Announce:FireAllClients("Server", player.DisplayName, gem.Id)
	end
	if gem.Odds >= RollConfig.SaveImmediatelyOdds then
		task.spawn(PlayerData.SaveNow, player)
	end

	return gem, count
end

function RollService.Init()
	Remotes.RequestRoll.OnServerInvoke = function(player: Player)
		if not PlayerData.IsLoaded(player) then
			return false, "NotLoaded"
		end
		local wait = rollCooldown(player)
		if wait > 0 then
			return false, "Cooldown", wait
		end
		local gem, count = RollService.Roll(player)
		if not gem then
			return false, "NotLoaded"
		end
		return true, gem.Id, count
	end

	Remotes.RequestEquip.OnServerInvoke = function(player: Player, gemId: unknown)
		if type(gemId) ~= "string" or #gemId > 64 then
			return false, "Invalid"
		end
		if equipCooldown(player) > 0 then
			return false, "Cooldown"
		end
		-- No swapping kits mid-fight.
		local lastCombat = player:GetAttribute(CombatConfig.PlayerAttributes.LastCombat)
		if type(lastCombat) == "number" and Workspace:GetServerTimeNow() - lastCombat < CombatConfig.InCombatTime then
			return false, "InCombat"
		end
		return PlayerData.Equip(player, gemId)
	end
end

return RollService
