# roblox-1 — Prism Shores (working title)

Crystal-gem faction warfare across 12 islands. Luau source laid out for [Rojo](https://rojo.space)
(`rojo serve`, then connect from the Studio plugin).

```
src/
  shared/          -> ReplicatedStorage
    GemConfig        gem types, placements, factions, 12 ranks, attribute/tag names
    TerritoryConfig  12 islands, hub, home bases, capture & economy rules, layout math
    SkyConfig        pastel day/night keyframes (shared clock)
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
  client/          -> StarterPlayer.StarterPlayerScripts
    Main.client      entry point
    SkyCycle         animates sky colours from the shared server clock
    AmbientFX        smooth spin/float of tagged parts, portal shimmer
    Movement         eased speed, sprint + trail, double jump, gem float
    UI/              Theme, LoadingScreen, Hud, TerritoryBar, MapPanel,
                     FactionSelect, Toasts, PortalLabels
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

## Controls

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Sprint | hold Shift | L3 | Sprint button (toggle) |
| Double jump / float | Space in air, hold to glide | A | Jump |
| World map | M | Y | Map button |

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
