if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.PlayerSettings = RARELOAD.PlayerSettings or {}

local playerSettingsCache = {}
local lastSettingsSyncAt = {}
local SETTINGS_SYNC_COOLDOWN = 0.75
local DebugHelpers = include("rareload/debug/sv_debug_helpers.lua")

local function GetServerDefaultSettings()
    ---@type table<string, boolean|number>
    local defaults = {}

    for convarName, settingKey in pairs(RARELOAD.ConVarToSetting or {}) do
        local cv = RARELOAD.ConVars[convarName]
        if cv then
            if RARELOAD.ConVarIsBool[convarName] then
                defaults[settingKey] = cv:GetBool()
            else
                defaults[settingKey] = cv:GetFloat()
            end
        end
    end

    return defaults
end

local function SafePlayerSettingsKey(steamID)
    return string.gsub(steamID or "unknown", "[^%w_%-.]", "_")
end

local function GetPlayerSettingsPath(steamID)
    return "rareload/player_settings/" .. SafePlayerSettingsKey(steamID) .. ".json"
end

local function EnsurePlayerSettingsFolderExists()
    if not file.Exists("rareload/player_settings", "DATA") then
        file.CreateDir("rareload/player_settings")
    end
end

local function WriteSettingsDebug(level, message, details, context)
    if not (DebugHelpers and DebugHelpers.Write) then return end

    DebugHelpers.Write("settings", level, message, details, {
        context = context,
        detailsAsPairs = true
    })
end

local function SanitizeSettings(loaded, defaults)
    loaded = istable(loaded) and loaded or {}
    local out = {}
    for key, def in pairs(defaults) do
        local v = loaded[key]
        if type(v) == type(def) then
            out[key] = v
        elseif type(def) == "number" then
            out[key] = tonumber(v) or def
        elseif type(def) == "boolean" then
            out[key] = (v == true) or (v == 1) or (v == "1") or (v == "true")
        else
            out[key] = def
        end
    end
    return out
end

function RARELOAD.PlayerSettings.Load(steamID)
    if not steamID or steamID == "" then return nil end

    if playerSettingsCache[steamID] then
        return playerSettingsCache[steamID]
    end

    local filePath = GetPlayerSettingsPath(steamID)

    if file.Exists(filePath, "DATA") then
        local json = file.Read(filePath, "DATA")
        local success, settings = pcall(util.JSONToTable, json)

        if success and settings then
            settings = SanitizeSettings(settings, GetServerDefaultSettings())
            playerSettingsCache[steamID] = settings

            WriteSettingsDebug("INFO", "Player settings loaded", {
                steamID = steamID,
                settingsCount = table.Count(settings)
            })

            return settings
        else
            print("[RARELOAD] Failed to load player settings for " .. steamID .. ": " .. tostring(settings))
        end
    end

    local defaults = GetServerDefaultSettings()
    playerSettingsCache[steamID] = defaults

    RARELOAD.PlayerSettings.Save(steamID, defaults)

    return defaults
end

function RARELOAD.PlayerSettings.Save(steamID, settings)
    if not steamID or steamID == "" then return false end
    if not settings then return false end

    EnsurePlayerSettingsFolderExists()

    playerSettingsCache[steamID] = settings

    local filePath = GetPlayerSettingsPath(steamID)
    local json = util.TableToJSON(settings, true)
    local success, err = pcall(file.Write, filePath, json)

    if not success then
        print("[RARELOAD] Failed to save player settings for " .. steamID .. ": " .. tostring(err))
        return false
    end

    WriteSettingsDebug("INFO", "Player settings saved", {
        steamID = steamID,
        settingsCount = table.Count(settings)
    })

    return true
end

function RARELOAD.PlayerSettings.Get(ply)
    if not IsValid(ply) then return GetServerDefaultSettings() end

    local steamID = ply:SteamID()
    return RARELOAD.PlayerSettings.Load(steamID)
end

function RARELOAD.PlayerSettings.GetValue(ply, settingKey, default)
    if settingKey == nil then
        return default
    end

    local key = tostring(settingKey)

    if not IsValid(ply) then
        if RARELOAD.settings and RARELOAD.settings[key] ~= nil then
            return RARELOAD.settings[key]
        end
        return default
    end

    local settings = RARELOAD.PlayerSettings.Get(ply)
    if not istable(settings) then
        return default
    end

    local settingValue = settings[key]
    if settingValue ~= nil then
        return settingValue
    end

    return default
end

function RARELOAD.PlayerSettings.Set(ply, settingKey, value)
    if not IsValid(ply) then return false end
    local steamID = ply:SteamID()
    local settings = RARELOAD.PlayerSettings.Load(steamID)

    settings[settingKey] = value

    return RARELOAD.PlayerSettings.Save(steamID, settings)
end

function RARELOAD.PlayerSettings.ClearCache(steamID)
    if steamID and playerSettingsCache[steamID] then
        playerSettingsCache[steamID] = nil
    end
end

util.AddNetworkString("RareloadSyncPlayerSettings")

function RARELOAD.PlayerSettings.SyncToPlayer(ply, force)
    if not IsValid(ply) then return false end

    local steamID = ply:SteamID()
    local now = CurTime()
    if not force and lastSettingsSyncAt[steamID] and (now - lastSettingsSyncAt[steamID]) < SETTINGS_SYNC_COOLDOWN then
        return false
    end

    local settings = RARELOAD.PlayerSettings.Get(ply)
    local syncedSettings = istable(settings) and settings or GetServerDefaultSettings()

    net.Start("RareloadSyncPlayerSettings")
    net.WriteTable(syncedSettings)
    net.Send(ply)
    lastSettingsSyncAt[steamID] = now

    WriteSettingsDebug("VERBOSE", "Player settings synced", {
        player = ply:Nick(),
        steamID = steamID
    }, { entity = ply })

    return true
end

util.AddNetworkString("RareloadUpdatePlayerSetting")
util.AddNetworkString("RareloadRequestPlayerSettings")

local ALLOWED_CLIENT_SETTINGS = {
    addonEnabled = "bool",
    spawnModeEnabled = "bool",
    autoSaveEnabled = "bool",
    autoSaveInterval = "number",
    maxHistorySize = "number",
    retainInventory = "bool",
    retainGlobalInventory = "bool",
    retainHealthArmor = "bool",
    retainAmmo = "bool",
    retainPlayerStates = "bool",
    debugEnabled = "bool",
    nocustomrespawnatdeath = "bool",
    retainVehicleState = "bool",
    retainMapEntities = "bool",
    autoOverwriteModified = "bool",
    cleanupMapAfterDeath = "bool",
    cleanupOnlyOwnedEntitiesOnDeath = "bool",
    cleanupOnlySavedEntitiesOnDeath = "bool",
    cleanupOwnedEntitiesOnDisconnect = "bool",
    retainMapNPCs = "bool",
    retainVehicles = "bool",
    angleTolerance = "number",
    maxDistance = "number",
}

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

    local expectedType = ALLOWED_CLIENT_SETTINGS[settingKey]
    if not expectedType then
        print("[RARELOAD] Player " .. ply:Nick() .. " attempted to modify restricted setting: " .. tostring(settingKey))
        return
    end

    if valueType ~= expectedType then
        print("[RARELOAD] Player " ..
            ply:Nick() .. " sent wrong type for " .. settingKey .. ": expected " .. expectedType .. ", got " .. valueType)
        return
    end

    if valueType == "number" and type(value) == "number" then
        if settingKey == "angleTolerance" then
            value = math.Clamp(value, 1, 360)
        elseif settingKey == "maxDistance" then
            value = math.Clamp(value, 1, 500)
        elseif settingKey == "autoSaveInterval" then
            value = math.Clamp(value, 0, 60)
        elseif settingKey == "maxHistorySize" then
            value = math.Clamp(math.Round(value), 1, 150)
        end
    end

    RARELOAD.PlayerSettings.Set(ply, settingKey, value)

    RARELOAD.PlayerSettings.SyncToPlayer(ply, true)

    WriteSettingsDebug("INFO", "Player setting updated", {
        player = ply:Nick(),
        settingKey = settingKey,
        value = tostring(value)
    }, { entity = ply })
end)

net.Receive("RareloadRequestPlayerSettings", function(_, ply)
    if not IsValid(ply) then return end
    local synced = RARELOAD.PlayerSettings.SyncToPlayer(ply, false)

    if synced then
        WriteSettingsDebug("VERBOSE", "Player settings resync requested", {
            player = ply:Nick(),
            steamID = ply:SteamID()
        }, { entity = ply })
    end
end)

hook.Add("PlayerInitialSpawn", "RareloadSyncPlayerSettings", function(ply)
    if IsValid(ply) and ply:SteamID() ~= "" then
        RARELOAD.PlayerSettings.Load(ply:SteamID())
    end

    timer.Simple(0, function()
        if IsValid(ply) then
            RARELOAD.PlayerSettings.SyncToPlayer(ply, true)
        end
    end)
end)

hook.Add("PlayerDisconnected", "RareloadClearPlayerSettingsCache", function(ply)
    if IsValid(ply) then
        local steamID = ply:SteamID()
        timer.Simple(300, function()
            RARELOAD.PlayerSettings.ClearCache(steamID)
        end)
    end
end)

hook.Add("PostCleanupMap", "RareloadResyncPlayerSettingsAfterCleanup", function()
    timer.Simple(0, function()
        for _, ply in ipairs(player.GetHumans()) do
            if IsValid(ply) then
                RARELOAD.PlayerSettings.SyncToPlayer(ply, true)
            end
        end
    end)
end)

function RARELOAD.GetPlayerSetting(ply, settingKey, default)
    if RARELOAD.PlayerSettings and RARELOAD.PlayerSettings.GetValue then
        return RARELOAD.PlayerSettings.GetValue(ply, settingKey, default)
    end

    if RARELOAD.settings and RARELOAD.settings[settingKey] ~= nil then
        return RARELOAD.settings[settingKey]
    end

    return default
end

print("[RARELOAD] Per-player settings system loaded")
