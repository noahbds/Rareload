---@diagnostic disable: undefined-field, inject-field, need-check-nil, deprecated

if not RARELOAD then RARELOAD = {} end
if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function GenerateNPCUniqueID(npc)
    return (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) and RARELOAD.Util.GenerateDeterministicID(npc) or
        "npc_legacyid"
end

local function GetOwnerSteamID(owner)
    if not IsValid(owner) then return nil end
    if owner.SteamID64 then
        local ok, sid = pcall(owner.SteamID64, owner)
        if ok and isstring(sid) then return sid end
    end
    if owner.SteamID then
        local ok, sid = pcall(owner.SteamID, owner)
        if ok and isstring(sid) then return sid end
    end
    return nil
end

local function SafeGetNPCProperty(npc, propertyFn, defaultValue)
    if not IsValid(npc) then return defaultValue end
    local ok, result = pcall(propertyFn)
    if ok then return result end
    return defaultValue
end

-- ####################################################################
-- These functions capture complex AI/state data that duplicator.Copy
-- might not preserve. We save this separately into the dupe table.
-- ####################################################################

local function GetNPCRelations(npc, players, allNPCs)
    local relations = { players = {}, npcs = {} }
    if not IsValid(npc) or not npc.Disposition then return relations end

    for _, ply in ipairs(players) do
        if IsValid(ply) then
            local disposition = SafeGetNPCProperty(npc, function() return npc:Disposition(ply) end, nil)
            if disposition then
                relations.players[ply:SteamID64()] = disposition
            end
        end
    end

    for _, other in ipairs(allNPCs) do
        if IsValid(other) and other ~= npc then
            local disposition = SafeGetNPCProperty(npc, function() return npc:Disposition(other) end, nil)
            if disposition then
                if not other.RareloadUniqueID then
                    other.RareloadUniqueID = GenerateNPCUniqueID(other)
                end
                relations.npcs[other.RareloadUniqueID] = disposition
            end
        end
    end

    return relations
end

local function GetNPCTarget(npc)
    if not npc.GetEnemy then return nil end
    local enemy = npc:GetEnemy()
    if not IsValid(enemy) then return nil end
    if enemy:IsPlayer() then
        return { type = "player", id = GetOwnerSteamID(enemy) }
    elseif enemy:IsNPC() then
        if not enemy.RareloadUniqueID then
            enemy.RareloadUniqueID = GenerateNPCUniqueID(enemy)
        end
        return { type = "npc", id = enemy.RareloadUniqueID }
    else
        return { type = "entity", class = enemy:GetClass(), pos = enemy:GetPos():ToTable() }
    end
end

local function GetNPCSchedule(npc)
    if not npc.GetCurrentSchedule then return nil end
    local scheduleID = npc:GetCurrentSchedule()
    if not scheduleID then return nil end
    local scheduleData = { id = scheduleID }
    if npc.GetTarget then
        local target = npc:GetTarget()
        if IsValid(target) then
            if target:IsPlayer() then
                scheduleData.target = { type = "player", id = GetOwnerSteamID(target) }
            else
                if not target.RareloadUniqueID then
                    target.RareloadUniqueID = GenerateNPCUniqueID(target)
                end
                scheduleData.target = { type = "entity", id = target.RareloadUniqueID, class = target:GetClass() }
            end
        end
    end
    return scheduleData
end

local function GetVJBaseFollowData(npc)
    if not IsValid(npc) then return nil end
    local entTbl = npc:GetTable() or {}
    local isFollowing = (npc.IsFollowing == true) or (entTbl.IsFollowing == true)
    if not isFollowing then return nil end

    local followData = {
        isFollowing = true,
        minDistance = entTbl.FollowData and entTbl.FollowData.MinDist or nil
    }
    if entTbl.FollowData and IsValid(entTbl.FollowData.Target) then
        local tgt = entTbl.FollowData.Target
        if tgt:IsPlayer() then
            followData.target = { type = "player", id = GetOwnerSteamID(tgt) }
        elseif tgt:IsNPC() then
            if not tgt.RareloadUniqueID then
                tgt.RareloadUniqueID = GenerateNPCUniqueID(tgt)
            end
            followData.target = { type = "npc", id = tgt.RareloadUniqueID }
        else
            followData.target = { type = "entity", class = tgt:GetClass(), pos = tgt:GetPos():ToTable() }
        end
    end
    return followData
end

-- ####################################################################

local function GetEntityOwner(ent)
    if not IsValid(ent) then return nil end
    local owner
    if isfunction(ent.CPPIGetOwner) then
        local ok, o = pcall(ent.CPPIGetOwner, ent)
        if ok and IsValid(o) and o:IsPlayer() then owner = o end
    end
    if not IsValid(owner) and ent.GetOwner then
        local o = ent:GetOwner()
        if IsValid(o) and o:IsPlayer() then owner = o end
    end
    return owner
end

return function(ply)
    if not IsValid(ply) then return nil end
    if not duplicator or not duplicator.Copy then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ERROR] Duplicator system not found!")
        end
        return nil
    end

    local startTime = SysTime()
    local npcsToSave = {}

    local allNPCs = ents.FindByClass("npc_*")
    for _, npc in ipairs(allNPCs) do
        if IsValid(npc) then
            local owner = GetEntityOwner(npc)
            local isOwnerPlayer = IsValid(owner) and owner:IsPlayer()
            local spawnedByRareload = npc.SpawnedByRareload == true
            
            if (isOwnerPlayer and owner == ply) or spawnedByRareload then
                table.insert(npcsToSave, npc)
            end
        end
    end

    if #npcsToSave == 0 then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] No player-owned or Rareload-spawned NPCs to save.")
        end
        return nil
    end

    local dupe = duplicator.Copy(npcsToSave, true)

    if not dupe or not dupe.Entities then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ERROR] Failed to create duplicator copy for NPCs.")
        end
        return nil
    end

    local players = player.GetAll()

    -- Inject our custom IDs and complex AI data into the dupe structure
    for i, npc in ipairs(npcsToSave) do
        local dupeNpc = dupe.Entities[i]
        if not dupeNpc then continue end
        
        if not npc.RareloadUniqueID then
            npc.RareloadUniqueID = GenerateNPCUniqueID(npc)
        end

        dupeNpc.RareloadUniqueID = npc.RareloadUniqueID
        dupeNpc.OriginallySpawnedBy = GetOwnerSteamID(GetEntityOwner(npc))
        dupeNpc.WasPlayerSpawned = IsValid(GetEntityOwner(npc))

        -- Store complex AI data that the duplicator might miss
        dupeNpc.RareloadAI = {
            relations = GetNPCRelations(npc, players, npcsToSave),
            target = GetNPCTarget(npc),
            schedule = GetNPCSchedule(npc),
            squad = npc:GetSquadName(),
            isSquadLeader = SafeGetNPCProperty(npc, function() return npc.IsSquadLeader and npc:IsSquadLeader() end, false),
            vjFollow = GetVJBaseFollowData(npc),
            npcState = SafeGetNPCProperty(npc, function() return npc:GetNPCState() end, nil),
            weaponProficiency = SafeGetNPCProperty(npc, function() return npc:GetCurrentWeaponProficiency() end, nil),
        }
    end

    if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " ..
            #npcsToSave .. " NPCs using duplicator in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")
    end

    return dupe
end