RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}
RARELOAD.Permissions.PlayerPerms = RARELOAD.Permissions.PlayerPerms or {}
RARELOAD.Permissions.DEFS = RARELOAD.Permissions.DEFS or {}
RARELOAD.OfflinePlayerData = RARELOAD.OfflinePlayerData or {}

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
    chat.AddText(Color(50, 255, 50),
        "Rareload Admin Panel available. Type !rareloadadmin or use the console command rareload_admin to open it.")
end)

hook.Add("OnPlayerChat", "RareloadAdminPanelChatCommand", function(ply, text)
    if text:lower() == "!rareloadadmin" and ply == LocalPlayer() then
        RunConsoleCommand("rareload_admin")
        return true
    end
end)
