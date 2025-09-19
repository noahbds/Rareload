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

    if DEBUG_CONFIG.LOG_TO_CONSOLE then
        MsgC(levelConfig.color, "\n[=====================================================================]\n")
        MsgC(levelConfig.color, fullHeader .. "\n")

        for _, message in ipairs(messages) do
            print(FormatMessage(message))
        end

        MsgC(levelConfig.color, "[=====================================================================]\n\n")
    end

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
    if not DEBUG_CONFIG.ENABLED() then
        return
    end

    if not DEBUG_CONFIG.LOG_TO_FILE then
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
        for i, entry in ipairs(logEntries) do
            logContent = logContent .. string.format("[%d] %s\n", i, tostring(entry))
        end
    end

    local success, size = WriteToLogFile(logFile, logContent)

    -- Only print to console if enabled
    if success and DEBUG_CONFIG.LOG_TO_CONSOLE then
        -- print("[RARELOAD] Log file written successfully. Size: " .. size .. " bytes")
    elseif not success then
        print("[RARELOAD ERROR] Failed to write log file: " .. logFile)
    end
end

function RARELOAD.Debug.LogGroup(title, level, logEntries)
    if not DEBUG_CONFIG.ENABLED() then return end

    level = level or DEBUG_CONFIG.DEFAULT_LEVEL
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]

    if DEBUG_CONFIG.LOG_TO_CONSOLE then
        MsgC(levelConfig.color,
            "\n[=====================================================================] " .. title .. "\n")

        if type(logEntries) == "table" then
            for i, entry in ipairs(logEntries) do
                print(string.format("[%d] %s", i, FormatMessage(entry)))
            end
        else
            print(FormatMessage(logEntries))
        end

        MsgC(levelConfig.color, "[=====================================================================]\n\n")
    end

    if DEBUG_CONFIG.LOG_TO_FILE then
        DEBUG_CONFIG.AddToLogBuffer(level, title, logEntries)
    end
end
