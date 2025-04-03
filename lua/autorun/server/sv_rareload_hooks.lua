LoadAddonState()

util.AddNetworkString("CreatePlayerPhantom")
util.AddNetworkString("RemovePlayerPhantom")
util.AddNetworkString("SyncData")
util.AddNetworkString("SyncPlayerPositions")
util.AddNetworkString("RareloadTeleportTo")
util.AddNetworkString("RareloadReloadData")
util.AddNetworkString("RareloadSyncAutoSaveTime")


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
    DebugEnabled = settings.debugEnabled
    local steamID = ply:SteamID()
    SavedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][steamID]

    RARELOAD.Debug.LogSpawnInfo(ply)
    RARELOAD.Debug.LogInventory(ply)

    --------------------------------------------------------------------------------------------------------------------
    ---------------------------------------------------[Cache system (broken)]--------------------------------------
    --------------------------------------------------------------------------------------------------------------------

    if not SavedInfo then return end

    ply.lastSpawnPosition = SavedInfo.pos
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

        if DebugEnabled then print("[RARELOAD DEBUG] Addon disabled, default weapons given.") end
        return
    end

    if settings.nocustomrespawnatdeath and ply.wasKilled then
        ply.wasKilled = false
        if DebugEnabled then print("[RARELOAD DEBUG] Player was killed, resetting flag.") end
        return
    end

    SavedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][steamID]
    if not SavedInfo then
        if DebugEnabled then print("[RARELOAD DEBUG] No saved player info found.") end
        return
    end

    -- **Handle Spawn Position & Move Type**
    local moveType = tonumber(SavedInfo.moveType) or MOVETYPE_WALK
    if not settings.spawnModeEnabled then
        local wasFlying = moveType == MOVETYPE_NOCLIP or moveType == MOVETYPE_FLY or moveType == MOVETYPE_FLYGRAVITY
        local wasSwimming = moveType == MOVETYPE_WALK or moveType == MOVETYPE_NONE

        if wasFlying or wasSwimming then
            local traceResult = TraceLine(SavedInfo.pos, SavedInfo.pos - Vector(0, 0, 10000), ply, MASK_SOLID_BRUSHONLY)
            if traceResult.Hit then
                local groundPos = traceResult.HitPos
                local waterTrace = TraceLine(groundPos, groundPos - Vector(0, 0, 100), ply, MASK_WATER)

                if waterTrace.Hit then
                    local foundPos = FindWalkableGround(groundPos, ply)
                    if foundPos then
                        ply:SetPos(foundPos)
                        ply:SetMoveType(MOVETYPE_NONE)
                        if DebugEnabled then print("[RARELOAD DEBUG] Spawned on walkable ground.") end
                    end
                    return
                end

                ply:SetPos(groundPos)
                ply:SetMoveType(MOVETYPE_NONE)
            else
                if DebugEnabled then print("[RARELOAD DEBUG] No ground found. Custom spawn prevented.") end
                return
            end
        else
            SetPlayerPositionAndEyeAngles(ply, SavedInfo)
        end
    else
        timer.Simple(0, function() ply:SetMoveType(moveType) end)
        SetPlayerPositionAndEyeAngles(ply, SavedInfo)
        if DebugEnabled then print("[RARELOAD DEBUG] Move type set to: " .. tostring(moveType)) end
    end

    -- **Restore Inventory**
    if RARELOAD.settings.retainInventory and SavedInfo.inventory then
        RARELOAD.RestoreInventory(ply)
    end

    -- **Restore Health & Ammo**
    if settings.retainHealthArmor then
        timer.Simple(0.5, function()
            ply:SetHealth(SavedInfo.health or ply:GetMaxHealth())
            ply:SetArmor(SavedInfo.armor or 0)
        end)
    end

    if settings.retainAmmo and SavedInfo.ammo then
        for weaponClass, ammoData in pairs(SavedInfo.ammo) do
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
    if settings.retainVehicles and SavedInfo.vehicles then
        RARELOAD.RestoreVehicles()
    end

    -- **Restore Vehicle State**
    if settings.retainVehicleState and SavedInfo.vehicleState then
        local vehicleData = SavedInfo.vehicleState

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
    if settings.retainMapEntities and SavedInfo.entities then
        RARELOAD.RestoreEntities()
    end

    -- **Restore NPCs**
    if settings.retainMapNPCs and SavedInfo.npcs and #SavedInfo.npcs > 0 then
        RARELOAD.RestoreNPCs()
    end

    -- **Restore Active Weapon**
    if SavedInfo.activeWeapon then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Attempting to restore active weapon: " .. tostring(SavedInfo.activeWeapon))
        end

        timer.Simple(0.2, function()
            if not IsValid(ply) then
                if RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Player invalid before weapon selection")
                end
                return
            end

            local availableWeapons = {}
            for _, weapon in ipairs(ply:GetWeapons()) do
                if IsValid(weapon) then
                    table.insert(availableWeapons, weapon:GetClass())
                end
            end

            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD DEBUG] Player weapons available: " .. table.concat(availableWeapons, ", "))
            end
        end)

        -- First attempt at 0.6 seconds
        timer.Simple(0.6, function()
            if IsValid(ply) then
                if ply:HasWeapon(SavedInfo.activeWeapon) then
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Selecting weapon (0.6s): " .. SavedInfo.activeWeapon)
                    end
                    ply:SelectWeapon(SavedInfo.activeWeapon)
                else
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Player doesn't have weapon (0.6s): " .. SavedInfo.activeWeapon)
                    end
                end
            end
        end)

        -- Second attempt at 1.2 seconds if needed
        timer.Simple(1.2, function()
            if IsValid(ply) and ply:GetActiveWeapon() and ply:GetActiveWeapon():GetClass() ~= SavedInfo.activeWeapon then
                if ply:HasWeapon(SavedInfo.activeWeapon) then
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Second attempt selecting weapon (1.2s): " .. SavedInfo.activeWeapon)
                    end
                    ply:SelectWeapon(SavedInfo.activeWeapon)

                    -- Force weapon selection via input
                    timer.Simple(0.1, function()
                        if IsValid(ply) and ply:HasWeapon(SavedInfo.activeWeapon) then
                            ply:ConCommand("use " .. SavedInfo.activeWeapon)
                        end
                    end)
                else
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Weapon still not available (1.2s): " .. SavedInfo.activeWeapon)
                    end
                end
            end
        end)

        -- Final check
        timer.Simple(1.5, function()
            if RARELOAD.settings.debugEnabled and IsValid(ply) then
                local currentWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "none"
                print("[RARELOAD DEBUG] Final weapon state - Current: " .. currentWeapon ..
                    ", Expected: " .. SavedInfo.activeWeapon ..
                    ", Success: " .. tostring(currentWeapon == SavedInfo.activeWeapon))
            end
        end)
    end

    -- **Create Player Phantom if debug is enbaled**
    if DebugEnabled then
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(ply:GetPos())
        net.WriteAngle(ply:GetAngles())
        net.Broadcast()
    end
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


local DEFAULT_CONFIG = {
    autoSaveInterval = 30,
    maxDistance = 100,
    angleTolerance = 20
}

local function ShouldSavePosition(ply, currentPos, currentEyeAngles, currentActiveWeapon, currentHealth, currentArmor)
    local settings = RARELOAD.settings

    if not ply.lastSavedPosition then
        return true
    end

    local maxDist = settings.maxDistance or DEFAULT_CONFIG.maxDistance
    local movedEnough = currentPos:DistToSqr(ply.lastSavedPosition) > (maxDist * maxDist)
    if movedEnough then
        return true
    end

    if ply.lastSavedEyeAngles then
        local tolerance = settings.angleTolerance or DEFAULT_CONFIG.angleTolerance
        local anglesChanged =
            math.abs(currentEyeAngles.p - ply.lastSavedEyeAngles.p) > tolerance or
            math.abs(currentEyeAngles.y - ply.lastSavedEyeAngles.y) > tolerance or
            math.abs(currentEyeAngles.r - ply.lastSavedEyeAngles.r) > tolerance
        if anglesChanged then
            return true
        end
    end

    if settings.retainInventory and ply.lastSavedActiveWeapon and
        IsValid(currentActiveWeapon) and currentActiveWeapon ~= ply.lastSavedActiveWeapon then
        return true
    end

    if settings.retainHealthArmor then
        if ply.lastSavedHealth and currentHealth ~= ply.lastSavedHealth then
            return true
        end
        if ply.lastSavedArmor and currentArmor ~= ply.lastSavedArmor then
            return true
        end
    end

    return false
end

local function IsPlayerInStableState(ply)
    if not ply:IsOnGround() or ply:InVehicle() then
        return false
    end

    if ply:KeyDown(IN_ATTACK) or ply:KeyDown(IN_ATTACK2) or
        ply:KeyDown(IN_JUMP) or ply:KeyDown(IN_DUCK) then
        return false
    end

    if ply:GetVelocity():Length() > 150 then
        return false
    end

    return true
end

timer.Create("RareloadSyncAutoSaveTimes", 5, 0, function()
    if not RARELOAD.settings.autoSaveEnabled then return end

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsPlayer() and ply:Alive() then
            net.Start("RareloadSyncAutoSaveTime")
            net.WriteFloat(lastSavedTimes[ply:UserID()] or 0)
            net.Send(ply)
        end
    end
end)

hook.Add("PlayerPostThink", "AutoSavePosition", function(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then
        return
    end

    local settings = RARELOAD.settings
    if not settings or not settings.autoSaveEnabled then
        return
    end

    local interval = settings.autoSaveInterval or DEFAULT_CONFIG.autoSaveInterval
    local lastSaveTime = lastSavedTimes[ply:UserID()] or 0
    local currentTime = CurTime()

    if currentTime - lastSaveTime < interval then
        return
    end

    local currentPos = ply:GetPos()
    local currentEyeAngles = ply:EyeAngles()
    local currentActiveWeapon = ply:GetActiveWeapon()
    local currentHealth = ply:Health()
    local currentArmor = ply:Armor()

    if ShouldSavePosition(ply, currentPos, currentEyeAngles, currentActiveWeapon, currentHealth, currentArmor) then
        if IsPlayerInStableState(ply) then
            Save_position(ply)

            lastSavedTimes[ply:UserID()] = currentTime
            ply.lastSavedPosition = currentPos
            ply.lastSavedEyeAngles = currentEyeAngles
            ply.lastSavedActiveWeapon = currentActiveWeapon
            ply.lastSavedHealth = currentHealth
            ply.lastSavedArmor = currentArmor

            net.Start("RareloadSyncAutoSaveTime")
            net.WriteFloat(lastSavedTimes[ply:UserID()])
            net.Send(ply)

            if settings.notifyOnSave then
                ply:PrintMessage(HUD_PRINTTALK, "[Rareload] Position sauvegardée")
            end

            if settings.debugEnabled then
                print("[RARELOAD DEBUG] Position sauvegardée pour " .. ply:Nick())
            end
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
