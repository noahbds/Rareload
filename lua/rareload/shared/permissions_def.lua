RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}

RARELOAD.Permissions.CATEGORIES = {
    BASIC = {
        name = "Basic Features",
        description = "Core Rareload functionality for all users",
        order = 1
    },
    TOOLS = {
        name = "Tool Access",
        description = "Access to toolgun and advanced interfaces",
        order = 2
    },
    SAVE_LOAD = {
        name = "Save & Load",
        description = "Position and data persistence capabilities",
        order = 3
    },
    INVENTORY = {
        name = "Inventory Management",
        description = "Weapon and item retention features",
        order = 4
    },
    WORLD = {
        name = "World Interaction",
        description = "Entity, NPC, and world state management",
        order = 5
    },
    AUTOMATION = {
        name = "Automation",
        description = "Automatic features and bulk operations",
        order = 6
    },
    ADMIN = {
        name = "Administration",
        description = "Server control and administrative functions",
        order = 7
    }
}

RARELOAD.Permissions.DEFS = {
    RARELOAD_SPAWN = {
        name = "Rareload Spawn",
        desc = "Allow spawning with the rareload system",
        category = "BASIC",
        default = true,
        dependencies = {},
        adminOnly = false,
        priority = 1
    },
    USE_TOOL = {
        name = "Use Toolgun",
        desc = "Can use the Rareload toolgun for saving/loading positions",
        category = "TOOLS",
        default = false,
        dependencies = { "RARELOAD_SPAWN" },
        adminOnly = false,
        priority = 2
    },

    SAVE_POSITION = {
        name = "Save Position",
        desc = "Can manually save their position and state",
        category = "SAVE_LOAD",
        default = false,
        dependencies = { "RARELOAD_SPAWN" },
        adminOnly = false,
        priority = 3
    },
    LOAD_POSITION = {
        name = "Load Position",
        desc = "Can load and teleport to their saved positions",
        category = "SAVE_LOAD",
        default = false,
        dependencies = { "SAVE_POSITION" },
        adminOnly = false,
        priority = 4
    },
    SAVE_OTHERS_POSITION = {
        name = "Save Others' Positions",
        desc = "Can save positions for other players (admin feature)",
        category = "SAVE_LOAD",
        default = false,
        dependencies = { "SAVE_POSITION", "ADMIN_FUNCTIONS" },
        adminOnly = true,
        priority = 5
    },
    LOAD_OTHERS_POSITION = {
        name = "Load Others' Positions",
        desc = "Can teleport other players to saved positions",
        category = "SAVE_LOAD",
        default = false,
        dependencies = { "LOAD_POSITION", "ADMIN_FUNCTIONS" },
        adminOnly = true,
        priority = 6
    },

    AUTOSAVE = {
        name = "Auto Save",
        desc = "Can use automatic position saving features",
        category = "AUTOMATION",
        default = false,
        dependencies = { "SAVE_POSITION" },
        adminOnly = false,
        priority = 7
    },
    AUTOSAVE_CUSTOM_INTERVAL = {
        name = "Custom Auto Save Interval",
        desc = "Can set custom auto-save intervals (otherwise uses server default)",
        category = "AUTOMATION",
        default = false,
        dependencies = { "AUTOSAVE" },
        adminOnly = false,
        priority = 8
    },

    KEEP_INVENTORY = {
        name = "Keep Inventory",
        desc = "Can retain their inventory when respawning",
        category = "INVENTORY",
        default = false,
        dependencies = { "RARELOAD_SPAWN" },
        adminOnly = false,
        priority = 9
    },
    KEEP_AMMO = {
        name = "Keep Ammo",
        desc = "Can retain ammunition counts on respawn",
        category = "INVENTORY",
        default = false,
        dependencies = { "KEEP_INVENTORY" },
        adminOnly = false,
        priority = 10
    },
    KEEP_HEALTH_ARMOR = {
        name = "Keep Health & Armor",
        desc = "Can retain health and armor values on respawn",
        category = "INVENTORY",
        default = false,
        dependencies = { "RARELOAD_SPAWN" },
        adminOnly = false,
        priority = 11
    },
    GLOBAL_INVENTORY = {
        name = "Global Inventory",
        desc = "Can use inventory across different maps",
        category = "INVENTORY",
        default = false,
        dependencies = { "KEEP_INVENTORY" },
        adminOnly = false,
        priority = 12
    },
    UNLIMITED_INVENTORY = {
        name = "Unlimited Inventory",
        desc = "Can bypass inventory restrictions and limits",
        category = "INVENTORY",
        default = false,
        dependencies = { "KEEP_INVENTORY", "ADMIN_FUNCTIONS" },
        adminOnly = true,
        priority = 13
    },

    MANAGE_ENTITIES = {
        name = "Manage Entities",
        desc = "Can save and restore entities in the world",
        category = "WORLD",
        default = false,
        dependencies = { "SAVE_POSITION" },
        adminOnly = false,
        priority = 14
    },
    MANAGE_NPCS = {
        name = "Manage NPCs",
        desc = "Can save and restore NPCs with their states",
        category = "WORLD",
        default = false,
        dependencies = { "MANAGE_ENTITIES" },
        adminOnly = false,
        priority = 15
    },
    MANAGE_VEHICLES = {
        name = "Manage Vehicles",
        desc = "Can save and restore vehicles with their properties",
        category = "WORLD",
        default = false,
        dependencies = { "MANAGE_ENTITIES" },
        adminOnly = false,
        priority = 16
    },
    ENTITY_VIEWER = {
        name = "Entity Viewer",
        desc = "Can view and inspect saved entities in the world",
        category = "WORLD",
        default = false,
        dependencies = { "MANAGE_ENTITIES" },
        adminOnly = false,
        priority = 17
    },
    RESPAWN_ENTITIES = {
        name = "Respawn Entities",
        desc = "Can manually respawn deleted entities from saves",
        category = "WORLD",
        default = false,
        dependencies = { "MANAGE_ENTITIES" },
        adminOnly = false,
        priority = 18
    },

    BULK_OPERATIONS = {
        name = "Bulk Operations",
        desc = "Can perform bulk save/load operations for efficiency",
        category = "AUTOMATION",
        default = false,
        dependencies = { "SAVE_POSITION", "LOAD_POSITION" },
        adminOnly = false,
        priority = 19
    },
    SCHEDULED_SAVES = {
        name = "Scheduled Saves",
        desc = "Can create scheduled automatic saves with custom triggers",
        category = "AUTOMATION",
        default = false,
        dependencies = { "AUTOSAVE" },
        adminOnly = false,
        priority = 20
    },

    ADMIN_FUNCTIONS = {
        name = "Admin Functions",
        desc = "Can access admin panel and basic administrative features",
        category = "ADMIN",
        default = false,
        dependencies = {},
        adminOnly = true,
        priority = 100
    },
    MANAGE_PERMISSIONS = {
        name = "Manage Permissions",
        desc = "Can modify permissions for other players and assign roles",
        category = "ADMIN",
        default = false,
        dependencies = { "ADMIN_FUNCTIONS" },
        adminOnly = true,
        priority = 101
    },
    SERVER_COMMANDS = {
        name = "Server Commands",
        desc = "Can execute server-wide rareload commands and configurations",
        category = "ADMIN",
        default = false,
        dependencies = { "ADMIN_FUNCTIONS" },
        adminOnly = true,
        priority = 102
    },
    OVERRIDE_LIMITS = {
        name = "Override Limits",
        desc = "Can bypass save limits, cooldowns, and other restrictions",
        category = "ADMIN",
        default = false,
        dependencies = { "ADMIN_FUNCTIONS" },
        adminOnly = true,
        priority = 103
    },
    DEBUG_ACCESS = {
        name = "Debug Access",
        desc = "Can access debug information and advanced troubleshooting tools",
        category = "ADMIN",
        default = false,
        dependencies = { "ADMIN_FUNCTIONS" },
        adminOnly = true,
        priority = 104
    },
    FORCE_SAVE_LOAD = {
        name = "Force Save/Load",
        desc = "Can force save/load operations for any player",
        category = "ADMIN",
        default = false,
        dependencies = { "ADMIN_FUNCTIONS", "SAVE_OTHERS_POSITION" },
        adminOnly = true,
        priority = 105
    }
}

RARELOAD.Permissions.ROLES = {
    GUEST = {
        name = "Guest",
        description = "Minimal access for new or temporary users",
        permissions = { "RARELOAD_SPAWN" },
        color = Color(180, 180, 180),
        priority = 1
    },
    PLAYER = {
        name = "Player",
        description = "Standard player with basic Rareload features",
        permissions = { "RARELOAD_SPAWN", "SAVE_POSITION", "LOAD_POSITION", "KEEP_INVENTORY" },
        color = Color(100, 150, 255),
        priority = 2
    },
    VIP = {
        name = "VIP",
        description = "Premium player with extended features and automation",
        permissions = {
            "RARELOAD_SPAWN", "SAVE_POSITION", "LOAD_POSITION", "KEEP_INVENTORY",
            "AUTOSAVE", "KEEP_AMMO", "KEEP_HEALTH_ARMOR", "USE_TOOL", "GLOBAL_INVENTORY",
            "AUTOSAVE_CUSTOM_INTERVAL"
        },
        color = Color(255, 215, 0),
        priority = 3
    },
    TRUSTED = {
        name = "Trusted",
        description = "Trusted player with world management capabilities",
        permissions = {
            "RARELOAD_SPAWN", "SAVE_POSITION", "LOAD_POSITION", "KEEP_INVENTORY",
            "AUTOSAVE", "KEEP_AMMO", "KEEP_HEALTH_ARMOR", "USE_TOOL", "GLOBAL_INVENTORY",
            "MANAGE_ENTITIES", "MANAGE_NPCS", "ENTITY_VIEWER", "BULK_OPERATIONS"
        },
        color = Color(0, 255, 150),
        priority = 4
    },
    MODERATOR = {
        name = "Moderator",
        description = "Moderator with advanced features and limited admin access",
        permissions = {
            "RARELOAD_SPAWN", "SAVE_POSITION", "LOAD_POSITION", "KEEP_INVENTORY",
            "AUTOSAVE", "KEEP_AMMO", "KEEP_HEALTH_ARMOR", "USE_TOOL", "GLOBAL_INVENTORY",
            "MANAGE_ENTITIES", "MANAGE_NPCS", "MANAGE_VEHICLES", "ENTITY_VIEWER",
            "RESPAWN_ENTITIES", "BULK_OPERATIONS", "SCHEDULED_SAVES"
        },
        color = Color(255, 165, 0),
        priority = 5
    },
    ADMIN = {
        name = "Administrator",
        description = "Full administrator access with all permissions",
        permissions = "*",
        color = Color(255, 100, 100),
        priority = 6
    }
}
