util.AddNetworkString("CreatePlayerPhantom")
util.AddNetworkString("RemovePlayerPhantom")
util.AddNetworkString("SyncData")
util.AddNetworkString("SyncPlayerPositions")

RARELOAD.Phanthom = RARELOAD.Phanthom or {}

local lastSavedTimes = {}

hook.Add("PlayerInitialSpawn", "SyncDataOnJoin", function(ply)
    SyncData(ply)
end)

hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    LoadAddonState()

    local settings = RARELOAD.settings
    if settings.debugEnabled then
        local debugMessages = {
            addonEnabled = "Respawn at Reload addon",
            spawnModeEnabled = "Spawn with saved move type",
            autoSaveEnabled = "Auto-save position",
            retainInventory = "Retain inventory",
            nocustomrespawnatdeath = "No Custom Respawn at Death",
            debugEnabled = "Debug mode"
        }

        for name, message in pairs(debugMessages) do
            local status = settings[name] and "enabled" or "disabled"
            print(string.format("[RARELOAD DEBUG] %s is %s.", message, status))
        end
    end

    if not settings.addonEnabled then return end

    EnsureFolderExists()

    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"
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

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType(),
    }

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Player " ..
            ply:SteamID() ..
            " disconnected. Saved position: " .. tostring(RARELOAD.playerPositions[mapName][ply:SteamID()].pos))
        print("[RARELOAD DEBUG] Player " ..
            ply:SteamID() ..
            " disconnected. Saved move type: " .. tostring(RARELOAD.playerPositions[mapName][ply:SteamID()].moveType))
    end
end)

hook.Add("PlayerDeath", "SetWasKilledFlag", function(ply)
    ply.wasKilled = true
end)

hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    RARELOAD.Debug.LogSpawnInfo(ply)
    RARELOAD.Debug.LogInventory(ply)

    if not RARELOAD.settings.addonEnabled then
        local defaultWeapons = {
            "weapon_crowbar", "weapon_physgun", "weapon_physcannon", "weapon_pistol", "weapon_357",
            "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg",
            "gmod_tool", "gmod_camera", "gmod_toolgun"
        }

        for _, weaponClass in ipairs(defaultWeapons) do
            ply:Give(weaponClass)
        end

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Addon disabled, gave default weapons")
        end
        return
    end

    if RARELOAD.settings.nocustomrespawnatdeath and ply.wasKilled then
        ply.wasKilled = false
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Player was killed, resetting wasKilled flag")
        end
        return
    end

    local mapName = game.GetMap()
    SavedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()]

    if not SavedInfo then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] No saved player info found")
        end
        return
    end

    MoveTypes = {
        none = MOVETYPE_NONE,             -- 0 (no movement)
        isometric = MOVETYPE_ISOMETRIC,   -- 1 (deprecated)
        walk = MOVETYPE_WALK,             -- 2 (normal walking)
        step = MOVETYPE_STEP,             -- 3 (for players)
        fly = MOVETYPE_FLY,               -- 4 (when flying)
        flyGravity = MOVETYPE_FLYGRAVITY, -- 5 (when flying with gravity)
        vphysics = MOVETYPE_VPHYSICS,     -- 6 (prop movement)
        push = MOVETYPE_PUSH,             -- 7 (player is pushed by other entities)
        noclip = MOVETYPE_NOCLIP,         -- 8 (player is in noclip mode)
        ladder = MOVETYPE_LADDER,         -- 9 (player is on a ladder)
        observer = MOVETYPE_OBSERVER,     -- 10 (player is in observer mode)
        custom = MOVETYPE_CUSTOM,         -- 11 (custom movement)
    }

    RARELOAD.Debug.LogAfterRespawnInfo()

    if not RARELOAD.settings.spawnModeEnabled then
        local function handleCustomSpawn()
            local traceResult = TraceLine(SavedInfo.pos, SavedInfo.pos - Vector(0, 0, 10000), ply, MASK_SOLID_BRUSHONLY)

            if not traceResult.Hit or not traceResult.HitPos then
                print("[RARELOAD DEBUG] No walkable ground found. Custom spawn prevented.")
                return
            end

            local waterTrace = TraceLine(traceResult.HitPos, traceResult.HitPos - Vector(0, 0, 100), ply, MASK_WATER)

            if waterTrace.Hit then
                local foundPos = FindWalkableGround(traceResult.HitPos, ply)

                if not foundPos then
                    print("[RARELOAD DEBUG] No walkable ground found. Custom spawn prevented.")
                    return
                end

                ply:SetPos(foundPos)
                ply:SetMoveType(MoveTypes.none)
                print("[RARELOAD DEBUG] Found walkable ground for player spawn.")
                return
            end

            ply:SetPos(traceResult.HitPos)
            ply:SetMoveType(MoveTypes.none)
        end

        if SavedInfo.moveType == MoveTypes.noclip or SavedInfo.moveType == MoveTypes.fly or SavedInfo.moveType == MoveTypes.flyGravity or SavedInfo.moveType == MoveTypes.ladder or SavedInfo.moveType == MoveTypes.walk or SavedInfo.moveType == MoveTypes.none then
            handleCustomSpawn()
        else
            SetPlayerPositionAndEyeAngles(ply, SavedInfo)
        end
    else
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Setting move type to: " .. tostring(tonumber(SavedInfo.moveType)))
        end
        timer.Simple(0, function() ply:SetMoveType(tonumber(SavedInfo.moveType)) end)
        SetPlayerPositionAndEyeAngles(ply, SavedInfo)
    end

    if RARELOAD.settings.retainInventory and SavedInfo.inventory then
        ply:StripWeapons()

        local debugMessages = {
            adminOnly = {},
            notRegistered = {},
            givenWeapons = {}
        }
        local debugInfo = {
            adminOnly = false,
            notRegistered = false,
            givenWeapons = false
        }

        for _, weaponClass in ipairs(SavedInfo.inventory) do
            local canGiveWeapon = true
            local weaponInfo = weapons.Get(weaponClass)

            if weaponInfo then
                if not weaponInfo.Spawnable and not weaponInfo.AdminOnly then
                    canGiveWeapon = false
                    if RARELOAD.settings.debugEnabled then
                        debugInfo.adminOnly = true
                        table.insert(debugMessages.adminOnly,
                            "Weapon " .. weaponClass .. " is not spawnable and not admin-only.")
                    end
                end
            else
                canGiveWeapon = false
                if RARELOAD.settings.debugEnabled then
                    debugInfo.notRegistered = true
                    table.insert(debugMessages.notRegistered, "Weapon " .. weaponClass .. " is not registered.")
                end
            end

            if canGiveWeapon then
                ply:Give(weaponClass)
                if not ply:HasWeapon(weaponClass) and RARELOAD.settings.debugEnabled then
                    table.insert(debugMessages.givenWeapons, "Failed to give weapon: " .. weaponClass)
                    if weaponInfo then
                        table.insert(debugMessages.givenWeapons,
                            "Weapon " .. weaponClass .. " is registered but failed to give.")
                        table.insert(debugMessages.givenWeapons, "Weapon Info: " .. tostring(weaponInfo))
                        table.insert(debugMessages.givenWeapons, "Weapon Base: " .. tostring(weaponInfo.Base))
                        table.insert(debugMessages.givenWeapons, "Weapon PrintName: " .. tostring(weaponInfo.PrintName))
                        table.insert(debugMessages.givenWeapons, "Weapon Spawnable: " .. tostring(weaponInfo.Spawnable))
                        table.insert(debugMessages.givenWeapons, "Weapon AdminOnly: " .. tostring(weaponInfo.AdminOnly))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Primary Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.Ammo))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Secondary Ammo: " .. tostring(weaponInfo.Secondary and weaponInfo.Secondary.Ammo))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Clip Size: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.ClipSize))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Default Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.DefaultClip))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Max Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxClip))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Max Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxAmmo))
                    end
                else
                    if RARELOAD.settings.debugEnabled then
                        debugInfo.givenWeapons = true
                        table.insert(debugMessages.givenWeapons, "Successfully gave weapon: " .. weaponClass)
                    end
                end
            end
        end

        RARELOAD.Debug.LogWeaponMessages(debugMessages, debugInfo)
    end

    ---[[ Beta [NOT TESTED] ]]---
    if RARELOAD.settings.retainHealthArmor then
        ply:SetHealth(SavedInfo.health or ply:GetMaxHealth())
        ply:SetArmor(SavedInfo.armor or 0)
    end

    if RARELOAD.settings.retainAmmo and SavedInfo.ammo then
        for weaponClass, ammoData in pairs(SavedInfo.ammo) do
            ply:SetAmmo(ammoData.primary, weaponClass)
            ply:SetAmmo(ammoData.secondary, weaponClass)
        end
    end

    if RARELOAD.settings.retainVehicleState and SavedInfo.vehicle then
        local existingVehicles = ents.FindInSphere(SavedInfo.vehicle.pos, 10)
        local vehicleExists = false

        for _, ent in ipairs(existingVehicles) do
            if ent:GetClass() == SavedInfo.vehicle.class then
                vehicleExists = true
                ply:EnterVehicle(ent)
                break
            end
        end

        if not vehicleExists then
            local vehicle = ents.Create(SavedInfo.vehicle.class)
            vehicle:SetPos(SavedInfo.vehicle.pos)
            vehicle:SetAngles(SavedInfo.vehicle.ang)
            vehicle:Spawn()
            vehicle:SetHealth(SavedInfo.vehicle.health)
            ply:EnterVehicle(vehicle)
        end
    end

    if RARELOAD.settings.retainMapEntities and SavedInfo.entities then
        timer.Simple(1, function()
            for _, entData in ipairs(SavedInfo.entities) do
                local existingEntities = ents.FindInSphere(entData.pos, 1)
                local entityExists = false

                for _, ent in ipairs(existingEntities) do
                    if ent:GetClass() == entData.class and ent:IsVehicle() then
                        entityExists = true
                        break
                    end
                end

                if not entityExists then
                    local ent = ents.Create(entData.class)
                    ent:SetPos(entData.pos)
                    ent:SetModel(entData.model)
                    ent:SetAngles(entData.ang)
                    ent:Spawn()
                    ent:SetHealth(entData.health)
                    if entData.frozen then
                        ent:GetPhysicsObject():EnableMotion(false)
                    end
                end
            end
        end)
    end

    if RARELOAD.settings.retainMapNPCs and SavedInfo.npcs then
        for _, npcData in ipairs(SavedInfo.npcs) do
            local existingNPCs = ents.FindInSphere(npcData.pos, 1)
            local npcExists = false

            for _, npc in ipairs(existingNPCs) do
                if npc:GetClass() == npcData.class then
                    npcExists = true
                    break
                end
            end

            if not npcExists then
                local npc = ents.Create(npcData.class)
                npc:SetPos(npcData.pos)
                npc:SetModel(npcData.model)
                npc:SetAngles(npcData.ang)
                npc:Spawn()
                npc:SetHealth(npcData.health)
            end
        end
    end

    --[[ End Of Beta [NOT TESTED] ]] --

    if RARELOAD.settings.debugEnabled then
        CreatePlayerPhantom(ply)
    end
end)

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
