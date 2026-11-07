# Rareload Readability Audit

**Goal:** make the code understandable to a developer who did not write it — names that state their purpose without the reader first knowing the architecture or Lua shorthand. This is about *comprehension*, not line count: do not lengthen a name that is already clear, do not delete a single-use helper that names a real step, do not inline logic until it becomes an unreadable expression.

**Scope & method.** Read line-by-line for this audit: the architectural spine — `sh_util.lua`, `sh_net.lua`, `sh_perms.lua`, `sh_exclude.lua`, `sv_pipeline.lua`, `sv_storage.lua`, `sv_antistuck.lua`, `autorun/rareload.lua`, `cl_state.lua` — plus representative samples of each remaining layer (`modules/player.lua`, `cl_history.lua`). The vocabulary is **highly consistent across all 54 files**, so the naming dictionary (§2) and the collision hazards (§3) apply codebase-wide; the per-file tables (§4) cite the files inspected directly, and the same patterns recur in the files covered by pattern. A follow-up pass should confirm each remaining file against §2 before renaming it.

---

## 1. Honest executive summary

Rareload is **already better-named and better-structured than the average GMod addon.** Function names are mostly descriptive (`AntiStuck.IsStuck`, `Store.BlobPut`, `Pipeline.Save`, `History.Append`), constants are `SCREAMING_SNAKE`, public methods are `PascalCase`, and most local helpers name a genuine step rather than fragmenting logic. The comments are unusually good. So this audit is **targeted, not a rewrite**, and it explicitly rejects three things the brief also rejects: blanket lengthening, deleting useful single-use helpers, and inflating line count.

The single highest-value change is **not** making names longer — it is resolving a small number of **short names that mean different things in different files** (§3). `def`, `d`, and `p` each carry two or three unrelated meanings across the codebase; those collisions, not abbreviation per se, are what force a reader to reconstruct the author's mental model. Fixing those first buys most of the comprehension win.

Priorities, in order:
1. **Resolve context-colliding names** (`def`, `d`, `p`) — §3. Highest impact.
2. **Rename genuinely opaque locals** (`by`, `may`, `why`, `r`, `i`-as-`info`, `out`) to purpose-named locals — §2, §4.
3. **Rename a handful of vague local functions** (`run`, `order`, `wants`, `check`, `doc`, `push`, `size`, `asText`, `fmt`) — §5.
4. **Leave structure, single-use helpers, and idiomatic math/loop locals alone** unless §6 flags them.

---

## 2. Codebase naming dictionary (abbreviation → purpose-named)

Apply these per occurrence **where they improve clarity**; keep the short form only inside a 1–3 line idiomatic scope (a tight math expression or a `for i = …` counter) where the longer name adds nothing.

| Current | Rename to | Why / where |
| :--- | :--- | :--- |
| `ply` | `player` | Universal. GMod-idiomatic, but the reader shouldn't have to know that; `player` is free of ambiguity (the `player` *library* is only ever called as `player.Iterator()`, never bare). |
| `opts` | `options` (or `saveOptions` / `restoreOptions`) | `Pipeline.Save`/`Restore` pass a big options table; the specific name documents which one. |
| `ctx` | `saveContext` / `restoreContext` | Two different shapes: the save `ctx` (`{ ply, opts, prev, shared, denied }`, `sv_pipeline.lua:190`) vs the restore `Ctx` object (`sv_pipeline.lua:257`). Name them apart. |
| `prev` | `previousSave` / `activeSave` | `RARELOAD.History.Active(ply)` result (`sv_pipeline.lua:188`). |
| `entry` / `e` | `saveEntry` | A timeline entry `{ time, reason, data, id }`. `e` as a loop var (`sv_storage.lua:279`) is especially terse. |
| `rel` | `documentPath` / `relativePath` | Store path like `"mp/gm_construct/7656…"` (`sv_storage.lua` throughout). |
| `doc` / `d` (storage) | `document` | Store/History JSON doc. |
| `d` (module restore) | `savedData` | In `restore = function(ply, d, ctx)` (`modules/player.lua:20,75,115`), `d` is the module's saved data — rename to `savedData` (the brief's own example). |
| `out` | name the thing built | Never leave it `out`. It is `results`, `candidates`, `matchingPositions`, `orderedModules`, `lines`, `players` depending on site (`sv_pipeline.lua:44`, `sv_antistuck.lua:96`, `sv_storage.lua:188`). |
| `by` | `replacingModuleId` | `sv_pipeline.lua:398` — the brief's own example; `local by = replacedBy(ctx, def)` reads as noise. |
| `may` | `isAllowed` / `canRun` | `sv_pipeline.lua:203,397` — a boolean; name it like one. |
| `why` | `refusalReason` (or `reason`) | Paired with `may`/`ok` throughout (`sv_pipeline.lua`, `sh_util.lua`). |
| `ok` | `succeeded` (where not trivially local) | `local ok, err = pcall(...)` is idiomatic and fine in a 2-line scope; in longer scopes (`sv_pipeline.lua:207-217`) `succeeded` reads better. |
| `err` | `errorText` | Same scoping rule. |
| `ms` | `elapsedMs` | `sv_pipeline.lua:139,207`. |
| `r` | `moduleResult` | `sv_pipeline.lua:414` `local r = ctx._result` — the brief's own example. |
| `i` (as data) | `info` | `local i = row.info or {}` (`cl_history.lua:26,40`) looks like a loop index but is the row's info table. Genuinely misleading; rename to `info`. |
| `u` | `usage` | `Store.UsageLines(u)` (`sv_storage.lua:302`). |
| `b` | `biggestSave` | `sv_storage.lua:319`. |
| `m` | `mapEntry` / `method` | `sv_storage.lua:307` (map), `sv_antistuck.lua:210` (method) — two meanings, name per site. |
| `s` | `settingName` / `text` | `sv_pipeline.lua:122` (setting), `sv_storage.lua:18` (string). |
| `fn` | `callback` / `stepFn` | Where it outlives one line. |
| `sc`, `L`, `UI`, `C` | **keep**, but document | Module-local aliases for `UI.sc`, `RARELOAD.L/UI`, `UI.C` (`cl_history.lua:8-9`). Caching globals as locals is correct GLua; just note them in `CONVENTIONS.md`. |

---

## 3. Context-dependent name collisions (fix these first)

These are the real comprehension hazard: **one short name, several unrelated meanings**, so the reader must hold "which `def`/`d`/`p` is this?" in their head.

### 3.1 `def` — module definition vs entity definition
- In the **pipeline and modules**, `def` is a *module* definition (`{ id, phase, save, restore, … }`): `sv_pipeline.lua:25,37,199,398`, `modules/*`.
- In **snapshot / history / duplicator** code, `def` is an *entity* definition (a duplicator table with `Class`, `PhysicsObjects`, `EntityMods`): `sv_snapshot.lua`, `sv_history.lua` object code.
- **Rename:** `moduleDefinition` (pipeline/modules) vs `entityDefinition` (snapshot/history/world). Never let both live as bare `def`.

### 3.2 `d` — storage document vs module saved-data
- In **Store/History/perms/antistuck**, `d` / `doc` is an on-disk JSON *document* (`sv_storage.lua`, `sh_perms.lua:187`).
- In **module `restore`**, `d` is that module's *saved data* slice (`modules/player.lua:20,75`).
- **Rename:** `document` vs `savedData`.

### 3.3 `p` — payload vs player-record vs point (worst offender)
- **Net receivers**: `p` is the decoded *payload* (`cl_state.lua:42,50,59,…`; `function(p)`).
- **`Store.Overview`**: `p` is a *player usage record* (`sv_storage.lua:232-247,259,312`).
- **Anti-stuck cache**: `p` is a *point/position* array (`sv_antistuck.lua:64-69,97`).
- **Rename:** `payload`, `playerUsage`, `cachedPoint` respectively. Same single letter meaning three things across files is exactly what makes a reader stop and reconstruct context.

---

## 4. Per-subsystem concrete findings (current → proposed)

### 4.1 `sv_pipeline.lua` (the heart — fix names here first; most of the vocabulary originates here)
| Line(s) | Current | Proposed |
| :--- | :--- | :--- |
| 136-140 | `local function run(fn, ...)` | `runProtectedTimed(stepFn, ...)` — it's "protected call + timing", not a generic "run". |
| 66-73 | `local function order()` / `ordered` | `orderedModules()` / `moduleOrder` cache. |
| 121-126 | `local function allowed(def, ply, saving, reason)` | `moduleAllowed(moduleDefinition, player, isSaving, reason)` — distinct from the public `Pipeline.Allowed`. |
| 356-366 | `wants(ctx, def)` | `shouldRestoreModule(restoreContext, moduleDefinition)` → returns `canRestore, refusalReason`. |
| 349-353 | `dataOf`, `loaded`, `external`, `emptied`, `replacedBy` | **Keep** — these name real decision steps and aid reading. Only widen args (`ctx`→`restoreContext`, `def`→`moduleDefinition`). |
| 398-414 | `by`, `may`, `why`, `r` | `replacingModuleId`, `isAllowed`, `refusalReason`, `moduleResult`. |
| 257-331 | `Ctx._current/_result/_waiting/_resumeAt` | Keep the mechanism (it's inherent async state), but document each private field in one comment block; the names are terse for subtle state. |

### 4.2 `sv_storage.lua`
| Line(s) | Current | Proposed |
| :--- | :--- | :--- |
| 296-299 | `local function size(bytes)` | `formatBytes(bytes)` — `size` is generic and shadows the common meaning "a count"; it actually formats a human string. (Also a Phase 7 dedup target with `cl_share`/`sv_commands`.) |
| 16 | `local function log()` | fine as a local accessor; keep. |
| 27-31 | `decode(raw)` | `decodeJson(raw)` or `parseDocument(raw)`. |
| 232-264 | `p`, `b`, `m`, `mine` | `playerUsage`, `biggestSave`, `mapEntry`, `blobsUsedByPlayer`. |
| 302-322 | `u`, `m`, `p`, `b` | `usage`, `mapEntry`, `playerUsage`, `biggestSave`. |

### 4.3 `sh_perms.lua`
| Line(s) | Current | Proposed |
| :--- | :--- | :--- |
| 223-243 | `check(ply, name)` | `hasPrivilege(player, privilegeName)`. |
| 163-168 | `doc()` | `grantsDocument()`. |
| 170-174 | `listOf(sid64)` | `grantedListFor(steamId64)`. |
| 176-180 | `push(ply)` | `pushGrantsToClient(player)`. |
| 153-158 | `granted`, `short`, `grants` | `isGranted`, `shortName`, `grantedCsv`. |

### 4.4 `sv_antistuck.lua`
| Line(s) | Current | Proposed |
| :--- | :--- | :--- |
| 44-47 | `byDistance(pos, points)` | fine (descriptive); keep. |
| 95-115 | `cached`, `displacement`, `navmeshPoints` | keep — they name real candidate sources. Widen `out`→`candidates`, `p`→`cachedPoint`. |
| 181-184 | `config()` / `c` | `methodConfig()`. |
| 107-112 | magic `36`, `128` | name them (`RING_Z_OFFSET`, `MAX_UP_STEP`) — see plan §13.6. |

### 4.5 `cl_state.lua` / client UI
| Line(s) | Current | Proposed |
| :--- | :--- | :--- |
| 23-28 | `asText(v)` | `vectorAngleToLiteral(value)` — states what it guards against (JSON turning `"[1 2 3]"` into a Vector). |
| 42-117 | `p` (every `Net.On`) | `payload`. |
| `cl_history.lua:26,40,74,…` | `local i = row.info or {}` | `local info = row.info` (and guarantee `row.info` per plan §7.6). |

### 4.6 `modules/*.lua`
| Current | Proposed |
| :--- | :--- |
| `d` (restore data) | `savedData` |
| `fmt` (`player.lua:5`) | `formatCoord` |
| `before` (`player.lua:70`) | `healthBeforeDeath` |
| `ctx` | `saveContext` / `restoreContext` |

---

## 5. Function-name findings (describe the action, not a generic verb)

Mostly already good. The ones worth renaming:
- `run` → `runProtectedTimed` (`sv_pipeline.lua:136`) — "run" says nothing; it protects + times.
- `order` → `orderedModules` (`sv_pipeline.lua:66`).
- `wants` → `shouldRestoreModule` (`sv_pipeline.lua:356`).
- `allowed` (local) → `moduleAllowed` (`sv_pipeline.lua:121`).
- `check` → `hasPrivilege` (`sh_perms.lua:223`).
- `push` → `pushGrantsToClient` (`sh_perms.lua:176`).
- `doc` → `grantsDocument` / `methodConfig` (`sh_perms.lua:163`, `sv_antistuck.lua:181`).
- `size` → `formatBytes` (`sv_storage.lua:296`).
- `asText` → `vectorAngleToLiteral` (`cl_state.lua:23`).
- `decode` → `decodeJson` (`sv_storage.lua:27`).

Leave clearly-named ones (`AntiStuck.IsStuck`, `Store.BlobPut`, `Pipeline.Payload`, `History.Append`, `snap`, `byDistance`, `eligible`, `blobRefs`) exactly as they are.

---

## 6. Single-use helpers, fragmentation & indirection — honest take (mostly: do not change)

The brief asks whether logic is "unnecessarily fragmented across numerous single-use local helpers" and whether there is "unnecessary indirection." **For Rareload the answer is largely no**, and the brief itself says not to eliminate single-use functions blindly:

- **Single-use named helpers are a feature here, not a smell.** `snap()`, `byDistance()`, `legacyInstalled()`, `emptied()`, `external()`, `loaded()`, `replacedBy()` each give a name to a non-obvious step. Inlining them would produce exactly the long, unnamed expressions the brief warns against. **Keep them; just rename their args per §2.**
- **Genuine inline candidates (few):** trivial one-liners used once that only forward or restate — e.g. `fmt` (`player.lua:5`, a `string.format` one-liner) could inline, but renaming it `formatCoord` is just as good and keeps intent. Decide case-by-case; this is not a systemic problem.
- **Indirection that is inherent, not gratuitous:** the pipeline's `token`/`pending`/`runFrom`/`nextTick`/`waitFor`/`async` machinery (`sv_pipeline.lua:253-331`) is the cost of multi-tick restore that can be superseded; the net layer's chunk/ack/inflight loop is the cost of paced transfers. Neither is "unnecessary." The fix is **documentation + clearer private-field names**, not removing layers.
- **One real indirection smell:** `Ctx:result` vs `Ctx:step` toggled by `self._current` (`sv_pipeline.lua:286-299`) is subtle. Add a comment and consider `recordModuleStep` / `overrideModuleStep` names.

## 7. Placement (right file / right module)

Structure is already clean (realm prefixes, `server/modules/`, `client/world/`, single `RARELOAD.*` namespace). The known *placement* issues are the cross-module state mutations the 5.5 plan already moves in **Phases 1–3** (checkpoint/death writes leaking into `Store.Save`, client receivers outside `cl_state.lua`). This audit adds only: during the rename pass, apply the "is this function in its owner's file?" check per §2.1 of the plan — a function that reads/writes another subsystem's state should move to (or route through) its owner.

---

## 8. Safe application strategy (so a rename doesn't break the addon)

Renames are mechanical but must preserve every externally-observed string and symbol:
1. **Never rename across a serialization or protocol boundary.** Public `RARELOAD.*` API names, net opcodes (`"rareload.sync"`, every `Net.Handle`/`Net.On` topic), hook names, `properties.Add` ids, console-command names, ConVar names, save-document keys (`entries`, `activeId`, `data`, `$blob`), and localization keys are **contracts** — they stay. This audit only renames *local variables, local functions, and parameters*.
2. **One file per commit**, run `glualint` + `glua_check` after each, so a mistyped rename is caught immediately. (`lint_shadowing` is already on and will flag a rename that collides.)
3. **Start with `sv_pipeline.lua`** (the vocabulary source), then storage, perms, antistuck, then modules, then client — the order the dictionary was derived in.
4. **Resolve §3 collisions first** (`def`/`d`/`p`), because those changes are the ones that most change how the code reads.
5. **Do not touch** idiomatic 1–3 line scopes (`for i = 1, n`, `local a, b` in a sort comparator, `tr`/`mv` in a trace), the `L`/`UI`/`C`/`sc` aliases, or the comments (they're already strong).

## 9. What explicitly NOT to do
- Do not lengthen names that are already clear (`IsStuck`, `BlobPut`, `Append`, `snap`, `byDistance`).
- Do not delete single-use helpers that name a real step (§6).
- Do not inline logic to the point of long unnamed expressions.
- Do not rename anything in §8.1 (serialization/protocol contracts).
- Do not grow the line count as a side effect; a rename is a rename.
