if not SERVER then return {} end

RARELOAD = RARELOAD or {}
RARELOAD.DebugState = RARELOAD.DebugState or {}

local DebugState = RARELOAD.DebugState

local function IsGlobalDebugEnabled()
    return RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled == true
end

function DebugState.IsEnabledForPlayer(ply)
    if IsValid(ply) and RARELOAD and RARELOAD.GetPlayerSetting then
        local ok, enabled = pcall(RARELOAD.GetPlayerSetting, ply, "debugEnabled", false)
        if ok then
            return enabled == true
        end
    end

    if DEBUG_CONFIG and DEBUG_CONFIG.ENABLED then
        local ok, enabled = pcall(DEBUG_CONFIG.ENABLED, { entity = ply })
        if ok then
            return enabled == true
        end
    end

    return IsGlobalDebugEnabled()
end

function DebugState.IsAnyEnabled()
    if DEBUG_CONFIG and DEBUG_CONFIG.ENABLED then
        local ok, enabled = pcall(DEBUG_CONFIG.ENABLED)
        if ok then
            return enabled == true
        end
    end

    if player and player.GetAll and RARELOAD and RARELOAD.GetPlayerSetting then
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) then
                local ok, enabled = pcall(RARELOAD.GetPlayerSetting, ply, "debugEnabled", false)
                if ok and enabled == true then
                    return true
                end
            end
        end
    end

    return IsGlobalDebugEnabled()
end

return DebugState
