-- Storage: the only file touching file.*. JSON documents under data/rareload/, written atomically
-- with a .bak copy, batched to at most one write every 0.5 s.
-- File names end in .json and are lowercase, because file.Write only accepts those.

RARELOAD.Store = RARELOAD.Store or {}
local Store = RARELOAD.Store

Store.SCHEMA = 5
local ROOT = "rareload/"

Store._cache = Store._cache or {} -- rel -> document, or false when there is none
Store._dirty = Store._dirty or {} -- rel -> document waiting to be written
local cache, dirty = Store._cache, Store._dirty
local readonly = {}

local function log() return RARELOAD.Log("storage") end

function Store.Clean(s)
    return (string.gsub(string.lower(tostring(s)), "[^a-z0-9_%-]", "_"))
end

-- Singleplayer and multiplayer saves never mix (D1, L16).
function Store.MapDir()
    return (game.SinglePlayer() and "sp/" or "mp/") .. Store.Clean(game.GetMap())
end

local function decode(raw)
    if not raw or raw == "" then return nil end
    local t = util.JSONToTable(raw, true) -- ignoreLimits: big saves must load (G1)
    return istable(t) and t or nil
end

local encoded = {} -- rel -> JSON of a dirty document that was already encoded (blobs)

local function writeNow(rel, doc)
    local base = ROOT .. rel
    local json = encoded[rel] or util.TableToJSON(doc)
    encoded[rel] = nil
    if not json then
        log():error("could not encode %s", rel)
        return false
    end
    local main, tmp, bak = base .. ".json", base .. ".tmp.json", base .. ".bak.json"
    file.CreateDir(string.GetPathFromFilename(base))
    if file.Write(tmp, json) == false then -- returns nil on older game builds, false on failure (G5)
        log():error("could not write %s", tmp)
        return false
    end
    if file.Exists(main, "DATA") then
        file.Delete(bak)
        file.Rename(main, bak)
    end
    if not file.Rename(tmp, main) then
        file.Write(main, json)
        file.Delete(tmp)
        log():warn("atomic rename failed for %s, wrote it directly", main)
    end
    return true
end

-- Returns the document stored at `rel` (e.g. "mp/gm_construct/7656…"), or nil.
-- A corrupt file is moved aside and the .bak copy is used instead (E8).
-- `fresh`: read the file again, for files people edit by hand (exported inventories).
function Store.Load(rel, fresh)
    if fresh and not dirty[rel] then cache[rel] = nil end
    if cache[rel] ~= nil then return cache[rel] or nil end

    local base = ROOT .. rel
    local doc = decode(file.Read(base .. ".json", "DATA"))
    if not doc and file.Exists(base .. ".json", "DATA") then
        local moved = base .. ".corrupt-" .. os.time() .. ".json"
        file.Rename(base .. ".json", moved)
        log():warn("%s.json was unreadable and was moved to %s", base, moved)
    end
    if not doc then
        doc = decode(file.Read(base .. ".bak.json", "DATA"))
        if doc then log():warn("loaded %s from its backup copy", rel) end
    end
    if doc and (tonumber(doc.v) or 0) > Store.SCHEMA then
        readonly[rel] = true
        log():warn("%s was written by a newer Rareload (v%s); it will not be modified", rel, tostring(doc.v))
    end

    cache[rel] = doc or false
    return doc
end

function Store.Flush()
    for rel, doc in pairs(dirty) do
        dirty[rel] = nil
        writeNow(rel, doc)
    end
end

function Store.Save(rel, doc)
    if readonly[rel] then return false end
    cache[rel] = doc
    dirty[rel], encoded[rel] = doc, nil
    if not timer.Exists("Rareload.Store.Flush") then
        timer.Create("Rareload.Store.Flush", 0.5, 1, Store.Flush)
    end
    return true
end

function Store.Delete(rel)
    local base = ROOT .. rel
    for _, suffix in ipairs({ ".json", ".tmp.json", ".bak.json" }) do
        file.Delete(base .. suffix)
    end
    cache[rel], dirty[rel], encoded[rel], readonly[rel] = nil, nil, nil, nil
end

-- Blobs: heavy module data (world snapshots) stored once by content hash, so identical snapshots
-- across many saves share one file (§16.3). Blobs are never modified; an edit makes a new blob.

local function blobRel(hash)
    return Store.MapDir() .. "/_blobs/" .. hash
end

function Store.BlobPut(data)
    local json = util.TableToJSON(data)
    local hash = util.SHA256(json):sub(1, 16)
    local rel = blobRel(hash)
    -- `false` in the cache means "looked for, not there" (a blob removed by GC): it is written again.
    if not cache[rel] and not file.Exists(ROOT .. rel .. ".json", "DATA") then
        Store.Save(rel, data)
        encoded[rel] = json -- written as is, not encoded a second time
    end
    return hash
end

function Store.BlobGet(hash)
    return Store.Load(blobRel(hash))
end

-- Deletes blobs that no save of this map references any more. Runs at startup and on demand.
-- Small flag files: data/rareload/_<name>.txt (the "server is running" flag for crash recovery, D9).
function Store.Flag(name)
    return file.Exists(ROOT .. "_" .. Store.Clean(name) .. ".txt", "DATA")
end

function Store.SetFlag(name, on)
    local path = ROOT .. "_" .. Store.Clean(name) .. ".txt"
    if on then file.Write(path, tostring(os.time())) else file.Delete(path) end
end

-- The blobs a map's server snapshots use (D9).
local function snapshotBlobs(dir, used)
    local doc = cache[dir .. "/_server"] or decode(file.Read(ROOT .. dir .. "/_server.json", "DATA"))
    for _, snap in ipairs(doc and doc.snapshots or {}) do
        for _, part in pairs(snap.players or {}) do
            for _, value in pairs(part.data or {}) do
                if istable(value) and value["$blob"] then used[value["$blob"]] = true end
            end
        end
    end
    return used
end

-- dir: a map's folder ("mp/gm_construct"); the current map's by default.
function Store.GC(dir)
    Store.Flush()
    dir = dir or Store.MapDir()
    local used = snapshotBlobs(dir, {})
    for _, name in ipairs(file.Find(ROOT .. dir .. "/*.json", "DATA") or {}) do
        local id = name:match("^(%d+)%.json$") -- saves docs are named <SteamID64>.json
        local doc = id and (cache[dir .. "/" .. id] or decode(file.Read(ROOT .. dir .. "/" .. name, "DATA")))
        for _, entry in ipairs(doc and doc.entries or {}) do
            -- placeOnly: objects of a save imported from another map, kept to be placed (D6).
            for _, part in ipairs({ entry.data or {}, entry.placeOnly or {} }) do
                for _, value in pairs(part) do
                    if istable(value) and value["$blob"] then used[value["$blob"]] = true end
                end
            end
        end
    end

    local removed = 0
    for _, name in ipairs(file.Find(ROOT .. dir .. "/_blobs/*.json", "DATA") or {}) do
        local hash = name:match("^(%x+)%.json$")
        if hash and not used[hash] then
            Store.Delete(dir .. "/_blobs/" .. hash)
            removed = removed + 1
        end
    end
    return removed
end

-- Every map folder that has saves: "sp/<map>" and "mp/<map>" (A3).
function Store.MapDirs()
    local out = {}
    for _, mode in ipairs({ "sp", "mp" }) do
        local _, dirs = file.Find(ROOT .. mode .. "/*", "DATA")
        for _, d in ipairs(dirs or {}) do out[#out + 1] = mode .. "/" .. d end
    end
    table.sort(out)
    return out
end

-- Removes unused blobs in every map folder. Returns how many.
function Store.GCAll()
    local removed = 0
    for _, dir in ipairs(Store.MapDirs()) do removed = removed + Store.GC(dir) end
    return removed
end

local function blobRefs(entry, out)
    for _, part in ipairs({ entry.data or {}, entry.placeOnly or {} }) do
        for _, value in pairs(part) do
            if istable(value) and value["$blob"] then out[#out + 1] = value["$blob"] end
        end
    end
    return out
end

-- What the saves take on disk (A3): bytes by map, by player (their saves documents plus the blobs
-- their saves use, a blob shared by two players counted for both), unused blobs, and the biggest
-- saves. Sizes are of the files on disk.
function Store.Overview()
    Store.Flush()
    local maps, players, biggest = {}, {}, {}
    local unusedCount, unusedBytes = 0, 0
    for _, dir in ipairs(Store.MapDirs()) do
        local mapBytes, blobSize, used = 0, {}, {}
        for _, name in ipairs(file.Find(ROOT .. dir .. "/_blobs/*.json", "DATA") or {}) do
            local hash = name:match("^(%x+)%.json$")
            local size = file.Size(ROOT .. dir .. "/_blobs/" .. name, "DATA") or 0
            if hash then blobSize[hash] = size end
            mapBytes = mapBytes + size
        end
        for _, name in ipairs(file.Find(ROOT .. dir .. "/*.json", "DATA") or {}) do
            local size = file.Size(ROOT .. dir .. "/" .. name, "DATA") or 0
            mapBytes = mapBytes + size
            local sid = name:match("^(%d+)%.json$")
            local doc = sid and decode(file.Read(ROOT .. dir .. "/" .. name, "DATA"))
            if doc then
                local p = players[sid] or { sid = sid, nick = doc.nick, bytes = 0, saves = 0 }
                players[sid] = p
                p.nick = p.nick or doc.nick
                p.bytes = p.bytes + size
                local mine = {}
                for _, entry in ipairs(doc.entries or {}) do
                    p.saves = p.saves + 1
                    local bytes = 0
                    for _, hash in ipairs(blobRefs(entry, {})) do
                        used[hash] = true
                        bytes = bytes + (blobSize[hash] or 0)
                        mine[hash] = true
                    end
                    biggest[#biggest + 1] = { map = dir, sid = sid, nick = doc.nick, id = entry.id, bytes = bytes }
                end
                for hash in pairs(mine) do p.bytes = p.bytes + (blobSize[hash] or 0) end
            end
        end
        snapshotBlobs(dir, used)
        for hash, size in pairs(blobSize) do
            if not used[hash] then
                unusedCount, unusedBytes = unusedCount + 1, unusedBytes + size
            end
        end
        maps[#maps + 1] = { dir = dir, bytes = mapBytes }
    end
    local list = {}
    for _, p in pairs(players) do list[#list + 1] = p end
    table.sort(maps, function(a, b) return a.bytes > b.bytes end)
    table.sort(list, function(a, b) return a.bytes > b.bytes end)
    table.sort(biggest, function(a, b) return a.bytes > b.bytes end)
    for i = #biggest, 6, -1 do biggest[i] = nil end
    return { maps = maps, players = list, unusedCount = unusedCount, unusedBytes = unusedBytes, biggest = biggest }
end

-- Deletes saves older than `days` on every map, except pinned saves and respawn points, then the blobs
-- no save uses any more. Returns how many saves were deleted.
function Store.Prune(days)
    local cutoff, removed = os.time() - days * 86400, 0
    for _, dir in ipairs(Store.MapDirs()) do
        for _, name in ipairs(file.Find(ROOT .. dir .. "/*.json", "DATA") or {}) do
            local sid = name:match("^(%d+)%.json$")
            local rel = sid and dir .. "/" .. sid
            local doc = rel and Store.Load(rel)
            if doc and istable(doc.entries) then
                local before = #doc.entries
                for i = #doc.entries, 1, -1 do
                    local e = doc.entries[i]
                    if (tonumber(e.time) or 0) < cutoff and not e.pinned and e.id ~= doc.activeId then
                        table.remove(doc.entries, i)
                    end
                end
                if #doc.entries ~= before then
                    removed = removed + before - #doc.entries
                    Store.Save(rel, doc)
                end
            end
        end
    end
    Store.Flush()
    Store.GCAll()
    return removed
end

local function size(bytes)
    if bytes >= 1048576 then return string.format("%.1f MB", bytes / 1048576) end
    return string.format("%d KB", math.max(1, math.Round(bytes / 1024)))
end

-- Store.Overview as English lines, for the console and the server menu.
function Store.UsageLines(u)
    local lines, total = {}, 0
    for _, m in ipairs(u.maps) do total = total + m.bytes end
    lines[#lines + 1] = "Total: " .. size(total) .. " in " .. #u.maps .. " map folders"
    lines[#lines + 1] = "By map:"
    for i, m in ipairs(u.maps) do
        if i > 8 then break end
        lines[#lines + 1] = "  " .. m.dir .. "  " .. size(m.bytes)
    end
    lines[#lines + 1] = "By player:"
    for i, p in ipairs(u.players) do
        if i > 8 then break end
        lines[#lines + 1] = string.format("  %s (%s)  %s, %d saves", p.nick or "?", p.sid, size(p.bytes), p.saves)
    end
    lines[#lines + 1] = "Unused data: " .. u.unusedCount .. " blobs, " .. size(u.unusedBytes)
        .. " ('rareload data cleanup all' removes it)"
    lines[#lines + 1] = "Biggest saves:"
    for _, b in ipairs(u.biggest) do
        lines[#lines + 1] = string.format("  %s, %s No. %d  %s", b.map, b.nick or b.sid, b.id, size(b.bytes))
    end
    return lines
end

RARELOAD.Net.Handle("data.usage", {
    priv = "rareload_data_cleanup",
    rate = 2,
    fn = function(ply)
        RARELOAD.Net.Push(ply, "data.usage", { lines = Store.UsageLines(Store.Overview()) })
    end,
})

hook.Add("InitPostEntity", "Rareload.Store.GC", function()
    local removed = Store.GC()
    if removed > 0 then log():info("removed %d unused blobs", removed) end
end)

-- Log files (sv_log.lua): data/rareload/logs/<YYYY-MM-DD>.txt, one line per event.
local LOGS = ROOT .. "logs/"
local logDirMade = false

function Store.AppendLog(day, line)
    if not logDirMade then
        file.CreateDir(LOGS)
        logDirMade = true
    end
    file.Append(LOGS .. Store.Clean(day) .. ".txt", line .. "\n")
end

-- Deletes log files older than `days`. Returns how many were removed.
function Store.PruneLogs(days)
    local removed, limit = 0, os.time() - days * 86400
    for _, name in ipairs(file.Find(LOGS .. "*.txt", "DATA") or {}) do
        if file.Time(LOGS .. name, "DATA") < limit then
            file.Delete(LOGS .. name)
            removed = removed + 1
        end
    end
    return removed
end

-- How many players have a saves document on this map.
function Store.PlayersWithSaves()
    local n = 0
    for _, name in ipairs(file.Find(ROOT .. Store.MapDir() .. "/*.json", "DATA") or {}) do
        if name:match("^%d+%.json$") then n = n + 1 end -- <SteamID64>.json
    end
    return n
end

-- How many files and bytes a folder under data/rareload holds (not counting sub-folders).
function Store.Usage(rel)
    local files, bytes = 0, 0
    for _, name in ipairs(file.Find(ROOT .. rel .. "/*", "DATA") or {}) do
        local size = file.Size(ROOT .. rel .. "/" .. name, "DATA")
        if size and size >= 0 then
            files, bytes = files + 1, bytes + size
        end
    end
    return files, bytes
end

-- Small per-player records (reload-key mode, global inventory) live in sv.db (D17, G49).
function Store.PData(ply, name, value)
    local key = "rareload_" .. name
    if value == nil then
        return decode(ply:GetPData(key, nil))
    end
    ply:SetPData(key, util.TableToJSON(value))
end
