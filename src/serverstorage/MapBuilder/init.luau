-- MapBuilder (ServerStorage)
-- Builds the whole gem world under Workspace.Map. Run it ONCE in Edit mode and
-- save the place, so the map lives in the place file:
--
--   Studio command bar:
--     require(game.ServerStorage.MapBuilder).Build()
--
-- If Workspace.Map already exists it is returned untouched: this never
-- rebuilds, deletes or edits an existing map. (The server only calls Build()
-- at runtime as a fallback for an empty test place.)
--
-- Layout (studs):
--   Prism Temple (arena)  island around (0, 0, -10), fan floor at Y = 62,
--                         dais / light pillar at (0, 62, 55)
--   Aqueduct              z = 86 .. 408
--   Dawn Gate (lobby)     plaza centre (0, 70, 470)
--   World                 sea, islets, colossus, spires, sky islands,
--                         mountains (r ~2500), moon, aurora
--
-- Gameplay contract:
--   Map.Arena   attributes Center, Radius, FloorY, KillY; Spawns/* tagged "ArenaSpawn"
--   Map.Lobby   SpawnLocation "LobbySpawn"; attributes Center, Radius
--   Animated decoration is tagged MapSpin / MapFloat / MapPulse / MapRise and
--   animated client-side (src/client/MapFX).

local Workspace = game:GetService("Workspace")

local Atmosphere = require(script:WaitForChild("Atmosphere"))
local Bridge = require(script:WaitForChild("Bridge"))
local Lobby = require(script:WaitForChild("Lobby"))
local Temple = require(script:WaitForChild("Temple"))
local World = require(script:WaitForChild("World"))

local MapBuilder = {}

MapBuilder.Title = "Prism Shores"
MapBuilder.Seed = 20261005

local function waypoint(name: string)
	pcall(function()
		game:GetService("ChangeHistoryService"):SetWaypoint(name)
	end)
end

local function countParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

function MapBuilder.Build(): Instance
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		return existing
	end

	waypoint("Before MapBuilder.Build")
	local started = os.clock()

	-- Assemble off-tree, parent once at the end.
	local map = Instance.new("Model")
	map.Name = "Map"

	Temple.Build(map, Random.new(MapBuilder.Seed))
	Bridge.Build(map, Temple.Pivot.Z + 31, Lobby.Center.Z - Lobby.Radius + 2, Temple.FloorY, Lobby.Center.Y, Random.new(MapBuilder.Seed + 1))
	Lobby.Build(map, Random.new(MapBuilder.Seed + 2), MapBuilder.Title)
	World.Build(map, Random.new(MapBuilder.Seed + 3))
	Atmosphere.Apply()

	Workspace.FallenPartsDestroyHeight = -60
	-- Stream the far world in and out (only settable from Studio, so best effort).
	pcall(function()
		(Workspace :: any).StreamingEnabled = true
	end)
	map.Parent = Workspace

	waypoint("MapBuilder.Build")
	print(string.format("[MapBuilder] Built Workspace.Map: %d parts in %.2fs", countParts(map), os.clock() - started))
	return map
end

return MapBuilder
