# Rareload 5.4 plan

Status: draft, for review before any code is written.
Branch: `claude/elegant-keller-dhbb3u`.

5.3 already saves where you are, what you carry and what you built. 5.4 has two goals:

1. **A save captures everything.** Weapon attachments, movement and body, the selected tool,
   moving and burning objects, animations, weapons on the ground, Wiremod state, NPC
   relationships, the map's own doors and props, the time of day and weather.
2. **Saves become things you can move, share and manage.** Restoring puts changed objects back,
   saves can be exported and shared, and admins can manage every player's saves.

There are also several new features (section D). Each item lists what it is, why it matters, how it
fits the current code, its settings and privileges, its risks, and how to test it.

Sizes: **S** is up to a day, **M** is a few days, **L** is a week or more, or needs research first.

---

## Overview

| ID | Feature | Size | Milestone |
|----|---------|------|-----------|
| **0** | **Housekeeping** | | |
| 0.1 | Fix CI (missing `tests/` and `tools/`) | S | M0 |
| 0.2 | Legacy-conflict strings in all 10 languages | S | M0 |
| 0.3 | README version, "pinned" tooltip, playermodel-enforcement warning | S | M0 |
| **A** | **The three big ones** | | |
| A1 | Restore puts changed objects back, plus an optional exact restore | M | M1 |
| A2 | Export, import and share saves | L | M1 |
| A3 | Admin save management and storage | M | M2 |
| **B** | **Player capture** | | |
| B1 | Weapon attachments (ARC9, ArcCW, TFA, MW Base) | L | M3 |
| B2 | Movement and body: speeds, jump, gravity, size, max HP and armor, FOV, suit power, fire | M | M3 |
| B3 | Selected tool and its settings | S | M3 |
| B4 | PAC3 outfit and playermodel-selector support | M | M3 |
| B5 | Objects held by hand (use key) | S | M3 |
| **C** | **World capture** | | |
| C1 | Props in motion (velocity) | S | M4 |
| C2 | Burning objects | S | M4 |
| C3 | Animated props (sequence, cycle, speed) | S | M4 |
| C4 | Poses and expressions (check, then fill the gaps) | S–M | M4 |
| C5 | Weapons on the ground | M | M4 |
| C6 | Entity API, then Wiremod, E2 and Starfall state | L | M4 |
| C7 | Vehicles: every networked value, ammo, sirens, signals | M | M4 |
| C8 | NPCs: weapon, accuracy, relationships, followers | M | M4 |
| C9 | Map state: doors, buttons, breakables, map props, movers | L | M5 |
| C10 | Environment: time of day and weather (StormFox2…), sky, fog, sun | M | M5 |
| C11 | World settings: gravity, physics speed, AI switches | S | M5 |
| **D** | **New features** | | |
| D1 | Exclude objects from saves (C menu) and blocked classes (admin) | S | M2 |
| D2 | Smooth restore of large builds (spread over ticks) | M | M2 |
| D3 | Quicksave and quickload keys, `rareload restore` / `back` | S | M6 |
| D4 | Death recovery: save on death, death marker, "back to before I died" | M | M6 |
| D5 | Save thumbnails | M | M6 |
| D6 | Place a save somewhere else (at aim, rotated, on another map) | L | M6 |
| D7 | Checkpoints (named teleport spots) | M | M6 |
| D8 | Compare two saves | M | M6 |
| D9 | Server snapshots, rollback and crash recovery | L | M7 |
| D10 | PvP rules: no saving in combat, restore cooldown | S | M7 |
| D11 | Public developer API and documentation | M | M7 |
| **E** | **Later (5.5 and after)** | | |
| E1 | Persistent builds (restored at map load, owner offline) | L | — |
| E2 | Group saves (several players, passengers) | L | — |
| E3 | Rewind (rolling buffer of the last seconds) | M | — |
| E4 | Saves tab in the spawn menu | M | — |
| E5 | Shared storage for server networks (MySQL) | L | — |

If 5.4 gets too big, **M6 and M7 become 5.5**. M0 to M5 make a complete release on their own:
"captures everything, and restores, shares and manages it properly".

---

## Rules every feature follows

These are already true of the 5.x code. New work keeps them.

- **New data is a new module.** `RARELOAD.Module{ id, phase, setting, privSave, privRestore, save,
  restore, summary }` (`sv_pipeline.lua`). Saves that don't have the module simply skip it, and
  older Rareload versions ignore modules they don't know. So **`Store.SCHEMA` stays at 5**: nothing
  here changes the format of existing data, only adds to it.
- **Never change the shape of an existing module's data.** For example, `weapons` stays a list of
  classes, and attachments go in a new module (B1).
- **Third-party addons go through adapters,** like `Vehicles.Adapter`: `matches`, `capture` and
  `apply`, each call wrapped in `pcall`. A renamed method in an addon must never break a save.
- **Every setting** is declared with `RARELOAD.Setting`, has a category, a server default and can be
  locked. **Every privilege** is declared with `RARELOAD.Priv` and a sensible tier (anything that
  can grant power defaults to `admin`, like godmode today).
- **Report cards and toasts:** use `ctx:step` / `ctx:result` / `ctx:deny`, so whatever can't be
  given back is named.
- **Stable values.** Round floats and sort lists, so an unchanged state compares equal
  (`Util.Equal`, L35). Otherwise autosave saves constantly and identical world blobs stop being
  shared.
- **Infrastructure.** Deferred work goes through the pipeline's tick queue, never timers. Net
  messages go only through `sh_net.lua`, and files only through `sv_storage.lua`.
- **Translations.** Every new string goes into all 10 languages (`tools/check_lang.lua`).
- **Timeline components.** A new component is added in two places: `History.COMPONENTS`
  (`sv_history.lua:183`) and `COMPONENTS` (`cl_history.lua:11`).

---

## 0. Housekeeping (M0)

### 0.1 Fix CI — S
**Problem:** every CI run fails, including on `main`. `.gitignore` excludes `/tests` and `/tools`,
but `.github/workflows/ci.yml` runs `tools/check_rules.sh`, `tests/run.lua` and
`tools/check_lang.lua`.

**Fix (choose one):**
- (a) Commit `tests/` and `tools/`. They're already excluded from the Workshop upload by
  `addon.json`'s `ignore`.
- (b) Keep them local and remove the `rules` and `tests` jobs, keeping only glualint.

**Recommendation:** (a). Every feature below adds tests, and the translation check catches missing
strings.

### 0.2 Legacy-conflict strings — S
`rareload.legacy.title` and `rareload.legacy.body` exist only in `en`. Add them to the other 9
languages.

### 0.3 Small fixes — S
- `README.md` still says "Version 5.0".
- Add a tooltip for "pinned" in the timeline (a pinned save is never pruned, but can still be
  deleted by hand). Remove the TODO at `sv_history.lua:80`.
- Detect playermodel enforcement (Enhanced PlayerModel Selector's "Enforce your playermodel") when
  restoring appearance. If the model was changed back after the restore, add a report-card line and
  a toast naming the addon option. This resolves the note at `modules/player.lua:153`.

---

## A. The three big ones

### A1. Restore puts changed objects back — M (M1)
**Problem:** `Snapshot.Restore` only counts objects that are still on the map as "already on the
map" (`sv_snapshot.lua:393`). Moved, rotated, unfrozen or recolored objects stay as they are now,
so restoring an older save of a build you changed does nothing visible.

**Feature:**
- **Reset changed objects** (default on for timeline restores). Every saved object that is still on
  the map goes back to its saved:
  - position and angles, bone by bone for ragdolls
  - freeze state and gravity
  - color, material, skin and bodygroups
  - health
  - velocity (C1)
- **Exact restore** (option in the timeline's restore dialog, off by default). Also removes the
  player's objects that aren't in the save, so the map matches the save exactly.

**How:**
- In `Snapshot.Restore`, objects found in `live[id]` go into a "reset" pass instead of only being
  counted.
- Contraptions move together: compute every target transform first, then set them all, then wake
  physics. That way welded props don't fight each other.
- Cosmetics: run the entity modifiers stored in the def on the existing entity again (`colour`,
  `material`, `rareload`). They can safely be run twice.
- Constraints are already recreated by the `constraints` module. A1 doesn't change that.
- **Undo:** today undo removes what the restore created. For A1 it must also bring back what was
  changed or removed. Before the reset, capture the affected live objects with `Snapshot.Capture`
  and keep them inline in the undo entry (like `captureOnly` does for player modules). Undo then
  removes what was created and pastes the captured objects back.

**Spawn restores:** a respawn after death does **not** reset objects unless the new player setting
`resetOnSpawn` is on (default off). Otherwise dying would snap a build in progress back to its save.

**Settings:**

| Setting | Scope | Default |
|---------|-------|---------|
| `resetObjects` | player | true |
| `resetOnSpawn` | player | false |

The exact-restore checkbox lives in the timeline restore dialog. Removing objects needs the existing
`rareload_restore_entities` privilege.

**Report card:** "12 reset, 3 removed, 2 created".

**Test:**
- Move a welded contraption, restore, undo.
- Ragdoll pose.
- Exact restore with new unsaved props, then undo.
- Respawn with `resetOnSpawn` on and off.

### A2. Export, import and share saves — L (M1)
**Problem:** only inventories can be exported (`rareload inventory export`). Saves are tied to a
SteamID, a map and singleplayer or multiplayer (`Store.MapDir`). You can't move a build from
singleplayer to your server, give it to a friend, or keep a backup.

**Feature:**
1. **Export** a save to `data/rareload/exports/<name>.json`. The file holds:
   - `format = "rareload-save"` and `v = 1`
   - the Rareload version
   - the map, and whether it came from singleplayer or multiplayer
   - the entry, with every `$blob` inlined
2. **Import** an export into your own timeline as a new save, with reason `import` and the
   original's time and note kept. On another map, only the player modules apply in place; the world
   goes through D6 (place elsewhere) or is refused with a clear message.
3. **Share with a player** on the same server. The save is copied into their timeline after they
   accept a prompt. Blobs are stored per map and by content hash, so a copy costs almost nothing.
4. **Client-side export and import** (phase 2 of A2). The player downloads an export into their own
   game's `data/` folder, and uploads one to the server. Uploading needs client-to-server chunking
   in `sh_net.lua`, which today only chunks server-to-client and caps a request at 64 KB
   (`MAX_REQUEST`).

**Security:**
- An imported save is untrusted. Every object still goes through `Snapshot.Restore`'s checks:
  `DENIED`, `duplicator.IsAllowed`, spawn hooks and limits when `respectSpawnLimits` is on.
- Player modules are clamped the way they already are (health is capped at the current max,
  privileged states are checked).
- Size limits: the server setting `importMaxKB` (default 4096) and a maximum object count.
- Godmode and other privileged states in an imported save are still checked against the
  importer's privileges.

**Privileges:**

| Privilege | Tier |
|-----------|------|
| `rareload_export` | user |
| `rareload_import` | admin (servers can lower it) |
| `rareload_share` | user |

**Commands:**
- `rareload export <id> [name]`
- `rareload import <name>`
- `rareload share <id> <player>`

**UI:** "Export", "Share…" and "Import…" buttons in the timeline.

**Test:**
- Export then import on the same map.
- Import on another map.
- Singleplayer to multiplayer.
- A file with a denied class.
- An oversized file.
- Share, then decline.

### A3. Admin save management and storage — M (M2)
**Problem:** admins can only list another player's saves or clear them, from the console
(`rareload history <player>`). Storage is never managed across maps:
- `Store.GC` only scans the current map, and only at startup (`sv_storage.lua:136`).
- Pinned saves get past `historySize` (`sv_history.lua:244`), so pinning everything grows the file
  without limit.

**Feature:**
- **Another player's timeline:** an admin opens it from the timeline's player picker (online
  players, plus offline players with saves on this map). The same window works in read-only mode,
  plus: teleport to the save, restore it for the player, make it their respawn point, delete, pin.
  The same is available as commands, `rareload history <action> <player> <id>`.
  - `History.Doc(ply)` gains a `History.DocByKey(sid64)` twin so offline players work.
- **Storage overview** (`rareload data usage`, plus a section in the server menu):
  - size by map
  - size by player
  - unused blobs
  - the biggest saves
- **Cleanup across all maps:** `rareload data cleanup all` runs `Store.GC` over every
  `sp/*` and `mp/*` folder. Optional: delete saves older than N days (`rareload data prune <days>`).
- **Pinned limit:** a new server setting, `pinnedMax` (default 20). Pinning past it is refused with
  a toast.
- **Audit log:** every admin action on another player's saves is logged through `sv_log` and shown
  in `rareload debug recent`.

**Privileges:** `rareload_manage_saves` (admin) for other players' saves. Data commands keep using
`rareload_data_cleanup`.

---

## B. Player capture (M3)

### B1. Weapon attachments — L
**Problem:** only weapon classes, clips and reserve ammo are saved (`Inventory.Weapons`). Customized
weapons from ARC9, ArcCW, TFA or MW Base come back with no attachments.

**How:**
- New registry `RARELOAD.Weapons.Adapter{ id, priority, matches(wep), capture(wep, ply) -> t,
  apply(wep, t, ply), captureOwned?(ply), applyOwned?(ply, t) }`. It's the same pattern as the
  vehicle adapters.
- New module **`weaponState`** (phase `inventory`, `after = { "weapons" }`). Its data is
  `{ [class] = { adapter = id, data = t } }`.
- `ammo` gains `after = { "weapons", "weaponState" }`, because attachments change magazine size, so
  clips must be set after them.
- `globalInventory` stores the same `extras` field and adds `weaponState` to its `replaces`.
- The inventory manager shows and edits `extras` in its JSON.
- `captureOwned` and `applyOwned` cover the **attachment inventory** that ArcCW and ARC9 keep for
  each player (when attachments aren't free).

**Adapters to build:** ARC9, ArcCW, TFA, MW Base. Each base's API must be researched first. Prefer
the base's own preset or export format where it has one (ARC9 and ArcCW have presets), because it
survives updates of the base better.

**Fallback:** none by default. Saving a scripted weapon's networked values generically could set
internal state that its base doesn't expect.

**Settings:** `keepAttachments` (player, default true). It's covered by `rareload_restore_inventory`.

**Test:** one customized weapon per base, then:
- respawn
- timeline restore
- global inventory on another map
- base not installed: report card says "addon not installed"

### B2. Movement and body — M
**Problem:** what's saved today:
- states: godmode, notarget, frozen, noclip, flashlight and velocity
- appearance: model, skin, bodygroups, colors and material

Many addons and admin commands change values that nothing saves:
- walk, run, slow-walk and crouch speeds, and jump power
- the player's gravity
- model scale, which also needs the view offsets and hull
- max health and max armor
- FOV set by addons
- suit power
- whether you're on fire

**How:**
- New module **`body`** (phase `player`), before `health`: `health` gains `after = { "body" }`, so
  health is clamped to the restored max HP and not the default 100.
- Model scale restores the scale and adjusts the view offset (`SetViewOffset`,
  `SetViewOffsetDucked`) and the hull, so a small player doesn't see through the floor.
- FOV is only saved when it was set by `SetFOV` and the player isn't zoomed (suit zoom).
- On fire: `IsOnFire`, restored with `Ignite(duration)`. Duration comes from the server setting
  `fireDuration` (default 10 s), because the remaining burn time can't be read.
- Suit power: `GetSuitPower` / `SetSuitPower`.

**Abuse:** speed, jump, gravity, scale and max health/armor can grant power. A temporary buff saved
once would otherwise last forever. These go behind the new privilege
**`rareload_restore_privileged_body`** (admin by default). It works like godmode: what the player
may not get back is reported and left as it is. Suit power, FOV and fire only need
`rareload_restore_states`.

**Settings:** `keepBody` (player, default true).

**Timeline component:** these values go in `states`, and max health/armor in `health`, so no new
component is needed.

### B3. Selected tool and its settings — S
**Problem:** `activeWeapon` saves only `gmod_tool`, so the toolgun comes back on its default tool
with default settings.

**How:**
- New module **`toolState`** (phase `finalize`, after `activeWeapon`). At save time the server reads
  `ply:GetInfo("gmod_toolmode")` and that tool's `ClientConVar` values (from the player's
  `gmod_tool` weapon `Tool` table).
- Limits: at most 64 convars, values up to 256 characters.
- Restore sends `tool.apply` to the client, which runs `RunConsoleCommand` only for names that
  start with `<mode>_` and are that tool's client convars.
- Saving every tool's settings is too much data, so only the selected tool's are saved.

**Settings:** `keepTool` (player, default true), in the `inventory` component.

### B4. PAC3 outfit and playermodel selectors — M (research first)
**Problem:** appearance doesn't include a worn PAC3 outfit, a large part of how many players look.
Playermodel selectors that enforce a model also undo the restored model (see 0.3).

**How:**
- **Research step:** how PAC3 exposes the worn outfit. Either the server keeps each player's
  outfit, or the client has to send it back. The outfit can be large, so saving the outfit file
  name (or a hash) and asking the client to wear it again may be better than storing the data.
- An appearance adapter registry, so other cosmetic addons can be added later.
- Enhanced PlayerModel Selector: when enforcement is on, restore through its own convars, or warn
  (0.3).

**Settings:** part of `keepAppearance`.

### B5. Objects held by hand — S
A prop held with the use key comes back where it was in the air, but dropped. After the restore,
`ply:PickupObject(ent)` picks it back up when it's still in reach. Objects held with the physgun
can't be grabbed again from code, so they're saved where they are.

---

## C. World capture

### C1. Props in motion — S (M4)
**Problem:** the duplicator doesn't copy velocity. A rolling car or a swinging contraption comes
back still.

**How:**
- The `rareload` entity modifier gains `vel = { [bone] = { lin, ang } }`. It's saved only for
  bones that are awake, not frozen, and faster than a threshold, so still builds keep comparing
  equal.
- Values are rounded to whole units (L35).
- Applied in `Snapshot.Restore` right after the frozen-state pass, in A1's reset, and in the
  vehicle scheduler's `APPLY` step.

**Settings:** `keepMotion` (player, default true).

### C2. Burning objects — S (M4)
The `rareload` modifier gains `fire = true` when `ent:IsOnFire()`. On restore, `Ignite(fireDuration)`
(the setting from B2). Covers props, NPCs and ragdolls. Vehicles that track fire themselves (Glide)
already go through their adapter.

### C3. Animated props — S (M4)
For objects that aren't NPCs or ragdolls and have a non-default animation, the `rareload` modifier
gains `anim = { seq, cycle, rate }`. Restore calls `ResetSequence(seq)`, `SetCycle(cycle)` and
`SetPlaybackRate(rate)`. This covers animated-prop tools and scripted entities.

### C4. Poses and expressions — S–M (M4)
**Step 1, check in game which of these survive a restore today:**
- Faceposer (flexes)
- Eye Poser
- Finger Poser
- Inflator
- bone manipulation (Ragdoll Mover, Stop Motion Helper)

**Step 2, fill the gaps:**
- flex weights and scale (`GetFlexNum` / `GetFlexWeight` / `GetFlexScale`)
- bone manipulations: position, angles, scale and jiggle

These go in the `rareload` modifier, and only for what's missing, so nothing is stored twice.

**Test:** a posed ragdoll with an expression, its eyes on a target and posed fingers.

### C5. Weapons on the ground — M (M4)
**Problem:** `Ownership.Owned` skips every weapon (`not ent:IsWeapon()`, `sv_ownership.lua`). Also,
`PlayerSpawnedSWEP` isn't recorded, so spawned weapons have no owner.

**How:**
- Record the owner on `PlayerSpawnedSWEP` and `PlayerDroppedWeapon`.
- `Ownership.Owned` includes weapons with **no holder** (`not IsValid(wep:GetOwner())`).
- The `entities` module saves them like props.

**Duplication risk:** the same weapon could be saved on the ground and given back by the inventory.
A weapon that is picked up keeps its Rareload ID, so as long as it exists it is "already on the
map" and never pasted again. When it's removed (stripped on death), the next restore would paste it
on the ground **and** give it.

Fixes:
- When a saved ground weapon is equipped, mark `entities` dirty for autosave.
- At restore time, skip a saved ground weapon when the same restore gives that class back.
- When `respectSpawnLimits` is on, ground weapons go through `PlayerGiveSWEP` / `PlayerSpawnSWEP`.

**Settings:** `keepGroundWeapons` (player). Defaults to the value of `respectSpawnLimits` inverted:
on in singleplayer, off on servers until the owner turns it on.

### C6. Entity API, then Wiremod, E2 and Starfall — L (M4, the adapters may slip)
**Problem:** the duplicator rebuilds chips and gates, but their running state is lost: E2
variables, latches, counters, memory chips and Starfall state.

**How, in two parts:**
1. **Generic entity API** (small, do first). If a scripted entity defines `ENT:RareloadCapture()`
   returning plain data, it's stored in the `rareload` modifier. After a paste or reset,
   `ENT:RareloadApply(data)` is called. Any addon can opt in without Rareload knowing it. This is
   also how D11 is documented.
2. **Wiremod adapters, after research:**
   - **Gates with memory:** latch, counter, timer, RAM and ROM chips, `wire_data_store`.
   - **E2:** saving `@persist` variables. Only types that can be serialized: numbers, strings,
     vectors, angles, arrays and tables of those, and entities as Rareload IDs. Apply after the
     chip finished its first run, or the chip's `first()` code overwrites them.
   - **Starfall:** no access from outside the script's sandbox. Offer a small Starfall library
     (`rareload.onSave` / `rareload.onRestore`) so scripts can opt in. This depends on whether
     Starfall allows extensions without a fork.

**Risk:** E2 internals change between Wiremod versions. Everything is behind `pcall` and the
setting `keepChipState` (player, default true). If any of the Wiremod adapters slip, part 1 alone
still ships.

### C7. Vehicles: more state — M (M4)
**Problem:** each adapter saves only some of its base's state (health, fuel, lights, engine).
Sirens, turn signals, gears and weapon ammo are lost on most bases.

**How:**
- **Generic networked values:** for root vehicles that are scripted entities, capture
  `ent:GetNetworkVars()`. After `WAIT_READY`, restore with `RestoreNetworkVars`, minus an exclusion
  list per adapter (drivers, entity references, timers, anything the adapter already sets). This
  picks up sirens, signals, gears and modes on every base without one adapter per field.
- **Weapon ammo:** LVS and WAC keep it in Lua tables, so each needs code in its adapter.
- **Passengers** (reseating other players) need their agreement, so they wait for group saves (E2).

**Test:** each supported base with sirens and lights on, in gear, with ammo spent.

### C8. NPCs: more state — M (M4)
**Problem:** `captureAI` saves state, schedule, squad and the current enemy only.

**Add to the NPC AI data:**
- **Weapon:** the active weapon's class. After the paste, `npc:Give(class)` if the NPC has none.
  Check first whether the duplicator already keeps it for each NPC type.
- **Accuracy:** `GetCurrentWeaponProficiency` / `SetCurrentWeaponProficiency`.
- **Relationships:** `npc:Disposition(target)` toward every online player (by SteamID64) and every
  other saved NPC (by Rareload ID). Restored with `AddEntityRelationship`. That's how a friendly
  Combine soldier stays friendly.
- **Followers:** citizens following the player are in `player_squad`, which is already saved. Check
  in game that they follow again, and add `npc:SetTarget` or a follow order if not.
- **Animation:** for sitting or scripted poses, C3 applies to NPCs too, but only when the NPC is in
  a scripted sequence.

### C9. Map state — L (M5)
**Problem:** map-created entities are never saved (`CreatedByMap` in `sv_ownership.lua`), so doors,
buttons, broken windows, elevators and moved map props are lost.

**How:**
- New module **`mapState`** (phase `world`). Map entities are identified with `ent:MapCreationID()`,
  which stays the same each time the map loads. It's only saved when `game.GetMapVersion()`
  matches.
- **What's saved:**
  - doors (`prop_door_rotating`, `func_door*`): open or closed, locked
  - buttons (`func_button`): locked
  - breakables (`func_breakable`, map `prop_physics`): present or broken
  - map physics props: position, angles, frozen
  - movers (`func_movelinear`, `func_tracktrain`): position
- **Restore uses the entity's own inputs** (`Fire("Open")`, `Fire("Close")`, `Fire("Lock")`)
  rather than setting position directly, so the entity's state machine stays right. Breakables that
  were broken in the save are removed. Things broken **after** the save can only come back with a
  map cleanup, which is the optional "reset the map first" step (admin only, because it affects
  everyone).
- **Who:** the map is shared by everyone. Privileges `rareload_save_map_state` and
  `rareload_restore_map_state` default to **admin**. The server setting `keepMapState` defaults to
  on in singleplayer and off in multiplayer.

**Timeline:** a new **`scene`** component (C9, C10, C11) with its own icon and string.

### C10. Environment — M (M5)
**How:**
- New registry `RARELOAD.Environment.Adapter{ id, available(), capture(), apply(t) }` and module
  **`environment`** (phase `world`).
- **StormFox2:** time, weather, temperature, wind. Other weather addons can be added later. Each
  base's API must be researched first.
- **Sky, sun and fog:** first check whether Sandbox's `edit_sky`, `edit_sun` and `edit_fog`
  entities are already saved (they're spawned scripted entities, and the duplicator copies their
  networked values). If they are, only document it. Either way, also capture `env_skypaint`'s
  networked values directly, so a sky changed without the edit entity is kept too.
- Same privileges and settings as C9: admin by default, and in the `scene` component.

### C11. World settings — S (M5)
**How:**
- Module **`worldSettings`** saves a fixed list of convars:
  - `sv_gravity`
  - `phys_timescale`
  - `ai_disabled`
  - `ai_ignoreplayers`
  - `ai_keepragdolls`
  - `host_timescale`, only when `sv_cheats` allows it
- Restore only sets the ones that differ.
- Admin only, in the `scene` component.

---

## D. New features

### D1. Exclude objects and block classes — S (M2)
- **Per object:** a C menu property (`properties.Add`) with "Don't save with Rareload" and "Save
  with Rareload". It sets `ent.RareloadExclude` (networked), which the world modules skip. The world
  display shows excluded objects with a crossed icon.
- **Blocked classes (admin):** today `DENIED` and `EXCLUDED` are hard-coded in `sv_snapshot.lua`.
  Add a list stored in `data/rareload/blocked.json` (a convar is limited to 250 characters), edited
  in the server menu and with `rareload block add|remove|list <class>`. It's checked in both capture
  and restore.

### D2. Smooth restore of large builds — M (M2)
**Problem:** `Snapshot.Restore` pastes everything in a single `duplicator.Paste`. A build with
hundreds of props freezes the server for a moment.

**How:**
- Above `restoreBatch` objects (server setting, default 50), create entities in batches, one batch
  per tick, with `duplicator.CreateEntityFromTable`, keeping an index-to-entity map.
- Create the snapshot's constraints once every batch exists, the way `duplicator.Paste` does
  internally.
- The module uses `ctx:async`, which already exists for NPCs and vehicles.
- Progress shows on the tool screen and the report card.

**Risk:** this reimplements part of `duplicator.Paste`, so entity modifiers, bone modifiers and the
post-paste functions must run in the same order. Compare against `duplicator.Paste` in game, with
AdvDupe2 builds as test cases.

### D3. Keys and commands — S (M6)
- **Commands:**

  | Command | Does |
  |---------|------|
  | `rareload restore [components]` | Restore your respawn point |
  | `rareload back` | Restore the previous save |
  | `rareload quicksave` | Save into a quick slot |
  | `rareload quickload` | Load the quick slot |

- **Binders in the tool panel** (`DBinder`) for save and load, stored as client convars
  (`cl_rareload_key_save`, `cl_rareload_key_load`) and handled in `PlayerButtonDown`, so they work
  without the tool out.
- Same privileges as the tool. On servers, D10's cooldown applies.

### D4. Death recovery — M (M6)
- **Save on death** (player setting `saveOnDeath`, default off). On `DoPlayerDeath`, before weapons
  are dropped, save with reason `death`, using the last health before the fatal hit (tracked from
  `PlayerHurt`).
- **Death marker:** a 3D marker on the client where you died, shown until you get there or restore.
- **"Back to before I died"** button in the timeline and a toast action after respawn.
- **Respawn choice** (optional, player setting): a small screen after death to respawn at the
  respawn point, the map spawn or the death save.
- PvP servers can lock `saveOnDeath` off.

### D5. Save thumbnails — M (M6)
- When the server confirms a save, the client captures a small image (256×144 JPEG,
  `render.Capture`) with the HUD hidden.
- Stored client-side: `data/rareload/thumbs/<server>/<map>/<id>.jpg`. The image is only for that
  player, so it isn't uploaded.
- Shown in timeline rows and the preview. Saves without one show the current icon.
- Old thumbnails are deleted with their save.

### D6. Place a save somewhere else — L (M6)
- "Place here" in the timeline: the save's objects follow your aim as phantoms (the preview system
  exists), and you rotate them with the scroll wheel. Clicking pastes them.
- Offset and rotation are applied to every def (`Pos` / `Angle`, and constraint positions in local
  space). Copies get **new Rareload IDs** (a flag in the `rareload` modifier), so the original and
  the copy are separate objects.
- **Across maps:** works with imports (A2), which is the main way a build moves between maps.
- Same checks as a restore (limits, spawn hooks). Undo removes the copy.

### D7. Checkpoints — M (M6)
- Named teleport spots, separate from saves: `checkpoints = { { name, pos, ang } }` in the player's
  saves document, at most `checkpointMax` (server setting, default 20).
- A quick menu, plus optional markers on screen.
- Uses the existing anti-stuck when teleporting.
- **Privilege** `rareload_checkpoints`: user tier in singleplayer. On servers it's allowed with the
  D10 cooldown, or set to admin by the owner.

### D8. Compare two saves — M (M6)
- "Compare with…" in the timeline. The server computes the difference between two entries:
  - player values changed (health, position, states)
  - weapons added and removed
  - objects added, removed and moved, matched by Rareload ID with a distance threshold
- The world display colors moved objects with the A1 colors.
- Useful before an exact restore (A1).

### D9. Server snapshots, rollback and crash recovery — L (M7)
**Problem:** nothing protects builds from a griefer or a crash. The `ShutDown` hook doesn't run on a
crash, and autosave is off by default.

**How:**
- **Snapshots:** every `snapshotInterval` minutes (server setting, 0 = off), a silent capture of
  every online player's world modules. They're stored in `<mapdir>/_server` as a ring of
  `snapshotKeep` entries (default 6). Blobs are shared with saves, so an unchanged build costs
  nothing.
- **Rollback:** `rareload rollback <minutes|id> [player]` and a section in the server menu. For
  each player in the snapshot, it uses A1's exact restore for that player's objects. Undo is kept.
- **Crash recovery:** a marker file is written at startup and removed in `ShutDown`. If it's still
  there at the next start, the last shutdown was a crash. Admins are told on join, and each player's
  last snapshot is used as their world on their first spawn when it's newer than their own save
  (server setting `crashRecovery`: off / ask / auto).

**Privilege:** `rareload_rollback` (admin).

### D10. PvP rules — S (M7)
New server settings, all off by default:

| Setting | Effect |
|---------|--------|
| `saveCombatDelay` | No saving within N seconds of taking or dealing damage |
| `restoreCooldown` | Seconds between timeline restores, for each player |
| `restoreNeedsSpawn` | Timeline restores only allowed within N seconds of spawning |

Refusals use `RareloadCanSave` / `RareloadCanRestore` internally and show a toast.

### D11. Public developer API — M (M7)
- Declare stable and document:
  - `RARELOAD.Module`
  - `RARELOAD.Vehicles.Adapter`
  - `RARELOAD.Weapons.Adapter`
  - `RARELOAD.Environment.Adapter`
  - `ENT:RareloadCapture` / `ENT:RareloadApply`
  - the existing hooks
- Bump `RARELOAD.API` to 2.
- **New hooks:**

  | Hook | Runs |
  |------|------|
  | `RareloadPreSave(ply, reason)` | Before a save |
  | `RareloadPreRestore(ply, entry, reason)` | Before a restore |
  | `RareloadObjectRestored(ent, def, ply)` | After each restored object |
  | `RareloadTimelineUpdated` | Client side, when the timeline changes |

- `docs/API.md` (excluded from the Workshop upload), plus an example addon that saves its own data.

---

## E. Later (5.5 and after)

- **E1 Persistent builds:** an admin marks a save as permanent, and its world is restored when the
  map loads, owner online or not. Owner-less objects go to the world, or to the owner once they
  join.
- **E2 Group saves:** one save for several players and their objects (RP scenes, events, co-op
  builds). Restoring reseats passengers too (C7).
- **E3 Rewind:** a rolling buffer of the last 30–60 s (position, health, states, and optionally the
  world) to undo a fall or a noclip trip.
- **E4 Saves tab in the spawn menu:** browse saves and exports with thumbnails, like dupes.
- **E5 Shared storage:** a storage backend interface (JSON files today, MySQL with MySQLOO) so
  server networks share saves and the global inventory.

---

## Milestones

| Milestone | Content | Theme |
|-----------|---------|-------|
| M0 | 0.1–0.3 | Clean base, green CI |
| M1 | A1, A2 | Restore really goes back; saves travel |
| M2 | A3, D1, D2 | Server owners: management, control, performance |
| M3 | B1–B5 | Player captured completely |
| M4 | C1–C8 | Objects captured completely |
| M5 | C9–C11 | The scene: map, weather, world settings |
| M6 | D3–D8 | New ways to use saves |
| M7 | D9–D11 | Safety and developers |

Each milestone ends with:
- all strings in the 10 languages
- tests for the pure functions in `tests/`
- new checks in `rareload selftest` for engine behaviour relied on (`MapCreationID` staying the
  same across loads, `GetNetworkVars` / `RestoreNetworkVars`, `Ignite`)
- an in-game checklist for the milestone's test cases

## Release

- Bump `RARELOAD.version` to "5.4".
- Update `README.md`, the Workshop description (`docs/workshop/descriptions/*`) and screenshots for
  the new windows.
- Write release notes listing new settings and privileges. Server owners should know that `scene`
  features and privileged body values default to admin.

## Open questions

1. CI: commit `tests/` and `tools/` (recommended), or drop those jobs?
2. A1: should "reset changed objects" be on by default for timeline restores? (Recommended: yes.)
3. A2: who may import on servers by default: admin (recommended) or user?
4. C5 and B2: are the defaults in this plan right for servers (ground weapons off, privileged body
   values admin)?
5. Scope: ship M0–M5 as 5.4 and move M6–M7 to 5.5, or everything in 5.4?
