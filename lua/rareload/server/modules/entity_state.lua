-- Entity state adapters (5.4 plan, C6): running state that an entity keeps in its Lua table and that
-- its duplicator factory starts over. What `capture` returns is stored in the object's "rareload"
-- modifier, and `apply` runs after a Rareload paste or reset (Snapshot.ApplyExtras).
--
-- Expression 2 chips need no adapter: Wiremod already passes their variables through the duplicator
-- (the "_vars" field of gmod_wire_expression2), and the chip restores them after compiling.

RARELOAD.EntityState = RARELOAD.EntityState or {}
local EntityState = RARELOAD.EntityState
EntityState.adapters = EntityState.adapters or {}

-- adapter = { id, matches(ent) -> bool, capture(ent) -> table?, apply(ent, t) }
function EntityState.Adapter(adapter)
    EntityState.adapters[adapter.id] = adapter
end

function EntityState.For(ent)
    for _, adapter in SortedPairs(EntityState.adapters) do
        local ok, match = pcall(adapter.matches, ent)
        if ok and match then return adapter end
    end
end

local function plain(value)
    if isnumber(value) or isstring(value) or isbool(value) then return value end
    if isvector(value) then return { value.x, value.y, value.z, vec = true } end
    if not istable(value) then return nil end
    local out = {}
    for key, item in pairs(value) do
        if isnumber(key) or isstring(key) then out[key] = plain(item) end
    end
    return out
end

local function unplain(value)
    if not istable(value) then return value end
    if value.vec then return Vector(value[1], value[2], value[3]) end
    local out = {}
    for key, item in pairs(value) do out[key] = unplain(item) end
    return out
end

-- Wire gates: the memory a gate action keeps on the gate (latches, counters, accumulators, RAM,
-- edge detection). Times (PrevTime, LastT) are left out: they are CurTime values of the old session.
local GATE_FIELDS = { "LatchStore", "Accum", "PrevValue", "Memory", "Stage", "countStore", "PrevReset",
    "PrevInc", "PrevDec", "PrevClk", "Last", "LastA" }

EntityState.Adapter({
    id = "wire_gate",
    matches = function(ent) return ent:GetClass() == "gmod_wire_gate" end,
    capture = function(ent)
        local vars = {}
        for _, field in ipairs(GATE_FIELDS) do vars[field] = plain(ent[field]) end
        return next(vars) and vars or nil
    end,
    apply = function(ent, vars)
        for _, field in ipairs(GATE_FIELDS) do
            if vars[field] ~= nil then ent[field] = unplain(vars[field]) end
        end
        if isfunction(ent.CalcOutput) then ent:CalcOutput() end
    end,
})
