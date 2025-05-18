-- Debug system configuration
DEBUG_CONFIG = {
    ENABLED = function() return RARELOAD.settings.debugEnabled end,
    LEVELS = {
        ERROR = { prefix = "ERROR", color = Color(255, 0, 0), value = 1 },
        WARNING = { prefix = "WARNING", color = Color(255, 165, 0), value = 2 },
        INFO = { prefix = "INFO", color = Color(0, 150, 255), value = 3 },
        VERBOSE = { prefix = "VERBOSE", color = Color(200, 200, 200), value = 4 }
    },
    DEFAULT_LEVEL = "INFO",
    LOG_TO_FILE = true,
    LOG_TO_CONSOLE = true,
    LOG_FOLDER = "rareload/logs/",
    MAX_LOG_FILES = 20,
    MAX_LOG_SIZE = 5 * 1024 * 1024, -- 5 MB
    MIN_LEVEL_TO_LOG = function() return RARELOAD.settings.debugLevel or "INFO" end,
    SESSION_ID = os.time(),
    TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S",
    AUTO_CLEANUP_LOGS_OLDER_THAN = 7 * 24 * 60 * 60, -- 7 days in seconds
    LOG_BUFFER_SIZE = 20,
    LOG_BUFFER_FLUSH_INTERVAL = 30,
    LOG_FORMAT = "TEXT",
    MAX_LOG_LINE_LENGTH = 1000,
    ROTATE_LOGS_BY_SIZE = true,
    LOG_FILE_PREFIX = "rareload_"
}

local currentDebugLevel = 3

local logBuffer = {}
local lastFlush = os.time()
local currentLogFile = nil
local currentLogSize = 0

local function UpdateDebugLevel()
    local levelName = DEBUG_CONFIG.MIN_LEVEL_TO_LOG()
    local levelConfig = DEBUG_CONFIG.LEVELS[levelName]
    if levelConfig then
        currentDebugLevel = levelConfig.value
    end
end

function DEBUG_CONFIG.ShouldLog(level)
    local levelConfig = DEBUG_CONFIG.LEVELS[level]
    return DEBUG_CONFIG.ENABLED() and levelConfig and levelConfig.value <= currentDebugLevel
end

function DEBUG_CONFIG.GetCurrentLevel()
    for name, config in pairs(DEBUG_CONFIG.LEVELS) do
        if config.value == currentDebugLevel then
            return name
        end
    end
    return DEBUG_CONFIG.DEFAULT_LEVEL
end

local function CleanupOldLogs()
    local files, _ = file.Find(DEBUG_CONFIG.LOG_FOLDER .. "*.txt", "DATA")

    local fileData = {}
    for _, fileName in ipairs(files) do
        local fullPath = DEBUG_CONFIG.LOG_FOLDER .. fileName
        local attributes = file.Time(fullPath, "DATA")
        table.insert(fileData, {
            name = fileName,
            path = fullPath,
            time = attributes
        })
    end

    table.sort(fileData, function(a, b) return a.time > b.time end)

    if #fileData > DEBUG_CONFIG.MAX_LOG_FILES then
        for i = DEBUG_CONFIG.MAX_LOG_FILES + 1, #fileData do
            print("[RARELOAD DEBUG] Removing old log file: " .. fileData[i].name)
            file.Delete(fileData[i].path)
        end
    end

    local cutoffTime = os.time() - DEBUG_CONFIG.AUTO_CLEANUP_LOGS_OLDER_THAN
    for _, fileInfo in ipairs(fileData) do
        if fileInfo.time < cutoffTime then
            print("[RARELOAD DEBUG] Removing outdated log file: " .. fileInfo.name)
            file.Delete(fileInfo.path)
        end
    end
end

local function FormatLogEntry(entry)
    if DEBUG_CONFIG.LOG_FORMAT == "JSON" then
        local json = {
            timestamp = entry.timestamp,
            level = entry.level,
            header = entry.header,
            message = entry.message
        }

        local jsonStr = "{"
        for k, v in pairs(json) do
            jsonStr = jsonStr .. string.format("\"%s\":\"%s\",", k, tostring(v):gsub("\"", "\\\""):gsub("\n", "\\n"))
        end
        jsonStr = jsonStr:sub(1, -2) .. "}"
        return jsonStr
    elseif DEBUG_CONFIG.LOG_FORMAT == "CSV" then
        local csvValues = {
            entry.timestamp,
            entry.level,
            entry.header:gsub(",", ";"),
            entry.message:gsub(",", ";"):gsub("\n", " ")
        }
        return table.concat(csvValues, ",")
    else
        return string.format("[%s][%s] %s\n%s\n",
            entry.timestamp,
            entry.level,
            entry.header,
            entry.message
        )
    end
end

local function TruncateString(str)
    if #str > DEBUG_CONFIG.MAX_LOG_LINE_LENGTH then
        return str:sub(1, DEBUG_CONFIG.MAX_LOG_LINE_LENGTH) .. "... [truncated]"
    end
    return str
end

local function GetLogFilePath()
    if not currentLogFile then
        currentLogFile = DEBUG_CONFIG.LOG_FOLDER .. DEBUG_CONFIG.LOG_FILE_PREFIX .. os.date("%Y-%m-%d_%H-%M") .. ".txt"

        if not file.Exists(currentLogFile, "DATA") then
            local header = ""
            if DEBUG_CONFIG.LOG_FORMAT == "CSV" then
                header = "Timestamp,Level,Header,Message\n"
            elseif DEBUG_CONFIG.LOG_FORMAT == "JSON" then
                header = "[\n"
            else
                header = string.format("[RARELOAD LOG] Started on %s - Map: %s - Session: %s\n%s\n",
                    os.date(DEBUG_CONFIG.TIMESTAMP_FORMAT),
                    game.GetMap(),
                    DEBUG_CONFIG.SESSION_ID,
                    string.rep("-", 80)
                )
            end
            file.Write(currentLogFile, header)
            currentLogSize = #header
        else
            currentLogSize = file.Size(currentLogFile, "DATA") or 0
        end
    end

    return currentLogFile
end

local function CheckLogRotation()
    if not DEBUG_CONFIG.ROTATE_LOGS_BY_SIZE then return false end

    if currentLogSize > DEBUG_CONFIG.MAX_LOG_SIZE then
        print("[RARELOAD DEBUG] Log file size limit reached (" ..
            math.floor(currentLogSize / 1024) .. " KB), rotating...")

        if DEBUG_CONFIG.LOG_FORMAT == "JSON" then
            if currentLogFile then
                file.Append(currentLogFile, "\n]")
            else
                print("[RARELOAD DEBUG] ERROR: Attempted to append to a nil log file.")
            end
        end

        currentLogFile = nil
        currentLogSize = 0
        return true
    end

    return false
end

local function FlushLogBuffer()
    if #logBuffer == 0 then return end

    local logFilePath = GetLogFilePath()
    local content = ""

    for _, entry in ipairs(logBuffer) do
        local formattedEntry = FormatLogEntry(entry)
        content = content .. formattedEntry

        if DEBUG_CONFIG.LOG_FORMAT == "JSON" and _ < #logBuffer then
            content = content .. ",\n"
        end
    end

    local success = pcall(function()
        file.Append(logFilePath, content)
    end)

    if not success then
        print("[RARELOAD DEBUG] ERROR: Failed to write to log file! Attempting recovery...")

        currentLogFile = DEBUG_CONFIG.LOG_FOLDER .. DEBUG_CONFIG.LOG_FILE_PREFIX ..
            "emergency_" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".txt"

        pcall(function()
            file.Write(currentLogFile, "EMERGENCY LOG - RECOVERY ATTEMPT\n\n" .. content)
        end)
    else
        currentLogSize = currentLogSize + #content
        CheckLogRotation()
    end

    table.Empty(logBuffer)
    lastFlush = os.time()
end

function DEBUG_CONFIG.AddToLogBuffer(level, header, message, entity)
    if not DEBUG_CONFIG.LOG_TO_FILE then return end

    local timestamp = os.date(DEBUG_CONFIG.TIMESTAMP_FORMAT)

    local entityInfo = ""
    if IsValid(entity) then
        if entity:IsPlayer() then
            entityInfo = " | Player: " .. entity:Nick() .. " (" .. entity:SteamID() .. ")"
        else
            entityInfo = " | Entity: " .. entity:GetClass() .. " (" .. entity:EntIndex() .. ")"
        end
    end

    local processedMessage = ""
    if type(message) == "table" then
        if DEBUG_CONFIG.LOG_FORMAT ~= "TEXT" then
            local entries = {}
            for k, v in pairs(message) do
                table.insert(entries, tostring(k) .. ": " .. tostring(v))
            end
            processedMessage = table.concat(entries, ", ")
        else
            processedMessage = TableToString(message)
        end
    else
        processedMessage = tostring(message)
    end

    processedMessage = TruncateString(processedMessage)

    table.insert(logBuffer, {
        timestamp = timestamp,
        level = level,
        header = header .. entityInfo,
        message = processedMessage
    })

    if #logBuffer >= DEBUG_CONFIG.LOG_BUFFER_SIZE or
        os.time() - lastFlush >= DEBUG_CONFIG.LOG_BUFFER_FLUSH_INTERVAL then
        FlushLogBuffer()
    end
end

timer.Create("RARELOAD_FlushLogBuffer", DEBUG_CONFIG.LOG_BUFFER_FLUSH_INTERVAL, 0, function()
    if #logBuffer > 0 then
        FlushLogBuffer()
    end
end)

hook.Add("ShutDown", "RARELOAD_FlushLogsOnShutdown", function()
    if #logBuffer > 0 then
        print("[RARELOAD DEBUG] Flushing " .. #logBuffer .. " log entries before shutdown")
        FlushLogBuffer()
    end

    if DEBUG_CONFIG.LOG_FORMAT == "JSON" and currentLogFile then
        file.Append(currentLogFile, "\n]")
    end
end)

local function InitDebugSystem()
    if DEBUG_CONFIG.LOG_TO_FILE then
        if not file.Exists(DEBUG_CONFIG.LOG_FOLDER, "DATA") then
            file.CreateDir(DEBUG_CONFIG.LOG_FOLDER)
        end

        CleanupOldLogs()
    end

    print("[RARELOAD DEBUG] Debug system initialized, Session ID: " .. DEBUG_CONFIG.SESSION_ID)
    print("[RARELOAD DEBUG] Log level set to: " .. DEBUG_CONFIG.GetCurrentLevel())
    print("[RARELOAD DEBUG] Log format: " .. DEBUG_CONFIG.LOG_FORMAT)

    DEBUG_CONFIG.AddToLogBuffer(
        "INFO",
        "Debug System Initialized",
        {
            version = RARELOAD.version or "Unknown",
            map = game.GetMap(),
            date = os.date("%Y-%m-%d_%H-%M"),
            sessionID = DEBUG_CONFIG.SESSION_ID,
            logLevel = DEBUG_CONFIG.GetCurrentLevel(),
            logFormat = DEBUG_CONFIG.LOG_FORMAT
        }
    )

    UpdateDebugLevel()
    FlushLogBuffer()
end

concommand.Add("rareload_debug_toggle", function(ply, cmd, args)
    if IsValid(ply) and not RARELOAD.Admin.HasPermission(ply, "debug_mode") then return end

    RARELOAD.settings.debugEnabled = not RARELOAD.settings.debugEnabled
    local status = RARELOAD.settings.debugEnabled and "enabled" or "disabled"
    print("[RARELOAD DEBUG] Debug system " .. status)

    if IsValid(ply) then
        ply:ChatPrint("[RARELOAD DEBUG] Debug system " .. status)
    end
end, nil, "Toggles the RARELOAD debug system on/off")

concommand.Add("rareload_debug_level", function(ply, cmd, args)
    if IsValid(ply) and not RARELOAD.Admin.HasPermission(ply, "debug_level") then return end

    local level = args[1] and string.upper(args[1])
    if level and DEBUG_CONFIG.LEVELS[level] then
        RARELOAD.settings.debugLevel = level
        UpdateDebugLevel()

        print("[RARELOAD DEBUG] Debug level set to: " .. level)
        if IsValid(ply) then
            ply:ChatPrint("[RARELOAD DEBUG] Debug level set to: " .. level)
        end
    else
        local availableLevels = {}
        for name, _ in pairs(DEBUG_CONFIG.LEVELS) do
            table.insert(availableLevels, name)
        end

        print("[RARELOAD DEBUG] Invalid debug level. Available levels: " .. table.concat(availableLevels, ", "))
        if IsValid(ply) then
            ply:ChatPrint("[RARELOAD DEBUG] Invalid debug level. Available levels: " ..
                table.concat(availableLevels, ", "))
        end
    end
end, nil, "Sets the debug level (ERROR, WARNING, INFO, VERBOSE)")

concommand.Add("rareload_debug_status", function(ply, cmd, args)
    if IsValid(ply) and not RARELOAD.Admin.HasPermission(ply, "debug_mode") then return end

    local status = {
        enabled = DEBUG_CONFIG.ENABLED(),
        level = DEBUG_CONFIG.GetCurrentLevel(),
        logToFile = DEBUG_CONFIG.LOG_TO_FILE,
        logToConsole = DEBUG_CONFIG.LOG_TO_CONSOLE,
        sessionID = DEBUG_CONFIG.SESSION_ID,
        logFolder = DEBUG_CONFIG.LOG_FOLDER
    }

    PrintTable(status)

    if IsValid(ply) then
        ply:ChatPrint("[RARELOAD DEBUG] Debug status: " .. (status.enabled and "Enabled" or "Disabled"))
        ply:ChatPrint("[RARELOAD DEBUG] Debug level: " .. status.level)
    end
end, nil, "Shows the current debug system status")

concommand.Add("rareload_debug_clean", function(ply, cmd, args)
    if IsValid(ply) and not RARELOAD.Admin.HasPermission(ply, "debug_clean") then return end

    CleanupOldLogs()
    print("[RARELOAD DEBUG] Log cleanup completed")

    if IsValid(ply) then
        ply:ChatPrint("[RARELOAD DEBUG] Log cleanup completed")
    end
end, nil, "Cleans up old log files")

concommand.Add("rareload_debug_format", function(ply, cmd, args)
    if IsValid(ply) and not RARELOAD.Admin.HasPermission(ply, "debug_format") then return end

    local format = args[1] and string.upper(args[1])
    local validFormats = { "TEXT", "JSON", "CSV" }

    if table.HasValue(validFormats, format) then
        FlushLogBuffer()

        if DEBUG_CONFIG.LOG_FORMAT == "JSON" and currentLogFile then
            file.Append(currentLogFile, "\n]")
        end

        DEBUG_CONFIG.LOG_FORMAT = format
        currentLogFile = nil

        print("[RARELOAD DEBUG] Log format set to: " .. format)
        if IsValid(ply) then
            ply:ChatPrint("[RARELOAD DEBUG] Log format set to: " .. format)
        end
    else
        print("[RARELOAD DEBUG] Invalid log format. Valid formats: " .. table.concat(validFormats, ", "))
        if IsValid(ply) then
            ply:ChatPrint("[RARELOAD DEBUG] Invalid log format. Valid formats: " .. table.concat(validFormats, ", "))
        end
    end
end, nil, "Sets the log format (TEXT, JSON, CSV)")

concommand.Add("rareload_debug_flush", function(ply, cmd, args)
    if IsValid(ply) and not RARELOAD.Admin.HasPermission(ply, "debug_mode") then return end

    local count = #logBuffer
    FlushLogBuffer()

    print("[RARELOAD DEBUG] Manually flushed " .. count .. " log entries")
    if IsValid(ply) then
        ply:ChatPrint("[RARELOAD DEBUG] Manually flushed " .. count .. " log entries")
    end
end, nil, "Forces the log buffer to flush to disk")

hook.Add("Initialize", "RARELOAD_InitDebugSystem", InitDebugSystem)
hook.Add("RARELOAD_SettingsLoaded", "RARELOAD_UpdateDebugLevel", UpdateDebugLevel)
