if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.PlayerSettings = RARELOAD.PlayerSettings or {}

-- Cache of per-player settings in memory
local playerSettingsCache = {}

-- Get default settings for a new player (from server ConVars)
local function GetServerDefaultSettings()
    local defaults = {}
    
    -- Read from ConVars (server-wide defaults)
    if RARELOAD.ConVars then
        for convarName, settingKey in pairs(RARELOAD.ConVarToSetting or {}) do
            local cv = RARELOAD.ConVars[convarName]
            if cv then
                local defaultValue = cv:GetDefault()
                if defaultValue == "0" or defaultValue == "1" then
                    defaults[settingKey] = cv:GetBool()
                else
                    defaults[settingKey] = cv:GetFloat()
                end
            end
        end
    end
    
    -- Fallback to hardcoded defaults
    if table.Count(defaults) == 0 then
        defaults = {
            addonEnabled = true,
            spawnModeEnabled = true,
            autoSaveEnabled = false,
            retainInventory = true,
            retainGlobalInventory = false,
            retainHealthArmor = true,
            retainPlayerStates = true,
            retainAmmo = true,
            retainVehicleState = false,
            retainMapEntities = true,
            retainMapNPCs = true,
            retainVehicles = false,
            nocustomrespawnatdeath = false,
            debugEnabled = false,
            maxHistorySize = 125,
            autoSaveInterval = 5,
            angleTolerance = 100,
            maxDistance = 50
        }
    end
    
    return defaults
end

local function SafePlayerSettingsKey(steamID)
    return string.gsub(steamID or "unknown", "[^%w_%-.]", "_")
end

-- Get file path for player settings
local function GetPlayerSettingsPath(steamID)
    return "rareload/player_settings/" .. SafePlayerSettingsKey(steamID) .. ".json"
end

-- Ensure player settings folder exists
local function EnsurePlayerSettingsFolderExists()
    if not file.Exists("rareload/player_settings", "DATA") then
        file.CreateDir("rareload/player_settings")
    end
end

-- Load settings for a specific player
function RARELOAD.PlayerSettings.Load(steamID)
    if not steamID or steamID == "" then return nil end
    
    -- Check cache first
    if playerSettingsCache[steamID] then
        return playerSettingsCache[steamID]
    end
    
    -- Try to load from file
    local filePath = GetPlayerSettingsPath(steamID)
    
    if file.Exists(filePath, "DATA") then
        local json = file.Read(filePath, "DATA")
        local success, settings = pcall(util.JSONToTable, json)
        
        if success and settings then
            playerSettingsCache[steamID] = settings
            
            if RARELOAD.Debug and RARELOAD.Debug.Log then
                RARELOAD.Debug.Log("INFO", "Player Settings Loaded", {
                    steamID = steamID,
                    settingsCount = table.Count(settings)
                })
            end
            
            return settings
        else
            print("[RARELOAD] Failed to load player settings for " .. steamID .. ": " .. tostring(settings))
        end
    end
    
    -- No file exists, create new settings from server defaults
    local defaults = GetServerDefaultSettings()
    playerSettingsCache[steamID] = defaults
    
    -- Save the new defaults
    RARELOAD.PlayerSettings.Save(steamID, defaults)
    
    return defaults
end

-- Save settings for a specific player
function RARELOAD.PlayerSettings.Save(steamID, settings)
    if not steamID or steamID == "" then return false end
    if not settings then return false end
    
    EnsurePlayerSettingsFolderExists()
    
    -- Update cache
    playerSettingsCache[steamID] = settings
    
    -- Save to file
    local filePath = GetPlayerSettingsPath(steamID)
    local json = util.TableToJSON(settings, true)
    local success, err = pcall(file.Write, filePath, json)
    
    if not success then
        print("[RARELOAD] Failed to save player settings for " .. steamID .. ": " .. tostring(err))
        return false
    end
    
    if RARELOAD.Debug and RARELOAD.Debug.Log then
        RARELOAD.Debug.Log("INFO", "Player Settings Saved", {
            steamID = steamID,
            settingsCount = table.Count(settings)
        })
    end
    
    return true
end

-- Get a player setting value
function RARELOAD.PlayerSettings.Get(ply)
    if not IsValid(ply) then return GetServerDefaultSettings() end
    
    local steamID = ply:SteamID()
    return RARELOAD.PlayerSettings.Load(steamID)
end

-- Get a specific setting value for a player
function RARELOAD.PlayerSettings.GetValue(ply, settingKey, default)
    if not IsValid(ply) then
        -- Return server default
        if RARELOAD.settings and RARELOAD.settings[settingKey] ~= nil then
            return RARELOAD.settings[settingKey]
        end
        return default
    end
    
    local settings = RARELOAD.PlayerSettings.Get(ply)
    if not istable(settings) then
        return default
    end

    if settings[settingKey] ~= nil then
        return settings[settingKey]
    end
    
    return default
end

-- Update a specific setting for a player
function RARELOAD.PlayerSettings.Set(ply, settingKey, value)
    if not IsValid(ply) then return false end
    
    local steamID = ply:SteamID()
    local settings = RARELOAD.PlayerSettings.Load(steamID)
    
    settings[settingKey] = value
    
    return RARELOAD.PlayerSettings.Save(steamID, settings)
end

-- Clear cache for a player (useful when player disconnects)
function RARELOAD.PlayerSettings.ClearCache(steamID)
    if steamID and playerSettingsCache[steamID] then
        playerSettingsCache[steamID] = nil
    end
end

-- Network player settings to client
util.AddNetworkString("RareloadSyncPlayerSettings")

function RARELOAD.PlayerSettings.SyncToPlayer(ply)
    if not IsValid(ply) then return end

    local settings = RARELOAD.PlayerSettings.Get(ply)
    if not istable(settings) then
        settings = GetServerDefaultSettings()
    end

    net.Start("RareloadSyncPlayerSettings")
    net.WriteTable(settings)
    net.Send(ply)
    
    if RARELOAD.Debug and RARELOAD.Debug.Log then
        RARELOAD.Debug.Log("VERBOSE", "Player Settings Synced", {
            player = ply:Nick(),
            steamID = ply:SteamID()
        })
    end
end

-- Receive setting changes from client
util.AddNetworkString("RareloadUpdatePlayerSetting")

net.Receive("RareloadUpdatePlayerSetting", function(len, ply)
    if not IsValid(ply) then return end
    
    local settingKey = net.ReadString()
    local valueType = net.ReadString()
    local value
    
    if valueType == "bool" then
        value = net.ReadBool()
    elseif valueType == "number" then
        value = net.ReadFloat()
    elseif valueType == "string" then
        value = net.ReadString()
    else
        return
    end
    
    -- Update player's setting
    RARELOAD.PlayerSettings.Set(ply, settingKey, value)
    
    -- Sync back to player (and potentially others if needed)
    RARELOAD.PlayerSettings.SyncToPlayer(ply)
    
    if RARELOAD.Debug and RARELOAD.Debug.Log then
        RARELOAD.Debug.Log("INFO", "Player Setting Updated", {
            player = ply:Nick(),
            settingKey = settingKey,
            value = tostring(value)
        })
    end
end)

-- Hook to sync settings when player joins
hook.Add("PlayerInitialSpawn", "RareloadSyncPlayerSettings", function(ply)
    -- Load settings immediately so HandlePlayerSpawn has the correct data
    if IsValid(ply) and ply:SteamID() ~= "" then
        RARELOAD.PlayerSettings.Load(ply:SteamID())
    end

    -- Sync to client once the player is fully ready
    timer.Simple(0, function()
        if IsValid(ply) then
            RARELOAD.PlayerSettings.SyncToPlayer(ply)
        end
    end)
end)

-- Hook to clear cache when player disconnects (optional, for memory management)
hook.Add("PlayerDisconnected", "RareloadClearPlayerSettingsCache", function(ply)
    if IsValid(ply) then
        local steamID = ply:SteamID()
        -- Don't clear cache immediately - keep it for a while in case they rejoin
        timer.Simple(300, function() -- Clear after 5 minutes
            RARELOAD.PlayerSettings.ClearCache(steamID)
        end)
    end
end)
-- Convenience function: Get player's setting value with fallback to global
-- Usage: local keepInventory = RARELOAD.GetPlayerSetting(ply, "retainInventory")
function RARELOAD.GetPlayerSetting(ply, settingKey, default)
    if RARELOAD.PlayerSettings and RARELOAD.PlayerSettings.GetValue then
        return RARELOAD.PlayerSettings.GetValue(ply, settingKey, default)
    end
    
    -- Fallback to global settings if player settings system not loaded
    if RARELOAD.settings and RARELOAD.settings[settingKey] ~= nil then
        return RARELOAD.settings[settingKey]
    end
    
    return default
end
print("[RARELOAD] Per-player settings system loaded")
