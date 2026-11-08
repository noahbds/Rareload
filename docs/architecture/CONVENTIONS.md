# Rareload Conventions

The rules the code already follows, written down so they stop drifting. When code and this file disagree, fix one of them in the same commit.

## 1. Files and loading

- **Realm by prefix:** `sh_` shared, `sv_` server, `cl_` client. `lua/autorun/rareload.lua` is the only loader:
  - shared core in a **fixed** order: `sh_util`, `sh_perms`, `sh_net`, `sh_config`, `sh_exclude` (`AddCSLuaFile` + `include`);
  - `server/*.lua`, then `server/modules/*.lua`, each folder in **alphabetical** order (`file.Find` + `table.sort`). A server file may not depend on a later file at load time; use it from hooks or functions instead;
  - client: `cl_ui`, `cl_state` first, then the rest of `client/` alphabetically, then `client/world/` in the fixed order `cl_tracking`, `cl_phantoms`, `cl_panels`, `cl_interact`, `cl_highlight`;
  - then `hook.Run("RareloadLoaded")`.
- New Lua files and convar flag changes need a `changelevel` to load; edits to existing files hot-reload. Every file must survive being run twice (`X = X or {}` for module tables, `hook.Add` with a fixed id).
- Line endings are **CRLF** for `.lua`, `.properties` and `.md` (some tools write LF: normalize before committing).
- The tool lives at `lua/weapons/gmod_tool/stools/rareload_tool.lua`; translations in `resource/localization/<lang>/rareload*.properties`.

## 2. Namespace and public surface

- One global: `RARELOAD`. Each subsystem is one `PascalCase` table on it (42 today: server `Store`, `History`, `Pipeline`, `Snapshot`, `Snapshots`, `Inventory`, `AntiStuck`, `Ownership`, `Share`, `Checkpoints`, `Death`, `PvP`, …; client `State`, `UI`, `Menu`, `Timeline`, `Inspector`, `World`, `Panels`, `Phantoms`, …; a client UI next to a server system of the same name takes a `UI` suffix: `CheckpointsUI`, `DeathUI`, `PlaceUI`), plus functions `RARELOAD.Get`, `.Can`, `.Toast`, `.Log`, `.Priv` and values `.version`, `.API`.
- Fields starting with `_` (`Store._cache`, `Pipeline._defs`, `Pipeline._queue`, `Net._handlers`) are **private to their file**. Other files call a function on the owner instead (see `STATE_OWNERSHIP.md`).
- Everything else is `local`. A missing `local` is a bug. Without `glualint` here it is checked two ways (5.5 Phase 10): a token scan for assignments to names a file never declares, and a `__newindex` trap on `_G` (both realms) that records any global written from `lua/rareload/` while the whole test suite and the windows run. Both found only `RARELOAD`.
- What other addons may call or hook, and so must keep its name and arguments: `RARELOAD.Module` (register a save module), `RARELOAD.Panels.Format` (fill a module's "other" tab on the world cards), the `RareloadCanSave` / `RareloadCanRestore` rules and the events in §4, plus `RARELOAD.Get`, `.Can`, `.version`, `.API`. Any other function on a subsystem table is internal and may change.
- `RARELOAD.version` is the only copy of the version string.

## 3. Naming

- `camelCase` locals and local functions, `PascalCase` public functions (`History.Append`), `SCREAMING_SNAKE` constants (`MAX_REQUEST`).
- Names say what a thing is, not its type. A parameter that is not used is dropped, or named `_` when a later one is (engine callbacks keep their parameter order: `Paint(self, width, height)`).
- **No single-letter names**, with exactly these exceptions: `i` / `j` as loop counters, the aliases `L` (translate), `C` (colors) and `D` (the inspector's and timeline's panel table), and `_` for an unused value. That includes `k, v` (`key, value`, or what they are), sort comparators (`left, right`), engine callbacks (`width, height`) and draw coordinates (`posX, posY`). A new name must not shadow a variable of the same name still in use around it.
- One name must not mean two things across the codebase — see `READABILITY_AUDIT.md` §3 (`def`, `d`, `p`).
- Keep a single-use local function when it names a real step or a complex condition; inline it only when it just forwards its arguments.
- Lua operators only: `~=`, `and`, `or`, `not` (no `!=`, `&&`, `//` comments).

## 4. Identifiers that are contracts (never rename for style)

| Kind | Scheme | Examples |
| :--- | :--- | :--- |
| Net strings | `rareload.<x>` | `rareload.sync`, `rareload.req` (only two; everything else is an op inside them) |
| Net ops / push topics | `<system>.<action>` | `history.restore`, `checkpoint.add`, `object.detail` |
| Hook ids (`hook.Add` 2nd arg) | `Rareload.<System>[.<Purpose>]` | `Rareload.Snapshots`, `Rareload.Death`, `Rareload.LegacyConflict` — all of them (the loader's `RareloadLegacyConflict` was renamed in 5.5) |
| Hook events Rareload fires | `Rareload<Event>` | `RareloadCanSave`, `RareloadCanRestore`, `RareloadSaved`, `RareloadRestored`, `RareloadStateChanged`, `RareloadClientReady`, `RareloadLoaded`, `RareloadLanguageChanged`, `RareloadToast` |
| Timer ids | `Rareload.<System>.<Purpose>` | `Rareload.Store.Flush`, `Rareload.History.Push` |
| ConVars | `sv_rareload_<snake_key>` (server), `cl_rareload_<snake_key>` (player, USERINFO) | generated from the setting key by `Util.Snake` |
| Privileges | `rareload_<snake>` | `rareload_restore`, `rareload_rollback` |
| Console command | `rareload <words…>` | `rareload checkpoint add` |
| Phrases | `rareload.<area>.<key>` / `toast.<key>` | `toast.checkpoint_added` |
| Save document keys | as on disk | `v`, `entries`, `activeId`, `quickId`, `deathId`, `checkpoints`, `data`, `$blob` |

## 5. Timing: tick queue vs timers

- Deferred save/restore work runs on the **pipeline tick queue** (`Pipeline.Defer` once Phase 2 adds it), never on timers, so it stays ordered and cancellable (`ctx:isCurrent()`).
- Timers are fine for debounce and pacing. The ones that exist and are legitimate: `Rareload.Store.Flush` (0.5 s one-shot, batches disk writes), `Rareload.Autosave` (1 s), `Rareload.History.Push` (0.1 s debounce), `Rareload.Net.Upload` (0.1 s × parts, paces uploads), `Rareload.World.Update` (client 0.2 s), `Rareload.Inspector.Check` (client 0.25 s debounce). Periodic snapshots use a `Tick` hook (`Rareload.Snapshots`), not a timer.

## 6. Validation and errors

- Validate where data enters (`VALIDATION_BOUNDARIES.md`); trust internal contracts after that.
- `pcall` only around other addons and engine calls on arbitrary entities.
- User-facing text goes through phrases (`RARELOAD.Toast(ply, key, args, kind)`), never hardcoded English on the server, except console output of `rareload` commands.

## 7. Tests

- Tests live in `tests/`, written with `dbg.test` for `gmod-debug-mcp` `run_tests`; `_sv.lua` server, `_cl.lua` client, others both.
- A test must leave `data/rareload` as it found it (or declare `-- may-change:`), and remove what it spawns.
- A bug fix lands with the test that failed before it.
