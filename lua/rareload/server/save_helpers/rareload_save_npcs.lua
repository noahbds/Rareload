local function GenerateNPCUniqueID(npc)
    if not IsValid(npc) then return "invalid" end
    local pos = npc:GetPos()
    local posStr = math.floor(pos.x) .. "_" .. math.floor(pos.y) .. "_" .. math.floor(pos.z)
    local id = npc:GetClass() .. "_" .. posStr .. "_" .. (npc:GetModel() or "nomodel")
    if npc:GetKeyValues().targetname then
        id = id .. "_" .. npc:GetKeyValues().targetname
    end
    if npc:GetKeyValues().squadname then
        id = id .. "_" .. npc:GetKeyValues().squadname
    end
    return id
end

local function GetNPCRelations(npc)
    local relations = { players = {}, npcs = {} }
    if not npc.Disposition then return relations end
    for _, player in ipairs(player.GetAll()) do
        local success, disposition = pcall(function() return npc:Disposition(player) end)
        if success and disposition then
            relations.players[player:SteamID()] = disposition
        end
    end
    for _, otherNPC in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(otherNPC) and otherNPC ~= npc then
            local npcID = GenerateNPCUniqueID(otherNPC)
            local success, disposition = pcall(function() return npc:Disposition(otherNPC) end)
            if success and disposition then
                relations.npcs[npcID] = disposition
            end
        end
    end
    return relations
end

return function(ply)
    local npcs = {}
    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) then
            local owner = npc:CPPIGetOwner()
            if (IsValid(owner) and owner:IsPlayer()) or npc.SpawnedByRareload then
                local npcID = GenerateNPCUniqueID(npc)
                local npcData = {
                    id = npcID,
                    class = npc:GetClass(),
                    pos = npc:GetPos(),
                    ang = npc:GetAngles(),
                    model = npc:GetModel(),
                    health = npc:Health(),
                    maxHealth = npc:GetMaxHealth(),
                    weapons = {},
                    keyValues = {},
                    skin = npc:GetSkin(),
                    bodygroups = {},
                    target = nil,
                    frozen = IsValid(npc:GetPhysicsObject()) and not npc:GetPhysicsObject():IsMotionEnabled(),
                    relations = GetNPCRelations(npc),
                    schedule = nil,
                    SavedByRareload = true
                }
                for i = 0, npc:GetNumBodyGroups() - 1 do
                    npcData.bodygroups[i] = npc:GetBodygroup(i)
                end
                if npc.GetEnemy and IsValid(npc:GetEnemy()) then
                    local enemy = npc:GetEnemy()
                    if enemy:IsPlayer() then
                        npcData.target = { type = "player", id = enemy:SteamID() }
                    elseif enemy:IsNPC() then
                        npcData.target = { type = "npc", id = GenerateNPCUniqueID(enemy) }
                    end
                end
                if npc.GetCurrentSchedule then
                    local scheduleID = npc:GetCurrentSchedule()
                    if scheduleID then
                        npcData.schedule = { id = scheduleID }
                        if npc.GetTarget and IsValid(npc:GetTarget()) then
                            local target = npc:GetTarget()
                            if target:IsPlayer() then
                                npcData.schedule.target = { type = "player", id = target:SteamID() }
                            else
                                npcData.schedule.target = { type = "entity", id = GenerateNPCUniqueID(target) }
                            end
                        end
                    end
                end
                local success, weapons = pcall(function() return npc:GetWeapons() end)
                if success and istable(weapons) then
                    for _, weapon in ipairs(weapons) do
                        if IsValid(weapon) then
                            local weaponData = { class = weapon:GetClass() }
                            pcall(function() weaponData.clipAmmo = weapon:Clip1() end)
                            table.insert(npcData.weapons, weaponData)
                        end
                    end
                end
                local keyValues = {
                    "spawnflags", "squadname", "targetname",
                    "wakeradius", "sleepstate", "health",
                    "rendercolor", "rendermode", "renderamt"
                }
                for _, keyName in ipairs(keyValues) do
                    local value = npc:GetKeyValues()[keyName]
                    if value then
                        npcData.keyValues[keyName] = value
                    end
                end
                table.insert(npcs, npcData)
            end
        end
    end
    return npcs
end
