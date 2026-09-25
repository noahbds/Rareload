-- Storage: the only file touching file.*. JSON documents under data/rareload/, written atomically
-- with a .bak copy, batched to at most one write every 0.5 s (REWRITE_PLAN.md §13.5, §16).
-- File names end in .json and are lowercase, because file.Write only accepts those (G5).

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
function Store.Load(rel)
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
    if cache[rel] == nil and not file.Exists(ROOT .. rel .. ".json", "DATA") then
        Store.Save(rel, data)
        encoded[rel] = json -- written as is, not encoded a second time
    end
    return hash
end

function Store.BlobGet(hash)
    return Store.Load(blobRel(hash))
end

-- Deletes blobs that no save of this map references any more. Runs at startup and on demand.
function Store.GC()
    Store.Flush()
    local dir = Store.MapDir()
    local used = {}
    for _, name in ipairs(file.Find(ROOT .. dir .. "/*.json", "DATA") or {}) do
        local id = name:match("^(%d+)%.json$") -- saves docs are named <SteamID64>.json
        local doc = id and (cache[dir .. "/" .. id] or decode(file.Read(ROOT .. dir .. "/" .. name, "DATA")))
        for _, entry in ipairs(doc and doc.entries or {}) do
            for _, value in pairs(entry.data or {}) do
                if istable(value) and value["$blob"] then used[value["$blob"]] = true end
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

hook.Add("InitPostEntity", "Rareload.Store.GC", function()
    local removed = Store.GC()
    if removed > 0 then log():info("removed %d unused blobs", removed) end
end)

-- Small per-player records (reload-key mode, global inventory) live in sv.db (D17, G49).
function Store.PData(ply, name, value)
    local key = "rareload_" .. name
    if value == nil then
        return decode(ply:GetPData(key, nil))
    end
    ply:SetPData(key, util.TableToJSON(value))
end
