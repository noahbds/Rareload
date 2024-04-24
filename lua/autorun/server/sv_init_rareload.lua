-- lua/autorun/server/init.lua

-- RARELOAD Prefix
RARELOAD = {}

RARELOAD.playerPositions = {}

-- RARELOAD base settings
RARELOAD.settings = {
    addonEnabled = true,
    spawnModeEnabled = true,
    autoSaveEnabled = false,
    printMessageEnabled = true,
    retainInventory = false,
    disableCustomSpawnAtDeath = false,
}

RARELOAD.lastSavedTime = 0

-- Function to ensure the rareload folder exists
function EnsureFolderExists()
    local folderPath = "rareload"
    if not file.Exists(folderPath, "DATA") then
        file.CreateDir(folderPath)
    end
end

-- Function to load addon state from file
function LoadAddonState()
    local addonStateFilePath = "rareload/addon_state.txt"
    local defaultSettings = RARELOAD.settings

    if file.Exists(addonStateFilePath, "DATA") then
        local addonStateData = file.Read(addonStateFilePath, "DATA")
        local addonStateLines = string.Explode("\n", addonStateData)

        for key, defaultValue in pairs(defaultSettings) do
            local line = table.remove(addonStateLines, 1)
            RARELOAD.settings[key] = line and line:lower() == "true" or defaultValue
        end
    else
        local addonStateData = {}
        for key, value in pairs(defaultSettings) do
            table.insert(addonStateData, tostring(value))
        end
        file.Write(addonStateFilePath, table.concat(addonStateData, "\n"))
    end
end

LoadAddonState()

-- Function to save addon state to file
function SaveAddonState()
    local addonStateFilePath = "rareload/addon_state.txt"
    file.Write(addonStateFilePath,
        tostring(RARELOAD.settings.addonEnabled) ..
        "\n" ..
        tostring(RARELOAD.settings.spawnModeEnabled) ..
        "\n" ..
        tostring(RARELOAD.settings.autoSaveEnabled) ..
        "\n" ..
        tostring(RARELOAD.settings.printMessageEnabled) ..
        "\n" ..
        tostring(RARELOAD.settings.retainInventory)
    )
end

-- For Console Commands
function ToggleSetting(ply, settingName, message)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings[settingName] = not RARELOAD.settings[settingName]

    local status = RARELOAD.settings[settingName] and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, message .. " is now " .. status)

    SaveAddonState()
end

concommand.Add("toggle_rareload", function(ply)
    ToggleSetting(ply, "addonEnabled", "Rareload addon")
end)

concommand.Add("toggle_spawn_mode", function(ply)
    ToggleSetting(ply, "spawnModeEnabled", "Spawn with saved move type")
end)

concommand.Add("toggle_auto_save", function(ply)
    ToggleSetting(ply, "autoSaveEnabled", "Auto-save position")
end)

concommand.Add("toggle_print_message", function(ply)
    ToggleSetting(ply, "printMessageEnabled", "Print message")
end)

concommand.Add("toggle_retain_inventory", function(ply)
    ToggleSetting(ply, "retainInventory", "Retain inventory")
end)

-- Command to save the player's position
concommand.Add("save_position", function(ply, _, _)
    local settings = RARELOAD.settings
    local mapName = game.GetMap()
    local steamId = ply:SteamID()
    local playerPositions = RARELOAD.playerPositions
    playerPositions[mapName] = playerPositions[mapName] or {}
    local playerData = playerPositions[mapName][steamId] or {}

    if not settings.addonEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE, "Rareload addon is currently disabled.")
        return
    end

    EnsureFolderExists()

    local newPos = ply:GetPos()
    local oldPos = playerData.pos

    local function printPlayerMessage(message)
        if not settings.autoSaveEnabled then
            ply:PrintMessage(HUD_PRINTCONSOLE, message)
        end
    end

    if oldPos and oldPos == newPos then
        return
    elseif oldPos then
        printPlayerMessage("Overwriting your previously saved position, camera orientation, and inventory.")
    else
        printPlayerMessage("Saved your current position, camera orientation, and inventory.")
    end

    playerData.pos = newPos
    playerData.moveType = ply:GetMoveType()
    playerData.ang = ply:EyeAngles()

    if settings.retainInventory then
        local activeWeapon = ply:GetActiveWeapon()
        if IsValid(activeWeapon) then
            playerData.activeWeapon = activeWeapon:GetClass()
        end

        local inventory = {}
        for _, weapon in pairs(ply:GetWeapons()) do
            if weapon.GetClass then
                table.insert(inventory, weapon:GetClass())
            end
        end
        playerData.inventory = inventory
    end

    playerPositions[mapName][steamId] = playerData

    if settings.printMessageEnabled and settings.autoSaveEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE, "Auto Save: Saved your current position, camera orientation, and inventory.")
    end
end)


-- create a file if the mapname where to store the data
hook.Add("ShutDown", "SavePlayerPosition", function()
    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    local mapName = game.GetMap()
    file.Write("rareload/player_positions_" .. mapName .. ".txt", util.TableToJSON(RARELOAD.playerPositions))
end)

-- Check the map and if data is tied to it
hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    LoadAddonState()

    local settings = {
        { name = "addonEnabled",        message = "Rareload addon" },
        { name = "spawnModeEnabled",    message = "Spawn with saved move type" },
        { name = "autoSaveEnabled",     message = "Auto-save position" },
        { name = "printMessageEnabled", message = "Print message" },
        { name = "retainInventory",     message = "Retain inventory" }
    }

    if RARELOAD.settings.printMessageEnabled then
        for i, setting in ipairs(settings) do
            if RARELOAD.settings[setting.name] then
                print(setting.message .. " is enabled.")
            else
                print(setting.message .. " is disabled.")
            end
        end
    end

    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".txt"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            RARELOAD.playerPositions = util.JSONToTable(data)
        end
    end
end)

-- Save the player's position when they disconnect
hook.Add("PlayerDisconnect", "SavePlayerPositionDisconnect", function(ply)
    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType()
    }
end)

-- Define movement types enumeration
local MOVETYPE = {
    NOCLIP = 8,
    FLY = 4,
    FLYGRAVITY = 9,
    LADDER = 3,
    WALK = 2
}

-- Respawn the player at their saved position
hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    if not RARELOAD.settings.addonEnabled then
        return false
    end

    local mapName = game.GetMap()
    local savedInfo
    if RARELOAD.playerPositions[mapName] then
        savedInfo = RARELOAD.playerPositions[mapName][ply:SteamID()]
    end

    if not savedInfo then
        return
    end

    if RARELOAD.settings.disableCustomSpawnAtDeath then
        ply:StripWeapons()
        ply:Spawn()
        return
    end

    local savedMoveType = tonumber(savedInfo.moveType)

    if RARELOAD.settings.spawnModeEnabled then
        print("Setting move type to: " .. tostring(savedMoveType))
        timer.Simple(0, function() ply:SetMoveType(savedMoveType) end)
        SetPlayerPositionAndEyeAngles(ply, savedInfo)
    else
        local requiresWalkableGround = savedMoveType == MOVETYPE.NOCLIP or
            savedMoveType == MOVETYPE.FLY or
            savedMoveType == MOVETYPE.FLYGRAVITY or
            savedMoveType == MOVETYPE.LADDER

        if requiresWalkableGround then
            local foundPos = FindWalkableGround(savedInfo.pos, ply)

            if not foundPos then
                print("No walkable ground found. Custom spawn prevented.")
                return
            end

            ply:SetPos(foundPos)
            ply:SetMoveType(MOVETYPE.NONE)
            print("Found walkable ground for player spawn.")
        else
            SetPlayerPositionAndEyeAngles(ply, savedInfo)
        end
    end

    if RARELOAD.settings.retainInventory and savedInfo.inventory then
        ply:StripWeapons()

        for _, weaponClass in ipairs(savedInfo.inventory) do
            ply:Give(weaponClass)
        end

        if savedInfo.activeWeapon then
            timer.Simple(1, function()
                if IsValid(ply) and ply:HasWeapon(savedInfo.activeWeapon) then
                    ply:SelectWeapon(savedInfo.activeWeapon)
                end
            end)
        end
    end
end)

-- Function to trace a line
local function TraceLine(start, endpos, filter, mask)
    return util.TraceLine({
        start = start,
        endpos = endpos,
        filter = filter,
        mask = mask
    })
end

-- Helper function to check if a position is walkable
function IsWalkable(pos, ply)
    local checkTrace = TraceLine(pos, pos - Vector(0, 0, 100), ply, MASK_SOLID_BRUSHONLY)

    if checkTrace.Hit and not checkTrace.StartSolid and not util.PointContents(checkTrace.HitPos) == CONTENTS_WATER then
        return true, checkTrace.HitPos + Vector(0, 0, 10)
    end

    return false
end

-- Use the navmesh to find walkable ground
function FindWalkableGround(startPos, ply)
    local radius = 2000
    local stepSize = 50
    local maxAttempts = 100
    local nearestNav = navmesh.GetNearestNavArea(startPos)

    if nearestNav then
        for r = stepSize, radius, stepSize do
            for theta = 0, 2 * math.pi, math.pi / 16 do
                local x = r * math.cos(theta)
                local y = r * math.sin(theta)

                local checkPos = startPos + Vector(x, y, 0)
                local closestPoint = nearestNav:GetClosestPointOnArea(checkPos)
                local attempts = 0

                while closestPoint and nearestNav:IsBlocked(-2, false) and attempts < maxAttempts do
                    theta = theta + math.pi / 16
                    x = r * math.cos(theta)
                    y = r * math.sin(theta)

                    checkPos = startPos + Vector(x, y, 0)
                    closestPoint = nearestNav:GetClosestPointOnArea(checkPos)
                    attempts = attempts + 1
                end

                if attempts >= maxAttempts then
                    break
                end

                if closestPoint then
                    local isWalkable, walkablePos = IsWalkable(closestPoint, ply)

                    if isWalkable then
                        return walkablePos
                    end
                end
            end
        end
    end

    return FindWalkableGroundFallback(startPos, ply)
end

-- Original method for finding walkable ground
function FindWalkableGroundFallback(startPos, ply)
    local radius = 2000
    local stepSize = 50

    for r = stepSize, radius, stepSize do
        for theta = 0, 2 * math.pi, math.pi / 16 do
            for phi = 0, math.pi, math.pi / 16 do
                local x = r * math.sin(phi) * math.cos(theta)
                local y = r * math.sin(phi) * math.sin(theta)
                local z = r * math.cos(phi)

                local checkPos = startPos + Vector(x, y, z)
                local isWalkable, walkablePos = IsWalkable(checkPos, ply)

                if isWalkable then
                    return walkablePos
                end
            end
        end
    end

    error("Could not find walkable ground")
end

-- Set the player's position and eye angles
function SetPlayerPositionAndEyeAngles(ply, savedInfo)
    ply:SetPos(savedInfo.pos)
    local ang = Angle(savedInfo.ang[1], savedInfo.ang[2], savedInfo.ang[3])
    ply:SetEyeAngles(ang)
end

hook.Add("PlayerPostThink", "AutoSavePosition", function(ply)
    if not RARELOAD.settings.autoSaveEnabled then return end
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local vel = ply:GetVelocity():Length()
    if vel >= 5 or CurTime() - RARELOAD.lastSavedTime <= 1 then return end
    local currentPos = ply:GetPos()
    local currentWeaponCount = #ply:GetWeapons()
    local currentWeapons = {}
    for _, weapon in pairs(ply:GetWeapons()) do
        table.insert(currentWeapons, weapon:GetClass())
    end
    if ply.lastSavedPosition and currentPos == ply.lastSavedPosition and ply.lastSavedWeapons and table.concat(currentWeapons) == table.concat(ply.lastSavedWeapons) then return end
    RunConsoleCommand("save_position")
    RARELOAD.lastSavedTime = CurTime()
    ply.lastSavedPosition = currentPos
    ply.lastSavedWeapons = currentWeapons
    if RARELOAD.settings.printMessageEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE,
            "Auto Save: Saved your current position, camera orientation and weapon inventory.")
    end
end)
