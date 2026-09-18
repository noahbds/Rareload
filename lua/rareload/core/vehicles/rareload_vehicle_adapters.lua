-- ============================================================================
-- Vehicle Framework Adapter registry.
-- ============================================================================

RARELOAD = RARELOAD or {}
if RARELOAD.VehicleAdapters then return RARELOAD.VehicleAdapters end

local Adapters = {}
RARELOAD.VehicleAdapters = Adapters

local registry = {}      -- id -> adapter
local ordered  = {}      -- adapters sorted by priority desc (rebuilt on register)
local genericId = nil    -- fallback adapter id (the Source adapter registers as generic)

local function rebuildOrder()
    ordered = {}
    for _, adapter in pairs(registry) do
        ordered[#ordered + 1] = adapter
    end
    table.sort(ordered, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)
end

function Adapters.Register(adapter)
    if not istable(adapter) or not isstring(adapter.id) or adapter.id == "" then
        error("[Rareload] VehicleAdapters.Register requires an adapter table with a string id")
    end
    if not isfunction(adapter.matches) and not adapter.generic then
        error("[Rareload] Vehicle adapter '" .. adapter.id .. "' needs a matches(ent) function")
    end

    adapter.priority     = tonumber(adapter.priority) or 0
    adapter.readyTimeout = tonumber(adapter.readyTimeout) or 4.0

    registry[adapter.id] = adapter
    if adapter.generic then genericId = adapter.id end
    rebuildOrder()
    return adapter
end

function Adapters.Get(id)
    return registry[id]
end

function Adapters.Generic()
    return genericId and registry[genericId] or nil
end

function Adapters.Resolve(ent)
    if not IsValid(ent) then return Adapters.Generic() end

    for i = 1, #ordered do
        local adapter = ordered[i]
        if not adapter.generic and isfunction(adapter.matches) then
            local ok, matched = pcall(adapter.matches, ent)
            if ok and matched then return adapter end
        end
    end

    return Adapters.Generic()
end

function Adapters.ResolveByIdOrEntity(savedId, ent)
    if isstring(savedId) and registry[savedId] then return registry[savedId] end
    return Adapters.Resolve(ent)
end

function Adapters.All()
    return ordered
end

local loaded = false
function Adapters.EnsureLoaded()
    if loaded then return end
    loaded = true
    include("rareload/core/vehicles/adapters/source.lua") -- generic fallback first
    include("rareload/core/vehicles/adapters/simfphys.lua")
    include("rareload/core/vehicles/adapters/lvs.lua")
    include("rareload/core/vehicles/adapters/glide.lua")
    include("rareload/core/vehicles/adapters/lfs.lua")
    include("rareload/core/vehicles/adapters/wac.lua")
end

return Adapters
