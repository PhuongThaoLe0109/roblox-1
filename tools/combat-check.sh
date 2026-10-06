#!/usr/bin/env bash
# Builds every crystal beast (BeastService) and every melee weapon
# (WeaponBuilder) offline against tests/RobloxStub.luau: no runtime errors,
# finite and orthonormal CFrames, sane part sizes, and part counts.
# Also runs tools/kit-check.sh for the 100 gem kits.
#   tools/combat-check.sh [path/to/luau]
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU="${1:-luau}"
OUT="$(mktemp)"
{
	echo "local Stub = (function()"
	cat tests/RobloxStub.luau
	echo "end)()"
	echo "local CombatConfig = (function()"
	cat src/shared/CombatConfig.luau
	echo "end)()"
	echo 'local CombatServiceStub = { FX = function() end, ColorsOf = function() return Color3.new(1, 0.5, 0.8), Color3.new(0.5, 0.8, 1) end, Extend = function() end, Now = function() return 0 end }'
	echo 'local modules = { CombatConfig = CombatConfig, CombatService = CombatServiceStub }'
	echo 'local function fakeScript() return setmetatable({}, { __index = function(_, k) if k == "WaitForChild" then return function(_, name) return { Name = name } end end if k == "Parent" then return fakeScript() end end }) end'
	echo 'require = function(m) return modules[m.Name] end'
	echo 'local rsModule = Instance.new("ModuleScript"); rsModule.Name = "CombatConfig"; rsModule.Parent = game:GetService("ReplicatedStorage")'
	echo "local BeastModels = (function()"
	cat src/server/Modules/Combat/BeastModels.luau
	echo "end)()"
	echo "modules.BeastModels = BeastModels"
	echo "local BeastService = (function()"
	echo "local script = fakeScript()"
	cat src/server/Modules/Combat/BeastService.luau
	echo "end)()"
	echo "local WeaponBuilder = (function()"
	cat src/server/Modules/Combat/WeaponBuilder.luau
	echo "end)()"
	cat <<'LUA'
local failures = 0
local beasts = { "PrismGolem", "PyreWyrm", "GlacierStag", "UmbralMaw", "ThunderRoc", "DreamMoth", "SolarLion", "StarKoi" }
for _, kind in beasts do
	local before = #Stub.Errors
	local ok, model = pcall(BeastService.Build, kind, Color3.new(1, 0.4, 0.6), Color3.new(0.4, 0.8, 1), 1.6, nil, 3)
	if not ok or not model then
		print("FAIL beast " .. kind .. ": " .. tostring(model))
		failures += 1
	else
		local parts, joints, top = 0, {}, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				top = math.max(top, d.CFrame.Y + d.Size.Y / 2)
			elseif d.ClassName == "Weld" and d.Name ~= "Weld" then
				table.insert(joints, d.Name)
			end
		end
		table.sort(joints)
		print(string.format("beast %-12s parts=%3d height=%5.1f joints=%s", kind, parts, top, table.concat(joints, ",")))
		if #Stub.Errors > before then failures += #Stub.Errors - before end
	end
end
local function character()
	local c = Instance.new("Model")
	for _, name in { "RightHand", "LeftHand" } do
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(1, 0.3, 1)
		p.CFrame = CFrame.new(if name == "RightHand" then 1.5 else -1.5, 1, 0)
		p.Parent = c
	end
	return c
end
for _, style in { "Blade", "Greatsword", "Daggers", "Gauntlets", "Spear", "Scythe", "Hammer", "Whip", "Fans" } do
	local before = #Stub.Errors
	local c = character()
	local ok, weapon = pcall(WeaponBuilder.Build, c, style, Color3.new(1, 0.4, 0.6), Color3.new(0.4, 0.8, 1))
	if not ok or not weapon then
		print("FAIL weapon " .. style .. ": " .. tostring(weapon))
		failures += 1
	else
		local parts, trail = 0, false
		for _, d in weapon:GetDescendants() do
			if d:IsA("BasePart") then parts += 1 end
			if d.Name == "SwingTrail" then trail = true end
		end
		if not trail or not weapon:FindFirstChild("Handle") then
			print("FAIL weapon " .. style .. " has no Handle/SwingTrail")
			failures += 1
		end
		print(string.format("weapon %-10s parts=%d", style, parts))
		if #Stub.Errors > before then failures += #Stub.Errors - before end
	end
end
for _, e in Stub.Errors do print("STUB: " .. e) end
print(if failures == 0 then "COMBAT MODELS OK" else ("COMBAT FAILURES: " .. failures))
LUA
} > "$OUT.luau"
"$LUAU" "$OUT.luau"
tools/kit-check.sh "$LUAU" | tail -1
