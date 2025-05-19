RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}
RARELOAD.Permissions.PlayerPerms = RARELOAD.Permissions.PlayerPerms or {}

local PERMISSIONS_FILE = "rareload/permissions.json"

function RARELOAD.Permissions.Initialize()
    if not file.Exists("rareload", "DATA") then
        file.CreateDir("rareload")
    end

    RARELOAD.Permissions.Load()

    util.AddNetworkString("RareloadRequestPermissions")
    util.AddNetworkString("RareloadSendPermissions")
    util.AddNetworkString("RareloadUpdatePermissions")
    util.AddNetworkString("RareloadSendPermissionsDefinitions")

    net.Receive("RareloadRequestPermissions", function(len, ply)
        if not RARELOAD.Permissions.HasPermission(ply, "ADMIN_FUNCTIONS") and not ply:IsAdmin() and not ply:IsSuperAdmin() then
            return
        end

        net.Start("RareloadSendPermissions")
        net.WriteTable(RARELOAD.Permissions.PlayerPerms)
        net.Send(ply)

        timer.Simple(0.1, function()
            if IsValid(ply) then
                RARELOAD.Permissions.SendDefinitions(ply)
            end
        end)
    end)

    net.Receive("RareloadUpdatePermissions", function(len, ply)
        if not RARELOAD.Permissions.HasPermission(ply, "ADMIN_FUNCTIONS") and not ply:IsAdmin() and not ply:IsSuperAdmin() then
            print("[Rareload] Permission update rejected: " .. ply:Nick() .. " doesn't have ADMIN_FUNCTIONS permission")
            return
        end

        local targetSteamID = net.ReadString()
        local permName = net.ReadString()
        local value = net.ReadBool()

        if not RARELOAD.Permissions.DEFS[permName] then
            print("[Rareload] Unknown permission: " .. permName)
            return
        end

        print("[Rareload] Permission updated: " .. targetSteamID .. " - " .. permName .. " = " .. tostring(value))

        RARELOAD.Permissions.SetPermission(targetSteamID, permName, value)
        RARELOAD.Permissions.Save()

        for _, admin in ipairs(player.GetAll()) do
            if RARELOAD.Permissions.HasPermission(admin, "ADMIN_FUNCTIONS") or admin:IsAdmin() or admin:IsSuperAdmin() then
                net.Start("RareloadSendPermissions")
                net.WriteTable(RARELOAD.Permissions.PlayerPerms)
                net.Send(admin)
            end
        end
    end)
end

function RARELOAD.Permissions.HasPermission(ply, permName)
    if not IsValid(ply) then return false end

    if ply:IsSuperAdmin() then return true end

    if ply:IsAdmin() and permName == "ADMIN_FUNCTIONS" then return true end

    local steamID = ply:SteamID()

    if RARELOAD.Permissions.PlayerPerms[steamID] and
        RARELOAD.Permissions.PlayerPerms[steamID][permName] ~= nil then
        return RARELOAD.Permissions.PlayerPerms[steamID][permName]
    end

    if RARELOAD.Permissions.DEFS[permName] then
        return RARELOAD.Permissions.DEFS[permName].default
    end

    return false
end

function RARELOAD.Permissions.SetPermission(steamID, permName, value)
    if not RARELOAD.Permissions.PlayerPerms[steamID] then
        RARELOAD.Permissions.PlayerPerms[steamID] = {}
    end

    RARELOAD.Permissions.PlayerPerms[steamID][permName] = value
end

-- using SQLite for permissions storage, it's more safe and prevent 'accident'
function RARELOAD.Permissions.Save()
    if not sql.TableExists("rareload_permissions") then
        sql.Query("CREATE TABLE rareload_permissions (steamid TEXT, permissions TEXT)")
    end

    sql.Query("DELETE FROM rareload_permissions")

    for steamID, perms in pairs(RARELOAD.Permissions.PlayerPerms) do
        local permJson = util.TableToJSON(perms)
        sql.Query("INSERT INTO rareload_permissions (steamid, permissions) VALUES (" ..
            sql.SQLStr(steamID) .. ", " .. sql.SQLStr(permJson) .. ")")
    end

    print("[Rareload] Permissions saved!")
    return true
end

function RARELOAD.Permissions.Load()
    if not sql.TableExists("rareload_permissions") then
        RARELOAD.Permissions.PlayerPerms = {}
        print("[Rareload] No permissions found, created a new one")
        return false
    end

    local results = sql.Query("SELECT * FROM rareload_permissions")
    if results then
        RARELOAD.Permissions.PlayerPerms = {}
        for _, row in ipairs(results) do
            RARELOAD.Permissions.PlayerPerms[row.steamid] = util.JSONToTable(row.permissions)
        end
        print("[Rareload] Permissions loaded successfully!")
        return true
    else
        RARELOAD.Permissions.PlayerPerms = {}
        print("[Rareload] Error loading permissions: " .. (sql.LastError() or "Unknown error"))
        return false
    end
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
