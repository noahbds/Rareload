-- ============================================================================
-- rareload/core/vehicles/adapters/lvs.lua
--
-- LVS (ent.LVS). sv_duping.lua resets active/engine/AI on paste and re-inits
-- after ~1s, exposing GetlvsReady() as a readiness flag.
-- ============================================================================

local Adapters = include("rareload/core/vehicles/rareload_vehicle_adapters.lua")
local Seats    = include("rareload/core/vehicles/rareload_vehicle_seats.lua")
local H        = include("rareload/core/vehicles/adapters/_shared.lua")

--- Recursively collect child entities that expose per-component HP.
local function collectHealthComponents(root, out, seen, ent, depth)
    if depth > 4 or not IsValid(ent) or not isfunction(ent.GetChildren) then return end
    for _, child in ipairs(ent:GetChildren() or {}) do
        if IsValid(child) and not seen[child] then
            seen[child] = true
            if isfunction(child.GetHP) and isfunction(child.SetHP) then
                out[#out + 1] = child
            end
            collectHealthComponents(root, out, seen, child, depth + 1)
        end
    end
end

local function healthComponents(root)
    local out, seen = {}, {}
    collectHealthComponents(root, out, seen, root, 0)
    return out
end

Adapters.Register({
    id       = "lvs",
    priority = 20,
    selfStabilizes = true,

    matches = function(ent)
        return IsValid(ent) and ent.LVS == true
    end,

    isReady = function(ent)
        if isfunction(ent.GetlvsReady) then
            local ok, ready = pcall(ent.GetlvsReady, ent)
            if ok then return ready == true end
        end
        return H.physReady(ent)
    end,

    captureRoot = function(ent)
        local root = {}
        root.engineActive = H.getBool(ent, "GetEngineActive")
        root.active       = H.getBool(ent, "GetActive")
        root.hp           = H.getNum(ent, "GetHP")
        root.maxHp        = H.getNum(ent, "GetMaxHP")
        root.damaged      = H.getBool(ent, "GetDamaged")
        root.ambientLight = H.get(ent, "GetAmbientLight")
        H.captureCosmetic(ent, root)
        return next(root) and root or nil
    end,

    captureComponents = function(ent)
        local out = {}
        for _, c in ipairs(healthComponents(ent)) do
            local hp = H.getNum(c, "GetHP")
            if hp then
                local lp = ent:WorldToLocal(c:GetPos())
                out[#out + 1] = {
                    role     = c:GetClass(),
                    localPos = { x = lp.x, y = lp.y, z = lp.z },
                    hp       = hp,
                    maxHp    = H.getNum(c, "GetMaxHP"),
                }
            end
        end
        return #out > 0 and out or nil
    end,

    applyRoot = function(ent, root)
        H.set(ent, "SetMaxHP", root.maxHp)
        H.set(ent, "SetHP", root.hp)
        if root.damaged ~= nil then H.set(ent, "SetDamaged", root.damaged == true) end
        H.set(ent, "SetAmbientLight", root.ambientLight)
        if root.engineActive ~= nil then H.set(ent, "SetEngineActive", root.engineActive == true) end
        if root.active ~= nil then H.set(ent, "SetActive", root.active == true) end
        H.applyCosmetic(ent, root)
    end,

    applyComponents = function(ent, components)
        local live = healthComponents(ent)
        local used = {}
        for _, saved in ipairs(components) do
            local target = Vector(saved.localPos and saved.localPos.x or 0,
                saved.localPos and saved.localPos.y or 0,
                saved.localPos and saved.localPos.z or 0)
            local best, bestDist
            for _, c in ipairs(live) do
                if not used[c] and c:GetClass() == saved.role then
                    local d = ent:WorldToLocal(c:GetPos()):DistToSqr(target)
                    if not bestDist or d < bestDist then bestDist, best = d, c end
                end
            end
            if IsValid(best) then
                used[best] = true
                H.set(best, "SetMaxHP", saved.maxHp)
                H.set(best, "SetHP", saved.hp)
            end
        end
    end,

    captureSeats = H.captureOccupiedSeats,
    resolveSeat  = function(ent, seatInfo) return Seats.Resolve(ent, seatInfo) end,
})
