RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}
RARELOAD.Permissions.PlayerPerms = RARELOAD.Permissions.PlayerPerms or {}
RARELOAD.Permissions.PlayerRoles = RARELOAD.Permissions.PlayerRoles or {}

local PERMISSIONS_FILE = "rareload/permissions.json"

local permissionCache = {}
local roleCache = {}
local cacheTimeout = 30 -- seconds

local function IsValidPermission(permName)
    return RARELOAD.Permissions.DEFS and RARELOAD.Permissions.DEFS[permName] ~= nil
end

local function IsValidRole(roleName)
    return RARELOAD.Permissions.ROLES and RARELOAD.Permissions.ROLES[roleName] ~= nil
end

local function IsValidPlayer(ply)
    return IsValid(ply) and ply:IsPlayer()
end

function RARELOAD.Permissions.Initialize()
    if not file.Exists("rareload", "DATA") then
        file.CreateDir("rareload")
    end

    local loadSuccess = RARELOAD.Permissions.Load()
    if not loadSuccess then
        print("[RARELOAD ERROR] Failed to load permissions, using defaults")
    end

    local networkStrings = {
        "RareloadRequestPermissions",
        "RareloadSendPermissions",
        "RareloadUpdatePermissions",
        "RareloadSendPermissionsDefinitions",
        "RareloadRequestRoles",
        "RareloadSendRoles",
        "RareloadUpdateRole",
        "RareloadGetPlayerRole"
    }

    for _, str in ipairs(networkStrings) do
        util.AddNetworkString(str)
    end

    timer.Create("RareloadPermissionCacheCleanup", cacheTimeout, 0, function()
        permissionCache = {}
        roleCache = {}
    end)

    net.Receive("RareloadRequestPermissions", function(len, ply)
        if not IsValidPlayer(ply) or not RARELOAD.Permissions.HasPermission(ply, "ADMIN_FUNCTIONS") then
            return
        end

        net.Start("RareloadSendPermissions")
        net.WriteTable(RARELOAD.Permissions.PlayerPerms or {})
        net.Send(ply)

        timer.Simple(0.1, function()
            if IsValidPlayer(ply) then
                RARELOAD.Permissions.SendDefinitions(ply)
            end
        end)
    end)

    net.Receive("RareloadUpdatePermissions", function(len, ply)
        if not IsValidPlayer(ply) or not RARELOAD.Permissions.HasPermission(ply, "MANAGE_PERMISSIONS") then
            print("[RARELOAD] Permission update rejected: " ..
                (IsValid(ply) and ply:Nick() or "Invalid player") .. " lacks MANAGE_PERMISSIONS")
            return
        end

        local targetSteamID = net.ReadString()
        local permName = net.ReadString()
        local value = net.ReadBool()

        if not targetSteamID or not permName or not IsValidPermission(permName) then
            print("[RARELOAD] Invalid permission update request")
            return
        end

        local permData = RARELOAD.Permissions.DEFS[permName]
        if permData.adminOnly and not ply:IsSuperAdmin() then
            print("[RARELOAD] Non-superadmin attempted to modify admin-only permission: " .. permName)
            return
        end

        print("[RARELOAD] Permission updated: " .. targetSteamID .. " - " .. permName .. " = " .. tostring(value))

        if RARELOAD.Permissions.SetPermission(targetSteamID, permName, value) then
            RARELOAD.Permissions.Save()

            for _, admin in ipairs(player.GetAll()) do
                if RARELOAD.Permissions.HasPermission(admin, "ADMIN_FUNCTIONS") then
                    net.Start("RareloadSendPermissions")
                    net.WriteTable(RARELOAD.Permissions.PlayerPerms)
                    net.Send(admin)
                end
            end
        end
    end)

    net.Receive("RareloadRequestRoles", function(len, ply)
        if not IsValidPlayer(ply) or not RARELOAD.Permissions.HasPermission(ply, "ADMIN_FUNCTIONS") then
            return
        end

        net.Start("RareloadSendRoles")
        net.WriteTable(RARELOAD.Permissions.PlayerRoles or {})
        net.Send(ply)
    end)

    net.Receive("RareloadUpdateRole", function(len, ply)
        if not IsValidPlayer(ply) or not RARELOAD.Permissions.HasPermission(ply, "MANAGE_PERMISSIONS") then
            print("[RARELOAD] Role update rejected: " ..
                (IsValid(ply) and ply:Nick() or "Invalid player") .. " lacks MANAGE_PERMISSIONS")
            return
        end

        local targetSteamID = net.ReadString()
        local roleName = net.ReadString()

        if not targetSteamID or not roleName then
            print("[RARELOAD] Invalid role update request")
            return
        end

        if roleName ~= "NONE" and not IsValidRole(roleName) then
            print("[RARELOAD] Invalid role name: " .. roleName)
            return
        end

        if roleName ~= "NONE" and RARELOAD.Permissions.ROLES[roleName] then
            local role = RARELOAD.Permissions.ROLES[roleName]
            if role.permissions == "*" and not ply:IsSuperAdmin() then
                print("[RARELOAD] Non-superadmin attempted to assign admin role")
                return
            end
        end

        RARELOAD.Permissions.SetPlayerRole(targetSteamID, roleName)
        RARELOAD.Permissions.Save()

        RARELOAD.Permissions.ClearPlayerCache(targetSteamID)

        print("[RARELOAD] Role updated: " .. targetSteamID .. " assigned role: " .. roleName)
    end)
end

function RARELOAD.Permissions.HasPermission(ply, permName)
    if not IsValidPlayer(ply) then return false end
    if ply:IsSuperAdmin() then return true end

    local steamID = ply:SteamID()
    local cacheKey = steamID .. "_" .. permName

    if permissionCache[cacheKey] and permissionCache[cacheKey].time > CurTime() - cacheTimeout then
        return permissionCache[cacheKey].value
    end

    local hasPermission = false

    if not IsValidPermission(permName) then
        print("[RARELOAD] Warning: Unknown permission requested: " .. tostring(permName))
        permissionCache[cacheKey] = { value = false, time = CurTime() }
        return false
    end

    local permDef = RARELOAD.Permissions.DEFS[permName]

    if permDef.adminOnly and not (ply:IsAdmin() or ply:IsSuperAdmin()) then
        hasPermission = false
    elseif RARELOAD.Permissions.PlayerRoles[steamID] then
        local roleName = RARELOAD.Permissions.PlayerRoles[steamID]
        hasPermission = RARELOAD.Permissions.RoleHasPermission(roleName, permName)
    elseif RARELOAD.Permissions.PlayerPerms[steamID] and RARELOAD.Permissions.PlayerPerms[steamID][permName] ~= nil then
        hasPermission = RARELOAD.Permissions.PlayerPerms[steamID][permName]
    else
        hasPermission = permDef.default or false
    end

    if hasPermission and permDef.dependencies and #permDef.dependencies > 0 then
        local visited = { [permName] = true }
        hasPermission = RARELOAD.Permissions.CheckDependencies(ply, permDef.dependencies, visited)
    end

    permissionCache[cacheKey] = {
        value = hasPermission,
        time = CurTime()
    }

    return hasPermission
end

function RARELOAD.Permissions.CheckDependencies(ply, dependencies, visited)
    for _, depPerm in ipairs(dependencies) do
        if visited[depPerm] then
            print("[RARELOAD] Warning: Circular dependency detected for permission: " .. depPerm)
            return false
        end

        if not RARELOAD.Permissions.HasPermission(ply, depPerm) then
            return false
        end
    end
    return true
end

function RARELOAD.Permissions.SetPlayerRole(steamID, roleName)
    if not steamID then
        print("[RARELOAD] Error: Invalid SteamID for role assignment")
        return false
    end

    if roleName == "NONE" or roleName == "" then
        RARELOAD.Permissions.PlayerRoles[steamID] = nil
    elseif IsValidRole(roleName) then
        RARELOAD.Permissions.PlayerRoles[steamID] = roleName
        RARELOAD.Permissions.PlayerPerms[steamID] = nil
    else
        print("[RARELOAD] Warning: Unknown role: " .. tostring(roleName))
        return false
    end

    RARELOAD.Permissions.ClearPlayerCache(steamID)
    return true
end

function RARELOAD.Permissions.GetPlayerRole(steamID)
    if not steamID then return "GUEST" end
    return RARELOAD.Permissions.PlayerRoles[steamID] or "GUEST"
end

function RARELOAD.Permissions.RoleHasPermission(roleName, permName)
    if not IsValidRole(roleName) or not IsValidPermission(permName) then
        return false
    end

    local cacheKey = roleName .. "_" .. permName
    if roleCache[cacheKey] and roleCache[cacheKey].time > CurTime() - cacheTimeout then
        return roleCache[cacheKey].value
    end

    local role = RARELOAD.Permissions.ROLES[roleName]
    local hasPermission = false

    if role.permissions == "*" then
        hasPermission = true
    elseif type(role.permissions) == "table" then
        for _, perm in ipairs(role.permissions) do
            if perm == permName then
                hasPermission = true
                break
            end
        end
    end

    roleCache[cacheKey] = { value = hasPermission, time = CurTime() }
    return hasPermission
end

function RARELOAD.Permissions.SetPermission(steamID, permName, value)
    if not steamID or not IsValidPermission(permName) then
        print("[RARELOAD] Error: Invalid parameters for SetPermission")
        return false
    end

    if RARELOAD.Permissions.PlayerRoles[steamID] then
        RARELOAD.Permissions.PlayerRoles[steamID] = nil
    end

    if not RARELOAD.Permissions.PlayerPerms[steamID] then
        RARELOAD.Permissions.PlayerPerms[steamID] = {}
    end

    RARELOAD.Permissions.PlayerPerms[steamID][permName] = value

    RARELOAD.Permissions.ClearPlayerCache(steamID)

    return true
end

function RARELOAD.Permissions.ClearPlayerCache(steamID)
    for cacheKey, _ in pairs(permissionCache) do
        if string.StartWith(cacheKey, steamID .. "_") then
            permissionCache[cacheKey] = nil
        end
    end
end

function RARELOAD.Permissions.GetPlayerPermissions(steamID)
    local permissions = {}
    local role = RARELOAD.Permissions.GetPlayerRole(steamID)

    if role and IsValidRole(role) then
        local roleData = RARELOAD.Permissions.ROLES[role]
        if roleData.permissions == "*" then
            for permName, _ in pairs(RARELOAD.Permissions.DEFS or {}) do
                permissions[permName] = true
            end
        elseif type(roleData.permissions) == "table" then
            for _, permName in ipairs(roleData.permissions) do
                if IsValidPermission(permName) then
                    permissions[permName] = true
                end
            end
        end
    end

    if RARELOAD.Permissions.PlayerPerms[steamID] then
        for permName, value in pairs(RARELOAD.Permissions.PlayerPerms[steamID]) do
            if IsValidPermission(permName) then
                permissions[permName] = value
            end
        end
    end

    return permissions
end

function RARELOAD.Permissions.Save()
    local success = pcall(function()
        if not sql.TableExists("rareload_permissions") then
            local result = sql.Query("CREATE TABLE rareload_permissions (steamid TEXT PRIMARY KEY, permissions TEXT)")
            if result == false then
                error("Failed to create permissions table: " .. sql.LastError())
            end
        end

        sql.Query("DELETE FROM rareload_permissions")

        for steamID, perms in pairs(RARELOAD.Permissions.PlayerPerms or {}) do
            local permJson = util.TableToJSON(perms)
            local result = sql.Query("INSERT INTO rareload_permissions (steamid, permissions) VALUES (" ..
                sql.SQLStr(steamID) .. ", " .. sql.SQLStr(permJson) .. ")")
            if result == false then
                error("Failed to save permissions for " .. steamID .. ": " .. sql.LastError())
            end
        end

        if not sql.TableExists("rareload_roles") then
            local result = sql.Query("CREATE TABLE rareload_roles (steamid TEXT PRIMARY KEY, role TEXT)")
            if result == false then
                error("Failed to create roles table: " .. sql.LastError())
            end
        end

        sql.Query("DELETE FROM rareload_roles")

        for steamID, role in pairs(RARELOAD.Permissions.PlayerRoles or {}) do
            local result = sql.Query("INSERT INTO rareload_roles (steamid, role) VALUES (" ..
                sql.SQLStr(steamID) .. ", " .. sql.SQLStr(role) .. ")")
            if result == false then
                error("Failed to save role for " .. steamID .. ": " .. sql.LastError())
            end
        end
    end)

    if success then
        print("[RARELOAD] Permissions and roles saved successfully!")
        return true
    else
        print("[RARELOAD] Error saving permissions: " .. sql.LastError())
        return false
    end
end

function RARELOAD.Permissions.Load()
    local success = pcall(function()
        if sql.TableExists("rareload_permissions") then
            local results = sql.Query("SELECT * FROM rareload_permissions")
            if results then
                RARELOAD.Permissions.PlayerPerms = {}
                for _, row in ipairs(results) do
                    local perms = util.JSONToTable(row.permissions)
                    if perms then
                        local validatedPerms = {}
                        for permName, value in pairs(perms) do
                            if IsValidPermission(permName) then
                                validatedPerms[permName] = value
                            else
                                print("[RARELOAD] Warning: Removing invalid permission '" ..
                                    tostring(permName) .. "' for " .. row.steamid)
                            end
                        end
                        RARELOAD.Permissions.PlayerPerms[row.steamid] = validatedPerms
                    end
                end
                print("[RARELOAD] Individual permissions loaded successfully!")
            else
                print("[RARELOAD] Error loading permissions: " .. (sql.LastError() or "Unknown error"))
            end
        else
            RARELOAD.Permissions.PlayerPerms = {}
            print("[RARELOAD] No individual permissions found, created new table")
        end

        if sql.TableExists("rareload_roles") then
            local results = sql.Query("SELECT * FROM rareload_roles")
            if results then
                RARELOAD.Permissions.PlayerRoles = {}
                for _, row in ipairs(results) do
                    if IsValidRole(row.role) then
                        RARELOAD.Permissions.PlayerRoles[row.steamid] = row.role
                    else
                        print("[RARELOAD] Warning: Invalid role '" ..
                            tostring(row.role) .. "' for " .. row.steamid .. ", removing")
                    end
                end
                print("[RARELOAD] Roles loaded successfully!")
            else
                print("[RARELOAD] Error loading roles: " .. (sql.LastError() or "Unknown error"))
            end
        else
            RARELOAD.Permissions.PlayerRoles = {}
            print("[RARELOAD] No roles found, created new table")
        end
    end)

    return success
end

function RARELOAD.Permissions.SendDefinitions(ply)
    if not IsValid(ply) then return end

    net.Start("RareloadSendPermissionsDefinitions")
    net.WriteTable(RARELOAD.Permissions.DEFS)
    net.Send(ply)

    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Sent permission definitions to " .. ply:Nick())
    end
end

hook.Add("PlayerInitialSpawn", "RareloadSendPermissionDefs", function(ply)
    timer.Simple(2, function()
        if IsValid(ply) and (ply:IsAdmin() or ply:IsSuperAdmin()) then
            RARELOAD.Permissions.SendDefinitions(ply)
        end
    end)
end)

function RARELOAD.Permissions.GetPermissionsByCategory()
    local categories = {}

    for permName, permData in pairs(RARELOAD.Permissions.DEFS) do
        local category = permData.category or "OTHER"
        if not categories[category] then
            categories[category] = {}
        end
        categories[category][permName] = permData
    end

    return categories
end

function RARELOAD.Permissions.ValidatePermissionDependencies(steamID)
    local permissions = RARELOAD.Permissions.GetPlayerPermissions(steamID)
    local issues = {}

    for permName, hasPermission in pairs(permissions) do
        if hasPermission then
            local permData = RARELOAD.Permissions.DEFS[permName]
            if permData and permData.dependencies then
                for _, depPerm in ipairs(permData.dependencies) do
                    if not permissions[depPerm] then
                        table.insert(issues, {
                            permission = permName,
                            missing_dependency = depPerm
                        })
                    end
                end
            end
        end
    end

    return issues
end

concommand.Add("rareload_perm_give", function(ply, cmd, args)
    if not IsValidPlayer(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then
        if IsValidPlayer(ply) then
            ply:ChatPrint("[RARELOAD] Admin access required.")
        end
        return
    end

    if #args < 3 then
        ply:ChatPrint("[RARELOAD] Usage: rareload_perm_give <player> <permission> <1/0>")
        return
    end

    local targetPly = nil
    local searchTerm = args[1]

    if tonumber(searchTerm) then
        targetPly = player.GetByID(tonumber(searchTerm))
    end

    if not IsValid(targetPly) then
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(searchTerm), 1, true) then
                targetPly = p
                break
            end
        end
    end

    if not IsValidPlayer(targetPly) then
        ply:ChatPrint("[RARELOAD] Player not found: " .. searchTerm)
        return
    end

    local permName = string.upper(args[2])
    local value = tobool(args[3])

    if not IsValidPermission(permName) then
        ply:ChatPrint("[RARELOAD] Unknown permission: " .. permName)
        return
    end

    local permData = RARELOAD.Permissions.DEFS[permName]
    if permData.adminOnly and not ply:IsSuperAdmin() then
        ply:ChatPrint("[RARELOAD] You cannot modify admin-only permissions.")
        return
    end

    if RARELOAD.Permissions.SetPermission(targetPly:SteamID(), permName, value) then
        RARELOAD.Permissions.Save()
        ply:ChatPrint("[RARELOAD] Permission " ..
            permName .. " set to " .. tostring(value) .. " for " .. targetPly:Nick())
    else
        ply:ChatPrint("[RARELOAD] Failed to set permission.")
    end
end)

concommand.Add("rareload_role_set", function(ply, cmd, args)
    if not IsValidPlayer(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then
        if IsValidPlayer(ply) then
            ply:ChatPrint("[RARELOAD] Admin access required.")
        end
        return
    end

    if #args < 2 then
        ply:ChatPrint("[RARELOAD] Usage: rareload_role_set <player> <role>")
        ply:ChatPrint("[RARELOAD] Available roles: " ..
            table.concat(table.GetKeys(RARELOAD.Permissions.ROLES or {}), ", "))
        return
    end

    local targetPly = nil
    local searchTerm = args[1]

    if tonumber(searchTerm) then
        targetPly = player.GetByID(tonumber(searchTerm))
    end

    if not IsValid(targetPly) then
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(searchTerm), 1, true) then
                targetPly = p
                break
            end
        end
    end

    if not IsValidPlayer(targetPly) then
        ply:ChatPrint("[RARELOAD] Player not found: " .. searchTerm)
        return
    end

    local roleName = string.upper(args[2])

    if roleName ~= "NONE" and not IsValidRole(roleName) then
        ply:ChatPrint("[RARELOAD] Unknown role: " .. roleName)
        ply:ChatPrint("[RARELOAD] Available roles: " ..
            table.concat(table.GetKeys(RARELOAD.Permissions.ROLES or {}), ", "))
        return
    end

    if roleName ~= "NONE" and RARELOAD.Permissions.ROLES[roleName] then
        local role = RARELOAD.Permissions.ROLES[roleName]
        if role.permissions == "*" and not ply:IsSuperAdmin() then
            ply:ChatPrint("[RARELOAD] You cannot assign admin roles.")
            return
        end
    end

    if RARELOAD.Permissions.SetPlayerRole(targetPly:SteamID(), roleName) then
        RARELOAD.Permissions.Save()
        ply:ChatPrint("[RARELOAD] Role " .. roleName .. " assigned to " .. targetPly:Nick())
    else
        ply:ChatPrint("[RARELOAD] Failed to set role.")
    end
end)
