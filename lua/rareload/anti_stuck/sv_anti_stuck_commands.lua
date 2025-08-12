if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck
local PS = AntiStuck.ProfileSystem

concommand.Add("rareload_antistuck_stats", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] You must be an admin to use this command.")
        return
    end

    local stats = AntiStuck.GetMethodStats and AntiStuck.GetMethodStats() or {}
    print("[RARELOAD] Anti-Stuck Method Statistics:")
    print("==========================================")

    local sortedMethods = {}
    for name, stat in pairs(stats) do table.insert(sortedMethods, { name = name, stat = stat }) end
    table.sort(sortedMethods, function(a, b) return (a.stat.calls or 0) > (b.stat.calls or 0) end)

    for _, methodInfo in ipairs(sortedMethods) do
        local name = methodInfo.name
        local stat = methodInfo.stat
        local successRate = (stat.calls and stat.calls > 0) and (stat.successes / stat.calls * 100) or 0
        print(string.format("Method: %s", name))
        print(string.format("  Calls: %d | Successes: %d | Failures: %d", stat.calls or 0, stat.successes or 0,
            stat.failures or 0))
        print(string.format("  Success Rate: %.1f%% | Avg Time: %.3fs", successRate, stat.avgTime or 0))
        print(string.format("  Last Used: %s",
            (stat.lastUsed and stat.lastUsed > 0) and os.date("%H:%M:%S", stat.lastUsed) or "Never"))
        print("  ---")
    end
    if IsValid(ply) then ply:ChatPrint("[RARELOAD] Method statistics printed to console") end
end)

concommand.Add("rareload_antistuck_reset_stats", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] You must be an admin to use this command.")
        return
    end
    if AntiStuck.ResetMethodStats then AntiStuck.ResetMethodStats() end
    print("[RARELOAD] Method statistics reset")
    if IsValid(ply) then ply:ChatPrint("[RARELOAD] Method statistics reset") end
end)

concommand.Add("rareload_antistuck_methods", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] You must be an admin to use this command.")
        return
    end

    print("[RARELOAD] Registered Anti-Stuck Methods:")
    print("==========================================")

    if not AntiStuck.methodRegistry or table.Count(AntiStuck.methodRegistry) == 0 then
        print("No methods registered!")
        return
    end

    local sortedMethods = {}
    for name, methodObj in pairs(AntiStuck.methodRegistry) do table.insert(sortedMethods,
            { name = name, obj = methodObj }) end
    table.sort(sortedMethods, function(a, b) return a.obj.priority < b.obj.priority end)

    for _, methodInfo in ipairs(sortedMethods) do
        local name = methodInfo.name
        local obj = methodInfo.obj
        local stats = AntiStuck.methodStats and AntiStuck.methodStats[name] or {}
        print(string.format("Method: %s (Priority: %d)", name, obj.priority))
        print(string.format("  Description: %s", obj.description))
        print(string.format("  Enabled: %s | Timeout: %.1fs | Retries: %d", tostring(obj.enabled), obj.timeout,
            obj.retries))
        print(string.format("  Stats: %d calls, %d successes (%.1f%%)", stats.calls or 0, stats.successes or 0,
            (stats.calls and stats.calls > 0) and (stats.successes / stats.calls * 100) or 0))
        print("  ---")
    end
    if IsValid(ply) then ply:ChatPrint("[RARELOAD] Method list printed to console") end
end)

concommand.Add("rareload_server_fix_corrupted_profiles", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] You must be an admin to use this command.")
        return
    end

    PS.LoadCurrentProfile()
    PS.EnsureDefaultProfile()

    local profiles = {}
    local files = file.Find(PS.profilesDir .. "*.json", "DATA")
    for _, fileName in ipairs(files or {}) do
        local profileName = string.gsub(fileName, "%.json$", "")
        table.insert(profiles, profileName)
    end

    local fixedCount, errorCount = 0, 0
    for _, profileName in ipairs(profiles) do
        local profile = PS.LoadProfile(profileName)
        if profile then
            local isValid, err = PS.ValidateProfileData(profile)
            if not isValid then
                print("[RARELOAD] Fixing corrupted server profile: " .. profileName)
                print("[RARELOAD] Error was: " .. err)

                if profile.settings and type(profile.settings) == "table" then
                    local hasNumericKeys = false
                    for k, v in pairs(profile.settings) do
                        if type(k) == "number" and type(v) == "table" and v.func and v.name then
                            hasNumericKeys = true
                            break
                        end
                    end
                    if hasNumericKeys then
                        profile.methods = RareloadDeepCopyMethods(profile.settings)
                        profile.settings = RareloadDeepCopySettings(RARELOAD.AntiStuck.DefaultSettings or {})
                        local fileName = PS.profilesDir .. profileName .. ".json"
                        file.CreateDir(PS.profilesDir)
                        local ok = pcall(file.Write, fileName, util.TableToJSON(profile, true))
                        if ok then fixedCount = fixedCount + 1 else errorCount = errorCount + 1 end
                    end
                end
            end
        end
    end

    local message = "[RARELOAD] Server profile fix complete. Fixed: " .. fixedCount .. ", Errors: " .. errorCount
    print(message)
    if IsValid(ply) then ply:ChatPrint(message) end
end)

-- Testing commands
concommand.Add("rareload_antistuck_test_enable", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] Only admins can enable anti-stuck testing mode.")
        return
    end
    AntiStuck.testingMode = true
    local message =
    "[RARELOAD] Anti-stuck testing mode ENABLED globally. All respawns will trigger the anti-stuck system."
    print(message)
    if IsValid(ply) then ply:ChatPrint(message) end
    for _, p in ipairs(player.GetAll()) do if p:IsAdmin() then p:ChatPrint(
            "[RARELOAD] Anti-stuck testing mode is now ACTIVE.") end end
end)

concommand.Add("rareload_antistuck_test_disable", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] Only admins can disable anti-stuck testing mode.")
        return
    end
    AntiStuck.testingMode = false
    AntiStuck.testingPlayers = {}
    local message = "[RARELOAD] Anti-stuck testing mode DISABLED globally."
    print(message)
    if IsValid(ply) then ply:ChatPrint(message) end
    for _, p in ipairs(player.GetAll()) do if p:IsAdmin() then p:ChatPrint(
            "[RARELOAD] Anti-stuck testing mode is now INACTIVE.") end end
end)

concommand.Add("rareload_antistuck_test_player", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] Only admins can enable player-specific anti-stuck testing.")
        return
    end
    local targetName = args[1]
    local duration = tonumber(args[2]) or 300
    if not targetName then
        local message = "[RARELOAD] Usage: rareload_antistuck_test_player <player_name> [duration_seconds]"
        print(message)
        if IsValid(ply) then ply:ChatPrint(message) end
        return
    end
    local targetPlayer
    for _, p in ipairs(player.GetAll()) do if string.lower(p:Nick()):find(string.lower(targetName), 1, true) then
            targetPlayer = p
            break
        end end
    if not IsValid(targetPlayer) then
        local message = "[RARELOAD] Player '" .. targetName .. "' not found."
        print(message)
        if IsValid(ply) then ply:ChatPrint(message) end
        return
    end
    local steamID = (targetPlayer.SteamID and targetPlayer:SteamID()) or nil
    if steamID then AntiStuck.testingPlayers[steamID] = CurTime() + duration end
    local targetNameSafe = (targetPlayer.Nick and targetPlayer:Nick()) or tostring(targetPlayer)
    local message = string.format("[RARELOAD] Anti-stuck testing enabled for %s for %d seconds.", targetNameSafe,
        duration)
    print(message)
    if IsValid(ply) then ply:ChatPrint(message) end
    if IsValid(targetPlayer) and targetPlayer.ChatPrint then
        targetPlayer:ChatPrint(
        "[RARELOAD] Anti-stuck testing mode enabled for you. Your next respawn will trigger the anti-stuck system.")
    end
end)

concommand.Add("rareload_antistuck_test_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] Only admins can check anti-stuck testing status.")
        return
    end
    local message = "[RARELOAD] Anti-stuck testing status:"
    print(message)
    if IsValid(ply) then ply:ChatPrint(message) end
    local globalStatus = "Global testing mode: " .. (AntiStuck.testingMode and "ENABLED" or "DISABLED")
    print("  " .. globalStatus)
    if IsValid(ply) then ply:ChatPrint("  " .. globalStatus) end
    local activePlayerTests, currentTime = 0, CurTime()
    for steamID, expireTime in pairs(AntiStuck.testingPlayers) do
        if expireTime > currentTime then
            activePlayerTests = activePlayerTests + 1
            local targetPlayer = player.GetBySteamID(steamID)
            local playerName
            if IsValid(targetPlayer) then
                playerName = tostring(targetPlayer)
            else
                playerName = "Offline (" .. steamID .. ")"
            end
            local timeLeft = math.ceil(expireTime - currentTime)
            local playerStatus = string.format("  Player testing: %s (%d seconds left)", playerName, timeLeft)
            print(playerStatus)
            if IsValid(ply) then ply:ChatPrint(playerStatus) end
        end
    end
    if activePlayerTests == 0 then
        local noPlayerTests = "  No active player-specific testing"
        print(noPlayerTests)
        if IsValid(ply) then ply:ChatPrint(noPlayerTests) end
    end
end)
