LoadAddonState()

util.AddNetworkString("CreatePlayerPhantom")
util.AddNetworkString("RemovePlayerPhantom")
util.AddNetworkString("SyncData")
util.AddNetworkString("SyncPlayerPositions")

RARELOAD.Phanthom = RARELOAD.Phanthom or {}

RARELOAD.Debug = RARELOAD.Debug or {}
MapName = game.GetMap()



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
            debugEnabled = "Debug mode",
            retainAmmo = "Retain ammo",
            retainHealthArmor = "Retain health and armor",
            retainVehicleState = "Retain vehicle state",
            retainMapEntities = "Retain map entities",
            retainMapNPCs = "Retain map NPCs"
        }

        for name, message in pairs(debugMessages) do
            local status = settings[name] and "enabled" or "disabled"
            print(string.format("[RARELOAD DEBUG] %s is %s.", message, status))
        end
    end

    if not settings.addonEnabled then return end

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
        ply:SetHealth(savedInfo.health or ply:GetMaxHealth())
        ply:SetArmor(savedInfo.armor or 0)
    end

    if settings.retainAmmo and savedInfo.ammo then
        for weaponClass, ammoData in pairs(savedInfo.ammo) do
            ply:SetAmmo(ammoData.primary, weaponClass)
            ply:SetAmmo(ammoData.secondary, weaponClass)
        end
    end

    -- **Restore Vehicle State**
    if settings.retainVehicleState and savedInfo.vehicle then
        local vehicleData = savedInfo.vehicle
        local foundVehicle = false

        for _, ent in ipairs(ents.FindInSphere(vehicleData.pos, 10)) do
            if ent:GetClass() == vehicleData.class then
                ply:EnterVehicle(ent)
                foundVehicle = true
                break
            end
        end

        if not foundVehicle then
            local newVehicle = ents.Create(vehicleData.class)
            if IsValid(newVehicle) then
                newVehicle:SetPos(vehicleData.pos)
                newVehicle:SetAngles(vehicleData.ang)
                newVehicle:Spawn()
                newVehicle:SetHealth(vehicleData.health)
                ply:EnterVehicle(newVehicle)
            else
                if debugEnabled then print("[RARELOAD DEBUG] Failed to create vehicle: " .. vehicleData.class) end
            end
        end
    end

    -- **Restore Entities**
    if settings.retainMapEntities and savedInfo.entities then
        timer.Simple(1, function()
            for _, entData in ipairs(savedInfo.entities) do
                if not ents.FindByClassAndModel(entData.class, entData.model, entData.pos) then
                    ---@class Entity
                    local newEnt = ents.Create(entData.class)
                    if IsValid(newEnt) then
                        newEnt:SetPos(entData.pos)
                        newEnt:SetAngles(entData.ang)
                        newEnt:Spawn()
                        newEnt:SetHealth(entData.health)
                        newEnt.SpawnedByRareload = true

                        local phys = newEnt:GetPhysicsObject()
                        if IsValid(phys) and entData.frozen then
                            phys:EnableMotion(false)
                        end
                    elseif debugEnabled then
                        print("[RARELOAD DEBUG] Failed to create entity: " .. tostring(entData.class))
                    end
                end
            end
        end)
    end

    -- **Restore NPCs**
    if settings.retainMapNPCs and savedInfo.npcs then
        for _, npcData in ipairs(savedInfo.npcs) do
            if not ents.FindByClassAndModel(npcData.class, npcData.model, npcData.pos) then
                local newNPC = ents.Create(npcData.class)
                if IsValid(newNPC) then
                    newNPC:SetPos(npcData.pos)
                    newNPC:SetModel(npcData.model)
                    newNPC:SetAngles(npcData.ang)
                    newNPC:Spawn()
                    newNPC:SetHealth(npcData.health)

                    if npcData.weapons then
                        for _, weapon in ipairs(npcData.weapons) do
                            ---@diagnostic disable-next-line: undefined-field
                            newNPC:Give(weapon)
                        end
                    end
                elseif debugEnabled then
                    print("[RARELOAD DEBUG] Failed to create NPC: " .. npcData.class)
                end
            end
        end
    end

    -- **Restore Active Weapon**
    if savedInfo.activeWeapon then
        timer.Simple(0.6, function()
            if IsValid(ply) and ply:HasWeapon(savedInfo.activeWeapon) then
                ply:SelectWeapon(savedInfo.activeWeapon)
            end
        end)
    end

    -- **Debugging & Final Sync**
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
