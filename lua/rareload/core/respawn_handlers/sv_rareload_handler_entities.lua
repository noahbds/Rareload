RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

local PROXIMITY_RADIUS_SQR = 150 * 150

local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local SnapshotRestore = include("rareload/core/respawn_handlers/sv_rareload_snapshot_restore.lua")
local DebugHelpers = include("rareload/debug/sv_debug_helpers.lua")

local WriteDebug = (DebugHelpers and DebugHelpers.MakeWriter)
    and DebugHelpers.MakeWriter("entity_respawn", { gate = true, allowPrintFallback = true, printPrefix = "[RARELOAD DEBUG] " })
    or function() end

function RARELOAD.RestoreEntities(playerSpawnPos, savedInfo, requestingPlayer)
    if not savedInfo or not istable(savedInfo.entities) then return false end
    local snapshot = savedInfo.entities.__duplicator
    if not snapshot then
        WriteDebug(requestingPlayer, "WARNING", "No duplicator snapshot found in SavedInfo.entities")
        return false
    end

    local spawnPos = RARELOAD.DataUtils.ToVector(playerSpawnPos)
    local entityStates = snapshot.entityStates or {}
    local startTime = SysTime()
    local spawnedClose = false

    local ok, info = SnapshotRestore.RestoreCategory({
        bucket = savedInfo.entities,
        fieldName = "RareloadEntityID",
        indexMap = { category = "entity", idPrefix = "entity" },
        requestingPlayer = requestingPlayer,
        restoreOpts = { validateClass = RARELOAD.DataUtils and RARELOAD.DataUtils.IsClassSpawnable or nil },
        onRetry = function(err)
            WriteDebug(requestingPlayer, "WARNING", "Server-context restore failed, retrying with player context", tostring(err))
        end,
        onCreated = function(ent, savedID, dupIndex, entityDefs)
            -- Reapply saved health (the duplicator does not carry current health).
            local st = savedID and entityStates[savedID]
            if st and st.maxHealth and isfunction(ent.SetMaxHealth) then ent:SetMaxHealth(st.maxHealth) end
            if st and st.health and isfunction(ent.SetHealth) then ent:SetHealth(st.health) end

            -- Honor a saved "disable gravity" flag: the duplicator restores Frozen
            -- but not per-physobj gravity, so apply NoGrav ourselves (matches vehicles).
            local def = entityDefs and dupIndex ~= nil and entityDefs[dupIndex]
            if istable(def) and istable(def.PhysicsObjects) and isfunction(ent.GetPhysicsObjectNum) then
                for boneIdx, p in pairs(def.PhysicsObjects) do
                    if istable(p) and p.NoGrav == true then
                        local phys = ent:GetPhysicsObjectNum(tonumber(boneIdx) or 0)
                        if IsValid(phys) then phys:EnableGravity(false) end
                    end
                end
            end

            if spawnPos and ent.GetPos and ent:GetPos():DistToSqr(spawnPos) <= PROXIMITY_RADIUS_SQR then
                spawnedClose = true
            end
        end,
    })

    if info.skipped > 0 then
        WriteDebug(info.targetOwner, "INFO", string.format("Skipped %d existing entities (already on map)", info.skipped))
    end

    if not ok then
        WriteDebug(info.targetOwner, "WARNING", "Duplicator restore failed", tostring(info.error))
        hook.Run("RareloadEntitiesRestored", { total = snapshot.entityCount or 0, restored = 0, failed = 1, skipped = info.skipped })
        return false
    end

    WriteDebug(info.targetOwner, "INFO",
        string.format("Entity restoration completed in %.2fs (%d restored)", SysTime() - startTime, info.restored),
        { "Spawned close to player: " .. tostring(spawnedClose) })

    hook.Run("RareloadEntitiesRestored", { total = snapshot.entityCount or 0, restored = info.restored, skipped = info.skipped })
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
            local normalized = SnapshotUtils.NormalizeBucketForSave(saveEntities(ply))
            local pdata = RARELOAD.playerPositions[mapName][sid] or {}

            -- Never clobber an existing saved snapshot with an invalid/empty capture.
            if normalized then pdata.entities = normalized end
            RARELOAD.playerPositions[mapName][sid] = pdata

            if RARELOAD.SavePlayerPositionEntry then
                RARELOAD.SavePlayerPositionEntry(ply, pdata)
            end

            if RARELOAD.GetPlayerSetting(ply, "debugEnabled", false) then
                local bucket = normalized or pdata.entities
                local n = SnapshotUtils.HasSnapshot(bucket) and #(SnapshotUtils.GetSummary(bucket, { category = "entity" }) or {}) or 0
                print(string.format("[RARELOAD] Entity pre-cleanup save for %s (%d entities)", sid, n))
            end
        end
    end
end)
