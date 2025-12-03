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

if not (RARELOAD.Util and RARELOAD.Util.GenerateEntityStateHash) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

local function CountTableEntries(tbl)
    if not istable(tbl) then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function FindSnapshotOwner(snapshot)
    if not snapshot then return nil end
    local sid64 = snapshot.ownerSteamID64
    local sid = snapshot.ownerSteamID

    for _, ply in ipairs(player.GetAll()) do
        if sid64 and ply.SteamID64 and ply:SteamID64() == sid64 then
            return ply
        end
        if sid and ply.SteamID and ply:SteamID() == sid then
            return ply
        end
    end

    return nil
end
function RARELOAD.RestoreEntities(playerSpawnPos)
    if not SavedInfo or not istable(SavedInfo.entities) then
        return false
    end

    local snapshot = SavedInfo.entities.__duplicator or nil
    if not snapshot then 
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] No duplicator snapshot found in SavedInfo.entities")
        end
        return false 
    end

    SnapshotUtils.EnsureIndexMap(snapshot, {
        category = "entity",
        idPrefix = "entity"
    })

    -- Convert playerSpawnPos to Vector if it's a table
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

    local owner = FindSnapshotOwner(snapshot)
    
    if RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD DEBUG] Restoring %d entities from duplicator snapshot", snapshot.entityCount or 0))
        print(string.format("[RARELOAD DEBUG] Owner: %s", IsValid(owner) and owner:Nick() or "none"))
    end
    
    -- Build index map from duplicator entity index to saved entity ID
    local indexToID = snapshot._indexMap or {}

    -- Check for existing entities to prevent duplication
    local existingIDs = {}
    for _, ent in ipairs(ents.GetAll()) do
        if ent.RareloadEntityID then
            existingIDs[ent.RareloadEntityID] = true
        else
            local nwID = ent:GetNWString("RareloadID", "")
            if nwID ~= "" then
                existingIDs[nwID] = true
            end
        end
    end

    local ok, res = DuplicatorBridge.RestoreSnapshot(snapshot, { 
        player = owner,
        filter = function(index, entData)
            local id = indexToID[index]
            if id and existingIDs[id] then
                if RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Skipping existing entity: " .. id)
                end
                return false
            end
            return true
        end
    })
    local spawnedClose = false
    if not ok then
        stats.failed = stats.failed + 1
        stats.endTime = SysTime()
        if RARELOAD.settings.debugEnabled then
            print(string.format("[RARELOAD DEBUG] Duplicator restore failed: %s", tostring(res)))
        end
        hook.Run("RareloadEntitiesRestored", stats)
        return false
    end

    local created = res and res.entities or {}
    stats.restored = CountTableEntries(created)

    if RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD DEBUG] Duplicator created %d entities", stats.restored))
    end

    -- Mark restored entities, assign IDs, and compute proximity
    local radiusSq = ENTITY_RESTORATION.PROXIMITY_RADIUS * ENTITY_RESTORATION.PROXIMITY_RADIUS
    for dupIndex, ent in pairs(created) do
        if IsValid(ent) then
            ent.SpawnedByRareload = true
            ent.SavedViaDuplicator = true
            
            -- Assign the RareloadID from saved data
            local savedID = indexToID[dupIndex]
            if savedID then
                ent.RareloadEntityID = savedID
                if ent.SetNWString then
                    pcall(ent.SetNWString, ent, "RareloadID", savedID)
                end
            end
            
            if IsValid(owner) and ent.CPPISetOwner then pcall(ent.CPPISetOwner, ent, owner) end
            if spawnPos and ent.GetPos and (ent:GetPos():DistToSqr(spawnPos) <= radiusSq) then
                spawnedClose = true
            end
        end
    end

    stats.endTime = SysTime()
    
    if RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD DEBUG] Entity restoration completed in %.2f seconds", stats.endTime - stats.startTime))
        print(string.format("[RARELOAD DEBUG] Spawned close to player: %s", tostring(spawnedClose)))
    end
    
    hook.Run("RareloadEntitiesRestored", stats)
    return spawnedClose
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
    local savedEntitiesBucket = SavedInfo and SavedInfo.entities or {}
    local savedEntities = SnapshotUtils.GetSummary(savedEntitiesBucket, {
        category = "entity",
        idPrefix = "entity"
    }) or {}
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
                    local summary = SnapshotUtils.GetSummary(SavedInfo.entities, { category = "entity" }) or {}
                    print(string.format("[RARELOAD] Saved %d entities before map cleanup", #summary))
                end

                break
            end
        end
    end
end)
