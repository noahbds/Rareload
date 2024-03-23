---@diagnostic disable: undefined-global

-- lua/autorun/server/init.lua

concommand.Add("toggle_respawn_at_reload", function(ply)
    if not ply:IsSuperAdmin() then
        ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255 You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.addonEnabled = not RARELOAD.settings.addonEnabled

    local status = RARELOAD.settings.addonEnabled and "enabled" or "disabled"
    ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255Respawn at Reload addon is now " .. status)

    SaveAddonState()
end)

concommand.Add("toggle_spawn_mode", function(ply)
    if not ply:IsSuperAdmin() then
        ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255 You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.spawnModeEnabled = not RARELOAD.settings.spawnModeEnabled

    local status = RARELOAD.settings.spawnModeEnabled and "enabled" or "disabled"
    ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255 Spawn with saved move type is now " .. status)
    SaveAddonState()
end)

concommand.Add("toggle_auto_save", function(ply)
    if not ply:IsSuperAdmin() then
        ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255 You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.autoSaveEnabled = not RARELOAD.settings.autoSaveEnabled

    local status = RARELOAD.settings.autoSaveEnabled and "enabled" or "disabled"
    ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255 Auto-save position is now " .. status)
    SaveAddonState()
end)

concommand.Add("toggle_print_message", function(ply)
    if not ply:IsSuperAdmin() then
        ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255 You do not have permission to use this command.")
        return
    end

    RARELOAD.settings.printMessageEnabled = not RARELOAD.settings.printMessageEnabled

    local status = RARELOAD.settings.printMessageEnabled and "enabled" or "disabled"
    ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255 Print message is now " .. status)

    SaveAddonState()
end)

concommand.Add("save_position", function(ply, _, _)
    if not RARELOAD.settings.addonEnabled then
        ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255 The Respawn at Reload addon is currently disabled.")
        return
    end

    EnsureFolderExists()

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = ply:GetPos()
    local oldPos = RARELOAD.playerPositions[mapName][ply:SteamID()] and
        RARELOAD.playerPositions[mapName][ply:SteamID()].pos

    if oldPos and oldPos == newPos then
        return
    elseif oldPos then
        if not RARELOAD.settings.autoSaveEnabled then
            ply:ChatPrint(
                "\124\255\165\0[RARELOAD]\124\255\255\255 Overwriting your previously saved position and camera orientation.")
        end
    else
        if not RARELOAD.settings.autoSaveEnabled then
            ply:ChatPrint("\124\255\165\0[RARELOAD]\124\255\255\255 Saved your current position and camera orientation.")
        end
    end

    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = newPos,
        moveType = ply:GetMoveType(),
        ang = ply:EyeAngles()
    }

    if RARELOAD.settings.printMessageEnabled and RARELOAD.settings.autoSaveEnabled then
        ply:ChatPrint(
            "\124\255\165\0[RARELOAD]\124\255\255\255 Auto Save: Saved your current position and camera orientation.")
    end
end)

hook.Add("ShutDown", "SavePlayerPosition", function()
    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    local mapName = game.GetMap()
    file.Write("respawn_at_reload/player_positions_" .. mapName .. ".txt",
        util.TableToJSON(RARELOAD.playerPositions, true))
end)

hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    LoadAddonState()

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

    EnsureFolderExists()

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

    EnsureFolderExists()

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType()
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

            if not RARELOAD.settings.spawnModeEnabled and (wasInNoclip or wasFlying or wasOnLadder) then
                local traceResult = PerformTrace(savedInfo.pos, ply, MASK_SOLID_BRUSHONLY)

                if traceResult.Hit and traceResult.HitPos then
                    local waterTrace = PerformTrace(traceResult.HitPos, ply, MASK_WATER)

                    if waterTrace.Hit then
                        local foundPos = FindWalkableGround(traceResult.HitPos, ply)

                        if foundPos then
                            local propTrace = PerformTrace(foundPos, ply, MASK_PLAYERSOLID)

                            if propTrace.StartSolid then
                                print("Spawn position is inside a prop. Custom spawn prevented.")
                                return
                            end

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
                SetPlayerPositionAndMoveType(ply, savedInfo, savedMoveType)
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
            local currentPos = ply:GetPos()

            if not ply.lastSavedPosition or currentPos ~= ply.lastSavedPosition then
                RunConsoleCommand("save_position")
                RARELOAD.lastSavedTime = CurTime()
                ply.lastSavedPosition = currentPos

                if RARELOAD.settings.printMessageEnabled and RARELOAD.settings.autoSaveEnabled then
                    ply:ChatPrint(
                        "\124\255\165\0[RARELOAD]\124\255\255\255 Auto Save: Saved your current position and camera orientation.")
                end
            end
        end
    end
end)
