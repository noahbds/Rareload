-- ─────────────────────────────────────────────────────────────────────────────
-- Rareload access check (shared)
--
-- Rareload has no permission system of its own. Every gated action is a CAMI
-- privilege, so the server's admin mod (ULX / SAM / ServerGuard / FAdmin / …) lists
-- them and an owner grants/revokes them per user-group in that mod's own UI.
--
--   • Admin privileges (tier admin/superadmin) gate admin-only actions.
--   • Feature privileges (tier "user") gate per-player features — everyone has them
--     by default, so default behaviour is unchanged; an owner restricts a group only
--     if they want to. A feature happens when the player's SETTING is on AND their
--     group HAS the privilege.
--
-- When an admin mod (CAMI) is present it is the sole authority — no IsSuperAdmin
-- bypass, so ULX grant/revoke actually applies (even to superadmins; re-grant from
-- server console if you lock yourself out). With no admin mod we fall back by tier.
-- ─────────────────────────────────────────────────────────────────────────────

RARELOAD = RARELOAD or {}
RARELOAD.Permissions = RARELOAD.Permissions or {}

local UMBRELLA = "rareload_admin" -- having this privilege grants every Rareload action

-- CAMI privilege -> { default access tier, description shown in admin mods }.
local PRIV = {
    [UMBRELLA]                    = { "superadmin", "Full access to all Rareload admin actions" },

    -- Admin actions
    rareload_manage_objects       = { "admin",      "Edit, flag or delete objects saved in any Save Timeline entry" },
    rareload_teleport             = { "admin",      "Use Rareload teleport-to-coordinates" },
    rareload_debug                = { "admin",      "Open the Debug & Tools menu and run Rareload debug commands" },
    rareload_anti_stuck           = { "admin",      "Configure anti-stuck methods on the server" },
    rareload_data_cleanup         = { "superadmin", "Run Rareload data cleanup / purge / cache-reset commands" },
    rareload_settings             = { "superadmin", "Change global Rareload settings (Configure Parameters)" },

    -- Per-player features (everyone by default; restrict a group to lock it down)
    rareload_use_tool             = { "user", "Use the Rareload toolgun" },
    rareload_save                 = { "user", "Save a Rareload position" },
    rareload_restore              = { "user", "Restore a saved Rareload position on spawn" },
    rareload_save_inventory       = { "user", "Include weapons/inventory when saving" },
    rareload_restore_inventory    = { "user", "Restore saved weapons/inventory on spawn" },
    rareload_global_inventory     = { "user", "Use the cross-map global inventory" },
    rareload_save_ammo            = { "user", "Include ammo when saving" },
    rareload_restore_ammo         = { "user", "Restore saved ammo on spawn" },
    rareload_save_health_armor    = { "user", "Include health & armor when saving" },
    rareload_restore_health_armor = { "user", "Restore saved health & armor on spawn" },
    rareload_save_appearance      = { "user", "Include appearance (model/color/bodygroups) when saving" },
    rareload_restore_appearance   = { "user", "Restore saved appearance on spawn" },
    rareload_save_states          = { "user", "Include player states (god/noclip/frozen/notarget) when saving" },
    rareload_restore_states       = { "user", "Restore saved player states on spawn" },
    rareload_save_entities        = { "user", "Include owned entities when saving" },
    rareload_restore_entities     = { "user", "Restore saved entities on spawn" },
    rareload_save_npcs            = { "user", "Include owned NPCs when saving" },
    rareload_restore_npcs         = { "user", "Restore saved NPCs on spawn" },
    rareload_save_vehicles        = { "user", "Include owned vehicles when saving" },
    rareload_restore_vehicles     = { "user", "Restore saved vehicles on spawn" },
}

-- Internal permission name (passed at call sites) -> CAMI privilege. Several legacy
-- names alias onto the same privilege so existing call sites keep working. Any name
-- NOT listed here is treated as an ungated action (allowed for everyone).
local NAME_TO_PRIV = {
    MANAGE_ENTITIES           = "rareload_manage_objects",
    TELEPORT_PLAYER           = "rareload_teleport",
    DEBUG_MENU                = "rareload_debug",
    ANTI_STUCK_CONFIG         = "rareload_anti_stuck",
    DATA_CLEANUP              = "rareload_data_cleanup",
    RARELOAD_TOGGLE           = "rareload_settings",

    USE_TOOL                  = "rareload_use_tool",
    SAVE_POSITION             = "rareload_save",
    EXECUTE_RARELOAD_COMMANDS = "rareload_save",
    RESTORE_POSITION          = "rareload_restore",
    LOAD_POSITION             = "rareload_restore",
    RARELOAD_SPAWN            = "rareload_restore",
    SAVE_INVENTORY            = "rareload_save_inventory",
    RESTORE_INVENTORY         = "rareload_restore_inventory",
    RETAIN_INVENTORY          = "rareload_restore_inventory",
    KEEP_INVENTORY            = "rareload_restore_inventory",
    GLOBAL_INVENTORY          = "rareload_global_inventory",
    RETAIN_GLOBAL_INVENTORY   = "rareload_global_inventory",
    SAVE_AMMO                 = "rareload_save_ammo",
    RESTORE_AMMO              = "rareload_restore_ammo",
    RETAIN_AMMO               = "rareload_restore_ammo",
    SAVE_HEALTH_ARMOR         = "rareload_save_health_armor",
    RESTORE_HEALTH_ARMOR      = "rareload_restore_health_armor",
    RETAIN_HEALTH_ARMOR       = "rareload_restore_health_armor",
    SAVE_APPEARANCE           = "rareload_save_appearance",
    RESTORE_APPEARANCE        = "rareload_restore_appearance",
    RETAIN_APPEARANCE         = "rareload_restore_appearance",
    SAVE_STATES               = "rareload_save_states",
    RESTORE_STATES            = "rareload_restore_states",
    RETAIN_PLAYER_STATES      = "rareload_restore_states",
    SAVE_ENTITIES             = "rareload_save_entities",
    RESTORE_ENTITIES          = "rareload_restore_entities",
    SAVE_NPCS                 = "rareload_save_npcs",
    RESTORE_NPCS              = "rareload_restore_npcs",
    SAVE_VEHICLES             = "rareload_save_vehicles",
    RESTORE_VEHICLES          = "rareload_restore_vehicles",
}

RARELOAD.Permissions.PRIV = PRIV
RARELOAD.Permissions.NAME_TO_PRIV = NAME_TO_PRIV

-- CAMI.PlayerHasAccess is callback-based — ULib (and others) REQUIRE the callback and
-- error on the 2-arg form. Admin mods invoke the callback synchronously for usergroup
-- checks, so capture the result and return it. Returns nil when CAMI is absent.
local function CAMIHasAccess(ply, priv)
    if not (CAMI and CAMI.PlayerHasAccess) then return nil end
    local result = false
    CAMI.PlayerHasAccess(ply, priv, function(hasAccess) result = hasAccess == true end)
    return result
end

-- Is this player a Rareload admin (umbrella)? CAMI is authoritative when present;
-- otherwise a plain admin/superadmin.
function RARELOAD.IsAdmin(ply)
    if not IsValid(ply) then return false end
    local viaCami = CAMIHasAccess(ply, UMBRELLA)
    if viaCami ~= nil then return viaCami end
    return ply:IsSuperAdmin() or ply:IsAdmin()
end

-- Access check used across the codebase. Umbrella grants all; otherwise the action's
-- own privilege. With no admin mod, fall back by the privilege's default tier.
function RARELOAD.CheckPermission(ply, permName)
    if not IsValid(ply) then return false end
    local priv = NAME_TO_PRIV[permName]
    if not priv then return true end -- ungated action → allowed
    if CAMI and CAMI.PlayerHasAccess then
        return CAMIHasAccess(ply, UMBRELLA) or CAMIHasAccess(ply, priv)
    end
    local tier = (PRIV[priv] and PRIV[priv][1]) or "admin"
    if tier == "user" then return true end
    if tier == "admin" then return ply:IsAdmin() end
    return ply:IsSuperAdmin()
end

-- Back-compat alias used across the codebase.
RARELOAD.Permissions.HasPermission = RARELOAD.CheckPermission

-- Iterate every privilege (umbrella first) as (name, tier, desc).
local function EachPrivilege(fn)
    fn(UMBRELLA, PRIV[UMBRELLA][1], PRIV[UMBRELLA][2])
    for name, spec in pairs(PRIV) do
        if name ~= UMBRELLA then fn(name, spec[1], spec[2]) end
    end
end
RARELOAD.Permissions.EachPrivilege = EachPrivilege

if SERVER then
    -- CAMI: register immediately so any admin mod (ULX/SAM/ServerGuard/FAdmin) sees them.
    if CAMI and CAMI.RegisterPrivilege then
        EachPrivilege(function(name, tier, desc)
            CAMI.RegisterPrivilege({ Name = name, MinAccess = tier, Description = desc })
        end)
    end

    -- ULib (ULX): also register the access under a "Rareload" category so the ULX
    -- groups menu groups them instead of dumping them in "_Uncategorized". Done on
    -- Initialize so ULib is guaranteed loaded regardless of addon mount order.
    hook.Add("Initialize", "RareloadRegisterULibAccess", function()
        if not (ULib and ULib.ucl and ULib.ucl.registerAccess) then return end
        EachPrivilege(function(name, tier, desc)
            ULib.ucl.registerAccess(name, tier, desc, "Rareload")
        end)
    end)

    -- Server-owner helper: list the privileges to grant in ULX/SAM/ServerGuard/…
    concommand.Add("rareload_perms", function(ply)
        local function out(msg) if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end end
        out("[RARELOAD] Privileges (grant/revoke per group in your admin mod):")
        EachPrivilege(function(name, tier, desc)
            out(string.format("  %-30s (%-10s) %s", name, tier, desc))
        end)
        out(CAMI and "[RARELOAD] CAMI detected — privileges are registered with your admin mod."
            or "[RARELOAD] No CAMI/admin mod detected — falling back to IsAdmin() for admin actions.")
    end)
end
