RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuck.ProfileSystem = RARELOAD.AntiStuck.ProfileSystem or {}
RARELOAD.AntiStuck.ProfileManager = RARELOAD.AntiStuck.ProfileManager or {}

local PROFILE_DIR = "rareload/anti_stuck_profiles/"
local CURRENT_PROFILE_FILE = "rareload/anti_stuck_current.json"
local DEFAULT_PROFILE_NAME = "default"
local PROFILE_VERSION = "1.3"
local CACHE_EXPIRE_TIME = 300 -- 5 minutes
local MAX_CACHE_SIZE = 50     -- Maximum cached profiles

-- Rareload Profile System that allow to manage the anti-stuck system (for now, maybe I will make the profile system global later)
RARELOAD.AntiStuck.ProfileSystem = {
    -- Core state
    _initialized = false,
    _currentProfile = nil,
    _isLoading = false,
    _operationLock = false,
    _pendingOperations = {},

    -- Smart caching system
    _cache = {
        profiles = {},
        metadata = {},
        lastUpdate = 0,
        size = 0
    },

    -- Event system
    _events = {
        onProfileChanged = {},
        onProfileLoaded = {},
        onProfileSaved = {},
        onProfileDeleted = {},
        onCacheUpdated = {}
    },

    -- Performance tracking
    _stats = {
        cacheHits = 0,
        cacheMisses = 0,
        loadOperations = 0,
        saveOperations = 0,
        totalLoadTime = 0,
        averageLoadTime = 0
    },

    -- Operation queue for batch processing
    _operationQueue = {},
    _processingQueue = false,

    -- Validation cache
    _validationCache = {},
    _lastValidation = 0,

    -- Cleanup tracking
    _timers = {},
    _eventHandlers = {}
}

-- Utility functions
local function SafeJSONDecode(str)
    if not str or str == "" then return nil end
    local success, result = pcall(util.JSONToTable, str)
    if not success then
        print("[ProfileSystem] JSON decode error:", result)
        return nil
    end
    return result
end

local function SafeJSONEncode(tbl)
    if not tbl then return "" end
    local success, result = pcall(util.TableToJSON, tbl, true)
    if not success then
        print("[ProfileSystem] JSON encode error:", result)
        return ""
    end
    return result
end

local function EnsureDirectoryExists()
    if not file.Exists(PROFILE_DIR, "DATA") then
        local success = pcall(file.CreateDir, PROFILE_DIR)
        if not success then
            print("[ProfileSystem] Failed to create profile directory")
            return false
        end
    end
    return true
end

-- Thread-safe operation wrapper
local function ExecuteWithLock(operation, ...)
    if RARELOAD.AntiStuck.ProfileSystem._operationLock then
        table.insert(RARELOAD.AntiStuck.ProfileSystem._pendingOperations, { operation, { ... } })
        return false, "Operation queued"
    end

    RARELOAD.AntiStuck.ProfileSystem._operationLock = true
    local success, result = pcall(operation, ...)
    RARELOAD.AntiStuck.ProfileSystem._operationLock = false

    -- Process pending operations
    if #RARELOAD.AntiStuck.ProfileSystem._pendingOperations > 0 then
        local pending = table.remove(RARELOAD.AntiStuck.ProfileSystem._pendingOperations, 1)
        timer.Simple(0, function()
            ExecuteWithLock(pending[1], unpack(pending[2]))
        end)
    end

    return success, result
end

local function GetCacheKey(profileName)
    return string.lower(string.Trim(profileName or ""))
end

local function IsValidProfileName(name)
    if not name or type(name) ~= "string" then return false end
    name = string.Trim(name)
    if #name == 0 or #name > 50 then return false end
    return not string.match(name, "[<>:\"/\\|?*]") -- Invalid filename characters
end

-- Profile validation with caching
local function ValidateProfileData(profile)
    if not profile or type(profile) ~= "table" then
        return false, "Profile must be a table"
    end

    -- Check required fields
    if not profile.name or not IsValidProfileName(profile.name) then
        return false, "Invalid profile name"
    end

    if not profile.version then
        profile.version = PROFILE_VERSION
    end

    -- Validate methods
    if profile.methods then
        if type(profile.methods) ~= "table" then
            return false, "Methods must be a table"
        end

        for i, method in ipairs(profile.methods) do
            if type(method) ~= "table" then
                return false, "Method " .. i .. " must be a table"
            end
            if not method.name or type(method.name) ~= "string" then
                return false, "Method " .. i .. " must have a valid name"
            end
            if method.enabled == nil then
                method.enabled = true
            end
            if not method.priority then
                method.priority = 50
            end
        end
    else
        profile.methods = {}
    end

    -- Validate settings
    if profile.settings then
        if type(profile.settings) ~= "table" then
            return false, "Settings must be a table"
        end

        -- Sanitize settings values
        if profile.settings.maxAttempts then
            profile.settings.maxAttempts = math.Clamp(tonumber(profile.settings.maxAttempts) or 10, 1, 100)
        end
        if profile.settings.timeout then
            profile.settings.timeout = math.Clamp(tonumber(profile.settings.timeout) or 5, 1, 60)
        end
    else
        profile.settings = {}
    end

    -- Set metadata with safe values
    profile.modified = profile.modified or os.time()
    profile.lastUsed = profile.lastUsed or 0
    profile.usageCount = profile.usageCount or 0
    profile.author = tostring(profile.author or "Unknown")
    profile.description = tostring(profile.description or "")

    -- Sanitize string fields
    profile.displayName = tostring(profile.displayName or profile.name)
    if #profile.description > 500 then
        profile.description = string.sub(profile.description, 1, 497) .. "..."
    end

    return true, profile
end

-- Cache management
function RARELOAD.AntiStuck.ProfileSystem.ClearCache()
    RARELOAD.AntiStuck.ProfileSystem._cache.profiles = {}
    RARELOAD.AntiStuck.ProfileSystem._cache.metadata = {}
    RARELOAD.AntiStuck.ProfileSystem._cache.size = 0
    RARELOAD.AntiStuck.ProfileSystem._cache.lastUpdate = SysTime()
end

function RARELOAD.AntiStuck.ProfileSystem.IsCacheValid()
    return (SysTime() - RARELOAD.AntiStuck.ProfileSystem._cache.lastUpdate) < CACHE_EXPIRE_TIME
end

function RARELOAD.AntiStuck.ProfileSystem.GetFromCache(profileName)
    local key = GetCacheKey(profileName)
    local cached = RARELOAD.AntiStuck.ProfileSystem._cache.profiles[key]

    if cached then
        RARELOAD.AntiStuck.ProfileSystem._stats.cacheHits = RARELOAD.AntiStuck.ProfileSystem._stats.cacheHits + 1
        return table.Copy(cached) -- Return copy to prevent mutations
    end

    RARELOAD.AntiStuck.ProfileSystem._stats.cacheMisses = RARELOAD.AntiStuck.ProfileSystem._stats.cacheMisses + 1
    return nil
end

function RARELOAD.AntiStuck.ProfileSystem.AddToCache(profileName, profile)
    local key = GetCacheKey(profileName)

    -- Evict oldest if cache is full
    if RARELOAD.AntiStuck.ProfileSystem._cache.size >= MAX_CACHE_SIZE then
        local oldestKey = nil
        local oldestTime = math.huge

        for cacheKey, metadata in pairs(RARELOAD.AntiStuck.ProfileSystem._cache.metadata) do
            if metadata.lastAccess < oldestTime then
                oldestTime = metadata.lastAccess
                oldestKey = cacheKey
            end
        end

        if oldestKey then
            RARELOAD.AntiStuck.ProfileSystem._cache.profiles[oldestKey] = nil
            RARELOAD.AntiStuck.ProfileSystem._cache.metadata[oldestKey] = nil
            RARELOAD.AntiStuck.ProfileSystem._cache.size = RARELOAD.AntiStuck.ProfileSystem._cache.size - 1
        end
    end

    -- Add to cache
    RARELOAD.AntiStuck.ProfileSystem._cache.profiles[key] = table.Copy(profile)
    RARELOAD.AntiStuck.ProfileSystem._cache.metadata[key] = {
        lastAccess = SysTime(),
        size = string.len(SafeJSONEncode(profile))
    }
    RARELOAD.AntiStuck.ProfileSystem._cache.size = RARELOAD.AntiStuck.ProfileSystem._cache.size + 1

    RARELOAD.AntiStuck.ProfileSystem.TriggerEvent("onCacheUpdated", profileName,
        RARELOAD.AntiStuck.ProfileSystem._cache.size)
end

-- Event system with cleanup
function RARELOAD.AntiStuck.ProfileSystem.RegisterEvent(eventName, callback)
    if not RARELOAD.AntiStuck.ProfileSystem._events[eventName] then
        RARELOAD.AntiStuck.ProfileSystem._events[eventName] = {}
    end

    local id = #RARELOAD.AntiStuck.ProfileSystem._events[eventName] + 1
    RARELOAD.AntiStuck.ProfileSystem._events[eventName][id] = callback

    -- Track for cleanup
    table.insert(RARELOAD.AntiStuck.ProfileSystem._eventHandlers, { eventName, id })

    return id
end

function RARELOAD.AntiStuck.ProfileSystem.UnregisterEvent(eventName, id)
    if RARELOAD.AntiStuck.ProfileSystem._events[eventName] and RARELOAD.AntiStuck.ProfileSystem._events[eventName][id] then
        RARELOAD.AntiStuck.ProfileSystem._events[eventName][id] = nil
    end
end

function RARELOAD.AntiStuck.ProfileSystem.TriggerEvent(eventName, ...)
    local handlers = RARELOAD.AntiStuck.ProfileSystem._events[eventName]
    if handlers then
        for id, callback in pairs(handlers) do
            local success, err = pcall(callback, ...)
            if not success then
                print("[ProfileSystem] Event error in", eventName, ":", err)
                -- Remove broken handler
                RARELOAD.AntiStuck.ProfileSystem._events[eventName][id] = nil
            end
        end
    end
end

function RARELOAD.AntiStuck.ProfileSystem.Cleanup()
    for _, timerName in ipairs(RARELOAD.AntiStuck.ProfileSystem._timers) do
        if timer.Exists(timerName) then
            timer.Remove(timerName)
        end
    end
    RARELOAD.AntiStuck.ProfileSystem._timers = {}

    RARELOAD.AntiStuck.ProfileSystem._events = {
        onProfileChanged = {},
        onProfileLoaded = {},
        onProfileSaved = {},
        onProfileDeleted = {},
        onCacheUpdated = {}
    }
    RARELOAD.AntiStuck.ProfileSystem._eventHandlers = {}

    RARELOAD.AntiStuck.ProfileSystem.ClearCache()

    print("[ProfileSystem] Cleanup completed")
end

-- Async operation queue
function RARELOAD.AntiStuck.ProfileSystem.QueueOperation(operation)
    table.insert(RARELOAD.AntiStuck.ProfileSystem._operationQueue, operation)
    RARELOAD.AntiStuck.ProfileSystem.ProcessQueue()
end

function RARELOAD.AntiStuck.ProfileSystem.ProcessQueue()
    if RARELOAD.AntiStuck.ProfileSystem._processingQueue then return end

    RARELOAD.AntiStuck.ProfileSystem._processingQueue = true

    timer.Simple(0, function()
        local processed = 0
        while #RARELOAD.AntiStuck.ProfileSystem._operationQueue > 0 and processed < 3 do
            local operation = table.remove(RARELOAD.AntiStuck.ProfileSystem._operationQueue, 1)
            if operation and operation.callback then
                local success, result = pcall(operation.callback)
                if operation.onComplete then
                    operation.onComplete(success, result)
                end
            end
            processed = processed + 1
        end

        RARELOAD.AntiStuck.ProfileSystem._processingQueue = false

        -- Continue processing if queue not empty
        if #RARELOAD.AntiStuck.ProfileSystem._operationQueue > 0 then
            RARELOAD.AntiStuck.ProfileSystem.ProcessQueue()
        end
    end)
end

-- Core profile operations
function RARELOAD.AntiStuck.ProfileSystem.Initialize()
    if RARELOAD.AntiStuck.ProfileSystem._initialized then return end

    EnsureDirectoryExists()
    RARELOAD.AntiStuck.ProfileSystem._initialized = true

    -- Load current profile
    RARELOAD.AntiStuck.ProfileSystem.LoadCurrentProfile()

    -- Create default profile if it doesn't exist
    if not RARELOAD.AntiStuck.ProfileSystem.ProfileExists(DEFAULT_PROFILE_NAME) then
        RARELOAD.AntiStuck.ProfileSystem.CreateDefaultProfile()
    end

    -- Set current profile to default if none set
    if not RARELOAD.AntiStuck.ProfileSystem._currentProfile then
        RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(DEFAULT_PROFILE_NAME)
    end

    print("[ProfileSystem] Initialized successfully")
end

function RARELOAD.AntiStuck.ProfileSystem.LoadProfile(profileName)
    if not profileName or not RARELOAD.AntiStuck.ProfileSystem._initialized then
        return nil, "Invalid profile name or system not initialized"
    end

    local startTime = SysTime()

    -- Try cache first
    local cached = RARELOAD.AntiStuck.ProfileSystem.GetFromCache(profileName)
    if cached then
        return cached
    end

    -- Load from file
    local fileName = PROFILE_DIR .. profileName .. ".json"

    if not file.Exists(fileName, "DATA") then
        return nil, "Profile file does not exist"
    end

    local content = file.Read(fileName, "DATA")
    if not content or content == "" then
        print("[ProfileSystem] Profile file is empty:", profileName)
        return nil, "Profile file is empty"
    end

    local profile = SafeJSONDecode(content)
    if not profile then
        print("[ProfileSystem] Failed to decode profile:", profileName)
        return nil, "Failed to decode profile data"
    end

    -- Validate and migrate if needed
    local valid, result = ValidateProfileData(profile)
    if not valid then
        print("[ProfileSystem] Invalid profile data:", result)
        return nil, "Invalid profile data: " .. result
    end

    if type(result) == "table" then
        profile = result
    else
        return nil, "Profile validation failed"
    end

    -- Add to cache
    RARELOAD.AntiStuck.ProfileSystem.AddToCache(profileName, profile)

    -- Update stats
    local loadTime = SysTime() - startTime
    RARELOAD.AntiStuck.ProfileSystem._stats.loadOperations = RARELOAD.AntiStuck.ProfileSystem._stats.loadOperations + 1
    RARELOAD.AntiStuck.ProfileSystem._stats.totalLoadTime = RARELOAD.AntiStuck.ProfileSystem._stats.totalLoadTime +
        loadTime
    RARELOAD.AntiStuck.ProfileSystem._stats.averageLoadTime = RARELOAD.AntiStuck.ProfileSystem._stats.totalLoadTime /
        RARELOAD.AntiStuck.ProfileSystem._stats.loadOperations

    RARELOAD.AntiStuck.ProfileSystem.TriggerEvent("onProfileLoaded", profileName, profile)

    return profile
end

function RARELOAD.AntiStuck.ProfileSystem.SaveProfile(profileName, profileData)
    if not profileName or not profileData or not RARELOAD.AntiStuck.ProfileSystem._initialized then
        return false, "Invalid parameters"
    end

    -- Create a copy to avoid modifying original data
    local profile = table.Copy(profileData)

    -- Validate profile data
    local valid, result = ValidateProfileData(profile)
    if not valid then
        return false, result
    end

    if type(result) == "table" then
        profile = result
        profile.modified = os.time()
    else
        return false, "Validation failed"
    end

    -- Ensure directory exists
    if not EnsureDirectoryExists() then
        return false, "Failed to create profile directory"
    end

    -- Save to file
    local fileName = PROFILE_DIR .. profileName .. ".json"
    local content = SafeJSONEncode(profile)

    if content == "" then
        return false, "Failed to encode profile data"
    end

    -- Atomic write operation
    local tempFileName = fileName .. ".tmp"
    local success = pcall(file.Write, tempFileName, content)
    if not success then
        return false, "Failed to write profile file"
    end

    -- Move temp file to final location
    if file.Exists(tempFileName, "DATA") then
        if file.Exists(fileName, "DATA") then
            file.Delete(fileName)
        end
        file.Rename(tempFileName, fileName:match("([^/]+)$"))
    else
        return false, "Failed to save profile"
    end

    -- Update cache
    RARELOAD.AntiStuck.ProfileSystem.AddToCache(profileName, profile)

    -- Update stats
    RARELOAD.AntiStuck.ProfileSystem._stats.saveOperations = RARELOAD.AntiStuck.ProfileSystem._stats.saveOperations + 1

    RARELOAD.AntiStuck.ProfileSystem.TriggerEvent("onProfileSaved", profileName, profile)

    return true
end

function RARELOAD.AntiStuck.ProfileSystem.DeleteProfile(profileName)
    if not profileName or profileName == DEFAULT_PROFILE_NAME then
        return false, "Cannot delete default profile"
    end

    local fileName = PROFILE_DIR .. profileName .. ".json"
    if not file.Exists(fileName, "DATA") then
        return false, "Profile does not exist"
    end

    file.Delete(fileName)

    -- Remove from cache
    local key = GetCacheKey(profileName)
    if RARELOAD.AntiStuck.ProfileSystem._cache.profiles[key] then
        RARELOAD.AntiStuck.ProfileSystem._cache.profiles[key] = nil
        RARELOAD.AntiStuck.ProfileSystem._cache.metadata[key] = nil
        RARELOAD.AntiStuck.ProfileSystem._cache.size = RARELOAD.AntiStuck.ProfileSystem._cache.size - 1
    end

    -- Switch away if this was the current profile
    if RARELOAD.AntiStuck.ProfileSystem._currentProfile == profileName then
        RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(DEFAULT_PROFILE_NAME)
    end

    RARELOAD.AntiStuck.ProfileSystem.TriggerEvent("onProfileDeleted", profileName)

    return true
end

function RARELOAD.AntiStuck.ProfileSystem.ProfileExists(profileName)
    if not profileName then return false end
    local fileName = PROFILE_DIR .. profileName .. ".json"
    return file.Exists(fileName, "DATA")
end

function RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
    return RARELOAD.AntiStuck.ProfileSystem._currentProfile
end

function RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(profileName)
    if not profileName or not RARELOAD.AntiStuck.ProfileSystem.ProfileExists(profileName) then
        return false, "Profile does not exist"
    end

    if RARELOAD.AntiStuck.ProfileSystem._currentProfile == profileName then
        return true -- Already current
    end

    local oldProfile = RARELOAD.AntiStuck.ProfileSystem._currentProfile
    RARELOAD.AntiStuck.ProfileSystem._currentProfile = profileName

    -- Save current profile setting
    file.Write(CURRENT_PROFILE_FILE, SafeJSONEncode({
        current = profileName,
        timestamp = os.time()
    }))

    -- Update usage stats
    local profile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(profileName)
    if profile then
        profile.lastUsed = os.time()
        profile.usageCount = (profile.usageCount or 0) + 1
        RARELOAD.AntiStuck.ProfileSystem.SaveProfile(profileName, profile)
    end

    RARELOAD.AntiStuck.ProfileSystem.TriggerEvent("onProfileChanged", profileName, oldProfile)

    return true
end

function RARELOAD.AntiStuck.ProfileSystem.LoadCurrentProfile()
    local content = file.Read(CURRENT_PROFILE_FILE, "DATA")
    if content then
        local data = SafeJSONDecode(content)
        if data and data.current and RARELOAD.AntiStuck.ProfileSystem.ProfileExists(data.current) then
            RARELOAD.AntiStuck.ProfileSystem._currentProfile = data.current
            return
        end
    end

    -- Fallback to default
    if RARELOAD.AntiStuck.ProfileSystem.ProfileExists(DEFAULT_PROFILE_NAME) then
        RARELOAD.AntiStuck.ProfileSystem._currentProfile = DEFAULT_PROFILE_NAME
    end
end

function RARELOAD.AntiStuck.ProfileSystem.CreateDefaultProfile()
    local defaultProfile = {
        name = DEFAULT_PROFILE_NAME,
        displayName = "Default Profile",
        description = "Default anti-stuck configuration",
        author = "System",
        version = PROFILE_VERSION,
        created = os.time(),
        modified = os.time(),
        methods = {
            { name = "space_scan",         enabled = true, priority = 10 },
            { name = "displacement",       enabled = true, priority = 20 },
            { name = "spawn_points",       enabled = true, priority = 30 },
            { name = "systematic_grid",    enabled = true, priority = 40 },
            { name = "emergency_teleport", enabled = true, priority = 90 }
        },
        settings = {
            maxAttempts = 10,
            timeout = 5,
            debug = false,
            autoResolve = true
        }
    }

    return RARELOAD.AntiStuck.ProfileSystem.SaveProfile(DEFAULT_PROFILE_NAME, defaultProfile)
end

function RARELOAD.AntiStuck.ProfileSystem.GetProfileList()
    local profiles = {}
    local files = file.Find(PROFILE_DIR .. "*.json", "DATA")

    for _, fileName in ipairs(files) do
        local profileName = string.gsub(fileName, "%.json$", "")
        local profile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(profileName)

        if profile then
            table.insert(profiles, {
                name = profile.name,
                displayName = profile.displayName or profile.name,
                description = profile.description or "",
                author = profile.author or "Unknown",
                modified = profile.modified or 0,
                lastUsed = profile.lastUsed or 0,
                usageCount = profile.usageCount or 0,
                isCurrent = (profile.name == RARELOAD.AntiStuck.ProfileSystem._currentProfile)
            })
        end
    end

    -- Sort by last used
    table.sort(profiles, function(a, b)
        return (a.lastUsed or 0) > (b.lastUsed or 0)
    end)

    return profiles
end

function RARELOAD.AntiStuck.ProfileSystem.GetStats()
    return table.Copy(RARELOAD.AntiStuck.ProfileSystem._stats)
end

-- Add convenience methods for backward compatibility
function RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileData()
    local current = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
    return current and RARELOAD.AntiStuck.ProfileSystem.LoadProfile(current) or nil
end

function RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileMethods()
    local profile = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileData()
    return profile and profile.methods or {}
end

function RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileSettings()
    local profile = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileData()
    return profile and profile.settings or {}
end

function RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile(settings, methods)
    local current = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
    if not current then return false, "No current profile" end

    local profile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(current)
    if not profile then return false, "Failed to load current profile" end

    if settings then profile.settings = settings end
    if methods then profile.methods = methods end

    return RARELOAD.AntiStuck.ProfileSystem.SaveProfile(current, profile)
end

-- Debug function for development
if CLIENT then
    function DebugProfileSystem()
        return {
            ProfileSystem = RARELOAD.AntiStuck.ProfileSystem,
            stats = RARELOAD.AntiStuck.ProfileSystem.GetStats(),
            cache = RARELOAD.AntiStuck.ProfileSystem._cache,
            current = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
        }
    end
end

-- Auto-initialize with safety checks
timer.Simple(0, function()
    if not RARELOAD.AntiStuck.ProfileSystem._initialized then
        local success, err = pcall(RARELOAD.AntiStuck.ProfileSystem.Initialize)
        if not success then
            print("[ProfileSystem] Initialization failed:", err)
        end
    end
end)

-- Cleanup on shutdown
hook.Add("ShutDown", "ProfileSystemCleanup", function()
    RARELOAD.AntiStuck.ProfileSystem.Cleanup()
end)

-- Cleanup on game state change
hook.Add("OnGamemodeLoaded", "ProfileSystemReinit", function()
    RARELOAD.AntiStuck.ProfileSystem.Cleanup()
    timer.Simple(1, function()
        RARELOAD.AntiStuck.ProfileSystem.Initialize()
    end)
end)

-- Console commands for debugging
concommand.Add("rareload_profile_stats", function()
    local stats = RARELOAD.AntiStuck.ProfileSystem.GetStats()
    print("=== Profile System Stats ===")
    print("Cache hits:", stats.cacheHits)
    print("Cache misses:", stats.cacheMisses)
    print("Load operations:", stats.loadOperations)
    print("Save operations:", stats.saveOperations)
    print("Average load time:", math.Round(stats.averageLoadTime * 1000, 2) .. "ms")
    print("Cache size:", RARELOAD.AntiStuck.ProfileSystem._cache.size .. "/" .. MAX_CACHE_SIZE)
end)

concommand.Add("rareload_profile_clear_cache", function()
    RARELOAD.AntiStuck.ProfileSystem.ClearCache()
    print("Profile cache cleared")
end)

concommand.Add("rareload_profile_list", function()
    local profiles = RARELOAD.AntiStuck.ProfileSystem.GetProfileList()
    print("=== Available Profiles ===")
    for _, profile in ipairs(profiles) do
        local status = profile.isCurrent and " [CURRENT]" or ""
        print(string.format("%s - %s%s", profile.name, profile.description, status))
    end
end)
