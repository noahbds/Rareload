# Rareload 5.5 — Web Research & Codebase Audit Log (`MODLOG.md`)

**Date:** 2026-11-06  
**Skill Applied:** `game-research-websearch` (`/Users/noah/.gemini/config/plugins/universal-modder/skills/game-research-websearch/SKILL.md`)  
**Target Document:** `RARELOAD_FUTURE_5.5_STATE_OWNERSHIP_AND_VALIDATION_PLAN.md`  
**Codebase Audited:** All 45 Lua files in `lua/` (`14,792` lines total)

---

## 1. Web Search Queries Executed (21 Distinct Queries Across 20+ Domains)

1. `um kb search "garrys mod"` & `um kb search "source"` (Local `universal-modder` Knowledge Base — 361 field notes checked)
2. `site:wiki.facepunch.com "optimization" OR "performance" OR "Derma" OR "net" OR "hook" Garry's Mod GLua`
3. `site:github.com "glua" OR "garrysmod" optimization luajit performance best practices`
4. `"LuaJIT" "NYI" "Not Yet Implemented" optimization performance guide table allocation closures`
5. `"Garry's Mod" GLua code deduplication data-driven Derma UI optimization Paint hook`
6. `site:wiki.facepunch.com "ents.Iterator" OR "player.Iterator" OR "util.Compress" OR "GetSaveTable" OR "duplicator"`
7. `site:github.com "advdupe2" OR "StarfallEx" OR "DarkRP" OR "pac3" glua optimization table serialization`
8. `site:lua-users.org "Optimisation" OR "Optimization" OR "Tables" OR "Metatable" Lua performance`
9. `site:reddit.com/r/gmod OR site:reddit.com/r/lua glua optimization derma net lag memory leak`
10. `site:web.archive.org "wiki.luajit.org/NYI" OR "wiki.luajit.org" bytecodes library functions trace abort`
11. `site:stackoverflow.com "luajit" OR "glua" table reuse metatable dispatch reduce code duplication data driven`
12. `site:github.com "PIXEL-UI" OR "XeninUI" OR "Helix" OR "NutScript" OR "ULib" glua derma theme vgui.Register deduplication`
13. `site:cloudflare.com "LuaJIT" optimization performance GC table string allocation`
14. `site:love2d.org "LuaJIT" optimization garbage collection table reuse closures performance`
15. `site:wiki.facepunch.com "vgui.Register" OR "DEFINE_BASECLASS" OR "surface.SetDrawColor" OR "draw.RoundedBox" optimization`
16. `site:developer.valvesoftware.com Source Engine entity edict limit saverestore constraint physics optimization`
17. `site:defold.com Lua LuaJIT optimization memory allocation garbage collection table reuse`
18. `site:github.com "FPtje" OR "Falco" DarkRP FPP glua optimization net validation ownership`
19. `site:openresty.org LuaJIT performance optimization table string NYI closures`
20. `site:github.com "GLuaFixer" OR "glualint" OR "luacheck" garrysmod optimization style rules`
21. `site:gmodstore.com` & `site:steamcommunity.com` `"GLua" OR "Garry's Mod" Lua optimization guide performance Derma net`

---

## 2. Source Credibility & Evidence Summary

| Source | URL | Credibility Tier | Key Takeaway Applied to Rareload 5.5 |
| :--- | :--- | :--- | :--- |
| **Facepunch GMod Wiki — Optimization Tips** | <https://wiki.facepunch.com/gmod/optimizationTips> | **Tier 1 (Primary)** | Measure with `SysTime()`, cache `Color()`/`Material()` outside `Paint`, replace $O(N \cdot M)$ scans with lookup maps, bit-size `net.WriteUInt`, use `t[#t+1]`. |
| **Facepunch GMod Wiki — `player.Iterator` & `ents.Iterator`** | <https://wiki.facepunch.com/gmod/player.Iterator> | **Tier 1 (Primary)** | Sequential Lua-cached entity/player iteration; avoids C++→Lua table allocation; return value is read-only. |
| **Facepunch GMod Wiki — `surface.DrawPoly` & `cam.PushModelMatrix`** | <https://wiki.facepunch.com/gmod/surface.DrawPoly> | **Tier 1 (Primary)** | Never allocate vertex tables `{ { x=..., y=... } }` or `Matrix()`/`Vector()` userdatas inside `Paint` or `HUDPaint` every frame. |
| **Facepunch GMod Wiki — `util.TableToJSON` / `util.JSONToTable`** | <https://wiki.facepunch.com/gmod/util.JSONToTable> | **Tier 1 (Primary)** | RapidJSON C++ round-trip is expensive on large tables and coerces numeric keys and `"[x y z]"` strings into `Vector`/`Angle`. |
| **Garry Newman — *Optimising Garry's Mod*** | <https://garry.net/posts/optimising-gmod> | **Tier 1 (Primary)** | C++↔Lua boundary crossings (`__index` on userdata metatables) dominate hot loops; cache values in Lua tables (`ent:GetTable()`). |
| **LuaJIT 2.1 Wiki Archive — NYI & Performance Guide** | <https://web.archive.org/web/20230000000000*/http://wiki.luajit.org/NYI> | **Tier 1 (Primary)** | `FNEW` (closure creation) and unsunk `TNEW` (table allocation) inside hot loops cause trace aborts and GC pressure. |
| **Lua Performance Tips (Roberto Ierusalimschy)** | <https://www.lua.org/gems/sample.pdf> | **Tier 1 (Primary)** | Local upvalues use VM registers instead of `_G` hash lookups; reuse tables in high-frequency callbacks. |
| **Valve Developer Community — Entity Limit** | <https://developer.valvesoftware.com/wiki/Entity_limit> | **Tier 1 (Primary)** | Source 8192 edict ceiling and physics shadow constraints. |
| **`GLuaFixer` / `glualint` (`FPtje/GLuaFixer`)** | <https://github.com/FPtje/GLuaFixer> | **Tier 2 (High)** | Enable `lint_unusedParameters` and `lint_unusedLoopVars` alongside `lint_unusedVars`. |
| **OpenResty & Cloudflare LuaJIT 2.1 Guides** | <https://blog.cloudflare.com/luajit-hacking-getting-next-out-of-the-nyi-list/> | **Tier 2 (High)** | Upvalue caching, `pairs`/`next` JIT behavior in LuaJIT 2.1, `table.concat` vs `..` in loops. |
| **Defold & LÖVE LuaJIT GC Guides** | <https://defold.com/manuals/optimization/> | **Tier 2 (High)** | Eliminating per-frame temporary tables in 60–240 Hz `Paint`/`draw` callbacks prevents incremental GC frame spikes. |
| **Wiremod AdvDupe2, DarkRP, StarfallEx, PAC3, Helix** | <https://github.com/wiremod/advdupe2>, <https://github.com/FPtje/DarkRP>, <https://github.com/Chessnut/helix> | **Tier 3 (Reference Addons)** | Declarative command/setting schemas, unified Derma theme palettes, and `pcall`-isolated addon adapters. |

---

## 3. High-Impact Codebase Findings Added to the 5.5 Plan

1. **Hardcoding & Schema Verbosity (`sh_config.lua`, `sh_perms.lua`, `cl_menu.lua`, `cl_toolscreen.lua`)**:
   - `sh_config.lua:88-503` uses 415 lines for 50 repetitive `RARELOAD.Setting` calls; a declarative `group(scope, category, list)` table schema saves ~290 lines with zero loss of functionality.
   - Domain constants (`COMPONENTS`, `WORLD_KINDS`, `PLAYER_STATES`, `RELOAD_MODES`, setting `unit` suffixes) are duplicated across 2–4 files each and are consolidated into `sh_config.lua` / `sh_util.lua`.
2. **Code Duplication (`cl_menu.lua`, `cl_ui.lua`, `cl_inspector.lua`, `cl_history.lua`, `cl_inventory.lua`, `sv_history.lua`, `sv_commands.lua`, `vehicle_adapters.lua`)**:
   - `cl_menu.lua:5-25, 193-262` re-implements the color palette, font helper, and `toggle`/`slider`/`dropdown`/`button` widgets already in `cl_ui.lua` (~159 lines saved).
   - `UI.Menu(options)` and `UI.SplitRow(parent, buttons, gap)` eliminate 4× duplicated `DermaMenu` builders and 2× duplicated equal-width button bars.
   - `sv_history.lua` duplicates `ModulesFor` (lines 168–173), `Objects`/`ObjectsOf` (lines 359–369), and `DeleteObject`/`DeleteObjects` (lines 494–531).
   - `sv_commands.lua` repeats player/saveId/alive guard boilerplate across 30+ commands (~149 lines saved via declarative command specs).
   - `vehicle_adapters.lua` repeats `get`/`set` property blocks across 6 adapters (~80 lines saved via `rootProps` descriptors).
3. **GLua & LuaJIT 2.1 Efficiency (`cl_ui.lua`, `cl_inspector.lua`, `cl_history.lua`, `cl_inventory.lua`, `cl_panels.lua`, `cl_toolscreen.lua`, `cl_highlight.lua`, `sv_history.lua`, `sh_exclude.lua`)**:
   - `UI.Rows.Paint` (`cl_ui.lua:627`) and `UI.Stats.Paint` (`cl_ui.lua:652`) invoke `rows()` and `cards()` **every single frame**, allocating 15–30 new tables and formatted strings per frame while a window is open. Event-driven caching on `:Refresh()` eliminates ~2,000+ table allocations/sec at 144 FPS.
   - Per-frame `ColorAlpha`, `UI.Mix`, `surface.DrawPoly`, `Matrix()`, and `Vector()` allocations across `cl_ui.lua`, `cl_panels.lua`, `cl_toolscreen.lua`, and `cl_highlight.lua` are eliminated via steady-state fast paths and file-local scratch objects.
   - `cl_inspector.lua:209, 327` serializes every key to JSON inside `pairs()` just to test equality (`util.TableToJSON({ v }) ~= util.TableToJSON({ original[k] })`) when `RARELOAD.Util.Equal` already exists.
   - `sv_history.lua:481, 517` serializes and re-parses the entire world snapshot JSON on the main server thread to edit or delete a single entity; replaced with structural copy-on-write + `Snapshot.Plain(def)`.
   - `sh_exclude.lua:52` runs `ents.FindInSphere` every frame in `HUDPaint`; moved to `cl_tracking.lua`'s 1 Hz scan.

---

## 4. Full Security & Bug Code Review Added as Phases 11 & 12

### Phase 11 — Security, Privilege & Untrusted-Input Hardening (`S-01`..`S-07`)
1. **`S-01` (`sv_history.lua:459-469, 559-566, 800-802`, `sv_snapshot.lua:730` — Critical)**:
   - `History.ValidateEdit` only gated `"Class"` and `"Model"` behind `isAdmin` (`rareload_admin`) and did not check `ClassOverride`, `Snapshot.DENIED`, `OnDieFunctions`, or nested `EntityMods.rareload.id` hijacking. In addition, `util.JSONToTable(a.json)` was not passed through `Snapshot.Plain`, allowing `"[x y z]"` string-to-`Vector` coercion.
2. **`S-02` (`sv_share.lua:105-193`, `modules/player.lua:311-334`, `modules/scene.lua:229-241` — High)**:
   - `Share.Import` accepted imported entity definitions without checking `Snapshot.DENIED[def.Class]` / `Snapshot.DENIED[def.ClassOverride]` or stripping `OnDieFunctions`, and did not clamp extreme/non-finite `data.body` scales/speeds/hulls or `data.worldSettings` ConVar values.
3. **`S-03` (`sv_history.lua:442-455, 734-754` — Medium)**:
   - `History.ObjectDetail` (`object.detail`, gated only by `rareload_restore`) returned the entire raw `def = obj.def` table (which `object.get` gates behind `rareload_manage_objects`).
4. **`S-04` (`sh_util.lua:58-145` — Medium)**:
   - `Util.CheckJSON` had unbounded recursion (`value() -> list() -> value()`) and re-threw string errors (`if not istable(err) then error(err, 0) end`), allowing 200+ nested `[` or `{` characters to trigger an unhandled Lua stack-overflow error.
5. **`S-05` (`sh_net.lua:207-244, 287-311` — Medium)**:
   - `upload.part` checked `a.part > u.total` without `a.part < 1` (while `"uint"` allows `0`), used $O(N)$ `table.Count(u.parts)` on every chunk, and client `net.Receive(SYNC)` lacked an upper bound on `total` chunks.
6. **`S-06` (`sv_share.lua:215-221` — Low–Medium)**:
   - `Share.ReadFile` used `Store.Load(rel, true)` + `Store._cache[rel] = nil` + `util.TableToJSON(doc)`, risking `.corrupt` renames and stale `readonly[rel]` flags on user export files plus a double JSON round-trip.
7. **`S-07` (`sh_perms.lua:127-143` — Low–Medium)**:
   - `RARELOAD.Grant` mutated the cached `d.grants[key]` table before checking `#table.concat(...) > MAX_NW`, and ran the `> MAX_NW` check even when revoking (`on == false`).

### Phase 12 — Runtime Bugs, Memory Corruption & Edge-Case Fixes (`B-01`..`B-12`)
1. **`B-01` (`sv_snapshot.lua:201-212` — Critical)**:
   - `revive(v, depth)` stopped copying at `depth > 8` (while `plainData` saves up to `depth <= 16`) and returned `Vector`/`Angle` userdata references without cloning them, allowing `duplicator.Paste` to mutate cached blobs in place across repeated restores.
2. **`B-02` (`sv_history.lua:536-556` — High)**:
   - `History.RenameObject` indexed `def.EntityMods.rareload.name` without checking if `def.EntityMods` or `def.EntityMods.rareload` is nil; `History.FlagObject` returned `true` and rewrote the snapshot blob even when `def.PhysicsObjects` was nil/empty.
3. **`B-03` (`cl_phantoms.lua:80-115` — High)**:
   - `remove(ent)` returned early when `not IsValid(ent)`, leaking up to 48 child vehicle-part `ClientsideModel` entities stored in `ent.parts` whenever the Source engine invalidated the parent `ClientsideModel` first.
4. **`B-04` (`sv_spawn.lua:4, 33-45` — High)**:
   - Simultaneous player deaths under `deathCleanupMode = "all"` caused the second player's restored entities to be wiped out by the first player's `game.CleanUpMap` callback, and `cleaningUp` had no timeout guard if `game.CleanUpMap` failed to run its callback.
5. **`B-05` (`sv_antistuck.lua:82-91, 260-264` — Medium–High)**:
   - `SetupMove` cached `w.pos` into `_safe_positions.json` (`cached` method #1) whenever the player moved >64 units within 5s—even if they were falling in mid-air, flying in noclip, swimming underwater, or driving a vehicle.
6. **`B-06` (`sv_ownership.lua:80-101` — Medium–High)**:
   - `ownerOf(ent, lists)` did not memoize fallback ownership resolutions (`lists`, `m_PlayerCreator`, `FIELDS`) into `Ownership.recorded[ent]`, causing AdvDupe2/tool-spawned entities to lose their owner when a player disconnected and reconnected.
7. **`B-07` (`sv_snapshot.lua:715-755` — Medium)**:
   - `Snapshot.Restore` ignored `report.existing` when enforcing `opts.limit` (`maxVehicles`), iterated `snap.Entities` in non-deterministic `pairs()` order, and called $O(N)$ `table.Count(paste)` inside the loop.
8. **`B-08` (`modules/player.lua:131` — Medium)**:
   - Privileged noclip restore failed for admins when Sandbox `sbox_noclip` was `0` because `GAMEMODE:PlayerNoClip` returns `false`.
9. **`B-09` (`sh_net.lua:113` — Low–Medium)**:
   - `Net.Push(nil, ...)` relied on `select(2, player.Iterator())`'s undocumented internal return tuple.
10. **`B-10` (`cl_share.lua:42-48`, `sh_net.lua:277` — Low)**:
    - `cl_share.lua` left `"Uploading X/X..."` stuck on the Import panel after the final chunk, and `Rareload.Net.Upload` used a single un-namespaced timer name.
11. **`B-11` (`sv_pipeline.lua:210-232` — Low–Medium)**:
    - `Pipeline.Save` called `Store.BlobPut(out)` before checking if the save was identical (`Util.Equal(prev.data, data)`).
12. **`B-12` (`sv_commands.lua:266-326` — Low)**:
    - `rareload history restore/pin/delete/activate/note` hardcoded `sid(ply)` even though `rareload history [player]` and `rareload history clear [player]` supported targeting another player (`rareload_manage_others`).

---

## 5. Live In-Game Reproduction Gate via `gmod-debug-mcp` (`/Users/noah/gmod-debug-mcp`)

To prevent adding dead defensive code for theoretical bugs that cannot happen in-game:
- **Rule Established in Plan (§14.0 & §15.13):** Every candidate (`S-01`..`S-07` and `B-01`..`B-12`) is treated as an unverified hypothesis until tested in a live Garry's Mod session via `/Users/noah/gmod-debug-mcp`. Unreproducible findings (or sub-claims) are marked `FALSE_POSITIVE` and dropped with **0 LOC added**.
- **Pre-Test Skeptical Catches Already Identified (§15.13):**
  1. **`B-11` (`Store.BlobPut` before `Util.Equal`)**: `prev.data.world` is stored as `{ __blob = "<sha256>" }`. Deferring `BlobPut` until after `Util.Equal(prev.data, data)` would compare a raw table against `{ __blob = "<sha256>" }`, breaking duplicate-save skipping!
  2. **`B-08` (`modules/player.lua:131` noclip when `sbox_noclip 0`)**: Vanilla Sandbox's `GAMEMODE:PlayerNoClip` already checks `GetConVar("sbox_noclip"):GetBool() or ply:IsAdmin()`, so admins can already restore noclip when `sbox_noclip` is `0` (only non-admins granted `rareload_restore_privileged_states` are affected).
  3. **`S-01` (`ValidateEdit` and `ClassOverride`)**: `ValidateEdit` already blocks any key where `def[k] == nil`, so standard props (which have no `ClassOverride` field on capture) already reject adding `ClassOverride`.
- **Planned Enhancements to `/Users/noah/gmod-debug-mcp` (§15.14):**
  1. `dbg.csents(filter)` in `/Users/noah/gmod-debug-mcp/lua/claude_debug.lua` to inspect client-only `ClientsideModel` entities (`EntIndex() == -1`) for `B-03`.
  2. `dbg.bench(fn_or_frames, opts)` in `/Users/noah/gmod-debug-mcp/lua/claude_debug.lua` with `jit.on()` + `collectgarbage("count")` KB delta to measure Phase 8 UI/GC wins.
  3. `dbg.withPlayer(ply, overrides, fn)` in `/Users/noah/gmod-debug-mcp/lua/claude_debug.lua` to test non-admin permission tiers (`S-01`, `S-03`, `S-07`, `B-08`) on a listen/singleplayer server.
  4. In-memory cache reset hook (`RARELOAD.Store._cache = {}`) after `run_tests` file restore in `/Users/noah/gmod-debug-mcp/src/tools3.js`.




## 2026-11-07 — `gmod-debug-mcp` (`v0.5.0`) + `gmod-glua-ls` Ecosystem Improvement Plan (`/game-research-websearch`)
- **Repositories Audited**:
  - [`/Users/noah/gmod-debug-mcp`](file:///Users/noah/gmod-debug-mcp) (`v0.4.0`: `lua/claude_debug.lua` [1,627 LOC], `src/server.js`, `src/tools.js`, `src/tools2.js`, `src/tools3.js`, `src/tools4.js`, `src/rdb.js`, `docs/gm_rdb-notes.md`).
  - [`/Users/noah/vscode-gmod-glua-ls`](file:///Users/noah/vscode-gmod-glua-ls) (commits `d1d70f0`, `ef8c432`, `5ed4bc2`, `bf1ee3b` implementing `src/mcp/*`, `GmodMcpBridgeLua.ts`, `logpoint.ts`, and branch `origin/feat/mcp-rework` `1effbe6`).
  - [`/Users/noah/gmod-glua-ls`](file:///Users/noah/gmod-glua-ls) (`glua_ls`, `glua_check`, and `docs/mintlify/debugger/ai-agents.mdx`).
- **Web Research Executed (`10` searches across primary wiki, GitHub, and MCP ecosystems)**:
  - Engine MCPs: `Coding-Solo/godot-mcp`, `IvanMurzak/Godot-MCP`, `mcp-unity`, Unity `com.unity.ai.assistant`.
  - Debugger & LSP MCPs: `dap-mcp`, `lldb-mcp`, `isaacphi/mcp-language-server`, `Tritlo/lsp-mcp`.
  - GMod Testing & Profiling: `CFC-Servers/GLuaTest`, `FPtje/FProfiler`, `GProfiler`, `DBugR`.
  - Facepunch Garry's Mod Wiki APIs: `Entity:GetNW2VarTable`, `Entity:GetNetworkVars`, `Entity:GetSaveTable`, `constraint.GetAllConstrainedEntities`, `util.TraceLine`/`TraceHull`, `GM:StartCommand`/`CUserCmd`, `ClientsideModel`/`CSEnt`, `physenv.GetPerformanceSettings`, `jit.util`, `sql.Query`.
- **Deliverables Written**:
  - Created [`/Users/noah/gmod-debug-mcp/MCP_IMPROVEMENT_PLAN.md`](file:///Users/noah/gmod-debug-mcp/MCP_IMPROVEMENT_PLAN.md) covering Phases `M1`–`M5`.
  - Updated [`RARELOAD_FUTURE_5.5_STATE_OWNERSHIP_AND_VALIDATION_PLAN.md`](file:///Users/noah/Library/Application%20Support/Steam/steamapps/common/GarrysMod/garrysmod/addons/Rareload/RARELOAD_FUTURE_5.5_STATE_OWNERSHIP_AND_VALIDATION_PLAN.md#L1511-L1557) (`§15.14`).


## 2026-11-07 — Full 54-File Rareload 5.4 (`main` `64797e3`) & `gmod-debug-mcp` (`v0.5.0` `3534946`) Codebase Audit
- **Scope Audited**:
  - Read **100% of all 54 Lua files (`16,616` LOC)** on `main` (`64797e3`, published Rareload `5.4` including `5.4-part-2` PR `#9`: `sv_checkpoints.lua`, `sv_death.lua`, `sv_snapshots.lua`, `cl_checkpoints.lua`, `cl_death.lua`, `cl_place.lua`, `Snapshot.RestoreBatched`, `History.MoveEntry`, `History.RestoreEntry` undo stack, `Store.Overview`/`Store.Prune`, and `1c655e7` `sh_perms.lua` `MAX_NW = 500`).
  - Verified [`/Users/noah/gmod-debug-mcp`](file:///Users/noah/gmod-debug-mcp) `v0.5.0` (`3534946`, all 5 phases `M1`–`M5` implemented).
- **Major Updates Applied to [`RARELOAD_FUTURE_5.5_STATE_OWNERSHIP_AND_VALIDATION_PLAN.md`](file:///Users/noah/Library/Application%20Support/Steam/steamapps/common/GarrysMod/garrysmod/addons/Rareload/RARELOAD_FUTURE_5.5_STATE_OWNERSHIP_AND_VALIDATION_PLAN.md)**:
  1. **State Ownership Fixes for 5.4-part-2 Modules (Phases 0–3)**:
     - Added `sv_checkpoints.lua:15-21`, `sv_death.lua:37-40`, and `sv_storage.lua:249-302` (`Store.Overview`/`Store.Prune` forgetting `d.deathId` and `d.quickId`) to Phase 2 `History`/`Store` encapsulation.
     - Added `sv_snapshots.lua:39,74,88,203` and `sv_snapshot.lua:906` (`Pipeline._defs`/`Pipeline._queue` reach-ins) to Phase 1 `Pipeline.Session(ply)` / `Pipeline.ModuleDefs()` encapsulation.
     - Added `cl_checkpoints.lua:11-26` and `cl_death.lua:15-17` client caches to Phase 3 `cl_state.lua`.
  2. **Deduplication & Performance Expansion Across All 54 Files (Phases 6–8)**:
     - Added `sh_net.lua` (56 net op schemas), `sv_commands.lua` (`949` LOC, 48 command paths), `sv_history.lua` (`1,043` LOC, `ModulesFor`/`Objects`/`DeleteObject`/`MoveEntry` consolidation), and `cl_place.lua:171-334` per-frame HUD trace/halo allocation removal.
  3. **Skeptical Triage & 4 New 5.4-part-2 Bug Candidates (Phases 11–12 & §15.17)**:
     - Proven `S-03` (`object.detail` sending `def = obj.def`) **`FALSE_POSITIVE`** (`world/cl_panels.lua:284-327` `objectCats` requires `detail.def` for 4 tabs of the 3D2D World Display).
     - Recorded `S-07` (`sh_perms.lua:182-206`) as already resolved in `1c655e7` (except revoking when `> MAX_NW`).
     - Added **`B-13`** (`sv_snapshots.lua:35` & `sv_history.lua:190` calling `Pipeline.Save(..., { captureOnly = true })` which aborts on dead/spectating/disabled players), **`B-14`** (`sv_snapshot.lua:885-981` `Snapshot.RestoreBatched` overlapping timer race & `DENIED[def.ClassOverride]`), **`B-15`** (`sv_history.lua:768-779` `history.move` target player refresh), and **`B-16`** (`sv_death.lua:34-40` double `Store.Save` & `keepActive` comparison bug).
