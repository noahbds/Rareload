-- lua/autorun/server/init.lua

-- Load the addon settings
local RARELOAD = {}
RARELOAD.playerPositions = {}
RARELOAD.settings = {
    addonEnabled = true,
    spawnModeEnabled = true,
    autoSaveEnabled = false,
    printMessageEnabled = true,
    retainInventory = false,
}
RARELOAD.lastSavedTime = 0

local function ensureFolderExists()
    local folderPath = "rareload"
    if not file.Exists(folderPath, "DATA") then
        file.CreateDir(folderPath)
    end
end

-- Function to load addon state from file
local function loadAddonState()
    local addonStateFilePath = "rareload/addon_state.txt"
    RARELOAD.settings = {}

    if file.Exists(addonStateFilePath, "DATA") then
        local addonStateData = file.Read(addonStateFilePath, "DATA")
        local addonStateLines = string.Explode("\n", addonStateData)

        RARELOAD.settings.addonEnabled = addonStateLines[1] and addonStateLines[1]:lower() == "true"
        RARELOAD.settings.spawnModeEnabled = addonStateLines[2] and addonStateLines[2]:lower() == "true"
        RARELOAD.settings.autoSaveEnabled = addonStateLines[3] and addonStateLines[3]:lower() == "true"
        RARELOAD.settings.printMessageEnabled = addonStateLines[4] and addonStateLines[4]:lower() == "true"
        RARELOAD.settings.retainInventory = addonStateLines[5] and addonStateLines[5]:lower() == "true"
    else
        local addonStateData = "true\ntrue\nfalse\ntrue\nfalse"
        file.Write(addonStateFilePath, addonStateData)

        RARELOAD.settings.addonEnabled = true
        RARELOAD.settings.spawnModeEnabled = true
        RARELOAD.settings.autoSaveEnabled = false
        RARELOAD.settings.printMessageEnabled = true
        RARELOAD.settings.retainInventory = false
    end
end

-- Load the addon state from the file
loadAddonState()

-- Function to save addon state to file
local function saveAddonState()
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

-- Command to toggle the addon's enabled state
concommand.Add("toggle_rareload", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.addonEnabled = not RARELOAD.settings.addonEnabled

    local status = RARELOAD.settings.addonEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Respawn at Reload addon is now " .. status)

    saveAddonState()
end)

-- Command to toggle the spawn mode preference
concommand.Add("toggle_spawn_mode", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.spawnModeEnabled = not RARELOAD.settings.spawnModeEnabled

    local status = RARELOAD.settings.spawnModeEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Spawn with saved move type is now " .. status)
    saveAddonState()
end)

-- Command to toggle the auto-save position
concommand.Add("toggle_auto_save", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.autoSaveEnabled = not RARELOAD.settings.autoSaveEnabled

    local status = RARELOAD.settings.autoSaveEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Auto-save position is now " .. status)
    saveAddonState()
end)

-- Command to toggle the print message in ingame console
concommand.Add("toggle_print_message", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.printMessageEnabled = not RARELOAD.settings.printMessageEnabled

    local status = RARELOAD.settings.printMessageEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Print message is now " .. status)

    saveAddonState()
end)

-- Command to toggle the retain inventory
concommand.Add("toggle_retain_inventory", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.retainInventory = not RARELOAD.settings.retainInventory

    local status = RARELOAD.settings.retainInventory and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Retain inventory is now " .. status)

    saveAddonState()
end)

concommand.Add("save_position", function(ply, _, _)
    if not RARELOAD.settings.addonEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE, "The Respawn at Reload addon is currently disabled.")
        return
    end

    ensureFolderExists()

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = ply:GetPos()
    local oldPos = RARELOAD.playerPositions[mapName][ply:SteamID()] and
        RARELOAD.playerPositions[mapName][ply:SteamID()].pos

    if oldPos and oldPos == newPos then
        return
    elseif oldPos then
        if not RARELOAD.settings.autoSaveEnabled then
            ply:PrintMessage(HUD_PRINTCONSOLE,
                "Overwriting your previously saved position, camera orientation, and inventory.")
        end
    else
        if not RARELOAD.settings.autoSaveEnabled then
            ply:PrintMessage(HUD_PRINTCONSOLE, "Saved your current position, camera orientation, and inventory.")
        end
    end

    local playerData = {
        pos = newPos,
        moveType = ply:GetMoveType(),
        ang = ply:EyeAngles()
    }

    if RARELOAD.settings.retainInventory then
        local activeWeapon = ply:GetActiveWeapon()
        if IsValid(activeWeapon) then
            playerData.activeWeapon = activeWeapon:GetClass()
        end

        RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData
    end

    if RARELOAD.settings.retainInventory then
        local inventory = {}
        for _, weapon in pairs(ply:GetWeapons()) do
            if weapon.GetClass then
                table.insert(inventory, weapon:GetClass())
            end
        end
        playerData.inventory = inventory
    end

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData

    if RARELOAD.settings.printMessageEnabled and RARELOAD.settings.autoSaveEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE, "Auto Save: Saved your current position, camera orientation, and inventory.")
    end
end)


-- create a file if the mapname where to store the data
hook.Add("ShutDown", "SavePlayerPosition", function()
    if not RARELOAD.settings.addonEnabled then return end

    ensureFolderExists()

    local mapName = game.GetMap()
    file.Write("rareload/player_positions_" .. mapName .. ".txt", util.TableToJSON(RARELOAD.playerPositions))
end)

-- Check the map and if data is tied to it
hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    loadAddonState()

    if RARELOAD.settings.printMessageEnabled then
        if not RARELOAD.settings.addonEnabled then
            print("Respawn at Reload addon is currently disabled.")
        end

        if RARELOAD.settings.spawnModeEnabled then
            print("Spawn with saved move type is enabled.")
        else
            print("Spawn with saved move type is disabled.")
        end

        if RARELOAD.settings.autoSaveEnabled then
            print("Auto-save position is enabled.")
        else
            print("Auto-save position is disabled.")
        end

        if RARELOAD.settings.printMessageEnabled then
            print("Print message is enabled.")
        else
            print("Print message is disabled.")
        end

        if RARELOAD.settings.retainInventory then
            print("Retain inventory is enabled.")
        else
            print("Retain inventory is disabled.")
        end
    end

    if not RARELOAD.settings.addonEnabled then return end

    ensureFolderExists()

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

    ensureFolderExists()

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType()
    }
end)

-- Respawn the player at their saved position
hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    if not RARELOAD.settings.addonEnabled then
        return false
    end

    local mapName = game.GetMap()
    local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()]

    if not savedInfo then
        return
    end

    local wasInNoclip = savedInfo.moveType == MOVETYPE_NOCLIP
    local wasFlying = savedInfo.moveType == MOVETYPE_FLY or savedInfo.moveType == MOVETYPE_FLYGRAVITY
    local wasOnLadder = savedInfo.moveType == MOVETYPE_LADDER

    if not savedInfo.moveType or not isnumber(savedInfo.moveType) then
        print("Error: Invalid saved move type.")
        return
    end

    local savedMoveType = tonumber(savedInfo.moveType) or MOVETYPE_WALK

    if not RARELOAD.settings.spawnModeEnabled then
        if wasInNoclip or wasFlying or wasOnLadder then
            local traceResult = TraceLine(savedInfo.pos, savedInfo.pos - Vector(0, 0, 10000), ply, MASK_SOLID_BRUSHONLY)

            if not traceResult.Hit or not traceResult.HitPos then
                print("No walkable ground found. Custom spawn prevented.")
                return
            end

            local waterTrace = TraceLine(traceResult.HitPos, traceResult.HitPos - Vector(0, 0, 100), ply, MASK_WATER)

            if waterTrace.Hit then
                local foundPos = FindWalkableGround(traceResult.HitPos, ply)

                if not foundPos then
                    print("No walkable ground found. Custom spawn prevented.")
                    return
                end

                ply:SetPos(foundPos)
                ply:SetMoveType(MOVETYPE_NONE)
                print("Found walkable ground for player spawn.")
                return
            end

            ply:SetPos(traceResult.HitPos)
            ply:SetMoveType(MOVETYPE_NONE)
        else
            SetPlayerPositionAndEyeAngles(ply, savedInfo)
        end
    else
        print("Setting move type to: " .. tostring(savedMoveType))
        timer.Simple(0, function() ply:SetMoveType(savedMoveType) end)
        SetPlayerPositionAndEyeAngles(ply, savedInfo)
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
function TraceLine(start, endpos, filter, mask)
    return util.TraceLine({
        start = start,
        endpos = endpos,
        filter = filter,
        mask = mask
    })
end

-- Helper function to check if a position is walkable
function IsWalkable(pos, ply)
    local checkTrace = util.TraceLine({
        start = pos,
        endpos = pos - Vector(0, 0, 100),
        filter = ply,
        mask =
            MASK_SOLID_BRUSHONLY
    })
    if checkTrace.Hit and not checkTrace.StartSolid then
        local checkWaterTrace = util.TraceLine({
            start = checkTrace.HitPos,
            endpos = checkTrace.HitPos -
                Vector(0, 0, 100),
            filter = ply,
            mask = MASK_WATER
        })
        if not checkWaterTrace.Hit then
            if util.PointContents(checkTrace.HitPos) == CONTENTS_EMPTY then
                return true, checkTrace.HitPos + Vector(0, 0, 10)
            end
        end
    end
    return false
end

-- Find walkable ground for the player to spawn on
function FindWalkableGround(startPos, ply)
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

function Save_position(ply)
    RunConsoleCommand("save_position")
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
    Save_position(ply)
    RARELOAD.lastSavedTime = CurTime()
    ply.lastSavedPosition = currentPos
    ply.lastSavedWeapons = currentWeapons
    if RARELOAD.settings.printMessageEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE,
            "Auto Save: Saved your current position, camera orientation and weapon inventory.")
    end
end)
