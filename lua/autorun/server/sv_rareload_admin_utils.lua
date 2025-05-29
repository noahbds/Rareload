AddCSLuaFile("rareload/shared/permissions_def.lua")
AddCSLuaFile("rareload/client/admin_panel.lua")
include("rareload/shared/permissions_def.lua")

---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}

util.AddNetworkString("RareloadOpenAdminPanel")
util.AddNetworkString("RareloadNoPermission")
util.AddNetworkString("RareloadAdminPanelAvailable")

local adminPanelPermCache = {}
local function canOpenAdminPanel(ply)
    if not IsValid(ply) then return false end

    local steamID = ply:SteamID()

    if adminPanelPermCache[steamID] and adminPanelPermCache[steamID].time > (CurTime() - 30) then
        return adminPanelPermCache[steamID].value
    end

    if ply:IsAdmin() or ply:IsSuperAdmin() then
        adminPanelPermCache[steamID] = { value = true, time = CurTime() }
        return true
    end

    local hasPermission = false
    if RARELOAD.Permissions and RARELOAD.Permissions.PlayerPerms then
        local perms = RARELOAD.Permissions.PlayerPerms[steamID]
        if perms and perms["can_use_admin_panel"] then
            hasPermission = true
        end
    end

    adminPanelPermCache[steamID] = { value = hasPermission, time = CurTime() }
    return hasPermission
end

timer.Create("RareloadAdminPanelPermCacheCleanup", 300, 0, function()
    adminPanelPermCache = {}
end)

concommand.Add("rareload_admin", function(ply)
    if canOpenAdminPanel(ply) then
        net.Start("RareloadOpenAdminPanel")
        net.Send(ply)
    else
        net.Start("RareloadNoPermission")
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
