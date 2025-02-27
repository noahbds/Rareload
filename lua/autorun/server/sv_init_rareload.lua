-- lua/autorun/server/sv_init_rareload.lua

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
        retainVehicles = false,
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
RARELOAD.Phantom = RARELOAD.Phantom or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}
RARELOAD.lastSavedTime = 0
MapName = game.GetMap()
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
--[[ Anti-Stuck System for Player Spawning ]] --------------------------------------------------
------------------------------------------------------------------------------------------------

-- Check if the position is walkable (used by FindWalkableGround)
function IsWalkable(pos, ply)
    local minHeight = -10000

    if pos.z < minHeight then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Position below map: ", pos, " - RED")
        end
        return false
    end

    if not util.IsInWorld(pos) then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Position not in world: ", pos, " - RED")
        end
        return false
    end

    local hullTrace = util.TraceHull({
        start = pos,
        endpos = pos,
        mins = ply:OBBMins(),
        maxs = ply:OBBMaxs(),
        filter = ply,
        mask = MASK_PLAYERSOLID
    })

    if hullTrace.Hit or hullTrace.StartSolid then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Position blocked by solid object: ", pos, " - RED")
        end
        return false
    end

    local waterTrace = util.TraceLine({
        start = pos,
        endpos = pos - Vector(0, 0, 1),
        mask = MASK_WATER
    })

    if waterTrace.Hit then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Position in water: ", pos, " - RED")
        end
        return false
    end

    local groundTrace = util.TraceLine({
        start = pos,
        endpos = pos - Vector(0, 0, 50),
        mask = MASK_SOLID_BRUSHONLY
    })

    if not groundTrace.Hit then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] No ground found below position: ", pos, " - RED")
        end
        return false
    end

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Position is walkable: ", pos, " - BLUE")
    end

    return true, pos
end

-- Function purpose is in the name
function TraceLine(start, endpos, filter, mask)
    return util.TraceLine({
        start = start,
        endpos = endpos,
        filter = filter,
        mask = mask
    })
end

-- Find walkable ground for the player to spawn on (if togglemovetype is off)
function FindWalkableGround(startPos, ply)
    local radius = 2000
    local stepSize = 50
    local zStepSize = 50
    local angleStep = math.pi / 16

    for i = 1, 10 do
        local angle = 0
        local r = stepSize
        local z = 0
        while r < radius do
            local x = r * math.cos(angle)
            local y = r * math.sin(angle)

            local checkPos = startPos + Vector(x, y, z)
            local isWalkable, walkablePos = IsWalkable(checkPos, ply)
            if isWalkable then
                return walkablePos
            end

            angle = angle + angleStep
            if angle >= 2 * math.pi then
                angle = angle - 2 * math.pi
                r = r + stepSize
                z = z + zStepSize
            end
        end

        stepSize = stepSize + 50
    end

    return startPos
end

-- Set the player's position and eye angles
function SetPlayerPositionAndEyeAngles(ply, savedInfo)
    ply:SetPos(savedInfo.pos)

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

-- Create the player's phantom when debug mode is enabled, this allow to see the player's last saved position
---@class phantom : Entity
---@field isPhantom boolean

function CreatePlayerPhantom(ply)
    if RARELOAD.Phantom and RARELOAD.Phantom[ply:SteamID()] then
        local existingPhantom = RARELOAD.Phantom[ply:SteamID()].phantom
        if IsValid(existingPhantom) then
            existingPhantom:Remove()
        end
        RARELOAD.Phantom[ply:SteamID()] = nil

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

                RARELOAD.Phantom[ply:SteamID()] = { phantom = phantom, ply = ply }

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
