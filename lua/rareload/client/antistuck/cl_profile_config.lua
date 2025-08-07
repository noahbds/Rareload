-- Profile System Optimization Configuration
-- Centralized configuration for all performance optimizations

RARELOAD = RARELOAD or {}
RARELOAD.ProfileConfig = {

    -- Cache Configuration
    cache = {
        -- Maximum number of profiles to keep in memory cache
        maxCacheSize = 20,

        -- Enable/disable profile caching entirely
        enabled = true,

        -- Cache cleanup interval in seconds
        cleanupInterval = 30,

        -- Automatic cache validation on access
        validateOnAccess = true,

        -- Enable cache statistics collection
        collectStats = true
    },

    -- Batch Operations Configuration
    batchOperations = {
        -- Enable batch file operations
        enabled = true,

        -- Number of operations to queue before auto-execution
        threshold = 5,

        -- Maximum time to wait before executing batch (seconds)
        maxWaitTime = 2.0,

        -- Enable background batch execution
        backgroundExecution = true,

        -- Batch execution interval (seconds)
        executionInterval = 2
    },

    -- Memory Pool Configuration
    memoryPool = {
        -- Enable memory pooling for objects
        enabled = true,

        -- Maximum objects per pool type
        maxPoolSize = 10,

        -- Pools to create
        pools = {
            "tempProfiles",
            "tempSettings",
            "tempMethods"
        },

        -- Auto-cleanup unused pools
        autoCleanup = true,

        -- Pool cleanup interval (seconds)
        cleanupInterval = 60
    },

    -- Validation Configuration
    validation = {
        -- Cache validation results
        cacheResults = true,

        -- Maximum validation cache entries
        maxCacheEntries = 50,

        -- Validation cache TTL in seconds (0 = no expiry)
        cacheTTL = 0,

        -- Enable strict validation mode
        strictMode = false,

        -- Auto-fix corrupted profiles
        autoFix = true
    },

    -- UI Optimization Configuration
    ui = {
        -- Enable incremental list updates
        incrementalUpdates = true,

        -- UI update debounce time (seconds)
        updateDebounce = 0.1,

        -- Cache UI component data
        cacheComponentData = true,

        -- Maximum cached components
        maxCachedComponents = 25,

        -- Enable smooth animations
        smoothAnimations = true
    },

    -- Performance Monitoring Configuration
    monitoring = {
        -- Enable performance monitoring
        enabled = true,

        -- Monitoring interval (seconds)
        interval = 60,

        -- Log performance warnings
        logWarnings = true,

        -- Performance warning thresholds
        thresholds = {
            -- Cache hit rate below this triggers warning
            cacheHitRate = 0.5,

            -- Average load time above this triggers warning (seconds)
            averageLoadTime = 0.1,

            -- Cache size above this triggers warning
            cacheSize = 25,

            -- Operations per second below this triggers warning
            operationsPerSecond = 0.1
        },

        -- Auto-performance tuning
        autoTuning = {
            enabled = false,
            -- Automatically adjust cache size based on usage
            adjustCacheSize = true,
            -- Automatically adjust batch thresholds
            adjustBatchThresholds = true
        }
    },

    -- Debug Configuration
    debug = {
        -- Enable debug logging
        enabled = false,

        -- Log levels: "DEBUG", "INFO", "WARN", "ERROR"
        logLevel = "INFO",

        -- Log cache operations
        logCacheOps = false,

        -- Log batch operations
        logBatchOps = false,

        -- Log validation operations
        logValidation = false,

        -- Performance logging
        logPerformance = false
    },

    -- Advanced Configuration
    advanced = {
        -- Enable experimental features
        experimental = false,

        -- Use async operations where possible
        asyncOperations = false,

        -- Preload frequently used profiles
        preloadProfiles = true,

        -- Predictive caching based on usage patterns
        predictiveCaching = false,

        -- Compress profile data in cache
        compressCacheData = false,

        -- Use binary serialization for speed
        binarySerialization = false
    }
}

-- Configuration validation and application
local function ApplyConfig()
    if not profileSystem then return end

    local config = RARELOAD.ProfileConfig

    -- Apply cache configuration
    if profileSystem._cacheConfig then
        profileSystem._cacheConfig.maxSize = config.cache.maxCacheSize
        profileSystem._cacheConfig.enabled = config.cache.enabled
        profileSystem._cacheConfig.cleanupInterval = config.cache.cleanupInterval
    end

    -- Apply batch operation configuration
    if profileSystem._batchConfig then
        profileSystem._batchConfig.enabled = config.batchOperations.enabled
        profileSystem._batchConfig.threshold = config.batchOperations.threshold
        profileSystem._batchConfig.maxWaitTime = config.batchOperations.maxWaitTime
    end

    -- Apply memory pool configuration
    if profileSystem._memoryPoolConfig then
        profileSystem._memoryPoolConfig.enabled = config.memoryPool.enabled
        profileSystem._memoryPoolConfig.maxPoolSize = config.memoryPool.maxPoolSize
    end

    print("[RARELOAD] Profile system configuration applied")
end

-- Configuration management functions
function RARELOAD.ProfileConfig.Save()
    file.CreateDir("rareload")
    local configFile = "rareload/profile_optimization_config.json"
    file.Write(configFile, util.TableToJSON(RARELOAD.ProfileConfig, true))
    print("[RARELOAD] Configuration saved to " .. configFile)
end

function RARELOAD.ProfileConfig.Load()
    local configFile = "rareload/profile_optimization_config.json"
    if file.Exists(configFile, "DATA") then
        local content = file.Read(configFile, "DATA")
        local success, config = pcall(util.JSONToTable, content)
        if success and config then
            -- Merge with defaults
            table.Merge(RARELOAD.ProfileConfig, config)
            ApplyConfig()
            print("[RARELOAD] Configuration loaded from " .. configFile)
            return true
        else
            print("[RARELOAD] Error loading configuration: Invalid JSON")
        end
    else
        print("[RARELOAD] No configuration file found, using defaults")
    end
    return false
end

function RARELOAD.ProfileConfig.Reset()
    -- Reset to defaults (this will reload the file)
    include("rareload/client/antistuck/cl_profile_config.lua")
    ApplyConfig()
    print("[RARELOAD] Configuration reset to defaults")
end

function RARELOAD.ProfileConfig.Print()
    print("=== RARELOAD Profile System Configuration ===")
    PrintTable(RARELOAD.ProfileConfig)
    print("============================================")
end

-- Console commands for configuration management
concommand.Add("rareload_config_save", function()
    RARELOAD.ProfileConfig.Save()
end)

concommand.Add("rareload_config_load", function()
    RARELOAD.ProfileConfig.Load()
end)

concommand.Add("rareload_config_reset", function()
    RARELOAD.ProfileConfig.Reset()
end)

concommand.Add("rareload_config_print", function()
    RARELOAD.ProfileConfig.Print()
end)

-- Auto-load configuration when file is included
timer.Simple(0.1, function()
    RARELOAD.ProfileConfig.Load()
    ApplyConfig()
end)
