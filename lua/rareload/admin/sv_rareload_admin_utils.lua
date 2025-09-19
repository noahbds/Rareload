AddCSLuaFile("rareload/shared/permissions_def.lua")
AddCSLuaFile("rareload/client/admin/admin_panel.lua")
include("rareload/shared/permissions_def.lua")

---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}

if SERVER then
    util.AddNetworkString("RareloadOpenAdminPanel")
    util.AddNetworkString("RareloadNoPermission")
    util.AddNetworkString("RareloadAdminPanelAvailable")
end

local function canOpenAdminPanel(ply)
    if not IsValid(ply) then return false end

    if ply:IsSuperAdmin() then return true end

    if RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        if RARELOAD.Permissions.HasPermission(ply, "ADMIN_PANEL") then
            return true
        end
    end

    -- CAMI (ULX, etc.)
    if CAMI and CAMI.PlayerHasAccess then
        local hasAccess = CAMI.PlayerHasAccess(ply, "rareload_admin")
        if hasAccess ~= nil then
            return hasAccess == true
        end
    end

    -- FAdmin (DarkRP)
    if FAdmin and FAdmin.Access and FAdmin.Access.PlayerHasPrivilege then
        local hasFAdmin = FAdmin.Access.PlayerHasPrivilege(ply, "rareload_admin")
        if hasFAdmin ~= nil then
            return hasFAdmin == true
        end
    end

    -- SAM (Simple Admin Mod)
    if sam and sam.player and sam.player.has_permission then
        local hasSAM = sam.player.has_permission(ply, "rareload_admin")
        if hasSAM ~= nil then
            return hasSAM == true
        end
    end

    -- ServerGuard
    if serverguard and serverguard.player and serverguard.player.HasPermission then
        local hasSG = serverguard.player.HasPermission(ply, "rareload_admin")
        if hasSG ~= nil then
            return hasSG == true
        end
    end

    -- xAdmin
    if xAdmin and xAdmin.HasPermission then
        local hasXAdmin = xAdmin.HasPermission(ply, "rareload_admin")
        if hasXAdmin ~= nil then
            return hasXAdmin == true
        end
    end

    -- No permission found
    return false
end

concommand.Add("rareload_admin", function(ply)
    if canOpenAdminPanel(ply) then
        net.Start("RareloadOpenAdminPanel")
        net.Send(ply)
    else
        net.Start("RareloadNoPermission")
        net.WriteBool(false)
        print("[RARELOAD] Player " .. ply:Nick() .. " attempted to open admin panel without permission.")
        net.Send(ply)
    end
end)

hook.Add("PlayerInitialSpawn", "RareloadAdminPanelInitMessage", function(ply)
    timer.Simple(5, function()
        if IsValid(ply) and canOpenAdminPanel(ply) then
            net.Start("RareloadAdminPanelAvailable")
            net.WriteString(RARELOAD.version or "1.0")
            net.Send(ply)
        end
    end)
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
        return
    end

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

        local backupFiles = file.Find("rareload/permissions_backup*.json", "DATA")
        local backupFilesRemoved = 0
        for _, backupFile in ipairs(backupFiles) do
            file.Delete("rareload/" .. backupFile)
            backupFilesRemoved = backupFilesRemoved + 1
            print("[RARELOAD] Removed backup file: " .. backupFile)
        end

        local message = string.format(
            "[RARELOAD] Admin data purge completed successfully! Dropped %d SQL tables and removed %d backup files.",
            tablesDropped, backupFilesRemoved)
        print(message)

        if IsValid(ply) then
            ply:ChatPrint(message)
            ply:ChatPrint("[RARELOAD] All admin permissions and player data have been permanently deleted.")
            ply:ChatPrint("[RARELOAD] You may need to restart the server or reload the addon for full effect.")
        else
            print("[RARELOAD] All admin permissions and player data have been permanently deleted.")
            print("[RARELOAD] You may need to restart the server or reload the addon for full effect.")
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
