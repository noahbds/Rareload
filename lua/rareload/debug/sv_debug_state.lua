-- Debug enablement state, backed by the v2 engine. Kept as its own file because
-- several handlers include it directly.
if not SERVER then return {} end

RARELOAD = RARELOAD or {}
RARELOAD.DebugState = RARELOAD.DebugState or {}
local DebugState = RARELOAD.DebugState

local function D() return RARELOAD.Debug end

function DebugState.IsGlobalDebugEnabled()
    return RARELOAD.settings and RARELOAD.settings.debugEnabled == true
end
RARELOAD.IsGlobalDebugEnabled = DebugState.IsGlobalDebugEnabled

function DebugState.IsEnabledForPlayer(ply)
    local d = D()
    if d and d.EnabledFor then return d.EnabledFor(ply) end
    return DebugState.IsGlobalDebugEnabled()
end

function DebugState.IsAnyEnabled()
    local d = D()
    if d and d.AnyoneListening then return d.AnyoneListening() end
    return DebugState.IsGlobalDebugEnabled()
end

return DebugState
