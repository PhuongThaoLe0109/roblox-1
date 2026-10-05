--!strict
-- TerritoryConfig
-- The 12 capturable islands, the neutral hub and the two faction home bases.
--
-- Travel is portal-based: islands sit far apart in open sea. Each island has a
-- forward portal to the next island (requires rank N for island N) and a return
-- portal to the hub. The hub has a portal to island 1 and to your faction home.
-- Positions are derived from angles so server (map, capture, portals) and
-- client (minimap) always agree.

local TerritoryConfig = {}

export type ThemeId =
	"Temple"
	| "Town"
	| "Garden"
	| "Battlefield"
	| "Colosseum"
	| "Outpost"
	| "Throne"
	| "Canyon"
	| "Crystal"
	| "Warp"
	| "Jungle"
	| "Citadel"

export type TerritoryInfo = {
	Id: string,
	DisplayName: string,
	Description: string,
	Theme: ThemeId,
	Ground: Color3,
	GroundMaterial: Enum.Material,
	Accent: Color3,
	Lush: boolean, -- trees/bushes vs. rocks for the scenery pass
	InitialOwner: string?,
}

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

TerritoryConfig.HubRadius = 110
TerritoryConfig.IslandRadius = 150
TerritoryConfig.RingRadius = 1000 -- ~215 studs of open sea between neighbours
TerritoryConfig.HomeIslandRadius = 80
TerritoryConfig.HomeRadius = 1450
TerritoryConfig.SeaLevel = -6 -- water surface; island ground tops sit at Y = 0
TerritoryConfig.WorldExtent = 1800 -- terrain water is filled to +/- this

-- Portals sit on the island's hub-facing axis: return portal at the front,
-- forward portal at the back. Values are fractions of the island radius.
TerritoryConfig.ReturnPortalDistance = 0.82
TerritoryConfig.ForwardPortalDistance = 0.82
TerritoryConfig.ArrivalDistance = 0.62

--------------------------------------------------------------------------------
-- Capture & economy
--------------------------------------------------------------------------------

TerritoryConfig.CaptureRadius = 26
TerritoryConfig.CaptureHeight = 18 -- vertical tolerance above the pad
TerritoryConfig.CaptureTime = 20 -- seconds for one player to go 0 -> 100
TerritoryConfig.MaxCaptureMultiplier = 3 -- more players capture faster, capped
TerritoryConfig.RegenPerSecond = 4 -- uncontested owned points recover, unowned decay
TerritoryConfig.TickInterval = 0.25

TerritoryConfig.CaptureReward = 100 -- essence to each capturing player
TerritoryConfig.IncomeInterval = 60
TerritoryConfig.BaseIncome = 10 -- every loaded player, so Rogues progress too
TerritoryConfig.IncomePerTerritory = 5 -- extra per island your faction owns

TerritoryConfig.FastTravelCooldown = 10

--------------------------------------------------------------------------------
-- Home bases & hub
--------------------------------------------------------------------------------

TerritoryConfig.Homes = {
	Guardians = { DisplayName = "Prism Haven", AngleDegrees = 15 },
	Dominion = { DisplayName = "Crown Bastion", AngleDegrees = 195 },
} :: { [string]: { DisplayName: string, AngleDegrees: number } }

TerritoryConfig.HubName = "Nexus Plaza"

--------------------------------------------------------------------------------
-- Islands (ring order; index 1 sits at angle 0, then every 30 degrees).
-- Island N requires rank N (GemConfig.Ranks[N]).
--------------------------------------------------------------------------------

TerritoryConfig.Territories = {
	{
		Id = "Tidecrest",
		DisplayName = "Tidecrest Sanctum",
		Description = "A beach cliff carved into a giant seated guardian, a lighthouse on its crown.",
		Theme = "Temple",
		Ground = Color3.fromRGB(240, 220, 175),
		GroundMaterial = Enum.Material.Sand,
		Accent = Color3.fromRGB(240, 160, 190),
		Lush = true,
		InitialOwner = "Guardians",
	},
	{
		Id = "Seabreeze",
		DisplayName = "Seabreeze Bay",
		Description = "A sleepy boardwalk town of shops, fries stands and colourful houses.",
		Theme = "Town",
		Ground = Color3.fromRGB(225, 205, 160),
		GroundMaterial = Enum.Material.Sand,
		Accent = Color3.fromRGB(110, 190, 230),
		Lush = true,
	},
	{
		Id = "Thornbloom",
		DisplayName = "Thornbloom Garden",
		Description = "An overgrown walled garden of thorny vines around a healing fountain.",
		Theme = "Garden",
		Ground = Color3.fromRGB(110, 170, 90),
		GroundMaterial = Enum.Material.Grass,
		Accent = Color3.fromRGB(230, 120, 160),
		Lush = true,
	},
	{
		Id = "Berryfield",
		DisplayName = "Berryfield Ruins",
		Description = "An ancient war field of giant berries and thousands of abandoned blades.",
		Theme = "Battlefield",
		Ground = Color3.fromRGB(120, 160, 80),
		GroundMaterial = Enum.Material.Grass,
		Accent = Color3.fromRGB(220, 50, 70),
		Lush = true,
	},
	{
		Id = "Mirrorfall",
		DisplayName = "Mirrorfall Isle",
		Description = "Jungle terraces with glowing crystal arches and a waterfall of light.",
		Theme = "Jungle",
		Ground = Color3.fromRGB(80, 140, 120),
		GroundMaterial = Enum.Material.Grass,
		Accent = Color3.fromRGB(90, 220, 255),
		Lush = true,
	},
	{
		Id = "CloudColosseum",
		DisplayName = "Cloud Colosseum",
		Description = "A broken amphitheatre drifting in pink clouds, ringed by crystal obelisks.",
		Theme = "Colosseum",
		Ground = Color3.fromRGB(215, 185, 190),
		GroundMaterial = Enum.Material.Marble,
		Accent = Color3.fromRGB(255, 170, 190),
		Lush = false,
	},
	{
		Id = "SovereignSpire",
		DisplayName = "Sovereign Spire",
		Description = "The empire's audience hall, crowned by twin throne spires.",
		Theme = "Throne",
		Ground = Color3.fromRGB(240, 235, 220),
		GroundMaterial = Enum.Material.Marble,
		Accent = Color3.fromRGB(255, 190, 70),
		Lush = false,
		InitialOwner = "Dominion",
	},
	{
		Id = "LunarOutpost",
		DisplayName = "Lunar Outpost",
		Description = "A domed observatory on a grey moonrock shelf.",
		Theme = "Outpost",
		Ground = Color3.fromRGB(150, 150, 160),
		GroundMaterial = Enum.Material.Slate,
		Accent = Color3.fromRGB(255, 210, 120),
		Lush = false,
	},
	{
		Id = "Hatchery",
		DisplayName = "The Hatchery",
		Description = "Canyon walls pocked with the holes where gems once emerged.",
		Theme = "Canyon",
		Ground = Color3.fromRGB(170, 110, 80),
		GroundMaterial = Enum.Material.Rock,
		Accent = Color3.fromRGB(255, 130, 60),
		Lush = false,
	},
	{
		Id = "PrimeDig",
		DisplayName = "Prime Excavation",
		Description = "A crystal mine where raw shards jut from the ground.",
		Theme = "Crystal",
		Ground = Color3.fromRGB(90, 80, 110),
		GroundMaterial = Enum.Material.Basalt,
		Accent = Color3.fromRGB(190, 120, 255),
		Lush = false,
	},
	{
		Id = "WarpRing",
		DisplayName = "Shattered Warp Ring",
		Description = "A ring of broken pillars around a dormant warp pad.",
		Theme = "Warp",
		Ground = Color3.fromRGB(70, 70, 95),
		GroundMaterial = Enum.Material.Slate,
		Accent = Color3.fromRGB(120, 230, 255),
		Lush = false,
	},
	{
		Id = "Sandglass",
		DisplayName = "Sandglass Citadel",
		Description = "Desert towers built around a never-ending hourglass.",
		Theme = "Citadel",
		Ground = Color3.fromRGB(230, 195, 130),
		GroundMaterial = Enum.Material.Sandstone,
		Accent = Color3.fromRGB(240, 150, 60),
		Lush = false,
	},
} :: { TerritoryInfo }

TerritoryConfig.ById = {} :: { [string]: TerritoryInfo }
TerritoryConfig.IndexOf = {} :: { [string]: number }

for index, info in TerritoryConfig.Territories do
	assert(TerritoryConfig.ById[info.Id] == nil, `TerritoryConfig: duplicate id {info.Id}`)
	TerritoryConfig.ById[info.Id] = info
	TerritoryConfig.IndexOf[info.Id] = index
end
assert(#TerritoryConfig.Territories == 12, "TerritoryConfig: expected 12 territories")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function onCircle(radius: number, angleDegrees: number): Vector3
	local a = math.rad(angleDegrees)
	return Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
end

function TerritoryConfig.GetAngle(index: number): number
	return (index - 1) * (360 / #TerritoryConfig.Territories)
end

function TerritoryConfig.GetTerritoryCenter(index: number): Vector3
	return onCircle(TerritoryConfig.RingRadius, TerritoryConfig.GetAngle(index))
end

function TerritoryConfig.GetHomeCenter(factionId: string): Vector3?
	local home = TerritoryConfig.Homes[factionId]
	return if home then onCircle(TerritoryConfig.HomeRadius, home.AngleDegrees) else nil
end

-- Island N requires rank N.
function TerritoryConfig.GetRequiredRank(territoryId: string): number
	return TerritoryConfig.IndexOf[territoryId] or 1
end

-- Which landmass a world position is over (horizontal distance only).
-- Returns a territory id, "Hub", "Home" or nil when over open sea.
function TerritoryConfig.GetLocationAt(position: Vector3): string?
	local flat = Vector3.new(position.X, 0, position.Z)
	local margin = 25 -- include beaches
	if flat.Magnitude <= TerritoryConfig.HubRadius + margin then
		return "Hub"
	end
	for index, info in TerritoryConfig.Territories do
		if (flat - TerritoryConfig.GetTerritoryCenter(index)).Magnitude <= TerritoryConfig.IslandRadius + margin then
			return info.Id
		end
	end
	for factionId in TerritoryConfig.Homes do
		local center = TerritoryConfig.GetHomeCenter(factionId) :: Vector3
		if (flat - center).Magnitude <= TerritoryConfig.HomeIslandRadius + margin then
			return "Home"
		end
	end
	return nil
end

function TerritoryConfig.GetHomeAt(position: Vector3): string?
	local flat = Vector3.new(position.X, 0, position.Z)
	for factionId in TerritoryConfig.Homes do
		local center = TerritoryConfig.GetHomeCenter(factionId) :: Vector3
		if (flat - center).Magnitude <= TerritoryConfig.HomeIslandRadius + 25 then
			return factionId
		end
	end
	return nil
end

table.freeze(TerritoryConfig.Homes)
table.freeze(TerritoryConfig.ById)
table.freeze(TerritoryConfig.IndexOf)
for _, info in TerritoryConfig.Territories do
	table.freeze(info)
end
table.freeze(TerritoryConfig.Territories)
table.freeze(TerritoryConfig)

return TerritoryConfig
