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
  serverstorage/   -> ServerStorage (MapBuilder arrives in a later PR)
  client/          -> StarterPlayer.StarterPlayerScripts
    Main.client      entry point (ScreenGui + responsive UIScale)
    ClientData       local mirror of inventory / equipped gem / rolls
    UI/
      Theme          palette, typography (Merriweather / Michroma / Nunito), shimmer gradients, widgets
      GemArt         gems drawn from UI frames + gradients, no image assets
      LobbyHud       title, stats, ROLL + cooldown, Auto / Fast, Inventory, PLAY
      RollReveal     spinning reel + reveal (rays, flash, gradient lettering, NEW!/×count)
      Inventory      100-gem collection grid, filters, detail pane, equip
      Announcements  server cards, rainbow banner for the rarest pulls, toasts
tests/RollSimulation.luau
tools/roll-sim.sh
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
