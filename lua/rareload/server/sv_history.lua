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

local refresh   -- pushes the new timeline and world display data, defined below

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

function History.SetPinned(ply, id, pinned)
    local d = History.Doc(ply)
    local entry = find(d, id)
    if not entry then return false end
    entry.pinned = pinned or nil
    return save(ply, d)
end

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

local undos = setmetatable({}, { __mode = "k" })   -- ply -> { entry, only, ctx }; one level, like v4

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
    if not entry then return false end
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
    return true
end

-- Removes what the last restore created (even vehicles that finished spawning later, E14) and puts
-- the player back the way they were before it.
function History.Undo(ply)
    local u = undos[ply]
    if not u then return false end
    undos[ply] = nil
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

-- Returns a toast key describing the outcome.
function History.ReloadKey(ply)
    local cfg = History.ReloadConfig(ply)
    local comps = cfg.comps and next(cfg.comps) and cfg.comps or nil
    local active, previous = History.Active(ply), History.Previous(ply)
    if not active then return "toast.reload.empty" end

    if cfg.mode == "restore_current" then
        History.Restore(ply, active.id, comps)
        return "toast.reload.restored"
    end
    if not previous then return "toast.reload.no_previous" end
    if cfg.mode == "restore_previous" then History.Restore(ply, previous.id, comps) end
    History.Activate(ply, previous.id)   -- walking back one save at a time
    return cfg.mode == "restore_previous" and "toast.reload.restored" or "toast.reload.previous"
end

-- Objects inside saves (F29) ----------------------------------------------------------------------

-- What the inspector, the timeline preview and the world display show about one saved object.
local function objectInfo(def, kind)
    local mods = istable(def.EntityMods) and def.EntityMods or {}
    local phys = istable(def.PhysicsObjects) and (def.PhysicsObjects[0] or def.PhysicsObjects["0"]) or {}
    local rl = istable(mods.rareload) and mods.rareload or {}
    return {
        id = RARELOAD.Snapshot.DefID(def), kind = kind, class = def.Class, model = def.Model, skin = def.Skin,
        pos = isvector(def.Pos) and RARELOAD.Util.Vec(def.Pos) or nil,
        ang = isangle(def.Angle) and RARELOAD.Util.Ang(def.Angle) or nil,
        frozen = phys.Frozen or nil, nograv = phys.NoGrav or nil,
        hp = rl.hp, maxHp = rl.maxHp,
        material = istable(mods.material) and mods.material.MaterialOverride or nil,
        color = istable(mods.colour) and mods.colour.Color or nil,   -- tagged { __color = { r, g, b, a } }
    }
end

-- Every saved object of an entry.
function History.Objects(ply, id)
    local entry = History.Get(ply, id)
    local out = {}
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = entry and RARELOAD.Pipeline.Payload(entry.data[kind])
        for _, def in pairs(snap and snap.Entities or {}) do
            out[#out + 1] = objectInfo(def, kind)
        end
    end
    return out
end

-- The full saved definition of one object, for the JSON editor.
function History.ObjectDef(ply, entryId, objectId)
    local entry = History.Get(ply, entryId)
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = entry and RARELOAD.Pipeline.Payload(entry.data[kind])
        for _, def in pairs(snap and snap.Entities or {}) do
            if RARELOAD.Snapshot.DefID(def) == objectId then return def end
        end
    end
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

local objectCounts = {}   -- blob hash -> number of objects, so building rows doesn't reload blobs

local function objectCount(value)
    local hash = istable(value) and value["$blob"]
    if hash and objectCounts[hash] then return objectCounts[hash] end
    local snap = RARELOAD.Pipeline.Payload(value)
    local n = istable(snap) and table.Count(snap.Entities or {}) or 0
    if hash then objectCounts[hash] = n end
    return n
end

-- Raw values for the timeline; the client formats and translates them (L29).
function History.Info(data)
    local t, h = data.transform or {}, data.health or {}
    local info = {
        pos = t.pos, ang = t.ang, model = data.appearance and data.appearance.model,
        hp = h.hp, armor = h.armor, active = data.activeWeapon, states = data.states,
        weapons = data.weapons and #data.weapons,
    }
    for _, kind in ipairs(WORLD_KINDS) do
        if data[kind] ~= nil then info[kind] = objectCount(data[kind]) end
    end
    return info
end

-- One row per entry.
function History.Rows(ply)
    local d, rows = History.Doc(ply), {}
    for _, e in ipairs(d and d.entries or {}) do
        local modules = {}
        for id in pairs(e.data) do modules[#modules + 1] = id end
        table.sort(modules)
        rows[#rows + 1] = { id = e.id, time = e.time, reason = e.reason, pinned = e.pinned, note = e.note,
            active = e.id == d.activeId, modules = modules, info = History.Info(e.data) }
    end
    return rows
end

local function pushRows(ply)
    RARELOAD.Net.Push(ply, "history", { rows = History.Rows(ply), reload = History.ReloadConfig(ply) })
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

local function handle(op, priv, args, fn)
    RARELOAD.Net.Handle(op, { priv = priv, rate = 0.2, args = args, fn = function(ply, a)
        local key = fn(ply, a)
        if key then RARELOAD.Toast(ply, key) end
        pushRows(ply)
    end })
end

handle("history.get", "rareload_restore", {}, function() end)
handle("history.pin", "rareload_restore", { id = "uint", pinned = "bool" }, function(ply, a) History.SetPinned(ply, a.id, a.pinned) end)
handle("history.note", "rareload_restore", { id = "uint", note = "string:256" }, function(ply, a) History.SetNote(ply, a.id, a.note) end)
handle("history.delete", "rareload_restore", { id = "uint" }, function(ply, a) History.Delete(ply, a.id) end)
handle("history.clear", "rareload_restore", {}, function(ply) History.Clear(ply) end)
handle("history.activate", "rareload_restore", { id = "uint" }, function(ply, a)
    return History.Activate(ply, a.id) and "toast.activated" or nil
end)
handle("history.restore", "rareload_restore", { id = "uint", comps = "string:128?" }, function(ply, a)
    return History.Restore(ply, a.id, parseComps(a.comps)) and "toast.restored" or nil
end)
handle("history.undo", "rareload_restore", {}, function(ply)
    return History.Undo(ply) and "toast.undone" or "toast.nothing_to_undo"
end)
handle("history.reloadMode", "rareload_use_tool", { mode = "string:32", comps = "string:128?" }, function(ply, a)
    if not History.RELOAD_MODES[a.mode] then return end
    RARELOAD.Store.PData(ply, "reload", { mode = a.mode, comps = parseComps(a.comps) })
end)

RARELOAD.Net.Handle("object.get", {
    priv = "rareload_manage_objects", rate = 0.3, args = { entryId = "uint", objectId = "string:32" },
    fn = function(ply, a)
        local def = History.ObjectDef(ply, a.entryId, a.objectId)
        if def then
            RARELOAD.Net.Push(ply, "object.def", { entryId = a.entryId, objectId = a.objectId, json = util.TableToJSON(def, true) })
        end
    end,
})

RARELOAD.Net.Handle("history.objects", {
    priv = "rareload_restore", rate = 0.3, args = { id = "uint" },
    fn = function(ply, a) RARELOAD.Net.Push(ply, "history.objects", { id = a.id, objects = History.Objects(ply, a.id) }) end,
})

local function objectOp(op, args, fn)
    RARELOAD.Net.Handle(op, { priv = "rareload_manage_objects", rate = 0.2, args = args, fn = function(ply, a)
        local ok, err = fn(ply, a)
        if not ok then RARELOAD.Log("history"):warn("%s: %s failed: %s", ply:Nick(), op, tostring(err)) end
        RARELOAD.Net.Push(ply, "history.objects", { id = a.entryId, objects = History.Objects(ply, a.entryId) })
    end })
end

objectOp("object.delete", { entryId = "uint", objectId = "string:32" }, function(ply, a)
    return History.DeleteObject(ply, a.entryId, a.objectId)
end)
objectOp("object.flag", { entryId = "uint", objectId = "string:32", flag = "string:16", value = "bool" }, function(ply, a)
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
    return { nick = ply:Nick(), data = light, objects = History.Objects(ply, active.id) }
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
    timer.Create("Rareload.History.Push", 0.5, 1, function()
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
