# Rareload — Position, Inventory, and World State for Garry's Mod

Version: 2.0.0

Rareload lets players save and restore their position/angles and persist inventory, ammo, map entities, and NPCs. It includes an advanced anti-stuck system with a full profile/settings UI, an admin permission panel, an entity viewer, and in-game debug/visualization tools.

## Features

- Position & angles
  - Save targeted or current position and your eye angles
  - History cache with “restore previous position” (tool reload)
  - Auto-save timer with on-screen countdown/progress and “Auto Saved!” feedback
- Inventory & player state
  - Retain inventory, global inventory (shared across maps), ammo, health, armor
- World state
  - Persist map entities and NPCs (with per-map storage)
- Anti-stuck system
  - Multi-method resolver (cached positions, displacement, nav graph, map entities, space scan, world brushes, grid, spawn points, emergency teleport)
  - Configurable settings & priorities
  - Profile system (create, save, load, apply profiles on client)
  - Debug panel (server-authorized)
- Admin & tools
  - Admin permissions panel (role-like granular flags)
  - Entity Viewer (inspect/modify saved entities/NPCs)
  - Phantom visualization of saved positions (debug)
- Networking & UI
  - Toolscreen with status, feature list, countdown, and reload-state overlay
  - Settings broadcast/sync to clients

## Toolgun: Rareload Tool

- Left click: Save a respawn position at the targeted location
- Right click: Save a respawn position at your current location
- Reload: Restore the previous saved position (uses history)

Tool menu (Utilities > Rareload > Rareload Configuration):

- Toggles
  - Enable Rareload (addonEnabled)
  - Anti-stuck system (spawnModeEnabled)
  - Auto save (autoSaveEnabled)
  - Keep Inventory (retainInventory)
  - Keep Global Inventory (retainGlobalInventory)
  - Keep Health & Armor (retainHealthArmor)
  - Keep Ammo (retainAmmo)
  - Keep Map Entities (retainMapEntities)
  - Keep Map NPCs (retainMapNPCs)
  - No custom respawn at death (nocustomrespawnatdeath)
  - Debug Mode (debugEnabled)
- Sliders
  - Auto Save Interval (autoSaveInterval)
  - Auto Save Angle Tolerance (angleTolerance)
  - Position History Size (maxHistorySize)
- Actions
  - Save Position now
  - Open Anti-Stuck Debug Panel
  - Open Entity Viewer

Notes:

- Vehicle/vehicle state toggles exist in code but are currently disabled.

## Anti-Stuck System

- Multiple resolution methods with tunable priorities
- Client-side profile system (create, save, apply, list)
- Settings buckets (general/search/navigation/grid/spiral/vertical/offsets/methods)
- Debug access (admins) via command and tool button

Open debug panel (admin):

- rareload_open_antistuck_debug

Profile data:

- Stored under data/rareload/anti_stuck_profiles/\*.json
- Current profile pointer in data/rareload/anti_stuck_current.json

## Entity Viewer

- Inspect saved entities and NPCs per-map
- Edit JSON in a validated, formatted editor
- Open from tool menu or:
  - entity_viewer_open

## Admin Permissions

Defined permissions:

- USE_TOOL — Can use the Rareload toolgun
- SAVE_POSITION — Can save position
- LOAD_POSITION — Can load saved position
- KEEP_INVENTORY — Can retain inventory
- MANAGE_ENTITIES — Can manage saved entities/NPCs
- ADMIN_PANEL — Can access admin panel
- RARELOAD_TOGGLE — Can toggle addon settings
- ENTITY_VIEWER — Can open the entity viewer
- RARELOAD_SPAWN — Allowed to spawn with Rareload features

Admin panel files are included client-side; access requires server permission. Permission plumbing is initialized on server start.

## Commands

User actions:

- save_position — Save your current position (also used by right click)
- entity_viewer_open — Open Entity Viewer (if permitted)

Toggles (server-side handlers):

- rareload_rareload — Enable/disable addon
- rareload_spawn_mode — Enable/disable anti-stuck system
- rareload_auto_save — Enable/disable auto position saving
- rareload_retain_inventory — Keep inventory
- rareload_retain_global_inventory — Keep global inventory
- rareload_retain_health_armor — Keep health & armor
- rareload_retain_ammo — Keep ammo
- rareload_retain_map_entities — Keep map entities
- rareload_retain_map_npcs — Keep map NPCs
- rareload_nocustomrespawnatdeath — Disable custom respawn on death
- rareload_debug — Toggle debug mode
- rareload_debug_cmd — Auxiliary debug toggle

Settings:

- set_auto_save_interval <seconds>
- set_angle_tolerance <degrees>
- set_history_size <count>
- set_max_distance <units> (used by some systems)

Anti-stuck:

- rareload_open_antistuck_debug — Open debug panel (admin)

Settings broadcast (server only):

- rareload_broadcast_settings

Note: Command availability depends on permissions and server installation.

## Data & Storage

- Addon settings: data/rareload/addon_state.json
- Per-map player positions: data/rareload/player*positions*<map>.json
- Global inventory: data/rareload/global_inventory.json
- Anti-stuck profiles: data/rareload/anti_stuck_profiles/\*.json
- Current anti-stuck profile: data/rareload/anti_stuck_current.json

## Visual Debug

- Toolscreen: shows addon status, features, and auto-save progress bar
- Reload overlay: shows whether previous position data exists
- Phantoms: ghost models rendered at saved positions (when debug enabled)

## Installation

- Install on server and/or client
- Restart GMod/server
- Access Toolgun > Utilities > Rareload > Rareload Configuration
- Ensure permissions are configured for your admins/players

## Troubleshooting

- Not spawning correctly: enable debug and use anti-stuck debug panel
- No previous position: the reload overlay will indicate “No Position Data”
- Entities/NPCs missing: verify map entity/NPC toggles are enabled and permissions allow management
- Global inventory not persisting: ensure retainGlobalInventory is enabled
- Permissions: server must initialize permission system; only permitted users can toggle settings or access tools

## Credits

Created by Noahbds

- **Performance issues**: Adjust batch sizes and intervals in settings

### Debug Information

Enable debug mode to access:

- Detailed spawn calculations
- Entity save/load statistics
- Permission validation logs
- Performance timing data

## 🤝 Contributing

This is my first foray into Garry's Mod addon development. While the code may not be perfect, it's functional and continuously improving. Feedback and suggestions are always welcome!

### Development Notes

- Built with modularity in mind
- Extensive error handling and validation
- Comprehensive debugging tools included
- Performance-focused design decisions

## 📞 Support & Contact

- **Issues**: Report bugs through Steam Workshop comments
- **Suggestions**: Feature requests welcome
- **Updates**: Check Steam Workshop for latest versions

## 📜 Version History

### v2.0.0 (Current)

- Complete permission system overhaul
- Advanced admin panel and entity viewer
- Enhanced NPC relationship management
- Performance optimizations and bug fixes

### v1.2

- Initial release with basic position saving
- Inventory management features
- Simple entity persistence

### v1.24

- Actual Steam Addon

---

**Note**: This addon represents a learning journey in Garry's Mod development. While the code continues to evolve, the functionality is robust and thoroughly tested in both singleplayer and multiplayer environments.

_Created by Noahbds | Enhanced with community feedback (I recieved 1 comment on the addon page :))_
