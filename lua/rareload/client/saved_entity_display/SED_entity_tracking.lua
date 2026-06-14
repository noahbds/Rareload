local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local SS = SED.Shared
if not (SS and SS._initialized) then
    include("rareload/client/saved_entity_display/SED_shared.lua")
    SS = SED.Shared
end

local function ingestSaved(target, bucket, opts)
    if not istable(bucket) then return end
    local list = SnapshotUtils.GetSummary(bucket, opts) or {}
    for _, saved in ipairs(list) do
        if istable(saved) and saved.id then
            saved._ownerSteamID = opts.owner
            target[saved.id] = saved
        end
    end
end

function SED.RebuildSavedLookup()
    local map = game.GetMap()
    if not (RARELOAD.playerPositions and map) then return end
    SED.SAVED_ENTITIES_BY_ID = {}
    SED.SAVED_NPCS_BY_ID     = {}

    for ownerSteamID, pdata in pairs(RARELOAD.playerPositions[map] or {}) do
        if istable(pdata) then
            if istable(pdata.entities) then
                ingestSaved(SED.SAVED_ENTITIES_BY_ID, pdata.entities, {
                    category = "entity", owner = ownerSteamID
                })
            end
            if istable(pdata.npcs) then
                ingestSaved(SED.SAVED_NPCS_BY_ID, pdata.npcs, {
                    category = "npc", owner = ownerSteamID
                })
            end
        end
    end
    SED.MAP_LAST_BUILD = CurTime()
end

function SED.PruneMissingTrackedEntities()
    local removed = 0

    for ent, id in pairs(SED.TrackedEntities or {}) do
        if not (id and SED.SAVED_ENTITIES_BY_ID and SED.SAVED_ENTITIES_BY_ID[id]) then
            SED.TrackedEntities[ent] = nil
            removed = removed + 1
            local idx = IsValid(ent) and ent:EntIndex() or nil
            if SED.EntityBoundsCache and idx then
                SED.EntityBoundsCache[idx] = nil
            end
        end
    end

    for npc, id in pairs(SED.TrackedNPCs or {}) do
        if not (id and SED.SAVED_NPCS_BY_ID and SED.SAVED_NPCS_BY_ID[id]) then
            SED.TrackedNPCs[npc] = nil
            removed = removed + 1
            local idx = IsValid(npc) and npc:EntIndex() or nil
            if SED.EntityBoundsCache and idx then
                SED.EntityBoundsCache[idx] = nil
            end
        end
    end

    return removed
end

function SED.EnsureSavedLookup()
    if CurTime() - SED.MAP_LAST_BUILD > SED.SAVED_LOOKUP_INTERVAL then
        SED.RebuildSavedLookup()
    end
end

function SED.TrackIfSaved(ent)
    if not IsValid(ent) or ent:IsPlayer() then return end
    SED.TrackIfSavedInternal(ent)
end

function SED.TrackIfSavedInternal(ent)
    if not IsValid(ent) or ent:IsPlayer() then return end
    local id = ent.GetNWString and ent:GetNWString("RareloadID", "") or ""
    if id == "" then return end
    SED.EnsureSavedLookup()
    if ent:IsNPC() then
        if SED.SAVED_NPCS_BY_ID[id] then
            SED.TrackedNPCs[ent] = id
        end
    else
        if SED.SAVED_ENTITIES_BY_ID[id] then
            SED.TrackedEntities[ent] = id
        end
    end
end

function SED.RescanLate()
    if CurTime() - SED.LAST_RESCAN < SED.RESCAN_INTERVAL then return end
    SED.LAST_RESCAN = CurTime()

    local processed, maxPerRescan = 0, 128
    local allEnts = ents.GetAll()
    local totalEnts = #allEnts

    if table.Count(SED.TrackedEntities) + table.Count(SED.TrackedNPCs) < totalEnts * 0.8 then
        for _, ent in ipairs(allEnts) do
            if IsValid(ent) and not SED.TrackedEntities[ent] and not SED.TrackedNPCs[ent] then
                SED.TrackIfSavedInternal(ent)
                processed = processed + 1
                if processed >= maxPerRescan then break end
            end
        end
    end
end

timer.Simple(1, function()
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then SED.TrackIfSaved(ent) end
    end
end)

timer.Create("RARELOAD_CacheCleanup", 45, 0, function()
    SS.CleanCaches(CurTime(), 200,
        SED.EntityPanelCache,
        SED.NPCPanelCache,
        SED.EntityBoundsCache)
end)
