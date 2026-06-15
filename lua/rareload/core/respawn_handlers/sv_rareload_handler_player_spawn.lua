local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

local function HasSnapshotData(bucket)
    if SnapshotUtils.HasSnapshot(bucket) then
        return true
    end
    return istable(bucket) and #bucket > 0
end

local function ToSpawnVector(pos)
    if pos and pos.x and pos.y and pos.z then
        return Vector(pos.x, pos.y, pos.z)
    end
    return pos
end

local function ApplySpawnTransform(ply, opts)
    if not IsValid(ply) then return end
    opts = opts or {}

    local targetPos = ToSpawnVector(opts.setPos)
    local moveType = opts.moveType or MOVETYPE_WALK

    timer.Simple(0, function()
        if not IsValid(ply) then return end
        ply:SetPos(targetPos)
        ply:SetMoveType(moveType)
    end)

    RARELOAD.SavePositionToCache(opts.cachePos)

    timer.Simple(0.05, function()
        if not IsValid(ply) then return end

        local parsedAngle = RARELOAD.DataUtils.ToAngle(opts.savedAng)
        if parsedAngle then
            ply:SetEyeAngles(parsedAngle)
            if opts.successMessage and opts.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.Write then
                local appendParsedAngle = opts.appendParsedAngle ~= false
                local successLine = opts.successMessage
                if appendParsedAngle then
                    successLine = successLine .. tostring(parsedAngle)
                end
                RARELOAD.Debug.Write("respawn", "INFO", 0, successLine, { entity = ply })
            end
            return
        end

        if opts.warnOnAngleParseFailure and opts.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.Write then
            RARELOAD.Debug.Write("respawn", "WARNING", 0,
                "Could not parse saved angle: " .. tostring(opts.savedAng), { entity = ply })
        end
    end)
end

function RARELOAD.CleanupPlayerOwnedEntities(ply)
    if not IsValid(ply) then return 0 end

    local removed  = 0
    local toRemove = {}

    local function isOwnedByPly(ent)
        if RARELOAD.Ownership and RARELOAD.Ownership.IsOwnedByPlayerSafe then
            if RARELOAD.Ownership.IsOwnedByPlayerSafe(ent, ply) then return true end
        end
        if ent.CPPIGetOwner then
            local ok, owner = pcall(ent.CPPIGetOwner, ent)
            if ok and IsValid(owner) and owner == ply then return true end
        end
        if ent.GetCreator then
            local ok, creator = pcall(ent.GetCreator, ent)
            if ok and IsValid(creator) and creator == ply then return true end
        end
        return false
    end

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or ent:IsPlayer() then continue end

        if not isOwnedByPly(ent) then continue end

        if ent:IsWeapon()
            or ent:GetClass() == "predicted_viewmodel"
            or ent:GetClass() == "viewmodel" then
            if ent.SetNWString then
                pcall(ent.SetNWString, ent, "RareloadID", "")
            end
            ent.RareloadEntityID = nil
            ent.RareloadNPCID    = nil
        else
            toRemove[#toRemove + 1] = ent
        end
    end

    for _, ent in ipairs(toRemove) do
        if IsValid(ent) then
            ent:Remove()
            removed = removed + 1
        end
    end

    return removed
end

function RARELOAD.CleanupSavedEntities(ply)
    if not IsValid(ply) then return 0 end
    local removed  = 0
    local toRemove = {}

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or ent:IsPlayer() then continue end

        if not ent.SavedByRareload then continue end

        if ent:IsWeapon()
            or ent:GetClass() == "predicted_viewmodel"
            or ent:GetClass() == "viewmodel" then
            if ent.SetNWString then
                pcall(ent.SetNWString, ent, "RareloadID", "")
            end
            ent.RareloadEntityID = nil
            ent.RareloadNPCID    = nil
        else
            toRemove[#toRemove + 1] = ent
        end
    end

    for _, ent in ipairs(toRemove) do
        if IsValid(ent) then
            ent:Remove()
            removed = removed + 1
        end
    end

    return removed
end

local function RestoreActiveWeapon(ply, SavedInfo, canRestoreGlobalInventory, canRestoreInventory)
    local function SendWeaponRestoreDebug(message)
        if not RARELOAD.GetPlayerSetting(ply, "debugEnabled") then return end

        local formatted = "[RARELOAD DEBUG] " .. tostring(message)
        if RARELOAD.Debug and RARELOAD.Debug.SendToPlayer then
            RARELOAD.Debug.SendToPlayer(ply, formatted)
        else
            print(formatted)
        end
    end

    local activeWeaponToRestore = nil

    if canRestoreGlobalInventory and RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
        if RARELOAD.globalInventory and RARELOAD.globalInventory[ply:SteamID()] then
            activeWeaponToRestore = RARELOAD.globalInventory[ply:SteamID()].activeWeapon
            SendWeaponRestoreDebug("Using global inventory active weapon: " .. tostring(activeWeaponToRestore))
        end
    elseif canRestoreInventory and SavedInfo.activeWeapon then
        activeWeaponToRestore = SavedInfo.activeWeapon
        SendWeaponRestoreDebug("Using saved position active weapon: " .. tostring(activeWeaponToRestore))
    end

    if not activeWeaponToRestore then return end

    SendWeaponRestoreDebug("Attempting to restore active weapon: " .. tostring(activeWeaponToRestore))
    timer.Simple(0.2, function()
        if not IsValid(ply) then
            SendWeaponRestoreDebug("Player invalid before weapon selection")
            return
        end
        local availableWeapons = {}
        for _, weapon in ipairs(ply:GetWeapons()) do
            if IsValid(weapon) then
                table.insert(availableWeapons, weapon:GetClass())
            end
        end
        SendWeaponRestoreDebug("Player weapons available: " .. table.concat(availableWeapons, ", "))
    end)
    timer.Simple(0.6, function()
        if IsValid(ply) then
            if ply:HasWeapon(activeWeaponToRestore) then
                SendWeaponRestoreDebug("Selecting weapon (0.6s): " .. activeWeaponToRestore)
                ply:SelectWeapon(activeWeaponToRestore)
            else
                SendWeaponRestoreDebug("Player doesn't have weapon (0.6s): " .. activeWeaponToRestore)
            end
        end
    end)
    timer.Simple(1.2, function()
        if IsValid(ply) and ply:GetActiveWeapon() and ply:GetActiveWeapon():GetClass() ~= activeWeaponToRestore then
            if ply:HasWeapon(activeWeaponToRestore) then
                SendWeaponRestoreDebug("Second attempt selecting weapon (1.2s): " .. activeWeaponToRestore)
                ply:SelectWeapon(activeWeaponToRestore)
                timer.Simple(0.1, function()
                    if IsValid(ply) and ply:HasWeapon(activeWeaponToRestore) then
                        ply:ConCommand("use " .. activeWeaponToRestore)
                    end
                end)
            else
                SendWeaponRestoreDebug("Weapon still not available (1.2s): " .. activeWeaponToRestore)
            end
        end
    end)
    timer.Simple(1.5, function()
        if IsValid(ply) then
            local currentWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "none"
            SendWeaponRestoreDebug("Final weapon state - Current: " .. currentWeapon ..
                ", Expected: " .. activeWeaponToRestore ..
                ", Success: " .. tostring(currentWeapon == activeWeaponToRestore))
        end
    end)
end

local function SendSpawnPhantom(ply, SavedInfo)
    if not (RARELOAD.CheckPermission(ply, "VIEW_PHANTOM") and SavedInfo) then return end

    local phantomPos = RARELOAD.DataUtils.ToVector(SavedInfo.pos) or ply:GetPos()
    local phantomAng = RARELOAD.DataUtils.ToAngle(SavedInfo.ang) or ply:GetAngles()
    net.Start("CreatePlayerPhantom")
    net.WriteEntity(ply)
    net.WriteVector(phantomPos)
    net.WriteAngle(phantomAng)
    net.Send(ply)
end

function RARELOAD.HandlePlayerSpawn(ply)
    if not IsValid(ply) then return end

    local function hasPerm(permName)
        if RARELOAD.CheckPermission then
            return RARELOAD.CheckPermission(ply, permName)
        end
        return true
    end

    if RARELOAD.PlayerSettings and RARELOAD.PlayerSettings.Load then
        RARELOAD.PlayerSettings.Load(ply:SteamID())
    end

    if not RARELOAD.GetPlayerSetting(ply, "addonEnabled", true) then return end
    if not hasPerm("LOAD_POSITION") or not hasPerm("RARELOAD_SPAWN") then
        return
    end
    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    local mapName = game.GetMap()
    local steamID = ply:SteamID()
    local hasThisPlayerData = RARELOAD.playerPositions[mapName]
        and RARELOAD.playerPositions[mapName][steamID] ~= nil

    if not hasThisPlayerData and RARELOAD.LoadPlayerPositions then
        RARELOAD.LoadPlayerPositions()
    end

    if not RARELOAD.AntiStuck then
        include("rareload/anti_stuck/sv_anti_stuck_init.lua")
        if RARELOAD.AntiStuck and RARELOAD.AntiStuck.Initialize then
            RARELOAD.AntiStuck.Initialize()
            if RARELOAD.AntiStuck.LoadMethodPriorities then
                RARELOAD.AntiStuck.LoadMethodPriorities(true)
            end
        end
    end

    local Settings = RARELOAD.PlayerSettings and RARELOAD.PlayerSettings.Get(ply) or RARELOAD.settings
    if not Settings then
        print("[RARELOAD] Error: Settings not loaded, cannot handle player spawn.")
        return
    end
    local DebugEnabled = Settings.debugEnabled
    local SteamID = ply:SteamID()
    local MapName = game.GetMap()
    local SavedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][SteamID]
    local playerSpawnMode = RARELOAD.GetPlayerSetting(ply, "spawnModeEnabled", nil)
    if playerSpawnMode == nil and Settings then
        playerSpawnMode = Settings.spawnModeEnabled
    end

    local globalSpawnMode = (RARELOAD.settings and RARELOAD.settings.spawnModeEnabled)
    if globalSpawnMode == nil then
        globalSpawnMode = true
    end

    local antiStuckEnabled = (playerSpawnMode == true) and (globalSpawnMode == true)

    if RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write("respawn", "INFO", 0, "Player spawn started", { entity = ply })
    end
    if not SavedInfo then return end

    if DebugEnabled and SavedInfo.ang and RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write("respawn", "VERBOSE", 0, "Saved angle data: " .. tostring(SavedInfo.ang), { entity = ply })
    end
    if not Settings then return end
    ply.lastSpawnPosition = ToSpawnVector(SavedInfo.pos)
    ply.hasMovedAfterSpawn = false
    local spawnedPly = ply
    local moveHookName = "RARELOAD_CheckMovement_" .. ply:EntIndex()
    hook.Add("PlayerTick", moveHookName, function(tickPly)
        if not IsValid(spawnedPly) then
            hook.Remove("PlayerTick", moveHookName)
            return
        end
        if tickPly ~= spawnedPly or not spawnedPly.lastSpawnPosition then return end
        if not spawnedPly.hasMovedAfterSpawn
            and (spawnedPly:GetPos() - spawnedPly.lastSpawnPosition):LengthSqr() > 4 then
            RARELOAD.SavePositionToCache(spawnedPly.lastSpawnPosition)
            spawnedPly.hasMovedAfterSpawn = true
            hook.Remove("PlayerTick", moveHookName)
        end
    end)

    if RARELOAD.GetPlayerSetting(ply, "cleanupMapAfterDeath", false) and ply.wasKilled then
        local ownedOnly = RARELOAD.GetPlayerSetting(ply, "cleanupOnlyOwnedEntitiesOnDeath", false)
        local savedOnly = RARELOAD.GetPlayerSetting(ply, "cleanupOnlySavedEntitiesOnDeath", false)

        if ownedOnly then
            ply.wasKilled = false

            if RARELOAD.Debug and RARELOAD.Debug.Write then
                RARELOAD.Debug.Write("respawn", "INFO", 0,
                    "Cleanup (owned only): removing player-owned Rareload entities before respawn", { entity = ply })
            elseif DebugEnabled then
                print("[RARELOAD DEBUG] Cleanup (owned only): removing player-owned Rareload entities before respawn.")
            end

            local removed = RARELOAD.CleanupPlayerOwnedEntities(ply)
            ply._rareloadSkipExistingFilter = true

            if DebugEnabled then
                print(string.format("[RARELOAD DEBUG] Removed %d player-owned entities for %s",
                    removed, ply:Nick()))
            end
        elseif savedOnly then
            ply.wasKilled = false

            if RARELOAD.Debug and RARELOAD.Debug.Write then
                RARELOAD.Debug.Write("respawn", "INFO", 0,
                    "Cleanup (saved only): removing Rareload saved entities before respawn", { entity = ply })
            elseif DebugEnabled then
                print("[RARELOAD DEBUG] Cleanup (saved only): removing Rareload saved entities before respawn.")
            end

            local removed = RARELOAD.CleanupSavedEntities(ply)
            ply._rareloadSkipExistingFilter = true

            if DebugEnabled then
                print(string.format("[RARELOAD DEBUG] Removed %d saved entities for %s",
                    removed, ply:Nick()))
            end
        else
            if not RARELOAD._isCleaningUpMap then
                RARELOAD._isCleaningUpMap = true
                ply.wasKilled = false

                if RARELOAD.Debug and RARELOAD.Debug.Write then
                    RARELOAD.Debug.Write("respawn", "INFO", 0, "Cleanup (full map): cleaning up before respawn",
                        { entity = ply })
                elseif DebugEnabled then
                    print("[RARELOAD DEBUG] Cleanup (full map): cleaning up before respawn.")
                end

                local preHookName = "RareloadSaveEntitiesBeforeCleanup"
                local savedPreHook = hook.GetTable()["PreCleanupMap"] and
                    hook.GetTable()["PreCleanupMap"][preHookName]

                if savedPreHook then
                    hook.Remove("PreCleanupMap", preHookName)
                end

                game.CleanUpMap(false, {}, function()
                    if savedPreHook then
                        hook.Add("PreCleanupMap", preHookName, savedPreHook)
                    end

                    timer.Simple(0.1, function()
                        if IsValid(ply) then
                            ply:Spawn()
                        end
                    end)

                    timer.Simple(1, function() RARELOAD._isCleaningUpMap = false end)
                end)

                return
            end
        end
    end

    if RARELOAD.GetPlayerSetting(ply, "nocustomrespawnatdeath", false) and ply.wasKilled then
        ply.wasKilled = false
        if RARELOAD.Debug and RARELOAD.Debug.Write then
            RARELOAD.Debug.Write("respawn", "INFO", 0, "Player was killed, resetting flag", { entity = ply })
        elseif DebugEnabled then
            print("[RARELOAD DEBUG] Player was killed, resetting flag.")
        end
        return
    end
    ply._rareloadSpawnTime = CurTime()
    SavedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][SteamID]
    if not SavedInfo then
        if DebugEnabled then RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] No saved player info found.") end
        return
    end
    local keepPlayerStates = hasPerm("RETAIN_PLAYER_STATES")
        and RARELOAD.GetPlayerSetting(ply, "retainPlayerStates", true)

    local moveType = tonumber(SavedInfo.moveType) or MOVETYPE_WALK
    if moveType == MOVETYPE_NOCLIP and not keepPlayerStates then
        moveType = MOVETYPE_WALK
    end
    local savedPos = ToSpawnVector(SavedInfo.pos)

    if antiStuckEnabled then
        if not RARELOAD.AntiStuck then
            include("rareload/anti_stuck/sv_anti_stuck_init.lua")
            if RARELOAD.AntiStuck.Initialize then
                RARELOAD.AntiStuck.Initialize()
            end
        end
        local isStuck, stuckReason = RARELOAD.AntiStuck.IsPositionStuck(savedPos, ply, true)

        if DebugEnabled and RARELOAD.Debug and RARELOAD.Debug.Write then
            local status = isStuck and "stuck" or "clear"
            RARELOAD.Debug.Write("anti_stuck", "INFO", 0, "Spawn position validation: " .. status,
                { entity = ply })
            if stuckReason then
                RARELOAD.Debug.Write("anti_stuck", "INFO", 1, "Reason: " .. tostring(stuckReason),
                    { entity = ply })
            end
        end

        if isStuck then
            if RARELOAD.GetPlayerSetting(ply, "debugEnabled") and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                RARELOAD.Debug.AntiStuck("IsPositionStuck",
                    { methodName = "IsPositionStuck", position = SavedInfo.pos, reason = stuckReason }, ply)
            end
            local safePos, success = RARELOAD.AntiStuck.ResolveStuckPosition(savedPos, ply)
            if success then
                local pos = safePos
                if type(pos) == "table" and pos.x and pos.y and pos.z then
                    pos = Vector(pos.x, pos.y, pos.z)
                end
                ApplySpawnTransform(ply, {
                    setPos = pos,
                    cachePos = safePos,
                    moveType = moveType,
                    savedAng = SavedInfo.ang,
                    debugEnabled = DebugEnabled,
                    successMessage = "Applied saved angle after anti-stuck: ",
                    warnOnAngleParseFailure = true
                })

                if safePos ~= SavedInfo.pos and DebugEnabled and RARELOAD.Debug and RARELOAD.Debug.Write then
                    RARELOAD.Debug.Write("respawn", "INFO", 0, "Player position adjusted by anti-stuck system",
                        { entity = ply })
                end
            else
                ApplySpawnTransform(ply, {
                    setPos = savedPos,
                    cachePos = savedPos,
                    moveType = moveType,
                    savedAng = SavedInfo.ang,
                    debugEnabled = DebugEnabled,
                    warnOnAngleParseFailure = false
                })
                ply:ChatPrint("[RARELOAD] Warning: Position may be stuck. Anti-stuck could not find a better spot.")
                if RARELOAD.Debug and RARELOAD.Debug.Write then
                    RARELOAD.Debug.Write("respawn", "WARNING", 0,
                        "Anti-stuck resolution failed; using original saved position", { entity = ply })
                elseif DebugEnabled then
                    print("[RARELOAD DEBUG] Anti-stuck resolution failed; using original saved position")
                end
            end
        else
            if DebugEnabled and RARELOAD.Debug and RARELOAD.Debug.Write then
                RARELOAD.Debug.Write("respawn", "VERBOSE", 0, "Position status: Not stuck, using saved position",
                    { entity = ply })
            end
            ApplySpawnTransform(ply, {
                setPos = savedPos,
                cachePos = SavedInfo.pos,
                moveType = moveType,
                savedAng = SavedInfo.ang,
                debugEnabled = DebugEnabled,
                successMessage = "Applied saved angle: ",
                warnOnAngleParseFailure = true
            })
        end
    else
        ApplySpawnTransform(ply, {
            setPos = savedPos,
            cachePos = savedPos,
            moveType = moveType,
            savedAng = SavedInfo.ang,
            debugEnabled = DebugEnabled,
            successMessage = "Applied saved angle (anti-stuck disabled)",
            appendParsedAngle = false,
            warnOnAngleParseFailure = true
        })

        if DebugEnabled and RARELOAD.Debug and RARELOAD.Debug.Write then
            RARELOAD.Debug.Write("respawn", "VERBOSE", 0,
                "Anti-stuck disabled; used saved position and angles directly",
                { entity = ply })
        end
    end
    local canRestoreInventory = hasPerm("KEEP_INVENTORY") and hasPerm("RETAIN_INVENTORY")
    local canRestoreGlobalInventory = hasPerm("KEEP_INVENTORY") and hasPerm("RETAIN_GLOBAL_INVENTORY")

    if canRestoreGlobalInventory and RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
        timer.Simple(0.5, function()
            if IsValid(ply) then
                RARELOAD.RestoreGlobalInventory(ply)
                if RARELOAD.GetPlayerSetting(ply, "debugEnabled") and RARELOAD.Debug and RARELOAD.Debug.Write then
                    RARELOAD.Debug.Write("respawn", "INFO", 0, "Global inventory: Attempting to restore (priority)",
                        { entity = ply })
                end
            end
        end)
    elseif canRestoreInventory and RARELOAD.GetPlayerSetting(ply, "retainInventory") and SavedInfo.inventory then
        RARELOAD.RestoreInventory(ply, SavedInfo)
        if RARELOAD.GetPlayerSetting(ply, "debugEnabled") and RARELOAD.Debug and RARELOAD.Debug.Write then
            RARELOAD.Debug.Write("respawn", "INFO", 0, "Using map-specific inventory (global inventory disabled)",
                { entity = ply })
        end
    end
    if hasPerm("RETAIN_HEALTH_ARMOR") and RARELOAD.GetPlayerSetting(ply, "retainHealthArmor", true) then
        timer.Simple(0.5, function()
            if not IsValid(ply) then return end
            ply:SetHealth(SavedInfo.health or ply:GetMaxHealth())
            ply:SetArmor(SavedInfo.armor or 0)
        end)
    end
    if hasPerm("RETAIN_AMMO") and RARELOAD.GetPlayerSetting(ply, "retainAmmo", true) and SavedInfo.ammo then
        timer.Simple(1, function()
            if not IsValid(ply) then return end
            for weaponClass, ammoData in pairs(SavedInfo.ammo) do
                local weapon = ply:GetWeapon(weaponClass)
                if IsValid(weapon) then
                    local primaryAmmoType = weapon:GetPrimaryAmmoType()
                    local secondaryAmmoType = weapon:GetSecondaryAmmoType()
                    ply:SetAmmo(ammoData.primary, primaryAmmoType)
                    ply:SetAmmo(ammoData.secondary, secondaryAmmoType)
                    if ammoData.clip1 and ammoData.clip1 >= 0 then
                        weapon:SetClip1(ammoData.clip1)
                    end
                    if ammoData.clip2 and ammoData.clip2 >= 0 then
                        weapon:SetClip2(ammoData.clip2)
                    end
                    RARELOAD.Debug.BufferClipRestore(ammoData.clip1, ammoData.clip2, weapon)
                end
            end
            RARELOAD.Debug.FlushClipRestoreBuffer()
        end)
    end
    if hasPerm("RESTORE_VEHICLES") and RARELOAD.GetPlayerSetting(ply, "retainVehicles", false) and SavedInfo.vehicles then
        RARELOAD.RestoreVehicles(SavedInfo, ply)
    end
    if RARELOAD.GetPlayerSetting(ply, "retainVehicleState", false) and SavedInfo.vehicleState then
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
    if hasPerm("RESTORE_ENTITIES") and RARELOAD.GetPlayerSetting(ply, "retainMapEntities", true) and SavedInfo.entities then
        local playerPos = SavedInfo.pos
        RARELOAD.RestoreEntities(playerPos, SavedInfo, ply)

        timer.Simple(0.1, function()
            if not IsValid(ply) then return end
            local currentPos = ply:GetPos()

            local rareloadEnts = {}
            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and ent.SpawnedByRareload then
                    rareloadEnts[#rareloadEnts + 1] = ent
                    ent._rareloadSavedSolid = ent:GetSolid()
                    ent:SetNotSolid(true)
                end
            end

            ply:SetPos(currentPos)

            timer.Simple(0.15, function()
                for _, ent in ipairs(rareloadEnts) do
                    if IsValid(ent) then
                        ent:SetNotSolid(false)
                        if ent._rareloadSavedSolid then
                            ent:SetSolid(ent._rareloadSavedSolid)
                            ent._rareloadSavedSolid = nil
                        end
                    end
                end
            end)
        end)
    end
    if hasPerm("RESTORE_NPCS") and RARELOAD.GetPlayerSetting(ply, "retainMapNPCs", true) and HasSnapshotData(SavedInfo.npcs) then
        RARELOAD.RestoreNPCs(SavedInfo, ply)
    end

    if keepPlayerStates and SavedInfo.playerStates then
        timer.Simple(0.1, function()
            if not IsValid(ply) then return end

            local states = SavedInfo.playerStates
            local restoredStates = {}

            if states.godmode then
                ply:GodEnable()
                table.insert(restoredStates, "godmode")
            end

            if states.notarget then
                ply:SetNoTarget(true)
                table.insert(restoredStates, "notarget")
            end

            if states.frozen then
                ply:Freeze(true)
                table.insert(restoredStates, "frozen")
            end

            if states.noclip and ply:GetMoveType() ~= MOVETYPE_NOCLIP then
                ply:SetMoveType(MOVETYPE_NOCLIP)
                table.insert(restoredStates, "noclip")
            end

            if RARELOAD.GetPlayerSetting(ply, "debugEnabled") and #restoredStates > 0 then
                RARELOAD.Debug.SendToPlayer(ply,
                    "[RARELOAD DEBUG] Restored player states: " .. table.concat(restoredStates, ", "))
            end
        end)
    end

    RestoreActiveWeapon(ply, SavedInfo, canRestoreGlobalInventory, canRestoreInventory)

    SendSpawnPhantom(ply, SavedInfo)
end
