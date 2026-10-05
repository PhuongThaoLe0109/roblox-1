-- PlayerData
-- Server-authoritative persistence for every player:
--   Inventory  { [gemId] = count }   gems owned (duplicates stack)
--   Equipped   gemId or ""           the aura being worn
--   Pity       { number }            hidden pity counters (never replicated)
--   Stats      Rolls, Kills, Deaths, BestStreak
--
-- DataStore safety: UpdateAsync with a session lock so two servers never
-- overwrite each other, retries with backoff, autosave, save on leave and on
-- shutdown, schema reconciliation. In Studio without API access it runs on
-- temporary data.
--
-- Clients learn about their data through Player attributes (DataLoaded,
-- EquippedGem, TotalRolls) and the InventorySync remote; pity never leaves
-- the server.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "PlayerData is server-only")

local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))
local Signal = require(ReplicatedStorage:WaitForChild("Signal"))
local RollConfig = require(script.Parent:WaitForChild("RollConfig"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local PlayerData = {}

local STORE_NAME = "GemBrawlData"
local STORE_SCOPE = "v1"
local KEY_PREFIX = "Player_"
local SCHEMA_VERSION = 1
local AUTOSAVE_INTERVAL = 90
local SESSION_LOCK_TIMEOUT = 30 * 60
local LOCK_RETRY_ATTEMPTS = 5
local LOCK_RETRY_DELAY = 6
local MAX_RETRIES = 5
local SHUTDOWN_TIMEOUT = 25

PlayerData.Attributes = {
	DataLoaded = "DataLoaded",
	EquippedGem = "EquippedGem",
	TotalRolls = "TotalRolls",
}
local ATTR = PlayerData.Attributes

PlayerData.Loaded = Signal.new() -- (player)
PlayerData.Released = Signal.new() -- (player)
PlayerData.GemAdded = Signal.new() -- (player, gemId, newCount)
PlayerData.EquippedChanged = Signal.new() -- (player, gemId)

export type Data = {
	SchemaVersion: number,
	Inventory: { [string]: number },
	Equipped: string,
	Pity: { number },
	Stats: {
		Rolls: number,
		Kills: number,
		Deaths: number,
		BestStreak: number,
	},
	FirstJoin: number,
	LastJoin: number,
}

type Profile = {
	Player: Player,
	Key: string,
	Data: Data,
	CanSave: boolean,
	Released: boolean,
}

local profiles: { [Player]: Profile } = {}
local pendingReleases = 0
local shuttingDown = false
local initialized = false

-- game.JobId is "" in Studio, so add a GUID to make each server unique.
local SESSION_ID = (if game.JobId ~= "" then game.JobId else "Studio") .. "_" .. HttpService:GenerateGUID(false)

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME, STORE_SCOPE)
	end)
	if ok then
		store = result
	else
		warn(`[PlayerData] DataStores unavailable ({result}); progress will not be saved.`)
	end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in (value :: any) do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

local function keyFor(userId: number): string
	return KEY_PREFIX .. tostring(userId)
end

local function waitForBudget()
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) <= 0 and waited < 10 do
		waited += task.wait(0.5)
	end
end

local function defaultData(): Data
	local now = os.time()
	return {
		SchemaVersion = SCHEMA_VERSION,
		Inventory = {},
		Equipped = "",
		Pity = table.create(#RollConfig.Pity, 0),
		Stats = { Rolls = 0, Kills = 0, Deaths = 0, BestStreak = 0 },
		FirstJoin = now,
		LastJoin = now,
	}
end

-- Fill missing fields, repair bad values, keep everything else.
local function reconcile(raw: any): Data
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end

	if type(raw.Inventory) == "table" then
		for gemId, count in raw.Inventory do
			-- Unknown ids are kept so a gem removed by mistake isn't lost.
			if type(gemId) == "string" and type(count) == "number" and count > 0 then
				data.Inventory[gemId] = math.floor(count)
			end
		end
	end
	if type(raw.Equipped) == "string" and (data.Inventory[raw.Equipped] or 0) > 0 then
		data.Equipped = raw.Equipped
	end
	if type(raw.Pity) == "table" then
		for i = 1, #RollConfig.Pity do
			local value = raw.Pity[i]
			data.Pity[i] = if type(value) == "number" and value >= 0 then math.floor(value) else 0
		end
	end
	if type(raw.Stats) == "table" then
		for key in data.Stats do
			local value = raw.Stats[key]
			if type(value) == "number" and value >= 0 then
				(data.Stats :: any)[key] = math.floor(value)
			end
		end
	end
	if type(raw.FirstJoin) == "number" then
		data.FirstJoin = raw.FirstJoin
	end
	data.LastJoin = os.time()
	return data
end

local function lockedByOther(session: any): boolean
	return type(session) == "table"
		and session.Id ~= SESSION_ID
		and type(session.Timestamp) == "number"
		and os.time() - session.Timestamp < SESSION_LOCK_TIMEOUT
end

--------------------------------------------------------------------------------
-- DataStore I/O
--------------------------------------------------------------------------------

type LoadResult = "Loaded" | "Locked" | "Failed"

local function load(userId: number): (LoadResult, Data?)
	if not store then
		return "Failed", nil
	end
	local key = keyFor(userId)
	local attempt, lockWaits = 0, 0

	while attempt < MAX_RETRIES do
		attempt += 1
		local blocked = false
		waitForBudget()
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, function(stored)
				stored = if type(stored) == "table" then stored else {}
				if lockedByOther(stored.Session) then
					blocked = true
					return nil -- leave another server's session alone
				end
				stored.Data = reconcile(stored.Data)
				stored.Session = { Id = SESSION_ID, Timestamp = os.time() }
				return stored
			end)
		end)

		if ok and not blocked and type(result) == "table" then
			return "Loaded", result.Data
		elseif ok and blocked then
			lockWaits += 1
			if lockWaits >= LOCK_RETRY_ATTEMPTS then
				return "Locked", nil
			end
			attempt -= 1
			task.wait(LOCK_RETRY_DELAY)
		else
			warn(`[PlayerData] Load attempt {attempt} for {key} failed: {result}`)
			-- 403: Studio API access is off; retrying won't help.
			if string.find(tostring(result), "403", 1, true) then
				return "Failed", nil
			end
			task.wait(2 ^ attempt)
		end
	end
	return "Failed", nil
end

-- Returns false when another server has taken this player's session.
local function save(profile: Profile, release: boolean): boolean
	if not store or not profile.CanSave then
		return true
	end
	local snapshot = deepCopy(profile.Data)
	local lost = false

	for attempt = 1, MAX_RETRIES do
		waitForBudget()
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(profile.Key, function(stored)
				stored = if type(stored) == "table" then stored else {}
				if type(stored.Session) == "table" and stored.Session.Id ~= SESSION_ID then
					lost = true
					return nil
				end
				stored.Data = snapshot
				stored.Session = if release then nil else { Id = SESSION_ID, Timestamp = os.time() }
				return stored
			end)
		end)
		if ok then
			if lost then
				warn(`[PlayerData] Session lock lost for {profile.Key}; this server's data was not saved.`)
			end
			return not lost
		end
		warn(`[PlayerData] Save attempt {attempt} for {profile.Key} failed: {err}`)
		if attempt < MAX_RETRIES then
			task.wait(if shuttingDown then 1 else 2 ^ attempt)
		end
	end
	return true -- transient failure; the lock is still ours, autosave retries
end

--------------------------------------------------------------------------------
-- Replication
--------------------------------------------------------------------------------

local function publicSnapshot(data: Data)
	return {
		Inventory = deepCopy(data.Inventory),
		Equipped = data.Equipped,
		Rolls = data.Stats.Rolls,
	}
end

local function replicate(profile: Profile)
	local player = profile.Player
	player:SetAttribute(ATTR.EquippedGem, profile.Data.Equipped)
	player:SetAttribute(ATTR.TotalRolls, profile.Data.Stats.Rolls)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if profiles[player] then
		return
	end
	local status, data = load(player.UserId)
	local canSave = status == "Loaded"
	if status == "Locked" then
		player:Kick("Your data is still open in another server. Please rejoin in a moment.")
		return
	elseif status == "Failed" then
		if store and not RunService:IsStudio() then
			-- Never let someone play on blank data in production: it would look like a wipe.
			player:Kick("Could not load your data. Please rejoin.")
			return
		end
		data = defaultData()
		warn(`[PlayerData] {player.Name} is using temporary data (not saved).`)
	end

	local profile: Profile = {
		Player = player,
		Key = keyFor(player.UserId),
		Data = data :: Data,
		CanSave = canSave,
		Released = false,
	}

	if player.Parent ~= Players then
		-- Left while loading: release the lock straight away.
		profile.Released = true
		save(profile, true)
		return
	end

	profiles[player] = profile
	replicate(profile)
	player:SetAttribute(ATTR.DataLoaded, true)
	Remotes.InventorySync:FireClient(player, "Full", publicSnapshot(profile.Data))
	PlayerData.Loaded:Fire(player)
end

local function release(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	profile.Released = true
	profiles[player] = nil
	pendingReleases += 1
	local ok, err = pcall(save, profile, true)
	pendingReleases -= 1
	if not ok then
		warn(`[PlayerData] Release failed for {profile.Key}: {err}`)
	end
	PlayerData.Released:Fire(player)
end

local function autosaveLoop()
	while not shuttingDown do
		task.wait(AUTOSAVE_INTERVAL)
		for player, profile in table.clone(profiles) do
			if not profile.Released then
				task.spawn(function()
					if not save(profile, false) and not profile.Released then
						profile.CanSave = false
						player:Kick("Your data was opened in another server.")
					end
				end)
				task.wait(0.1)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function PlayerData.Init()
	if initialized then
		return
	end
	initialized = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		shuttingDown = true
		for player in profiles do
			task.spawn(release, player)
		end
		local deadline = os.clock() + SHUTDOWN_TIMEOUT
		while (pendingReleases > 0 or next(profiles) ~= nil) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
	task.spawn(autosaveLoop)

	Remotes.GetProfile.OnServerInvoke = function(player: Player)
		local profile = profiles[player]
		return if profile then publicSnapshot(profile.Data) else nil
	end
end

function PlayerData.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function PlayerData.GetCount(player: Player, gemId: string): number
	local profile = profiles[player]
	return if profile then profile.Data.Inventory[gemId] or 0 else 0
end

function PlayerData.GetEquipped(player: Player): string?
	local profile = profiles[player]
	if not profile or profile.Data.Equipped == "" then
		return nil
	end
	return profile.Data.Equipped
end

function PlayerData.GetStats(player: Player)
	local profile = profiles[player]
	return if profile then deepCopy(profile.Data.Stats) else nil
end

-- Hidden pity counters (server only).
function PlayerData.GetPity(player: Player): { number }?
	local profile = profiles[player]
	return if profile then table.clone(profile.Data.Pity) else nil
end

function PlayerData.SetPity(player: Player, pity: { number })
	local profile = profiles[player]
	if profile then
		profile.Data.Pity = table.clone(pity)
	end
end

function PlayerData.AddGem(player: Player, gemId: string): number?
	local profile = profiles[player]
	if not profile or not GemCatalog.Get(gemId) then
		return nil
	end
	local count = (profile.Data.Inventory[gemId] or 0) + 1
	profile.Data.Inventory[gemId] = count
	Remotes.InventorySync:FireClient(player, "Gem", gemId, count)
	PlayerData.GemAdded:Fire(player, gemId, count)
	return count
end

-- Gives one of every gem the player doesn't own yet (founder command).
-- Returns how many new gems were added.
function PlayerData.GrantAll(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local added = 0
	for _, gem in GemCatalog.List do
		if (profile.Data.Inventory[gem.Id] or 0) <= 0 then
			profile.Data.Inventory[gem.Id] = 1
			added += 1
		end
	end
	Remotes.InventorySync:FireClient(player, "Full", publicSnapshot(profile.Data))
	return added
end

function PlayerData.Equip(player: Player, gemId: string): (boolean, string?)
	local profile = profiles[player]
	if not profile then
		return false, "NotLoaded"
	end
	if gemId ~= "" and (profile.Data.Inventory[gemId] or 0) <= 0 then
		return false, "NotOwned"
	end
	profile.Data.Equipped = gemId
	replicate(profile)
	Remotes.InventorySync:FireClient(player, "Equipped", gemId)
	PlayerData.EquippedChanged:Fire(player, gemId)
	return true
end

function PlayerData.IncrementStat(player: Player, stat: string, amount: number?): number?
	local profile = profiles[player]
	local stats = profile and (profile.Data.Stats :: any)
	if not stats or type(stats[stat]) ~= "number" then
		return nil
	end
	stats[stat] += amount or 1
	if stat == "Rolls" then
		replicate(profile :: Profile)
	end
	return stats[stat]
end

function PlayerData.SetBestStreak(player: Player, streak: number)
	local profile = profiles[player]
	if profile and streak > profile.Data.Stats.BestStreak then
		profile.Data.Stats.BestStreak = streak
	end
end

-- Save right away (e.g. after a very rare pull). Yields.
function PlayerData.SaveNow(player: Player): boolean
	local profile = profiles[player]
	return if profile then save(profile, false) else false
end

return PlayerData
