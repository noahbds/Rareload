RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

AntiStuck.methods = AntiStuck.methods or {}

-- Register a method with the AntiStuck system, you can create your own methods in the "rareload/anti_stuck/methods" directory. Be sure to register then with AntiStuck.RegisterMethod("method_name", AntiStuck.method_name) at the end of your method file.
function AntiStuck.RegisterMethod(name, func)
    if not name or type(name) ~= "string" or not func or type(func) ~= "function" then
        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Invalid method registration", {
                methodName = "RegisterMethod",
                name = tostring(name),
                validFunc = type(func) == "function",
                validName = type(name) == "string",
                action = "Method registration failed"
            }, nil, "ERROR")
        else
            print("[RARELOAD ERROR] Invalid method registration: " .. tostring(name))
        end
        return false
    end

    AntiStuck.methods[name] = func

    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("Registered method: " .. name)
    elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] Registered method: " .. name)
    end

    return true
end

-- Get a method by name, returns nil if not found
function AntiStuck.GetMethod(name)
    if not name or not AntiStuck.methods then return nil end

    if not AntiStuck.methods then
        AntiStuck.methods = {}
        print("[RARELOAD WARNING] Methods table was nil, initialized empty table")
    end

    return AntiStuck.methods[name]
end

-- Fallback method to use when no other methods are available or if all methods fail
AntiStuck.emergencyFallbackMethod = function(originalPos, ply)
    print("[RARELOAD ANTI-STUCK] Using emergency fallback method")
    local offset = 50
    local testPositions = {
        originalPos + Vector(0, 0, 40),
        originalPos + Vector(offset, 0, 0),
        originalPos + Vector(-offset, 0, 0),
        originalPos + Vector(0, offset, 0),
        originalPos + Vector(0, -offset, 0)
    }

    for _, pos in ipairs(testPositions) do
        if util.IsInWorld(pos) then
            local trace = {
                start = pos + Vector(0, 0, 20),
                endpos = pos - Vector(0, 0, 100),
                mask = MASK_PLAYERSOLID
            }
            local tr = util.TraceLine(trace)
            if tr.Hit then
                return tr.HitPos + Vector(0, 0, 10), false
            end
        end
    end

    return Vector(0, 0, 4096), false
end

-- Convert various input formats to a Vector
function AntiStuck.ToVector(input)
    if type(input) == "table" and input.x and input.y and input.z then
        return Vector(input.x, input.y, input.z)
    end

    if type(input) == "string" then
        input = input:Trim():gsub("^\"(.*)\"$", "%1"):gsub("^'(.*)'$", "%1")

        local x, y, z

        x, y, z = string.match(input, "%[([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)%]")

        if not (x and y and z) then
            x, y, z = string.match(input, "^([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)$")
        end

        if not (x and y and z) then
            x, y, z = string.match(input, "([%d%-%.]+),%s*([%d%-%.]+),%s*([%d%-%.]+)")
        end

        if x and y and z then
            local vx, vy, vz = tonumber(x), tonumber(y), tonumber(z)
            if vx and vy and vz then
                return Vector(vx, vy, vz)
            end
        end
    elseif type(input) == "Vector" then
        return input
    elseif IsValid(input) and input.GetPos then
        return input:GetPos()
    end

    return nil
end
