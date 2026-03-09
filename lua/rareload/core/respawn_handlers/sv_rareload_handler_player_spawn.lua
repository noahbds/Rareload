---@diagnostic disable: inject-field, undefined-field

local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

local function HasSnapshotData(bucket)
    if SnapshotUtils.HasSnapshot(bucket) then
        return true
    end
    return istable(bucket) and #bucket > 0
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
    RARELOAD.Debug.LogSpawnInfo(ply)
    RARELOAD.Debug.LogInventory(ply)
    if not SavedInfo then return end

    if DebugEnabled and SavedInfo.ang then
        RARELOAD.Debug.Log("VERBOSE", "Saved angle data", {
            "Type: " .. type(SavedInfo.ang),
            "Value: " .. tostring(SavedInfo.ang)
        }, ply)
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
        if DebugEnabled then print("[RARELOAD DEBUG] Addon disabled, default weapons given.") end
        return
    end
    if RARELOAD.GetPlayerSetting(ply, "nocustomrespawnatdeath", false) and ply.wasKilled then
        ply.wasKilled = false
        if DebugEnabled then print("[RARELOAD DEBUG] Player was killed, resetting flag.") end
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

    if RARELOAD.GetPlayerSetting(ply, "spawnModeEnabled", true) then
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
                -- Defer SetPos to next frame to ensure it persists after engine spawn processing
                timer.Simple(0, function()
                    if not IsValid(ply) then return end
                    ply:SetPos(pos)
                    ply:SetMoveType(moveType)
                end)
                RARELOAD.SavePositionToCache(safePos)

                timer.Simple(0.05, function()
                    if not IsValid(ply) then return end
                    local parsedAngle = RARELOAD.DataUtils.ToAngle(SavedInfo.ang)
                    if parsedAngle then
                        ply:SetEyeAngles(parsedAngle)
                        if DebugEnabled then
                            RARELOAD.Debug.Log("INFO", "Applied saved angle after anti-stuck", tostring(parsedAngle), ply)
                        end
                    else
                        if DebugEnabled then
                            print("[RARELOAD DEBUG] Could not parse saved angle: " .. tostring(SavedInfo.ang))
                        end
                    end
                end)

                if safePos ~= SavedInfo.pos and DebugEnabled then
                    RARELOAD.Debug.Log("INFO", "Player position adjusted by anti-stuck system", tostring(safePos), ply)
                end
            else
                -- Anti-stuck resolution failed; still attempt the original saved position
                local fallbackPos = (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
                    and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
                    or SavedInfo.pos
                timer.Simple(0, function()
                    if not IsValid(ply) then return end
                    ply:SetPos(fallbackPos)
                    ply:SetMoveType(moveType)
                end)
                timer.Simple(0.05, function()
                    if not IsValid(ply) then return end
                    local parsedAngle = RARELOAD.DataUtils.ToAngle(SavedInfo.ang)
                    if parsedAngle then ply:SetEyeAngles(parsedAngle) end
                end)
                RARELOAD.SavePositionToCache(fallbackPos)
                ply:ChatPrint("[RARELOAD] Warning: Position may be stuck. Anti-stuck could not find a better spot.")
                if DebugEnabled then print("[RARELOAD DEBUG] Anti-stuck resolution failed; using original saved position") end
            end
        else
            if DebugEnabled then
                RARELOAD.Debug.Log("VERBOSE", "Position status", "Not stuck, using saved position", ply)
            end
            local pos = (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
                and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
                or SavedInfo.pos
            -- Defer SetPos to next frame to ensure it persists after engine spawn processing
            timer.Simple(0, function()
                if not IsValid(ply) then return end
                ply:SetPos(pos)
                ply:SetMoveType(moveType)
            end)
            RARELOAD.SavePositionToCache(SavedInfo.pos)

            timer.Simple(0.05, function()
                if not IsValid(ply) then return end
                local parsedAngle = RARELOAD.DataUtils.ToAngle(SavedInfo.ang)
                if parsedAngle then
                    ply:SetEyeAngles(parsedAngle)
                    if DebugEnabled then
                        print("[RARELOAD DEBUG] Applied saved angle: " .. tostring(parsedAngle))
                    end
                else
                    if DebugEnabled then
                        print("[RARELOAD DEBUG] Could not parse saved angle: " .. tostring(SavedInfo.ang))
                    end
                end
            end)
        end
    else
        local pos = (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
            and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
            or SavedInfo.pos
        -- Defer SetPos to next frame to ensure it persists after engine spawn processing
        timer.Simple(0, function()
            if not IsValid(ply) then return end
            ply:SetPos(pos)
            ply:SetMoveType(moveType)
        end)
        RARELOAD.SavePositionToCache(pos)

        timer.Simple(0.05, function()
            if not IsValid(ply) then return end
            local parsedAngle = RARELOAD.DataUtils.ToAngle(SavedInfo.ang)
            if parsedAngle then
                ply:SetEyeAngles(parsedAngle)
                if DebugEnabled then
                    print("[RARELOAD DEBUG] Applied saved angle (anti-stuck disabled): " .. tostring(parsedAngle))
                end
            else
                if DebugEnabled then
                    print("[RARELOAD DEBUG] Could not parse saved angle: " .. tostring(SavedInfo.ang))
                end
            end
        end)

        if DebugEnabled then
            print("[RARELOAD DEBUG] Move type set to: " .. tostring(moveType))
            print("[RARELOAD DEBUG] Anti-stuck disabled; used saved position and angles directly")
        end
    end
    local canRestoreInventory = hasPerm("KEEP_INVENTORY") and hasPerm("RETAIN_INVENTORY")
    local canRestoreGlobalInventory = hasPerm("KEEP_INVENTORY") and hasPerm("RETAIN_GLOBAL_INVENTORY")

    if canRestoreGlobalInventory and RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
        timer.Simple(0.5, function()
            if IsValid(ply) then
                RARELOAD.RestoreGlobalInventory(ply)
                if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
                    RARELOAD.Debug.Log("INFO", "Global inventory", "Attempting to restore (priority)", ply)
                end
            end
        end)
    elseif canRestoreInventory and RARELOAD.GetPlayerSetting(ply, "retainInventory") and SavedInfo.inventory then
        RARELOAD.RestoreInventory(ply, SavedInfo)
        if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
            print("[RARELOAD DEBUG] Using map-specific inventory (global inventory disabled)")
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
                RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Restored player states: " .. table.concat(restoredStates, ", "))
            end
        end)
    end
    
    local activeWeaponToRestore = nil
    if canRestoreGlobalInventory and RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
        if RARELOAD.globalInventory and RARELOAD.globalInventory[ply:SteamID()] then
            activeWeaponToRestore = RARELOAD.globalInventory[ply:SteamID()].activeWeapon
            if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
                RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Using global inventory active weapon: " .. tostring(activeWeaponToRestore))
            end
        end
    elseif canRestoreInventory and SavedInfo.activeWeapon then
        activeWeaponToRestore = SavedInfo.activeWeapon
        if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
            RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Using saved position active weapon: " .. tostring(activeWeaponToRestore))
        end
    end
    if activeWeaponToRestore then
        if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
            RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Attempting to restore active weapon: " .. tostring(activeWeaponToRestore))
        end
        timer.Simple(0.2, function()
            if not IsValid(ply) then
                if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
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
            if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
                RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Player weapons available: " .. table.concat(availableWeapons, ", "))
            end
        end)
        timer.Simple(0.6, function()
            if IsValid(ply) then
                if ply:HasWeapon(activeWeaponToRestore) then
                    if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
                        RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Selecting weapon (0.6s): " .. activeWeaponToRestore)
                    end
                    ply:SelectWeapon(activeWeaponToRestore)
                else
                    if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
                        RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Player doesn't have weapon (0.6s): " .. activeWeaponToRestore)
                    end
                end
            end
        end)
        timer.Simple(1.2, function()
            if IsValid(ply) and ply:GetActiveWeapon() and ply:GetActiveWeapon():GetClass() ~= activeWeaponToRestore then
                if ply:HasWeapon(activeWeaponToRestore) then
                    if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
                        RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Second attempt selecting weapon (1.2s): " .. activeWeaponToRestore)
                    end
                    ply:SelectWeapon(activeWeaponToRestore)
                    timer.Simple(0.1, function()
                        if IsValid(ply) and ply:HasWeapon(activeWeaponToRestore) then
                            ply:ConCommand("use " .. activeWeaponToRestore)
                        end
                    end)
                else
                    if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
                        RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Weapon still not available (1.2s): " .. activeWeaponToRestore)
                    end
                end
            end
        end)
        timer.Simple(1.5, function()
            if RARELOAD.GetPlayerSetting(ply, "debugEnabled") and IsValid(ply) then
                local currentWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "none"
                RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Final weapon state - Current: " .. currentWeapon ..
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
