local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

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
    SED.SAVED_NPCS_BY_ID = {}

    for ownerSteamID, pdata in pairs(RARELOAD.playerPositions[map] or {}) do
        if istable(pdata) then
            if istable(pdata.entities) then
                ingestSaved(SED.SAVED_ENTITIES_BY_ID, pdata.entities, {
                    category = "entity",
                    owner = ownerSteamID
                })
            end
            if istable(pdata.npcs) then
                ingestSaved(SED.SAVED_NPCS_BY_ID, pdata.npcs, {
                    category = "npc",
                    owner = ownerSteamID
                })
            end
        end
    end
    SED.MAP_LAST_BUILD = CurTime()
end

function SED.EnsureSavedLookup()
    if CurTime() - SED.MAP_LAST_BUILD > SED.SAVED_LOOKUP_INTERVAL then
        SED.RebuildSavedLookup()
    end
end

function SED.TrackIfSaved(ent)
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

    local processed = 0
    local maxPerRescan = 256
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not SED.TrackedEntities[ent] and not SED.TrackedNPCs[ent] then
            SED.TrackIfSaved(ent)
            processed = processed + 1
            if processed >= maxPerRescan then break end
        end
    end
end

timer.Simple(1, function()
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            SED.TrackIfSaved(ent)
        end
    end
end)

local function purgeExpiredEntries(cache, now)
    if not cache then return end
    for key, entry in pairs(cache) do
        if entry and entry.expires and entry.expires < now then
            cache[key] = nil
        end
    end
end

local function pruneOldestIfNeeded(cache, maxCacheSize, now)
    if not cache or table.Count(cache) <= maxCacheSize then return end

    local oldest = now
    local oldestKey = nil
    for key, entry in pairs(cache) do
        if entry and entry.expires and entry.expires < oldest then
            oldest = entry.expires
            oldestKey = key
        end
    end

    if oldestKey then
        cache[oldestKey] = nil
    end
end

timer.Create("RARELOAD_CacheCleanup", 45, 0, function()
    local now = CurTime()

    purgeExpiredEntries(SED.EntityPanelCache, now)
    purgeExpiredEntries(SED.NPCPanelCache, now)
    purgeExpiredEntries(SED.EntityBoundsCache, now)

    local maxCacheSize = 200
    pruneOldestIfNeeded(SED.EntityPanelCache, maxCacheSize, now)
    pruneOldestIfNeeded(SED.NPCPanelCache, maxCacheSize, now)
    pruneOldestIfNeeded(SED.EntityBoundsCache, maxCacheSize, now)
end)
