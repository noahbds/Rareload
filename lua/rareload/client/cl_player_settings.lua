if not CLIENT then return end

RARELOAD = RARELOAD or {}
RARELOAD.MySettings = RARELOAD.MySettings or {}

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
    
    if RARELOAD.settings.debugEnabled then
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
function RARELOAD.RequestPlayerSettings()
    -- For now, settings are auto-synced on join
    -- Could add a net message to request refresh if needed
    print("[RARELOAD CLIENT] Player settings will be synced on join")
end

print("[RARELOAD] Client player settings module loaded")
