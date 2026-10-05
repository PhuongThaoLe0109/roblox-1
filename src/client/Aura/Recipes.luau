-- Aura recipes
-- One hand-tuned recipe per gem: which layers (see Layers.luau) it wears and
-- how they're shaped. Rarer gems get more layers, bigger reach and more
-- motion; the rarest forty each have a signature built around their name.
-- Colours always come from the gem (GemCatalog Color / Accent), so no two
-- auras look alike even where they share a layer type.
--
-- Y values are studs from the root (head top is about +2.5); Ground = true
-- measures from the feet. Every aura also gets a breathing Glow light sized
-- by rarity (added by the renderer).

local Recipes = {}

local function L(kind: string)
	return function(spec: { [string]: any }): { [string]: any }
		spec.Kind = kind
		return spec
	end
end

local Ring = L("Ring")
local Orbit = L("Orbit")
local Motes = L("Motes")
local Wings = L("Wings")
local Crown = L("Crown")
local Helix = L("Helix")
local Mandala = L("Mandala")
local Pillars = L("Pillars")
local Crest = L("Crest")
local Stars = L("Stars")
local Lightning = L("Lightning")
local Eclipse = L("Eclipse")
local Pulse = L("Pulse")
local Monoliths = L("Monoliths")

-- Frequently used shapes.
local function groundRing(radius: number, sides: number?, step: number?, speed: number?, width: number?)
	return Ring({ Ground = true, Y = 0.15, Radius = radius, Sides = sides or 32, Step = step, Speed = speed or 0.4, Width = width or 0.22 })
end
local function halo(radius: number?, sides: number?, step: number?, extra: { [string]: any }?)
	local spec = { Y = 3, Radius = radius or 0.95, Sides = sides or 28, Step = step, Speed = 0.8, Width = 0.14, Tilt = 8, Wobble = 0.05 }
	for k, v in extra or {} do
		spec[k] = v
	end
	return Ring(spec)
end
local function embers(count: number, extra: { [string]: any }?)
	local spec = { Count = count, Speed = 0.55, Flicker = true, Swirl = 1.1, Size = 0.22, Height = 8 }
	for k, v in extra or {} do
		spec[k] = v
	end
	return Motes(spec)
end
local function petals(count: number, extra: { [string]: any }?)
	local spec = { Count = count, Shape = "Petal", Direction = -1, Speed = 0.22, Swirl = 1.4, Radius = 3.4, Height = 9, Size = 0.35 }
	for k, v in extra or {} do
		spec[k] = v
	end
	return Motes(spec)
end

local R: { [string]: { { [string]: any } } } = {
	----------------------------------------------------------------------------
	-- 1 in 2 .. 1 in 750: one quiet signature each
	----------------------------------------------------------------------------
	Quartz = { groundRing(2.2, 6, nil, 0.25, 0.14) },
	Jasper = { Motes({ Count = 5, Speed = 0.25, Size = 0.2, Height = 5 }) },
	Agate = { groundRing(2.5, 32, nil, 0.3, 0.16), groundRing(1.8, 32, nil, -0.45, 0.12) },
	Onyx = { Orbit({ Count = 1, Radius = 2.2, Y = 0.6, Size = 0.45, Speed = 1 }) },
	Obsidian = { Orbit({ Count = 2, Shape = "Shard", Radius = 2.4, Y = 0.2, Size = 0.4, Speed = -0.9 }) },
	Calcite = { groundRing(2.6, 3, nil, 0.35, 0.18) },
	Fluorite = { groundRing(2.5, 8, 3, 0.5, 0.15) },
	Hematite = { Orbit({ Count = 3, Shape = "Orb", Radius = 1.8, Y = 1, Size = 0.3, Speed = 2.4, Bob = 0.15 }) },
	Pyrite = { Motes({ Count = 8, Flicker = true, Speed = 0.3, Size = 0.18, Height = 6 }) },
	Jade = { halo(0.9, 24) },
	Amethyst = { Orbit({ Count = 2, Shape = "Shard", Radius = 2.3, Y = 0.8, Size = 0.45 }), groundRing(2.2, 6, nil, -0.3, 0.14) },
	Citrine = { Motes({ Count = 10, Speed = 0.4, Size = 0.2 }), groundRing(2.4, 12, nil, 0.3, 0.14) },
	Carnelian = { embers(12, { Height = 6 }) },
	Malachite = { groundRing(3.1, 40, nil, 0.25, 0.18), groundRing(2.4, 40, nil, -0.35, 0.14), groundRing(1.7, 40, nil, 0.5, 0.1) },
	Turquoise = { Pulse({ Interval = 2.4, Radius = 4.5, Width = 0.3 }) },
	Moonstone = { Orbit({ Count = 1, Shape = "Orb", Radius = 2.6, Y = 2.2, Size = 0.7, Speed = 0.5 }), halo(1, 32, nil, { Transparency = 0.35 }) },

	----------------------------------------------------------------------------
	-- 1 in 1,000 .. 1 in 75,000: two or three layers
	----------------------------------------------------------------------------
	Sunstone = { halo(1.1, 12, 5, { Speed = 0.5 }), Motes({ Count = 8, Speed = 0.35 }) },
	Garnet = { Orbit({ Count = 3, Radius = 2.4, Y = 0.5, Size = 0.5 }), groundRing(2.6, 6, nil, 0.3) },
	Topaz = { Pillars({ Count = 4, Radius = 2.3, Height = 7, Width = 0.4 }), groundRing(2.3, 24) },
	Peridot = { petals(8, { Radius = 2.8, Height = 7 }), groundRing(2.4, 5, 2, 0.35) },
	Aquamarine = { Pulse({ Interval = 2, Radius = 5, Width = 0.3 }), Motes({ Count = 10, Speed = 0.3, Size = 0.3, Swirl = 0.3 }) },
	Tourmaline = { Helix({ Strands = 2, Radius = 1.9, Height = 6.5, Turns = 1.2, Width = 0.22 }), groundRing(2.1, 24) },
	Zircon = { Stars({ Count = 12, Radius = 4 }), groundRing(2.5, 8, 3, 0.4) },
	Spinel = { Orbit({ Count = 4, Shape = "Shard", Radius = 2.5, Y = 0.8, Tilt = 20, Size = 0.45 }), halo(0.9) },
	Iolite = { Ring({ Y = 0.6, Radius = 2.6, Tilt = 30, Speed = 0.9, Width = 0.16 }), Ring({ Y = 0.6, Radius = 2.6, Tilt = -30, Speed = -0.9, Width = 0.16 }), Motes({ Count = 6, Speed = 0.3 }) },
	Labradorite = { groundRing(2.8, 32, nil, 0.4), Orbit({ Count = 3, Shape = "Orb", Radius = 2.4, Y = 1.2, Size = 0.3, Speed = 1.8, Trail = true }) },
	Chrysoberyl = { Orbit({ Count = 2, Mode = "Figure8", Radius = 3, Y = 1, Size = 0.45, Speed = 1.3 }), groundRing(2.4, 16) },
	Kunzite = { petals(12), halo(0.95, 32) },
	Morganite = { Wings({ Feathers = 2, Span = 3.2, Size = 0.7, Glass = false }), Motes({ Count = 8, Speed = 0.3 }) },
	Tanzanite = { Helix({ Strands = 3, Radius = 2, Height = 7, Turns = 1.4, Width = 0.2 }), Orbit({ Count = 2, Radius = 2.6, Y = 1.6, Size = 0.45 }) },
	Sapphire = { Orbit({ Count = 3, Radius = 2.6, Y = 0.8, Size = 0.55, Trail = true }), groundRing(2.8, 10, 3, 0.3), Pulse({ Interval = 2.6, Radius = 5 }) },

	----------------------------------------------------------------------------
	-- 1 in 100,000 .. 1 in 7,500,000: three or four layers
	----------------------------------------------------------------------------
	Ruby = { Crown({ Count = 6, Height = 0.9 }), embers(14), groundRing(2.9, 5, 2, 0.35) },
	Emerald = { Monoliths({ Count = 3, Radius = 3.2, Size = 0.8 }), groundRing(2.9, 8, nil, 0.25), Motes({ Count = 10, Speed = 0.3 }) },
	Opal = { Orbit({ Count = 4, Shape = "Orb", Radius = 2.6, Y = 0.8, Size = 0.35, Trail = true, Rainbow = true, Speed = 1.6 }), Ring({ Ground = true, Y = 0.15, Radius = 3, Rainbow = true, Speed = 0.4 }) },
	Azurite = { Pulse({ Interval = 2.2, Radius = 6 }), Stars({ Count = 16, Radius = 4.5 }), halo(1) },
	Rhodonite = { Mandala({ Count = 8, Radius = 2.4, Size = 0.8 }), petals(10) },
	Larimar = { Helix({ Strands = 2, Radius = 2.6, Height = 4, Turns = 2.5, Width = 0.35, Speed = 0.8 }), Pulse({ Interval = 1.8, Radius = 5.5, Sides = 40 }), Motes({ Count = 10, Size = 0.32, Speed = 0.25, Swirl = 0.2 }) },
	Charoite = { Lightning({ Arcs = 2, Radius = 2.4, Height = 5.5, Rate = 0.12 }), groundRing(2.6, 24, nil, 0.6) },
	Sugilite = { Orbit({ Count = 3, Shape = "Orb", Mode = "Atom", Radius = 2.6, Size = 0.3, Speed = 2, Trail = true }), Crest({ Size = 0.6, Y = 3.6 }) },
	Prehnite = { Pillars({ Count = 6, Radius = 2.5, Height = 8 }), halo(1), Motes({ Count = 10 }) },
	Alexandrite = { halo(1.05, 32, nil, { Rainbow = true }), Orbit({ Count = 3, Radius = 2.6, Y = 0.9, Size = 0.5, Rainbow = true }), Motes({ Count = 12, Rainbow = true }) },
	Benitoite = { Stars({ Count = 20, Radius = 4.8 }), Orbit({ Count = 6, Shape = "Shard", Radius = 2.8, Y = 0.4, Size = 0.4, Speed = 0.8 }), groundRing(3, 6, nil, 0.3) },
	Tsavorite = { Monoliths({ Count = 4, Radius = 3.4 }), Helix({ Strands = 2, Radius = 2, Height = 7 }), Pulse({ Interval = 2.6, Radius = 5 }) },
	Demantoid = { Crest({ Size = 0.8, Y = 3.8 }), Orbit({ Count = 4, Radius = 2.7, Y = 0.6, Size = 0.45, Trail = true }), groundRing(2.8, 24) },
	Paraiba = { Wings({ Feathers = 3, Span = 4, Size = 0.85 }), Pulse({ Interval = 2, Radius = 5.5 }), Motes({ Count = 12, Speed = 0.4 }) },
	Jadeite = { Mandala({ Count = 10, Radius = 2.6 }), halo(1), Motes({ Count = 12 }), groundRing(2.6, 8, 3, 0.3) },

	----------------------------------------------------------------------------
	-- 1 in 10,000,000 .. 1 in 600,000,000: four or five layers
	----------------------------------------------------------------------------
	BlackOpal = { Orbit({ Count = 5, Shape = "Orb", Radius = 2.8, Y = 0.8, Size = 0.35, Trail = true, Rainbow = true, Speed = 1.4 }), Ring({ Ground = true, Y = 0.15, Radius = 3.2, Rainbow = true, Sides = 6, Speed = 0.3 }), Stars({ Count = 18, Radius = 4.6 }) },
	StarSapphire = { Crest({ Size = 0.8, Y = 3.9 }), halo(1.2, 12, 5, { Y = 3.9, Tilt = 0, Speed = 0.6 }), Stars({ Count = 22, Radius = 4.8 }), Orbit({ Count = 3, Radius = 2.8, Y = 0.6, Size = 0.5 }) },
	RedBeryl = { Crown({ Count = 8, Height = 1, Tall = true }), Wings({ Feathers = 3, Span = 4.2, Size = 0.9 }), embers(16) },
	Grandidierite = { Helix({ Strands = 3, Radius = 2.2, Height = 7.5, Turns = 1.6 }), Monoliths({ Count = 3, Radius = 3.6, Size = 1.1 }), Pulse({ Interval = 2.4, Radius = 6 }) },
	Taaffeite = { Mandala({ Count = 12, Radius = 2.6, Rings = 2 }), Orbit({ Count = 2, Mode = "Figure8", Radius = 3.4, Y = 0.8, Size = 0.5, Trail = true }), petals(14) },
	Musgravite = { Pillars({ Count = 8, Radius = 2.6, Height = 9 }), Lightning({ Arcs = 2, Rate = 0.14 }), groundRing(2.9, 8, 3, 0.5) },
	Painite = { Monoliths({ Count = 5, Radius = 3.6 }), Crown({ Count = 7, Height = 0.9 }), Pulse({ Interval = 2.2, Radius = 6.5 }) },
	Poudretteite = { Wings({ Feathers = 4, Span = 4.6, Size = 0.9 }), Orbit({ Count = 4, Shape = "Orb", Radius = 2.6, Y = 1.4, Size = 0.3, Speed = 1.8 }), halo(1.05, 32) },
	Jeremejevite = { Orbit({ Count = 4, Shape = "Orb", Mode = "Atom", Radius = 2.8, Size = 0.32, Speed = 2.2, Trail = true }), Stars({ Count = 20 }), groundRing(3, 24, nil, 0.5) },
	Serendibite = { Eclipse({ Radius = 1.4, Y = 2.4 }), Motes({ Count = 14, Direction = -1, Speed = 0.25 }), groundRing(2.8, 12, 5, 0.3) },
	Hibonite = { Helix({ Strands = 4, Radius = 2.3, Height = 7.5, Turns = 1.3, Width = 0.2 }), Crest({ Size = 0.8, Y = 4 }), Pulse({ Interval = 2.4, Radius = 6 }) },
	Kyawthuite = { Crown({ Count = 9, Height = 1, Jewel = true }), Mandala({ Count = 10, Radius = 2.7 }), embers(14) },
	FireOpal = { embers(22, { Height = 9 }), Helix({ Strands = 2, Radius = 2.1, Height = 7, Turns = 1.8, Speed = 2.2 }), Crown({ Count = 7, Height = 1.1, Tall = true }), Pulse({ Interval = 1.6, Radius = 5 }) },
	Diamond = { Crest({ Size = 1.1, Y = 4.2 }), Monoliths({ Count = 6, Radius = 3.8, Size = 0.9 }), Stars({ Count = 26, Radius = 5 }), groundRing(3.4, 8, 3, 0.35) },

	----------------------------------------------------------------------------
	-- 1 in 750,000,000 and rarer: signature auras
	----------------------------------------------------------------------------
	Starquartz = { Stars({ Count = 30, Radius = 5.2 }), Orbit({ Count = 5, Shape = "Shard", Radius = 3, Y = 0.8, Size = 0.5 }), halo(1.2, 10, 3), Pulse({ Interval = 2.2, Radius = 6 }), Crest({ Size = 0.8, Y = 4.2 }) },
	MoonveilOpal = {
		Orbit({ Count = 1, Shape = "Orb", Radius = 3.2, Y = 3, Size = 1.1, Speed = 0.35 }),
		Helix({ Strands = 3, Radius = 2.6, Height = 8, Turns = 0.8, Width = 0.6, Transparency = 0.5, Speed = 0.5 }),
		Motes({ Count = 18, Direction = -1, Speed = 0.18, Radius = 3.6, Height = 9 }),
		halo(1.1, 32, nil, { Rainbow = true, Transparency = 0.3 }),
	},
	SunflareTopaz = { halo(1.3, 12, 5, { Width = 0.2 }), Pillars({ Count = 8, Radius = 2.6, Height = 10 }), embers(20), Pulse({ Interval = 1.8, Radius = 6.5 }), Crown({ Count = 10, Height = 1, Tall = true }) },
	Auroralite = { Helix({ Strands = 3, Radius = 3, Height = 9, Turns = 0.7, Width = 0.9, Rainbow = true, Transparency = 0.45, Speed = 0.6 }), Stars({ Count = 26, Radius = 5 }), Ring({ Ground = true, Y = 0.15, Radius = 3.4, Rainbow = true, Speed = 0.3 }), Motes({ Count = 14, Rainbow = true, Speed = 0.25 }) },
	Nebulite = { Stars({ Count = 40, Radius = 5.5 }), Orbit({ Count = 3, Shape = "Orb", Mode = "Atom", Radius = 3, Size = 0.4, Trail = true, TrailLife = 0.7 }), Helix({ Strands = 2, Radius = 3, Height = 7, Turns = 0.9, Width = 0.7, Transparency = 0.5 }), Motes({ Count = 14 }) },
	Glimmerstone = { Stars({ Count = 32, Radius = 4.8 }), Motes({ Count = 22, Flicker = true, Speed = 0.35 }), Orbit({ Count = 6, Radius = 2.9, Y = 0.8, Size = 0.4, Speed = 1.4 }), groundRing(3.1, 6, nil, 0.4) },
	FrostheartSpinel = {
		Motes({ Count = 26, Direction = -1, Speed = 0.16, Radius = 4, Height = 10, Size = 0.2 }),
		Crown({ Count = 8, Height = 1.2, Tall = true }),
		Monoliths({ Count = 5, Radius = 3.6 }),
		groundRing(3.2, 6, nil, 0.2, 0.3),
		Pulse({ Interval = 3, Radius = 6, Sides = 6 }),
	},
	Emberglass = { embers(30, { Height = 10, Radius = 3 }), Helix({ Strands = 2, Radius = 2.2, Height = 8, Turns = 2, Speed = 2.6 }), Pillars({ Count = 6, Radius = 2.4, Height = 8 }), Crown({ Count = 7, Height = 1.1 }), Pulse({ Interval = 1.5, Radius = 5 }) },
	Voidshard = { Eclipse({ Radius = 1.7, Y = 2.5, Rays = 14 }), Orbit({ Count = 6, Shape = "Shard", Radius = 3, Y = 0.6, Size = 0.55, Speed = -1.1 }), Motes({ Count = 18, Direction = -1, Speed = 0.3, Radius = 4.2 }), groundRing(3.2, 7, 3, -0.4) },
	Stormcore = { Lightning({ Arcs = 4, Radius = 2.8, Height = 7, Rate = 0.07 }), Pulse({ Interval = 1.4, Radius = 6 }), Orbit({ Count = 3, Shape = "Orb", Radius = 2.4, Y = 1.4, Size = 0.35, Speed = 3, Trail = true }), Ring({ Y = 0.8, Radius = 3, Tilt = 25, Speed = 1.6, Wobble = 0.2 }), Motes({ Count = 14, Flicker = true, Speed = 0.6 }) },
	Bloomstone = { petals(30, { Radius = 4 }), Wings({ Feathers = 3, Span = 4.2, Size = 0.85, Glass = false }), groundRing(3.2, 10, 3, 0.3), Crown({ Count = 6, Height = 0.8, Jewel = true }) },
	DuskmereOnyx = { Eclipse({ Radius = 1.6, Y = 2.6 }), Wings({ Feathers = 4, Span = 5, Size = 1 }), Motes({ Count = 16, Speed = 0.3 }), groundRing(3.2, 32, nil, 0.3) },
	Dawnspire = { Pillars({ Count = 10, Radius = 2.8, Height = 11 }), Crest({ Size = 1, Y = 4.4 }), Wings({ Feathers = 3, Span = 4.4, Size = 0.9 }), halo(1.1, 32) },
	Cometite = { Orbit({ Count = 4, Shape = "Orb", Radius = 3.2, Y = 0.8, Size = 0.45, Speed = 2.4, Trail = true, TrailLife = 0.9 }), Orbit({ Count = 1, Mode = "Figure8", Radius = 4, Y = 2.4, Size = 0.6, Speed = 1.6, Trail = true, TrailLife = 1.1 }), Stars({ Count = 22, Radius = 5 }), groundRing(3.2, 24) },
	Lunarine = { Orbit({ Count = 2, Shape = "Orb", Radius = 3.4, Y = 2.2, Size = 0.8, Speed = 0.5 }), Crest({ Size = 0.9, Y = 4.2 }), halo(1.2, 32), Motes({ Count = 18, Direction = -1, Speed = 0.2 }), Mandala({ Count = 8, Radius = 2.4 }) },
	Solarite = { Crest({ Size = 1.4, Y = 4.6, Speed = 0.8 }), halo(1.6, 16, 7, { Y = 4.6, Tilt = 0, Speed = 0.4, Width = 0.2 }), Pillars({ Count = 8, Radius = 2.6, Height = 10 }), Pulse({ Interval = 1.8, Radius = 7 }), embers(20) },
	Prismora = { Helix({ Strands = 3, Radius = 2.4, Height = 8, Turns = 1.4, Rainbow = true }), Ring({ Ground = true, Y = 0.15, Radius = 3.4, Rainbow = true, Sides = 7, Step = 3 }), Orbit({ Count = 5, Radius = 2.9, Y = 0.8, Size = 0.45, Rainbow = true, Trail = true }), Wings({ Feathers = 4, Span = 4.6, Size = 0.9, Rainbow = true }), Stars({ Count = 20 }) },
	MirageOpal = { Monoliths({ Count = 5, Radius = 3.8 }), Orbit({ Count = 2, Shape = "Orb", Mode = "Figure8", Radius = 3.6, Y = 1, Size = 0.5, Rainbow = true, Trail = true }), Helix({ Strands = 2, Radius = 3, Height = 6, Turns = 0.6, Width = 0.8, Transparency = 0.55 }), Pulse({ Interval = 2.4, Radius = 6.5 }) },
	Thunderjade = { Lightning({ Arcs = 5, Radius = 3, Height = 8, Rate = 0.06 }), Crown({ Count = 8, Height = 1.1, Tall = true }), Pillars({ Count = 6, Radius = 2.6, Height = 9 }), Pulse({ Interval = 1.2, Radius = 6 }), Orbit({ Count = 3, Shape = "Shard", Radius = 2.8, Y = 0.8, Size = 0.5, Speed = 2 }) },
	AbyssalSapphire = { Motes({ Count = 22, Size = 0.32, Speed = 0.2, Swirl = 0.3, Radius = 3.6 }), Helix({ Strands = 3, Radius = 2.6, Height = 8, Turns = 1, Width = 0.5, Transparency = 0.45, Speed = -0.8 }), Pulse({ Interval = 2.8, Radius = 7 }), Eclipse({ Radius = 1.3, Y = 2.4 }), groundRing(3.4, 40, nil, 0.2) },

	----------------------------------------------------------------------------
	-- 1 in 400,000,000,000 and rarer: the legends
	----------------------------------------------------------------------------
	Starheart = { Crest({ Size = 1.2, Y = 4.4 }), Stars({ Count = 42, Radius = 5.6 }), Orbit({ Count = 4, Shape = "Orb", Mode = "Atom", Radius = 3.2, Size = 0.4, Trail = true }), halo(1.3, 10, 3, { Y = 4.4 }), Pulse({ Interval = 2, Radius = 7 }) },
	Eclipsium = { Eclipse({ Radius = 2.1, Y = 2.8, Rays = 18 }), Wings({ Feathers = 5, Span = 5.4, Size = 1 }), Motes({ Count = 20, Direction = -1, Speed = 0.3 }), Lightning({ Arcs = 2, Rate = 0.15 }), groundRing(3.6, 32, nil, 0.3) },
	Chronocrystal = { halo(1.6, 12, nil, { Y = 3.4, Tilt = 0, Speed = -0.25, Width = 0.18 }), Crown({ Count = 12, Radius = 1.6, Y = 2.9, Height = 0.6, Speed = -0.25 }), Mandala({ Count = 12, Radius = 2.9, Rings = 2, Speed = 0.2 }), Orbit({ Count = 2, Mode = "Figure8", Radius = 3.6, Y = 0.8, Size = 0.5, Trail = true }), Pulse({ Interval = 1, Radius = 5 }) },
	NovaPrism = { Pulse({ Interval = 1.1, Radius = 8, Width = 0.6 }), Stars({ Count = 30, Radius = 5.4 }), Orbit({ Count = 6, Radius = 3, Y = 0.8, Size = 0.45, Speed = 1.8 }), Pillars({ Count = 8, Radius = 2.8, Height = 10 }), Crest({ Size = 1.1, Y = 4.4, Rainbow = true }), Helix({ Strands = 2, Radius = 2.2, Height = 8 }) },
	InfinityShard = { Orbit({ Count = 3, Mode = "Figure8", Radius = 3.8, Y = 1, Size = 0.5, Trail = true, TrailLife = 0.8 }), Orbit({ Count = 2, Mode = "Figure8", Radius = 3, Y = 0, Tilt = 90, Size = 0.4, Trail = true, Speed = -1.4 }), groundRing(3.4, 32), Mandala({ Count = 10, Radius = 2.6 }), Stars({ Count = 24 }) },
	Galaxite = { Stars({ Count = 52, Radius = 6 }), Helix({ Strands = 4, Radius = 3.2, Height = 4, Turns = 1.2, Width = 0.6, Rainbow = true, Transparency = 0.45, Speed = 0.5 }), Orbit({ Count = 4, Shape = "Orb", Mode = "Atom", Radius = 3.4, Size = 0.38, Trail = true }), Crest({ Size = 0.9, Y = 4.4 }), Pulse({ Interval = 2.6, Radius = 7 }) },
	Aetherium = { Wings({ Feathers = 5, Span = 5.8, Size = 1.05 }), Pillars({ Count = 8, Radius = 2.8, Height = 11 }), Crest({ Size = 1, Y = 4.4 }), Motes({ Count = 20, Speed = 0.35 }), halo(1.2, 32) },
	Seraphite = { Wings({ Feathers = 6, Span = 6.6, Size = 1.15 }), Crown({ Count = 9, Height = 1.1, Tall = true, Jewel = true }), halo(1.25, 32, nil, { Y = 3.2, Width = 0.2 }), Pillars({ Count = 6, Radius = 2.6, Height = 11 }), Motes({ Count = 18, Direction = -1, Speed = 0.2 }) },
	Riftstone = { Lightning({ Arcs = 4, Radius = 3.2, Height = 8, Rate = 0.08 }), Eclipse({ Radius = 1.7, Y = 2.6 }), Monoliths({ Count = 5, Radius = 4 }), Pulse({ Interval = 1.6, Radius = 6.5 }), Motes({ Count = 16, Direction = -1, Speed = 0.35 }) },
	Dreamglass = { petals(24, { Rainbow = true, Radius = 4 }), Orbit({ Count = 5, Shape = "Orb", Radius = 3, Y = 1, Size = 0.4, Rainbow = true, Trail = true }), Helix({ Strands = 3, Radius = 2.6, Height = 8, Turns = 1, Width = 0.5, Rainbow = true, Transparency = 0.4 }), Stars({ Count = 26 }), Mandala({ Count = 12, Radius = 2.7 }) },
	Wishstone = { Stars({ Count = 44, Radius = 5.6 }), Orbit({ Count = 3, Shape = "Orb", Radius = 4, Y = 2.5, Size = 0.5, Speed = 1.2, Trail = true, TrailLife = 1.2 }), Crest({ Size = 1.1, Y = 4.4 }), Motes({ Count = 18, Flicker = true }), halo(1.4, 10, 3, { Y = 4.4 }) },
	Paradoxite = { Ring({ Y = 0.6, Radius = 3.2, Tilt = 60, Speed = 1.2, Width = 0.2 }), Ring({ Y = 0.6, Radius = 3.2, Tilt = -60, Speed = -1.2, Width = 0.2 }), Orbit({ Count = 3, Shape = "Orb", Mode = "Atom", Radius = 2.6, Size = 0.36, Speed = -2, Trail = true }), Helix({ Strands = 2, Radius = 2.2, Height = 8, Speed = -1.6 }), Monoliths({ Count = 4, Radius = 4, Speed = -0.4 }), Lightning({ Arcs = 2, Rate = 0.16 }) },
	Etherveil = { Helix({ Strands = 4, Radius = 2.9, Height = 9, Turns = 0.6, Width = 1, Transparency = 0.55, Speed = 0.4 }), Wings({ Feathers = 5, Span = 5.6, Size = 1 }), Pillars({ Count = 10, Radius = 3, Height = 12 }), Stars({ Count = 30 }), Crest({ Size = 1, Y = 4.4 }) },
	SupernovaDiamond = { Pulse({ Interval = 0.9, Radius = 9, Width = 0.7 }), Pulse({ Interval = 2.7, Radius = 12, Width = 1 }), Crest({ Size = 1.4, Y = 4.6, Rainbow = true }), Stars({ Count = 40, Radius = 6 }), Pillars({ Count = 10, Radius = 3, Height = 12 }), Monoliths({ Count = 6, Radius = 4.2 }), embers(20) },
	Quasarine = { Pillars({ Count = 2, Radius = 0.2, Height = 18, Width = 1.6, Speed = 0 }), Eclipse({ Radius = 1.6, Y = 2.5 }), Helix({ Strands = 3, Radius = 3.4, Height = 3, Turns = 1.5, Width = 0.6, Speed = 2.4 }), Pulse({ Interval = 1.4, Radius = 7.5 }), Orbit({ Count = 4, Shape = "Orb", Mode = "Atom", Radius = 3.2, Size = 0.36, Trail = true }), Stars({ Count = 30 }) },
	SingularityGem = { Eclipse({ Radius = 2.3, Y = 2.8, Rays = 20 }), Motes({ Count = 30, Direction = -1, Speed = 0.45, Radius = 5, Swirl = 2.4 }), Lightning({ Arcs = 3, Rate = 0.1 }), Orbit({ Count = 5, Shape = "Orb", Mode = "Atom", Radius = 3.4, Size = 0.32, Speed = 3, Trail = true }), groundRing(4, 40, nil, 1.2), Helix({ Strands = 4, Radius = 3.6, Height = 2, Turns = 2, Width = 0.4, Speed = 3 }) },
	GenesisCrystal = { Monoliths({ Count = 6, Radius = 4.2, Size = 1.2 }), Crest({ Size = 1.3, Y = 4.6 }), Wings({ Feathers = 5, Span = 5.6, Size = 1 }), Pulse({ Interval = 2, Radius = 8 }), Motes({ Count = 22 }), groundRing(3.8, 6, nil, 0.25, 0.3) },
	AstralCrown = { Crown({ Count = 12, Radius = 1.3, Height = 1.4, Tall = true, Jewel = true }), Wings({ Feathers = 6, Span = 6.4, Size = 1.1 }), Stars({ Count = 40, Radius = 5.8 }), Mandala({ Count = 14, Radius = 3, Rings = 2 }), halo(1.6, 12, 5, { Y = 4.6 }), Pulse({ Interval = 2.2, Radius = 8 }) },
	PrimordialShard = { Monoliths({ Count = 8, Radius = 4.6, Size = 1.2 }), Lightning({ Arcs = 4, Rate = 0.09 }), Eclipse({ Radius = 1.8, Y = 2.7 }), Helix({ Strands = 3, Radius = 2.8, Height = 9, Turns = 1.6 }), Pulse({ Interval = 1.8, Radius = 9 }), Stars({ Count = 34, Radius = 6 }) },
	TheFirstLight = {
		Pillars({ Count = 12, Radius = 3.2, Height = 16, Width = 0.7 }),
		Wings({ Feathers = 7, Span = 7.4, Size = 1.2, Rainbow = true }),
		Crest({ Size = 1.5, Y = 4.8, Rainbow = true }),
		Crown({ Count = 12, Height = 1.2, Tall = true }),
		Mandala({ Count = 16, Radius = 3.2, Rings = 2 }),
		Stars({ Count = 48, Radius = 6.5 }),
		Pulse({ Interval = 1.5, Radius = 10, Width = 0.8 }),
		Helix({ Strands = 4, Radius = 2.6, Height = 10, Turns = 1.4, Rainbow = true }),
	},
}

--------------------------------------------------------------------------------
-- Power-up: every aura also bursts into flame around the body, glows, and the
-- rarer ones grow crystal armour, a diadem and finally transform with a giant
-- crystal sovereign rising behind them. All of it scales with rarity.
--------------------------------------------------------------------------------

-- How each gem's flame burns (default: by position in the catalogue).
local FLAME_STYLE: { [string]: string } = {
	-- fire
	Carnelian = "Inferno", Ruby = "Inferno", Garnet = "Inferno", Sunstone = "Inferno", FireOpal = "Inferno",
	Emberglass = "Inferno", SunflareTopaz = "Inferno", Solarite = "Inferno", SupernovaDiamond = "Inferno", RedBeryl = "Inferno",
	-- ice and water
	Quartz = "Frost", Moonstone = "Frost", Aquamarine = "Frost", Larimar = "Frost", Diamond = "Frost",
	Starquartz = "Frost", FrostheartSpinel = "Frost", Lunarine = "Frost", Calcite = "Frost",
	-- shadow
	Onyx = "Void", Obsidian = "Void", Hematite = "Void", Voidshard = "Void", DuskmereOnyx = "Void",
	Eclipsium = "Void", SingularityGem = "Void", AbyssalSapphire = "Void", Riftstone = "Void", Serendibite = "Void",
	-- storm
	Pyrite = "Electric", Charoite = "Electric", Musgravite = "Electric", Stormcore = "Electric", Thunderjade = "Electric",
	Paradoxite = "Electric", PrimordialShard = "Electric",
	-- soft and dreamy
	Kunzite = "Wisp", Morganite = "Wisp", Rhodonite = "Wisp", Bloomstone = "Wisp", Dreamglass = "Wisp",
	MoonveilOpal = "Wisp", Etherveil = "Wisp", Auroralite = "Wisp", Nebulite = "Wisp", MirageOpal = "Wisp",
	-- rising light
	Seraphite = "Torrent", Aetherium = "Torrent", Dawnspire = "Torrent", NovaPrism = "Torrent", Quasarine = "Torrent",
	TheFirstLight = "Torrent", Wishstone = "Torrent", Starheart = "Torrent",
}
local CYCLE = { "Blaze", "Spike", "Blaze", "Wisp", "Spike", "Torrent" }

local COLOSSUS_VARIANT = { "Spire", "Bloom", "Halo" }

local cache: { [string]: { { [string]: any } } } = {}

-- The full layer list for a gem: power-up layers + its signature recipe.
function Recipes.Build(gem: { Id: string, Index: number }): { { [string]: any } }?
	local signature = R[gem.Id]
	if not signature then
		return nil
	end
	local cached = cache[gem.Id]
	if cached then
		return cached
	end
	local i = gem.Index
	local list: { { [string]: any } } = {}

	-- Flames for everyone, from a strong burn to a towering inferno.
	table.insert(list, L("Flame")({
		Style = FLAME_STYLE[gem.Id] or CYCLE[i % #CYCLE + 1],
		Count = 12 + i * 0.22,
		Height = 5.5 + i * 0.085,
		Radius = 1.55 + i * 0.006,
		Width = 1 + i * 0.004,
		Shells = if i < 20 then 2 else 3,
	}))
	table.insert(list, L("Charge")({ Fill = 0.8 - i * 0.0025, Outline = 0.25 - i * 0.0015 }))
	-- Sparks rising through the flames.
	if i >= 8 then
		table.insert(list, Motes({ Count = 6 + math.floor(i * 0.14), Flicker = true, Speed = 0.6, Swirl = 0.9, Size = 0.16, Height = 6 + i * 0.06, Radius = 2 }))
	end
	-- Crystal armour from "1 in 100,000".
	if i >= 32 then
		table.insert(list, L("Armor")({ Gauntlets = i >= 47, Back = if i >= 61 then 5 elseif i >= 47 then 3 else 0, Scale = 0.9 + (i - 32) * 0.006 }))
	end
	-- A crystal diadem from "1 in 10,000,000".
	if i >= 47 then
		table.insert(list, L("Diadem")({ Spikes = if i >= 81 then 7 else 5, Height = 1.4 + (i - 47) * 0.02, Style = if i % 2 == 0 then "Crown" else "Spire" }))
	end
	-- Transformation from "1 in 750,000,000": a giant crystal sovereign.
	if i >= 61 then
		table.insert(list, L("Colossus")({ Scale = 2.4 + (i - 61) * 0.045, Variant = COLOSSUS_VARIANT[i % 3 + 1] }))
	end

	for _, spec in signature do
		table.insert(list, spec)
	end
	cache[gem.Id] = list
	return list
end

-- The signature layers only.
function Recipes.Get(gemId: string): { { [string]: any } }?
	return R[gemId]
end

Recipes.All = R

return Recipes
