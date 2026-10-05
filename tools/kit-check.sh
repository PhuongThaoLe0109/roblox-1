#!/usr/bin/env bash
# Checks every gem's combat kit (src/shared/GemKits.luau): skill counts by
# rarity, unique skill names and keys, known archetypes / melee styles /
# beasts, filled-in descriptions. Prints a sample of kits.
#   tools/kit-check.sh [path/to/luau]
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
	echo 'local realRequire = require'
	echo 'require = function() return GemCatalog end'
	echo "local GemKits = (function()"
	cat src/shared/GemKits.luau
	echo "end)()"
	cat <<'LUA'
local failures = 0
local function fail(msg) print("FAIL " .. msg); failures += 1 end
local expected = function(i) if i <= 16 then return 1 elseif i <= 31 then return 2 elseif i <= 46 then return 3 end return 4 end
local archetypeUse = {}
for _, gem in GemCatalog.List do
	local kit = GemKits.ForGem(gem)
	if #kit.Skills ~= expected(gem.Index) then fail(gem.Id .. " has " .. #kit.Skills .. " skills") end
	if (kit.Ultimate ~= nil) ~= (gem.Index >= 61) then fail(gem.Id .. " ultimate mismatch") end
	if (kit.Domain ~= nil) ~= (gem.Index >= 81) then fail(gem.Id .. " domain mismatch") end
	if kit.Domain and kit.Domain.Description:find("{") then fail(gem.Id .. " unfilled domain text") end
	if gem.Index >= 32 and kit.Melee.Id == "Blade" then fail(gem.Id .. " should have its own melee") end
	if not GemKits.Melee[kit.Melee.Id] then fail(gem.Id .. " unknown melee") end
	local names, keys = {}, {}
	for slot, skill in kit.Skills do
		if not GemKits.Archetypes[skill.Archetype] then fail(gem.Id .. " unknown archetype " .. tostring(skill.Archetype)) end
		if names[skill.Name] then fail(gem.Id .. " duplicate name " .. skill.Name) end
		if keys[skill.Key] then fail(gem.Id .. " duplicate key " .. skill.Key) end
		if skill.Key ~= GemKits.SkillKeys[slot] then fail(gem.Id .. " key order") end
		if skill.Description:find("{") then fail(gem.Id .. " unfilled description: " .. skill.Description) end
		names[skill.Name] = true; keys[skill.Key] = true
		archetypeUse[skill.Archetype] = (archetypeUse[skill.Archetype] or 0) + 1
	end
	if slot == 1 then end
	if kit.Skills[1].Archetype == "Shield" or kit.Skills[1].Archetype == "Blink" then fail(gem.Id .. " first skill is utility") end
	if kit.Ultimate then
		if not GemKits.Beasts[kit.Ultimate.Beast] then fail(gem.Id .. " unknown beast") end
		if kit.Ultimate.Description:find("{") then fail(gem.Id .. " unfilled ultimate text") end
	end
	if gem.Index == 1 or gem.Index == 20 or gem.Index == 40 or gem.Index == 55 or gem.Index == 70 or gem.Index == 100 then
		local parts = {}
		for _, s in kit.Skills do table.insert(parts, s.Key .. "=" .. s.Name .. "(" .. s.Archetype .. ")") end
		print(string.format("%3d %-16s %-5s x%.2f  %-17s %s%s%s", gem.Index, gem.Id, kit.Element, kit.Power, kit.Melee.Name, table.concat(parts, " "), kit.Ultimate and ("  G=" .. kit.Ultimate.Name) or "", kit.Domain and ("  T=" .. kit.Domain.Name) or ""))
	end
end
local usage = {}
for a, n in archetypeUse do table.insert(usage, a .. "=" .. n) end
table.sort(usage)
print("archetype use: " .. table.concat(usage, " "))
for a in GemKits.Archetypes do if a ~= "Transform" and a ~= "Domain" and not archetypeUse[a] then fail("archetype never used: " .. a) end end
print(if failures == 0 then "KITS OK" else ("KIT FAILURES: " .. failures))
LUA
} > "$OUT.luau"
"$LUAU" "$OUT.luau"
