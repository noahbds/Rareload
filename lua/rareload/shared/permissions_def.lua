RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}

-- Define all available permissions
RARELOAD.Permissions.DEFS = {
    USE_TOOL = {
        name = "Use Toolgun",
        desc = "Can use the Rareload toolgun",
        default = true
    },
    SAVE_POSITION = {
        name = "Save Position",
        desc = "Can save their position",
        default = true
    },
    LOAD_POSITION = {
        name = "Load Position",
        desc = "Can load their saved position",
        default = true
    },
    KEEP_INVENTORY = {
        name = "Inventory Restore Master Switch",
        desc = "Global gate: if disabled, no inventory restore is allowed (map + global)",
        default = true
    },
    RETAIN_INVENTORY = {
        name = "Map Inventory Restore",
        desc = "Allows restoring map-specific inventory on respawn (requires master switch)",
        default = true
    },
    RETAIN_GLOBAL_INVENTORY = {
        name = "Global Inventory Restore",
        desc = "Allows restoring cross-map global inventory on respawn (requires master switch)",
        default = true
    },
    RETAIN_HEALTH_ARMOR = {
        name = "Retain Health and Armor",
        desc = "Can restore health and armor from saved data",
        default = true
    },
    RETAIN_AMMO = {
        name = "Retain Ammo",
        desc = "Can restore ammo and clips from saved data",
        default = true
    },
    RETAIN_PLAYER_STATES = {
        name = "Retain Player States",
        desc = "Can restore player states (godmode, notarget, noclip, frozen)",
        default = true
    },
    EXECUTE_RARELOAD_COMMANDS = {
        name = "Execute Rareload Commands",
        desc = "Can run Rareload save/restore console commands",
        default = true
    },
    MANAGE_ENTITIES = {
        name = "Manage Entities",
        desc = "Can manage saved entities and NPCs",
        default = false
    },
    ADMIN_PANEL = {
        name = "Admin Panel Access",
        desc =
        "Can access the admin panel and manage permissions without having the 'rareload_admin' permission",
        default = false
    },
    RARELOAD_TOGGLE = {
        name = "Settings Toggle",
        desc = "Can toggle addon settings on/off",
        default = false
    },
    ENTITY_VIEWER = {
        name = "Entity Viewer",
        desc = "Can view entities and npcs saved in the world",
        default = false
    },
    RARELOAD_SPAWN = {
        name = "Rareload Spawn",
        desc = "Allowed to spawn with rareload features",
        default = true
    },
    DEBUG_MENU = {
        name = "Debug Menu",
        desc = "Can access the Debug & Tools section in the toolgun panel",
        default = false
    }
}
