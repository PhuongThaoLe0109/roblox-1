# roblox-1 — Prism Shores (working title)

Crystal-gem faction warfare across 12 islands. Luau source laid out for [Rojo](https://rojo.space)
(`rojo serve`, then connect from the Studio plugin).

```
src/
  shared/          -> ReplicatedStorage
    GemConfig        gem types, placements, factions, 12 ranks, attribute/tag names
    TerritoryConfig  12 islands, hub, home bases, capture & economy rules, layout math
    SkyConfig        pastel day/night keyframes (shared clock)
    WeaponConfig     8 light-weapons: look, basic attack, Q/E/R skills, all balance numbers
    CombatConfig     status-effect attribute names, damage formula, safe zones
    Signal           leak-safe event object
  serverstorage/   -> ServerStorage
    MapBuilder       procedural world generator (bake once in Edit mode)
  server/          -> ServerScriptService
    Main.server      entry point; wires everything in order
    Modules/
      GemDataManager   DataStore persistence, session locking, gem on body
      FactionTeams     Teams + spawning/respawning at faction homes
      PortalService    rank-gated portals and fast travel
      TerritoryService capture points, income, location tracking, anti-bypass
      Remotes          ReplicatedStorage.GemRemotes + notifications
      Combat/
        CombatService    hit queries, damage, shields, status effects, knockback, projectiles
        WeaponService    summon/dismiss, action validation, cooldowns, combo, dispatch
        WeaponBuilder    procedural glowing weapon models welded to the character
        SkillKit         shared skill building blocks (combo melee, shots, dashes, slams)
        Skills/<Id>      one module per weapon: Basic, Q, E, R
        TrainingDummies  hittable training crystals on the hub
        PuffService      0 HP -> gem capsule; reform, seal, revive, return home
  client/          -> StarterPlayer.StarterPlayerScripts
    Main.client      entry point
    SkyCycle         animates sky colours from the shared server clock
    AmbientFX        smooth spin/float of tagged parts, portal shimmer
    Movement         eased speed, sprint + trail, double jump, gem float, status effects
    WeaponController weapon input, aim, cooldown prediction, dash/roll/leap motion
    VFX              all weapon effects + swing/whip/drone/wing animation
    UI/              Theme, LoadingScreen, Hud, TerritoryBar, MapPanel,
                     FactionSelect, Toasts, PortalLabels, SkillBar, PuffOverlay
```

## Baking the map

Run once in **Edit mode** from the Studio command bar, then save the place:

```lua
require(game.ServerStorage.MapBuilder).Build()                    -- build if missing
require(game.ServerStorage.MapBuilder).Build({ Rebuild = true })  -- regenerate
```

It creates `Workspace.Map`, fills the terrain sea and adds clouds/atmosphere/bloom.
At game start the server only builds the map when `Workspace.Map` is missing.
You can hand-edit or replace the baked map as long as these names stay:
`Territories/<Id>/{CapturePoint, Arrival}`, `Hub/Arrival`, `Homes/<Faction>/Arrival`,
and portal parts tagged `Portal` (attributes `PortalKind`, `TargetId`, `TargetName`, `RequiredRank`).

## World & progression

- Hub (Nexus Plaza) in the middle; 12 islands on a ring in open sea; two faction home bases outside.
- Island *N* needs rank *N*. Each island has a forward portal to the next island and a return portal to the hub.
  Standing on an island above your rank (e.g. by swimming) sends you back to the hub.
- Stand on an island's glowing pad to capture it (contested when both factions are on it).
  Captures pay essence; everyone earns base income plus a bonus per island their faction holds.

## Weapons

Each gem type has its own light-weapon (`GemConfig.GemTypes.<Gem>.WeaponId`):

| Weapon | Gem | Basic | Q | E | R |
|---|---|---|---|---|---|
| Prism Spear | Pearl | thrust combo | Piercing Lunge (dash) | Spear Volley (3 spears) | Mirror Echo (phantom thrusts) |
| Amethyst Lash | Amethyst | wide lash combo | Lasso Pull | Spin Lash (2 spins) | Tumble Comet (steerable roll) |
| Ember Gauntlet | Ruby | fast punches | Blaze Rush (dash punch) | Heat Up (attack speed + burn) | Meteor Slam (leap + fire ring) |
| Rime Gauntlet | Sapphire | chilling punches | Glacier Spikes (slow) | Foresight (dodge next hit) | Deep Freeze (AoE freeze) |
| Forge Hammer | Bismuth | heavy smashes | Shatter Strike (wind-up crater) | Forge Wall (blocks bodies + shots) | Anvil Quake (3 shockwaves) |
| Ram Crest | Jasper | headbutts | Horn Charge (stun) | War Cry (ally buff + shield) | Quake Leap (stun) |
| Arc Drones | Peridot | ranged bolts | Tractor Beam (pull + stun) | Drone Shield | Overload Turret |
| Tide Wings | Lapis Lazuli | splashing water bolts | Wing Burst (fly-dash) | Riptide Grip (root) | Tidal Surge (wave) |

Balance lives in `WeaponConfig`. Allies can't hurt each other, the hub and homes are PvP-safe,
and the training crystals on the hub are always hittable for testing.
## Puff state

Combat never kills outright. At 0 HP the body bursts into a puff of light and
the gem floats in a crystal capsule (`CombatConfig.Puff` holds the tuning):

- After 8 s the gem **reforms** on the spot at full health with 2.5 s of protection.
- An **enemy** can hold **G** on the capsule to **seal** it: the gem is sent home and the sealer earns essence.
- An **ally** can hold **H** to **revive** it immediately.
- The puffed player can press **Return Home** to respawn at their base.

Training crystals puff and reform too. Falling into the void still respawns normally.

## Controls

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Sprint | hold Shift | L3 | Sprint button (toggle) |
| Double jump / float | Space in air, hold to glide | A | Jump |
| World map | M | Y | Map button |
| Summon / dismiss weapon | F | D-pad Up | Weapon button |
| Basic attack (hold to repeat) | Left mouse | R2 | Attack button |
| Skills | Q / E / R | X / B / R1 | Q / E / R buttons |

Sprint uses Left Shift, so Roblox's shift-lock is disabled
(`StarterPlayer.EnableMouseLockOption = false`, set in `default.project.json`).

## Replication contract

| Instance | Attributes |
|---|---|
| `Player` | `GemDataLoaded`, `GemType`, `GemPlacement`, `Faction`, `Rank`, `RankName`, `CrystalEssence`, `LifetimeEssence`, `WeaponId`, `CurrentIsland`, `CaptureTerritory` |
| Character (tag `GemCharacter`) | `OwnerUserId`, `GemType`, `Faction`, `WeaponId` |
| Gem part (tag `Gemstone`) | `OwnerUserId`, `GemType`, `Faction` |
| `Map.Territories.<Id>` | `Owner`, `Capturer`, `Progress`, `Contested` |

## Original-IP note

The setting is inspired by a crystal-gem cartoon, but every name and design in
the game is our own: factions (Prism Guardians / Crown Dominion / Rogue Shards),
islands, ranks, weapons and landmarks. Gem types use real mineral names. Avoid
copying show characters, logos (e.g. the star or diamond emblems) or music.

## Studio testing

Enable *Game Settings → Security → Enable Studio Access to API Services* to test saving.
Without it the data manager runs on temporary, unsaved data.
