if not CLIENT then return end

RARELOAD = RARELOAD or {}
RARELOAD.MySettings = RARELOAD.MySettings or {}
RARELOAD.settings = RARELOAD.settings or {}

local function IsClientDebugEnabled()
    if RARELOAD.MySettings and RARELOAD.MySettings.debugEnabled ~= nil then
        return RARELOAD.MySettings.debugEnabled == true
    end

    if RARELOAD.settings and RARELOAD.settings.debugEnabled ~= nil then
        return RARELOAD.settings.debugEnabled == true
    end

    return false
end

RARELOAD.IsDebugEnabled = IsClientDebugEnabled

local lastSettingsRequestAt = 0
local SETTINGS_REQUEST_COOLDOWN = 1.0

-- Receive player settings from server
net.Receive("RareloadSyncPlayerSettings", function()
    local settings = net.ReadTable()

    if settings then
        RARELOAD.MySettings = settings

        -- Update RARELOAD.settings for backward compatibility
        RARELOAD.settings = table.Copy(settings)

        -- Trigger hook for UI updates
        hook.Run("RareloadPlayerSettingsUpdated", settings)
    end
end)

-- Send a setting update to server
function RARELOAD.UpdatePlayerSetting(settingKey, value)
    if not settingKey then return end

    -- Determine value type
    local valueType = type(value)
    if valueType == "boolean" then
        valueType = "bool"
    elseif valueType == "number" then
        valueType = "number"
    elseif valueType == "string" then
        valueType = "string"
    else
        print("[RARELOAD CLIENT] Unsupported setting value type: " .. valueType)
        return
    end

    -- Send to server
    net.Start("RareloadUpdatePlayerSetting")
    net.WriteString(settingKey)
    net.WriteString(valueType)

    if valueType == "bool" then
        net.WriteBool(value)
    elseif valueType == "number" then
        net.WriteFloat(value)
    elseif valueType == "string" then
        net.WriteString(value)
    end

    net.SendToServer()

    -- Update local copy optimistically
    RARELOAD.MySettings[settingKey] = value
    RARELOAD.settings[settingKey] = value

    if IsClientDebugEnabled() then
        print("[RARELOAD CLIENT] Updated setting: " .. settingKey .. " = " .. tostring(value))
    end
end

-- Get a player setting value
function RARELOAD.GetPlayerSetting(settingKey, default)
    if RARELOAD.MySettings[settingKey] ~= nil then
        return RARELOAD.MySettings[settingKey]
    end
    return default
end

-- Request settings from server (in case sync was missed)
function RARELOAD.RequestPlayerSettings(options)
    options = options or {}
    local force = options.force == true
    local silent = options.silent
    if silent == nil then
        silent = true
    end

    local now = CurTime()
    if not force and (now - lastSettingsRequestAt) < SETTINGS_REQUEST_COOLDOWN then
        return false
    end

    lastSettingsRequestAt = now

    net.Start("RareloadRequestPlayerSettings")
    net.SendToServer()

    if (not silent) and IsClientDebugEnabled() then
        print("[RARELOAD CLIENT] Requested player settings sync")
    end

    return true
end

hook.Add("InitPostEntity", "RareloadRequestPlayerSettings_OnInitPostEntity", function()
    timer.Simple(0.25, function()
        if IsValid(LocalPlayer()) and RARELOAD and RARELOAD.RequestPlayerSettings then
            if not RARELOAD.MySettings or not next(RARELOAD.MySettings) then
                RARELOAD.RequestPlayerSettings({ silent = true })
            end
        end
    end)
end)

print("[RARELOAD] Client player settings module loaded")
