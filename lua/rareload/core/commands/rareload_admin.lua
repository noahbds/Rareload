return function(ply)
    if not IsValid(ply) then
        print("[RARELOAD] This command can only be run by a player.")
        return
    end

    local canOpen = false

    if ply:IsSuperAdmin() then
        canOpen = true
    elseif RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        canOpen = RARELOAD.Permissions.HasPermission(ply, "ADMIN_PANEL")
    elseif CAMI and CAMI.PlayerHasAccess then
        canOpen = CAMI.PlayerHasAccess(ply, "rareload_admin") == true
    end

    if canOpen then
        net.Start("RareloadOpenAdminPanel")
        net.Send(ply)
    else
        net.Start("RareloadNoPermission")
        net.WriteBool(false)
        print("[RARELOAD] Player " .. ply:Nick() .. " attempted to open admin panel without permission.")
        net.Send(ply)
    end
end
