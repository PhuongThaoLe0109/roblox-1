# roblox-1 — Prism Shores (working title)

A PvP brawler: roll gems, wear their aura, jump into the arena and fight.
Luau source laid out for [Rojo](https://rojo.space) (`rojo serve`, then connect from the Studio plugin).

## Game loop

1. Spawn in the lobby. **Roll** for gems (free, unlimited, 1.5 s cooldown) and open the **Inventory**.
2. Pick a gem to wear: gems are purely cosmetic and change your **aura** (each of the 100 has its own colours and look).
3. Press **Play** to enter the arena. Everyone has the same full combat kit from the start.
4. When you're defeated you return to the lobby, choose again and jump back in.

## Gems & rolling

- `src/shared/GemCatalog.luau` lists the 100 gems from most common (Quartz) to rarest (The First Light).
  Odds are shown as **"1 in N"**: every gem except Quartz rolls with probability exactly `1/N`; Quartz takes the rest.
- Very rare pulls are announced to the whole server ("1 in 100,000" or rarer) or shown as a full-screen banner
  ("1 in 100,000,000" or rarer), and saved to the DataStore immediately.
- **Hidden pity** (`src/server/Modules/RollConfig.luau`, server-only, never replicated): three tiers that quietly raise
  the odds of better gems during long dry streaks and guarantee one at a hard limit. Gems rarer than
  "1 in 1,000,000,000,000" are never helped by pity.
- The server does the roll with 64-bit randomness (two 32-bit draws), so even "1 in 300,000,000,000,000" is reachable.

Run the offline roll simulation after changing odds or pity:

```sh
tools/roll-sim.sh path/to/luau        # standalone Luau CLI from github.com/luau-lang/luau
```

## Layout

```
src/
  shared/          -> ReplicatedStorage
    GemCatalog       100 gems: name, "1 in N" odds, aura colours
    Signal           leak-safe event object
  server/          -> ServerScriptService
    Main.server      entry point
    Modules/
      PlayerData     DataStore persistence (session lock): inventory, equipped gem, hidden pity, stats
      RollConfig     roll cooldown, announcements, hidden pity tiers (server-only)
      RollEngine     pure roll + pity logic (simulated offline by tools/roll-sim.sh)
      RollService    RequestRoll / RequestEquip handling, announcements
      Remotes        ReplicatedStorage.Remotes
  serverstorage/   -> ServerStorage
    MapBuilder/      the gem world (init + Geometry, Palette, Temple, Bridge, Lobby, World, Atmosphere)
  client/          -> StarterPlayer.StarterPlayerScripts
    Main.client      entry point (ScreenGui + responsive UIScale)
    MapFX            client-side animation of the world's decoration
    ClientData       local mirror of inventory / equipped gem / rolls
    UI/
      Theme          palette, typography (Merriweather / Michroma / Nunito), shimmer gradients, widgets
      GemArt         gems drawn from UI frames + gradients, no image assets
      LobbyHud       title, stats, ROLL + cooldown, Auto / Fast, Inventory, PLAY
      RollReveal     spinning reel + reveal (rays, flash, gradient lettering, NEW!/×count)
      Inventory      100-gem collection grid, filters, detail pane, equip
      Announcements  server cards, rainbow banner for the rarest pulls, toasts
tests/RollSimulation.luau, tests/RobloxStub.luau
tools/roll-sim.sh, tools/map-check.sh, tools/render-map.py
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

Player attributes: `DataLoaded`, `EquippedGem`, `TotalRolls`.

## Lobby controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Roll | R / ROLL button | X |
| Inventory | I | Y |

Auto roll keeps rolling and pauses itself after a "1 in 100,000" or rarer result. Fast skips the reel.

## Studio testing

Enable *Game Settings → Security → Enable Studio Access to API Services* to test saving.
Without it the game runs on temporary, unsaved data.
