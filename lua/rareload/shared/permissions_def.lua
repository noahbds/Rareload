RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}

-- Define all available permissions
-- Each permission has: name, desc, default, category
-- Categories: ADMIN, POSITION, INVENTORY, ENTITIES, TOOL
RARELOAD.Permissions.DEFS = {
    -- ═══════════════════════════════════════════
    -- TOOL ACCESS
    -- ═══════════════════════════════════════════
    USE_TOOL = {
        name = "Use Toolgun",
        desc = "Can use the Rareload toolgun",
        default = true,
        category = "TOOL"
    },
    EXECUTE_RARELOAD_COMMANDS = {
        name = "Console Commands",
        desc = "Can use Rareload save/restore console commands (e.g. save_position)",
        default = true,
        category = "TOOL"
    },

    -- ═══════════════════════════════════════════
    -- POSITION & SPAWN
    -- ═══════════════════════════════════════════
    LOAD_POSITION = {
        name = "Load Position",
        desc = "Can load their saved position",
        default = true,
        category = "POSITION"
    },
    RARELOAD_SPAWN = {
        name = "Restore Position on Spawn",
        desc = "Player's saved position and data will be restored when they respawn",
        default = true,
        category = "POSITION"
    },
    TELEPORT_PLAYER = {
        name = "Teleport to Position",
        desc = "Can use teleport commands to move to specific coordinates",
        default = false,
        category = "POSITION"
    },

    -- ═══════════════════════════════════════════
    -- INVENTORY & STATS
    -- ═══════════════════════════════════════════
    KEEP_INVENTORY = {
        name = "Inventory Restore (Master Switch)",
        desc = "Master gate: disabling this blocks ALL inventory restore (map & global) for this player",
        default = true,
        category = "INVENTORY"
    },
    RETAIN_INVENTORY = {
        name = "Map Inventory Restore",
        desc = "Allows restoring map-specific inventory on respawn (requires master switch)",
        default = true,
        category = "INVENTORY"
    },
    RETAIN_GLOBAL_INVENTORY = {
        name = "Global Inventory Restore",
        desc = "Allows restoring cross-map global inventory on respawn (requires master switch)",
        default = true,
        category = "INVENTORY"
    },
    RETAIN_HEALTH_ARMOR = {
        name = "Retain Health and Armor",
        desc = "Can restore health and armor from saved data on respawn",
        default = true,
        category = "INVENTORY"
    },
    RETAIN_AMMO = {
        name = "Retain Ammo",
        desc = "Can restore ammo and clips from saved data on respawn",
        default = true,
        category = "INVENTORY"
    },
    RETAIN_PLAYER_STATES = {
        name = "Retain Player States",
        desc = "Can restore player states on respawn: god mode, notarget, noclip, frozen",
        default = true,
        category = "INVENTORY"
    },

    -- ═══════════════════════════════════════════
    -- ENTITIES & NPCs
    -- ═══════════════════════════════════════════
    SAVE_ENTITIES = {
        name = "Save Entities",
        desc = "Entities owned by this player will be included when saving their position",
        default = true,
        category = "ENTITIES"
    },
    RESTORE_ENTITIES = {
        name = "Restore Entities",
        desc = "Player's saved entities will be restored on respawn",
        default = true,
        category = "ENTITIES"
    },
    SAVE_NPCS = {
        name = "Save NPCs",
        desc = "NPCs owned by this player will be included when saving their position",
        default = true,
        category = "ENTITIES"
    },
    RESTORE_NPCS = {
        name = "Restore NPCs",
        desc = "Player's saved NPCs will be restored on respawn",
        default = true,
        category = "ENTITIES"
    },
    SAVE_VEHICLES = {
        name = "Save Vehicles",
        desc = "Vehicles owned by this player will be included when saving their position",
        default = true,
        category = "ENTITIES"
    },
    RESTORE_VEHICLES = {
        name = "Restore Vehicles",
        desc = "Player's saved vehicles will be restored on respawn",
        default = true,
        category = "ENTITIES"
    },
    MANAGE_ENTITIES = {
        name = "Manage Entities (Admin)",
        desc = "Can manage, manually respawn, delete, and freeze/unfreeze saved entities and NPCs via admin commands",
        default = false,
        category = "ENTITIES"
    },
    ANTI_STUCK_CONFIG = {
        name = "Anti-Stuck Configuration",
        desc = "Can configure anti-stuck settings, methods, and profiles on the server",
        default = false,
        category = "ENTITIES"
    },

    -- ═══════════════════════════════════════════
    -- DISPLAY & VISUALIZATION
    -- ═══════════════════════════════════════════
    VIEW_PHANTOM = {
        name = "View Phantom",
        desc = "Can see the phantom (ghost) showing saved positions in the world",
        default = true,
        category = "DISPLAY"
    },
    VIEW_SED = {
        name = "View Saved Entity Display",
        desc = "Can see the Saved Entity Display (SED) panels on entities and NPCs in the world",
        default = true,
        category = "DISPLAY"
    },

    -- ═══════════════════════════════════════════
    -- ADMINISTRATION
    -- ═══════════════════════════════════════════
    ADMIN_PANEL = {
        name = "Admin Panel Access",
        desc = "Can open the admin panel and manage player permissions",
        default = false,
        category = "ADMIN"
    },
    DEBUG_MENU = {
        name = "Debug & Tools Menu",
        desc = "Can access the Debug & Tools section in the toolgun panel and use debug commands",
        default = false,
        category = "ADMIN"
    },
    RARELOAD_TOGGLE = {
        name = "Global Settings Toggle",
        desc = "Can toggle global addon settings (ConVars) on/off for the entire server",
        default = false,
        category = "ADMIN"
    },
    DATA_CLEANUP = {
        name = "Data Cleanup",
        desc = "Can run data cleanup and maintenance commands to manage server files",
        default = false,
        category = "ADMIN"
    },
}
