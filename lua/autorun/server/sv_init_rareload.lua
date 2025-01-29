-- lua/autorun/server/init.lua

RARELOAD = RARELOAD or {}
RARELOAD.Phanthom = RARELOAD.Phanthom or {}
MapName = game.GetMap()


-- Default settings for the addon if they don't exist
function GetDefaultSettings()
    return {
        addonEnabled = true,
        spawnModeEnabled = true,
        autoSaveEnabled = false,
        retainInventory = false,
        retainHealthArmor = false,  -- Beta [NOT TESTED]
        retainAmmo = false,         -- Beta [NOT TESTED]
        retainVehicleState = false, -- Beta [NOT TESTED]
        retainMapEntities = false,
        retainMapNPCs = false,
        nocustomrespawnatdeath = false,
        debugEnabled = false,
        autoSaveInterval = 5,
        angleTolerance = 100,
        maxDistance = 50
    }
end

-- Rareload is a Garry's Mod addon that allows players to respawn at their last saved position, camera orientation, and inventory.
RARELOAD = {}
RARELOAD.settings = GetDefaultSettings()
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.lastSavedTime = 0
ADDON_STATE_FILE_PATH = "rareload/addon_state.json"
local lastDebugTime = 0

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

    if RARELOAD.settings.debugEnabled then
        local currentTime = SysTime()
        if currentTime - lastDebugTime >= 5 then
            print("[RARELOAD DEBUG] Debug: " .. json)
            lastDebugTime = currentTime
        end
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
                print("[RARELOAD DEBUG] JSON data: " .. json)
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

------------------------------------------------------------------------------------------------
--[[ Optimized Anti-Stuck System for Player Spawning ]]
------------------------------------------------------------------------------------------------

local walkableCache = {}
local stuckPositions = {}
local lastKnownPositions = {}

local mapName = game.GetMap()
local cacheFilePath = "rareload/cached_position_" .. mapName .. ".json"
local MAX_CACHE_SIZE = 5000
local SAVE_INTERVAL = 300

-- Cleanup cache if it exceeds limit
local function PruneCache()
    if table.Count(walkableCache) <= MAX_CACHE_SIZE then return end

    print("[RARELOAD] Pruning cache...")

    local keys = {}
    for k in pairs(walkableCache) do table.insert(keys, k) end
    table.sort(keys)

    for i = 1, #keys - MAX_CACHE_SIZE do
        walkableCache[keys[i]] = nil
    end
end

-- Save cache to file
local function SaveWalkableCache()
    PruneCache()

    local cacheData = {
        map = mapName,
        positions = walkableCache,
        lastKnownPositions = lastKnownPositions
    }

    file.CreateDir("rareload")
    file.Write(cacheFilePath, util.TableToJSON(cacheData, true))
    print("[RARELOAD] Cached data saved.")
end

-- Load cache from file
local function LoadWalkableCache()
    if not file.Exists(cacheFilePath, "DATA") then
        print("[RARELOAD] No cache found. Starting fresh.")
        return
    end

    local jsonData = file.Read(cacheFilePath, "DATA")
    local decodedData = util.JSONToTable(jsonData)

    if decodedData and decodedData.map == mapName then
        walkableCache = decodedData.positions or {}
        lastKnownPositions = decodedData.lastKnownPositions or {}
        print("[RARELOAD] Loaded walkable position cache for map: " .. mapName)
    else
        print("[RARELOAD] Cache is outdated or corrupted. Resetting...")
        walkableCache, lastKnownPositions = {}, {}
        SaveWalkableCache()
    end
end

-- Check if position is walkable, using cache when possible
function IsWalkable(pos, ply)
    local cacheKey = string.format("%.2f,%.2f,%.2f", pos.x, pos.y, pos.z)

    if walkableCache[cacheKey] ~= nil then
        return walkableCache[cacheKey]
    end

    if stuckPositions[cacheKey] then
        return false
    end

    if pos.z < -10000 or not util.IsInWorld(pos) then
        stuckPositions[cacheKey] = true
        return false
    end

    local groundTrace = util.TraceHull({
        start = pos,
        endpos = pos - Vector(0, 0, 50),
        mins = ply:GetHullMins(),
        maxs = ply:GetHullMaxs(),
        filter = ply,
        mask = MASK_PLAYERSOLID
    })

    local waterTrace = util.TraceLine({
        start = pos,
        endpos = pos - Vector(0, 0, 50),
        filter = ply,
        mask = MASK_WATER
    })

    local isValid = not groundTrace.Hit and not groundTrace.StartSolid and not waterTrace.Hit
    walkableCache[cacheKey] = isValid

    if isValid then
        lastKnownPositions[ply:SteamID()] = pos
    else
        stuckPositions[cacheKey] = true
    end

    return isValid
end

-- Get the closest valid position from the cache
local function GetClosestValidCachedPos(targetPos)
    local closestPos = nil
    local closestDist = math.huge

    for _, pos in pairs(walkableCache) do
        local dist = targetPos:DistToSqr(pos)
        if dist < closestDist then
            closestDist = dist
            closestPos = pos
        end
    end

    return closestPos
end

-- Find the best spawn position
function FindBestSpawn(startPos, ply)
    -- Step 1: Only try closest valid cached if Step 1 failed
    local closestValidPos = GetClosestValidCachedPos(startPos)
    if closestValidPos and IsWalkable(closestValidPos, ply) then
        print("[RARELOAD] Using closest valid cached position.")
        return closestValidPos
    end

    -- Step 2: Limited area scan only if Steps 1 failed
    local bestPosition = nil
    local maxSearchRadius = 2000
    local stepSize = 100
    local zStepSize = 50
    local maxAttempts = 500
    local attempts = 0
    local angleStep = 30
    local currentRadius = 0
    local currentAngle = 0

    while currentRadius <= maxSearchRadius and attempts < maxAttempts do
        local x = math.cos(math.rad(currentAngle)) * currentRadius
        local y = math.sin(math.rad(currentAngle)) * currentRadius
        local checkPos = startPos + Vector(x, y, 0)

        for z = -50, 100, zStepSize do
            local finalPos = checkPos + Vector(0, 0, z)
            if IsWalkable(finalPos, ply) then
                print("[RARELOAD] Found valid position via scanning.")
                return finalPos
            end
            attempts = attempts + 1
        end

        currentAngle = currentAngle + angleStep
        if currentAngle >= 360 then
            currentAngle = 0
            currentRadius = currentRadius + stepSize
            stepSize = math.max(stepSize * 0.8, 10)
        end
    end

    -- Step 3: Try last known good position
    local lastGoodPos = lastKnownPositions[ply:SteamID()]
    if lastGoodPos and IsWalkable(lastGoodPos, ply) then
        print("[RARELOAD] Using last known good position.")
        return lastGoodPos
    end

    -- Step 4: Fallback only if all previous steps failed
    print("[RARELOAD] No valid position found, using original position as last resort.")
    return startPos
end

-- Set player's position and eye angles
function SetPlayerPositionAndEyeAngles(ply, savedInfo)
    ply:SetPos(savedInfo.pos)

    local angTable = type(savedInfo.ang) == "string" and util.JSONToTable(savedInfo.ang) or savedInfo.ang
    if type(angTable) == "table" and #angTable == 3 then
        ply:SetEyeAngles(Angle(angTable[1], angTable[2], angTable[3]))
    else
        print("[RARELOAD] Error: Invalid angle data.")
    end
end

-- Utility function for tracing lines
function TraceLine(start, endpos, filter, mask)
    return util.TraceLine({
        start = start,
        endpos = endpos,
        filter = filter,
        mask = mask
    })
end

-- Hooks and auto-save timer
hook.Add("ShutDown", "RARELOAD_SaveCache", SaveWalkableCache)
hook.Add("Initialize", "RARELOAD_LoadCache", LoadWalkableCache)
timer.Create("RARELOAD_AutoSaveCache", SAVE_INTERVAL, 0, SaveWalkableCache)

------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------

-- Create the player's phantom when debug mode is enabled, this allow to see the player's last saved position
---@class phantom : Entity
---@field isPhantom boolean

function CreatePlayerPhantom(ply)
    if RARELOAD.Phanthom and RARELOAD.Phanthom[ply:SteamID()] then
        local existingPhantom = RARELOAD.Phanthom[ply:SteamID()].phantom
        if IsValid(existingPhantom) then
            existingPhantom:Remove()
        end
        RARELOAD.Phanthom[ply:SteamID()] = nil

        net.Start("RemovePlayerPhantom")
        net.WriteEntity(ply)
        net.Broadcast()
    end

    timer.Simple(1, function()
        if not IsValid(ply) or not RARELOAD.settings.debugEnabled then return end

        local pos = ply:GetPos()
        if pos:WithinAABox(Vector(-16384, -16384, -16384), Vector(16384, 16384, 16384)) then
            if pos.z > -15000 then
                ---@type phantom
                ---@diagnostic disable-next-line: assign-type-mismatch
                local phantom = ents.Create("prop_physics")
                phantom:SetModel(ply:GetModel())
                phantom:SetPos(pos)
                phantom:SetAngles(ply:GetAngles())
                phantom.isPhantom = true
                phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
                phantom:SetColor(Color(255, 255, 255, 100))
                phantom:Spawn()

                phantom:SetMoveType(MOVETYPE_NONE)
                phantom:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

                RARELOAD.Phanthom[ply:SteamID()] = { phantom = phantom, ply = ply }

                net.Start("CreatePlayerPhantom")
                net.WriteEntity(ply)
                net.WriteVector(pos)
                net.WriteAngle(ply:GetAngles())
                net.Broadcast()
            else
                print("[RARELOAD DEBUG] Invalid Z position for phantom creation: ", pos)
            end
        else
            print("[RARELOAD DEBUG] Invalid position for phantom creation: ", pos)
        end
    end)
end

-- Hard to code function, probably a better way to do that
function Save_position(ply)
    RunConsoleCommand("save_position")
end

-- This convert the eye angle table to a a single line (used for the 3D2D frame)
function AngleToString(angle)
    return string.format("[%.2f, %.2f, %.2f]", angle[1], angle[2], angle[3])
end

-- This synchronize the data between the server and the client (used for the phantom)
function SyncData(ply)
    net.Start("SyncData")
    net.WriteTable({
        playerPositions = RARELOAD.playerPositions[MapName] or {},
        settings = RARELOAD.settings,
        Phanthom = RARELOAD.Phanthom
    })
    net.Send(ply)
end

-- This function only purpose is to print a message in the console when a setting is changed (and change the setting)
function ToggleSetting(ply, settingKey, message)
    if not ply:IsSuperAdmin() then
        print("[RARELOAD] You do not have permission to use this command.")
        return
    end

    RARELOAD.settings[settingKey] = not RARELOAD.settings[settingKey]

    local status = RARELOAD.settings[settingKey] and "enabled" or "disabled"
    print("[RARELOAD DEBUG]" .. message .. " is now " .. status)

    SaveAddonState()
end

-- I don't remember what this function does but it's probably important
function SyncPlayerPositions(ply)
    net.Start("SyncPlayerPositions")
    net.WriteTable(RARELOAD.playerPositions[MapName] or {})
    net.Send(ply)
end

LoadAddonState()
