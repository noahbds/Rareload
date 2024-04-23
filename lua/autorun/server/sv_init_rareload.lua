-- lua/autorun/server/init.lua

-- Prefix all your variables and functions with the namespace
local RARELOAD = {}
RARELOAD.playerPositions = {}
RARELOAD.settings = {
    addonEnabled = true,
    spawnModeEnabled = true,
    autoSaveEnabled = false,
    printMessageEnabled = true,
}
RARELOAD.lastSavedTime = 0

local function ensureFolderExists()
    local folderPath = "respawn_at_reload"
    if not file.Exists(folderPath, "DATA") then
        file.CreateDir(folderPath)
    end
end

-- Function to load addon state from file
local function loadAddonState()
    local addonStateFilePath = "respawn_at_reload/addon_state.txt"
    RARELOAD.settings = {} -- Initialize settings table

    -- Check if the file exists
    if file.Exists(addonStateFilePath, "DATA") then
        local addonStateData = file.Read(addonStateFilePath, "DATA")
        local addonStateLines = string.Explode("\n", addonStateData)

        -- Assign addon settings from file data
        RARELOAD.settings.addonEnabled = addonStateLines[1] and addonStateLines[1]:lower() == "true"
        RARELOAD.settings.spawnModeEnabled = addonStateLines[2] and addonStateLines[2]:lower() == "true"
        RARELOAD.settings.autoSaveEnabled = addonStateLines[3] and addonStateLines[3]:lower() == "true"
        RARELOAD.settings.printMessageEnabled = addonStateLines[4] and addonStateLines[4]:lower() == "true"
    else
        -- If the file doesn't exist, create it with default values
        local addonStateData = "true\ntrue\nfalse\ntrue"
        file.Write(addonStateFilePath, addonStateData)

        -- Assign default settings
        RARELOAD.settings.addonEnabled = true
        RARELOAD.settings.spawnModeEnabled = true
        RARELOAD.settings.autoSaveEnabled = false
        RARELOAD.settings.printMessageEnabled = true
    end
end

-- Expose loadAddonState function globally or within the addon table
loadAddonState() -- Call the function to initialize settings

-- Include other necessary files
include("weapons/gmod_tool/stools/sv_respawn_at_reload_tool.lua")


local function saveAddonState()
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

concommand.Add("toggle_respawn_at_reload", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.addonEnabled = not RARELOAD.settings.addonEnabled

    local status = RARELOAD.settings.addonEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Respawn at Reload addon is now " .. status)

    -- Save the addon's enabled state to a file
    saveAddonState()
end)

concommand.Add("toggle_spawn_mode", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.spawnModeEnabled = not RARELOAD.settings.spawnModeEnabled

    local status = RARELOAD.settings.spawnModeEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Spawn with saved move type is now " .. status)
    -- Save the spawn mode preference to the addon state file
    saveAddonState()
end)

concommand.Add("toggle_auto_save", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.autoSaveEnabled = not RARELOAD.settings.autoSaveEnabled

    local status = RARELOAD.settings.autoSaveEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Auto-save position is now " .. status)
    -- Save the auto-save state to the addon state file
    saveAddonState()
end)

concommand.Add("toggle_print_message", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.printMessageEnabled = not RARELOAD.settings.printMessageEnabled

    local status = RARELOAD.settings.printMessageEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Print message is now " .. status)

    -- Save the print message state to the addon state file
    saveAddonState()
end)

concommand.Add("save_position", function(ply, _, _)
    if not RARELOAD.settings.addonEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE, "The Respawn at Reload addon is currently disabled.")
        return
    end

    ensureFolderExists() -- Ensure the folder exists before saving

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = ply:GetPos()
    local oldPos = RARELOAD.playerPositions[mapName][ply:SteamID()] and
        RARELOAD.playerPositions[mapName][ply:SteamID()].pos

    -- Check if a position is already saved for the player and if it has changed
    if oldPos and oldPos == newPos then
        return -- Don't save the position or print a message if the position hasn't changed
    elseif oldPos then
        if not RARELOAD.settings.autoSaveEnabled then
            ply:PrintMessage(HUD_PRINTCONSOLE, "Overwriting your previously saved position and camera orientation.")
        end
    else
        if not RARELOAD.settings.autoSaveEnabled then
            ply:PrintMessage(HUD_PRINTCONSOLE, "Saved your current position and camera orientation.")
        end
    end

    -- Overwrite or save the player's position, movement type, and camera orientation
    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = newPos,
        moveType = ply:GetMoveType(),
        ang = ply:EyeAngles() -- Save the player's view angles as an Angle
    }

    -- Print a message indicating that the position was saved due to auto-save
    if RARELOAD.settings.printMessageEnabled and RARELOAD.settings.autoSaveEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE, "Auto Save: Saved your current position and camera orientation.")
    end
end)

hook.Add("ShutDown", "SavePlayerPosition", function()
    if not RARELOAD.settings.addonEnabled then return end

    ensureFolderExists() -- Ensure the folder exists before saving

    local mapName = game.GetMap()
    file.Write("respawn_at_reload/player_positions_" .. mapName .. ".txt", util.TableToJSON(RARELOAD.playerPositions))
end)

hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    -- Load the addon state, spawn mode preference, and print message state from the file
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
    end

    if not RARELOAD.settings.addonEnabled then return end

    ensureFolderExists() -- Ensure the folder exists before loading

    local mapName = game.GetMap()
    local filePath = "respawn_at_reload/player_positions_" .. mapName .. ".txt"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            RARELOAD.playerPositions = util.JSONToTable(data)
        end
    end
end)

hook.Add("PlayerDisconnect", "SavePlayerPositionDisconnect", function(ply)
    if not RARELOAD.settings.addonEnabled then return end

    ensureFolderExists() -- Ensure the folder exists before saving

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType() -- Save the player's movement type
    }
end)

hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    if not RARELOAD.settings.addonEnabled then
        return false
    end

    local mapName = game.GetMap()
    local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()]

    if savedInfo then
        local wasInNoclip = savedInfo.moveType == MOVETYPE_NOCLIP
        local wasFlying = savedInfo.moveType == MOVETYPE_FLY or savedInfo.moveType == MOVETYPE_FLYGRAVITY
        local wasOnLadder = savedInfo.moveType == MOVETYPE_LADDER

        if savedInfo.moveType and isnumber(savedInfo.moveType) then
            local savedMoveType = tonumber(savedInfo.moveType) or MOVETYPE_WALK

            if not RARELOAD.settings.spawnModeEnabled then
                if wasInNoclip or wasFlying or wasOnLadder then
                    local traceStart = savedInfo.pos
                    local traceEnd = savedInfo.pos - Vector(0, 0, 10000)
                    local traceResult = util.TraceLine({
                        start = traceStart,
                        endpos = traceEnd,
                        filter = ply,
                        mask = MASK_SOLID_BRUSHONLY
                    })

                    if traceResult.Hit and traceResult.HitPos then
                        local waterTrace = util.TraceLine({
                            start = traceResult.HitPos,
                            endpos = traceResult.HitPos - Vector(0, 0, 100),
                            filter = ply,
                            mask = MASK_WATER
                        })

                        if waterTrace.Hit then
                            print("Player spawn position is underwater. Searching for walkable ground.")

                            -- Perform a spherical search around the initial spawn point
                            local radius = 2000 -- Increase the radius
                            local stepSize = 50 -- Reduce the step size
                            local foundPos = nil

                            for r = stepSize, radius, stepSize do
                                for theta = 0, 2 * math.pi, math.pi / 16 do -- Increase the resolution of the search
                                    for phi = 0, math.pi, math.pi / 16 do   -- Increase the resolution of the search
                                        local x = r * math.sin(phi) * math.cos(theta)
                                        local y = r * math.sin(phi) * math.sin(theta)
                                        local z = r * math.cos(phi)

                                        local checkPos = traceResult.HitPos + Vector(x, y, z)
                                        local checkTrace = util.TraceLine({
                                            start = checkPos,
                                            endpos = checkPos - Vector(0, 0, 100),
                                            filter = ply,
                                            mask = MASK_SOLID_BRUSHONLY
                                        })

                                        if checkTrace.Hit and not checkTrace.StartSolid then
                                            local checkWaterTrace = util.TraceLine({
                                                start = checkTrace.HitPos,
                                                endpos = checkTrace.HitPos - Vector(0, 0, 100),
                                                filter = ply,
                                                mask = MASK_WATER
                                            })

                                            if not checkWaterTrace.Hit then
                                                -- Add an offset to the found position to ensure the player is above the ground
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

                            if foundPos then
                                ply:SetPos(foundPos)
                                ply:SetMoveType(MOVETYPE_NONE)
                                print("Found walkable ground for player spawn.")
                                return
                            else
                                print("No walkable ground found. Custom spawn prevented.")
                                return
                            end
                        end

                        ply:SetPos(traceResult.HitPos)
                        ply:SetMoveType(MOVETYPE_NONE)
                    else
                        print("No walkable ground found. Custom spawn prevented.")
                        return
                    end
                else
                    ply:SetPos(savedInfo.pos)
                    local ang = Angle(savedInfo.ang[1], savedInfo.ang[2], savedInfo.ang[3])
                    ply:SetEyeAngles(ang)
                end
            else
                print("Setting move type to: " .. tostring(savedMoveType))
                timer.Simple(0, function() ply:SetMoveType(savedMoveType) end)
                ply:SetPos(savedInfo.pos)

                local ang = Angle(tonumber(savedInfo.ang[1]), tonumber(savedInfo.ang[2]), tonumber(savedInfo.ang[3]))
                ply:SetEyeAngles(ang)
            end
        else
            print("Error: Invalid saved move type.")
        end
    end
end)


hook.Add("PlayerPostThink", "AutoSavePosition", function(ply)
    if RARELOAD.settings.autoSaveEnabled and IsValid(ply) and ply:IsPlayer() and ply:Alive() then
        local vel = ply:GetVelocity():Length()

        if vel < 5 and CurTime() - RARELOAD.lastSavedTime > 1 then
            -- Player has stopped moving for at least 1 second, check if the position changed
            local currentPos = ply:GetPos()

            if not ply.lastSavedPosition or currentPos ~= ply.lastSavedPosition then
                -- Save their position only if it's different from the last saved position
                RunConsoleCommand("save_position")
                RARELOAD.lastSavedTime = CurTime() -- Update the last saved time
                ply.lastSavedPosition = currentPos

                if RARELOAD.settings.printMessageEnabled and RARELOAD.settings.autoSaveEnabled then
                    ply:PrintMessage(HUD_PRINTCONSOLE, "Auto Save: Saved your current position and camera orientation.")
                end
            end
        end
    end
end)
