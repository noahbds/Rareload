-- lua/autorun/server/init.lua

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

-- Cache for walkable positions to avoid redundant checks
local walkableCache = {}

-- Check if the position is walkable
function IsWalkable(pos, ply)
    local cacheKey = tostring(pos)
    if walkableCache[cacheKey] ~= nil then
        return walkableCache[cacheKey]
    end

    local minHeight = -10000

    -- Check if the position is below the minimum height
    if pos.z < minHeight then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Position below map: ", pos, " - RED")
            debugoverlay.Sphere(pos, 10, 5, Color(255, 0, 0), true) -- Visualize in red
        end
        walkableCache[cacheKey] = false
        return false
    end

    -- Check if the position is within the world boundaries
    if not util.IsInWorld(pos) then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Position not in world: ", pos, " - RED")
            debugoverlay.Sphere(pos, 10, 5, Color(255, 0, 0), true) -- Visualize in red
        end
        walkableCache[cacheKey] = false
        return false
    end

    -- Combined trace for hull and ground
    local traceResult = util.TraceEntity({
        start = pos,
        endpos = pos - Vector(0, 0, 50),     -- Check for ground below
        filter = ply,
        mask = MASK_PLAYERSOLID + MASK_WATER -- Combine masks
    }, ply)

    -- Check if the position is blocked by a solid object or water
    if traceResult.Hit or traceResult.StartSolid or traceResult.HitWorld then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Position blocked or in water: ", pos, " - RED")
            debugoverlay.Line(pos, traceResult.HitPos, 5, Color(255, 0, 0), true) -- Visualize in red
        end
        walkableCache[cacheKey] = false
        return false
    end

    -- If all checks pass, the position is walkable
    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Position is walkable: ", pos, " - BLUE")
        debugoverlay.Sphere(pos, 10, 5, Color(0, 0, 255), true) -- Visualize in blue
    end

    walkableCache[cacheKey] = true
    return true, pos
end

-- Find walkable ground for the player to spawn on
function FindWalkableGround(startPos, ply)
    local radius = 2000
    local stepSize = 50
    local zStepSize = 50
    local maxAttempts = 1000
    local attempts = 0

    -- Grid-based search around the start position
    for z = 0, radius, zStepSize do
        for x = -radius, radius, stepSize do
            for y = -radius, radius, stepSize do
                local checkPos = startPos + Vector(x, y, z)
                local isWalkable, walkablePos = IsWalkable(checkPos, ply)
                if isWalkable then
                    return walkablePos
                end
                attempts = attempts + 1
                if attempts >= maxAttempts then
                    if RARELOAD.settings.debugEnabled then
                        print("[RARELOAD DEBUG] Max attempts reached, returning startPos")
                    end
                    return startPos -- Fallback to the original position
                end
            end
        end
    end

    return startPos -- Fallback to the original position
end

-- Set the player's position and eye angles
function SetPlayerPositionAndEyeAngles(ply, savedInfo)
    ply:SetPos(savedInfo.pos)

    -- Parse the angle data
    local angTable = type(savedInfo.ang) == "string" and util.JSONToTable(savedInfo.ang) or savedInfo.ang

    if type(angTable) == "table" and #angTable == 3 then
        ply:SetEyeAngles(Angle(angTable[1], angTable[2], angTable[3]))
    else
        print("[RARELOAD] Error: Invalid angle data.")
    end
end

-- Utility function to trace a line
function TraceLine(start, endpos, filter, mask)
    return util.TraceLine({
        start = start,
        endpos = endpos,
        filter = filter,
        mask = mask
    })
end

RARELOAD = RARELOAD or {}
RARELOAD.Phanthom = RARELOAD.Phanthom or {}




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
    local mapName = game.GetMap()
    net.Start("SyncData")
    net.WriteTable({
        playerPositions = RARELOAD.playerPositions[mapName] or {},
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
    local mapName = game.GetMap()
    net.Start("SyncPlayerPositions")
    net.WriteTable(RARELOAD.playerPositions[mapName] or {})
    net.Send(ply)
end

LoadAddonState()
