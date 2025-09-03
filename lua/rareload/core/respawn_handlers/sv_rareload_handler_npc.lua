---@diagnostic disable: inject-field, undefined-field, need-check-nil, param-type-mismatch
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
local npcRestoreLogs = {}
local debugEnabled = false

util.AddNetworkString("RareloadRespawnNPC")

if not RARELOAD or not RARELOAD.DataUtils then
    include("rareload/utils/rareload_data_utils.lua")
end

-- Load shared deterministic ID / hash utilities (used by savers) if not already present
if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

RARELOAD._MapReady = RARELOAD._MapReady or false
RARELOAD._MapReadyTime = RARELOAD._MapReadyTime or 0
RARELOAD._NPCSpawnQueue = RARELOAD._NPCSpawnQueue or {}

hook.Add("InitPostEntity", "RARELOAD_MapReady", function()
    RARELOAD._MapReady = true
    RARELOAD._MapReadyTime = CurTime()
    debugEnabled = RARELOAD.settings.debugEnabled or false

    if debugEnabled then
        RARELOAD.Debug.Log("INFO", "Map Ready", { "InitPostEntity fired", "Ready time: " .. RARELOAD._MapReadyTime })
    end
end)

hook.Add("PostCleanupMap", "RARELOAD_MapReadyAfterCleanup", function()
    timer.Simple(0, function()
        RARELOAD._MapReady = true
        RARELOAD._MapReadyTime = CurTime()
        debugEnabled = RARELOAD.settings.debugEnabled or false

        if debugEnabled then
            RARELOAD.Debug.Log("INFO", "Map Ready After Cleanup",
                { "PostCleanupMap processed", "Ready time: " .. RARELOAD._MapReadyTime })
        end
    end)
end)

function RARELOAD.IsMapReady()
    return RARELOAD._MapReady == true
end

local vectorCache = {}
function RARELOAD.CoerceVector(pos)
    if isvector and isvector(pos) then return pos end

    local cacheKey = tostring(pos)
    if vectorCache[cacheKey] then return vectorCache[cacheKey] end

    local result = nil
    if istable(pos) then
        local x = pos.x ~= nil and pos.x or pos[1]
        local y = pos.y ~= nil and pos.y or pos[2]
        local z = pos.z ~= nil and pos.z or pos[3]
        if x ~= nil and y ~= nil and z ~= nil then
            result = Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
        end
    elseif isstring(pos) and RARELOAD and RARELOAD.DataUtils and RARELOAD.DataUtils.ToVector then
        local ok, vec = pcall(RARELOAD.DataUtils.ToVector, pos)
        if ok and isvector and isvector(vec) then result = vec end
    end

    if result then vectorCache[cacheKey] = result end
    return result
end

function RARELOAD.RestoreNPCs()
    if not SavedInfo or not SavedInfo.npcs or #SavedInfo.npcs == 0 then
        if debugEnabled then
            RARELOAD.Debug.Log("INFO", "NPC Restoration Skipped", { "No NPCs to restore" })
        end
        return
    end

    if not RARELOAD.IsMapReady() then
        if debugEnabled then
            RARELOAD.Debug.Log("WARN", "Map Not Ready", { "Deferring NPC restoration until InitPostEntity" })
        end

        hook.Add("InitPostEntity", "RARELOAD_RestoreNPCs_OnReady", function()
            hook.Remove("InitPostEntity", "RARELOAD_RestoreNPCs_OnReady")
            timer.Simple(RARELOAD.settings.npcRestoreDelay or 1, RARELOAD.RestoreNPCs)
        end)
        return
    end

    local delay = RARELOAD.settings.npcRestoreDelay or 1
    local batchSize = math.max(RARELOAD.settings.npcBatchSize or 8, 3)
    local interval = math.max(RARELOAD.settings.npcSpawnInterval or 0.08, 0.05)

    if debugEnabled then
        RARELOAD.Debug.Log("INFO", "NPC Restoration Started", {
            "Total NPCs: " .. #SavedInfo.npcs,
            "Batch size: " .. batchSize,
            "Interval: " .. interval .. "s",
            "Initial delay: " .. delay .. "s"
        })
    end

    timer.Simple(delay, function()
        local stats = {
            total = #SavedInfo.npcs,
            restored = 0,
            skipped = 0,
            failed = 0,
            relationshipsRestored = 0,
            schedulesRestored = 0,
            targetsSet = 0,
            startTime = SysTime(),
            endTime = 0,
            errors = {}
        }

        local npcDataStats = { restored = {}, skipped = {}, failed = {} }
        local spawnedNPCsByID = {}
        local pendingRelations = {}
        local npcsToCreate = table.Copy(SavedInfo.npcs)
        local existingNpcs = RARELOAD.CollectExistingNPCs(spawnedNPCsByID)

        local function ProcessBatch()
            local count = 0
            local batchStart = SysTime()
            local processed = {}

            while #npcsToCreate > 0 and count < batchSize and (SysTime() - batchStart) < 0.08 do
                local npcData = table.remove(npcsToCreate, 1)
                count = count + 1

                if not npcData.class then
                    stats.failed = stats.failed + 1
                    table.insert(stats.errors, "Missing NPC class for entry #" .. count)
                    table.insert(npcDataStats.failed, npcData)
                    continue
                end

                local posKey = (RARELOAD and RARELOAD.DataUtils and RARELOAD.DataUtils.PositionToString(npcData.pos, 2))
                    or tostring(npcData.pos)
                local entityKey = npcData.class .. "|" .. (npcData.model or "") .. "|" .. posKey

                if (npcData.id and spawnedNPCsByID[npcData.id]) or existingNpcs[entityKey] then
                    stats.skipped = stats.skipped + 1
                    table.insert(npcDataStats.skipped, npcData)
                    if debugEnabled then
                        table.insert(processed, "SKIP: " .. npcData.class .. " (already exists)")
                    end
                    continue
                end

                local success, result = RARELOAD.SpawnNPC(npcData, spawnedNPCsByID, pendingRelations)

                if success and IsValid(result) then
                    stats.restored = stats.restored + 1
                    table.insert(npcDataStats.restored, npcData)
                    if debugEnabled then
                        table.insert(processed, "OK: " .. npcData.class .. " (" .. (npcData.id or "no-id") .. ")")
                    end
                else
                    stats.failed = stats.failed + 1
                    local errorMsg = isstring(result) and result or "Spawn failed"
                    table.insert(stats.errors, npcData.class .. ": " .. errorMsg)
                    table.insert(npcDataStats.failed, npcData)
                    if debugEnabled then
                        table.insert(processed, "FAIL: " .. npcData.class .. " - " .. errorMsg)
                    end
                end
            end

            if debugEnabled and #processed > 0 then
                table.insert(npcRestoreLogs, {
                    header = "Batch Processed (Remaining: " .. #npcsToCreate .. ")",
                    messages = processed
                })
            end

            if #npcsToCreate > 0 then
                timer.Simple(interval, ProcessBatch)
            else
                timer.Simple(0.3, function()
                    RARELOAD.RestoreNPCRelationships(pendingRelations, spawnedNPCsByID, stats)
                    stats.endTime = SysTime()

                    if debugEnabled then
                        table.insert(npcRestoreLogs, {
                            header = "NPC Restoration Complete",
                            messages = {
                                "Total: " ..
                                stats.total ..
                                " | Restored: " ..
                                stats.restored .. " | Skipped: " .. stats.skipped .. " | Failed: " .. stats.failed,
                                "Duration: " .. math.Round(stats.endTime - stats.startTime, 3) .. "s",
                                "Relationships: " ..
                                stats.relationshipsRestored ..
                                " | Targets: " .. stats.targetsSet .. " | Schedules: " .. stats.schedulesRestored,
                                #stats.errors > 0 and ("Errors: " .. table.concat(stats.errors, " | ")) or "No errors"
                            }
                        })
                        RARELOAD.Debug.LogGroup("NPC RESTORATION", "INFO", npcRestoreLogs)
                    end
                end)
            end
        end

        ProcessBatch()
    end)
end

function RARELOAD.CollectExistingNPCs(spawnedNPCsByID)
    local existingNpcs = {}
    local existingCount = 0
    local rareloadNpcs = {}

    for _, npc in ipairs(ents.GetAll()) do
        if IsValid(npc) and npc:IsNPC() and (npc.SpawnedByRareload or npc.SavedByRareload) then
            local posStr = (RARELOAD and RARELOAD.DataUtils and RARELOAD.DataUtils.PositionToString(npc:GetPos(), 2))
                or tostring(npc:GetPos())
            local key = npc:GetClass() .. "|" .. (npc:GetModel() or "") .. "|" .. posStr
            existingNpcs[key] = true
            existingCount = existingCount + 1

            if npc.RareloadUniqueID then
                spawnedNPCsByID[npc.RareloadUniqueID] = npc
                table.insert(rareloadNpcs, {
                    class = npc:GetClass(),
                    id = npc.RareloadUniqueID,
                    position = npc:GetPos()
                })
            end
        end
    end

    if debugEnabled and existingCount > 0 then
        table.insert(npcRestoreLogs, {
            header = "Existing NPCs Found",
            messages = {
                "Total existing: " .. existingCount,
                "With unique IDs: " .. #rareloadNpcs,
                "Sample: " ..
                (rareloadNpcs[1] and (rareloadNpcs[1].class .. " (" .. rareloadNpcs[1].id .. ")") or "none")
            }
        })
    end

    return existingNpcs
end

function RARELOAD.SpawnNPC(npcData, spawnedNPCsByID, pendingRelations)
    local success, result = pcall(function()
        local npc = ents.Create(npcData.class)
        if not IsValid(npc) then return nil, "Entity creation failed" end

        local pos = RARELOAD.CoerceVector(npcData.pos) or Vector(0, 0, 0)
        npcData.pos = pos
        npc:SetPos(pos)

        if npc.SetSaveValue then
            pcall(function()
                npc:SetSaveValue("m_vecOrigin", pos)
                npc:SetSaveValue("m_vecAbsOrigin", pos)
                npc:SetSaveValue("origin", pos)
            end)
        end

        if npcData.model and util.IsValidModel(npcData.model) then
            npc:SetModel(npcData.model)
        end

        if npcData.ang ~= nil then
            local ang = npcData.ang
            if not (isangle and isangle(ang)) then
                if istable(ang) then
                    if ang.p and ang.y and ang.r then
                        ang = Angle(ang.p, ang.y, ang.r)
                    elseif #ang >= 3 then
                        ang = Angle(ang[1], ang[2], ang[3])
                    end
                elseif isstring(ang) and RARELOAD and RARELOAD.DataUtils then
                    ang = RARELOAD.DataUtils.ToAngle(ang)
                end
            end
            if isangle and isangle(ang) then
                npcData.ang = ang
                npc:SetAngles(ang)
            end
        end

        if npcData.keyValues then
            local keyValuesCopy = table.Copy(npcData.keyValues)
            local originalSquad = keyValuesCopy.squadname
            keyValuesCopy.squadname = nil
            for key, value in pairs(keyValuesCopy) do
                pcall(function() npc:SetKeyValue(key, value) end)
            end
            if originalSquad then
                npcData.originalSquad = originalSquad
            end
        end

        npc:Spawn()
        npc:Activate()

        local cls = npc:GetClass() or ""
        local isVJBase = string.sub(cls, 1, 7) == "npc_vj_"

        if isVJBase then
            local desiredPos = pos
            local desiredAng = npcData.ang
            timer.Simple(0, function()
                if not IsValid(npc) then return end
                npc:SetPos(desiredPos)
                if desiredAng and isangle and isangle(desiredAng) then
                    npc:SetAngles(desiredAng)
                end
                if npc.DropToFloor then
                    pcall(function() npc:DropToFloor() end)
                end
            end)
        end

        if npcData.id then
            spawnedNPCsByID[npcData.id] = npc
        end

        if npcData.modelScale then
            pcall(function() npc:SetModelScale(npcData.modelScale, 0) end)
        end

        if npcData.skin then
            npc:SetSkin(npcData.skin or 0)
        end

        if npcData.bodygroups then
            for id, value in pairs(npcData.bodygroups) do
                local bodygroupID = tonumber(id)
                if bodygroupID then
                    npc:SetBodygroup(bodygroupID, value)
                end
            end
        end

        if npcData.submaterials then
            for idx, mat in pairs(npcData.submaterials) do
                local i = tonumber(idx) or idx
                if i ~= nil and isstring(mat) then
                    pcall(function() npc:SetSubMaterial(i, mat) end)
                end
            end
        end

        if npcData.color then
            npc:SetColor(Color(
                npcData.color.r or 255,
                npcData.color.g or 255,
                npcData.color.b or 255,
                npcData.color.a or 255
            ))
        end

        if npcData.materialOverride and npcData.materialOverride ~= "" then
            npc:SetMaterial(npcData.materialOverride)
        end

        if npcData.renderMode then npc:SetRenderMode(npcData.renderMode) end
        if npcData.renderFX then npc:SetRenderFX(npcData.renderFX) end

        if npcData.collisionGroup then
            pcall(function() npc:SetCollisionGroup(npcData.collisionGroup) end)
        end

        if npcData.health or npcData.maxHealth then
            if npcData.maxHealth then
                npc:SetMaxHealth(npcData.maxHealth)
            end
            npc:SetHealth(npcData.health or npc:GetMaxHealth())
        end

        if npcData.weapons and #npcData.weapons > 0 then
            for _, weaponData in ipairs(npcData.weapons) do
                if weaponData.class then
                    local okGive, weapon = pcall(function() return npc:Give(weaponData.class) end)
                    if okGive and IsValid(weapon) and weaponData.clipAmmo then
                        pcall(function() weapon:SetClip1(weaponData.clipAmmo) end)
                    end
                end
            end
        end

        -- Physics & movement restore
        do
            local phys = npc:GetPhysicsObject()
            if IsValid(phys) then
                if npcData.physics then
                    if npcData.physics.mass then
                        pcall(function() phys:SetMass(npcData.physics.mass) end)
                    end
                    if npcData.physics.gravityEnabled ~= nil then
                        pcall(function() phys:EnableGravity(npcData.physics.gravityEnabled) end)
                    end
                    if npcData.physics.motionEnabled ~= nil then
                        pcall(function() phys:EnableMotion(npcData.physics.motionEnabled) end)
                    end
                    if npcData.physics.material and phys.SetMaterial then
                        pcall(function() phys:SetMaterial(npcData.physics.material) end)
                    end
                end
                if npcData.frozen then
                    phys:EnableMotion(false)
                end
            end
            if npcData.velocity and npc.SetVelocity then
                local v = npcData.velocity
                if istable(v) and v.x and v.y and v.z then v = Vector(v.x, v.y, v.z) end
                if isvector and isvector(v) then pcall(function() npc:SetVelocity(v) end) end
            end
        end

        -- Core types & flags
        if npcData.moveType and npc.SetMoveType then pcall(function() npc:SetMoveType(npcData.moveType) end) end
        if npcData.solidType and npc.SetSolid then pcall(function() npc:SetSolid(npcData.solidType) end) end
        if npcData.hullType then pcall(function() if npc.SetHullType then npc:SetHullType(npcData.hullType) end end) end
        if npcData.bloodColor and npc.SetBloodColor then pcall(function() npc:SetBloodColor(npcData.bloodColor) end) end

        if npcData.relations then
            pendingRelations[npc] = npcData.relations
        end

        if npcData.citizenData and npc:GetClass() == "npc_citizen" then
            RARELOAD.RestoreCitizenProperties(npc, npcData.citizenData)
        end

        if npcData.vjBaseData and isVJBase then
            RARELOAD.RestoreVJBaseProperties(npc, npcData.vjBaseData)
        end

        if npcData.sequence and npc.SetSequence then
            pcall(function() npc:SetSequence(npcData.sequence) end)
        end
        if npcData.cycle and npc.SetCycle then
            pcall(function() npc:SetCycle(npcData.cycle) end)
        end
        if npcData.playbackRate and npc.SetPlaybackRate then
            pcall(function() npc:SetPlaybackRate(npcData.playbackRate) end)
        end

        if npcData.ownerSteamID and npc.CPPISetOwner then
            local owner = RARELOAD.FindPlayerBySteamID(npcData.ownerSteamID)
            if IsValid(owner) then pcall(function() npc:CPPISetOwner(owner) end) end
        end

        npc.RareloadData = npcData
        npc.SpawnedByRareload = true
        npc.SavedByRareload = true
        npc.RareloadUniqueID = npcData.id
        if npc.SetNWString and npc.RareloadUniqueID then
            pcall(function() npc:SetNWString("RareloadID", npc.RareloadUniqueID) end)
        end

        return npc
    end)

    return success, result
end

function RARELOAD.RestoreCitizenProperties(npc, citizenData)
    if not IsValid(npc) or not citizenData then return end

    local restoredProps = {}

    if citizenData.isMedic then
        npc:SetKeyValue("citizentype", "3")
        npc:SetNWBool("IsMedic", true)
        table.insert(restoredProps, "medic")
    end

    if citizenData.isAmmoSupplier then
        npc:SetKeyValue("ammosupplier", "1")
        npc:SetNWBool("IsAmmoSupplier", true)
        table.insert(restoredProps, "ammo_supplier")
    end

    if citizenData.isRebel then
        npc:SetNWBool("IsRebel", true)
        table.insert(restoredProps, "rebel")

        if not string.find(npc:GetModel() or "", "rebel") then
            local rebelModels = {
                "models/humans/group03/male_01.mdl",
                "models/humans/group03/male_02.mdl",
                "models/humans/group03/female_01.mdl"
            }
            npc:SetModel(rebelModels[math.random(#rebelModels)])
            table.insert(restoredProps, "rebel_model")
        end
    end

    if debugEnabled and #restoredProps > 0 then
        table.insert(npcRestoreLogs, {
            header = "Citizen Properties Restored",
            messages = {
                "NPC: " .. npc:GetClass() .. " (" .. (npc.RareloadUniqueID or "no-id") .. ")",
                "Properties: " .. table.concat(restoredProps, ", ")
            }
        })
    end
end

function RARELOAD.RestoreVJBaseProperties(npc, vjData)
    if not IsValid(npc) or not vjData then return end

    local restoredProps = {}

    if vjData.vjType then
        npc:SetNWString("VJ_Type", vjData.vjType)
        table.insert(restoredProps, "type=" .. vjData.vjType)
    end

    if vjData.maxHealth then
        npc:SetMaxHealth(vjData.maxHealth)
        npc:SetHealth(vjData.maxHealth)
        table.insert(restoredProps, "maxHealth=" .. vjData.maxHealth)
    end

    if vjData.startHealth then
        npc:SetNWInt("VJ_StartingHealth", vjData.startHealth)
        table.insert(restoredProps, "startHealth=" .. vjData.startHealth)
    end

    if vjData.animationPlaybackRate then
        npc:SetNWFloat("AnimationPlaybackRate", vjData.animationPlaybackRate)
        table.insert(restoredProps, "animRate=" .. vjData.animationPlaybackRate)
    end

    if vjData.walkSpeed then
        npc:SetNWInt("VJ_WalkSpeed", vjData.walkSpeed)
        table.insert(restoredProps, "walkSpeed=" .. vjData.walkSpeed)
    end

    if vjData.runSpeed then
        npc:SetNWInt("VJ_RunSpeed", vjData.runSpeed)
        table.insert(restoredProps, "runSpeed=" .. vjData.runSpeed)
    end

    if vjData.faction then
        if istable(vjData.faction) then
            npc.VJ_NPC_Class = table.Copy(vjData.faction)
            table.insert(restoredProps, "faction=table")
        elseif isstring(vjData.faction) then
            npc:SetNWString("VJ_NPC_Class", vjData.faction)
            table.insert(restoredProps, "faction=" .. vjData.faction)
        end
    end

    if vjData.isFollowing then
        table.insert(restoredProps, "following")
        timer.Simple(0, function()
            if not IsValid(npc) then return end
            local minDist = vjData.followMinDistance
            if vjData.followTarget and vjData.followTarget.type == "player" then
                local target = RARELOAD.FindPlayerBySteamID(vjData.followTarget.id)
                if IsValid(target) then
                    RARELOAD.TryStartFollowVJ(npc, target, minDist)
                    RARELOAD.EnforceVJFollow(npc, target, minDist)
                else
                    timer.Simple(0.2, function()
                        if not IsValid(npc) then return end
                        local t = RARELOAD.FindPlayerBySteamID(vjData.followTarget.id)
                        if IsValid(t) then
                            RARELOAD.TryStartFollowVJ(npc, t, minDist)
                            RARELOAD.EnforceVJFollow(npc, t, minDist)
                        end
                    end)
                end
            elseif vjData.followTarget and vjData.followTarget.type == "npc" and npc.RareloadData then
                npc.Rareload_FollowTargetNPC = vjData.followTarget.id
                npc.Rareload_FollowMinDist = minDist
            else
                RARELOAD.TryStartFollowVJ(npc, nil, minDist)
            end
        end)
    end

    if vjData.isMeleeAttacker ~= nil then
        npc:SetNWBool("VJ_IsMeleeAttacking", vjData.isMeleeAttacker)
        table.insert(restoredProps, "melee=" .. tostring(vjData.isMeleeAttacker))
    end

    if vjData.isRangeAttacker ~= nil then
        npc:SetNWBool("VJ_IsRangeAttacking", vjData.isRangeAttacker)
        table.insert(restoredProps, "range=" .. tostring(vjData.isRangeAttacker))
    end

    if debugEnabled and #restoredProps > 0 then
        table.insert(npcRestoreLogs, {
            header = "VJ Base Properties Restored",
            messages = {
                "NPC: " .. npc:GetClass() .. " (" .. (npc.RareloadUniqueID or "no-id") .. ")",
                "Properties: " .. table.concat(restoredProps, ", ")
            }
        })
    end
end

function RARELOAD.FindPlayerBySteamID(steamID)
    if not steamID then return nil end
    steamID = tostring(steamID)
    for _, p in ipairs(player.GetAll()) do
        if p.SteamID64 and tostring(p:SteamID64()) == steamID then return p end
        if p.SteamID and p:SteamID() == steamID then return p end
    end
    return nil
end

function RARELOAD.RestoreNPCRelationships(pendingRelations, spawnedNPCsByID, stats)
    local relationshipStats = { player = 0, npc = 0, faction = 0 }

    for npc, relations in pairs(pendingRelations) do
        if not IsValid(npc) then continue end

        if relations.players then
            for steamID, disposition in pairs(relations.players) do
                local player = RARELOAD.FindPlayerBySteamID(steamID)
                if IsValid(player) then
                    pcall(function() npc:AddEntityRelationship(player, disposition, 99) end)
                    relationshipStats.player = relationshipStats.player + 1
                end
            end
        end

        if relations.npcs then
            for targetID, disposition in pairs(relations.npcs) do
                local targetNPC = spawnedNPCsByID[targetID]
                if IsValid(targetNPC) then
                    pcall(function() npc:AddEntityRelationship(targetNPC, disposition, 99) end)
                    relationshipStats.npc = relationshipStats.npc + 1
                end
            end
        end

        if relations.factions then
            for faction, disposition in pairs(relations.factions) do
                relationshipStats.faction = relationshipStats.faction + 1
            end
        end
    end

    stats.relationshipsRestored = relationshipStats.player + relationshipStats.npc + relationshipStats.faction

    if debugEnabled and stats.relationshipsRestored > 0 then
        table.insert(npcRestoreLogs, {
            header = "Relationships Restored",
            messages = {
                "Player relations: " .. relationshipStats.player,
                "NPC relations: " .. relationshipStats.npc,
                "Faction relations: " .. relationshipStats.faction,
                "Total: " .. stats.relationshipsRestored
            }
        })
    end

    RARELOAD.RestoreNPCTargetsAndSchedules(spawnedNPCsByID, stats)
    timer.Simple(0.1, function() RARELOAD.RestoreSquads(spawnedNPCsByID) end)
end

function RARELOAD.RestoreNPCTargetsAndSchedules(spawnedNPCsByID, stats)
    local targetsRestored = 0
    local schedulesRestored = 0
    local followRestored = 0

    for uniqueID, npc in pairs(spawnedNPCsByID) do
        if not IsValid(npc) then continue end
        local npcData = npc.RareloadData
        if not npcData then continue end

        if npcData.vjBaseData and npc.Rareload_FollowTargetNPC then
            local tgt = spawnedNPCsByID[npc.Rareload_FollowTargetNPC]
            if IsValid(tgt) then
                local minDist = npc.Rareload_FollowMinDist or
                    (npcData.vjBaseData and npcData.vjBaseData.followMinDistance)
                RARELOAD.TryStartFollowVJ(npc, tgt, minDist)
                RARELOAD.EnforceVJFollow(npc, tgt, minDist)
                npc.Rareload_FollowTargetNPC = nil
                npc.Rareload_FollowMinDist = nil
                followRestored = followRestored + 1
            end
        end

        if npcData.target then
            local target
            if npcData.target.type == "player" then
                target = RARELOAD.FindPlayerBySteamID(npcData.target.id)
            elseif npcData.target.type == "npc" then
                target = spawnedNPCsByID[npcData.target.id]
            end
            if IsValid(target) then
                pcall(function() npc:SetEnemy(target) end)
                targetsRestored = targetsRestored + 1
            end
        end

        if npcData.schedule and npc.SetSchedule then
            pcall(function() npc:SetSchedule(npcData.schedule.id) end)
            schedulesRestored = schedulesRestored + 1
            if npcData.schedule.target and npc.SetTarget then
                local target
                if npcData.schedule.target.type == "player" then
                    target = RARELOAD.FindPlayerBySteamID(npcData.schedule.target.id)
                elseif npcData.schedule.target.type == "npc" or npcData.schedule.target.type == "entity" then
                    target = spawnedNPCsByID[npcData.schedule.target.id]
                end
                if IsValid(target) then pcall(function() npc:SetTarget(target) end) end
            end
        end

        if npcData.weaponProficiency and npc.SetCurrentWeaponProficiency then
            pcall(function() npc:SetCurrentWeaponProficiency(npcData.weaponProficiency) end)
        end
        if npcData.npcState and npc.SetNPCState then
            pcall(function() npc:SetNPCState(npcData.npcState) end)
        end

        if npcData.sequence and npc.SetSequence then
            pcall(function() npc:SetSequence(npcData.sequence) end)
        end
        if npcData.cycle and npc.SetCycle then
            pcall(function() npc:SetCycle(npcData.cycle) end)
        end
        if npcData.playbackRate and npc.SetPlaybackRate then
            pcall(function() npc:SetPlaybackRate(npcData.playbackRate) end)
        end
    end

    stats.targetsSet = targetsRestored
    stats.schedulesRestored = schedulesRestored

    if debugEnabled and (targetsRestored > 0 or schedulesRestored > 0 or followRestored > 0) then
        table.insert(npcRestoreLogs, {
            header = "Targets & Schedules Restored",
            messages = {
                "Targets set: " .. targetsRestored,
                "Schedules restored: " .. schedulesRestored,
                "Follow behaviors: " .. followRestored
            }
        })
    end
end

function RARELOAD.TryStartFollowVJ(npc, target, minDist)
    if not IsValid(npc) then return end

    local entTbl = npc:GetTable()
    entTbl.IsFollowing = true
    entTbl.FollowData = entTbl.FollowData or {}
    if IsValid(target) then entTbl.FollowData.Target = target end
    entTbl.FollowData.MinDist = minDist or entTbl.FollowData.MinDist or entTbl.FollowMinDistance or 100
    entTbl.FollowData.Using = true

    if IsValid(target) then
        pcall(function()
            if target:IsPlayer() then
                npc:AddEntityRelationship(target, D_LI, 99)
            elseif target:IsNPC() then
                npc:AddEntityRelationship(target, D_FR, 99)
            end
        end)
    end

    local followMethods = {
        function() if isfunction(npc.VJ_DoFollow) then npc:VJ_DoFollow(target, true) end end,
        function() if isfunction(npc.StartFollowing) then npc:StartFollowing(target) end end,
        function() if isfunction(npc.Follow) then npc:Follow(target) end end,
        function() if isfunction(npc.SetFollowTarget) then npc:SetFollowTarget(target) end end
    }

    for _, method in ipairs(followMethods) do pcall(method) end

    for i = 0, 2 do
        timer.Simple(0.05 * i, function()
            if not IsValid(npc) then return end
            local t = target
            if not IsValid(t) and npc.RareloadData and npc.RareloadData.vjBaseData and npc.RareloadData.vjBaseData.followTarget and npc.RareloadData.vjBaseData.followTarget.type == "player" then
                t = RARELOAD.FindPlayerBySteamID(npc.RareloadData.vjBaseData.followTarget.id)
            end
            entTbl.IsFollowing = true
            entTbl.FollowData = entTbl.FollowData or {}
            if IsValid(t) then entTbl.FollowData.Target = t end
            entTbl.FollowData.MinDist = minDist or entTbl.FollowData.MinDist or entTbl.FollowMinDistance or 100
            entTbl.FollowData.Using = true
            if IsValid(t) and npc.SetLastPosition and npc.SetSchedule then
                pcall(function()
                    npc:SetLastPosition(t:GetPos())
                    if SCHED_FORCED_GO_RUN then
                        npc:SetSchedule(SCHED_FORCED_GO_RUN)
                    elseif SCHED_FORCED_GO then
                        npc:SetSchedule(SCHED_FORCED_GO)
                    end
                end)
            end
        end)
    end
end

function RARELOAD.EnforceVJFollow(npc, target, minDist)
    if not IsValid(npc) then return end

    for i = 1, 15 do
        timer.Simple(0.05 * i, function()
            if not IsValid(npc) then return end
            local t = target
            if not IsValid(t) and npc.RareloadData and npc.RareloadData.vjBaseData and npc.RareloadData.vjBaseData.followTarget then
                local ft = npc.RareloadData.vjBaseData.followTarget
                if ft.type == "player" then
                    t = RARELOAD.FindPlayerBySteamID(ft.id)
                end
            end
            RARELOAD.TryStartFollowVJ(npc, t, minDist)
        end)
    end
end

function RARELOAD.RestoreSquads(spawnedNPCsByID)
    local groups = {}
    local squadStats = { total = 0, formed = 0, conflicts = 0, renamed = 0, split = 0 }

    -- Helper: safe disposition check (treat errors as friendly to avoid over-splitting)
    local function SafeDisposition(a, b)
        if not (IsValid(a) and IsValid(b) and a.Disposition) then return D_LI end
        local ok, disp = pcall(function() return a:Disposition(b) end)
        if ok and disp ~= nil then return disp end
        return D_LI
    end

    -- Helper: find existing non-Rareload NPCs on map with same squad name
    local function MapHasForeignSquadMembers(name, ourSet)
        if not name or name == "" then return false end
        local found = false
        for _, e in ipairs(ents.GetAll()) do
            if IsValid(e) and e:IsNPC() then
                local kv = e:GetKeyValues() or {}
                if tostring(kv.squadname or "") == name then
                    if not ourSet[e] then
                        found = true
                        break
                    end
                end
            end
        end
        return found
    end

    -- Helper: generate deterministic unique suffix from first member id
    local function SquadSuffix(firstNPC)
        local id = (IsValid(firstNPC) and firstNPC.RareloadUniqueID) or tostring(firstNPC)
        return string.sub(util.CRC(tostring(id)), 1, 6)
    end

    -- Build groups keyed by saved squad name (prefer explicit npcData.squad)
    for _, npc in pairs(spawnedNPCsByID) do
        if not IsValid(npc) then continue end
        local npcData = npc.RareloadData
        if not npcData then continue end

        local squadName = npcData.squad or npcData.originalSquad or (npcData.keyValues and npcData.keyValues.squadname)
        if not squadName or squadName == "" then continue end

        groups[squadName] = groups[squadName] or {}
        table.insert(groups[squadName], npc)
        squadStats.total = squadStats.total + 1
    end

    -- For each saved squad name, partition hostile members into separate components and form squads
    for baseName, members in pairs(groups) do
        -- Build adjacency for non-hostile relationships among members
        local adj = {}
        local indexMap = {}
        for i, npc in ipairs(members) do
            if IsValid(npc) then
                adj[i] = {}
                indexMap[npc] = i
            end
        end

        local conflicts = 0
        for i = 1, #members do
            local a = members[i]
            if not IsValid(a) then continue end
            for j = i + 1, #members do
                local b = members[j]
                if not IsValid(b) then continue end
                local disp = SafeDisposition(a, b)
                if disp == D_HT then
                    conflicts = conflicts + 1
                else
                    adj[i][j] = true
                    adj[j][i] = true
                end
            end
        end
        if conflicts > 0 then squadStats.conflicts = squadStats.conflicts + 1 end

        -- Find connected components (friendliness graph)
        local visited = {}
        local components = {}
        for i = 1, #members do
            if not visited[i] and IsValid(members[i]) then
                local queue = { i }
                visited[i] = true
                local comp = {}
                while #queue > 0 do
                    local v = table.remove(queue, 1)
                    if IsValid(members[v]) then table.insert(comp, members[v]) end
                    for w, ok in pairs(adj[v] or {}) do
                        if ok and not visited[w] then
                            visited[w] = true
                            table.insert(queue, w)
                        end
                    end
                end
                if #comp > 0 then table.insert(components, comp) end
            end
        end

        if #components == 0 and #members > 0 then components = { members } end
        if #components > 1 then squadStats.split = squadStats.split + (#components - 1) end

        -- Assign squads per component
        for idx, comp in ipairs(components) do
            -- Choose squad name; avoid collisions with foreign map squads
            local leader = comp[1]
            -- Prefer saved leader if marked
            for _, n in ipairs(comp) do
                if IsValid(n) and n.RareloadData and n.RareloadData.squadLeader then
                    leader = n
                    break
                end
            end
            local suffix = SquadSuffix(leader)
            local finalName = baseName
            local ourSet = {}
            for _, n in ipairs(comp) do ourSet[n] = true end
            if MapHasForeignSquadMembers(finalName, ourSet) then
                finalName = (baseName .. "_rl_" .. suffix)
                squadStats.renamed = squadStats.renamed + 1
            end
            if #components > 1 then
                finalName = finalName .. "_" .. tostring(idx)
            end

            -- Enforce friendly relations within squad component
            for i = 1, #comp do
                local a = comp[i]
                if not IsValid(a) then goto continue_inner end
                for j = 1, #comp do
                    local b = comp[j]
                    if i ~= j and IsValid(b) then
                        pcall(function() a:AddEntityRelationship(b, D_LI, 99) end)
                    end
                end
                ::continue_inner::
            end

            -- Clear any previous squad and assign the final one
            for _, n in ipairs(comp) do
                if not IsValid(n) then goto continue_assign end
                n:Fire("ClearSquad", "", 0)
                -- Use both input and fallback KeyValue in case input is unsupported
                n:Fire("setsquad", finalName, 0.05)
                if n.SetKeyValue then pcall(function() n:SetKeyValue("squadname", finalName) end) end
                ::continue_assign::
            end

            squadStats.formed = squadStats.formed + #comp
        end
    end

    if debugEnabled and squadStats.total > 0 then
        table.insert(npcRestoreLogs, {
            header = "Squad Restoration Complete",
            messages = {
                "Total NPCs with squads: " .. squadStats.total,
                "Members assigned: " .. squadStats.formed,
                "Groups split: " .. squadStats.split,
                "Squads with conflicts: " .. squadStats.conflicts,
                "Renamed to avoid collisions: " .. squadStats.renamed,
                "Unique base squads: " .. table.Count(groups)
            }
        })
    end
end

hook.Add("RARELOAD_SaveEntities", "RARELOAD_MarkSavedNPCs", function()
    local markedCount = 0
    for _, npc in ipairs(ents.GetAll()) do
        if npc:IsNPC() and npc:IsValid() then
            npc.SavedByRareload = true
            markedCount = markedCount + 1
        end
    end

    if debugEnabled then
        RARELOAD.Debug.Log("INFO", "NPCs Marked for Save", { "Total marked: " .. markedCount })
    end
end)

net.Receive("RareloadRespawnNPC", function(len, ply)
    if not IsValid(ply) or not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] Admin privileges required")
        return
    end

    local entityClass = net.ReadString()
    local position = net.ReadVector()

    if not entityClass or entityClass == "" or not position then
        ply:ChatPrint("[RARELOAD] Invalid entity data received")
        return
    end

    if debugEnabled then
        RARELOAD.Debug.Log("INFO", "Manual Respawn Request", {
            "Admin: " .. ply:Nick(),
            "Class: " .. entityClass,
            "Position: " .. tostring(position)
        })
    end

    local matchedData = nil
    local isNPC = (isstring(entityClass) and string.sub(entityClass, 1, 4) == "npc_") or
        (list.Get("NPC")[entityClass] ~= nil)
    local savedList = isNPC and (SavedInfo and SavedInfo.npcs or {}) or (SavedInfo and SavedInfo.entities or {})

    if savedList then
        for _, savedEntity in ipairs(savedList) do
            if savedEntity.class == entityClass and
                savedEntity.pos and
                position:DistToSqr(Vector(savedEntity.pos.x, savedEntity.pos.y, savedEntity.pos.z)) < 100 then
                matchedData = savedEntity
                break
            end
        end
    end

    local success = false
    if matchedData then
        if isNPC then
            local spawnedNPCsByID = {}
            local pendingRelations = {}
            local spawnSuccess, newNPC = RARELOAD.SpawnNPC(matchedData, spawnedNPCsByID, pendingRelations)

            if spawnSuccess and IsValid(newNPC) then
                if next(pendingRelations) then
                    timer.Simple(0.1, function()
                        RARELOAD.RestoreNPCRelationships(pendingRelations, spawnedNPCsByID, {
                            relationshipsRestored = 0, targetsSet = 0, schedulesRestored = 0
                        })
                    end)
                end
                ply:ChatPrint("[RARELOAD] " .. entityClass .. " restored successfully")
                success = true
            end
        else
            local entity = ents.Create(entityClass)
            if IsValid(entity) then
                entity:SetPos(position)
                if matchedData.ang then entity:SetAngles(matchedData.ang) end
                if matchedData.model and util.IsValidModel(matchedData.model) then entity:SetModel(matchedData.model) end

                entity:Spawn()
                entity:Activate()

                if matchedData.health then entity:SetHealth(matchedData.health) end
                if matchedData.skin then entity:SetSkin(matchedData.skin) end

                if matchedData.bodygroups then
                    for id, value in pairs(matchedData.bodygroups) do
                        local bodygroupID = tonumber(id)
                        if bodygroupID then
                            entity:SetBodygroup(bodygroupID, value)
                        end
                    end
                end

                if matchedData.submaterials then
                    for idx, mat in pairs(matchedData.submaterials) do
                        local i = tonumber(idx) or idx
                        if i ~= nil and isstring(mat) then
                            pcall(function() entity:SetSubMaterial(i, mat) end)
                        end
                    end
                end

                if matchedData.frozen then
                    local phys = entity:GetPhysicsObject()
                    if IsValid(phys) then phys:EnableMotion(false) end
                end

                if matchedData.collisionGroup then
                    pcall(function() entity:SetCollisionGroup(matchedData.collisionGroup) end)
                end

                if matchedData.color then
                    entity:SetColor(Color(
                        matchedData.color.r or 255,
                        matchedData.color.g or 255,
                        matchedData.color.b or 255,
                        matchedData.color.a or 255
                    ))
                end

                entity.SpawnedByRareload = true
                entity.SavedByRareload = true
                ply:ChatPrint("[RARELOAD] " .. entityClass .. " restored with saved properties")
                success = true
            end
        end
    end

    if not success then
        local entity = ents.Create(entityClass)
        if IsValid(entity) then
            entity:SetPos(position)
            entity:Spawn()
            if not isNPC then entity:Activate() end
            entity.SpawnedByRareload = true
            ply:ChatPrint("[RARELOAD] " .. entityClass .. " spawned with default properties")
        else
            ply:ChatPrint("[RARELOAD] Failed to spawn " .. entityClass)
        end
    end

    local entity = ents.FindInSphere(position, 5)[1]
    if IsValid(entity) and entity.CPPISetOwner then
        entity:CPPISetOwner(ply)
    end
end)
