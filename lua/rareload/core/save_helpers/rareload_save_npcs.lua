-- RareLoad Save NPCs Module

local RARELOAD = RARELOAD or {}
RARELOAD.NPCSaver = RARELOAD.NPCSaver or {}

local CONFIG = {
    DEBUG = true,
    SAVE_PLAYER_OWNED_ONLY = false,
    MAX_NPCS_TO_SAVE = 500,
    SAVE_NPC_NPC_RELATIONS = false,
    MAX_RELATION_NPCS = 128,
    KEY_VALUES_TO_SAVE = {
        "spawnflags", "squadname", "targetname",
        "wakeradius", "sleepstate", "health",
        "rendercolor", "rendermode", "renderamt",
        "additionalequipment", "expression", "citizentype"
    }
}

local function DebugLog(msg, ...)
    if CONFIG.DEBUG then
        local formatted = string.format(msg, ...)
        print("[RareLoad NPC Saver] " .. formatted)
        if SERVER then ServerLog("[RareLoad NPC Saver] " .. formatted .. "\n") end
    end
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

local function GenerateNPCUniqueID(npc)
    if not IsValid(npc) then return "invalid_npc" end
    local pos = npc:GetPos()
    local ang = npc:GetAngles()
    local gx, gy, gz = math.floor(pos.x / 16), math.floor(pos.y / 16), math.floor(pos.z / 16)
    local class = npc:GetClass() or "unknown"
    local model = npc:GetModel() or "nomodel"
    local skin = npc:GetSkin() or 0
    local kv = npc:GetKeyValues() or {}
    local targetname = tostring(kv.targetname or "")
    local squadname = tostring(kv.squadname or "")
    local numBG = SafeGetNPCProperty(npc, function() return npc:GetNumBodyGroups() end, 0)
    local bgParts = {}
    for i = 0, numBG - 1 do
        bgParts[#bgParts + 1] = tostring(npc:GetBodygroup(i))
    end
    local base = table.concat({
        class, model, tostring(skin),
        tostring(gx), tostring(gy), tostring(gz),
        string.format("%.1f", ang.p), string.format("%.1f", ang.y), string.format("%.1f", ang.r),
        targetname, squadname, table.concat(bgParts, ",")
    }, "|")
    local hash = util.CRC(base)
    return class .. "_" .. hash
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
        if npcKeyValues[keyName] ~= nil then
            keyValuesData[keyName] = npcKeyValues[keyName]
        end
    end
    return keyValuesData
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
    vjData.isFollowing = npc:GetNWBool("VJ_IsBeingControlled", false)
    vjData.followTarget = npc:GetNWEntity("VJ_TheController")
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
        local shouldSave = (IsValid(owner) and owner:IsPlayer()) or npc.SpawnedByRareload or
        not CONFIG.SAVE_PLAYER_OWNED_ONLY
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

            local npcData = {
                id = GenerateNPCUniqueID(npc),
                class = npc:GetClass(),
                pos = npc:GetPos():ToTable(),
                ang = npc:GetAngles(),
                model = npc:GetModel(),
                skin = npc:GetSkin(),
                bodygroups = GetNPCBodygroups(npc),
                modelScale = npc:GetModelScale(),
                color = colTbl,
                renderColor = colTbl,
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
                keyValues = GetNPCKeyValues(npc),
                target = GetNPCTarget(npc),
                schedule = GetNPCSchedule(npc),
                relations = GetNPCRelations(npc, players, allNPCs),
                citizenData = GetCitizenProperties(npc),
                velocity = npc:GetVelocity(),
                ownerSteamID = IsValid(owner) and (owner.SteamID64 and owner:SteamID64() or owner:SteamID()) or nil,
                creationTime = npc.CreationTime or CurTime(),
                flags = npc:GetFlags(),
                npcState = npc.GetNPCState and npc:GetNPCState() or nil,
                hullType = npc.GetHullType and npc:GetHullType() or nil,
                expression = npc.GetExpression and npc:GetExpression() or nil,
                weaponProficiency = npc.GetCurrentWeaponProficiency and npc:GetCurrentWeaponProficiency() or nil,
                isControlled = npc:GetNWBool("IsControlled", false),
                sequence = npc.GetSequence and npc:GetSequence() or nil,
                cycle = npc.GetCycle and npc:GetCycle() or nil,
                playbackRate = npc.GetPlaybackRate and npc:GetPlaybackRate() or nil,
                spawnflags = npc.GetSpawnFlags and npc:GetSpawnFlags() or nil,
                SavedByRareload = true,
                SavedAt = os.time()
            }

            if npc:GetClass() == "npc_vortigaunt" then
                npcData.isAlly = SafeGetNPCProperty(npc,
                    function() return npc.IsCurrentSchedule and npc:IsCurrentSchedule(SCHED_ALLY_INJURED_FOLLOW) end,
                    false)
            end

            if npc.AddEntityRelationship and IsValid(ply) then
                npcData.playerRelationship = SafeGetNPCProperty(npc, function() return npc:Disposition(ply) end, nil)
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
