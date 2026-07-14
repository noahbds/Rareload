RARELOAD = RARELOAD or {}
RARELOAD.ConVars = RARELOAD.ConVars or {}

local CONVAR_DEFS = {
    { "sv_rareload_enabled",               "1",   "Enable/disable Rareload addon",                                                                                                 "addonEnabled",                     "bool" },
    { "sv_rareload_spawn_mode",            "1",   "Enable anti-stuck spawn system",                                                                                                "spawnModeEnabled",                 "bool" },
    { "sv_rareload_auto_save",             "0",   "Enable automatic position saving",                                                                                              "autoSaveEnabled",                  "bool" },
    { "sv_rareload_no_custom_death",       "0",   "Disable custom respawn on death",                                                                                               "nocustomrespawnatdeath",           "bool" },
    { "sv_rareload_debug",                 "0",   "Enable debug logging",                                                                                                          "debugEnabled",                     "bool" },

    { "sv_rareload_keep_health",           "1",   "Keep health and armor on respawn",                                                                                              "retainHealthArmor",                "bool" },
    { "sv_rareload_keep_states",           "1",   "Keep player states (godmode, notarget, etc.)",                                                                                  "retainPlayerStates",               "bool" },
    { "sv_rareload_keep_inventory",        "1",   "Keep inventory on respawn",                                                                                                     "retainInventory",                  "bool" },
    { "sv_rareload_keep_ammo",             "1",   "Keep ammunition on respawn",                                                                                                    "retainAmmo",                       "bool" },
    { "sv_rareload_global_inventory",      "0",   "Enable global inventory sharing",                                                                                               "retainGlobalInventory",            "bool" },

    { "sv_rareload_keep_map_entities",     "1",   "Keep map entities on respawn",                                                                                                  "retainMapEntities",                "bool" },
    { "sv_rareload_keep_map_npcs",         "1",   "Keep map NPCs on respawn",                                                                                                      "retainMapNPCs",                    "bool" },
    { "sv_rareload_auto_overwrite",        "0",   "On save, overwrite already-saved entities/NPCs that were moved or changed (off preserves their old saved state)",               "autoOverwriteModified",            "bool" },
    { "sv_rareload_cleanup_map",           "0",   "Clean up the map right before respawning",                                                                                      "cleanupMapAfterDeath",             "bool" },
    { "sv_rareload_cleanup_owned_only",    "0",   "When cleanup on death is enabled, only remove the player's own Rareload-spawned entities/NPCs instead of wiping the whole map", "cleanupOnlyOwnedEntitiesOnDeath",  "bool" },
    { "sv_rareload_cleanup_only_saved",    "0",   "When cleanup on death is enabled, only remove entities/NPCs that were saved by Rareload instead of wiping the whole map",       "cleanupOnlySavedEntitiesOnDeath",  "bool" },
    { "sv_rareload_cleanup_on_disconnect", "0",   "Remove the player's owned entities and NPCs when they disconnect",                                                              "cleanupOwnedEntitiesOnDisconnect", "bool" },

    { "sv_rareload_auto_save_interval",    "0",   "Seconds between auto saves",                                                                                                    "autoSaveInterval",                 "number" },
    { "sv_rareload_angle_tolerance",       "100", "Angle tolerance for entity restoration",                                                                                        "angleTolerance",                   "number" },
    { "sv_rareload_history_size",          "125", "Maximum position history entries",                                                                                              "maxHistorySize",                   "number" },
}
RARELOAD.ConVarToSetting = {}
RARELOAD.SettingToConVar = {}
RARELOAD.ConVarIsBool = {}

for _, def in ipairs(CONVAR_DEFS) do
    RARELOAD.ConVarToSetting[def[1]] = def[4]
    RARELOAD.SettingToConVar[def[4]] = def[1]
    RARELOAD.ConVarIsBool[def[1]] = (def[5] == "bool")
end

local function ReadConVarValue(cv, isBool)
    if isBool then return cv:GetBool() end
    return cv:GetFloat()
end

local function CoerceConVarString(newVal, isBool)
    if isBool then return newVal == "1" end
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
            local name, settingsKey = def[1], def[4]
            local cv = RARELOAD.ConVars[name]

            if cv then
                RARELOAD.settings[settingsKey] = ReadConVarValue(cv, def[5] == "bool")
            end
        end
    end

    hook.Add("RareloadSettingsLoaded", "SyncConVarsFromSettings", SyncConVarsFromSettings)

    for _, def in ipairs(CONVAR_DEFS) do
        local name, settingsKey, isBool = def[1], def[4], def[5] == "bool"

        cvars.AddChangeCallback(name, function(convar, oldVal, newVal)
            if not RARELOAD.settings then return end

            RARELOAD.settings[settingsKey] = CoerceConVarString(newVal, isBool)

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
            local name, settingsKey = def[1], def[4]
            local cv = GetConVar(name)
            if cv then
                RARELOAD.settings[settingsKey] = ReadConVarValue(cv, def[5] == "bool")
            end
        end
    end

    for _, def in ipairs(CONVAR_DEFS) do
        local name, settingsKey, isBool = def[1], def[4], def[5] == "bool"

        cvars.AddChangeCallback(name, function(convar, oldVal, newVal)
            RARELOAD.settings = RARELOAD.settings or {}
            RARELOAD.settings[settingsKey] = CoerceConVarString(newVal, isBool)
        end, "RareloadClientSync_" .. name)
    end

    hook.Add("InitPostEntity", "RareloadClientSettingsInit", function()
        RARELOAD.LoadSettingsFromConVars()
    end)
end

return RARELOAD.ConVars
