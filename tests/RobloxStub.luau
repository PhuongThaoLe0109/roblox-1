-- Minimal Roblox API stand-ins for running build scripts offline with the
-- standalone Luau CLI. Covers what MapBuilder uses: Vector3, CFrame, Color3,
-- Instances with properties/attributes/children, a few services and enums.
-- Part sizes and CFrames are validated on assignment.

local Stub = { Errors = {}, PartCount = 0 }

local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end

-- Vector3 -------------------------------------------------------------------
local V = {}
V.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z); if m == 0 then return v end return Vector3.new(v.X / m, v.Y / m, v.Z / m) end
	return V[k]
end
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return vec(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V.Cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function V.Lerp(a, b, t) return a + (b - a) * t end
Vector3 = { new = vec, zero = vec(0, 0, 0), one = vec(1, 1, 1), xAxis = vec(1, 0, 0), yAxis = vec(0, 1, 0), zAxis = vec(0, 0, 1) }
Vector2 = { new = function(x, y) return { X = x, Y = y } end }

-- CFrame (rotation stored as columns R = right, U = up, B = back) -----------
local C = {}
local function cf(p, r, u, b) return setmetatable({ P = p, R = r, U = u, B = b }, C) end
local function rot(c, v) return c.R * v.X + c.U * v.Y + c.B * v.Z end
C.__index = function(c, k)
	if k == "Position" or k == "p" then return c.P end
	if k == "LookVector" then return -c.B end
	if k == "RightVector" then return c.R end
	if k == "UpVector" then return c.U end
	if k == "X" then return c.P.X end
	if k == "Y" then return c.P.Y end
	if k == "Z" then return c.P.Z end
	if k == "Rotation" then return cf(vec(), c.R, c.U, c.B) end
	return C[k]
end
C.__mul = function(a, b)
	if getmetatable(b) == V then return a.P + rot(a, b) end
	return cf(a.P + rot(a, b.P), rot(a, b.R), rot(a, b.U), rot(a, b.B))
end
C.__add = function(a, v) return cf(a.P + v, a.R, a.U, a.B) end
C.__sub = function(a, v) return cf(a.P - v, a.R, a.U, a.B) end
function C.PointToObjectSpace(c, v) local d = v - c.P; return vec(d:Dot(c.R), d:Dot(c.U), d:Dot(c.B)) end
function C.VectorToWorldSpace(c, v) return rot(c, v) end
function C.Inverse(c)
	local r = vec(c.R.X, c.U.X, c.B.X); local u = vec(c.R.Y, c.U.Y, c.B.Y); local b = vec(c.R.Z, c.U.Z, c.B.Z)
	local inv = cf(vec(), r, u, b); inv.P = -rot(inv, c.P); return inv
end
local I = function(p) return cf(p or vec(), vec(1, 0, 0), vec(0, 1, 0), vec(0, 0, 1)) end
local function rx(a) return cf(vec(), vec(1, 0, 0), vec(0, math.cos(a), math.sin(a)), vec(0, -math.sin(a), math.cos(a))) end
local function ry(a) return cf(vec(), vec(math.cos(a), 0, -math.sin(a)), vec(0, 1, 0), vec(math.sin(a), 0, math.cos(a))) end
local function rz(a) return cf(vec(), vec(math.cos(a), math.sin(a), 0), vec(-math.sin(a), math.cos(a), 0), vec(0, 0, 1)) end
CFrame = {
	identity = I(),
	new = function(x, y, z)
		if x == nil then return I() end
		if type(x) == "table" then return I(x) end
		return I(vec(x, y, z))
	end,
	Angles = function(x, y, z) return rx(x) * ry(y) * rz(z) end,
	lookAt = function(at, target, up)
		up = up or vec(0, 1, 0)
		local back = (at - target).Unit
		local right = up:Cross(back).Unit
		local up2 = back:Cross(right)
		return cf(at, right, up2, back)
	end,
	fromMatrix = function(p, x, y, z) return cf(p, x, y, z or x:Cross(y).Unit) end,
	fromAxisAngle = function(axis, a)
		local k = axis.Unit
		local function r(v) return v * math.cos(a) + k:Cross(v) * math.sin(a) + k * (k:Dot(v) * (1 - math.cos(a))) end
		return cf(vec(), r(vec(1, 0, 0)), r(vec(0, 1, 0)), r(vec(0, 0, 1)))
	end,
}

-- Color3 ------------------------------------------------------------------
local Col = {}
Col.__index = Col
local function col(r, g, b) return setmetatable({ R = r, G = g, B = b }, Col) end
function Col.Lerp(a, b, t) return col(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
function Col.ToHSV(c)
	local mx, mn = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	local d = mx - mn; local h = 0
	if d > 0 then
		if mx == c.R then h = ((c.G - c.B) / d) % 6 elseif mx == c.G then h = (c.B - c.R) / d + 2 else h = (c.R - c.G) / d + 4 end
		h = h / 6
	end
	return h, (mx == 0 and 0 or d / mx), mx
end
Color3 = {
	new = function(r, g, b) return col(r or 0, g or 0, b or 0) end,
	fromRGB = function(r, g, b) return col(r / 255, g / 255, b / 255) end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6); local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		i = i % 6
		if i == 0 then return col(v, t, p) elseif i == 1 then return col(q, v, p) elseif i == 2 then return col(p, v, t)
		elseif i == 3 then return col(p, q, v) elseif i == 4 then return col(t, p, v) end
		return col(v, p, q)
	end,
}

local function passthrough(...) return { ... } end
ColorSequence = { new = passthrough }
ColorSequenceKeypoint = { new = passthrough }
NumberSequence = { new = passthrough }
NumberSequenceKeypoint = { new = passthrough }
UDim2 = { new = passthrough, fromScale = passthrough, fromOffset = passthrough }
Font = { new = passthrough }
Enum = setmetatable({}, { __index = function(_, e) return setmetatable({}, { __index = function(_, k) return e .. "." .. k end }) end })

Random = {
	new = function(seed)
		local state = (seed or 1) % 2147483647
		if state <= 0 then state = state + 2147483646 end
		local function nxt() state = (state * 48271) % 2147483647; return state / 2147483647 end
		return {
			NextNumber = function(_, a, b) if a == nil then return nxt() end return a + (b - a) * nxt() end,
			NextInteger = function(_, a, b) return a + math.floor(nxt() * (b - a + 1)) end,
		}
	end,
}

-- Instances -----------------------------------------------------------------
local PART_CLASSES = { Part = true, WedgePart = true, SpawnLocation = true }
local Inst = {}
local function isA(self, class)
	local c = rawget(self, "ClassName")
	if c == class or class == "Instance" then return true end
	if class == "BasePart" then return PART_CLASSES[c] == true end
	return false
end
local function validate(self, key, value)
	if not PART_CLASSES[rawget(self, "ClassName")] then return end
	if key == "Size" then
		for _, n in { value.X, value.Y, value.Z } do
			if not finite(n) or n < 0 or n > 2048 then
				table.insert(Stub.Errors, string.format("%s.Size invalid (%s, %s, %s)", tostring(rawget(self, "_props").Name), value.X, value.Y, value.Z))
				return
			end
		end
	elseif key == "CFrame" then
		for _, n in { value.P.X, value.P.Y, value.P.Z, value.R.X, value.U.Y, value.B.Z } do
			if not finite(n) then
				table.insert(Stub.Errors, tostring(rawget(self, "_props").Name) .. ".CFrame is not finite")
				return
			end
		end
		-- Rotation must be orthonormal (catches lookAt along the up vector).
		local r, u, b = value.R, value.U, value.B
		if math.abs(r.Magnitude - 1) > 1e-3 or math.abs(u.Magnitude - 1) > 1e-3 or math.abs(b.Magnitude - 1) > 1e-3
			or math.abs(r:Dot(u)) > 1e-3 or math.abs(r:Dot(b)) > 1e-3 or math.abs(u:Dot(b)) > 1e-3 then
			table.insert(Stub.Errors, tostring(rawget(self, "_props").Name) .. ".CFrame rotation is degenerate")
		end
	end
end
Inst.__index = function(self, k)
	local method = Inst[k]
	if method then return method end
	local props = rawget(self, "_props")
	if k == "Parent" then return rawget(self, "_parent") end
	if props[k] ~= nil then return props[k] end
	local child = Inst.FindFirstChild(self, k)
	if child then return child end
	if k == "Position" and props.CFrame then return props.CFrame.P end
	return nil
end
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local list = rawget(old, "_children")
			for i, c in list do if c == self then table.remove(list, i) break end end
		end
		rawset(self, "_parent", v)
		if v then table.insert(rawget(v, "_children"), self) end
		return
	end
	validate(self, k, v)
	rawget(self, "_props")[k] = v
end
function Inst.IsA(self, class) return isA(self, class) end
function Inst.GetChildren(self) return table.clone(rawget(self, "_children")) end
function Inst.GetDescendants(self)
	local out = {}
	local function walk(n) for _, c in rawget(n, "_children") do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
function Inst.FindFirstChild(self, name)
	for _, c in rawget(self, "_children") do if rawget(c, "_props").Name == name then return c end end
	return nil
end
function Inst.FindFirstChildOfClass(self, class)
	for _, c in rawget(self, "_children") do if rawget(c, "ClassName") == class then return c end end
	return nil
end
function Inst.WaitForChild(self, name) return Inst.FindFirstChild(self, name) end
function Inst.SetAttribute(self, k, v) rawget(self, "_attrs")[k] = v end
function Inst.GetAttribute(self, k) return rawget(self, "_attrs")[k] end
function Inst.Destroy(self) self.Parent = nil end
function Inst.Clone(self)
	local copy = Instance.new(rawget(self, "ClassName"))
	for k, v in rawget(self, "_props") do rawget(copy, "_props")[k] = v end
	for _, c in rawget(self, "_children") do Inst.Clone(c).Parent = copy end
	return copy
end
function Inst.GetPivot(self) return rawget(self, "_props").CFrame or CFrame.new() end
Instance = {
	new = function(class)
		if PART_CLASSES[class] then Stub.PartCount += 1 end
		local o = setmetatable({ ClassName = class, _props = { Name = class }, _children = {}, _attrs = {} }, Inst)
		return o
	end,
}

local services = {}
local function service(name)
	if not services[name] then
		local s = Instance.new(name)
		rawget(s, "_props").Name = name
		services[name] = s
	end
	return services[name]
end
local tags = {}
Stub.Tags = tags
local collection = service("CollectionService")
rawset(collection, "AddTag", function(_, inst, tag) tags[tag] = (tags[tag] or 0) + 1 end)
game = setmetatable({}, { __index = function(_, k)
	if k == "GetService" then return function(_, name) return service(name) end end
	return nil
end })
workspace = service("Workspace")

return Stub
