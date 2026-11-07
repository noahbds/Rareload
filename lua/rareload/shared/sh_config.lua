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
        -- A player without the value (bots have no userinfo; GetInfoNum then returns 0, not the
        -- default) uses the server value.
        -- An enum's own value is its text.
        local raw = SERVER and ply:GetInfo(def.pref) or GetConVar(def.pref):GetString()
        if def.type == "enum" then
            if raw ~= "" and raw ~= "-1" then value = coerce(def, raw) end
        else
            local pref = tonumber(raw) or -1
            if pref ~= -1 then value = coerce(def, pref) end
        end
    end
    if def.capBy then
        value = math.min(value, RARELOAD.Get(nil, def.capBy))
    end
    return value
end

-- Settings that share a scope and a category: { key, field = value, … } each, in menu order.
local function group(scope, category, list)
    for _, def in ipairs(list) do
        local key = table.remove(def, 1)
        def.scope, def.category = scope, category
        RARELOAD.Setting(key, def)
    end
end

group("player", "general", {
    { "enabled", type = "bool", default = true, priv = "rareload_restore",
        help = "Respawn players at their Rareload save" },
    { "antiStuck", type = "bool", default = true,
        help = "Move players out of blocked saved positions" },
})
group("player", "player", {
    { "keepHealth", type = "bool", default = true, priv = "rareload_restore_health_armor",
        help = "Restore health and armor" },
    { "keepStates", type = "bool", default = true, priv = "rareload_restore_states",
        help = "Restore noclip, godmode, notarget, frozen and flashlight" },
    { "keepBody", type = "bool", default = true, priv = "rareload_restore_states",
        help = "Restore speeds, jump power, gravity, size, max health and armor, FOV, suit power and fire" },
    { "keepTool", type = "bool", default = true, priv = "rareload_restore_inventory",
        help = "Restore the selected tool and its settings" },
    { "keepAppearance", type = "bool", default = true, priv = "rareload_restore_appearance",
        help = "Restore the player model, skin, bodygroups and colors" },
    { "keepInventory", type = "bool", default = true, priv = "rareload_restore_inventory",
        help = "Restore weapons and the active weapon" },
    { "keepAmmo", type = "bool", default = true, priv = "rareload_restore_ammo",
        help = "Restore reserve ammo and clips" },
    { "keepAttachments", type = "bool", default = true, priv = "rareload_restore_inventory",
        help = "Restore weapon attachments and fire modes (ARC9, ArcCW, TFA, MW Base)" },
    { "globalInventory", type = "bool", default = false, priv = "rareload_global_inventory",
        help = "Use one inventory across all maps" },
})
group("player", "world", {
    { "keepEntities", type = "bool", default = true, priv = "rareload_restore_entities",
        help = "Save and restore the props and entities you own" },
    { "keepNPCs", type = "bool", default = true, priv = "rareload_restore_npcs",
        help = "Save and restore the NPCs you own" },
    { "keepVehicles", type = "bool", default = true, priv = "rareload_restore_vehicles",
        help = "Save and restore your vehicles and put you back in your seat" },
    { "overwriteModified", type = "bool", default = true,
        help = "On save, overwrite objects that are already saved (off keeps their saved state)" },
    { "overwriteDeleted", type = "bool", default = true,
        help = "On save, drop saved objects that were deleted from the map (off keeps them saved)" },
    { "keepMotion", type = "bool", default = true,
        help = "Objects saved while moving come back moving at the same speed" },
    { "keepGroundWeapons", type = "bool", default = game.SinglePlayer(), priv = "rareload_restore_entities",
        help = "Save and restore the weapons you spawned or dropped that lie on the ground" },
    { "resetObjects", type = "bool", default = true,
        help = "Timeline restores put saved objects still on the map back the way they were saved" },
    { "resetOnSpawn", type = "bool", default = false,
        help = "Respawning at your save also puts your saved objects back the way they were saved" },
})
group("player", "general", {
    { "saveOnDeath", type = "bool", default = false, priv = "rareload_save",
        help = "Save just before dying (it doesn't replace the respawn point), to go back to it later" },
    { "deathChoice", type = "bool", default = false, priv = "rareload_restore",
        help = "After dying, choose where to respawn: the respawn point, the map spawn or where you died" },
    { "deathChoiceAlways", type = "enum", values = { "ask", "save", "map", "death" }, default = "ask",
        priv = "rareload_restore",
        help = "Where to respawn after dying: asked (with the respawn choice on), or always the same place" },
})
-- The old "Normal respawn after dying" (skipRestoreOnDeath) is now "Respawn after dying: at the map's
-- spawn". Turned on, the server or player value moves over once.
if SERVER then
    local old = CreateConVar("sv_rareload_skip_restore_on_death", "0", FCVAR_ARCHIVE,
        "Replaced by sv_rareload_death_choice_always")
    if old:GetBool() then
        RunConsoleCommand("sv_rareload_death_choice_always", "map")
        old:SetBool(false)
    end
else
    local old = CreateClientConVar("rareload_pref_skip_restore_on_death", "-1", true, false,
        "Replaced by rareload_pref_death_choice_always")
    if old:GetInt() == 1 then RunConsoleCommand("rareload_pref_death_choice_always", "map") end
    if old:GetInt() ~= -1 then RunConsoleCommand("rareload_pref_skip_restore_on_death", "-1") end
end
group("player", "general", {
    { "autoSave", type = "bool", default = false, priv = "rareload_save",
        help = "Save automatically when something changes" },
    { "saveOnDisconnect", type = "bool", default = false, priv = "rareload_save",
        help = "Save everything when you disconnect or the server shuts down" },
    { "saveOnCleanup", type = "bool", default = false, priv = "rareload_save",
        help = "Save everything when the map is cleaned up" },
})
group("player", "timing", {
    { "autoSaveInterval", type = "int", default = 30, min = 1, max = 600, unit = "s",
        help = "Autosave: minimum seconds between two saves" },
    { "autoSaveAngleThreshold", type = "float", default = 45, min = 1, max = 180, unit = "°",
        help = "Autosave: degrees of view change that count as a change" },
    { "historySize", type = "int", default = 50, min = 1, max = 1000, capBy = "historySizeMax",
        help = "How many saves each player keeps per map" },
})
group("server", "timing", {
    { "historySizeMax", type = "int", default = 100, min = 1, max = 1000,
        help = "Upper limit for historySize, so players can't fill the disk" },
    { "importMaxKB", type = "int", default = 4096, min = 64, max = 65536,
        help = "Largest save file a player may import, in KB once compressed" },
    { "saveCombatDelay", type = "int", default = 0, min = 0, max = 600,
        help = "PvP: no saving within this many seconds of taking or dealing combat damage (0 = off)" },
    { "restoreCooldown", type = "int", default = 0, min = 0, max = 3600,
        help = "PvP: seconds a player waits between two timeline restores (0 = off)" },
    { "restoreNeedsSpawn", type = "int", default = 0, min = 0, max = 600,
        help = "PvP: timeline restores only within this many seconds of spawning (0 = off)" },
    { "restoreBatch", type = "int", default = 50, min = 0, max = 1000,
        help = "Objects created per tick when restoring a large build, so it doesn't freeze the server (0 = all at"
            .. " once)" },
})
group("server", "server", {
    { "snapshotInterval", type = "int", default = 0, min = 0, max = 120,
        help = "Minutes between two server snapshots of every player's objects, for rollback (0 = off)" },
    { "snapshotKeep", type = "int", default = 6, min = 1, max = 50,
        help = "How many server snapshots are kept on each map" },
    { "crashRecovery", type = "enum", values = { "off", "ask", "auto" }, default = "ask",
        help = "After a crash, a player's objects from the last snapshot newer than their save: off, offered, or"
            .. " restored" },
})
group("server", "timing", {
    { "pinnedMax", type = "int", default = 20, min = 1, max = 500,
        help = "Most pinned saves each player can have on a map (pinned saves are never dropped)" },
    { "checkpointMax", type = "int", default = 20, min = 1, max = 100,
        help = "Most checkpoints each player can have on a map" },
})
group("server", "server", {
    { "fireDuration", type = "float", default = 10, min = 1, max = 120,
        help = "Seconds a player or object saved while burning burns again after a restore" },
    { "enableInAllGamemodes", type = "bool", default = false,
        help = "Also run Rareload in gamemodes not derived from Sandbox (D19)" },
    { "logLevel", type = "enum", values = { "errors", "warnings", "activity", "debug" }, default = "activity",
        help = "What Rareload prints to the server console: errors, warnings, activity (one line per save, "
            .. "restore and admin change) or debug (every step)" },
    { "logToFile", type = "bool", default = false,
        help = "Also write the log to data/rareload/logs, one file per day" },
    { "logKeepDays", type = "int", default = 14, min = 1, max = 365,
        help = "Days log files are kept" },
    { "debug", type = "bool", default = false,
        help = "Print Rareload debug logs, send report cards to admins and show the world display" },
})
group("server", "world", {
    { "keepMapState", type = "bool", default = game.SinglePlayer(), priv = "rareload_restore_scene",
        help = "Save and restore the map's doors, locks, broken objects and physics props (for everyone)" },
    { "keepEnvironment", type = "bool", default = game.SinglePlayer(), priv = "rareload_restore_scene",
        help = "Save and restore the time of day, weather (StormFox2) and sky (for everyone)" },
    { "keepWorldSettings", type = "bool", default = game.SinglePlayer(), priv = "rareload_restore_scene",
        help = "Save and restore gravity, physics speed and the AI switches (for everyone)" },
    { "deathCleanupMode", type = "enum", values = { "off", "all", "owned", "saved" }, default = "off",
        help = "Before respawning a dead player: off, clean the whole map, "
            .. "remove their own objects, or remove only their saved objects" },
    { "disconnectCleanup", type = "bool", default = false,
        help = "Remove a player's objects when they disconnect" },
    { "maxVehicles", type = "int", default = 0, min = 0, max = 100,
        help = "Most vehicles restored per player (0 = no limit)" },
    { "respectSpawnLimits", type = "bool", default = not game.SinglePlayer(),
        help = "Restored objects go through Sandbox spawn permissions and sbox_max limits (D10)" },
})
group("server", "antistuck", {
    { "asMaxSearchTime", type = "float", default = 0.3, min = 0.05, max = 5, unit = "s",
        help = "Anti-stuck: seconds to spend looking for a free spot" },
    { "asMaxDistance", type = "int", default = 1200, min = 64, max = 8192,
        help = "Anti-stuck: how far from the saved position to look" },
})
group("client", "display", {
    { "wdDrawDistance", type = "int", default = 800, min = 100, max = 5000,
        help = "World display: how far away saved objects show an info panel" },
    { "wdMaxDrawPerFrame", type = "int", default = 16, min = 1, max = 100,
        help = "World display: most info panels drawn at once" },
    { "wdInteractDistance", type = "int", default = 400, min = 100, max = 5000,
        help = "World display: how far away aiming at a saved object focuses its panel (its tag: as far as panels"
            .. " show)" },
    { "showCheckpoints", type = "bool", default = true,
        help = "Show your checkpoints as markers in the world" },
    { "toastHold", type = "float", default = 6, min = 1, max = 30, unit = "s",
        help = "Seconds a debug report card stays on screen (cards with more steps stay a little longer)" },
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
            local value, before = coerce(def, a.value), RARELOAD.ServerValue(a.key)
            def.cv:SetString(def.type == "bool" and (value and "1" or "0") or tostring(value))
            RARELOAD.Log("settings", ply):info("%s changed %s from %s to %s", ply:Nick(), a.key, tostring(before),
                tostring(value))
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
            RARELOAD.Log("settings", ply):info("%s %s the player setting %s", ply:Nick(),
                a.locked and "locked" or "unlocked", a.key)
        end,
    })
end
