# Rareload v5 — handoff for a new conversation

Read this first. It replaces the context of the previous conversation (on the Mac), which a new
conversation doesn't have. `*.md` files are not shipped with the addon (see `addon.json`).

## Where things are

- Repo: `github.com/noahbds/Rareload`, branch **`Rareload_Rewrite_Branch`** (v5). v4 is archived on
  **`legacy/v4`**: read it only to compare, never maintain it. `main` gets v5 when it's released.
- Version: **`5.0.0-rc.1`** (`lua/autorun/rareload.lua`). v5 is feature complete; we are in the
  release-candidate phase: find and fix bugs, polish. Localisation (8 more languages) comes after.
- The design plan `REWRITE_PLAN.md` was removed from the tree in `cb24005`; read it with
  `git show 55027c9:REWRITE_PLAN.md`. Code comments cite its IDs (F = feature, E = edge case,
  S = security, L = v4 lesson, G = GMod gotcha, B = v4 bug, D = decision).
- The offline tests (`tests/`, gitignored) and `tools/check_rules.sh` / `tools/check_lang.lua` were
  deleted, so checks are manual: `luajit -bl <file>` for syntax and globals, and in-game testing.

## Working with the user

- Follow `CLAUDE.md` (think first, simplest change, surgical edits, verify).
- **Never commit or push unless asked.** The user commits themselves most of the time.
- **No backward compatibility with v4** (no importer, no old convar names, no aliases). Nobody really
  uses the addon yet, so losing old data is fine.
- The user tests in game and sends screenshots and console errors. They write in English (sometimes
  French); answer in English. They care a lot about the UI looking good and being clear.
- Save numbers are written **"Save No. 5"** everywhere (translation key `save_no`), never "#5".
- Rareload is on the Steam Workshop; its Workshop ID is still unknown (needed for `resource.AddWorkshop`).
- The vehicle addons used for testing (WAC Aircraft…) are unpacked in `/Users/noah/vehicule_addon` on
  the Mac; ask where they are on Windows. Don't dig through Workshop `.gma` files.

## Architecture (one owner per job)

- `lua/autorun/rareload.lua` — loader, fixed order; the only global is `RARELOAD`.
- Shared: `sh_util` (vectors, equality, JSON checker), `sh_perms` (privileges + CAMI), `sh_net` (the only
  file using `net.*`: server pushes compressed chunked topics, per-chunk acks, byte budget per tick,
  urgent toasts; clients send validated rate-limited requests), `sh_config` (settings registry: one
  `RARELOAD.Setting` line makes the convar, the per-player override `rareload_pref_*`, locks, menu row;
  also `RARELOAD.ResetSettings`).
- Server: `sv_pipeline` (module registry, phases, save/restore, report sessions, manual save cooldown),
  `sv_snapshot` (duplicator snapshots: `CopyEntTable` per target, `plainData` strips live references,
  `Merge` / `KeepDeleted` for the overwrite settings, restore with spawn limits), `sv_history`
  (per-player saves per map, timeline ops, undo, object edits, world display feed), `sv_storage` (the
  only file touching `file.*`: atomic JSON + .bak, content-hash blobs, GC), `sv_spawn` (restore on
  spawn, death/disconnect cleanup), `sv_autosave`, `sv_antistuck` (method registry, one-frame search
  with a time budget), `sv_ownership`, `sv_commands` (`rareload <subcommand>`), `sv_log` (logs, report
  cards). Modules in `server/modules/`: player (transform, health, states, appearance), inventory
  (weapons, ammo, activeWeapon), world (entities, npcs, constraints), vehicles + vehicle_adapters
  (LVS, LFS, simfphys, Glide, WAC, Source).
- Client: `cl_ui` (UI kit, palette, fonts, sharp 16 px icons, toasts), `cl_state` (the one store of
  server data), `cl_menu` (tool panel = player settings; Utilities › Rareload › Server = server
  settings + player defaults with locks + anti-stuck methods + reset; Client = display settings; rows
  re-read values live), `cl_history` (Save Timeline), `cl_inspector` (objects of a save, JSON editor
  in DHTML with Ace and a plain-text fallback), `cl_debug` (report cards), `cl_toolscreen`, and
  `client/world/` (world display: tracking, phantoms, panels a.k.a. "SED", interaction, highlights).
- Translations: `resource/localization/en/rareload.properties` (GMod `.properties`, keys `rareload.*`).

## GMod gotchas learned the hard way

- `util.JSONToTable` turns string **values** shaped like `"[1 2 3]"` / `"{1 2 3}"` into Vectors/Angles,
  and numeric-looking **keys** into numbers. Never send user text or summaries in that shape
  unguarded; sort mixed keys with `tostring`.
- `duplicator.CopyEntTable` copies the entity's whole Lua table, live entity references included, and
  paste merges it back: stale references broke WAC (NULL rotor). Also don't store flags on the entity
  table if they must not be saved (use a weak table in Rareload instead).
- `duplicator.Copy` re-copies a whole contraption for each target (O(n²)); use `CopyEntTable` per target.
- DHTML: `AddFunction` only works after the document loaded (`OnDocumentReady`); `IsLoading` lags
  (GMod issue #4541). GMod's browser is CEF 86 on Windows, CEF 137 on macOS/Linux via GModPatchTool,
  Awesomium (Chromium 17) on some Linux setups.
- The listen-server host shares the server console; it still needs net pushes (report cards).
- `cvars.AddChangeCallback` doesn't fire reliably on clients for replicated convars: poll instead.
- Silkicons are 16 px: draw them at whole multiples of 16 on whole pixels, no "smooth", or they blur.
- In singleplayer `gmod_camera`'s attack runs `jpeg`: the held weapon is given first, and attack
  buttons are ignored after a respawn until released.

## RC1 pass (2026-09-25) — verified in game on Windows

Starting ammo when ammo isn't restored, the world panel detail cache, `[1 2 3]` notes/names, the 1 s
manual save cooldown, `object.deleteMany`, restore refused while dead, and the redesigned report cards.

## RC2 fixes (2026-09-25, not committed yet)

- `cl_state`: `forgetDetails` was called before its `local function` (nil global): every
  `history.objects` push errored on the client.
- `sh_net`: `ready`/queues/rate limits are kept on `Net._state`, so `rareload dev reload` (or a
  refresh of `sh_net`) no longer silently stops every push to connected players. `Net.Handle` only
  errors when a *different* file registers an opcode, so Lua auto-refresh of `sv_history`,
  `sh_config` or `sv_antistuck` no longer breaks the running server (`refresh` was left nil).
- Report cards: one net key per card (cards finished in the same tick replaced each other); a
  player named like `[1 2 3]` no longer drops the card.
- World display: the timeline preview hides your own phantom while you stand on the spot (the
  camera was inside it: giant glasses and a black box). Unbreakable props (health 0 of 1) show no
  health bar.
- Autosave with no current save does a full save (the first one had only the spawn loadout).
- `AntiStuck.Configure` with an unknown action no longer wipes the cached method order.
- All-digit object IDs (numeric JSON keys) now find their vehicle runtime / NPC AI in the vehicle
  restore and object info.
- A Confirm dialog can't be resized from its corner; `rareload history` prints "No. N";
  `rareload history restore` while dead says so.

Still unconfirmed in game: the JSON editor in GMod's browser (it falls back to a plain text box and
prints `[Rareload] JSON editor: …` when Ace doesn't draw). Version is still `5.0.0-rc.1`.

## Next steps

- Test the list above in game (on Windows there is a local debug server exposed as an MCP).
- Review the UI files not yet read line by line in the RC pass: `cl_ui.lua`, `cl_menu.lua`,
  `cl_toolscreen.lua`.
- Then localisation of the 8 other languages, from `en/rareload.properties`.
