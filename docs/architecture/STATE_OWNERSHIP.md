# Rareload State Ownership

Who owns each piece of state in Rareload 5.5 (55 Lua files). Functions are named instead of line numbers, which drift.

Every state store has exactly one **owner**: it decides what the store means and is the only writer. Other files may read it, store it on the owner's behalf, send it or show it.

## 1. Server: persistent stores

| Store | Where | Owner | Notes |
| :--- | :--- | :--- | :--- |
| Player save document (`entries`, `nextId`, `activeId`, `quickId`, `deathId`, `checkpoints`, `nick`, `sid64`) | `data/rareload/<mapdir>/<sid64>.json` | `History` (`sv_history.lua`). It writes only through the local `save()`, which also pushes the timeline. `History.Doc` normalizes a document once when it is read. | Checkpoints change through `History.UpdateCheckpoints`, the death save through `Append{death}` / `History.SetDeath`, and which saves may be pruned through `History.PruneDoc`. `Store.Prune` (every map, admin command) writes the documents `PruneDoc` changed. It is the store's own maintenance, and it does not push a timeline. |
| Content-addressed blobs (`{ ["$blob"] = hash }`) | `<mapdir>/_blobs/<hash>.json` | `Store` (`BlobPut`/`BlobGet`/`GC`/`GCAll`) | References are owned by `History` (entries) and `Snapshots` (`_server.json`). GC keeps every blob that either one refers to (regression test 12). |
| Server snapshots | `<mapdir>/_server.json` | `Snapshots` | — |
| Crash flag | `data/rareload/_running.txt` | `Snapshots`, through `Store.Flag`/`SetFlag` | — |
| Object name counters | `<mapdir>/_objects.json` | `Snapshot.Num` (`sv_snapshot.lua`) | — |
| Anti-stuck safe positions | `<mapdir>/_safe_positions.json` | `AntiStuck` | — |
| Anti-stuck method order | `data/rareload/antistuck.json` | `AntiStuck` | — |
| Blocked classes | `data/rareload/blocked.json` | `Blocked` (`sv_exclude.lua`) | — |
| Persistent grants | `data/rareload/perms.json` | `sh_perms.lua` (`loadGrants`) | — |
| Global settings | archived `sv_rareload_*` convars | `RARELOAD.Settings` (`sh_config.lua`) | There is no `settings.json`. |
| Per-player settings | `cl_rareload_*` USERINFO convars, read with `RARELOAD.Get(ply, key)` | `RARELOAD.Settings` | — |
| Global inventory and its versions | PData `global_inventory`, `global_inventory_versions` (through `Store.PData`) | `Inventory` (`sv_inventory.lua` `Write`) | `modules/inventory_global.lua` also writes `global_inventory`: it is the save module that captures and restores it, so it is a co-owner, not a leak. |
| Reload-key config | PData `reload` | `History` (`ReloadConfig`/`SetReloadConfig`) | The command goes through `SetReloadConfig`. |
| Exports | `data/rareload/exports/…` | `Share` | `Store.Forget` replaces the old `_cache` pokes. |
| Inventory exports | `data/rareload/inventories/<sid64>/…` | `sv_commands.lua` (inventory export command) | — |
| Logs | `data/rareload/logs/<date>.txt` | `sv_log.lua` through `Store.AppendLog` | — |

## 2. Server: in-memory stores

| Store | Owner | Notes |
| :--- | :--- | :--- |
| Document cache and the dirty queue (`Store._cache`, flush timer `Rareload.Store.Flush`) | `Store` | Other files call `Store.Forget(rel)`. Nothing outside `sv_storage.lua` reads `_cache`. |
| Module registry (`Pipeline._defs`) | `Pipeline` | Read through `Pipeline.Def(id)` / `Pipeline.Defs()` |
| Tick queue (`Pipeline._queue`) | `Pipeline` | Appended through `Pipeline.Defer(fn)` |
| Undo captures (`undos`, weak) | `History` | One level per player |
| Admin viewing target (`History._viewing`, weak) | `History` | Kept on the table so a hot reload keeps it |
| Checkpoint cursor (`cursor`, weak) | `Checkpoints` | — |
| Death state (`Death.State(ply)`, weak; `beforeHit`, weak) | `Death` | `sv_spawn.lua` sets `died` / reads `choice` through `Death.State` |
| Crash-recovery flags (`crashCheck`, `recovered`, weak) | `Snapshots` | — |
| PvP timestamps (`lastCombat`/`lastSpawn`/`lastRestore`, weak) | `PvP` | — |
| Entity owners (`recorded[ent]`, weak, plus the `RareloadOwner` NW2 value) | `Ownership` | Cleanup and undo lists are mapped through their UniqueID, so ownership survives a reconnect |
| Excluded entities (`RareloadExclude` NW2Bool, plus `EntityMods.rareload.exclude`) | `Exclude` (`sh_exclude.lua`) | The client tracks them through `EntityNetworkedVarChanged` |
| Net handlers (50 request ops), upload handlers, send queues, `ready` set | `Net` | `ready` is once per connection: a client that asks again is ignored |

No Rareload state lives on the `Player` entity: no `ply.rareload*` fields are left, against 9 in 5.4.

## 3. Client

| Store | Owner | Notes |
| :--- | :--- | :--- |
| `RARELOAD.State` (`history`, `objects`, `entryData`, `saves`, `savesRev`, `details`, `antistuck`, `players`, `snapshots`, `usage`, `blocked`, `checkpoints`, `death`, `inventory`) | `cl_state.lua` (14 `Net.On` receivers). It fires `RareloadStateChanged(what, key)`. | Every topic exists from load, so readers don't guard against nil. A reconnect rebuilds it fully. |
| `death.choice`, `export.file`, `share.offer`, `debug`, `toast`, `cmd`, `tool.apply`, `dev.reload` | The UI file that handles the event | These are events, not state. |
| Widget state (search, tab, scroll, place ghost), phantoms, world cards, panel fields (`panel.rareload*`, `ent.rareloadSig`) | The UI file | Presentation only |

## 4. Invariants

1. Only `sv_history.lua` decides what changes in `<mapdir>/<sid64>.json`. Its `save()` is the only writer during play; `Store.Prune` writes what `History.PruneDoc` decided.
2. `activeId`, `quickId` and `deathId` either name an existing entry or are nil, after an append (with the cap), delete, clear or prune. This is enforced by `kept()` and `forgetMissing()` (tests `history_ids_sv`, `regression_sv` 5/8).
3. Nothing outside `Store` touches `_cache`; nothing outside `Pipeline` touches `_defs` or `_queue`. `grep` finds no other use.
4. Transient per-player server state lives in weak-keyed module tables, never on the `Player` entity.
5. Every server push the client keeps lives in `RARELOAD.State`.

How to re-check them:

- 1: `grep -rn "Store.Save(" lua`
- 3: `grep -rnE "\._cache|\._defs|\._queue" lua`
- 4: `grep -rnE "\.rareload[A-Z]" lua/rareload/server`
- 5: `grep -rn "Net.On(" lua/rareload/client`
