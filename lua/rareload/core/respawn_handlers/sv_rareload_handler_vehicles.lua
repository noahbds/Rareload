---@diagnostic disable: inject-field, undefined-field
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

if not (RARELOAD.DataUtils and RARELOAD.DataUtils.LoadDataForPlayer) then
    if file.Exists("rareload/utils/rareload_data_utils.lua", "LUA") then
        include("rareload/utils/rareload_data_utils.lua")
    end
end

-- Wrapper function to be called on player spawn
function RARELOAD.RespawnVehiclesForPlayer(ply)
    if not IsValid(ply) then return end
    
    local savedVehiclesDupe = RARELOAD.LoadDataForPlayer(ply, "vehicles")

    if not savedVehiclesDupe or not savedVehiclesDupe.Entities or #savedVehiclesDupe.Entities == 0 then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD] No saved vehicle dupe found to restore.")
        end
        return
    end

    if not duplicator or not duplicator.Paste then
        print("[RARELOAD ERROR] Duplicator system not found for pasting vehicles!")
        return
    end

    -- 1. Remove previously restored vehicles to prevent duplication
    local removedCount = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.SpawnedByRareload and ent:IsVehicle() then
            ent:Remove()
            removedCount = removedCount + 1
        end
    end
    if RARELOAD.settings.debugEnabled and removedCount > 0 then
        print("[RARELOAD] Removed " .. removedCount .. " previously restored vehicles.")
    end

    -- 2. Paste the entire dupe
    timer.Simple(0.7, function() -- Stagger vehicle spawn slightly after entities
        if not IsValid(ply) then return end

        local ok, pastedVehicles = pcall(duplicator.Paste, ply, savedVehiclesDupe, {})
        if not ok or not pastedVehicles then
            print("[RARELOAD ERROR] Failed to paste vehicle dupe: " .. tostring(pastedVehicles))
            return
        end

        -- 3. Re-assign our custom IDs and mark the entities
        local restoredCount = 0
        if savedVehiclesDupe.Entities and #pastedVehicles > 0 then
            for i, dupeVehData in ipairs(savedVehiclesDupe.Entities) do
                local newVeh = pastedVehicles[i]
                if IsValid(newVeh) and dupeVehData.RareloadVehicleID then
                    newVeh.RareloadVehicleID = dupeVehData.RareloadVehicleID
                    newVeh.SpawnedByRareload = true
                    newVeh.OriginalSpawner = dupeVehData.OriginallySpawnedBy

                    if newVeh.SetNWString then
                        pcall(function() newVeh:SetNWString("RareloadID", newVeh.RareloadVehicleID) end)
                    end
                    restoredCount = restoredCount + 1
                end
            end
        end

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Successfully restored " .. restoredCount .. " vehicles from dupe.")
        end
    end)
end

-- The pre-cleanup save hook needs to be updated to save the dupe
hook.Add("PreCleanupMap", "RareloadSaveVehiclesBeforeCleanup", function()
    if RARELOAD.settings.addonEnabled and RARELOAD.settings.retainVehicles then
        for _, ply in ipairs(player.GetHumans()) do
            if IsValid(ply) then
                local saveVehicles = include("rareload/core/save_helpers/rareload_save_vehicles.lua")
                local vehiclesDupe = saveVehicles(ply)
                
                if vehiclesDupe then
                    RARELOAD.SaveDataForPlayer(ply, "vehicles", vehiclesDupe)
                    if RARELOAD.settings.debugEnabled then
                        print(string.format("[RARELOAD] Saved %d vehicles (as dupe) before map cleanup", #(vehiclesDupe.Entities or {})))
                    end
                end

                -- We only need to save for one player
                break 
            end
        end
    end
end)