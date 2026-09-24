-- Save/restore engine: the module registry, phase order, gating, restore tokens and report cards
-- (REWRITE_PLAN.md §14.0, §15). The only file that decides what runs and in which order.

RARELOAD.Pipeline = RARELOAD.Pipeline or {}
local Pipeline = RARELOAD.Pipeline

Pipeline.PHASES = { "position", "player", "inventory", "world", "finalize" }
Pipeline._defs = Pipeline._defs or {}
Pipeline._queue = Pipeline._queue or {}
local defs = Pipeline._defs
local ordered

-- def = { id, phase, after?, setting?, privSave?, privRestore?, heavy?, save(ply, ctx), restore(ply, data, ctx),
--         spawn? = { hook, fn(ply, data, ctx) -> true when handled }, summary?(data) -> string }
function RARELOAD.Module(def)
    defs[def.id] = def
    ordered = nil
end

-- Pure: sorts modules by phase, then by `after` inside a phase, then by id. Errors on an unknown
-- phase or a dependency cycle.
function Pipeline.Order(list)
    local phaseIndex = {}
    for i, p in ipairs(Pipeline.PHASES) do phaseIndex[p] = i end

    local groups = {}
    for _, def in ipairs(list) do
        local i = phaseIndex[def.phase] or error("[Rareload] module " .. def.id .. " has unknown phase " .. tostring(def.phase))
        groups[i] = groups[i] or {}
        table.insert(groups[i], def)
    end

    local out = {}
    for i = 1, #Pipeline.PHASES do
        local group = groups[i] or {}
        table.sort(group, function(a, b) return a.id < b.id end)
        local byId, state = {}, {}
        for _, def in ipairs(group) do byId[def.id] = def end

        local function visit(def)
            if state[def.id] == "done" then return end
            if state[def.id] == "visiting" then error("[Rareload] module dependency cycle at " .. def.id) end
            state[def.id] = "visiting"
            for _, dep in ipairs(def.after or {}) do
                if byId[dep] then visit(byId[dep]) end
            end
            state[def.id] = "done"
            out[#out + 1] = def
        end
        for _, def in ipairs(group) do visit(def) end
    end
    return out
end

local function order()
    if not ordered then
        local list = {}
        for _, def in pairs(defs) do list[#list + 1] = def end
        ordered = Pipeline.Order(list)
    end
    return ordered
end

-- Fail on bad module definitions at load time, not on the first save.
hook.Add("RareloadLoaded", "Rareload.Pipeline.Validate", function() order() end)

-- One Tick hook runs deferred work; the pipeline and modules never use timers (§15.1).
hook.Add("Tick", "Rareload.Pipeline.NextTick", function()
    local queue = Pipeline._queue
    if #queue == 0 then return end
    Pipeline._queue = {}
    for _, fn in ipairs(queue) do ProtectedCall(fn) end
end)

-- Rareload only runs in Sandbox-derived gamemodes unless a server admin allows the rest (D19, G54).
function Pipeline.Enabled()
    return (GAMEMODE and GAMEMODE.IsSandboxDerived) or RARELOAD.Get(nil, "enableInAllGamemodes")
end

-- NPC factories need the map to be fully loaded (L3); a cleanup makes it "not ready" again briefly.
Pipeline.mapReady = Pipeline.mapReady or false
hook.Add("InitPostEntity", "Rareload.Pipeline.MapReady", function() Pipeline.mapReady = true end)
hook.Add("PreCleanupMap", "Rareload.Pipeline.MapReady", function() Pipeline.mapReady = false end)
hook.Add("PostCleanupMap", "Rareload.Pipeline.MapReady", function()
    local queue = Pipeline._queue
    queue[#queue + 1] = function() Pipeline.mapReady = true end
end)

-- After a Source save load or a map transition the engine already restored the world, so the first
-- spawn of each player skips the world modules (E30, G51, B29).
local externalWorld = {}
hook.Add("InitPostEntity", "Rareload.Pipeline.ExternalWorld", function()
    local how = game.MapLoadType()
    if how == "loadgame" or how == "transition" then externalWorld.active = true end
end)

local function allowed(def, ply, saving)
    local priv = saving and def.privSave or def.privRestore
    if priv and not RARELOAD.Can(ply, priv) then return false end
    if def.setting and not RARELOAD.Get(ply, def.setting) then return false end
    return true
end

-- Heavy data is stored as { ["$blob"] = hash } (§16.2); this returns the real data either way.
function Pipeline.Payload(value)
    if istable(value) and value["$blob"] then return RARELOAD.Store.BlobGet(value["$blob"]) end
    return value
end

-- Runs fn like ProtectedCall (an error is still printed with its stack), and also returns the error
-- text and how long it took in ms, for the report card.
local function run(fn, ...)
    local started = SysTime()
    local ok, err = xpcall(fn, function(e) ErrorNoHaltWithStack(e) return tostring(e) end, ...)
    return ok, not ok and err or nil, (SysTime() - started) * 1000
end

-- Save --------------------------------------------------------------------------------------------

local function refuse(ply, opts, why)
    if not opts.silent then RARELOAD.Toast(ply, "toast.save_denied", nil, "error") end
    return false, why
end

-- A manual save copies every object the player owns, so saving faster than this only adds load
-- (a player clicking the tool as fast as they can, on a big build, would lag the server).
local MANUAL_COOLDOWN = 1
local lastManual = setmetatable({}, { __mode = "k" })

-- opts = { at?: Vector, reason?: string, only?: { [moduleId] = true }, silent?: bool, captureOnly?: bool,
--          keepMissing?: bool (a module that captures nothing keeps its data from the current save) }
-- Returns true plus "saved" or "unchanged", or false plus the reason. With captureOnly the entry is
-- returned instead of saved, with heavy data inline (used for undo, which must not depend on blobs).
function Pipeline.Save(ply, opts)
    opts = opts or {}
    if not Pipeline.Enabled() then return false, "gamemode" end
    if not RARELOAD.Get(ply, "enabled") then return refuse(ply, opts, "disabled") end
    if not RARELOAD.Can(ply, "rareload_save") then return refuse(ply, opts, "permission") end
    if not ply:Alive() or ply:GetObserverMode() ~= OBS_MODE_NONE then return refuse(ply, opts, "state") end   -- E33
    if not RARELOAD.Util.PlayerKey(ply) then return refuse(ply, opts, "no steamid") end                      -- E24
    if hook.Run("RareloadCanSave", ply, opts.reason) == false then return refuse(ply, opts, "hook") end
    if not opts.silent and not opts.captureOnly then
        if CurTime() - (lastManual[ply] or -math.huge) < MANUAL_COOLDOWN then
            RARELOAD.Toast(ply, "toast.save_wait", nil, "error")
            return false, "cooldown"
        end
        lastManual[ply] = CurTime()
    end

    local prev = RARELOAD.History.Active(ply)
    local ctx = { ply = ply, opts = opts, prev = prev, shared = {} }
    local session = RARELOAD.Log.Session("Save (" .. (opts.reason or "command") .. ")", ply, "save")

    -- A partial save keeps the other modules' data from the current save.
    local data = {}
    if opts.only and prev and not opts.captureOnly then
        for id, value in pairs(prev.data) do data[id] = value end
    end

    for _, def in ipairs(order()) do
        if not opts.only or opts.only[def.id] then
            local kept = opts.keepMissing and data[def.id] or nil
            data[def.id] = nil
            if allowed(def, ply, true) then
                local out
                local ok, err, ms = run(function() out = def.save(ply, ctx) end)
                if not ok then
                    out = prev and Pipeline.Payload(prev.data[def.id])   -- fail soft: keep the last good value
                end
                local detail = not ok and err or out == nil and "nothing to save" or def.summary and def.summary(out) or ""
                session:step(ok and "ok" or "fail", def.id, detail, ms)
                if out ~= nil and def.heavy and not opts.captureOnly then
                    out = { ["$blob"] = RARELOAD.Store.BlobPut(out) }
                end
                if out == nil then out = kept end
                data[def.id] = out
            end
        end
    end

    local entry = { time = os.time(), reason = opts.reason or "command", data = data }
    if opts.captureOnly then return true, "captured", entry end

    local info = { reason = opts.reason or "command", auto = opts.silent == true }
    if prev and RARELOAD.Util.Equal(prev.data, data) then
        if not opts.silent then
            RARELOAD.Toast(ply, "toast.unchanged", { prev.id })
            info.result, info.entry = "unchanged", prev.id
            session:finish(info)   -- silent saves (autosave) that change nothing aren't worth a card
        end
        return true, "unchanged"
    end

    RARELOAD.History.Append(ply, entry)
    if not opts.silent then RARELOAD.Toast(ply, "toast.saved", { entry.id }, "ok") end
    info.result, info.entry = "saved", entry.id
    session:finish(info)
    hook.Run("RareloadSaved", ply, entry)
    return true, "saved"
end

-- Restore -----------------------------------------------------------------------------------------

local tokens = setmetatable({}, { __mode = "k" })    -- ply -> number of the latest restore (L21)
local pending = setmetatable({}, { __mode = "k" })   -- ply -> spawn restore waiting for its gamemode hooks
local ASYNC_TIMEOUT = 10

local Ctx = {}
Ctx.__index = Ctx

function Ctx:isCurrent()
    return IsValid(self.ply) and tokens[self.ply] == self.token
end

function Ctx:nextTick(fn)
    local queue = Pipeline._queue
    queue[#queue + 1] = function()
        if self:isCurrent() then fn() end
    end
end

-- Polls `pred` once per tick; runs `fn` when it's true, or `onTimeout` after `timeout` seconds.
function Ctx:waitFor(pred, timeout, fn, onTimeout)
    local deadline = CurTime() + timeout
    local function poll()
        if pred() then
            fn()
        elseif CurTime() > deadline then
            if onTimeout then onTimeout() end
        else
            self:nextTick(poll)
        end
    end
    self:nextTick(poll)
end

function Ctx:step(status, title, detail, ms)
    self.session:step(status, title, detail, ms)
end

-- Remembers entities this restore created, including ones created later (E14), for undo.
function Ctx:spawnedAdd(ent)
    self.spawned[#self.spawned + 1] = ent
end

local runFrom

-- A module that finishes later calls ctx:async() and then the returned function when it's done.
-- The pipeline waits for it (at most ASYNC_TIMEOUT seconds) before running the next module.
function Ctx:async(label)
    local finished = false
    self._waiting = true
    local resume = function()
        if finished then return end
        finished = true
        local at = self._resumeAt
        self:nextTick(function() runFrom(self, at) end)
    end
    self:waitFor(function() return finished end, ASYNC_TIMEOUT, function() end, function()
        self:step("warn", label, "still running after " .. ASYNC_TIMEOUT .. " s; continuing")
        resume()
    end)
    return resume
end

local function wants(ctx, def)
    if ctx.skipWorld and def.phase == "world" then return false end
    return (not ctx.only or ctx.only[def.id]) and ctx.entry.data[def.id] ~= nil and allowed(def, ctx.ply, false)
end

runFrom = function(ctx, i)
    pending[ctx.ply] = nil
    local list = order()
    while i <= #list do
        if not ctx:isCurrent() then return end
        local def = list[i]
        i = i + 1
        if wants(ctx, def) then
            local data = Pipeline.Payload(ctx.entry.data[def.id])
            if data == nil then
                ctx:step("fail", def.id, "saved data is missing")
            else
                ctx._waiting, ctx._resumeAt = false, i
                local ok, err, ms = run(def.restore, ctx.ply, data, ctx)
                ctx:step(ok and "ok" or "fail", def.id, not ok and err or def.summary and def.summary(data) or "", ms)
                if ok and ctx._waiting then return end
            end
        end
    end
    ctx.session:finish({ reason = ctx.reason, entry = ctx.entry.id })
    hook.Run("RareloadRestored", ctx.ply, ctx.entry)
end

-- opts = { reason?: "spawn"|"timeline"|"undo"|..., only?: { [moduleId] = true } }
-- On a spawn, modules with a `spawn` hook run inside the gamemode's own spawn hooks (G16, G17);
-- everything else runs one tick later, once the gamemode has applied its spawn defaults.
function Pipeline.Restore(ply, entry, opts)
    opts = opts or {}
    local token = (tokens[ply] or 0) + 1
    tokens[ply] = token

    local reason = opts.reason or "timeline"
    local ctx = setmetatable({
        ply = ply, entry = entry, reason = reason, only = opts.only, token = token,
        spawnDone = {}, shared = {}, spawned = {},
        session = RARELOAD.Log.Session("Restore (" .. reason .. ")", ply, "restore"),
    }, Ctx)
    if reason == "spawn" then
        pending[ply] = ctx
        local key = RARELOAD.Util.PlayerKey(ply)
        if externalWorld.active and key and not externalWorld[key] then
            externalWorld[key] = true
            ctx.skipWorld = true
            ctx:step("warn", "world", "skipped: the engine restored the world from a save")
        end
    end
    ctx:nextTick(function() runFrom(ctx, 1) end)
    return ctx
end

-- Called from the gamemode's PlayerSetModel / PlayerLoadout hooks. Returns true when a module took
-- over that hook, so the caller can stop the gamemode default.
function Pipeline.SpawnHook(ply, hookName)
    local ctx = pending[ply]
    if not ctx or not ctx:isCurrent() then return false end

    local handled = false
    for _, def in ipairs(order()) do
        if def.spawn and def.spawn.hook == hookName and wants(ctx, def) then
            local result
            ProtectedCall(function() result = def.spawn.fn(ply, Pipeline.Payload(ctx.entry.data[def.id]), ctx) end)
            if result then
                ctx.spawnDone[def.id] = true
                handled = true
            end
        end
    end
    return handled
end

-- Drops any restore in progress for this player.
function Pipeline.Cancel(ply)
    tokens[ply] = (tokens[ply] or 0) + 1
    pending[ply] = nil
end
