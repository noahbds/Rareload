-- Privileges: declared once, registered with CAMI

RARELOAD.Privs = RARELOAD.Privs or {}
local Privs = RARELOAD.Privs

local UMBRELLA = "rareload_admin"

function RARELOAD.Priv(name, tier, desc)
    Privs[name] = { tier = tier, desc = desc }
end

RARELOAD.Priv(UMBRELLA, "superadmin", "Every Rareload privilege")

-- Server settings and diagnostics
RARELOAD.Priv("rareload_settings", "superadmin", "Change Rareload server settings")
RARELOAD.Priv("rareload_debug", "admin", "See Rareload debug reports and run debug commands")
RARELOAD.Priv("rareload_data_cleanup", "superadmin", "Run Rareload data cleanup commands")

-- Basic player functionality
RARELOAD.Priv("rareload_use_tool", "user", "Use the Rareload tool")
RARELOAD.Priv("rareload_save", "user", "Save a Rareload position")
RARELOAD.Priv("rareload_restore", "user", "Respawn at the saved Rareload position")

-- Inventory
RARELOAD.Priv("rareload_save_inventory", "user", "Include weapons when saving")
RARELOAD.Priv("rareload_restore_inventory", "user", "Get saved weapons back on spawn")
RARELOAD.Priv("rareload_global_inventory", "admin", "Use the cross-map inventory")

-- Ammo
RARELOAD.Priv("rareload_save_ammo", "user", "Include ammo when saving")
RARELOAD.Priv("rareload_restore_ammo", "user", "Get saved ammo back on spawn")

-- Health and armor
RARELOAD.Priv("rareload_save_health_armor", "user", "Include health and armor when saving")
RARELOAD.Priv("rareload_restore_health_armor", "user", "Get saved health and armor back on spawn")

-- Appearance
RARELOAD.Priv("rareload_save_appearance", "user", "Include the player model and colors when saving")
RARELOAD.Priv("rareload_restore_appearance", "user", "Get the saved player model and colors back on spawn")

-- Player states
RARELOAD.Priv("rareload_save_states", "user", "Include noclip, godmode, frozen and flashlight when saving")
RARELOAD.Priv("rareload_restore_states", "admin", "Get saved noclip, frozen and flashlight back on spawn")
RARELOAD.Priv("rareload_restore_privileged_states", "admin",
    "Get saved godmode and notarget back on spawn (S14)")
RARELOAD.Priv("rareload_restore_privileged_body", "admin",
    "Get saved speeds, jump power, gravity, size and max health/armor back when they differ from now")

-- Entities
RARELOAD.Priv("rareload_save_entities", "user", "Include your props and entities when saving")
RARELOAD.Priv("rareload_restore_entities", "admin", "Get your saved props and entities back on spawn")

-- NPCs
RARELOAD.Priv("rareload_save_npcs", "admin", "Include NPCs when saving")
RARELOAD.Priv("rareload_restore_npcs", "admin", "Get your saved NPCs back on spawn")

-- Vehicles
RARELOAD.Priv("rareload_save_vehicles", "admin", "Include vehicles when saving")
RARELOAD.Priv("rareload_restore_vehicles", "admin", "Get your saved vehicles back on spawn")

-- Save management
RARELOAD.Priv("rareload_export", "user", "Export your saves to a file")
RARELOAD.Priv("rareload_import", "admin", "Add a save from a file to your timeline")
RARELOAD.Priv("rareload_share", "user", "Offer a copy of your saves to other players")

-- World and server management
RARELOAD.Priv("rareload_save_scene", "admin", "Include the map, time, weather and world settings when saving")
RARELOAD.Priv("rareload_restore_scene", "admin",
    "Restore the map, time, weather and world settings (they change the server for everyone)")
RARELOAD.Priv("rareload_manage_objects", "admin", "Edit, flag or delete objects inside saves")
RARELOAD.Priv("rareload_manage_inventory", "admin", "Edit, copy, give and roll back saved and global inventories")
RARELOAD.Priv("rareload_teleport", "admin", "Teleport to saved positions and objects")
RARELOAD.Priv("rareload_anti_stuck", "admin", "Test anti-stuck and choose its methods")
RARELOAD.Priv("rareload_rollback", "admin", "Take server snapshots and roll players' objects back to one")
RARELOAD.Priv("rareload_manage_saves", "admin", "See and manage other players' saves, online or not")
RARELOAD.Priv("rareload_checkpoints", "admin", "Set named teleport spots and go back to them")
RARELOAD.Priv("rareload_block_classes", "admin", "Choose object classes Rareload never saves or restores")

local function tierAllows(ply, tier)
    if tier == "superadmin" then return ply:IsSuperAdmin() end
    if tier == "admin" then return ply:IsAdmin() end
    return true
end

-- Server-specific tier overrides.
local TIERS = { user = true, admin = true, superadmin = true }
local MAX_CONVAR = 250

local changed = CreateConVar(
    "sv_rareload_tiers",
    "",
    FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "Rareload privileges whose tier was changed (privilege=tier, comma-separated)"
)

local tierCache = { raw = nil, set = {} }

function RARELOAD.Tier(name)
    local raw = changed:GetString()

    if raw ~= tierCache.raw then
        tierCache.raw, tierCache.set = raw, {}

        for key, tier in string.gmatch(raw, "([%w_]+)=(%a+)") do
            if TIERS[tier] then
                tierCache.set["rareload_" .. key] = tier
            end
        end
    end

    local priv = Privs[name]
    return tierCache.set[name] or (priv and priv.tier)
end

if SERVER then
    -- tier: user, admin, superadmin or default.
    function RARELOAD.SetTier(name, tier)
        if not Privs[name] then
            return false, "Unknown Rareload privilege."
        end

        if tier ~= "default" and not TIERS[tier] then
            return false, "The tier is user, admin, superadmin or default."
        end

        RARELOAD.Tier(name)

        local set = table.Copy(tierCache.set)
        set[name] = tier ~= "default" and tier ~= Privs[name].tier and tier or nil

        local parts = {}

        for key, value in SortedPairs(set) do
            if Privs[key] then
                parts[#parts + 1] = string.gsub(key, "^rareload_", "") .. "=" .. value
            end
        end

        local raw = table.concat(parts, ",")

        if #raw > MAX_CONVAR then
            return false, "Too many changed privileges; use an admin mod for more."
        end

        changed:SetString(raw)
        return true
    end
end

-- Individual player grants, persisted by SteamID64.
local GRANTS = "rl_grants"

local function granted(ply, name)
    local short = string.gsub(name, "^rareload_", "")
    local grants = ply:GetNW2String(GRANTS)

    return string.find("," .. grants .. ",", "," .. short .. ",", 1, true) ~= nil
end

if SERVER then
    local MAX_NW = 500

    local function loadGrants()
        return RARELOAD.Store.Load("perms") or {
            v = RARELOAD.Store.SCHEMA,
            grants = {}
        }
    end

    local function listOf(sid64)
        local names = table.GetKeys(loadGrants().grants["id" .. sid64] or {})
        table.sort(names)
        return table.concat(names, ",")
    end

    local function push(ply)
        ply:SetNW2String(GRANTS, listOf(ply:SteamID64()))
    end

    hook.Add("PlayerInitialSpawn", "Rareload.Perms.Grants", push)

    function RARELOAD.Grant(sid64, name, on)
        if not Privs[name] then
            return false, "Unknown Rareload privilege."
        end

        local doc = loadGrants()
        local key = "id" .. sid64
        local set = doc.grants[key] or {}
        local short = string.gsub(name, "^rareload_", "")

        set[short] = on and true or nil

        if #table.concat(table.GetKeys(set), ",") > MAX_NW then
            set[short] = nil
            return false, "Too many privileges for one player; give them rareload_admin instead."
        end

        doc.grants[key] = next(set) and set or nil

        RARELOAD.Store.Save("perms", doc)

        local ply = player.GetBySteamID64(sid64)
        if IsValid(ply) then
            push(ply)
        end

        return true
    end

    function RARELOAD.Grants()
        local out = {}

        for key in pairs(loadGrants().grants) do
            local sid64 = string.sub(key, 3)
            out[sid64] = listOf(sid64)
        end

        return out
    end
end

local function check(ply, name)
    local priv = Privs[name]

    if not priv then
        error("[Rareload] unknown privilege " .. tostring(name), 3)
    end

    if CAMI then
        local result

        CAMI.PlayerHasAccess(ply, name, function(hasAccess)
            result = hasAccess
        end)

        if result ~= nil then
            return result
        end
    end

    return granted(ply, name) or tierAllows(ply, RARELOAD.Tier(name))
end

-- The server console (no player) can do everything.
function RARELOAD.Can(ply, name)
    if not IsValid(ply) then
        return true
    end

    return check(ply, name)
        or (name ~= UMBRELLA and check(ply, UMBRELLA))
end

-- Register privileges once the gamemode and admin mods have loaded.
hook.Add("Initialize", "Rareload.Perms.CAMI", function()
    if not CAMI then return end

    local ulib = SERVER and ULib and ULib.ucl and ULib.ucl.registerAccess

    for name, priv in pairs(Privs) do
        if ulib then
            ulib(name, RARELOAD.Tier(name), priv.desc, "Rareload")
        else
            CAMI.RegisterPrivilege({
                Name = name,
                MinAccess = RARELOAD.Tier(name),
                Description = priv.desc
            })
        end
    end
end)
