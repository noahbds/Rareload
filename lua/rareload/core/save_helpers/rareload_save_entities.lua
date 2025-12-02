---@diagnostic disable: undefined-field, inject-field, need-check-nil

if not RARELOAD then RARELOAD = {} end
if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function GenerateEntityUniqueID(ent)
    return RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID and RARELOAD.Util.GenerateDeterministicID(ent) or
        "ent_legacyid"
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

    local entitiesToSave = {}
    local startTime = SysTime()

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
            local owner = (isfunction(ent.CPPIGetOwner) and ent:CPPIGetOwner()) or nil
            local isOwnerBot = false
            if IsValid(owner) and owner.IsBot then
                local ok, res = pcall(function() return owner:IsBot() end)
                if ok and res then isOwnerBot = true end
            end
            local ownerValid = IsValid(owner) and (isOwnerBot or owner == ply)
            local spawnedByRareload = ent.SpawnedByRareload == true

            if ownerValid or spawnedByRareload then
                table.insert(entitiesToSave, ent)
            end
        end
    end

    if #entitiesToSave == 0 then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] No entities to save.")
        end
        return nil
    end

    local dupe = duplicator.Copy(entitiesToSave)

    if not dupe or not dupe.Entities then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ERROR] Failed to create duplicator copy for entities.")
        end
        return nil
    end

    -- Inject our custom IDs and other metadata into the dupe structure
    for _, ent in ipairs(entitiesToSave) do
        if not ent.RareloadEntityID then
            ent.RareloadEntityID = GenerateEntityUniqueID(ent)
        end

        -- FIX: Access dupe.Entities using the Entity Index
        local dupeEnt = dupe.Entities[ent:EntIndex()]
        if dupeEnt then
            dupeEnt.RareloadEntityID = ent.RareloadEntityID
            dupeEnt.OriginallySpawnedBy = ent.OriginalSpawner or GetOwnerSteamID(ent:CPPIGetOwner())
            dupeEnt.WasPlayerSpawned = IsValid(ent:CPPIGetOwner()) and ent:CPPIGetOwner():IsPlayer()
        end
    end

    if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " ..
            #entitiesToSave .. " entities using duplicator in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")
    end

    return dupe
end