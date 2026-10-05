#!/usr/bin/env bash
# Runs ServerStorage.MapBuilder.Build() offline against tests/RobloxStub.luau
# to catch runtime errors, invalid part sizes / CFrames and to count parts.
#   tools/map-check.sh [path/to/luau]
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU="${1:-luau}"
OUT="$(mktemp)"
DIR=src/serverstorage/MapBuilder
{
	echo "local Stub = (function()"
	cat tests/RobloxStub.luau
	echo "end)()"
	echo "local MAP_DUMP = ${MAP_DUMP:-nil}"
	echo "local loaders, cache = {}, {}"
	echo 'local function fakeScript(name) return setmetatable({ Name = name }, { __index = function(_, k) if k == "WaitForChild" or k == "FindFirstChild" then return function(_, child) return fakeScript(child) end end if k == "Parent" then return fakeScript("MapBuilder") end end }) end'
	echo 'local realRequire = require'
	echo 'require = function(s) local name = s.Name if not cache[name] then cache[name] = loaders[name]() end return cache[name] end'
	for f in "$DIR"/*.luau; do
		name="$(basename "$f" .luau)"
		[ "$name" = "init" ] && name="MapBuilder"
		echo "loaders[\"$name\"] = function() local script = fakeScript(\"$name\")"
		cat "$f"
		echo "end"
	done
	cat <<'LUA'
local MapBuilder = require({ Name = "MapBuilder" })
local map = MapBuilder.Build()
assert(map and map.Name == "Map", "Build() did not return Workspace.Map")
assert(map.Parent == workspace, "map not parented to Workspace")
assert(MapBuilder.Build() == map, "second Build() must return the existing map")
local arena = map:FindFirstChild("Arena")
assert(arena and arena:GetAttribute("Center") and arena:GetAttribute("Radius"), "Map.Arena contract missing")
assert(#arena:FindFirstChild("Spawns"):GetChildren() >= 8, "not enough arena spawns")
local lobby = map:FindFirstChild("Lobby")
assert(lobby and lobby:FindFirstChild("LobbySpawn"), "Map.Lobby.LobbySpawn missing")
local parts = 0
for _, d in map:GetDescendants() do if d:IsA("BasePart") then parts += 1 end end
print("parts:", parts)
for _, zone in map:GetChildren() do
	local n = 0
	for _, d in zone:GetDescendants() do if d:IsA("BasePart") then n += 1 end end
	print(string.format("  %-8s %d", zone.Name, n))
end
local tagList = {}
for tag, n in Stub.Tags do table.insert(tagList, tag .. "=" .. n) end
table.sort(tagList)
print("tags:", table.concat(tagList, " "))
-- Walkable floors must be flat: the top of every facet sits on its floor height.
local function topY(w)
	local cf, sz = w.CFrame, w.Size
	local best = -math.huge
	for _, x in { -1, 1 } do for _, y in { -1, 1 } do for _, z in { -1, 1 } do
		local p = cf * Vector3.new(sz.X / 2 * x, sz.Y / 2 * y, sz.Z / 2 * z)
		best = math.max(best, p.Y)
	end end end
	return best
end
for _, check in { { "Temple", "Floor", 62 }, { "Lobby", "Plaza", 70 } } do
	local zone = map:FindFirstChild(check[1])
	for _, d in zone:GetDescendants() do
		if d.Name == check[2] then
			local y = topY(d)
			if math.abs(y - check[3]) > 0.05 then
				table.insert(Stub.Errors, string.format("%s.%s facet top at %.2f, expected %d", check[1], check[2], y, check[3]))
			end
		end
	end
end
if #Stub.Errors > 0 then
	for i = 1, math.min(#Stub.Errors, 20) do print("ERROR", Stub.Errors[i]) end
	error(#Stub.Errors .. " invalid parts")
end
for _, zone in map:FindFirstChild("World"):GetChildren() do local n = 0 for _, d in zone:GetDescendants() do if d:IsA("BasePart") then n += 1 end end print(string.format("    World.%-14s %d", zone.Name, n)) end
for _, zone in map:FindFirstChild("Temple"):GetChildren() do local n = 0 for _, d in zone:GetDescendants() do if d:IsA("BasePart") then n += 1 end end print(string.format("    Temple.%-13s %d", zone.Name, n)) end
print("MAP OK")
if MAP_DUMP then
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			local c, s, col = d.CFrame, d.Size, d.Color
			print(string.format("PART|%s|%s|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f|%.3f,%.3f,%.3f|%.2f|%s",
				d.ClassName, tostring(d.Shape or "Block"), s.X, s.Y, s.Z, c.P.X, c.P.Y, c.P.Z,
				c.R.X, c.R.Y, c.R.Z, c.U.X, c.U.Y, c.U.Z, c.B.X, c.B.Y, c.B.Z,
				col.R, col.G, col.B, d.Transparency or 0, tostring(d.Material or "")))
		end
	end
end
LUA
} > "$OUT"
"$LUAU" "$OUT"
