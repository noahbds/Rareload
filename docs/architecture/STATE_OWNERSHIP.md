# Rareload State Ownership (5.5 Phase 0 baseline)

Measured on branch `v5.5` (from `main` `396f9ad`): **55 Lua files, 16,616 LOC** (the plan says 54; it misses `server/sv_status.lua`). Line numbers below are from this checkout; the plan's line numbers come from another copy and are often off.

Every state store has exactly one **owner** (decides what it means and is the only writer). Other files may read it, persist it on the owner's behalf, transport it or show it. Rows marked **LEAK** are writes by a non-owner, to be fixed in Phases 1–3.

## 1. Server: persistent stores

| Store | Where | Owner | Other writers today |
| :--- | :--- | :--- | :--- |
| Player save document (`entries`, `nextId`, `activeId`, `quickId`, `deathId`, `checkpoints`, `nick`, `sid64`) | `data/rareload/<mapdir>/<sid64>.json` | `History` (`sv_history.lua`, writes only through local `save()`, line 32) | **LEAK** `sv_checkpoints.lua:63,74,86` (`Store.Save` after mutating `d.checkpoints`, ×3, not ×1 as the plan says); **LEAK** `sv_death.lua:40` (sets `d.deathId` then a second `Store.Save` after `Pipeline.Save` already saved); **LEAK** `sv_storage.lua:276-287` (`Store.Prune` removes entries itself, keeping only `pinned` and `activeId` — it **drops the quick and death entries**, leaving `quickId`/`deathId` dangling) |
| Content-addressed blobs (`{ ["$blob"] = sha }`) | `data/rareload/blobs/<sha>.json` | `Store` (`BlobPut`/`BlobGet`/`GC`/`GCAll`) | References are owned by `History` (entries) and `Snapshots` (`_server.json`) |
| Server snapshots ring | `<mapdir>/_server.json` | `Snapshots` (`sv_snapshots.lua:83`) | none |
| Crash flag | `data/rareload/_running.txt` | `Snapshots` lifecycle, written through `Store.Flag`/`SetFlag` | none |
| Object name counters | `<mapdir>/_objects.json` | `Snapshot.Num` (`sv_snapshot.lua:133-145`) — not in the plan's audit | none; note it does a `Store.Load` + `Store.Save` per newly numbered entity |
| Anti-stuck safe positions | `<mapdir>/_safe_positions.json` | `AntiStuck` (`sv_antistuck.lua:71`) | none |
| Anti-stuck method order | `data/rareload/antistuck.json` | `AntiStuck` (`sv_antistuck.lua:233`) | none |
| Blocked classes | `data/rareload/blocked.json` | `Blocked` (`sv_exclude.lua:55,67`) | none |
| Persistent grants | `data/rareload/perms.json` | `RARELOAD.Perms` (`sh_perms.lua:201`) | none |
| Global settings | archived `sv_rareload_*` convars | `RARELOAD.Settings` (`sh_config.lua`) | none — there is **no** `settings.json` (the plan's §3.3 lists `sh_config.lua` `Store.Save` calls that no longer exist) |
| Per-player settings | `cl_rareload_*` USERINFO convars, read with `RARELOAD.Get(ply, key)` | `RARELOAD.Settings` | none |
| Global inventory + versions | PData `global_inventory`, `global_inventory_versions` (via `Store.PData`) | `Inventory` (`sv_inventory.lua:109,130`) | `modules/inventory_global.lua:24,32` reads and writes PData directly — it is the module that captures/restores it, so this is a shared-owner, not a leak; the plan's "route the clear through Inventory" is a Phase 1 cleanup |
| Reload-key config | PData `reload` | `History` (`sv_history.lua:225,799`) | `sv_commands.lua:368` writes it directly (**LEAK**, small) |
| Exports | `data/rareload/exports/...json` | `Share` (`sv_share.lua:50`) | none; `sv_share.lua:52` then clears `Store._cache[rel]` directly |
| Inventory exports | `data/rareload/inventories/<sid64>/...` | `sv_commands.lua:750` | none |
| Logs | `data/rareload/logs/<date>.txt` | `sv_log.lua` | none |

## 2. Server: in-memory stores

| Store | Where | Owner | Notes |
| :--- | :--- | :--- | :--- |
| Document cache + dirty queue | `Store._cache`, flush timer `Rareload.Store.Flush` (0.5 s) | `Store` | **LEAK** `_cache[rel] = nil` from `sv_share.lua:52,218` and `sv_commands.lua:898,903` (self-test). Needs a `Store.Forget(rel)` |
| Module registry | `Pipeline._defs` | `Pipeline` | Read directly by `sv_snapshots.lua:39`, `sv_share.lua:154,177`, `sv_commands.lua:907` (plan only lists `sv_snapshots`) |
| Tick queue | `Pipeline._queue` | `Pipeline` | Appended directly by `sv_snapshots.lua:74,88,203`, `sv_snapshot.lua:906` |
| Undo snapshots | `History._undo[sid]` | `History` | — |
| Admin viewing target | `viewing[admin] = sid` (weak) | `History` | — |
| Checkpoint cursor | `cursor[ply]` | `Checkpoints` | — |
| Pre-hit health | `beforeHit[ply]` | `Death` | — |
| PvP timestamps | `lastCombat`/`lastSpawn`/`lastRestore` (weak) | `PvP` | already clean |
| Entity owners | `recorded[ent]` (weak) + `RareloadOwner` NW2 | `Ownership` | — |
| Excluded entities | `RareloadExclude` NW2Bool + `EntityMods.rareload.exclude` | `Exclude` (`sh_exclude.lua`) | — |
| Net handler + upload registry, send queues | `Net._handlers` (50 ops), `Net._uploadHandlers` (`import`), `Net._state` | `Net` | — |
| **Loose fields on the `Player` entity** | `ply.rareload*` | — | **9 fields**, not 7: `DeathPending`, `DeathTold`, `DeathSpot`, `BackAt`, `SpawnChoice` (`sv_death.lua`), `Died`, `Cleaned`, `SpawnChoice` (`sv_spawn.lua`), `CrashCheck`, `Recovered` (`sv_snapshots.lua`). None in `sv_pipeline.lua` (the plan's `:301` reference is stale). Target: module-owned weak tables (`Death.State(ply)`, and the same in `Snapshots`) |

## 3. Client

| Store | Owner | Notes |
| :--- | :--- | :--- |
| `RARELOAD.State` (`history`, `players`, `snapshots`, `usage`, `objects`, `entryData`, `inventory`, `saves`, `savesRev`, `details`, `antistuck`, `blocked`, `lastAutosave`) | `cl_state.lua` (13 receivers), fires `RareloadStateChanged(what, key)` | single projection |
| Checkpoint list | **LEAK** `cl_checkpoints.lua:12` (`Net.On("checkpoints")` into a file-local list) | move into `State` (Phase 3) |
| Death info / spot | **LEAK** `cl_death.lua:9` (`Net.On("death")`) | move into `State` (Phase 3) |
| `death.choice`, `export.file`, `share.offer`, `debug`, `toast`, `cmd`, `tool.apply`, `dev.reload` | the UI file that handles the event | events, not state — they stay where they are |
| Widget state (search text, tab, scroll, place ghost), phantoms, world cards | the UI file | presentation only |

## 4. Invariants to hold through 5.5

1. Only `sv_history.lua` calls `Store.Save` on `<mapdir>/<sid64>.json`.
2. `activeId`, `quickId` and `deathId` either name an existing entry or are nil, after append (cap), delete, clear and prune. **Today `History.Delete` (`sv_history.lua:117`) only repairs `activeId`, and the cap in `History.Append` and `Store.Prune` can drop the quick and death entries.**
3. Nothing outside `Store` touches `Store._cache`; nothing outside `Pipeline` touches `_defs` / `_queue`.
4. Transient per-player server state lives in weak-keyed module tables, never on the `Player` entity.
5. Every server push the client keeps lives in `RARELOAD.State`.

## 5. Baseline test and lint results (2026-11-07, `gm_construct`, 1 player)

Static check: `glua_check` and `glualint` are **not installed** on this machine; `gmod-debug-mcp check` fell back to `CompileString` — all 55 files compile. Install one of them before the Phase 10 lint exit criteria can be measured.

`run_tests tests/` (19 files): **13 failures in 7 files**, all others pass. These are the baseline; Phase 12 triage decides which are real bugs and which are test-environment problems.

| File | Failing cases | First look |
| :--- | :--- | :--- |
| `antistuck_sv.lua` | 3 / 6 | Calls `AntiStuck.OnFloor`, which does not exist: the test was written ahead for **B-05** (safe positions recorded in the air / after a teleport). Failures = B-05 reproduces. |
| `checkpoints_sv.lua` | 2 / 10 | "go by name" and "cycle wraps" end not at the checkpoint |
| `death_sv.lua` | 2 / 10 | respawn not at the respawn point; "back to before I died" not where they died |
| `spawn_sv.lua` | 2 / 11 | after two spawns in a row the position is right but health is 100, expected the saved 73; the bot case then sees the same |
| `snapshots_sv.lua` | 1 / 8 | `Snapshots.Find(60)` returned an older snapshot already on disk (the test assumes an empty `_server.json`: environment) |
| `pvp_quick_sv.lua` | 2 / 17 | "shoot" needs a bot (environment); the autosave-refused-in-combat case follows from it |
| `smooth_restore_sv.lua` | 1 / 8 | 120 props: ticks of 100–116 ms with `restoreBatch` 50 (perf budget, machine dependent) |

The checkpoint and death position failures share a pattern (the player ends somewhere else after a teleport/restore); the current spot is not considered stuck (`AntiStuck.IsStuck` → false), so **B-17** is not confirmed by this alone. Also, `run_tests` reported that the full suite leaves data changed (`_objects.json`, `_safe_positions.json`, `_server.json`, the player's document) — the tests need cleanup hooks (Phase 5).
