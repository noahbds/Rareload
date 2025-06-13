if SERVER then
    RARELOAD = RARELOAD or {}
    RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
    local AntiStuck = RARELOAD.AntiStuck

    function AntiStuck.ResolveStuckPosition(originalPos, ply)
        if not IsValid(ply) then return originalPos, false end

        if RARELOAD.settings and RARELOAD.settings.spawnModeEnabled then
            return originalPos, true
        end

        local isStuck, reason = AntiStuck.IsPositionStuck(originalPos, ply)

        if not isStuck then
            if AntiStuck.CacheSafePosition then
                AntiStuck.CacheSafePosition(originalPos)
            end
            return originalPos, true
        end

        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Position is stuck (" .. reason .. "), attempting to resolve...", {
                position = tostring(originalPos),
                originalPosition = originalPos,
                playerName = IsValid(ply) and ply:Nick() or "Unknown",
                steamID = IsValid(ply) and ply:SteamID() or "Unknown",
                reason = reason
            }, ply)
        elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Position is stuck (" .. reason .. "), attempting to resolve...")
        end

        if not AntiStuck.GetMethod then
            print("[RARELOAD ERROR] Anti-Stuck methods system not available! Using emergency positioning.")
            pcall(function()
                include("rareload/anti_stuck/sv_anti_stuck_methods.lua")
            end)

            if not AntiStuck.GetMethod then
                local emergencyPos = Vector(0, 0, 16384)
                print("[RARELOAD ANTI-STUCK] Using high altitude emergency position")
                return emergencyPos, false
            end
        end

        if AntiStuck.LoadMethodPriorities then
            AntiStuck.LoadMethodPriorities(true)
        else
            print("[RARELOAD ERROR] LoadMethodPriorities not available")
        end

        if not AntiStuck.methodPriorities or #AntiStuck.methodPriorities == 0 then
            if AntiStuck.emergencyFallbackMethod then
                local emergencyPos, success = AntiStuck.emergencyFallbackMethod(originalPos, ply)
                return emergencyPos, success
            end

            print("[RARELOAD ANTI-STUCK] No methods available! Using absolute fallback position")
            return Vector(0, 0, 16384), false
        end

        local methods = {}
        for i, methodData in ipairs(AntiStuck.methodPriorities) do
            if methodData.enabled then
                local methodFunc = nil

                local success, result = pcall(function()
                    return AntiStuck.GetMethod(methodData.func)
                end)

                if success and result then
                    methodFunc = result
                end

                if methodFunc then
                    table.insert(methods, {
                        func = methodFunc,
                        name = methodData.name,
                        priority = i
                    })
                end
            end
        end

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Will try " .. #methods .. " enabled methods in priority order:")
            for i, method in ipairs(methods) do
                print("  " .. i .. ": " .. method.name .. " (Priority: " .. method.priority .. ")")
            end
        end

        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Methods to try", {
                methodName = "Resolver",
                position = originalPos,
                methods = methods
            }, ply)
        end

        for i, method in ipairs(methods) do
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD ANTI-STUCK] Trying method " ..
                    i .. ": " .. method.name .. " (Priority: " .. method.priority .. ")")
            end

            local success, safePos = pcall(function()
                return method.func(originalPos, ply)
            end)

            local methodUsed = false

            if not success then
                print("[RARELOAD ERROR] Method failed: " .. tostring(method.name))
                continue
            end

            if safePos and util.IsInWorld(safePos) then
                local isStuck, reason = AntiStuck.IsPositionStuck(safePos, ply)

                if not isStuck then
                    if AntiStuck.CacheSafePosition then
                        AntiStuck.CacheSafePosition(safePos)
                    end

                    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                        RARELOAD.Debug.AntiStuck("Successfully resolved position", {
                            methodName = method.name,
                            methodUsed = method.name,
                            position = safePos,
                            originalPosition = originalPos,
                            success = true,
                            reason = reason
                        }, ply)
                    elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
                        print("[RARELOAD ANTI-STUCK] SUCCESS! Resolved using method: " .. method.name)
                    end

                    return safePos, true
                else
                    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                        print("[RARELOAD ANTI-STUCK] Method " ..
                            method.name .. " returned invalid position (" .. reason .. "), continuing...")
                    end
                end
            else
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Method " .. method.name .. " found no position, continuing...")
                end
            end
        end

        print("[RARELOAD ANTI-STUCK] CRITICAL FAILURE: All enabled methods failed for player " .. ply:Nick())

        if AntiStuck.emergencyFallbackMethod then
            print("[RARELOAD ANTI-STUCK] Trying emergency fallback method")
            local emergencyPos, success = AntiStuck.emergencyFallbackMethod(originalPos, ply)
            return emergencyPos, success
        end

        local emergencyMethod = nil
        local success, result = pcall(function()
            return AntiStuck.GetMethod("TryEmergencyTeleport")
        end)

        if success and result then
            emergencyMethod = result
        end

        if emergencyMethod then
            local emergencyPos, _ = emergencyMethod(originalPos, ply)
            if emergencyPos and util.IsInWorld(emergencyPos) then
                print("[RARELOAD ANTI-STUCK] Using emergency teleport position")
                return emergencyPos, false
            end
        end

        local absoluteFallback = Vector(0, 0, 16384)
        print("[RARELOAD ANTI-STUCK] Using high altitude fallback position")
        return absoluteFallback, false
    end
end
