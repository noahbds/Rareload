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
    _initialized = false,
    _currentProfile = nil,
    _isLoading = false,
    _operationLock = false,
    _pendingOperations = {},

    _cache = {
        profiles = {},
        metadata = {},
        lastUpdate = 0,
        size = 0
    },

    _events = {
        onProfileChanged = {},
        onProfileLoaded = {},
        onProfileSaved = {},
        onProfileDeleted = {},
        onCacheUpdated = {}
    },

    _stats = {
        cacheHits = 0,
        cacheMisses = 0,
        loadOperations = 0,
        saveOperations = 0,
        totalLoadTime = 0,
        averageLoadTime = 0
    },

    _operationQueue = {},
    _processingQueue = false,
    _validationCache = {},
    _lastValidation = 0,
    _timers = {},
    _eventHandlers = {}
}

local function SafeJSONDecode(str)
    if not str or str == "" then
        print("[ProfileSystem] SafeJSONDecode: Input string is empty or nil")
        return nil
    end

    local success, result = pcall(util.JSONToTable, str)
    if not success then
        print("[ProfileSystem] JSON decode error:", tostring(result))
        print("[ProfileSystem] Failed string length:", string.len(str))
        return nil
    end

    if not result then
        print("[ProfileSystem] JSON decode returned nil result")
        return nil
    end

    return result
end

local function SafeJSONEncode(tbl)
    if not tbl then
        print("[ProfileSystem] SafeJSONEncode: Input table is nil")
        return ""
    end

    local success, result = pcall(util.TableToJSON, tbl, true)
    if not success then
        print("[ProfileSystem] JSON encode error:", tostring(result))
        print("[ProfileSystem] Failed table content:", tostring(tbl))
        return ""
    end

    if not result or result == "" then
        print("[ProfileSystem] JSON encode returned empty result")
        return ""
    end

    return result
end

local function EnsureDirectoryExists()
    local dir = string.gsub(PROFILE_DIR, "/+$", "")

    if not file.IsDir(dir, "DATA") then
        print("[ProfileSystem] Directory does not exist, creating: " .. dir)
        local success, err = pcall(file.CreateDir, dir)
        if not success then
            print("[ProfileSystem] Failed to create profile directory: " .. tostring(err))
            return false
        end

        if not file.IsDir(dir, "DATA") then
            print("[ProfileSystem] Directory creation appeared successful but directory still doesn't exist")
            return false
        end

        print("[ProfileSystem] Successfully created directory: " .. dir)
    end

    return file.IsDir(dir, "DATA")
end

local function ExecuteWithLock(operation, ...)
    if RARELOAD.AntiStuck.ProfileSystem._operationLock then
        table.insert(RARELOAD.AntiStuck.ProfileSystem._pendingOperations, { operation, { ... } })
        return false, "Operation queued"
    end

    RARELOAD.AntiStuck.ProfileSystem._operationLock = true
    local success, result = pcall(operation, ...)
    RARELOAD.AntiStuck.ProfileSystem._operationLock = false

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
    return not string.match(name, "[<>:\"/\\|?*]")
end

local function ValidateProfileData(profile)
    if not profile or type(profile) ~= "table" then
        local errorMsg = "Profile must be a table, got: " .. type(profile)
        print("[ProfileSystem] Validation error: " .. errorMsg)
        return false, errorMsg
    end

    if not profile.name then
        print("[ProfileSystem] Validation error: Profile missing name field")
        return false, "Profile must have a name field"
    end

    if not IsValidProfileName(profile.name) then
        local errorMsg = "Invalid profile name: '" .. tostring(profile.name) .. "'"
        print("[ProfileSystem] Validation error: " .. errorMsg)
        return false, errorMsg
    end

    if not profile.version then
        profile.version = PROFILE_VERSION
        print("[ProfileSystem] Added missing version to profile: " .. profile.name)
    end

    if profile.methods then
        if type(profile.methods) ~= "table" then
            print("[ProfileSystem] Validation error: Methods must be a table for profile: " .. profile.name)
            return false, "Methods must be a table"
        end

        for i, method in ipairs(profile.methods) do
            if type(method) ~= "table" then
                local errorMsg = "Method " .. i .. " must be a table"
                print("[ProfileSystem] Validation error: " .. errorMsg .. " for profile: " .. profile.name)
                return false, errorMsg
            end
            if not method.name or type(method.name) ~= "string" then
                local errorMsg = "Method " .. i .. " must have a valid name"
                print("[ProfileSystem] Validation error: " .. errorMsg .. " for profile: " .. profile.name)
                return false, errorMsg
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
        print("[ProfileSystem] Added empty methods array to profile: " .. profile.name)
    end

    if profile.settings then
        if type(profile.settings) ~= "table" then
            print("[ProfileSystem] Validation error: Settings must be a table for profile: " .. profile.name)
            return false, "Settings must be a table"
        end

        if profile.settings.maxAttempts then
            profile.settings.maxAttempts = math.Clamp(tonumber(profile.settings.maxAttempts) or 10, 1, 100)
        end
        if profile.settings.timeout then
            profile.settings.timeout = math.Clamp(tonumber(profile.settings.timeout) or 5, 1, 60)
        end
    else
        profile.settings = {}
        print("[ProfileSystem] Added empty settings to profile: " .. profile.name)
    end

    profile.modified = profile.modified or os.time()
    profile.lastUsed = profile.lastUsed or 0
    profile.usageCount = profile.usageCount or 0
    profile.author = tostring(profile.author or "Unknown")
    profile.description = tostring(profile.description or "")

    profile.displayName = tostring(profile.displayName or profile.name)
    if #profile.description > 500 then
        profile.description = string.sub(profile.description, 1, 497) .. "..."
    end

    print("[ProfileSystem] Profile validation successful for: " .. profile.name)
    return true, profile
end

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
        return table.Copy(cached)
    end

    RARELOAD.AntiStuck.ProfileSystem._stats.cacheMisses = RARELOAD.AntiStuck.ProfileSystem._stats.cacheMisses + 1
    return nil
end

function RARELOAD.AntiStuck.ProfileSystem.AddToCache(profileName, profile)
    local key = GetCacheKey(profileName)

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

    RARELOAD.AntiStuck.ProfileSystem._cache.profiles[key] = table.Copy(profile)
    RARELOAD.AntiStuck.ProfileSystem._cache.metadata[key] = {
        lastAccess = SysTime(),
        size = string.len(SafeJSONEncode(profile))
    }
    RARELOAD.AntiStuck.ProfileSystem._cache.size = RARELOAD.AntiStuck.ProfileSystem._cache.size + 1

    RARELOAD.AntiStuck.ProfileSystem.TriggerEvent("onCacheUpdated", profileName,
        RARELOAD.AntiStuck.ProfileSystem._cache.size)
end

function RARELOAD.AntiStuck.ProfileSystem.RegisterEvent(eventName, callback)
    if not RARELOAD.AntiStuck.ProfileSystem._events[eventName] then
        RARELOAD.AntiStuck.ProfileSystem._events[eventName] = {}
    end

    local id = #RARELOAD.AntiStuck.ProfileSystem._events[eventName] + 1
    RARELOAD.AntiStuck.ProfileSystem._events[eventName][id] = callback

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

        if #RARELOAD.AntiStuck.ProfileSystem._operationQueue > 0 then
            RARELOAD.AntiStuck.ProfileSystem.ProcessQueue()
        end
    end)
end

function RARELOAD.AntiStuck.ProfileSystem.Initialize()
    if RARELOAD.AntiStuck.ProfileSystem._initialized then
        print("[ProfileSystem] Already initialized")
        return
    end

    print("[ProfileSystem] Starting initialization...")

    local dirSuccess = EnsureDirectoryExists()
    if not dirSuccess then
        print("[ProfileSystem] Failed to ensure directory exists during initialization")
        return false
    end

    RARELOAD.AntiStuck.ProfileSystem._initialized = true
    print("[ProfileSystem] Marked as initialized")

    RARELOAD.AntiStuck.ProfileSystem.LoadCurrentProfile()

    if not RARELOAD.AntiStuck.ProfileSystem.ProfileExists(DEFAULT_PROFILE_NAME) then
        print("[ProfileSystem] Creating default profile...")
        local success, err = RARELOAD.AntiStuck.ProfileSystem.CreateDefaultProfile()
        if not success then
            print("[ProfileSystem] Failed to create default profile: " .. tostring(err))
        else
            print("[ProfileSystem] Default profile created successfully")
        end
    end

    if not RARELOAD.AntiStuck.ProfileSystem._currentProfile then
        print("[ProfileSystem] Setting current profile to default")
        RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(DEFAULT_PROFILE_NAME)
    else
        RARELOAD.AntiStuck.ProfileSystem.currentProfile = RARELOAD.AntiStuck.ProfileSystem._currentProfile
    end

    print("[ProfileSystem] Initialized successfully")
    return true
end

function RARELOAD.AntiStuck.ProfileSystem.LoadProfile(profileName)
    if not profileName or not RARELOAD.AntiStuck.ProfileSystem._initialized then
        return nil, "Invalid profile name or system not initialized"
    end

    local startTime = SysTime()

    local cached = RARELOAD.AntiStuck.ProfileSystem.GetFromCache(profileName)
    if cached then
        return cached
    end

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

    RARELOAD.AntiStuck.ProfileSystem.AddToCache(profileName, profile)

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
        local errorMsg = "Invalid parameters: " ..
            "profileName=" .. tostring(profileName) ..
            ", profileData=" .. tostring(profileData ~= nil) ..
            ", initialized=" .. tostring(RARELOAD.AntiStuck.ProfileSystem._initialized)
        print("[ProfileSystem] " .. errorMsg)
        return false, errorMsg
    end

    print("[ProfileSystem] Attempting to save profile: " .. profileName)

    local profile = table.Copy(profileData)

    local valid, result = ValidateProfileData(profile)
    if not valid then
        print("[ProfileSystem] Profile validation failed: " .. tostring(result))
        return false, result
    end

    if type(result) == "table" then
        profile = result
        profile.modified = os.time()
    else
        print("[ProfileSystem] Validation failed - unexpected result type: " .. type(result))
        return false, "Validation failed"
    end

    if not EnsureDirectoryExists() then
        local errorMsg = "Failed to create profile directory: " .. PROFILE_DIR
        print("[ProfileSystem] " .. errorMsg)
        return false, errorMsg
    end

    local fileName = PROFILE_DIR .. profileName .. ".json"
    print("[ProfileSystem] Saving to file: " .. fileName)

    local content = SafeJSONEncode(profile)
    if content == "" then
        local errorMsg = "Failed to encode profile data for: " .. profileName
        print("[ProfileSystem] " .. errorMsg)
        return false, errorMsg
    end

    print("[ProfileSystem] Encoded content length: " .. string.len(content))

    print("[ProfileSystem] Attempting direct write to: " .. fileName)

    local writeSuccess, writeError = pcall(file.Write, fileName, content)
    if not writeSuccess then
        local errorMsg = "Failed to write profile file: " .. tostring(writeError)
        print("[ProfileSystem] " .. errorMsg)
        return false, errorMsg
    end

    timer.Simple(0, function() end)

    if not file.Exists(fileName, "DATA") then
        print("[ProfileSystem] File not found after first write, retrying...")

        if not EnsureDirectoryExists() then
            return false, "Directory disappeared during save"
        end

        local retrySuccess = pcall(file.Write, fileName, content)
        if not retrySuccess or not file.Exists(fileName, "DATA") then
            local errorMsg = "File was not created after write operation: " .. fileName
            print("[ProfileSystem] " .. errorMsg)
            return false, errorMsg
        end
    end

    local savedContent = file.Read(fileName, "DATA")
    if not savedContent or savedContent == "" then
        local errorMsg = "File was created but is empty: " .. fileName
        print("[ProfileSystem] " .. errorMsg)
        return false, errorMsg
    end

    if string.len(savedContent) < string.len(content) * 0.9 then
        local errorMsg = "File content appears corrupted (too short): " .. fileName
        print("[ProfileSystem] " ..
            errorMsg .. " (expected ~" .. string.len(content) .. ", got " .. string.len(savedContent) .. ")")
        return false, errorMsg
    end

    print("[ProfileSystem] Profile saved successfully: " .. profileName .. " (" .. string.len(savedContent) .. " bytes)")

    RARELOAD.AntiStuck.ProfileSystem.AddToCache(profileName, profile)

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

    local key = GetCacheKey(profileName)
    if RARELOAD.AntiStuck.ProfileSystem._cache.profiles[key] then
        RARELOAD.AntiStuck.ProfileSystem._cache.profiles[key] = nil
        RARELOAD.AntiStuck.ProfileSystem._cache.metadata[key] = nil
        RARELOAD.AntiStuck.ProfileSystem._cache.size = RARELOAD.AntiStuck.ProfileSystem._cache.size - 1
    end

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

RARELOAD.AntiStuck.ProfileSystem.currentProfile = RARELOAD.AntiStuck.ProfileSystem._currentProfile

function RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(profileName)
    if not profileName or not RARELOAD.AntiStuck.ProfileSystem.ProfileExists(profileName) then
        return false, "Profile does not exist"
    end

    if RARELOAD.AntiStuck.ProfileSystem._currentProfile == profileName then
        return true
    end

    local oldProfile = RARELOAD.AntiStuck.ProfileSystem._currentProfile
    RARELOAD.AntiStuck.ProfileSystem._currentProfile = profileName

    RARELOAD.AntiStuck.ProfileSystem.currentProfile = profileName

    file.Write(CURRENT_PROFILE_FILE, SafeJSONEncode({
        current = profileName,
        timestamp = os.time()
    }))

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
            RARELOAD.AntiStuck.ProfileSystem.currentProfile = data.current
            return
        end
    end

    if RARELOAD.AntiStuck.ProfileSystem.ProfileExists(DEFAULT_PROFILE_NAME) then
        RARELOAD.AntiStuck.ProfileSystem._currentProfile = DEFAULT_PROFILE_NAME
        RARELOAD.AntiStuck.ProfileSystem.currentProfile = DEFAULT_PROFILE_NAME
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

    table.sort(profiles, function(a, b)
        return (a.lastUsed or 0) > (b.lastUsed or 0)
    end)

    return profiles
end

function RARELOAD.AntiStuck.ProfileSystem.GetProfilesList()
    return RARELOAD.AntiStuck.ProfileSystem.GetProfileList()
end

function RARELOAD.AntiStuck.ProfileSystem.ApplyProfile(profileName)
    if not profileName then
        print("[ProfileSystem] ApplyProfile: profileName is nil")
        return false
    end

    print("[ProfileSystem] Applying profile: " .. profileName)

    local success, err = RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(profileName)
    if success then
        print("[ProfileSystem] Successfully applied profile: " .. profileName)
        return true
    else
        print("[ProfileSystem] Failed to apply profile: " .. profileName .. " - " .. tostring(err))
        return false
    end
end

function RARELOAD.AntiStuck.ProfileSystem.GetStats()
    return table.Copy(RARELOAD.AntiStuck.ProfileSystem._stats)
end

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

timer.Simple(0, function()
    if not RARELOAD.AntiStuck.ProfileSystem._initialized then
        local success, err = pcall(RARELOAD.AntiStuck.ProfileSystem.Initialize)
        if not success then
            print("[ProfileSystem] Initialization failed:", err)
        end
    end
end)

hook.Add("ShutDown", "ProfileSystemCleanup", function()
    RARELOAD.AntiStuck.ProfileSystem.Cleanup()
end)

hook.Add("OnGamemodeLoaded", "ProfileSystemReinit", function()
    RARELOAD.AntiStuck.ProfileSystem.Cleanup()
    timer.Simple(1, function()
        RARELOAD.AntiStuck.ProfileSystem.Initialize()
    end)
end)

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

concommand.Add("rareload_profile_reinit", function()
    print("Reinitializing profile system...")
    RARELOAD.AntiStuck.ProfileSystem._initialized = false
    RARELOAD.AntiStuck.ProfileSystem._currentProfile = nil
    RARELOAD.AntiStuck.ProfileSystem.ClearCache()

    local success, err = pcall(RARELOAD.AntiStuck.ProfileSystem.Initialize)
    if success then
        print("Profile system reinitialized successfully")
    else
        print("Profile system reinitialization failed: " .. tostring(err))
    end
end)

concommand.Add("rareload_profile_list", function()
    local profiles = RARELOAD.AntiStuck.ProfileSystem.GetProfileList()
    print("=== Available Profiles ===")
    for _, profile in ipairs(profiles) do
        local status = profile.isCurrent and " [CURRENT]" or ""
        print(string.format("%s - %s%s", profile.name, profile.description, status))
    end
end)

if CLIENT then
    function DebugProfileSystem()
        return {
            ProfileSystem = RARELOAD.AntiStuck.ProfileSystem,
            stats = RARELOAD.AntiStuck.ProfileSystem.GetStats(),
            cache = RARELOAD.AntiStuck.ProfileSystem._cache,
            currentProfile = RARELOAD.AntiStuck.ProfileSystem._currentProfile,
            initialized = RARELOAD.AntiStuck.ProfileSystem._initialized
        }
    end

    function DiagnoseProfileSystem()
        print("=== Profile System Diagnostic ===")
        print("Initialized: " .. tostring(RARELOAD.AntiStuck.ProfileSystem._initialized))
        print("Current Profile: " .. tostring(RARELOAD.AntiStuck.ProfileSystem._currentProfile))
        print("Profile Directory: " .. PROFILE_DIR)

        local dir = string.gsub(PROFILE_DIR, "/+$", "")
        local dirExists = file.IsDir(dir, "DATA")
        print("Directory Exists: " .. tostring(dirExists))

        if dirExists then
            local files = file.Find(PROFILE_DIR .. "*.json", "DATA")
            print("Profile Files Found: " .. #files)
            for i, fileName in ipairs(files) do
                print("  " .. i .. ". " .. fileName)
            end
        else
            print("Directory does not exist, attempting to create...")
            local success = EnsureDirectoryExists()
            print("Directory creation result: " .. tostring(success))
        end

        local testFile = PROFILE_DIR .. "test_write_profile.json"
        local testProfile = {
            name = "test_diagnostic",
            version = "1.0",
            methods = {},
            settings = {},
            created = os.time()
        }
        local testContent = SafeJSONEncode(testProfile)

        print("Testing profile-style write operations...")
        print("Test file path: " .. testFile)
        print("Test content length: " .. string.len(testContent))

        local writeSuccess, writeError = pcall(file.Write, testFile, testContent)
        print("Write test result: " .. tostring(writeSuccess))

        if not writeSuccess then
            print("Write error: " .. tostring(writeError))
        else
            if file.Exists(testFile, "DATA") then
                local readContent = file.Read(testFile, "DATA")
                if readContent and string.len(readContent) > 0 then
                    print("File verification: SUCCESS (" .. string.len(readContent) .. " bytes)")
                    file.Delete(testFile)
                    print("Test file cleaned up")
                else
                    print("File verification: FAILED - file exists but is empty")
                end
            else
                print("File verification: FAILED - file was not created")
            end
        end

        local testTable = { name = "test", version = "1.0" }
        local jsonResult = SafeJSONEncode(testTable)
        print("JSON encoding test: " .. (jsonResult ~= "" and "SUCCESS" or "FAILED"))
        if jsonResult == "" then
            print("JSON encoding failed for test table")
        end

        print("=== End Diagnostic ===")
    end

    concommand.Add("rareload_profile_diagnose", function()
        DiagnoseProfileSystem()
    end)

    concommand.Add("rareload_profile_test_save", function(ply, cmd, args)
        local testName = args[1] or ("test_save_" .. os.time())
        print("Testing profile save with name: " .. testName)

        local testProfile = {
            name = testName,
            displayName = "Test Profile",
            description = "Test profile for debugging save issues",
            author = "System Test",
            version = PROFILE_VERSION,
            created = os.time(),
            modified = os.time(),
            methods = {
                { name = "test_method", enabled = true, priority = 10 }
            },
            settings = {
                maxAttempts = 5,
                timeout = 3,
                debug = true
            }
        }

        local success, err = RARELOAD.AntiStuck.ProfileSystem.SaveProfile(testName, testProfile)
        if success then
            print("✓ Test profile save SUCCESSFUL")

            local loaded = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(testName)
            if loaded then
                print("✓ Test profile load verification SUCCESSFUL")

                RARELOAD.AntiStuck.ProfileSystem.DeleteProfile(testName)
                print("✓ Test profile cleanup SUCCESSFUL")
            else
                print("✗ Test profile load verification FAILED")
            end
        else
            print("✗ Test profile save FAILED: " .. tostring(err))
        end
    end)

    concommand.Add("rareload_profile_test_dropdown", function()
        print("=== Testing Dropdown Functions ===")

        if RARELOAD.AntiStuck.ProfileSystem.GetProfilesList then
            local profiles = RARELOAD.AntiStuck.ProfileSystem.GetProfilesList()
            print("✓ GetProfilesList available, found " .. #profiles .. " profiles:")
            for i, profile in ipairs(profiles) do
                print("  " .. i .. ". " .. profile.name .. " (" .. (profile.displayName or "N/A") .. ")")
            end
        else
            print("✗ GetProfilesList not available")
        end

        local current1 = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
        local current2 = RARELOAD.AntiStuck.ProfileSystem.currentProfile
        print("Current profile (function): " .. tostring(current1))
        print("Current profile (property): " .. tostring(current2))
        print("Match: " .. tostring(current1 == current2))

        if RARELOAD.AntiStuck.ProfileSystem.ApplyProfile then
            print("✓ ApplyProfile function available")
        else
            print("✗ ApplyProfile function not available")
        end

        print("=== End Dropdown Test ===")
    end)
end
