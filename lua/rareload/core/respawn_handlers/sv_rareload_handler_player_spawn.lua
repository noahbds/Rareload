---@diagnostic disable: inject-field, undefined-field

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

function RARELOAD.HandlePlayerSpawn(ply)
    if not IsValid(ply) then return end

    local function hasPerm(permName)
        if RARELOAD.CheckPermission then
            return RARELOAD.CheckPermission(ply, permName)
        end
        return true
    end

    -- Ensure player settings are loaded before any spawn decisions.
    if RARELOAD.PlayerSettings and RARELOAD.PlayerSettings.Load then
        RARELOAD.PlayerSettings.Load(ply:SteamID())
    end

    -- Check if addon is enabled for this player
    if not RARELOAD.GetPlayerSetting(ply, "addonEnabled", true) then return end
    if not hasPerm("LOAD_POSITION") or not hasPerm("RARELOAD_SPAWN") then
        return
    end
    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    -- Load player positions for this specific player if not already loaded
    local mapName = game.GetMap()
    local steamID = ply:SteamID()
    local hasThisPlayerData = RARELOAD.playerPositions[mapName]
        and RARELOAD.playerPositions[mapName][steamID] ~= nil

    if not hasThisPlayerData and RARELOAD.LoadPlayerPositions then
        -- Load all player positions (will load from disk if not in memory)
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

    -- Get player-specific settings instead of global
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
    ply.lastSpawnPosition = (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
        and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
        or SavedInfo.pos
    ply.hasMovedAfterSpawn = false
    hook.Add("PlayerTick", "RARELOAD_CheckMovement_" .. ply:EntIndex(), function(ply, mv)
        if not IsValid(ply) or not ply.lastSpawnPosition then return end
        local moved = (ply:GetPos() - ply.lastSpawnPosition):LengthSqr() > 4
        if moved and not ply.hasMovedAfterSpawn then
            RARELOAD.SavePositionToCache(ply.lastSpawnPosition)
            ply.hasMovedAfterSpawn = true
            hook.Remove("PlayerTick", "RARELOAD_CheckMovement_" .. ply:EntIndex())
        end
    end)
    if not RARELOAD.GetPlayerSetting(ply, "addonEnabled", true) then
        for _, weapon in ipairs({
            "weapon_crowbar", "weapon_physgun", "weapon_physcannon", "weapon_pistol", "weapon_357",
            "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg",
            "gmod_tool", "gmod_camera", "gmod_toolgun"
        }) do
            ply:Give(weapon)
        end
        if RARELOAD.Debug and RARELOAD.Debug.Write then
            RARELOAD.Debug.Write("respawn", "INFO", 0, "Addon disabled, default weapons given", { entity = ply })
        elseif DebugEnabled then
            print("[RARELOAD DEBUG] Addon disabled, default weapons given.")
        end
        return
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
    -- Mark spawn time so autosave doesn't immediately overwrite the saved position
    ply._rareloadSpawnTime = CurTime()
    SavedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][SteamID]
    if not SavedInfo then
        if DebugEnabled then RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] No saved player info found.") end
        return
    end
    local moveType = tonumber(SavedInfo.moveType) or MOVETYPE_WALK

    if antiStuckEnabled then
        if not RARELOAD.AntiStuck then
            include("rareload/anti_stuck/sv_anti_stuck_init.lua")
            if RARELOAD.AntiStuck.Initialize then
                RARELOAD.AntiStuck.Initialize()
            end
        end
        local testPos = (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
            and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z + 2)
            or (SavedInfo.pos + Vector(0, 0, 2))
        local isStuck, stuckReason = false, nil

        isStuck, stuckReason = RARELOAD.AntiStuck.IsPositionStuck(
            (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
            and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
            or SavedInfo.pos, ply, true)

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
            local safePos, success = RARELOAD.AntiStuck.ResolveStuckPosition(
                (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
                and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
                or SavedInfo.pos, ply)
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
                -- Anti-stuck resolution failed; still attempt the original saved position
                local fallbackPos = (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
                    and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
                    or SavedInfo.pos
                ApplySpawnTransform(ply, {
                    setPos = fallbackPos,
                    cachePos = fallbackPos,
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
            local pos = (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
                and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
                or SavedInfo.pos
            ApplySpawnTransform(ply, {
                setPos = pos,
                cachePos = SavedInfo.pos,
                moveType = moveType,
                savedAng = SavedInfo.ang,
                debugEnabled = DebugEnabled,
                successMessage = "Applied saved angle: ",
                warnOnAngleParseFailure = true
            })
        end
    else
        local pos = (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
            and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
            or SavedInfo.pos
        ApplySpawnTransform(ply, {
            setPos = pos,
            cachePos = pos,
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

        -- After entity restoration, the Source physics engine will push the
        -- player out of any restored entity that overlaps the spawn position.
        -- To prevent this, temporarily make all Rareload-spawned entities
        -- non-solid, re-apply the current position (which may have been
        -- adjusted by the anti-stuck system), then restore solidity.
        timer.Simple(0.1, function()
            if not IsValid(ply) then return end
            -- Use the player's *current* position — this is either the saved
            -- position or the safe position chosen by the anti-stuck system.
            -- We must NOT overwrite it with SavedInfo.pos which could put the
            -- player back into a stuck spot that anti-stuck already resolved.
            local currentPos = ply:GetPos()

            -- Collect restored entities and make them temporarily non-solid
            local rareloadEnts = {}
            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and ent.SpawnedByRareload then
                    rareloadEnts[#rareloadEnts + 1] = ent
                    ent._rareloadSavedSolid = ent:GetSolid()
                    ent:SetNotSolid(true)
                end
            end

            -- Re-apply the position while entities are non-solid so the
            -- physics engine doesn't push the player away from the entities
            ply:SetPos(currentPos)

            -- Restore entity solidity after the player is settled
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

    -- NEW - Restore player states (godmode, notarget, etc.)
    if hasPerm("RETAIN_PLAYER_STATES") and RARELOAD.GetPlayerSetting(ply, "retainPlayerStates", true) and SavedInfo.playerStates then
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

    local activeWeaponToRestore = nil

    local function SendWeaponRestoreDebug(message)
        if not RARELOAD.GetPlayerSetting(ply, "debugEnabled") then return end

        local formatted = "[RARELOAD DEBUG] " .. tostring(message)
        if RARELOAD.Debug and RARELOAD.Debug.SendToPlayer then
            RARELOAD.Debug.SendToPlayer(ply, formatted)
        else
            print(formatted)
        end
    end

    if canRestoreGlobalInventory and RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
        if RARELOAD.globalInventory and RARELOAD.globalInventory[ply:SteamID()] then
            activeWeaponToRestore = RARELOAD.globalInventory[ply:SteamID()].activeWeapon
            SendWeaponRestoreDebug("Using global inventory active weapon: " .. tostring(activeWeaponToRestore))
        end
    elseif canRestoreInventory and SavedInfo.activeWeapon then
        activeWeaponToRestore = SavedInfo.activeWeapon
        SendWeaponRestoreDebug("Using saved position active weapon: " .. tostring(activeWeaponToRestore))
    end
    if activeWeaponToRestore then
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
    if RARELOAD.CheckPermission(ply, "VIEW_PHANTOM") and SavedInfo then
        local phantomPos = RARELOAD.DataUtils.ToVector(SavedInfo.pos) or ply:GetPos()
        local phantomAng = RARELOAD.DataUtils.ToAngle(SavedInfo.ang) or ply:GetAngles()
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(phantomPos)
        net.WriteAngle(phantomAng)
        net.Send(ply)
    end
end
