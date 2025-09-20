local RARELOAD = RARELOAD or {}
local AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuck = AntiStuck

AntiStuck.methodRegistry = AntiStuck.methodRegistry or {}
AntiStuck.methods = AntiStuck.methods or {}
AntiStuck.methodStats = AntiStuck.methodStats or {}

AntiStuck.UNSTUCK_METHODS = {
    NONE = 0,
    SUCCESS = 1,
    PARTIAL = 2,
    FAILED = 3
}

local function ValidateMethodInterface(func)
    if type(func) ~= "function" then return false, "Not a function" end

    local testPos = Vector(0, 0, 0)
    local ok, result1, result2 = pcall(func, testPos, nil)

    if not ok then return false, "Function call failed: " .. tostring(result1) end

    if result1 ~= nil and type(result1) ~= "Vector" then
        return false, "First return must be Vector or nil"
    end

    if result2 ~= nil and type(result2) ~= "number" then
        return false, "Second return must be number or nil"
    end

    return true, "Valid"
end

function AntiStuck.RegisterMethod(name, func, config)
    if not name or type(name) ~= "string" then
        local msg = "Invalid method name: " .. tostring(name)
        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck(msg)
        else
            print("[RARELOAD ERROR] " .. msg)
        end
        return false
    end

    local isValid, errorMsg = ValidateMethodInterface(func)
    if not isValid then
        local msg = "Invalid method interface for '" .. name .. "': " .. errorMsg
        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck(msg)
        else
            print("[RARELOAD ERROR] " .. msg)
        end
        return false
    end

    AntiStuck.methodRegistry[name] = {
        func = func,
        name = name,
        description = config and config.description or "No description",
        enabled = config and config.enabled ~= false or true,
        priority = config and config.priority or 50,
        timeout = config and config.timeout or 2.0,
        retries = config and config.retries or 1,
        registeredAt = os.time()
    }

    AntiStuck.methodStats[name] = {
        calls = 0,
        successes = 0,
        failures = 0,
        totalTime = 0,
        avgTime = 0,
        lastUsed = 0
    }

    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("Registered method: " .. name)
    elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] Registered method: " .. name)
    end
    return true
end

function AntiStuck.GetMethod(name)
    if not name then return nil end
    local methodObj = AntiStuck.methodRegistry[name]
    if methodObj then
        return methodObj.func, methodObj
    end
    return nil
end

function AntiStuck.ExecuteMethod(methodName, originalPos, ply)
    local method = AntiStuck.methodRegistry[methodName]
    if not method then
        if RARELOAD.settings and RARELOAD.settings.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Method not found", { methodName = tostring(methodName) })
        end
        return nil, AntiStuck.UNSTUCK_METHODS.FAILED
    end

    local stats = AntiStuck.methodStats[methodName]
    stats.calls = stats.calls + 1
    stats.lastUsed = CurTime()

    local startTime = SysTime()
    local success, pos, methodResult = pcall(method.func, originalPos, ply)
    local duration = SysTime() - startTime

    stats.totalTime = stats.totalTime + duration
    stats.avgTime = stats.totalTime / stats.calls

    if success and pos then
        stats.successes = stats.successes + 1
        return pos, methodResult or AntiStuck.UNSTUCK_METHODS.SUCCESS
    else
        stats.failures = stats.failures + 1
        local resultCode = methodResult or AntiStuck.UNSTUCK_METHODS.FAILED
        return nil, resultCode
    end
end

function AntiStuck.GetMethodStats(methodName)
    if methodName then
        return AntiStuck.methodStats[methodName]
    else
        return AntiStuck.methodStats
    end
end

function AntiStuck.ResetMethodStats(methodName)
    if methodName then
        AntiStuck.methodStats[methodName] = {
            calls = 0,
            successes = 0,
            failures = 0,
            totalTime = 0,
            avgTime = 0,
            lastUsed = 0
        }
    else
        for name in pairs(AntiStuck.methodStats) do
            AntiStuck.ResetMethodStats(name)
        end
    end
end

AntiStuck.emergencyFallbackMethod = function(originalPos, ply)
    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] Using emergency fallback method")
    end

    local offset = 50
    local testPositions = {
        originalPos + Vector(0, 0, 40),
        originalPos + Vector(offset, 0, 0),
        originalPos + Vector(-offset, 0, 0),
        originalPos + Vector(0, offset, 0),
        originalPos + Vector(0, -offset, 0),
        originalPos + Vector(0, 0, 100),
    }

    for i, pos in ipairs(testPositions) do
        if util.IsInWorld(pos) then
            local isStuck = false
            if AntiStuck.IsPositionStuck then
                isStuck = AntiStuck.IsPositionStuck(pos, ply, false)
            else
                local tr = util.TraceLine({
                    start = pos + Vector(0, 0, 20),
                    endpos = pos - Vector(0, 0, 100),
                    mask = MASK_PLAYERSOLID,
                    collisiongroup = COLLISION_GROUP_NONE,
                    ignoreworld = false,
                    hitclientonly = false,
                    output = {},
                    filter = ply,
                    whitelist = nil
                })

                if tr.Hit then
                    local groundPos = tr.HitPos + Vector(0, 0, 10)
                    if not AntiStuck.IsPositionStuck or not AntiStuck.IsPositionStuck(groundPos, ply, false) then
                        return groundPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
                    end
                end
            end

            if not isStuck then
                return pos, AntiStuck.UNSTUCK_METHODS.SUCCESS
            end
        end
    end

    return Vector(0, 0, 4096), AntiStuck.UNSTUCK_METHODS.PARTIAL
end

function AntiStuck.ToVector(input)
    if not input then return nil end
    if type(input) == "Vector" then return input end
    if type(input) == "table" and input.x and input.y and input.z then
        return Vector(input.x, input.y, input.z)
    end
    if IsValid(input) and input.GetPos then return input:GetPos() end
    if type(input) == "string" then
        local x, y, z = string.match(input, "%[([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)%]")
        if not (x and y and z) then
            x, y, z = string.match(input, "^([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)$")
        end
        if not (x and y and z) then
            x, y, z = string.match(input, "([%d%-%.]+),%s*([%d%-%.]+),%s*([%d%-%.]+)")
        end
        if x and y and z then
            local vx, vy, vz = tonumber(x), tonumber(y), tonumber(z)
            if vx and vy and vz then return Vector(vx, vy, vz) end
        end
    end
    return nil
end
