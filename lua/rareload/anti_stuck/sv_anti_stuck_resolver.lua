if SERVER then
    RARELOAD = RARELOAD or {}
    RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
    local AntiStuck = RARELOAD.AntiStuck

    -- Cache for loaded methods to avoid reloading on every call
    local methodsCache = {}
    local lastMethodsLoad = 0
    local METHODS_CACHE_TTL = 30 -- seconds

    -- Get enabled methods in priority order (cached)
    local function GetEnabledMethods()
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

        if not AntiStuck.methods or #AntiStuck.methods == 0 then
            print("[RARELOAD ANTI-STUCK] ERROR: No methods available!")
            return {}
        end

        -- Build enabled methods list with validation
        for _, methodData in ipairs(AntiStuck.methods) do
            if methodData.enabled and methodData.func then
                local methodObj = AntiStuck.methodRegistry[methodData.func]
                if methodObj then
                    table.insert(methodsCache, {
                        name = methodData.name or methodData.func,
                        func = methodData.func,
                        priority = methodData.priority or methodObj.priority or 50,
                        timeout = methodObj.timeout or 2.0
                    })
                else
                    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                        print("[RARELOAD ANTI-STUCK] Warning: Method function not found: " .. tostring(methodData.func))
                    end
                end
            end
        end

        -- Sort by priority (lower number = higher priority)
        table.sort(methodsCache, function(a, b) return a.priority < b.priority end)

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Loaded " .. #methodsCache .. " enabled methods:")
            for i, method in ipairs(methodsCache) do
                print("  " .. i .. ": " .. method.name .. " (priority: " .. method.priority .. ")")
            end
        end

        return methodsCache
    end

    -- Main resolver for stuck positions - improved and optimized
    function AntiStuck.ResolveStuckPosition(originalPos, ply)
        if not originalPos or not IsValid(ply) then
            print("[RARELOAD ANTI-STUCK] ERROR: Invalid parameters")
            return Vector(0, 0, 16384), false
        end

        local startTime = SysTime()
        local enabledMethods = GetEnabledMethods()

        if #enabledMethods == 0 then
            print("[RARELOAD ANTI-STUCK] CRITICAL: No enabled methods available!")
            return AntiStuck.EmergencyFallback(originalPos, ply)
        end

        local maxSearchTime = (AntiStuck.CONFIG and AntiStuck.CONFIG.MAX_SEARCH_TIME) or 2.0
        local retryDelay = (AntiStuck.CONFIG and AntiStuck.CONFIG.RETRY_DELAY) or 0.0
        local maxAttempts = (AntiStuck.CONFIG and AntiStuck.CONFIG.MAX_UNSTUCK_ATTEMPTS) or 50
        local attemptCount = 0

        -- Try each method in priority order
        for i, methodInfo in ipairs(enabledMethods) do
            if attemptCount >= maxAttempts then
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Reached maximum attempts: " .. maxAttempts)
                end
                break
            end

            local methodStartTime = SysTime()

            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD ANTI-STUCK] Trying method " .. i .. "/" .. #enabledMethods .. ": " .. methodInfo.name)
            end

            local pos, result = AntiStuck.ExecuteMethod(methodInfo.func, originalPos, ply)
            attemptCount = attemptCount + 1

            if pos and result == AntiStuck.UNSTUCK_METHODS.SUCCESS then
                -- Cache successful position
                if AntiStuck.CacheSafePosition then
                    AntiStuck.CacheSafePosition(pos)
                end

                local totalTime = SysTime() - startTime
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print(string.format(
                        "[RARELOAD ANTI-STUCK] SUCCESS: Method '%s' found position in %.3fs (attempt %d)",
                        methodInfo.name, totalTime, attemptCount))
                end

                return pos, true
            elseif pos and result == AntiStuck.UNSTUCK_METHODS.PARTIAL then
                -- Partial success - continue trying but keep this as backup
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] PARTIAL: Method '" .. methodInfo.name .. "' found partial solution")
                end
                -- Could implement backup position logic here
            end

            -- Check global timeout and method timeout
            local elapsed = SysTime() - startTime
            if elapsed > maxSearchTime then
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] TIMEOUT: Exceeded global search time limit (" .. maxSearchTime .. "s)")
                end
                break
            end

            if SysTime() - methodStartTime > methodInfo.timeout then
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] TIMEOUT: Method '" .. methodInfo.name .. "' exceeded timeout")
                end
            end

            -- Apply retry delay between attempts
            if retryDelay > 0 and i < #enabledMethods then
                timer.Simple(retryDelay, function() end)
            end
        end

        -- All methods failed
        local totalTime = SysTime() - startTime
        print(string.format("[RARELOAD ANTI-STUCK] FAILURE: All %d methods failed in %.3fs for player %s",
            #enabledMethods, totalTime, ply:Nick()))

        return AntiStuck.EmergencyFallback(originalPos, ply)
    end

    -- Emergency fallback when all methods fail
    function AntiStuck.EmergencyFallback(originalPos, ply)
        print("[RARELOAD ANTI-STUCK] Using emergency fallback")

        -- Try the emergency method first if available
        local emergencyMethod = AntiStuck.methodRegistry["TryEmergencyTeleport"]
        if emergencyMethod then
            local pos, result = AntiStuck.ExecuteMethod("TryEmergencyTeleport", originalPos, ply)
            if pos and result == AntiStuck.UNSTUCK_METHODS.SUCCESS then
                return pos, true
            end
        end

        -- Final fallback - high altitude safe position
        local fallbackPos = Vector(0, 0, 16384)
        print("[RARELOAD ANTI-STUCK] Using high altitude fallback position")
        return fallbackPos, false
    end

    -- Force refresh methods cache (useful for admin commands)
    function AntiStuck.RefreshMethodsCache()
        methodsCache = {}
        lastMethodsLoad = 0
        return GetEnabledMethods()
    end
end
