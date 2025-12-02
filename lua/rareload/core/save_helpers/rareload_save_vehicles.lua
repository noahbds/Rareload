---@diagnostic disable: undefined-field, inject-field, need-check-nil

if not RARELOAD then RARELOAD = {} end
if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function GenerateVehicleUniqueID(ent)
    return RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID and RARELOAD.Util.GenerateDeterministicID(ent) or
        "veh_legacyid"
end

local function GetOwnerSteamID(owner)
    if not IsValid(owner) then return nil end
    if owner.SteamID then
        local ok, sid = pcall(owner.SteamID, owner)
        if ok and isstring(sid) then return sid end
    end
    if owner.SteamID64 then
        local ok, sid = pcall(owner.SteamID64, owner)
        if ok and isstring(sid) then return sid end
    end
    return nil
end

return function(ply)
    if not IsValid(ply) then return nil end
    if not duplicator or not duplicator.Copy then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ERROR] Duplicator system not found!")
        end
        return nil
    end

    local vehiclesToSave = {}
    local startTime = SysTime()

    -- Using FindByClass for vehicles is generally reliable.
    for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
        if IsValid(vehicle) then
            local owner = vehicle:CPPIGetOwner()
            local ownerValid = IsValid(owner) and owner:IsPlayer() and owner == ply
            local spawnedByRareload = vehicle.SpawnedByRareload == true

            if ownerValid or spawnedByRareload then
                table.insert(vehiclesToSave, vehicle)
            end
        end
    end

    if #vehiclesToSave == 0 then
        return nil
    end

    local dupe = duplicator.Copy(vehiclesToSave)

    if not dupe or not dupe.Entities then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ERROR] Failed to create duplicator copy for vehicles.")
        end
        return nil
    end

    -- Inject our custom IDs and other metadata into the dupe structure
    for _, vehicle in ipairs(vehiclesToSave) do
        if not vehicle.RareloadVehicleID then
            vehicle.RareloadVehicleID = GenerateVehicleUniqueID(vehicle)
        end
        
        -- FIX: Access dupe.Entities using the Entity Index
        local dupeVeh = dupe.Entities[vehicle:EntIndex()]
        if dupeVeh then
            dupeVeh.RareloadVehicleID = vehicle.RareloadVehicleID
            dupeVeh.OriginallySpawnedBy = GetOwnerSteamID(vehicle:CPPIGetOwner())
        end
    end

    if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " ..
            #vehiclesToSave .. " vehicles using duplicator in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")
    end

    return dupe
end