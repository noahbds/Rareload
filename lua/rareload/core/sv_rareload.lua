if SERVER then
    -- lua/autorun/server/sv_init_rareload.lua

    -- Default settings for the addon if they don't exist
    function GetDefaultSettings()
        return {
            addonEnabled = true,
            spawnModeEnabled = true,
            autoSaveEnabled = false,
            retainInventory = true,
            retainGlobalInventory = false,
            retainHealthArmor = true,
            retainPlayerStates = true,
            retainAmmo = true,
            retainVehicleState = false, -- BROKEN
            retainMapEntities = true,
            retainMapNPCs = true,
            retainVehicles = false, -- BROKEN
            nocustomrespawnatdeath = false,
            debugEnabled = false,
            maxHistorySize = 125,
            autoSaveInterval = 5,
            angleTolerance = 100,
            maxDistance = 50
        }
    end

    -- Rareload is a Garry's Mod addon that allows players to respawn at their last saved position, camera orientation, and inventory.
    RARELOAD = RARELOAD or {}
    RARELOAD.settings = GetDefaultSettings()
    RARELOAD.Phantom = RARELOAD.Phantom or {}
    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.globalInventory = RARELOAD.globalInventory or {}
    RARELOAD.lastSavedTime = 0
    RARELOAD.version = "3.1"
    ADDON_STATE_FILE_PATH = "rareload/addon_state.json"
    local lastDebugTime = 0

    util.AddNetworkString("RareloadOpenAntiStuckDebug")
    util.AddNetworkString("RareloadAntiStuckPriorities")

    function EnsureFolderExists()
        local folderPath = "rareload"
        if not file.Exists(folderPath, "DATA") then
            file.CreateDir(folderPath)
        end
    end

    function SaveAddonState()
        local json = util.TableToJSON(RARELOAD.settings, true)
        local success, err = pcall(file.Write, ADDON_STATE_FILE_PATH, json)
        if not success then
            print("[RARELOAD] Failed to save addon state: " .. err)
        end
    end
    
    RARELOAD.SaveAddonState = SaveAddonState

    function LoadAddonState()
        if file.Exists(ADDON_STATE_FILE_PATH, "DATA") then
            local json = file.Read(ADDON_STATE_FILE_PATH, "DATA")
            local success, settings = pcall(util.JSONToTable, json)
            if success then
                RARELOAD.settings = settings
                if RARELOAD.settings.debugEnabled then
                    if RARELOAD.Debug and RARELOAD.Debug.Log then
                        RARELOAD.Debug.Log("DEBUG", "Loaded Addon State", { json })
                    end
                end
            else
                print("[RARELOAD] Failed to save addon state: " .. settings)
                RARELOAD.settings = GetDefaultSettings()
                SaveAddonState()
            end
        else
            RARELOAD.settings = GetDefaultSettings()
            EnsureFolderExists()
            SaveAddonState()
        end
        
        -- Trigger hook to sync ConVars with loaded settings
        hook.Run("RareloadSettingsLoaded")
    end

    function SaveGlobalInventory()
        EnsureFolderExists()
        local globalInventoryData = {}

        for steamID, inventory in pairs(RARELOAD.globalInventory) do
            globalInventoryData[steamID] = inventory
        end

        local json = util.TableToJSON(globalInventoryData, true)
        local success, err = pcall(file.Write, "rareload/global_inventory.json", json)

        if not success then
            print("[RARELOAD] Failed to save global inventory: " .. err)
        elseif RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Global inventory saved successfully")
        end
    end

    function LoadGlobalInventory()
        EnsureFolderExists()

        if file.Exists("rareload/global_inventory.json", "DATA") then
            local json = file.Read("rareload/global_inventory.json", "DATA")
            local success, inventoryData = pcall(util.JSONToTable, json)

            if success and inventoryData then
                RARELOAD.globalInventory = inventoryData
                if RARELOAD.settings.debugEnabled then
                    if RARELOAD.Debug and RARELOAD.Debug.Log then
                        RARELOAD.Debug.Log("DEBUG", "Loaded Global Inventory", { json })
                    else
                        print("[RARELOAD DEBUG] Global inventory loaded successfully")
                    end
                end
            else
                print("[RARELOAD] Failed to load global inventory")
                RARELOAD.globalInventory = {}
            end
        else
            if RARELOAD.settings.debugEnabled then
                if not (RARELOAD.Debug and RARELOAD.Debug.Log) then
                    print("[RARELOAD DEBUG] No global inventory file found, creating new one")
                end
            end
            RARELOAD.globalInventory = {}
            SaveGlobalInventory()
        end
    end

    function RARELOAD.CheckPermission(ply, permName)
        if ply:IsSuperAdmin() then
            return true
        end

        if RARELOAD.Permissions.HasPermission then
            return RARELOAD.Permissions.HasPermission(ply, permName)
        end

        -- Fallback to permission defaults if HasPermission is not loaded yet
        if RARELOAD.Permissions.DEFS and RARELOAD.Permissions.DEFS[permName] then
            return RARELOAD.Permissions.DEFS[permName].default
        end

        return false
    end

    ------------------------------------------------------------------------------------------------
    --[[ Anti-Stuck System for Player Spawning ]] --------------------------------------------------
    ------------------------------------------------------------------------------------------------

    -- Function to use anti-stuck system
    function SetPlayerPositionAndEyeAngles(ply, savedInfo)
        if not RARELOAD.CheckPermission(ply, "RARELOAD_SPAWN") then
            ply:ChatPrint("[RARELOAD] You don't have permission to spawn with rareload.")
            ply:EmitSound("buttons/button10.wav")
            return
        end

        if RARELOAD.settings.debugEnabled and not RARELOAD.Debug then
            include("rareload/debug/sv_debug_config.lua")
            include("rareload/debug/sv_debug_utils.lua")
            include("rareload/debug/sv_debug_logging.lua")
            include("rareload/debug/sv_debug_specialized.lua")
        end

        if not RARELOAD.AntiStuck then
            include("rareload/anti_stuck/sv_anti_stuck_init.lua")
        end

        local isStuck = false
        local stuckReason = nil

        local testPos = savedInfo.pos
        if type(testPos) == "table" and testPos.x and testPos.y and testPos.z then
            testPos = Vector(testPos.x, testPos.y, testPos.z)
        end

        ---@diagnostic disable-next-line: missing-fields
        local simpleCheck = util.TraceHull({
            start = testPos + Vector(0, 0, 2),
            endpos = testPos + Vector(0, 0, 2),
            mins = ply:OBBMins(),
            maxs = ply:OBBMaxs(),
            filter = ply,
            mask = MASK_PLAYERSOLID
        })

        if simpleCheck.Hit or simpleCheck.StartSolid then
            isStuck, stuckReason = RARELOAD.AntiStuck.IsPositionStuck(testPos, ply)
        end

        if not isStuck then
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD] Position not stuck, using directly: " .. tostring(testPos))
            end

            local pos = savedInfo.pos
            if type(pos) == "table" and pos.x and pos.y and pos.z then
                pos = Vector(pos.x, pos.y, pos.z)
            end
            -- Ground and validate position before teleporting player
            if not util.IsInWorld(pos) then
                -- Try to recover by grounding near center
                local fallback = Vector(0, 0, 256)
                local tr = util.TraceLine({
                    start = fallback,
                    endpos = fallback - Vector(0, 0, 32768),
                    mask =
                        MASK_SOLID_BRUSHONLY
                })
                pos = (tr.Hit and tr.HitPos + Vector(0, 0, 16)) or fallback
            else
                -- Ground to nearest surface below to avoid inside-skybox Z
                local tr = util.TraceLine({
                    start = pos + Vector(0, 0, 64),
                    endpos = pos - Vector(0, 0, 32768),
                    mask =
                        MASK_SOLID_BRUSHONLY
                })
                if tr.Hit then pos = tr.HitPos + Vector(0, 0, 16) end
            end
            ply:SetPos(pos)

            if RARELOAD.SavePositionToCache then
                RARELOAD.SavePositionToCache(pos)
            end

            -- Parse and apply saved angle using centralized data utils with slight delay
            timer.Simple(0.05, function()
                if not IsValid(ply) then return end

                local parsedAngle = RARELOAD.DataUtils.ToAngle(savedInfo.ang)
                if parsedAngle then
                    ply:SetEyeAngles(parsedAngle)
                    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                        print("[RARELOAD] Applied saved angle: " .. tostring(parsedAngle))
                    end
                else
                    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                        print("[RARELOAD] Could not parse saved angle: " .. tostring(savedInfo.ang))
                    end
                end
            end)

            return
        end

        if RARELOAD.settings and RARELOAD.settings.debugEnabled and RARELOAD.Debug and RARELOAD.Debug.StartAntiStuckSession then
            RARELOAD.Debug.AntiStuck("IsPositionStuck", nil,
                { position = testPos, reason = stuckReason, methodName = "IsPositionStuck" }, ply)
        end

        local safePos, success = RARELOAD.AntiStuck.ResolveStuckPosition(testPos, ply)

        if success then
            if util.IsInWorld(safePos) then
                local tr = util.TraceLine({
                    start = safePos + Vector(0, 0, 64),
                    endpos = safePos - Vector(0, 0, 32768),
                    mask =
                        MASK_SOLID_BRUSHONLY
                })
                if tr.Hit then safePos = tr.HitPos + Vector(0, 0, 16) end
            end
            ply:SetPos(safePos)

            if RARELOAD.SavePositionToCache then
                RARELOAD.SavePositionToCache(safePos)
            end
        else
            ply:ChatPrint("[RARELOAD] Warning: Had to use emergency positioning due to stuck position.")
            ply:EmitSound("buttons/button10.wav")
            if util.IsInWorld(safePos) then
                local tr2 = util.TraceLine({
                    start = safePos + Vector(0, 0, 64),
                    endpos = safePos - Vector(0, 0, 32768),
                    mask =
                        MASK_SOLID_BRUSHONLY
                })
                if tr2.Hit then safePos = tr2.HitPos + Vector(0, 0, 16) end
            end
            ply:SetPos(safePos)
        end

        -- Parse and apply saved angle using centralized data utils with slight delay
        timer.Simple(0.05, function()
            if not IsValid(ply) then return end

            local parsedAngle = RARELOAD.DataUtils.ToAngle(savedInfo.ang)
            if parsedAngle then
                ply:SetEyeAngles(parsedAngle)
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    RARELOAD.Debug.Log("INFO", "Applied saved angle after anti-stuck", tostring(parsedAngle), ply)
                end
            else
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    RARELOAD.Debug.Log("WARNING", "Could not parse saved angle after anti-stuck", tostring(savedInfo.ang),
                        ply)
                end
            end
        end)
    end

    ------------------------------------------------------------------------------------------------
    --[[ End Of Anti-Stuck System for Player Spawning ]] -------------------------------------------
    ------------------------------------------------------------------------------------------------

    function Save_position(ply)
        if IsValid(ply) and RARELOAD.SaveRespawnPoint then
            RARELOAD.SaveRespawnPoint(ply, ply:GetPos(), ply:EyeAngles(), { whereMsg = "your location" })
        end
    end

    -- Convert eye angle table to string (used for 3D2D frame)
    function AngleToString(angle)
        return RARELOAD.DataUtils.FormatAngleCompact(angle)
    end

    function SyncData(ply)
        local mapName = game.GetMap()
        local playerPositions = RARELOAD.playerPositions[mapName] or {}

        net.Start("SyncData")
        net.WriteTable({
            playerPositions = playerPositions,
            settings = RARELOAD.settings,
        })
        net.Send(ply)
    end

    -- Sends the full map-keyed positions table to clients.
    function SyncPlayerPositions(ply)
        local mapName = game.GetMap()
        local playerPositions = RARELOAD.playerPositions[mapName] or {}

        net.Start("SyncPlayerPositions")
        net.WriteTable(playerPositions)
        if IsValid(ply) then
            net.Send(ply)
        else
            net.Broadcast()
        end
    end

    LoadAddonState()
    LoadGlobalInventory()

    concommand.Add("rareload_open_antistuck_debug", function(ply, cmd, args)
        if not IsValid(ply) then return end
        if not RARELOAD.Permissions.HasPermission or not RARELOAD.Permissions.HasPermission(ply, "DEBUG_MENU") then
            ply:ChatPrint("[RARELOAD] You don't have permission to access debug features.")
            return
        end

        net.Start("RareloadOpenAntiStuckDebug")
        net.Send(ply)

        ply:ConCommand("rareload_debug_antistuck")
    end)

    concommand.Add("rareload_debug_antistuck_server", function(ply, cmd, args)
        if not IsValid(ply) then return end
        if not RARELOAD.Permissions.HasPermission or not RARELOAD.Permissions.HasPermission(ply, "DEBUG_MENU") then
            ply:ChatPrint("[RARELOAD] You don't have permission to access debug features.")
            return
        end

        print("[RARELOAD] Admin " .. ply:Nick() .. " opened anti-stuck debug panel (via server command)")

        net.Start("RareloadOpenAntiStuckDebug")
        net.Send(ply)
    end)

    function RARELOAD.Initialize()
        print("[RARELOAD] Core system initialized")
    end
end
