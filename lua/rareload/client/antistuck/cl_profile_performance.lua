-- Profile System Performance Monitor
-- Provides runtime performance monitoring and debugging tools

RARELOAD = RARELOAD or {}
RARELOAD.ProfilePerformance = {}

local performanceMonitor = RARELOAD.ProfilePerformance
local profileSystem = RARELOAD.profileSystem or _G.profileSystem or {}

-- Ensure deep copy utilities are available
if not profileSystem.DeepCopy then
    include("cl_profile_deepcopy.lua")
end

local performanceMonitor = RARELOAD.ProfilePerformance

-- Performance data collection
performanceMonitor.metrics = {
    startTime = SysTime(),
    operations = {
        profileLoads = 0,
        profileSaves = 0,
        cacheHits = 0,
        cacheMisses = 0,
        batchOperations = 0,
        validationCacheHits = 0
    },
    timings = {
        averageLoadTime = 0,
        averageSaveTime = 0,
        totalLoadTime = 0,
        totalSaveTime = 0
    },
    memory = {
        cacheSize = 0,
        memoryPoolUsage = 0,
        peakCacheSize = 0
    }
}

-- Performance monitoring functions
function performanceMonitor.StartTimer()
    return SysTime()
end

function performanceMonitor.EndTimer(startTime, operation)
    local duration = SysTime() - startTime
    local metrics = performanceMonitor.metrics

    if operation == "load" then
        metrics.operations.profileLoads = metrics.operations.profileLoads + 1
        metrics.timings.totalLoadTime = metrics.timings.totalLoadTime + duration
        metrics.timings.averageLoadTime = metrics.timings.totalLoadTime / metrics.operations.profileLoads
    elseif operation == "save" then
        metrics.operations.profileSaves = metrics.operations.profileSaves + 1
        metrics.timings.totalSaveTime = metrics.timings.totalSaveTime + duration
        metrics.timings.averageSaveTime = metrics.timings.totalSaveTime / metrics.operations.profileSaves
    end

    return duration
end

function performanceMonitor.RecordCacheEvent(eventType)
    local metrics = performanceMonitor.metrics

    if eventType == "hit" then
        metrics.operations.cacheHits = metrics.operations.cacheHits + 1
    elseif eventType == "miss" then
        metrics.operations.cacheMisses = metrics.operations.cacheMisses + 1
    elseif eventType == "validation_hit" then
        metrics.operations.validationCacheHits = metrics.operations.validationCacheHits + 1
    end
end

function performanceMonitor.UpdateMemoryStats()
    if not profileSystem then return end

    local metrics = performanceMonitor.metrics
    local cacheSize = table.Count(profileSystem._profileCache or {})

    metrics.memory.cacheSize = cacheSize
    if cacheSize > metrics.memory.peakCacheSize then
        metrics.memory.peakCacheSize = cacheSize
    end

    -- Calculate memory pool usage
    local poolUsage = 0
    for poolName, pool in pairs(profileSystem._memoryPool or {}) do
        poolUsage = poolUsage + #pool
    end
    metrics.memory.memoryPoolUsage = poolUsage
end

function performanceMonitor.GetPerformanceReport()
    performanceMonitor.UpdateMemoryStats()
    local metrics = performanceMonitor.metrics
    local uptime = SysTime() - metrics.startTime

    local report = {
        uptime = uptime,
        operations = {
            profileLoads = metrics.operations.profileLoads,
            profileSaves = metrics.operations.profileSaves,
            totalOperations = metrics.operations.profileLoads + metrics.operations.profileSaves
        },
        cache = {
            hits = metrics.operations.cacheHits,
            misses = metrics.operations.cacheMisses,
            hitRate = metrics.operations.cacheHits /
                math.max(1, metrics.operations.cacheHits + metrics.operations.cacheMisses),
            validationHits = metrics.operations.validationCacheHits
        },
        performance = {
            averageLoadTime = metrics.timings.averageLoadTime,
            averageSaveTime = metrics.timings.averageSaveTime,
            operationsPerSecond = (metrics.operations.profileLoads + metrics.operations.profileSaves) /
                math.max(1, uptime)
        },
        memory = {
            currentCacheSize = metrics.memory.cacheSize,
            peakCacheSize = metrics.memory.peakCacheSize,
            memoryPoolUsage = metrics.memory.memoryPoolUsage
        }
    }

    return report
end

function performanceMonitor.PrintPerformanceReport()
    local report = performanceMonitor.GetPerformanceReport()

    print("=== RARELOAD Profile System Performance Report ===")
    print(string.format("Uptime: %.2f seconds", report.uptime))
    print("")
    print("Operations:")
    print(string.format("  Profile Loads: %d", report.operations.profileLoads))
    print(string.format("  Profile Saves: %d", report.operations.profileSaves))
    print(string.format("  Total Operations: %d", report.operations.totalOperations))
    print(string.format("  Operations/sec: %.2f", report.performance.operationsPerSecond))
    print("")
    print("Cache Performance:")
    print(string.format("  Cache Hits: %d", report.cache.hits))
    print(string.format("  Cache Misses: %d", report.cache.misses))
    print(string.format("  Hit Rate: %.2f%%", report.cache.hitRate * 100))
    print(string.format("  Validation Cache Hits: %d", report.cache.validationHits))
    print("")
    print("Performance:")
    print(string.format("  Average Load Time: %.4f ms", report.performance.averageLoadTime * 1000))
    print(string.format("  Average Save Time: %.4f ms", report.performance.averageSaveTime * 1000))
    print("")
    print("Memory Usage:")
    print(string.format("  Current Cache Size: %d profiles", report.memory.currentCacheSize))
    print(string.format("  Peak Cache Size: %d profiles", report.memory.peakCacheSize))
    print(string.format("  Memory Pool Usage: %d objects", report.memory.memoryPoolUsage))
    print("================================================")
end

-- Automatic performance monitoring
function performanceMonitor.StartMonitoring()
    timer.Create("RareloadProfilePerformanceMonitor", 60, 0, function()
        performanceMonitor.UpdateMemoryStats()

        -- Log performance issues
        local report = performanceMonitor.GetPerformanceReport()

        if report.cache.hitRate < 0.5 and report.operations.totalOperations > 10 then
            print("[RARELOAD] Warning: Low cache hit rate (" .. math.Round(report.cache.hitRate * 100, 1) .. "%)")
        end

        if report.performance.averageLoadTime > 0.1 then
            print("[RARELOAD] Warning: High average load time (" ..
                math.Round(report.performance.averageLoadTime * 1000, 2) .. "ms)")
        end

        if report.memory.currentCacheSize > 25 then
            print("[RARELOAD] Warning: Large cache size (" .. report.memory.currentCacheSize .. " profiles)")
        end
    end)
end

-- Performance testing utilities
function performanceMonitor.RunPerformanceTest()
    print("[RARELOAD] Starting profile system performance test...")

    if not profileSystem then
        print("[RARELOAD] Error: Profile system not available")
        return
    end

    local testStartTime = SysTime()
    local testProfiles = {}

    -- Test profile creation
    for i = 1, 10 do
        local profileData = {
            name = "test_profile_" .. i,
            displayName = "Test Profile " .. i,
            description = "Performance test profile",
            settings = profileSystem.DeepCopySettings(Default_Anti_Stuck_Settings or {}),
            methods = {
                { name = "Test Method", func = "TestMethod", enabled = true }
            }
        }

        local startTime = performanceMonitor.StartTimer()
        local success, result = profileSystem.CreateProfile(profileData)
        local duration = performanceMonitor.EndTimer(startTime, "save")

        if success then
            table.insert(testProfiles, result)
            print(string.format("[RARELOAD] Created test profile %d in %.4f ms", i, duration * 1000))
        else
            print("[RARELOAD] Failed to create test profile " .. i .. ": " .. tostring(result))
        end
    end

    -- Test profile loading (should hit cache)
    for i = 1, 5 do
        for _, profileName in ipairs(testProfiles) do
            local startTime = performanceMonitor.StartTimer()
            local profile = profileSystem.LoadProfile(profileName)
            local duration = performanceMonitor.EndTimer(startTime, "load")

            if profile then
                print(string.format("[RARELOAD] Loaded profile %s in %.4f ms", profileName, duration * 1000))
            end
        end
    end

    -- Clean up test profiles
    for _, profileName in ipairs(testProfiles) do
        profileSystem.DeleteProfile(profileName)
    end

    local testDuration = SysTime() - testStartTime
    print(string.format("[RARELOAD] Performance test completed in %.2f seconds", testDuration))

    -- Print performance report
    timer.Simple(0.1, function()
        performanceMonitor.PrintPerformanceReport()
    end)
end

-- Console commands for performance monitoring
concommand.Add("rareload_performance_report", function()
    performanceMonitor.PrintPerformanceReport()
end)

concommand.Add("rareload_performance_test", function()
    performanceMonitor.RunPerformanceTest()
end)

concommand.Add("rareload_performance_reset", function()
    performanceMonitor.metrics = {
        startTime = SysTime(),
        operations = {
            profileLoads = 0,
            profileSaves = 0,
            cacheHits = 0,
            cacheMisses = 0,
            batchOperations = 0,
            validationCacheHits = 0
        },
        timings = {
            averageLoadTime = 0,
            averageSaveTime = 0,
            totalLoadTime = 0,
            totalSaveTime = 0
        },
        memory = {
            cacheSize = 0,
            memoryPoolUsage = 0,
            peakCacheSize = 0
        }
    }
    print("[RARELOAD] Performance metrics reset")
end)

-- Start monitoring when the file loads
timer.Simple(1, function()
    if profileSystem then
        performanceMonitor.StartMonitoring()
        print("[RARELOAD] Profile performance monitoring started")
    end
end)
