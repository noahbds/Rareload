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
            cleanupMapAfterDeath = false,
            retainVehicles = false,       -- BROKEN
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
    RARELOAD.version = "3.6"
    ADDON_STATE_FILE_PATH = "rareload/addon_state.json"

    util.AddNetworkString("RareloadAntiStuckPriorities")
    util.AddNetworkString("SyncData")
    util.AddNetworkString("SyncPlayerPositions")
    util.AddNetworkString("SyncPlayerPositionsChunk")

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
                    if RARELOAD.Debug and RARELOAD.Debug.Write then
                        RARELOAD.Debug.Write("system", "VERBOSE", 0, "Loaded addon state")
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
                    if RARELOAD.Debug and RARELOAD.Debug.Write then
                        RARELOAD.Debug.Write("inventory", "VERBOSE", 0, "Loaded global inventory")
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

        if RARELOAD.Permissions.DEFS and RARELOAD.Permissions.DEFS[permName] then
            return RARELOAD.Permissions.DEFS[permName].default
        end

        return false
    end

    function SyncData(ply)
        net.Start("SyncData")
        net.WriteTable({
            settings = RARELOAD.settings,
        })
        net.Send(ply)
    end

    local SYNC_CHUNK_MAX_BYTES = 56000
    local syncTransferId = 0

    local function NextSyncTransferId()
        syncTransferId = syncTransferId + 1
        if syncTransferId > 2147483000 then
            syncTransferId = 1
        end
        return syncTransferId
    end

    local function SendPlayerPositionsChunked(mapName, playerPositions, ply, isDelta)
        local json = util.TableToJSON(playerPositions or {}, false)
        if not json then
            return false, "json_encode_failed"
        end

        local compressed = util.Compress(json)
        if not compressed then
            return false, "compress_failed"
        end

        local transferId = NextSyncTransferId()
        local totalBytes = #compressed
        local totalChunks = math.max(1, math.ceil(totalBytes / SYNC_CHUNK_MAX_BYTES))

        for chunkIndex = 1, totalChunks do
            local byteStart = (chunkIndex - 1) * SYNC_CHUNK_MAX_BYTES + 1
            local chunk = compressed:sub(byteStart, byteStart + SYNC_CHUNK_MAX_BYTES - 1)

            net.Start("SyncPlayerPositionsChunk")
            net.WriteString(mapName or "")
            net.WriteUInt(transferId, 32)
            net.WriteUInt(totalChunks, 16)
            net.WriteUInt(chunkIndex, 16)
            net.WriteBool(isDelta == true)
            net.WriteUInt(#chunk, 16)
            net.WriteData(chunk, #chunk)

            if IsValid(ply) then
                net.Send(ply)
            else
                net.Broadcast()
            end
        end

        return true
    end

    function SyncPlayerPositions(ply, steamIDFilter)
        local mapName = game.GetMap()
        local sourcePositions = RARELOAD.playerPositions[mapName] or {}
        local playerPositions = sourcePositions
        local isDelta = false

        if steamIDFilter then
            isDelta = true
            playerPositions = {}
            if sourcePositions[steamIDFilter] ~= nil then
                playerPositions[steamIDFilter] = sourcePositions[steamIDFilter]
            end
        end

        local ok = SendPlayerPositionsChunked(mapName, playerPositions, ply, isDelta)
        if ok then
            return
        end

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

    function RARELOAD.Initialize()
        print("[RARELOAD] Core system initialized")
    end
end
