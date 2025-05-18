RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

util.AddNetworkString("RareloadRespawnEntity")
util.AddNetworkString("RareloadEntityRestoreProgress")

local ENTITY_RESTORATION = {
    PROXIMITY_RADIUS = 150,
    BATCH_SIZE = 10,
    BATCH_DELAY = 0.1,
    INITIAL_DELAY = 1,
    MAX_SPAWN_TIME = 0.05,
    POSITION_TOLERANCE = 5
}

local function GenerateEntityStateHash(data)
    local values = {
        data.material or "",
        tostring(data.skin or 0),
        tostring(data.health or 0)
    }

    if data.color then
        table.insert(values, tostring(data.color.r or 255))
        table.insert(values, tostring(data.color.g or 255))
        table.insert(values, tostring(data.color.b or 255))
        table.insert(values, tostring(data.color.a or 255))
    end

    if data.bodygroups then
        for id, value in pairs(data.bodygroups) do
            table.insert(values, tostring(id) .. "=" .. tostring(value))
        end
    end

    table.insert(values, data.frozen and "1" or "0")
    if data.mass then table.insert(values, tostring(data.mass)) end

    return table.concat(values, "|")
end

local function GetEntityProperties(ent)
    if not IsValid(ent) then return {} end

    local data = {
        class = ent:GetClass(),
        model = ent:GetModel(),
        pos = ent:GetPos(),
        ang = ent:GetAngles(),
        color = ent:GetColor(),
        material = ent:GetMaterial(),
        skin = ent:GetSkin(),
        health = ent:Health(),
        maxHealth = ent:GetMaxHealth(),
        bodygroups = {}
    }

    if ent:GetNumBodyGroups() > 0 then
        for i = 0, ent:GetNumBodyGroups() - 1 do
            data.bodygroups[i] = ent:GetBodygroup(i)
        end
    end

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        data.frozen = not phys:IsMotionEnabled()
        data.mass = phys:GetMass()
    end

    local owner = ent:CPPIGetOwner() and ent:CPPIGetOwner() or nil
    if owner then
        data.owner = IsValid(owner) and owner:SteamID() or nil
    end

    data.stateHash = GenerateEntityStateHash(data)

    if ent.SavedData and ent.SavedData.id then
        data.id = ent.SavedData.id
    end

    return data
end

local function EntitiesHaveDifferentProperties(existingData, savedData, debugOutput)
    if not existingData or not savedData then return true end

    local differences = {}

    if savedData.stateHash and existingData.stateHash and savedData.stateHash ~= existingData.stateHash then
        if debugOutput then table.insert(differences, "State hash mismatch") end
        return true, differences
    end

    if existingData.material ~= (savedData.material or "") then
        if debugOutput then
            table.insert(differences,
                "Material: '" .. tostring(existingData.material) .. "' vs '" .. tostring(savedData.material or "") .. "'")
        end
        return true, differences
    end

    if existingData.skin ~= (savedData.skin or 0) then
        if debugOutput then
            table.insert(differences,
                "Skin: " .. tostring(existingData.skin) .. " vs " .. tostring(savedData.skin or 0))
        end
        return true, differences
    end

    if existingData.health ~= (savedData.health or 0) and savedData.health and savedData.health > 0 then
        if debugOutput then
            table.insert(differences,
                "Health: " .. tostring(existingData.health) .. " vs " .. tostring(savedData.health))
        end
        return true, differences
    end

    if existingData.color and savedData.color then
        local ec = existingData.color
        local sc = type(savedData.color) == "table" and savedData.color or { r = 255, g = 255, b = 255, a = 255 }

        if math.abs(ec.r - (sc.r or 255)) > 2 or
            math.abs(ec.g - (sc.g or 255)) > 2 or
            math.abs(ec.b - (sc.b or 255)) > 2 or
            math.abs(ec.a - (sc.a or 255)) > 2 then
            if debugOutput then
                table.insert(differences, string.format("Color: [%d,%d,%d,%d] vs [%d,%d,%d,%d]",
                    ec.r, ec.g, ec.b, ec.a, sc.r or 255, sc.g or 255, sc.b or 255, sc.a or 255))
            end
            return true, differences
        end
    end

    if existingData.bodygroups and savedData.bodygroups then
        for id, value in pairs(savedData.bodygroups) do
            if existingData.bodygroups[id] ~= value then
                if debugOutput then
                    table.insert(differences,
                        "Bodygroup " .. id .. ": " .. tostring(existingData.bodygroups[id]) .. " vs " .. tostring(value))
                end
                return true, differences
            end
        end
    end

    if existingData.frozen ~= (savedData.frozen or false) then
        if debugOutput then
            table.insert(differences, "Frozen state: " .. (existingData.frozen and "true" or "false") .. " vs " ..
                ((savedData.frozen or false) and "true" or "false"))
        end
        return true, differences
    end

    if existingData.mass and savedData.mass and math.abs(existingData.mass - savedData.mass) > 0.1 then
        if debugOutput then
            table.insert(differences, "Mass: " .. tostring(existingData.mass) .. " vs " .. tostring(savedData.mass))
        end
        return true, differences
    end

    return false, differences
end

function RARELOAD.RestoreEntities(playerSpawnPos)
    if not SavedInfo or not SavedInfo.entities or #SavedInfo.entities == 0 then
        return false
    end

    local stats = {
        total = #SavedInfo.entities,
        restored = 0,
        skipped = 0,
        failed = 0,
        replaced = 0,
        startTime = SysTime(),
        endTime = nil,
        progress = 0
    }

    local entityData = {
        restored = {},
        skipped = {},
        failed = {},
        replaced = {}
    }
    local errorMessages = {}

    local closeEntities = {}
    local farEntities = {}
    local proximityRadiusSqr = ENTITY_RESTORATION.PROXIMITY_RADIUS * ENTITY_RESTORATION.PROXIMITY_RADIUS

    local admins = {}
    for _, p in ipairs(player.GetAll()) do
        if p:IsAdmin() then
            table.insert(admins, p)
        end
    end

    local function UpdateProgress(current, total)
        stats.progress = math.Clamp(current / total * 100, 0, 100)

        for _, admin in ipairs(admins) do
            if IsValid(admin) then
                net.Start("RareloadEntityRestoreProgress")
                net.WriteFloat(stats.progress)
                net.WriteBool(current >= total)
                net.WriteInt(stats.restored, 16)
                net.WriteInt(stats.skipped, 16)
                net.WriteInt(stats.failed, 16)
                net.Send(admin)
            end
        end
    end

    local existingEntities = {}
    local entitiesByID = {}

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end

        if ent.SavedData and ent.SavedData.id then
            entitiesByID[ent.SavedData.id] = {
                entity = ent,
                data = GetEntityProperties(ent)
            }
        end

        if ent.SpawnedByRareload or ent.SavedByRareload then
            local pos = ent:GetPos()
            local key = string.format("%s|%s|%d,%d,%d",
                ent:GetClass(),
                ent:GetModel() or "nomodel",
                math.Round(pos.x / ENTITY_RESTORATION.POSITION_TOLERANCE) * ENTITY_RESTORATION.POSITION_TOLERANCE,
                math.Round(pos.y / ENTITY_RESTORATION.POSITION_TOLERANCE) * ENTITY_RESTORATION.POSITION_TOLERANCE,
                math.Round(pos.z / ENTITY_RESTORATION.POSITION_TOLERANCE) * ENTITY_RESTORATION.POSITION_TOLERANCE)

            existingEntities[key] = {
                entity = ent,
                data = GetEntityProperties(ent)
            }
        end
    end

    for _, entData in ipairs(SavedInfo.entities) do
        local pos = entData.pos
        if pos and type(pos) ~= "Vector" then
            pos = util.StringToType(entData.pos, "Vector")
        end

        if not entData.class or not entData.pos then
            stats.failed = stats.failed + 1
            table.insert(entityData.failed, entData)
            table.insert(errorMessages, "Missing class or position data")
            continue
        end

        local existingEntry = nil
        local matchMethod = "none"

        if entData.id and entitiesByID[entData.id] then
            existingEntry = entitiesByID[entData.id]
            matchMethod = "id"
        end

        if not existingEntry then
            local pos = util.StringToType(entData.pos, "Vector")
            local key = string.format("%s|%s|%d,%d,%d",
                entData.class,
                entData.model or "nomodel",
                math.Round(pos.x / ENTITY_RESTORATION.POSITION_TOLERANCE) * ENTITY_RESTORATION.POSITION_TOLERANCE,
                math.Round(pos.y / ENTITY_RESTORATION.POSITION_TOLERANCE) * ENTITY_RESTORATION.POSITION_TOLERANCE,
                math.Round(pos.z / ENTITY_RESTORATION.POSITION_TOLERANCE) * ENTITY_RESTORATION.POSITION_TOLERANCE)

            existingEntry = existingEntities[key]
            if existingEntry then
                matchMethod = "position"
            end
        end

        if existingEntry then
            local isDifferent, differences = EntitiesHaveDifferentProperties(existingEntry.data, entData,
                RARELOAD.settings.debugEnabled)

            if isDifferent then
                if IsValid(existingEntry.entity) then
                    table.insert(entityData.replaced, {
                        old = existingEntry.data,
                        new = entData,
                        differences = differences
                    })

                    existingEntry.entity:Remove()

                    if existingEntry.data.id then
                        entitiesByID[existingEntry.data.id] = nil
                    end

                    local pos = existingEntry.entity:GetPos()
                    local key = string.format("%s|%s|%d,%d,%d",
                        existingEntry.entity:GetClass(),
                        existingEntry.entity:GetModel() or "nomodel",
                        math.Round(pos.x / ENTITY_RESTORATION.POSITION_TOLERANCE) * ENTITY_RESTORATION
                        .POSITION_TOLERANCE,
                        math.Round(pos.y / ENTITY_RESTORATION.POSITION_TOLERANCE) * ENTITY_RESTORATION
                        .POSITION_TOLERANCE,
                        math.Round(pos.z / ENTITY_RESTORATION.POSITION_TOLERANCE) * ENTITY_RESTORATION
                        .POSITION_TOLERANCE)

                    existingEntities[key] = nil

                    stats.replaced = stats.replaced + 1

                    if RARELOAD.settings.debugEnabled then
                        print(string.format("[RARELOAD] Replaced entity %s with updated properties (matched by %s)",
                            entData.class, matchMethod))

                        if differences and #differences > 0 then
                            for i, diff in ipairs(differences or {}) do
                                print("  - " .. diff)
                            end
                        end
                    end
                end
            else
                stats.skipped = stats.skipped + 1
                table.insert(entityData.skipped, entData)
                if RARELOAD.settings.debugEnabled then
                    print(string.format("[RARELOAD] Skipped entity %s (matched by %s) - properties unchanged",
                        entData.class, matchMethod))
                end
                continue
            end
        end

        if playerSpawnPos and pos then
            local distSqr = pos:DistToSqr(playerSpawnPos)
            if distSqr < proximityRadiusSqr then
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
            if not entData.class or entData.class == "" then
                return false, "Invalid entity class"
            end

            ---@class Entity
            local ent = ents.Create(entData.class)
            if not IsValid(ent) then
                return false, "Failed to create entity: " .. entData.class
            end

            if entData.pos then
                local pos = type(entData.pos) == "Vector" and entData.pos or
                    util.StringToType(entData.pos, "Vector")
                ent:SetPos(pos)
            end

            if entData.ang then
                local ang = type(entData.ang) == "Angle" and entData.ang or
                    util.StringToType(entData.ang, "Angle")
                ent:SetAngles(ang)
            end

            if entData.model and util.IsValidModel(entData.model) then
                ent:SetModel(entData.model)
            end

            ent:Spawn()
            ent:Activate()

            if entData.health and entData.health > 0 then
                ent:SetHealth(entData.health)
            end

            if entData.maxHealth and entData.maxHealth > 0 then
                ent:SetMaxHealth(entData.maxHealth)
            end

            if entData.color then
                local color
                if type(entData.color) == "table" then
                    color = Color(
                        entData.color.r or 255,
                        entData.color.g or 255,
                        entData.color.b or 255,
                        entData.color.a or 255
                    )
                else
                    color = util.StringToType(entData.color, "Color")
                end
                ent:SetColor(color)
            end

            if entData.material then
                ent:SetMaterial(entData.material)
            end

            if entData.skin then
                ent:SetSkin(entData.skin)
            end

            if entData.bodygroups then
                for id, value in pairs(entData.bodygroups) do
                    local bodygroupID = tonumber(id)
                    if bodygroupID and value then
                        ent:SetBodygroup(bodygroupID, value)
                    end
                end
            end

            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                if entData.frozen then
                    phys:EnableMotion(false)
                end

                if entData.velocity then
                    local vel = type(entData.velocity) == "Vector" and entData.velocity or
                        util.StringToType(entData.velocity, "Vector")
                    phys:SetVelocity(vel)
                end

                if entData.mass then
                    phys:SetMass(entData.mass)
                end
            end

            if entData.owner then
                for _, p in ipairs(player.GetAll()) do
                    if p:SteamID() == entData.owner then
                        ---@diagnostic disable-next-line: undefined-field
                        if ent.CPPISetOwner then
                            ---@diagnostic disable-next-line: undefined-field
                            ent:CPPISetOwner(p)
                        end
                        break
                    end
                end
            end

            ent.SpawnedByRareload = true
            ent.SavedByRareload = true
            ent.RestoreTime = os.time()

            ent.SavedData = table.Copy(entData)

            if entData.stateHash then
                ent.InitialStateHash = entData.stateHash
            end

            return true, ent
        end)

        if success and result == true then
            stats.restored = stats.restored + 1
            table.insert(entityData.restored, entData)
            return true
        else
            stats.failed = stats.failed + 1
            local errorMsg = isstring(result) and result or "Unknown error"
            table.insert(entityData.failed, entData)
            table.insert(errorMessages, errorMsg)
            return false
        end
    end

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Spawning " .. #closeEntities .. " close entities immediately")
    end

    for _, entData in ipairs(closeEntities) do
        SpawnEntity(entData)
    end

    UpdateProgress(stats.restored + stats.skipped, stats.total)

    if #farEntities > 0 then
        local batchCount = math.ceil(#farEntities / ENTITY_RESTORATION.BATCH_SIZE)
        local currentBatch = 0

        local function ProcessBatch()
            local startBatchTime = SysTime()
            local entitiesProcessed = 0

            while currentBatch < #farEntities and
                (SysTime() - startBatchTime) < ENTITY_RESTORATION.MAX_SPAWN_TIME and
                entitiesProcessed < ENTITY_RESTORATION.BATCH_SIZE do
                currentBatch = currentBatch + 1
                local entData = farEntities[currentBatch]

                if SpawnEntity(entData) then
                    entitiesProcessed = entitiesProcessed + 1
                end
            end

            UpdateProgress(stats.restored + stats.skipped, stats.total)

            if currentBatch < #farEntities then
                timer.Simple(ENTITY_RESTORATION.BATCH_DELAY, ProcessBatch)
            else
                stats.endTime = SysTime()
                if RARELOAD.settings.debugEnabled then
                    print(string.format("[RARELOAD DEBUG] Entity restoration completed in %.2f seconds:",
                        stats.endTime - stats.startTime))
                    print(string.format("  - Total: %d", stats.total))
                    print(string.format("  - Restored: %d", stats.restored))
                    print(string.format("  - Skipped: %d", stats.skipped))
                    print(string.format("  - Failed: %d", stats.failed))
                    print(string.format("  - Replaced: %d", stats.replaced))
                end

                UpdateProgress(stats.total, stats.total)

                if #errorMessages > 0 and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Entity restoration errors:")
                    for i, err in ipairs(errorMessages) do
                        if i <= 5 then
                            print("  - " .. err)
                        end
                    end
                    if #errorMessages > 5 then
                        print("  - ..." .. (#errorMessages - 5) .. " more errors")
                    end
                end

                hook.Run("RareloadEntitiesRestored", stats)
            end
        end

        timer.Simple(ENTITY_RESTORATION.INITIAL_DELAY, ProcessBatch)
    else
        stats.endTime = SysTime()
        UpdateProgress(stats.total, stats.total)
    end

    do
        local savedIDs = {}
        for _, d in ipairs(SavedInfo.entities) do
            if d.id then savedIDs[d.id] = true end
        end

        for key, entry in pairs(existingEntities) do
            local ent = entry.entity
            local id  = entry.data.id
            if IsValid(ent) and not (id and savedIDs[id]) then
                if RARELOAD.settings.debugEnabled then
                    print(("[RARELOAD] Removing orphaned entity %s (id=%s)"):format(tostring(ent), tostring(id)))
                end
                ent:Remove()
                stats.failed = stats.failed + 1
                table.insert(errorMessages, "Removed orphaned entity " .. tostring(id or key))
            end
        end
    end

    return #closeEntities > 0
end

net.Receive("RareloadRespawnEntity", function(len, ply)
    if not IsValid(ply) then return end

    if not RARELOAD.Admin.HasPermission(ply, "entity_restore") then
        ply:ChatPrint("[RARELOAD] You need permission to respawn entities")
        return
    end

    local entityClass = net.ReadString()
    local position = net.ReadVector()

    if not entityClass or entityClass == "" or not position or position:IsZero() then
        ply:ChatPrint("[RARELOAD] Invalid entity data received")
        return
    end

    if RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD] Admin %s respawning %s at %s",
            ply:Nick(), entityClass, tostring(position)))
    end

    local matchedData = nil
    local savedEntities = SavedInfo and SavedInfo.entities or {}
    local searchRadiusSqr = 150 * 150

    for _, savedEntity in ipairs(savedEntities) do
        if savedEntity.class == entityClass and savedEntity.pos then
            local savedPos = type(savedEntity.pos) == "Vector" and savedEntity.pos or
                Vector(savedEntity.pos.x, savedEntity.pos.y, savedEntity.pos.z)

            if position:DistToSqr(savedPos) < searchRadiusSqr then
                matchedData = savedEntity
                break
            end
        end
    end

    if matchedData then
        local success, entity = pcall(function()
            local ent = ents.Create(entityClass)
            if IsValid(ent) then
                ent:SetPos(position)
                if matchedData.ang then ent:SetAngles(matchedData.ang) end
                if matchedData.model and util.IsValidModel(matchedData.model) then ent:SetModel(matchedData.model) end
                ent:Spawn()
                ent:Activate()

                if matchedData.health then ent:SetHealth(matchedData.health) end
                if matchedData.skin then ent:SetSkin(matchedData.skin) end

                if matchedData.bodygroups then
                    for id, value in pairs(matchedData.bodygroups) do
                        local bodygroupID = tonumber(id)
                        if bodygroupID then
                            ent:SetBodygroup(bodygroupID, value)
                        end
                    end
                end

                if matchedData.frozen then
                    local phys = ent:GetPhysicsObject()
                    if IsValid(phys) then phys:EnableMotion(false) end
                end

                if matchedData.color then
                    ent:SetColor(Color(
                        matchedData.color.r or 255,
                        matchedData.color.g or 255,
                        matchedData.color.b or 255,
                        matchedData.color.a or 255
                    ))
                end

                ent.SpawnedByRareload = true
                ent.SavedByRareload = true

                if ent.CPPISetOwner then
                    ent:CPPISetOwner(ply)
                end

                return ent
            end
        end)

        if success and IsValid(entity) then
            ply:ChatPrint("[RARELOAD] Entity " .. entityClass .. " respawned with saved properties!")
        else
            local basicEntity = ents.Create(entityClass)
            if IsValid(basicEntity) then
                basicEntity:SetPos(position)
                basicEntity:Spawn()
                basicEntity:Activate()

                if basicEntity.CPPISetOwner then
                    basicEntity:CPPISetOwner(ply)
                end

                basicEntity.SpawnedByRareload = true
                ply:ChatPrint("[RARELOAD] Entity " ..
                    entityClass .. " respawned with basic properties (full restore failed)")
            else
                ply:ChatPrint("[RARELOAD] Failed to respawn entity: " .. entityClass)
            end
        end
    else
        local entity = ents.Create(entityClass)
        if IsValid(entity) then
            entity:SetPos(position)
            entity:Spawn()
            entity:Activate()
            entity.SpawnedByRareload = true

            if entity.CPPISetOwner then
                entity:CPPISetOwner(ply)
            end

            ply:ChatPrint("[RARELOAD] Entity " ..
                entityClass .. " respawned with default properties (no saved data found)")
        else
            ply:ChatPrint("[RARELOAD] Failed to respawn entity: " .. entityClass)
        end
    end
end)

hook.Add("PreCleanupMap", "RareloadSaveEntitiesBeforeCleanup", function()
    if RARELOAD.settings.addonEnabled and RARELOAD.settings.retainMapEntities then
        for _, ply in ipairs(player.GetHumans()) do
            if IsValid(ply) then
                local saveEntities = include("rareload/server/save_helpers/rareload_save_entities.lua")
                SavedInfo = SavedInfo or {}
                SavedInfo.entities = saveEntities(ply)

                if RARELOAD.settings.debugEnabled then
                    print(string.format("[RARELOAD] Saved %d entities before map cleanup", #(SavedInfo.entities or {})))
                end

                break
            end
        end
    end
end)
