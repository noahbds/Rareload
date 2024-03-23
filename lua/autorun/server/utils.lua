---@diagnostic disable: undefined-global

-- lua/autorun/server/utils.lua

RARELOAD = RARELOAD or {}

-- Store the player positions
RARELOAD.playerPositions = {}

-- Last time the positions was saved
RARELOAD.lastSavedTime = 0

function string:split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

-- Function to load addon state from file
function LoadAddonState()
    local addonStateFilePath = "respawn_at_reload/addon_state.txt"
    RARELOAD.settings = {}

    if file.Exists(addonStateFilePath, "DATA") then
        local addonStateData = file.Read(addonStateFilePath, "DATA")
        local addonStateLines = string.split(addonStateData, "\n")

        RARELOAD.settings.addonEnabled = addonStateLines[1] and addonStateLines[1]:lower() == "true"
        RARELOAD.settings.spawnModeEnabled = addonStateLines[2] and addonStateLines[2]:lower() == "true"
        RARELOAD.settings.autoSaveEnabled = addonStateLines[3] and addonStateLines[3]:lower() == "true"
        RARELOAD.settings.printMessageEnabled = addonStateLines[4] and addonStateLines[4]:lower() == "true"
    else
        local addonStateData = "true\ntrue\nfalse\ntrue"
        file.Write(addonStateFilePath, addonStateData)

        RARELOAD.settings.addonEnabled = true
        RARELOAD.settings.spawnModeEnabled = true
        RARELOAD.settings.autoSaveEnabled = false
        RARELOAD.settings.printMessageEnabled = true
    end
end

-- Function to ensure that the folder exists
function EnsureFolderExists()
    local folderPath = "respawn_at_reload"
    if not file.Exists(folderPath, "DATA") then
        file.CreateDir(folderPath)
    end
end

-- Function to save addon state to data file
function SaveAddonState()
    local addonStateFilePath = "respawn_at_reload/addon_state.txt"
    file.Write(addonStateFilePath,
        tostring(RARELOAD.settings.addonEnabled) ..
        "\n" ..
        tostring(RARELOAD.settings.spawnModeEnabled) ..
        "\n" ..
        tostring(RARELOAD.settings.autoSaveEnabled) ..
        "\n" ..
        tostring(RARELOAD.settings.printMessageEnabled)
    )
end

-- Function to check around the saved pos
function PerformTrace(startPos, ply, mask)
    return util.TraceLine({
        start = startPos,
        endpos = startPos - Vector(0, 0, 10000),
        filter = ply,
        mask = mask
    })
end

-- Function to check For walkable ground
function FindWalkableGround(startPos, ply)
    local radius = 2000
    local stepSize = 50
    local foundPos = nil

    for r = stepSize, radius, stepSize do
        for theta = 0, 2 * math.pi, math.pi / 16 do
            for phi = 0, math.pi, math.pi / 16 do
                local x = r * math.sin(phi) * math.cos(theta)
                local y = r * math.sin(phi) * math.sin(theta)
                local z = r * math.cos(phi)

                local checkPos = startPos + Vector(x, y, z)
                local checkTrace = performTrace(checkPos, ply, MASK_SOLID_BRUSHONLY)

                if checkTrace.Hit and not checkTrace.StartSolid then
                    local checkWaterTrace = performTrace(checkTrace.HitPos, ply, MASK_WATER)

                    if not checkWaterTrace.Hit then
                        foundPos = checkTrace.HitPos + Vector(0, 0, 10)
                        break
                    end
                end
            end

            if foundPos then
                break
            end
        end

        if foundPos then
            break
        end
    end

    return foundPos
end

-- Function to set player position and move type
function SetPlayerPositionAndMoveType(ply, savedInfo, savedMoveType)
    print("Setting move type to: " .. tostring(savedMoveType))
    timer.Simple(0, function() ply:SetMoveType(savedMoveType) end)
    ply:SetPos(savedInfo.pos)

    local ang = Angle(tonumber(savedInfo.ang[1]), tonumber(savedInfo.ang[2]), tonumber(savedInfo.ang[3]))
    ply:SetEyeAngles(ang)
end
