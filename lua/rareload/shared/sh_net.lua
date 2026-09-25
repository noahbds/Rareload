-- Networking: the only file using net.*. Server pushes topics (JSON, compressed, chunked, paced per
-- client); clients send validated, rate-limited, privilege-checked requests (REWRITE_PLAN.md §13.4, §17).

RARELOAD.Net = RARELOAD.Net or {}
local Net = RARELOAD.Net

local SYNC, REQ = "rareload.sync", "rareload.req"
local CHUNK = 60000                   -- G10
local MAX_REQUEST = 64 * 1024         -- S2
local MAX_TRANSFER = 16 * 1024 * 1024 -- S11
local MAX_INFLIGHT = 96 * 1024        -- S13
local ACK_TIMEOUT = 30

-- Pure helpers (unit-tested) ---------------------------------------------------------------------

function Net.Split(data, size)
    local chunks = {}
    for i = 1, math.max(#data, 1), size do
        chunks[#chunks + 1] = data:sub(i, i + size - 1)
    end
    return chunks
end

local function finite(n)
    return isnumber(n) and n == n and n ~= math.huge and n ~= -math.huge
end

-- Schema types: "bool", "number", "uint", "string" or "string:<max length>". A trailing "?" makes a
-- field optional. Keys not in the schema are dropped. Returns the clean table, or nil and a reason.
function Net.Validate(schema, args)
    if not istable(args) then return nil, "arguments are not a table" end
    local clean = {}
    for key, spec in pairs(schema) do
        local optional = spec:sub(-1) == "?"
        local kind, limit = (optional and spec:sub(1, -2) or spec):match("^(%a+):?(%d*)$")
        local v = args[key]
        local ok
        if v == nil then
            ok = optional
        elseif kind == "bool" then
            ok = isbool(v)
        elseif kind == "number" then
            ok = finite(v)
        elseif kind == "uint" then
            ok = finite(v) and v >= 0 and v == math.floor(v)
        elseif kind == "string" then
            ok = isstring(v) and (limit == "" or #v <= tonumber(limit))
        end
        if not ok then return nil, "bad field " .. key end
        clean[key] = v
    end
    return clean
end

if SERVER then
    util.AddNetworkString(SYNC)
    util.AddNetworkString(REQ)

    Net._handlers = Net._handlers or {}
    local handlers = Net._handlers
    -- Kept across a Lua reload: clients say they're ready only once, so a reload that forgot it
    -- would stop every push to the players already in game.
    local function weak() return setmetatable({}, { __mode = "k" }) end
    Net._state = Net._state or { ready = weak(), queues = weak(), inflight = weak(), lastCall = weak() }
    local ready = Net._state.ready
    local queues = Net._state.queues     -- ply -> transfers waiting to be sent
    local inflight = Net._state.inflight -- ply -> transferId -> { bytes, t }
    local lastCall = Net._state.lastCall -- ply -> op -> CurTime of last accepted call
    local nextId = Net._state.nextId or 0

    -- `def` = { priv?, rate?, args? (schema), fn(ply, args) }.
    -- The same file registering again is a Lua auto-refresh of that file, not a duplicate.
    function Net.Handle(op, def)
        local prev = handlers[op]
        def.gen, def.src = RARELOAD.loadGen, debug.getinfo(2, "S").short_src
        if prev and prev.gen == def.gen and prev.src ~= def.src then
            error("[Rareload] net opcode registered twice: " .. op, 2) -- L31
        end
        handlers[op] = def
    end

    local function enqueue(ply, topic, key, chunks, urgent)
        if not ready[ply] then return end -- G14: nothing is sent before the client is loaded
        local queue = queues[ply] or {}
        queues[ply] = queue
        -- A newer push of the same key replaces one that hasn't started sending.
        for _, t in ipairs(queue) do
            if t.key == key and t.next == 1 then
                t.topic, t.chunks = topic, chunks
                return
            end
        end
        nextId = nextId % 2147483647 + 1
        Net._state.nextId = nextId
        local t = { id = nextId, topic = topic, key = key, chunks = chunks, next = 1 }
        -- An urgent push (a toast) goes ahead of everything that hasn't started sending.
        local at = #queue + 1
        if urgent then at = (queue[1] and queue[1].next > 1) and 2 or 1 end
        table.insert(queue, math.min(at, #queue + 1), t)
    end

    -- target: a player, a list of players, or nil for every ready player.
    -- opts = { key? (a newer push with the same key replaces a waiting one), urgent? }
    function Net.Push(target, topic, payload, opts)
        local chunks = Net.Split(util.Compress(util.TableToJSON(payload)), CHUNK)
        local key = opts and opts.key or topic
        local urgent = opts and opts.urgent
        if isentity(target) then
            enqueue(target, topic, key, chunks, urgent)
        else
            for _, ply in ipairs(target or select(2, player.Iterator())) do
                enqueue(ply, topic, key, chunks, urgent)
            end
        end
    end

    -- At most CHUNK bytes per client per tick (several small pushes fit in one tick), and never more
    -- than MAX_INFLIGHT unacknowledged bytes (G11). The client acknowledges every chunk.
    hook.Add("Tick", "Rareload.Net.Send", function()
        local now = CurTime()
        for ply, queue in pairs(queues) do
            if not IsValid(ply) or #queue == 0 then
                queues[ply] = nil
            else
                local sent = inflight[ply] or {}
                inflight[ply] = sent
                local pending = 0
                for id, rec in pairs(sent) do
                    if now - rec.t > ACK_TIMEOUT then sent[id] = nil else pending = pending + rec.bytes end
                end
                local budget = CHUNK
                while queue[1] and pending < MAX_INFLIGHT and budget > 0 do
                    local t = queue[1]
                    local chunk = t.chunks[t.next]
                    if #chunk > budget and budget < CHUNK then break end
                    net.Start(SYNC)
                    net.WriteUInt(t.id, 32)
                    net.WriteString(t.topic)
                    net.WriteUInt(t.next, 16)
                    net.WriteUInt(#t.chunks, 16)
                    net.WriteUInt(#chunk, 16)
                    net.WriteData(chunk, #chunk)
                    net.Send(ply)
                    sent[t.id .. ":" .. t.next] = { bytes = #chunk, t = now }
                    pending, budget = pending + #chunk, budget - #chunk
                    t.next = t.next + 1
                    if t.next > #t.chunks then table.remove(queue, 1) end
                end
            end
        end
    end)

    net.Receive(REQ, function(len, ply)
        if len > MAX_REQUEST * 8 then return end
        local op, raw = net.ReadString(), net.ReadString()
        local h = handlers[op]
        if not h then
            RARELOAD.Log("net"):warn("%s sent unknown request %q", ply:Nick(), op)
            return
        end

        local calls = lastCall[ply] or {}
        lastCall[ply] = calls
        local now = CurTime()
        if h.rate and calls[op] and now - calls[op] < h.rate then return end
        calls[op] = now

        if h.priv and not RARELOAD.Can(ply, h.priv) then return end

        local args, err = Net.Validate(h.args or {}, util.JSONToTable(raw) or {}) -- default limits (S12)
        if not args then
            RARELOAD.Log("net"):warn("%s sent a bad %q request: %s", ply:Nick(), op, err)
            return
        end
        ProtectedCall(h.fn, ply, args)
    end)

    Net.Handle("ready", {
        fn = function(ply)
            if ready[ply] then return end
            ready[ply] = true
            hook.Run("RareloadClientReady", ply)
        end,
    })

    Net.Handle("ack", {
        args = { id = "uint", part = "uint" },
        fn = function(ply, a)
            if inflight[ply] then inflight[ply][a.id .. ":" .. a.part] = nil end
        end,
    })

    -- Toasts carry a translation key and arguments; the client localizes them (L29).
    function RARELOAD.Toast(ply, key, args, kind)
        Net.Push(ply, "toast", { key = key, args = args or {}, kind = kind or "info" },
            { key = "toast:" .. key, urgent = true })
    end
end

if CLIENT then
    Net._topics = Net._topics or {}
    local topics = Net._topics
    local partial = {}

    function Net.On(topic, fn)
        topics[topic] = fn
    end

    function Net.Request(op, args)
        local json = util.TableToJSON(args or {})
        if #json + #op > MAX_REQUEST - 16 then
            ErrorNoHalt("[Rareload] request too large: " .. op .. "\n")
            return
        end
        net.Start(REQ)
        net.WriteString(op)
        net.WriteString(json)
        net.SendToServer()
    end

    net.Receive(SYNC, function()
        local id, topic = net.ReadUInt(32), net.ReadString()
        local index, total = net.ReadUInt(16), net.ReadUInt(16)
        local data = net.ReadData(net.ReadUInt(16))

        local now = RealTime()
        for tid, p in pairs(partial) do
            if now - p.t > 10 then partial[tid] = nil end
        end
        Net.Request("ack", { id = id, part = index })
        local p = partial[id] or { parts = {}, got = 0 }
        partial[id] = p
        p.t = now
        if not p.parts[index] then
            p.parts[index] = data
            p.got = p.got + 1
        end
        if p.got < total then return end

        partial[id] = nil
        local json = util.Decompress(table.concat(p.parts), MAX_TRANSFER)
        local payload = json and util.JSONToTable(json, true)
        local fn = topics[topic]
        if payload and fn then ProtectedCall(fn, payload) end
    end)

    hook.Add("InitPostEntity", "Rareload.Net.Ready", function()
        Net.Request("ready")
    end)
end
