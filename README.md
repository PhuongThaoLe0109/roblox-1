# roblox-1 — Prism Shores (working title)

An open-world PvP brawler: roll gems, wear their aura, and fight with the gem's own kit anywhere in the world
(Sol's RNG meets an anime battlegrounds game, in a Steven-Universe-style crystal world).
Luau source laid out for [Rojo](https://rojo.space) (`rojo serve`, then connect from the Studio plugin).

## Game loop

1. Spawn on the Dawn Gate plaza (a safe zone). **Roll** for gems (free, unlimited, 1.5 s cooldown) and open the **Inventory**.
2. Wear a gem: it decides your **aura** and your **combat kit** (weapon, skills, transformation, domain).
3. Step off the plaza and fight anyone, anywhere. There is no Play button.
4. When you're defeated you **shatter** into your gem, then reform at the plaza a few seconds later.

## Combat (`src/shared/GemKits.luau`, `src/server/Modules/Combat`)

Every gem has its own kit, and it grows with rarity:

| Gems | Kit |
|---|---|
| 1-16 (1 in 2 .. 1 in 750) | Crystal Blade + 1 skill (Z) |
| 17-31 (1 in 1,000 .. 1 in 75,000) | Crystal Blade + 2 skills (Z X) |
| 32-46 (1 in 100,000 .. 1 in 7.5M) | own melee weapon + 3 skills (Z X C) |
| 47-60 (1 in 10M .. 1 in 600M) | own melee weapon + 4 skills (Z X C V) |
| 61-80 (1 in 750M .. 1 in 300B) | + **transformation** (G) into a crystal beast |
| 81-100 (1 in 400B and rarer) | + **domain** (T): a dimension that traps, slows and grinds down everyone inside |

- **Melee weapons**: Crystal Blade, Prism Greatsword, Twin Facets (daggers), Geode Fists, Spire Lance (spear), Moon Scythe,
  Monolith Hammer, Ribbon Whip, Gale Fans. Each has its own combo length, reach, arc and finisher.
- **Skill archetypes** (24): volleys, piercing lances, homing orbs, boomerang discs, crystal rain, meteors, launchers, rushes,
  cyclones, quakes, flurries, novas, spire lines, vortexes, rays, prisons, chain lightning, blinks, aegis shields, blooms,
  frost fields (slow), shackles (root), hooks (pull), hexes (take more damage). Each gem gets a mix picked from its
  element (the same element as its aura), named after it ("Umbral Vortex", "Glacial Prison", ...).
- **Beasts**: Prism Golem, Pyre Wyrm, Glacier Stag, Umbral Maw, Thunder Roc, Dream Moth, Solar Lion, Star Koi. While
  transformed your strikes become a beast maul, you take less damage and move at the beast's speed.
- **Domains**: 8 dimensions (one per element, e.g. "Event Horizon", "Crucible of Embers"). Walls of light, a tinted sky, and
  foes inside are slowed, take damage every half second and are pushed back if they try to leave; your cooldowns run faster.
- Damage is close between rarities (power ×1.00 to ×1.20): rarer gems win by having more tools.
- Block (F) from the front with a guard meter, dash (Q) with i-frames, stuns, knockback, combo counter, spawn protection.
- Server-authoritative: hit detection, cooldowns, combos and kit checks happen on the server (`ActionService`), with a request
  budget and a movement guard. The client predicts the melee swing and moves its own character for dashing skills.
- **SKILLS** button / **H** opens the guide for your gem's kit. You can't change gems mid-fight.
- Overhead titles show every fighter's gem, its rarity, name, HP, streak and status (stunned, rooted, slowed, hexed).
- Kills, streaks and best streaks are saved; leaderstats (Kills, Streak) give the in-server leaderboard.

Founder command: the account `swarovski_i` can type `?admin` in chat to receive every gem (`src/server/Modules/AdminService.luau`;
add user ids to `FOUNDER_IDS` to keep access if the name changes).

Offline checks:

```sh
tools/kit-check.sh path/to/luau      # all 100 kits: skill counts, names, keys, descriptions
tools/combat-check.sh path/to/luau   # builds the 8 beasts and 9 weapons against the Roblox stub, then runs kit-check
```

## Gems & rolling

- `src/shared/GemCatalog.luau` lists the 100 gems from most common (Quartz) to rarest (The First Light).
  Odds are shown as **"1 in N"**: every gem except Quartz rolls with probability exactly `1/N`; Quartz takes the rest.
- Very rare pulls are announced to the whole server ("1 in 100,000" or rarer) or shown as a full-screen banner
  ("1 in 100,000,000" or rarer), and saved to the DataStore immediately.
- **Hidden pity** (`src/server/Modules/RollConfig.luau`, server-only, never replicated): three tiers that quietly raise
  the odds of better gems during long dry streaks and guarantee one at a hard limit. Gems rarer than
  "1 in 1,000,000,000,000" are never helped by pity.
- The server does the roll with 64-bit randomness (two 32-bit draws), so even "1 in 300,000,000,000,000" is reachable.

## Auras

Each of the 100 gems has its own hand-tuned aura (`src/client/Aura/Recipes.luau`), drawn locally on every client
from the wearer's `EquippedGem`. Auras are built from shared layers (`src/client/Aura/Layers.luau`):
rings and star sigils, orbiting gems and comets, rising motes, embers, petals and snow, crystal wings, crowns,
light helixes, shard mandalas, light pillars, floating crests, starfields, lightning, eclipses, pulses and monoliths.

- Every aura stands on a **magic circle** under the feet: a glowing floor, an outer ring with rune ticks and a
  counter-turning star (more rings and points with rarity).
- **Power-up** for every gem: tongues of light burst up from the whole body like a powered-up fighter. There are 8 burn styles
  (Blaze, Spike, Wisp, Torrent, Inferno, Frost, dark-cored Void, flickering Electric) and the body glows in the gem's colours.
  The flames grow taller, denser and gain a third shell with rarity.
- Then, by rarity: rising sparks (1 in 120+), crystal armour on the shoulders and chest (1 in 100,000+),
  gauntlets, back crystals and a crystal diadem (1 in 10,000,000+), and from 1 in 750,000,000 a **transformation**:
  a giant translucent crystal sovereign rises behind the wearer (three crest variants, growing with rarity).
  It fades out when it would block your own camera.
- On top of that, each gem keeps its own signature layers (Recipes): from a quiet sigil (Quartz) to eight layers for The First Light.
- Colours always come from the gem, so no two auras look alike.
- Only Neon / Glass parts, untextured Beams and Trails, and PointLights; no textures, decals, meshes or ParticleEmitters.
- One `Workspace:BulkMoveTo` per frame; auras far from the camera are paused and hidden.
- In the Inventory, selecting an owned gem lets you try its aura on before equipping it.

Check every aura offline (builds and animates all 100, checks part budgets per rarity):

```sh
tools/aura-check.sh path/to/luau
```

Run the offline roll simulation after changing odds or pity:

```sh
tools/roll-sim.sh path/to/luau        # standalone Luau CLI from github.com/luau-lang/luau
```

## Layout

```
src/
  shared/          -> ReplicatedStorage
    GemCatalog       100 gems: name, "1 in N" odds, aura colours
    GemKits          every gem's combat kit: melee style, skills, beast, domain
    CombatConfig     general combat numbers + status attribute names
    MovementConfig   sprint, dash, double jump, hoverboard
    Signal           leak-safe event object
  server/          -> ServerScriptService
    Main.server      entry point
    Modules/
      PlayerData     DataStore persistence (session lock): inventory, equipped gem, hidden pity, stats
      RollConfig     roll cooldown, announcements, hidden pity tiers (server-only)
      RollEngine     pure roll + pity logic (simulated offline by tools/roll-sim.sh)
      RollService    RequestRoll / RequestEquip handling, announcements
      MovementService hoverboard + movement effect relay
      AdminService   founder chat commands (?admin)
      Remotes        ReplicatedStorage.Remotes
      Combat/
        CombatService  targets, queries, damage (block, shields, hex, beast armour), projectiles, FX
        ActionService  validates every CombatAction against the gem's kit, cooldowns, combos, guard
        Melee          M1 combos for every melee style
        Skills         all skill archetypes, crowd control and domains
        BeastService   the 8 crystal beasts and transformations
        WeaponBuilder  the 9 crystal weapons
        LifeService    spawning, shattering death, kill credit, streaks, leaderstats, safe zone
        MovementGuard  basic speed / teleport anti-cheat
  serverstorage/   -> ServerStorage
    MapBuilder/      the gem world (init + Geometry, Palette, Temple, Bridge, Lobby, World, Atmosphere)
  client/          -> StarterPlayer.StarterPlayerScripts
    Main.client      entry point (ScreenGui + responsive UIScale)
    MapFX            client-side animation of the world's decoration
    ClientData       local mirror of inventory / equipped gem / rolls
    Movement/        MovementController (sprint, dash, double jump, board, combat speeds), MovementFX
    Combat/
      CombatController inputs, aim, cooldowns, melee prediction, self-moving skills
      CombatFX       every combat effect (swings, projectiles, areas, domains, transformations, shattering)
      BeastFX        animates beasts' wings, tails and heads
      Overheads      gem title, rarity, name, HP and status over every fighter
    Aura/
      Auras          draws every player's aura, Inventory "try on" preview
      Layers         aura building blocks (rings, orbits, wings, helixes, eclipses, ...)
      Recipes        one recipe per gem
    UI/
      Theme          palette, typography (Merriweather / Michroma / Nunito), shimmer gradients, widgets
      GemArt         gems drawn from UI frames + gradients, no image assets
      LobbyHud       title, stats, ROLL + cooldown, Auto / Fast, Inventory
      CombatHud      health, skill bar, combo, kill feed, status, shattered screen
      SkillGuide     the SKILLS / H panel explaining your gem's kit
      MovementHud    board button, sprint and dash pills
      RollReveal     spinning reel + reveal (rays, flash, gradient lettering, NEW!/×count)
      Inventory      100-gem collection grid, filters, detail pane, equip
      Announcements  server cards, rainbow banner for the rarest pulls, toasts
tests/RollSimulation.luau, tests/RobloxStub.luau
tools/roll-sim.sh, tools/map-check.sh, tools/render-map.py, tools/aura-check.sh, tools/kit-check.sh, tools/combat-check.sh
```

## The world (`ServerStorage.MapBuilder`)

Run **once in Edit mode**, then save the place:

```lua
require(game.ServerStorage.MapBuilder).Build()
```

If `Workspace.Map` already exists, `Build()` returns it untouched (it never rebuilds, deletes or edits a map).
At game start the server only builds it as a fallback when the place has no `Workspace.Map`.
It also sets the lighting and enables `StreamingEnabled` (both only settable from Studio).

What it builds (~16,500 parts, plain SmoothPlastic / Neon / Glass, no textures, no Terrain):

- **Prism Temple (arena)**: a stratified dark-rock island crowned by a pale five-lobed fan.
  - Double cyan light channels curve from glowing crystal pods to a stepped dais.
  - A pillar of light with drifting halo rings rises from the dais.
  - Light falls spill off the lobes; crystal clusters line the rim; etched wave markings cover the floor.
  - A sealed light-gate closes the bridge entrance.
- **Aqueduct**: a two-tier arched bridge with railings, crystal lanterns and a light channel.
- **Dawn Gate (lobby)**: its own island.
  - Terraced octagonal plaza with neon rose inlays.
  - The Altar of Fortune with a giant floating gem.
  - Eight crystal pylons and crystal blossom trees.
  - A pointed gate arch engraved with the title, and a viewing balcony.
- **World**:
  - a teal sea with glowing ripples and glints, and 22 stratified islets;
  - the Sunken Colossus: two giant stone hands cradling a gem;
  - giant crystal spires, floating sky islands with light-falls, and a ring of low-poly mountains;
  - drifting crystal shards, a moon and gradient aurora ribbons.

Gameplay contract:
- `Map.Arena` has attributes `Center`, `Radius`, `FloorY`, `KillY`, and `Spawns/*` parts tagged `ArenaSpawn`.
- `Map.Lobby` has a `LobbySpawn` SpawnLocation and attributes `Center`, `Radius`.
- Decoration tagged `MapSpin` / `MapFloat` / `MapPulse` / `MapRise` is animated client-side by `src/client/MapFX`.

Offline tooling (needs the standalone Luau CLI; the renderer needs Python with Pillow and NumPy):

```sh
tools/map-check.sh path/to/luau     # runs Build() against a Roblox stub: errors, part sizes, rotations, flat floors, part counts
MAP_DUMP=true tools/map-check.sh path/to/luau > parts.txt
tools/render-map.py parts.txt preview.png --cam 0,105,600 --look 0,70,-20   # z-buffered preview render
```

## Remotes (`ReplicatedStorage.Remotes`)

| Remote | Direction | Payload |
|---|---|---|
| `RequestRoll` | client → server | `() -> (ok, gemId \| reason, count \| retryIn)` |
| `RequestEquip` | client → server | `(gemId) -> (ok, reason?)` |
| `GetProfile` | client → server | `() -> { Inventory, Equipped, Rolls }` |
| `InventorySync` | server → client | `("Full", snapshot)`, `("Gem", id, count)`, `("Equipped", id)` |
| `Announce` | server → all | `(kind, playerName, gemId)` with kind `"Server"` or `"Banner"` |
| `SetHoverboard` | client → server | `(on: boolean)`: server builds/removes the board, sets character attribute `Hoverboard` |
| `MovementFX` | client → server → others | `("Dash" \| "DoubleJump", direction?)`, relayed as `(character, kind, direction?)` |
| `CombatAction` | client → server | `(action, aimDirection, aimPoint)`: action `"M1"`, `"Z"`..`"V"`, `"G"`, `"T"`, `"Block"`, `"Unblock"`, `"Dash"` |
| `CombatState` | server → client | `("Cooldown", slot, readyAt, combo?)`, `("Rejected", slot, reason)`, `("Reset")` |
| `CombatFX` | server → all | `(kind, params)`: every combat effect, drawn by `src/client/Combat/CombatFX` |
| `KillFeed` | server → all | `{ Killer?, Victim, Streak, Milestone, Ended, ... }` |
| `Notify` | server → client | `(text, kind)` toast |

Player attributes: `DataLoaded`, `EquippedGem`, `TotalRolls`, `Streak`, `InSafeZone`, `LastCombat`.
Character attributes: the combat status in `CombatConfig.Status` (stun, block, guard, busy, slow, root, hex, shield,
beast, domain, shattered, ...), all as server-time timestamps where they expire.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Roll | R / ROLL button | X |
| Inventory | I | Y |
| Sprint (hold) | Ctrl / SPRINT button | L3 (toggle) |
| Dash (one more in the air) | Q / DASH button | B |
| Double jump | Space in the air | A in the air |
| Hoverboard (not while in combat) | B / BOARD button | D-pad up |
| Attack (hold for combo) | Left mouse / ATTACK slot | R2 |
| Skills | Z X C V | R1, L1, D-pad left, D-pad right |
| Transformation | G | D-pad down |
| Domain | T | R3 |
| Block (hold) | F | L2 |
| Skills guide | H / SKILLS button | Select |

Auto roll keeps rolling and pauses itself after a "1 in 100,000" or rarer result. Fast skips the reel.

## Studio testing

Enable *Game Settings → Security → Enable Studio Access to API Services* to test saving.
Without it the game runs on temporary, unsaved data.
