-- Global Admin System for Rareload
RARELOAD = RARELOAD or {}
RARELOAD.Admin = RARELOAD.Admin or {}

-- Admin data storage
RARELOAD.Admin.admins = RARELOAD.Admin.admins or {}
RARELOAD.Admin.roles = RARELOAD.Admin.roles or {}
RARELOAD.Admin.rolePermissions = RARELOAD.Admin.rolePermissions or {}

-- Addon prefix for commands to avoid conflicts
RARELOAD.Admin.CommandPrefix = "rareload_"

-- Permission levels with more granular control
RARELOAD.Admin.Permissions = {
    NONE = 0,
    USER = 1,
    MODERATOR = 2,
    ADMIN = 3,
    SUPER_ADMIN = 4,
    OWNER = 5
}

-- Permission names for display
RARELOAD.Admin.PermissionNames = {
    [0] = "None",
    [1] = "User",
    [2] = "Moderator",
    [3] = "Admin",
    [4] = "Super Admin",
    [5] = "Owner"
}

-- Default roles with their permissions
RARELOAD.Admin.DefaultRoles = {
    ["user"] = {
        name = "User",
        level = RARELOAD.Admin.Permissions.USER,
        permissions = {
            "respawn_teleport",
            "respawn_save",
            "respawn_clear",
            "inventory_save",
            "inventory_restore",
            "settings_view"
        }
    },
    ["moderator"] = {
        name = "Moderator",
        level = RARELOAD.Admin.Permissions.MODERATOR,
        permissions = {
            "respawn_teleport",
            "respawn_save",
            "respawn_clear",
            "respawn_override",
            "inventory_save",
            "inventory_restore",
            "inventory_clear",
            "settings_view",
            "view_logs"
        }
    },
    ["admin"] = {
        name = "Admin",
        level = RARELOAD.Admin.Permissions.ADMIN,
        permissions = {
            "respawn_teleport",
            "respawn_save",
            "respawn_clear",
            "respawn_override",
            "respawn_force",
            "inventory_save",
            "inventory_restore",
            "inventory_clear",
            "inventory_override",
            "settings_view",
            "settings_change",
            "view_logs",
            "admin_menu",
            "admin_commands"
        }
    },
    ["superadmin"] = {
        name = "Super Admin",
        level = RARELOAD.Admin.Permissions.SUPER_ADMIN,
        permissions = {
            "respawn_teleport",
            "respawn_save",
            "respawn_clear",
            "respawn_override",
            "respawn_force",
            "inventory_save",
            "inventory_restore",
            "inventory_clear",
            "inventory_override",
            "inventory_global",
            "settings_view",
            "settings_change",
            "settings_reset",
            "view_logs",
            "admin_menu",
            "admin_commands",
            "manage_admins",
            "debug_mode",
            "debug_level",
            "debug_status",
            "debug_clean",
            "debug_format",
            "debug_flush"
        }
    },
    ["owner"] = {
        name = "Owner",
        level = RARELOAD.Admin.Permissions.OWNER,
        permissions = "*" -- All permissions
    }
}

-- Feature permissions with better organization
RARELOAD.Admin.Features = {
    -- Core features
    ["addon_enable"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Enable/Disable Addon", category = "Core" },
    ["auto_save"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "Auto Save", category = "Core" },
    ["save_inventory"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "Save Inventory", category = "Core" },
    ["save_global_inventory"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Save Global Inventory", category = "Core" },
    ["save_ammo"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "Save Ammo", category = "Core" },
    ["save_health_armor"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "Save Health and Armor", category = "Core" },
    ["save_entities"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Save Entities", category = "Core" },
    ["save_npcs"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Save NPCs", category = "Core" },

    -- Respawn features
    ["respawn_teleport"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "Teleport to Saved Position", category = "Respawn" },
    ["respawn_save"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "Save Respawn Position", category = "Respawn" },
    ["respawn_clear"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "Clear Saved Position", category = "Respawn" },
    ["respawn_override"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Override Player Respawn", category = "Respawn" },
    ["respawn_force"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Force Player Respawn", category = "Respawn" },
    ["respawn_history"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "View Respawn History", category = "Respawn" },

    -- Inventory management
    ["inventory_save"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "Save Inventory", category = "Inventory" },
    ["inventory_restore"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "Restore Inventory", category = "Inventory" },
    ["inventory_clear"] = { min_level = RARELOAD.Admin.Permissions.MODERATOR, name = "Clear Inventory", category = "Inventory" },
    ["inventory_override"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Override Player Inventory", category = "Inventory" },
    ["inventory_global"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Manage Global Inventory", category = "Inventory" },

    -- Entity management
    ["entity_save"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Save Map Entities", category = "Entity" },
    ["entity_restore"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Restore Map Entities", category = "Entity" },
    ["entity_clear"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Clear Saved Entities", category = "Entity" },
    ["entity_blacklist"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Manage Entity Blacklist", category = "Entity" },

    -- Debug features
    ["debug_mode"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Debug Mode", category = "Debug" },
    ["debug_level"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Debug Level", category = "Debug" },
    ["debug_status"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Debug Status", category = "Debug" },
    ["debug_clean"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Clean Debug Logs", category = "Debug" },
    ["debug_format"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Debug Format", category = "Debug" },
    ["debug_flush"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Debug Flush", category = "Debug" },

    -- Admin features
    ["admin_menu"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Admin Menu", category = "Admin" },
    ["manage_admins"] = { min_level = RARELOAD.Admin.Permissions.SUPER_ADMIN, name = "Manage Admins", category = "Admin" },
    ["view_logs"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "View Logs", category = "Admin" },
    ["admin_commands"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Use Admin Commands", category = "Admin" },

    -- Settings features
    ["settings_view"] = { min_level = RARELOAD.Admin.Permissions.USER, name = "View Settings", category = "Settings" },
    ["settings_change"] = { min_level = RARELOAD.Admin.Permissions.ADMIN, name = "Change Settings", category = "Settings" },
    ["settings_reset"] = { min_level = RARELOAD.Admin.Permissions.SUPER_ADMIN, name = "Reset Settings", category = "Settings" }
}

-- ULX integration with better role mapping
RARELOAD.Admin.ULXGroups = {
    ["user"] = "user",
    ["operator"] = "moderator",
    ["admin"] = "admin",
    ["superadmin"] = "superadmin"
}

-- Command registration with better organization
RARELOAD.Admin.Commands = {
    -- Core commands
    ["rareload_rareload"] = { permission = "addon_enable", description = "Toggle addon", category = "Core" },
    ["rareload_spawn_mode"] = { permission = "respawn_override", description = "Toggle spawn mode", category = "Core" },
    ["rareload_auto_save"] = { permission = "auto_save", description = "Toggle auto save", category = "Core" },
    ["rareload_retain_inventory"] = { permission = "inventory_save", description = "Toggle inventory retention", category = "Core" },
    ["rareload_retain_health_armor"] = { permission = "save_health_armor", description = "Toggle health/armor retention", category = "Core" },
    ["rareload_retain_ammo"] = { permission = "save_ammo", description = "Toggle ammo retention", category = "Core" },
    ["rareload_retain_vehicle_state"] = { permission = "entity_save", description = "Toggle vehicle state retention", category = "Core" },
    ["rareload_retain_map_npcs"] = { permission = "npc_save", description = "Toggle NPC retention", category = "Core" },
    ["rareload_retain_map_entities"] = { permission = "entity_save", description = "Toggle entity retention", category = "Core" },
    ["rareload_retain_vehicles"] = { permission = "entity_save", description = "Toggle vehicle retention", category = "Core" },
    ["rareload_retain_global_inventory"] = { permission = "save_global_inventory", description = "Toggle global inventory", category = "Core" },

    -- Slider commands
    ["set_auto_save_interval"] = { permission = "settings_change", description = "Set auto save interval", category = "Settings" },
    ["set_max_distance"] = { permission = "settings_change", description = "Set max distance", category = "Settings" },
    ["set_angle_tolerance"] = { permission = "settings_change", description = "Set angle tolerance", category = "Settings" },
    ["set_history_size"] = { permission = "settings_change", description = "Set history size", category = "Settings" },

    -- Save commands
    ["save_position"] = { permission = "respawn_save", description = "Save position", category = "Respawn" },
    ["save_bot_position"] = { permission = "respawn_save", description = "Save bot position", category = "Respawn" },

    -- Debug commands
    ["rareload_debug_toggle"] = { permission = "debug_mode", description = "Toggle debug mode", category = "Debug" },
    ["rareload_debug_level"] = { permission = "debug_level", description = "Set debug level", category = "Debug" },
    ["rareload_debug_status"] = { permission = "debug_status", description = "Show debug status", category = "Debug" },
    ["rareload_debug_clean"] = { permission = "debug_clean", description = "Clean debug logs", category = "Debug" },
    ["rareload_debug_format"] = { permission = "debug_format", description = "Set debug format", category = "Debug" },
    ["rareload_debug_flush"] = { permission = "debug_flush", description = "Flush debug buffer", category = "Debug" }
}

-- File paths for data persistence
local ADMIN_FILE = "rareload/admins.json"
local ROLES_FILE = "rareload/roles.json"

-- Load admin data from file
function RARELOAD.Admin.LoadAdmins()
    if file.Exists(ADMIN_FILE, "DATA") then
        local data = file.Read(ADMIN_FILE, "DATA")
        if data then
            local success, result = pcall(util.JSONToTable, data)
            if success then
                RARELOAD.Admin.admins = result
                print("[RARELOAD Admin] Loaded " .. table.Count(RARELOAD.Admin.admins) .. " admins.")
            else
                print("[RARELOAD Admin] Error parsing admin data: " .. tostring(result))
            end
        end
    end
end

-- Save admin data to file
function RARELOAD.Admin.SaveAdmins()
    local data = util.TableToJSON(RARELOAD.Admin.admins, true)
    file.Write(ADMIN_FILE, data)
    print("[RARELOAD Admin] Saved " .. table.Count(RARELOAD.Admin.admins) .. " admins.")
end

-- Load roles from file
function RARELOAD.Admin.LoadRoles()
    if file.Exists(ROLES_FILE, "DATA") then
        local data = file.Read(ROLES_FILE, "DATA")
        if data then
            local success, result = pcall(util.JSONToTable, data)
            if success then
                RARELOAD.Admin.roles = result
                print("[RARELOAD Admin] Loaded " .. table.Count(RARELOAD.Admin.roles) .. " roles.")
            else
                print("[RARELOAD Admin] Error parsing roles data: " .. tostring(result))
            end
        end
    end

    -- Initialize with default roles if none exist
    if table.IsEmpty(RARELOAD.Admin.roles) then
        RARELOAD.Admin.roles = table.Copy(RARELOAD.Admin.DefaultRoles)
        RARELOAD.Admin.SaveRoles()
    end
end

-- Save roles to file
function RARELOAD.Admin.SaveRoles()
    local data = util.TableToJSON(RARELOAD.Admin.roles, true)
    file.Write(ROLES_FILE, data)
    print("[RARELOAD Admin] Saved " .. table.Count(RARELOAD.Admin.roles) .. " roles.")
end

-- Get player's role
function RARELOAD.Admin.GetPlayerRole(ply)
    if not IsValid(ply) then return "user" end

    -- Check ULX groups first
    if ULib and ULib.ucl then
        local user = ULib.ucl.users[ply:SteamID()]
        if user and RARELOAD.Admin.ULXGroups[user.group] then
            return RARELOAD.Admin.ULXGroups[user.group]
        end
    end

    -- Fall back to our admin system
    local level = RARELOAD.Admin.admins[ply:SteamID()]
    if level then
        for role, data in pairs(RARELOAD.Admin.roles) do
            if data.level == level then
                return role
            end
        end
    end

    return "user"
end

-- Get player's permission level
function RARELOAD.Admin.GetPermissionLevel(ply)
    if not IsValid(ply) then return RARELOAD.Admin.Permissions.NONE end

    local role = RARELOAD.Admin.GetPlayerRole(ply)
    return RARELOAD.Admin.roles[role].level
end

-- Check if player has permission for a feature
function RARELOAD.Admin.HasPermission(ply, feature)
    if not IsValid(ply) then return false end
    if not RARELOAD.Admin.Features[feature] then return false end

    local role = RARELOAD.Admin.GetPlayerRole(ply)
    local roleData = RARELOAD.Admin.roles[role]

    -- Owner has all permissions
    if roleData.permissions == "*" then return true end

    -- Check if the role has the specific permission
    return table.HasValue(roleData.permissions, feature)
end

-- Add an admin by SteamID with role
function RARELOAD.Admin.AddAdmin(steamid, role)
    if not steamid or not role then return false end
    if not RARELOAD.Admin.roles[role] then return false end

    RARELOAD.Admin.admins[steamid] = RARELOAD.Admin.roles[role].level
    RARELOAD.Admin.SaveAdmins()
    print("[RARELOAD Admin] Added admin: " .. steamid .. " with role: " .. role)
    return true
end

-- Remove an admin by SteamID
function RARELOAD.Admin.RemoveAdmin(steamid)
    if not steamid then return false end
    RARELOAD.Admin.admins[steamid] = nil
    RARELOAD.Admin.SaveAdmins()
    print("[RARELOAD Admin] Removed admin: " .. steamid)
    return true
end

-- Update admin role
function RARELOAD.Admin.UpdateAdminRole(steamid, newRole)
    if not steamid or not newRole then return false end
    if not RARELOAD.Admin.roles[newRole] then return false end

    RARELOAD.Admin.admins[steamid] = RARELOAD.Admin.roles[newRole].level
    RARELOAD.Admin.SaveAdmins()
    print("[RARELOAD Admin] Updated admin role for " .. steamid .. " to: " .. newRole)
    return true
end

-- Get all features a player has access to
function RARELOAD.Admin.GetPlayerFeatures(ply)
    if not IsValid(ply) then return {} end
    local role = RARELOAD.Admin.GetPlayerRole(ply)
    local roleData = RARELOAD.Admin.roles[role]
    local features = {}

    if roleData.permissions == "*" then
        return RARELOAD.Admin.Features
    end

    for _, feature in ipairs(roleData.permissions) do
        if RARELOAD.Admin.Features[feature] then
            features[feature] = RARELOAD.Admin.Features[feature]
        end
    end

    return features
end

-- Get features by category
function RARELOAD.Admin.GetFeaturesByCategory()
    local categories = {}

    for feature, data in pairs(RARELOAD.Admin.Features) do
        if not categories[data.category] then
            categories[data.category] = {}
        end
        categories[data.category][feature] = data
    end

    return categories
end

-- Get commands by category
function RARELOAD.Admin.GetCommandsByCategory()
    local categories = {}

    for cmd, data in pairs(RARELOAD.Admin.Commands) do
        if not categories[data.category] then
            categories[data.category] = {}
        end
        categories[data.category][cmd] = data
    end

    return categories
end

-- Check if player can manage another player
function RARELOAD.Admin.CanManagePlayer(manager, target)
    if not IsValid(manager) or not IsValid(target) then return false end
    if manager == target then return false end

    local managerRole = RARELOAD.Admin.GetPlayerRole(manager)
    local targetRole = RARELOAD.Admin.GetPlayerRole(target)

    return RARELOAD.Admin.roles[managerRole].level > RARELOAD.Admin.roles[targetRole].level
end

-- Get player's available commands
function RARELOAD.Admin.GetPlayerCommands(ply)
    local commands = {}
    for cmd, data in pairs(RARELOAD.Admin.Commands) do
        if RARELOAD.Admin.HasPermission(ply, data.permission) then
            commands[cmd] = data
        end
    end
    return commands
end

-- Add hooks for permission checks
hook.Add("PlayerSay", "RARELOAD_AdminCommands", function(ply, text)
    if text:sub(1, 1) == "!" then
        local cmd = text:sub(2):lower()
        -- Use addon-specific prefix for commands
        if cmd == "rareload" and RARELOAD.Admin.HasPermission(ply, "admin_menu") then
            RunConsoleCommand(RARELOAD.Admin.CommandPrefix .. "admin_menu")
            return ""
        elseif cmd == "rareload_respawn" and RARELOAD.Admin.HasPermission(ply, "respawn_teleport") then
            RunConsoleCommand(RARELOAD.Admin.CommandPrefix .. "respawn")
            return ""
        elseif cmd == "rareload_inventory" and RARELOAD.Admin.HasPermission(ply, "inventory_restore") then
            RunConsoleCommand(RARELOAD.Admin.CommandPrefix .. "inventory_restore")
            return ""
        elseif cmd == "rareload_help" then
            -- Show available commands to the player
            local commands = RARELOAD.Admin.GetPlayerCommands(ply)
            if table.Count(commands) > 0 then
                chat.AddText(Color(65, 145, 255), "[Rareload] Available commands:")
                for cmd, data in pairs(commands) do
                    chat.AddText(Color(245, 245, 245), "!" .. cmd:gsub(RARELOAD.Admin.CommandPrefix, ""),
                        Color(180, 180, 190), " - " .. data.description)
                end
            else
                chat.AddText(Color(255, 70, 70), "[Rareload] You don't have access to any commands.")
            end
            return ""
        end
    end
end)

-- Add compatibility hooks
hook.Add("Initialize", "RARELOAD_Compatibility", function()
    -- Check for potential conflicts with other addons
    local conflicts = {}

    -- Check for other admin systems
    if hook.GetTable()["PlayerSay"]["RARELOAD_AdminCommands"] then
        table.insert(conflicts, "Another addon is using the PlayerSay hook for admin commands")
    end

    -- Check for other respawn systems
    if hook.GetTable()["PlayerSpawn"]["RARELOAD_Respawn"] then
        table.insert(conflicts, "Another addon is using the PlayerSpawn hook for respawn")
    end

    -- Check for other inventory systems
    if hook.GetTable()["PlayerLoadout"]["RARELOAD_Inventory"] then
        table.insert(conflicts, "Another addon is using the PlayerLoadout hook for inventory")
    end

    -- Log conflicts if any found
    if #conflicts > 0 then
        print("[Rareload] Potential conflicts detected:")
        for _, conflict in ipairs(conflicts) do
            print("[Rareload] - " .. conflict)
        end
        print("[Rareload] Please check your addons for compatibility issues.")
    end
end)

-- Register commands with ULX
if ULib and ULib.ucl then
    for cmd, data in pairs(RARELOAD.Admin.Commands) do
        ULib.addCommand(cmd, data.permission, function(ply, cmd, args)
            if not RARELOAD.Admin.HasPermission(ply, data.permission) then
                ply:ChatPrint("[RARELOAD] You don't have permission to use this command.")
                return
            end
            RunConsoleCommand(cmd, unpack(args))
        end, data.description)
    end
end

-- Load admins and roles on initialization
hook.Add("Initialize", "RARELOAD_LoadAdmins", function()
    RARELOAD.Admin.LoadRoles()
    RARELOAD.Admin.LoadAdmins()
end)
