-- Save history per player and map: the current save is simply the active entry. Timeline operations, undo, the tool's reload-key modes and edits of saved objects.

RARELOAD.History = RARELOAD.History or {}
local History = RARELOAD.History

local WORLD_KINDS = RARELOAD.WORLD_KINDS

History.COMPONENTS = RARELOAD.COMPONENTS

-- Returns the player's saves document (a new, unsaved one if they have none) and its storage path,
-- or nil for players without a stable ID. `ply` can also be a SteamID64: admins manage the saves of
-- players who are offline (A3). The functions below take either.
function History.Doc(ply)
    local key = isstring(ply) and (ply:match("^%d+$") and ply) or (not isstring(ply) and RARELOAD.Util.PlayerKey(ply))
    if not key then return nil end
    local rel = RARELOAD.Store.MapDir() .. "/" .. key
    local d = RARELOAD.Store.Load(rel) or { v = RARELOAD.Store.SCHEMA, sid64 = key, nextId = 1, entries = {} }
    return d, rel
end

local refresh -- pushes the new timeline and world display data, defined below

-- The only writer of a player's saves document. `quiet`: nothing the timeline shows changed
-- (checkpoints), so the timeline and world display aren't pushed again.
local function save(ply, d, quiet)
    local _, rel = History.Doc(ply)
    if not quiet then refresh(ply) end
    return RARELOAD.Store.Save(rel, d)
end

local function find(d, id)
    for i, entry in ipairs(d and d.entries or {}) do
        if entry.id == id then return entry, i end
    end
end

-- Entries never dropped to make room or by age: pinned ones, the respawn point and the quick slot.
-- (A death save may go; its id is then forgotten.)
local function kept(d, e)
    return e.pinned or e.id == d.activeId or e.id == d.quickId
end

-- After entries were removed: the quick slot and the death save point at an entry, or at nothing.
local function forgetMissing(d)
    if d.quickId and not find(d, d.quickId) then d.quickId = nil end
    if d.deathId and not find(d, d.deathId) then d.deathId = nil end
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

-- Adds a save and makes it active (unless opts.keepActive: an imported or shared save). The oldest
-- entries beyond `historySize` are dropped, except pinned ones and the active one.
-- opts = { keepActive? (not the respawn point), death? (the player's death save, D4) }
function History.Append(ply, entry, opts)
    local d = History.Doc(ply)
    if not d then return false end
    opts = opts or {}
    entry.id = d.nextId
    d.nextId = d.nextId + 1
    if not isstring(ply) and IsValid(ply) then d.nick = ply:Nick() end
    d.entries[#d.entries + 1] = entry
    if not (opts.keepActive and d.activeId) then d.activeId = entry.id end
    if opts.death then d.deathId = entry.id end

    local cap, i = RARELOAD.Get(ply, "historySize"), 1
    while #d.entries > cap and i <= #d.entries do
        local e = d.entries[i]
        if kept(d, e) or e.id == d.deathId then i = i + 1 else table.remove(d.entries, i) end
    end
    forgetMissing(d)
    return save(ply, d)
end

-- Makes an existing entry the player's death save (a death that changed nothing since a save).
function History.SetDeath(ply, id)
    local d = History.Doc(ply)
    if not d or not find(d, id) then return false end
    d.deathId = id
    return save(ply, d)
end

-- Deletes the entries older than `cutoff` (os.time) that History may drop; for Store.Prune. Returns
-- how many were deleted. The caller stores the document.
function History.PruneDoc(d, cutoff)
    local before = #d.entries
    for i = #d.entries, 1, -1 do
        local e = d.entries[i]
        if (tonumber(e.time) or 0) < cutoff and not kept(d, e) then table.remove(d.entries, i) end
    end
    forgetMissing(d)
    return before - #d.entries
end

-- The player's checkpoints (D7) are kept in the same document: fn(list) changes the list and
-- returns ok, ...; the document is stored when ok. Returns what fn returned.
function History.UpdateCheckpoints(ply, fn)
    local d = History.Doc(ply)
    if not d then return false end
    d.checkpoints = istable(d.checkpoints) and d.checkpoints or {}
    local result = table.Pack(fn(d.checkpoints))
    if result[1] then save(ply, d, true) end
    return unpack(result, 1, result.n)
end

-- A pinned save is never dropped when the timeline is full (History.Append); it can still be deleted by hand.
function History.SetPinned(ply, id, pinned)
    local d = History.Doc(ply)
    local entry = find(d, id)
    if not entry then return false end
    -- Pinned saves are never dropped, so their number is capped (A3).
    if pinned and not entry.pinned then
        local n = 0
        for _, e in ipairs(d.entries) do if e.pinned then n = n + 1 end end
        if n >= RARELOAD.Get(nil, "pinnedMax") then return false, "full" end
    end
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

-- Changes one entry: fn(entry) edits it in place, or returns false and why to leave it as it was.
function History.Update(ply, id, fn)
    local d = History.Doc(ply)
    local entry = find(d, id)
    if not entry then return false, "no such save" end
    local ok, err = fn(entry)
    if ok == false then return false, err end
    save(ply, d)
    return true
end

-- Deleting the active entry makes the newest remaining one active.
function History.Delete(ply, id)
    local d = History.Doc(ply)
    local _, i = find(d, id)
    if not i then return false end
    table.remove(d.entries, i)
    if d.activeId == id then d.activeId = d.entries[#d.entries] and d.entries[#d.entries].id or nil end
    forgetMissing(d)
    return save(ply, d)
end

-- Removes every entry except pinned ones, the active one and the quick slot.
function History.Clear(ply)
    local d = History.Doc(ply)
    if not d then return false end
    local left = {}
    for _, e in ipairs(d.entries) do
        if kept(d, e) then left[#left + 1] = e end
    end
    d.entries = left
    forgetMissing(d)
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

local undos = setmetatable({}, { __mode = "k" }) -- ply -> { entry, only, world, ctx }; one level, like v4

-- comps: a set of component names (§15.4), or nil for everything. Returns the module set or nil.
function History.ModulesFor(comps)
    if not comps then return nil end
    local only = {}
    for comp in pairs(comps) do
        for _, id in ipairs(History.COMPONENTS[comp] or {}) do only[id] = true end
    end
    return only
end

-- Restores an entry now (F25). The current state of the same modules is captured first, for undo
-- (F26), the player's objects included when the world is restored. opts = { exact? = also remove
-- the player's objects the save doesn't hold }. Saved objects still on the map are put back the way
-- they were saved when the player's resetObjects setting is on, or for an exact restore.
function History.Restore(ply, id, comps, opts)
    local entry = History.Get(ply, id)
    if not entry then return false end
    return History.RestoreEntry(ply, entry, comps, opts)
end

-- Restores any entry (a save, or a server snapshot's part for this player, D9) the way the timeline
-- does, with undo. opts.admin: an admin's rollback, which the player's own rules (PvP) don't refuse.
function History.RestoreEntry(ply, entry, comps, opts)
    if not ply:Alive() then return false end
    opts = opts or {}
    -- Rules for the whole restore (PvP cooldowns, other addons). A rule may name its own toast.
    local veto, why
    if not opts.admin then veto, why = hook.Run("RareloadCanRestore", ply, "timeline") end
    if veto == false then
        if istable(why) and why.toast then RARELOAD.Toast(ply, why.toast, why.args, "error") end
        return false
    end
    local only = History.ModulesFor(comps)

    local undoOnly, world = History.ModulesFor(comps or History.COMPONENTS), not comps or comps.world == true
    local _, _, snapshot = RARELOAD.Pipeline.Save(ply, { only = undoOnly, captureOnly = true, silent = true })

    local ctx = RARELOAD.Pipeline.Restore(ply, entry, {
        only = only,
        reason = opts.reason or "timeline",
        exact = opts.exact and world,
        reset = RARELOAD.Get(ply, "resetObjects"),
    })
    undos[ply] = { entry = snapshot, only = undoOnly, world = world, ctx = ctx }
    refresh(ply) -- the timeline should now show Undo button being active
    return true
end

-- Puts the player back the way they were before the last restore: what it created is removed (even
-- vehicles that finished spawning later, E14), and their objects are restored exactly as captured
-- (moved ones put back, removed ones pasted again, new ones removed).
function History.Undo(ply)
    local u = undos[ply]
    if not u then return false end
    undos[ply] = nil
    refresh(ply)
    for _, ent in ipairs(u.ctx.spawned) do
        if IsValid(ent) then ent:Remove() end
    end
    if u.entry then
        RARELOAD.Pipeline.Restore(ply, u.entry, { only = u.only, reason = "undo", reset = true, exact = u.world })
    end
    return true
end

-- Reload key (F28) --------------------------------------------------------------------------------

History.RELOAD_MODES = {}
for _, mode in ipairs(RARELOAD.RELOAD_MODES) do History.RELOAD_MODES[mode] = true end

function History.ReloadConfig(ply)
    local cfg = RARELOAD.Store.PData(ply, "reload")
    if not istable(cfg) or not History.RELOAD_MODES[cfg.mode] then cfg = { mode = RARELOAD.RELOAD_MODES[1] } end
    return cfg
end

-- comps: as History.ParseComps returns. Returns false for an unknown mode.
function History.SetReloadConfig(ply, mode, comps)
    if not History.RELOAD_MODES[mode] then return false end
    RARELOAD.Store.PData(ply, "reload", { mode = mode, comps = comps })
    return true
end

-- Returns a toast key describing the outcome, and the number of the save it's about.
function History.ReloadKey(ply)
    local cfg = History.ReloadConfig(ply)
    local comps = cfg.comps and next(cfg.comps) and cfg.comps or nil
    local active, previous = History.Active(ply), History.Previous(ply)
    if not active then return "toast.reload.empty" end

    -- A refused restore has already told the player why.
    if cfg.mode == "restore_current" then
        if not History.Restore(ply, active.id, comps) then return nil end
        return "toast.reload.restored", active.id
    end
    if not previous then return "toast.reload.no_previous" end
    if cfg.mode == "restore_previous" and not History.Restore(ply, previous.id, comps) then return nil end
    History.Activate(ply, previous.id) -- walking back one save at a time
    return cfg.mode == "restore_previous" and "toast.reload.restored" or "toast.reload.previous", previous.id
end

-- Quick keys and commands (5.4 plan, D3) ---------------------------------------------------------------
-- The quick slot is a save like any other (it becomes the respawn point too); the document remembers
-- which one it is, so quickload finds it even after more saves were made. Each function tells the
-- player how it went and returns whether it did something.

function History.Quick(ply)
    local d = History.Doc(ply)
    return d and d.quickId and (find(d, d.quickId)) or nil
end

function History.QuickSave(ply)
    if not RARELOAD.Pipeline.Save(ply, { reason = "quick" }) then return false end
    local d, active = History.Doc(ply), History.Active(ply)
    if not d or not active then return false end
    d.quickId = active.id
    save(ply, d)
    return true
end

local function restoreAndTell(ply, entry, comps)
    if not ply:Alive() then
        RARELOAD.Toast(ply, "toast.restore_dead", nil, "error")
        return false
    end
    if not History.Restore(ply, entry.id, comps) then return false end
    RARELOAD.Toast(ply, "toast.restored", { entry.id }, "ok")
    return true
end

function History.QuickLoad(ply)
    local quick = History.Quick(ply)
    if not quick then
        RARELOAD.Toast(ply, "toast.quick_empty", nil, "error")
        return false
    end
    return restoreAndTell(ply, quick)
end

-- Restores the respawn point now. comps: as History.Restore.
function History.RestoreActive(ply, comps)
    local active = History.Active(ply)
    if not active then
        RARELOAD.Toast(ply, "toast.reload.empty", nil, "error")
        return false
    end
    return restoreAndTell(ply, active, comps)
end

-- Restores the save before the respawn point, which becomes the respawn point.
function History.Back(ply)
    local previous = History.Previous(ply)
    if not previous then
        RARELOAD.Toast(ply, History.Active(ply) and "toast.reload.no_previous" or "toast.reload.empty", nil, "error")
        return false
    end
    if not restoreAndTell(ply, previous) then return false end
    History.Activate(ply, previous.id)
    return true
end

-- The quick keys (cl_keys.lua): the server sees each key press once, from the player's commands, and
-- never while they type in a menu or the chat.
-- Checkpoint keys (D7): a new checkpoint here, and cycling through checkpoints from the last one.
local function checkpointKey(fn)
    return function(ply)
        local ok, key, args = fn(ply)
        if key then RARELOAD.Toast(ply, key, args, ok and "ok" or "error") end
    end
end
local KEYS = {
    cl_rareload_key_save = { fn = History.QuickSave },
    cl_rareload_key_load = { fn = History.QuickLoad, priv = "rareload_restore" },
    cl_rareload_key_checkpoint = { fn = checkpointKey(function(ply) return RARELOAD.Checkpoints.Add(ply) end),
        priv = "rareload_checkpoints", cooldown = 0.25 },
    cl_rareload_key_checkpoint_go = { fn = checkpointKey(function(ply) return RARELOAD.Checkpoints.Cycle(ply) end),
        priv = "rareload_checkpoints", cooldown = 0.15 },
}
local lastKey = setmetatable({}, { __mode = "k" })

hook.Add("PlayerButtonDown", "Rareload.QuickKeys", function(ply, button)
    if ply:IsBot() then return end
    for convar, k in pairs(KEYS) do
        if button ~= 0 and ply:GetInfoNum(convar, 0) == button then
            if CurTime() - (lastKey[ply] or -math.huge) < (k.cooldown or 1) then return end
            lastKey[ply] = CurTime()
            if not RARELOAD.Can(ply, "rareload_use_tool") then return end
            if k.priv and not RARELOAD.Can(ply, k.priv) then return end
            k.fn(ply)
            return
        end
    end
end)

-- Objects inside saves (F29) ----------------------------------------------------------------------

-- A snapshot's per-object table (ai, runtime) by object id: JSON may have turned an all-digit id key
-- into a number.
local function byObjectId(map, id)
    return istable(map) and id and (map[id] or map[tonumber(id)]) or nil
end

-- What the inspector, the timeline preview and the world display show about one saved object.
-- `snap` gives the NPC AI state and vehicle runtime kept next to the duplicator data.
local function objectInfo(def, kind, snap)
    local mods = istable(def.EntityMods) and def.EntityMods or {}
    local phys = istable(def.PhysicsObjects) and (def.PhysicsObjects[0] or def.PhysicsObjects["0"]) or {}
    local rl = istable(mods.rareload) and mods.rareload or {}
    local id = RARELOAD.Snapshot.DefID(def)
    local runtime, ai = byObjectId(snap.runtime, id), byObjectId(snap.ai, id)
    return {
        id = id,
        num = rl.num,   -- kept for life, shown after the name when another object shares it
        name = rl.name, -- the player's own name for it
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
function History.ObjectsOf(entry)
    local out = {}
    eachObject(entry, function(def, kind, snap) out[#out + 1] = objectInfo(def, kind, snap) end)
    return out
end

function History.Objects(ply, id)
    return History.ObjectsOf(History.Get(ply, id))
end

-- Constraint settings worth showing: plain values, without the ends (shown as names) and the type.
local function constraintSettings(c)
    local out = {}
    for k, v in pairs(c) do
        if isstring(k) and (isnumber(v) or isbool(v) or isstring(v)) and k ~= "Type"
            and not string.match(k, "^Bone%d?$") and not string.match(k, "^Ent%d$") then
            out[k] = v
        end
    end
    return out
end

-- What a saved object is attached to: { { type, to = { { world = true } | { id, class, model } },
-- set = { setting = value } } }. Read from the constraints module (every constraint between saved
-- objects) and, for saves made before it held them all, from the snapshots.
local function objectConstraints(entry, objectId)
    local DefID = RARELOAD.Snapshot.DefID
    local me, objects = tostring(objectId), {}
    eachObject(entry, function(def)
        local id = DefID(def)
        if id then
            local rl = def.EntityMods.rareload
            objects[tostring(id)] = { id = id, class = def.Class, model = def.Model, num = rl.num, name = rl.name }
        end
    end)

    local out, seen = {}, {}
    local function add(c, ids)
        local to, own, list = {}, false, {}
        for _, id in pairs(ids) do
            id = tostring(id)
            list[#list + 1] = id
            if id == me and not own then
                own = true
            else
                to[#to + 1] = id == "world" and { world = true } or objects[id] or { id = id }
            end
        end
        if not own then return end
        table.sort(list)
        local key = tostring(c.Type) .. "|" .. table.concat(list, "|")
        if (seen[key] or 0) > 0 then
            seen[key] = seen[key] - 1 -- the same constraint, already listed from the other source
            return
        end
        out[#out + 1] = { type = c.Type, to = to, set = constraintSettings(c), key = key }
    end

    local list = RARELOAD.Pipeline.Payload(entry.data.constraints)
    for _, saved in ipairs(istable(list) and list or {}) do add(saved.def, saved.ids) end
    for _, o in ipairs(out) do seen[o.key] = (seen[o.key] or 0) + 1 end
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = RARELOAD.Pipeline.Payload(entry.data[kind])
        for _, c in pairs(snap and snap.Constraints or {}) do
            if istable(c) and c.Type and istable(c.Entity) then
                local ids, known = {}, true
                for i, e in pairs(c.Entity) do
                    local def = snap.Entities[e.Index] or snap.Entities[tostring(e.Index)]
                    ids[i] = e.World and "world" or def and DefID(def)
                    known = known and ids[i] ~= nil
                end
                if known then add(c, ids) end
            end
        end
    end
    for _, o in ipairs(out) do o.key = nil end
    return #out > 0 and out or nil
end

-- The full saved definition of one object, with its NPC AI state and vehicle runtime, or nil.
function History.ObjectDetail(entry, objectId)
    return eachObject(entry, function(def, _, snap)
        if RARELOAD.Snapshot.DefID(def) == objectId then
            return {
                def = def,
                constraints = objectConstraints(entry, objectId),
                ai = byObjectId(snap.ai, objectId),
                runtime = byObjectId(snap.runtime, objectId),
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

-- Deletes objects (ids = { [objectId] = true }): each snapshot is copied and stored once, not once per object.
local function deleteObjects(ply, entryId, ids)
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

History.DeleteObjects = deleteObjects

-- One object (logged as such, so not through the logged History.DeleteObjects).
function History.DeleteObject(ply, entryId, objectId)
    return deleteObjects(ply, entryId, { [objectId] = true })
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

-- The player's own name for a saved object ("" removes it). An object still on the map takes it
-- too, so later saves keep it.
function History.RenameObject(ply, entryId, objectId, name)
    name = string.Trim(name)
    name = name ~= "" and name or nil
    local ok, err = changeObject(ply, entryId, objectId, function(def)
        def.EntityMods.rareload.name = name
        return true
    end)
    if not ok then return false, err end
    for _, ent in ents.Iterator() do
        if ent.RareloadID and tostring(ent.RareloadID) == tostring(objectId) then ent.RareloadName = name end
    end
    return true
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

-- An entry's player modules light enough to send with every update (not the world, nothing heavy):
-- what the world display's player panel shows, for the respawn point and for a previewed save alike.
function History.LightData(entry)
    local light = {}
    for id, value in pairs(entry and entry.data or {}) do
        local def = RARELOAD.Pipeline.Def(id)
        if def and not def.heavy and def.phase ~= "world" then light[id] = value end
    end
    return light
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

-- Admins looking at another player's timeline (A3): admin -> SteamID64.
History._viewing = History._viewing or setmetatable({}, { __mode = "k" })
local viewing = History._viewing

local function pushRows(ply)
    local key = viewing[ply]
    if key then
        RARELOAD.Net.Push(ply, "history", { rows = History.Rows(key), reload = {}, undo = false, target = key })
        return
    end
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
-- Every operation can name another player (`sid`): admins with rareload_manage_saves act on their
-- saves (A3), online or not, and each such action is logged. fn(target, a, actor), where target is
-- the player when online, else their SteamID64.
local MANAGE = "rareload_manage_saves"

local function targetFor(ply, sid)
    if not sid or sid == "" or sid == ply:SteamID64() then return ply end
    if not RARELOAD.Can(ply, MANAGE) or not sid:match("^%d+$") then return nil end
    return player.GetBySteamID64(sid) or sid
end

local function nameOf(target)
    if not isstring(target) then return target:Nick() end
    local d = History.Doc(target)
    return (d and d.nick or "?") .. " (" .. target .. ")"
end

local function handle(op, priv, args, fn)
    args.sid = "string:20?"
    RARELOAD.Net.Handle(op, {
        priv = priv,
        rate = 0.2,
        args = args,
        fn = function(ply, a)
            local target = targetFor(ply, a.sid)
            if not target then return end
            local key, targs = fn(target, a, ply)
            if key then RARELOAD.Toast(ply, key, targs) end
            if target ~= ply and op ~= "history.get" then
                RARELOAD.Log("admin", ply):info("%s: %s, save No. %s of %s", ply:Nick(), op, tostring(a.id or "-"),
                    nameOf(target))
            end
            pushRows(ply)
        end
    })
end

-- Which timeline the player looks at: their own, or (admins) another player's.
handle("history.get", "rareload_restore", {}, function(target, _, ply)
    viewing[ply] = target ~= ply and (isstring(target) and target or target:SteamID64()) or nil
end)
handle("history.pin", "rareload_restore", { id = "uint", pinned = "bool" }, function(ply, a)
    local _, why = History.SetPinned(ply, a.id, a.pinned)
    if why == "full" then return "toast.pin_full", { RARELOAD.Get(nil, "pinnedMax") } end
end)
handle("history.note", "rareload_restore", { id = "uint", note = "string:256" },
    function(ply, a) History.SetNote(ply, a.id, a.note) end)
-- "Place here…" (D6): moves where the save respawns the player; the rest of the save stays as it is.
handle("history.move", "rareload_save", { id = "uint", x = "number", y = "number", z = "number", yaw = "number" },
    function(ply, a)
        local pos = Vector(a.x, a.y, a.z)
        if not util.IsInWorld(pos + Vector(0, 0, 16)) then return "toast.place_outside" end
        local ok = History.Update(ply, a.id, function(e)
            local t = istable(e.data.transform) and e.data.transform or {}
            t.pos, t.ang = RARELOAD.Util.Vec(pos), RARELOAD.Util.Ang(Angle(0, a.yaw % 360, 0))
            t.crouched, t.mapVersion = nil, game.GetMapVersion()
            e.data.transform = t
        end)
        if ok then return "toast.placed", { a.id } end
    end)
handle("history.delete", "rareload_restore", { id = "uint" }, function(ply, a) History.Delete(ply, a.id) end)
handle("history.clear", "rareload_restore", {}, function(ply) History.Clear(ply) end)
handle("history.activate", "rareload_restore", { id = "uint" }, function(ply, a)
    if History.Activate(ply, a.id) then return "toast.activated", { a.id } end
end)
handle("history.restore", "rareload_restore", { id = "uint", comps = "string:128?", exact = "bool?" },
    function(ply, a)
        if isstring(ply) then return "toast.admin_offline" end -- restoring needs the player in game
        if not ply:Alive() then return "toast.restore_dead" end
        if History.Restore(ply, a.id, parseComps(a.comps), { exact = a.exact }) then
            return "toast.restored", { a.id }
        end
    end)
handle("history.undo", "rareload_restore", {}, function(ply)
    if isstring(ply) then return "toast.nothing_to_undo" end
    return History.Undo(ply) and "toast.undone" or "toast.nothing_to_undo"
end)
handle("history.reloadMode", "rareload_use_tool", { mode = "string:32", comps = "string:128?" }, function(ply, a)
    if isstring(ply) then return end
    History.SetReloadConfig(ply, a.mode, parseComps(a.comps))
end)

RARELOAD.Net.Handle("history.players", {
    priv = MANAGE,
    rate = 1,
    fn = function(ply)
        local list, seen = {}, {}
        for _, p in player.Iterator() do
            if not p:IsBot() then
                local sid = p:SteamID64()
                local d = History.Doc(p)
                seen[sid] = true
                list[#list + 1] = { sid = sid, nick = p:Nick(), online = true, saves = d and #d.entries or 0 }
            end
        end
        local dir = RARELOAD.Store.MapDir()
        for _, name in ipairs(file.Find("rareload/" .. dir .. "/*.json", "DATA") or {}) do
            local sid = name:match("^(%d+)%.json$")
            if sid and not seen[sid] then
                local d = History.Doc(sid)
                if d and #d.entries > 0 then
                    list[#list + 1] = { sid = sid, nick = d.nick or sid, online = false, saves = #d.entries }
                end
            end
        end
        RARELOAD.Net.Push(ply, "history.players", { list = list })
    end,
})

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
            if not IsValid(owner) then return end
            if not RARELOAD.Get(nil, "debug") or not RARELOAD.Can(ply, "rareload_debug") then return end
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

-- A save's objects, with its light player data for the timeline preview.
local function pushObjects(ply, id)
    RARELOAD.Net.Push(ply, "history.objects",
        { id = id, objects = History.Objects(ply, id), data = History.LightData(History.Get(ply, id)) })
end

RARELOAD.Net.Handle("history.objects", {
    priv = "rareload_restore",
    rate = 0.3,
    args = { id = "uint" },
    fn = function(ply, a) pushObjects(ply, a.id) end,
})

local function objectOp(op, args, fn, priv)
    RARELOAD.Net.Handle(op, {
        priv = priv or "rareload_manage_objects",
        rate = 0.2,
        args = args,
        fn = function(ply, a)
            local ok, err = fn(ply, a)
            if not ok then RARELOAD.Log("history", ply):warn("%s: %s failed: %s", ply:Nick(), op, tostring(err)) end
            pushObjects(ply, a.entryId)
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
-- Naming your own saved objects needs no more than seeing them.
objectOp("object.rename", { entryId = "uint", objectId = "string:32", name = "string:48" }, function(ply, a)
    return History.RenameObject(ply, a.entryId, a.objectId, a.name)
end, "rareload_restore")
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
    return {
        nick = ply:Nick(),
        data = History.LightData(active),
        objects = History.ObjectsOf(active),
        seated = History.Info(active.data).vehicle ~= nil
    }
end

local function pushFeed(ply, targets)
    targets = targets or subscribers()
    if #targets == 0 then return end
    local sid = ply:SteamID64()
    RARELOAD.Net.Push(targets, "saves", { sid = sid, save = feedFor(ply) }, { key = "saves:" .. sid })
end

local changed, changedKeys = {}, {}

-- Called on every change of a saves document (`ply` may be a SteamID64); the pushes wait until the
-- changes settle. Admins looking at that player's timeline get it too.
refresh = function(ply)
    local key = isstring(ply) and ply or RARELOAD.Util.PlayerKey(ply)
    local online = isstring(ply) and player.GetBySteamID64(ply) or ply
    if IsValid(online) then changed[online] = true end
    if key then changedKeys[key] = true end
    if timer.Exists("Rareload.History.Push") then return end
    timer.Create("Rareload.History.Push", 0.1, 1, function()
        for p in pairs(changed) do
            if IsValid(p) then
                pushRows(p)
                pushFeed(p)
            end
        end
        for admin, sid in pairs(viewing) do
            if IsValid(admin) and changedKeys[sid] and not changed[admin] then pushRows(admin) end
        end
        changed, changedKeys = {}, {}
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

-- Activity log -----------------------------------------------------------------------------------------
-- One line for each change to a timeline or to an object inside a save, from the window or the console.

local function logged(name, level, describe)
    local fn = History[name]
    History[name] = function(ply, ...)
        local results = { fn(ply, ...) }
        if results[1] and IsValid(ply) then
            local log = RARELOAD.Log("timeline", ply)
            log[level](log, describe(ply, ...))
        end
        return unpack(results)
    end
end

local function idList(ids)
    local n = 0
    for _ in pairs(ids or {}) do n = n + 1 end
    return n
end

logged("Delete", "info", function(ply, id) return ply:Nick() .. " deleted save No. " .. tostring(id) end)
logged("Clear", "info", function(ply)
    return ply:Nick() .. " cleared their saves on this map (pinned saves and the respawn point kept)"
end)
logged("Activate", "info", function(ply, id)
    return ply:Nick() .. " made save No. " .. tostring(id) .. " their respawn point"
end)
logged("Undo", "info", function(ply) return ply:Nick() .. " undid their last restore" end)
logged("SetPinned", "verbose", function(ply, id, pinned)
    return ply:Nick() .. (pinned and " pinned" or " unpinned") .. " save No. " .. tostring(id)
end)
logged("SetNote", "verbose", function(ply, id)
    return ply:Nick() .. " changed the note of save No. " .. tostring(id)
end)
logged("DeleteObject", "info", function(ply, entryId, objectId)
    return string.format("%s removed object %s from save No. %s", ply:Nick(), tostring(objectId), tostring(entryId))
end)
logged("DeleteObjects", "info", function(ply, entryId, ids)
    return string.format("%s removed %d objects from save No. %s", ply:Nick(), idList(ids), tostring(entryId))
end)
logged("FlagObject", "info", function(ply, entryId, objectId, flag, value)
    return string.format("%s turned %s %s on object %s in save No. %s", ply:Nick(), tostring(flag),
        value and "on" or "off", tostring(objectId), tostring(entryId))
end)
logged("RenameObject", "verbose", function(ply, entryId, objectId, name)
    return string.format("%s named object %s in save No. %s \"%s\"", ply:Nick(), tostring(objectId),
        tostring(entryId), tostring(name))
end)
logged("EditObject", "info", function(ply, entryId, objectId, edit)
    local keys = table.GetKeys(istable(edit) and edit or {})
    table.sort(keys)
    return string.format("%s edited object %s in save No. %s (%s)", ply:Nick(), tostring(objectId),
        tostring(entryId), table.concat(keys, ", "))
end)
