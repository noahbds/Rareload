-- Save history per player and map: the current save is simply the active entry. Timeline operations, undo, the tool's
-- reload-key modes and edits of saved objects.

RARELOAD.History = RARELOAD.History or {}
local History = RARELOAD.History

local WORLD_KINDS = RARELOAD.WORLD_KINDS

History.COMPONENTS = RARELOAD.COMPONENTS

-- Returns the player's saves document (a new, unsaved one if they have none) and its storage path,
-- or nil for players without a stable ID. `ply` can also be a SteamID64: admins manage the saves of
-- players who are offline (A3). The functions below take either.
-- A document read from disk is given its parts once (a hand-edited or old file may lack them), so the
-- code below never checks for them: entries and checkpoints are lists, every entry has its data.
local normalized = setmetatable({}, { __mode = "k" })
local function normalize(doc)
    if normalized[doc] then return doc end
    doc.entries = istable(doc.entries) and doc.entries or {}
    doc.checkpoints = istable(doc.checkpoints) and doc.checkpoints or {}
    for _, entry in ipairs(doc.entries) do
        if not istable(entry.data) then entry.data = {} end
    end
    normalized[doc] = true
    return doc
end

function History.Doc(ply)
    local key = isstring(ply) and (ply:match("^%d+$") and ply) or (not isstring(ply) and RARELOAD.Util.PlayerKey(ply))
    if not key then return nil end
    local rel = RARELOAD.Store.MapDir() .. "/" .. key
    local doc = RARELOAD.Store.Load(rel)
    doc = doc and normalize(doc) or normalize({ v = RARELOAD.Store.SCHEMA, sid64 = key, nextId = 1 })
    return doc, rel
end

local refresh -- pushes the new timeline and world display data, defined below

-- The only writer of a player's saves document. `quiet`: nothing the timeline shows changed
-- (checkpoints), so the timeline and world display aren't pushed again.
local function save(ply, doc, quiet)
    local _, rel = History.Doc(ply)
    if not quiet then refresh(ply) end
    return RARELOAD.Store.Save(rel, doc)
end

local function find(doc, id)
    for i, entry in ipairs(doc and doc.entries or {}) do
        if entry.id == id then return entry, i end
    end
end

-- Entries never dropped to make room or by age: pinned ones, the respawn point and the quick slot.
-- (A death save may go; its id is then forgotten.)
local function kept(doc, entry)
    return entry.pinned or entry.id == doc.activeId or entry.id == doc.quickId
end

-- After entries were removed: the quick slot and the death save point at an entry, or at nothing.
local function forgetMissing(doc)
    if doc.quickId and not find(doc, doc.quickId) then doc.quickId = nil end
    if doc.deathId and not find(doc, doc.deathId) then doc.deathId = nil end
end

function History.Get(ply, id)
    return (find(History.Doc(ply), id))
end

function History.Active(ply)
    local doc = History.Doc(ply)
    return doc and doc.activeId and (find(doc, doc.activeId)) or nil
end

-- The entry saved just before the active one (for the reload key).
function History.Previous(ply)
    local doc = History.Doc(ply)
    local _, i = find(doc, doc and doc.activeId)
    return i and doc.entries[i - 1] or nil
end

-- Adds a save and makes it active (unless opts.keepActive: an imported or shared save). The oldest
-- entries beyond `historySize` are dropped, except pinned ones and the active one.
-- opts = { keepActive? (not the respawn point), death? (the player's death save, D4) }
function History.Append(ply, entry, opts)
    local doc = History.Doc(ply)
    if not doc then return false end
    opts = opts or {}
    entry.id = doc.nextId
    doc.nextId = doc.nextId + 1
    if not isstring(ply) and IsValid(ply) then doc.nick = ply:Nick() end
    doc.entries[#doc.entries + 1] = entry
    if not (opts.keepActive and doc.activeId) then doc.activeId = entry.id end
    if opts.death then doc.deathId = entry.id end

    local cap, i = RARELOAD.Get(ply, "historySize"), 1
    while #doc.entries > cap and i <= #doc.entries do
        local oldEntry = doc.entries[i]
        if kept(doc, oldEntry) or oldEntry.id == doc.deathId then i = i + 1 else table.remove(doc.entries, i) end
    end
    forgetMissing(doc)
    return save(ply, doc)
end

-- Makes an existing entry the player's death save (a death that changed nothing since a save).
function History.SetDeath(ply, id)
    local doc = History.Doc(ply)
    if not doc or not find(doc, id) then return false end
    doc.deathId = id
    return save(ply, doc)
end

-- Deletes the entries older than `cutoff` (os.time) that History may drop; for Store.Prune. Returns
-- how many were deleted. The caller stores the document.
function History.PruneDoc(doc, cutoff)
    local before = #doc.entries
    for i = #doc.entries, 1, -1 do
        local entry = doc.entries[i]
        if (tonumber(entry.time) or 0) < cutoff and not kept(doc, entry) then table.remove(doc.entries, i) end
    end
    forgetMissing(doc)
    return before - #doc.entries
end

-- The player's checkpoints (D7) are kept in the same document: fn(list) changes the list and
-- returns ok, ...; the document is stored when ok. Returns what fn returned.
function History.UpdateCheckpoints(ply, fn)
    local doc = History.Doc(ply)
    if not doc then return false end
    local result = table.Pack(fn(doc.checkpoints))
    if result[1] then save(ply, doc, true) end
    return unpack(result, 1, result.n)
end

-- A pinned save is never dropped when the timeline is full (History.Append); it can still be deleted by hand.
function History.SetPinned(ply, id, pinned)
    local doc = History.Doc(ply)
    local entry = find(doc, id)
    if not entry then return false end
    -- Pinned saves are never dropped, so their number is capped (A3).
    if pinned and not entry.pinned then
        local pinnedCount = 0
        for _, other in ipairs(doc.entries) do if other.pinned then pinnedCount = pinnedCount + 1 end end
        if pinnedCount >= RARELOAD.Get(nil, "pinnedMax") then return false, "full" end
    end
    entry.pinned = pinned or nil
    return save(ply, doc)
end

-- Give the ability to set a note to a save, so the player can remember what was saved in that save.
-- Not really useful in a sense but it's there.
function History.SetNote(ply, id, note)
    local doc = History.Doc(ply)
    local entry = find(doc, id)
    if not entry then return false end
    entry.note = note ~= "" and note or nil
    return save(ply, doc)
end

-- Changes one entry: fn(entry) edits it in place, or returns false and why to leave it as it was.
function History.Update(ply, id, fn)
    local doc = History.Doc(ply)
    local entry = find(doc, id)
    if not entry then return false, "no such save" end
    local ok, err = fn(entry)
    if ok == false then return false, err end
    save(ply, doc)
    return true
end

-- Deleting the active entry makes the newest remaining one active.
function History.Delete(ply, id)
    local doc = History.Doc(ply)
    local _, i = find(doc, id)
    if not i then return false end
    table.remove(doc.entries, i)
    if doc.activeId == id then doc.activeId = doc.entries[#doc.entries] and doc.entries[#doc.entries].id or nil end
    forgetMissing(doc)
    return save(ply, doc)
end

-- Removes every entry except pinned ones, the active one and the quick slot.
function History.Clear(ply)
    local doc = History.Doc(ply)
    if not doc then return false end
    local left = {}
    for _, entry in ipairs(doc.entries) do
        if kept(doc, entry) then left[#left + 1] = entry end
    end
    doc.entries = left
    forgetMissing(doc)
    return save(ply, doc)
end

-- Makes an entry the respawn point (F24).
function History.Activate(ply, id)
    local doc = History.Doc(ply)
    if not find(doc, id) then return false end
    doc.activeId = id
    return save(ply, doc)
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
    local undo = undos[ply]
    if not undo then return false end
    undos[ply] = nil
    refresh(ply)
    for _, ent in ipairs(undo.ctx.spawned) do
        if IsValid(ent) then ent:Remove() end
    end
    if undo.entry then
        RARELOAD.Pipeline.Restore(ply, undo.entry,
            { only = undo.only, reason = "undo", reset = true, exact = undo.world })
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
    local doc = History.Doc(ply)
    return doc and doc.quickId and (find(doc, doc.quickId)) or nil
end

function History.QuickSave(ply)
    if not RARELOAD.Pipeline.Save(ply, { reason = "quick" }) then return false end
    local doc, active = History.Doc(ply), History.Active(ply)
    if not doc or not active then return false end
    doc.quickId = active.id
    save(ply, doc)
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
    for convar, keyDef in pairs(KEYS) do
        if button ~= 0 and ply:GetInfoNum(convar, 0) == button then
            if CurTime() - (lastKey[ply] or -math.huge) < (keyDef.cooldown or 1) then return end
            lastKey[ply] = CurTime()
            if not RARELOAD.Can(ply, "rareload_use_tool") then return end
            if keyDef.priv and not RARELOAD.Can(ply, keyDef.priv) then return end
            keyDef.fn(ply)
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
local function objectInfo(entityDef, kind, snap)
    local Snapshot = RARELOAD.Snapshot
    local mods, rl, bones = Snapshot.Mods(entityDef), Snapshot.Rareload(entityDef), Snapshot.Bones(entityDef)
    local phys = bones[0] or bones["0"] or {}
    local id = RARELOAD.Snapshot.DefID(entityDef)
    local runtime, ai = byObjectId(snap.runtime, id), byObjectId(snap.ai, id)
    return {
        id = id,
        num = rl.num,   -- kept for life, shown after the name when another object shares it
        name = rl.name, -- the player's own name for it
        kind = kind,
        class = entityDef.Class,
        model = entityDef.Model,
        skin = entityDef.Skin,
        pos = isvector(entityDef.Pos) and RARELOAD.Util.Vec(entityDef.Pos) or nil,
        ang = isangle(entityDef.Angle) and RARELOAD.Util.Ang(entityDef.Angle) or nil,
        frozen = phys.Frozen or nil,
        nograv = phys.NoGrav or nil,
        hp = rl.hp,
        maxHp = (tonumber(rl.hp) or 0) > 0 and rl.maxHp or nil,
        scale = entityDef.ModelScale,
        bodygroups = entityDef.BodyG,
        material = istable(mods.material) and mods.material.MaterialOverride or nil,
        color = istable(mods.colour) and mods.colour.Color or nil, -- tagged { __color = { r, g, b, a } }
        base = runtime and runtime.adapter,
        parts = runtime and runtime.parts,
        squad = ai and ai.squad,
        npcState = ai and ai.state,
    }
end

-- Calls fn(entityDef, kind, snap) for every saved object of an entry until fn returns a value.
local function eachObject(entry, fn)
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = entry and RARELOAD.Pipeline.Payload(entry.data[kind])
        for _, entityDef in pairs(snap and snap.Entities or {}) do
            local result = fn(entityDef, kind, snap)
            if result ~= nil then return result end
        end
    end
end

-- Every saved object of an entry.
function History.ObjectsOf(entry)
    local out = {}
    eachObject(entry, function(entityDef, kind, snap) out[#out + 1] = objectInfo(entityDef, kind, snap) end)
    return out
end

function History.Objects(ply, id)
    return History.ObjectsOf(History.Get(ply, id))
end

-- Constraint settings worth showing: plain values, without the ends (shown as names) and the type.
local function constraintSettings(constraintData)
    local out = {}
    for key, value in pairs(constraintData) do
        if isstring(key) and (isnumber(value) or isbool(value) or isstring(value)) and key ~= "Type"
            and not string.match(key, "^Bone%d?$") and not string.match(key, "^Ent%d$") then
            out[key] = value
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
    eachObject(entry, function(entityDef)
        local id = DefID(entityDef)
        if id then
            local rl = entityDef.EntityMods.rareload
            objects[tostring(id)] = { id = id, class = entityDef.Class, model = entityDef.Model, num = rl.num,
                name = rl.name }
        end
    end)

    local out, seen = {}, {}
    local function add(constraintData, ids)
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
        local key = tostring(constraintData.Type) .. "|" .. table.concat(list, "|")
        if (seen[key] or 0) > 0 then
            seen[key] = seen[key] - 1 -- the same constraint, already listed from the other source
            return
        end
        out[#out + 1] = { type = constraintData.Type, to = to, set = constraintSettings(constraintData), key = key }
    end

    local list = RARELOAD.Pipeline.Payload(entry.data.constraints)
    for _, saved in ipairs(istable(list) and list or {}) do add(saved.def, saved.ids) end
    for _, info in ipairs(out) do seen[info.key] = (seen[info.key] or 0) + 1 end
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = RARELOAD.Pipeline.Payload(entry.data[kind])
        for _, constraintData in pairs(snap and snap.Constraints or {}) do
            if istable(constraintData) and constraintData.Type and istable(constraintData.Entity) then
                local ids, known = {}, true
                for i, endpoint in pairs(constraintData.Entity) do
                    local entityDef = snap.Entities[endpoint.Index] or snap.Entities[tostring(endpoint.Index)]
                    ids[i] = endpoint.World and "world" or entityDef and DefID(entityDef)
                    known = known and ids[i] ~= nil
                end
                if known then add(constraintData, ids) end
            end
        end
    end
    for _, info in ipairs(out) do info.key = nil end
    return #out > 0 and out or nil
end

-- The full saved definition of one object, with its NPC AI state and vehicle runtime, or nil.
function History.ObjectDetail(entry, objectId)
    return eachObject(entry, function(entityDef, _, snap)
        if RARELOAD.Snapshot.DefID(entityDef) == objectId then
            return {
                def = entityDef,
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
function History.ValidateEdit(entityDef, edit, isAdmin)
    if not istable(edit) then return false, "the edit is not a table" end
    for key, value in pairs(edit) do
        if entityDef[key] == nil then return false, "unknown key " .. tostring(key) end
        if type(entityDef[key]) ~= type(value) then return false, "wrong type for " .. tostring(key) end
        if (key == "Class" or key == "Model") and not isAdmin then return false, key .. " needs rareload_admin" end
    end
    return true
end

-- Applies `change(entityDef, snap, index)` to one object of an entry. Saved data is never modified in
-- place: the snapshot is copied, changed, and stored as a new blob (§16.3).
local function changeObject(ply, entryId, objectId, change)
    local doc = History.Doc(ply)
    local entry = find(doc, entryId)
    if not entry then return false, "no such save" end
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = RARELOAD.Pipeline.Payload(entry.data[kind])
        for index, entityDef in pairs(snap and snap.Entities or {}) do
            if RARELOAD.Snapshot.DefID(entityDef) == objectId then
                local copy = util.JSONToTable(util.TableToJSON(snap), true)
                local ok, err = change(copy.Entities[index], copy, index)
                if not ok then return false, err end
                RARELOAD.Snapshot.PruneConstraints(copy)
                entry.data[kind] = { ["$blob"] = RARELOAD.Store.BlobPut(copy) }
                save(ply, doc)
                return true
            end
        end
    end
    return false, "no such object"
end

-- Deletes objects (ids = { [objectId] = true }): each snapshot is copied and stored once, not once per object.
local function deleteObjects(ply, entryId, ids)
    local doc = History.Doc(ply)
    local entry = find(doc, entryId)
    if not entry then return false, "no such save" end
    local removed = 0
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = RARELOAD.Pipeline.Payload(entry.data[kind])
        local hit = false
        for _, entityDef in pairs(snap and snap.Entities or {}) do
            if ids[RARELOAD.Snapshot.DefID(entityDef)] then
                hit = true
                break
            end
        end
        if hit then
            local copy = util.JSONToTable(util.TableToJSON(snap), true)
            for index, entityDef in pairs(copy.Entities) do
                if ids[RARELOAD.Snapshot.DefID(entityDef)] then
                    copy.Entities[index] = nil
                    removed = removed + 1
                end
            end
            RARELOAD.Snapshot.PruneConstraints(copy)
            entry.data[kind] = { ["$blob"] = RARELOAD.Store.BlobPut(copy) }
        end
    end
    if removed == 0 then return false, "no such object" end
    save(ply, doc)
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
    return changeObject(ply, entryId, objectId, function(entityDef)
        for _, phys in pairs(RARELOAD.Snapshot.Bones(entityDef)) do phys[field] = value or nil end
        return true
    end)
end

-- The player's own name for a saved object ("" removes it). An object still on the map takes it
-- too, so later saves keep it.
function History.RenameObject(ply, entryId, objectId, name)
    name = string.Trim(name)
    name = name ~= "" and name or nil
    local ok, err = changeObject(ply, entryId, objectId, function(entityDef)
        entityDef.EntityMods.rareload.name = name
        return true
    end)
    if not ok then return false, err end
    for _, ent in ents.Iterator() do
        if ent.RareloadID and tostring(ent.RareloadID) == tostring(objectId) then ent.RareloadName = name end
    end
    return true
end

function History.EditObject(ply, entryId, objectId, edit)
    return changeObject(ply, entryId, objectId, function(entityDef)
        local ok, err = History.ValidateEdit(entityDef, edit, RARELOAD.Can(ply, "rareload_admin"))
        if not ok then return false, err end
        for key, value in pairs(edit) do entityDef[key] = value end
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
        for _, entityDef in pairs(seatId and snap.Entities or {}) do
            if RARELOAD.Snapshot.DefID(entityDef) == seatId then facts.seatClass = entityDef.Class end
        end
    end
    if hash then snapFacts[hash] = facts end
    return facts
end

-- Raw values for the timeline; the client formats and translates them (L29).
function History.Info(data)
    local transform, health = data.transform or {}, data.health or {}
    local info = {
        pos = transform.pos,
        ang = transform.ang,
        crouched = transform.crouched,
        model = data.appearance and data.appearance.model,
        hp = health.hp,
        armor = health.armor,
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
        local moduleDef = RARELOAD.Pipeline.Def(id)
        if moduleDef and not moduleDef.heavy and moduleDef.phase ~= "world" then light[id] = value end
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
    local doc, rows = History.Doc(ply), {}
    for _, entry in ipairs(doc and doc.entries or {}) do
        entry.note = noteText(entry.note)
        local modules = {}
        for id in pairs(entry.data) do modules[#modules + 1] = id end
        table.sort(modules)
        rows[#rows + 1] = {
            id = entry.id,
            time = entry.time,
            reason = entry.reason,
            pinned = entry.pinned,
            note = entry.note,
            active = entry.id == doc.activeId,
            modules = modules,
            info = History.Info(entry.data)
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
    local doc = History.Doc(target)
    return (doc and doc.nick or "?") .. " (" .. target .. ")"
end

local function handle(op, priv, schema, fn)
    schema.sid = "string:20?"
    RARELOAD.Net.Handle(op, {
        priv = priv,
        rate = 0.2,
        args = schema,
        fn = function(ply, args)
            local target = targetFor(ply, args.sid)
            if not target then return end
            local key, targs = fn(target, args, ply)
            if key then RARELOAD.Toast(ply, key, targs) end
            if target ~= ply and op ~= "history.get" then
                RARELOAD.Log("admin", ply):info("%s: %s, save No. %s of %s", ply:Nick(), op, tostring(args.id or "-"),
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
handle("history.pin", "rareload_restore", { id = "uint", pinned = "bool" }, function(ply, args)
    local _, why = History.SetPinned(ply, args.id, args.pinned)
    if why == "full" then return "toast.pin_full", { RARELOAD.Get(nil, "pinnedMax") } end
end)
handle("history.note", "rareload_restore", { id = "uint", note = "string:256" },
    function(ply, args) History.SetNote(ply, args.id, args.note) end)
-- "Place here…" (D6): moves where the save respawns the player; the rest of the save stays as it is.
handle("history.move", "rareload_save", { id = "uint", x = "number", y = "number", z = "number", yaw = "number" },
    function(ply, args)
        local pos = Vector(args.x, args.y, args.z)
        if not util.IsInWorld(pos + Vector(0, 0, 16)) then return "toast.place_outside" end
        local ok = History.Update(ply, args.id, function(entry)
            local transform = istable(entry.data.transform) and entry.data.transform or {}
            transform.pos, transform.ang = RARELOAD.Util.Vec(pos), RARELOAD.Util.Ang(Angle(0, args.yaw % 360, 0))
            transform.crouched, transform.mapVersion = nil, game.GetMapVersion()
            entry.data.transform = transform
        end)
        if ok then return "toast.placed", { args.id } end
    end)
handle("history.delete", "rareload_restore", { id = "uint" }, function(ply, args) History.Delete(ply, args.id) end)
handle("history.clear", "rareload_restore", {}, function(ply) History.Clear(ply) end)
handle("history.activate", "rareload_restore", { id = "uint" }, function(ply, args)
    if History.Activate(ply, args.id) then return "toast.activated", { args.id } end
end)
handle("history.restore", "rareload_restore", { id = "uint", comps = "string:128?", exact = "bool?" },
    function(ply, args)
        if isstring(ply) then return "toast.admin_offline" end -- restoring needs the player in game
        if not ply:Alive() then return "toast.restore_dead" end
        if History.Restore(ply, args.id, parseComps(args.comps), { exact = args.exact }) then
            return "toast.restored", { args.id }
        end
    end)
handle("history.undo", "rareload_restore", {}, function(ply)
    if isstring(ply) then return "toast.nothing_to_undo" end
    return History.Undo(ply) and "toast.undone" or "toast.nothing_to_undo"
end)
handle("history.reloadMode", "rareload_use_tool", { mode = "string:32", comps = "string:128?" }, function(ply, args)
    if isstring(ply) then return end
    History.SetReloadConfig(ply, args.mode, parseComps(args.comps))
end)

RARELOAD.Net.Handle("history.players", {
    priv = MANAGE,
    rate = 1,
    fn = function(ply)
        local list, seen = {}, {}
        for _, other in player.Iterator() do
            if not other:IsBot() then
                local sid = other:SteamID64()
                local doc = History.Doc(other)
                seen[sid] = true
                list[#list + 1] = { sid = sid, nick = other:Nick(), online = true, saves = doc and #doc.entries or 0 }
            end
        end
        local dir = RARELOAD.Store.MapDir()
        for _, name in ipairs(file.Find("rareload/" .. dir .. "/*.json", "DATA") or {}) do
            local sid = name:match("^(%d+)%.json$")
            if sid and not seen[sid] then
                local doc = History.Doc(sid)
                if doc and #doc.entries > 0 then
                    list[#list + 1] = { sid = sid, nick = doc.nick or sid, online = false, saves = #doc.entries }
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
    fn = function(ply, args)
        local entityDef = History.ObjectDef(ply, args.entryId, args.objectId)
        if entityDef then
            RARELOAD.Net.Push(ply, "object.def",
                { entryId = args.entryId, objectId = args.objectId, json = util.TableToJSON(entityDef, true) })
        end
    end,
})

-- Everything saved about one object, for the world display's focused panel: from one of the
-- player's own saves, or (with rareload_debug while debug is on) another player's respawn point.
RARELOAD.Net.Handle("object.detail", {
    rate = 0.1,
    args = { sid = "string:20?", entryId = "uint?", objectId = "string:32" },
    fn = function(ply, args)
        local entry
        if args.sid and args.sid ~= ply:SteamID64() then
            local owner = player.GetBySteamID64(args.sid)
            if not IsValid(owner) then return end
            if not RARELOAD.Get(nil, "debug") or not RARELOAD.Can(ply, "rareload_debug") then return end
            entry = History.Active(owner)
        elseif RARELOAD.Can(ply, "rareload_restore") then
            entry = args.entryId and History.Get(ply, args.entryId) or History.Active(ply)
        end
        local detail = entry and History.ObjectDetail(entry, args.objectId)
        if detail then
            RARELOAD.Net.Push(ply, "object.detail",
                { sid = args.sid, entryId = args.entryId, objectId = args.objectId, detail = detail },
                { key = "detail:" .. tostring(args.sid) .. ":" .. tostring(args.entryId) .. ":" .. args.objectId })
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
    fn = function(ply, args) pushObjects(ply, args.id) end,
})

local function objectOp(op, schema, fn, priv)
    RARELOAD.Net.Handle(op, {
        priv = priv or "rareload_manage_objects",
        rate = 0.2,
        args = schema,
        fn = function(ply, args)
            local ok, err = fn(ply, args)
            if not ok then RARELOAD.Log("history", ply):warn("%s: %s failed: %s", ply:Nick(), op, tostring(err)) end
            pushObjects(ply, args.entryId)
        end
    })
end

objectOp("object.delete", { entryId = "uint", objectId = "string:32" }, function(ply, args)
    return History.DeleteObject(ply, args.entryId, args.objectId)
end)
-- ids: object IDs separated by commas.
objectOp("object.deleteMany", { entryId = "uint", ids = "string:60000" }, function(ply, args)
    local ids = {}
    for id in string.gmatch(args.ids, "[%w]+") do ids[id] = true end
    return History.DeleteObjects(ply, args.entryId, ids)
end)
objectOp("object.flag", { entryId = "uint", objectId = "string:32", flag = "string:16", value = "bool" },
    function(ply, args)
        return History.FlagObject(ply, args.entryId, args.objectId, args.flag, args.value)
    end)
-- Naming your own saved objects needs no more than seeing them.
objectOp("object.rename", { entryId = "uint", objectId = "string:32", name = "string:48" }, function(ply, args)
    return History.RenameObject(ply, args.entryId, args.objectId, args.name)
end, "rareload_restore")
-- The edit arrives as JSON and is decoded with the default size limits (S12).
objectOp("object.edit", { entryId = "uint", objectId = "string:32", json = "string:60000" }, function(ply, args)
    return History.EditObject(ply, args.entryId, args.objectId, util.JSONToTable(args.json))
end)

-- Pushes after changes ----------------------------------------------------------------------------

-- World display feed (§17.2): each player's respawn point with its light modules and objects, sent
-- to players with rareload_debug while the debug setting is on.
local function subscribers()
    local out = {}
    if not RARELOAD.Get(nil, "debug") then return out end
    for _, other in player.Iterator() do
        if RARELOAD.Can(other, "rareload_debug") then out[#out + 1] = other end
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
        for changedPly in pairs(changed) do
            if IsValid(changedPly) then
                pushRows(changedPly)
                pushFeed(changedPly)
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
        for _, viewer in player.Iterator() do pushFeed(viewer, { ply }) end
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
        for _, viewer in player.Iterator() do pushFeed(viewer) end
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
    local count = 0
    for _ in pairs(ids or {}) do count = count + 1 end
    return count
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
