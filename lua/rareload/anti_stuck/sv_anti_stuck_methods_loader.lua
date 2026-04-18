if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.LoadMethods(forceReload)
    if not forceReload and AntiStuck.methods and #AntiStuck.methods > 0 and AntiStuck._lastMethodLoad and (CurTime() - AntiStuck._lastMethodLoad) < 30 then
        return true
    end
    AntiStuck._lastMethodLoad = CurTime()

    local defaultMethods = RareloadDeepCopyMethods(AntiStuck.DefaultMethods)
    local validMethods = {}
    for idx, method in ipairs(defaultMethods) do
        method.enabled = method.enabled ~= false
        method.priority = method.priority or (idx * 10)
        if method.func and method.name and AntiStuck.methodRegistry and AntiStuck.methodRegistry[method.func] then
            table.insert(validMethods, method)
        elseif AntiStuck.DebugEnabled and AntiStuck.DebugEnabled() then
            print("[RARELOAD ANTI-STUCK] Skipping unregistered method: " .. tostring(method.func))
        end
    end

    table.sort(validMethods, function(a, b) return (a.priority or 50) < (b.priority or 50) end)
    AntiStuck.methods = validMethods

    AntiStuck.LogDebug("Initialized with default methods",
        { methodName = "LoadMethods", source = "Defaults", methodCount = #validMethods })

    return true
end

function AntiStuck.SaveMethods()
    AntiStuck.LogDebug("SaveMethods skipped (runtime method editing disabled)", { methodName = "SaveMethods" })
end
