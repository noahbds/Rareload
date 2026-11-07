-- Server snapshots, rollback and crash recovery (5.4 plan, D9).
-- Every `snapshotInterval` minutes the objects of every player in game are captured silently (one
-- player per tick) into <map folder>/_server, the last `snapshotKeep` of them. The objects are stored
-- as blobs, shared with saves, so a build that didn't change costs nothing. An admin can roll a player
-- (or everyone) back to a snapshot: an exact restore of their objects, which they can undo. After a
-- crash, players get their objects from the last snapshot when it is newer than their own save.

RARELOAD.Snapshots = RARELOAD.Snapshots or {}
local Snapshots = RARELOAD.Snapshots
-- sv_storage.lua loads after this file, so Store is looked up when used.
local Pipeline = RARELOAD.Pipeline

local PRIV = "rareload_rollback"
local WORLD = { entities = true, npcs = true, vehicles = true, constraints = true }

local function rel() return RARELOAD.Store.MapDir() .. "/_server" end

local function doc()
    local d = RARELOAD.Store.Load(rel())
    if not istable(d) or not istable(d.snapshots) then d = { v = RARELOAD.Store.SCHEMA, nextId = 1, snapshots = {} } end
    -- Snapshots from before the players became a list (keyed by SteamID64, unreadable) are dropped.
    for i = #d.snapshots, 1, -1 do
        local players = d.snapshots[i].players
        if not istable(players) or (players[1] == nil and next(players) ~= nil) then table.remove(d.snapshots, i) end
    end
    return d
end

function Snapshots.List()
    return doc().snapshots
end

-- One player's objects, as a save entry's data (heavy modules as blobs).
local function capture(ply)
    local ok, _, entry = Pipeline.Save(ply, { only = WORLD, captureOnly = true, silent = true })
    if not ok or not entry then return nil end
    local data = {}
    for id, value in pairs(entry.data) do
        local def = Pipeline.Def(id)
        data[id] = def and def.heavy and { ["$blob"] = RARELOAD.Store.BlobPut(value) } or value
    end
    return next(data) and data or nil
end

local taking = false

-- The players of a snapshot are a list of { sid, nick, data }: a table keyed by SteamID64 would not
-- survive the JSON round trip (util.JSONToTable turns number-like keys into numbers, which then lose
-- digits).
local function partOf(snap, sid)
    for _, part in ipairs(snap.players) do
        if part.sid == sid then return part end
    end
end

-- Takes a snapshot, one player per tick. done(snapshot) when finished; false when one is running.
function Snapshots.Take(done)
    if taking then return false end
    taking = true
    local players = {}
    for _, p in player.Iterator() do
        if not p:IsBot() and RARELOAD.Util.PlayerKey(p) then players[#players + 1] = p end
    end
    local snap = { time = os.time(), players = {} }
    local i = 0
    local function step()
        i = i + 1
        local p = players[i]
        if p then
            if IsValid(p) then
                local data = capture(p)
                if data then snap.players[#snap.players + 1] = { sid = p:SteamID64(), nick = p:Nick(), data = data } end
            end
            Pipeline.Defer(step)
            return
        end
        local d = doc()
        snap.id = d.nextId
        d.nextId = d.nextId + 1
        d.snapshots[#d.snapshots + 1] = snap
        while #d.snapshots > RARELOAD.Get(nil, "snapshotKeep") do table.remove(d.snapshots, 1) end
        RARELOAD.Store.Save(rel(), d)
        taking = false
        RARELOAD.Log("snapshots", nil):verbose("snapshot No. %d: %d players", snap.id, #snap.players)
        if done then done(snap) end
    end
    Pipeline.Defer(step)
    return true
end

-- The snapshot with this id, or the newest one at least `minutes` old.
function Snapshots.Find(what)
    local list = Snapshots.List()
    local id = tostring(what or ""):match("^#(%d+)$")
    if id then
        for _, s in ipairs(list) do if s.id == tonumber(id) then return s end end
        return nil
    end
    local minutes = tonumber(what)
    if not minutes then return nil end
    local cutoff = os.time() - minutes * 60
    for i = #list, 1, -1 do
        if list[i].time <= cutoff then return list[i] end
    end
end

-- Rolls players back to a snapshot: an exact restore of their objects (undoable from their timeline).
-- only: a SteamID64, or nil for everyone in it. Returns how many were rolled back and the names of
-- those who could not be (offline or dead).
function Snapshots.Rollback(snap, only)
    local done, skipped = 0, {}
    for _, part in ipairs(snap.players) do
        local sid = part.sid
        if not only or only == sid then
            local ply = player.GetBySteamID64(sid)
            local ok = IsValid(ply) and RARELOAD.History.RestoreEntry(ply, { data = part.data }, { world = true },
                { exact = true, admin = true, reason = "rollback" })
            if ok then
                done = done + 1
                RARELOAD.Toast(ply, "toast.rolled_back", { os.date("%H:%M", snap.time) })
            else
                skipped[#skipped + 1] = part.nick or sid
            end
        end
    end
    return done, skipped
end

-- Snapshots every snapshotInterval minutes.
local nextAt = 0
hook.Add("Tick", "Rareload.Snapshots", function()
    local minutes = RARELOAD.Get(nil, "snapshotInterval")
    if minutes <= 0 then return end
    local now = CurTime()
    if nextAt == 0 then nextAt = now + minutes * 60 end
    if now < nextAt then return end
    nextAt = now + minutes * 60
    if player.GetCount() > 0 then Snapshots.Take() end
end)

-- Crash recovery -----------------------------------------------------------------------------------------
-- A flag file says the server is running; it is cleared on a clean shutdown (and on a map change). Found
-- at start, the last shutdown was a crash.

hook.Add("InitPostEntity", "Rareload.Snapshots", function()
    if Snapshots.crashed ~= nil then return end
    Snapshots.crashed = RARELOAD.Store.Flag("running")
    RARELOAD.Store.SetFlag("running", true)
    if Snapshots.crashed then RARELOAD.Log("snapshots", nil):warn("the server did not shut down cleanly last time") end
end)
hook.Add("ShutDown", "Rareload.Snapshots", function() RARELOAD.Store.SetFlag("running", false) end)

-- The player's part of the newest snapshot, when it is newer than their own respawn point.
function Snapshots.Recoverable(ply)
    local list = Snapshots.List()
    local snap = list[#list]
    local part = snap and partOf(snap, ply:SteamID64())
    if not part then return nil end
    local active = RARELOAD.History.Active(ply)
    if active and (tonumber(active.time) or 0) >= snap.time then return nil end
    return snap, part
end

-- Players to offer crash recovery to after their first spawn, and players already recovered.
local crashCheck, recovered = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })

function Snapshots.Recover(ply)
    local snap, part = Snapshots.Recoverable(ply)
    if not snap or recovered[ply] then
        RARELOAD.Toast(ply, "toast.recover_none", nil, "error")
        return false
    end
    recovered[ply] = true
    local ok = RARELOAD.History.RestoreEntry(ply, { data = part.data }, { world = true },
        { exact = true, admin = true, reason = "recover" })
    if ok then RARELOAD.Toast(ply, "toast.recovered", { os.date("%H:%M", snap.time) }, "ok") end
    return ok
end

hook.Add("PlayerInitialSpawn", "Rareload.Snapshots", function(ply)
    recovered[ply] = nil
    crashCheck[ply] = Snapshots.crashed or nil
end)

-- After the player's first spawn restore: offer (or restore) their objects from before the crash.
local function afterFirstSpawn(ply)
    if not crashCheck[ply] then return end
    crashCheck[ply] = nil
    if RARELOAD.Can(ply, PRIV) then RARELOAD.Toast(ply, "toast.crash_detected", nil, "error") end
    local snap = Snapshots.Recoverable(ply)
    if not snap then return end
    local mode = RARELOAD.Get(nil, "crashRecovery")
    if mode == "auto" then
        Snapshots.Recover(ply)
    elseif mode == "ask" then
        RARELOAD.Toast(ply, "toast.crash_offer", { os.date("%H:%M", snap.time) })
    end
end

hook.Add("RareloadRestored", "Rareload.Snapshots", function(ply) afterFirstSpawn(ply) end)
hook.Add("PlayerSpawn", "Rareload.Snapshots", function(ply)
    -- No save on this map: nothing is restored, so the check happens a tick later.
    if crashCheck[ply] and not RARELOAD.History.Active(ply) then
        Pipeline.Defer(function() if IsValid(ply) then afterFirstSpawn(ply) end end)
    end
end)

-- Server menu -----------------------------------------------------------------------------------------

local function push(ply)
    local rows = {}
    for _, s in ipairs(Snapshots.List()) do
        local names = {}
        for _, part in ipairs(s.players) do names[#names + 1] = part.nick end
        table.sort(names)
        rows[#rows + 1] = { id = s.id, time = s.time, players = names }
    end
    RARELOAD.Net.Push(ply, "snapshots", { list = rows, crashed = Snapshots.crashed == true })
end

RARELOAD.Net.Handle("snapshot.list", { priv = PRIV, rate = 0.5, fn = push })
RARELOAD.Net.Handle("snapshot.take", {
    priv = PRIV,
    rate = 2,
    fn = function(ply)
        if not Snapshots.Take(function(snap)
            RARELOAD.Toast(ply, "toast.snapshot_taken", { snap.id, #snap.players }, "ok")
            push(ply)
        end) then
            RARELOAD.Toast(ply, "toast.snapshot_busy", nil, "error")
        end
    end,
})
RARELOAD.Net.Handle("snapshot.rollback", {
    priv = PRIV,
    rate = 2,
    args = { id = "uint" },
    fn = function(ply, a)
        local snap = Snapshots.Find("#" .. a.id)
        if not snap then return end
        local n, skipped = Snapshots.Rollback(snap)
        RARELOAD.Log("admin", ply):info("%s rolled back to snapshot No. %d: %d players%s", ply:Nick(), a.id, n,
            #skipped > 0 and (", not: " .. table.concat(skipped, ", ")) or "")
        RARELOAD.Toast(ply, "toast.rollback_done", { n, #skipped }, "ok")
    end,
})
