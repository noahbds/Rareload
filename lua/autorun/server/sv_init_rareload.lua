-- lua/autorun/server/init.lua

-- This Where the functions and variables are stored

-- Rareload is a Garry's Mod addon that allows players to respawn at their last saved position, camera orientation, and inventory.
RARELOAD = {}

RARELOAD.playerPositions = {}
RARELOAD.lastSavedTime = 0
ADDON_STATE_FILE_PATH = "rareload/addon_state.json"

-- The default settings for the addon (if the file does not exist, this will be the settings used)
function GetDefaultSettings()
    return {
        addonEnabled = true,
        spawnModeEnabled = true,
        autoSaveEnabled = false,
        retainInventory = false,
        nocustomrespawnatdeath = false,
        debugEnabled = false,
        useSpawnPointEntity = true,
    }
end

RARELOAD.settings = GetDefaultSettings()

-- This makes sure the folder where the data (data tied to a map and addon settings data) is stored exists
function EnsureFolderExists()
    local folderPath = "rareload"
    if not file.Exists(folderPath, "DATA") then
        file.CreateDir(folderPath)
    end
end

-- When this function is called, it will save the new addon settings to the addon state file
function SaveAddonState()
    local json = util.TableToJSON(RARELOAD.settings, true)
    local success, err = pcall(file.Write, ADDON_STATE_FILE_PATH, json)
    if not success then
        print("[RARELOAD] Failed to save addon state: " .. err)
    end

    -- If debug is enabled, print the JSON string to the console
    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Debug: " .. json)
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

-- Function to trace a line (duh)
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

-- Function to create a spawn point entity
function CreateSpawnPoint(ply, savedInfo)
    if not RARELOAD.settings.useSpawnPointEntity then
        return nil -- Do not create the entity if the setting is disabled
    end

    local spawnPoint = ents.Create("ent_rareload_spawnpoint")
    if not IsValid(spawnPoint) then return end

    spawnPoint:SetPos(savedInfo.pos)
    spawnPoint:Spawn()

    local function isValidSpawnPoint(ent)
        local pos = ent:GetPos()
        if pos.z < -10000 or not util.IsInWorld(pos) then
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
            return false
        end

        local waterTrace = util.TraceLine({
            start = pos,
            endpos = pos - Vector(0, 0, 1),
            mask = MASK_WATER
        })

        if waterTrace.Hit then
            return false
        end

        local groundTrace = util.TraceLine({
            start = pos,
            endpos = pos - Vector(0, 0, 50),
            mask = MASK_SOLID_BRUSHONLY
        })

        if not groundTrace.Hit then
            return false
        end

        return true
    end

    local function adjustSpawnPoint(ent)
        local pos = ent:GetPos()
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

                local checkPos = pos + Vector(x, y, z)
                ent:SetPos(checkPos)
                if isValidSpawnPoint(ent) then
                    return true
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

        return false
    end

    if not isValidSpawnPoint(spawnPoint) then
        if not adjustSpawnPoint(spawnPoint) then
            spawnPoint:Remove()
            return nil
        end
    end

    return spawnPoint
end

LoadAddonState()
