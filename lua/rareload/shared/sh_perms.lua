-- Privileges: declared once, registered with CAMI

RARELOAD.Privs = RARELOAD.Privs or {}
local Privs = RARELOAD.Privs

local UMBRELLA = "rareload_admin"

-- Priv for privilege or perm or whatever you want
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
RARELOAD.Priv("rareload_anti_stuck", "admin", "Test anti-stuck and choose its methods")
RARELOAD.Priv("rareload_data_cleanup", "superadmin", "Run Rareload data cleanup commands")

local function tierAllows(ply, tier)
    if tier == "superadmin" then return ply:IsSuperAdmin() end
    if tier == "admin" then return ply:IsAdmin() end
    return true
end

-- Tiers changed with `rareload perms set`, for servers without an admin mod: "privilege=tier" pairs
-- (names without their rareload_ prefix) in one replicated convar, like the setting locks.
local TIERS = { user = true, admin = true, superadmin = true }
local MAX_CONVAR = 250 -- longer replicated strings are cut off
local changed = CreateConVar("sv_rareload_tiers", "", FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "Rareload privileges whose tier was changed (privilege=tier, comma-separated)")
local tierCache = { raw = nil, set = {} }

-- The tier that has a privilege when no admin mod answers.
function RARELOAD.Tier(name)
    local raw = changed:GetString()
    if raw ~= tierCache.raw then
        tierCache.raw, tierCache.set = raw, {}
        for key, tier in string.gmatch(raw, "([%w_]+)=(%a+)") do
            if TIERS[tier] then tierCache.set["rareload_" .. key] = tier end
        end
    end
    return tierCache.set[name] or Privs[name].tier
end

if SERVER then
    -- tier: "user", "admin", "superadmin", or "default" to undo the change. Returns false and why.
    function RARELOAD.SetTier(name, tier)
        if tier ~= "default" and not TIERS[tier] then return false, "The tier is user, admin, superadmin or default." end
        RARELOAD.Tier(name)
        local set = table.Copy(tierCache.set)
        set[name] = tier ~= "default" and tier ~= Privs[name].tier and tier or nil
        local parts = {}
        for key, value in SortedPairs(set) do
            if Privs[key] then parts[#parts + 1] = (string.gsub(key, "^rareload_", "")) .. "=" .. value end
        end
        local raw = table.concat(parts, ",")
        if #raw > MAX_CONVAR then return false, "Too many changed privileges; use an admin mod for more." end
        changed:SetString(raw)
        return true
    end
end

-- Privileges given to one player with `rareload perms set <privilege> <player>`, whatever their
-- tier. Kept in data/rareload/perms.json by SteamID64; each player's own list is networked to them
-- (names without their rareload_ prefix), so the menus see it too.
local GRANTS = "rl_grants"

local function granted(ply, name)
    local short = string.gsub(name, "^rareload_", "")
    return string.find("," .. ply:GetNW2String(GRANTS) .. ",", "," .. short .. ",", 1, true) ~= nil
end

if SERVER then
    local MAX_NW = 500 -- longer networked strings are cut off

    local function doc()
        return RARELOAD.Store.Load("perms") or { v = RARELOAD.Store.SCHEMA, grants = {} }
    end

    -- The key is not the bare SteamID64: JSON would read it back as a number and lose digits.
    local function listOf(sid64)
        local names = table.GetKeys(doc().grants["id" .. sid64] or {})
        table.sort(names)
        return table.concat(names, ",")
    end

    local function push(ply)
        ply:SetNW2String(GRANTS, listOf(ply:SteamID64()))
    end
    hook.Add("PlayerInitialSpawn", "Rareload.Perms.Grants", push)

    -- Returns false and why.
    function RARELOAD.Grant(sid64, name, on)
        local d = doc()
        local key = "id" .. sid64
        local set = d.grants[key] or {}
        local short = string.gsub(name, "^rareload_", "")
        set[short] = on or nil
        if #table.concat(table.GetKeys(set), ",") > MAX_NW then
            set[short] = nil
            return false, "Too many privileges for one player; give them rareload_admin instead."
        end
        d.grants[key] = next(set) and set or nil
        RARELOAD.Store.Save("perms", d)
        local ply = player.GetBySteamID64(sid64)
        if ply then push(ply) end
        return true
    end

    -- SteamID64 -> "privilege,privilege" for every player with privileges of their own.
    function RARELOAD.Grants()
        local out = {}
        for key in pairs(doc().grants) do
            local sid64 = string.sub(key, 3)
            out[sid64] = listOf(sid64)
        end
        return out
    end
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
    return granted(ply, name) or tierAllows(ply, RARELOAD.Tier(name))
end

-- The server console (no player) can do everything.
function RARELOAD.Can(ply, name)
    if not IsValid(ply) then return true end
    return check(ply, name) or (name ~= UMBRELLA and check(ply, UMBRELLA))
end

-- Admin mods load their CAMI after our autorun file, so register once the gamemode is up.
hook.Add("Initialize", "Rareload.Perms.CAMI", function()
    if not CAMI then return end
    -- ULX lists everything registered through CAMI under "CAMI", without its description; its own
    -- registration puts the privileges in a Rareload category. It still answers the CAMI checks.
    local ulib = SERVER and ULib and ULib.ucl and ULib.ucl.registerAccess
    for name, priv in pairs(Privs) do
        if ulib then
            ulib(name, RARELOAD.Tier(name), priv.desc, "Rareload")
        else
            CAMI.RegisterPrivilege({ Name = name, MinAccess = RARELOAD.Tier(name), Description = priv.desc })
        end
    end
end)
