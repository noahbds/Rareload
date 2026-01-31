AddCSLuaFile("rareload/shared/permissions_def.lua")
AddCSLuaFile("rareload/client/admin/admin_panel.lua")
include("rareload/shared/permissions_def.lua")

---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}
RARELOAD.AdminSecurity = RARELOAD.AdminSecurity or {}

local SECURITY_CONFIG = {
    RATE_LIMIT_WINDOW = 60,
    MAX_REQUESTS_PER_WINDOW = 30,
    MAX_PERMISSION_CHANGES_PER_MINUTE = 10,
    
    SESSION_TOKEN_LENGTH = 32,
    SESSION_TIMEOUT = 3600,
    
    ADMIN_PANEL_COOLDOWN = 2,
    PERMISSION_UPDATE_COOLDOWN = 1,
    
    ENABLE_AUDIT_LOG = true,
    MAX_AUDIT_ENTRIES = 1000,
    
    VALIDATE_STEAMID_FORMAT = true,
    VALIDATE_PERMISSION_NAMES = true
}

local RateLimitData = {}
local SessionTokens = {}
local AuditLog = {}
local LastActionTime = {}

if SERVER then
    util.AddNetworkString("RareloadOpenAdminPanel")
    util.AddNetworkString("RareloadNoPermission")
    util.AddNetworkString("RareloadAdminPanelAvailable")
    util.AddNetworkString("RareloadAdminSessionToken")
    util.AddNetworkString("RareloadSecurityViolation")
end

local function GenerateSecureToken(length)
    length = length or SECURITY_CONFIG.SESSION_TOKEN_LENGTH
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local token = ""
    
    for i = 1, length do
        local idx = math.random(1, #chars)
        token = token .. string.sub(chars, idx, idx)
    end
    
    return token .. "_" .. os.time() .. "_" .. math.random(1000, 9999)
end

local function IsValidSteamID(steamID)
    if not SECURITY_CONFIG.VALIDATE_STEAMID_FORMAT then return true end
    if not steamID or type(steamID) ~= "string" then return false end
    
    if string.match(steamID, "^STEAM_%d:%d:%d+$") then return true end
    if string.match(steamID, "^7656119%d+$") and #steamID == 17 then return true end
    
    return false
end

local function IsValidPermissionName(permName)
    if not SECURITY_CONFIG.VALIDATE_PERMISSION_NAMES then return true end
    if not permName or type(permName) ~= "string" then return false end
    
    if RARELOAD.Permissions.DEFS and RARELOAD.Permissions.DEFS[permName] then
        return true
    end
    
    return false
end

local function AddAuditEntry(action, ply, data)
    if not SECURITY_CONFIG.ENABLE_AUDIT_LOG then return end
    
    local entry = {
        timestamp = os.time(),
        action = action,
        playerSteamID = IsValid(ply) and ply:SteamID() or "CONSOLE",
        playerName = IsValid(ply) and ply:Nick() or "Console",
        playerIP = IsValid(ply) and ply:IPAddress() or "N/A",
        data = data or {}
    }
    
    table.insert(AuditLog, 1, entry)
    
    while #AuditLog > SECURITY_CONFIG.MAX_AUDIT_ENTRIES do
        table.remove(AuditLog)
    end
    
    if action == "PERMISSION_CHANGE" or action == "SECURITY_VIOLATION" or action == "DATA_PURGE" then
        local logMsg = string.format("[RARELOAD AUDIT] %s by %s (%s)", 
            action, entry.playerName, entry.playerSteamID)
        if data then
            logMsg = logMsg .. " - " .. util.TableToJSON(data)
        end
        print(logMsg)
        ServerLog(logMsg .. "\n")
    end
end

local function GetRateLimitKey(ply, action)
    if not IsValid(ply) then return nil end
    return ply:SteamID() .. "_" .. action
end

local function CheckRateLimit(ply, action, maxRequests)
    if not IsValid(ply) then return false, "Invalid player" end
    
    maxRequests = maxRequests or SECURITY_CONFIG.MAX_REQUESTS_PER_WINDOW
    local key = GetRateLimitKey(ply, action)
    local currentTime = os.time()
    
    RateLimitData[key] = RateLimitData[key] or { requests = {}, blocked = false }
    local data = RateLimitData[key]
    
    local validRequests = {}
    for _, timestamp in ipairs(data.requests) do
        if currentTime - timestamp < SECURITY_CONFIG.RATE_LIMIT_WINDOW then
            table.insert(validRequests, timestamp)
        end
    end
    data.requests = validRequests
    
    if #data.requests >= maxRequests then
        if not data.blocked then
            data.blocked = true
            AddAuditEntry("RATE_LIMIT_EXCEEDED", ply, { action = action, count = #data.requests })
        end
        return false, "Rate limit exceeded. Please wait."
    end
    
    table.insert(data.requests, currentTime)
    data.blocked = false
    
    return true
end

local function CheckCooldown(ply, action, cooldownTime)
    if not IsValid(ply) then return false end
    
    local key = GetRateLimitKey(ply, action)
    local currentTime = CurTime()
    
    if LastActionTime[key] and (currentTime - LastActionTime[key]) < cooldownTime then
        return false, cooldownTime - (currentTime - LastActionTime[key])
    end
    
    LastActionTime[key] = currentTime
    return true
end

local function CreateSession(ply)
    if not IsValid(ply) then return nil end
    
    local steamID = ply:SteamID()
    local token = GenerateSecureToken()
    
    SessionTokens[steamID] = {
        token = token,
        created = os.time(),
        lastActivity = os.time(),
        ip = ply:IPAddress()
    }
    
    AddAuditEntry("SESSION_CREATED", ply, {})
    
    return token
end

local function ValidateSession(ply, token)
    if not IsValid(ply) then return false, "Invalid player" end
    if not token or token == "" then return false, "No session token" end
    
    local steamID = ply:SteamID()
    local session = SessionTokens[steamID]
    
    if not session then return false, "No active session" end
    if session.token ~= token then return false, "Invalid token" end
    if os.time() - session.created > SECURITY_CONFIG.SESSION_TIMEOUT then
        SessionTokens[steamID] = nil
        return false, "Session expired"
    end
    
    session.lastActivity = os.time()
    return true
end

local function InvalidateSession(ply)
    if not IsValid(ply) then return end
    SessionTokens[ply:SteamID()] = nil
    AddAuditEntry("SESSION_INVALIDATED", ply, {})
end

local function CheckAdminSystemAccess(ply, permission)
    if not IsValid(ply) then return false end
    
    if ply:IsSuperAdmin() then return true end
    
    if RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        if RARELOAD.Permissions.HasPermission(ply, permission) then
            return true
        end
    end
    
    if CAMI and CAMI.PlayerHasAccess then
        local success, result = pcall(CAMI.PlayerHasAccess, ply, "rareload_admin", nil)
        if success and result == true then
            return true
        end
    end
    
    if FAdmin and FAdmin.Access and FAdmin.Access.PlayerHasPrivilege then
        local success, result = pcall(FAdmin.Access.PlayerHasPrivilege, ply, "rareload_admin")
        if success and result == true then
            return true
        end
    end
    
    if sam and sam.player and sam.player.has_permission then
        local success, result = pcall(sam.player.has_permission, ply, "rareload_admin")
        if success and result == true then
            return true
        end
    end
    
    if serverguard and serverguard.player and serverguard.player.HasPermission then
        local success, result = pcall(serverguard.player.HasPermission, ply, "rareload_admin")
        if success and result == true then
            return true
        end
    end
    
    if xAdmin and xAdmin.HasPermission then
        local success, result = pcall(xAdmin.HasPermission, ply, "rareload_admin")
        if success and result == true then
            return true
        end
    end
    
    if sAdmin and sAdmin.checkpermission then
        local success, result = pcall(sAdmin.checkpermission, ply, "rareload_admin")
        if success and result == true then
            return true
        end
    end
    
    return false
end

local function CanOpenAdminPanel(ply)
    return CheckAdminSystemAccess(ply, "ADMIN_PANEL")
end

concommand.Add("rareload_admin", function(ply)
    if not IsValid(ply) then return end
    
    local allowed, errMsg = CheckRateLimit(ply, "admin_panel", 10)
    if not allowed then
        net.Start("RareloadNoPermission")
        net.WriteBool(false)
        net.Send(ply)
        return
    end
    
    local cooldownOk, remaining = CheckCooldown(ply, "admin_panel", SECURITY_CONFIG.ADMIN_PANEL_COOLDOWN)
    if not cooldownOk then
        ply:ChatPrint(string.format("[RARELOAD] Please wait %.1f seconds.", remaining))
        return
    end
    
    if CanOpenAdminPanel(ply) then
        local token = CreateSession(ply)
        
        net.Start("RareloadAdminSessionToken")
        net.WriteString(token)
        net.Send(ply)
        
        net.Start("RareloadOpenAdminPanel")
        net.Send(ply)
        
        AddAuditEntry("ADMIN_PANEL_OPENED", ply, {})
    else
        net.Start("RareloadNoPermission")
        net.WriteBool(false)
        net.Send(ply)
        
        AddAuditEntry("ADMIN_PANEL_DENIED", ply, {})
        print("[RARELOAD] Player " .. ply:Nick() .. " attempted to open admin panel without permission.")
    end
end)

hook.Add("PlayerInitialSpawn", "RareloadAdminPanelInitMessage", function(ply)
    timer.Simple(5, function()
        if IsValid(ply) and CanOpenAdminPanel(ply) then
            net.Start("RareloadAdminPanelAvailable")
            net.WriteString(RARELOAD.version or "1.0")
            net.Send(ply)
        end
    end)
end)

hook.Add("PlayerDisconnected", "RareloadInvalidateSession", function(ply)
    if IsValid(ply) then
        InvalidateSession(ply)
    end
end)

if CAMI and CAMI.RegisterPrivilege then
    CAMI.RegisterPrivilege({
        Name = "rareload_admin",
        MinAccess = "superadmin",
        Description = "Access to Rareload Admin Panel"
    })
end

concommand.Add("rareload_purge_admin_data", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        ply:ChatPrint("[RARELOAD] Only SuperAdmins can purge admin data.")
        AddAuditEntry("PURGE_DENIED", ply, {})
        return
    end
    
    if not args[1] or args[1] ~= "CONFIRM" then
        local msg = "[RARELOAD] WARNING: This will permanently delete all admin data!"
        local msg2 = "[RARELOAD] Type 'rareload_purge_admin_data CONFIRM' to proceed."
        
        if IsValid(ply) then
            ply:ChatPrint(msg)
            ply:ChatPrint(msg2)
        else
            print(msg)
            print(msg2)
        end
        return
    end
    
    AddAuditEntry("DATA_PURGE", ply, { confirmed = true })
    
    if not IsValid(ply) then
        print("[RARELOAD] Purging admin data from console...")
    else
        print("[RARELOAD] " .. ply:Nick() .. " is purging admin data...")
        ply:ChatPrint("[RARELOAD] Purging admin data from SQL database...")
    end
    
    local tablesDropped = 0
    local errors = {}
    
    local adminTables = {
        "rareload_permissions",
        "rareload_permissions_backup",
        "rareload_player_data"
    }
    
    sql.Begin()
    
    local success = true
    for _, tableName in ipairs(adminTables) do
        if sql.TableExists(tableName) then
            local result = sql.Query("DROP TABLE " .. tableName)
            if result == false then
                table.insert(errors, "Failed to drop table " .. tableName .. ": " .. sql.LastError())
                success = false
            else
                tablesDropped = tablesDropped + 1
                print("[RARELOAD] Dropped table: " .. tableName)
            end
        else
            print("[RARELOAD] Table " .. tableName .. " does not exist, skipping...")
        end
    end
    
    if success then
        sql.Commit()
        
        if RARELOAD.Permissions then
            RARELOAD.Permissions.PlayerPerms = {}
        end
        
        SessionTokens = {}
        RateLimitData = {}
        
        local backupFiles = file.Find("rareload/permissions_backup*.json", "DATA")
        local backupFilesRemoved = 0
        for _, backupFile in ipairs(backupFiles) do
            file.Delete("rareload/" .. backupFile)
            backupFilesRemoved = backupFilesRemoved + 1
            print("[RARELOAD] Removed backup file: " .. backupFile)
        end
        
        local message = string.format(
            "[RARELOAD] Admin data purge completed! Dropped %d SQL tables and removed %d backup files.",
            tablesDropped, backupFilesRemoved)
        print(message)
        
        if IsValid(ply) then
            ply:ChatPrint(message)
            ply:ChatPrint("[RARELOAD] All admin permissions and player data have been permanently deleted.")
        end
        
        for _, admin in ipairs(player.GetAll()) do
            if IsValid(admin) and admin:IsAdmin() and admin ~= ply then
                admin:ChatPrint("[RARELOAD] WARNING: Admin data has been purged by " ..
                    (IsValid(ply) and ply:Nick() or "Console"))
            end
        end
    else
        sql.Rollback()
        local errorMessage = "[RARELOAD] Admin data purge failed! Errors: " .. table.concat(errors, ", ")
        print(errorMessage)
        
        if IsValid(ply) then
            ply:ChatPrint(errorMessage)
        end
    end
end)

concommand.Add("rareload_audit_log", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        ply:ChatPrint("[RARELOAD] Only SuperAdmins can view the audit log.")
        return
    end
    
    local count = tonumber(args[1]) or 20
    count = math.Clamp(count, 1, 100)
    
    print("\n[RARELOAD] === AUDIT LOG (Last " .. count .. " entries) ===")
    
    for i = 1, math.min(count, #AuditLog) do
        local entry = AuditLog[i]
        print(string.format("[%s] %s - %s (%s) - %s",
            os.date("%Y-%m-%d %H:%M:%S", entry.timestamp),
            entry.action,
            entry.playerName,
            entry.playerSteamID,
            util.TableToJSON(entry.data)
        ))
    end
    
    print("[RARELOAD] === END OF LOG ===\n")
end)

RARELOAD.AdminSecurity = {
    CheckRateLimit = CheckRateLimit,
    CheckCooldown = CheckCooldown,
    ValidateSession = ValidateSession,
    IsValidSteamID = IsValidSteamID,
    IsValidPermissionName = IsValidPermissionName,
    AddAuditEntry = AddAuditEntry,
    CanOpenAdminPanel = CanOpenAdminPanel,
    CheckAdminSystemAccess = CheckAdminSystemAccess,
    Config = SECURITY_CONFIG
}

print("[RARELOAD] Admin security module loaded")
