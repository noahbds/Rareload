-- ============================================================================
-- Rareload state-provider registry
--
-- A single declarative list describing every piece of player/world state that
-- Rareload saves and restores. save_point and the player-spawn handler iterate
-- this registry instead of hardcoding a block per state, so adding a new saved
-- state type is one Register{} call rather than edits scattered across both
-- files plus their permission/setting gating.
--
-- A provider definition may set:
--   id                (string, required) unique identifier
--   savePermission    permission name gating capture   (default: `permission`)
--   restorePermission permission name gating restore   (default: `permission`)
--   saveSetting       per-player setting gating capture (default: `setting`)
--   restoreSetting    per-player setting gating restore (default: `setting`)
--   settingDefault    default value for a missing setting (default: true)
--   saveOrder         sort key for the save pass  (default: `order` or 100)
--   restoreOrder      sort key for the restore pass (default: `order` or 100)
--   restoreDelay      timer.Simple delay before restore runs (default: 0)
--   save(ply, playerData, ctx)   captures state into playerData
--   restore(ply, savedInfo, ctx) applies saved state (already gated + delayed)
--   shouldSave(ply, ctx)         optional extra gate on top of perm+setting
--   shouldRestore(ply, savedInfo, ctx) optional extra gate
--
-- Gating (permission + setting) is applied centrally by the runners; providers
-- only implement the capture/restore body.
-- ============================================================================

RARELOAD = RARELOAD or {}
RARELOAD.StateRegistry = RARELOAD.StateRegistry or { _list = {}, _byId = {} }

local R = RARELOAD.StateRegistry

-- Register (or replace) a provider by id. Replacing in place keeps the registry
-- stable across the addon's Lua hot-reloads and the repeated includes of the
-- providers file from save_point / player_spawn.
function R.Register(def)
    assert(istable(def) and isstring(def.id) and def.id ~= "", "state provider needs a string id")
    local existing = R._byId[def.id]
    if existing then
        for i = 1, #R._list do
            if R._list[i] == existing then
                R._list[i] = def
                break
            end
        end
    else
        R._list[#R._list + 1] = def
    end
    R._byId[def.id] = def
    return def
end

function R.Get(id)
    return R._byId[id]
end

local function orderedCopy(keyFn)
    local copy = {}
    for i = 1, #R._list do copy[i] = R._list[i] end
    -- stable sort: fall back to registration index for equal keys
    local index = {}
    for i = 1, #copy do index[copy[i]] = i end
    table.sort(copy, function(a, b)
        local ka, kb = keyFn(a), keyFn(b)
        if ka == kb then return index[a] < index[b] end
        return ka < kb
    end)
    return copy
end

function R.SaveOrdered()
    return orderedCopy(function(d) return d.saveOrder or d.order or 100 end)
end

function R.RestoreOrdered()
    return orderedCopy(function(d) return d.restoreOrder or d.order or 100 end)
end

-- ----------------------------------------------------------------------------
-- Central gating helpers used by the runners.
-- ----------------------------------------------------------------------------

local function permOk(ply, permName)
    if not permName then return true end
    if RARELOAD.CheckPermission then return RARELOAD.CheckPermission(ply, permName) end
    return true
end

local function settingOn(ply, settingKey, default)
    if not settingKey then return true end
    return RARELOAD.GetPlayerSetting(ply, settingKey, default) and true or false
end

-- Should this provider capture for this player right now?
function R.CanSave(def, ply, ctx)
    local default = def.settingDefault
    if default == nil then default = true end
    if not permOk(ply, def.savePermission or def.permission) then return false end
    if not settingOn(ply, def.saveSetting or def.setting, default) then return false end
    if isfunction(def.shouldSave) and not def.shouldSave(ply, ctx) then return false end
    return true
end

-- Should this provider restore for this player right now?
function R.CanRestore(def, ply, savedInfo, ctx)
    local default = def.settingDefault
    if default == nil then default = true end
    if not permOk(ply, def.restorePermission or def.permission) then return false end
    if not settingOn(ply, def.restoreSetting or def.setting, default) then return false end
    if isfunction(def.shouldRestore) and not def.shouldRestore(ply, savedInfo, ctx) then return false end
    return true
end

-- Run every save provider that passes its gate, in save order.
function R.RunSave(ply, playerData, ctx)
    for _, def in ipairs(R.SaveOrdered()) do
        if isfunction(def.save) and R.CanSave(def, ply, ctx) then
            def.save(ply, playerData, ctx)
        end
    end
end

-- Deterministic restore runner.
--
--  * Per-life token: each call bumps ply._rareloadRestoreToken. Every scheduled
--    step captures that token and no-ops if the player has since respawned, so a
--    fast death->respawn can never let the previous life's pending timers land on
--    the new one. ctx.isCurrent() lets provider-internal deferrals opt in too.
--  * dependsOn: a provider with `dependsOn = "<id>"` runs only after that
--    provider has completed, instead of racing it on a fixed delay. A provider
--    marked `restoreAsync = true` receives a `done` callback and signals its own
--    completion (used by inventory, whose global path finishes ~0.5s later); all
--    others complete as soon as their restore returns. A dependency that is
--    gated out is treated as already complete, so dependents never hang.
--  * restoreDelay: still honored, but now applied when the step becomes eligible
--    (i.e. after its dependency), not as an absolute offset from spawn.
function R.RunRestore(ply, savedInfo, ctx)
    if not IsValid(ply) then return end
    ctx = ctx or {}

    ply._rareloadRestoreToken = (ply._rareloadRestoreToken or 0) + 1
    local token = ply._rareloadRestoreToken
    ctx.restoreToken = token
    local function isCurrent() return IsValid(ply) and ply._rareloadRestoreToken == token end
    ctx.isCurrent = isCurrent

    -- Providers that pass their gate this pass.
    local runnable, scheduled = {}, {}
    for _, def in ipairs(R.RestoreOrdered()) do
        if isfunction(def.restore) and R.CanRestore(def, ply, savedInfo, ctx) then
            runnable[#runnable + 1] = def
            scheduled[def.id] = true
        end
    end

    local completed, waiters = {}, {}
    local function markComplete(id)
        if not id or completed[id] then return end
        completed[id] = true
        local list = waiters[id]
        if list then
            waiters[id] = nil
            for _, fn in ipairs(list) do fn() end
        end
    end
    local function afterComplete(id, fn)
        if not scheduled[id] or completed[id] then
            fn() -- dependency gated out or already done: don't wait
        else
            waiters[id] = waiters[id] or {}
            table.insert(waiters[id], fn)
        end
    end

    local function runProvider(def)
        if not isCurrent() then return end
        if def.restoreAsync then
            def.restore(ply, savedInfo, ctx, function()
                if isCurrent() then markComplete(def.id) end
            end)
        else
            def.restore(ply, savedInfo, ctx)
            markComplete(def.id)
        end
    end

    local function schedule(def)
        local function eligible()
            if not isCurrent() then return end
            local delay = tonumber(def.restoreDelay) or 0
            if delay <= 0 then
                runProvider(def)
            else
                timer.Simple(delay, function()
                    if isCurrent() then runProvider(def) end
                end)
            end
        end
        if def.dependsOn then afterComplete(def.dependsOn, eligible) else eligible() end
    end

    for _, def in ipairs(runnable) do
        schedule(def)
    end
end

return R
