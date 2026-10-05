-- FactionTeams
-- Maps factions onto Roblox Teams (player list colours, team spawns) and owns
-- character spawning: characters only load once gem data is ready, and
-- respawn at the faction home (Rogues at the hub).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local GemDataManager = require(script.Parent:WaitForChild("GemDataManager"))

local FactionTeams = {}

local teams: { [string]: Team } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}
local initialized = false

local function getOrCreateTeam(factionId: string): Team
	local faction = GemConfig.Factions[factionId]
	local team = Teams:FindFirstChild(faction.DisplayName)
	if not (team and team:IsA("Team")) then
		team = Instance.new("Team")
		team.Name = faction.DisplayName
		team.Parent = Teams
	end
	team.TeamColor = faction.TeamColor
	team.AutoAssignable = false
	team:SetAttribute("Faction", factionId)
	return team :: Team
end

local function spawnCharacter(player: Player)
	if player.Parent ~= Players then
		return
	end
	local ok, err = pcall(player.LoadCharacter, player)
	if not ok then
		warn(`[FactionTeams] LoadCharacter failed for {player.Name}: {err}`)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	-- Connection dies with the character, so no manual cleanup needed.
	humanoid.Died:Connect(function()
		task.delay(Players.RespawnTime, function()
			if player.Character == character and GemDataManager.IsLoaded(player) then
				spawnCharacter(player)
			end
		end)
	end)
end

local function assignTeam(player: Player, factionId: string)
	player.Team = teams[factionId] or teams[GemConfig.DefaultFaction]
	player.Neutral = false
end

function FactionTeams.GetTeam(factionId: string): Team?
	return teams[factionId]
end

-- Respawn a player immediately (e.g. after switching faction).
function FactionTeams.Respawn(player: Player)
	task.spawn(spawnCharacter, player)
end

function FactionTeams.Init()
	if initialized then
		return
	end
	initialized = true

	for factionId in GemConfig.Factions do
		teams[factionId] = getOrCreateTeam(factionId)
	end

	-- We decide when characters load (after data), so the gem and stats are
	-- applied to the very first character.
	Players.CharacterAutoLoads = false

	local function track(player: Player)
		if characterConnections[player] then
			return
		end
		characterConnections[player] = player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local connection = characterConnections[player]
		if connection then
			connection:Disconnect()
			characterConnections[player] = nil
		end
	end)

	GemDataManager.ProfileLoaded:Connect(function(player, data)
		assignTeam(player, data.Faction)
		spawnCharacter(player)
	end)

	GemDataManager.FactionChanged:Connect(function(player, newFaction)
		assignTeam(player, newFaction)
		spawnCharacter(player) -- respawn at the new home base
	end)
end

return FactionTeams
