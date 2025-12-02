---@diagnostic disable: inject-field, undefined-field, global-is-nil
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

util.AddNetworkString("RareloadEntityRestoreProgress")

-- Wrapper function to be called on player spawn
function RARELOAD.RespawnEntitiesForPlayer(ply, data)
    if not IsValid(ply) then return end

    -- Use passed data (from player_positions) or fallback to player_data file
    local savedEntitiesDupe = data or RARELOAD.LoadDataForPlayer(ply, "entities")

    if not savedEntitiesDupe or not savedEntitiesDupe.Entities or next(savedEntitiesDupe.Entities) == nil then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD] No saved entity dupe found to restore.")
        end
        return
    end

    if not duplicator or not duplicator.Paste then
        print("[RARELOAD ERROR] Duplicator system not found for pasting entities!")
        return
    end

    -- Announce start
    net.Start("RareloadEntityRestoreProgress")
    net.WriteFloat(0)
    net.WriteBool(false)
    net.WriteInt(0, 16)
    net.WriteInt(0, 16)
    net.WriteInt(#savedEntitiesDupe.Entities, 16)
    net.Send(ply)

    -- 1. Remove previously restored entities to prevent duplication
    local removedCount = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.SpawnedByRareload and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
            ent:Remove()
            removedCount = removedCount + 1
        end
    end
    if RARELOAD.settings.debugEnabled and removedCount > 0 then
        print("[RARELOAD] Removed " .. removedCount .. " previously restored entities.")
    end

    -- 2. Paste the entire dupe
    -- We run this in a short timer to ensure the player is fully initialized.
    timer.Simple(0.5, function()
        if not IsValid(ply) then return end

        local ok, pastedEntities = pcall(duplicator.Paste, ply, savedEntitiesDupe, {})
        if not ok or not pastedEntities then
            print("[RARELOAD ERROR] Failed to paste entity dupe: " .. tostring(pastedEntities))
            -- Announce failure
            net.Start("RareloadEntityRestoreProgress")
            net.WriteFloat(100)
            net.WriteBool(true)
            net.WriteInt(0, 16)
            net.WriteInt(#savedEntitiesDupe.Entities, 16)
            net.WriteInt(#savedEntitiesDupe.Entities, 16)
            net.Send(ply)
            return
        end

        -- 3. Re-assign our custom IDs and mark the entities
        local restoredCount = 0
        if savedEntitiesDupe.Entities and table.Count(pastedEntities) > 0 then
            for i, dupeEntData in pairs(savedEntitiesDupe.Entities) do
                local newEnt = pastedEntities[i]
                if IsValid(newEnt) and dupeEntData.RareloadEntityID then
                    newEnt.RareloadEntityID = dupeEntData.RareloadEntityID
                    newEnt.SpawnedByRareload = true
                    newEnt.OriginalSpawner = dupeEntData.OriginallySpawnedBy
                    newEnt.WasPlayerSpawned = dupeEntData.WasPlayerSpawned

                    if newEnt.SetNWString then
                        pcall(function() newEnt:SetNWString("RareloadID", newEnt.RareloadEntityID) end)
                    end
                    restoredCount = restoredCount + 1
                end
            end
        end

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Successfully restored " .. restoredCount .. " entities from dupe.")
        end

        -- Announce completion
        net.Start("RareloadEntityRestoreProgress")
        net.WriteFloat(100)
        net.WriteBool(true)
        net.WriteInt(restoredCount, 16)
        net.WriteInt(#savedEntitiesDupe.Entities - restoredCount, 16)
        net.WriteInt(#savedEntitiesDupe.Entities, 16)
        net.Send(ply)

        hook.Run("RareloadEntitiesRestored", {
            total = #savedEntitiesDupe.Entities,
            restored = restoredCount,
            skipped = #savedEntitiesDupe.Entities - restoredCount,
            failed = 0 -- pcall handles full failure
        })
    end)
end

-- This hook will trigger the restoration logic when a player spawns.
-- It replaces the old RARELOAD.RestoreEntities function call.
hook.Add("PlayerSpawn", "Rareload_RespawnPlayerEntities", function(ply)
    if RARELOAD.settings.addonEnabled and RARELOAD.settings.retainMapEntities then
        -- The main restore logic is now more generic and needs to be called from the core spawn handler
        -- to ensure correct load order and access to player data.
        -- This file now primarily provides the implementation for entity-specific restoration.
    end
end)

-- The pre-cleanup save hook needs to be updated to save the dupe
hook.Add("PreCleanupMap", "RareloadSaveEntitiesBeforeCleanup", function()
    if RARELOAD.settings.addonEnabled and RARELOAD.settings.retainMapEntities then
        for _, ply in ipairs(player.GetHumans()) do
            if IsValid(ply) then
                local saveEntities = include("rareload/core/save_helpers/rareload_save_entities.lua")
                local entitiesDupe = saveEntities(ply)

                if entitiesDupe then
                    RARELOAD.SaveDataForPlayer(ply, "entities", entitiesDupe)
                    if RARELOAD.settings.debugEnabled then
                        print(string.format("[RARELOAD] Saved %d entities (as dupe) before map cleanup", #(entitiesDupe.Entities or {})))
                    end
                end

                -- We only need to save for one player
                break 
            end
        end
    end
end)