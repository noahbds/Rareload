if not SERVER then return end

-- Deep copy utilities
include("sv_deepcopy_utils.lua")

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

-- Testing flags (shared state)
AntiStuck.testingMode = AntiStuck.testingMode or false
AntiStuck.testingPlayers = AntiStuck.testingPlayers or {}
AntiStuck.originalStuckPositions = AntiStuck.originalStuckPositions or {}

-- Default settings and methods
AntiStuck.DefaultSettings = AntiStuck.DefaultSettings or {
    MAX_UNSTUCK_ATTEMPTS = 35,
    MAX_SEARCH_TIME = 1.5,
    RETRY_DELAY = 0.05,
    DEBUG_LOGGING = false,
    ENABLE_CACHE = true,
    CACHE_DURATION = 900,

    SAFE_DISTANCE = 48,
    PLAYER_HULL_TOLERANCE = 8,
    MIN_GROUND_DISTANCE = 12,
    MAP_BOUNDS_PADDING = 128,

    VERTICAL_SEARCH_RANGE = 2048,
    HORIZONTAL_SEARCH_RANGE = 1536,
    MAX_TRACE_DISTANCE = 2048,
    NODE_SEARCH_RADIUS = 1024,
    ENTITY_SEARCH_RADIUS = 384,

    SPAWN_POINT_OFFSET_Z = 24,
    MAP_ENTITY_OFFSET_Z = 40,
    NAV_AREA_OFFSET_Z = 20,
    NAVMESH_HEIGHT_OFFSET = 24,
    FALLBACK_HEIGHT = 8192,

    GRID_RESOLUTION = 32,
    SEARCH_RESOLUTIONS = { 32, 64, 128, 256 },
    SPIRAL_RINGS = 8,
    POINTS_PER_RING = 12,
    MAX_DISTANCE = 1200,
    VERTICAL_STEPS = 7,
    VERTICAL_RANGE = 600,

    DISPLACEMENT_STEP_SIZE = 64,
    DISPLACEMENT_MAX_HEIGHT = 800,
    SPACE_SCAN_ACCURACY = 3,
    EMERGENCY_SAFE_RADIUS = 160,
    RANDOM_ATTEMPTS = 25,

    ADAPTIVE_TIMEOUTS = true,
    PROGRESSIVE_ACCURACY = true,
    EARLY_EXIT_OPTIMIZATION = true,
    DISTANCE_PRIORITY = true,
    SUCCESS_RATE_LEARNING = true,
    PERFORMANCE_MONITORING = true,

    METHOD_TIMEOUT_MULTIPLIERS = {
        TryCachedPositions = 0.3,
        TryDisplacement = 0.5,
        Try3DSpaceScan = 0.8,
        TryNodeGraph = 1.0,
        TryMapEntities = 0.7,
        TrySystematicGrid = 1.2,
        TryWorldBrushes = 1.0,
        TrySpawnPoints = 0.4,
        TryEmergencyTeleport = 0.2
    }
}

AntiStuck.DefaultMethods = AntiStuck.DefaultMethods or {
    { name = "Cached Positions",   func = "TryCachedPositions",   enabled = true, priority = 5,  timeout = 0.3, description = "Ultra-fast: Use proven safe positions" },
    { name = "Smart Displacement", func = "TryDisplacement",      enabled = true, priority = 10, timeout = 0.8, description = "Fast: Intelligent physics-based movement" },
    { name = "Navigation Mesh",    func = "TryNodeGraph",         enabled = true, priority = 15, timeout = 1.0, description = "Optimal: Source engine navigation system" },
    { name = "Map Entities",       func = "TryMapEntities",       enabled = true, priority = 20, timeout = 0.7, description = "Fast: Leverage map spawn points" },
    { name = "3D Space Scan",      func = "Try3DSpaceScan",       enabled = true, priority = 25, timeout = 1.2, description = "Thorough: Advanced volumetric analysis" },
    { name = "World Brushes",      func = "TryWorldBrushes",      enabled = true, priority = 30, timeout = 1.0, description = "Smart: Geometry-based positioning" },
    { name = "Systematic Grid",    func = "TrySystematicGrid",    enabled = true, priority = 35, timeout = 1.5, description = "Comprehensive: Full area coverage" },
    { name = "Spawn Points",       func = "TrySpawnPoints",       enabled = true, priority = 40, timeout = 0.4, description = "Reliable: Map-defined safe zones" },
    { name = "Emergency Teleport", func = "TryEmergencyTeleport", enabled = true, priority = 45, timeout = 0.2, description = "Failsafe: Guaranteed positioning" }
}

-- Initialize CONFIG and utilities
AntiStuck.CONFIG = AntiStuck.CONFIG or RareloadDeepCopySettings(AntiStuck.DefaultSettings)

function AntiStuck.GetConfig(key)
    if AntiStuck.CONFIG[key] ~= nil then return AntiStuck.CONFIG[key] end
    return AntiStuck.DefaultSettings[key]
end

function AntiStuck.DebugEnabled()
    if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled ~= nil then
        return RARELOAD.settings.debugEnabled
    end
    return AntiStuck.CONFIG and AntiStuck.CONFIG.DEBUG_LOGGING or false
end

function AntiStuck.LogDebug(message, data, player, level)
    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck(message, data, player, level)
    elseif AntiStuck.DebugEnabled() then
        print("[RARELOAD ANTI-STUCK] " .. tostring(message))
    end
end

-- Performance stats and optimizer
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

    -- Adjust method priorities based on success rates
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
        print("[RARELOAD ANTI-STUCK] Performance optimization completed")
        print("  Average resolution time: " .. string.format("%.3f", avgTime) .. "s")
        print("  Success rate: " ..
        string.format("%.1f", (stats.successfulCalls / math.max(stats.totalCalls, 1)) * 100) .. "%")
    end
end
