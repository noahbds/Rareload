RARELOAD = RARELOAD or {}
RARELOAD.playerPositionHistory = RARELOAD.playerPositionHistory or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.settings.maxHistorySize = RARELOAD.settings.maxHistorySize or 125
RARELOAD.playerActiveHistoryId = RARELOAD.playerActiveHistoryId or {}

-- Which history entry id is currently the active respawn save, per map+player.
-- Persisted in the history file so the "active" marker survives map reloads.
function RARELOAD.GetActiveHistoryId(steamID, mapName)
    mapName = mapName or game.GetMap()
    local m = RARELOAD.playerActiveHistoryId[mapName]
    return m and m[steamID] or nil
end

function RARELOAD.SetActiveHistoryId(steamID, mapName, id)
    mapName = mapName or game.GetMap()
    RARELOAD.playerActiveHistoryId[mapName] = RARELOAD.playerActiveHistoryId[mapName] or {}
    RARELOAD.playerActiveHistoryId[mapName][steamID] = id
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Persistent save-history store (4.0 · Phase 2)
--
-- Every meaningful save appends a timestamped snapshot here, and the store is
-- written to disk (rareload/history/<map>/<steamid>.json) so the whole timeline
-- survives map reloads and server restarts. Reads are NON-destructive: the
-- upcoming Save Timeline panel browses and restores any entry without consuming
-- it. The tool-gun reload key is untouched — it still restores the active save.
--
-- On disk, heavy entity/NPC duplicator snapshots are stored once in a `blobs`
-- table keyed by a content hash and referenced from each entry, so repeated
-- saves of the same map objects don't bloat the file. JSON is written compact.
-- ─────────────────────────────────────────────────────────────────────────────

local HISTORY_VERSION = 1
local HISTORY_ROOT    = "rareload/history"
local HEAVY_KEYS      = { "entities", "npcs" }
local DEFAULT_MAX     = 125

-- Next sequence number per "<map>/<steamid>", so entry ids stay unique across
-- sessions. Seeded from each file's stored nextSeq on load.
local seqByFile = {}

-- ── small helpers ─────────────────────────────────────────────────────────────

local function IsDebugEnabledForSteamID(steamID)
    if steamID and player and player.GetAll and RARELOAD.GetPlayerSetting then
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:SteamID() == steamID then
                return RARELOAD.GetPlayerSetting(ply, "debugEnabled", false)
            end
        end
    end
    if DEBUG_CONFIG and DEBUG_CONFIG.ENABLED then
        return DEBUG_CONFIG.ENABLED()
    end
    return RARELOAD.settings and RARELOAD.settings.debugEnabled or false
end

local function FindPlayer(steamID)
    if player and player.GetBySteamID then
        local ply = player.GetBySteamID(steamID)
        if IsValid(ply) then return ply end
    end
    return nil
end

local function ResolveMaxSize(steamID)
    local v
    local ply = FindPlayer(steamID)
    if ply and RARELOAD.GetPlayerSetting then
        v = RARELOAD.GetPlayerSetting(ply, "maxHistorySize", nil)
    end
    v = tonumber(v) or tonumber(RARELOAD.settings.maxHistorySize) or DEFAULT_MAX
    return math.max(1, math.floor(v))
end

local function ResolveSteamID64(steamID)
    local ply = FindPlayer(steamID)
    if ply then return ply:SteamID64() end
    return (util.SteamIDTo64 and util.SteamIDTo64(steamID)) or ""
end

local function SafeKey(steamID)
    if RARELOAD.DataUtils and RARELOAD.DataUtils.SanitizeSteamID then
        return RARELOAD.DataUtils.SanitizeSteamID(steamID)
    end
    return string.gsub(steamID or "unknown", "[^%w_%-.]", "_")
end

local function EnsureDirs(mapName)
    if not file.Exists("rareload", "DATA") then file.CreateDir("rareload") end
    if not file.Exists(HISTORY_ROOT, "DATA") then file.CreateDir(HISTORY_ROOT) end
    local mapDir = HISTORY_ROOT .. "/" .. mapName
    if not file.Exists(mapDir, "DATA") then file.CreateDir(mapDir) end
    return mapDir
end

local function FilePath(mapName, steamID)
    return HISTORY_ROOT .. "/" .. mapName .. "/" .. SafeKey(steamID) .. ".json"
end

-- ── dedup: heavy buckets <-> content-hashed blobs ─────────────────────────────

local function IsHeavy(bucket)
    return istable(bucket) and next(bucket) ~= nil
end

local function BucketHash(bucket)
    local json = util.TableToJSON(bucket) or ""
    local crc  = (util.CRC and util.CRC(json)) or tostring(#json)
    return crc .. "-" .. #json -- length guards against CRC collisions
end

-- ── (de)serialization ─────────────────────────────────────────────────────────

local META_KEYS = { id = true, timestamp = true, pinned = true, note = true }

local function Serialize(mapName, steamID, steamID64, history, nextSeq, activeId)
    local blobs, entries = {}, {}
    for i = 1, #history do
        local e = history[i]
        local data = {}
        for k, v in pairs(e) do
            if not META_KEYS[k] then data[k] = v end
        end
        for _, hk in ipairs(HEAVY_KEYS) do
            if IsHeavy(data[hk]) then
                local h = BucketHash(data[hk])
                if blobs[h] == nil then blobs[h] = data[hk] end
                data[hk] = { __ref = h }
            end
        end
        entries[i] = {
            id        = e.id,
            timestamp = e.timestamp,
            pinned    = e.pinned and true or nil,
            note      = (e.note and e.note ~= "" and e.note) or nil,
            data      = data,
        }
    end
    return {
        version   = HISTORY_VERSION,
        map       = mapName,
        steamID   = steamID,
        steamID64 = steamID64 or "",
        nextSeq   = nextSeq or (#history + 1),
        activeId  = activeId,
        entries   = entries,
        blobs     = blobs,
    }
end

local function Deserialize(payload)
    if not istable(payload) or not istable(payload.entries) then return nil, nil end
    local blobs = payload.blobs or {}
    local out = {}
    for i = 1, #payload.entries do
        local pe = payload.entries[i]
        if istable(pe) and istable(pe.data) then
            local data = pe.data
            for _, hk in ipairs(HEAVY_KEYS) do
                local ref = data[hk]
                if istable(ref) and ref.__ref then
                    data[hk] = blobs[ref.__ref] or nil -- shared reference; treated as read-only
                end
            end
            data.id        = pe.id
            data.timestamp = pe.timestamp
            data.pinned    = pe.pinned and true or false
            data.note      = pe.note or ""
            out[#out + 1]  = data
        end
    end
    return out, payload.nextSeq
end

-- ── disk I/O ──────────────────────────────────────────────────────────────────

local function Persist(mapName, steamID)
    local byMap = RARELOAD.playerPositionHistory[mapName]
    local history = byMap and byMap[steamID]
    if not history then return end

    EnsureDirs(mapName)
    local seqKey  = mapName .. "/" .. steamID
    local nextSeq = seqByFile[seqKey] or (#history + 1)
    local payload = Serialize(mapName, steamID, ResolveSteamID64(steamID), history, nextSeq,
        RARELOAD.GetActiveHistoryId(steamID, mapName))

    local ok, jsonOrErr = pcall(util.TableToJSON, payload, false)
    if not ok then
        ErrorNoHalt("[RARELOAD] History encode failed for " .. tostring(steamID) .. ": " .. tostring(jsonOrErr) .. "\n")
        return
    end
    local okW, err = pcall(file.Write, FilePath(mapName, steamID), jsonOrErr)
    if not okW then
        ErrorNoHalt("[RARELOAD] History write failed for " .. tostring(steamID) .. ": " .. tostring(err) .. "\n")
    end
end
RARELOAD.PersistPositionHistory = Persist

function RARELOAD.LoadPositionHistory(mapName)
    mapName = mapName or game.GetMap()
    RARELOAD.playerPositionHistory[mapName] = RARELOAD.playerPositionHistory[mapName] or {}

    local mapDir = HISTORY_ROOT .. "/" .. mapName
    if not file.Exists(mapDir, "DATA") then return end

    local files = file.Find(mapDir .. "/*.json", "DATA") or {}
    local loaded = 0
    for _, fname in ipairs(files) do
        local raw = file.Read(mapDir .. "/" .. fname, "DATA")
        if raw and raw ~= "" then
            local ok, payload = pcall(util.JSONToTable, raw)
            if ok and istable(payload) then
                local entries, nextSeq = Deserialize(payload)
                local sid = payload.steamID
                if istable(entries) and isstring(sid) and sid ~= "" then
                    RARELOAD.playerPositionHistory[mapName][sid] = entries
                    seqByFile[mapName .. "/" .. sid] = tonumber(nextSeq) or (#entries + 1)
                    if payload.activeId then RARELOAD.SetActiveHistoryId(sid, mapName, payload.activeId) end
                    loaded = loaded + 1
                end
            end
        end
    end

    if loaded > 0 and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD DEBUG] Loaded position history for %d player(s) on %s", loaded, mapName))
    end
end

-- ── retention ─────────────────────────────────────────────────────────────────

-- Keep at most `maxSize` UNPINNED entries (newest kept). Pinned entries are never
-- pruned and don't count toward the cap, so deliberate keeps can't be evicted.
local function Prune(history, maxSize)
    local unpinned = 0
    for i = 1, #history do
        if not history[i].pinned then unpinned = unpinned + 1 end
    end
    local removable = unpinned - maxSize
    if removable <= 0 then return end
    for i = #history, 1, -1 do
        if removable <= 0 then break end
        if not history[i].pinned then
            table.remove(history, i)
            removable = removable - 1
        end
    end
end

-- Copy a snapshot for archival: small fields become independent copies, but the
-- heavy entity/NPC buckets are shared by reference. They are immutable once saved
-- (the next save replaces the bucket wholesale rather than mutating it in place),
-- so this keeps memory flat across many autosaves instead of duplicating the map
-- snapshot for every entry. On disk they are deduped by content hash anyway.
local function ArchiveCopy(src)
    local out = {}
    for k, v in pairs(src) do
        if k == "entities" or k == "npcs" then
            out[k] = v
        elseif istable(v) then
            out[k] = table.Copy(v)
        else
            out[k] = v
        end
    end
    return out
end

-- ── public API ────────────────────────────────────────────────────────────────

function RARELOAD.CacheCurrentPositionData(steamID, mapName)
    if not steamID or not mapName then return end

    local byMapPos = RARELOAD.playerPositions and RARELOAD.playerPositions[mapName]
    local current  = byMapPos and byMapPos[steamID]
    if not current then return end

    RARELOAD.playerPositionHistory[mapName] = RARELOAD.playerPositionHistory[mapName] or {}
    RARELOAD.playerPositionHistory[mapName][steamID] = RARELOAD.playerPositionHistory[mapName][steamID] or {}
    local history = RARELOAD.playerPositionHistory[mapName][steamID]

    local seqKey = mapName .. "/" .. steamID
    local seq = seqByFile[seqKey] or (#history + 1)
    seqByFile[seqKey] = seq + 1

    local entry = ArchiveCopy(current)
    entry.timestamp = os.time()
    entry.id        = os.time() .. "-" .. seq
    entry.pinned    = false
    entry.note      = ""

    table.insert(history, 1, entry)
    -- A fresh save becomes the active respawn, matching normal Rareload behaviour.
    RARELOAD.SetActiveHistoryId(steamID, mapName, entry.id)

    local maxSize = ResolveMaxSize(steamID)
    Prune(history, maxSize)

    Persist(mapName, steamID)

    if IsDebugEnabledForSteamID(steamID) then
        print(string.format("[RARELOAD DEBUG] Archived save for %s (%d entries, cap %d)", steamID, #history, maxSize))
    end
end

-- Non-destructive: the newest-first array of snapshots for a player on a map.
function RARELOAD.GetPositionHistoryEntries(steamID, mapName)
    mapName = mapName or game.GetMap()
    local byMap = RARELOAD.playerPositionHistory[mapName]
    return (byMap and byMap[steamID]) or {}
end

function RARELOAD.GetHistoryEntryById(steamID, mapName, id)
    for _, e in ipairs(RARELOAD.GetPositionHistoryEntries(steamID, mapName)) do
        if e.id == id then return e end
    end
    return nil
end

function RARELOAD.GetPositionHistory(steamID, mapName)
    return #RARELOAD.GetPositionHistoryEntries(steamID, mapName)
end

-- Destructive "pop newest", kept for backwards compatibility. It is NOT used by
-- the reload key (that restores the active save) — prefer the getters above.
function RARELOAD.GetPreviousPositionData(steamID, mapName)
    if not steamID or not mapName then return nil end
    local byMap = RARELOAD.playerPositionHistory[mapName]
    local history = byMap and byMap[steamID]
    if history and #history > 0 then
        local last = history[1]
        table.remove(history, 1)
        Persist(mapName, steamID)
        return last
    end
    return nil
end

function RARELOAD.SetHistoryEntryPinned(steamID, mapName, id, pinned)
    local e = RARELOAD.GetHistoryEntryById(steamID, mapName, id)
    if not e then return false end
    e.pinned = pinned and true or false
    Persist(mapName or game.GetMap(), steamID)
    return true
end

function RARELOAD.SetHistoryEntryNote(steamID, mapName, id, note)
    local e = RARELOAD.GetHistoryEntryById(steamID, mapName, id)
    if not e then return false end
    e.note = tostring(note or "")
    Persist(mapName or game.GetMap(), steamID)
    return true
end

function RARELOAD.DeleteHistoryEntry(steamID, mapName, id)
    mapName = mapName or game.GetMap()
    local byMap = RARELOAD.playerPositionHistory[mapName]
    local history = byMap and byMap[steamID]
    if not history then return false end
    for i = 1, #history do
        if history[i].id == id then
            table.remove(history, i)
            Persist(mapName, steamID)
            return true
        end
    end
    return false
end

function RARELOAD.ClearPositionHistory(steamID, mapName)
    if not steamID then return end

    local function clearMap(map)
        if RARELOAD.playerPositionHistory[map] then
            RARELOAD.playerPositionHistory[map][steamID] = nil
        end
        seqByFile[map .. "/" .. steamID] = nil
        local path = FilePath(map, steamID)
        if file.Exists(path, "DATA") then file.Delete(path) end
    end

    if mapName then
        clearMap(mapName)
    else
        for map in pairs(RARELOAD.playerPositionHistory) do clearMap(map) end
    end

    if IsDebugEnabledForSteamID(steamID) then
        print(string.format("[RARELOAD DEBUG] Cleared position history for %s on %s", steamID, mapName or "all maps"))
    end
end

function RARELOAD.SetMaxHistorySize(size)
    if type(size) == "number" and size > 0 then
        RARELOAD.settings.maxHistorySize = math.floor(size)
        return true
    end
    print("[RARELOAD ERROR] Invalid max history size. Must be a positive number.")
    return false
end

-- ── lifecycle ──────────────────────────────────────────────────────────────────

hook.Add("InitPostEntity", "RARELOAD_LoadPositionHistory", function()
    RARELOAD.LoadPositionHistory(game.GetMap())
end)

-- ── test / inspection commands (Phase 3 replaces these with the panel) ─────────

concommand.Add("rareload_history_dump", function(ply, _, args)
    local steamID = (IsValid(ply) and ply:SteamID()) or args[1]
    local function out(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end
    if not steamID then
        out("[RARELOAD] usage from server console: rareload_history_dump <steamid>")
        return
    end

    local mapName = game.GetMap()
    local entries = RARELOAD.GetPositionHistoryEntries(steamID, mapName)
    out(string.format("[RARELOAD] History for %s on %s: %d entr%s", steamID, mapName, #entries, #entries == 1 and "y" or "ies"))
    for i, e in ipairs(entries) do
        local p = e.pos or {}
        out(string.format("  [%2d] id=%-14s %s %s%spos=%.0f, %.0f, %.0f",
            i, tostring(e.id),
            os.date("%Y-%m-%d %H:%M:%S", tonumber(e.timestamp) or 0),
            e.pinned and "[pinned] " or "",
            (e.note and e.note ~= "") and ("note='" .. e.note .. "' ") or "",
            tonumber(p.x) or 0, tonumber(p.y) or 0, tonumber(p.z) or 0))
    end
end)

concommand.Add("rareload_history_clear", function(ply, _, args)
    local steamID = (IsValid(ply) and ply:SteamID()) or args[1]
    local function out(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end
    if not steamID then
        out("[RARELOAD] usage from server console: rareload_history_clear <steamid>")
        return
    end
    RARELOAD.ClearPositionHistory(steamID, game.GetMap())
    out("[RARELOAD] Cleared position history for " .. steamID .. " on " .. game.GetMap())
end)
