RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}

-- Define all available permissions
RARELOAD.Permissions.DEFS = {
    USE_TOOL = {
        name = "Use Toolgun",
        desc = "Can use the Rareload toolgun",
        default = false
    },
    SAVE_POSITION = {
        name = "Save Position",
        desc = "Can save their position",
        default = false
    },
    LOAD_POSITION = {
        name = "Load Position",
        desc = "Can load their saved position",
        default = false
    },
    KEEP_INVENTORY = {
        name = "Keep Inventory",
        desc = "Can keep their inventory when reloading/dying",
        default = false
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
        default = false
    }
}
