-- GemDataManager
-- Server-authoritative owner of every player's gem identity, faction and
-- progression. Responsibilities:
--   * Load/save player data through DataStoreService with session locking,
--     retries with exponential backoff, schema migration and default reconciliation.
--   * Replicate state through Player/Character attributes (no remotes needed for reads).
--   * Physically attach the gemstone to the character at its body placement and
--     tag it with CollectionService so combat/puff systems can find it.
--   * Expose a small mutation API + Signals for other server systems.
--
-- Usage (server only):
--   local GemDataManager = require(ServerScriptService.Server.Modules.GemDataManager)
--   GemDataManager.Init()
--   GemDataManager.AddEssence(player, 50, "TerritoryCapture")

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "GemDataManager can only be required on the server")

local GemConfig = require(ReplicatedStorage:WaitForChild("GemConfig"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))

local DS = GemConfig.DataStore
local ATTR = GemConfig.Attributes

local GemDataManager = {}

--------------------------------------------------------------------------------
-- Public signals
--------------------------------------------------------------------------------

GemDataManager.ProfileLoaded = Signal.new() -- (player, dataSnapshot)
GemDataManager.ProfileReleased = Signal.new() -- (player)
GemDataManager.GemChanged = Signal.new() -- (player, gemType, placement)
GemDataManager.FactionChanged = Signal.new() -- (player, newFaction, oldFaction)
GemDataManager.EssenceChanged = Signal.new() -- (player, newTotal, delta, reason)
GemDataManager.RankChanged = Signal.new() -- (player, newRankIndex, oldRankIndex)

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type PlayerData = {
	SchemaVersion: number,
	GemType: string,
	GemPlacement: string,
	Faction: string,
	LastFactionChange: number,
	CrystalEssence: number,
	LifetimeEssence: number,
	Rank: number,
	Stats: {
		TimesPuffed: number,
		PuffsInflicted: number,
		GemsSealed: number,
		TerritoriesCaptured: number,
		Fusions: number,
	},
	FirstJoin: number,
	LastJoin: number,
}

type Profile = {
	Player: Player,
	UserId: number,
	Key: string,
	Data: PlayerData,
	CanSave: boolean, -- false for mock/offline sessions or a lost lock
	Released: boolean,
	Connections: { RBXScriptConnection },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local profiles: { [Player]: Profile } = {}
local loadingPlayers: { [Player]: boolean } = {}
local pendingReleases = 0
local initialized = false
local shuttingDown = false

-- Unique per server instance; game.JobId is "" in Studio, so we can't rely on it alone.
local SESSION_ID = (game.JobId ~= "" and game.JobId or "Studio") .. "_" .. HttpService:GenerateGUID(false)

local dataStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DS.Name, DS.Scope)
	end)
	if ok then
		dataStore = result
	else
		warn(`[GemDataManager] DataStores unavailable ({result}). Running in non-persistent mode.`)
	end
end

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in (value :: any) do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy :: any
end

local function keyFor(userId: number): string
	return DS.KeyPrefix .. tostring(userId)
end

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) <= 0 and waited < 10 do
		waited += task.wait(0.5)
	end
end

local function pickStarterGem(userId: number): string
	local starters = GemConfig.GetStarterGemTypes()
	-- Seed by UserId so a failed first save doesn't re-roll a different gem next join.
	local rng = Random.new(userId)
	return starters[rng:NextInteger(1, #starters)]
end

local function createDefaultData(userId: number): PlayerData
	local gemType = pickStarterGem(userId)
	local now = os.time()
	return {
		SchemaVersion = DS.SchemaVersion,
		GemType = gemType,
		GemPlacement = GemConfig.GemTypes[gemType].DefaultPlacement,
		Faction = GemConfig.DefaultFaction,
		LastFactionChange = 0,
		CrystalEssence = 0,
		LifetimeEssence = 0,
		Rank = 1,
		Stats = {
			TimesPuffed = 0,
			PuffsInflicted = 0,
			GemsSealed = 0,
			TerritoriesCaptured = 0,
			Fusions = 0,
		},
		FirstJoin = now,
		LastJoin = now,
	}
end

-- Ordered migration steps: MIGRATIONS[n] upgrades data from version n to n + 1.
local MIGRATIONS: { [number]: (any) -> any } = {
	-- [1] = function(data) data.NewField = 0; return data end,
}

local function migrate(data: any): any
	local version = data.SchemaVersion or 1
	while version < DS.SchemaVersion do
		local step = MIGRATIONS[version]
		if step then
			data = step(data)
		end
		version += 1
		data.SchemaVersion = version
	end
	return data
end

-- Fill any missing keys from defaults and repair invalid values (e.g. a gem type
-- that was removed from GemConfig) without discarding the rest of the save.
local function reconcile(data: any, userId: number): PlayerData
	local defaults = createDefaultData(userId)
	if type(data) ~= "table" then
		return defaults
	end

	local function fill(target: any, template: any)
		for key, defaultValue in template do
			if target[key] == nil or type(target[key]) ~= type(defaultValue) then
				target[key] = deepCopy(defaultValue)
			elseif type(defaultValue) == "table" then
				fill(target[key], defaultValue)
			end
		end
	end
	fill(data, defaults)

	if not GemConfig.IsValidGemType(data.GemType) then
		data.GemType = defaults.GemType
	end
	if not GemConfig.IsPlacementAllowed(data.GemType, data.GemPlacement) then
		data.GemPlacement = GemConfig.GemTypes[data.GemType].DefaultPlacement
	end
	if not GemConfig.IsValidFaction(data.Faction) then
		data.Faction = GemConfig.DefaultFaction
	end
	data.CrystalEssence = math.max(0, math.floor(data.CrystalEssence))
	data.LifetimeEssence = math.max(data.LifetimeEssence, data.CrystalEssence)
	data.Rank = GemConfig.GetRankForEssence(data.LifetimeEssence)

	return data :: PlayerData
end

local function isLockHeldByOther(session: any): boolean
	return type(session) == "table"
		and session.Id ~= SESSION_ID
		and type(session.Timestamp) == "number"
		and os.time() - session.Timestamp < DS.SessionLockTimeout
end

--------------------------------------------------------------------------------
-- DataStore I/O
--------------------------------------------------------------------------------

type LoadResult = "Loaded" | "Locked" | "Failed"

local function loadAsync(userId: number): (LoadResult, PlayerData?)
	if not dataStore then
		return "Failed", nil
	end

	local key = keyFor(userId)
	local lockWaits = 0
	local attempt = 0

	while attempt < DS.MaxRequestRetries do
		attempt += 1
		local lockedByOther = false

		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, result = pcall(function()
			return (dataStore :: DataStore):UpdateAsync(key, function(stored)
				stored = if type(stored) == "table" then stored else {}

				if isLockHeldByOther(stored.Session) then
					lockedByOther = true
					return nil -- cancel the write; don't touch another server's session
				end

				stored.Data = reconcile(migrate(stored.Data or {}), userId)
				stored.Data.LastJoin = os.time()
				stored.Session = { Id = SESSION_ID, PlaceId = game.PlaceId, Timestamp = os.time() }
				return stored
			end)
		end)

		if ok and not lockedByOther and type(result) == "table" then
			return "Loaded", result.Data
		elseif ok and lockedByOther then
			lockWaits += 1
			if lockWaits >= DS.LockRetryAttempts then
				return "Locked", nil
			end
			attempt -= 1 -- lock waits have their own budget
			task.wait(DS.LockRetryDelay)
		else
			warn(`[GemDataManager] Load attempt {attempt} failed for {key}: {result}`)
			-- 403 = "Enable Studio Access to API Services" is off; retrying won't help.
			if string.find(tostring(result), "403", 1, true) then
				return "Failed", nil
			end
			task.wait(2 ^ attempt)
		end
	end

	return "Failed", nil
end

-- Returns false if another server has taken over this player's session.
local function saveAsync(profile: Profile, releaseLock: boolean): boolean
	if not dataStore or not profile.CanSave then
		return true
	end

	local snapshot = deepCopy(profile.Data)
	local lockLost = false

	for attempt = 1, DS.MaxRequestRetries do
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, err = pcall(function()
			(dataStore :: DataStore):UpdateAsync(profile.Key, function(stored)
				stored = if type(stored) == "table" then stored else {}

				if type(stored.Session) == "table" and stored.Session.Id ~= SESSION_ID then
					lockLost = true
					return nil
				end

				stored.Data = snapshot
				stored.Session = if releaseLock
					then nil
					else { Id = SESSION_ID, PlaceId = game.PlaceId, Timestamp = os.time() }
				return stored
			end)
		end)

		if ok then
			if lockLost then
				warn(`[GemDataManager] Session lock lost for {profile.Key}; data from this server was NOT saved.`)
				return false
			end
			return true
		end

		warn(`[GemDataManager] Save attempt {attempt} failed for {profile.Key}: {err}`)
		if attempt < DS.MaxRequestRetries then
			task.wait(if shuttingDown then 1 else 2 ^ attempt)
		end
	end

	return true -- transient failure; lock still ours, autosave will retry
end

--------------------------------------------------------------------------------
-- Character / gemstone presentation
--------------------------------------------------------------------------------

local function findGemstone(character: Model): BasePart?
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and CollectionService:HasTag(child, GemConfig.Tags.Gemstone) then
			return child
		end
	end
	return nil
end

local function buildGemstone(gemType: string): BasePart
	local info = GemConfig.GemTypes[gemType]

	-- Prefer an artist-made model at ReplicatedStorage.Assets.Gemstones.<GemType>.
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Gemstones")
	local template = folder and folder:FindFirstChild(gemType)

	local gem: BasePart
	if template and template:IsA("BasePart") then
		gem = template:Clone()
	else
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.45, 0.45, 0.2)
		part.Shape = if info.Shape == "Round" then Enum.PartType.Ball else Enum.PartType.Block
		if info.Shape == "Round" then
			part.Size = Vector3.new(0.4, 0.4, 0.4)
		end
		part.Color = info.Color
		part.Material = info.Material
		part.Reflectance = 0.15
		part.Transparency = 0.05

		local light = Instance.new("PointLight")
		light.Color = info.Color
		light.Range = 4
		light.Brightness = 0.6
		light.Parent = part

		gem = part
	end

	gem.Name = GemConfig.GemstoneName
	gem.Anchored = false
	gem.CanCollide = false
	gem.CanTouch = false
	gem.CanQuery = true -- lets combat raycasts register precise gem hits
	gem.Massless = true
	return gem
end

local function resolveBodyPart(character: Model, placementName: string): BasePart?
	local placement = GemConfig.Placements[placementName]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local partName = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6
		then placement.R6Fallback
		else placement.BodyPart

	local part = character:WaitForChild(partName, 5)
	return if part and part:IsA("BasePart") then part else nil
end

local function applyGemToCharacter(profile: Profile, character: Model)
	if profile.Released or character.Parent == nil then
		return
	end

	local data = profile.Data
	local userId = profile.UserId

	local existing = findGemstone(character)
	if existing then
		existing:Destroy()
	end

	local bodyPart = resolveBodyPart(character, data.GemPlacement)
	if not bodyPart or profile.Released or character.Parent == nil then
		warn(`[GemDataManager] Could not attach gem for {profile.Player.Name}: body part missing`)
		return
	end

	local gem = buildGemstone(data.GemType)
	gem.CFrame = bodyPart.CFrame * GemConfig.Placements[data.GemPlacement].Offset

	local weld = Instance.new("Weld")
	weld.Name = "GemWeld"
	weld.Part0 = bodyPart
	weld.Part1 = gem
	weld.C0 = GemConfig.Placements[data.GemPlacement].Offset
	weld.Parent = gem

	gem:SetAttribute(ATTR.OwnerUserId, userId)
	gem:SetAttribute(ATTR.GemType, data.GemType)
	gem:SetAttribute(ATTR.Faction, data.Faction)
	CollectionService:AddTag(gem, GemConfig.Tags.Gemstone)
	gem.Parent = character

	character:SetAttribute(ATTR.OwnerUserId, userId)
	character:SetAttribute(ATTR.GemType, data.GemType)
	character:SetAttribute(ATTR.Faction, data.Faction)
	character:SetAttribute(ATTR.WeaponId, GemConfig.GemTypes[data.GemType].WeaponId)
	CollectionService:AddTag(character, GemConfig.Tags.GemCharacter)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local stats = GemConfig.GemTypes[data.GemType].BaseStats
		humanoid.MaxHealth = stats.MaxHealth
		humanoid.Health = stats.MaxHealth
		humanoid.WalkSpeed = stats.WalkSpeed
	end
end

--------------------------------------------------------------------------------
-- Replication
--------------------------------------------------------------------------------

local function replicate(profile: Profile)
	local player = profile.Player
	local data = profile.Data
	local rankInfo = GemConfig.Ranks[data.Rank]

	player:SetAttribute(ATTR.GemType, data.GemType)
	player:SetAttribute(ATTR.GemPlacement, data.GemPlacement)
	player:SetAttribute(ATTR.Faction, data.Faction)
	player:SetAttribute(ATTR.Rank, data.Rank)
	player:SetAttribute(ATTR.RankName, rankInfo and rankInfo.Name or "?")
	player:SetAttribute(ATTR.CrystalEssence, data.CrystalEssence)
	player:SetAttribute(ATTR.LifetimeEssence, data.LifetimeEssence)
	player:SetAttribute(ATTR.WeaponId, GemConfig.GemTypes[data.GemType].WeaponId)

	local character = player.Character
	if character then
		character:SetAttribute(ATTR.Faction, data.Faction)
		character:SetAttribute(ATTR.GemType, data.GemType)
		local gem = findGemstone(character)
		if gem then
			gem:SetAttribute(ATTR.Faction, data.Faction)
		end
	end
end

--------------------------------------------------------------------------------
-- Profile lifecycle
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if profiles[player] or loadingPlayers[player] then
		return
	end
	loadingPlayers[player] = true

	local userId = player.UserId
	local status, data = loadAsync(userId)
	loadingPlayers[player] = nil

	local canSave = status == "Loaded"
	if status == "Locked" then
		player:Kick("Your gem is still active in another server. Please rejoin in a moment.")
		return
	elseif status == "Failed" then
		if dataStore and not RunService:IsStudio() then
			-- Never let a player play on default data in production: it would
			-- look like a wipe and progress earned this session would be lost.
			player:Kick("Could not load your gem data. Please rejoin.")
			return
		end
		data = createDefaultData(userId)
		warn(`[GemDataManager] Using temporary (unsaved) data for {player.Name}`)
	end

	local profile: Profile = {
		Player = player,
		UserId = userId,
		Key = keyFor(userId),
		Data = data :: PlayerData,
		CanSave = canSave,
		Released = false,
		Connections = {},
	}

	-- Player left while we were loading: release the lock we just took.
	if player.Parent ~= Players then
		profile.Released = true
		saveAsync(profile, true)
		return
	end

	profiles[player] = profile
	replicate(profile)

	table.insert(
		profile.Connections,
		player.CharacterAdded:Connect(function(character)
			applyGemToCharacter(profile, character)
		end)
	)
	if player.Character then
		task.spawn(applyGemToCharacter, profile, player.Character)
	end

	player:SetAttribute(ATTR.DataLoaded, true)
	GemDataManager.ProfileLoaded:Fire(player, deepCopy(profile.Data))
end

local function releaseProfile(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end

	profile.Released = true
	profiles[player] = nil
	for _, connection in profile.Connections do
		connection:Disconnect()
	end
	table.clear(profile.Connections)

	pendingReleases += 1
	local ok, err = pcall(saveAsync, profile, true)
	pendingReleases -= 1
	if not ok then
		warn(`[GemDataManager] Release failed for {profile.Key}: {err}`)
	end

	GemDataManager.ProfileReleased:Fire(player)
end

local function autoSaveLoop()
	while not shuttingDown do
		task.wait(DS.AutoSaveInterval)
		if shuttingDown then
			break
		end

		-- Snapshot: players may join/leave while this loop yields.
		for player, profile in table.clone(profiles) do
			if profile.Released then
				continue
			end
			task.spawn(function()
				local stillOwned = saveAsync(profile, false)
				if not stillOwned and not profile.Released then
					profile.CanSave = false
					player:Kick("Your gem data was opened in another server.")
				end
			end)
			-- Spread requests out to stay well under DataStore throughput limits.
			task.wait(0.1)
		end
	end
end

local function onServerClose()
	shuttingDown = true

	for player in profiles do
		task.spawn(releaseProfile, player)
	end

	local deadline = os.clock() + DS.ShutdownTimeout
	while (pendingReleases > 0 or next(profiles) ~= nil) and os.clock() < deadline do
		task.wait(0.1)
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function GemDataManager.Init()
	if initialized then
		return
	end
	initialized = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(releaseProfile)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(onServerClose)
	task.spawn(autoSaveLoop)
end

function GemDataManager.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Returns a deep copy; mutate only through the API below.
function GemDataManager.GetData(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then deepCopy(profile.Data) else nil
end

-- Yields until the player's profile is loaded. Returns nil if they leave or time out.
function GemDataManager.WaitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while not profiles[player] do
		if player.Parent ~= Players or os.clock() > deadline then
			return nil
		end
		task.wait(0.1)
	end
	return GemDataManager.GetData(player)
end

function GemDataManager.GetGemInfo(player: Player)
	local profile = profiles[player]
	return if profile then GemConfig.GemTypes[profile.Data.GemType] else nil
end

function GemDataManager.GetFaction(player: Player): string?
	local profile = profiles[player]
	return if profile then profile.Data.Faction else nil
end

function GemDataManager.AreAllies(a: Player, b: Player): boolean
	local fa, fb = GemDataManager.GetFaction(a), GemDataManager.GetFaction(b)
	-- Neutral (Rogue Shards) gems have no allies.
	return fa ~= nil and fa == fb and fa ~= "Neutral"
end

function GemDataManager.GetPlayersInFaction(factionId: string): { Player }
	local result = {}
	for player, profile in profiles do
		if profile.Data.Faction == factionId then
			table.insert(result, player)
		end
	end
	return result
end

function GemDataManager.SetGemType(player: Player, gemType: string, placement: string?): (boolean, string?)
	local profile = profiles[player]
	if not profile then
		return false, "NotLoaded"
	end
	if not GemConfig.IsValidGemType(gemType) then
		return false, "InvalidGemType"
	end

	local newPlacement = placement or GemConfig.GemTypes[gemType].DefaultPlacement
	if not GemConfig.IsPlacementAllowed(gemType, newPlacement) then
		return false, "InvalidPlacement"
	end

	profile.Data.GemType = gemType
	profile.Data.GemPlacement = newPlacement
	replicate(profile)
	if player.Character then
		task.spawn(applyGemToCharacter, profile, player.Character)
	end

	GemDataManager.GemChanged:Fire(player, gemType, newPlacement)
	return true
end

function GemDataManager.SetGemPlacement(player: Player, placement: string): (boolean, string?)
	local profile = profiles[player]
	if not profile then
		return false, "NotLoaded"
	end
	return GemDataManager.SetGemType(player, profile.Data.GemType, placement)
end

function GemDataManager.SetFaction(player: Player, factionId: string, ignoreCooldown: boolean?): (boolean, string?)
	local profile = profiles[player]
	if not profile then
		return false, "NotLoaded"
	end
	if not GemConfig.IsValidFaction(factionId) then
		return false, "InvalidFaction"
	end

	local data = profile.Data
	local oldFaction = data.Faction
	if oldFaction == factionId then
		return false, "AlreadyInFaction"
	end

	local now = os.time()
	local leavingNeutral = oldFaction == "Neutral"
	if not ignoreCooldown and not leavingNeutral and now - data.LastFactionChange < GemConfig.FactionChangeCooldown then
		return false, "Cooldown"
	end

	data.Faction = factionId
	data.LastFactionChange = now
	replicate(profile)

	GemDataManager.FactionChanged:Fire(player, factionId, oldFaction)
	return true
end

function GemDataManager.GetFactionCooldownRemaining(player: Player): number
	local profile = profiles[player]
	if not profile or profile.Data.Faction == "Neutral" then
		return 0
	end
	local elapsed = os.time() - profile.Data.LastFactionChange
	return math.max(0, GemConfig.FactionChangeCooldown - elapsed)
end

local function updateRank(profile: Profile)
	local data = profile.Data
	local oldRank = data.Rank
	local newRank = GemConfig.GetRankForEssence(data.LifetimeEssence)
	if newRank ~= oldRank then
		data.Rank = newRank
		GemDataManager.RankChanged:Fire(profile.Player, newRank, oldRank)
	end
end

function GemDataManager.AddEssence(player: Player, amount: number, reason: string?): number?
	local profile = profiles[player]
	if not profile or type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return nil
	end
	amount = math.floor(amount)

	local data = profile.Data
	data.CrystalEssence += amount
	data.LifetimeEssence += amount
	updateRank(profile)
	replicate(profile)

	GemDataManager.EssenceChanged:Fire(player, data.CrystalEssence, amount, reason)
	return data.CrystalEssence
end

function GemDataManager.SpendEssence(player: Player, amount: number, reason: string?): boolean
	local profile = profiles[player]
	if not profile or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	amount = math.floor(amount)

	local data = profile.Data
	if data.CrystalEssence < amount then
		return false
	end

	data.CrystalEssence -= amount
	replicate(profile)

	GemDataManager.EssenceChanged:Fire(player, data.CrystalEssence, -amount, reason)
	return true
end

function GemDataManager.IncrementStat(player: Player, statName: string, amount: number?): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local stats = profile.Data.Stats :: any
	if type(stats[statName]) ~= "number" then
		warn(`[GemDataManager] Unknown stat '{statName}'`)
		return false
	end
	stats[statName] += amount or 1
	return true
end

-- Force a save outside the autosave cycle (e.g. after a purchase). Yields.
function GemDataManager.SaveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	return saveAsync(profile, false)
end

return GemDataManager
