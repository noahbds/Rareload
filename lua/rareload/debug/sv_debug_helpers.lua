-- Category-scoped debug writers, backed by the v2 engine. Kept as its own file
-- because several save/respawn handlers include it directly to build a writer.
if not SERVER then return {} end

RARELOAD = RARELOAD or {}

if RARELOAD.DebugHelpers and RARELOAD.DebugHelpers.Write then
    return RARELOAD.DebugHelpers
end

local DebugState = include("rareload/debug/sv_debug_state.lua")
local DebugHelpers = RARELOAD.DebugHelpers or {}
RARELOAD.DebugHelpers = DebugHelpers

function DebugHelpers.IsEnabledForPlayer(ply)
    if DebugState and DebugState.IsEnabledForPlayer then
        return DebugState.IsEnabledForPlayer(ply)
    end
    return false
end

-- Plain print fallback (used only when the engine isn't available).
function DebugHelpers.PrintLines(prefix, message, details, detailsAsPairs)
    prefix = prefix or "[RARELOAD DEBUG] "
    print(prefix .. tostring(message))
    if istable(details) then
        for k, v in pairs(details) do
            print(prefix .. (detailsAsPairs and (tostring(k) .. ": ") or "") .. tostring(v))
        end
    elseif details ~= nil then
        print(prefix .. tostring(details))
    end
end

-- DebugHelpers.Write(category, level, message, details, opts)
-- opts: { ply, gate (true|"any"|fn), context, ... }. Routes to the structured
-- engine; `details` (list or key/value table) becomes the event's data rows.
function DebugHelpers.Write(category, level, message, details, opts)
    opts = opts or {}
    local ply = opts.ply
    local gate = opts.gate
    if gate == true then
        if not DebugHelpers.IsEnabledForPlayer(ply) then return false end
    elseif gate == "any" then
        if not (DebugState and DebugState.IsAnyEnabled and DebugState.IsAnyEnabled()) then return false end
    elseif isfunction(gate) then
        if not gate(ply, opts.context) then return false end
    end

    local Debug = RARELOAD.Debug
    if Debug and Debug.Log then
        Debug.Log(category or "system", level or "INFO", tostring(message), istable(details) and details or (details ~= nil and { tostring(details) } or nil))
        return true
    end

    if opts.allowPrintFallback then
        DebugHelpers.PrintLines(opts.printPrefix, message, details, opts.detailsAsPairs == true)
        return true
    end
    return false
end

-- Builds a category-scoped writer: function(ply, level, message, details, opts).
function DebugHelpers.MakeWriter(category, defaultOpts)
    defaultOpts = defaultOpts or {}
    return function(ply, level, message, details, opts)
        local merged = {}
        for k, v in pairs(defaultOpts) do merged[k] = v end
        if istable(opts) then for k, v in pairs(opts) do merged[k] = v end end
        merged.ply = ply
        return DebugHelpers.Write(category, level, message, details, merged)
    end
end

return DebugHelpers
