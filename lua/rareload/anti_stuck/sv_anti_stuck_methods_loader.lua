if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck
local PS = AntiStuck.ProfileSystem

function AntiStuck.LoadMethods(forceReload)
    if not forceReload and AntiStuck.methods and #AntiStuck.methods > 0 and AntiStuck._lastMethodLoad and (CurTime() - AntiStuck._lastMethodLoad) < 30 then
        return true
    end
    AntiStuck._lastMethodLoad = CurTime()

    local profileMethods = (PS and PS.GetCurrentProfileMethods and PS.GetCurrentProfileMethods()) or {}
    if profileMethods and #profileMethods > 0 then
        local validMethods, enabledCount = {}, 0
        local anyCorrections = false
        local defaultByFunc = {}
        if AntiStuck.DefaultMethods then
            for _, dm in ipairs(AntiStuck.DefaultMethods) do
                defaultByFunc[dm.func] = dm
            end
        end
        local step = 10
        for idx, m in ipairs(profileMethods) do
            if m.func and m.name then
                local methodObj = AntiStuck.methodRegistry and AntiStuck.methodRegistry[m.func]
                if methodObj then
                    if m.enabled == nil then m.enabled = true end
                    m.priority = idx * step
                    local def = defaultByFunc[m.func]
                    if def then
                        if m.name ~= def.name and def.name then
                            m.name = def.name
                            anyCorrections = true
                        end
                        if (not m.description or m.description == "") and def.description then
                            m.description = def.description
                            anyCorrections = true
                        end
                        if m.timeout == nil and def.timeout then
                            m.timeout = def.timeout
                            anyCorrections = true
                        end
                    end
                    table.insert(validMethods, m)
                    if m.enabled then enabledCount = enabledCount + 1 end
                else
                    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                        print("[RARELOAD ANTI-STUCK] Warning: Method function '" .. m.func .. "' not registered")
                    end
                end
            else
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Warning: Invalid method configuration (missing func or name)")
                end
            end
        end
        AntiStuck.methods = validMethods

        if anyCorrections and PS and PS.UpdateCurrentProfile then
            PS.UpdateCurrentProfile(nil, validMethods)
        end

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Method loading summary:")
            print("  Profile: " .. ((PS and PS.currentProfile) or "unknown"))
            print("  Total methods loaded: " .. #validMethods)
            print("  Enabled methods: " .. enabledCount)
            print("  Registered functions: " .. table.Count(AntiStuck.methodRegistry or {}))
            print("  Method execution order:")
            for i, method in ipairs(validMethods) do
                local status = method.enabled and "✓" or "✗"
                local regStatus = (AntiStuck.methodRegistry and AntiStuck.methodRegistry[method.func]) and "REG" or
                    "MISSING"
                print(string.format("    %s [%s] %d: %s (%s) - priority: %d", status, regStatus, i, method.name,
                    method.func, method.priority or 50))
            end
        end
        return true
    end

    local defaultMethods = RareloadDeepCopyMethods(AntiStuck.DefaultMethods)
    for _, method in ipairs(defaultMethods) do
        method.enabled = true
        method.priority = method.priority or 50
    end
    table.sort(defaultMethods, function(a, b) return (a.priority or 50) < (b.priority or 50) end)
    AntiStuck.methods = defaultMethods
    AntiStuck.LogDebug("Initialized with default methods",
        { methodName = "LoadMethods", source = "Defaults", methodCount = #AntiStuck.methods })
    return true
end

function AntiStuck.SaveMethods()
    local ok = PS and PS.UpdateCurrentProfile and PS.UpdateCurrentProfile(nil, AntiStuck.methods)
    if ok then
        AntiStuck.LogDebug("Methods saved to profile",
            {
                methodName = "SaveMethods",
                profileName = (PS and PS.currentProfile) or "unknown",
                methodCount = #
                    AntiStuck.methods
            })
    else
        AntiStuck.LogDebug("Failed to save methods to profile",
            { methodName = "SaveMethods", profileName = (PS and PS.currentProfile) or "unknown" }, nil, "ERROR")
    end
end
