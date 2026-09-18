-- Rareload debug networking: streams structured events and session reports to
-- the players who have their own debug enabled (never to everyone).
if not SERVER then return end

RARELOAD = RARELOAD or {}
local Debug = RARELOAD.Debug
if not Debug then return end

util.AddNetworkString("RareloadDebugEvent")
util.AddNetworkString("RareloadDebugReport")
util.AddNetworkString("RareloadDebugSync") -- client requests a backlog on demand

-- Serialize an event compactly. data is already a list of {key,val} strings.
local function writeEvent(ev)
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

-- Broadcast one event to all current subscribers.
function Debug.Broadcast(ev)
    local subs = Debug.Subscribers()
    if #subs == 0 then return end
    net.Start("RareloadDebugEvent")
    writeEvent(ev)
    net.Send(subs)
end

-- Send one event to a single player (used by Debug.ToPlayer).
function Debug.SendTo(ply, ev)
    if not IsValid(ply) then return end
    net.Start("RareloadDebugEvent")
    writeEvent(ev)
    net.Send(ply)
end

-- Send a finished session as a structured "report" card.
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

-- A client can ask for the current backlog when it opens the HUD.
net.Receive("RareloadDebugSync", function(_, ply)
    if not Debug.EnabledFor(ply) then return end
    local recent = Debug.Recent(60)
    for _, ev in ipairs(recent) do
        net.Start("RareloadDebugEvent")
        writeEvent(ev)
        net.Send(ply)
    end
end)
