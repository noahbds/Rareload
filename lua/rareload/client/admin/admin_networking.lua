RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}
RARELOAD.Permissions.PlayerPerms = RARELOAD.Permissions.PlayerPerms or {}
RARELOAD.Permissions.DEFS = RARELOAD.Permissions.DEFS or {}
RARELOAD.Permissions.MyPermissions = RARELOAD.Permissions.MyPermissions or {}
RARELOAD.OfflinePlayerData = RARELOAD.OfflinePlayerData or {}

-- Client-side permission check that uses server-synced permissions
function RARELOAD.Permissions.HasPermission(ply, permName)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end

    -- For the local player, use the resolved permissions synced from the server
    if ply == LocalPlayer() then
        if RARELOAD.Permissions.MyPermissions[permName] ~= nil then
            return RARELOAD.Permissions.MyPermissions[permName]
        end
    end

    -- For other players (admin panel view), use the full permissions table
    local steamID = ply:SteamID()
    if RARELOAD.Permissions.PlayerPerms[steamID] and
        RARELOAD.Permissions.PlayerPerms[steamID][permName] ~= nil then
        return RARELOAD.Permissions.PlayerPerms[steamID][permName]
    end

    -- Fall back to permission defaults
    if RARELOAD.Permissions.DEFS[permName] then
        return RARELOAD.Permissions.DEFS[permName].default
    end

    return ply:IsAdmin()
end

-- Receive own resolved permissions from server (sent on join + permission changes)
net.Receive("RareloadSyncOwnPermissions", function()
    local perms = net.ReadTable()
    if perms then
        RARELOAD.Permissions.MyPermissions = perms
    end
end)

net.Receive("RareloadSendPermissionsDefinitions", function()
    RARELOAD.Permissions.DEFS = net.ReadTable()

    if RARELOAD.AdminPanel.Frame and IsValid(RARELOAD.AdminPanel.Frame) then
        local steamID = RARELOAD.AdminPanel.Frame.selectedPlayer
        if steamID then
            RARELOAD.AdminPanel.Frame:SelectPlayer(steamID)
        end
    end

    print("[Rareload] Permission definitions loaded: " .. table.Count(RARELOAD.Permissions.DEFS) .. " permissions")
end)

net.Receive("RareloadSendOfflinePlayerData", function()
    RARELOAD.OfflinePlayerData = net.ReadTable()

    if RARELOAD.AdminPanel.Frame and IsValid(RARELOAD.AdminPanel.Frame) then
        RARELOAD.AdminPanel.Frame:RefreshPlayerList()
    end

    print("[Rareload] Offline player data loaded: " .. table.Count(RARELOAD.OfflinePlayerData) .. " players")
end)

net.Receive("RareloadSendPermissions", function()
    RARELOAD.Permissions.PlayerPerms = net.ReadTable()
    if RARELOAD.AdminPanel.Frame and RARELOAD.AdminPanel.Frame.selectedPlayer then
        RARELOAD.AdminPanel.Frame:SelectPlayer(RARELOAD.AdminPanel.Frame.selectedPlayer)
    end
end)

net.Receive("RareloadOpenAdminPanel", function()
    if RARELOAD.AdminPanel and RARELOAD.AdminPanel.Open then
        RARELOAD.AdminPanel.Open()
    end
end)

net.Receive("RareloadNoPermission", function()
    chat.AddText(Color(255, 50, 50), "You don't have permission to open the Rareload admin panel.")
end)

net.Receive("RareloadAdminPanelAvailable", function()
    local version = net.ReadString()
    RARELOAD.version = version
end)

hook.Add("OnPlayerChat", "RareloadAdminPanelChatCommand", function(ply, text)
    if text:lower() == "!rareloadadmin" and ply == LocalPlayer() then
        RunConsoleCommand("rareload_admin")
        return true
    end
end)
