util.AddNetworkString("RareloadDebugMessage")

MoveTypeNames = {
    [0] = "MOVETYPE_NONE",
    [1] = "MOVETYPE_ISOMETRIC",
    [2] = "MOVETYPE_WALK",
    [3] = "MOVETYPE_STEP",
    [4] = "MOVETYPE_FLY",
    [5] = "MOVETYPE_FLYGRAVITY",
    [6] = "MOVETYPE_VPHYSICS",
    [7] = "MOVETYPE_PUSH",
    [8] = "MOVETYPE_NOCLIP",
    [9] = "MOVETYPE_LADDER",
    [10] = "MOVETYPE_OBSERVER",
    [11] = "MOVETYPE_CUSTOM",
}

-- REMOVED: GetTimestamp() - use DEBUG_CONFIG.GetTimestamp() instead
-- REMOVED: FormatValue() - use RARELOAD.DataUtils.FormatValue() directly
-- REMOVED: AngleToDetailedString() - use RARELOAD.DataUtils.FormatAngleDetailed() directly
-- REMOVED: VectorToDetailedString() - use RARELOAD.DataUtils.FormatVectorDetailed() directly

function TableToString(tbl, indent)
    if not tbl then return "nil" end

    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    local result = {}

    for k, v in pairs(tbl) do
        local key = tostring(k)
        if type(v) == "table" then
            table.insert(result, indent_str .. key .. " = {")
            table.insert(result, TableToString(v, indent + 1))
            table.insert(result, indent_str .. "}")
        else
            table.insert(result, indent_str .. key .. " = " .. tostring(v))
        end
    end

    return table.concat(result, "\n")
end

function MoveTypeToString(moveType)
    return MoveTypeNames[moveType] or ("MOVETYPE_UNKNOWN (" .. tostring(moveType) .. ")")
end

-- REMOVED: Old rate limiting system
-- - messageRateLimits table
-- - ShouldLimitMessage() function
-- - RARELOAD_CleanupRateLimits timer
-- Use DEBUG_CONFIG.CheckRateLimit() instead for new code

function RARELOAD.Debug.GetPlayerInfoString(ply)
    if not IsValid(ply) then return "Invalid Player" end
    return string.format("%s (%s) [%s]",
        ply:Nick(),
        ply:SteamID(),
        ply:IsSuperAdmin() and "SuperAdmin" or (ply:IsAdmin() and "Admin" or "Player")
    )
end

function RARELOAD.Debug.FormatPosition(pos, includeDistance, ply)
    if not pos then return "No Position" end
    local result = string.format("%.1f, %.1f, %.1f", pos.x, pos.y, pos.z)
    if includeDistance and IsValid(ply) then
        local distance = pos:Distance(ply:GetPos())
        result = result .. string.format(" (%.1fm away)", distance)
    end
    return result
end

local debugPerformance = {}

local function WriteUtilityDebug(category, level, header, messages, context, entityFallback)
    if RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write(category or "system", level or "INFO", 0, tostring(header), context)

        if istable(messages) then
            local hadSequential = false
            for _, message in ipairs(messages) do
                hadSequential = true
                RARELOAD.Debug.Write(category or "system", level or "INFO", 1, tostring(message), context)
            end

            if not hadSequential then
                for key, value in pairs(messages) do
                    RARELOAD.Debug.Write(category or "system", level or "INFO", 1,
                        tostring(key) .. " = " .. tostring(value), context)
                end
            end
        elseif messages ~= nil and messages ~= "" then
            RARELOAD.Debug.Write(category or "system", level or "INFO", 1, tostring(messages), context)
        end

        return
    end

    print("[RARELOAD DEBUG] " .. tostring(header))
    if istable(messages) then
        for _, message in ipairs(messages) do
            print("[RARELOAD DEBUG] " .. tostring(message))
        end
    elseif messages ~= nil and messages ~= "" then
        print("[RARELOAD DEBUG] " .. tostring(messages))
    end
end

function RARELOAD.Debug.StartPerfTimer(operation)
    debugPerformance[operation] = SysTime()
end

function RARELOAD.Debug.EndPerfTimer(operation, warnThreshold)
    if not debugPerformance[operation] then return 0 end
    local elapsed = SysTime() - debugPerformance[operation]
    debugPerformance[operation] = nil
    warnThreshold = warnThreshold or 0.1
    if elapsed > warnThreshold then
        WriteUtilityDebug("system", "WARNING", "Performance Issue", {
            "Operation: " .. operation,
            "Time Taken: " .. string.format("%.3f seconds", elapsed),
            "Threshold: " .. string.format("%.3f seconds", warnThreshold)
        })
    end
    return elapsed
end

function RARELOAD.Debug.LogMemoryUsage(context)
    if not DEBUG_CONFIG.ENABLED() then return end
    local memInfo = {
        "Context: " .. (context or "Unknown"),
        "Lua Memory: " .. string.format("%.2f MB", collectgarbage("count") / 1024),
        "Player Positions Size: " .. table.Count(RARELOAD.playerPositions or {}),
        "Phantom Count: " .. table.Count(RARELOAD.Phantom or {}),
        "Global Inventory Size: " .. table.Count(RARELOAD.globalInventory or {})
    }
    WriteUtilityDebug("system", "VERBOSE", "Memory Usage", memInfo)
end

function RARELOAD.Debug.ValidateJsonFile(filePath)
    if not file.Exists(filePath, "DATA") then
        return false, "File does not exist"
    end
    local data = file.Read(filePath, "DATA")
    if not data or data == "" then
        return false, "File is empty"
    end
    local success, result = pcall(util.JSONToTable, data)
    if not success then
        return false, "Invalid JSON: " .. tostring(result)
    end
    return true, result
end

-- REMOVED: LogNetworkMessage() - use RARELOAD.Debug.Write() for network logging
-- REMOVED: SafeCall() - deprecated error wrapper, not used
-- REMOVED: DumpPlayerData() - use RARELOAD.Debug.Write() or LogMemoryUsage() instead

function RARELOAD.Debug.SystemHealthCheck()
    if not DEBUG_CONFIG.ENABLED() then return end
    local issues = {}
    if not RARELOAD.playerPositions then
        table.insert(issues, "RARELOAD.playerPositions is nil")
    end
    if not RARELOAD.settings then
        table.insert(issues, "RARELOAD.settings is nil")
    end
    local testFile = "rareload/health_check.txt"
    local success = pcall(file.Write, testFile, "test")
    if not success then
        table.insert(issues, "Cannot write to data folder")
    else
        file.Delete(testFile)
    end
    local requiredNetStrings = {
        "SyncData", "SyncPlayerPositions", "RareloadTeleportTo",
        "RareloadReloadData", "CreatePlayerPhantom", "RemovePlayerPhantom",
        "SyncPlayerPositionsChunk"
    }
    for _, netString in ipairs(requiredNetStrings) do
        if not util.NetworkStringToID(netString) then
            table.insert(issues, "Network string not registered: " .. netString)
        end
    end
    if #issues == 0 then
        WriteUtilityDebug("system", "INFO", "System Health Check", { "All systems operational" })
    else
        WriteUtilityDebug("system", "ERROR", "System Health Check Failed", issues)
    end
    return #issues == 0
end

function RARELOAD.Debug.AntiStuck(header, messages, entity, logLevel)
    if not (DEBUG_CONFIG and DEBUG_CONFIG.ENABLED and DEBUG_CONFIG.ENABLED({ entity = entity })) then return end
    if RARELOAD.Debug.LogAntiStuck then
        local methodName = nil
        if type(messages) == "table" and messages.methodName then
            methodName = messages.methodName
        end
        RARELOAD.Debug.LogAntiStuck(header, methodName, messages or {}, entity)
        return
    end
    local level = logLevel or "INFO"
    if not logLevel then
        if string.find(string.lower(tostring(header)), "error") then
            level = "ERROR"
        elseif string.find(string.lower(tostring(header)), "fail") or
            string.find(string.lower(tostring(header)), "invalid") or
            string.find(string.lower(tostring(header)), "warning") then
            level = "WARNING"
        end
    end
    local formattedHeader = "Anti-Stuck: " .. header
    local context = IsValid(entity) and { entity = entity } or nil
    WriteUtilityDebug("anti_stuck", level, formattedHeader, messages or "", context, entity)
end

function RARELOAD.Debug.SendToPlayer(ply, msg)
    if IsValid(ply) and ply:IsPlayer() then
        net.Start("RareloadDebugMessage")
        net.WriteString(msg)
        net.Send(ply)

        -- On dedicated servers there is no local client console, so keep a server copy.
        if game.IsDedicated() then
            print(msg)
        end
        return
    end

    print(msg)
end
