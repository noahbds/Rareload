RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

local ENTITY_RESTORATION = {
    PROXIMITY_RADIUS = 150
}

if not (RARELOAD.Util and RARELOAD.Util.GenerateEntityStateHash) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local DebugState = include("rareload/debug/sv_debug_state.lua")
local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")
local SnapshotRestore = include("rareload/core/respawn_handlers/sv_rareload_snapshot_restore.lua")

local function CountTableEntries(tbl)
    if not istable(tbl) then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end
function RARELOAD.RestoreEntities(playerSpawnPos, savedInfo, requestingPlayer)
    if not savedInfo or not istable(savedInfo.entities) then
        return false
    end

    local snapshot = savedInfo.entities.__duplicator or nil
    local debugEnabled = (DebugState and DebugState.IsEnabledForPlayer and DebugState.IsEnabledForPlayer(requestingPlayer))
        or (DebugState and DebugState.IsAnyEnabled and DebugState.IsAnyEnabled())
    if not snapshot then
        if RARELOAD.Debug and RARELOAD.Debug.Write then
            RARELOAD.Debug.Write("entity_respawn", "WARNING", 0, "No duplicator snapshot found in SavedInfo.entities")
        elseif debugEnabled then
            print("[RARELOAD DEBUG] No duplicator snapshot found in SavedInfo.entities")
        end
        return false
    end

    SnapshotUtils.EnsureIndexMap(snapshot, {
        category = "entity",
        idPrefix = "entity"
    })

    local spawnPos = nil
    if playerSpawnPos then
        if isvector(playerSpawnPos) then
            spawnPos = playerSpawnPos
        elseif istable(playerSpawnPos) and playerSpawnPos.x and playerSpawnPos.y and playerSpawnPos.z then
            spawnPos = Vector(playerSpawnPos.x, playerSpawnPos.y, playerSpawnPos.z)
        end
    end

    local stats = {
        startTime = SysTime(),
        endTime = 0,
        total = snapshot.entityCount or 0,
        restored = 0,
        failed = 0,
        replaced = 0,
        duplicatesRemoved = 0
    }

    local targetOwner = IsValid(requestingPlayer) and requestingPlayer or DuplicatorBridge.FindSnapshotOwner(snapshot)
    debugEnabled = debugEnabled or
        (DebugState and DebugState.IsEnabledForPlayer and DebugState.IsEnabledForPlayer(targetOwner))

    if RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write("entity_respawn", "INFO", 0,
            string.format("Restoring %d entities from duplicator snapshot", snapshot.entityCount or 0),
            { entity = targetOwner })
        RARELOAD.Debug.Write("entity_respawn", "INFO", 1,
            "Target owner: " .. (IsValid(targetOwner) and targetOwner:Nick() or "none"))
    elseif debugEnabled then
        print(string.format("[RARELOAD DEBUG] Restoring %d entities from duplicator snapshot", snapshot.entityCount or 0))
        print(string.format("[RARELOAD DEBUG] Target owner: %s", IsValid(targetOwner) and targetOwner:Nick() or "none"))
    end

    local indexToID = snapshot._indexMap or {}
    local validateClass = RARELOAD.DataUtils and RARELOAD.DataUtils.IsClassSpawnable or nil
    local ok, res, skippedEntities = SnapshotRestore.RestoreWithExistingIDFilter(
        snapshot,
        indexToID,
        "RareloadEntityID",
        requestingPlayer,
        function(err)
            if debugEnabled then
                print(string.format("[RARELOAD DEBUG] Server-context restore failed, retrying with player context: %s",
                    tostring(err)))
            end
        end,
        {
            validateClass = validateClass
        }
    )

    if debugEnabled and #skippedEntities > 0 then
        print(string.format("[RARELOAD DEBUG] Skipped %d existing entities (already on map)", #skippedEntities))
    end

    local spawnedClose = false
    if not ok then
        stats.failed = stats.failed + 1
        stats.endTime = SysTime()
        if debugEnabled then
            print(string.format("[RARELOAD DEBUG] Duplicator restore failed: %s", tostring(res)))
        end
        hook.Run("RareloadEntitiesRestored", stats)
        return false
    end

    local created = res and res.entities or {}
    stats.restored = CountTableEntries(created)

    if RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write("entity_respawn", "INFO", 1,
            string.format("Duplicator created %d entities", stats.restored),
            { entity = targetOwner })
    elseif debugEnabled then
        print(string.format("[RARELOAD DEBUG] Duplicator created %d entities", stats.restored))
    end

    local radiusSq = ENTITY_RESTORATION.PROXIMITY_RADIUS * ENTITY_RESTORATION.PROXIMITY_RADIUS
    for dupIndex, ent in pairs(created) do
        if IsValid(ent) then
            ent.SpawnedByRareload = true
            ent.SavedViaDuplicator = true

            local savedID = indexToID[dupIndex]
            if savedID then
                EntityIdentity.SetID(ent, "RareloadEntityID", savedID)
            end

            if IsValid(targetOwner) and RARELOAD.Ownership then
                RARELOAD.Ownership.SetOwner(ent, targetOwner)
            end
            if spawnPos and ent.GetPos and (ent:GetPos():DistToSqr(spawnPos) <= radiusSq) then
                spawnedClose = true
            end
        end
    end

    stats.endTime = SysTime()

    if RARELOAD.Debug and RARELOAD.Debug.Write then
        local duration = string.format("%.2f", stats.endTime - stats.startTime)
        RARELOAD.Debug.Write("entity_respawn", "INFO", 0, "Entity restoration completed in " .. duration .. " seconds")
        RARELOAD.Debug.Write("entity_respawn", "INFO", 1, "Spawned close to player: " .. tostring(spawnedClose))
    elseif debugEnabled then
        print(string.format("[RARELOAD DEBUG] Entity restoration completed in %.2f seconds",
            stats.endTime - stats.startTime))
        print(string.format("[RARELOAD DEBUG] Spawned close to player: %s", tostring(spawnedClose)))
    end

    hook.Run("RareloadEntitiesRestored", stats)
    return spawnedClose
end

hook.Add("PreCleanupMap", "RareloadSaveEntitiesBeforeCleanup", function()
    local saveEntities = include("rareload/core/save_helpers/rareload_save_entities.lua")
    local mapName = game.GetMap()
    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    for _, ply in ipairs(player.GetHumans()) do
        if IsValid(ply)
            and RARELOAD.GetPlayerSetting(ply, "addonEnabled", true)
            and RARELOAD.GetPlayerSetting(ply, "retainMapEntities", true) then
            local sid = ply:SteamID()
            local saved = saveEntities(ply)
            local normalized = SnapshotUtils.NormalizeBucketForSave(saved)
            local pdata = RARELOAD.playerPositions[mapName][sid] or {}

            -- Never clobber an existing saved snapshot with an invalid/empty capture.
            if normalized then
                pdata.entities = normalized
            end

            RARELOAD.playerPositions[mapName][sid] = pdata

            if RARELOAD.SavePlayerPositionEntry then
                RARELOAD.SavePlayerPositionEntry(ply, pdata)
            end

            if RARELOAD.GetPlayerSetting(ply, "debugEnabled", false) then
                if normalized then
                    local summary = SnapshotUtils.GetSummary(normalized, { category = "entity" }) or {}
                    print(string.format("[RARELOAD] Saved %d entities before map cleanup for %s", #summary, sid))
                else
                    local existing = pdata.entities or {}
                    if SnapshotUtils.HasSnapshot(existing) then
                        local summary = SnapshotUtils.GetSummary(existing, { category = "entity" }) or {}
                        print(string.format(
                            "[RARELOAD] Reused previous entity snapshot (%d entities) before map cleanup for %s",
                            #summary, sid))
                    else
                        print(string.format("[RARELOAD] No entity snapshot available before map cleanup for %s", sid))
                    end
                end
            end
        end
    end
end)
