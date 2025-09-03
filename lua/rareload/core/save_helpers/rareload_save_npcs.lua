-- RareLoad Save NPCs Module

---@class RARELOAD
local RARELOAD = RARELOAD or {}
RARELOAD.NPCSaver = RARELOAD.NPCSaver or {}

local CONFIG = {
    DEBUG = true,
    SAVE_PLAYER_OWNED_ONLY = false,
    MAX_NPCS_TO_SAVE = 500,
    -- Save relationships between NPCs (may be heavy on large maps)
    SAVE_NPC_NPC_RELATIONS = true,
    MAX_RELATION_NPCS = 128,
    -- Only keep KV keys that are NOT already serialized explicitly elsewhere.
    -- Removed: spawnflags, health, rendercolor, rendermode, expression (explicitly captured separately)
    KEY_VALUES_TO_SAVE = {
        "squadname", "targetname",
        "wakeradius", "sleepstate",
        "additionalequipment", "citizentype"
    }
}

local function DebugLog(msg, ...)
    if CONFIG.DEBUG then
        local formatted = string.format(msg, ...)
        print("[RareLoad NPC Saver] " .. formatted)
        if SERVER then ServerLog("[RareLoad NPC Saver] " .. formatted .. "\n") end
    end
end

local function getsquadname(npc)
    if not IsValid(npc) then return "" end
    local kv = npc:GetKeyValues() or {}
    local squadName = kv.squadname or ""
    if squadName == "" and npc.GetSquad then
        local ok, val = pcall(function() return npc:GetSquad() end)
        if ok and isstring(val) then squadName = val end
    end
    return squadName
end

local function SafeGetNPCProperty(npc, propertyFn, defaultValue)
    if not IsValid(npc) then return defaultValue end
    local ok, result = pcall(propertyFn)
    if ok then return result end
    DebugLog("Failed to get NPC property: %s", tostring(result))
    return defaultValue
end

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
    if not IsValid(owner) and ent.GetNWEntity then
        local o = ent:GetNWEntity("Owner")
        if IsValid(o) and o:IsPlayer() then owner = o end
    end
    return owner
end

-- Shared deterministic helpers (load once)
if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function GenerateNPCUniqueID(npc)
    return (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) and RARELOAD.Util.GenerateDeterministicID(npc) or
        "npc_legacyid"
end

local function GetNPCRelations(npc, players, allNPCs)
    local relations = { players = {}, npcs = {} }
    if not IsValid(npc) or not npc.Disposition then return relations end

    for i = 1, #players do
        local ply = players[i]
        if IsValid(ply) then
            local disposition = SafeGetNPCProperty(npc, function() return npc:Disposition(ply) end, nil)
            if disposition then
                relations.players[ply:SteamID64()] = disposition
            end
        end
    end

    if CONFIG.SAVE_NPC_NPC_RELATIONS and istable(allNPCs) then
        local saved = 0
        for i = 1, #allNPCs do
            local other = allNPCs[i]
            if IsValid(other) and other ~= npc then
                local disposition = SafeGetNPCProperty(npc, function() return npc:Disposition(other) end, nil)
                if disposition then
                    relations.npcs[GenerateNPCUniqueID(other)] = disposition
                    saved = saved + 1
                    if saved >= CONFIG.MAX_RELATION_NPCS then break end
                end
            end
        end
    end

    return relations
end

local function GetNPCWeapons(npc)
    local weaponData = {}
    local weapons = {}

    if isfunction(npc.GetWeapons) then
        weapons = SafeGetNPCProperty(npc, function() return npc:GetWeapons() end, {})
    end

    if (not istable(weapons)) or (#weapons == 0) then
        local active = SafeGetNPCProperty(npc, function() return npc:GetActiveWeapon() end, nil)
        if IsValid(active) then weapons = { active } else weapons = {} end
    end

    for i = 1, #weapons do
        local weapon = weapons[i]
        if IsValid(weapon) then
            weaponData[#weaponData + 1] = {
                class = weapon:GetClass(),
                clipAmmo = SafeGetNPCProperty(weapon, function() return weapon:Clip1() end, -1),
                ammoType = SafeGetNPCProperty(weapon, function() return weapon:GetPrimaryAmmoType() end, -1),
                secondaryAmmoType = SafeGetNPCProperty(weapon, function() return weapon:GetSecondaryAmmoType() end, -1)
            }
        end
    end

    return weaponData
end

local function GetNPCTarget(npc)
    if not npc.GetEnemy then return nil end
    local enemy = npc:GetEnemy()
    if not IsValid(enemy) then return nil end
    if enemy:IsPlayer() then
        return { type = "player", id = enemy:SteamID64() }
    elseif enemy:IsNPC() then
        return { type = "npc", id = GenerateNPCUniqueID(enemy) }
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
                scheduleData.target = { type = "player", id = target:SteamID64() }
            else
                scheduleData.target = { type = "entity", id = GenerateNPCUniqueID(target), class = target:GetClass() }
            end
        end
    end
    return scheduleData
end

local function GetNPCKeyValues(npc)
    local keyValuesData = {}
    local npcKeyValues = npc:GetKeyValues() or {}
    for _, keyName in ipairs(CONFIG.KEY_VALUES_TO_SAVE) do
        local val = npcKeyValues[keyName]
        if val ~= nil then
            keyValuesData[keyName] = val
        end
    end
    return next(keyValuesData) and keyValuesData or nil
end

local function GetNPCBodygroups(npc)
    local bodygroupsData = {}
    local numBodygroups = SafeGetNPCProperty(npc, function() return npc:GetNumBodyGroups() end, 0)
    for i = 0, numBodygroups - 1 do
        bodygroupsData[i] = npc:GetBodygroup(i)
    end
    return bodygroupsData
end

local function GetCitizenProperties(npc)
    if not IsValid(npc) or npc:GetClass() ~= "npc_citizen" then return {} end
    local citizenData = {}
    local keyValues = npc:GetKeyValues() or {}
    if keyValues.citizentype then citizenData.citizenType = tonumber(keyValues.citizentype) end
    if keyValues.citizentype == "3" or npc:GetNWBool("IsMedic", false) then citizenData.isMedic = true end
    if keyValues.ammosupplier == "1" or npc:GetNWBool("IsAmmoSupplier", false) then citizenData.isAmmoSupplier = true end
    citizenData.isRebel = npc:GetNWBool("IsRebel", false)
    return citizenData
end

local function GetNPCPhysicsProperties(npc)
    local physData = {
        exists = false,
        frozen = false,
        gravityEnabled = true,
        motionEnabled = true,
        mass = 85,
        material = "flesh"
    }
    if not IsValid(npc) then return physData end
    local phys = npc:GetPhysicsObject()
    if not IsValid(phys) then return physData end
    physData.exists = true
    physData.frozen = SafeGetNPCProperty(phys, function() return not phys:IsMotionEnabled() end, false)
    physData.motionEnabled = SafeGetNPCProperty(phys, function() return phys:IsMotionEnabled() end, true)
    physData.gravityEnabled = SafeGetNPCProperty(phys, function() return phys:IsGravityEnabled() end, true)
    physData.mass = SafeGetNPCProperty(phys, function() return phys:GetMass() end, 85)
    physData.material = SafeGetNPCProperty(phys, function() return phys:GetMaterial() end, "flesh")
    if phys.GetVelocity then physData.velocity = phys:GetVelocity() end
    return physData
end

local function GetVJBaseProperties(npc)
    if not IsValid(npc) then return {} end
    local cls = npc:GetClass() or ""
    local isVJ = string.sub(cls, 1, 7) == "npc_vj_" or npc.IsVJBaseSNPC == true
    if not isVJ then return {} end
    local vjData = {}
    vjData.isVJBaseNPC = true
    vjData.vjType = npc:GetNWString("VJ_Type", "")
    vjData.maxHealth = npc:GetMaxHealth()
    vjData.startHealth = npc:GetNWInt("VJ_StartingHealth", npc:GetMaxHealth())
    vjData.animationPlaybackRate = npc:GetNWFloat("AnimationPlaybackRate", 1)
    vjData.walkSpeed = npc:GetNWInt("VJ_WalkSpeed", 0)
    vjData.runSpeed = npc:GetNWInt("VJ_RunSpeed", 0)
    -- Follow state: use entity table fields instead of controller NWVars
    local entTbl = npc:GetTable() or {}
    local isFollowing = (npc.IsFollowing == true) or (entTbl.IsFollowing == true)
    vjData.isFollowing = isFollowing or false
    if entTbl.FollowData and IsValid(entTbl.FollowData.Target) then
        local tgt = entTbl.FollowData.Target
        if tgt:IsPlayer() then
            vjData.followTarget = { type = "player", id = (tgt.SteamID64 and tgt:SteamID64()) or tgt:SteamID() }
        elseif tgt:IsNPC() then
            vjData.followTarget = { type = "npc", id = GenerateNPCUniqueID(tgt) }
        else
            vjData.followTarget = { type = "entity", class = tgt:GetClass(), pos = tgt:GetPos():ToTable() }
        end
        vjData.followMinDistance = entTbl.FollowData.MinDist
    end
    vjData.isMeleeAttacker = npc:GetNWBool("VJ_IsMeleeAttacking", false)
    vjData.isRangeAttacker = npc:GetNWBool("VJ_IsRangeAttacking", false)
    vjData.faction = npc.VJ_NPC_Class or npc:GetNWString("VJ_NPC_Class", "")
    return vjData
end

return function(ply)
    local startTime = SysTime()
    local npcsData = {}

    local allNPCs = {}
    do
        local entsAll = ents.GetAll()
        for i = 1, #entsAll do
            local e = entsAll[i]
            if IsValid(e) and e:IsNPC() then
                allNPCs[#allNPCs + 1] = e
            end
        end
    end

    local npcCount = #allNPCs
    DebugLog("Found %d NPCs on the map", npcCount)

    table.sort(allNPCs, function(a, b)
        local ao, bo = GetEntityOwner(a), GetEntityOwner(b)
        return IsValid(ao) and not IsValid(bo)
    end)

    if #allNPCs > CONFIG.MAX_NPCS_TO_SAVE then
        DebugLog("WARNING: NPC count exceeds maximum (%d/%d). Some NPCs will not be saved.", #allNPCs,
            CONFIG.MAX_NPCS_TO_SAVE)
        allNPCs = { unpack(allNPCs, 1, CONFIG.MAX_NPCS_TO_SAVE) }
    end

    local players = player.GetAll()
    local savedCount = 0

    for i = 1, #allNPCs do
        local npc = allNPCs[i]
        if not IsValid(npc) then continue end

        local owner = GetEntityOwner(npc)
        local isOwnerPlayer = false
        if owner and owner.IsPlayer and owner:IsPlayer() then isOwnerPlayer = true end
        local shouldSave = isOwnerPlayer or npc.SpawnedByRareload or not CONFIG.SAVE_PLAYER_OWNED_ONLY
        if not shouldSave then continue end

        local ok, err = pcall(function()
            local col = npc:GetColor() or Color(255, 255, 255, 255)
            local colTbl = { r = col.r or 255, g = col.g or 255, b = col.b or 255, a = col.a or 255 }

            local submaterials = {}
            local mats = npc:GetMaterials() or {}
            for sm = 0, #mats do
                local sub = npc:GetSubMaterial(sm)
                if sub and sub ~= "" then submaterials[sm] = sub end
            end

            local ang = npc:GetAngles() or Angle(0, 0, 0)
            local pos = npc:GetPos() or Vector(0, 0, 0)

            local npcData = {
                id = GenerateNPCUniqueID(npc),
                class = npc:GetClass(),
                pos = { x = pos.x, y = pos.y, z = pos.z },
                ang = { p = ang.p, y = ang.y, r = ang.r },
                model = npc:GetModel(),
                skin = npc:GetSkin(),
                bodygroups = GetNPCBodygroups(npc),
                modelScale = npc:GetModelScale(),
                color = colTbl, -- single canonical color table
                renderMode = npc:GetRenderMode(),
                renderFX = npc:GetRenderFX(),
                materialOverride = npc:GetMaterial(),
                submaterials = submaterials,
                health = npc:Health(),
                maxHealth = npc:GetMaxHealth(),
                bloodColor = npc:GetBloodColor(),
                moveType = npc:GetMoveType(),
                solidType = npc:GetSolid(),
                collisionGroup = npc:GetCollisionGroup(),
                physics = GetNPCPhysicsProperties(npc),
                vjBaseData = GetVJBaseProperties(npc),
                frozen = IsValid(npc:GetPhysicsObject()) and not npc:GetPhysicsObject():IsMotionEnabled(),
                weapons = GetNPCWeapons(npc),
                keyValues = GetNPCKeyValues(npc), -- already stripped of duplicates
                squad = (function()
                    local kv = npc:GetKeyValues() or {}
                    local s = kv.squadname
                    if s == nil and npc.GetSquad then
                        local ok, val = pcall(function() return npc:GetSquad() end)
                        if ok and isstring(val) then s = val end
                    end
                    return s
                end)(),
                squadMembers = (function()
                    local members = {}
                    if npc.GetSquad then
                        local ok, squad = pcall(function() return npc:GetSquad() end)
                        if ok and squad and squad ~= "" then
                            -- Find all NPCs with the same squad name
                            for j = 1, #allNPCs do
                                local otherNPC = allNPCs[j]
                                if IsValid(otherNPC) and otherNPC ~= npc then
                                    local otherSquad = getsquadname(otherNPC)
                                    if otherSquad == squad then
                                        members[#members + 1] = GenerateNPCUniqueID(otherNPC)
                                    end
                                end
                            end
                        end
                    end
                    return members
                end)(),
                squadLeader = SafeGetNPCProperty(npc, function() return npc.IsSquadLeader and npc:IsSquadLeader() end,
                    false),
                target = GetNPCTarget(npc),
                schedule = GetNPCSchedule(npc),
                relations = GetNPCRelations(npc, players, allNPCs),
                citizenData = GetCitizenProperties(npc),
                velocity = npc:GetVelocity(), -- not duplicated elsewhere
                creationTime = npc.CreationTime or CurTime(),
                flags = npc:GetFlags(),       -- distinct from spawnflags
                npcState = npc.GetNPCState and npc:GetNPCState() or nil,
                hullType = npc.GetHullType and npc:GetHullType() or nil,
                expression = npc.GetExpression and npc:GetExpression() or nil,
                weaponProficiency = npc.GetCurrentWeaponProficiency and npc:GetCurrentWeaponProficiency() or nil,
                isControlled = npc:GetNWBool("IsControlled", false),
                sequence = npc.GetSequence and npc:GetSequence() or nil,
                cycle = npc.GetCycle and npc:GetCycle() or nil,
                playbackRate = npc.GetPlaybackRate and npc:GetPlaybackRate() or nil,
                spawnflags = npc.GetSpawnFlags and npc:GetSpawnFlags() or nil, -- explicit (removed from keyValues)
                SavedByRareload = true,
                SavedAt = os.time()
            }

            -- Network the ID immediately so client can associate without waiting for respawn
            if npc.SetNWString and npcData.id then
                pcall(function() npc:SetNWString("RareloadID", npcData.id) end)
            end

            if npc:GetClass() == "npc_vortigaunt" then
                local SCHED_ALLY_INJURED_FOLLOW_CONST = rawget(_G, "SCHED_ALLY_INJURED_FOLLOW")
                npcData.isAlly = SafeGetNPCProperty(npc,
                    function()
                        return npc.IsCurrentSchedule and SCHED_ALLY_INJURED_FOLLOW_CONST ~= nil and
                            npc:IsCurrentSchedule(SCHED_ALLY_INJURED_FOLLOW_CONST)
                    end,
                    false)
            end

            if npc.AddEntityRelationship and IsValid(ply) then
                npcData.playerRelationship = SafeGetNPCProperty(npc, function() return npc:Disposition(ply) end, nil)
            end

            -- Safer owner serialization
            do
                local osid = nil
                if owner then
                    if owner.SteamID64 then
                        osid = owner:SteamID64()
                    elseif owner.SteamID then
                        osid = owner:SteamID()
                    end
                end
                npcData.ownerSteamID = osid
            end

            if RARELOAD.Util and RARELOAD.Util.GenerateEntityStateHash then
                npcData.stateHash = RARELOAD.Util.GenerateEntityStateHash({
                    material = npcData.materialOverride,
                    model = npcData.model,
                    skin = npcData.skin,
                    health = npcData.health,
                    maxHealth = npcData.maxHealth,
                    modelScale = npcData.modelScale,
                    collisionGroup = npcData.collisionGroup,
                    moveType = npcData.moveType,
                    solidType = npcData.solidType,
                    spawnFlags = npcData.spawnflags,
                    color = npcData.color,
                    bodygroups = npcData.bodygroups,
                    physicsMaterial = npcData.physics and npcData.physics.material or nil,
                    gravityEnabled = npcData.physics and npcData.physics.gravityEnabled,
                    elasticity = npcData.physics and npcData.physics.elasticity,
                    frozen = npcData.frozen,
                    mass = npcData.physics and npcData.physics.mass or nil
                })
            end

            npcsData[#npcsData + 1] = npcData
        end)

        if ok then
            savedCount = savedCount + 1
        else
            DebugLog("Failed to save NPC %s: %s", IsValid(npc) and npc:GetClass() or "invalid", tostring(err))
        end
    end

    local endTime = SysTime()
    DebugLog("Saved %d/%d NPCs in %.3f seconds", savedCount, npcCount, endTime - startTime)

    return npcsData
end
