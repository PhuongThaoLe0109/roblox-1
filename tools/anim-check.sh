#!/usr/bin/env bash
# Offline checks for character animation and the flying broom, against
# tests/RobloxStub.luau:
#   * builds the broom (MovementService.BuildBroom): no errors, finite and
#     orthonormal CFrames, part count, it lies along the flight direction;
#   * plays every CombatAnim animation on an R15 and an R6 dummy (plus the
#     broom, airborne and landing layers, a held charge and a stun that cuts
#     an action short): every joint C0 stays finite and orthonormal, and every
#     joint is back at rest once the animation is over.
#   tools/anim-check.sh [path/to/luau]
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
	echo "local MovementConfig = (function()"
	cat src/shared/MovementConfig.luau
	echo "end)()"
	cat <<'LUA'
CFrame.fromEulerAnglesYXZ = CFrame.fromEulerAnglesYXZ or function(rx, ry, rz)
	return CFrame.Angles(0, ry, 0) * CFrame.Angles(rx, 0, 0) * CFrame.Angles(0, 0, rz)
end
local function clock() return Stub.Clock end
local realTypeof = typeof
typeof = function(v) if type(v) == "table" and rawget(v, "ClassName") then return "Instance" end return realTypeof(v) end
local renderFns = {}
local playersList = {}
local players = game:GetService("Players")
rawset(players, "GetPlayers", function() return playersList end)
rawset(players, "GetPlayerFromCharacter", function() return nil end)
rawset(players, "PlayerAdded", { Connect = function() end })
rawset(players, "PlayerRemoving", { Connect = function() end })
local runService = game:GetService("RunService")
rawset(runService, "RenderStepped", { Connect = function(_, fn) table.insert(renderFns, fn) end })
rawset(runService, "Heartbeat", { Connect = function() end })
local modules = {
	CombatConfig = CombatConfig,
	MovementConfig = MovementConfig,
	GemCatalog = { Get = function() return nil end },
	Remotes = { CreateCooldown = function() return function() return 0 end end },
}
local rs = game:GetService("ReplicatedStorage")
for _, name in { "CombatConfig", "MovementConfig", "GemCatalog" } do
	local m = Instance.new("ModuleScript"); m.Name = name; m.Parent = rs
end
local function fakeScript() return setmetatable({}, { __index = function(_, k) if k == "WaitForChild" then return function(_, name) return { Name = name } end end if k == "Parent" then return fakeScript() end end }) end
require = function(m) return modules[m.Name] end
LUA
	echo "local CombatAnim = (function()"
	sed 's/os\.clock()/clock()/g' src/client/Combat/CombatAnim.luau
	echo "end)()"
	echo "local MovementService = (function()"
	echo "local script = fakeScript()"
	sed 's/os\.clock()/clock()/g' src/server/Modules/MovementService.luau
	echo "end)()"
	cat <<'LUA'
local failures = 0
local function fail(msg) print("FAIL " .. msg); failures += 1 end

local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end
local function goodCFrame(c)
	for _, n in { c.P.X, c.P.Y, c.P.Z, c.R.X, c.U.Y, c.B.Z } do
		if not finite(n) then return false end
	end
	local r, u, b = c.R, c.U, c.B
	return math.abs(r.Magnitude - 1) < 1e-3 and math.abs(u.Magnitude - 1) < 1e-3 and math.abs(b.Magnitude - 1) < 1e-3
		and math.abs(r:Dot(u)) < 1e-3 and math.abs(r:Dot(b)) < 1e-3 and math.abs(u:Dot(b)) < 1e-3
end
local function same(a, b)
	return (a.P - b.P).Magnitude < 1e-3 and (a.R - b.R).Magnitude < 1e-3 and (a.U - b.U).Magnitude < 1e-3
end

local function part(model, name, size)
	local p = Instance.new("Part"); p.Name = name; p.Size = size; p.CFrame = CFrame.new(); p.Parent = model
	return p
end
local function motor(name, p0, p1, c0, c1, parent)
	local m = Instance.new("Motor6D"); m.Name = name; m.Part0 = p0; m.Part1 = p1; m.C0 = c0; m.C1 = c1 or CFrame.new(); m.Parent = parent
	return m
end
local function humanoid(c, rig)
	local h = Instance.new("Humanoid"); h.RigType = rig; h.HipHeight = 2; h.Health = 100; h.Parent = c
end
local function rig15()
	local c = Instance.new("Model")
	local hrp = part(c, "HumanoidRootPart", Vector3.new(2, 2, 1)); hrp.AssemblyLinearVelocity = Vector3.new()
	humanoid(c, Enum.HumanoidRigType.R15)
	local lt = part(c, "LowerTorso", Vector3.new(2, 0.4, 1))
	local ut = part(c, "UpperTorso", Vector3.new(2, 1.6, 1))
	local head = part(c, "Head", Vector3.new(1.2, 1.2, 1.2))
	motor("Root", hrp, lt, CFrame.new(0, -1, 0), nil, lt)
	motor("Waist", lt, ut, CFrame.new(0, 0.2, 0), nil, ut)
	motor("Neck", ut, head, CFrame.new(0, 0.8, 0), nil, head)
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local ua = part(c, side .. "UpperArm", Vector3.new(1, 1.2, 1))
		local la = part(c, side .. "LowerArm", Vector3.new(1, 1.1, 1))
		local hand = part(c, side .. "Hand", Vector3.new(1, 0.3, 1))
		motor(side .. "Shoulder", ut, ua, CFrame.new(s, 0.55, 0), nil, ua)
		motor(side .. "Elbow", ua, la, CFrame.new(0, -0.45, 0), nil, la)
		motor(side .. "Wrist", la, hand, CFrame.new(0, -0.5, 0), nil, hand)
		local ul = part(c, side .. "UpperLeg", Vector3.new(1, 1.2, 1))
		local ll = part(c, side .. "LowerLeg", Vector3.new(1, 1.2, 1))
		motor(side .. "Hip", lt, ul, CFrame.new(s * 0.5, -0.2, 0), nil, ul)
		motor(side .. "Knee", ul, ll, CFrame.new(0, -0.6, 0), nil, ll)
	end
	return c
end
local R6ROT = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local SR = CFrame.new(0, 0, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local SL = CFrame.new(0, 0, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
local function rig6()
	local c = Instance.new("Model")
	local hrp = part(c, "HumanoidRootPart", Vector3.new(2, 2, 1)); hrp.AssemblyLinearVelocity = Vector3.new()
	humanoid(c, Enum.HumanoidRigType.R6)
	local torso = part(c, "Torso", Vector3.new(2, 2, 1))
	local head = part(c, "Head", Vector3.new(1.2, 1, 1))
	motor("RootJoint", hrp, torso, R6ROT, R6ROT, hrp)
	motor("Neck", torso, head, CFrame.new(0, 1, 0) * R6ROT, nil, torso)
	for _, spec in { { "Right Shoulder", "Right Arm", CFrame.new(1, 0.5, 0) * SR }, { "Left Shoulder", "Left Arm", CFrame.new(-1, 0.5, 0) * SL },
		{ "Right Hip", "Right Leg", CFrame.new(1, -1, 0) * SR }, { "Left Hip", "Left Leg", CFrame.new(-1, -1, 0) * SL } } do
		local limb = part(c, spec[2], Vector3.new(1, 2, 1))
		motor(spec[1], torso, limb, spec[3], nil, torso)
	end
	return c
end

local function motors(c)
	local list = {}
	for _, d in c:GetDescendants() do
		if d.ClassName == "Motor6D" then table.insert(list, d) end
	end
	return list
end

-- Steps every rig `seconds` at 60 fps, checking every joint each frame.
local function step(chars, seconds, label)
	playersList = {}
	for _, c in chars do table.insert(playersList, { Character = c }) end
	for _ = 1, math.floor(seconds * 60 + 0.5) do
		Stub.Clock += 1 / 60
		for _, fn in renderFns do fn(1 / 60) end
		for _, c in chars do
			for _, m in motors(c) do
				if not goodCFrame(m.C0) then
					fail(label .. ": " .. m.Name .. ".C0 is not finite / orthonormal")
					return
				end
			end
		end
	end
end
local function rest(c, base, label)
	for m, c0 in base do
		if not same(m.C0, c0) then
			fail(label .. ": " .. m.Name .. " did not return to rest")
			return
		end
	end
end
local function snapshot(c)
	local base = {}
	for _, m in motors(c) do base[m] = m.C0 end
	return base
end

CombatAnim.Start()

-- Every animation on both rigs.
local names = CombatAnim.List()
for _, rigName in { "R15", "R6" } do
	local c = if rigName == "R15" then rig15() else rig6()
	local base = snapshot(c)
	for _, name in names do
		CombatAnim.Play(c, name)
		step({ c }, 3, rigName .. " " .. name)
		rest(c, base, rigName .. " " .. name)
	end
	-- Held charge: still posed while held, released afterwards.
	CombatAnim.Play(c, "NovaCharge", 1.5)
	step({ c }, 1.2, rigName .. " hold")
	if same(c:FindFirstChild(if rigName == "R15" then "RightUpperArm" else "Torso"):FindFirstChild(if rigName == "R15" then "RightShoulder" else "Right Shoulder").C0, base[c:FindFirstChild(if rigName == "R15" then "RightUpperArm" else "Torso"):FindFirstChild(if rigName == "R15" then "RightShoulder" else "Right Shoulder")]) then
		fail(rigName .. " hold: the charge pose is not held")
	end
	step({ c }, 3, rigName .. " hold release")
	rest(c, base, rigName .. " hold release")
	-- A stun cuts an action short.
	CombatAnim.Play(c, "Domain")
	step({ c }, 0.3, rigName .. " stun")
	c:SetAttribute(CombatConfig.Status.StunnedUntil, Stub.Clock + 5)
	step({ c }, 0.6, rigName .. " stun")
	rest(c, base, rigName .. " stun")
	c:SetAttribute(CombatConfig.Status.StunnedUntil, 0)
	-- Movement layers: broom seat, airborne, landing.
	c:SetAttribute(MovementConfig.BroomAttribute, true)
	step({ c }, 1, rigName .. " broom")
	c:SetAttribute(MovementConfig.BroomAttribute, false)
	Stub.Airborne = true
	c.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, -45, 0)
	step({ c }, 0.8, rigName .. " fall")
	Stub.Airborne = false
	c.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new()
	step({ c }, 2, rigName .. " land")
	rest(c, base, rigName .. " movement layers")
	print(string.format("%s: %d animations, hold, stun, broom, fall, land OK", rigName, #names))
end

-- The broom.
local before = #Stub.Errors
local c = rig15()
local ok, broom = pcall(MovementService.BuildBroom, c, c.HumanoidRootPart, Color3.new(1, 0.4, 0.7), Color3.new(0.5, 0.8, 1))
if not ok or not broom then
	fail("broom: " .. tostring(broom))
else
	local parts, front, back = 0, math.huge, -math.huge
	for _, d in broom:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			front = math.min(front, d.CFrame.Z)
			back = math.max(back, d.CFrame.Z)
		end
	end
	print(string.format("broom: %d parts, from z=%.1f (tip) to z=%.1f (bristles)", parts, front, back))
	if parts > 60 then fail("broom has too many parts") end
	if front > -4 or back < 4 then fail("broom does not lie along the flight direction") end
end
if #Stub.Errors > before then
	for i = before + 1, #Stub.Errors do fail(Stub.Errors[i]) end
end

-- The guard must allow what the broom can do.
local b = MovementConfig.Broom
if b.Speed <= MovementConfig.WalkSpeed then fail("broom is not faster than running") end
if MovementConfig.WalkSpeed < 29 then fail("running speed below the old sprint speed") end

if failures > 0 then
	error(failures .. " ANIM CHECK FAILURES")
end
print("ANIM OK")
LUA
} > "$OUT"
"$LUAU" "$OUT"
