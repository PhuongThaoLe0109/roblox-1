#!/usr/bin/env bash
# Builds and animates all 100 auras offline against tests/RobloxStub.luau:
# every gem must have a recipe, every layer must build and update without
# errors, part CFrames must stay finite/orthonormal, and part counts stay
# within budget for the rarity.
#   tools/aura-check.sh [path/to/luau]
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU="${1:-luau}"
OUT="$(mktemp)"
{
	echo "local Stub = (function()"
	cat tests/RobloxStub.luau
	echo "end)()"
	echo "local GemCatalog = (function()"
	cat src/shared/GemCatalog.luau
	echo "end)()"
	echo "local Layers = (function()"
	cat src/client/Aura/Layers.luau
	echo "end)()"
	echo "local Recipes = (function()"
	cat src/client/Aura/Recipes.luau
	echo "end)()"
	cat <<'LUA'
local failures = 0
local seen = {}
for id in Recipes.All do
	assert(GemCatalog.Get(id), "recipe for unknown gem " .. id)
end
local budget = { 30, 50, 100, 200, 280 }
-- A stand-in R15 character for the limb-following layers.
local function dummy(root)
	local character = Instance.new("Model")
	for name, offset in {
		UpperTorso = Vector3.new(0, 0.6, 0), Head = Vector3.new(0, 2.1, 0),
		LeftUpperArm = Vector3.new(-1.5, 0.8, 0), RightUpperArm = Vector3.new(1.5, 0.8, 0),
		LeftLowerArm = Vector3.new(-1.5, -0.4, 0), RightLowerArm = Vector3.new(1.5, -0.4, 0),
	} do
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(1, 1, 1)
		p.CFrame = root * CFrame.new(offset.X, offset.Y, offset.Z)
		p.Parent = character
	end
	return character
end
local function tierOf(odds)
	if odds < 1_000 then return 1 elseif odds < 100_000 then return 2 elseif odds < 10_000_000 then return 3 elseif odds < 1_000_000_000 then return 4 end
	return 5
end
local totals = {}
for _, gem in GemCatalog.List do
	local recipe = Recipes.Build(gem)
	if not recipe then
		print("MISSING recipe: " .. gem.Id)
		failures += 1
		continue
	end
	local signature = {}
	for _, spec in recipe do table.insert(signature, spec.Kind) end
	local model = Instance.new("Model")
	local root = CFrame.new(10, 70, -5) * CFrame.Angles(0, 0.7, 0)
	local placed = 0
	local ctx = {
		Parent = model, Color = gem.Color, Accent = gem.Accent, Seed = gem.Index, Ground = -3,
		Place = function(p, cf) p.CFrame = cf; placed += 1 end,
		Rng = Random.new(gem.Index * 7919 + 17),
		Character = dummy(root),
	}
	local updates = { Layers.Glow(ctx, { Range = 9, Brightness = 1 }) }
	for _, spec in recipe do
		local layer = Layers[spec.Kind]
		if not layer then
			print("UNKNOWN layer " .. tostring(spec.Kind) .. " in " .. gem.Id)
			failures += 1
		else
			local ok, update = pcall(layer, ctx, spec)
			if ok then table.insert(updates, update) else print(gem.Id .. " " .. spec.Kind .. ": " .. tostring(update)); failures += 1 end
		end
	end
	for _, t in { 0, 0.016, 0.5, 1.37, 7.9, 123.4 } do
		for _, update in updates do
			local ok, err = pcall(update, t, root)
			if not ok then print(gem.Id .. " update: " .. tostring(err)); failures += 1; break end
		end
	end
	local parts, beams = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if not d.CFrame then print(gem.Id .. ": a part is never placed"); failures += 1 end
		elseif d.ClassName == "Beam" then beams += 1 end
	end
	local tier = tierOf(gem.Odds)
	if parts > budget[tier] then
		print(string.format("OVER BUDGET %s: %d parts (tier %d allows %d)", gem.Id, parts, tier, budget[tier]))
		failures += 1
	end
	totals[tier] = totals[tier] or { n = 0, parts = 0, beams = 0, max = 0 }
	local tt = totals[tier]
	tt.n += 1; tt.parts += parts; tt.beams += beams; tt.max = math.max(tt.max, parts)
	if gem.Index % 10 == 0 or gem.Index >= 95 then
		print(string.format("%3d %-18s layers=%d parts=%d beams=%d  %s", gem.Index, gem.Id, #recipe, parts, beams, table.concat(signature, "+")))
	end
end
for tier = 1, 5 do
	local tt = totals[tier]
	if tt then print(string.format("tier %d: %d gems, avg %.0f parts / %.0f beams, max %d parts", tier, tt.n, tt.parts / tt.n, tt.beams / tt.n, tt.max)) end
end
for _, e in Stub.Errors do print("STUB: " .. e); failures += 1 end
print(if failures == 0 then "AURAS OK" else ("AURA FAILURES: " .. failures))
LUA
} > "$OUT.luau"
"$LUAU" "$OUT.luau"
