-- Geometry
-- Low-level building blocks for the hand-crafted low-poly world. Everything is
-- built from plain Parts / WedgeParts with SmoothPlastic, Neon or Glass —
-- no textures, no ForceField, no Terrain.
--
-- Highlights:
--   Triangle(a, b, c)   any triangle in 3D from two wedges (faceted surfaces)
--   Polygon / Fan       flat faceted polygons with alternating facet shades
--   Prism / Pyramid     crystal shapes
--   Ring                segmented rings (ripples, halos, trims)
--   RockStack           stratified dark rock islands with light rim layers

local CollectionService = game:GetService("CollectionService")

local Geometry = {}

local function applyDefaults(part: BasePart)
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

export type Style = {
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	CastShadow: boolean?,
}

local function style(part: BasePart, s: Style)
	part.Color = s.Color
	part.Material = s.Material or Enum.Material.SmoothPlastic
	part.Transparency = s.Transparency or 0
	part.CanCollide = if s.CanCollide == nil then true else s.CanCollide
	part.CanQuery = part.CanCollide
	part.CastShadow = if s.CastShadow == nil then part.Material ~= Enum.Material.Neon else s.CastShadow
end

function Geometry.Block(parent: Instance, name: string, cf: CFrame, size: Vector3, s: Style): Part
	local part = Instance.new("Part")
	part.Name = name
	applyDefaults(part)
	part.Size = size
	part.CFrame = cf
	style(part, s)
	part.Parent = parent
	return part
end

function Geometry.Ball(parent: Instance, name: string, position: Vector3, diameter: number, s: Style): Part
	local part = Geometry.Block(parent, name, CFrame.new(position), Vector3.one * diameter, s)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Upright cylinder: base centre + height.
function Geometry.Cylinder(parent: Instance, name: string, base: Vector3, radius: number, height: number, s: Style): Part
	local part = Geometry.Block(parent, name, CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(height, radius * 2, radius * 2), s)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- CFrame.lookAt that stays well-defined when looking straight up or down
-- (the default up vector would be parallel to the view direction).
function Geometry.LookAt(at: Vector3, target: Vector3, up: Vector3?): CFrame
	local upVector = up or Vector3.yAxis
	local direction = (target - at).Unit
	if math.abs(direction:Dot(upVector)) > 0.999 then
		upVector = if math.abs(direction:Dot(Vector3.zAxis)) > 0.999 then Vector3.xAxis else Vector3.zAxis
	end
	return CFrame.lookAt(at, target, upVector)
end

-- Cylinder between two points (beams of light, pipes).
function Geometry.CylinderBetween(parent: Instance, name: string, a: Vector3, b: Vector3, radius: number, s: Style): Part
	local length = (b - a).Magnitude
	local cf = Geometry.LookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	local part = Geometry.Block(parent, name, cf, Vector3.new(length, radius * 2, radius * 2), s)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Box between two points with a given width/height (strips, beams, rails).
function Geometry.Strip(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, height: number, s: Style, up: Vector3?): Part
	local length = (b - a).Magnitude
	local cf = Geometry.LookAt((a + b) / 2, b, up)
	return Geometry.Block(parent, name, cf, Vector3.new(width, height, length), s)
end

-- A triangle in 3D built from two wedges (the classic Roblox technique).
-- The front face is the side (b - a) x (c - a) points to (right-hand rule);
-- `thickness` always extrudes behind it, so floors built with a consistent
-- winding stay perfectly flat.
function Geometry.Triangle(parent: Instance, name: string, a: Vector3, b: Vector3, c: Vector3, s: Style, thickness: number?): (WedgePart?, WedgePart?)
	local t = thickness or 0.4
	local front = (b - a):Cross(c - a)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-6 or bc.Magnitude < 1e-6 then
		return nil, nil -- degenerate
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.05 then
		return nil, nil
	end
	-- Extrude away from the front face whichever way the wedges are oriented.
	local behind = if right:Dot(front) >= 0 then -right else right

	local w1 = Instance.new("WedgePart")
	w1.Name = name
	applyDefaults(w1)
	w1.Size = Vector3.new(t, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2 + behind * t / 2, right, up, back)
	style(w1, s)
	w1.Parent = parent

	local w2 = Instance.new("WedgePart")
	w2.Name = name
	applyDefaults(w2)
	w2.Size = Vector3.new(t, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2 + behind * t / 2, -right, up, -back)
	style(w2, s)
	w2.Parent = parent
	return w1, w2
end

-- Flat-shaded colour variation for low-poly facets.
function Geometry.Shade(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * (1 + amount), 0, 1))
end

-- Fan of triangles from a centre to a closed loop of points (faceted top).
-- Loops come from Geometry.Loop; the face points up (+Y) and the thickness
-- hangs below. Facets alternate between two shades for the hand-painted
-- low-poly look.
function Geometry.Fan(parent: Instance, name: string, center: Vector3, points: { Vector3 }, s: Style, thickness: number?, shadeA: number?, shadeB: number?)
	for i = 1, #points do
		local a = points[i]
		local b = points[i % #points + 1]
		local shade = if i % 2 == 0 then (shadeA or 0.04) else (shadeB or -0.04)
		Geometry.Triangle(parent, name, center, b, a, {
			Color = Geometry.Shade(s.Color, shade),
			Material = s.Material,
			Transparency = s.Transparency,
			CanCollide = s.CanCollide,
		}, thickness)
	end
end

-- Vertical skirt between two loops (cliff faces, bevels, rims); faces point
-- outward and the thickness goes inward.
function Geometry.Skirt(parent: Instance, name: string, top: { Vector3 }, bottom: { Vector3 }, s: Style, thickness: number?)
	for i = 1, #top do
		local j = i % #top + 1
		local shade = if i % 2 == 0 then 0.05 else -0.05
		local st = {
			Color = Geometry.Shade(s.Color, shade),
			Material = s.Material,
			Transparency = s.Transparency,
			CanCollide = s.CanCollide,
		}
		Geometry.Triangle(parent, name, top[i], top[j], bottom[i], st, thickness)
		Geometry.Triangle(parent, name, top[j], bottom[j], bottom[i], st, thickness)
	end
end

-- Points on a circle (optionally irregular via rng + jitter fraction).
function Geometry.Loop(center: Vector3, radius: number, count: number, rng: Random?, jitter: number?, startAngle: number?): { Vector3 }
	local points = {}
	for i = 1, count do
		local a = (startAngle or 0) + (i - 1) / count * math.pi * 2
		local r = radius
		if rng and jitter then
			r *= 1 + rng:NextNumber(-jitter, jitter)
		end
		table.insert(points, center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
	end
	return points
end

-- Square prism crystal with a pyramid tip (base centre, up direction).
function Geometry.Crystal(parent: Instance, name: string, base: Vector3, width: number, height: number, tilt: CFrame?, core: Style, shell: Style?)
	local cf = CFrame.new(base) * (tilt or CFrame.identity) * CFrame.Angles(0, math.rad(45), 0)
	local bodyHeight = height * 0.78
	local tipHeight = height - bodyHeight
	Geometry.Block(parent, name, cf * CFrame.new(0, bodyHeight / 2, 0), Vector3.new(width, bodyHeight, width), core)
	-- Pyramid tip from four triangles.
	local top = cf * CFrame.new(0, bodyHeight, 0)
	local apex = (cf * CFrame.new(0, height, 0)).Position
	local hw = width / 2
	local corners = {
		(top * CFrame.new(hw, 0, hw)).Position,
		(top * CFrame.new(-hw, 0, hw)).Position,
		(top * CFrame.new(-hw, 0, -hw)).Position,
		(top * CFrame.new(hw, 0, -hw)).Position,
	}
	for i = 1, 4 do
		Geometry.Triangle(parent, name .. "Tip", corners[i], corners[i % 4 + 1], apex, {
			Color = Geometry.Shade(core.Color, if i % 2 == 0 then 0.12 else -0.06),
			Material = core.Material,
			Transparency = core.Transparency,
			CanCollide = core.CanCollide,
		}, 0.3)
	end
	if shell then
		local inner = width * 0.45
		Geometry.Block(parent, name .. "Core", cf * CFrame.new(0, bodyHeight * 0.55, 0), Vector3.new(inner, bodyHeight * 0.9, inner), shell)
	end
	local _ = tipHeight
end

-- Octahedron gem (two pyramids) centred on `center`.
function Geometry.Gem(parent: Instance, name: string, center: CFrame, radius: number, height: number, s: Style)
	local top = (center * CFrame.new(0, height, 0)).Position
	local bottom = (center * CFrame.new(0, -height, 0)).Position
	local ring = {}
	for i = 0, 3 do
		local a = i * math.pi / 2
		table.insert(ring, (center * CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius)).Position)
	end
	for i = 1, 4 do
		local j = i % 4 + 1
		local up = { Color = Geometry.Shade(s.Color, if i % 2 == 0 then 0.18 else 0), Material = s.Material, Transparency = s.Transparency, CanCollide = s.CanCollide }
		local down = { Color = Geometry.Shade(s.Color, if i % 2 == 0 then -0.1 else -0.22), Material = s.Material, Transparency = s.Transparency, CanCollide = s.CanCollide }
		Geometry.Triangle(parent, name, ring[i], ring[j], top, up, 0.3)
		Geometry.Triangle(parent, name, ring[j], ring[i], bottom, down, 0.3)
	end
end

-- Segmented ring lying flat (ripples, trims) or around any CFrame.
function Geometry.Ring(parent: Instance, name: string, cf: CFrame, radius: number, thickness: number, height: number, segments: number, s: Style)
	local segLength = 2 * math.pi * radius / segments * 1.04
	for i = 0, segments - 1 do
		local a = i / segments * math.pi * 2
		local p = cf * CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		Geometry.Block(parent, name, p * CFrame.Angles(0, -a, 0), Vector3.new(thickness, height, segLength), s)
	end
end

-- Stratified rock island: stacked irregular faceted layers, each with a pale
-- rim, cliff faces between layers and faint glowing streaks — the dark-rock-
-- with-light-edges look. Returns the top loop and top height.
export type RockPalette = {
	Rock: Color3,
	Rim: Color3,
	Streak: Color3?,
}

-- `lowDetail` (for distant islands) caps only the top layer and skips the
-- streaks, roughly halving the part count with no visible difference at range.
function Geometry.RockStack(parent: Instance, name: string, center: Vector3, baseRadius: number, topRadius: number, height: number, layers: number, rng: Random, palette: RockPalette, sides: number?, inverted: boolean?, lowDetail: boolean?): ({ Vector3 }, number)
	local n = sides or 14
	local layerHeight = height / layers
	local prevLoop: { Vector3 }? = nil
	local topLoop: { Vector3 } = {}
	local topY = center.Y
	for layer = 0, layers - 1 do
		local t = layer / math.max(1, layers - 1)
		local radius = baseRadius + (topRadius - baseRadius) * t
		local yBottom = if inverted then center.Y - layer * layerHeight else center.Y + layer * layerHeight
		local yTop = if inverted then yBottom - layerHeight else yBottom + layerHeight
		local angle0 = rng:NextNumber(0, math.pi * 2)
		local outer = Geometry.Loop(Vector3.new(center.X, yTop, center.Z), radius, n, rng, 0.14, angle0)
		local lower = {}
		for i, p in outer do
			-- Cliff faces lean a little inward/outward for a hand-cut feel.
			local dir = (Vector3.new(p.X, 0, p.Z) - Vector3.new(center.X, 0, center.Z)).Unit
			lower[i] = Vector3.new(p.X, yBottom, p.Z) + dir * rng:NextNumber(-1.5, 3)
		end
		Geometry.Skirt(parent, name .. "Cliff", outer, lower, { Color = palette.Rock }, 1)
		-- Pale rim band along the layer's top edge (one block per side).
		local rimOffset = Vector3.new(0, if inverted then 0.7 else -0.7, 0)
		for i, p in outer do
			local q = outer[i % n + 1]
			local mid = (p + q) / 2
			local dir = (Vector3.new(mid.X, 0, mid.Z) - Vector3.new(center.X, 0, center.Z)).Unit
			Geometry.Strip(parent, name .. "Rim", p + dir * 0.8 + rimOffset, q + dir * 0.8 + rimOffset, 1.6, 1.4, { Color = palette.Rim })
		end
		-- Top cap of the layer (the visible ledge between strata).
		if not lowDetail or layer == layers - 1 then
			Geometry.Fan(parent, name .. "Ledge", Vector3.new(center.X, yTop, center.Z), outer, { Color = Geometry.Shade(palette.Rock, 0.08) }, 1)
		end
		-- Glowing streaks on some cliff faces.
		if palette.Streak and not lowDetail then
			for i = 1, n do
				if rng:NextNumber() < 0.35 then
					local p = lower[i]:Lerp(outer[i], rng:NextNumber(0.2, 0.6))
					local dir = (Vector3.new(p.X, 0, p.Z) - Vector3.new(center.X, 0, center.Z)).Unit
					local length = layerHeight * rng:NextNumber(0.3, 0.8)
					Geometry.Block(parent, name .. "Streak", CFrame.lookAt(p + dir * 1.2, p + dir * 3) * CFrame.new(0, 0, 0), Vector3.new(0.35, length, 0.2), {
						Color = palette.Streak,
						Material = Enum.Material.Neon,
						Transparency = 0.35,
						CanCollide = false,
					})
				end
			end
		end
		prevLoop = outer
		topLoop = outer
		topY = yTop
	end
	local _ = prevLoop
	return topLoop, topY
end

function Geometry.Tag(instance: Instance, tag: string)
	CollectionService:AddTag(instance, tag)
end

function Geometry.Folder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Geometry.Model(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Geometry.Light(parent: BasePart, color: Color3, range: number, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1.5
	light.Shadows = false
	light.Parent = parent
	return light
end

return Geometry
