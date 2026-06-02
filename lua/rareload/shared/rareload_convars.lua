RARELOAD = RARELOAD or {}
RARELOAD.ConVars = RARELOAD.ConVars or {}

local CONVAR_DEFS = {
    { "sv_rareload_enabled",               "1",   "Enable/disable Rareload addon",                                                                                                 "addonEnabled" },
    { "sv_rareload_spawn_mode",            "1",   "Enable anti-stuck spawn system",                                                                                                "spawnModeEnabled" },
    { "sv_rareload_auto_save",             "0",   "Enable automatic position saving",                                                                                              "autoSaveEnabled" },
    { "sv_rareload_no_custom_death",       "0",   "Disable custom respawn on death",                                                                                               "nocustomrespawnatdeath" },
    { "sv_rareload_debug",                 "0",   "Enable debug logging",                                                                                                          "debugEnabled" },

    { "sv_rareload_keep_health",           "1",   "Keep health and armor on respawn",                                                                                              "retainHealthArmor" },
    { "sv_rareload_keep_states",           "1",   "Keep player states (godmode, notarget, etc.)",                                                                                  "retainPlayerStates" },
    { "sv_rareload_keep_inventory",        "1",   "Keep inventory on respawn",                                                                                                     "retainInventory" },
    { "sv_rareload_keep_ammo",             "1",   "Keep ammunition on respawn",                                                                                                    "retainAmmo" },
    { "sv_rareload_global_inventory",      "0",   "Enable global inventory sharing",                                                                                               "retainGlobalInventory" },

    { "sv_rareload_keep_map_entities",     "1",   "Keep map entities on respawn",                                                                                                  "retainMapEntities" },
    { "sv_rareload_keep_map_npcs",         "1",   "Keep map NPCs on respawn",                                                                                                      "retainMapNPCs" },
    { "sv_rareload_cleanup_map",           "0",   "Clean up the map right before respawning",                                                                                      "cleanupMapAfterDeath" },
    { "sv_rareload_cleanup_owned_only",    "0",   "When cleanup on death is enabled, only remove the player's own Rareload-spawned entities/NPCs instead of wiping the whole map", "cleanupOnlyOwnedEntitiesOnDeath" },
    { "sv_rareload_cleanup_on_disconnect", "0",   "Remove the player's owned entities and NPCs when they disconnect",                                                              "cleanupOwnedEntitiesOnDisconnect" },

    { "sv_rareload_auto_save_interval",    "5",   "Seconds between auto saves",                                                                                                    "autoSaveInterval" },
    { "sv_rareload_angle_tolerance",       "100", "Angle tolerance for entity restoration",                                                                                        "angleTolerance" },
    { "sv_rareload_history_size",          "125", "Maximum position history entries",                                                                                              "maxHistorySize" },
}
RARELOAD.ConVarToSetting = {}
RARELOAD.SettingToConVar = {}

for _, def in ipairs(CONVAR_DEFS) do
    RARELOAD.ConVarToSetting[def[1]] = def[4]
    RARELOAD.SettingToConVar[def[4]] = def[1]
end

-- A ConVar represents a bool when its default is "0" or "1", otherwise a number.
local function IsBoolDef(default)
    return default == "0" or default == "1"
end

-- Read a ConVar's current value, coerced to bool/number per its default.
local function ReadConVarValue(cv, default)
    if IsBoolDef(default) then return cv:GetBool() end
    return cv:GetFloat()
end

-- Coerce a ConVar string value (from a change callback) per its default.
local function CoerceConVarString(newVal, default)
    if IsBoolDef(default) then return newVal == "1" end
    return tonumber(newVal) or 0
end

if SERVER then
    for _, def in ipairs(CONVAR_DEFS) do
        local name, default, description = def[1], def[2], def[3]

        RARELOAD.ConVars[name] = CreateConVar(
            name,
            default,
            FCVAR_ARCHIVE + FCVAR_REPLICATED + FCVAR_NOTIFY,
            description
        )
    end

    local function SyncConVarsFromSettings()
        if not RARELOAD.settings then return end

        for _, def in ipairs(CONVAR_DEFS) do
            local name, settingsKey = def[1], def[4]
            local value = RARELOAD.settings[settingsKey]

            if value ~= nil then
                local cv = RARELOAD.ConVars[name]
                if cv then
                    if isbool(value) then
                        cv:SetBool(value)
                    elseif isnumber(value) then
                        cv:SetFloat(value)
                    end
                end
            end
        end
    end

    local function SyncSettingsFromConVars()
        RARELOAD.settings = RARELOAD.settings or {}

        for _, def in ipairs(CONVAR_DEFS) do
            local name, default, _, settingsKey = def[1], def[2], def[3], def[4]
            local cv = RARELOAD.ConVars[name]

            if cv then
                RARELOAD.settings[settingsKey] = ReadConVarValue(cv, default)
            end
        end
    end

    hook.Add("RareloadSettingsLoaded", "SyncConVarsFromSettings", SyncConVarsFromSettings)

    for _, def in ipairs(CONVAR_DEFS) do
        local name, default, _, settingsKey = def[1], def[2], def[3], def[4]

        cvars.AddChangeCallback(name, function(convar, oldVal, newVal)
            if not RARELOAD.settings then return end

            RARELOAD.settings[settingsKey] = CoerceConVarString(newVal, default)

            if RARELOAD.SaveAddonState then
                RARELOAD.SaveAddonState()
            end

            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD] Setting changed: " .. settingsKey .. " = " .. tostring(RARELOAD.settings[settingsKey]))
            end
        end, "RareloadSync_" .. name)
    end

    RARELOAD.SyncConVarsFromSettings = SyncConVarsFromSettings
    RARELOAD.SyncSettingsFromConVars = SyncSettingsFromConVars
else
    for _, def in ipairs(CONVAR_DEFS) do
        local name = def[1]
        RARELOAD.ConVars[name] = GetConVar(name)
    end

    function RARELOAD.GetConVarBool(name)
        local cv = GetConVar(name)
        return cv and cv:GetBool() or false
    end

    function RARELOAD.GetConVarNumber(name)
        local cv = GetConVar(name)
        return cv and cv:GetFloat() or 0
    end

    function RARELOAD.LoadSettingsFromConVars()
        RARELOAD.settings = RARELOAD.settings or {}
        for _, def in ipairs(CONVAR_DEFS) do
            local name, default, _, settingsKey = def[1], def[2], def[3], def[4]
            local cv = GetConVar(name)
            if cv then
                RARELOAD.settings[settingsKey] = ReadConVarValue(cv, default)
            end
        end
    end

    -- Keep RARELOAD.settings in sync when replicated ConVars change
    for _, def in ipairs(CONVAR_DEFS) do
        local name, default, _, settingsKey = def[1], def[2], def[3], def[4]

        cvars.AddChangeCallback(name, function(convar, oldVal, newVal)
            RARELOAD.settings = RARELOAD.settings or {}
            RARELOAD.settings[settingsKey] = CoerceConVarString(newVal, default)
        end, "RareloadClientSync_" .. name)
    end

    -- Initialize settings from ConVars as soon as the client is ready
    hook.Add("InitPostEntity", "RareloadClientSettingsInit", function()
        RARELOAD.LoadSettingsFromConVars()
    end)
end

return RARELOAD.ConVars
