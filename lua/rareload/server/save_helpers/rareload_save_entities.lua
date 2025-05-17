return function(ply)
    local CONFIG = {
        MAX_ENTITIES = 1000,
        SAVE_RADIUS = 5000,
        PRIORITY_OWNED = true,
        DEBUG = RARELOAD.settings and RARELOAD.settings.debugEnabled or false,
        SAVE_STATE_HASH = true
    }

    local function DebugLog(msg, ...)
        if CONFIG.DEBUG then
            print(string.format("[RARELOAD ENTITY SAVE] " .. msg, ...))
        end
    end

    local function GenerateEntityUniqueID(ent)
        if not IsValid(ent) then return "invalid_entity" end

        local class = ent:GetClass()
        local pos = ent:GetPos()
        local posStr = math.floor(pos.x) .. "_" .. math.floor(pos.y) .. "_" .. math.floor(pos.z)

        local friendlyName = class:gsub("^.+_", "")

        if ent:GetModel() and ent:GetModel() ~= "" then
            local modelPath = ent:GetModel():lower()
            local modelName = string.match(modelPath, ".*/([^/%.]+)") or "unknown"
            modelName = modelName:gsub("[_]", " ")
            modelName = modelName:gsub("0*(%d+)", "%1")
            friendlyName = modelName
        end

        local shortHash = string.sub(util.CRC(tostring(ent:EntIndex()) .. "_" .. tostring(CurTime()) .. "_" .. posStr), 1,
            5)
        local readableID = friendlyName:sub(1, 1):upper() .. friendlyName:sub(2)
        local technicalID = class .. "_" .. posStr .. "_" .. (ent:GetModel() or "nomodel") .. "_" .. shortHash

        return {
            readableID = readableID .. " #" .. shortHash,
            technicalID = technicalID
        }
    end

    local function GenerateEntityStateHash(data)
        if not CONFIG.SAVE_STATE_HASH then return nil end

        local values = {
            data.material or "",
            tostring(data.skin or 0),
            tostring(data.health or 0),
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

    local startTime = SysTime()
    local entities = {}
    local entityCount = 0
    local skippedCount = 0
    local errorCount = 0
    local playerPos = ply:GetPos()

    local allEntities = ents.GetAll()
    DebugLog("Found %d total entities in the world", #allEntities)

    table.sort(allEntities, function(a, b)
        ---@diagnostic disable-next-line: undefined-field
        local aOwned = IsValid(a:CPPIGetOwner()) and a:CPPIGetOwner() == ply
        ---@diagnostic disable-next-line: undefined-field
        local bOwned = IsValid(b:CPPIGetOwner()) and b:CPPIGetOwner() == ply

        if CONFIG.PRIORITY_OWNED and (aOwned ~= bOwned) then
            return aOwned
        end

        if CONFIG.SAVE_RADIUS > 0 then
            local aDist = a:GetPos():DistToSqr(playerPos)
            local bDist = b:GetPos():DistToSqr(playerPos)
            return aDist < bDist
        end

        return false
    end)

    for _, ent in ipairs(allEntities) do
        if entityCount >= CONFIG.MAX_ENTITIES then
            DebugLog("Entity limit reached (%d). Stopping.", CONFIG.MAX_ENTITIES)
            break
        end

        if not IsValid(ent) then continue end

        if ent:IsPlayer() or ent:IsNPC() or ent:IsVehicle() then
            continue
        end

        if ent:GetClass():match("env_") or
            ent:GetClass():match("_fx") or
            ent:GetClass() == "worldspawn" then
            continue
        end

        if CONFIG.SAVE_RADIUS > 0 and ent:GetPos():DistToSqr(playerPos) > (CONFIG.SAVE_RADIUS * CONFIG.SAVE_RADIUS) then
            skippedCount = skippedCount + 1
            continue
        end

        ---@diagnostic disable-next-line: undefined-field
        local owner = ent:CPPIGetOwner()
        local entID = GenerateEntityUniqueID(ent)
        if not ((IsValid(owner) and owner:IsPlayer()) or ent.SpawnedByRareload) then
            skippedCount = skippedCount + 1
            continue
        end

        local success, entityData = pcall(function()
            local data = {
                id = entID.technicalID,
                readableName = entID.readableID,
                class = ent:GetClass(),
                pos = ent:GetPos(),
                ang = ent:GetAngles(),
                model = ent:GetModel(),
                health = ent:Health(),
                maxHealth = ent:GetMaxHealth(),
                frozen = IsValid(ent:GetPhysicsObject()) and not ent:GetPhysicsObject():IsMotionEnabled(),
                color = ent:GetColor(),
                material = ent:GetMaterial(),
                skin = ent:GetSkin(),
                owner = IsValid(owner) and owner:SteamID() or nil,
                savedTime = os.time()
            }

            if IsValid(ent:GetPhysicsObject()) then
                data.velocity = ent:GetVelocity()
                data.mass = ent:GetPhysicsObject():GetMass()
            end

            if ent:GetNumBodyGroups() > 0 then
                data.bodygroups = {}
                for i = 0, ent:GetNumBodyGroups() - 1 do
                    data.bodygroups[i] = ent:GetBodygroup(i)
                end
            end

            if ent:GetClass() == "prop_dynamic" then
                data.sequence = ent:GetSequence()
                data.playbackRate = ent:GetPlaybackRate()
            end

            data.stateHash = GenerateEntityStateHash(data)

            return data
        end)

        if success and entityData then
            table.insert(entities, entityData)
            entityCount = entityCount + 1
        else
            errorCount = errorCount + 1
            DebugLog("Error saving entity %s: %s", tostring(ent), tostring(entityData))
        end
    end

    local endTime = SysTime()
    DebugLog("Saved %d entities (skipped %d, errors %d) in %.3f seconds",
        entityCount, skippedCount, errorCount, endTime - startTime)

    return entities
end
