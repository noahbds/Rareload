local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

-----------------------------------------------------------------
-- Utility helpers
-----------------------------------------------------------------

local function HasSnapshotData(bucket)
    if bucket == nil then return false end
    if SnapshotUtils.HasSnapshot(bucket) then return true end
    return istable(bucket) and next(bucket) ~= nil
end

local function DebugLog(ply, level, indent, msg)
    if RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write("respawn", level, indent, msg, { entity = ply })
    end
end

local function ApplySpawnTransform(ply, opts)
    if not IsValid(ply) then return end
    opts = opts or {}

    local targetPos = RARELOAD.DataUtils.ToVector(opts.setPos)
    local moveType = opts.moveType or MOVETYPE_WALK
    local cachePos = RARELOAD.DataUtils.ToVector(opts.cachePos)

    timer.Simple(0, function()
        if not IsValid(ply) then return end
        ply:SetPos(targetPos)
        ply:SetMoveType(moveType)
    end)

    RARELOAD.SavePositionToCache(cachePos)

    timer.Simple(0.05, function()
        if not IsValid(ply) then return end

        local parsedAngle = RARELOAD.DataUtils.ToAngle(opts.savedAng)
        if parsedAngle then
            ply:SetEyeAngles(parsedAngle)
            if opts.successMessage and opts.debugEnabled then
                local appendParsedAngle = opts.appendParsedAngle ~= false
                local msg = opts.successMessage
                if appendParsedAngle then
                    msg = msg .. tostring(parsedAngle)
                end
                DebugLog(ply, "INFO", 0, msg)
            end
            return
        end

        if opts.warnOnAngleParseFailure and opts.debugEnabled then
            DebugLog(ply, "WARNING", 0,
                "Could not parse saved angle: " .. tostring(opts.savedAng))
        end
    end)
end

-----------------------------------------------------------------
-- Cleanup helpers
-----------------------------------------------------------------

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

-----------------------------------------------------------------
-- Active weapon restoration
-----------------------------------------------------------------
local function RestoreActiveWeapon(ply, SavedInfo, inventoryWasRestored, globalInventoryWasRestored)
    local activeWeaponToRestore

    if globalInventoryWasRestored and RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
        local globalInventory = RARELOAD.globalInventory and RARELOAD.globalInventory[ply:SteamID()]
        activeWeaponToRestore = globalInventory and globalInventory.activeWeapon or nil
    elseif inventoryWasRestored then
        activeWeaponToRestore = SavedInfo.activeWeapon
    end

    if not activeWeaponToRestore or activeWeaponToRestore == "None" then return end

    timer.Simple(0.6, function()
        if not IsValid(ply) or not ply:HasWeapon(activeWeaponToRestore) then
            return
        end
        ply:SelectWeapon(activeWeaponToRestore)

        if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
            local message = "[RARELOAD DEBUG] Restored active weapon: " .. activeWeaponToRestore
            if RARELOAD.Debug and RARELOAD.Debug.SendToPlayer then
                RARELOAD.Debug.SendToPlayer(ply, message)
            else
                print(message)
            end
        end
    end)
end

-----------------------------------------------------------------
-- Helper to safely get a setting with fallback chain
-----------------------------------------------------------------
local function GetSettingOrDefault(ply, key, default)
    local val = RARELOAD.GetPlayerSetting(ply, key)
    if val ~= nil then return val end
    if RARELOAD.settings and RARELOAD.settings[key] ~= nil then
        return RARELOAD.settings[key]
    end
    return default
end

-----------------------------------------------------------------
-- Main spawn handler
-----------------------------------------------------------------
function RARELOAD.HandlePlayerSpawn(ply)
    if not IsValid(ply) then return end

    local function hasPerm(permName)
        if RARELOAD.CheckPermission then
            return RARELOAD.CheckPermission(ply, permName)
        end
        return true
    end

    -- Load player settings early
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

    if not (RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]) then
        if RARELOAD.LoadPlayerPositions then
            RARELOAD.LoadPlayerPositions()
        end
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
    local SavedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
    if not SavedInfo then return end

    DebugLog(ply, "INFO", 0, "Player spawn started")

    if DebugEnabled and SavedInfo.ang then
        DebugLog(ply, "VERBOSE", 0, "Saved angle data: " .. tostring(SavedInfo.ang))
    end

    ply.lastSpawnPosition = RARELOAD.DataUtils.ToVector(SavedInfo.pos)
    ply.hasMovedAfterSpawn = false
    local moveHookName = "RARELOAD_CheckMovement_" .. ply:EntIndex()
    hook.Add("PlayerTick", moveHookName, function(tickPly)
        if not IsValid(ply) then
            hook.Remove("PlayerTick", moveHookName)
            return
        end
        if tickPly ~= ply or not ply.lastSpawnPosition then return end
        if not ply.hasMovedAfterSpawn
            and (ply:GetPos() - ply.lastSpawnPosition):LengthSqr() > 4096 then
            RARELOAD.SavePositionToCache(ply.lastSpawnPosition)
            ply.hasMovedAfterSpawn = true
            hook.Remove("PlayerTick", moveHookName)
        end
    end)
    timer.Simple(5, function()
        if IsValid(ply) and not ply.hasMovedAfterSpawn then
            hook.Remove("PlayerTick", moveHookName)
        end
    end)

    -----------------------------------------------------------------
    -- Death cleanup handling
    -----------------------------------------------------------------
    if RARELOAD.GetPlayerSetting(ply, "cleanupMapAfterDeath", false) and ply.wasKilled then
        local ownedOnly = RARELOAD.GetPlayerSetting(ply, "cleanupOnlyOwnedEntitiesOnDeath", false)
        local savedOnly = RARELOAD.GetPlayerSetting(ply, "cleanupOnlySavedEntitiesOnDeath", false)

        if ownedOnly then
            ply.wasKilled = false
            DebugLog(ply, "INFO", 0, "Cleanup (owned only): removing player-owned Rareload entities before respawn")
            local removed = RARELOAD.CleanupPlayerOwnedEntities(ply)
            ply._rareloadSkipExistingFilter = true
            if DebugEnabled then
                print(string.format("[RARELOAD DEBUG] Removed %d player-owned entities for %s", removed, ply:Nick()))
            end
        elseif savedOnly then
            ply.wasKilled = false
            DebugLog(ply, "INFO", 0, "Cleanup (saved only): removing Rareload saved entities before respawn")
            local removed = RARELOAD.CleanupSavedEntities(ply)
            ply._rareloadSkipExistingFilter = true
            if DebugEnabled then
                print(string.format("[RARELOAD DEBUG] Removed %d saved entities for %s", removed, ply:Nick()))
            end
        else
            if not RARELOAD._isCleaningUpMap then
                RARELOAD._isCleaningUpMap = true
                ply.wasKilled = false
                DebugLog(ply, "INFO", 0, "Cleanup (full map): cleaning up before respawn")

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
        DebugLog(ply, "INFO", 0, "Player was killed, resetting flag")
        return
    end

    ply._rareloadSpawnTime = CurTime()

    SavedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
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

    local savedPos = RARELOAD.DataUtils.ToVector(SavedInfo.pos)

    local antiStuckEnabled = GetSettingOrDefault(ply, "spawnModeEnabled", true)

    if antiStuckEnabled then
        local isStuck, stuckReason = RARELOAD.AntiStuck.IsPositionStuck(savedPos, ply, true)

        if DebugEnabled then
            local status = isStuck and "stuck" or "clear"
            DebugLog(ply, "INFO", 0, "Spawn position validation: " .. status)
            if stuckReason then
                DebugLog(ply, "INFO", 1, "Reason: " .. tostring(stuckReason))
            end
        end

        if isStuck then
            if RARELOAD.GetPlayerSetting(ply, "debugEnabled") and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                RARELOAD.Debug.AntiStuck("IsPositionStuck",
                    { methodName = "IsPositionStuck", position = SavedInfo.pos, reason = stuckReason }, ply)
            end

            local safePos, success = RARELOAD.AntiStuck.ResolveStuckPosition(savedPos, ply)
            local finalPos = RARELOAD.DataUtils.ToVector(safePos)
            if success then
                ApplySpawnTransform(ply, {
                    setPos = finalPos,
                    cachePos = finalPos,
                    moveType = moveType,
                    savedAng = SavedInfo.ang,
                    debugEnabled = DebugEnabled,
                    successMessage = "Applied saved angle after anti-stuck: ",
                    warnOnAngleParseFailure = true
                })
                if finalPos ~= savedPos then
                    DebugLog(ply, "INFO", 0, "Player position adjusted by anti-stuck system")
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
                DebugLog(ply, "WARNING", 0, "Anti-stuck resolution failed; using original saved position")
            end
        else
            DebugLog(ply, "VERBOSE", 0, "Position status: Not stuck, using saved position")
            ApplySpawnTransform(ply, {
                setPos = savedPos,
                cachePos = savedPos,
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
            cachePos = savedPos, -- Vector
            moveType = moveType,
            savedAng = SavedInfo.ang,
            debugEnabled = DebugEnabled,
            successMessage = "Applied saved angle (anti-stuck disabled)",
            appendParsedAngle = false,
            warnOnAngleParseFailure = true
        })
        DebugLog(ply, "VERBOSE", 0, "Anti-stuck disabled; used saved position and angles directly")
    end

    local canRestoreInventory = hasPerm("KEEP_INVENTORY") and hasPerm("RETAIN_INVENTORY")
    local canRestoreGlobalInventory = hasPerm("KEEP_INVENTORY") and hasPerm("RETAIN_GLOBAL_INVENTORY")
    local globalInventoryRestored = false
    local inventoryRestored = false

    if canRestoreGlobalInventory and RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
        timer.Simple(0.5, function()
            if IsValid(ply) then
                RARELOAD.RestoreGlobalInventory(ply)
                if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
                    DebugLog(ply, "INFO", 0, "Global inventory: Attempting to restore (priority)")
                end
            end
        end)
        globalInventoryRestored = true
    elseif canRestoreInventory and RARELOAD.GetPlayerSetting(ply, "retainInventory") and SavedInfo.inventory then
        RARELOAD.RestoreInventory(ply, SavedInfo)
        if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
            DebugLog(ply, "INFO", 0, "Using map-specific inventory (global inventory disabled)")
        end
        inventoryRestored = true
    end

    -- Restore advanced appearance (or fallback to legacy playermodel)
    local permVal = hasPerm("RETAIN_APPEARANCE")
    local setVal = RARELOAD.GetPlayerSetting(ply, "retainAppearance", true)
    local hasData = (SavedInfo.appearance ~= nil) or (SavedInfo.playermodel ~= nil)
    DebugLog(ply, "INFO", 0, "APPEARANCE RESTORE CHECK: hasPerm: " .. tostring(permVal) .. " | setting: " .. tostring(setVal) .. " | hasData: " .. tostring(hasData))
    
    if permVal and setVal then
        if hasData then
            timer.Simple(1, function()
                if not IsValid(ply) then return end
                
                local savedModel = (SavedInfo.appearance and SavedInfo.appearance.model) or SavedInfo.playermodel
                local beforeModel = ply:GetModel()
                DebugLog(ply, "INFO", 0, "APPEARANCE RESTORE: Attempting to restore model: " .. tostring(savedModel) .. " | Model before restore: " .. tostring(beforeModel))
                
                if SavedInfo.appearance and RARELOAD.RestoreAppearance then
                    RARELOAD.RestoreAppearance(ply, SavedInfo.appearance)
                else
                    ply:SetModel(SavedInfo.playermodel)
                    ply:SetupHands()
                end
                
                timer.Simple(0.1, function()
                    if IsValid(ply) then
                        DebugLog(ply, "INFO", 0, "APPEARANCE RESTORE RESULT: Actual model is now: " .. tostring(ply:GetModel()) .. " | Expected: " .. tostring(savedModel))
                    end
                end)
            end)
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
                    if primaryAmmoType >= 0 then
                        ply:SetAmmo(ammoData.primary, primaryAmmoType)
                    end
                    if secondaryAmmoType >= 0 then
                        ply:SetAmmo(ammoData.secondary, secondaryAmmoType)
                    end
                    if ammoData.clip1 and ammoData.clip1 >= 0 then
                        weapon:SetClip1(ammoData.clip1)
                    end
                    if ammoData.clip2 and ammoData.clip2 >= 0 then
                        weapon:SetClip2(ammoData.clip2)
                    end
                    if RARELOAD.Debug and RARELOAD.Debug.BufferClipRestore then
                        RARELOAD.Debug.BufferClipRestore(ammoData.clip1, ammoData.clip2, weapon)
                    end
                end
            end
            if RARELOAD.Debug and RARELOAD.Debug.FlushClipRestoreBuffer then
                RARELOAD.Debug.FlushClipRestoreBuffer()
            end
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
        RARELOAD.RestoreEntities(SavedInfo.pos, SavedInfo, ply)

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

    RestoreActiveWeapon(ply, SavedInfo, inventoryRestored, globalInventoryRestored)
end
