LoadAddonState()

util.AddNetworkString("CreatePlayerPhantom")
util.AddNetworkString("RemovePlayerPhantom")
util.AddNetworkString("SyncData")
util.AddNetworkString("SyncPlayerPositions")
util.AddNetworkString("RareloadTeleportTo")

RARELOAD.Phanthom = RARELOAD.Phanthom or {}

RARELOAD.Debug = RARELOAD.Debug or {}
MapName = game.GetMap()

local lastSavedTimes = {}

hook.Add("PlayerInitialSpawn", "SyncDataOnJoin", function(ply)
    SyncData(ply)
end)

hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    LoadAddonState()

    Settings = RARELOAD.settings

    if not Settings.addonEnabled then return end

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

hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    local settings = RARELOAD.settings
    local debugEnabled = settings.debugEnabled
    local steamID = ply:SteamID()
    local savedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][steamID]

    RARELOAD.Debug.LogSpawnInfo(ply)
    RARELOAD.Debug.LogInventory(ply)

    if not settings.addonEnabled then
        RARELOAD.Inventory.GiveDefaultWeapons(ply, debugEnabled)
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

    RARELOAD.PlayerPosition.HandlePlayerSpawnPosition(ply, savedInfo, settings, debugEnabled)
    RARELOAD.PlayerPosition.HandlePositionCache(ply, savedInfo)
    RARELOAD.Inventory.HandleInventoryRestore(ply, savedInfo, settings)
    RARELOAD.Inventory.HandleHealthAndAmmoRestore(ply, savedInfo, settings)
    RARELOAD.Inventory.HandleActiveWeaponRestore(ply, savedInfo)
    RARELOAD.Vehicles.HandleVehicleRestore(ply, savedInfo, settings, debugEnabled)
    RARELOAD.Vehicles.HandleVehicleStateRestore(ply, savedInfo, settings)
    RARELOAD.Entities.HandleEntitiesRestore(ply, savedInfo, settings, debugEnabled)
    RARELOAD.NPCs.HandleNPCsRestore(ply, savedInfo, settings, debugEnabled)

    timer.Simple(1, function()
        RARELOAD.Debug.Count(ply)
    end)

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
