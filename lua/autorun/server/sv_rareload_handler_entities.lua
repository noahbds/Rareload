---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

util.AddNetworkString("RareloadRespawnEntity")


-- This function is called when the addon need to restore entities from a save file. Allow to restore entities, their position, health, etc.
function RARELOAD.RestoreEntities(playerSpawnPos)
    if not SavedInfo or not SavedInfo.entities or #SavedInfo.entities == 0 then
        return
    end

    local stats = {
        total = #SavedInfo.entities,
        restored = 0,
        skipped = 0,
        failed = 0,
        startTime = SysTime()
    }

    local entityData = {
        restored = {},
        skipped = {},
        failed = {}
    }
    local errorMessages = {}

    local existingEntities = {}
    for _, ent in ipairs(ents.GetAll()) do
        if ent.SpawnedByRareload or ent.SavedByRareload then
            local key = ent:GetClass() .. "|" .. ent:GetModel()
            existingEntities[key] = true
        end
    end

    local closeEntities = {}
    local farEntities = {}
    local proximityRadius = 150

    for _, entData in ipairs(SavedInfo.entities) do
        if not entData.class or not entData.model then
            stats.failed = stats.failed + 1
            table.insert(entityData.failed, entData)
            table.insert(errorMessages, "Missing class or model")
            continue
        end

        local entityKey = entData.class .. "|" .. entData.model

        if existingEntities[entityKey] then
            stats.skipped = stats.skipped + 1
            table.insert(entityData.skipped, entData)
            continue
        end

        if playerSpawnPos then
            local entPos = util.StringToType(entData.pos, "Vector")
            local distSqr = entPos:DistToSqr(playerSpawnPos)

            if distSqr < (proximityRadius * proximityRadius) then
                table.insert(closeEntities, entData)
            else
                table.insert(farEntities, entData)
            end
        else
            table.insert(farEntities, entData)
        end
    end

    local function SpawnEntity(entData)
        local success, result = pcall(function()
            ---@class Entity
            local ent = ents.Create(entData.class)
            if not IsValid(ent) then return false, "Failed to create entity" end

            ent:SetPos(util.StringToType(entData.pos, "Vector"))
            ent:SetAngles(util.StringToType(entData.ang, "Angle"))
            ent:SetModel(entData.model)
            ent:Spawn()

            if entData.health then ent:SetHealth(entData.health) end
            if entData.color then ent:SetColor(util.StringToType(entData.color, "Color")) end
            if entData.material then ent:SetMaterial(entData.material) end

            ent.SpawnedByRareload = true
            ent.SavedByRareload = true

            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                if entData.frozen then
                    phys:EnableMotion(false)
                end

                if entData.velocity then
                    phys:SetVelocity(util.StringToType(entData.velocity, "Vector"))
                end
            end

            return true, ent
        end)

        if success and result == true then
            stats.restored = stats.restored + 1
            table.insert(entityData.restored, entData)
        else
            stats.failed = stats.failed + 1
            local errorMsg = isstring(result) and result or "Unknown error"
            table.insert(entityData.failed, entData)
            table.insert(errorMessages, errorMsg)
        end
    end

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Spawning " .. #closeEntities .. " close entities immediately")
    end

    for _, entData in ipairs(closeEntities) do
        SpawnEntity(entData)
    end

    local delay = RARELOAD.settings.restoreDelay or 1
    timer.Simple(delay, function()
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Spawning " .. #farEntities .. " distant entities with delay")
        end

        for _, entData in ipairs(farEntities) do
            SpawnEntity(entData)
        end

        stats.endTime = SysTime()
    end)

    return #closeEntities > 0
end

-- Used to respawn the entities from the saved entities and npcs viewer.
net.Receive("RareloadRespawnEntity", function(len, ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        ply:ChatPrint("You need admin privileges to respawn entities")
        return
    end

    local entityClass = net.ReadString()
    local position = net.ReadVector()

    if not entityClass or entityClass == "" or not position then
        ply:ChatPrint("Invalid entity data received")
        return
    end

    print("[Rareload] Admin " .. ply:Nick() .. " respawning entity " .. entityClass .. " at " .. tostring(position))

    local matchedData = nil
    local savedEntities = SavedInfo and SavedInfo.entities or {}

    for _, savedEntity in ipairs(savedEntities) do
        if savedEntity.class == entityClass and
            savedEntity.pos and
            position:DistToSqr(Vector(savedEntity.pos.x, savedEntity.pos.y, savedEntity.pos.z)) then
            matchedData = savedEntity
            break
        end
    end

    if matchedData then
        local success, entity = pcall(function()
            local ent = ents.Create(entityClass)
            if not IsValid(ent) then return nil end

            ent:SetPos(position)

            if matchedData.ang then ent:SetAngles(matchedData.ang) end
            if matchedData.model and util.IsValidModel(matchedData.model) then ent:SetModel(matchedData.model) end

            ent:Spawn()
            ent:Activate()

            if matchedData.health then ent:SetHealth(matchedData.health) end
            if matchedData.skin then ent:SetSkin(matchedData.skin) end
            if matchedData.color then
                ent:SetColor(Color(
                    matchedData.color.r or 255,
                    matchedData.color.g or 255,
                    matchedData.color.b or 255,
                    matchedData.color.a or 255
                ))
            end
            if matchedData.material then ent:SetMaterial(matchedData.material) end

            if matchedData.bodygroups then
                for id, value in pairs(matchedData.bodygroups) do
                    local bodygroupID = tonumber(id)
                    if bodygroupID then ent:SetBodygroup(bodygroupID, value) end
                end
            end

            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                if matchedData.frozen then phys:EnableMotion(false) end
                if matchedData.velocity then phys:SetVelocity(matchedData.velocity) end
            end

            ent.SpawnedByRareload = true
            ent.SavedByRareload = true

            return ent
        end)

        if success and IsValid(entity) then
            ply:ChatPrint("Entity " .. entityClass .. " respawned with saved properties!")

            if entity and entity.CPPISetOwner then
                entity:CPPISetOwner(ply)
            end
        else
            local basicEntity = ents.Create(entityClass)
            if IsValid(basicEntity) then
                basicEntity:SetPos(position)
                basicEntity:Spawn()
                basicEntity:Activate()
                ply:ChatPrint("Entity " .. entityClass .. " respawned with basic properties (full restore failed)")
            else
                ply:ChatPrint("Failed to respawn entity: " .. entityClass)
            end
        end
    else
        local entity = ents.Create(entityClass)
        if IsValid(entity) then
            entity:SetPos(position)
            entity:Spawn()
            entity:Activate()
            entity.SpawnedByRareload = true

            ---@diagnostic disable-next-line: undefined-field
            if entity.CPPISetOwner then
                ---@diagnostic disable-next-line: undefined-field
                entity:CPPISetOwner(ply)
            end

            ply:ChatPrint("Entity " .. entityClass .. " respawned with default properties (no saved data found)")
        else
            ply:ChatPrint("Failed to respawn entity: " .. entityClass)
        end
    end
end)
