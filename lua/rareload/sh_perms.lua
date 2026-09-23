-- Privileges: declared once, registered with CAMI, with a usergroup-tier fallback (REWRITE_PLAN.md §13.3).

RARELOAD.Privs = RARELOAD.Privs or {}
local Privs = RARELOAD.Privs

local UMBRELLA = "rareload_admin"

function RARELOAD.Priv(name, tier, desc)
    Privs[name] = { tier = tier, desc = desc }
end

RARELOAD.Priv(UMBRELLA, "superadmin", "Every Rareload privilege")
RARELOAD.Priv("rareload_settings", "superadmin", "Change Rareload server settings")
RARELOAD.Priv("rareload_debug", "admin", "See Rareload debug reports and run debug commands")
RARELOAD.Priv("rareload_use_tool", "user", "Use the Rareload tool")
RARELOAD.Priv("rareload_save", "user", "Save a Rareload position")
RARELOAD.Priv("rareload_restore", "user", "Respawn at the saved Rareload position")
RARELOAD.Priv("rareload_save_inventory", "user", "Include weapons when saving")
RARELOAD.Priv("rareload_restore_inventory", "user", "Get saved weapons back on spawn")
RARELOAD.Priv("rareload_global_inventory", "user", "Use the cross-map inventory")
RARELOAD.Priv("rareload_save_ammo", "user", "Include ammo when saving")
RARELOAD.Priv("rareload_restore_ammo", "user", "Get saved ammo back on spawn")
RARELOAD.Priv("rareload_save_health_armor", "user", "Include health and armor when saving")
RARELOAD.Priv("rareload_restore_health_armor", "user", "Get saved health and armor back on spawn")
RARELOAD.Priv("rareload_save_appearance", "user", "Include the player model and colors when saving")
RARELOAD.Priv("rareload_restore_appearance", "user", "Get the saved player model and colors back on spawn")
RARELOAD.Priv("rareload_save_states", "user", "Include noclip, godmode, frozen and flashlight when saving")
RARELOAD.Priv("rareload_restore_states", "user", "Get saved noclip, frozen and flashlight back on spawn")
RARELOAD.Priv("rareload_restore_privileged_states", "admin", "Get saved godmode and notarget back on spawn (S14)")
RARELOAD.Priv("rareload_save_entities", "user", "Include your props and entities when saving")
RARELOAD.Priv("rareload_restore_entities", "user", "Get your saved props and entities back on spawn")
RARELOAD.Priv("rareload_save_npcs", "user", "Include your NPCs when saving")
RARELOAD.Priv("rareload_restore_npcs", "user", "Get your saved NPCs back on spawn")
RARELOAD.Priv("rareload_save_vehicles", "user", "Include your vehicles when saving")
RARELOAD.Priv("rareload_restore_vehicles", "user", "Get your saved vehicles back on spawn")
RARELOAD.Priv("rareload_manage_objects", "admin", "Edit, flag or delete objects inside saves")
RARELOAD.Priv("rareload_teleport", "admin", "Teleport to saved positions and objects")
RARELOAD.Priv("rareload_data_cleanup", "superadmin", "Run Rareload data cleanup commands")

local function tierAllows(ply, tier)
    if tier == "superadmin" then return ply:IsSuperAdmin() end
    if tier == "admin" then return ply:IsAdmin() end
    return true
end

local function check(ply, name)
    local priv = Privs[name]
    if not priv then error("[Rareload] unknown privilege " .. tostring(name), 3) end

    if CAMI then
        -- ULib's CAMI requires the callback form; admin mods answer synchronously for usergroup checks (L30).
        local result
        CAMI.PlayerHasAccess(ply, name, function(hasAccess) result = hasAccess end)
        if result ~= nil then return result end
    end
    return tierAllows(ply, priv.tier)
end

-- The server console (no player) can do everything.
function RARELOAD.Can(ply, name)
    if not IsValid(ply) then return true end
    return check(ply, name) or (name ~= UMBRELLA and check(ply, UMBRELLA))
end

-- Admin mods load their CAMI after our autorun file, so register once the gamemode is up.
hook.Add("Initialize", "Rareload.Perms.CAMI", function()
    if not CAMI then return end
    for name, priv in pairs(Privs) do
        CAMI.RegisterPrivilege({ Name = name, MinAccess = priv.tier, Description = priv.desc })
    end
end)
