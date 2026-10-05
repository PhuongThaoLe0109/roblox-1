-- Bridge
-- A two-tier arched aqueduct of pale temple stone linking the Dawn Gate
-- (lobby) to the Prism Temple. Railings, crystal lanterns on every pier and a
-- cyan light channel running down the middle of the deck.

local G = require(script.Parent:WaitForChild("Geometry"))
local P = require(script.Parent:WaitForChild("Palette"))

local Bridge = {}

local WIDTH = 18
local SPAN = 30

local function arch(parent: Instance, center: Vector3, radius: number, depth: number, thickness: number, color: Color3)
	-- Half ring in the bridge's YZ plane, spanning along Z.
	local segments = 12
	for i = 0, segments - 1 do
		local a0 = i / segments * math.pi
		local a1 = (i + 1) / segments * math.pi
		local p0 = center + Vector3.new(0, math.sin(a0) * radius, math.cos(a0) * radius)
		local p1 = center + Vector3.new(0, math.sin(a1) * radius, math.cos(a1) * radius)
		-- Strip width = radial thickness; height runs across the bridge (up = X).
		G.Strip(parent, "Arch", p0, p1, thickness, depth, { Color = G.Shade(color, if i % 2 == 0 then 0.03 else -0.03) }, Vector3.xAxis)
	end
end

function Bridge.Build(map: Instance, fromZ: number, toZ: number, fromY: number, toY: number, rng: Random)
	local root = G.Model(map, "Bridge")
	local length = toZ - fromZ
	local spans = math.max(1, math.floor(length / SPAN))
	local spanLength = length / spans

	local function deckY(z: number): number
		return fromY + (toY - fromY) * ((z - fromZ) / length)
	end

	-- Deck, one slab per span so it follows the gentle slope.
	for s = 0, spans - 1 do
		local z0 = fromZ + s * spanLength
		local z1 = z0 + spanLength
		local a = Vector3.new(0, deckY(z0), z0)
		local b = Vector3.new(0, deckY(z1), z1)
		G.Strip(root, "Deck", a - Vector3.new(0, 1.2, 0), b - Vector3.new(0, 1.2, 0), WIDTH, 2.4, { Color = G.Shade(P.Stone, if s % 2 == 0 then 0.02 else -0.02) })
		G.Strip(root, "DeckEdge", a - Vector3.new(0, 2.6, 0), b - Vector3.new(0, 2.6, 0), WIDTH + 1.6, 1, { Color = P.StoneShade })
		-- Railings
		for _, x in { -WIDTH / 2 + 0.6, WIDTH / 2 - 0.6 } do
			G.Strip(root, "Rail", a + Vector3.new(x, 1.3, 0), b + Vector3.new(x, 1.3, 0), 1.2, 2.6, { Color = P.Stone })
			G.Strip(root, "RailCap", a + Vector3.new(x, 2.75, 0), b + Vector3.new(x, 2.75, 0), 1.6, 0.4, { Color = P.Trim })
		end
		-- Centre light channel
		G.Strip(root, "DeckGlow", a + Vector3.new(0, 0.08, 0), b + Vector3.new(0, 0.08, 0), 3.2, 0.2, { Color = P.ChannelGlow, Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false })
		G.Strip(root, "DeckChannel", a + Vector3.new(0, 0.2, 0), b + Vector3.new(0, 0.2, 0), 1.1, 0.25, { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })
	end

	-- Piers, two tiers of arches, lanterns.
	for s = 0, spans do
		local z = fromZ + s * spanLength
		local y = deckY(z)
		local pierTop = y - 3
		-- Pier from the sea floor up to the deck.
		G.Block(root, "Pier", CFrame.new(0, (pierTop - 8) / 2, z), Vector3.new(WIDTH - 2, pierTop + 8, 7), { Color = G.Shade(P.StoneShade, -0.05) })
		G.Block(root, "PierCap", CFrame.new(0, pierTop - 0.6, z), Vector3.new(WIDTH, 1.2, 8.5), { Color = P.Stone })
		G.Block(root, "PierBase", CFrame.new(0, 1.5, z), Vector3.new(WIDTH + 3, 3, 10), { Color = P.StoneDeep })

		-- Crystal lantern on both rails.
		for _, x in { -WIDTH / 2 + 0.6, WIDTH / 2 - 0.6 } do
			G.Block(root, "LanternPost", CFrame.new(x, y + 4.5, z), Vector3.new(1.2, 6, 1.2), { Color = P.Stone })
			G.Gem(root, "LanternGem", CFrame.new(x, y + 9, z), 1.1, 1.8, { Color = P.Channel, Material = Enum.Material.Neon, CanCollide = false })
			if s % 2 == 0 then
				local holder = G.Block(root, "LanternLight", CFrame.new(x, y + 9, z), Vector3.one * 0.2, { Color = P.Channel, Transparency = 1, CanCollide = false })
				G.Light(holder, P.Channel, 18, 1.4)
			end
		end

		if s < spans then
			local midZ = z + spanLength / 2
			local yMid = deckY(midZ)
			local openRadius = spanLength / 2 - 3.5
			-- Upper arch just under the deck, lower big arch near the water.
			arch(root, Vector3.new(0, yMid - 3 - openRadius - 2, midZ), openRadius, WIDTH - 2, 2.2, P.Stone)
			arch(root, Vector3.new(0, yMid * 0.35, midZ), openRadius, WIDTH - 4, 2.6, P.StoneShade)
			-- Spandrel infill between the arches and the deck.
			G.Block(root, "Spandrel", CFrame.new(0, yMid - 4, midZ), Vector3.new(WIDTH - 2.4, 2, spanLength - 6), { Color = G.Shade(P.Stone, -0.06) })
		end
	end

	local _ = rng
	return root
end

return Bridge
