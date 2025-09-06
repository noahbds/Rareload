-- Entity tracking and saved data lookup functions

function SED.RebuildSavedLookup()
    local map = game.GetMap()
    if not (RARELOAD.playerPositions and map) then return end
    SED.SAVED_ENTITIES_BY_ID = {}
    SED.SAVED_NPCS_BY_ID = {}

    for ownerSteamID, pdata in pairs(RARELOAD.playerPositions[map] or {}) do
        if istable(pdata) then
            if istable(pdata.entities) then
                for _, saved in ipairs(pdata.entities) do
                    if istable(saved) and saved.id then
                        saved._ownerSteamID = ownerSteamID
                        SED.SAVED_ENTITIES_BY_ID[saved.id] = saved
                    end
                end
            end
            if istable(pdata.npcs) then
                for _, saved in ipairs(pdata.npcs) do
                    if istable(saved) and saved.id then
                        saved._ownerSteamID = ownerSteamID
                        SED.SAVED_NPCS_BY_ID[saved.id] = saved
                    end
                end
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

timer.Create("RARELOAD_CacheCleanup", 45, 0, function()
    local now = CurTime()

    if SED.EntityPanelCache then
        for id, entry in pairs(SED.EntityPanelCache) do
            if entry and entry.expires and entry.expires < now then
                SED.EntityPanelCache[id] = nil
            end
        end
    end

    if SED.NPCPanelCache then
        for id, entry in pairs(SED.NPCPanelCache) do
            if entry and entry.expires and entry.expires < now then
                SED.NPCPanelCache[id] = nil
            end
        end
    end

    if SED.EntityBoundsCache then
        for entIndex, entry in pairs(SED.EntityBoundsCache) do
            if entry and entry.expires and entry.expires < now then
                SED.EntityBoundsCache[entIndex] = nil
            end
        end
    end

    local maxCacheSize = 200
    if SED.EntityPanelCache and table.Count(SED.EntityPanelCache) > maxCacheSize then
        local oldest = now
        local oldestKey = nil
        for id, entry in pairs(SED.EntityPanelCache) do
            if entry and entry.expires and entry.expires < oldest then
                oldest = entry.expires
                oldestKey = id
            end
        end
        if oldestKey then SED.EntityPanelCache[oldestKey] = nil end
    end

    if SED.NPCPanelCache and table.Count(SED.NPCPanelCache) > maxCacheSize then
        local oldest = now
        local oldestKey = nil
        for id, entry in pairs(SED.NPCPanelCache) do
            if entry and entry.expires and entry.expires < oldest then
                oldest = entry.expires
                oldestKey = id
            end
        end
        if oldestKey then SED.NPCPanelCache[oldestKey] = nil end
    end

    if SED.EntityBoundsCache and table.Count(SED.EntityBoundsCache) > maxCacheSize then
        local oldest = now
        local oldestKey = nil
        for entIndex, entry in pairs(SED.EntityBoundsCache) do
            if entry and entry.expires and entry.expires < oldest then
                oldest = entry.expires
                oldestKey = entIndex
            end
        end
        if oldestKey then SED.EntityBoundsCache[oldestKey] = nil end
    end
end)
