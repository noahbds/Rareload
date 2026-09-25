RARELOAD.Settings = RARELOAD.Settings or {}
local Settings = RARELOAD.Settings

-- Turns a raw value into the setting's type, clamped to its range. Enums fall back to their default.
local function coerce(def, n)
    if def.type == "enum" then
        for _, v in ipairs(def.values) do
            if v == tostring(n) then return v end
        end
        return def.default
    end
    n = tonumber(n) or 0
    if def.type == "bool" then return n ~= 0 end
    if def.min then n = math.max(n, def.min) end
    if def.max then n = math.min(n, def.max) end
    if def.type == "int" then n = math.floor(n) end
    return n
end

-- Locked player settings, as a comma-separated list of keys in one replicated convar (D3).
local locks = CreateConVar("sv_rareload_locked", "", FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "Player settings locked to the server value (comma-separated keys)")
local lockCache = { raw = nil, set = {} }

function RARELOAD.IsLocked(key)
    local raw = locks:GetString()
    if raw ~= lockCache.raw then
        lockCache.raw, lockCache.set = raw, {}
        for k in string.gmatch(raw, "[%w_]+") do lockCache.set[k] = true end
    end
    return lockCache.set[key] == true
end

-- def = { type = "bool"|"int"|"float"|"enum", default, scope = "server"|"player"|"client", category,
--         min?, max?, values? (enum), capBy?, priv? (needed for the feature to do anything), help }
function RARELOAD.Setting(key, def)
    local name = RARELOAD.Util.Snake(key)
    local lo, hi = def.min, def.max
    local default = tostring(def.default)
    if def.type == "bool" then
        lo, hi, default = 0, 1, def.default and "1" or "0"
    end
    def.key = key
    def.order = def.order or (Settings[key] and Settings[key].order) or table.Count(Settings) + 1 -- menu order
    Settings[key] = def

    if def.scope == "client" then
        def.convar = "cl_rareload_" .. name
        if CLIENT then def.cv = CreateClientConVar(def.convar, default, true, false, def.help, lo, hi) end
        return
    end

    def.convar = "sv_rareload_" .. name
    def.cv = CreateConVar(def.convar, default, FCVAR_ARCHIVE + FCVAR_REPLICATED, def.help, lo, hi) -- G42
    if def.scope == "player" then
        def.pref = "rareload_pref_" .. name
        if CLIENT then
            CreateClientConVar(def.pref, "-1", true, true,
                "Your own value for " .. def.convar .. " (-1 = use the server value)")
        end
    end
end

-- The server's value of a server or player setting.
function RARELOAD.ServerValue(key)
    local def = Settings[key]
    return coerce(def, def.type == "enum" and def.cv:GetString() or def.cv:GetFloat())
end

-- The effective value of a setting. `ply` may be nil for the server value.
function RARELOAD.Get(ply, key)
    local def = Settings[key] or error("[Rareload] unknown setting " .. tostring(key), 2)
    if def.scope == "client" then return coerce(def, def.cv:GetFloat()) end
    local value = RARELOAD.ServerValue(key)

    if def.scope == "player" and IsValid(ply) and (SERVER or ply == LocalPlayer()) and not RARELOAD.IsLocked(key) then
        local pref = SERVER and ply:GetInfoNum(def.pref, -1) or GetConVar(def.pref):GetFloat()
        if pref ~= -1 then value = coerce(def, pref) end
    end
    if def.capBy then
        value = math.min(value, RARELOAD.Get(nil, def.capBy))
    end
    return value
end

RARELOAD.Setting("enabled", {
    type = "bool",
    default = true,
    scope = "player",
    category = "general",
    priv = "rareload_restore",
    help = "Respawn players at their Rareload save"
})
RARELOAD.Setting("antiStuck", {
    type = "bool",
    default = true,
    scope = "player",
    category = "general",
    help = "Move players out of blocked saved positions"
})
RARELOAD.Setting("skipRestoreOnDeath", {
    type = "bool",
    default = false,
    scope = "player",
    category = "general",
    help = "Don't restore the save when respawning after a death"
})
RARELOAD.Setting("keepHealth", {
    type = "bool",
    default = true,
    scope = "player",
    category = "player",
    priv = "rareload_restore_health_armor",
    help = "Restore health and armor"
})
RARELOAD.Setting("keepStates", {
    type = "bool",
    default = true,
    scope = "player",
    category = "player",
    priv = "rareload_restore_states",
    help = "Restore noclip, godmode, notarget, frozen and flashlight"
})
RARELOAD.Setting("keepAppearance", {
    type = "bool",
    default = true,
    scope = "player",
    category = "player",
    priv = "rareload_restore_appearance",
    help = "Restore the player model, skin, bodygroups and colors"
})
RARELOAD.Setting("keepInventory", {
    type = "bool",
    default = true,
    scope = "player",
    category = "player",
    priv = "rareload_restore_inventory",
    help = "Restore weapons and the active weapon"
})
RARELOAD.Setting("keepAmmo", {
    type = "bool",
    default = true,
    scope = "player",
    category = "player",
    priv = "rareload_restore_ammo",
    help = "Restore reserve ammo and clips"
})
RARELOAD.Setting("globalInventory", {
    type = "bool",
    default = false,
    scope = "player",
    category = "player",
    priv = "rareload_global_inventory",
    help = "Use one inventory across all maps"
})
RARELOAD.Setting("keepEntities", {
    type = "bool",
    default = true,
    scope = "player",
    category = "world",
    priv = "rareload_restore_entities",
    help = "Save and restore the props and entities you own"
})
RARELOAD.Setting("keepNPCs", {
    type = "bool",
    default = true,
    scope = "player",
    category = "world",
    priv = "rareload_restore_npcs",
    help = "Save and restore the NPCs you own"
})
RARELOAD.Setting("keepVehicles", {
    type = "bool",
    default = true,
    scope = "player",
    category = "world",
    priv = "rareload_restore_vehicles",
    help = "Save and restore your vehicles and put you back in your seat"
})
RARELOAD.Setting("overwriteModified", {
    type = "bool",
    default = true,
    scope = "player",
    category = "world",
    help = "On save, overwrite objects that are already saved (off keeps their saved state)"
})
RARELOAD.Setting("overwriteDeleted", {
    type = "bool",
    default = true,
    scope = "player",
    category = "world",
    help = "On save, drop saved objects that were deleted from the map (off keeps them saved)"
})
RARELOAD.Setting("autoSave", {
    type = "bool",
    default = false,
    scope = "player",
    category = "general",
    priv = "rareload_save",
    help = "Save automatically when something changes"
})
RARELOAD.Setting("saveOnDisconnect", {
    type = "bool",
    default = false,
    scope = "player",
    category = "general",
    priv = "rareload_save",
    help = "Save everything when you disconnect or the server shuts down"
})
RARELOAD.Setting("saveOnCleanup", {
    type = "bool",
    default = false,
    scope = "player",
    category = "general",
    priv = "rareload_save",
    help = "Save everything when the map is cleaned up"
})
RARELOAD.Setting("autoSaveInterval", {
    type = "int",
    default = 30,
    min = 1,
    max = 600,
    scope = "player",
    category = "timing",
    help = "Autosave: minimum seconds between two saves"
})
RARELOAD.Setting("autoSaveAngleThreshold", {
    type = "float",
    default = 45,
    min = 1,
    max = 180,
    scope = "player",
    category = "timing",
    help = "Autosave: degrees of view change that count as a change"
})
RARELOAD.Setting("historySize", {
    type = "int",
    default = 50,
    min = 1,
    max = 1000,
    scope = "player",
    category = "timing",
    capBy = "historySizeMax",
    help = "How many saves each player keeps per map"
})
RARELOAD.Setting("historySizeMax", {
    type = "int",
    default = 100,
    min = 1,
    max = 1000,
    scope = "server",
    category = "timing",
    help = "Upper limit for historySize, so players can't fill the disk"
})
RARELOAD.Setting("enableInAllGamemodes", {
    type = "bool",
    default = false,
    scope = "server",
    category = "server",
    help = "Also run Rareload in gamemodes not derived from Sandbox (D19)"
})
RARELOAD.Setting("debug", {
    type = "bool",
    default = false,
    scope = "server",
    category = "server",
    help = "Print Rareload debug logs, send report cards to admins and show the world display"
})
RARELOAD.Setting("deathCleanupMode", {
    type = "enum",
    values = { "off", "all", "owned", "saved" },
    default = "off",
    scope = "server",
    category = "world",
    help = "Before respawning a dead player: off, clean the whole map, "
        .. "remove their own objects, or remove only their saved objects"
})
RARELOAD.Setting("disconnectCleanup", {
    type = "bool",
    default = false,
    scope = "server",
    category = "world",
    help = "Remove a player's objects when they disconnect"
})
RARELOAD.Setting("maxVehicles", {
    type = "int",
    default = 0,
    min = 0,
    max = 100,
    scope = "server",
    category = "world",
    help = "Most vehicles restored per player (0 = no limit)"
})
RARELOAD.Setting("respectSpawnLimits", {
    type = "bool",
    default = not game.SinglePlayer(),
    scope = "server",
    category = "world",
    help = "Restored objects go through Sandbox spawn permissions and sbox_max limits (D10)"
})
RARELOAD.Setting("asMaxSearchTime", {
    type = "float",
    default = 0.3,
    min = 0.05,
    max = 5,
    scope = "server",
    category = "antistuck",
    help = "Anti-stuck: seconds to spend looking for a free spot"
})
RARELOAD.Setting("asMaxDistance", {
    type = "int",
    default = 1200,
    min = 64,
    max = 8192,
    scope = "server",
    category = "antistuck",
    help = "Anti-stuck: how far from the saved position to look"
})
RARELOAD.Setting("wdDrawDistance", {
    type = "int",
    default = 800,
    min = 100,
    max = 5000,
    scope = "client",
    category = "display",
    help = "World display: how far away saved objects show an info panel"
})
RARELOAD.Setting("wdMaxDrawPerFrame", {
    type = "int",
    default = 16,
    min = 1,
    max = 100,
    scope = "client",
    category = "display",
    help = "World display: most info panels drawn at once"
})
RARELOAD.Setting("wdInteractDistance", {
    type = "int",
    default = 400,
    min = 100,
    max = 5000,
    scope = "client",
    category = "display",
    help = "World display: how far away you can focus an info panel"
})
RARELOAD.Setting("toastHold", {
    type = "float",
    default = 6,
    min = 1,
    max = 30,
    scope = "client",
    category = "display",
    help = "Seconds a debug report card stays on screen (cards with more steps stay a little longer)"
})

if SERVER then
    function RARELOAD.ResetSettings(who)
        local changed = 0
        for _, def in pairs(Settings) do
            if def.scope ~= "client" and def.cv:GetString() ~= def.cv:GetDefault() then
                def.cv:SetString(def.cv:GetDefault())
                changed = changed + 1
            end
        end
        if locks:GetString() ~= "" then
            locks:SetString("")
            changed = changed + 1
        end
        RARELOAD.AntiStuck.Configure("reset")
        RARELOAD.Log("settings"):info("%s reset every setting to its default (%d changed)", who, changed)
        return changed
    end

    RARELOAD.Net.Handle("settings.reset", {
        priv = "rareload_settings",
        rate = 1,
        fn = function(ply)
            RARELOAD.Toast(ply, "toast.settings_reset", { RARELOAD.ResetSettings(ply:Nick()) }, "ok")
        end,
    })

    RARELOAD.Net.Handle("settings.set", {
        priv = "rareload_settings",
        rate = 0.1,
        args = { key = "string:64", value = "string:32" },
        fn = function(ply, a)
            local def = Settings[a.key]
            if not def or def.scope == "client" or (def.type ~= "enum" and not tonumber(a.value)) then return end
            local value = coerce(def, a.value)
            def.cv:SetString(def.type == "bool" and (value and "1" or "0") or tostring(value))
            RARELOAD.Log("settings"):info("%s set %s to %s", ply:Nick(), def.convar, tostring(value))
        end,
    })

    RARELOAD.Net.Handle("settings.lock", {
        priv = "rareload_settings",
        rate = 0.1,
        args = { key = "string:64", locked = "bool" },
        fn = function(ply, a)
            local def = Settings[a.key]
            if not def or def.scope ~= "player" or RARELOAD.IsLocked(a.key) == a.locked then return end
            local keys = {}
            for k in string.gmatch(locks:GetString(), "[%w_]+") do
                if k ~= a.key and Settings[k] then keys[#keys + 1] = k end
            end
            if a.locked then keys[#keys + 1] = a.key end
            table.sort(keys)
            locks:SetString(table.concat(keys, ","))
            RARELOAD.Log("settings"):info("%s %s %s", ply:Nick(), a.locked and "locked" or "unlocked", a.key)
        end,
    })
end
