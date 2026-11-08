# Rareload Validation Boundaries

Rule (plan §7.2): **parse and normalize once where data enters, then trust internal contracts.** This file lists every place untrusted or uncertain data enters Rareload, what checks it there today, and what code behind it may therefore assume. Phase 4 removes internal re-checks only behind a boundary listed here.

Written at the Phase 0 baseline and checked against the code at the end of 5.5 (Phase 5 audit, 2026-11-08). The op list below was compared with the live `Net._handlers` (50 ops, 1 upload handler). Line numbers have drifted, so functions are named instead.

## 1. Client → server requests (`sh_net.lua`)

Entry: `net.Receive("rareload.req")` (`sh_net.lua:154-177`). Every request passes, in order:

1. size: `len > MAX_REQUEST * 8` (64 KB) is dropped;
2. known op: unknown ops are logged and dropped;
3. rate limit: per player per op (`h.rate` seconds);
4. privilege: `RARELOAD.Can(ply, h.priv)` when the op has one;
5. schema: `Net.Validate(h.args, util.JSONToTable(raw))` — `bool`, `number` (finite), `uint` (finite, ≥ 0, integer), `string[:max]`, `?` = optional; **keys not in the schema are dropped**;
6. `ProtectedCall(h.fn, ply, args)`.

**Handlers may assume:** `ply` is a valid connected player, `args` has exactly the schema keys with the declared types, and the privilege check passed. They must still check **meaning**: that an id/entry exists, that `sid` names a player they may act on, that a JSON string field parses to the expected shape.

**50 registered ops** (the plan says 36; it predates several 5.4 features), plus 1 upload handler (`import`). Unchanged by 5.5. Live inventory (`Net._handlers` at runtime):

| Op | Privilege | Rate (s) | Args |
| :--- | :--- | :--- | :--- |
| `ready`, `ack` | — | — | `ack`: id, part |
| `upload.part` | per upload op (`import`) | — | op, id, part, total, data (string:60000) |
| `antistuck.get` / `.config` | `rareload_anti_stuck` | 0.5 / 0.1 | `.config`: action, id |
| `blocked.get` / `.set` | `rareload_block_classes` | 0.5 / 0.1 | `.set`: add, class |
| `checkpoint.get/add/go/toggle/remove` | `rareload_checkpoints` | 0.1–0.2 | name / i |
| `data.usage` | `rareload_data_cleanup` | 2 | — |
| `death.back` / `.get` / `.respawn` | `rareload_restore` | 1 / 0.5 / 0.5 | `.respawn`: mode |
| `export.get` | `rareload_export` | 2 | id |
| `history.get/activate/clear/delete/note/pin/restore/undo` | `rareload_restore` (+ `sid` checked in `handle()` for other players) | 0.2 | sid, id, … |
| `history.move` | `rareload_save` | 0.2 | sid, id, x, y, z, yaw |
| `history.objects` | `rareload_restore` | 0.3 | id |
| `history.players` | `rareload_manage_saves` | 1 | — |
| `history.reloadMode` | `rareload_use_tool` | 0.2 | sid, mode, comps |
| `inventory.get/set/give/copy/rollback` | `rareload_manage_inventory` | 0.3 | save, json, from, version |
| `object.get/delete/deleteMany/edit/flag` | `rareload_manage_objects` | 0.2–0.3 | entryId, objectId, ids, json, flag, value |
| `object.rename` | `rareload_restore` | 0.2 | entryId, objectId, name |
| `object.detail` | — (checked inside: own save needs `rareload_restore`; another player's needs `debug` on **and** `rareload_debug`) | 0.1 | sid, entryId, objectId |
| `object.exclude` | `rareload_save_entities` (+ ownership checked inside) | 0.2 | ent, on |
| `settings.set` / `.lock` / `.reset` | `rareload_settings` | 0.1 / 0.1 / 1 | key, value / key, locked |
| `share.send` | `rareload_share` | 3 | id, sid |
| `share.answer` | — (token checked inside) | 0.5 | token, accept |
| `snapshot.list/take/rollback` | `rareload_rollback` | 0.5 / 2 / 2 | id |

Ops with **no** schema-level privilege (`ready`, `ack`, `upload.part`, `object.detail`, `share.answer`) each check authority inside the handler.

### JSON fields inside requests (second-level boundary)

These ops carry a JSON string that the handler parses itself, so the schema only bounds its length:

| Op | Parse | Validator | Status |
| :--- | :--- | :--- | :--- |
| `object.edit` | `util.JSONToTable(a.json)` | `History.ValidateEdit(entityDef, edit, isAdmin)`: known keys, same types, `Class`/`Model` only for `rareload_admin` | **S-01 fixed**: an edited id can no longer make a restore move another player's object (`object_owner_sv`); edits are copy-on-write (`regression_sv` 16) |
| `inventory.set` | `util.JSONToTable(a.json)` | `Inventory.SetFrom` → `Inventory.Clean` | covered by `regression_sv` 15 |

Note: `util.JSONToTable` turns `"[1 2 3]"`-shaped strings into `Vector`/`Angle` userdata; validators must not assume strings stay strings (see `Util.AsText`).

### Uploads (`upload.part` → `Net._uploadHandlers.import` → `Share.Import`)

Checks at the boundary (`sh_net.lua:212-236`): handler exists and its privilege; part 1 opens the upload and `total` is bounded by `maxBytes()`; later parts must match op/id and arrive within 30 s; base64 must decode; `part ≤ total`, no duplicate part; running byte total ≤ `maxBytes()`; final text decompressed with a `MAX_TRANSFER` (16 MB) cap.
**S-05: false positive.** Part 1 is needed to open an upload, and a stray part 0 can only make the concat stop early, so decompression fails and the upload is refused. There is no bypass. The part counter is now a plain count (`upload.got`).

## 2. Files read from disk (`sv_storage.lua`)

Entry: `Store.Load(rel)` → `decodeJson()`: empty → nil; `util.JSONToTable(raw, true)` (no size limits, big saves must load); non-table → nil. Unreadable files are moved to `*.corrupt-<time>.json` and the `.bak.json` copy is tried. Documents with `v > Store.SCHEMA` are loaded **read-only** (never written back).

**Callers may assume:** a table or nil, never a string. They may **not** assume shape: a document can be from an older schema, hand-edited, or from a newer build. Shape normalization belongs in the owner's load function, and happens there once. `History.Doc` normalizes a player document once (`entries`, `checkpoints`, each `entry.data`); `Snapshots`, `Blocked` and `AntiStuck` replace a wrong-shaped document in their `loadDoc`. A saved object's optional parts are read through `Snapshot.Mods/Rareload/Bones`. Saved snapshots themselves are never rewritten: that would change their blob hashes.

JSON numeric-key coercion: `util.JSONToTable` turns number-like string keys into numbers, the root of the `t[id] or t[tonumber(id)]` probing (plan §7.4). Keys that must survive are prefixed (`"k_"` in `_objects.json`, string ids in snapshots).

PData (`Store.PData`): same `decode()`; same assumptions.

## 3. Imports (`sv_share.lua`)

Entries: `Share.Import` (upload from a client, privilege `rareload_import`), `rareload import` console command, and share offers between players (`share.send` / `share.answer`). `Share.ReadFile` loads through `Store.Load`, then calls `Store.Forget` (**S-06 fixed**, Phase 2).
**S-02 fixed:** `body` and `worldSettings` are checked against per-field ranges (`RANGES` in `sv_share.lua`). Parts out of range are left out and listed (`import_ranges_sv`). Ids in imported objects never make a restore take over another player's object (S-01).

## 4. Console commands (`sv_commands.lua`)

Entry: `concommand.Add("rareload", …)` → `Cmd.Run(ply, args)`. Each command declares its privilege, and whether it needs a `player`, a living (`alive`) one, a `target` (an online or offline player, resolved and logged by `Cmd.Target`) or a save `id` (`Cmd.SaveID`). `Cmd.Run` enforces all of them in one place (Phase 7). The server console (`ply == NULL`) may run everything that doesn't need a player. Other command: `gmod_admin_cleanup` is wrapped in `sv_spawn.lua` (it passes through to the original).
Client-only: `rareload_checkpoints` opens a window.

## 5. Third-party addons and engine calls (keep the guards)

Code calling into other addons, or into engine functions that can error on odd entities, stays `pcall`-guarded (or uses `Util.Call` / `ProtectedCall`). `pcall` count per file at the end of 5.5:

| File | `pcall` | Reason |
| :--- | :--- | :--- |
| `modules/vehicles.lua` | 8 | vehicle bases (simfphys, LFS/LVS, WAC, Glide…) |
| `modules/vehicle_adapters.lua` | 6 | per-addon adapters |
| `sv_commands.lua` | 7 | self-test / command bodies |
| `modules/scene.lua` | 2 | map entities, environment |
| `modules/weapon_state.lua` | 2 | ARC9 / ArcCW attachments |
| `sv_ownership.lua` | 2 | prop-protection addons (CPPI) |
| `sv_snapshot.lua` | 2 | duplicator paste of arbitrary entities |
| `sh_util.lua` | 2 | `Util.Call` (other addons' functions), JSON check |
| `modules/entity_state.lua`, `sv_spawn.lua`, `sv_status.lua`, `cl_ui.lua` | 1 each | entity methods, cleanup wrapper, addon probes, UI |

Module isolation in `sv_pipeline.lua` uses `xpcall` (`runProtectedTimed`). PAC3 calls in `modules/player.lua` run inside that protected module call. Built-in Player methods are called directly (Phase 4 rule 5). Phase 4 reviewed the internal ones: the `sv_commands.lua` self-test and the `sv_status.lua` probes are diagnostics that must not crash, so they stay.

## 6. What internal code may trust (contracts)

- A **save entry** returned by `History.Get/Active/Quick` is a table with numeric `id`, `time`, `data` (module id → saved data or `{["$blob"]=sha}`).
- **Module data** handed to a module's `restore` is what that same module's `capture` produced (or an older schema of it — modules own their migration).
- **`RARELOAD.Get(ply, key)`** always returns the declared type within range (tested by `util_spec.lua`).
- **Client `RARELOAD.State`**: every topic exists from file load (`history`, `objects`, `entryData`, `saves`, `savesRev`, `details`, `antistuck`, `players`, `snapshots`, `usage`, `blocked`, `checkpoints`, `death`), so readers don't guard against nil (Phase 3). `row.info` and inventory `versions` are always sent (Phase 4). The `inventory` payload itself can be absent or old, and stays guarded.
