-- Rareload debug networking: batches structured events (max ~10Hz) and streams
-- them, plus session reports, only to players who have their own debug enabled.
if not SERVER then return end

RARELOAD = RARELOAD or {}
local Debug = RARELOAD.Debug
if not Debug then return end

util.AddNetworkString("RareloadDebugBatch")
util.AddNetworkString("RareloadDebugReport")
util.AddNetworkString("RareloadDebugSync")
util.AddNetworkString("RareloadDebugStatus")
util.AddNetworkString("RareloadDebugDiag")

-- Serialize one event. `data` is a list of {key,val} strings; seq lets the
-- client upsert (so a collapsed repeat updates its existing line via count).
local function writeEvent(ev)
    net.WriteUInt(ev.seq or 0, 32)
    net.WriteUInt(math.min(ev.count or 1, 65535), 16)
    net.WriteString(ev.category or "system")
    net.WriteUInt(ev.level or 3, 3)
    net.WriteString(string.sub(ev.message or "", 1, 400))
    local data = ev.data or {}
    local n = math.min(#data, 32)
    net.WriteUInt(n, 6)
    for i = 1, n do
        net.WriteString(string.sub(data[i][1] or "", 1, 48))
        net.WriteString(string.sub(data[i][2] or "", 1, 200))
    end
end

local function sendBatch(events, targets)
    if #events == 0 then return end
    net.Start("RareloadDebugBatch")
    local n = math.min(#events, 255)
    net.WriteUInt(n, 8)
    for i = 1, n do writeEvent(events[i]) end
    net.Send(targets)
end

--------------------------------------------------------------------------------
-- Per-frame batch queue
--------------------------------------------------------------------------------
local pending = {}        -- ordered list of events awaiting send
local pendingBySeq = {}   -- seq -> index in `pending`, to dedup collapsed repeats

function Debug.Enqueue(ev)
    local idx = pendingBySeq[ev.seq]
    if idx then
        pending[idx] = ev -- updated (e.g. bumped count); keep position
    else
        pending[#pending + 1] = ev
        pendingBySeq[ev.seq] = #pending
    end
end

local function flush()
    if #pending == 0 then return end
    local subs = Debug.Subscribers()
    if #subs > 0 then
        -- send in chunks of 255
        for start = 1, #pending, 255 do
            local chunk = {}
            for i = start, math.min(start + 254, #pending) do chunk[#chunk + 1] = pending[i] end
            sendBatch(chunk, subs)
        end
    end
    pending = {}
    pendingBySeq = {}
end

timer.Create("RareloadDebugFlush", 0.1, 0, flush)

-- Direct one event to a single player (Debug.ToPlayer); bypasses batching.
function Debug.SendTo(ply, ev)
    if not IsValid(ply) then return end
    sendBatch({ ev }, ply)
end

-- Kept for callers/tests that push a single event immediately.
function Debug.Broadcast(ev)
    Debug.Enqueue(ev)
end

--------------------------------------------------------------------------------
-- Session report card
--------------------------------------------------------------------------------
function Debug.SendReport(sess)
    local subs = Debug.Subscribers()
    if #subs == 0 then return end
    net.Start("RareloadDebugReport")
    net.WriteString(sess.category or "system")
    net.WriteBool(sess.outcome and sess.outcome.success == true)
    net.WriteString(string.format("%.3fs", sess.elapsed or 0))
    net.WriteString(tostring((sess.meta and sess.meta.title) or sess.category or ""))
    local steps = sess.steps or {}
    local n = math.min(#steps, 40)
    net.WriteUInt(n, 6)
    for i = 1, n do
        local st = steps[i]
        net.WriteString(st.status or "")
        net.WriteString(string.sub(st.title or "", 1, 120))
        net.WriteString(string.sub(st.detail or "", 1, 160))
    end
    net.Send(subs)
end

--------------------------------------------------------------------------------
-- Status: running counters + live watch values, polled and streamed.
--------------------------------------------------------------------------------
local function sendStatus(targets)
    local stats = Debug.stats or {}
    local watches = Debug.EvalWatches and Debug.EvalWatches() or {}
    net.Start("RareloadDebugStatus")
    net.WriteUInt(stats.errors or 0, 24)
    net.WriteUInt(stats.warns or 0, 24)
    net.WriteUInt(stats.total or 0, 24)
    local n = math.min(#watches, 32)
    net.WriteUInt(n, 6)
    for i = 1, n do
        net.WriteString(string.sub(watches[i][1] or "", 1, 32))
        net.WriteString(string.sub(watches[i][2] or "", 1, 64))
    end
    net.Send(targets)
end

timer.Create("RareloadDebugStatus", 0.25, 0, function()
    local subs = Debug.Subscribers()
    if #subs > 0 then sendStatus(subs) end
end)

-- Client asks for the current backlog when it opens the HUD.
net.Receive("RareloadDebugSync", function(_, ply)
    if not Debug.EnabledFor(ply) then return end
    sendBatch(Debug.Recent(80), ply)
    sendStatus(ply)
end)

-- Player requested a diagnostics snapshot from the HUD.
net.Receive("RareloadDebugDiag", function(_, ply)
    if not Debug.EnabledFor(ply) then return end
    if Debug.Diag then Debug.Diag() end
end)
