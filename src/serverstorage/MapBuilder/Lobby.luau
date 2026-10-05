-- Lobby
-- The Dawn Gate: a raised plaza on its own stratified island at the far end
-- of the aqueduct, looking across to the temple. Faceted octagonal floor with
-- neon inlays, the Altar of Fortune with a giant floating gem, eight crystal
-- pylons, a pointed gate arch with the game's name, and a viewing balcony.
--
-- Exposes Map.Lobby with a SpawnLocation ("LobbySpawn") and attributes
-- Center, Radius.

local G = require(script.Parent:WaitForChild("Geometry"))
local P = require(script.Parent:WaitForChild("Palette"))

local Lobby = {}

Lobby.Center = Vector3.new(0, 70, 470)
Lobby.Radius = 64

function Lobby.Build(map: Instance, rng: Random, title: string)
	local root = G.Model(map, "Lobby")
	local c = Lobby.Center
	local y = c.Y

	-- Island
	local _, topY = G.RockStack(root, "Rock", Vector3.new(c.X, -6, c.Z), 130, 92, 72, 6, rng, {
		Rock = P.Rock,
		Rim = P.Rim,
		Streak = P.StreakPink,
	}, 16)

	-- Outer promenade: a lower pale terrace ringing the plaza.
	local terraceY = topY + 1.2
	local terraceCenter = Vector3.new(c.X, terraceY, c.Z)
	G.Fan(root, "Terrace", terraceCenter, G.Loop(terraceCenter, 86, 16, nil, nil, math.rad(11.25)), { Color = P.StoneShade }, 1.2, 0.03, -0.03)
	local terraceEdge = G.Loop(terraceCenter, 86, 16, nil, nil, math.rad(11.25))
	local terraceLow = {}
	for i, p in terraceEdge do
		terraceLow[i] = p + (p - terraceCenter).Unit * 1.5 - Vector3.new(0, 2.4, 0)
	end
	G.Skirt(root, "TerraceSkirt", terraceEdge, terraceLow, { Color = P.Rim }, 0.8)
	G.Ring(root, "TerraceInlay", CFrame.new(terraceCenter + Vector3.new(0, 0.2, 0)), 80, 0.6, 0.3, 48, { Color = P.Pink, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false })

	-- Plaza: faceted octagon with a stone skirt.
	local outer = G.Loop(c, Lobby.Radius, 16, nil, nil, math.rad(11.25))
	G.Fan(root, "Plaza", c, outer, { Color = P.Stone }, 2, 0.03, -0.03)
	local skirt = {}
	for i, p in outer do
		local dir = (p - c).Unit
		skirt[i] = p + dir * 3 - Vector3.new(0, y - topY + 1, 0)
	end
	G.Skirt(root, "PlazaSkirt", outer, skirt, { Color = P.StoneShade }, 1)
	-- Inner rose: a slightly pinker disc and neon inlays.
	G.Fan(root, "Rose", c + Vector3.new(0, 0.15, 0), G.Loop(c + Vector3.new(0, 0.15, 0), 42, 16, nil, nil, math.rad(11.25)), { Color = G.Shade(P.Pink, -0.2) }, 0.4, 0.05, -0.05)
	for _, r in { 42.5, 22 } do
		G.Ring(root, "Inlay", CFrame.new(c + Vector3.new(0, 0.45, 0)), r, 0.7, 0.3, 40, { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local a1 = c + Vector3.new(math.cos(a) * 22, 0.45, math.sin(a) * 22)
		local a2 = c + Vector3.new(math.cos(a) * 42, 0.45, math.sin(a) * 42)
		G.Strip(root, "InlaySpoke", a1, a2, 0.7, 0.3, { Color = P.Pink, Material = Enum.Material.Neon, CanCollide = false })
	end
	-- Low parapet with gaps for the gate (north) and the balcony (south).
	for i, p in outer do
		local q = outer[i % #outer + 1]
		local mid = (p + q) / 2
		local north = (mid - c).Unit:Dot(Vector3.new(0, 0, -1)) > 0.92
		local south = (mid - c).Unit:Dot(Vector3.new(0, 0, 1)) > 0.92
		if not north and not south then
			G.Strip(root, "Parapet", p + Vector3.new(0, 1.4, 0), q + Vector3.new(0, 1.4, 0), 1.6, 2.8, { Color = P.Stone })
			G.Strip(root, "ParapetCap", p + Vector3.new(0, 2.95, 0), q + Vector3.new(0, 2.95, 0), 2.2, 0.4, { Color = P.Trim })
		end
	end

	-- Altar of Fortune
	local altar = G.Model(root, "Altar")
	G.Fan(altar, "AltarStep", c + Vector3.new(0, 1.4, 0), G.Loop(c + Vector3.new(0, 1.4, 0), 12, 8), { Color = P.StoneShade }, 1.4)
	G.Fan(altar, "AltarTop", c + Vector3.new(0, 2.8, 0), G.Loop(c + Vector3.new(0, 2.8, 0), 8.5, 8), { Color = P.Stone }, 1.4)
	G.Ring(altar, "AltarRing", CFrame.new(c + Vector3.new(0, 3, 0)), 8.8, 0.6, 0.4, 24, { Color = P.Pink, Material = Enum.Material.Neon, CanCollide = false })
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local foot = c + Vector3.new(math.cos(a) * 7, 3, math.sin(a) * 7)
		G.Strip(altar, "AltarRay", foot, c + Vector3.new(0, 15, 0), 0.5, 0.5, { Color = P.Pink, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false })
	end
	local fortune = G.Model(root, "FortuneGem")
	G.Gem(fortune, "Facet", CFrame.new(c + Vector3.new(0, 20, 0)), 6, 9, { Color = P.Pink, Material = Enum.Material.Glass, Transparency = 0.1, CanCollide = false })
	local fortuneCore = G.Ball(fortune, "Core", c + Vector3.new(0, 20, 0), 5, { Color = G.Shade(P.Pink, 0.2), Material = Enum.Material.Neon, CanCollide = false })
	G.Light(fortuneCore, P.Pink, 40, 2.5)
	fortune:SetAttribute("SpinSpeed", 0.5)
	fortune:SetAttribute("FloatHeight", 1.5)
	G.Tag(fortune, "MapSpin")

	-- Eight crystal pylons with floating gems.
	local pylonColors = { P.Pink, P.Teal, P.Lavender, P.Gold }
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local base = c + Vector3.new(math.cos(a) * 54, 0, math.sin(a) * 54)
		local color = pylonColors[i % 4 + 1]
		G.Cylinder(root, "PylonBase", base, 3.6, 1.2, { Color = P.StoneShade })
		G.Crystal(root, "Pylon", base + Vector3.new(0, 1.2, 0), 3, if i % 2 == 0 then 24 else 18, nil, {
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
		}, { Color = G.Shade(color, 0.3), Material = Enum.Material.Neon, CanCollide = false })
		local float = G.Model(root, "PylonGem")
		G.Gem(float, "Facet", CFrame.new(base + Vector3.new(0, if i % 2 == 0 then 31 else 25, 0)), 1.4, 2.2, { Color = color, Material = Enum.Material.Neon, CanCollide = false })
		float:SetAttribute("SpinSpeed", 1.2)
		float:SetAttribute("FloatHeight", 0.8)
		G.Tag(float, "MapSpin")
	end

	-- Crystal blossom trees around the plaza, on the island rim.
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + math.pi / 6
		local base = Vector3.new(c.X + math.cos(a) * 76, topY + 1.2, c.Z + math.sin(a) * 76)
		if math.abs(math.cos(a)) > 0.3 or math.sin(a) < 0 then
			local tree = G.Model(root, "BlossomTree")
			local trunkTop = base + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(14, 20), rng:NextNumber(-2, 2))
			G.CylinderBetween(tree, "Trunk", base, trunkTop, 1.1, { Color = Color3.fromRGB(110, 86, 130) })
			for b = 1, 5 do
				local branch = trunkTop + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-3, 4), rng:NextNumber(-6, 6))
				G.CylinderBetween(tree, "Branch", trunkTop - Vector3.new(0, 4, 0), branch, 0.5, { Color = Color3.fromRGB(120, 94, 140) })
				local color = if (i + b) % 2 == 0 then P.Pink else P.Lavender
				G.Gem(tree, "Blossom", CFrame.new(branch) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), rng:NextNumber(4.5, 6.5), rng:NextNumber(4, 5.5), {
					Color = G.Shade(color, 0.12),
					Material = Enum.Material.Glass,
					Transparency = 0.12,
					CanCollide = false,
				})
			end
			local glow = G.Ball(tree, "BlossomGlow", trunkTop, 3, { Color = P.Pink, Material = Enum.Material.Neon, CanCollide = false })
			G.Light(glow, P.Pink, 20, 1.4)
		end
	end

	-- Gate arch facing the bridge (north).
	local gateZ = c.Z - Lobby.Radius + 2
	for _, x in { -11, 11 } do
		G.Block(root, "GatePillar", CFrame.new(x, y + 12, gateZ), Vector3.new(4, 24, 4), { Color = P.Stone })
		G.Block(root, "GatePillarTrim", CFrame.new(x, y + 24.4, gateZ), Vector3.new(5, 0.8, 5), { Color = P.Trim })
		G.Block(root, "GatePillarGlow", CFrame.new(x, y + 12, gateZ - 2.05), Vector3.new(0.8, 20, 0.1), { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })
	end
	-- Pointed arch from two slanted beams + a keystone gem.
	local apex = Vector3.new(0, y + 36, gateZ)
	for _, x in { -11, 11 } do
		local foot = Vector3.new(x, y + 24.8, gateZ)
		G.Strip(root, "ArchBeam", foot, apex, 3.4, 3.4, { Color = P.Stone })
		G.Strip(root, "ArchGlow", foot + Vector3.new(0, 0, -1.8), apex + Vector3.new(0, 0, -1.8), 0.7, 0.7, { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })
	end
	G.Gem(root, "Keystone", CFrame.new(apex + Vector3.new(0, 1, -0.5)), 2.4, 3.4, { Color = P.Pink, Material = Enum.Material.Neon, CanCollide = false })
	-- Engraved title on a lintel.
	local lintel = G.Block(root, "Lintel", CFrame.new(0, y + 26.5, gateZ), Vector3.new(26, 3.6, 3), { Color = P.Stone })
	local sign = Instance.new("SurfaceGui")
	sign.Face = Enum.NormalId.Front
	sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sign.PixelsPerStud = 40
	sign.LightInfluence = 0
	sign.Parent = lintel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Text = title
	text.TextScaled = true
	text.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Black, Enum.FontStyle.Italic)
	text.TextColor3 = Color3.fromRGB(255, 240, 255)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, P.Pink),
		ColorSequenceKeypoint.new(0.5, P.Trim),
		ColorSequenceKeypoint.new(1, P.Channel),
	})
	gradient.Parent = text
	text.Parent = sign
	local back = sign:Clone()
	back.Face = Enum.NormalId.Back
	back.Parent = lintel

	-- Viewing balcony (south) overlooking the sea.
	local balcony = c + Vector3.new(0, 0, Lobby.Radius + 10)
	G.Fan(root, "Balcony", balcony, G.Loop(balcony, 14, 10), { Color = P.Stone }, 2)
	G.Strip(root, "BalconyLink", c + Vector3.new(0, -1, Lobby.Radius - 4), balcony + Vector3.new(0, -1, -8), 14, 2, { Color = P.Stone })
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		if math.sin(a) > -0.6 then
			local p1 = balcony + Vector3.new(math.cos(a) * 14, 1.4, math.sin(a) * 14)
			local a2 = (i + 1) / 10 * math.pi * 2
			local p2 = balcony + Vector3.new(math.cos(a2) * 14, 1.4, math.sin(a2) * 14)
			G.Strip(root, "BalconyRail", p1, p2, 1.2, 2.8, { Color = P.Stone })
		end
	end

	-- Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.lookAt(c + Vector3.new(0, 0.4, 30), c + Vector3.new(0, 0.4, -100))
	spawn.Color = P.Pink
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.6
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.CanCollide = false
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root

	root:SetAttribute("Center", c)
	root:SetAttribute("Radius", Lobby.Radius + 25)
	return root
end

return Lobby
