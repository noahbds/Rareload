# Vehicle Module — Complete Rewrite Design

Status: **proposed (v3 — greenfield rewrite)** · Created: 2026-09-18
Grounded in a full read of the Rareload snapshot pipeline and the internals of the six reference
bases in `/Users/noah/vehicule_addon` (simfphys, LVS, LFS, Glide, WAC, Source).

This document specifies a **from-scratch rewrite** of Rareload's vehicle save/restore, not an
incremental patch. It replaces:

- `lua/rareload/core/save_helpers/rareload_save_vehicles.lua`
- `lua/rareload/core/respawn_handlers/sv_rareload_handler_vehicles.lua`
- `lua/rareload/core/respawn_handlers/sv_rareload_wac_compat.lua` (folded into an adapter)

with a new `lua/rareload/core/vehicles/` module built around a **framework adapter registry** and a
**single readiness-gated restore scheduler**.

---

## 1. Why a rewrite (not a patch)

The existing module works for the happy path but has structural problems that can't be cleanly
patched out:

- Runtime state (engine/fuel/health/lights/gear/turret) is handled by one flat, hardcoded if-chain
  (`CaptureOperationalState`/`RestoreOperationalState`) that misses most state.
- Timing is guesswork: a fixed `0.3s` state-apply delay, an 8-tick physics settle loop, a 35-attempt
  reseat timer, WAC `attempts < 15` gates, a `0.2s` constraint delay — one per-entity timer each.
- Seating captures only the local player's single seat.
- WAC support is a concommand-wrapper hack tangled into the generic path.
- The two files interleave capture, ownership, physics, seating, and WAC concerns.

A rewrite lets us encode what the reference audit actually proved (below) into a clean architecture,
and fix the concrete correctness bugs (health/damage never re-applied; fuel simfphys-only) at the
same time.

---

## 2. What the reference audit proved (design-forcing facts)

### 2.1 Every base wipes runtime state on paste
The generic `duplicator` paste is a good *transport* (model, skin, physics, tuning, per-base dupe
data, constraints), but each base's own `PostEntityPaste`/`OnEntityCopyTableFinish` **deliberately
resets runtime state to defaults**:

- **simfphys** (`spawn.lua` `PostEntityPaste`): `SetActive(false)`, `SetLightsEnabled(false)`,
  `SetLampsEnabled(false)`, `SetFogLightsEnabled(false)`, `SetThrottle(0)`, `SetFlyWheelRPM(0)`,
  `SetDriver/DriverSeat(NULL)`.
- **LVS** (`sv_duping.lua`): `SetActive(false)`, `SetEngineActive(false)`, `SetAI(false)`, strips
  every `_`-prefixed timing var, re-inits after a 1s timer, sets `SetlvsReady(true)`.
- **Glide** (`init.lua`/`util.lua`): filters `DT` NetworkVars down to `DuplicatorNetworkVariables`,
  which are **tuning/config only** (springs, torque curves, wheel radius, turbo). Runtime NetworkVars
  (engine state, health, gear, lights, lock) are **not** in the dupe data.

**Consequence:** a faithful restore *must* re-apply runtime state deliberately, *after* the base
finishes its own init. This is the reason the adapter + readiness-gated scheduler exist.

### 2.2 Do NOT re-apply what the base already restores
Glide's `DuplicatorNetworkVariables` (wheel radius, spring strength, torque curves, turbo, steer
cone…) are restored by Glide itself. Re-capturing/re-applying those would fight the base. Adapters
capture **only** the runtime state the base wipes or loses.

### 2.3 Health is captured but never re-applied (real bug)
`SnapshotUtils` copies `MaxHealth`/`CurHealth` into the summary, but nothing on the restore path ever
calls a health setter. **Every base restores at full health today.**

### 2.4 Health/damage is component-based on some bases (the subtle one)
- **LVS** keeps HP on **engine sub-entities** (`lvs_wheeldrive_engine`, `lvs_starfighter_engine`,
  `lvs_helicopter_rotor`, `lvs_wheeldrive_ammorack` each have `NetworkVar HP/MaxHP` + `SetHP`). The
  root delegates `GetHP()`/`SetHP()`, but full fidelity means restoring per-component HP and the
  `Damaged` flag. Rareload's vehicle capture keeps only **root** vehicles (sub-entities are dropped),
  so component HP is neither in the dupe payload nor in today's op-state.
- **Glide** keeps `ChassisHealth`, `EngineHealth`, `TireHealth` as NetworkVars on the root (auto
  setters `SetChassisHealth`/`SetEngineHealth` exist), plus `IsOnFire`/`IsEngineOnFire`.
- **simfphys** uses root `GetCurHealth`/`SetCurHealth` + `GetMaxHealth`/`SetMaxHealth`.

Adapters must therefore be allowed to capture/apply **sub-entity/component** state, not just root
accessors.

### 2.5 Constraints are already (partly) solved — extend, don't rebuild
- Within-contraption constraints ride in `payload.Constraints` (kept when both ends survive filtering).
- Prop⇄vehicle constraints have a working `CaptureCrossCategoryConstraints` /
  `RestoreCrossCategoryConstraints` path via the `crossConstraints` state provider.
- Gaps: vehicle⇄vehicle links between two separately-captured vehicles; and cross-restore uses a
  fixed `0.2s` delay instead of readiness.

### 2.6 Readiness probes exist — use them instead of delays
- LVS: `ent:GetlvsReady()` (true after its 1s re-init).
- WAC: `isfunction(ent.receiveInput)` present.
- Glide / simfphys: physics object valid + first tick after paste.

---

## 3. Design decision: keep duplicator transport, rewrite the layer around it

**Considered and rejected: native spawning** (e.g. `simfphys.SpawnVehicleSimple`, list
`simfphys_vehicles`, Glide `SpawnFunction`). Native spawn would lose duplicator-carried tuning,
Wiremod dupe info, EntityModifiers, and constraints, and would require a bespoke spawn path per base.

**Chosen: duplicator paste is the transport; the rewrite owns everything else.** The new module:
1. captures the duplicator snapshot (unchanged transport) **plus** an adapter-produced `runtimeState`
   keyed by stable RareloadEntityID (root + components), **plus** a full multi-occupant `seats[]`;
2. on restore, pastes, then a single scheduler drives each vehicle through a readiness-gated state
   machine that re-applies runtime state, stabilizes physics (only if the base doesn't), re-seats all
   occupants, and links constraints.

---

## 4. New module layout

```
lua/rareload/core/vehicles/
  rareload_vehicles.lua            -- public API (Save/Restore) + PreCleanupMap hook, thin orchestrator
  rareload_vehicle_adapters.lua    -- registry + Resolve() + generic fallback + contract
  rareload_vehicle_schema.lua      -- bucket structure helpers (Normalize/Finalize)
  rareload_vehicle_capture.lua     -- discovery, ownership, snapshot + runtimeState + seats
  rareload_vehicle_restore.lua     -- paste orchestration → scheduler handoff
  rareload_vehicle_scheduler.lua   -- ONE ticking pass; PENDING→…→DONE state machine
  rareload_vehicle_seats.lua       -- seat enumeration/matching/entering (base-agnostic core)
  adapters/
    simfphys.lua  lvs.lua  glide.lua  lfs.lua  wac.lua  source.lua
```
The old three files are deleted; the `vehicles` and `crossConstraints` state providers call the new
`RARELOAD.Vehicles.*` public API.

---

## 5. Public API (what Rareload core calls)

```lua
RARELOAD.Vehicles.Save(ply)               -> bucket        -- capture; returns { __duplicator, runtimeState, seats }
RARELOAD.Vehicles.Restore(savedInfo, ply) -> bool, stats   -- paste + enqueue into scheduler (reseats all occupants)
RARELOAD.RestoreVehicles(savedInfo, ply)                   -- global binding used by state providers / history
-- hook.Run("RareloadVehiclesRestored", stats, ply)         -- preserved for downstream consumers
```

There is **no migration and no legacy/back-compat layer** — the addon was never released, so the v2
bucket is the only format. Occupant re-seating goes entirely through `seats[]` (every seat carries
its occupant's SteamID); the old single-seat `vehicleState` / `RestorePlayerVehicle` mechanism is gone.

`Save` returns `{ __duplicator = <snapshot>, schemaVersion = 2, runtimeState = {...}, seats = {...},
crossConstraints = {...}? }`. Restore is **non-blocking**: it pastes synchronously, then hands each
created vehicle to the scheduler and returns immediately.

---

## 6. Data model (v2 schema)

```lua
bucket = {
  __duplicator  = <existing snapshot: payload.Entities/Constraints, rareloadIDOverrides, _indexMap>,

  -- Runtime state keyed by STABLE RareloadEntityID (never EntIndex).
  runtimeState = {
    ["<vehID>"] = {
      adapter   = "lvs",                 -- which adapter produced/consumes this
      root      = { engineActive=true, fuel=0.62, hp=740, maxHp=1000, damaged=false,
                    lights=true, gear=3, turretAngle={p=..,y=..,r=..}, weaponIndex=2,
                    locked=false, color={r,g,b,a}, skin=1, bodygroups={[0]=2,...} },
      -- Component/sub-entity state (LVS engines/rotors/ammoracks, etc.), matched on restore
      components = { { role="engine", localPos={x,y,z}, hp=300, maxHp=300 },
                     { role="rotor",  localPos={x,y,z}, hp=8 } },
    },
  },

  -- ALL occupants at save time, not just the requester.
  seats = {
    ["<vehID>"] = {
      { podIndex=0, localPos={x,y,z}, class="prop_vehicle_prisoner_pod",
        isDriver=true, occupant={ kind="player", steamID="STEAM_0:...", steamID64="..." } },
      { podIndex=1, localPos={x,y,z}, isDriver=false, occupant={ kind="npc", model="..." } },
    },
  },
}
```
Seat descriptors also carry `vehClass` (the owning vehicle's class) so the client phantom UI can show
the "reseat in vehicle" hint and framework label without a separate sidecar field.

---

## 7. Adapter contract (fully specified)

```lua
--- Every field optional except id + matches. Missing capabilities degrade gracefully.
RARELOAD.VehicleAdapters.Register({
  id       = "lvs",
  priority = 10,                                   -- higher wins when multiple match

  matches  = function(ent) end,                    -- prefer DataUtils.ClassIsRootVehicle hierarchy

  ------------------------------------------------ CAPTURE (save)
  captureRoot       = function(ent) return { ... } end,   -- runtime state the base wipes/loses ONLY
  captureComponents = function(ent) return { ... } end,   -- sub-entity state (LVS engines/rotors)
  captureSeats      = function(ent) return { ... } end,   -- occupied seats + occupant identity

  ------------------------------------------------ APPLY (restore); all idempotent + pcall-guarded
  applyRoot         = function(ent, root) end,
  applyComponents   = function(ent, components) end,      -- re-match components by role/localPos
  resolveSeat       = function(ent, seatInfo) return seat, isExact end,
  onSeatEnter       = function(ent, seat, ply) end,       -- e.g. WAC.BindPassenger

  ------------------------------------------------ SCHEDULING
  isReady           = function(ent) return bool end,      -- LVS: ent:GetlvsReady(); WAC: has receiveInput
  selfStabilizes    = true,                               -- skip Rareload phys settle when base does it
  readyTimeout      = 4.0,                                -- best-effort apply after this, then DONE
})

RARELOAD.VehicleAdapters.Resolve(ent) -- best match by priority, else generic Source adapter
```

### Worked example: LVS (the hard one)
- `captureRoot`: `engineActive` (`GetEngineActive`), `active` (`GetActive`), `hp`/`maxHp`
  (`GetHP`/`GetMaxHP`), `damaged` (`GetDamaged`), `fuel` (`GetFuelTank`), `fuelType` (`GetFuelType`),
  `activeWeapon` (`GetActiveWeapon`), `ambientLight` (`GetAmbientLight`), skin/color.
- `captureComponents`: walk children; for each engine/rotor/ammorack entity record
  `{ role, localPos = root:WorldToLocal(c:GetPos()), hp = c:GetHP(), maxHp = c:GetMaxHP() }`.
- `applyComponents`: after `isReady`, re-enumerate children, match by role + nearest `localPos`,
  call `c:SetHP(saved.hp)`.
- `isReady`: `ent.GetlvsReady and ent:GetlvsReady()`.
- `selfStabilizes = true` (LVS re-seats its own physics on init).

---

## 8. Capture pipeline (`rareload_vehicle_capture.lua`)

1. Discover candidate roots: iterate owned/tracked entities (reuse `DataUtils.IsRootVehicle`,
   `GetRootVehicle`, `IsVehiclePart`); dedupe by root. Optional owned-vehicle cache to avoid a full
   `ents.GetAll()` scan every save.
2. Ownership: keep existing `Ownership.ResolveOwner` + "claim if driving" (formalized as
   `retainDrivenVehicles` setting).
3. For each root: `EntityIdentity.EnsureID` → `RareloadEntityID`; then
   `adapter.captureRoot` + `captureComponents` + `captureSeats`.
4. Snapshot transport unchanged (`SnapshotUtils.BuildOwnedBucket`), but stash `runtimeState`/`seats`
   keyed by RareloadEntityID (not EntIndex) as snapshot extras.
5. Emit v2 bucket. Never persist `_`-prefixed transient/time-based values (LVS strips these for a
   reason — CurTime differs across sessions); capture semantic values (fuel amount), not raw timers.

---

## 9. Restore pipeline + scheduler

### 9.1 Restore (`rareload_vehicle_restore.lua`)
1. `Normalize` the bucket (pull out snapshot / runtimeState / seats).
2. Paste via existing `SnapshotRestore.RestoreCategory` (keeps ID-exists idempotency filter,
   `maxRestoredVehicles` cap, `validateClass` uninstalled-addon skip).
3. For each created root: resolve adapter, look up `runtimeState`/`seats` by RareloadEntityID, and
   **enqueue** into the scheduler. Return `true, stats` immediately (non-blocking).

### 9.2 Scheduler (`rareload_vehicle_scheduler.lua`) — one timer, a state machine per vehicle
```
PENDING ──(adapter.isReady OR t>readyTimeout)──▶ APPLY_STATE
APPLY_STATE: applyRoot → applyComponents                     ▶ STABILIZE
STABILIZE:   if not adapter.selfStabilizes → phys settle     ▶ RESEAT
             (convars: sv_rareload_veh_settle_ticks/_interval)
RESEAT:      for each recorded occupant present on server:
               seat,exact = adapter.resolveSeat or seats core
               if exact/urgent → EnterVehicle + adapter.onSeatEnter
                                                             ▶ LINK
LINK:        restore vehicle⇄prop and vehicle⇄vehicle cross-constraints by ID  ▶ DONE
```
One shared ticker replaces every per-entity timer and every magic delay. `readyTimeout` guarantees a
broken base can never hang a vehicle. Ordering is now correct by construction (state before reseat
before constraints).

---

## 10. Seating model (`rareload_vehicle_seats.lua` + adapters)
- Base-agnostic core provides the current heuristic ladder: LVS pod index → networked `pPodIndex` →
  local-position nearest match → class match → first free seat. (Ported from today's `FindSavedSeat`.)
- Capture records **every** occupied seat with occupant identity (player SteamID or `npc:<model>`)
  and `isDriver`.
- Reseat restores all recorded humans currently on the server; NPC re-seating behind a setting.
- `wac` adapter supplies `onSeatEnter = WAC.BindPassenger` and `isReady = has receiveInput`; the
  concommand wrapper + failsafe hooks stay global in the wac adapter file, but the per-vehicle branch
  logic leaves the generic path.

---

## 11. Constraints
- Within-payload constraints: unchanged (ride in `payload.Constraints`).
- Cross-category: reuse `CaptureCrossCategoryConstraints`/`RestoreCrossCategoryConstraints`, extended
  to cover vehicle⇄vehicle, and moved into the scheduler LINK stage (readiness-gated, not `0.2s`).
- Optional parenting restore (`SetParent`) for attached turrets/props where both ends are tracked.

---

## 12. Per-base adapter spec (concrete)

| Adapter | Root runtime state (real accessors) | Components | Ready / stabilize |
|---|---|---|---|
| **simfphys** | `GetCurHealth`/`GetMaxHealth`, `GetFuel`/`GetMaxFuel`/`GetFuelType`, `GetActive`, `GetLightsEnabled`(+lamps/fog), `GetHandbrake`, `SetColors`, skin, bodygroups | seats via `GetPassengerSeats`/`GetDriverSeat` | ready = phys valid; `selfStabilizes=true` |
| **LVS** | `GetEngineActive`,`GetActive`,`GetHP`/`GetMaxHP`,`GetDamaged`,`GetFuelTank`/`GetFuelType`,`GetActiveWeapon`,`GetAmbientLight`, skin | engines/rotors/ammoracks HP via child walk | ready = `GetlvsReady()`; `selfStabilizes=true` |
| **Glide** | NW: `IsEngineOn`/`IsActive`,`EngineState`,`ChassisHealth`,`EngineHealth`,`TireHealth`,`IsOnFire`/`IsEngineOnFire`,`Gear`,`HeadlightState`,`SirenState`,`TurnSignalState`,`LockState`/`IsLocked`,`TurretAngle`,`WeaponIndex`, skin. **Skip DuplicatorNetworkVariables (tuning).** | turret/gun via `GetTurret`/`GetGunUser` | ready = phys valid + 1 tick; `selfStabilizes=true` |
| **LFS** | NW: `Active`,`EngineActive`,`IsLocked`,`RPM`,`LGear`/`RGear`,`Shield`,`GetHP`/`GetMaxHP` | gunner seat | ready = phys valid; `selfStabilizes=true` |
| **WAC** | engine/rotor/light via WAC accessors | passenger table | ready = `isfunction(ent.receiveInput)`; `onSeatEnter=BindPassenger` |
| **Source** | `Health`, `GetColor`, skin, bodygroups, relevant KeyValues | n/a | ready = phys valid; Rareload stabilizes |

---

## 13. Rollout status
1. ✅ New module landed under `RARELOAD.Vehicles.*`; the `vehicles` state provider (save + restore)
   and history restore call it via `RARELOAD.RestoreVehicles`. `RareloadVehiclesRestored` hook + `stats`
   preserved. `crossConstraints` provider untouched (still works).
2. ✅ Old `rareload_save_vehicles.lua` and `sv_rareload_handler_vehicles.lua` deleted. No migration,
   no legacy `vehicleState`/`RestorePlayerVehicle` — the phantom UI + history summary now read `seats`.
3. ✅ All six adapters shipped (Source generic fallback + simfphys, LVS w/ component HP, Glide, LFS, WAC).
4. ⏳ In-game validation per the §6 matrix (not runnable outside GMod).
5. ⏳ Optional `rareload_vehicle_dump <id|aim>` diagnostic concommand.

---

## 14. Validation matrix (per base regression checklist)
For each of simfphys / LVS / Glide / LFS / WAC / Source:
1. Spawn; set distinct state — **damage** (partial HP; for LVS damage a specific component),
   **burn fuel**, **lights on**, **engine on**, **change skin/paint**, **change gear/turret** where
   supported, **sit in a non-driver seat**.
2. Save (or `PreCleanupMap`).
3. Map change / cleanup / reconnect; restore.
4. Verify position/angle + frozen state, **HP (incl. component HP for LVS)**, **fuel**, engine/lights,
   paint/skin, gear/turret, and correct seat.
5. Two humans in one vehicle → both re-seated.
6. Vehicle welded to trailer/prop → constraint restored.
7. Remove one base addon → its vehicles skip cleanly; others restore.
Record pass/fail per base so future changes are diffable.

---

## 15. Risks & mitigations
- **Accessor drift upstream** → all calls pcall-guarded; adapter degrades to "restore what we can";
  `rareload_vehicle_dump` makes drift visible.
- **Readiness never true** → `readyTimeout` best-effort apply then DONE; nothing hangs.
- **Fighting base re-init** → `selfStabilizes` + readiness gating exist specifically to prevent this.
- **LVS component matching ambiguity** → match by role + nearest localPos; fall back to root HP only.
- **Save cost with many vehicles** → owned-vehicle cache; duplicator.Copy is the floor (transport).

---

## 16. Reference index (for implementers)

Rareload (transport + services the rewrite reuses):
- `shared/rareload_snapshot_utils.lua` — bucket/summary/constraint iteration
- `core/save_helpers/rareload_duplicator_utils.lua` — capture/restore + cross-constraints
- `core/respawn_handlers/sv_rareload_snapshot_restore.lua` — RestoreCategory + ID-exists filter
- `core/rareload_entity_identity.lua` — RareloadEntityID (field + NWString)
- `core/rareload_state_providers.lua` — `vehicles` + `crossConstraints` providers (repoint to new API)
- `utils/rareload_data_utils.lua` — `ClassIsRootVehicle`, `IsRootVehicle`, `IsVehiclePart`, `GetRootVehicle`
- `utils/rareload_ownership.lua` — ownership resolution

Reference bases (`/Users/noah/vehicule_addon`) — the source of §2/§12 facts:
- `simfphys_base/lua/entities/gmod_sent_vehicle_fphysics_base/{spawn,init}.lua` — PostEntityPaste wipes state; `GetCurHealth`/`SetCurHealth`, `SetColors`
- `lvs_base/lua/entities/lvs_base/sv_duping.lua` — resets active/engine/AI; `GetlvsReady`
- `lvs_base/lua/entities/lvs_wheeldrive_engine.lua` (+ starfighter/helicopter/ammorack) — component `HP/MaxHP` NetworkVars + `SetHP`
- `gmod-glide/lua/entities/base_glide/init.lua` + `base_glide_car/shared.lua` — `DuplicatorNetworkVariables` (tuning), skin/wheel restore
- `gmod-glide/lua/glide/server/util.lua` — `FilterEntityCopyTable`, Wire dupe, `SetChassisHealth`/`SetEngineHealth`, `Repair`
- full Glide NetworkVar set (engine/health/gear/lights/turret/lock) — `grep NetworkVar gmod-glide/lua`
- `LunasFlightSchool/lfs_base/lua/...` — NetworkVars (`Active`,`EngineActive`,`RPM`,`LGear`/`RGear`,`Shield`,`GetMaxHP`)
- `wac/...` — aircraft seat/passenger + input model
