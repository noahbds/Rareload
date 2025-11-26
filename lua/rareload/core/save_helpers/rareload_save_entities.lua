if not RARELOAD then RARELOAD = {} end
if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function GenerateEntityUniqueID(ent)
    return RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID and RARELOAD.Util.GenerateDeterministicID(ent) or ("ent_" .. ent:EntIndex())
end

local function GetOwnerSteamID(owner)
    if not IsValid(owner) then return nil end
    if owner:IsPlayer() then return owner:SteamID() end
    return nil
end

return function(ply)
    if not IsValid(ply) then return {} end

    local entities = {}
    local count = 0
    local startTime = SysTime()

    local ignoredClasses = {
        ["gmod_hands"] = true,
        ["physgun_beam"] = true,
        ["worldspawn"] = true,
        ["predicted_viewmodel"] = true,
    }

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() and not ent:IsWeapon() then
            local class = ent:GetClass()
            if ignoredClasses[class] then goto continue end

            local owner = (isfunction(ent.CPPIGetOwner) and ent:CPPIGetOwner()) or nil
            local isOwnerBot = (IsValid(owner) and owner:IsBot())
            local ownerValid = IsValid(owner) and (isOwnerBot or owner == ply)
            if ownerValid or ent.SpawnedByRareload then
                local dupData = duplicator.CopyEntTable(ent)

                if dupData then
                    count = count + 1
                    if not ent.RareloadEntityID then
                        ent.RareloadEntityID = GenerateEntityUniqueID(ent)
                    end

                    local entityEntry = {
                        duplicatorData = dupData,
                        
                        id = ent.RareloadEntityID,
                        class = class,
                        pos = ent:GetPos(),
                        ang = ent:GetAngles(),
                        model = ent:GetModel(),
                        owner = GetOwnerSteamID(owner),
                        originallySpawnedBy = ent.OriginalSpawner or GetOwnerSteamID(owner),
                        spawnTime = ent.SpawnTime or os.time(),
                        SavedByRareload = true
                    }
                    if ent.Health then entityEntry.health = ent:Health() end
                    if ent.GetMaxHealth then entityEntry.maxHealth = ent:GetMaxHealth() end

                    table.insert(entities, entityEntry)
                    
                    ent.SavedByRareload = true
                end
            end
        end
        ::continue::
    end

    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " .. count .. " entities using Duplicator in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")
    end

    return entities
end