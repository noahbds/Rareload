---@diagnostic disable: inject-field, undefined-field
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

-- Use shared state hash util (loaded by savers) for consistency
if not (RARELOAD.Util and RARELOAD.Util.GenerateEntityStateHash) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function GenerateEntityStateHash(data)
    if RARELOAD.Util and RARELOAD.Util.GenerateEntityStateHash then
        return RARELOAD.Util.GenerateEntityStateHash(data)
    end
    return tostring(os.time()) -- fallback (shouldn't happen)
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
        if phys.IsGravityEnabled then
            local okGrav, grav = pcall(phys.IsGravityEnabled, phys)
            if okGrav then data.gravityEnabled = grav end
        end
        if phys.GetMaterial then
            local okMat, mat = pcall(phys.GetMaterial, phys)
            if okMat and mat then data.physicsMaterial = mat end
        end
        if phys.GetElasticity then
            local okEl, el = pcall(phys.GetElasticity, phys)
            if okEl and el then data.elasticity = el end
        end
    end

    -- Extended properties captured by saver
    if ent.GetCollisionGroup then data.collisionGroup = ent:GetCollisionGroup() end
    if ent.GetMoveType then data.moveType = ent:GetMoveType() end
    if ent.GetSolid then data.solidType = ent:GetSolid() end
    if ent.GetModelScale then
        local sc = ent:GetModelScale()
        if sc and sc ~= 1 then data.modelScale = sc end
    end
    if ent.GetSpawnFlags then
        local sf = ent:GetSpawnFlags()
        if sf and sf ~= 0 then data.spawnFlags = sf end
    end
    if ent.GetVelocity then
        local vel = ent:GetVelocity()
        if vel.x ~= 0 or vel.y ~= 0 or vel.z ~= 0 then
            data.velocity = { x = vel.x, y = vel.y, z = vel.z }
        end
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

    if savedData.stateHash and existingData.stateHash then
        if savedData.stateHash == existingData.stateHash then
            return false, differences
        else
            if debugOutput then table.insert(differences, "State hash mismatch") end
            return true, differences
        end
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

    if savedData.health ~= nil and isnumber(savedData.health) and existingData.health ~= savedData.health then
        if debugOutput then
            table.insert(differences, "Health: " .. tostring(existingData.health) .. " vs " .. tostring(savedData.health))
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
    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        local ok, tbl = pcall(util.JSONToTable, data)
        if ok and tbl and tbl[mapName] then
            for _, pdata in pairs(tbl[mapName]) do
                if pdata.entities then
                    SavedInfo = SavedInfo or {}
                    SavedInfo.entities = pdata.entities
                    if pdata.pos and type(pdata.pos) == "table" and pdata.pos.x and pdata.pos.y and pdata.pos.z then
                        SavedInfo.pos = Vector(pdata.pos.x, pdata.pos.y, pdata.pos.z)
                    end
                    if pdata.ang and type(pdata.ang) == "table" and pdata.ang.p and pdata.ang.y and pdata.ang.r then
                        SavedInfo.ang = Angle(pdata.ang.p, pdata.ang.y, pdata.ang.r)
                    end
                    break
                end
            end
        end
    end
    if not SavedInfo or not SavedInfo.entities or #SavedInfo.entities == 0 then
        return false
    end
    local stats = {
        total = #SavedInfo.entities,
        restored = 0,
        skipped = 0,
        failed = 0,
        replaced = 0,
        duplicatesRemoved = 0,
        originalStillExists = 0,
        startTime = SysTime(),
        endTime = nil,
        progress = 0
    }
    local entityData = {
        restored = {},
        skipped = {},
        failed = {},
        replaced = {},
        duplicatesRemoved = {}
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
    local originalEntitiesByID = {}
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        if ent.RareloadEntityID then
            entitiesByID[ent.RareloadEntityID] = {
                entity = ent,
                data = GetEntityProperties(ent),
                isOriginal = not ent.SpawnedByRareload
            }
            if not ent.SpawnedByRareload then
                originalEntitiesByID[ent.RareloadEntityID] = ent
            end
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
            if type(pos) == "table" and pos.x and pos.y and pos.z then
                pos = Vector(pos.x, pos.y, pos.z)
            else
                pos = nil
            end
            entData.pos = pos
        end
        if entData.ang and type(entData.ang) ~= "Angle" then
            -- Load centralized conversion functions
            if not RARELOAD or not RARELOAD.DataUtils then
                include("rareload/utils/rareload_data_utils.lua")
            end

            local convertedAngle = RARELOAD.DataUtils.ToAngle(entData.ang)
            entData.ang = convertedAngle
        end
        -- Compute a state hash for saved data (new format) if not present so extended properties differences trigger replacements
        if not entData.stateHash then
            entData.stateHash = GenerateEntityStateHash(entData)
        end

        if not entData.class or type(entData.class) ~= "string" or entData.class == "" then
            stats.failed = stats.failed + 1
            table.insert(entityData.failed, entData)
            table.insert(errorMessages,
                "Missing or invalid class: " .. tostring(entData.class) .. " | Data: " .. util.TableToJSON(entData, true))
            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD DEBUG] Skipping entity due to missing/invalid class: " ..
                    util.TableToJSON(entData, true))
            end
            continue
        end
        if not entData.pos or type(entData.pos) ~= "Vector" then
            stats.failed = stats.failed + 1
            table.insert(entityData.failed, entData)
            table.insert(errorMessages,
                "Missing or invalid position: " ..
                tostring(entData.pos) .. " | Data: " .. util.TableToJSON(entData, true))
            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD DEBUG] Skipping entity due to missing/invalid pos: " .. util.TableToJSON(entData, true))
            end
            continue
        end
        local existingEntry = nil
        local matchMethod = "none"
        local isOriginalStillHere = false
        if entData.id and originalEntitiesByID[entData.id] then
            isOriginalStillHere = true
            stats.originalStillExists = stats.originalStillExists + 1

            local ent = originalEntitiesByID[entData.id]
            if IsValid(ent) then
                -- Sync position and angles to saved data
                if entData.pos and type(entData.pos) == "Vector" then
                    pcall(ent.SetPos, ent, entData.pos)
                end
                if entData.ang and type(entData.ang) == "Angle" then
                    pcall(ent.SetAngles, ent, entData.ang)
                end

                -- Sync health (and max health when available)
                if entData.health ~= nil and isnumber(entData.health) and ent.SetHealth then
                    if entData.maxHealth and entData.maxHealth > 0 and ent.SetMaxHealth then
                        pcall(ent.SetMaxHealth, ent, entData.maxHealth)
                    else
                        -- Ensure saved HP is not clamped by current max health
                        if ent.GetMaxHealth and ent.SetMaxHealth then
                            local curMax = ent:GetMaxHealth() or 0
                            if entData.health > curMax then
                                pcall(ent.SetMaxHealth, ent, entData.health)
                            end
                        end
                    end
                    pcall(ent.SetHealth, ent, entData.health)
                end

                stats.restored = stats.restored + 1
                table.insert(entityData.restored, entData)

                if RARELOAD.settings.debugEnabled then
                    print(string.format(
                        "[RARELOAD] Updated original entity %s (ID: %s) to saved pos/ang/health",
                        tostring(ent), tostring(entData.id)))
                end
            else
                -- If somehow invalid, just record as skipped to avoid spawning a duplicate here
                stats.skipped = stats.skipped + 1
                table.insert(entityData.skipped, entData)
            end
            continue
        end
        if entData.id and entitiesByID[entData.id] then
            existingEntry = entitiesByID[entData.id]
            matchMethod = "id"
        end
        if not existingEntry then
            local pos = entData.pos
            if type(pos) == "table" and pos.x and pos.y and pos.z then
                pos = Vector(pos.x, pos.y, pos.z)
            elseif type(pos) ~= "Vector" then
                pos = util.StringToType(tostring(pos), "Vector")
            end
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
        if existingEntry and not isOriginalStillHere then
            local isDifferent, differences = EntitiesHaveDifferentProperties(existingEntry.data, entData,
                RARELOAD.settings.debugEnabled)
            if not isDifferent then
                stats.skipped = stats.skipped + 1
                table.insert(entityData.skipped, entData)
                if RARELOAD.settings.debugEnabled then
                    print(string.format("[RARELOAD] Skipped identical entity %s (matched by %s)",
                        entData.class, matchMethod))
                end
                continue
            else
                if IsValid(existingEntry.entity) then
                    table.insert(entityData.replaced, {
                        old = existingEntry.data,
                        new = entData,
                        differences = differences
                    })
                    existingEntry.entity:Remove()
                    stats.replaced = stats.replaced + 1
                    if RARELOAD.settings.debugEnabled then
                        print(string.format("[RARELOAD] Replaced entity %s with updated properties (matched by %s)",
                            entData.class, matchMethod))
                    end
                end
            end
        end
        if playerSpawnPos and entData.pos then
            local pos = entData.pos
            if type(pos) == "table" and pos.x and pos.y and pos.z then
                pos = Vector(pos.x, pos.y, pos.z)
            elseif type(pos) ~= "Vector" then
                local success, converted = pcall(util.StringToType, tostring(pos), "Vector")
                if success and converted then
                    pos = converted
                else
                    table.insert(farEntities, entData)
                    continue
                end
            end
            local spawnPos = playerSpawnPos
            if type(spawnPos) == "table" and spawnPos.x and spawnPos.y and spawnPos.z then
                spawnPos = Vector(spawnPos.x, spawnPos.y, spawnPos.z)
            elseif type(spawnPos) ~= "Vector" then
                table.insert(farEntities, entData)
                continue
            end
            local distSqr = pos:DistToSqr(spawnPos)
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
            if entData.id and originalEntitiesByID[entData.id] then
                return false, "Original entity still exists"
            end
            local ent = ents.Create(entData.class)
            if not IsValid(ent) then
                return false, "Failed to create entity: " .. entData.class
            end
            if entData.pos then
                local pos
                if type(entData.pos) == "Vector" then
                    pos = entData.pos
                elseif type(entData.pos) == "table" and entData.pos.x and entData.pos.y and entData.pos.z then
                    pos = Vector(entData.pos.x, entData.pos.y, entData.pos.z)
                else
                    pos = nil
                end
                if pos then
                    ent:SetPos(pos)
                end
            end
            if entData.ang then
                local ang
                if type(entData.ang) == "Angle" then
                    ang = entData.ang
                elseif type(entData.ang) == "table" and entData.ang.p and entData.ang.y and entData.ang.r then
                    ang = Angle(entData.ang.p, entData.ang.y, entData.ang.r)
                elseif type(entData.ang) == "table" and #entData.ang == 3 then
                    ang = Angle(entData.ang[1], entData.ang[2], entData.ang[3])
                else
                    -- Use centralized conversion functions for string and other types
                    if not RARELOAD or not RARELOAD.DataUtils then
                        include("rareload/utils/rareload_data_utils.lua")
                    end
                    ang = RARELOAD.DataUtils.ToAngle(entData.ang)
                    if not ang then
                        ang = util.StringToType(tostring(entData.ang), "Angle")
                    end
                end
                if ang then
                    ent:SetAngles(ang)
                end
            end
            if entData.model and util.IsValidModel(entData.model) then
                ent:SetModel(entData.model)
            end
            if entData.id then
                ent.RareloadEntityID = entData.id
            else
                ent.RareloadEntityID = "ent_" .. ent:EntIndex() .. "_" .. os.time() .. "_" .. math.random(1000, 9999)
            end
            if ent.SetNWString then
                pcall(function() ent:SetNWString("RareloadID", ent.RareloadEntityID) end)
            end
            ent:Spawn()
            if entData.maxHealth and entData.maxHealth > 0 and ent.SetMaxHealth then
                pcall(ent.SetMaxHealth, ent, entData.maxHealth)
            end
            if entData.health ~= nil and isnumber(entData.health) and ent.SetHealth then
                if (not entData.maxHealth or entData.maxHealth <= 0) and ent.GetMaxHealth and ent.SetMaxHealth then
                    local curMax = ent:GetMaxHealth() or 0
                    if entData.health > curMax then
                        pcall(ent.SetMaxHealth, ent, entData.health)
                    end
                end
                pcall(ent.SetHealth, ent, entData.health)
            end
            ent:Activate()
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
            if entData.modelScale and ent.SetModelScale then
                pcall(ent.SetModelScale, ent, entData.modelScale, 0)
            end
            if entData.collisionGroup and ent.SetCollisionGroup then
                pcall(ent.SetCollisionGroup, ent, entData.collisionGroup)
            end
            if entData.moveType and ent.SetMoveType then
                pcall(ent.SetMoveType, ent, entData.moveType)
            end
            if entData.solidType and ent.SetSolid then
                pcall(ent.SetSolid, ent, entData.solidType)
            end
            if entData.spawnFlags and ent.AddSpawnFlags then
                pcall(ent.AddSpawnFlags, ent, entData.spawnFlags)
            end
            if entData.renderMode and ent.SetRenderMode then
                pcall(ent.SetRenderMode, ent, entData.renderMode)
            end
            if entData.renderFX and ent.SetRenderFX then
                pcall(ent.SetRenderFX, ent, entData.renderFX)
            end
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                if entData.frozen then
                    phys:EnableMotion(false)
                end
                if entData.velocity then
                    local vel
                    if type(entData.velocity) == "Vector" then
                        vel = entData.velocity
                    elseif type(entData.velocity) == "table" and entData.velocity.x and entData.velocity.y and entData.velocity.z then
                        vel = Vector(entData.velocity.x, entData.velocity.y, entData.velocity.z)
                    else
                        vel = util.StringToType(tostring(entData.velocity), "Vector")
                    end
                    if vel then
                        phys:SetVelocity(vel)
                    end
                end
                if entData.mass then
                    phys:SetMass(entData.mass)
                end
                if entData.gravityEnabled ~= nil then
                    pcall(phys.EnableGravity, phys, entData.gravityEnabled)
                end
                if entData.physicsMaterial then
                    pcall(phys.SetMaterial, phys, entData.physicsMaterial)
                end
                if entData.elasticity and phys.SetElasticity then
                    pcall(phys.SetElasticity, phys, entData.elasticity)
                end
            end
            if entData.owner then
                for _, p in ipairs(player.GetAll()) do
                    if p:SteamID() == entData.owner then
                        if ent.CPPISetOwner then
                            ent:CPPISetOwner(p)
                        end
                        break
                    end
                end
            end
            if entData.keyvalues and ent.KeyValue then
                for k, v in pairs(entData.keyvalues) do
                    pcall(ent.KeyValue, ent, k, tostring(v))
                end
            end
            if entData.name and ent.SetName then
                pcall(ent.SetName, ent, entData.name)
            end
            ent.SpawnedByRareload = true
            ent.SavedByRareload = true
            ent.RestoreTime = os.time()
            ent.OriginalSpawner = entData.originallySpawnedBy
            ent.WasPlayerSpawned = entData.wasPlayerSpawned
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
        -- No batched spawns; signal completion after immediate phase
        hook.Run("RareloadEntitiesRestored", stats)
    end

    local savedIDs = {}
    for _, d in ipairs(SavedInfo.entities) do
        if d.id then savedIDs[d.id] = true end
    end

    for id, entry in pairs(entitiesByID) do
        local ent = entry.entity
        local isOriginal = entry.isOriginal

        if IsValid(ent) and not savedIDs[id] and not isOriginal then
            if RARELOAD.settings.debugEnabled then
                print(string.format("[RARELOAD] Removing orphaned restored entity %s (id=%s)",
                    tostring(ent), tostring(id)))
            end
            ent:Remove()
            stats.duplicatesRemoved = stats.duplicatesRemoved + 1
            table.insert(entityData.duplicatesRemoved, entry.data)
        end
    end

    -- If there were no far entities, the completion hook was run above.
    -- If there were far entities, the completion hook runs inside ProcessBatch after all spawns.

    return #closeEntities > 0
end

net.Receive("RareloadRespawnEntity", function(len, ply)
    if not IsValid(ply) then return end

    if not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] You need admin privileges to respawn entities")
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
            local savedPos
            if type(savedEntity.pos) == "Vector" then
                savedPos = savedEntity.pos
            elseif type(savedEntity.pos) == "table" and savedEntity.pos.x and savedEntity.pos.y and savedEntity.pos.z then
                savedPos = Vector(savedEntity.pos.x, savedEntity.pos.y, savedEntity.pos.z)
            else
                savedPos = util.StringToType(tostring(savedEntity.pos), "Vector")
            end

            if position:DistToSqr(savedPos) < searchRadiusSqr then
                matchedData = savedEntity
                break
            end
        end
    end

    if matchedData then
        local success, entity = pcall(function()
            local ent = ents.Create(entityClass)
            if not IsValid(ent) then return nil end

            ent:SetPos(position)

            if matchedData.ang then
                local ang
                if type(matchedData.ang) == "Angle" then
                    ang = matchedData.ang
                elseif type(matchedData.ang) == "table" and matchedData.ang.p and matchedData.ang.y and matchedData.ang.r then
                    ang = Angle(matchedData.ang.p, matchedData.ang.y, matchedData.ang.r)
                elseif type(matchedData.ang) == "table" and #matchedData.ang == 3 then
                    ang = Angle(matchedData.ang[1], matchedData.ang[2], matchedData.ang[3])
                else
                    ang = util.StringToType(tostring(matchedData.ang), "Angle")
                end
                if ang then
                    ent:SetAngles(ang)
                end
            end

            if matchedData.model and util.IsValidModel(matchedData.model) then
                ent:SetModel(matchedData.model)
            end

            ent:Spawn()
            -- Set max health before health to avoid clamping, and bump max if only health is provided
            if matchedData.maxHealth and matchedData.maxHealth > 0 and ent.SetMaxHealth then
                pcall(ent.SetMaxHealth, ent, matchedData.maxHealth)
            end
            if matchedData.health ~= nil and isnumber(matchedData.health) and ent.SetHealth then
                if (not matchedData.maxHealth or matchedData.maxHealth <= 0) and ent.GetMaxHealth and ent.SetMaxHealth then
                    local curMax = ent:GetMaxHealth() or 0
                    if matchedData.health > curMax then
                        pcall(ent.SetMaxHealth, ent, matchedData.health)
                    end
                end
                pcall(ent.SetHealth, ent, matchedData.health)
            end
            ent:Activate()
            if matchedData.skin then ent:SetSkin(matchedData.skin) end

            if matchedData.color then
                local color = Color(
                    matchedData.color.r or 255,
                    matchedData.color.g or 255,
                    matchedData.color.b or 255,
                    matchedData.color.a or 255
                )
                ent:SetColor(color)
            end

            if matchedData.material then ent:SetMaterial(matchedData.material) end

            if matchedData.bodygroups then
                for id, value in pairs(matchedData.bodygroups) do
                    local bodygroupID = tonumber(id)
                    if bodygroupID then
                        ent:SetBodygroup(bodygroupID, value)
                    end
                end
            end
            if matchedData.modelScale and ent.SetModelScale then pcall(ent.SetModelScale, ent, matchedData.modelScale, 0) end
            if matchedData.collisionGroup and ent.SetCollisionGroup then
                pcall(ent.SetCollisionGroup, ent,
                    matchedData.collisionGroup)
            end
            if matchedData.moveType and ent.SetMoveType then pcall(ent.SetMoveType, ent, matchedData.moveType) end
            if matchedData.solidType and ent.SetSolid then pcall(ent.SetSolid, ent, matchedData.solidType) end
            if matchedData.spawnFlags and ent.AddSpawnFlags then pcall(ent.AddSpawnFlags, ent, matchedData.spawnFlags) end
            if matchedData.renderMode and ent.SetRenderMode then pcall(ent.SetRenderMode, ent, matchedData.renderMode) end
            if matchedData.renderFX and ent.SetRenderFX then pcall(ent.SetRenderFX, ent, matchedData.renderFX) end

            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                if matchedData.frozen then phys:EnableMotion(false) end
                if matchedData.velocity then
                    local vel
                    if type(matchedData.velocity) == "Vector" then
                        vel = matchedData.velocity
                    elseif type(matchedData.velocity) == "table" and matchedData.velocity.x and matchedData.velocity.y and matchedData.velocity.z then
                        vel = Vector(matchedData.velocity.x, matchedData.velocity.y, matchedData.velocity.z)
                    else
                        vel = util.StringToType(tostring(matchedData.velocity), "Vector")
                    end
                    if vel then
                        phys:SetVelocity(vel)
                    end
                end
                if matchedData.mass then pcall(phys.SetMass, phys, matchedData.mass) end
                if matchedData.gravityEnabled ~= nil then pcall(phys.EnableGravity, phys, matchedData.gravityEnabled) end
                if matchedData.physicsMaterial then pcall(phys.SetMaterial, phys, matchedData.physicsMaterial) end
                if matchedData.elasticity and phys.SetElasticity then
                    pcall(phys.SetElasticity, phys,
                        matchedData.elasticity)
                end
            end

            ent.SpawnedByRareload = true
            ent.SavedByRareload = true
            ent.RespawnedBy = ply:SteamID()
            ent.RespawnTime = os.time()
            if matchedData.keyvalues and ent.KeyValue then
                for k, v in pairs(matchedData.keyvalues) do
                    pcall(ent.KeyValue, ent, k, tostring(v))
                end
            end
            if matchedData.name and ent.SetName then pcall(ent.SetName, ent, matchedData.name) end

            return ent
        end)

        if success and IsValid(entity) then
            if entity then
                if entity.CPPISetOwner then
                    entity:CPPISetOwner(ply)
                end
            end

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
                local saveEntities = include("rareload/core/save_helpers/rareload_save_entities.lua")
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
