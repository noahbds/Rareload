-- RareLoad Save NPCs Module

local RARELOAD = RARELOAD or {}
RARELOAD.NPCSaver = RARELOAD.NPCSaver or {}

local CONFIG = {
    DEBUG = true,
    SAVE_PLAYER_OWNED_ONLY = false,
    SAVE_RADIUS = 5000,
    MAX_NPCS_TO_SAVE = 500,
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


local function GenerateNPCUniqueID(npc)
    if not IsValid(npc) then return "invalid_npc" end

    local pos = npc:GetPos()
    local posStr = math.floor(pos.x) .. "_" .. math.floor(pos.y) .. "_" .. math.floor(pos.z)
    local baseID = npc:GetClass() .. "_" .. posStr .. "_" .. (npc:GetModel() or "nomodel")

    local extraData = {}
    local keyValues = npc:GetKeyValues() or {}
    if keyValues.targetname then table.insert(extraData, keyValues.targetname) end
    if keyValues.squadname then table.insert(extraData, keyValues.squadname) end

    local hashComponent = util.CRC(tostring(npc:EntIndex()) .. "_" .. tostring(CurTime()) .. "_" .. posStr)

    return baseID .. (next(extraData) and "_" .. table.concat(extraData, "_") or "") .. "_" .. hashComponent
end

local function SafeGetNPCProperty(npc, propertyFn, defaultValue)
    if not IsValid(npc) then return defaultValue end

    local success, result = pcall(propertyFn)
    if success then
        return result
    else
        DebugLog("Failed to get NPC property: %s", result)
        return defaultValue
    end
end


local function GetNPCRelations(npc)
    local relations = { players = {}, npcs = {} }

    if not IsValid(npc) or not npc.Disposition then
        return relations
    end

    local allPlayers = player.GetAll()
    for _, player in ipairs(allPlayers) do
        local disposition = SafeGetNPCProperty(
            npc,
            function() return npc:Disposition(player) end,
            nil
        )
        if disposition then
            relations.players[player:SteamID()] = disposition
        end
    end

    local allNPCs = ents.FindByClass("npc_*")
    for _, otherNPC in ipairs(allNPCs) do
        if IsValid(otherNPC) and otherNPC ~= npc then
            local disposition = SafeGetNPCProperty(
                npc,
                function() return npc:Disposition(otherNPC) end,
                nil
            )
            if disposition then
                local npcID = GenerateNPCUniqueID(otherNPC)
                relations.npcs[npcID] = disposition
            end
        end
    end

    return relations
end


local function GetNPCWeapons(npc)
    local weaponData = {}

    local weapons = SafeGetNPCProperty(
        npc,
        function() return npc:GetWeapons() end,
        {}
    )

    if istable(weapons) then
        for _, weapon in ipairs(weapons) do
            if IsValid(weapon) then
                local singleWeapon = {
                    class = weapon:GetClass(),
                    clipAmmo = SafeGetNPCProperty(weapon, function() return weapon:Clip1() end, -1),
                    ammoType = SafeGetNPCProperty(weapon, function() return weapon:GetPrimaryAmmoType() end, -1),
                    secondaryAmmoType = SafeGetNPCProperty(weapon, function() return weapon:GetSecondaryAmmoType() end,
                        -1)
                }
                table.insert(weaponData, singleWeapon)
            end
        end
    end

    return weaponData
end


local function GetNPCTarget(npc)
    if not npc.GetEnemy or not IsValid(npc:GetEnemy()) then
        return nil
    end

    local enemy = npc:GetEnemy()
    if enemy:IsPlayer() then
        return { type = "player", id = enemy:SteamID() }
    elseif enemy:IsNPC() then
        return { type = "npc", id = GenerateNPCUniqueID(enemy) }
    elseif IsValid(enemy) then
        return {
            type = "entity",
            class = enemy:GetClass(),
            pos = enemy:GetPos():ToTable()
        }
    end

    return nil
end


local function GetNPCSchedule(npc)
    if not npc.GetCurrentSchedule then
        return nil
    end

    local scheduleID = npc:GetCurrentSchedule()
    if not scheduleID then
        return nil
    end

    local scheduleData = { id = scheduleID }

    if npc.GetTarget and IsValid(npc:GetTarget()) then
        local target = npc:GetTarget()
        if target:IsPlayer() then
            scheduleData.target = { type = "player", id = target:SteamID() }
        else
            scheduleData.target = {
                type = "entity",
                id = GenerateNPCUniqueID(target),
                class = target:GetClass()
            }
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

    local numBodygroups = SafeGetNPCProperty(
        npc,
        function() return npc:GetNumBodyGroups() end,
        0
    )

    for i = 0, numBodygroups - 1 do
        bodygroupsData[i] = npc:GetBodygroup(i)
    end

    return bodygroupsData
end


local function GetCitizenProperties(npc)
    if not IsValid(npc) or npc:GetClass() ~= "npc_citizen" then
        return {}
    end

    local citizenData = {}
    local keyValues = npc:GetKeyValues() or {}

    if keyValues.citizentype then
        citizenData.citizenType = tonumber(keyValues.citizentype)
    end

    if keyValues.citizentype == "3" or npc:GetNWBool("IsMedic", false) then
        citizenData.isMedic = true
    end

    if keyValues.ammosupplier == "1" or npc:GetNWBool("IsAmmoSupplier", false) then
        citizenData.isAmmoSupplier = true
    end

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

    if not IsValid(npc) then
        return physData
    end

    local phys = npc:GetPhysicsObject()
    if not IsValid(phys) then
        return physData
    end

    physData.exists = true

    physData.frozen = SafeGetNPCProperty(phys, function() return not phys:IsMotionEnabled() end, false)
    physData.motionEnabled = SafeGetNPCProperty(phys, function() return phys:IsMotionEnabled() end, true)
    physData.gravityEnabled = SafeGetNPCProperty(phys, function() return phys:IsGravityEnabled() end, true)
    physData.mass = SafeGetNPCProperty(phys, function() return phys:GetMass() end, 85)
    physData.material = SafeGetNPCProperty(phys, function() return phys:GetMaterial() end, "flesh")

    if phys.GetVelocity then
        physData.velocity = phys:GetVelocity()
    end

    return physData
end


local function GetVJBaseProperties(npc)
    if not IsValid(npc) then return {} end

    local isVJBaseNPC = string.find(npc:GetClass() or "", "npc_vj_") == 1
    if not isVJBaseNPC then return {} end

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

    vjData.faction = npc:GetNWString("VJ_NPC_Class", "")

    return vjData
end

return function(ply)
    local startTime = SysTime()
    local npcCount = 0
    local savedCount = 0
    local npcsData = {}

    local allNPCs = ents.FindByClass("npc_*")
    npcCount = #allNPCs

    DebugLog("Found %d NPCs on the map", npcCount)

    table.sort(allNPCs, function(a, b)
        local aOwned = IsValid(a:CPPIGetOwner())
        local bOwned = IsValid(b:CPPIGetOwner())
        return aOwned and not bOwned
    end)

    if #allNPCs > CONFIG.MAX_NPCS_TO_SAVE then
        DebugLog("WARNING: NPC count exceeds maximum (%d/%d). Some NPCs will not be saved.",
            #allNPCs, CONFIG.MAX_NPCS_TO_SAVE)
        allNPCs = { unpack(allNPCs, 1, CONFIG.MAX_NPCS_TO_SAVE) }
    end

    for _, npc in ipairs(allNPCs) do
        if not IsValid(npc) then continue end

        local owner = npc:CPPIGetOwner()
        local shouldSave = (
            (IsValid(owner) and owner:IsPlayer()) or
            npc.SpawnedByRareload or
            not CONFIG.SAVE_PLAYER_OWNED_ONLY
        )

        if shouldSave then
            local success, result = pcall(function()
                local npcID = GenerateNPCUniqueID(npc)

                local npcData = {
                    id = npcID,
                    class = npc:GetClass(),
                    pos = npc:GetPos(),
                    ang = npc:GetAngles(),
                    model = npc:GetModel(),
                    health = npc:Health(),
                    maxHealth = npc:GetMaxHealth(),
                    modelScale = npc:GetModelScale(),
                    color = npc:GetColor(),
                    bloodColor = npc:GetBloodColor(),
                    materialOverride = npc:GetMaterial(),
                    renderMode = npc:GetRenderMode(),
                    renderFX = npc:GetRenderFX(),

                    renderAlpha = SafeGetNPCProperty(npc, function() return npc:GetRenderMode() end, 0) == 0
                        and 255 or SafeGetNPCProperty(npc, function() return npc:GetRenderFX() end, 0),
                    renderColor = SafeGetNPCProperty(npc, function()
                        if npc.GetRenderColor then
                            return npc:GetRenderColor()
                        else
                            return Color(255, 255, 255, 255)
                        end
                    end, Color(255, 255, 255, 255)),

                    moveType = npc:GetMoveType(),
                    solidType = npc:GetSolid(),
                    collisionGroup = npc:GetCollisionGroup(),
                    skin = npc:GetSkin(),
                    physics = GetNPCPhysicsProperties(npc),
                    vjBaseData = GetVJBaseProperties(npc),
                    frozen = IsValid(npc:GetPhysicsObject()) and not npc:GetPhysicsObject():IsMotionEnabled(),

                    weapons = GetNPCWeapons(npc),
                    keyValues = GetNPCKeyValues(npc),
                    bodygroups = GetNPCBodygroups(npc),
                    target = GetNPCTarget(npc),
                    schedule = GetNPCSchedule(npc),
                    relations = GetNPCRelations(npc),

                    citizenData = GetCitizenProperties(npc),

                    velocity = npc:GetVelocity(),
                    ownerSteamID = IsValid(owner) and owner:SteamID() or nil,
                    creationTime = npc.CreationTime or CurTime(),
                    flags = npc:GetFlags(),

                    SavedByRareload = true,
                    SavedAt = os.time()
                }

                if npc.GetNPCState then npcData.npcState = npc:GetNPCState() end
                if npc.GetHullType then npcData.hullType = npc:GetHullType() end
                if npc.GetExpression then npcData.expression = npc:GetExpression() end

                if npc:GetClass() == "npc_vortigaunt" then
                    npcData.isAlly = SafeGetNPCProperty(npc,
                        function() return npc:IsCurrentSchedule(SCHED_ALLY_INJURED_FOLLOW) end, false)
                end

                if npc.GetCurrentWeaponProficiency then
                    npcData.weaponProficiency = npc:GetCurrentWeaponProficiency()
                end

                if npc.AddEntityRelationship then
                    npcData.playerRelationship = SafeGetNPCProperty(
                        npc,
                        function()
                            if IsValid(ply) then
                                return npc:Disposition(ply)
                            end
                            return nil
                        end,
                        nil
                    )
                end

                npcData.isControlled = npc:GetNWBool("IsControlled", false)

                table.insert(npcsData, npcData)
                return true
            end)

            if success then
                savedCount = savedCount + 1
            else
                DebugLog("Failed to save NPC %s: %s", npc:GetClass(), tostring(result))
            end
        end
    end

    local endTime = SysTime()
    DebugLog("Saved %d/%d NPCs in %.3f seconds", savedCount, npcCount, endTime - startTime)

    return npcsData
end
