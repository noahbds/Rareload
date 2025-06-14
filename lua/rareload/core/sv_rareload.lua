if SERVER then
    -- lua/autorun/server/sv_init_rareload.lua

    -- Default settings for the addon if they don't exist
    function GetDefaultSettings()
        return {
            addonEnabled = true,
            spawnModeEnabled = true,
            autoSaveEnabled = false,
            retainInventory = false,
            retainGlobalInventory = false,
            retainHealthArmor = false,
            retainAmmo = false,
            retainVehicleState = false, -- BROKEN
            retainMapEntities = false,
            retainMapNPCs = false,
            retainVehicles = false, -- BROKEN
            nocustomrespawnatdeath = false,
            debugEnabled = false,
            maxHistorySize = 10,
            autoSaveInterval = 5,
            angleTolerance = 100,
            maxDistance = 50
        }
    end

    -- Rareload is a Garry's Mod addon that allows players to respawn at their last saved position, camera orientation, and inventory.
    RARELOAD = RARELOAD or {}
    -- The Rareload settings are what the addon will use to determine how it behaves.
    RARELOAD.settings = GetDefaultSettings()
    RARELOAD.Phantom = RARELOAD.Phantom or {}
    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.globalInventory = RARELOAD.globalInventory or {}
    RARELOAD.lastSavedTime = 0
    MapName = game.GetMap()
    RARELOAD.version = "2.0.0" -- Update this when we make changes to the addon that are released
    ADDON_STATE_FILE_PATH = "rareload/addon_state.json"
    local lastDebugTime = 0

    util.AddNetworkString("SyncData")
    util.AddNetworkString("SyncPlayerPositions")
    util.AddNetworkString("RareloadOpenAntiStuckDebug")
    util.AddNetworkString("RareloadAntiStuckConfig")
    util.AddNetworkString("RareloadAntiStuckPriorities")
    util.AddNetworkString("RareloadRequestAntiStuckConfig")

    -- Function to ensure the rareload folder exists, if not create it
    function EnsureFolderExists()
        local folderPath = "rareload"
        if not file.Exists(folderPath, "DATA") then
            file.CreateDir(folderPath)
        end
    end

    -- Function to save addon state to file
    function SaveAddonState()
        local json = util.TableToJSON(RARELOAD.settings, true)
        local success, err = pcall(file.Write, ADDON_STATE_FILE_PATH, json)
        if not success then
            print("[RARELOAD] Failed to save addon state: " .. err)
        end
    end

    -- Function to load addon state from file
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

    -- Function to load global inventory from file
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

        return ply:IsAdmin()
    end

    ------------------------------------------------------------------------------------------------
    --[[ Anti-Stuck System for Player Spawning ]] --------------------------------------------------
    ------------------------------------------------------------------------------------------------

    -- Legacy function - now redirects to new anti-stuck system
    function IsWalkable(pos, ply)
        if not RARELOAD.AntiStuck then
            include("rareload/anti_stuck/sv_anti_stuck_init.lua")
        end

        local isStuck, reason = RARELOAD.AntiStuck.IsPositionStuck(pos, ply)
        return not isStuck, pos
    end

    -- Legacy function - now redirects to new anti-stuck system
    function FindWalkableGround(startPos, ply)
        if not RARELOAD.AntiStuck then
            include("rareload/anti_stuck/sv_anti_stuck_init.lua")
        end

        if RARELOAD.AntiStuck and RARELOAD.AntiStuck.Initialize and not RARELOAD.AntiStuck.Initialized then
            RARELOAD.AntiStuck.Initialize()
        end

        local safePos, success = RARELOAD.AntiStuck.ResolveStuckPosition(startPos, ply)
        return safePos
    end

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
            ply:SetPos(pos)

            if RARELOAD.SavePositionToCache then
                RARELOAD.SavePositionToCache(pos)
            end

            local angTable = type(savedInfo.ang) == "string" and util.JSONToTable(savedInfo.ang) or savedInfo.ang
            if type(angTable) == "table" and #angTable == 3 then
                ply:SetEyeAngles(Angle(angTable[1], angTable[2], angTable[3]))
            end

            return
        end

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Position is stuck (" .. stuckReason .. "), using anti-stuck system")
        end

        local safePos, success = RARELOAD.AntiStuck.ResolveStuckPosition(testPos, ply)

        if success then
            ply:SetPos(safePos)

            if RARELOAD.SavePositionToCache then
                RARELOAD.SavePositionToCache(safePos)
            end
        else
            ply:ChatPrint("[RARELOAD] Warning: Had to use emergency positioning due to stuck position.")
            ply:EmitSound("buttons/button10.wav")
            ply:SetPos(safePos)
        end

        local angTable = type(savedInfo.ang) == "string" and util.JSONToTable(savedInfo.ang) or savedInfo.ang
        if type(angTable) == "table" and #angTable == 3 then
            ply:SetEyeAngles(Angle(angTable[1], angTable[2], angTable[3]))
        else
            print("[RARELOAD] Error: Invalid angle data.")
        end
    end

    ------------------------------------------------------------------------------------------------
    --[[ End Of Anti-Stuck System for Player Spawning ]] -------------------------------------------
    ------------------------------------------------------------------------------------------------

    -- Hard to code function, probably a better way to do that
    function Save_position(ply)
        RunConsoleCommand("save_position")
    end

    -- This convert the eye angle table to a a single line (used for the 3D2D frame)
    function AngleToString(angle)
        return string.format("[%.2f, %.2f, %.2f]", angle[1], angle[2], angle[3])
    end

    function SyncData(ply)
        local playerPositions = RARELOAD.playerPositions[MapName] or {}
        local chunkSize = 100
        for i = 1, #playerPositions, chunkSize do
            local chunk = {}
            for j = i, math.min(i + chunkSize - 1, #playerPositions) do
                table.insert(chunk, playerPositions[j])
            end

            net.Start("SyncData")
            net.WriteTable({
                playerPositions = chunk,
                settings = RARELOAD.settings,
                Phantom = RARELOAD.Phantom
            })
            net.Send(ply)
        end
    end

    -- This function only purpose is to print a message in the console when a setting is changed (and change the setting)
    function ToggleSetting(ply, settingKey, message)
        if not RARELOAD.CheckPermission(ply, "RARELOAD_TOGGLE") then
            ply:ChatPrint("[RARELOAD] You don't have permission to toggle settings.")
            ply:EmitSound("buttons/button10.wav")
            return
        end

        RARELOAD.settings[settingKey] = not RARELOAD.settings[settingKey]

        local status = RARELOAD.settings[settingKey] and "enabled" or "disabled"
        print("[RARELOAD DEBUG]" .. message .. " is now " .. status)

        SaveAddonState()
    end

    -- I don't remember what this function does but it's probably important
    function SyncPlayerPositions(ply)
        local playerPositions = RARELOAD.playerPositions[MapName] or {}
        local chunkSize = 100

        for i = 1, #playerPositions, chunkSize do
            local chunk = {}
            for j = i, math.min(i + chunkSize - 1, #playerPositions) do
                table.insert(chunk, playerPositions[j])
            end

            net.Start("SyncPlayerPositions")
            net.WriteTable(chunk)
            net.Send(ply)
        end
    end

    LoadAddonState()
    LoadGlobalInventory()

    concommand.Add("rareload_open_antistuck_debug", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsAdmin() then
            if IsValid(ply) then
                ply:ChatPrint("[RARELOAD] You must be an admin to access debug features.")
            end
            return
        end

        net.Start("RareloadOpenAntiStuckDebug")
        net.Send(ply)

        ply:ConCommand("rareload_debug_antistuck")
    end)

    concommand.Add("rareload_debug_antistuck_server", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsAdmin() then
            if IsValid(ply) then
                ply:ChatPrint("[RARELOAD] You must be an admin to access debug features.")
            end
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
