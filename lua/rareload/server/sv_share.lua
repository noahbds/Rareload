-- Export, import and share saves (5.4 plan, A2). An export is one JSON document holding a save with
-- its world data inline, so it can be kept as a backup, moved between singleplayer and a server, or
-- given to another player. Imports are untrusted: only known modules are kept, every object still
-- goes through the restore checks (spawn hooks, limits, denied classes) and player values through
-- the usual privileges when the save is restored.

RARELOAD.Share = RARELOAD.Share or {}
local Share = RARELOAD.Share

local FORMAT, FORMAT_VERSION = "rareload-save", 1
local EXPORTS = "exports/"
local MAX_OBJECTS = 4096
local OFFER_TIME = 120
local SNAPSHOT_KINDS = { entities = true, npcs = true, vehicles = true }

local function log(ply) return RARELOAD.Log("share", ply) end

-- Export ------------------------------------------------------------------------------------------

-- The export document of a save. The global inventory marker is left out: the inventory itself
-- lives in the player's own data, and the map's weapons and ammo are saved next to it anyway.
function Share.Export(ply, entry)
    local data = {}
    for id, value in pairs(entry.data) do
        if id ~= "globalInventory" then data[id] = RARELOAD.Pipeline.Payload(value) end
    end
    return {
        v = RARELOAD.Store.SCHEMA,
        format = FORMAT,
        formatVersion = FORMAT_VERSION,
        rareload = RARELOAD.version,
        map = game.GetMap(),
        sp = game.SinglePlayer(),
        sid64 = ply:SteamID64(),
        nick = ply:Nick(),
        exported = os.time(),
        entry = { time = entry.time, reason = entry.reason, note = entry.note, data = data },
    }
end

-- A file name from the map, the save number and the time: lowercase, as file.Write wants (G5).
function Share.FileName(entry, name)
    if isstring(name) and name ~= "" then return RARELOAD.Store.Clean(name) end
    return RARELOAD.Store.Clean(game.GetMap() .. "_" .. entry.id .. "_" .. os.date("%Y%m%d_%H%M%S"))
end

-- Writes an export to data/rareload/exports/<name>.json on this machine. Returns the path.
function Share.WriteFile(ply, entry, name)
    local rel = EXPORTS .. Share.FileName(entry, name)
    RARELOAD.Store.Save(rel, Share.Export(ply, entry))
    RARELOAD.Store.Flush()
    RARELOAD.Store._cache[rel] = nil -- an export is never read back by this session
    log(ply):info("%s exported save No. %s to data/rareload/%s.json", ply:Nick(), tostring(entry.id), rel)
    return "data/rareload/" .. rel .. ".json"
end

-- Import ------------------------------------------------------------------------------------------

local function newId(old)
    return util.SHA256(tostring(old) .. ":" .. SysTime() .. ":" .. math.random()):sub(1, 12)
end

-- Gives every object of an imported save a new Rareload ID, the same way in every place that names
-- it, so the copy is its own set of objects and never touches the original's (still on the map,
-- maybe owned by someone else).
function Share.Rekey(data)
    local DefID, map = RARELOAD.Snapshot.DefID, {}
    local function remap(id)
        if id == nil or id == "world" then return id end
        local key = tostring(id) -- an all-digit ID comes back from JSON as a number
        map[key] = map[key] or newId(key)
        return map[key]
    end
    for kind in pairs(SNAPSHOT_KINDS) do
        local snap = data[kind]
        if istable(snap) then
            for _, def in pairs(snap.Entities) do
                local id = DefID(def)
                if id then def.EntityMods.rareload.id = remap(id) end
            end
            for _, field in ipairs({ "ai", "runtime" }) do
                if istable(snap[field]) then
                    local out = {}
                    for id, value in pairs(snap[field]) do out[remap(id)] = value end
                    snap[field] = out
                end
            end
            if istable(snap.seat) then snap.seat.vehicle = remap(snap.seat.vehicle) end
        end
    end
    for _, saved in ipairs(istable(data.constraints) and data.constraints or {}) do
        for i, id in pairs(istable(saved.ids) and saved.ids or {}) do saved.ids[i] = remap(id) end
    end
end

local function isBlobRef(value)
    return istable(value) and value["$blob"] ~= nil
end

-- What each module's data is: a table, except the held weapon (a class name). A value of another
-- type would break the timeline that shows it.
local STRING_MODULES = { activeWeapon = true }

-- Checks the shape of one module's imported data. Returns false and why.
local function checkModule(id, value)
    if isBlobRef(value) then return false, "refers to stored data" end
    if STRING_MODULES[id] and not isstring(value) then return false, "not a weapon class" end
    if not STRING_MODULES[id] and not istable(value) then return false, "not the right kind of data" end
    if id == "weapons" then
        for _, class in pairs(value) do
            if not isstring(class) then return false, "not a list of weapon classes" end
        end
    end
    if SNAPSHOT_KINDS[id] then
        if not istable(value) or not istable(value.Entities) then return false, "not a snapshot" end
        for _, def in pairs(value.Entities) do
            if not istable(def) or not isstring(def.Class) then return false, "an object has no class" end
        end
    elseif id == "constraints" then
        if not istable(value) then return false, "not a list" end
        for _, saved in ipairs(value) do
            if not istable(saved) or not istable(saved.def) or not istable(saved.ids) then
                return false, "a constraint is incomplete"
            end
        end
    end
    return true
end

-- Adds an export document to the player's timeline as a new save (not their respawn point). The
-- document is changed (new object IDs), so it must not be shared with cached saves.
-- opts = { reason? ("import" | "shared"), from? (who shared it) }.
-- Returns true and the new save's number plus the dropped parts, or false and why (English, for
-- the console and the toast).
function Share.Import(ply, doc, opts)
    opts = opts or {}
    if not istable(doc) or doc.format ~= FORMAT or not istable(doc.entry) or not istable(doc.entry.data) then
        return false, "this is not a Rareload save"
    end
    if (tonumber(doc.formatVersion) or 0) > FORMAT_VERSION then
        return false, "it was made by a newer version of Rareload"
    end

    local sameMap = doc.map == game.GetMap()
    local data, dropped, objects = {}, {}, 0
    for id, value in pairs(doc.entry.data) do
        local def = RARELOAD.Pipeline._defs[id]
        local ok, why = def ~= nil and def.load == nil, "unknown part"
        if ok and not sameMap and (def.phase == "world" or id == "transform") then
            ok, why = false, "made on " .. tostring(doc.map)
        end
        if ok then ok, why = checkModule(id, value) end
        if ok and SNAPSHOT_KINDS[id] then objects = objects + table.Count(value.Entities) end
        if ok then
            data[id] = value
        else
            dropped[#dropped + 1] = tostring(id) .. " (" .. why .. ")"
        end
    end
    if objects > MAX_OBJECTS then return false, "it holds more than " .. MAX_OBJECTS .. " objects" end
    if not next(data) then return false, "nothing in it can be used on this map" end

    -- Your own export, back on the same map: the objects are still yours, so they keep their IDs and
    -- one that is still on the map is put back instead of copied. Anything else becomes a copy, and
    -- leaves out the attachment stock of whoever made it (it would give attachments for free).
    local own = doc.sid64 == ply:SteamID64() and opts.reason ~= "shared"
    if not (sameMap and own) then Share.Rekey(data) end
    if not own and istable(data.weaponState) then data.weaponState.owned = nil end
    for id, value in pairs(data) do
        local def = RARELOAD.Pipeline._defs[id]
        if def.heavy then data[id] = { ["$blob"] = RARELOAD.Store.BlobPut(value) } end
    end

    local note = isstring(doc.entry.note) and string.Trim(doc.entry.note) or ""
    if opts.from then note = string.Trim("[" .. opts.from .. "] " .. note) end
    local entry = {
        time = os.time(), reason = opts.reason or "import", data = data,
        note = note ~= "" and string.sub(note, 1, 256) or nil,
    }
    if not RARELOAD.History.Append(ply, entry, { keepActive = true }) then
        return false, "your saves can't be stored (no SteamID)"
    end
    log(ply):info("%s imported a save (%s) as No. %d%s", ply:Nick(), opts.reason or "import", entry.id,
        #dropped > 0 and ", left out: " .. table.concat(dropped, ", ") or "")
    return true, entry.id, dropped
end

-- Imports and tells the player how it went. Returns like Share.Import.
local function importAndTell(ply, doc, opts)
    local ok, idOrWhy, dropped = Share.Import(ply, doc, opts)
    if not ok then
        RARELOAD.Toast(ply, "toast.import_failed", { idOrWhy }, "error")
        return false, idOrWhy
    end
    if #dropped > 0 then
        RARELOAD.Toast(ply, "toast.imported_partly", { idOrWhy, #dropped }, "ok")
        ply:PrintMessage(HUD_PRINTCONSOLE, "[Rareload] Save No. " .. idOrWhy .. ", left out: "
            .. table.concat(dropped, ", "))
    else
        RARELOAD.Toast(ply, "toast.imported", { idOrWhy }, "ok")
    end
    return true, idOrWhy, dropped
end

Share.ImportAndTell = importAndTell

-- An export file from data/rareload/exports on this machine, or nil. `name` without ".json".
function Share.ReadFile(name)
    local rel = EXPORTS .. RARELOAD.Store.Clean(name)
    local doc = RARELOAD.Store.Load(rel, true)
    RARELOAD.Store._cache[rel] = nil -- read once, never kept
    return doc
end

local function decode(text)
    local doc = util.JSONToTable(text, true) -- big saves must load (G1)
    return istable(doc) and doc or nil
end

RARELOAD.Net.HandleUpload("import", {
    priv = "rareload_import",
    maxBytes = function() return RARELOAD.Get(nil, "importMaxKB") * 1024 end,
    fn = function(ply, text) importAndTell(ply, decode(text)) end,
})

-- Sending an export to the player's own game, which writes it to its data/rareload/exports folder.
RARELOAD.Net.Handle("export.get", {
    priv = "rareload_export",
    rate = 2,
    args = { id = "uint" },
    fn = function(ply, a)
        local entry = RARELOAD.History.Get(ply, a.id)
        if not entry then return end
        log(ply):info("%s downloaded save No. %d as a file", ply:Nick(), a.id)
        RARELOAD.Net.Push(ply, "export.file", { name = Share.FileName(entry), doc = Share.Export(ply, entry) },
            { key = "export:" .. a.id })
    end,
})

-- Sharing with another player on the server ---------------------------------------------------------

Share._offers = Share._offers or setmetatable({}, { __mode = "k" }) -- recipient -> offer
local offers = Share._offers

-- Offers a copy of one of `ply`'s saves to `target`, who accepts or declines it. A newer offer to
-- the same player replaces the last one. Returns false and why (English).
function Share.Offer(ply, id, target)
    local entry = RARELOAD.History.Get(ply, id)
    if not entry then return false, "no such save" end
    if not IsValid(target) or not target:IsPlayer() or target:IsBot() then return false, "no such player" end
    if target == ply then return false, "that's you" end
    if not RARELOAD.Can(target, "rareload_restore") then return false, "they can't use Rareload saves" end

    -- Kept as text: the save as it is now, and never the cached blobs themselves (Import changes the
    -- data it is given).
    local token = newId(ply:SteamID64() .. id)
    offers[target] = {
        token = token, from = ply, nick = ply:Nick(), id = id,
        text = util.TableToJSON(Share.Export(ply, entry)), expires = CurTime() + OFFER_TIME,
    }
    local info = RARELOAD.History.Info(entry.data)
    RARELOAD.Net.Push(target, "share.offer", {
        token = token, nick = ply:Nick(), id = id, note = entry.note, time = entry.time,
        objects = (info.entities or 0) + (info.npcs or 0) + (info.vehicles or 0), weapons = info.weapons,
    })
    log(ply):info("%s offered save No. %d to %s", ply:Nick(), id, target:Nick())
    return true
end

RARELOAD.Net.Handle("share.send", {
    priv = "rareload_share",
    rate = 3,
    args = { id = "uint", sid = "string:20" },
    fn = function(ply, a)
        local ok, why = Share.Offer(ply, a.id, player.GetBySteamID64(a.sid))
        if ok then
            RARELOAD.Toast(ply, "toast.share_sent", { a.id })
        else
            RARELOAD.Toast(ply, "toast.share_failed", { why }, "error")
        end
    end,
})

RARELOAD.Net.Handle("share.answer", {
    rate = 0.5,
    args = { token = "string:16", accept = "bool" },
    fn = function(ply, a)
        local offer = offers[ply]
        if not offer or offer.token ~= a.token then return end
        offers[ply] = nil
        local from = offer.from
        if CurTime() > offer.expires then return RARELOAD.Toast(ply, "toast.share_expired", nil, "error") end
        if not a.accept then
            if IsValid(from) then RARELOAD.Toast(from, "toast.share_declined", { ply:Nick() }) end
            return
        end
        local ok, newIdOrWhy = importAndTell(ply, decode(offer.text), { reason = "shared", from = offer.nick })
        if ok and IsValid(from) then RARELOAD.Toast(from, "toast.share_accepted", { ply:Nick() }, "ok") end
        if not ok then log(ply):warn("%s could not take %s's save: %s", ply:Nick(), offer.nick, newIdOrWhy) end
    end,
})

hook.Add("PlayerDisconnected", "Rareload.Share", function(ply) offers[ply] = nil end)
