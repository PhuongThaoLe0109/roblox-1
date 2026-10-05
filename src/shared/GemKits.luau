--!strict
-- GemKits
-- What every gem fights with. The kit grows with rarity:
--
--   gems  1-16  (1 in 2 .. 1 in 750)          Crystal Blade + 1 skill  (Z)
--   gems 17-31  (1 in 1,000 .. 1 in 75,000)   Crystal Blade + 2 skills (Z X)
--   gems 32-46  (1 in 100,000 .. 1 in 7.5M)   own melee weapon + 3 skills (Z X C)
--   gems 47-60  (1 in 10M .. 1 in 600M)       own melee weapon + 4 skills (Z X C V)
--   gems 61-80  (1 in 750M .. 1 in 300B)      own melee + 4 skills + ULTIMATE (G):
--                                             transform into a crystal beast
--   gems 81-100 (1 in 400B and rarer)         ... + DOMAIN (T): open a dimension that
--                                             traps, slows and grinds down everyone inside
--
-- Skills come from a library of archetypes (volleys, lances, meteors,
-- vortexes, rays, prisons, chain lightning, ...). Each gem gets its own mix,
-- picked from its element (the same element as its aura), named after it, and
-- scaled by a gentle power multiplier (x1.00 .. x1.20): rarer gems win by
-- having more tools, not by hitting much harder.
-- Shared by server (rules) and client (inputs, HUD, skill guide).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GemCatalog = require(ReplicatedStorage:WaitForChild("GemCatalog"))

local GemKits = {}

export type Melee = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Weapon: string,
	Hits: number,
	Damage: { number },
	Range: number,
	Arc: number,
	Interval: number,
	EndLag: number,
	ResetTime: number,
	HitStun: number,
	FinisherKnockback: number,
	FinisherLaunch: number,
	FinisherStun: number,
	FinisherRadius: number?, -- a shockwave around the finishing blow
}

export type Skill = {
	Key: string,
	Archetype: string,
	Name: string,
	Icon: string,
	Cooldown: number,
	Description: string,
	[string]: any,
}

export type Kit = {
	GemId: string,
	Element: string,
	Power: number,
	Melee: Melee,
	Skills: { Skill },
	Ultimate: Skill?,
	Domain: Skill?,
}

GemKits.SkillKeys = { "Z", "X", "C", "V" }
GemKits.UltimateKey = "G"
GemKits.DomainKey = "T"

--------------------------------------------------------------------------------
-- Melee styles
--------------------------------------------------------------------------------

local function melee(spec: { [string]: any }): Melee
	spec.ResetTime = spec.ResetTime or 1
	spec.HitStun = spec.HitStun or 0.25
	spec.FinisherLaunch = spec.FinisherLaunch or 20
	return table.freeze(spec) :: any
end

GemKits.Melee = {
	Blade = melee({
		Id = "Blade", Name = "Crystal Blade", Icon = "†", Weapon = "Blade",
		Description = "A balanced four-hit combo; the last hit knocks back.",
		Hits = 4, Damage = { 6, 6, 7, 11 }, Range = 8, Arc = 110, Interval = 0.32, EndLag = 0.85,
		FinisherKnockback = 55, FinisherStun = 0.55,
	}),
	Greatsword = melee({
		Id = "Greatsword", Name = "Prism Greatsword", Icon = "⚔", Weapon = "Greatsword",
		Description = "Three heavy, wide swings. Slow, but every hit lands hard.",
		Hits = 3, Damage = { 10, 11, 17 }, Range = 10.5, Arc = 140, Interval = 0.5, EndLag = 1.0,
		FinisherKnockback = 75, FinisherStun = 0.7,
	}),
	Daggers = melee({
		Id = "Daggers", Name = "Twin Facets", Icon = "⨯", Weapon = "Daggers",
		Description = "Two crystal daggers: a blistering five-hit combo.",
		Hits = 5, Damage = { 4, 4, 4, 5, 9 }, Range = 6.5, Arc = 100, Interval = 0.2, EndLag = 0.7,
		FinisherKnockback = 40, FinisherStun = 0.45, HitStun = 0.2,
	}),
	Gauntlets = melee({
		Id = "Gauntlets", Name = "Geode Fists", Icon = "✊", Weapon = "Gauntlets",
		Description = "Crystal-armoured fists. Short reach, long stuns.",
		Hits = 4, Damage = { 5, 5, 6, 12 }, Range = 6, Arc = 90, Interval = 0.25, EndLag = 0.75,
		FinisherKnockback = 60, FinisherStun = 0.95, HitStun = 0.32,
	}),
	Spear = melee({
		Id = "Spear", Name = "Spire Lance", Icon = "↟", Weapon = "Spear",
		Description = "Long, narrow thrusts that keep foes at a distance.",
		Hits = 4, Damage = { 6, 6, 7, 12 }, Range = 12.5, Arc = 50, Interval = 0.36, EndLag = 0.9,
		FinisherKnockback = 65, FinisherStun = 0.5,
	}),
	Scythe = melee({
		Id = "Scythe", Name = "Moon Scythe", Icon = "☾", Weapon = "Scythe",
		Description = "Sweeping arcs that hit all around you.",
		Hits = 3, Damage = { 8, 9, 14 }, Range = 10, Arc = 220, Interval = 0.45, EndLag = 0.95,
		FinisherKnockback = 50, FinisherStun = 0.6,
	}),
	Hammer = melee({
		Id = "Hammer", Name = "Monolith Hammer", Icon = "⚒", Weapon = "Hammer",
		Description = "Three crushing blows; the last one sends a shockwave through the ground.",
		Hits = 3, Damage = { 11, 12, 16 }, Range = 9, Arc = 120, Interval = 0.6, EndLag = 1.1,
		FinisherKnockback = 70, FinisherStun = 0.8, FinisherRadius = 10, FinisherLaunch = 35,
	}),
	Whip = melee({
		Id = "Whip", Name = "Ribbon Whip", Icon = "∿", Weapon = "Whip",
		Description = "A crystal-link whip with the longest reach of any weapon.",
		Hits = 4, Damage = { 5, 5, 6, 10 }, Range = 15, Arc = 40, Interval = 0.38, EndLag = 0.85,
		FinisherKnockback = 45, FinisherStun = 0.5,
	}),
	Fans = melee({
		Id = "Fans", Name = "Gale Fans", Icon = "◗", Weapon = "Fans",
		Description = "Paired fans that cut with gusts of wind at mid range.",
		Hits = 4, Damage = { 5, 5, 6, 10 }, Range = 11, Arc = 80, Interval = 0.3, EndLag = 0.8,
		FinisherKnockback = 60, FinisherStun = 0.45, FinisherLaunch = 30,
	}),
	Maul = melee({
		Id = "Maul", Name = "Beast Maul", Icon = "✹", Weapon = "None",
		Description = "Your beast's colossal strikes.",
		Hits = 3, Damage = { 13, 13, 20 }, Range = 15, Arc = 170, Interval = 0.42, EndLag = 0.9,
		FinisherKnockback = 80, FinisherStun = 0.7, FinisherRadius = 12, FinisherLaunch = 30,
	}),
}

--------------------------------------------------------------------------------
-- Skill archetypes ({Name} fields in descriptions are filled from the skill)
--------------------------------------------------------------------------------

GemKits.Archetypes = {
	Volley = { Noun = "Volley", Icon = "⋔", Cooldown = 6, Damage = 8, Count = 3, Spread = 11, Speed = 150, Range = 85, Radius = 2.5, Shape = "Shard",
		Text = "Fling a fan of {Count} crystal shards, {Damage} damage each." },
	Lance = { Noun = "Lance", Icon = "➹", Cooldown = 7, Damage = 16, Speed = 210, Range = 110, Radius = 3, Pierce = true, Shape = "Lance",
		Text = "Hurl a piercing lance through everyone in a line: {Damage} damage." },
	Orbs = { Noun = "Orbs", Icon = "◎", Cooldown = 9, Damage = 8, Count = 3, Speed = 55, Range = 80, Radius = 2.5, Homing = true, Shape = "Orb",
		Text = "Release {Count} seeking orbs that hunt the nearest foe, {Damage} damage each." },
	Boomerang = { Noun = "Disc", Icon = "◐", Cooldown = 8, Damage = 10, Speed = 85, Range = 45, Radius = 3.5, Return = true, Pierce = true, Shape = "Disc",
		Text = "Throw a spinning disc that cuts out and back: {Damage} damage each way." },
	Rain = { Noun = "Rain", Icon = "⁂", Cooldown = 12, Damage = 6, Count = 12, Radius = 12, Range = 60, Duration = 1.4,
		Text = "Call down {Count} crystal shards over the target area, {Damage} damage each." },
	Meteor = { Noun = "Meteor", Icon = "☄", Cooldown = 16, Damage = 30, Radius = 14, Range = 70, Delay = 1,
		Text = "Drop a giant crystal on the target point: {Damage} damage and a huge knockback after {Delay}s." },
	Launcher = { Noun = "Uprising", Icon = "⤒", Cooldown = 8, Damage = 12, Range = 10, Arc = 120, Launch = 62, Stun = 0.9,
		Text = "An upward slash that launches everyone in front of you: {Damage} damage." },
	Rush = { Noun = "Rush", Icon = "➶", Cooldown = 9, Damage = 14, Speed = 120, Duration = 0.28, Radius = 7, Knockback = 35,
		Text = "Dash forward, slicing through everyone in your path: {Damage} damage." },
	Spin = { Noun = "Cyclone", Icon = "✺", Cooldown = 10, Damage = 4, Hits = 6, Radius = 9, Duration = 1.2,
		Text = "Become a whirling storm of blades: {Hits} hits of {Damage} all around you." },
	Slam = { Noun = "Quake", Icon = "⤓", Cooldown = 11, Damage = 18, Radius = 13, Delay = 0.55,
		Text = "Leap into the air and crash down: {Damage} damage in a shockwave around you." },
	Flurry = { Noun = "Flurry", Icon = "≋", Cooldown = 9, Damage = 3, Hits = 8, Range = 9, Arc = 100,
		Text = "Unleash {Hits} lightning-fast strikes in front of you, {Damage} damage each." },
	Nova = { Noun = "Nova", Icon = "✷", Cooldown = 18, Damage = 24, Radius = 18, WindUp = 0.55, Knockback = 75, Launch = 35, Stun = 0.8,
		Text = "Gather light, then release a crystal shockwave: {Damage} damage all around you." },
	Pillars = { Noun = "Spires", Icon = "⩚", Cooldown = 10, Damage = 14, Count = 9, Spacing = 4.5, Interval = 0.05,
		Text = "Crystal spires erupt in a line ahead of you: {Damage} damage and a launch." },
	Vortex = { Noun = "Vortex", Icon = "◉", Cooldown = 14, Damage = 3, Ticks = 6, Burst = 12, Radius = 14, Range = 45, Duration = 1.5,
		Text = "Open a vortex at the target point that drags foes in ({Ticks} × {Damage}), then bursts for {Burst}." },
	Beam = { Noun = "Ray", Icon = "⟿", Cooldown = 13, Damage = 3, Ticks = 10, Length = 70, Width = 4, Duration = 1.2,
		Text = "Channel a ray of pure light: {Ticks} pulses of {Damage} down a long line. You move slowly while it fires." },
	Trap = { Noun = "Prison", Icon = "⬡", Cooldown = 12, Damage = 10, Radius = 10, Range = 45, Delay = 0.45, Stun = 1.6,
		Text = "Seal the target area in a crystal prison: {Damage} damage and frozen for {Stun}s." },
	Chain = { Noun = "Chain", Icon = "ϟ", Cooldown = 10, Damage = 12, Jumps = 4, Range = 40, JumpRange = 22,
		Text = "Lightning leaps between up to {Jumps} foes, starting at {Damage} damage." },
	Blink = { Noun = "Step", Icon = "⇢", Cooldown = 7, Damage = 10, Distance = 30, Radius = 9,
		Text = "Vanish and reappear {Distance} studs ahead, bursting for {Damage} where you land." },
	Shield = { Noun = "Aegis", Icon = "⛉", Cooldown = 16, Absorb = 40, Duration = 5, Reflect = 0.3,
		Text = "A crystal barrier absorbs {Absorb} damage for {Duration}s and reflects part of each hit." },
	Bloom = { Noun = "Bloom", Icon = "❀", Cooldown = 20, Heal = 30, Duration = 3,
		Text = "A blossom of light heals you for {Heal} over {Duration}s." },
	Frostbite = { Noun = "Field", Icon = "❄", Cooldown = 11, Damage = 3, Ticks = 5, Radius = 13, Range = 50, Duration = 2.5, Slow = 2.5,
		Text = "Freeze the ground at the target point: foes inside take {Ticks} × {Damage} and are slowed for {Slow}s." },
	Bind = { Noun = "Shackles", Icon = "⛓", Cooldown = 12, Damage = 8, Range = 40, Width = 6, Root = 2,
		Text = "Fire crystal shackles down a line: {Damage} damage and rooted in place for {Root}s (they can still fight back)." },
	Grab = { Noun = "Hook", Icon = "⚓", Cooldown = 10, Damage = 9, Range = 45, Width = 5, Stun = 0.7,
		Text = "Hook the first foe in a line and yank them to you: {Damage} damage and stunned for {Stun}s." },
	Curse = { Noun = "Hex", Icon = "☍", Cooldown = 14, Damage = 6, Range = 50, Radius = 8, Duration = 5, Amplify = 25,
		Text = "Brand the target area: foes take {Damage}, then {Amplify}% more damage from everything for {Duration}s." },
	Domain = { Noun = "Dimension", Icon = "⌬", Cooldown = 75, Damage = 3, Radius = 34, Duration = 8, Tick = 0.5, Slow = 1, Haste = 50,
		Text = "DOMAIN: tear open a dimension {Radius} studs wide around you for {Duration}s. Foes inside can't escape, are slowed and take {Damage} every {Tick}s; your cooldowns run {Haste}% faster." },
	Transform = { Noun = "Form", Icon = "✦", Cooldown = 60, Duration = 15,
		Text = "Transform into the {BeastName}, {BeastText}. Your strikes become a beast maul and you take {Armor}% less damage for {Duration}s." },
}

-- Values multiplied by the gem's power.
local SCALED = { Damage = true, Burst = true, Absorb = true, Heal = true }

-- Every key a kit can bind, in HUD order.
GemKits.AllKeys = { "Z", "X", "C", "V", "G", "T" }

--------------------------------------------------------------------------------
-- Beasts (ultimate transformations)
--------------------------------------------------------------------------------

GemKits.Beasts = {
	PrismGolem = { Name = "Prism Golem", Text = "a walking fortress of faceted stone and light", Speed = 22, DamageTaken = 0.55 },
	PyreWyrm = { Name = "Pyre Wyrm", Text = "a coiled serpent-dragon of molten crystal", Speed = 26, DamageTaken = 0.65 },
	GlacierStag = { Name = "Glacier Stag", Text = "a towering stag crowned with ice-crystal antlers", Speed = 30, DamageTaken = 0.65 },
	UmbralMaw = { Name = "Umbral Maw", Text = "a shadow wolf with a jaw full of void shards", Speed = 30, DamageTaken = 0.65 },
	ThunderRoc = { Name = "Thunder Roc", Text = "a storm bird whose wings crackle with lightning", Speed = 28, DamageTaken = 0.7 },
	DreamMoth = { Name = "Dream Moth", Text = "a vast moth with glowing stained-glass wings", Speed = 26, DamageTaken = 0.7 },
	SolarLion = { Name = "Solar Lion", Text = "a lion whose mane is a crown of sunlit shards", Speed = 28, DamageTaken = 0.6 },
	StarKoi = { Name = "Star Koi", Text = "a giant celestial koi swimming through the air", Speed = 27, DamageTaken = 0.65 },
}

--------------------------------------------------------------------------------
-- Elements (same as the aura's flame style)
--------------------------------------------------------------------------------

local ELEMENT: { [string]: string } = {
	Carnelian = "Inferno", Ruby = "Inferno", Garnet = "Inferno", Sunstone = "Inferno", FireOpal = "Inferno",
	Emberglass = "Inferno", SunflareTopaz = "Inferno", Solarite = "Inferno", SupernovaDiamond = "Inferno", RedBeryl = "Inferno",
	Quartz = "Frost", Moonstone = "Frost", Aquamarine = "Frost", Larimar = "Frost", Diamond = "Frost",
	Starquartz = "Frost", FrostheartSpinel = "Frost", Lunarine = "Frost", Calcite = "Frost",
	Onyx = "Void", Obsidian = "Void", Hematite = "Void", Voidshard = "Void", DuskmereOnyx = "Void",
	Eclipsium = "Void", SingularityGem = "Void", AbyssalSapphire = "Void", Riftstone = "Void", Serendibite = "Void",
	Pyrite = "Electric", Charoite = "Electric", Musgravite = "Electric", Stormcore = "Electric", Thunderjade = "Electric",
	Paradoxite = "Electric", PrimordialShard = "Electric",
	Kunzite = "Wisp", Morganite = "Wisp", Rhodonite = "Wisp", Bloomstone = "Wisp", Dreamglass = "Wisp",
	MoonveilOpal = "Wisp", Etherveil = "Wisp", Auroralite = "Wisp", Nebulite = "Wisp", MirageOpal = "Wisp",
	Seraphite = "Torrent", Aetherium = "Torrent", Dawnspire = "Torrent", NovaPrism = "Torrent", Quasarine = "Torrent",
	TheFirstLight = "Torrent", Wishstone = "Torrent", Starheart = "Torrent",
}
local ELEMENT_CYCLE = { "Blaze", "Spike", "Blaze", "Wisp", "Spike", "Torrent" }

local POOLS: { [string]: { string } } = {
	Inferno = { "Volley", "Rush", "Curse", "Meteor", "Pillars", "Grab", "Slam", "Nova", "Flurry", "Spin" },
	Frost = { "Lance", "Frostbite", "Trap", "Rain", "Bind", "Pillars", "Shield", "Nova", "Boomerang", "Blink" },
	Void = { "Orbs", "Grab", "Vortex", "Curse", "Blink", "Beam", "Trap", "Chain", "Nova", "Lance" },
	Electric = { "Chain", "Rush", "Bind", "Beam", "Blink", "Orbs", "Grab", "Nova", "Flurry", "Launcher" },
	Wisp = { "Orbs", "Boomerang", "Curse", "Bloom", "Vortex", "Frostbite", "Rain", "Shield", "Trap", "Blink" },
	Torrent = { "Lance", "Beam", "Bind", "Rain", "Launcher", "Meteor", "Frostbite", "Nova", "Shield", "Rush" },
	Blaze = { "Volley", "Launcher", "Grab", "Rush", "Slam", "Spin", "Bind", "Nova", "Pillars", "Meteor" },
	Spike = { "Lance", "Pillars", "Frostbite", "Flurry", "Launcher", "Grab", "Spin", "Volley", "Meteor", "Trap" },
}

local WORDS: { [string]: { string } } = {
	Inferno = { "Blaze", "Ember", "Cinder", "Pyre", "Scorch" },
	Frost = { "Frost", "Glacial", "Rime", "Tide", "Hoar" },
	Void = { "Umbral", "Void", "Eclipse", "Shade", "Abyssal" },
	Electric = { "Storm", "Volt", "Thunder", "Arc", "Tempest" },
	Wisp = { "Veil", "Dream", "Petal", "Mist", "Gossamer" },
	Torrent = { "Radiant", "Dawn", "Solar", "Halo", "Zenith" },
	Blaze = { "Prism", "Crystal", "Facet", "Gleam", "Lustre" },
	Spike = { "Shard", "Spire", "Jagged", "Edge", "Splinter" },
}

local MELEE_BY_ELEMENT: { [string]: { string } } = {
	Inferno = { "Greatsword", "Hammer" },
	Frost = { "Spear", "Daggers" },
	Void = { "Scythe", "Daggers" },
	Electric = { "Gauntlets", "Daggers" },
	Wisp = { "Fans", "Whip" },
	Torrent = { "Spear", "Greatsword" },
	Blaze = { "Greatsword", "Gauntlets" },
	Spike = { "Daggers", "Scythe" },
}

local BEAST_BY_ELEMENT: { [string]: { string } } = {
	Inferno = { "PyreWyrm", "SolarLion" },
	Frost = { "GlacierStag", "StarKoi" },
	Void = { "UmbralMaw", "PyreWyrm" },
	Electric = { "ThunderRoc", "UmbralMaw" },
	Wisp = { "DreamMoth", "StarKoi" },
	Torrent = { "SolarLion", "ThunderRoc" },
	Blaze = { "PrismGolem", "GlacierStag" },
	Spike = { "PrismGolem", "DreamMoth" },
}

-- Hand-picked kits for some showcase gems (skills in key order).
local OVERRIDE_SKILLS: { [string]: { string } } = {
	Stormcore = { "Chain", "Bind", "Beam", "Blink" },
	Bloomstone = { "Orbs", "Bloom", "Vortex", "Curse" },
	SingularityGem = { "Grab", "Vortex", "Curse", "Blink" },
	TheFirstLight = { "Beam", "Meteor", "Bind", "Nova" },
	SupernovaDiamond = { "Meteor", "Nova", "Rush", "Pillars" },
	FrostheartSpinel = { "Frostbite", "Lance", "Trap", "Shield" },
	Cometite = { "Meteor", "Volley", "Rush", "Rain" },
	Paradoxite = { "Boomerang", "Blink", "Chain", "Vortex" },
	InfinityShard = { "Boomerang", "Grab", "Blink", "Beam" },
	Chronocrystal = { "Trap", "Frostbite", "Blink", "Curse" },
}
local OVERRIDE_BEAST: { [string]: string } = {
	TheFirstLight = "SolarLion",
	AstralCrown = "SolarLion",
	Galaxite = "StarKoi",
	Cometite = "StarKoi",
	PrimordialShard = "PrismGolem",
	GenesisCrystal = "PrismGolem",
	Seraphite = "DreamMoth",
}

local UTILITY = { Shield = true, Bloom = true, Blink = true, Curse = true }

-- Domain names (a dimension per element).
local DOMAIN_NAMES: { [string]: string } = {
	Inferno = "Crucible of Embers",
	Frost = "Glacial Silence",
	Void = "Event Horizon",
	Electric = "Thunderhead Cathedral",
	Wisp = "Garden of Dreams",
	Torrent = "Sanctum of First Light",
	Blaze = "Hall of Facets",
	Spike = "Forest of Spires",
}

--------------------------------------------------------------------------------
-- Building kits
--------------------------------------------------------------------------------

local function fill(text: string, values: { [string]: any }): string
	return (text:gsub("{(%w+)}", function(key)
		local v = values[key]
		if type(v) == "number" then
			if v == math.floor(v) then
				return tostring(v)
			end
			return string.format("%.1f", v)
		end
		return if v ~= nil then tostring(v) else key
	end))
end

local function makeSkill(archetype: string, key: string, name: string, power: number, extra: { [string]: any }?): Skill
	local base = GemKits.Archetypes[archetype]
	local skill: { [string]: any } = { Key = key, Archetype = archetype, Name = name, Icon = base.Icon }
	for k, v in base do
		if k ~= "Noun" and k ~= "Icon" and k ~= "Text" then
			skill[k] = if SCALED[k] and type(v) == "number" then math.floor(v * power + 0.5) else v
		end
	end
	for k, v in extra or {} do
		skill[k] = v
	end
	skill.Description = fill(base.Text, skill)
	return table.freeze(skill) :: any
end

local function powerOf(index: number): number
	return 1 + (index - 1) / 99 * 0.2
end

local function skillCount(index: number): number
	if index <= 16 then
		return 1
	elseif index <= 31 then
		return 2
	elseif index <= 46 then
		return 3
	end
	return 4
end

local cache: { [string]: Kit } = {}

function GemKits.ElementOf(gemId: string, index: number): string
	return ELEMENT[gemId] or ELEMENT_CYCLE[index % #ELEMENT_CYCLE + 1]
end

function GemKits.ForGem(gem: GemCatalog.Gem): Kit
	local cached = cache[gem.Id]
	if cached then
		return cached
	end
	local index = gem.Index
	local element = GemKits.ElementOf(gem.Id, index)
	local power = powerOf(index)
	local words = WORDS[element]

	-- Pick the archetypes.
	local picks: { string } = {}
	local override = OVERRIDE_SKILLS[gem.Id]
	local count = skillCount(index)
	if override then
		for i = 1, count do
			picks[i] = override[i]
		end
	else
		local pool = POOLS[element]
		local offset = index % 3
		local used = {}
		local i = 0
		while #picks < count and i < #pool * 2 do
			local archetype = pool[(offset + i) % #pool + 1]
			if not used[archetype] then
				used[archetype] = true
				table.insert(picks, archetype)
			end
			i += 1
		end
		-- The first skill always hits something.
		if UTILITY[picks[1]] then
			local swapped = false
			for j = 2, #picks do
				if not UTILITY[picks[j]] then
					picks[1], picks[j] = picks[j], picks[1]
					swapped = true
					break
				end
			end
			if not swapped then
				for _, archetype in pool do
					if not UTILITY[archetype] and not used[archetype] then
						picks[1] = archetype
						break
					end
				end
			end
		end
	end

	local skills: { Skill } = {}
	for slot, archetype in picks do
		local word = words[(index + slot * 2) % #words + 1]
		local name = `{word} {GemKits.Archetypes[archetype].Noun}`
		skills[slot] = makeSkill(archetype, GemKits.SkillKeys[slot], name, power)
	end

	-- Weapon
	local meleeId = "Blade"
	if index >= 32 then
		local options = MELEE_BY_ELEMENT[element]
		meleeId = options[index % #options + 1]
	end

	-- Ultimate
	local ultimate: Skill? = nil
	if index >= 61 then
		local options = BEAST_BY_ELEMENT[element]
		local beastId = OVERRIDE_BEAST[gem.Id] or options[index % #options + 1]
		local beast = GemKits.Beasts[beastId]
		ultimate = makeSkill("Transform", GemKits.UltimateKey, `{beast.Name} Form`, power, {
			Beast = beastId,
			BeastName = beast.Name,
			BeastText = beast.Text,
			Armor = math.floor((1 - beast.DamageTaken) * 100 + 0.5),
			Duration = 15 + math.floor((index - 61) / 8),
			Scale = 1 + (index - 61) * 0.012,
		})
	end

	-- Domain
	local domain: Skill? = nil
	if index >= 81 then
		domain = makeSkill("Domain", GemKits.DomainKey, `Domain: {DOMAIN_NAMES[element]}`, power, {
			Radius = 30 + math.floor((index - 81) / 4),
			Duration = 8 + math.floor((index - 81) / 10),
			DomainName = DOMAIN_NAMES[element],
		})
	end

	local kit: Kit = table.freeze({
		GemId = gem.Id,
		Element = element,
		Power = power,
		Melee = GemKits.Melee[meleeId],
		Skills = table.freeze(skills),
		Ultimate = ultimate,
		Domain = domain,
	}) :: any
	cache[gem.Id] = kit
	return kit
end

-- Kit for a gem id; unknown or missing ids get Quartz's kit.
function GemKits.Get(gemId: string?): Kit
	local gem = gemId and GemCatalog.Get(gemId) or GemCatalog.List[1]
	return GemKits.ForGem(gem)
end

-- The skill bound to a key ("Z".."V", "G" or "T"), if this kit has one.
function GemKits.SkillFor(kit: Kit, key: string): Skill?
	if key == GemKits.UltimateKey then
		return kit.Ultimate
	elseif key == GemKits.DomainKey then
		return kit.Domain
	end
	for _, skill in kit.Skills do
		if skill.Key == key then
			return skill
		end
	end
	return nil
end

-- Melee damage for a hit, with the gem's power applied.
function GemKits.MeleeDamage(kit: Kit, style: Melee, hit: number): number
	return math.floor(style.Damage[hit] * (if style.Id == "Maul" then 1 else kit.Power) + 0.5)
end

table.freeze(GemKits.SkillKeys)
table.freeze(GemKits.AllKeys)
table.freeze(GemKits.Melee)
for _, archetype in GemKits.Archetypes do
	table.freeze(archetype)
end
table.freeze(GemKits.Archetypes)
for _, beast in GemKits.Beasts do
	table.freeze(beast)
end
table.freeze(GemKits.Beasts)

return GemKits
