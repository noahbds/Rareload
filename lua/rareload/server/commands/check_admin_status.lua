return function(ply)
    if not IsValid(ply) then
        print("[RARELOAD] This command can only be run by a player.")
        return
    end

    local adminStatus = "Player"
    local hasAdminPerms = false

    if ply:IsSuperAdmin() then
        adminStatus = "SuperAdmin"
        hasAdminPerms = true
    elseif ply:IsAdmin() then
        adminStatus = "Admin"
        hasAdminPerms = true
    elseif RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        if RARELOAD.Permissions.HasPermission(ply, "ADMIN_FUNCTIONS") then
            adminStatus = "Rareload Admin"
            hasAdminPerms = true
        end
    end

    print("[RARELOAD] " .. ply:Nick() .. " status: " .. adminStatus)

    Admin = hasAdminPerms

    return hasAdminPerms
end
