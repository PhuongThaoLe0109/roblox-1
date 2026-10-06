-- BeastFX
-- Brings the crystal beasts (BeastService / BeastModels) to life on every
-- client by posing their bone welds each frame:
--   * locomotion that follows how fast the beast moves: a trot that becomes a
--     gallop for the lion, wolf and stag, a heavy stride for the golem, wing
--     beats for the roc and moth, a swimming undulation for the wyrm and koi;
--   * breathing, tail sway and head motion while idle;
--   * a roar when the transformation completes;
--   * three attacks per creature for the beast maul combo (claw swipes and a
--     pounce, bites, antler sweeps and a rearing stomp, haymakers and a
--     double-fist smash, wing buffets, tail slaps, a lunging bite ...).
-- Only Weld.C0 values are changed, locally, so animation costs no network.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local BeastFX = {}

type Joint = { Weld: Weld, Base: CFrame }
type Beast = {
	Model: Model,
	Kind: string,
	Joints: { [string]: Joint },
	Mount: Joint?,
	Root: BasePart?,
	Gait: number, -- accumulated stride phase
	Move: number, -- smoothed 0 (still) .. 1 (full run)
	Born: number,
	Attack: { Combo: number, Start: number, Duration: number }?,
	Seed: number,
	Parts: { BasePart }, -- the biggest visible parts (for the shatter)
	Snapshot: { { CFrame: CFrame, Size: Vector3, Color: Color3, Material: Enum.Material, Transparency: number } }?,
	SnapshotAt: number,
}

local beasts: { [Model]: Beast } = {}

local RUN_SPEED = 30
local MAX_SHARDS = 40 -- pieces thrown out when a beast form ends

local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function track(model: Instance)
	if not model:IsA("Model") or beasts[model] then
		return
	end
	local joints = {}
	local mount = nil
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") then
			if d.Name == "Mount" then
				mount = { Weld = d, Base = d.C0 }
			elseif d.Name ~= "Weld" then
				joints[d.Name] = { Weld = d, Base = d.C0 }
			end
		end
	end
	local character = model.Parent
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.9 then
			table.insert(parts, d)
		end
	end
	table.sort(parts, function(a, b)
		return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z
	end)
	for i = #parts, MAX_SHARDS + 1, -1 do
		parts[i] = nil
	end
	beasts[model] = {
		Model = model,
		Kind = model:GetAttribute("Kind") or "",
		Joints = joints,
		Mount = mount,
		Root = if root and root:IsA("BasePart") then root else nil,
		Gait = 0,
		Move = 0,
		Born = os.clock(),
		Attack = nil,
		Seed = math.random() * 10,
		Parts = parts,
		Snapshot = nil,
		SnapshotAt = 0,
	}
end

-- When the form ends, the beast bursts apart: copies of its biggest pieces
-- fly outward spinning, shrink and fade (from the last snapshot, since the
-- model itself is already gone).
local fragments: Folder? = nil
local function shatter(b: Beast)
	local snapshot = b.Snapshot
	if not snapshot or #snapshot == 0 then
		return
	end
	if not fragments or not fragments.Parent then
		local f = Instance.new("Folder")
		f.Name = "BeastShatter"
		f.Parent = workspace
		fragments = f
	end
	local center = Vector3.zero
	for _, item in snapshot do
		center += item.CFrame.Position
	end
	center /= #snapshot
	local pieces = {}
	for _, item in snapshot do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = item.Size
		p.CFrame = item.CFrame
		p.Color = item.Color
		p.Material = item.Material
		p.Transparency = item.Transparency
		p.Parent = fragments
		local out = item.CFrame.Position - center
		out = if out.Magnitude > 1e-3 then out.Unit else Vector3.yAxis
		table.insert(pieces, {
			Part = p,
			From = item.CFrame,
			Size = item.Size,
			Base = item.Transparency,
			Velocity = out * (16 + math.random() * 22) + Vector3.new(0, 10 + math.random() * 14, 0),
			Spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14,
		})
	end
	local started = os.clock()
	local life = 0.85
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		local a = math.min(1, t / life)
		for _, piece in pieces do
			local pos = piece.From.Position + piece.Velocity * t + Vector3.new(0, -30 * t * t, 0)
			local rot = CFrame.Angles(piece.Spin.X * t, piece.Spin.Y * t, piece.Spin.Z * t)
			piece.Part.CFrame = CFrame.new(pos) * (piece.From - piece.From.Position) * rot
			piece.Part.Size = piece.Size * (1 - 0.7 * a)
			piece.Part.Transparency = piece.Base + (1 - piece.Base) * a ^ 1.5
		end
		if a >= 1 then
			connection:Disconnect()
			for _, piece in pieces do
				piece.Part:Destroy()
			end
		end
	end)
end

local function vanish(model: Model)
	local b = beasts[model]
	if b then
		beasts[model] = nil
		shatter(b)
	end
end

-- Pose accumulator: degrees per bone (x = pitch, y = yaw, z = roll).
type Pose = { [string]: Vector3 }

local function add(pose: Pose, bone: string, x: number, y: number?, z: number?)
	local v = pose[bone] or Vector3.zero
	pose[bone] = v + Vector3.new(x, y or 0, z or 0)
end

-- Attack envelope: wind-up then strike.
local function envelope(b: Beast, now: number): (number, number, number)
	local attack = b.Attack
	if not attack then
		return 0, 0, 0
	end
	local a = (now - attack.Start) / attack.Duration
	if a >= 1 then
		b.Attack = nil
		return 0, 0, 0
	end
	local wind = smooth(0, 0.3, a) * (1 - smooth(0.3, 0.45, a))
	local strike = smooth(0.28, 0.45, a) * (1 - smooth(0.6, 1, a))
	return wind, strike, attack.Combo
end

local function roarAmount(b: Beast, now: number): number
	local a = (now - b.Born) / 1.6
	if a >= 1 then
		return 0
	end
	return smooth(0, 0.25, a) * (1 - smooth(0.7, 1, a))
end

--------------------------------------------------------------------------------
-- Creature motion
--------------------------------------------------------------------------------

local LEG_PHASE = { FL = 0, BR = 0, FR = math.pi, BL = math.pi }

local function quadruped(b: Beast, pose: Pose, t: number, now: number): Vector3
	local m = b.Move
	local p = b.Gait
	local amp = 8 + 30 * m
	local knee = 6 + 40 * m
	for leg, offset in LEG_PHASE do
		local s = math.sin(p + offset)
		add(pose, leg .. "Upper", s * amp)
		add(pose, leg .. "Lower", -math.max(0, -math.cos(p + offset)) * knee)
		add(pose, leg .. "Paw", -s * amp * 0.45)
	end
	-- Spine flex, breathing, head steady against the bob
	add(pose, "Hips", math.sin(p * 2) * 2.5 * m)
	add(pose, "Chest", -math.sin(p * 2) * 2.5 * m + math.sin(t * 1.6) * 1.2)
	add(pose, "Neck", math.sin(p * 2) * 3 * m + math.sin(t * 0.9) * 2, math.sin(t * 0.5) * 6 * (1 - m))
	add(pose, "Head", -math.sin(p * 2) * 3 * m, math.sin(t * 0.7 + 1) * 8 * (1 - m))
	for i = 1, 5 do
		add(pose, "Tail" .. i, -4 + math.sin(t * 1.3 + i) * 3, math.sin(t * (2 + m * 4) - i * 0.6) * (7 + 12 * m))
	end

	-- Roar
	local roar = roarAmount(b, now)
	add(pose, "Neck", 22 * roar)
	add(pose, "Head", 20 * roar)
	add(pose, "Jaw", -38 * roar)
	add(pose, "Chest", 6 * roar)

	-- Attacks
	local wind, strike, combo = envelope(b, now)
	local bob = math.abs(math.sin(p)) * 0.35 * m
	local lift = 0
	if wind + strike > 0 then
		if b.Kind == "GlacierStag" then
			if combo == 3 then
				-- Rear up, then stamp down.
				add(pose, "Chest", 32 * wind - 14 * strike)
				add(pose, "Hips", -10 * wind)
				for _, leg in { "FL", "FR" } do
					add(pose, leg .. "Upper", 55 * wind - 25 * strike)
					add(pose, leg .. "Lower", -60 * wind)
				end
				add(pose, "Neck", -10 * wind - 18 * strike)
				lift = 1.6 * wind
			else
				-- Antler sweep
				local side = if combo == 1 then 1 else -1
				add(pose, "Neck", -12 * wind - 20 * strike, side * (-30 * wind + 40 * strike))
				add(pose, "Head", 10 * wind - 25 * strike, side * (-20 * wind + 30 * strike), side * 15 * strike)
				add(pose, "Chest", 0, side * (-8 * wind + 10 * strike))
			end
		elseif b.Kind == "UmbralMaw" and combo ~= 3 then
			-- Snapping bite (1) and a raking claw (2)
			if combo == 1 then
				add(pose, "Neck", 8 * wind - 20 * strike)
				add(pose, "Head", 15 * wind - 15 * strike)
				add(pose, "Jaw", -45 * wind)
				add(pose, "Chest", -6 * wind + 8 * strike)
			else
				add(pose, "FLUpper", -35 * wind + 75 * strike, 0, -15 * strike)
				add(pose, "FLLower", -40 * wind)
				add(pose, "Chest", 8 * wind, 10 * wind - 14 * strike)
				add(pose, "Jaw", -25 * strike)
			end
		elseif combo == 3 then
			-- Pounce: rear up, spring forward and slam both paws down.
			add(pose, "Hips", -10 * wind + 10 * strike)
			add(pose, "Chest", 24 * wind - 26 * strike)
			for _, leg in { "FL", "FR" } do
				add(pose, leg .. "Upper", 60 * wind + 48 * strike)
				add(pose, leg .. "Lower", -60 * wind + 15 * strike)
				add(pose, leg .. "Paw", -20 * strike)
			end
			for _, leg in { "BL", "BR" } do
				add(pose, leg .. "Upper", -18 * wind - 30 * strike)
				add(pose, leg .. "Lower", -20 * strike)
			end
			add(pose, "Neck", -8 * wind - 10 * strike)
			add(pose, "Head", 10 * strike)
			add(pose, "Jaw", -42 * (wind + strike) * 0.8)
			lift = 2.2 * wind + 0.6 * strike
		else
			-- Claw swipe with one forepaw.
			local leg = if combo == 1 then "FR" else "FL"
			local side = if combo == 1 then 1 else -1
			add(pose, leg .. "Upper", -40 * wind + 80 * strike, 0, side * 20 * strike)
			add(pose, leg .. "Lower", -50 * wind + 10 * strike)
			add(pose, "Chest", 10 * wind - 4 * strike, side * (-12 * wind + 16 * strike))
			add(pose, "Neck", 6 * strike, side * 10 * strike)
			add(pose, "Jaw", -28 * strike)
		end
	end
	return Vector3.new(0, bob + lift, 0)
end

local function golem(b: Beast, pose: Pose, t: number, now: number): Vector3
	local m = b.Move
	local p = b.Gait
	local amp = 6 + 26 * m
	for _, side in { "L", "R" } do
		local offset = if side == "L" then 0 else math.pi
		local s = math.sin(p + offset)
		add(pose, "Thigh" .. side, s * amp)
		add(pose, "Shin" .. side, -math.max(0, -math.cos(p + offset)) * (10 + 35 * m))
		add(pose, "Foot" .. side, -s * amp * 0.4)
		-- Arms swing against the legs; knuckles drag a little when idle.
		add(pose, "Arm" .. side, -s * amp * 0.7 + math.sin(t * 1.1 + offset) * 2)
		add(pose, "Fore" .. side, 10 + math.max(0, s) * 15 * m)
	end
	add(pose, "Chest", math.sin(t * 1.3) * 1.5, math.sin(p) * 5 * m)
	add(pose, "Head", math.sin(t * 0.8) * 2, math.sin(t * 0.4) * 10 * (1 - m))
	local roar = roarAmount(b, now)
	add(pose, "Chest", -10 * roar)
	add(pose, "Head", 25 * roar)
	add(pose, "ArmL", 0, 0, -50 * roar)
	add(pose, "ArmR", 0, 0, 50 * roar)

	local wind, strike, combo = envelope(b, now)
	if wind + strike > 0 then
		if combo == 3 then
			-- Both fists raised overhead, then brought down.
			for _, side in { "L", "R" } do
				add(pose, "Arm" .. side, 160 * wind + 45 * strike)
				add(pose, "Fore" .. side, 30 * wind + 10 * strike)
			end
			add(pose, "Chest", 10 * wind - 24 * strike)
			add(pose, "Head", -15 * strike)
		else
			local side = if combo == 1 then "R" else "L"
			local sign = if combo == 1 then 1 else -1
			add(pose, "Arm" .. side, -30 * wind + 95 * strike, 0, sign * 10 * strike)
			add(pose, "Fore" .. side, 50 * wind - 30 * strike)
			add(pose, "Chest", 0, sign * (25 * wind - 35 * strike))
		end
	end
	return Vector3.new(0, math.abs(math.sin(p)) * 0.4 * m - 0.6 * strike, 0)
end

-- Wing helpers: `side` -1 for the left wing (extends -X), +1 for the right.
local function wing(pose: Pose, bone: string, side: number, sweepBack: number, up: number)
	add(pose, bone, 0, -side * sweepBack, side * up)
end

local function roc(b: Beast, pose: Pose, t: number, now: number): Vector3
	local m = b.Move
	local p = b.Gait
	local flap = math.sin(t * (2 + 5 * m))
	for _, sideName in { "L", "R" } do
		local side = if sideName == "L" then -1 else 1
		-- Folded along the body when still, beating when on the move.
		wing(pose, "Wing" .. sideName, side, 55 * (1 - m) + 10, -15 * (1 - m) + flap * 38 * m)
		wing(pose, "WingMid" .. sideName, side, 35 * (1 - m), flap * 15 * m)
		wing(pose, "WingTip" .. sideName, side, 30 * (1 - m), flap * 12 * m)
		local offset = if sideName == "L" then 0 else math.pi
		add(pose, "Thigh" .. sideName, math.sin(p + offset) * (8 + 20 * m))
		add(pose, "Foot" .. sideName, -math.max(0, math.sin(p + offset)) * 25 * m)
	end
	add(pose, "Neck", math.sin(t * 1.4) * 4, math.sin(t * 0.6) * 12)
	add(pose, "Head", -math.sin(t * 1.4) * 4, math.sin(t * 0.9) * 10)
	add(pose, "Tail1", math.sin(t * 2) * 4, math.sin(t * 1.5) * 6)
	local roar = roarAmount(b, now)
	add(pose, "Neck", 25 * roar)
	add(pose, "Head", 15 * roar)
	for _, sideName in { "L", "R" } do
		local side = if sideName == "L" then -1 else 1
		wing(pose, "Wing" .. sideName, side, -55 * roar, 45 * roar)
	end

	local wind, strike, combo = envelope(b, now)
	if wind + strike > 0 then
		if combo == 3 then
			-- Wings clap forward and the talons kick.
			for _, sideName in { "L", "R" } do
				local side = if sideName == "L" then -1 else 1
				wing(pose, "Wing" .. sideName, side, -40 * wind - 70 * strike, 60 * wind - 30 * strike)
				add(pose, "Thigh" .. sideName, -30 * wind + 70 * strike)
			end
			add(pose, "Chest", -15 * wind + 10 * strike)
		else
			local sideName = if combo == 1 then "R" else "L"
			local side = if combo == 1 then 1 else -1
			wing(pose, "Wing" .. sideName, side, -30 * wind - 80 * strike, 70 * wind - 40 * strike)
			add(pose, "Chest", 0, side * (-15 * wind + 20 * strike))
			add(pose, "Neck", -10 * strike)
		end
	end
	return Vector3.new(0, math.abs(flap) * 0.6 * m, 0)
end

local function moth(b: Beast, pose: Pose, t: number, now: number): Vector3
	local beat = math.sin(t * 9)
	local roar = roarAmount(b, now)
	local wind, strike, combo = envelope(b, now)
	for _, sideName in { "L", "R" } do
		local side = if sideName == "L" then -1 else 1
		local attackSweep = 0
		if wind + strike > 0 and (combo == 3 or (combo == 1) == (sideName == "R")) then
			attackSweep = -45 * wind - 70 * strike
		end
		wing(pose, "Wing" .. sideName, side, attackSweep - 20 * roar, beat * 32 + 10 + 30 * roar)
		wing(pose, "HindWing" .. sideName, side, attackSweep * 0.5, math.sin(t * 9 - 0.6) * 24)
	end
	add(pose, "Head", math.sin(t * 1.3) * 5, math.sin(t * 0.7) * 10)
	add(pose, "Tail1", math.sin(t * 2.2) * 6 - 6 * strike)
	add(pose, "Chest", -10 * strike + 8 * wind)
	return Vector3.new(0, math.sin(t * 2) * 0.6 + beat * 0.15, 0)
end

local function wyrm(b: Beast, pose: Pose, t: number, now: number): Vector3
	local m = b.Move
	local wind, strike, combo = envelope(b, now)
	for i = 1, 8 do
		add(pose, "Spine" .. i, math.sin(t * 1.2 - i * 0.4) * 2.5, math.sin(t * (1.6 + m * 2) - i * 0.55) * (5 + 4 * m))
	end
	for i = 1, 4 do
		add(pose, "Tail" .. i, 0, math.sin(t * 2 - i * 0.7) * (10 + 10 * m))
	end
	for _, sideName in { "L", "R" } do
		local side = if sideName == "L" then -1 else 1
		wing(pose, "Wing" .. sideName, side, 10, math.sin(t * (1.8 + 3 * m)) * (14 + 16 * m))
		wing(pose, "WingTip" .. sideName, side, 0, math.sin(t * (1.8 + 3 * m) - 0.5) * 10)
	end
	add(pose, "Head", math.sin(t * 0.9) * 4, math.sin(t * 0.6) * 10)
	local roar = roarAmount(b, now)
	add(pose, "Spine8", -15 * roar)
	add(pose, "Head", 25 * roar)
	add(pose, "Jaw", -40 * roar)
	if wind + strike > 0 then
		if combo == 2 then
			-- Tail whip
			for i = 1, 4 do
				add(pose, "Tail" .. i, 0, (40 * wind - 70 * strike) * (i / 4))
			end
			for i = 1, 4 do
				add(pose, "Spine" .. i, 0, -15 * wind + 15 * strike)
			end
		else
			-- Rear back and lunge to bite (3: a heavier slam down).
			local heavy = if combo == 3 then 1.5 else 1
			for i = 5, 8 do
				add(pose, "Spine" .. i, (-14 * wind + 22 * strike) * heavy)
			end
			add(pose, "Head", 18 * wind - 12 * strike)
			add(pose, "Jaw", -45 * wind)
		end
	end
	return Vector3.zero
end

local function koi(b: Beast, pose: Pose, t: number, now: number): (Vector3, number)
	local m = b.Move
	local wind, strike, combo = envelope(b, now)
	local rate = 2.4 + 3 * m
	for i = 1, 7 do
		add(pose, "Body" .. i, math.sin(t * 1.1 - i * 0.5) * 2, math.sin(t * rate - i * 0.7) * (4 + 6 * m) * (0.4 + i * 0.12))
	end
	add(pose, "Tail1", 0, math.sin(t * rate - 5) * (14 + 12 * m))
	add(pose, "Tail2", math.sin(t * 1.7) * 6, math.sin(t * rate - 5.8) * (18 + 14 * m))
	for _, sideName in { "L", "R" } do
		local side = if sideName == "L" then -1 else 1
		add(pose, "Fin" .. sideName, 0, side * math.sin(t * 4) * 20, side * math.sin(t * 3) * 15)
	end
	add(pose, "Head", math.sin(t * 0.8) * 3, 0)
	local spin = 0
	if wind + strike > 0 then
		if combo == 3 then
			spin = 360 * smooth(0.3, 0.65, (now - (b.Attack :: any).Start) / (b.Attack :: any).Duration)
		else
			local side = if combo == 1 then 1 else -1
			for i = 3, 7 do
				add(pose, "Body" .. i, 0, side * (25 * wind - 45 * strike))
			end
			add(pose, "Tail1", 0, side * (30 * wind - 60 * strike))
		end
	end
	return Vector3.new(0, math.sin(t * 1.5) * 0.5, 0), spin
end

local ANIMATORS = {
	SolarLion = quadruped,
	UmbralMaw = quadruped,
	GlacierStag = quadruped,
	PrismGolem = golem,
	ThunderRoc = roc,
	DreamMoth = moth,
	PyreWyrm = wyrm,
	StarKoi = koi,
}

local GAIT_RATE = {
	SolarLion = 1,
	UmbralMaw = 1.15,
	GlacierStag = 0.9,
	PrismGolem = 0.7,
	ThunderRoc = 1.2,
}

local function step(dt: number)
	local now = os.clock()
	for model, b in beasts do
		if model.Parent == nil then
			vanish(model)
			continue
		end
		-- Keep a light snapshot of the body for the shatter.
		if now >= b.SnapshotAt then
			b.SnapshotAt = now + 0.2
			local snapshot = {}
			for _, p in b.Parts do
				if p.Parent then
					table.insert(snapshot, { CFrame = p.CFrame, Size = p.Size, Color = p.Color, Material = p.Material, Transparency = p.Transparency })
				end
			end
			b.Snapshot = snapshot
		end
		local speed = 0
		if b.Root and b.Root.Parent then
			local v = b.Root.AssemblyLinearVelocity
			speed = Vector3.new(v.X, 0, v.Z).Magnitude
		end
		local target = math.clamp(speed / RUN_SPEED, 0, 1)
		b.Move += (target - b.Move) * math.min(1, dt * 6)
		b.Gait += dt * (2.2 + b.Move * 9) * (GAIT_RATE[b.Kind] or 1)
		local t = now + b.Seed

		local pose: Pose = {}
		local animate = ANIMATORS[b.Kind]
		local offset, spin = Vector3.zero, 0
		if animate then
			local o, s = (animate :: any)(b, pose, t, now)
			offset, spin = o or Vector3.zero, s or 0
		end
		for name, joint in b.Joints do
			local r = pose[name]
			joint.Weld.C0 = if r then joint.Base * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z)) else joint.Base
		end
		if b.Mount then
			b.Mount.Weld.C0 = b.Mount.Base * CFrame.new(offset) * CFrame.Angles(0, math.rad(spin), 0)
		end
	end
end

-- Plays the beast maul attack `combo` (1-3) on a character's beast.
function BeastFX.Attack(character: Instance, combo: number)
	if typeof(character) ~= "Instance" then
		return
	end
	local model = character:FindFirstChild("Beast")
	if not model then
		return
	end
	track(model)
	local b = beasts[model :: Model]
	if b then
		b.Attack = { Combo = combo, Start = os.clock(), Duration = if combo == 3 then 0.7 else 0.5 }
	end
end

function BeastFX.Start(combatFX: any?)
	CollectionService:GetInstanceAddedSignal("BeastForm"):Connect(function(model)
		task.defer(track, model)
	end)
	CollectionService:GetInstanceRemovedSignal("BeastForm"):Connect(function(model)
		if model:IsA("Model") then
			vanish(model)
		end
	end)
	for _, model in CollectionService:GetTagged("BeastForm") do
		track(model)
	end
	if combatFX then
		combatFX.OnBeastAttack = BeastFX.Attack
	end
	RunService.RenderStepped:Connect(step)
end

return BeastFX
