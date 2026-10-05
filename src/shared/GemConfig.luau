--!strict
-- GemConfig
-- Single source of truth for gem types, body placements, factions and ranks.
-- Shared (ReplicatedStorage) so client UI can read display names/colors, but
-- every gameplay decision is validated on the server against this table.

local GemConfig = {}

--------------------------------------------------------------------------------
-- Factions
--------------------------------------------------------------------------------

export type FactionId = "CrystalGems" | "Homeworld" | "Neutral"

export type FactionInfo = {
	Id: FactionId,
	DisplayName: string,
	Color: Color3,
	TeamColor: BrickColor,
}

GemConfig.Factions = {
	CrystalGems = {
		Id = "CrystalGems",
		DisplayName = "Crystal Gems",
		Color = Color3.fromRGB(255, 120, 170),
		TeamColor = BrickColor.new("Pink"),
	},
	Homeworld = {
		Id = "Homeworld",
		DisplayName = "Homeworld",
		Color = Color3.fromRGB(255, 220, 90),
		TeamColor = BrickColor.new("Bright yellow"),
	},
	Neutral = {
		Id = "Neutral",
		DisplayName = "Off-Color",
		Color = Color3.fromRGB(180, 180, 190),
		TeamColor = BrickColor.new("Medium stone grey"),
	},
} :: { [string]: FactionInfo }

GemConfig.DefaultFaction = "Neutral" :: FactionId

-- Seconds a player must wait between faction switches (leaving Neutral is free).
GemConfig.FactionChangeCooldown = 24 * 60 * 60

--------------------------------------------------------------------------------
-- Gem body placements
-- BodyPart is the R15 part name; R6Fallback is used for R6 rigs.
-- Offset is the CFrame of the gem relative to that part (Weld.C0).
--------------------------------------------------------------------------------

export type PlacementInfo = {
	BodyPart: string,
	R6Fallback: string,
	Offset: CFrame,
}

GemConfig.Placements = {
	Forehead = {
		BodyPart = "Head",
		R6Fallback = "Head",
		Offset = CFrame.new(0, 0.3, -0.6),
	},
	Nose = {
		BodyPart = "Head",
		R6Fallback = "Head",
		Offset = CFrame.new(0, 0, -0.65),
	},
	Chest = {
		BodyPart = "UpperTorso",
		R6Fallback = "Torso",
		Offset = CFrame.new(0, 0.2, -0.55),
	},
	Back = {
		BodyPart = "UpperTorso",
		R6Fallback = "Torso",
		Offset = CFrame.new(0, 0.2, 0.55) * CFrame.Angles(0, math.pi, 0),
	},
	Navel = {
		BodyPart = "LowerTorso",
		R6Fallback = "Torso",
		Offset = CFrame.new(0, 0, -0.5),
	},
	LeftHand = {
		BodyPart = "LeftHand",
		R6Fallback = "Left Arm",
		Offset = CFrame.new(0, 0, 0.25) * CFrame.Angles(0, math.pi, 0),
	},
	RightHand = {
		BodyPart = "RightHand",
		R6Fallback = "Right Arm",
		Offset = CFrame.new(0, 0, 0.25) * CFrame.Angles(0, math.pi, 0),
	},
} :: { [string]: PlacementInfo }

--------------------------------------------------------------------------------
-- Gem types
-- WeaponId is consumed by the Weapon Summoning System.
-- BaseStats is consumed by the Combat & Puff State Handler.
--------------------------------------------------------------------------------

export type GemStats = {
	MaxHealth: number,
	WalkSpeed: number,
	Power: number,
	Defense: number,
}

export type GemTypeInfo = {
	Id: string,
	DisplayName: string,
	Color: Color3,
	Material: Enum.Material,
	Shape: "Round" | "Faceted" | "Diamond",
	DefaultPlacement: string,
	AllowedPlacements: { string },
	WeaponId: string,
	BaseStats: GemStats,
	Starter: boolean, -- can be rolled for a brand-new player
}

GemConfig.GemTypes = {
	Pearl = {
		Id = "Pearl",
		DisplayName = "Pearl",
		Color = Color3.fromRGB(240, 235, 225),
		Material = Enum.Material.SmoothPlastic,
		Shape = "Round",
		DefaultPlacement = "Forehead",
		AllowedPlacements = { "Forehead", "Chest", "Navel", "Back" },
		WeaponId = "EnergySpear",
		BaseStats = { MaxHealth = 90, WalkSpeed = 20, Power = 9, Defense = 6 },
		Starter = true,
	},
	Amethyst = {
		Id = "Amethyst",
		DisplayName = "Amethyst",
		Color = Color3.fromRGB(160, 90, 220),
		Material = Enum.Material.Glass,
		Shape = "Faceted",
		DefaultPlacement = "Chest",
		AllowedPlacements = { "Chest", "Navel", "Back", "Forehead" },
		WeaponId = "LightWhip",
		BaseStats = { MaxHealth = 120, WalkSpeed = 16, Power = 10, Defense = 10 },
		Starter = true,
	},
	Ruby = {
		Id = "Ruby",
		DisplayName = "Ruby",
		Color = Color3.fromRGB(220, 30, 50),
		Material = Enum.Material.Glass,
		Shape = "Faceted",
		DefaultPlacement = "LeftHand",
		AllowedPlacements = { "LeftHand", "RightHand", "Navel", "Forehead" },
		WeaponId = "PowerGauntlet",
		BaseStats = { MaxHealth = 100, WalkSpeed = 17, Power = 12, Defense = 8 },
		Starter = true,
	},
	Sapphire = {
		Id = "Sapphire",
		DisplayName = "Sapphire",
		Color = Color3.fromRGB(40, 90, 230),
		Material = Enum.Material.Glass,
		Shape = "Faceted",
		DefaultPlacement = "RightHand",
		AllowedPlacements = { "LeftHand", "RightHand", "Forehead" },
		WeaponId = "FrostGauntlet",
		BaseStats = { MaxHealth = 85, WalkSpeed = 16, Power = 9, Defense = 9 },
		Starter = true,
	},
	Bismuth = {
		Id = "Bismuth",
		DisplayName = "Bismuth",
		Color = Color3.fromRGB(110, 200, 190),
		Material = Enum.Material.Foil,
		Shape = "Faceted",
		DefaultPlacement = "Chest",
		AllowedPlacements = { "Chest", "Navel", "Back" },
		WeaponId = "ForgeHammer",
		BaseStats = { MaxHealth = 140, WalkSpeed = 15, Power = 13, Defense = 12 },
		Starter = false,
	},
	Jasper = {
		Id = "Jasper",
		DisplayName = "Jasper",
		Color = Color3.fromRGB(230, 120, 50),
		Material = Enum.Material.Marble,
		Shape = "Diamond",
		DefaultPlacement = "Nose",
		AllowedPlacements = { "Nose", "Forehead", "Chest" },
		WeaponId = "CrashHelmet",
		BaseStats = { MaxHealth = 150, WalkSpeed = 17, Power = 14, Defense = 11 },
		Starter = false,
	},
	Peridot = {
		Id = "Peridot",
		DisplayName = "Peridot",
		Color = Color3.fromRGB(140, 230, 60),
		Material = Enum.Material.Glass,
		Shape = "Diamond",
		DefaultPlacement = "Forehead",
		AllowedPlacements = { "Forehead", "Chest" },
		WeaponId = "LimbEnhancer",
		BaseStats = { MaxHealth = 80, WalkSpeed = 19, Power = 8, Defense = 7 },
		Starter = true,
	},
	LapisLazuli = {
		Id = "LapisLazuli",
		DisplayName = "Lapis Lazuli",
		Color = Color3.fromRGB(30, 60, 160),
		Material = Enum.Material.Glass,
		Shape = "Diamond",
		DefaultPlacement = "Back",
		AllowedPlacements = { "Back", "Chest" },
		WeaponId = "WaterWings",
		BaseStats = { MaxHealth = 110, WalkSpeed = 18, Power = 11, Defense = 8 },
		Starter = false,
	},
} :: { [string]: GemTypeInfo }

--------------------------------------------------------------------------------
-- Ranks (driven by lifetime essence, so spending essence never de-ranks)
--------------------------------------------------------------------------------

export type RankInfo = {
	Name: string,
	EssenceRequired: number,
}

GemConfig.Ranks = {
	{ Name = "Shard", EssenceRequired = 0 },
	{ Name = "Rough Cut", EssenceRequired = 500 },
	{ Name = "Polished", EssenceRequired = 1_500 },
	{ Name = "Faceted", EssenceRequired = 4_000 },
	{ Name = "Radiant", EssenceRequired = 10_000 },
	{ Name = "Perfect", EssenceRequired = 25_000 },
	{ Name = "Diamond Elite", EssenceRequired = 60_000 },
} :: { RankInfo }

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

GemConfig.DataStore = {
	Name = "GemPlayerData",
	Scope = "v1",
	KeyPrefix = "Player_",
	SchemaVersion = 1,
	AutoSaveInterval = 120, -- seconds; also refreshes the session lock
	SessionLockTimeout = 30 * 60, -- a lock older than this is considered dead
	LockRetryAttempts = 5, -- how many times to wait on another server's lock
	LockRetryDelay = 6,
	MaxRequestRetries = 5,
	ShutdownTimeout = 25,
}

--------------------------------------------------------------------------------
-- Replication contract (other systems read these instead of requiring the
-- server module)
--------------------------------------------------------------------------------

GemConfig.Attributes = {
	DataLoaded = "GemDataLoaded",
	GemType = "GemType",
	GemPlacement = "GemPlacement",
	Faction = "Faction",
	Rank = "Rank",
	RankName = "RankName",
	CrystalEssence = "CrystalEssence",
	WeaponId = "WeaponId",
	OwnerUserId = "OwnerUserId",
}

GemConfig.Tags = {
	Gemstone = "Gemstone", -- the physical gem part on a character
	GemCharacter = "GemCharacter", -- any character owned by a loaded gem player
}

GemConfig.GemstoneName = "Gemstone"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

function GemConfig.IsValidGemType(gemType: any): boolean
	return type(gemType) == "string" and GemConfig.GemTypes[gemType] ~= nil
end

function GemConfig.IsValidFaction(factionId: any): boolean
	return type(factionId) == "string" and GemConfig.Factions[factionId] ~= nil
end

function GemConfig.IsPlacementAllowed(gemType: string, placement: any): boolean
	local info = GemConfig.GemTypes[gemType]
	if not info or type(placement) ~= "string" or not GemConfig.Placements[placement] then
		return false
	end
	return table.find(info.AllowedPlacements, placement) ~= nil
end

function GemConfig.GetRankForEssence(lifetimeEssence: number): (number, RankInfo)
	local index = 1
	for i, rank in GemConfig.Ranks do
		if lifetimeEssence >= rank.EssenceRequired then
			index = i
		else
			break
		end
	end
	return index, GemConfig.Ranks[index]
end

function GemConfig.GetStarterGemTypes(): { string }
	local list = {}
	for id, info in GemConfig.GemTypes do
		if info.Starter then
			table.insert(list, id)
		end
	end
	table.sort(list) -- deterministic order regardless of hash iteration
	return list
end

-- Sanity-check config once at require time so typos fail loudly in Studio.
for id, info in GemConfig.GemTypes do
	assert(info.Id == id, `GemConfig: GemTypes.{id}.Id mismatch`)
	assert(
		table.find(info.AllowedPlacements, info.DefaultPlacement),
		`GemConfig: {id}.DefaultPlacement must be in AllowedPlacements`
	)
	for _, placement in info.AllowedPlacements do
		assert(GemConfig.Placements[placement], `GemConfig: {id} references unknown placement '{placement}'`)
	end
end
assert(GemConfig.Factions[GemConfig.DefaultFaction], "GemConfig: DefaultFaction is not a valid faction")

local function deepFreeze(t: any)
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			deepFreeze(value)
		end
	end
	table.freeze(t)
end
deepFreeze(GemConfig)

return GemConfig
