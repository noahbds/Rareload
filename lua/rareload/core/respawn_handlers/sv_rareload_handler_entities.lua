RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

util.AddNetworkString("RareloadRespawnEntity")
util.AddNetworkString("RareloadEntityRestoreProgress")

local function IsEntityAlreadyExists(id)
    if not id then return false end
    for _, ent in ipairs(ents.GetAll()) do
        if ent.RareloadEntityID == id then return true end
    end
    return false
end

function RARELOAD.RestoreEntities(playerSpawnPos)
    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"
    
    if not file.Exists(filePath, "DATA") then return false end
    
    local data = file.Read(filePath, "DATA")
    local ok, tbl = pcall(util.JSONToTable, data)
    
    if not ok or not tbl or not tbl[mapName] then return false end

    local entitiesToSpawn = nil
    for steamID, pdata in pairs(tbl[mapName]) do
        if pdata.entities then
            entitiesToSpawn = pdata.entities
            SavedInfo = SavedInfo or {}
            SavedInfo.entities = pdata.entities
            break
        end
    end

    if not entitiesToSpawn or #entitiesToSpawn == 0 then return false end

    local stats = { restored = 0, failed = 0, skipped = 0, total = #entitiesToSpawn }
    local proximityRadiusSqr = 200 * 200

    for _, entData in ipairs(entitiesToSpawn) do
        if entData.id and IsEntityAlreadyExists(entData.id) then
            stats.skipped = stats.skipped + 1
            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD] Skipped existing entity: " .. (entData.class or "?"))
            end
            goto continue
        end

        if entData.duplicatorData then
            local ownerPly = nil
            if entData.owner then
                ownerPly = player.GetBySteamID(entData.owner)
            end

            local ent = duplicator.CreateEntityFromTable(ownerPly, entData.duplicatorData)

            if IsValid(ent) then
                ent.SpawnedByRareload = true
                ent.SavedByRareload = true
                ent.RareloadEntityID = entData.id
                ent.OriginalSpawner = entData.originallySpawnedBy
                ent.RespawnTime = os.time()

                if ent.SetNWString and entData.id then
                    ent:SetNWString("RareloadID", entData.id)
                end

                if entData.pos then
                    local pos = Vector(entData.pos.x, entData.pos.y, entData.pos.z)
                    ent:SetPos(pos)
                end
                if entData.ang then
                    local ang = Angle(entData.ang.p, entData.ang.y, entData.ang.r)
                    ent:SetAngles(ang)
                end

                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    if not entData.duplicatorData.Frozen then
                        phys:Wake()
                    end
                end

                stats.restored = stats.restored + 1
            else
                stats.failed = stats.failed + 1
                if RARELOAD.settings.debugEnabled then
                    print("[RARELOAD] Duplicator failed to create: " .. (entData.class or "unknown"))
                end
            end
        else
            stats.failed = stats.failed + 1
        end
        ::continue::
    end

    hook.Run("RareloadEntitiesRestored", stats)
    
    if RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD] Restoration Complete: %d restored, %d skipped, %d failed.", 
            stats.restored, stats.skipped, stats.failed))
    end

    return stats.restored > 0
end

net.Receive("RareloadRespawnEntity", function(len, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    
    local entityClass = net.ReadString()
    local position = net.ReadVector()

    local matchedData = nil
    local savedEntities = (SavedInfo and SavedInfo.entities) or {}
    
    for _, savedEntity in ipairs(savedEntities) do
        local sPos = Vector(savedEntity.pos.x, savedEntity.pos.y, savedEntity.pos.z)
        if savedEntity.class == entityClass and sPos:DistToSqr(position) < 2500 then
            matchedData = savedEntity
            break
        end
    end

    if matchedData and matchedData.duplicatorData then
        local ent = duplicator.CreateEntityFromTable(ply, matchedData.duplicatorData)
        if IsValid(ent) then
            ent.SpawnedByRareload = true
            ent.RareloadEntityID = matchedData.id
            ent:SetPos(position)
            ply:ChatPrint("[RARELOAD] Entity restored via Duplicator.")
        else
            ply:ChatPrint("[RARELOAD] Duplicator failed to spawn entity.")
        end
    else
        ply:ChatPrint("[RARELOAD] No saved data found for this entity location.")
    end
end)