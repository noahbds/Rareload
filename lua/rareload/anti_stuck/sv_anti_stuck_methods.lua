local RARELOAD = RARELOAD or {}
local AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuck = AntiStuck

-- Separate the method registry (functions) from method order data
AntiStuck.methodRegistry = AntiStuck.methodRegistry or {} -- Stores function references
AntiStuck.methods = AntiStuck.methods or {}               -- Stores method order and enabled states

function AntiStuck.RegisterMethod(name, func)
    if not name or type(name) ~= "string" or type(func) ~= "function" then
        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Invalid method registration: " .. tostring(name))
        else
            print("[RARELOAD ERROR] Invalid method registration: " .. tostring(name))
        end
        return false
    end

    -- Store in the method registry
    AntiStuck.methodRegistry[name] = func

    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("Registered method: " .. name)
    elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] Registered method: " .. name)
    end
    return true
end

function AntiStuck.GetMethod(name)
    if not name then return nil end
    -- Look in the method registry for the actual function
    return AntiStuck.methodRegistry[name]
end

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
                return tr.HitPos + Vector(0, 0, 10), false
            end
        end
    end
    return Vector(0, 0, 4096), false
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
