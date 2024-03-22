-- lua/autorun/server/init.lua

local playerPositions = {}
local addonEnabled = true        -- Initial state is enabled
local canPlayerSpawn = true      -- Variable to track if the player is allowed to spawn
local autoSaveEnabled = false
local printMessageEnabled = true -- Variable to track if messages should be printed
local lastSavedTime = 0          -- Variable to track the last time the position was saved


-- Vérifie si le dossier 'respawn_at_reload' existe, sinon le crée
if not file.Exists("respawn_at_reload", "DATA") then
    file.CreateDir("respawn_at_reload")
end

-- Vérifie si le fichier 'addon_state.txt' existe, sinon le crée et écrit 'true' dedans
if not file.Exists("respawn_at_reload/addon_state.txt", "DATA") then
    file.Write("respawn_at_reload/addon_state.txt", "true\ntrue\ntrue\ntrue")
end

-- Function to create the folder if it doesn't exist
local function EnsureFolderExists()
    local folderPath = "respawn_at_reload"
    if not file.Exists(folderPath, "DATA") then
        file.CreateDir(folderPath)
    end
end

concommand.Add("toggle_respawn_at_reload", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    addonEnabled = not addonEnabled

    local status = addonEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Respawn at Reload addon is now " .. status)

    -- Save the addon's enabled state to a file
    file.Write("respawn_at_reload/addon_state.txt", tostring(addonEnabled))
end)

concommand.Add("toggle_spawn_mode", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    spawnWithSavedMoveType = not spawnWithSavedMoveType

    local status = spawnWithSavedMoveType and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Spawn with saved move type is now " .. status)
    -- Save the spawn mode preference to the addon state file
    file.Write("respawn_at_reload/addon_state.txt", tostring(addonEnabled) .. "\n" .. tostring(spawnWithSavedMoveType))
end)

concommand.Add("toggle_auto_save", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    autoSaveEnabled = not autoSaveEnabled

    local status = autoSaveEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Auto-save position is now " .. status)
    -- Save the auto-save state to the addon state file
    file.Write("respawn_at_reload/addon_state.txt",
        tostring(addonEnabled) .. "\n" .. tostring(spawnWithSavedMoveType) .. "\n" .. tostring(autoSaveEnabled))
end)

concommand.Add("toggle_print_message", function(ply)
    if not ply:IsSuperAdmin() then
        ply:PrintMessage(HUD_PRINTCONSOLE, "You do not have permission to use this command.")
        return
    end

    printMessageEnabled = not printMessageEnabled

    local status = printMessageEnabled and "enabled" or "disabled"
    ply:PrintMessage(HUD_PRINTCONSOLE, "Print message is now " .. status)

    -- Save the print message state to the addon state file
    file.Write("respawn_at_reload/addon_state.txt",
        tostring(addonEnabled) ..
        "\n" ..
        tostring(spawnWithSavedMoveType) .. "\n" .. tostring(autoSaveEnabled) .. "\n" .. tostring(printMessageEnabled))
end)


concommand.Add("save_position", function(ply, _, _)
    if not addonEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE, "The Respawn at Reload addon is currently disabled.")
        return
    end

    EnsureFolderExists() -- Ensure the folder exists before saving

    local mapName = game.GetMap()
    playerPositions[mapName] = playerPositions[mapName] or {}

    local newPos = ply:GetPos()
    local oldPos = playerPositions[mapName][ply:SteamID()] and playerPositions[mapName][ply:SteamID()].pos

    -- Check if a position is already saved for the player and if it has changed
    if oldPos and oldPos == newPos then
        return -- Don't save the position or print a message if the position hasn't changed
    elseif oldPos then
        if not autoSaveEnabled then
            ply:PrintMessage(HUD_PRINTCONSOLE, "Overwriting your previously saved position and camera orientation.")
        end
    else
        if not autoSaveEnabled then
            ply:PrintMessage(HUD_PRINTCONSOLE, "Saved your current position and camera orientation.")
        end
    end

    -- Overwrite or save the player's position, movement type, and camera orientation
    playerPositions[mapName][ply:SteamID()] = {
        pos = newPos,
        moveType = ply:GetMoveType(),
        ang = ply:EyeAngles() -- Save the player's view angles as an Angle
    }

    -- Print a message indicating that the position was saved due to auto-save
    if printMessageEnabled and autoSaveEnabled then
        ply:PrintMessage(HUD_PRINTCONSOLE, "Auto Save: Saved your current position and camera orientation.")
    end
end)

hook.Add("ShutDown", "SavePlayerPosition", function()
    if not addonEnabled then return end

    EnsureFolderExists() -- Ensure the folder exists before saving

    local mapName = game.GetMap()
    file.Write("respawn_at_reload/player_positions_" .. mapName .. ".txt", util.TableToJSON(playerPositions))
end)

hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    -- Load the addon state, spawn mode preference, and print message state from the file
    local addonStateFilePath = "respawn_at_reload/addon_state.txt"
    if file.Exists(addonStateFilePath, "DATA") then
        local data = file.Read(addonStateFilePath, "DATA")
        local lines = string.Explode("\n", data)

        addonEnabled = lines[1] and lines[1]:lower() == "true"
        spawnWithSavedMoveType = lines[2] and lines[2]:lower() == "true"
        autoSaveEnabled = lines[3] and lines[3]:lower() == "true"
        printMessageEnabled = lines[4] and lines[4]:lower() == "true"
    end

    if printMessageEnabled then
        if not addonEnabled then
            print("Respawn at Reload addon is currently disabled.")
        end

        if spawnWithSavedMoveType then
            print("Spawn with saved move type is enabled.")
        else
            print("Spawn with saved move type is disabled.")
        end

        if autoSaveEnabled then
            print("Auto-save position is enabled.")
        else
            print("Auto-save position is disabled.")
        end

        if printMessageEnabled then
            print("Print message is enabled.")
        else
            print("Print message is disabled.")
        end
    end

    if not addonEnabled then return end

    EnsureFolderExists() -- Ensure the folder exists before loading

    local mapName = game.GetMap()
    local filePath = "respawn_at_reload/player_positions_" .. mapName .. ".txt"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            playerPositions = util.JSONToTable(data)
        end
    end
end)


hook.Add("PlayerDisconnect", "SavePlayerPositionDisconnect", function(ply)
    if not addonEnabled then return end

    EnsureFolderExists() -- Ensure the folder exists before saving

    local mapName = game.GetMap()
    playerPositions[mapName] = playerPositions[mapName] or {}
    playerPositions[mapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType() -- Save the player's movement type
    }
end)


hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    if not addonEnabled then
        -- If the addon is disabled, prevent the player from spawning
        canPlayerSpawn = false
        return
    end

    if not canPlayerSpawn then
        -- If the player is not allowed to spawn, return without executing custom spawn logic
        return
    end

    local mapName = game.GetMap()
    local savedInfo = playerPositions[mapName] and playerPositions[mapName][ply:SteamID()]

    if savedInfo then
        local wasInNoclip = savedInfo.moveType == 8.0
        local wasFlying = savedInfo.moveType == 4.0 or savedInfo.moveType == 5.0
        local wasOnLadder = savedInfo.moveType == 9.0

        -- Check if saved move type is valid before setting it
        if savedInfo.moveType and isnumber(savedInfo.moveType) then
            local savedMoveType = tonumber(savedInfo.moveType) or MOVETYPE_WALK

            if not spawnWithSavedMoveType then
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
                        -- Check if the spawn position is inside a wall
                        local traceHull = util.TraceHull({
                            start = traceResult.HitPos,
                            endpos = traceResult.HitPos,
                            mins = ply:OBBMins(),
                            maxs = ply:OBBMaxs(),
                            filter = ply,
                            mask = MASK_PLAYERSOLID
                        })

                        -- If the spawn position is inside a wall, move it a little bit further
                        while traceHull.StartSolid do
                            traceResult.HitPos = traceResult.HitPos + Vector(0, 0, 10)
                            traceHull = util.TraceHull({
                                start = traceResult.HitPos,
                                endpos = traceResult.HitPos,
                                mins = ply:OBBMins(),
                                maxs = ply:OBBMaxs(),
                                filter = ply,
                                mask = MASK_PLAYERSOLID
                            })
                        end

                        -- Check if the spawn position is inside a prop
                        local entities = ents.FindInBox(traceResult.HitPos + ply:OBBMins(),
                            traceResult.HitPos + ply:OBBMaxs())
                        while #entities > 0 do
                            traceResult.HitPos = traceResult.HitPos + Vector(0, 0, 10)
                            entities = ents.FindInBox(traceResult.HitPos + ply:OBBMins(),
                                traceResult.HitPos + ply:OBBMaxs())
                        end

                        ply:SetPos(traceResult.HitPos)
                        ply:SetMoveType(0.0) -- Set the move type to none
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

    canPlayerSpawn = false
end)


hook.Add("PlayerPostThink", "AutoSavePosition", function(ply)
    if autoSaveEnabled and IsValid(ply) and ply:IsPlayer() and ply:Alive() then
        local vel = ply:GetVelocity():Length()

        if vel < 5 and CurTime() - lastSavedTime > 1 then
            -- Player has stopped moving for at least 1 second, check if the position changed
            local currentPos = ply:GetPos()

            if not ply.lastSavedPosition or currentPos ~= ply.lastSavedPosition then
                -- Save their position only if it's different from the last saved position
                RunConsoleCommand("save_position")
                lastSavedTime = CurTime() -- Update the last saved time
                ply.lastSavedPosition = currentPos

                if printMessageEnabled and autoSaveEnabled then
                    ply:PrintMessage(HUD_PRINTCONSOLE, "Auto Save: Saved your current position and camera orientation.")
                end
            end
        end
    end
end)
