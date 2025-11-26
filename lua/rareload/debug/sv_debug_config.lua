RARELOAD = RARELOAD or {}
RARELOAD.Debug = RARELOAD.Debug or {}

-- [CRITICAL FIX] Maintain this global table for backward compatibility
DEBUG_CONFIG = {
    ENABLED = RARELOAD.Debug.IsEnabled,
    -- Map legacy levels to new shared levels
    LEVELS = RARELOAD.Debug.LEVELS,
    DEFAULT_LEVEL = "INFO",
    
    -- Settings
    LOG_TO_FILE = true,
    LOG_TO_CONSOLE = true,
    LOG_FOLDER = "rareload/logs/",
    MAX_LOG_FILES = 20,
    MAX_LOG_SIZE = 5 * 1024 * 1024,
    
    -- Session Data
    SESSION_ID = os.time(),
    TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S",
    LOG_BUFFER_SIZE = 20,
    LOG_BUFFER_FLUSH_INTERVAL = 30,
    LOG_FORMAT = "TEXT",
    
    -- Helpers
    MIN_LEVEL_TO_LOG = function() return RARELOAD.settings.debugLevel or "INFO" end
}

-- Buffer for file writing
DEBUG_CONFIG.LogBuffer = {}
DEBUG_CONFIG.LastFlush = os.time()

-- [Added] Helper to check if we should log based on level
function DEBUG_CONFIG.ShouldLog(levelName)
    if not DEBUG_CONFIG.ENABLED() then return false end
    local currentLevelVal = RARELOAD.Debug.GetLevel()
    local msgLevelVal = RARELOAD.Debug.LEVELS[levelName] and RARELOAD.Debug.LEVELS[levelName].value or 3
    return msgLevelVal <= currentLevelVal
end

-- Keep existing functionality
function DEBUG_CONFIG.AddToLogBuffer(level, header, message, entity)
    if not DEBUG_CONFIG.LOG_TO_FILE then return end
    
    table.insert(DEBUG_CONFIG.LogBuffer, {
        timestamp = os.date(DEBUG_CONFIG.TIMESTAMP_FORMAT),
        level = level,
        header = header,
        message = message,
        entity = entity
    })
    
    if #DEBUG_CONFIG.LogBuffer >= DEBUG_CONFIG.LOG_BUFFER_SIZE then
        RARELOAD.Debug.FlushLog()
    end
end