-- Helper functions to reduce code duplication
local function FormatEntityInfo(entity)
    if not IsValid(entity) then return "" end

    if entity:IsPlayer() then
        return string.format(" | Player: %s (%s)", entity:Nick(), entity:SteamID())
    else
        return string.format(" | Entity: %s (%d)", entity:GetClass(), entity:EntIndex())
    end
end

local function FormatHeader(level, header, entity)
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]
    local timestamp = GetTimestamp()
    return string.format("[%s][RARELOAD %s] %s%s",
        timestamp, levelConfig.prefix, header, FormatEntityInfo(entity))
end

local function FormatMessage(message)
    if type(message) == "table" then
        return TableToString(message)
    else
        return tostring(message)
    end
end

local function EnsureLogFolder()
    if not file.Exists(DEBUG_CONFIG.LOG_FOLDER, "DATA") then
        file.CreateDir(DEBUG_CONFIG.LOG_FOLDER)
    end

    local testFile = DEBUG_CONFIG.LOG_FOLDER .. "write_test.txt"
    file.Write(testFile, "Test write")

    if not file.Exists(testFile, "DATA") then
        print("[RARELOAD] ERROR: Cannot write to logs folder! Falling back to root data folder.")
        DEBUG_CONFIG.LOG_FOLDER = ""
        return false
    else
        file.Delete(testFile)
        return true
    end
end

local function WriteToLogFile(logPath, content)
    if not file.Exists(logPath, "DATA") then
        file.Write(logPath, "")
    end

    file.Append(logPath, content)

    if file.Exists(logPath, "DATA") then
        local size = file.Size(logPath, "DATA")
        return true, size
    else
        return false, 0
    end
end

function RARELOAD.Debug.Log(level, header, messages, entity)
    if not DEBUG_CONFIG.ENABLED() then return end

    level = level or DEBUG_CONFIG.DEFAULT_LEVEL
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]

    messages = type(messages) == "table" and messages or { messages }

    local fullHeader = FormatHeader(level, header or "", entity)

    MsgC(levelConfig.color, "\n[=====================================================================]\n")
    MsgC(levelConfig.color, fullHeader .. "\n")

    for _, message in ipairs(messages) do
        print(FormatMessage(message))
    end

    MsgC(levelConfig.color, "[=====================================================================]\n\n")

    if DEBUG_CONFIG.LOG_TO_FILE then
        local logFile = DEBUG_CONFIG.LOG_FOLDER .. "rareload_" .. os.date("%Y-%m-%d_%H-%M") .. ".txt"
        local logContent = fullHeader .. "\n"

        for _, message in ipairs(messages) do
            logContent = logContent .. FormatMessage(message) .. "\n"
        end

        logContent = logContent .. "---------------------------------------------------------------------\n"
        WriteToLogFile(logFile, logContent)
    end
end

function RARELOAD.Debug.LogSquadFileOnly(title, level, logEntries)
    print("[RARELOAD] Squad logging attempt: " .. title)

    if not DEBUG_CONFIG.ENABLED() then
        print("[RARELOAD] Debug is disabled - aborting squad logging")
        return
    end

    if not DEBUG_CONFIG.LOG_TO_FILE then
        print("[RARELOAD] File logging is disabled - aborting squad logging")
        return
    end

    EnsureLogFolder()

    level = level or DEBUG_CONFIG.DEFAULT_LEVEL
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]

    local logFile = DEBUG_CONFIG.LOG_FOLDER .. "rareload_squads_" .. os.date("%Y-%m-%d_%H-%M") .. ".txt"
    local logContent = "[" .. GetTimestamp() .. "] " .. title .. "\n"

    if type(logEntries) ~= "table" or #logEntries == 0 then
        logContent = logContent .. "No entries provided\n"
    else
        for _, entry in ipairs(logEntries) do
            local fullHeader = FormatHeader(level, entry.header or "No header", entry.entity)
            logContent = logContent .. fullHeader .. "\n"

            local messages = entry.messages or {}
            for _, message in ipairs(messages) do
                logContent = logContent .. FormatMessage(message) .. "\n"
            end

            logContent = logContent .. "---------------------------------------------------------------------\n"
        end
    end

    print("[RARELOAD DEBUG] Attempting to write to: " .. logFile)
    local success, size = WriteToLogFile(logFile, logContent)

    if success then
        print("[RARELOAD] Log file written successfully. Size: " .. size .. " bytes")
    else
        print("[RARELOAD] ERROR: Failed to write log file!")

        local rootLogFile = "rareload_emergency_log.txt"
        local emergencySuccess = WriteToLogFile(rootLogFile, logContent)

        if emergencySuccess then
            print("[RARELOAD DEBUG] Emergency log file created in root data folder.")
        else
            print("[RARELOAD DEBUG] CRITICAL ERROR: Cannot write to file system at all!")
        end
    end
end

function RARELOAD.Debug.LogGroup(title, level, logEntries)
    if not DEBUG_CONFIG.ENABLED() then return end

    level = level or DEBUG_CONFIG.DEFAULT_LEVEL
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]

    MsgC(levelConfig.color, "\n[=====================================================================] " ..
        title .. " [=====================================================================]\n\n")

    for _, entry in ipairs(logEntries or {}) do
        local fullHeader = FormatHeader(level, entry.header or "", entry.entity)
        MsgC(levelConfig.color, fullHeader .. "\n")

        local messages = entry.messages or {}
        for _, message in ipairs(messages) do
            print(FormatMessage(message))
        end

        MsgC(levelConfig.color, "---------------------------------------------------------------------\n")
    end

    MsgC(levelConfig.color, "[=====================================================================]\n\n")

    if DEBUG_CONFIG.LOG_TO_FILE then
        local logFile = DEBUG_CONFIG.LOG_FOLDER .. "rareload_" .. os.date("%Y-%m-%d_%H-%M") .. ".txt"
        local logContent = "[" .. GetTimestamp() .. "] " .. title .. "\n"

        for _, entry in ipairs(logEntries or {}) do
            logContent = logContent .. (entry.header or "") .. "\n"

            local messages = entry.messages or {}
            for _, message in ipairs(messages) do
                logContent = logContent .. FormatMessage(message) .. "\n"
            end

            logContent = logContent .. "---------------------------------------------------------------------\n"
        end

        WriteToLogFile(logFile, logContent)
    end
end
