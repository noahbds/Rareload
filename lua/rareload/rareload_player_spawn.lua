function RARELOAD.HandlePlayerSpawn(ply)
    Settings = RARELOAD.settings
    DebugEnabled = Settings.debugEnabled
    SteamID = ply:SteamID()
    MapName = game.GetMap()

    RARELOAD.Debug.LogSpawnInfo(ply)
    RARELOAD.Debug.LogInventory(ply)

    -- Cache system (broken)
    if not SavedInfo then return end

    ply.lastSpawnPosition = SavedInfo.pos
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

    if not Settings.addonEnabled then
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

    if Settings.nocustomrespawnatdeath and ply.wasKilled then
        ply.wasKilled = false
        if DebugEnabled then print("[RARELOAD DEBUG] Player was killed, resetting flag.") end
        return
    end

    SavedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][SteamID]
    if not SavedInfo then
        if DebugEnabled then print("[RARELOAD DEBUG] No saved player info found.") end
        return
    end

    -- **Handle Spawn Position & Move Type**
    local moveType = tonumber(SavedInfo.moveType) or MOVETYPE_WALK
    if not Settings.spawnModeEnabled then
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

    if RARELOAD.settings.retainGlobalInventory then
        timer.Simple(0.5, function()
            if IsValid(ply) then
                RARELOAD.RestoreGlobalInventory(ply)
                if RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Attempting to restore global inventory (priority)")
                end
            end
        end)
    elseif RARELOAD.settings.retainInventory and SavedInfo.inventory then
        RARELOAD.RestoreInventory(ply)
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Using map-specific inventory (global inventory disabled)")
        end
    end

    -- **Restore Health & Armor**
    if Settings.retainHealthArmor then
        timer.Simple(0.5, function()
            ply:SetHealth(SavedInfo.health or ply:GetMaxHealth())
            ply:SetArmor(SavedInfo.armor or 0)
        end)
    end

    -- **Restore Ammo**
    if Settings.retainAmmo and SavedInfo.ammo then
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

    -- **Restore Vehicles** BROKEN
    if Settings.retainVehicles and SavedInfo.vehicles then
        RARELOAD.RestoreVehicles()
    end

    -- **Restore Vehicle State** BROKEN
    if Settings.retainVehicleState and SavedInfo.vehicleState then
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
    if Settings.retainMapEntities and SavedInfo.entities then
        RARELOAD.RestoreEntities()
    end

    -- **Restore NPCs**
    if Settings.retainMapNPCs and SavedInfo.npcs and #SavedInfo.npcs > 0 then
        RARELOAD.RestoreNPCs()
    end

    -- **Restore Active Weapon**
    local activeWeaponToRestore = nil

    if RARELOAD.settings.retainGlobalInventory then
        if RARELOAD.globalInventory and RARELOAD.globalInventory[ply:SteamID()] then
            activeWeaponToRestore = RARELOAD.globalInventory[ply:SteamID()].activeWeapon
            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD DEBUG] Using global inventory active weapon: " .. tostring(activeWeaponToRestore))
            end
        end
    elseif SavedInfo.activeWeapon then
        activeWeaponToRestore = SavedInfo.activeWeapon
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Using saved position active weapon: " .. tostring(activeWeaponToRestore))
        end
    end

    if activeWeaponToRestore then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Attempting to restore active weapon: " .. tostring(activeWeaponToRestore))
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

        timer.Simple(0.6, function()
            if IsValid(ply) then
                if ply:HasWeapon(activeWeaponToRestore) then
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Selecting weapon (0.6s): " .. activeWeaponToRestore)
                    end
                    ply:SelectWeapon(activeWeaponToRestore)
                else
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Player doesn't have weapon (0.6s): " .. activeWeaponToRestore)
                    end
                end
            end
        end)

        timer.Simple(1.2, function()
            if IsValid(ply) and ply:GetActiveWeapon() and ply:GetActiveWeapon():GetClass() ~= activeWeaponToRestore then
                if ply:HasWeapon(activeWeaponToRestore) then
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Second attempt selecting weapon (1.2s): " .. activeWeaponToRestore)
                    end
                    ply:SelectWeapon(activeWeaponToRestore)

                    timer.Simple(0.1, function()
                        if IsValid(ply) and ply:HasWeapon(activeWeaponToRestore) then
                            ply:ConCommand("use " .. activeWeaponToRestore)
                        end
                    end)
                else
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Weapon still not available (1.2s): " .. activeWeaponToRestore)
                    end
                end
            end
        end)

        timer.Simple(1.5, function()
            if RARELOAD.settings.debugEnabled and IsValid(ply) then
                local currentWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "none"
                print("[RARELOAD DEBUG] Final weapon state - Current: " .. currentWeapon ..
                    ", Expected: " .. activeWeaponToRestore ..
                    ", Success: " .. tostring(currentWeapon == activeWeaponToRestore))
            end
        end)
    end

    -- **Create Player Phantom if debug is enabled**
    if DebugEnabled then
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(ply:GetPos())
        net.WriteAngle(ply:GetAngles())
        net.Broadcast()
    end
end
