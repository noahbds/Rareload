RARELOAD = RARELOAD or {}
RARELOAD.ConVars = RARELOAD.ConVars or {}

local CONVAR_DEFS = {
    { "sv_rareload_enabled",            "1", "Enable/disable Rareload addon",                    "addonEnabled" },
    { "sv_rareload_spawn_mode",         "1", "Enable anti-stuck spawn system",                   "spawnModeEnabled" },
    { "sv_rareload_auto_save",          "0", "Enable automatic position saving",                 "autoSaveEnabled" },
    { "sv_rareload_no_custom_death",    "0", "Disable custom respawn on death",                  "nocustomrespawnatdeath" },
    { "sv_rareload_debug",              "0", "Enable debug logging",                             "debugEnabled" },
    
    { "sv_rareload_keep_health",        "1", "Keep health and armor on respawn",                 "retainHealthArmor" },
    { "sv_rareload_keep_states",        "1", "Keep player states (godmode, notarget, etc.)",     "retainPlayerStates" },
    { "sv_rareload_keep_inventory",     "1", "Keep inventory on respawn",                        "retainInventory" },
    { "sv_rareload_keep_ammo",          "1", "Keep ammunition on respawn",                       "retainAmmo" },
    { "sv_rareload_global_inventory",   "0", "Enable global inventory sharing",                  "retainGlobalInventory" },
    
    { "sv_rareload_keep_map_entities",  "1", "Keep map entities on respawn",                     "retainMapEntities" },
    { "sv_rareload_keep_map_npcs",      "1", "Keep map NPCs on respawn",                         "retainMapNPCs" },
    
    { "sv_rareload_auto_save_interval", "5",   "Seconds between auto saves",                     "autoSaveInterval" },
    { "sv_rareload_angle_tolerance",    "100", "Angle tolerance for entity restoration",         "angleTolerance" },
    { "sv_rareload_history_size",       "125", "Maximum position history entries",               "maxHistorySize" },
}

RARELOAD.ConVarToSetting = {}
RARELOAD.SettingToConVar = {}

for _, def in ipairs(CONVAR_DEFS) do
    RARELOAD.ConVarToSetting[def[1]] = def[4]
    RARELOAD.SettingToConVar[def[4]] = def[1]
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
                if default == "0" or default == "1" then
                    RARELOAD.settings[settingsKey] = cv:GetBool()
                else
                    RARELOAD.settings[settingsKey] = cv:GetFloat()
                end
            end
        end
    end
    
    hook.Add("RareloadSettingsLoaded", "SyncConVarsFromSettings", SyncConVarsFromSettings)
    
    for _, def in ipairs(CONVAR_DEFS) do
        local name, default, _, settingsKey = def[1], def[2], def[3], def[4]
        
        cvars.AddChangeCallback(name, function(convar, oldVal, newVal)
            if not RARELOAD.settings then return end
            
            if default == "0" or default == "1" then
                RARELOAD.settings[settingsKey] = (newVal == "1")
            else
                RARELOAD.settings[settingsKey] = tonumber(newVal) or 0
            end
            
            if RARELOAD.SaveAddonState then
                RARELOAD.SaveAddonState()
            end
            
            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD] Setting changed: " .. settingsKey .. " = " .. tostring(RARELOAD.settings[settingsKey]))
            end
        end, "RareloadSync_" .. name)
    end
    
    util.AddNetworkString("RareloadSetConVar")
    
    net.Receive("RareloadSetConVar", function(len, ply)
        if not IsValid(ply) then return end
        
        if not RARELOAD.CheckPermission(ply, "RARELOAD_TOGGLE") then
            ply:ChatPrint("[RARELOAD] You don't have permission to change settings.")
            return
        end
        
        local convarName = net.ReadString()
        local value = net.ReadString()
        
        if not RARELOAD.ConVars[convarName] then
            ply:ChatPrint("[RARELOAD] Invalid setting: " .. convarName)
            return
        end
        
        -- NEW: Instead of changing server ConVar (which affects everyone),
        -- update this player's personal settings
        local settingKey = RARELOAD.ConVarToSetting[convarName]
        if settingKey and RARELOAD.PlayerSettings then
            -- Convert value to appropriate type
            local convertedValue
            local def = nil
            for _, d in ipairs(CONVAR_DEFS) do
                if d[1] == convarName then
                    def = d
                    break
                end
            end
            
            if def and (def[2] == "0" or def[2] == "1") then
                convertedValue = (value == "1")
            else
                convertedValue = tonumber(value) or 0
            end
            
            -- Update player's personal settings
            RARELOAD.PlayerSettings.Set(ply, settingKey, convertedValue)
            
            -- Sync back to player
            RARELOAD.PlayerSettings.SyncToPlayer(ply)
            
            if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
                print("[RARELOAD] " .. ply:Nick() .. " changed their " .. settingKey .. " to " .. tostring(convertedValue))
            end
        else
            -- Fallback to old behavior if player settings system not loaded
            RunConsoleCommand(convarName, value)
            
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD] " .. ply:Nick() .. " changed " .. convarName .. " to " .. value)
            end
        end
    end)
    
    RARELOAD.SyncConVarsFromSettings = SyncConVarsFromSettings
    RARELOAD.SyncSettingsFromConVars = SyncSettingsFromConVars
    
else

    for _, def in ipairs(CONVAR_DEFS) do
        local name = def[1]
        RARELOAD.ConVars[name] = GetConVar(name)
    end
    
    function RARELOAD.SetConVar(name, value)
        net.Start("RareloadSetConVar")
        net.WriteString(name)
        net.WriteString(tostring(value))
        net.SendToServer()
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
                if default == "0" or default == "1" then
                    RARELOAD.settings[settingsKey] = cv:GetBool()
                else
                    RARELOAD.settings[settingsKey] = cv:GetFloat()
                end
            end
        end
    end

    -- Keep RARELOAD.settings in sync when replicated ConVars change
    for _, def in ipairs(CONVAR_DEFS) do
        local name, default, _, settingsKey = def[1], def[2], def[3], def[4]
        
        cvars.AddChangeCallback(name, function(convar, oldVal, newVal)
            RARELOAD.settings = RARELOAD.settings or {}
            if default == "0" or default == "1" then
                RARELOAD.settings[settingsKey] = (newVal == "1")
            else
                RARELOAD.settings[settingsKey] = tonumber(newVal) or 0
            end
        end, "RareloadClientSync_" .. name)
    end

    -- Initialize settings from ConVars as soon as the client is ready
    hook.Add("InitPostEntity", "RareloadClientSettingsInit", function()
        RARELOAD.LoadSettingsFromConVars()
    end)

end

return RARELOAD.ConVars
