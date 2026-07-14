if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

AntiStuck.testingMode = AntiStuck.testingMode or false
AntiStuck.testingPlayers = AntiStuck.testingPlayers or {}
AntiStuck.originalStuckPositions = AntiStuck.originalStuckPositions or {}

AntiStuck.DefaultSettings = AntiStuck.DefaultSettings or {
    MAX_UNSTUCK_ATTEMPTS = 35,
    MAX_SEARCH_TIME = 1.5,
    DEBUG_LOGGING = false,
    ENABLE_CACHE = true,
    CACHE_DURATION = 900,

    SAFE_DISTANCE = 48,
    PLAYER_HULL_TOLERANCE = 8,
    MIN_GROUND_DISTANCE = 12,
    MAP_BOUNDS_PADDING = 128,

    HORIZONTAL_SEARCH_RANGE = 1536,
    MAX_TRACE_DISTANCE = 2048,
    ENTITY_SEARCH_RADIUS = 384,

    SPAWN_POINT_OFFSET_Z = 24,
    MAP_ENTITY_OFFSET_Z = 40,
    NAV_AREA_OFFSET_Z = 20,
    FALLBACK_HEIGHT = 8192,

    MAX_DISTANCE = 1200,

    DISPLACEMENT_STEP_SIZE = 64,
    DISPLACEMENT_MAX_HEIGHT = 800,
    EMERGENCY_SAFE_RADIUS = 160,
    RANDOM_ATTEMPTS = 25,

    RESPECT_PROFILE_ORDER = true,

    METHOD_TIMEOUT_MULTIPLIERS = {
        TryCachedPositions = 0.3,
        TryDisplacement = 0.5,
        TryNodeGraph = 1.0,
        TryMapEntities = 0.7,
        TryEmergencyTeleport = 0.2
    }
}

AntiStuck.DefaultMethods = AntiStuck.DefaultMethods or {
    { name = "Cached Positions",   func = "TryCachedPositions",   enabled = true, priority = 5,  timeout = 0.3, description = "Ultra-fast: Use proven safe positions" },
    { name = "Smart Displacement", func = "TryDisplacement",      enabled = true, priority = 10, timeout = 0.8, description = "Fast: Intelligent physics-based movement" },
    { name = "Navigation Mesh",    func = "TryNodeGraph",         enabled = true, priority = 15, timeout = 1.0, description = "Optimal: Source engine navigation system" },
    { name = "Map Entities",       func = "TryMapEntities",       enabled = true, priority = 20, timeout = 0.7, description = "Fast: Leverage map entities and spawn points" },
    { name = "Emergency Teleport", func = "TryEmergencyTeleport", enabled = true, priority = 45, timeout = 0.2, description = "Failsafe: Guaranteed positioning" }
}

AntiStuck.CONFIG = AntiStuck.CONFIG or RareloadDeepCopySettings(AntiStuck.DefaultSettings)

function AntiStuck.GetConfig(key)
    if AntiStuck.CONFIG[key] ~= nil then return AntiStuck.CONFIG[key] end
    return AntiStuck.DefaultSettings[key]
end

function AntiStuck.InvalidateMethodCache()
    if AntiStuck._invalidateResolverCache then
        AntiStuck._invalidateResolverCache()
    end
end

function AntiStuck.SetMethodEnabled(funcName, enabled)
    if not AntiStuck.methods then return false, "Methods not loaded" end

    for _, method in ipairs(AntiStuck.methods) do
        if method.func == funcName then
            method.enabled = enabled
            
            RARELOAD.settings = RARELOAD.settings or {}
            RARELOAD.settings.antiStuckMethods = RARELOAD.settings.antiStuckMethods or {}
            RARELOAD.settings.antiStuckMethods[funcName] = enabled
            if RARELOAD.SaveAddonState then
                RARELOAD.SaveAddonState()
            end
            
            AntiStuck.InvalidateMethodCache()
            AntiStuck.LogDebug(
                string.format("Method %s %s", funcName, enabled and "enabled" or "disabled"),
                { methodName = "SetMethodEnabled", func = funcName, enabled = enabled })
            return true
        end
    end

    return false, "Method '" .. tostring(funcName) .. "' not found"
end

function AntiStuck.GetMethodList()
    local result = {}
    for _, method in ipairs(AntiStuck.methods or {}) do
        result[#result + 1] = {
            name = method.name,
            func = method.func,
            enabled = method.enabled,
            priority = method.priority,
            timeout = method.timeout
        }
    end
    return result
end

function AntiStuck.DebugEnabled(ply)
    if RARELOAD and RARELOAD.GetPlayerSetting and IsValid(ply) then
        return RARELOAD.GetPlayerSetting(ply, "debugEnabled", false)
    end

    if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        return true
    end

    if RARELOAD and RARELOAD.GetPlayerSetting and player and player.GetHumans then
        for _, human in ipairs(player.GetHumans()) do
            if IsValid(human) and RARELOAD.GetPlayerSetting(human, "debugEnabled", false) then
                return true
            end
        end
    end

    return AntiStuck.CONFIG and AntiStuck.CONFIG.DEBUG_LOGGING or false
end

function AntiStuck.HasStructuredDebugWriter(ply)
    return AntiStuck.DebugEnabled(ply)
        and RARELOAD
        and RARELOAD.Debug
        and type(RARELOAD.Debug.AntiStuck) == "function"
end

function AntiStuck.HasDetailedMethodLogger(ply)
    return AntiStuck.DebugEnabled(ply)
        and RARELOAD
        and RARELOAD.Debug
        and type(RARELOAD.Debug.LogAntiStuck) == "function"
end

function AntiStuck.LogMethodDetail(eventName, methodName, details, ply)
    if not AntiStuck.HasDetailedMethodLogger(ply) then
        return false
    end

    RARELOAD.Debug.LogAntiStuck(eventName, methodName, details, ply)
    return true
end

function AntiStuck.LogDebug(message, data, player, level)
    if RARELOAD.Debug and RARELOAD.Debug.Write then
        level = level or "INFO"
        RARELOAD.Debug.Write("anti_stuck", level, 0, message, { entity = player })
    elseif RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck(message, data, player, level)
    elseif AntiStuck.DebugEnabled() then
        print("[RARELOAD ANTI-STUCK] " .. tostring(message))
    end
end

AntiStuck.performanceStats = AntiStuck.performanceStats or {
    totalCalls = 0,
    successfulCalls = 0,
    averageTime = 0,
    methodSuccessRates = {},
    lastOptimization = 0,
    adaptiveTimeouts = {},
    recentCallTimes = {},
    mapSpecificStats = {}
}

function AntiStuck.OptimizePerformance()
    local stats = AntiStuck.performanceStats
    local currentTime = CurTime()
    if currentTime - (stats.lastOptimization or 0) < 60 then return end
    stats.lastOptimization = currentTime

    for methodName, successRate in pairs(stats.methodSuccessRates) do
        for _, method in ipairs(AntiStuck.methods or {}) do
            if method.func == methodName then
                if successRate > 0.8 then
                    method.priority = math.max((method.priority or 50) - 2, 5)
                elseif successRate < 0.3 then
                    method.priority = math.min((method.priority or 50) + 3, 50)
                end
                break
            end
        end
    end

    local avgTime = stats.averageTime or 0
    if avgTime > 0 then
        local timeoutMultiplier = math.Clamp(avgTime / 1.0, 0.5, 2.0)
        AntiStuck.CONFIG.MAX_SEARCH_TIME = math.Clamp(1.5 * timeoutMultiplier, 0.8, 3.0)
    end

    if AntiStuck.DebugEnabled() then
        if RARELOAD.Debug and RARELOAD.Debug.Write then
            local lines = {
                "Average resolution time: " .. string.format("%.3f", avgTime) .. "s",
                "Success rate: " ..
                string.format("%.1f", (stats.successfulCalls / math.max(stats.totalCalls, 1)) * 100) .. "%"
            }
            RARELOAD.Debug.Write("anti_stuck", "INFO", 0, "Performance optimization completed", {})
            for _, line in ipairs(lines) do
                RARELOAD.Debug.Write("anti_stuck", "INFO", 1, line)
            end
        else
            print("[RARELOAD ANTI-STUCK] Performance optimization completed")
            print("  Average resolution time: " .. string.format("%.3f", avgTime) .. "s")
            print("  Success rate: " ..
                string.format("%.1f", (stats.successfulCalls / math.max(stats.totalCalls, 1)) * 100) .. "%")
        end
    end
end
