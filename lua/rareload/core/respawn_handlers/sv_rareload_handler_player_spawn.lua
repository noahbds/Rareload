-- Load centralized conversion functions
if not RARELOAD or not RARELOAD.DataUtils then
    include("rareload/utils/rareload_data_utils.lua")
end

-- Using centralized angle conversion function directly
-- from RARELOAD.DataUtils instead of creating a local wrapper function

function RARELOAD.HandlePlayerSpawn(ply)
    if not RARELOAD.settings.addonEnabled then return end
    if not IsValid(ply) then return end
    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    if not RARELOAD.AntiStuck then
        include("rareload/anti_stuck/sv_anti_stuck_init.lua")
        if RARELOAD.AntiStuck and RARELOAD.AntiStuck.Initialize then
            RARELOAD.AntiStuck.Initialize()
            if RARELOAD.AntiStuck.LoadMethodPriorities then
                RARELOAD.AntiStuck.LoadMethodPriorities(true)
            end
        end
    end
    local Settings = RARELOAD.settings
    if not Settings then
        print("[RARELOAD] Error: Settings not loaded, cannot handle player spawn.")
        return
    end
    local DebugEnabled = Settings.debugEnabled
    local SteamID = ply:SteamID()
    local MapName = game.GetMap()
    SavedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][SteamID]
    RARELOAD.Debug.LogSpawnInfo(ply)
    RARELOAD.Debug.LogInventory(ply)
    if not SavedInfo then return end

    if DebugEnabled and SavedInfo.ang then
        print("[RARELOAD DEBUG] Saved angle data type: " .. type(SavedInfo.ang))
        print("[RARELOAD DEBUG] Saved angle data: " .. tostring(SavedInfo.ang))
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
    local moveType = tonumber(SavedInfo.moveType) or MOVETYPE_WALK
    if not Settings.spawnModeEnabled then
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

        -- Always check if position is stuck, regardless of hull collision
        isStuck, stuckReason = RARELOAD.AntiStuck.IsPositionStuck(
            (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
            and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
            or SavedInfo.pos, ply, true) -- Mark as original position

        if isStuck then
            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD DEBUG] Position is stuck (" .. stuckReason .. "), using anti-stuck system")
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
                ply:SetPos(pos)
                RARELOAD.SavePositionToCache(safePos)

                -- Apply saved angle with slight delay
                timer.Simple(0.05, function()
                    if not IsValid(ply) then return end
                    local parsedAngle = RARELOAD.DataUtils.ToAngle(SavedInfo.ang)
                    if parsedAngle then
                        ply:SetEyeAngles(parsedAngle)
                        if DebugEnabled then
                            print("[RARELOAD DEBUG] Applied saved angle after anti-stuck: " .. tostring(parsedAngle))
                        end
                    else
                        if DebugEnabled then
                            print("[RARELOAD DEBUG] Could not parse saved angle: " .. tostring(SavedInfo.ang))
                        end
                    end
                end)

                ply:SetMoveType(MOVETYPE_WALK)
                if safePos ~= SavedInfo.pos and DebugEnabled then
                    print("[RARELOAD DEBUG] Player position adjusted by anti-stuck system")
                end
            else
                ply:ChatPrint("[RARELOAD] Warning: Emergency positioning was required.")
                if DebugEnabled then print("[RARELOAD DEBUG] Anti-stuck system used emergency positioning") end
            end
        else
            if DebugEnabled then
                print("[RARELOAD DEBUG] Position is not stuck, using directly")
            end
            local pos = (SavedInfo.pos and SavedInfo.pos.x and SavedInfo.pos.y and SavedInfo.pos.z)
                and Vector(SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z)
                or SavedInfo.pos
            ply:SetPos(pos)
            RARELOAD.SavePositionToCache(SavedInfo.pos)

            -- Apply saved angle with slight delay
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

            ply:SetMoveType(MOVETYPE_WALK)
        end
    else
        timer.Simple(0, function() ply:SetMoveType(moveType) end)
        SetPlayerPositionAndEyeAngles(ply, SavedInfo)
        if DebugEnabled then
            print("[RARELOAD DEBUG] Move type set to: " .. tostring(moveType))
            print("[RARELOAD DEBUG] Using SetPlayerPositionAndEyeAngles for spawn mode")
        end
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
    if Settings.retainHealthArmor then
        timer.Simple(0.5, function()
            ply:SetHealth(SavedInfo.health or ply:GetMaxHealth())
            ply:SetArmor(SavedInfo.armor or 0)
        end)
    end
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
    if Settings.retainVehicles and SavedInfo.vehicles then
        RARELOAD.RestoreVehicles()
    end
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
    if Settings.retainMapEntities and SavedInfo.entities then
        local playerPos = SavedInfo.pos
        local spawnedCloseEntities = RARELOAD.RestoreEntities(playerPos)
        if spawnedCloseEntities and not Settings.spawnModeEnabled then
            timer.Simple(0.05, function()
                if IsValid(ply) then
                    SetPlayerPositionAndEyeAngles(ply, SavedInfo)
                end
            end)
        end
    end
    if Settings.retainMapNPCs and SavedInfo.npcs and #SavedInfo.npcs > 0 then
        RARELOAD.RestoreNPCs()
    end
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
    if DebugEnabled then
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(ply:GetPos())
        net.WriteAngle(ply:GetAngles())
        net.Broadcast()
    end
end
