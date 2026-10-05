--!strict
-- WeaponConfig
-- Every light-weapon: look, basic attack and its three skills (Q, E, R).
-- All balance numbers live here; the server skill modules
-- (ServerScriptService.Modules.Combat.Skills.<WeaponId>) read them, and the
-- client reads cooldowns/names/icons for the skill bar.
--
-- SelfMotion on a skill is applied by the caster's own client the moment the
-- key is pressed (instant, smooth movement); the server then resolves hits
-- from the caster's replicated position.
--   Dash: { Type = "Dash", Speed, Duration, Lift? }
--   Leap: { Type = "Leap", Up, Forward }
--   Roll: { Type = "Roll", Speed, Duration }  (steerable dash)

local WeaponConfig = {}

export type SelfMotion = {
	Type: "Dash" | "Leap" | "Roll",
	Speed: number?,
	Duration: number?,
	Lift: number?,
	Up: number?,
	Forward: number?,
}

export type Basic = {
	Name: string,
	Kind: "Melee" | "Projectile",
	Style: string, -- swing animation style used by the VFX
	Damage: number,
	Range: number,
	Arc: number?, -- melee cone in degrees
	Cooldown: number,
	ComboFinisher: number?, -- damage multiplier on every 3rd melee hit
	Speed: number?, -- projectile speed
	Radius: number?, -- projectile hit radius
	Splash: number?, -- projectile splash radius
}

export type Skill = {
	Name: string,
	Description: string,
	Icon: string,
	Cooldown: number,
	SelfMotion: SelfMotion?,
	[string]: any, -- skill-specific tuning (Damage, Radius, Duration, ...)
}

export type Weapon = {
	Id: string,
	DisplayName: string,
	Description: string,
	Color: Color3,
	Glow: Color3,
	Basic: Basic,
	Skills: { Q: Skill, E: Skill, R: Skill },
}

local rgb = Color3.fromRGB

WeaponConfig.SlotOrder = { "Basic", "Q", "E", "R" }
WeaponConfig.SummonCooldown = 0.8
WeaponConfig.ComboResetTime = 1.1

WeaponConfig.Weapons = {
	EnergySpear = {
		Id = "EnergySpear",
		DisplayName = "Prism Spear",
		Description = "A long, elegant spear of light. Precise thrusts and graceful dashes.",
		Color = rgb(170, 235, 255),
		Glow = rgb(255, 200, 240),
		Basic = { Name = "Thrust", Kind = "Melee", Style = "Thrust", Damage = 12, Range = 13, Arc = 40, Cooldown = 0.45, ComboFinisher = 1.6 },
		Skills = {
			Q = {
				Name = "Piercing Lunge",
				Description = "Dash forward, skewering everything in your path.",
				Icon = "➶",
				Cooldown = 6,
				Damage = 22,
				HitRadius = 6,
				SelfMotion = { Type = "Dash", Speed = 115, Duration = 0.3 },
			},
			E = {
				Name = "Spear Volley",
				Description = "Hurl a fan of three light spears.",
				Icon = "⋔",
				Cooldown = 9,
				Damage = 15,
				Count = 3,
				Spread = 12,
				Speed = 160,
				Range = 80,
			},
			R = {
				Name = "Mirror Echo",
				Description = "For a while, a mirrored phantom spear repeats every thrust with longer reach.",
				Icon = "⟡",
				Cooldown = 24,
				Duration = 7,
				EchoDamage = 10,
				EchoRange = 22,
			},
		},
	},

	LightWhip = {
		Id = "LightWhip",
		DisplayName = "Amethyst Lash",
		Description = "A crackling whip of violet light. Wide sweeps and crowd control.",
		Color = rgb(190, 120, 255),
		Glow = rgb(255, 170, 240),
		Basic = { Name = "Lash", Kind = "Melee", Style = "Lash", Damage = 10, Range = 16, Arc = 130, Cooldown = 0.55, ComboFinisher = 1.4 },
		Skills = {
			Q = {
				Name = "Lasso Pull",
				Description = "Snare the first enemy in a line and yank them to you.",
				Icon = "➰",
				Cooldown = 7,
				Damage = 10,
				Range = 34,
				Width = 5,
				StunTime = 0.6,
			},
			E = {
				Name = "Spin Lash",
				Description = "Whirl the whip around you twice, knocking enemies away.",
				Icon = "↻",
				Cooldown = 8,
				Damage = 12,
				Radius = 15,
				Hits = 2,
				Interval = 0.35,
				Knockback = 45,
			},
			R = {
				Name = "Tumble Comet",
				Description = "Curl into a spinning comet and plough through enemies.",
				Icon = "☄",
				Cooldown = 22,
				Damage = 20,
				HitRadius = 7,
				Knockback = 70,
				SelfMotion = { Type = "Roll", Speed = 70, Duration = 2.2 },
			},
		},
	},

	PowerGauntlet = {
		Id = "PowerGauntlet",
		DisplayName = "Ember Gauntlet",
		Description = "A blazing crystal fist. Fast punches that set foes alight.",
		Color = rgb(255, 90, 90),
		Glow = rgb(255, 200, 120),
		Basic = { Name = "Jab", Kind = "Melee", Style = "Punch", Damage = 9, Range = 8, Arc = 80, Cooldown = 0.3, ComboFinisher = 1.8 },
		Skills = {
			Q = {
				Name = "Blaze Rush",
				Description = "Rocket forward fist-first, launching the first enemy you hit.",
				Icon = "➤",
				Cooldown = 6,
				Damage = 18,
				HitRadius = 6,
				Knockback = 85,
				SelfMotion = { Type = "Dash", Speed = 100, Duration = 0.28 },
			},
			E = {
				Name = "Heat Up",
				Description = "Overheat: faster punches that burn.",
				Icon = "♨",
				Cooldown = 15,
				Duration = 6,
				AttackSpeed = 1.6,
				BurnDps = 4,
				BurnTime = 3,
			},
			R = {
				Name = "Meteor Slam",
				Description = "Leap high and crash down in a ring of fire.",
				Icon = "✹",
				Cooldown = 20,
				Damage = 34,
				Radius = 17,
				Knockup = 45,
				BurnDps = 5,
				BurnTime = 3,
				SelfMotion = { Type = "Leap", Up = 75, Forward = 35 },
			},
		},
	},

	FrostGauntlet = {
		Id = "FrostGauntlet",
		DisplayName = "Rime Gauntlet",
		Description = "An ice-crystal fist with a glimpse of the future. Slows, roots and freezes.",
		Color = rgb(120, 180, 255),
		Glow = rgb(220, 245, 255),
		Basic = { Name = "Chill Strike", Kind = "Melee", Style = "Punch", Damage = 9, Range = 8, Arc = 80, Cooldown = 0.38, ComboFinisher = 1.5 },
		Skills = {
			Q = {
				Name = "Glacier Spikes",
				Description = "Raise a racing line of ice spikes that slow everything they hit.",
				Icon = "⩓",
				Cooldown = 7,
				Damage = 14,
				Count = 7,
				Spacing = 6,
				Radius = 5,
				Delay = 0.07,
				SlowMult = 0.5,
				SlowTime = 2,
			},
			E = {
				Name = "Foresight",
				Description = "See the next blow coming: the first hit you take is dodged.",
				Icon = "◉",
				Cooldown = 14,
				Duration = 3,
				BlinkDistance = 12,
			},
			R = {
				Name = "Deep Freeze",
				Description = "Flash-freeze every enemy around you.",
				Icon = "❄",
				Cooldown = 24,
				Damage = 18,
				Radius = 20,
				FreezeTime = 2,
			},
		},
		-- Every basic hit chills.
		ChillMult = 0.8,
		ChillTime = 1.5,
	},

	ForgeHammer = {
		Id = "ForgeHammer",
		DisplayName = "Forge Hammer",
		Description = "A huge crystal-forged hammer. Slow, crushing and immovable.",
		Color = rgb(110, 230, 200),
		Glow = rgb(255, 160, 220),
		Basic = { Name = "Smash", Kind = "Melee", Style = "Smash", Damage = 18, Range = 11, Arc = 90, Cooldown = 0.85, ComboFinisher = 1.5 },
		Skills = {
			Q = {
				Name = "Shatter Strike",
				Description = "Wind up and smash the ground, cratering everything in front.",
				Icon = "⚒",
				Cooldown = 8,
				Damage = 40,
				Range = 14,
				Arc = 100,
				WindUp = 0.4,
				Knockup = 40,
			},
			E = {
				Name = "Forge Wall",
				Description = "Raise a wall of crystal that blocks bodies and projectiles.",
				Icon = "▥",
				Cooldown = 14,
				Distance = 10,
				Width = 24,
				Height = 12,
				Duration = 6,
			},
			R = {
				Name = "Anvil Quake",
				Description = "Three shockwaves ripple out from you, each wider than the last.",
				Icon = "◎",
				Cooldown = 22,
				Damage = 20,
				Radii = { 10, 18, 26 },
				Interval = 0.35,
				Knockup = 30,
			},
		},
	},

	RamCrest = {
		Id = "RamCrest",
		DisplayName = "Ram Crest",
		Description = "A horned crystal crest. Charge, roar, and fall from the sky.",
		Color = rgb(255, 150, 80),
		Glow = rgb(255, 230, 160),
		Basic = { Name = "Headbutt", Kind = "Melee", Style = "Headbutt", Damage = 14, Range = 8, Arc = 90, Cooldown = 0.6, ComboFinisher = 1.5 },
		Skills = {
			Q = {
				Name = "Horn Charge",
				Description = "Charge forward, stunning and flinging anyone in the way.",
				Icon = "♈",
				Cooldown = 7,
				Damage = 18,
				HitRadius = 6,
				Knockback = 70,
				StunTime = 0.8,
				SelfMotion = { Type = "Dash", Speed = 95, Duration = 0.45 },
			},
			E = {
				Name = "War Cry",
				Description = "Roar: you and nearby allies hit harder, and you gain a crystal shield.",
				Icon = "📯",
				Cooldown = 16,
				Radius = 28,
				DamageMult = 1.25,
				Duration = 6,
				Shield = 30,
			},
			R = {
				Name = "Quake Leap",
				Description = "Leap forward and land with a stunning quake.",
				Icon = "⛰",
				Cooldown = 20,
				Damage = 28,
				Radius = 18,
				StunTime = 1.2,
				SelfMotion = { Type = "Leap", Up = 60, Forward = 70 },
			},
		},
	},

	ArcDrones = {
		Id = "ArcDrones",
		DisplayName = "Arc Drones",
		Description = "Three orbiting crystal drones. Ranged bolts, beams and turrets.",
		Color = rgb(150, 255, 110),
		Glow = rgb(220, 255, 180),
		Basic = { Name = "Arc Bolt", Kind = "Projectile", Style = "Cast", Damage = 9, Range = 75, Cooldown = 0.35, Speed = 150, Radius = 2.5 },
		Skills = {
			Q = {
				Name = "Tractor Beam",
				Description = "Lock onto the first enemy in a line, lift and drag them to you.",
				Icon = "⇶",
				Cooldown = 9,
				Damage = 8,
				Range = 45,
				Width = 5,
				StunTime = 1.2,
			},
			E = {
				Name = "Drone Shield",
				Description = "Drones weave a crystal barrier that absorbs damage.",
				Icon = "⬡",
				Cooldown = 14,
				Shield = 35,
				Duration = 5,
			},
			R = {
				Name = "Overload Turret",
				Description = "Deploy a drone turret that zaps the nearest enemy.",
				Icon = "✣",
				Cooldown = 22,
				Damage = 7,
				Range = 30,
				Interval = 0.5,
				Duration = 7,
				PlaceRange = 45,
			},
		},
	},

	TideWings = {
		Id = "TideWings",
		DisplayName = "Tide Wings",
		Description = "Wings of living water. Ranged torrents, flight and tidal waves.",
		Color = rgb(70, 150, 255),
		Glow = rgb(170, 240, 255),
		Basic = { Name = "Water Bolt", Kind = "Projectile", Style = "Cast", Damage = 11, Range = 60, Cooldown = 0.5, Speed = 115, Radius = 3, Splash = 5 },
		Skills = {
			Q = {
				Name = "Wing Burst",
				Description = "Beat your wings to soar up and away, blasting enemies below.",
				Icon = "⇮",
				Cooldown = 7,
				Damage = 12,
				Radius = 11,
				Knockback = 50,
				SelfMotion = { Type = "Dash", Speed = 75, Duration = 0.4, Lift = 55 },
			},
			E = {
				Name = "Riptide Grip",
				Description = "A hand of water erupts at the target spot and pins enemies down.",
				Icon = "✋",
				Cooldown = 10,
				Damage = 15,
				Radius = 9,
				RootTime = 1.6,
				Delay = 0.45,
				PlaceRange = 50,
			},
			R = {
				Name = "Tidal Surge",
				Description = "Summon a towering wave that sweeps the lane ahead.",
				Icon = "🌊",
				Cooldown = 24,
				Damage = 26,
				Length = 70,
				Width = 28,
				Speed = 60,
				Knockback = 60,
			},
		},
	},
} :: { [string]: Weapon }

function WeaponConfig.Get(weaponId: any): Weapon?
	return if type(weaponId) == "string" then WeaponConfig.Weapons[weaponId] else nil
end

function WeaponConfig.GetSlot(weapon: Weapon, slot: string): (Basic | Skill)?
	if slot == "Basic" then
		return weapon.Basic
	end
	return (weapon.Skills :: any)[slot]
end

local function deepFreeze(t: any)
	for _, value in t do
		if type(value) == "table" and not table.isfrozen(value) then
			deepFreeze(value)
		end
	end
	table.freeze(t)
end

for id, weapon in WeaponConfig.Weapons do
	assert(weapon.Id == id, `WeaponConfig: {id}.Id mismatch`)
	for _, slot in { "Q", "E", "R" } do
		assert((weapon.Skills :: any)[slot], `WeaponConfig: {id} is missing skill {slot}`)
	end
end
deepFreeze(WeaponConfig)

return WeaponConfig
