-- Save history per player and map: the current save is simply the active entry (REWRITE_PLAN.md §15.4,
-- §15.8, §16.2). Timeline operations, undo, the tool's reload-key modes and edits of saved objects.

RARELOAD.History = RARELOAD.History or {}
local History = RARELOAD.History

local WORLD_KINDS = { "entities", "npcs", "vehicles" }

-- Timeline components and the modules they restore (§15.4).
History.COMPONENTS = {
    position = { "transform" },
    health = { "health" },
    inventory = { "weapons", "activeWeapon" },
    ammo = { "ammo" },
    appearance = { "appearance" },
    states = { "states" },
    world = { "entities", "npcs", "vehicles", "constraints" },
}

-- Returns the player's saves document (a new, unsaved one if they have none) and its storage path,
-- or nil for players without a stable ID.
function History.Doc(ply)
    local key = RARELOAD.Util.PlayerKey(ply)
    if not key then return nil end
    local rel = RARELOAD.Store.MapDir() .. "/" .. key
    local d = RARELOAD.Store.Load(rel) or { v = RARELOAD.Store.SCHEMA, sid64 = key, nextId = 1, entries = {} }
    return d, rel
end

local refresh -- pushes the new timeline and world display data, defined below

local function save(ply, d)
    local _, rel = History.Doc(ply)
    refresh(ply)
    return RARELOAD.Store.Save(rel, d)
end

local function find(d, id)
    for i, entry in ipairs(d and d.entries or {}) do
        if entry.id == id then return entry, i end
    end
end

function History.Get(ply, id)
    return (find(History.Doc(ply), id))
end

function History.Active(ply)
    local d = History.Doc(ply)
    return d and d.activeId and (find(d, d.activeId)) or nil
end

-- The entry saved just before the active one (for the reload key).
function History.Previous(ply)
    local d = History.Doc(ply)
    local _, i = find(d, d and d.activeId)
    return i and d.entries[i - 1] or nil
end

-- Adds a save and makes it active. The oldest entries beyond `historySize` are dropped, except
-- pinned ones and the active one.
function History.Append(ply, entry)
    local d = History.Doc(ply)
    if not d then return false end
    entry.id = d.nextId
    d.nextId = d.nextId + 1
    d.entries[#d.entries + 1] = entry
    d.activeId = entry.id

    local cap, i = RARELOAD.Get(ply, "historySize"), 1
    while #d.entries > cap and i <= #d.entries do
        local e = d.entries[i]
        if e.pinned or e.id == d.activeId then i = i + 1 else table.remove(d.entries, i) end
    end
    return save(ply, d)
end

-- The name of this option is a bit confusing, what it does is to prevent the pinned save to be deleted after to many saves,
-- but it doesn't prevent the save to be deleted if the player deletes it manually.
-- TODO: rename this option to "keepPinnedSaves" or something like that. Or at least add a tooltip to explain what it does.
function History.SetPinned(ply, id, pinned)
    local d = History.Doc(ply)
    local entry = find(d, id)
    if not entry then return false end
    entry.pinned = pinned or nil
    return save(ply, d)
end

-- Give the ability to set a note to a save, so the player can remember what was saved in that save.
-- Not really useful in a sense but it's there.
function History.SetNote(ply, id, note)
    local d = History.Doc(ply)
    local entry = find(d, id)
    if not entry then return false end
    entry.note = note ~= "" and note or nil
    return save(ply, d)
end

-- Deleting the active entry makes the newest remaining one active.
function History.Delete(ply, id)
    local d = History.Doc(ply)
    local _, i = find(d, id)
    if not i then return false end
    table.remove(d.entries, i)
    if d.activeId == id then d.activeId = d.entries[#d.entries] and d.entries[#d.entries].id or nil end
    return save(ply, d)
end

-- Removes every entry except pinned ones and the active one.
function History.Clear(ply)
    local d = History.Doc(ply)
    if not d then return false end
    local kept = {}
    for _, e in ipairs(d.entries) do
        if e.pinned or e.id == d.activeId then kept[#kept + 1] = e end
    end
    d.entries = kept
    return save(ply, d)
end

-- Makes an entry the respawn point (F24).
function History.Activate(ply, id)
    local d = History.Doc(ply)
    if not find(d, id) then return false end
    d.activeId = id
    return save(ply, d)
end

-- Restore and undo -------------------------------------------------------------------------------

local undos = setmetatable({}, { __mode = "k" }) -- ply -> { entry, only, ctx }; one level, like v4

-- comps: a set of component names (§15.4), or nil for everything. Returns the module set or nil.
function History.ModulesFor(comps)
    if not comps then return nil end
    local only = {}
    for comp in pairs(comps) do
        for _, id in ipairs(History.COMPONENTS[comp] or {}) do only[id] = true end
    end
    return only
end

-- Restores an entry now (F25). The current state of the same modules (except the world, which is
-- undone by removing what the restore created) is captured first, for undo (F26).
function History.Restore(ply, id, comps)
    local entry = History.Get(ply, id)
    if not entry or not ply:Alive() then return false end
    local only = History.ModulesFor(comps)

    local undoOnly = {}
    for _, name in ipairs(table.GetKeys(History.COMPONENTS)) do
        if name ~= "world" and (not comps or comps[name]) then
            for _, m in ipairs(History.COMPONENTS[name]) do undoOnly[m] = true end
        end
    end
    local _, _, snapshot = RARELOAD.Pipeline.Save(ply, { only = undoOnly, captureOnly = true, silent = true })

    local ctx = RARELOAD.Pipeline.Restore(ply, entry, { only = only, reason = "timeline" })
    undos[ply] = { entry = snapshot, only = undoOnly, ctx = ctx }
    refresh(ply) -- the timeline should now show Undo button being active
    return true
end

-- Removes what the last restore created (even vehicles that finished spawning later, E14) and puts
-- the player back the way they were before it.
function History.Undo(ply)
    local u = undos[ply]
    if not u then return false end
    undos[ply] = nil
    refresh(ply)
    for _, ent in ipairs(u.ctx.spawned) do
        if IsValid(ent) then ent:Remove() end
    end
    if u.entry then RARELOAD.Pipeline.Restore(ply, u.entry, { only = u.only, reason = "undo" }) end
    return true
end

-- Reload key (F28) --------------------------------------------------------------------------------

History.RELOAD_MODES = { set_previous = true, restore_current = true, restore_previous = true }

function History.ReloadConfig(ply)
    local cfg = RARELOAD.Store.PData(ply, "reload")
    if not istable(cfg) or not History.RELOAD_MODES[cfg.mode] then cfg = { mode = "set_previous" } end
    return cfg
end

-- Returns a toast key describing the outcome, and the number of the save it's about.
function History.ReloadKey(ply)
    local cfg = History.ReloadConfig(ply)
    local comps = cfg.comps and next(cfg.comps) and cfg.comps or nil
    local active, previous = History.Active(ply), History.Previous(ply)
    if not active then return "toast.reload.empty" end

    if cfg.mode == "restore_current" then
        History.Restore(ply, active.id, comps)
        return "toast.reload.restored", active.id
    end
    if not previous then return "toast.reload.no_previous" end
    if cfg.mode == "restore_previous" then History.Restore(ply, previous.id, comps) end
    History.Activate(ply, previous.id) -- walking back one save at a time
    return cfg.mode == "restore_previous" and "toast.reload.restored" or "toast.reload.previous", previous.id
end

-- Objects inside saves (F29) ----------------------------------------------------------------------

-- What the inspector, the timeline preview and the world display show about one saved object.
-- `snap` gives the NPC AI state and vehicle runtime kept next to the duplicator data.
local function objectInfo(def, kind, snap)
    local mods = istable(def.EntityMods) and def.EntityMods or {}
    local phys = istable(def.PhysicsObjects) and (def.PhysicsObjects[0] or def.PhysicsObjects["0"]) or {}
    local rl = istable(mods.rareload) and mods.rareload or {}
    local id = RARELOAD.Snapshot.DefID(def)
    local runtime = id and istable(snap.runtime) and (snap.runtime[id] or snap.runtime[tonumber(id)]) or nil
    local ai = id and istable(snap.ai) and (snap.ai[id] or snap.ai[tonumber(id)]) or nil
    return {
        id = id,
        kind = kind,
        class = def.Class,
        model = def.Model,
        skin = def.Skin,
        pos = isvector(def.Pos) and RARELOAD.Util.Vec(def.Pos) or nil,
        ang = isangle(def.Angle) and RARELOAD.Util.Ang(def.Angle) or nil,
        frozen = phys.Frozen or nil,
        nograv = phys.NoGrav or nil,
        hp = rl.hp,
        maxHp = (tonumber(rl.hp) or 0) > 0 and rl.maxHp or nil,
        scale = def.ModelScale,
        bodygroups = def.BodyG,
        material = istable(mods.material) and mods.material.MaterialOverride or nil,
        color = istable(mods.colour) and mods.colour.Color or nil, -- tagged { __color = { r, g, b, a } }
        base = runtime and runtime.adapter,
        parts = runtime and runtime.parts,
        squad = ai and ai.squad,
        npcState = ai and ai.state,
    }
end

-- Calls fn(def, kind, snap) for every saved object of an entry until fn returns a value.
local function eachObject(entry, fn)
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = entry and RARELOAD.Pipeline.Payload(entry.data[kind])
        for _, def in pairs(snap and snap.Entities or {}) do
            local r = fn(def, kind, snap)
            if r ~= nil then return r end
        end
    end
end

-- Every saved object of an entry.
function History.Objects(ply, id)
    local out = {}
    eachObject(History.Get(ply, id), function(def, kind, snap) out[#out + 1] = objectInfo(def, kind, snap) end)
    return out
end

History.ObjectsOf = function(entry)
    local out = {}
    eachObject(entry, function(def, kind, snap) out[#out + 1] = objectInfo(def, kind, snap) end)
    return out
end

-- The full saved definition of one object, with its NPC AI state and vehicle runtime, or nil.
function History.ObjectDetail(entry, objectId)
    return eachObject(entry, function(def, _, snap)
        if RARELOAD.Snapshot.DefID(def) == objectId then
            return {
                def = def,
                ai = istable(snap.ai) and (snap.ai[objectId] or snap.ai[tonumber(objectId)]) or nil,
                runtime = istable(snap.runtime) and (snap.runtime[objectId] or snap.runtime[tonumber(objectId)]) or nil
            }
        end
    end)
end

function History.ObjectDef(ply, entryId, objectId)
    local detail = History.ObjectDetail(History.Get(ply, entryId), objectId)
    return detail and detail.def
end

-- Pure (unit-tested): an edit may only change keys the object already has, to a value of the same
-- type, and never its class or model unless the editor is a full admin (S6).
function History.ValidateEdit(def, edit, isAdmin)
    if not istable(edit) then return false, "the edit is not a table" end
    for k, v in pairs(edit) do
        if def[k] == nil then return false, "unknown key " .. tostring(k) end
        if type(def[k]) ~= type(v) then return false, "wrong type for " .. tostring(k) end
        if (k == "Class" or k == "Model") and not isAdmin then return false, k .. " needs rareload_admin" end
    end
    return true
end

-- Applies `change(def, snap, index)` to one object of an entry. Saved data is never modified in
-- place: the snapshot is copied, changed, and stored as a new blob (§16.3).
local function changeObject(ply, entryId, objectId, change)
    local d = History.Doc(ply)
    local entry = find(d, entryId)
    if not entry then return false, "no such save" end
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = RARELOAD.Pipeline.Payload(entry.data[kind])
        for index, def in pairs(snap and snap.Entities or {}) do
            if RARELOAD.Snapshot.DefID(def) == objectId then
                local copy = util.JSONToTable(util.TableToJSON(snap), true)
                local ok, err = change(copy.Entities[index], copy, index)
                if not ok then return false, err end
                RARELOAD.Snapshot.PruneConstraints(copy)
                entry.data[kind] = { ["$blob"] = RARELOAD.Store.BlobPut(copy) }
                save(ply, d)
                return true
            end
        end
    end
    return false, "no such object"
end

function History.DeleteObject(ply, entryId, objectId)
    return changeObject(ply, entryId, objectId, function(_, snap, index)
        snap.Entities[index] = nil
        return true
    end)
end

-- Deletes several objects at once: each snapshot is copied and stored once, not once per object.
function History.DeleteObjects(ply, entryId, ids)
    local d = History.Doc(ply)
    local entry = find(d, entryId)
    if not entry then return false, "no such save" end
    local removed = 0
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = RARELOAD.Pipeline.Payload(entry.data[kind])
        local hit = false
        for _, def in pairs(snap and snap.Entities or {}) do
            if ids[RARELOAD.Snapshot.DefID(def)] then
                hit = true
                break
            end
        end
        if hit then
            local copy = util.JSONToTable(util.TableToJSON(snap), true)
            for index, def in pairs(copy.Entities) do
                if ids[RARELOAD.Snapshot.DefID(def)] then
                    copy.Entities[index] = nil
                    removed = removed + 1
                end
            end
            RARELOAD.Snapshot.PruneConstraints(copy)
            entry.data[kind] = { ["$blob"] = RARELOAD.Store.BlobPut(copy) }
        end
    end
    if removed == 0 then return false, "no such object" end
    save(ply, d)
    return true
end

-- flag: "frozen" or "nogravity"
function History.FlagObject(ply, entryId, objectId, flag, value)
    local field = ({ frozen = "Frozen", nogravity = "NoGrav" })[flag]
    if not field then return false, "unknown flag" end
    return changeObject(ply, entryId, objectId, function(def)
        for _, phys in pairs(def.PhysicsObjects or {}) do phys[field] = value or nil end
        return true
    end)
end

function History.EditObject(ply, entryId, objectId, edit)
    return changeObject(ply, entryId, objectId, function(def)
        local ok, err = History.ValidateEdit(def, edit, RARELOAD.Can(ply, "rareload_admin"))
        if not ok then return false, err end
        for k, v in pairs(edit) do def[k] = v end
        return true
    end)
end

-- Network requests (§17.3) ------------------------------------------------------------------------

-- Facts about a world snapshot the timeline shows, cached by blob hash so building rows doesn't
-- reload blobs: how many objects, and the class of the vehicle the player was seated in.
local snapFacts = {}

local function factsOf(value)
    local hash = istable(value) and value["$blob"]
    if hash and snapFacts[hash] then return snapFacts[hash] end
    local snap = RARELOAD.Pipeline.Payload(value)
    local facts = { count = 0 }
    if istable(snap) then
        facts.count = table.Count(snap.Entities or {})
        local seatId = istable(snap.seat) and snap.seat.vehicle
        for _, def in pairs(seatId and snap.Entities or {}) do
            if RARELOAD.Snapshot.DefID(def) == seatId then facts.seatClass = def.Class end
        end
    end
    if hash then snapFacts[hash] = facts end
    return facts
end

-- Raw values for the timeline; the client formats and translates them (L29).
function History.Info(data)
    local t, h = data.transform or {}, data.health or {}
    local info = {
        pos = t.pos,
        ang = t.ang,
        crouched = t.crouched,
        model = data.appearance and data.appearance.model,
        hp = h.hp,
        armor = h.armor,
        active = data.activeWeapon,
        states = data.states,
        weapons = data.weapons and #data.weapons,
    }
    for _, kind in ipairs(WORLD_KINDS) do
        if data[kind] ~= nil then info[kind] = factsOf(data[kind]).count end
    end
    if data.vehicles ~= nil then info.vehicle = factsOf(data.vehicles).seatClass end
    local look = data.appearance
    if istable(look) then
        info.look = {
            skin = look.skin,
            bodygroups = look.bodygroups,
            material = look.material,
            playerColor = look.playerColor,
            color = look.color
        }
    end
    return info
end

-- A note read back from disk: GMod's JSON turns a note like "[1 2 3]" into a Vector.
local function noteText(note)
    if isvector(note) then return string.format("[%g %g %g]", note.x, note.y, note.z) end
    if isangle(note) then return string.format("{%g %g %g}", note.p, note.y, note.r) end
    return note ~= nil and tostring(note) or nil
end

-- One row per entry.
function History.Rows(ply)
    local d, rows = History.Doc(ply), {}
    for _, e in ipairs(d and d.entries or {}) do
        e.note = noteText(e.note)
        local modules = {}
        for id in pairs(e.data) do modules[#modules + 1] = id end
        table.sort(modules)
        rows[#rows + 1] = {
            id = e.id,
            time = e.time,
            reason = e.reason,
            pinned = e.pinned,
            note = e.note,
            active = e.id == d.activeId,
            modules = modules,
            info = History.Info(e.data)
        }
    end
    return rows
end

local function pushRows(ply)
    RARELOAD.Net.Push(ply, "history", {
        rows = History.Rows(ply),
        reload = History.ReloadConfig(ply),
        undo = undos[ply] ~= nil
    })
end

local function parseComps(text)
    if text == nil or text == "" or text == "all" then return nil end
    local comps = {}
    for name in string.gmatch(text, "[%w_]+") do
        if History.COMPONENTS[name] then comps[name] = true end
    end
    return comps
end
History.ParseComps = parseComps

-- Network handlers for timeline and object operations. The client pushes a request, the server
-- checks the player's privilege, performs the operation, and pushes back the new timeline rows.
local function handle(op, priv, args, fn)
    RARELOAD.Net.Handle(op, {
        priv = priv,
        rate = 0.2,
        args = args,
        fn = function(ply, a)
            local key, args = fn(ply, a)
            if key then RARELOAD.Toast(ply, key, args) end
            pushRows(ply)
        end
    })
end

handle("history.get", "rareload_restore", {}, function() end)
handle("history.pin", "rareload_restore", { id = "uint", pinned = "bool" },
    function(ply, a) History.SetPinned(ply, a.id, a.pinned) end)
handle("history.note", "rareload_restore", { id = "uint", note = "string:256" },
    function(ply, a) History.SetNote(ply, a.id, a.note) end)
handle("history.delete", "rareload_restore", { id = "uint" }, function(ply, a) History.Delete(ply, a.id) end)
handle("history.clear", "rareload_restore", {}, function(ply) History.Clear(ply) end)
handle("history.activate", "rareload_restore", { id = "uint" }, function(ply, a)
    if History.Activate(ply, a.id) then return "toast.activated", { a.id } end
end)
handle("history.restore", "rareload_restore", { id = "uint", comps = "string:128?" }, function(ply, a)
    if not ply:Alive() then return "toast.restore_dead" end
    if History.Restore(ply, a.id, parseComps(a.comps)) then return "toast.restored", { a.id } end
end)
handle("history.undo", "rareload_restore", {}, function(ply)
    return History.Undo(ply) and "toast.undone" or "toast.nothing_to_undo"
end)
handle("history.reloadMode", "rareload_use_tool", { mode = "string:32", comps = "string:128?" }, function(ply, a)
    if not History.RELOAD_MODES[a.mode] then return end
    RARELOAD.Store.PData(ply, "reload", { mode = a.mode, comps = parseComps(a.comps) })
end)

RARELOAD.Net.Handle("object.get", {
    priv = "rareload_manage_objects",
    rate = 0.3,
    args = { entryId = "uint", objectId = "string:32" },
    fn = function(ply, a)
        local def = History.ObjectDef(ply, a.entryId, a.objectId)
        if def then
            RARELOAD.Net.Push(ply, "object.def",
                { entryId = a.entryId, objectId = a.objectId, json = util.TableToJSON(def, true) })
        end
    end,
})

-- Everything saved about one object, for the world display's focused panel: from one of the
-- player's own saves, or (with rareload_debug while debug is on) another player's respawn point.
RARELOAD.Net.Handle("object.detail", {
    rate = 0.1,
    args = { sid = "string:20?", entryId = "uint?", objectId = "string:32" },
    fn = function(ply, a)
        local entry
        if a.sid and a.sid ~= ply:SteamID64() then
            local owner = player.GetBySteamID64(a.sid)
            if not IsValid(owner) or not RARELOAD.Get(nil, "debug") or not RARELOAD.Can(ply, "rareload_debug") then return end
            entry = History.Active(owner)
        elseif RARELOAD.Can(ply, "rareload_restore") then
            entry = a.entryId and History.Get(ply, a.entryId) or History.Active(ply)
        end
        local detail = entry and History.ObjectDetail(entry, a.objectId)
        if detail then
            RARELOAD.Net.Push(ply, "object.detail",
                { sid = a.sid, entryId = a.entryId, objectId = a.objectId, detail = detail },
                { key = "detail:" .. tostring(a.sid) .. ":" .. tostring(a.entryId) .. ":" .. a.objectId })
        end
    end,
})

RARELOAD.Net.Handle("history.objects", {
    priv = "rareload_restore",
    rate = 0.3,
    args = { id = "uint" },
    fn = function(ply, a) RARELOAD.Net.Push(ply, "history.objects", { id = a.id, objects = History.Objects(ply, a.id) }) end,
})

local function objectOp(op, args, fn)
    RARELOAD.Net.Handle(op, {
        priv = "rareload_manage_objects",
        rate = 0.2,
        args = args,
        fn = function(ply, a)
            local ok, err = fn(ply, a)
            if not ok then RARELOAD.Log("history"):warn("%s: %s failed: %s", ply:Nick(), op, tostring(err)) end
            RARELOAD.Net.Push(ply, "history.objects", { id = a.entryId, objects = History.Objects(ply, a.entryId) })
        end
    })
end

objectOp("object.delete", { entryId = "uint", objectId = "string:32" }, function(ply, a)
    return History.DeleteObject(ply, a.entryId, a.objectId)
end)
-- ids: object IDs separated by commas.
objectOp("object.deleteMany", { entryId = "uint", ids = "string:60000" }, function(ply, a)
    local ids = {}
    for id in string.gmatch(a.ids, "[%w]+") do ids[id] = true end
    return History.DeleteObjects(ply, a.entryId, ids)
end)
objectOp("object.flag", { entryId = "uint", objectId = "string:32", flag = "string:16", value = "bool" },
    function(ply, a)
        return History.FlagObject(ply, a.entryId, a.objectId, a.flag, a.value)
    end)
-- The edit arrives as JSON and is decoded with the default size limits (S12).
objectOp("object.edit", { entryId = "uint", objectId = "string:32", json = "string:60000" }, function(ply, a)
    return History.EditObject(ply, a.entryId, a.objectId, util.JSONToTable(a.json))
end)

-- Pushes after changes ----------------------------------------------------------------------------

-- World display feed (§17.2): each player's respawn point with its light modules and objects, sent
-- to players with rareload_debug while the debug setting is on.
local function subscribers()
    local out = {}
    if not RARELOAD.Get(nil, "debug") then return out end
    for _, p in player.Iterator() do
        if RARELOAD.Can(p, "rareload_debug") then out[#out + 1] = p end
    end
    return out
end

local function feedFor(ply)
    local active = History.Active(ply)
    if not active then return nil end
    local light = {}
    for id, value in pairs(active.data) do
        local def = RARELOAD.Pipeline._defs[id]
        if def and not def.heavy and def.phase ~= "world" then light[id] = value end
    end
    return { nick = ply:Nick(), data = light, objects = History.ObjectsOf(active), seated = History.Info(active.data)
    .vehicle ~= nil }
end

local function pushFeed(ply, targets)
    targets = targets or subscribers()
    if #targets == 0 then return end
    local sid = ply:SteamID64()
    RARELOAD.Net.Push(targets, "saves", { sid = sid, save = feedFor(ply) }, { key = "saves:" .. sid })
end

local changed = {}

-- Called on every change of a saves document; the pushes wait until the changes settle.
refresh = function(ply)
    changed[ply] = true
    if timer.Exists("Rareload.History.Push") then return end
    timer.Create("Rareload.History.Push", 0.1, 1, function()
        for p in pairs(changed) do
            if IsValid(p) then
                pushRows(p)
                pushFeed(p)
            end
        end
        changed = {}
    end)
end

hook.Add("RareloadClientReady", "Rareload.History", function(ply)
    pushRows(ply)
    if RARELOAD.Get(nil, "debug") and RARELOAD.Can(ply, "rareload_debug") then
        for _, p in player.Iterator() do pushFeed(p, { ply }) end
    end
end)

hook.Add("PlayerDisconnected", "Rareload.History", function(ply)
    local targets = subscribers()
    if #targets > 0 then
        RARELOAD.Net.Push(targets, "saves", { sid = ply:SteamID64() }, { key = "saves:" .. ply:SteamID64() })
    end
end)

cvars.AddChangeCallback("sv_rareload_debug", function(_, _, value)
    if tonumber(value) == 1 then
        for _, p in player.Iterator() do pushFeed(p) end
    end
end, "Rareload.History")
