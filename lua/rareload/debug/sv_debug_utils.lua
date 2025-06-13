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

function GetTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

function FormatValue(val)
    if type(val) == "table" then
        local result = {}
        for k, v in pairs(val) do
            if type(v) == "table" then
                table.insert(result, k .. " = {table}")
            else
                table.insert(result, k .. " = " .. tostring(v))
            end
        end
        return "{ " .. table.concat(result, ", ") .. " }"
    elseif type(val) == "string" then
        return val
    else
        return tostring(val)
    end
end

function AngleToDetailedString(ang)
    if not ang then return "nil" end
    return string.format("Pitch: %.2f, Yaw: %.2f, Roll: %.2f", ang.p, ang.y, ang.r)
end

function VectorToDetailedString(vec)
    if not vec then return "nil" end
    return string.format("X: %.2f, Y: %.2f, Z: %.2f", vec.x, vec.y, vec.z)
end

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

local messageRateLimits = {}
local RATE_LIMIT_WINDOW = 60
local MAX_MESSAGES_PER_WINDOW = 10

function RARELOAD.Debug.ShouldLimitMessage(messageKey)
    local currentTime = CurTime()
    if not messageRateLimits[messageKey] then
        messageRateLimits[messageKey] = {
            count = 0,
            windowStart = currentTime
        }
    end
    local rateLimit = messageRateLimits[messageKey]
    if currentTime - rateLimit.windowStart > RATE_LIMIT_WINDOW then
        rateLimit.count = 1
        rateLimit.windowStart = currentTime
        return false
    end
    if rateLimit.count >= MAX_MESSAGES_PER_WINDOW then
        return true
    end
    rateLimit.count = rateLimit.count + 1
    return false
end

timer.Create("RARELOAD_CleanupRateLimits", 60, 0, function()
    local currentTime = CurTime()
    for key, data in pairs(messageRateLimits) do
        if currentTime - data.windowStart > RATE_LIMIT_WINDOW * 2 then
            messageRateLimits[key] = nil
        end
    end
end)

function RARELOAD.Debug.GetPlayerInfoString(ply)
    if not IsValid(ply) then return "Invalid Player" end
    return string.format("%s (%s) [%s]",
        ply:Nick(),
        ply:SteamID(),
        ply:IsSuperAdmin() and "SuperAdmin" or (ply:IsAdmin() and "Admin" or "Player")
    )
end

function RARELOAD.Debug.FormatPosition(pos, includeDistance)
    if not pos then return "No Position" end
    local result = string.format("%.1f, %.1f, %.1f", pos.x, pos.y, pos.z)
    if includeDistance and IsValid(LocalPlayer()) then
        local distance = pos:Distance(LocalPlayer():GetPos())
        result = result .. string.format(" (%.1fm away)", distance)
    end
    return result
end

local debugPerformance = {}

function RARELOAD.Debug.StartPerfTimer(operation)
    debugPerformance[operation] = SysTime()
end

function RARELOAD.Debug.EndPerfTimer(operation, warnThreshold)
    if not debugPerformance[operation] then return 0 end
    local elapsed = SysTime() - debugPerformance[operation]
    debugPerformance[operation] = nil
    warnThreshold = warnThreshold or 0.1
    if elapsed > warnThreshold then
        RARELOAD.Debug.Log("WARNING", "Performance Issue", {
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
    RARELOAD.Debug.Log("VERBOSE", "Memory Usage", memInfo)
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

function RARELOAD.Debug.LogNetworkMessage(messageName, direction, size, recipient)
    if not DEBUG_CONFIG.ENABLED() then return end
    local rateKey = "net_" .. messageName
    if RARELOAD.Debug.ShouldLimitMessage(rateKey) then return end
    local netInfo = {
        "Message: " .. messageName,
        "Direction: " .. direction,
        "Size: " .. (size or "Unknown") .. " bytes"
    }
    if recipient then
        table.insert(netInfo, "Recipient: " .. RARELOAD.Debug.GetPlayerInfoString(recipient))
    end
    RARELOAD.Debug.Log("VERBOSE", "Network Message", netInfo)
end

function RARELOAD.Debug.SafeCall(func, context, ...)
    local success, result = pcall(func, ...)
    if not success then
        RARELOAD.Debug.Log("ERROR", "Safe Call Failed", {
            "Context: " .. (context or "Unknown"),
            "Error: " .. tostring(result),
            "Function: " .. tostring(func)
        })
        return false, result
    end
    return true, result
end

function RARELOAD.Debug.DumpPlayerData(steamID)
    if not DEBUG_CONFIG.ENABLED() then return end
    local mapName = game.GetMap()
    local playerData = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
    if not playerData then
        print("[RARELOAD DEBUG] No data found for player: " .. steamID)
        return
    end
    print("[RARELOAD DEBUG] Player Data Dump for " .. steamID .. ":")
    print(TableToString(playerData))
end

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
        "RareloadReloadData", "CreatePlayerPhantom", "RemovePlayerPhantom"
    }
    for _, netString in ipairs(requiredNetStrings) do
        if not util.NetworkStringToID(netString) then
            table.insert(issues, "Network string not registered: " .. netString)
        end
    end
    if #issues == 0 then
        RARELOAD.Debug.Log("INFO", "System Health Check", { "All systems operational" })
    else
        RARELOAD.Debug.Log("ERROR", "System Health Check Failed", issues)
    end
    return #issues == 0
end

function RARELOAD.Debug.AntiStuck(header, messages, entity, logLevel)
    if not RARELOAD.settings or not RARELOAD.settings.debugEnabled then return end
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
    RARELOAD.Debug.Log(level, formattedHeader, messages or "", entity)
end
