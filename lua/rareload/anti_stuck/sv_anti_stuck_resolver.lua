if SERVER then
    RARELOAD = RARELOAD or {}
    RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
    local AntiStuck = RARELOAD.AntiStuck

    -- Main resolver for stuck positions
    function AntiStuck.ResolveStuckPosition(originalPos, ply)
        -- Always reload selected profile before resolving
        if serverProfileSystem and serverProfileSystem.LoadCurrentProfile then
            serverProfileSystem.LoadCurrentProfile()
        end
        if AntiStuck.LoadMethods then
            AntiStuck.LoadMethods(true)
        else
            print("[RARELOAD ERROR] LoadMethods not available")
        end
        if not AntiStuck.methods or #AntiStuck.methods == 0 then
            print("[RARELOAD ANTI-STUCK] No enabled methods available! Checking method data...")

            -- Debug: Check what methods we actually have
            if serverProfileSystem then
                local profileMethods = serverProfileSystem.GetCurrentProfileMethods()
                if profileMethods then
                    print("[RARELOAD ANTI-STUCK] Profile has " .. #profileMethods .. " methods:")
                    for i, method in ipairs(profileMethods) do
                        print("  " ..
                            i .. ": " .. (method.name or "unnamed") .. " (enabled: " .. tostring(method.enabled) .. ")")
                    end
                else
                    print("[RARELOAD ANTI-STUCK] No profile methods found!")
                end
            else
                print("[RARELOAD ANTI-STUCK] serverProfileSystem not available!")
            end

            if AntiStuck.emergencyFallbackMethod then
                return AntiStuck.emergencyFallbackMethod(originalPos, ply)
            end
            print("[RARELOAD ANTI-STUCK] No methods available! Using absolute fallback position")
            return Vector(0, 0, 16384), false
        end
        local methods = {}
        for _, methodData in ipairs(AntiStuck.methods) do
            if methodData.enabled then
                -- Fix: Look for registered methods in the methods registry, not the loaded method data
                local func = AntiStuck.GetMethod(methodData.func)
                if type(func) == "function" then
                    table.insert(methods, { func = func, name = methodData.name })
                else
                    -- Debug: Show which methods are missing
                    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                        print("[RARELOAD ANTI-STUCK] Method function not found: " .. (methodData.func or "nil"))
                    end
                end
            end
        end
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Will try " .. #methods .. " enabled methods in method order:")
            for i, method in ipairs(methods) do
                print("  " .. i .. ": " .. method.name)
            end
        end
        for _, method in ipairs(methods) do
            local ok, pos, methodType = pcall(function()
                return method.func(originalPos, ply)
            end)
            if ok and pos and methodType and methodType ~= AntiStuck.UNSTUCK_METHODS.NONE then
                if AntiStuck.CacheSafePosition then
                    AntiStuck.CacheSafePosition(pos)
                end
                return pos, true
            end
        end
        print("[RARELOAD ANTI-STUCK] CRITICAL FAILURE: All enabled methods failed for player " ..
            (IsValid(ply) and ply:Nick() or "Unknown"))
        if AntiStuck.emergencyFallbackMethod then
            return AntiStuck.emergencyFallbackMethod(originalPos, ply)
        end
        local ok, emergencyMethod = pcall(function() return AntiStuck.GetMethod("TryEmergencyTeleport") end)
        if ok and emergencyMethod then
            local pos, methodType = emergencyMethod(originalPos, ply)
            if pos and methodType and methodType ~= AntiStuck.UNSTUCK_METHODS.NONE then
                return pos, true
            end
        end
        print("[RARELOAD ANTI-STUCK] Using high altitude fallback position")
        return Vector(0, 0, 16384), false
    end
end
