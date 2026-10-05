--!strict
-- GemCatalog
-- The 100 collectible gems. A gem is purely cosmetic: it decides the aura
-- (colours + effects) your character wears. Everyone fights with the same kit.
--
-- Odds are shown to players as "1 in N" (bigger N = rarer). Every gem except
-- the first rolls with probability exactly 1/N; the first gem (Quartz) takes
-- whatever probability is left, so the odds always add up to 100%.
-- Hidden pity lives on the server (ServerScriptService.Modules.RollConfig) and
-- is intentionally not in this shared module.

local GemCatalog = {}

export type Gem = {
	Id: string,
	Name: string,
	Index: number, -- 1 = most common, 100 = rarest
	Odds: number, -- displayed "1 in Odds"
	Probability: number, -- true per-roll chance (0-1) before pity
	Color: Color3, -- primary aura colour
	Accent: Color3, -- secondary colour for gradients
}

local rgb = Color3.fromRGB

local function gem(id: string, name: string, odds: number, color: Color3, accent: Color3): Gem
	return {
		Id = id,
		Name = name,
		Index = 0,
		Odds = odds,
		Probability = 0,
		Color = color,
		Accent = accent,
	}
end

-- Ordered from most common to rarest.
GemCatalog.List = {
	gem("Quartz", "Quartz", 2, rgb(240, 240, 250), rgb(200, 210, 235)),
	gem("Jasper", "Jasper", 6, rgb(190, 80, 60), rgb(235, 145, 95)),
	gem("Agate", "Agate", 10, rgb(205, 150, 120), rgb(150, 185, 210)),
	gem("Onyx", "Onyx", 15, rgb(45, 42, 58), rgb(120, 105, 150)),
	gem("Obsidian", "Obsidian", 30, rgb(32, 26, 48), rgb(130, 70, 170)),
	gem("Calcite", "Calcite", 40, rgb(250, 240, 200), rgb(255, 200, 175)),
	gem("Fluorite", "Fluorite", 50, rgb(150, 110, 230), rgb(100, 225, 205)),
	gem("Hematite", "Hematite", 75, rgb(95, 95, 108), rgb(180, 70, 70)),
	gem("Pyrite", "Pyrite", 100, rgb(225, 195, 95), rgb(175, 155, 85)),
	gem("Jade", "Jade", 120, rgb(80, 180, 120), rgb(175, 232, 185)),
	gem("Amethyst", "Amethyst", 150, rgb(160, 90, 220), rgb(222, 175, 255)),
	gem("Citrine", "Citrine", 200, rgb(250, 200, 60), rgb(255, 150, 55)),
	gem("Carnelian", "Carnelian", 300, rgb(222, 92, 52), rgb(255, 172, 115)),
	gem("Malachite", "Malachite", 400, rgb(30, 140, 92), rgb(122, 222, 165)),
	gem("Turquoise", "Turquoise", 500, rgb(60, 200, 200), rgb(155, 242, 232)),
	gem("Moonstone", "Moonstone", 750, rgb(212, 222, 255), rgb(172, 202, 255)),
	gem("Sunstone", "Sunstone", 1000, rgb(255, 152, 82), rgb(255, 212, 125)),
	gem("Garnet", "Garnet", 1200, rgb(150, 22, 42), rgb(222, 72, 92)),
	gem("Topaz", "Topaz", 1500, rgb(255, 190, 92), rgb(125, 202, 255)),
	gem("Peridot", "Peridot", 2000, rgb(172, 222, 62), rgb(222, 250, 145)),
	gem("Aquamarine", "Aquamarine", 3000, rgb(112, 210, 240), rgb(192, 242, 255)),
	gem("Tourmaline", "Tourmaline", 4000, rgb(240, 92, 152), rgb(92, 202, 132)),
	gem("Zircon", "Zircon", 6000, rgb(92, 162, 255), rgb(222, 242, 255)),
	gem("Spinel", "Spinel", 7500, rgb(255, 62, 122), rgb(255, 152, 192)),
	gem("Iolite", "Iolite", 10000, rgb(92, 92, 202), rgb(172, 152, 242)),
	gem("Labradorite", "Labradorite", 15000, rgb(62, 92, 132), rgb(92, 232, 202)),
	gem("Chrysoberyl", "Chrysoberyl", 20000, rgb(202, 212, 92), rgb(242, 242, 172)),
	gem("Kunzite", "Kunzite", 25000, rgb(240, 162, 222), rgb(222, 192, 255)),
	gem("Morganite", "Morganite", 40000, rgb(255, 182, 172), rgb(255, 222, 212)),
	gem("Tanzanite", "Tanzanite", 50000, rgb(82, 62, 202), rgb(162, 112, 242)),
	gem("Sapphire", "Sapphire", 75000, rgb(32, 82, 222), rgb(122, 172, 255)),
	gem("Ruby", "Ruby", 100000, rgb(230, 22, 62), rgb(255, 112, 132)),
	gem("Emerald", "Emerald", 120000, rgb(22, 182, 92), rgb(122, 242, 172)),
	gem("Opal", "Opal", 200000, rgb(242, 232, 255), rgb(132, 232, 222)),
	gem("Azurite", "Azurite", 250000, rgb(22, 62, 182), rgb(62, 142, 242)),
	gem("Rhodonite", "Rhodonite", 300000, rgb(222, 92, 112), rgb(70, 58, 70)),
	gem("Larimar", "Larimar", 400000, rgb(112, 192, 232), rgb(232, 250, 255)),
	gem("Charoite", "Charoite", 600000, rgb(142, 72, 182), rgb(232, 192, 242)),
	gem("Sugilite", "Sugilite", 750000, rgb(152, 42, 172), rgb(242, 102, 202)),
	gem("Prehnite", "Prehnite", 1000000, rgb(182, 232, 142), rgb(242, 250, 202)),
	gem("Alexandrite", "Alexandrite", 1500000, rgb(42, 172, 142), rgb(172, 62, 162)),
	gem("Benitoite", "Benitoite", 2000000, rgb(62, 112, 255), rgb(182, 202, 255)),
	gem("Tsavorite", "Tsavorite", 3000000, rgb(42, 212, 82), rgb(182, 255, 162)),
	gem("Demantoid", "Demantoid", 4000000, rgb(122, 222, 62), rgb(255, 255, 182)),
	gem("Paraiba", "Paraiba", 5000000, rgb(0, 232, 232), rgb(122, 255, 212)),
	gem("Jadeite", "Jadeite", 7500000, rgb(0, 162, 102), rgb(202, 255, 222)),
	gem("BlackOpal", "Black Opal", 10000000, rgb(32, 32, 62), rgb(255, 122, 202)),
	gem("StarSapphire", "Star Sapphire", 15000000, rgb(42, 62, 182), rgb(255, 255, 255)),
	gem("RedBeryl", "Red Beryl", 20000000, rgb(202, 32, 82), rgb(255, 122, 172)),
	gem("Grandidierite", "Grandidierite", 25000000, rgb(92, 202, 192), rgb(202, 255, 245)),
	gem("Taaffeite", "Taaffeite", 40000000, rgb(202, 152, 222), rgb(255, 222, 250)),
	gem("Musgravite", "Musgravite", 50000000, rgb(122, 112, 152), rgb(222, 202, 255)),
	gem("Painite", "Painite", 60000000, rgb(182, 62, 42), rgb(255, 142, 92)),
	gem("Poudretteite", "Poudretteite", 80000000, rgb(242, 192, 232), rgb(255, 242, 255)),
	gem("Jeremejevite", "Jeremejevite", 120000000, rgb(142, 202, 255), rgb(242, 250, 255)),
	gem("Serendibite", "Serendibite", 150000000, rgb(32, 42, 82), rgb(122, 162, 255)),
	gem("Hibonite", "Hibonite", 200000000, rgb(72, 48, 36), rgb(255, 162, 82)),
	gem("Kyawthuite", "Kyawthuite", 300000000, rgb(255, 122, 32), rgb(255, 222, 122)),
	gem("FireOpal", "Fire Opal", 400000000, rgb(255, 92, 32), rgb(255, 202, 62)),
	gem("Diamond", "Diamond", 600000000, rgb(232, 250, 255), rgb(255, 255, 255)),
	gem("Starquartz", "Starquartz", 750000000, rgb(255, 250, 232), rgb(255, 212, 255)),
	gem("MoonveilOpal", "Moonveil Opal", 1000000000, rgb(202, 212, 255), rgb(255, 232, 250)),
	gem("SunflareTopaz", "Sunflare Topaz", 1500000000, rgb(255, 172, 42), rgb(255, 250, 182)),
	gem("Auroralite", "Auroralite", 2000000000, rgb(82, 255, 182), rgb(202, 122, 255)),
	gem("Nebulite", "Nebulite", 2500000000, rgb(122, 62, 202), rgb(255, 122, 202)),
	gem("Glimmerstone", "Glimmerstone", 4000000000, rgb(255, 242, 182), rgb(182, 255, 255)),
	gem("FrostheartSpinel", "Frostheart Spinel", 5000000000, rgb(142, 222, 255), rgb(255, 122, 172)),
	gem("Emberglass", "Emberglass", 7500000000, rgb(255, 82, 22), rgb(255, 202, 102)),
	gem("Voidshard", "Voidshard", 10000000000, rgb(22, 4, 42), rgb(162, 62, 255)),
	gem("Stormcore", "Stormcore", 12000000000, rgb(62, 82, 142), rgb(222, 242, 255)),
	gem("Bloomstone", "Bloomstone", 20000000000, rgb(255, 152, 202), rgb(152, 242, 142)),
	gem("DuskmereOnyx", "Duskmere Onyx", 25000000000, rgb(62, 32, 82), rgb(255, 142, 122)),
	gem("Dawnspire", "Dawnspire", 30000000000, rgb(255, 192, 162), rgb(172, 202, 255)),
	gem("Cometite", "Cometite", 40000000000, rgb(182, 232, 255), rgb(255, 255, 255)),
	gem("Lunarine", "Lunarine", 60000000000, rgb(182, 192, 255), rgb(92, 82, 182)),
	gem("Solarite", "Solarite", 75000000000, rgb(255, 222, 82), rgb(255, 122, 42)),
	gem("Prismora", "Prismora", 100000000000, rgb(255, 122, 122), rgb(122, 182, 255)),
	gem("MirageOpal", "Mirage Opal", 150000000000, rgb(255, 212, 172), rgb(152, 232, 255)),
	gem("Thunderjade", "Thunderjade", 200000000000, rgb(62, 222, 142), rgb(242, 255, 122)),
	gem("AbyssalSapphire", "Abyssal Sapphire", 300000000000, rgb(12, 22, 82), rgb(0, 202, 255)),
	gem("Starheart", "Starheart", 400000000000, rgb(255, 202, 232), rgb(255, 255, 202)),
	gem("Eclipsium", "Eclipsium", 600000000000, rgb(22, 12, 32), rgb(255, 182, 62)),
	gem("Chronocrystal", "Chronocrystal", 750000000000, rgb(212, 182, 122), rgb(122, 242, 255)),
	gem("NovaPrism", "Nova Prism", 1000000000000, rgb(255, 255, 255), rgb(255, 92, 202)),
	gem("InfinityShard", "Infinity Shard", 1500000000000, rgb(152, 122, 255), rgb(255, 255, 255)),
	gem("Galaxite", "Galaxite", 2000000000000, rgb(42, 22, 92), rgb(255, 152, 232)),
	gem("Aetherium", "Aetherium", 3000000000000, rgb(202, 255, 255), rgb(255, 222, 255)),
	gem("Seraphite", "Seraphite", 4000000000000, rgb(255, 255, 232), rgb(255, 212, 122)),
	gem("Riftstone", "Riftstone", 6000000000000, rgb(92, 0, 122), rgb(0, 255, 202)),
	gem("Dreamglass", "Dreamglass", 8000000000000, rgb(255, 192, 250), rgb(172, 222, 255)),
	gem("Wishstone", "Wishstone", 12000000000000, rgb(255, 242, 152), rgb(202, 182, 255)),
	gem("Paradoxite", "Paradoxite", 20000000000000, rgb(8, 8, 12), rgb(255, 255, 255)),
	gem("Etherveil", "Etherveil", 25000000000000, rgb(222, 232, 255), rgb(142, 122, 255)),
	gem("SupernovaDiamond", "Supernova Diamond", 40000000000000, rgb(255, 255, 255), rgb(255, 142, 62)),
	gem("Quasarine", "Quasarine", 50000000000000, rgb(62, 122, 255), rgb(255, 82, 202)),
	gem("SingularityGem", "Singularity Gem", 75000000000000, rgb(6, 0, 16), rgb(255, 255, 255)),
	gem("GenesisCrystal", "Genesis Crystal", 100000000000000, rgb(255, 250, 242), rgb(122, 255, 182)),
	gem("AstralCrown", "Astral Crown", 150000000000000, rgb(255, 215, 122), rgb(162, 122, 255)),
	gem("PrimordialShard", "Primordial Shard", 200000000000000, rgb(255, 122, 82), rgb(82, 202, 255)),
	gem("TheFirstLight", "The First Light", 300000000000000, rgb(255, 255, 255), rgb(255, 242, 212)),
} :: { Gem }

GemCatalog.ById = {} :: { [string]: Gem }

do
	local rest = 0
	for index, entry in GemCatalog.List do
		entry.Index = index
		assert(GemCatalog.ById[entry.Id] == nil, `GemCatalog: duplicate id {entry.Id}`)
		GemCatalog.ById[entry.Id] = entry
		if index > 1 then
			assert(entry.Odds > GemCatalog.List[index - 1].Odds, `GemCatalog: {entry.Id} must be rarer than the gem before it`)
			entry.Probability = 1 / entry.Odds
			rest += entry.Probability
		end
	end
	assert(rest < 1, "GemCatalog: odds of gems 2..N exceed 100%")
	GemCatalog.List[1].Probability = 1 - rest
end

-- "1 in 250,000,000"
function GemCatalog.FormatOdds(odds: number): string
	local digits = tostring(math.floor(odds + 0.5))
	local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "1 in " .. formatted:gsub("^,", "")
end

function GemCatalog.Get(id: any): Gem?
	return if type(id) == "string" then GemCatalog.ById[id] else nil
end

for _, entry in GemCatalog.List do
	table.freeze(entry)
end
table.freeze(GemCatalog.List)
table.freeze(GemCatalog.ById)
table.freeze(GemCatalog)

return GemCatalog
