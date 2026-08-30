-- ─────────────────────────────────────────────────────────────────────────────
-- Rareload access check (shared)
--
-- Rareload no longer ships its own per-player permission system (SQL store, admin
-- GUI, per-player grant sync). Admin-only actions defer to the server's admin mod
-- through CAMI (ULX / ServerGuard / SAM / …) with a plain IsAdmin fallback; every
-- other "permission" is a normal per-player feature that the player's own settings
-- decide. This file is the thin compatibility shim the rest of the code calls, so
-- existing CheckPermission / Permissions.HasPermission call sites keep working.
-- ─────────────────────────────────────────────────────────────────────────────

RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}

-- The only actions that require admin rights. Everything else is a per-player
-- feature governed by settings, so it is allowed for everyone here.
local ADMIN_PERMS = {
    ADMIN_PANEL       = true,
    MANAGE_ENTITIES   = true,
    DEBUG_MENU        = true,
    DATA_CLEANUP      = true,
    ANTI_STUCK_CONFIG = true,
    TELEPORT_PLAYER   = true,
    RARELOAD_TOGGLE   = true,
}
RARELOAD.Permissions.ADMIN_PERMS = ADMIN_PERMS

-- Is this player a Rareload admin? Superadmin, or granted the CAMI privilege
-- `rareload_admin` by the server's admin mod, or a plain admin as a fallback.
function RARELOAD.IsAdmin(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    if CAMI and CAMI.PlayerHasAccess and CAMI.PlayerHasAccess(ply, "rareload_admin") == true then
        return true
    end
    return ply:IsAdmin()
end

-- Admin actions require IsAdmin; every other feature is allowed (settings decide
-- whether it actually happens).
function RARELOAD.CheckPermission(ply, permName)
    if not IsValid(ply) then return false end
    if ADMIN_PERMS[permName] then return RARELOAD.IsAdmin(ply) end
    return true
end

-- Back-compat alias used across the codebase.
RARELOAD.Permissions.HasPermission = RARELOAD.CheckPermission

-- Register the privilege so admin mods (ULX/ServerGuard/SAM) can grant it.
if SERVER and CAMI and CAMI.RegisterPrivilege then
    CAMI.RegisterPrivilege({
        Name = "rareload_admin",
        MinAccess = "superadmin",
        Description = "Access to Rareload admin actions",
    })
end
