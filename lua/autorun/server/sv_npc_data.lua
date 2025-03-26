RARELOAD = RARELOAD or {}

function RARELOAD.AddNPCsData(playerData)
    playerData.npcs = {}
    local startTime = SysTime()
    local count = 0

    RARELOAD.npcIDMap = {}

    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) then
            count = count + 1
            local npcID = RARELOAD.GenerateNPCUniqueID(npc)

            local RARELOAD = {
                id = npcID,
                class = npc:GetClass(),
                pos = npc:GetPos(),
                ang = npc:GetAngles(),
                model = npc:GetModel() or "models/error.mdl",
                health = npc:Health(),
                maxHealth = npc:GetMaxHealth(),
                weapons = {},
                keyValues = {},
                skin = npc:GetSkin(),
                bodygroups = {},
                target = nil,
                frozen = IsValid(npc:GetPhysicsObject()) and not npc:GetPhysicsObject():IsMotionEnabled(),
                relations = RARELOAD.GetNPCRelations(npc),
                schedule = nil,
            }

            RARELOAD.AddBodygroups(npc, RARELOAD)
            RARELOAD.AddTargetData(npc, RARELOAD)
            RARELOAD.AddScheduleData(npc, RARELOAD)
            RARELOAD.AddWeaponsData(npc, RARELOAD)
            RARELOAD.AddKeyValuesData(npc, RARELOAD)

            RARELOAD.npcIDMap[npcID] = RARELOAD
            table.insert(playerData.npcs, RARELOAD)
        end
    end

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " .. count .. " NPCs in " ..
            math.Round((SysTime() - startTime) * 1000) .. " ms")
        print("[RARELOAD DEBUG] NPC data size: " ..
            string.NiceSize(#util.TableToJSON(playerData.npcs)))
    end
end

function RARELOAD.GenerateNPCUniqueID(npc)
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

function RARELOAD.GetNPCRelations(npc)
    local relations = {
        players = {},
        npcs = {}
    }

    if not npc.Disposition then
        return relations
    end

    for _, player in ipairs(player.GetAll()) do
        local success, disposition = pcall(function() return npc:Disposition(player) end)
        if success and disposition then
            relations.players[player:SteamID()] = disposition
        end
    end

    local npcMap = {}
    for _, otherNPC in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(otherNPC) and otherNPC ~= npc then
            local npcID = RARELOAD.GenerateNPCUniqueID(otherNPC)
            npcMap[otherNPC] = npcID

            local success, disposition = pcall(function() return npc:Disposition(otherNPC) end)
            if success and disposition then
                relations.npcs[npcID] = disposition
            end
        end
    end

    return relations
end

function RARELOAD.AddBodygroups(npc, RARELOAD)
    for i = 0, npc:GetNumBodyGroups() - 1 do
        RARELOAD.bodygroups[i] = npc:GetBodygroup(i)
    end
end

function RARELOAD.AddTargetData(npc, RARELOAD)
    if npc.GetEnemy and IsValid(npc:GetEnemy()) then
        local enemy = npc:GetEnemy()
        if enemy:IsPlayer() then
            RARELOAD.target = {
                type = "player",
                id = enemy:SteamID()
            }
        elseif enemy:IsNPC() then
            RARELOAD.target = {
                type = "npc",
                id = RARELOAD.GenerateNPCUniqueID(enemy)
            }
        end
    end
end

function RARELOAD.AddScheduleData(npc, RARELOAD)
    if npc.GetCurrentSchedule then
        local scheduleID = npc:GetCurrentSchedule()
        if scheduleID then
            RARELOAD.schedule = {
                id = scheduleID
            }

            if npc.GetTarget and IsValid(npc:GetTarget()) then
                local target = npc:GetTarget()
                if target:IsPlayer() then
                    RARELOAD.schedule.target = {
                        type = "player",
                        id = target:SteamID()
                    }
                else
                    RARELOAD.schedule.target = {
                        type = "entity",
                        id = RARELOAD.GenerateNPCUniqueID(target)
                    }
                end
            end
        end
    end
end

function RARELOAD.AddWeaponsData(npc, RARELOAD)
    local success, weapons = pcall(function() return npc:GetWeapons() end)
    if success and istable(weapons) then
        for _, weapon in ipairs(weapons) do
            if IsValid(weapon) then
                local weaponData = {
                    class = weapon:GetClass()
                }

                pcall(function()
                    weaponData.clipAmmo = weapon:Clip1()
                end)

                table.insert(RARELOAD.weapons, weaponData)
            end
        end
    end
end

function RARELOAD.AddKeyValuesData(npc, RARELOAD)
    RARELOAD.keyValues = {}
    local keyValues = {
        "spawnflags", "squadname", "targetname",
        "wakeradius", "sleepstate", "health",
        "rendercolor", "rendermode", "renderamt"
    }

    for _, keyName in ipairs(keyValues) do
        local value = npc:GetKeyValues()[keyName]
        if value then
            RARELOAD.keyValues[keyName] = value
        end
    end
end
