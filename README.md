# roblox-1 — Crystal Gems faction warfare

Luau source for a Steven Universe–inspired multiplayer Roblox game, laid out for [Rojo](https://rojo.space)
(`rojo serve` then connect from the Studio plugin).

```
src/
  shared/                      -> ReplicatedStorage
    GemConfig.luau             gem types, placements, factions, ranks, DataStore + attribute config
    Signal.luau                leak-safe event object
  server/                      -> ServerScriptService
    GemDataBootstrap.server.luau   starts the manager, creates ReplicatedStorage.GemRemotes
    Modules/GemDataManager.luau    persistence, session locking, gem attachment, faction/essence API
  client/                      -> StarterPlayer.StarterPlayerScripts
```

## Replication contract

Clients and other systems read state from attributes rather than requiring server modules:

| Instance | Attributes |
|---|---|
| `Player` | `GemDataLoaded`, `GemType`, `GemPlacement`, `Faction`, `Rank`, `RankName`, `CrystalEssence`, `WeaponId` |
| Character (tag `GemCharacter`) | `OwnerUserId`, `GemType`, `Faction`, `WeaponId` |
| Gem part (tag `Gemstone`) | `OwnerUserId`, `GemType`, `Faction` |

Custom gem meshes can be dropped in `ReplicatedStorage.Assets.Gemstones.<GemType>` (a BasePart); otherwise a
procedural gem is generated.

## Studio testing

Enable *Game Settings → Security → Enable Studio Access to API Services* to test saving. Without it the
manager runs on temporary, unsaved data.
