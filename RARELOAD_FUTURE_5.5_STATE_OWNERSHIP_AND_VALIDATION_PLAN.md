# Rareload 5.5 --- State Ownership & Validation Simplification

## 1. Purpose

Rareload 5.5 is a focused architectural cleanup. It is not a general
rewrite and should not introduce new features unrelated to the goals
below.

The release focuses on two problems:

1.  **Duplicated state management:** the server, storage layer, history
    system, inventory features, and client cache must have clear and
    non-overlapping ownership.
2.  **Defensive programming everywhere:** validate untrusted data at
    system boundaries, then rely on established internal contracts
    instead of repeatedly checking the same invariants.

The objective is to reduce the number of concepts and mutation paths
developers must understand, without sacrificing compatibility,
reliability, or runtime safety.

### Core principles

-   Every piece of authoritative state has exactly one owner.
-   Other systems may persist, transport, cache, or project that state,
    but must not become competing authorities.
-   Persistent mutations go through explicit APIs owned by the relevant
    subsystem.
-   Validate data when it crosses a trust boundary.
-   Internal functions may rely on documented contracts once those
    boundaries have been crossed.
-   Keep defensive checks that protect against real runtime uncertainty,
    engine behavior, asynchronous execution, or third-party addons.
-   Prefer simplifying existing architecture over introducing new
    abstractions.

------------------------------------------------------------------------

## 2. Target Architecture and Ownership

### 2.1 Ownership model

  -----------------------------------------------------------------------
  Subsystem               Owns                    Must not own
  ----------------------- ----------------------- -----------------------
  `History`               Save documents,         File I/O, client UI
                          entries, active save,   state, restore
                          timeline metadata,      execution
                          save-level mutations    

  `Store`                 Disk persistence, JSON  Save semantics,
                          encoding/decoding,      active-save decisions,
                          storage cache,          inventory rules
                          dirty-write queue,      
                          blobs, persistent       
                          player data             

  `Pipeline`              Save/restore execution, Persistent save
                          module ordering,        documents or
                          execution context,      independent copies of
                          restore lifecycle       saved state

  State modules           Capture and restore     Independent copies of
                          their own domain data   the complete save
                                                  document

  `Inventory`             Inventory-specific      A second source of
                          normalization, rules,   truth for per-save
                          operations, and         inventory data
                          inventory version       
                          semantics               

  `Net`                   Transport, request      Application state and
                          decoding, boundary      save semantics
                          validation,             
                          permissions, rate       
                          limiting                

  Client `State`          Client-side             Authoritative game
                          projection/cache of     state or persistent
                          server-provided data    save state
                          for UI                  

  UI panels               Temporary presentation  Independent
                          state and derived       authoritative copies of
                          display values          server data
  -----------------------------------------------------------------------

### 2.2 Data flow

``` mermaid
flowchart TD
    subgraph SERVER["Server — authoritative application state"]
        PIPE["Pipeline"]
        MOD["State modules"]
        HIST["History — save documents"]
        INV["Inventory — inventory rules"]
        STORE["Store — persistence"]
        NET["Net — transport"]
    end

    DISK[("Disk / JSON / blobs")]
    CLIENT["Client State — UI projection"]

    PIPE --> MOD
    MOD --> PIPE
    PIPE --> HIST
    INV --> HIST
    HIST --> STORE
    STORE <--> DISK
    HIST --> NET
    INV --> NET
    NET --> CLIENT

    CLIENT -. "requests changes" .-> NET
    NET -. "validated commands" .-> HIST
    NET -. "validated commands" .-> INV
```

### 2.3 Ownership rules

1.  `History` is the authority for the logical contents and lifecycle of
    save documents.
2.  `Store` is the authority for persistence mechanics and
    storage-related caches.
3.  `Pipeline` coordinates execution but does not become another owner
    of saved data.
4.  State modules own domain-specific capture and restore behavior, not
    copies of the save document.
5.  `Inventory` owns inventory semantics. Per-save inventory data
    remains part of the corresponding History entry; global inventory
    remains a distinct target.
6.  `Net` transports commands and projections. It does not decide
    application state.
7.  Client `State` is disposable. It can be rebuilt from server pushes
    and must never be treated as authoritative.
8.  UI panels should derive their views from client `State` rather than
    maintaining independent copies of the same server data.

------------------------------------------------------------------------

## 3. Phase 0 --- Baseline and State Audit

**Goal:** understand the existing ownership and mutation paths before
changing implementation.

Do not refactor during this phase.

### 3.1 Establish a baseline

-   Record the current branch, commit, and test results.
-   Run the existing lint, type/static checks, unit tests, and
    integration/e2e tests.
-   Record known failures separately from regressions introduced by 5.5.
-   Identify the existing save-format/schema version and compatibility
    expectations.

### 3.2 Inventory authoritative state

Find every persistent or semi-persistent state structure and document:

-   State name and shape.
-   Current location.
-   Intended authoritative owner.
-   Read paths.
-   Mutation paths.
-   Persistence mechanism.
-   Client synchronization mechanism, if applicable.
-   Whether it is authoritative, cached, derived, or temporary.
-   Whether multiple systems can mutate it directly.

Initial areas to inspect:

  ---------------------------------------------------------------------------
  State                   Known/current location to   Intended authority
                          inspect                     
  ----------------------- --------------------------- -----------------------
  Save entries            `History.Doc()` and         `History`
                          `d.entries`                 

  Active save ID          `d.activeId`                `History`

  Save metadata           History document entries    `History`

  World snapshot blobs    Blob references in entry    `History` owns
                          data                        references; `Store`
                                                      owns blob persistence

  Global inventory        `Store.PData()` and         `Inventory` owns
                          inventory functions         semantics; Store
                                                      persists

  Per-save inventory      `entry.data` and            `History` owns
                          `entry.inventoryVersions`   document; `Inventory`
                                                      owns inventory
                                                      operations

  Storage cache           Store-local cache           `Store`

  Pending writes          Store dirty queue           `Store`

  Client timeline         `RARELOAD.State.history`    Server History is
                                                      authoritative; client
                                                      is a replica

  Client object details   `RARELOAD.State.details`    Server is
                                                      authoritative; client
                                                      cache is disposable

  Restore context         Pipeline context            `Pipeline`

  Module execution data   `ctx.shared` and related    `Pipeline` execution
                          context fields              context
  ---------------------------------------------------------------------------

Treat this table as a starting point, not a complete inventory. Verify
all entries against the current source.

### 3.3 Find all mutation paths

Search for and classify:

-   `Store.Save`, `Store.Delete`, `Store.PData`, `Store.BlobPut`, and
    `Store.BlobGet`.
-   Direct mutations of History documents and entries.
-   Direct writes to `entry.data` and `entry.inventoryVersions`.
-   Direct writes to global inventory data.
-   Mutations of `RARELOAD.State` on the client.
-   UI-local caches that duplicate server-provided state.
-   Network handlers that mutate persistent state.
-   Import, export, rollback, undo, cleanup, and autosave paths.

For every persistent structure, identify all writers. Each should have
one documented mutation API.

### 3.4 Deliverables

Create:

-   `docs/architecture/STATE_OWNERSHIP.md`
-   `docs/architecture/VALIDATION_BOUNDARIES.md`

The ownership document must identify one authoritative owner for every
persistent state structure. The validation document must record the
intended validation boundary for each important data flow.

**Exit criteria:**

-   Baseline test results are recorded.
-   All important persistent state structures are inventoried.
-   All direct mutation paths are identified.
-   No implementation changes have been made yet.

------------------------------------------------------------------------

## 4. Phase 1 --- Centralize History Mutations

**Goal:** make `History` the single owner of save-document semantics and
mutations.

### 4.1 Standardize the History API

Use the existing History API as the foundation rather than introducing a
new repository or document-management layer.

Relevant operations include:

  -----------------------------------------------------------------------
  Operation                           Responsibility
  ----------------------------------- -----------------------------------
  `History.Doc()`                     Resolve/load the player's save
                                      document

  `History.Get()`                     Read a save entry

  `History.Active()`                  Read the active entry

  `History.Append()`                  Add a save entry and update
                                      timeline state

  `History.Update()`                  Mutate an existing entry through a
                                      controlled callback

  `History.Delete()`                  Delete an entry

  `History.Activate()`                Change the active save
  -----------------------------------------------------------------------

Verify the exact public API and behavior in the target branch before
changing it.

### 4.2 Route mutations through History

Audit and update all features that modify save documents, including:

-   Pinning and notes.
-   Active-save changes.
-   Quick-save metadata.
-   Inventory editing and rollback.
-   Object editing, deletion, flags, and names.
-   Import operations.
-   Undo operations.
-   Save append and retention cleanup.
-   Any administrative or console command that modifies an entry.

Existing specialized operations may remain when they provide meaningful
domain behavior, but they should use History-owned mutation paths
internally.

### 4.3 Restrict mutable document access

-   Avoid exposing mutable document references to unrelated systems when
    they only need read access.
-   Keep mutation callbacks narrow and explicit.
-   Do not add defensive copies everywhere by default; copying large
    save documents can be expensive.
-   Use copies where isolation is required, especially when editing
    immutable/shared blob content.
-   Document which APIs return read-only-by-contract data and which
    permit mutation.

### 4.4 Preserve timeline invariants

Verify that:

-   Entry IDs remain unique within a document.
-   `activeId` references an existing entry or is nil.
-   `quickId`, if present, references an existing entry or follows a
    documented fallback policy.
-   Pinned entries follow the existing retention rules.
-   Deleting or trimming entries updates references correctly.
-   A failed mutation does not leave partially updated in-memory state.

### 4.5 Inventory ownership

Keep global and per-save inventory targets distinct:

``` text
Global inventory
    -> Inventory operations
    -> Store.PData persistence
    -> global inventory versions

Per-save inventory
    -> Inventory operations
    -> History entry
       -> entry.data.weapons
       -> entry.data.activeWeapon
       -> entry.data.ammo
       -> entry.data.weaponState
       -> entry.inventoryVersions
```

Rules:

-   `Inventory.Read()` and `Inventory.Write()` (or their deliberately
    chosen replacements) are the inventory-specific access paths.
-   Other systems should not manipulate inventory fields directly.
-   `History` remains the authority for the containing save document.
-   `Inventory` remains the authority for inventory normalization,
    validation, versioning, and operations.
-   Document how global inventory interacts with saved inventory modules
    and spawn restoration.
-   Avoid storing the same inventory in multiple places unless each copy
    has a distinct, documented purpose.

**Exit criteria:**

-   Existing save mutations use History-owned operations.
-   No unrelated subsystem directly edits save documents.
-   Global and per-save inventory ownership is documented.
-   Timeline invariants are covered by tests.
-   Existing save data remains compatible.

------------------------------------------------------------------------

## 5. Phase 2 --- Clarify Store and Persistence Ownership

**Goal:** make `Store` a persistence subsystem, not a second
application-state manager.

### 5.1 Define Store responsibilities

`Store` should own:

-   File paths and directory management.
-   JSON serialization and decoding.
-   Disk reads and writes.
-   In-memory storage cache.
-   Dirty-write queue and flush scheduling.
-   Backup and corrupt-file recovery.
-   Blob persistence and retrieval.
-   Blob garbage collection.
-   Persistent player data storage.

`Store` should not own:

-   Save entry semantics.
-   Active-save selection.
-   Timeline retention rules.
-   Inventory rules.
-   Restore decisions.
-   Client UI state.

### 5.2 Audit cache and dirty-write semantics

Verify:

-   Cache entries represent the latest accepted in-memory document.
-   Dirty entries represent data awaiting disk persistence.
-   Flush failures remain observable and recoverable.
-   Cache invalidation cannot discard pending writes accidentally.
-   `fresh` reads have clearly defined behavior.
-   Deletion clears all relevant cache, dirty, encoded, and read-only
    bookkeeping.
-   Shutdown and map transitions flush pending writes safely.

Do not mistake a successful queue operation for a durable disk write.

### 5.3 Clarify persistence guarantees

Document the distinction between:

1.  **Mutation accepted:** the application state has been updated and
    the Store accepted it.
2.  **Write queued:** persistence is pending.
3.  **Write completed:** the disk operation succeeded.
4.  **Write failed:** the failure is reported and the system has a
    defined recovery behavior.

Review the current History refresh/push sequence. In particular,
determine whether client synchronization happens before or after
persistence has been accepted, and what happens if `Store.Save()` fails.

Do not blindly move synchronization: first define whether the UI
represents the latest in-memory authoritative state or only successfully
persisted state. Then make the behavior consistent.

### 5.4 Blob ownership and immutability

-   Keep heavy snapshots in blobs where this provides real storage
    benefits.
-   Treat stored blobs as immutable.
-   Editing a snapshot creates a new blob and updates the owning History
    entry's reference.
-   Ensure garbage collection only removes blobs that are genuinely
    unreferenced.
-   Verify that queued writes and cache state are considered correctly
    during garbage collection.
-   Avoid creating additional blob indexes or caches unless measurements
    demonstrate a need.

**Exit criteria:**

-   Store has a documented persistence contract.
-   Cache and dirty-write behavior is understood and tested.
-   Failed writes are observable.
-   Blob references and garbage collection are safe.
-   Store contains no save-history or inventory business rules.

------------------------------------------------------------------------

## 6. Phase 3 --- Make Client State a Single Projection

**Goal:** keep one client-side UI-facing replica of server state and
remove unnecessary duplicated caches.

### 6.1 Establish the client state contract

Keep `cl_state.lua` as the central UI-facing state store.

The client state is:

-   A projection of server-owned data.
-   Rebuildable after reconnect.
-   Safe to invalidate and repopulate.
-   Not a source of truth for saved data.

### 6.2 Audit client consumers

Inspect:

-   History/timeline panels.
-   Object browser and object details.
-   Inventory window.
-   Save feeds and player previews.
-   Antistuck and blocked-state displays.
-   Any other panel caching data received through state topics.

For each consumer:

-   Identify what it reads from `RARELOAD.State`.
-   Identify any duplicate local copy.
-   Determine whether local state is genuinely presentation-specific or
    duplicates server data.
-   Remove redundant copies where practical.
-   Keep temporary UI state such as selection, search text, expanded
    rows, and active tabs local to the component.

### 6.3 Standardize synchronization

-   Keep server pushes as the source of authoritative UI data.
-   Use the existing state-change hook consistently.
-   Define replacement versus merge behavior for each state topic.
-   Invalidate object details when their corresponding save or object
    changes.
-   Ensure stale asynchronous responses cannot overwrite newer state.
-   Ensure reconnecting clients can request or receive a complete
    initial projection.
-   Avoid sending large data structures when a lightweight projection is
    sufficient.

### 6.4 Do not over-engineer client state

Do not introduce a new state-management framework or a universal event
bus. Use the existing state module and hooks unless a concrete
limitation is demonstrated.

**Exit criteria:**

-   Client panels do not independently cache authoritative server data.
-   Temporary presentation state remains local.
-   Reconnect and stale-response behavior is tested.
-   State updates have documented merge/replacement semantics.

------------------------------------------------------------------------

## 7. Phase 4 --- Simplify Defensive Programming

**Goal:** remove redundant internal validation without weakening
security or runtime reliability.

### 7.1 Validation policy

> Validate when data crosses a trust boundary. Once validated, internal
> functions may rely on the established contract.

### 7.2 Validation boundary matrix

  -----------------------------------------------------------------------
  Boundary                Validation policy       Examples
  ----------------------- ----------------------- -----------------------
  Client to server        Strict                  Network payload shape,
                                                  permissions, rate
                                                  limits

  JSON/file to            Strict                  Document structure,
  application                                     schema version,
                                                  corrupted data

  Import to application   Strict                  Save format, inventory
                                                  content, entity
                                                  definitions

  External addon to       Strict                  Adapter return values,
  Rareload                                        entity references

  Public API to internal  Contract-level          Player validity, save
  subsystem                                       existence, operation
                                                  permissions

  Pipeline to trusted     Contract-based          Established execution
  module                                          context and module
                                                  contract

  Internal helper to      Minimal                 Do not repeat
  internal helper                                 established invariants
  -----------------------------------------------------------------------

### 7.3 Classify every defensive check

For each check, assign one category:

  -----------------------------------------------------------------------
  Category                            Action
  ----------------------------------- -----------------------------------
  Security boundary                   Keep

  Untrusted input validation          Keep

  Engine/runtime uncertainty          Keep

  Third-party compatibility           Keep

  Asynchronous lifetime protection    Keep

  Duplicate internal invariant        Remove or centralize

  Redundant type/nil guard on trusted Remove when contract is clear
  data                                

  Unclear purpose                     Investigate before changing
  -----------------------------------------------------------------------

### 7.4 Preserve meaningful runtime checks

Do not remove checks that protect against:

-   Invalid or removed entities.
-   Players disconnecting or changing state.
-   Delayed callbacks running after a restore was superseded.
-   Entity creation failures.
-   Missing weapon classes, vehicle bases, or third-party addons.
-   File read/write and JSON failures.
-   Permission changes and unauthorized requests.
-   Older saves with optional or missing module data.
-   Engine hooks returning unexpected values.
-   External adapter failures.

These are real runtime uncertainties, not redundant validation.

### 7.5 Example: trusted internal data

Before:

``` lua
local function applyInventory(ply, inventory)
    if not istable(inventory) then return false end
    if not istable(inventory.weapons) then return false end

    for _, class in ipairs(inventory.weapons) do
        if not isstring(class) then return false end
        if not weapons.GetStored(class) then continue end

        ply:Give(class)
    end
end
```

If every caller is required to pass an inventory returned by
`Inventory.Clean()`, repeated shape validation is unnecessary.

After:

``` lua
-- Expects an inventory returned by Inventory.Clean().
local function applyInventory(ply, inventory)
    for _, class in ipairs(inventory.weapons) do
        if weapons.GetStored(class) then
            ply:Give(class)
        end
    end
end
```

The weapon existence check remains because the runtime environment may
have changed since the inventory was created.

### 7.6 Avoid global mechanical cleanup

Do not globally remove or rewrite:

-   `IsValid`
-   `istable`
-   `isstring`
-   `isnumber`
-   `pcall` / `xpcall`
-   nil checks
-   fallback values

Each occurrence must be evaluated in context. A check is redundant only
when the relevant invariant is already guaranteed by a clear and
enforced contract.

**Exit criteria:**

-   Boundary validation remains strict.
-   Internal redundant checks are reduced.
-   Runtime and compatibility protections remain.
-   Every removed check has a clear reason.
-   Tests cover malformed external data and valid internal data.

------------------------------------------------------------------------

## 8. Phase 5 --- Regression Testing and Final Audit

**Goal:** demonstrate that the simpler architecture preserves existing
behavior.

### 8.1 Required regression scenarios

  Scenario                    Expected result
  --------------------------- --------------------------------------------------
  Normal save                 Correct entry created and activated
  Partial save                Untouched modules retain their data
  Undo                        Previous state restored
  Quick-save / quick-load     Correct save selected
  Inventory edit              Correct target modified
  Inventory rollback          Previous version restored
  Object edit                 Correct blob replaced
  Object deletion             Constraints remain consistent
  History deletion            Active and quick references remain valid
  History retention           Pinned and active entries follow retention rules
  Corrupt JSON                Backup recovery works
  Failed disk write           Failure is observable and recoverable
  Server restart              Saves and blobs load correctly
  Client reconnect            UI state is rebuilt from server
  Stale object detail         Old responses cannot overwrite current state
  Missing addon               Restore skips unsupported content safely
  Interrupted restore         Stale callbacks cannot modify a newer restore
  Malformed network payload   Request is rejected safely
  Malformed import            Invalid data is rejected before mutation

### 8.2 Run tests after every phase

After each phase:

-   Run lint.
-   Run static/type checks where applicable.
-   Run unit tests.
-   Run integration/e2e tests.
-   Compare against the Phase 0 baseline.
-   Investigate regressions before continuing.

Do not defer all testing until the end.

### 8.3 Final ownership audit

Repeat the Phase 0 searches.

Verify:

-   Every persistent state structure still has one authoritative owner.
-   All persistent mutations follow the intended APIs.
-   No new duplicate cache or shadow state was introduced.
-   Store remains focused on persistence.
-   Client State remains a disposable projection.
-   No important safety check was removed without justification.

**Exit criteria:**

-   Existing save formats remain compatible.
-   All required regression scenarios pass.
-   No unexplained test regressions remain.
-   Ownership and validation documentation matches the implementation.

------------------------------------------------------------------------

## 9. Phase 6 --- Debloat, Native Functions and Measured Optimization

**Goal:** remove genuinely dead code, replace hand-rolled logic with the
engine's own functions, and apply the few optimizations that a
measurement actually justifies --- without turning this into a
stylistic rewrite.

This phase runs *after* the ownership and validation work, because
centralizing mutations (Phases 1--3) and pruning redundant checks
(Phase 4) is what exposes the code that is truly unused. Deleting
"unused" code before the audit risks removing a path the audit would
have re-routed rather than deleted.

### 9.0 Reality check (measured 2026-11, 5.4 branch)

The 5.x codebase is already close to the Garry's Mod wiki's optimization
guidance, so this phase is a scalpel, not a chainsaw. What is *already*
correct and must **not** be "fixed":

  -----------------------------------------------------------------------
  Already good                        Evidence
  ----------------------------------- -----------------------------------
  `player.Iterator()` everywhere;     `grep player.GetAll` → none;
  no cached `player.GetAll` loops      iterator used in `sv_autosave`,
                                      `sv_spawn`, `sv_history`,
                                      `world.lua`, `sh_net`, …

  Render objects created once at file Colors/materials at
  scope, not per frame                 `cl_highlight.lua:13-14`,
                                      `cl_toolscreen.lua:8`

  Exact net writers, not              `sh_net.lua:138-144`
  `net.WriteTable`                     (`WriteUInt`/`WriteData`)

  State is pushed on change, paced     `sh_net.lua` Tick sender sends
  and ACKed --- not resent every tick  queued chunks only; autosave is
                                      dirty-driven

  Dense appends already use            `Net.Split` (`chunks[#chunks+1]`),
  `t[#t+1]`                            snapshot code

  `glualint` with `lint_unusedVars`    `.glualint.json`, CI `lint` job is
  runs green in CI                     green → no unused *locals* remain
  -----------------------------------------------------------------------

The wiki's own first rule applies to every item below: *"Correctness and
readability should usually come first,"* and *measure with `SysTime`
before and after* --- do not optimize on appearance
([optimizationTips](https://wiki.facepunch.com/gmod/optimizationTips)).

### 9.1 Dead-code removal (the real "unused things")

`glualint`'s `lint_unusedVars` already guarantees no unused *local*
variables survive. It does **not** flag:

-   Unused **function parameters** (`lint_unusedParameters` is `false`).
-   Unused **loop variables** (`lint_unusedLoopVars` is `false`).
-   Unused **table fields / globals** --- an orphaned
    `function RARELOAD.Util.Foo()` or `Module`-registry helper that
    nothing calls.

Actions:

1.  Turn on `lint_unusedParameters` and `lint_unusedLoopVars` in
    `.glualint.json`, fix or `_`-prefix what they surface, and keep them
    on so regressions can't creep back. Expect noise in callback
    signatures the engine dictates (hook params); prefix those with `_`
    rather than deleting.
2.  Add a `luacheck` pass (or a small reference-count script over the
    `RARELOAD.*` and `Util.*` namespaces) for **unused module-level
    functions**, which `glualint` cannot see. Every hit is either dead
    (remove) or an intended public API (document it as such). Resolve
    each explicitly; a silent orphan is the bug this phase targets.
3.  Remove code the Phase 1--4 audits proved unreachable: mutation
    helpers superseded by History-owned paths, defensive branches whose
    callers can no longer pass the guarded value, and any
    compatibility/alias left from 5.4.

Record every removal with its reason, mirroring Phase 4's rule that
*"every removed check has a clear reason."*

### 9.2 Native-function and better-method audit

Prefer the engine's own tools over equivalents implemented in Lua, but
only where behaviour is identical and the wiki does not warn against it.
Audit, per hit:

-   **Iteration:** confirm no new `player.GetAll`/`ents.GetAll`-into-a-
    cache loops were introduced. Use `player.Iterator()` --- it reads a
    Lua-side cache and avoids a Lua↔C++ crossing and a fresh table
    ([player.Iterator](https://wiki.facepunch.com/gmod/player.Iterator)).
    Respect its caveats: the returned table is read-only, and it is not
    guaranteed fresh inside `OnEntityCreated`/`EntityRemoved`.
-   **Appends:** `t[#t+1]` for dense sequential appends can beat
    `table.insert`; keep `table.insert` for positional inserts or where
    it reads more clearly (only ~9 call sites exist today ---
    `cl_panels`, `cl_menu`, `sh_net`, `sv_pipeline`, …).
-   **Nested scans:** any O(n·m) loop over two collections should become
    a lookup table / single pass
    ([optimizationTips](https://wiki.facepunch.com/gmod/optimizationTips)).
    Check `sv_antistuck.lua` entity gathering and the client world feed.
-   **Net sizing:** size `net.WriteUInt(n, bits)` to the value's real
    range rather than a reflexive 32; match reads to writes; use
    `net.WriteBool`/`WriteFloat`/`WriteEntity` for their types
    ([net.WriteUInt](https://wiki.facepunch.com/gmod/net.WriteUInt)).
    Review the fixed-width headers in `sh_net.lua:138-144`.
-   **String building:** collect into a table and `table.concat` instead
    of `..` in a loop where a hot path builds strings (log lines,
    report cards).
-   **Engine-vs-Lua boundary:** do **not** assume moving work to a C
    function is faster --- every crossing has a cost; measure the hot
    path first ([garry.net](https://garry.net/posts/optimising-gmod)).

### 9.3 Reconcile the "no timers" rule with reality

The architecture note *"the pipeline uses a per-tick queue, never
timers"* is about **deferred pipeline/restore work**, not a blanket ban.
These timers are legitimate debounce/flush/pacing and must stay:

  -----------------------------------------------------------------------
  Timer                               Purpose
  ----------------------------------- -----------------------------------
  `Rareload.Store.Flush` (0.5s)       Batch disk writes
  `Rareload.Autosave` (1s)            Dirty-driven autosave tick
  `Rareload.History.Push` (0.1s)      Debounce client pushes
  `Rareload.Net.Upload` (0.1s)        Pace upload parts
  `Rareload.World.Update` (0.2s)      Client world-feed refresh
  -----------------------------------------------------------------------

Document this distinction in `docs/architecture/STATE_OWNERSHIP.md` so
the cleanup does not mistakenly convert a correct debounce timer into
tick-queue work, or vice versa.

### 9.4 Where the bloat actually concentrates

By size, the client UI files dominate (`cl_panels.lua` ~1060,
`cl_ui.lua` ~880, `cl_menu.lua` ~770, `cl_inspector.lua` ~730,
`cl_history.lua` ~660). This is the same surface Phase 3 audits for
duplicated state, so **run 9.1/9.2 on the client UI as part of Phase
3**, not as a separate sweep: dead UI helpers and derived-state copies
are the highest-yield, lowest-risk debloat targets, and the panels are
not performance-critical the way the save/restore path is.

### 9.5 Measurement harness

Use instrumentation that already exists rather than guessing:

-   The pipeline already times each module (`run()` returns ms) and
    writes it to the report card --- capture a before/after for a large
    save and a large restore.
-   `sh_net`'s in-flight byte accounting gives transfer sizes before and
    after any net-sizing change.
-   Wrap any candidate hot path in `SysTime()` and run it several times,
    as the wiki instructs; keep the numbers in the commit message.

**Exit criteria:**

-   `lint_unusedParameters` and `lint_unusedLoopVars` are enabled and
    green.
-   Every unused module-level function is removed or documented as a
    public API.
-   No hand-rolled logic remains where an identical, un-warned native
    function exists.
-   Every optimization landed in this phase cites a before/after
    `SysTime`/byte measurement in its commit.
-   No readability regression and no behaviour change (the Phase 5
    regression suite still passes).

------------------------------------------------------------------------

## 10. Explicitly Out of Scope

Do not use 5.5 as an excuse to:

-   Rewrite History or Store from scratch.
-   Introduce Redux-like client state management.
-   Add a generic repository abstraction over every subsystem.
-   Create a universal validation framework.
-   Remove all defensive checks.
-   Change the save format without a demonstrated need.
-   Rename every API solely for stylistic consistency.
-   Combine this work with unrelated feature development.
-   Perform *broad* or *speculative* performance optimization without
    measurements. (Targeted, measured cleanup and native-function
    substitution are in scope --- see Phase 6, which requires a
    before/after number for every change.)
-   Mechanically strip `table.insert`, parameters, or helpers purely for
    style. A thing is removed only when proven unused or measurably
    better, not because it looks redundant.
-   Add compatibility layers for hypothetical integrations without a
    concrete use case.

The goal is to simplify the existing architecture, not replace it with a
more elaborate one.

------------------------------------------------------------------------

## 11. Definition of Done

### State ownership

-   [ ] Every persistent state structure has one documented
    authoritative owner.
-   [ ] Every persistent mutation follows an explicit API.
-   [ ] History owns save-document semantics and timeline mutations.
-   [ ] Store owns persistence mechanics, cache, dirty writes, and
    blobs.
-   [ ] Pipeline owns execution lifecycle, not persistent save data.
-   [ ] Inventory ownership is clear for global and per-save data.
-   [ ] Client State is a disposable server projection.
-   [ ] UI panels do not maintain redundant copies of authoritative
    data.

### Validation

-   [ ] Network and import boundaries validate untrusted input.
-   [ ] File loading validates persisted data and handles corruption.
-   [ ] External addon boundaries validate external results.
-   [ ] Internal functions rely on documented contracts.
-   [ ] Redundant internal checks have been removed selectively.
-   [ ] Engine, asynchronous, security, and compatibility checks remain.
-   [ ] No broad mechanical removal of defensive checks was performed.

### Reliability and compatibility

-   [ ] Failed persistence operations are observable.
-   [ ] Blob references and garbage collection remain safe.
-   [ ] Existing save files remain compatible.
-   [ ] Reconnect and stale-response behavior is correct.
-   [ ] The existing test suite passes.
-   [ ] Required regression scenarios pass.
-   [ ] Architecture documentation matches the final code.

### Debloat and optimization (Phase 6)

-   [ ] `lint_unusedParameters` and `lint_unusedLoopVars` are enabled
    and CI is green.
-   [ ] Every unused module-level function is removed or documented as a
    public API.
-   [ ] No hand-rolled logic remains where an identical, un-warned
    native function exists.
-   [ ] Every optimization that landed cites a before/after measurement.
-   [ ] The legitimate debounce/flush timers are documented and intact.

------------------------------------------------------------------------

## 12. Priority and Recommended Execution Order

  -----------------------------------------------------------------------
  Priority                Work                    Reason
  ----------------------- ----------------------- -----------------------
  P0                      State ownership audit   Establishes the facts
                                                  before refactoring

  P0                      Centralize History      Removes competing
                          mutations               mutation paths

  P1                      Clarify Store           Prevents confusion
                          persistence contract    between in-memory state
                                                  and durable storage

  P1                      Establish client        Removes duplicated
                          projection rules        client-side
                                                  authoritative state

  P1                      Validation boundary     Makes safe
                          audit                   simplification possible

  P2                      Remove redundant checks Reduces noise after
                                                  contracts are
                                                  established

  P2                      Debloat and native-     Only safe once
                          function audit          contracts and ownership
                          (Phase 6)               are settled; needs
                                                  measurement

  P2                      Documentation and final Prevents the
                          audit                   architecture from
                                                  regressing
  -----------------------------------------------------------------------

Recommended order:

1.  Complete Phase 0 and review the ownership map.
2.  Refactor History mutation paths.
3.  Verify Store behavior and persistence failure semantics.
4.  Simplify client projections (run the Phase 6 UI debloat here ---
    §9.4).
5.  Audit and document validation boundaries.
6.  Remove redundant internal checks.
7.  Debloat and native-function audit (Phase 6): dead code, native
    substitutions, measured optimizations.
8.  Run the complete regression suite and final ownership audit.

Do not combine phases merely to reduce the number of commits. Keep
changes reviewable and independently testable.

------------------------------------------------------------------------

## 13. Guiding Architectural Rule

> **A system may own data, persist data, transport data, execute
> operations on data, or project data for presentation. It should not
> silently assume several of these responsibilities.**

Applied to Rareload:

-   **History** owns the meaning and lifecycle of a save.
-   **Store** persists it.
-   **Pipeline** captures and restores it.
-   **State modules** handle domain-specific data.
-   **Inventory** owns inventory-specific rules and operations.
-   **Net** transports requests and projections.
-   **Client State** presents a disposable replica.

The desired outcome for 5.5 is not necessarily fewer lines of code. It
is fewer mutation paths, fewer duplicated invariants, clearer ownership,
and a codebase that is easier to reason about without tracing the entire
system.

------------------------------------------------------------------------

## 14. References

Sources behind the Phase 6 optimization and native-function guidance
(verified 2026-11):

-   **Garry's Mod optimization tips** (primary; measure first, cache
    render objects, lookup tables over nested scans, exact net writers,
    `t[#t+1]` for dense appends) ---
    <https://wiki.facepunch.com/gmod/optimizationTips>
-   **`player.Iterator`** (Lua-side cache, avoids a Lua↔C++ crossing;
    read-only return; not fresh inside entity-create/remove hooks) ---
    <https://wiki.facepunch.com/gmod/player.Iterator>
-   **`net.WriteUInt`** (bit sizing to the value's real range; match
    reads to writes) --- <https://wiki.facepunch.com/gmod/net.WriteUInt>
-   **Optimising Garry's Mod** by Garry Newman (the Lua↔engine boundary
    has a real cost; do not assume C is faster; measure the hot path)
    --- <https://garry.net/posts/optimising-gmod>
-   **`glualint` / GLuaFixer** (the linter in CI; `lint_unusedVars`,
    `lint_unusedParameters`, `lint_unusedLoopVars`) ---
    <https://github.com/FPtje/GLuaFixer>

Community benchmarks consulted for `t[#t+1]` vs `table.insert` and
numeric-`for` vs `ipairs` ordering (lower authority; not LuaJIT-specific,
so treated as directional only, confirmed against the Facepunch wiki):
[Defold forum](https://forum.defold.com/t/some-tests-lua-performance/70782),
[OTLand Lua guide](https://docs.otland.net/lua-guide/auxiliary),
[OpenResty best practices](https://github.com/moonbingbing/openresty-best-practices/blob/master/ngx_lua/lua_opt.md).
