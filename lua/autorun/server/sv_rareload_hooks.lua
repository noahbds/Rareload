LoadAddonState()

util.AddNetworkString("CreatePlayerPhantom")
util.AddNetworkString("RemovePlayerPhantom")
util.AddNetworkString("SyncData")
util.AddNetworkString("SyncPlayerPositions")
util.AddNetworkString("RareloadTeleportTo")
util.AddNetworkString("RareloadReloadData")


local RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Debug = RARELOAD.Debug or {}

MapName = game.GetMap()
local lastSavedTimes = {}

hook.Add("PlayerInitialSpawn", "SyncDataOnJoin", function(ply)
    SyncData(ply)
end)

hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    LoadAddonState()

    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    local filePath = "rareload/player_positions_" .. MapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            local status, result = pcall(util.JSONToTable, data)
            if status then
                RARELOAD.playerPositions = result
            else
                print("[RARELOAD DEBUG] Error parsing JSON: " .. result)
            end
        else
            print("[RARELOAD DEBUG] File is empty: " .. filePath)
        end
    else
        print("[RARELOAD DEBUG] File does not exist: " .. filePath)
    end
end)

hook.Add("PlayerDisconnect", "SavePlayerPositionDisconnect", function(ply)
    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    RARELOAD.playerPositions[MapName] = RARELOAD.playerPositions[MapName] or {}
    RARELOAD.playerPositions[MapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType(),
    }
end)

hook.Add("PlayerDeath", "SetWasKilledFlag", function(ply)
    ply.wasKilled = true
end)

local json = util.JSONToTable
local cacheFile = "rareload/cached_pos_" .. MapName .. ".json"

local function LoadCachedPositions()
    if not file.Exists(cacheFile, "DATA") then return {} end
    local data = file.Read(cacheFile, "DATA")
    return json(data) or {}
end

local function SavePositionToCache(pos)
    local cachedPositions = LoadCachedPositions()

    for _, savedPos in ipairs(cachedPositions) do
        if savedPos.x == pos.x and savedPos.y == pos.y and savedPos.z == pos.z then
            return
        end
    end
    table.insert(cachedPositions, pos)
    file.Write(cacheFile, util.TableToJSON(cachedPositions, true))
end

hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    local settings = RARELOAD.settings
    local debugEnabled = settings.debugEnabled
    local steamID = ply:SteamID()
    local savedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][steamID]

    RARELOAD.Debug.LogSpawnInfo(ply)
    RARELOAD.Debug.LogInventory(ply)

    --------------------------------------------------------------------------------------------------------------------
    ---------------------------------------------------[Cache system (Not tested)]--------------------------------------
    --------------------------------------------------------------------------------------------------------------------

    if not savedInfo then return end

    ply.lastSpawnPosition = savedInfo.pos
    ply.hasMovedAfterSpawn = false

    hook.Add("PlayerTick", "RARELOAD_CheckMovement_" .. ply:EntIndex(), function(ply, mv)
        if not IsValid(ply) or not ply.lastSpawnPosition then return end

        local moved = (ply:GetPos() - ply.lastSpawnPosition):LengthSqr() > 4
        if moved and not ply.hasMovedAfterSpawn then
            SavePositionToCache(ply.lastSpawnPosition)
            ply.hasMovedAfterSpawn = true
            hook.Remove("PlayerTick", "RARELOAD_CheckMovement_" .. ply:EntIndex())
        end
    end)

    --------------------------------------------------------------------------------------------------------------------
    ---------------------------------------------------[end]------------------------------------------------------------
    --------------------------------------------------------------------------------------------------------------------

    if not settings.addonEnabled then
        for _, weapon in ipairs({
            "weapon_crowbar", "weapon_physgun", "weapon_physcannon", "weapon_pistol", "weapon_357",
            "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg",
            "gmod_tool", "gmod_camera", "gmod_toolgun"
        }) do
            ply:Give(weapon)
        end

        if debugEnabled then print("[RARELOAD DEBUG] Addon disabled, default weapons given.") end
        return
    end

    if settings.nocustomrespawnatdeath and ply.wasKilled then
        ply.wasKilled = false
        if debugEnabled then print("[RARELOAD DEBUG] Player was killed, resetting flag.") end
        return
    end

    local savedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][steamID]
    if not savedInfo then
        if debugEnabled then print("[RARELOAD DEBUG] No saved player info found.") end
        return
    end

    -- **Handle Spawn Position & Move Type**
    local moveType = tonumber(savedInfo.moveType) or MOVETYPE_WALK
    if not settings.spawnModeEnabled then
        local wasFlying = moveType == MOVETYPE_NOCLIP or moveType == MOVETYPE_FLY or moveType == MOVETYPE_FLYGRAVITY
        local wasSwimming = moveType == MOVETYPE_WALK or moveType == MOVETYPE_NONE

        if wasFlying or wasSwimming then
            local traceResult = TraceLine(savedInfo.pos, savedInfo.pos - Vector(0, 0, 10000), ply, MASK_SOLID_BRUSHONLY)
            if traceResult.Hit then
                local groundPos = traceResult.HitPos
                local waterTrace = TraceLine(groundPos, groundPos - Vector(0, 0, 100), ply, MASK_WATER)

                if waterTrace.Hit then
                    local foundPos = FindWalkableGround(groundPos, ply)
                    if foundPos then
                        ply:SetPos(foundPos)
                        ply:SetMoveType(MOVETYPE_NONE)
                        if debugEnabled then print("[RARELOAD DEBUG] Spawned on walkable ground.") end
                    end
                    return
                end

                ply:SetPos(groundPos)
                ply:SetMoveType(MOVETYPE_NONE)
            else
                if debugEnabled then print("[RARELOAD DEBUG] No ground found. Custom spawn prevented.") end
                return
            end
        else
            SetPlayerPositionAndEyeAngles(ply, savedInfo)
        end
    else
        timer.Simple(0, function() ply:SetMoveType(moveType) end)
        SetPlayerPositionAndEyeAngles(ply, savedInfo)
        if debugEnabled then print("[RARELOAD DEBUG] Move type set to: " .. tostring(moveType)) end
    end

    -- **Restore Inventory**
    if RARELOAD.settings.retainInventory and savedInfo.inventory then
        ply:StripWeapons()

        local debugMessages = {
            adminOnly = {},
            notRegistered = {},
            givenWeapons = {}
        }
        local debugFlags = {
            adminOnly = false,
            notRegistered = false,
            givenWeapons = false
        }

        for _, weaponClass in ipairs(savedInfo.inventory) do
            local weaponInfo = weapons.Get(weaponClass)
            local canGiveWeapon = weaponInfo and (weaponInfo.Spawnable or weaponInfo.AdminOnly)

            if not canGiveWeapon then
                if RARELOAD.settings.debugEnabled then
                    if weaponInfo then
                        debugFlags.adminOnly = true
                        table.insert(debugMessages.adminOnly,
                            "Weapon " .. weaponClass .. " is not spawnable and not admin-only.")
                    else
                        debugFlags.notRegistered = true
                        table.insert(debugMessages.notRegistered, "Weapon " .. weaponClass .. " is not registered.")
                    end
                end
            else
                ply:Give(weaponClass)
                if ply:HasWeapon(weaponClass) then
                    if RARELOAD.settings.debugEnabled then
                        debugFlags.givenWeapons = true
                        table.insert(debugMessages.givenWeapons, "Successfully gave weapon: " .. weaponClass)
                    end
                elseif RARELOAD.settings.debugEnabled then
                    debugFlags.givenWeapons = true
                    table.insert(debugMessages.givenWeapons, "Failed to give weapon: " .. weaponClass)

                    local weaponDetails = {
                        "Weapon Info: " .. tostring(weaponInfo),
                        "Weapon Base: " .. tostring(weaponInfo.Base),
                        "PrintName: " .. tostring(weaponInfo.PrintName),
                        "Spawnable: " .. tostring(weaponInfo.Spawnable),
                        "AdminOnly: " .. tostring(weaponInfo.AdminOnly),
                        "Primary Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.Ammo or "N/A"),
                        "Secondary Ammo: " .. tostring(weaponInfo.Secondary and weaponInfo.Secondary.Ammo or "N/A"),
                        "Clip Size: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.ClipSize or "N/A"),
                        "Default Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.DefaultClip or "N/A"),
                        "Max Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxClip or "N/A"),
                        "Max Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxAmmo or "N/A")
                    }
                    table.Add(debugMessages.givenWeapons, weaponDetails)
                end
            end
        end
        RARELOAD.Debug.LogWeaponMessages(debugMessages, debugFlags)
    end

    -- **Restore Health & Ammo**
    if settings.retainHealthArmor then
        timer.Simple(0.5, function()
            ply:SetHealth(savedInfo.health or ply:GetMaxHealth())
            ply:SetArmor(savedInfo.armor or 0)
        end)
    end

    if settings.retainAmmo and savedInfo.ammo then
        for weaponClass, ammoData in pairs(savedInfo.ammo) do
            local weapon = ply:GetWeapon(weaponClass)
            if IsValid(weapon) then
                local primaryAmmoType = weapon:GetPrimaryAmmoType()
                local secondaryAmmoType = weapon:GetSecondaryAmmoType()
                ply:SetAmmo(ammoData.primary, primaryAmmoType)
                ply:SetAmmo(ammoData.secondary, secondaryAmmoType)
            end
        end
    end

    -- **Restore Vehicles**
    if settings.retainVehicles and savedInfo.vehicles then
        timer.Simple(1, function()
            local vehicleCount = 0
            for _, vehicleData in ipairs(savedInfo.vehicles) do
                local exists = false
                for _, ent in ipairs(ents.FindInSphere(vehicleData.pos, 50)) do
                    if ent:GetClass() == vehicleData.class and ent:GetModel() == vehicleData.model then
                        exists = true
                        break
                    end
                end

                if not exists then
                    local success, vehicle = pcall(function()
                        local veh = ents.Create(vehicleData.class)
                        if not IsValid(veh) then return nil end

                        veh:SetPos(vehicleData.pos)
                        veh:SetAngles(vehicleData.ang)
                        veh:SetModel(vehicleData.model)
                        veh:Spawn()
                        veh:Activate()

                        veh:SetHealth(vehicleData.health or 100)
                        veh:SetSkin(vehicleData.skin or 0)
                        veh:SetColor(vehicleData.color or Color(255, 255, 255, 255))

                        if vehicleData.bodygroups then
                            for id, value in pairs(vehicleData.bodygroups) do
                                ---@diagnostic disable-next-line: param-type-mismatch
                                veh:SetBodygroup(tonumber(id), value)
                            end
                        end

                        local phys = veh:GetPhysicsObject()
                        if IsValid(phys) and vehicleData.frozen then
                            phys:EnableMotion(false)
                        end

                        ---@diagnostic disable-next-line: undefined-field
                        if vehicleData.vehicleParams and veh.SetVehicleParams then
                            ---@diagnostic disable-next-line: undefined-field
                            veh:SetVehicleParams(vehicleData.vehicleParams)
                        end

                        ---@diagnostic disable-next-line: inject-field
                        veh.SpawnedByRareload = true

                        if vehicleData.owner then
                            for _, p in ipairs(player.GetAll()) do
                                if p:SteamID() == vehicleData.owner then
                                    ---@diagnostic disable-next-line: undefined-field
                                    if veh.CPPISetOwner then
                                        ---@diagnostic disable-next-line: undefined-field
                                        veh:CPPISetOwner(p)
                                    end
                                    break
                                end
                            end
                        end

                        return veh
                    end)

                    if success and IsValid(vehicle) then
                        vehicleCount = vehicleCount + 1
                    elseif debugEnabled then
                        print("[RARELOAD DEBUG] Failed to create vehicle: " .. vehicleData.class)
                    end
                end
            end

            if debugEnabled and vehicleCount > 0 then
                print("[RARELOAD DEBUG] Restored " .. vehicleCount .. " vehicles")
            end
        end)
    end

    -- **Restore Vehicle State**
    if settings.retainVehicleState and savedInfo.vehicleState then
        local vehicleData = savedInfo.vehicleState

        timer.Simple(1.5, function()
            if not IsValid(ply) then return end

            for _, ent in ipairs(ents.FindInSphere(vehicleData.pos, 50)) do
                if ent:GetClass() == vehicleData.class then
                    timer.Simple(0.2, function()
                        if IsValid(ply) and IsValid(ent) then
                            ply:EnterVehicle(ent)
                        end
                    end)
                    break
                end
            end
        end)
    end

    -- **Restore Entities**
    if settings.retainMapEntities and savedInfo.entities then
        timer.Simple(1, function()
            for _, entData in ipairs(savedInfo.entities) do
                local exists = false
                for _, ent in ipairs(ents.FindInSphere(util.StringToType(entData.pos, "Vector"), 10)) do
                    if ent:GetClass() == entData.class and ent:GetModel() == entData.model then
                        exists = true
                        break
                    end
                end

                if not exists then
                    local success, newEnt = pcall(function()
                        local ent = ents.Create(entData.class)
                        if not IsValid(ent) then return nil end

                        ent:SetPos(util.StringToType(entData.pos, "Vector"))
                        ent:SetAngles(util.StringToType(entData.ang, "Angle"))
                        ent:SetModel(entData.model)
                        ent:Spawn()
                        ent:SetHealth(entData.health)
                        ---@diagnostic disable-next-line: inject-field
                        ent.SpawnedByRareload = true

                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) and entData.frozen then
                            phys:EnableMotion(false)
                        end

                        return ent
                    end)

                    if not success or not IsValid(newEnt) then
                        if debugEnabled then
                            print("[RARELOAD DEBUG] Failed to create entity: " ..
                                entData.class .. " - " .. tostring(newEnt))
                        end
                    end
                end
            end
        end)
    end

    -- **Restore NPCs**
    if settings.retainMapNPCs and savedInfo.npcs and #savedInfo.npcs > 0 then
        local npcsToCreate = table.Copy(savedInfo.npcs)
        local batchSize = settings.npcBatchSize or 5
        local interval = settings.npcSpawnInterval or 0.2

        local function ProcessNPCBatch()
            local count = 0
            local startTime = SysTime()

            while #npcsToCreate > 0 and count < batchSize and (SysTime() - startTime) < 0.05 do
                local npcData = table.remove(npcsToCreate, 1)
                count = count + 1

                local exists = false
                for _, ent in ipairs(ents.FindInSphere(npcData.pos, 10)) do
                    if ent:GetClass() == npcData.class and ent:GetModel() == npcData.model then
                        exists = true
                        break
                    end
                end

                if not exists then
                    local success, newNPC = pcall(function()
                        local npc = ents.Create(npcData.class)
                        if not IsValid(npc) then return nil end

                        npc:SetPos(npcData.pos)

                        if util.IsValidModel(npcData.model) then
                            npc:SetModel(npcData.model)
                        elseif debugEnabled then
                            print("[RARELOAD DEBUG] Invalid model for NPC: " .. npcData.model)
                        end

                        npc:SetAngles(npcData.ang)
                        npc:Spawn()

                        npc:SetHealth(npcData.health or npc:GetMaxHealth())

                        if npcData.relations then
                            for targetID, disposition in pairs(npcData.relations) do
                                local target = Entity(targetID)
                                if IsValid(target) then
                                    ---@diagnostic disable-next-line: undefined-field
                                    npc:AddEntityRelationship(target, disposition, 99)
                                end
                            end
                        end

                        if npcData.weapons then
                            for _, weapon in ipairs(npcData.weapons) do
                                ---@diagnostic disable-next-line: undefined-field
                                npc:Give(weapon)
                            end
                        else
                            if debugEnabled then
                                print("[RARELOAD DEBUG] No weapons found for NPC: " .. npcData.class)
                            end
                        end

                        if npcData.schedule then
                            timer.Simple(0.5, function()
                                if IsValid(npc) then
                                    ---@diagnostic disable-next-line: undefined-field
                                    npc:SetSchedule(npcData.schedule)
                                end
                            end)
                        end

                        if npcData.frozen then
                            local phys = npc:GetPhysicsObject()
                            if IsValid(phys) then
                                phys:EnableMotion(false)
                            end
                        end

                        if npcData.target then
                            local target = Entity(npcData.target)
                            if IsValid(target) then
                                ---@diagnostic disable-next-line: undefined-field
                                npc:SetTarget(target)
                            end
                        end

                        return npc
                    end)

                    if not success or not IsValid(newNPC) then
                        if debugEnabled then
                            print("[RARELOAD DEBUG] Failed to create NPC: " .. npcData.class .. " - " .. tostring(newNPC))
                        end
                    end
                end
            end
            if #npcsToCreate > 0 then
                timer.Simple(interval, ProcessNPCBatch)
            elseif debugEnabled then
                print("[RARELOAD DEBUG] NPC restoration complete. " .. count .. " NPCs restored.")
            end
        end
        timer.Simple(settings.initialNPCDelay or 1, ProcessNPCBatch)
    end

    -- **Restore Active Weapon**
    if savedInfo.activeWeapon then
        timer.Simple(0.6, function()
            if IsValid(ply) and ply:HasWeapon(savedInfo.activeWeapon) then
                ply:SelectWeapon(savedInfo.activeWeapon)
            end
        end)
    end

    -- **Create Player Phantom if debug is enbaled**
    if debugEnabled then CreatePlayerPhantom(ply) end
end)


local function loadSettings()
    local settingsFilePath = "rareload/addon_state.json"
    if file.Exists(settingsFilePath, "DATA") then
        local json = file.Read(settingsFilePath, "DATA")
        RARELOAD.settings = util.JSONToTable(json)
    end
end

loadSettings()

if not RARELOAD.settings then
    return
end

hook.Add("PlayerPostThink", "AutoSavePosition", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or not RARELOAD.settings.autoSaveEnabled then
        return
    end

    local lastSaveTime = lastSavedTimes[ply:UserID()] or 0
    local currentTime = CurTime()

    if currentTime - lastSaveTime < RARELOAD.settings.autoSaveInterval then
        return
    end

    local currentPos = ply:GetPos()
    local currentEyeAngles = ply:EyeAngles()
    local currentActiveWeapon = ply:GetActiveWeapon()
    local currentHealth = ply:Health()
    local currentArmor = ply:Armor()

    local movedEnough = ply.lastSavedPosition and
        currentPos:DistToSqr(ply.lastSavedPosition) > (RARELOAD.settings.maxDistance * RARELOAD.settings.maxDistance)

    local anglesChanged = ply.lastSavedEyeAngles and (
        math.abs(currentEyeAngles.p - ply.lastSavedEyeAngles.p) > RARELOAD.settings.angleTolerance or
        math.abs(currentEyeAngles.y - ply.lastSavedEyeAngles.y) > RARELOAD.settings.angleTolerance or
        math.abs(currentEyeAngles.r - ply.lastSavedEyeAngles.r) > RARELOAD.settings.angleTolerance
    )

    local weaponChanged = RARELOAD.settings.retainInventory and ply.lastSavedActiveWeapon and
        IsValid(currentActiveWeapon) and
        currentActiveWeapon ~= ply.lastSavedActiveWeapon

    local healthChanged = RARELOAD.settings.retainHealthArmor and ply.lastSavedHealth and IsValid(currentHealth) and
        currentHealth ~= ply.lastSavedHealth

    local armorChanged = RARELOAD.settings.retainHealthArmor and ply.lastSavedArmor and IsValid(currentArmor) and
        currentArmor ~= ply.lastSavedArmor

    if (not ply.lastSavedPosition or movedEnough or anglesChanged or weaponChanged or healthChanged or armorChanged) then
        if ply:IsOnGround() and not ply:InVehicle() and not ply:KeyDown(IN_ATTACK) and not ply:KeyDown(IN_ATTACK2) then
            Save_position(ply)
            lastSavedTimes[ply:UserID()] = currentTime
            ply.lastSavedPosition = currentPos
            ply.lastSavedEyeAngles = currentEyeAngles
            ply.lastSavedActiveWeapon = currentActiveWeapon
            ply.lastSavedHealth = currentHealth
            ply.lastSavedArmor = currentArmor
        end
    end
end)

net.Receive("RareloadTeleportTo", function(len, ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:IsAdmin() then return end

    local pos = net.ReadVector()

    if not pos or pos:IsZero() then return end

    local trace = {}
    trace.start = pos + Vector(0, 0, 50)
    trace.endpos = pos - Vector(0, 0, 50)
    trace.filter = ply
    local tr = util.TraceLine(trace)

    local safePos = tr.HitPos + Vector(0, 0, 10)

    if ply:InVehicle() then
        ply:ExitVehicle()
    end

    ply:SetPos(safePos)
    ply:SetEyeAngles(Angle(0, ply:EyeAngles().yaw, 0))
    ply:SetVelocity(Vector(0, 0, 0))

    ply:ChatPrint("Téléporté à la position: " .. tostring(safePos))
end)

net.Receive("RareloadReloadData", function(len, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local filePath = "rareload/player_positions_" .. MapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            local status, result = pcall(util.JSONToTable, data)
            if status then
                RARELOAD.playerPositions = result
                if RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Data refreshed because npc saved data was deleted")
                end
            else
                if RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Error refreshing data : " .. result)
                end
            end
        end
    end
end)
