concommand.Add("rareload_toggle_debug", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] You must be an admin to toggle debug mode.")
        return
    end

    RARELOAD.settings.debugEnabled = not RARELOAD.settings.debugEnabled

    if SaveAddonState then
        SaveAddonState()
    end

    local status = RARELOAD.settings.debugEnabled and "enabled" or "disabled"
    local message = "[RARELOAD] Debug mode " .. status

    if IsValid(ply) then
        ply:ChatPrint(message)
    end

    print(message)

    if RARELOAD.settings.debugEnabled and RARELOAD.Debug.SystemHealthCheck then
        timer.Simple(0.1, function()
            RARELOAD.Debug.SystemHealthCheck()
        end)
    end

    if RARELOAD.Debug and RARELOAD.Debug.Log then
        RARELOAD.Debug.Log("INFO", "Debug Mode Toggled", {
            "New State: " .. status,
            "Toggled By: " .. (IsValid(ply) and RARELOAD.Debug.GetPlayerInfoString(ply) or "Server Console")
        })
    end
end)

concommand.Add("rareload_debug", function(ply, cmd, args)
    RunConsoleCommand("rareload_toggle_debug")
end)

concommand.Add("rareload_debug_toggle", function(ply, cmd, args)
    RunConsoleCommand("rareload_toggle_debug")
end)

concommand.Add("rareload_debug_level", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        ply:ChatPrint("[RARELOAD] You must be a super admin to change debug level.")
        return
    end

    if not args[1] then
        local currentLevel = RARELOAD.settings.debugLevel or "INFO"
        local message = "[RARELOAD] Current debug level: " .. currentLevel
        if IsValid(ply) then
            ply:ChatPrint(message)
        end
        print(message)
        return
    end

    local newLevel = string.upper(args[1])
    local validLevels = { "ERROR", "WARNING", "INFO", "VERBOSE" }

    if not table.HasValue(validLevels, newLevel) then
        local message = "[RARELOAD] Invalid debug level. Valid levels: " .. table.concat(validLevels, ", ")
        if IsValid(ply) then
            ply:ChatPrint(message)
        end
        print(message)
        return
    end

    RARELOAD.settings.debugLevel = newLevel

    if SaveAddonState then
        SaveAddonState()
    end

    local message = "[RARELOAD] Debug level set to: " .. newLevel
    if IsValid(ply) then
        ply:ChatPrint(message)
    end
    print(message)
end)

concommand.Add("rareload_debug_dump", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] You must be an admin to use debug dump.")
        return
    end

    if not RARELOAD.settings.debugEnabled then
        local message = "[RARELOAD] Debug mode must be enabled to use debug dump."
        if IsValid(ply) then
            ply:ChatPrint(message)
        end
        print(message)
        return
    end

    local steamID = args[1]
    if steamID then
        if RARELOAD.Debug.DumpPlayerData then
            RARELOAD.Debug.DumpPlayerData(steamID)
        end
    else
        if RARELOAD.Debug.SystemHealthCheck then
            RARELOAD.Debug.SystemHealthCheck()
        end

        if RARELOAD.Debug.LogMemoryUsage then
            RARELOAD.Debug.LogMemoryUsage("Manual Dump")
        end
    end
end)
