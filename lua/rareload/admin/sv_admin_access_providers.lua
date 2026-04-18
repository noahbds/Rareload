if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AdminSecurity = RARELOAD.AdminSecurity or {}

local AdminSecurity = RARELOAD.AdminSecurity

local function SafeProviderAccess(func, ...)
    local ok, result = pcall(func, ...)
    return ok and result == true
end

function AdminSecurity.CheckExternalAdminProviders(ply, privilegeName)
    if not IsValid(ply) then return false end

    privilegeName = privilegeName or "rareload_admin"

    if CAMI and CAMI.PlayerHasAccess and SafeProviderAccess(CAMI.PlayerHasAccess, ply, privilegeName, nil) then
        return true
    end

    if FAdmin and FAdmin.Access and FAdmin.Access.PlayerHasPrivilege and
        SafeProviderAccess(FAdmin.Access.PlayerHasPrivilege, ply, privilegeName) then
        return true
    end

    if sam and sam.player and sam.player.has_permission and
        SafeProviderAccess(sam.player.has_permission, ply, privilegeName) then
        return true
    end

    if serverguard and serverguard.player and serverguard.player.HasPermission and
        SafeProviderAccess(serverguard.player.HasPermission, ply, privilegeName) then
        return true
    end

    if xAdmin and xAdmin.HasPermission and SafeProviderAccess(xAdmin.HasPermission, ply, privilegeName) then
        return true
    end

    if sAdmin and sAdmin.checkpermission and SafeProviderAccess(sAdmin.checkpermission, ply, privilegeName) then
        return true
    end

    return false
end

return AdminSecurity
