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
    for _, a in SortedPairs(EntityState.adapters) do
        local ok, match = pcall(a.matches, ent)
        if ok and match then return a end
    end
end

local function plain(v)
    if isnumber(v) or isstring(v) or isbool(v) then return v end
    if isvector(v) then return { v.x, v.y, v.z, vec = true } end
    if not istable(v) then return nil end
    local out = {}
    for k, x in pairs(v) do
        if isnumber(k) or isstring(k) then out[k] = plain(x) end
    end
    return out
end

local function unplain(v)
    if not istable(v) then return v end
    if v.vec then return Vector(v[1], v[2], v[3]) end
    local out = {}
    for k, x in pairs(v) do out[k] = unplain(x) end
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
        local t = {}
        for _, field in ipairs(GATE_FIELDS) do t[field] = plain(ent[field]) end
        return next(t) and t or nil
    end,
    apply = function(ent, t)
        for _, field in ipairs(GATE_FIELDS) do
            if t[field] ~= nil then ent[field] = unplain(t[field]) end
        end
        if isfunction(ent.CalcOutput) then ent:CalcOutput() end
    end,
})
