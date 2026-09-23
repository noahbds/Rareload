-- ============================================================================
-- Rareload state-provider registry
-- ============================================================================

RARELOAD = RARELOAD or {}
-- StateRegistry is the central registry of all state providers. It handles save/restore order, gating, and dependency management.
RARELOAD.StateRegistry = RARELOAD.StateRegistry or { _list = {}, _byId = {} }

function RARELOAD.StateRegistry.Register(def)
    assert(istable(def) and isstring(def.id) and def.id ~= "", "state provider needs a string id")
    local existing = RARELOAD.StateRegistry._byId[def.id]
    if existing then
        for i = 1, #RARELOAD.StateRegistry._list do
            if RARELOAD.StateRegistry._list[i] == existing then
                RARELOAD.StateRegistry._list[i] = def
                break
            end
        end
    else
        RARELOAD.StateRegistry._list[#RARELOAD.StateRegistry._list + 1] = def
    end
    RARELOAD.StateRegistry._byId[def.id] = def
    return def
end

function RARELOAD.StateRegistry.Get(id)
    return RARELOAD.StateRegistry._byId[id]
end

local function orderedCopy(keyFn)
    local copy = {}
    for i = 1, #RARELOAD.StateRegistry._list do copy[i] = RARELOAD.StateRegistry._list[i] end
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

function RARELOAD.StateRegistry.SaveOrdered()
    return orderedCopy(function(d) return d.saveOrder or d.order or 100 end)
end

function RARELOAD.StateRegistry.RestoreOrdered()
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
function RARELOAD.StateRegistry.CanSave(def, ply, ctx)
    local default = def.settingDefault
    if default == nil then default = true end
    if not permOk(ply, def.savePermission or def.permission) then return false end
    if not settingOn(ply, def.saveSetting or def.setting, default) then return false end
    if isfunction(def.shouldSave) and not def.shouldSave(ply, ctx) then return false end
    return true
end

-- Should this provider restore for this player right now?
function RARELOAD.StateRegistry.CanRestore(def, ply, savedInfo, ctx)
    local default = def.settingDefault
    if default == nil then default = true end
    if not permOk(ply, def.restorePermission or def.permission) then return false end
    if not settingOn(ply, def.restoreSetting or def.setting, default) then return false end
    if isfunction(def.shouldRestore) and not def.shouldRestore(ply, savedInfo, ctx) then return false end
    return true
end

-- Run every save provider that passes its gate, in save order.
function RARELOAD.StateRegistry.RunSave(ply, playerData, ctx)
    for _, def in ipairs(RARELOAD.StateRegistry.SaveOrdered()) do
        if isfunction(def.save) and RARELOAD.StateRegistry.CanSave(def, ply, ctx) then
            def.save(ply, playerData, ctx)
        end
    end
end

function RARELOAD.StateRegistry.RunRestore(ply, savedInfo, ctx)
    if not IsValid(ply) then return end
    ctx = ctx or {}

    ply._rareloadRestoreToken = (ply._rareloadRestoreToken or 0) + 1
    local token = ply._rareloadRestoreToken
    ctx.restoreToken = token
    local function isCurrent() return IsValid(ply) and ply._rareloadRestoreToken == token end
    ctx.isCurrent = isCurrent

    -- Providers that pass their gate this pass.
    local runnable, scheduled = {}, {}
    for _, def in ipairs(RARELOAD.StateRegistry.RestoreOrdered()) do
        if isfunction(def.restore) and RARELOAD.StateRegistry.CanRestore(def, ply, savedInfo, ctx) then
            runnable[#runnable + 1] = def
            scheduled[def.id] = true
        end
    end

    local completed, waiters = {}, {}
    local totalRunnable = #runnable
    local doneCount = 0
    ctx._restored = {}
    local function markComplete(id)
        if not id or completed[id] then return end
        completed[id] = true
        doneCount = doneCount + 1
        ctx._restored[#ctx._restored + 1] = id
        local list = waiters[id]
        if list then
            waiters[id] = nil
            for _, fn in ipairs(list) do fn() end
        end
        if doneCount >= totalRunnable and isfunction(ctx.onAllRestored) then
            ctx.onAllRestored(ctx._restored)
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

    -- Nothing to restore this pass: still notify so a report can finalize.
    if totalRunnable == 0 and isfunction(ctx.onAllRestored) then
        ctx.onAllRestored(ctx._restored)
    end
end

return RARELOAD.StateRegistry
