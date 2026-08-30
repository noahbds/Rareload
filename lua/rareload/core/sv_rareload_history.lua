-- ─────────────────────────────────────────────────────────────────────────────
-- Save Timeline — server net + restore (4.0 · Phase 3)
--
-- Sends each player a COMPACT summary of their own save history (the heavy
-- entity/NPC blobs stay server-side and are only touched on restore) and handles
-- the panel's actions: pin, note, delete, clear, teleport-to and restore.
--
-- Restore reuses the existing respawn primitives (RestoreInventory,
-- RestoreAppearance, RestoreEntities, RestoreNPCs, …) so a history entry is
-- applied to the living player exactly the way the reload key applies the active
-- save — component by component, so partial restore is precise.
-- ─────────────────────────────────────────────────────────────────────────────

if not SERVER then return end

util.AddNetworkString("RareloadHistory_Request")
util.AddNetworkString("RareloadHistory_Data")
util.AddNetworkString("RareloadHistory_Action")
util.AddNetworkString("RareloadHistory_Preview")
util.AddNetworkString("RareloadHistory_Objects")   -- serve one save's full object list
util.AddNetworkString("RareloadHistory_ObjAction") -- edit / flag / delete an object in a save

local SnapshotUtils = RARELOAD.SnapshotUtils
if not SnapshotUtils then
    local ok, mod = pcall(include, "rareload/shared/rareload_snapshot_utils.lua")
    if ok then SnapshotUtils = mod end
end

local MAX_SENT_ENTRIES = 512 -- net-size guard; the default cap is 125

RARELOAD.restoreUndo = RARELOAD.restoreUndo or {} -- per-steamID pre-restore snapshot

-- Restore components the client may request. NEVER read these as an arbitrary
-- net.ReadTable (unbounded / exploitable) — the client writes them as a fixed
-- ordered run of booleans and we read exactly that many.
local RESTORE_COMPS = { "all", "position", "health", "inventory", "ammo", "appearance", "states", "world" }

local function ReadComps()
    local comps = {}
    for _, k in ipairs(RESTORE_COMPS) do
        if net.ReadBool() then comps[k] = true end
    end
    return comps
end

-- Per-player, per-message cooldowns so a client can't spam the (relatively
-- expensive) history/preview builders.
local netCooldown = {}
local function RateLimited(ply, key, interval)
    local id = ply:SteamID()
    local slot = netCooldown[id]
    if not slot then slot = {}; netCooldown[id] = slot end
    local now = CurTime()
    if slot[key] and now < slot[key] then return true end
    slot[key] = now + interval
    return false
end

-- ── counts ─────────────────────────────────────────────────────────────────────

-- Single shared accessor for a bucket's summary list (cached inside GetSummary).
local function SummaryOf(bucket)
    if not (SnapshotUtils and SnapshotUtils.GetSummary and istable(bucket)) then return nil end
    local ok, list = pcall(SnapshotUtils.GetSummary, bucket, {})
    if ok and istable(list) then return list end
    return nil
end

local function CountBucket(bucket)
    if not istable(bucket) then return 0 end
    local list = SummaryOf(bucket)
    if list then return #list end
    local n = 0
    for k in pairs(bucket) do
        if k ~= "__duplicator" then n = n + 1 end
    end
    -- Modern snapshots keep entries under the duplicator payload; count those too.
    local dup = bucket.__duplicator
    if n == 0 and istable(dup) and istable(dup.payload) and istable(dup.payload.Entities) then
        for _ in pairs(dup.payload.Entities) do n = n + 1 end
    end
    return n
end

-- ── summary sent to the client ──────────────────────────────────────────────────

local function BuildSummary(steamID, mapName)
    local entries = RARELOAD.GetPositionHistoryEntries(steamID, mapName)
    local activeId = RARELOAD.GetActiveHistoryId and RARELOAD.GetActiveHistoryId(steamID, mapName) or nil
    local out = {}
    local count = math.min(#entries, MAX_SENT_ENTRIES)
    for i = 1, count do
        local e = entries[i]
        local st
        if istable(e.playerStates) then
            st = {
                g = e.playerStates.godmode and 1 or nil,
                n = e.playerStates.notarget and 1 or nil,
                f = e.playerStates.frozen and 1 or nil,
                c = e.playerStates.noclip and 1 or nil,
            }
            if not next(st) then st = nil end
        end
        out[i] = {
            id   = e.id,
            t    = e.timestamp,
            pin  = e.pinned and 1 or nil,
            note = (e.note and e.note ~= "") and e.note or nil,
            pos  = e.pos,
            ang  = e.ang,
            hp   = tonumber(e.health),
            ar   = tonumber(e.armor),
            mdl  = (e.appearance and e.appearance.model) or e.playermodel,
            wc   = (istable(e.inventory) and #e.inventory) or 0,
            aw   = e.activeWeapon,
            st   = st,
            ec   = CountBucket(e.entities),
            nc   = CountBucket(e.npcs),
            vc   = CountBucket(e.vehicles),
            veh  = (e.vehicleState and e.vehicleState.savedInVehicle) and (e.vehicleState.class or "1") or nil,
            act  = (activeId and e.id == activeId) and 1 or nil,
        }
    end
    return out, #entries
end

local function SendData(ply)
    if not IsValid(ply) then return end
    local steamID = ply:SteamID()
    local summary, total = BuildSummary(steamID, game.GetMap())
    local undo = RARELOAD.restoreUndo[steamID] ~= nil
    local json = util.TableToJSON({ entries = summary, total = total, undo = undo }) or "{}"
    local data = util.Compress(json) or ""

    net.Start("RareloadHistory_Data")
    net.WriteUInt(#data, 32)
    net.WriteData(data, #data)
    net.Send(ply)
end
RARELOAD.SendHistoryToClient = SendData

net.Receive("RareloadHistory_Request", function(_, ply)
    if not IsValid(ply) or RateLimited(ply, "request", 0.25) then return end
    SendData(ply)
end)

-- ── in-world preview data (player + entity/NPC geometry, fetched on demand) ──────

local PREVIEW_OBJ_CAP = 48
local PLAYER_INFO_KEYS = {
    "pos", "ang", "moveType", "health", "armor", "inventory", "ammo",
    "playerStates", "appearance", "activeWeapon", "playermodel", "vehicles", "vehicleState",
}

local function ExtractObjects(bucket, out, isNPC)
    local list = SummaryOf(bucket)
    if not list then return end
    for _, s in ipairs(list) do
        if #out >= PREVIEW_OBJ_CAP then break end
        local pos   = s.pos or s.Pos
        local model = s.model or s.Model
        if istable(pos) and isstring(model) and model ~= "" then
            out[#out + 1] = {
                c   = s.class or s.Class or s.NPCName or "?",
                m   = model,
                p   = pos,
                a   = s.Angle or s.Ang or s.ang or nil,
                npc = isNPC and 1 or nil,
                rec = s, -- full saved record so the client can draw the SED info panel
            }
        end
    end
end

local function BuildPreviewData(steamID, mapName, id)
    local e = RARELOAD.GetHistoryEntryById(steamID, mapName, id)
    if not e then return nil end

    local info = {}
    for _, k in ipairs(PLAYER_INFO_KEYS) do info[k] = e[k] end

    local objects = {}
    ExtractObjects(e.entities, objects, false)
    ExtractObjects(e.npcs, objects, true)
    ExtractObjects(e.vehicles, objects, false)

    -- If legacy array format without duplicator, fallback to iterating directly
    if istable(e.vehicles) and not SnapshotUtils.HasSnapshot(e.vehicles) then
        for i, v in ipairs(e.vehicles) do
            if #objects >= PREVIEW_OBJ_CAP then break end
            if istable(v.pos) and isstring(v.model) and v.model ~= "" then
                objects[#objects + 1] = {
                    c   = v.class or "vehicle",
                    m   = v.model,
                    p   = v.pos,
                    a   = v.ang,
                    rec = {
                        id    = "vehicle_" .. i,
                        class = v.class, Class = v.class,
                        model = v.model, Model = v.model,
                        pos   = v.pos, Pos = v.pos,
                        ang   = v.ang, Angle = v.ang,
                        health = v.health, CurHealth = v.health, MaxHealth = v.health,
                        skin  = v.skin,
                        isVehicle = true,
                    },
                }
            end
        end
    end

    return {
        player = {
            m    = (istable(e.appearance) and e.appearance.model) or e.playermodel,
            p    = e.pos,
            a    = e.ang,
            info = info,
        },
        objects = objects,
    }
end

net.Receive("RareloadHistory_Preview", function(_, ply)
    if not IsValid(ply) then return end
    local id = net.ReadString()
    if RateLimited(ply, "preview", 0.5) then return end
    local data = (id ~= "") and BuildPreviewData(ply:SteamID(), game.GetMap(), id) or nil
    local json = util.TableToJSON(data or {}) or "{}"
    local blob = util.Compress(json) or ""

    -- Net messages cap near 64KB. If the full records blow past that, drop them and resend
    -- a lightweight version (phantoms + fallback cards still work, just no SED panels).
    if #blob > 60000 and istable(data) then
        if istable(data.player) then data.player.info = nil end
        for _, o in ipairs(data.objects or {}) do o.rec = nil end
        json = util.TableToJSON(data) or "{}"
        blob = util.Compress(json) or ""
    end

    net.Start("RareloadHistory_Preview")
    net.WriteString(id)
    net.WriteUInt(#blob, 32)
    net.WriteData(blob, #blob)
    net.Send(ply)
end)

-- ── restore ─────────────────────────────────────────────────────────────────────

local function SafeTeleport(ply, pos, ang)
    pos = RARELOAD.DataUtils.ToVector(pos)
    if not pos then return end
    if ply:InVehicle() then ply:ExitVehicle() end

    local finalPos = pos
    if RARELOAD.AntiStuck and RARELOAD.AntiStuck.IsPositionStuck then
        local stuck = RARELOAD.AntiStuck.IsPositionStuck(pos, ply, true)
        if stuck and RARELOAD.AntiStuck.ResolveStuckPosition then
            local safe, ok = RARELOAD.AntiStuck.ResolveStuckPosition(pos, ply)
            if ok then finalPos = RARELOAD.DataUtils.ToVector(safe) or pos end
        end
    end

    ply:SetPos(finalPos)
    ply:SetVelocity(Vector(0, 0, 0))
    local a = RARELOAD.DataUtils.ToAngle(ang)
    if a then ply:SetEyeAngles(a) end
end

-- comps: { all=true } for a full restore, or any subset of
-- { position, health, inventory, ammo, appearance, states, world }.
function RARELOAD.ApplyHistoryComponents(ply, data, comps)
    if not IsValid(ply) or not istable(data) then return end
    comps = istable(comps) and comps or {}

    local function want(k) return comps.all == true or comps[k] == true end
    local function perm(p) return (not RARELOAD.CheckPermission) or RARELOAD.CheckPermission(ply, p) end

    if want("position") and (perm("TELEPORT_PLAYER") or perm("RARELOAD_SPAWN")) then
        SafeTeleport(ply, data.pos, data.ang)
    end

    if want("health") and perm("RETAIN_HEALTH_ARMOR") then
        timer.Simple(0.05, function()
            if not IsValid(ply) then return end
            if data.health then ply:SetHealth(tonumber(data.health) or ply:Health()) end
            if data.armor then ply:SetArmor(tonumber(data.armor) or 0) end
        end)
    end

    if want("inventory") and perm("KEEP_INVENTORY") and istable(data.inventory) and RARELOAD.RestoreInventory then
        RARELOAD.RestoreInventory(ply, data)
    end

    if want("ammo") and perm("RETAIN_AMMO") and istable(data.ammo) then
        timer.Simple(0.5, function()
            if not IsValid(ply) then return end
            for weaponClass, ammoData in pairs(data.ammo) do
                local weapon = ply:GetWeapon(weaponClass)
                if IsValid(weapon) and istable(ammoData) then
                    local pt, st = weapon:GetPrimaryAmmoType(), weapon:GetSecondaryAmmoType()
                    if pt >= 0 and ammoData.primary then ply:SetAmmo(ammoData.primary, pt) end
                    if st >= 0 and ammoData.secondary then ply:SetAmmo(ammoData.secondary, st) end
                    if ammoData.clip1 and ammoData.clip1 >= 0 then weapon:SetClip1(ammoData.clip1) end
                    if ammoData.clip2 and ammoData.clip2 >= 0 then weapon:SetClip2(ammoData.clip2) end
                end
            end
        end)
    end

    if want("appearance") and perm("RETAIN_APPEARANCE") then
        local appearance = data.appearance
        local model = (istable(appearance) and appearance.model) or data.playermodel
        if appearance or model then
            timer.Simple(0.1, function()
                if not IsValid(ply) then return end
                if istable(appearance) and RARELOAD.RestoreAppearance then
                    RARELOAD.RestoreAppearance(ply, appearance)
                elseif model then
                    ply:SetModel(model)
                    ply:SetupHands()
                end
            end)
        end
    end

    if want("states") and perm("RETAIN_PLAYER_STATES") and istable(data.playerStates) then
        timer.Simple(0.1, function()
            if not IsValid(ply) then return end
            local s = data.playerStates
            if s.godmode then ply:GodEnable() else ply:GodDisable() end
            ply:SetNoTarget(s.notarget == true)
            ply:Freeze(s.frozen == true)
            if s.noclip and ply:GetMoveType() ~= MOVETYPE_NOCLIP then
                ply:SetMoveType(MOVETYPE_NOCLIP)
            end
        end)
    end

    if want("world") then
        if perm("RESTORE_ENTITIES") and istable(data.entities) and RARELOAD.RestoreEntities then
            RARELOAD.RestoreEntities(data.pos, data, ply)
        end
        if perm("RESTORE_NPCS") and istable(data.npcs) and RARELOAD.RestoreNPCs then
            RARELOAD.RestoreNPCs(data, ply)
        end
        if perm("RESTORE_VEHICLES") and istable(data.vehicles) and RARELOAD.RestoreVehicles then
            RARELOAD.RestoreVehicles(data, ply)
            if data.vehicleState and data.vehicleState.savedInVehicle and RARELOAD.RestorePlayerVehicle then
                RARELOAD.RestorePlayerVehicle(ply, data)
            end
        end
    end
end

-- Snapshot the player's current player-state so a restore can be undone.
local function CaptureLiveSnapshot(ply)
    local weps = {}
    for _, w in ipairs(ply:GetWeapons()) do
        if IsValid(w) then weps[#weps + 1] = w:GetClass() end
    end
    local active = ply:GetActiveWeapon()
    return {
        pos          = RARELOAD.DataUtils.ToPositionTable(ply:GetPos()),
        ang          = RARELOAD.DataUtils.ToAngleTable(ply:EyeAngles()),
        moveType     = ply:GetMoveType(),
        health       = ply:Health(),
        armor        = ply:Armor(),
        inventory    = weps,
        activeWeapon = IsValid(active) and active:GetClass() or "None",
        playermodel  = ply:GetModel(),
    }
end

function RARELOAD.RestoreHistoryEntry(ply, id, comps)
    if not IsValid(ply) then return false end
    local data = RARELOAD.GetHistoryEntryById(ply:SteamID(), game.GetMap(), id)
    if not data then
        ply:ChatPrint("[Rareload] That saved position is no longer in your history.")
        return false
    end

    local undo = CaptureLiveSnapshot(ply)
    RARELOAD.restoreUndo[ply:SteamID()] = undo

    -- Record which Rareload world objects already exist so undo can remove ONLY
    -- the ones this restore spawns. The world restore below is synchronous, so
    -- the diff right after is accurate.
    local before = {}
    for _, e in ipairs(ents.GetAll()) do
        if IsValid(e) and e.SpawnedByRareload then before[e] = true end
    end

    RARELOAD.ApplyHistoryComponents(ply, data, comps)

    local spawned = {}
    for _, e in ipairs(ents.GetAll()) do
        if IsValid(e) and e.SpawnedByRareload and not before[e] then
            spawned[#spawned + 1] = e
        end
    end
    undo.spawned = spawned
    return true
end

-- Revert the most recent restore: player-state AND the world objects it spawned.
function RARELOAD.UndoRestore(ply)
    if not IsValid(ply) then return false end
    local steamID = ply:SteamID()
    local snap = RARELOAD.restoreUndo[steamID]
    if not snap then
        ply:ChatPrint("[Rareload] Nothing to undo.")
        return false
    end
    RARELOAD.restoreUndo[steamID] = nil

    local removed = 0
    if istable(snap.spawned) then
        for _, e in ipairs(snap.spawned) do
            if IsValid(e) then e:Remove(); removed = removed + 1 end
        end
        snap.spawned = nil -- keep it out of the player-state apply below
    end

    RARELOAD.ApplyHistoryComponents(ply, snap, { all = true })
    ply:ChatPrint(string.format("[Rareload] Reverted to your pre-restore state%s.",
        removed > 0 and (" and removed " .. removed .. " restored object" .. (removed == 1 and "" or "s")) or ""))
    return true
end

-- Promote a history entry to be the ACTIVE save — the one the tool-gun reload key and
-- respawn restore. This is what makes an old save "current" again.
function RARELOAD.ActivateHistoryEntry(ply, id)
    if not IsValid(ply) then return false end
    local steamID, mapName = ply:SteamID(), game.GetMap()
    local entry = RARELOAD.GetHistoryEntryById(steamID, mapName, id)
    if not entry then
        ply:ChatPrint("[Rareload] That saved position is no longer in your history.")
        return false
    end

    -- Clean player-state snapshot (drop history-only meta), deep-copied so the active
    -- save is independent of the shared history entry.
    local data = {}
    for k, v in pairs(entry) do
        if k ~= "id" and k ~= "timestamp" and k ~= "pinned" and k ~= "note" then
            data[k] = istable(v) and table.Copy(v) or v
        end
    end

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][steamID] = data

    if RARELOAD.SavePlayerPositionEntry then
        RARELOAD.SavePlayerPositionEntry(ply, data)
    end
    RARELOAD.SetActiveHistoryId(steamID, mapName, id)

    if SyncPlayerPositions then SyncPlayerPositions(nil, steamID) end
    ply:ChatPrint("[Rareload] This save is now your respawn point.")
    return true
end

-- ── action dispatch ─────────────────────────────────────────────────────────────

net.Receive("RareloadHistory_Action", function(_, ply)
    if not IsValid(ply) then return end
    local action  = net.ReadString()
    local id      = net.ReadString()
    local steamID = ply:SteamID()
    local mapName = game.GetMap()
    local mutated = false

    if action == "pin" then
        local pinned = net.ReadBool()
        mutated = RARELOAD.SetHistoryEntryPinned(steamID, mapName, id, pinned)
    elseif action == "note" then
        local note = net.ReadString()
        if #note > 256 then note = string.sub(note, 1, 256) end
        mutated = RARELOAD.SetHistoryEntryNote(steamID, mapName, id, note)
    elseif action == "delete" then
        mutated = RARELOAD.DeleteHistoryEntry(steamID, mapName, id)
    elseif action == "clear" then
        RARELOAD.ClearPositionHistory(steamID, mapName)
        mutated = true
    elseif action == "restore" then
        local comps = ReadComps()
        if RateLimited(ply, "restore", 0.3) then return end
        RARELOAD.RestoreHistoryEntry(ply, id, comps)
    elseif action == "activate" then
        mutated = RARELOAD.ActivateHistoryEntry(ply, id)
    elseif action == "undo" then
        RARELOAD.UndoRestore(ply)
    else
        return
    end

    -- Re-sync so the panel reflects the change (harmless after a pure restore too).
    SendData(ply)

    if mutated and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD DEBUG] %s history action '%s' on %s (%s)",
            ply:Nick(), action, id, mapName))
    end
end)

-- ── per-save object browser (entity viewer / JSON editor over any save) ──────────
--
-- The Save Timeline's "Objects" overlay reuses the entity-viewer UI, but scoped to
-- ONE history entry instead of the live current save. The server serves that
-- entry's full object records on demand and applies edit/flag/delete back into the
-- history store (with copy-on-write so shared, deduped heavy buckets aren't
-- corrupted). Guarded by MANAGE_ENTITIES, same as the live entity viewer.

local function HasEntityPerm(ply)
    if RARELOAD.CheckPermission then return RARELOAD.CheckPermission(ply, "MANAGE_ENTITIES") end
    if RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        return RARELOAD.Permissions.HasPermission(ply, "MANAGE_ENTITIES")
    end
    return IsValid(ply) and ply:IsAdmin()
end

-- Flatten a history entry's entities/npcs/vehicles into viewer-ready records. Each
-- GetSummary record is a full copy of the stored def (so the JSON editor has every
-- field) plus id/class/model/pos/ang; we only tag its bucket + isNPC.
local function BuildEntryObjects(steamID, mapName, id)
    local e = RARELOAD.GetHistoryEntryById(steamID, mapName, id)
    if not e then return nil end
    local out = {}
    local function add(bucket, isNPC, isVehicle)
        local list = SummaryOf(bucket)
        if not list then return end
        for _, s in ipairs(list) do
            if istable(s) then
                s.isNPC = isNPC or nil
                s.isVehicle = isVehicle or nil
                out[#out + 1] = s
            end
        end
    end
    add(e.entities, false, false)
    add(e.npcs, true, false)
    add(e.vehicles, false, true)
    return out
end

net.Receive("RareloadHistory_Objects", function(_, ply)
    if not IsValid(ply) or RateLimited(ply, "objects", 0.3) then return end
    local id = net.ReadString()
    local steamID = ply:SteamID()
    local objs = (id ~= "") and BuildEntryObjects(steamID, game.GetMap(), id) or nil
    local payload = { id = id, ownerSID = steamID, objects = objs or {} }

    local json = util.TableToJSON(payload) or "{}"
    local blob = util.Compress(json) or ""
    -- Net messages cap near 64KB. Full defs (physics/mods) can blow past that on a
    -- big save; drop the heavy per-def tables and resend so the grid still lists
    -- every object (the JSON editor then edits the common fields only).
    if #blob > 60000 and objs then
        for _, s in ipairs(objs) do
            s.PhysicsObjects, s.EntityMods, s.BoneManip, s.BoneMods, s.FlexScale = nil, nil, nil, nil, nil
        end
        json = util.TableToJSON(payload) or "{}"
        blob = util.Compress(json) or ""
    end

    net.Start("RareloadHistory_Objects")
    net.WriteString(id)
    net.WriteUInt(#blob, 32)
    net.WriteData(blob, #blob)
    net.Send(ply)
end)

-- Locate a stored def by id inside a bucket (top-level map or duplicator payload)
-- and hand it to modifyFn (top-level map or duplicator payload).
local function ModifyDefInBucket(bucket, targetId, modifyFn)
    if not istable(bucket) then return false end
    local function isMatch(record, key)
        if tostring(key) == targetId then return true end
        if istable(record) then
            if tostring(record.RareloadNPCID or "") == targetId then return true end
            if tostring(record.RareloadEntityID or "") == targetId then return true end
            if tostring(record.RareloadID or "") == targetId then return true end
        end
        return false
    end
    local function tryMap(map)
        if not istable(map) then return false end
        for k, v in pairs(map) do
            if k ~= "__duplicator" and istable(v) and isMatch(v, k) then
                modifyFn(v); return true
            end
        end
        return false
    end
    if tryMap(bucket) then return true end
    local dup = bucket.__duplicator
    if istable(dup) and istable(dup.payload) and istable(dup.payload.Entities) then
        if tryMap(dup.payload.Entities) then return true end
    end
    return false
end

local OBJ_FLAG_HANDLERS = {
    freeze = function(v, value)
        v.frozen = value
        if istable(v.PhysicsObjects) then
            for _, p in pairs(v.PhysicsObjects) do if istable(p) then p.Frozen = value end end
        end
    end,
    gravity_disabled = function(v, value)
        v.gravity_disabled = value
        if istable(v.PhysicsObjects) then
            for _, p in pairs(v.PhysicsObjects) do if istable(p) then p.GravityEnabled = not value end end
        end
    end,
}

-- Clone a heavy bucket before mutating so we never corrupt another entry that
-- shares the same deduped blob in memory (Persist re-dedups on write).
local function CloneEntryBucket(e, key)
    if istable(e[key]) then e[key] = table.Copy(e[key]) end
    return e[key]
end

net.Receive("RareloadHistory_ObjAction", function(_, ply)
    if not IsValid(ply) then return end
    local saveId   = net.ReadString()
    local op       = net.ReadString()
    local targetId = net.ReadString()
    local isNPC    = net.ReadBool()

    local edit  = op == "edit" and net.ReadTable() or nil
    local flag, flagVal
    if op == "flag" then flag = net.ReadString(); flagVal = net.ReadBool() end

    if not HasEntityPerm(ply) then
        ply:ChatPrint("[Rareload] You lack permission to modify saved objects.")
        return
    end
    if saveId == "" or targetId == "" then return end

    local steamID = ply:SteamID()
    local mapName = game.GetMap()
    local e = RARELOAD.GetHistoryEntryById(steamID, mapName, saveId)
    if not e then return end

    -- entities & vehicles both hold non-NPC objects; NPCs are separate.
    local bucketKeys = isNPC and { "npcs" } or { "entities", "vehicles" }
    local mutated = false

    for _, key in ipairs(bucketKeys) do
        if istable(e[key]) then
            if op == "delete" then
                -- delete doesn't touch inner defs' shared identity, but the bucket
                -- table itself is shared — clone before removing from it.
                CloneEntryBucket(e, key)
                if SnapshotUtils and SnapshotUtils.RemoveEntryByID
                    and SnapshotUtils.RemoveEntryByID(e[key], targetId) then
                    mutated = true
                end
            elseif op == "edit" and istable(edit) then
                CloneEntryBucket(e, key)
                if ModifyDefInBucket(e[key], targetId, function(v)
                        edit.RareloadNPCID    = edit.RareloadNPCID or v.RareloadNPCID
                        edit.RareloadEntityID = edit.RareloadEntityID or v.RareloadEntityID
                        for k in pairs(v) do v[k] = nil end
                        for k, val in pairs(edit) do v[k] = val end
                    end) then
                    mutated = true
                end
            elseif op == "flag" and OBJ_FLAG_HANDLERS[flag] then
                CloneEntryBucket(e, key)
                if ModifyDefInBucket(e[key], targetId, function(v) OBJ_FLAG_HANDLERS[flag](v, flagVal) end) then
                    mutated = true
                end
            end
        end
        if mutated then break end
    end

    if mutated then
        RARELOAD.PersistPositionHistory(mapName, steamID)
        SendData(ply) -- refresh timeline summaries (counts change on delete)
        -- push the fresh object list back so the open overlay updates in place
        local objs = BuildEntryObjects(steamID, mapName, saveId)
        local blob = util.Compress(util.TableToJSON({ id = saveId, ownerSID = steamID, objects = objs or {} }) or "{}") or ""
        if #blob <= 60000 then
            net.Start("RareloadHistory_Objects")
            net.WriteString(saveId)
            net.WriteUInt(#blob, 32)
            net.WriteData(blob, #blob)
            net.Send(ply)
        end
    end
end)

hook.Add("PlayerDisconnected", "RARELOAD_HistoryUndo_Cleanup", function(ply)
    if IsValid(ply) then
        local id = ply:SteamID()
        RARELOAD.restoreUndo[id] = nil
        netCooldown[id] = nil
    end
end)
