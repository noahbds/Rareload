if SERVER then
    RARELOAD = RARELOAD or {}
    RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
    local AntiStuck = RARELOAD.AntiStuck

    -- Ensure performance stats exist (prevents nil indexing)
    AntiStuck.performanceStats = AntiStuck.performanceStats or {
        totalCalls = 0,
        successfulCalls = 0,
        averageTime = 0,
        methodSuccessRates = {}
    }

    -- High-performance cached resolution system
    local methodsCache = {}
    local lastMethodsLoad = 0
    local METHODS_CACHE_TTL = 45 -- Longer cache for stability
    local positionMemory = {}    -- Remember bad positions to avoid retrying

    -- Public cache invalidation so other modules can refresh method order immediately
    function AntiStuck.InvalidateResolverCache()
        methodsCache = {}
        lastMethodsLoad = 0
    end

    -- Intelligent method selection with performance optimization
    local function GetOptimizedMethods()
        local currentTime = CurTime()

        -- Use cached methods if still valid
        if #methodsCache > 0 and (currentTime - lastMethodsLoad) < METHODS_CACHE_TTL then
            return methodsCache
        end

        -- Load fresh methods
        methodsCache = {}
        lastMethodsLoad = currentTime

        -- Ensure methods are loaded
        if not AntiStuck.methods or #AntiStuck.methods == 0 then
            if AntiStuck.LoadMethods then
                AntiStuck.LoadMethods(true)
            end
        end

        if not AntiStuck.methods then
            if RARELOAD.settings and RARELOAD.settings.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                RARELOAD.Debug.AntiStuck("WARNING: No methods available")
            end
            return {}
        end

        -- Filter enabled methods and apply intelligent sorting (optional)
        for idx, method in ipairs(AntiStuck.methods) do
            if method.enabled and AntiStuck.methodRegistry and AntiStuck.methodRegistry[method.func] then
                -- Add performance-based timeout adjustment
                local baseTimeout = method.timeout or 1.0
                local perfMultiplier = (AntiStuck.CONFIG and AntiStuck.CONFIG.METHOD_TIMEOUT_MULTIPLIERS and
                    AntiStuck.CONFIG.METHOD_TIMEOUT_MULTIPLIERS[method.func]) or 1.0

                table.insert(methodsCache, {
                    name = method.name,
                    func = method.func,
                    priority = method.priority or 50,
                    timeout = baseTimeout * perfMultiplier,
                    enabled = method.enabled,
                    successRate = AntiStuck.performanceStats.methodSuccessRates[method.func] or 0.5,
                    originalIndex = idx
                })
            end
        end

        local respectProfileOrder = (AntiStuck.CONFIG and AntiStuck.CONFIG.RESPECT_PROFILE_ORDER ~= false)
        if not respectProfileOrder then
            -- Smart sorting: success rate first, then priority, with stable tiebreaker on original index
            table.sort(methodsCache, function(a, b)
                if math.abs(a.successRate - b.successRate) > 0.1 then
                    return a.successRate > b.successRate -- Higher success rate first
                end
                if a.priority ~= b.priority then
                    return a.priority < b.priority       -- Lower priority number = higher priority
                end
                return a.originalIndex < b.originalIndex -- Stable order
            end)
        end

        if RARELOAD.settings and RARELOAD.settings.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            local respectProfileOrder = (AntiStuck.CONFIG and AntiStuck.CONFIG.RESPECT_PROFILE_ORDER ~= false)
            local header = respectProfileOrder and "Using profile-defined order" or "Optimized methods for performance"
            local lines = {}
            for i, method in ipairs(methodsCache) do
                table.insert(lines, string.format("%d: %s (priority: %d, success: %.1f%%, timeout: %.1fs)",
                    i, method.name, method.priority or -1, (method.successRate or 0.5) * 100, method.timeout or 1.0))
            end
            RARELOAD.Debug.LogGroup("Anti-Stuck Methods", "VERBOSE", { header, unpack(lines) })
        end

        return methodsCache
    end

    -- Main resolver for stuck positions - Ultra-optimized with smart caching
    function AntiStuck.ResolveStuckPosition(originalPos, ply)
        if not originalPos or not IsValid(ply) then
            if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                RARELOAD.Debug.AntiStuck("ERROR: Invalid parameters", { methodName = "ResolveStuckPosition" }, ply)
            end
            return Vector(0, 0, 8192), false
        end

        -- Ensure ExecuteMethod is available
        if not AntiStuck.ExecuteMethod or type(AntiStuck.ExecuteMethod) ~= "function" then
            if RARELOAD.settings and RARELOAD.settings.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                RARELOAD.Debug.AntiStuck("ERROR: ExecuteMethod not available; using fallback",
                    { methodName = "ResolveStuckPosition" }, ply)
            end
            return AntiStuck.EmergencyFallback(originalPos, ply)
        end

        local startTime = SysTime()
        local session = nil
        if RARELOAD and RARELOAD.Debug and RARELOAD.Debug.StartAntiStuckSession and DEBUG_CONFIG and DEBUG_CONFIG.ENABLED() then
            session = RARELOAD.Debug.StartAntiStuckSession(ply, originalPos)
        end
        AntiStuck._currentSession = session

        -- Restore stats reference and increment totalCalls
        local stats = AntiStuck.performanceStats
        stats.totalCalls = stats.totalCalls + 1

        -- Check recent failure memory for this position (avoid repeated failures)
        local posKey = string.format("%.0f_%.0f_%.0f", originalPos.x, originalPos.y, originalPos.z)
        if positionMemory[posKey] and CurTime() - positionMemory[posKey] < 30 then
            -- Skip detailed attempts for recently failed positions
            return AntiStuck.EmergencyFallback(originalPos, ply)
        end

        local enabledMethods = GetOptimizedMethods()

        if #enabledMethods == 0 then
            if session then
                RARELOAD.Debug.AntiStuckStep(session, "fail", "No methods available",
                    "Check profile and registry")
            end
            return AntiStuck.EmergencyFallback(originalPos, ply)
        end

        if session then
            local names = {}
            for i, m in ipairs(enabledMethods) do
                table.insert(names, string.format("%d:%s", i, m.name))
            end
            RARELOAD.Debug.AntiStuckStep(session, "start", "Method order", table.concat(names, ", "))
        end

        local maxSearchTime = math.min((AntiStuck.CONFIG and AntiStuck.CONFIG.MAX_SEARCH_TIME) or 1.5, 2.0)
        local maxAttempts = math.min((AntiStuck.CONFIG and AntiStuck.CONFIG.MAX_UNSTUCK_ATTEMPTS) or 35, 50)
        local attemptCount = 0
        local bestPartialResult = nil

        -- Adaptive search with early exit optimization
        for i, methodInfo in ipairs(enabledMethods) do
            if attemptCount >= maxAttempts then break end

            -- Check global timeout with buffer
            local elapsed = SysTime() - startTime
            if elapsed > maxSearchTime * 0.85 then break end

            local methodStartTime = SysTime()

            if session then
                RARELOAD.Debug.AntiStuckStep(session, "start",
                    string.format("Method %d/%d: %s", i, #enabledMethods, methodInfo.name),
                    string.format("success %.1f%%, timeout %.1fs", (methodInfo.successRate or 0.5) * 100,
                        methodInfo.timeout or 1.0))
            end

            local pos, result = AntiStuck.ExecuteMethod(methodInfo.func, originalPos, ply)
            attemptCount = attemptCount + 1

            -- Update method performance tracking
            local methodTime = SysTime() - methodStartTime
            if not stats.methodSuccessRates[methodInfo.func] then
                stats.methodSuccessRates[methodInfo.func] = 0.5
            end

            if pos and result == AntiStuck.UNSTUCK_METHODS.SUCCESS then
                -- Immediate success - cache and return
                if AntiStuck.CacheSafePosition then
                    AntiStuck.CacheSafePosition(pos)
                end

                -- Update success rate (moving average)
                local oldRate = stats.methodSuccessRates[methodInfo.func]
                stats.methodSuccessRates[methodInfo.func] = oldRate * 0.8 + 0.2

                stats.successfulCalls = stats.successfulCalls + 1
                local totalTime = SysTime() - startTime
                stats.averageTime = stats.averageTime * 0.9 + totalTime * 0.1

                if session then
                    RARELOAD.Debug.AntiStuckStep(session, "ok",
                        string.format("%s", methodInfo.name),
                        string.format("found position in %.3fs (attempt %d)", SysTime() - startTime, attemptCount))
                end

                -- Structured log for successful anti-stuck resolution
                if RARELOAD and RARELOAD.Debug and RARELOAD.Debug.LogAntiStuck and RARELOAD.settings and
                    RARELOAD.settings.debugEnabled then
                    RARELOAD.Debug.LogAntiStuck("Method success", methodInfo.name, {
                        originalPos = originalPos,
                        finalPos = pos,
                        attempts = attemptCount,
                        index = i,
                        totalMethods = #enabledMethods,
                        elapsed = SysTime() - startTime,
                        methodTime = methodTime,
                        timeout = methodInfo.timeout,
                        priority = methodInfo.priority,
                        func = methodInfo.func,
                        success = true,
                        distance = originalPos:Distance(pos)
                    }, ply)
                end

                -- Trigger performance optimization periodically
                if stats.totalCalls % 20 == 0 and AntiStuck.OptimizePerformance then
                    AntiStuck.OptimizePerformance()
                end

                return pos, true
            elseif pos and result == AntiStuck.UNSTUCK_METHODS.PARTIAL then
                -- Store partial result as backup
                if not bestPartialResult or pos:DistToSqr(originalPos) < bestPartialResult.pos:DistToSqr(originalPos) then
                    bestPartialResult = { pos = pos, method = methodInfo.name }
                end

                -- Structured log for partial result
                if RARELOAD.settings.debugEnabled then
                    RARELOAD.Debug.LogAntiStuck("Method partial", methodInfo.name, {
                        originalPos = originalPos,
                        partialPos = pos,
                        attempts = attemptCount,
                        index = i,
                        totalMethods = #enabledMethods,
                        methodTime = methodTime,
                        timeout = methodInfo.timeout,
                        priority = methodInfo.priority,
                        func = methodInfo.func,
                        success = false,
                        distance = originalPos:Distance(pos)

                    }, ply)
                end

                -- Continue trying for full success but update partial success rate
                local oldRate = stats.methodSuccessRates[methodInfo.func]
                stats.methodSuccessRates[methodInfo.func] = oldRate * 0.9 + 0.1
            else
                -- Method failed - update failure rate
                local oldRate = stats.methodSuccessRates[methodInfo.func]
                stats.methodSuccessRates[methodInfo.func] = oldRate * 0.95

                if session then
                    RARELOAD.Debug.AntiStuckStep(session, "fail",
                        string.format("%s", methodInfo.name),
                        string.format("failed in %.3fs", methodTime))
                end
            end

            -- Early exit if method took too long
            if methodTime > (methodInfo.timeout or 1.0) * 1.2 then
                if session then
                    RARELOAD.Debug.AntiStuckStep(session, "fail", "Timeout",
                        string.format("%s exceeded %.2fs", methodInfo.name, methodInfo.timeout or 1.0))
                end
                -- continue to next method (no break)
            end
        end

        -- Mark this position as problematic
        positionMemory[posKey] = CurTime()

        -- Use partial result if available
        if bestPartialResult then
            if session then RARELOAD.Debug.AntiStuckStep(session, "ok", "Using partial result", bestPartialResult.method) end
            if RARELOAD and RARELOAD.Debug and RARELOAD.Debug.LogAntiStuck and RARELOAD.settings and
                RARELOAD.settings.debugEnabled then
                RARELOAD.Debug.LogAntiStuck("Using partial result", bestPartialResult.method, {
                    originalPos = originalPos,
                    finalPos = bestPartialResult.pos,
                    attempts = attemptCount,
                    success = true,
                    reason = "All full methods failed; best partial used",
                    distance = originalPos:Distance(bestPartialResult.pos)
                }, ply)
            end
            if session then
                RARELOAD.Debug.FinishAntiStuckSession(session,
                    {
                        success = true,
                        attempts = attemptCount,
                        totalTime = SysTime() - startTime,
                        finalPos =
                            bestPartialResult.pos
                    })
            end
            AntiStuck._currentSession = nil
            return bestPartialResult.pos, true
        end

        -- All methods failed
        local totalTime = SysTime() - startTime
        if session then
            RARELOAD.Debug.FinishAntiStuckSession(session,
                { success = false, attempts = attemptCount, totalTime = totalTime, reason = "All methods failed" })
        end
        AntiStuck._currentSession = nil
        return AntiStuck.EmergencyFallback(originalPos, ply)
    end

    -- Enhanced emergency fallback with smart positioning
    function AntiStuck.EmergencyFallback(originalPos, ply)
        if RARELOAD.settings and RARELOAD.settings.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Using enhanced emergency fallback", { methodName = "EmergencyFallback" }, ply)
        end

        -- Try the emergency method first if available
        local emergencyMethod = AntiStuck.methodRegistry and AntiStuck.methodRegistry["TryEmergencyTeleport"]
        if emergencyMethod and AntiStuck.ExecuteMethod then
            local pos, result = AntiStuck.ExecuteMethod("TryEmergencyTeleport", originalPos, ply)
            if pos and result == AntiStuck.UNSTUCK_METHODS.SUCCESS then
                return pos, true
            end
        end

        -- Intelligent fallback position calculation
        local mapBounds = AntiStuck.mapBounds
        local fallbackHeight = (AntiStuck.CONFIG and AntiStuck.CONFIG.FALLBACK_HEIGHT) or 8192

        local fallbackPos
        if mapBounds then
            -- Use map center with safe height
            local centerX = (mapBounds.mins.x + mapBounds.maxs.x) / 2
            local centerY = (mapBounds.mins.y + mapBounds.maxs.y) / 2
            local safeZ = math.max(mapBounds.maxs.z + 200, fallbackHeight / 2)
            fallbackPos = Vector(centerX, centerY, safeZ)
        else
            -- Default high altitude position
            fallbackPos = Vector(0, 0, fallbackHeight)
        end

        if RARELOAD.settings and RARELOAD.settings.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Using calculated emergency fallback position",
                { methodName = "EmergencyFallback" }, ply)
        end
        if RARELOAD and RARELOAD.Debug and RARELOAD.Debug.LogAntiStuck and RARELOAD.settings and
            RARELOAD.settings.debugEnabled then
            RARELOAD.Debug.LogAntiStuck("EmergencyFallback used", "EmergencyFallback", {
                originalPos = originalPos,
                finalPos = fallbackPos,
                success = false,
                reason = "Resolver exhausted or invalid params"
            }, ply)
        end
        return fallbackPos, false
    end

    -- Cleanup memory periodically
    timer.Create("RareloadAntiStuckMemoryCleanup", 300, 0, function()
        local currentTime = CurTime()
        local cleaned = 0

        for posKey, timestamp in pairs(positionMemory) do
            if currentTime - timestamp > 300 then -- 5 minutes
                positionMemory[posKey] = nil
                cleaned = cleaned + 1
            end
        end

        if cleaned > 0 and RARELOAD.settings and RARELOAD.settings.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Cleaned position memory entries", { cleaned = cleaned })
        end
    end)

    -- Force refresh methods cache (useful for admin commands)
    function AntiStuck.RefreshMethodsCache()
        methodsCache = {}
        lastMethodsLoad = 0
        return GetOptimizedMethods()
    end

    -- Get performance statistics
    function AntiStuck.GetPerformanceStats()
        return AntiStuck.performanceStats
    end
end
