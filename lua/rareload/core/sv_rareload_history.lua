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

local SnapshotUtils = RARELOAD.SnapshotUtils
if not SnapshotUtils then
    local ok, mod = pcall(include, "rareload/shared/rareload_snapshot_utils.lua")
    if ok then SnapshotUtils = mod end
end

local MAX_SENT_ENTRIES = 512 -- net-size guard; the default cap is 125

-- ── counts ─────────────────────────────────────────────────────────────────────

local function CountBucket(bucket)
    if not istable(bucket) then return 0 end
    if SnapshotUtils and SnapshotUtils.GetSummary then
        local ok, list = pcall(SnapshotUtils.GetSummary, bucket, {})
        if ok and istable(list) then return #list end
    end
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
        }
    end
    return out, #entries
end

local function SendData(ply)
    if not IsValid(ply) then return end
    local summary, total = BuildSummary(ply:SteamID(), game.GetMap())
    local json = util.TableToJSON({ entries = summary, total = total }) or "{}"
    local data = util.Compress(json) or ""

    net.Start("RareloadHistory_Data")
    net.WriteUInt(#data, 32)
    net.WriteData(data, #data)
    net.Send(ply)
end
RARELOAD.SendHistoryToClient = SendData

net.Receive("RareloadHistory_Request", function(_, ply)
    SendData(ply)
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
    end
end

function RARELOAD.RestoreHistoryEntry(ply, id, comps)
    if not IsValid(ply) then return false end
    local data = RARELOAD.GetHistoryEntryById(ply:SteamID(), game.GetMap(), id)
    if not data then
        ply:ChatPrint("[Rareload] That saved position is no longer in your history.")
        return false
    end
    RARELOAD.ApplyHistoryComponents(ply, data, comps)
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
        local comps = net.ReadTable()
        RARELOAD.RestoreHistoryEntry(ply, id, comps)
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
