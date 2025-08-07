RARELOAD = RARELOAD or {}
RARELOAD.ProfileSystem = RARELOAD.ProfileSystem or {}

-- Constants
local PROFILE_DIR = "rareload/anti_stuck_profiles/"
local SELECTED_PROFILE_FILE = "rareload/anti_stuck_selected_profile.json"
local DEFAULT_PROFILE_NAME = "default"
local PROFILE_VERSION = "1.2"
local CACHE_TTL = 300 -- 5 minutes
local MAX_CACHE_SIZE = 50
local PROFILE_REFRESH_INTERVAL = 0.5 -- 0.5 seconds
local BATCH_OPERATION_SIZE = 5 -- Number of operations to batch together

-- Profile System Core
local ProfileSystem = {
    -- Core state
    _initialized = false,
    _currentProfile = nil,
    _profiles = {},
    _listDirty = true,
    
    -- Cache system with TTL
    _cache = {
        profiles = {},
        timestamps = {},
        lastAccess = {},
        validation = {}
    },
    
    -- Performance metrics
    _metrics = {
        cacheHits = 0,
        cacheMisses = 0,
        fileOperations = 0,
        validationHits = 0,
        lastCleanup = 0,
        batchOperations = 0
    },
    
    -- Memory pools for optimization
    _pools = {
        tempProfiles = {},
        tempSettings = {},
        tempMethods = {}
    },
    
    -- Batch operations
    _batchOps = {
        queue = {},
        timer = nil,
        processing = false
    },
    
    -- Event handlers
    _eventHandlers = {
        onProfileChanged = {},
        onProfileDeleted = {},
        onProfileCreated = {},
        onProfileUpdated = {}
    }
}

-- Utility functions
local function SafeJSONDecode(str)
    if not str or str == "" then return nil end
    local success, result = pcall(util.JSONToTable, str)
    return success and result or nil
end

local function SafeJSONEncode(tbl)
    if not tbl then return nil end
    local success, result = pcall(util.TableToJSON, tbl, true)
    return success and result or nil
end

local function GetFromPool(poolName)
    local pool = ProfileSystem._pools[poolName]
    if pool and #pool > 0 then
        return table.remove(pool)
    end
    return {}
end

local function ReturnToPool(poolName, obj)
    if not obj then return end
    table.Empty(obj)
    local pool = ProfileSystem._pools[poolName]
    if #pool < 20 then -- Increased pool size for better performance
        table.insert(pool, obj)
    end
end

-- Event handling
function ProfileSystem.RegisterEventHandler(event, handler)
    if not ProfileSystem._eventHandlers[event] then
        ProfileSystem._eventHandlers[event] = {}
    end
    table.insert(ProfileSystem._eventHandlers[event], handler)
end

function ProfileSystem.UnregisterEventHandler(event, handler)
    if not ProfileSystem._eventHandlers[event] then return end
    for i, h in ipairs(ProfileSystem._eventHandlers[event]) do
        if h == handler then
            table.remove(ProfileSystem._eventHandlers[event], i)
            break
        end
    end
end

local function TriggerEvent(event, ...)
    if not ProfileSystem._eventHandlers[event] then return end
    for _, handler in ipairs(ProfileSystem._eventHandlers[event]) do
        handler(...)
    end
end

-- Batch operations
local function ProcessBatchOperations()
    if ProfileSystem._batchOps.processing or #ProfileSystem._batchOps.queue == 0 then return end
    
    ProfileSystem._batchOps.processing = true
    local batch = {}
    
    -- Get next batch of operations
    for i = 1, math.min(BATCH_OPERATION_SIZE, #ProfileSystem._batchOps.queue) do
        table.insert(batch, table.remove(ProfileSystem._batchOps.queue, 1))
    end
    
    -- Process batch
    for _, op in ipairs(batch) do
        if op.type == "write" then
            RARELOAD.ProfileFileOps.WriteProfile(op.profileName, op.data)
        elseif op.type == "delete" then
            RARELOAD.ProfileFileOps.DeleteProfile(op.profileName)
        end
        ProfileSystem._metrics.batchOperations = ProfileSystem._metrics.batchOperations + 1
    end
    
    ProfileSystem._batchOps.processing = false
    
    -- Schedule next batch if queue not empty
    if #ProfileSystem._batchOps.queue > 0 then
        timer.Simple(0.1, ProcessBatchOperations)
    end
end

local function QueueOperation(opType, profileName, data)
    table.insert(ProfileSystem._batchOps.queue, {
        type = opType,
        profileName = profileName,
        data = data
    })
    
    -- Start processing if not already running
    if not ProfileSystem._batchOps.timer then
        ProfileSystem._batchOps.timer = timer.Create("RareloadProfileBatchOps", 0.1, 1, function()
            ProcessBatchOperations()
            ProfileSystem._batchOps.timer = nil
        end)
    end
end

-- Profile validation
local function ValidateProfileStructure(profile)
    if not profile or type(profile) ~= "table" then return false end
    
    -- Required fields
    local required = {
        "name", "displayName", "description", "version",
        "settings", "methods", "created", "modified"
    }
    
    for _, field in ipairs(required) do
        if profile[field] == nil then return false end
    end
    
    -- Validate settings and methods
    if type(profile.settings) ~= "table" or type(profile.methods) ~= "table" then
        return false
    end
    
    -- Version check
    if profile.version ~= PROFILE_VERSION then
        -- Attempt to migrate if possible
        return ProfileSystem.MigrateProfile(profile)
    end
    
    return true
end

-- Profile migration
function ProfileSystem.MigrateProfile(profile)
    if not profile.version then return false end
    
    -- Migration path from 1.1 to 1.2
    if profile.version == "1.1" then
        -- Add new fields
        profile.lastUsed = profile.lastUsed or os.time()
        profile.usageCount = profile.usageCount or 0
        profile.tags = profile.tags or {}
        profile.compatibility = profile.compatibility or {
            minVersion = "1.0",
            maxVersion = "1.2"
        }
        
        -- Update version
        profile.version = PROFILE_VERSION
        
        return true
    end
    
    return false
end

-- Core profile system functions
function ProfileSystem.Initialize()
    if ProfileSystem._initialized then return end
    
    -- Ensure directories exist
    file.CreateDir("rareload")
    file.CreateDir(PROFILE_DIR)
    
    -- Load current profile
    ProfileSystem.LoadCurrentProfile()
    
    -- Ensure default profile exists
    ProfileSystem.EnsureDefaultProfile()
    
    -- Initialize cache cleanup timer
    timer.Create("RareloadProfileCacheCleanup", CACHE_TTL, 0, function()
        ProfileSystem.CleanupCache()
    end)
    
    -- Initialize profile refresh timer
    timer.Create("RareloadProfileRefresh", PROFILE_REFRESH_INTERVAL, 0, function()
        if ProfileSystem._listDirty then
            ProfileSystem.RefreshProfiles()
        end
    end)
    
    -- Register default event handlers
    ProfileSystem.RegisterEventHandler("onProfileChanged", function(profileName, profile)
        if RARELOAD.AntiStuckSettings then
            RARELOAD.AntiStuckSettings.ApplyProfile(profile)
        end
    end)
    
    ProfileSystem._initialized = true
    print("[RARELOAD] Profile system initialized")
end

function ProfileSystem.LoadCurrentProfile()
    if not file.Exists(SELECTED_PROFILE_FILE, "DATA") then
        ProfileSystem._currentProfile = DEFAULT_PROFILE_NAME
        ProfileSystem.SaveCurrentProfile()
        return
    end
    
    local content = file.Read(SELECTED_PROFILE_FILE, "DATA")
    local data = SafeJSONDecode(content)
    
    if data and data.selectedProfile then
        -- Verify the profile still exists
        if file.Exists(PROFILE_DIR .. data.selectedProfile .. ".json", "DATA") then
            ProfileSystem._currentProfile = data.selectedProfile
        else
            ProfileSystem._currentProfile = DEFAULT_PROFILE_NAME
            ProfileSystem.SaveCurrentProfile()
            print("[RARELOAD] Selected profile no longer exists, falling back to default")
        end
    end
end

function ProfileSystem.SaveCurrentProfile()
    local data = { selectedProfile = ProfileSystem._currentProfile }
    local json = SafeJSONEncode(data)
    if json then
        file.Write(SELECTED_PROFILE_FILE, json)
    end
end

function ProfileSystem.EnsureDefaultProfile()
    local defaultPath = PROFILE_DIR .. DEFAULT_PROFILE_NAME .. ".json"
    if file.Exists(defaultPath, "DATA") then return end
    
    local defaultProfile = {
        name = DEFAULT_PROFILE_NAME,
        displayName = "Default Settings",
        description = "Standard anti-stuck configuration",
        author = "System",
        created = os.time(),
        modified = os.time(),
        lastUsed = os.time(),
        usageCount = 0,
        shared = false,
        mapSpecific = false,
        map = "",
        version = PROFILE_VERSION,
        tags = {"default", "system"},
        compatibility = {
            minVersion = "1.0",
            maxVersion = PROFILE_VERSION
        },
        settings = RARELOAD.DefaultAntiStuckSettings or {},
        methods = RARELOAD.DefaultAntiStuckMethods or {}
    }
    
    ProfileSystem.SaveProfile(DEFAULT_PROFILE_NAME, defaultProfile)
    print("[RARELOAD] Created default anti-stuck profile")
end

function ProfileSystem.LoadProfile(profileName)
    if not profileName then return nil end
    
    -- Check cache first
    if ProfileSystem._cache.profiles[profileName] and 
       ProfileSystem.IsCacheValid(profileName) then
        ProfileSystem._metrics.cacheHits = ProfileSystem._metrics.cacheHits + 1
        ProfileSystem._cache.lastAccess[profileName] = os.time()
        return ProfileSystem._cache.profiles[profileName]
    end
    
    ProfileSystem._metrics.cacheMisses = ProfileSystem._metrics.cacheMisses + 1
    ProfileSystem._metrics.fileOperations = ProfileSystem._metrics.fileOperations + 1
    
    local profile = RARELOAD.ProfileFileOps.ReadProfile(profileName)
    if not profile then return nil end
    
    -- Validate profile data
    if not ValidateProfileStructure(profile) then
        print("[RARELOAD] Invalid profile data in " .. profileName)
        return nil
    end
    
    -- Update cache
    ProfileSystem._cache.profiles[profileName] = profile
    ProfileSystem._cache.timestamps[profileName] = file.Time(PROFILE_DIR .. profileName .. ".json", "DATA")
    ProfileSystem._cache.lastAccess[profileName] = os.time()
    
    return profile
end

function ProfileSystem.SaveProfile(profileName, data)
    if not profileName or not data then return false end
    
    -- Validate profile data
    if not ValidateProfileStructure(data) then
        return false, "Invalid profile data"
    end
    
    -- Update metadata
    data.modified = os.time()
    data.version = PROFILE_VERSION
    
    -- Queue write operation
    QueueOperation("write", profileName, data)
    
    -- Update cache
    ProfileSystem._cache.profiles[profileName] = data
    ProfileSystem._cache.timestamps[profileName] = os.time()
    ProfileSystem._cache.lastAccess[profileName] = os.time()
    
    -- Mark list as dirty
    ProfileSystem._listDirty = true
    
    -- Trigger event
    TriggerEvent("onProfileUpdated", profileName, data)
    
    return true
end

function ProfileSystem.DeleteProfile(profileName)
    if not profileName or profileName == DEFAULT_PROFILE_NAME then
        return false, "Cannot delete default profile"
    end
    
    -- Queue delete operation
    QueueOperation("delete", profileName)
    
    -- Remove from cache
    ProfileSystem.InvalidateCache(profileName)
    
    -- If this was the current profile, switch to default
    if ProfileSystem._currentProfile == profileName then
        ProfileSystem._currentProfile = DEFAULT_PROFILE_NAME
        ProfileSystem.SaveCurrentProfile()
        print("[RARELOAD] Deleted current profile, switching to default")
    end
    
    -- Mark list as dirty
    ProfileSystem._listDirty = true
    
    -- Trigger event
    TriggerEvent("onProfileDeleted", profileName)
    
    return true
end

function ProfileSystem.GetCurrentProfile()
    return ProfileSystem._currentProfile
end

function ProfileSystem.SetCurrentProfile(profileName)
    if not profileName then return false, "Invalid profile name" end
    
    local profile = ProfileSystem.LoadProfile(profileName)
    if not profile then return false, "Profile not found" end
    
    ProfileSystem._currentProfile = profileName
    ProfileSystem.SaveCurrentProfile()
    
    -- Update usage statistics
    profile.lastUsed = os.time()
    profile.usageCount = (profile.usageCount or 0) + 1
    ProfileSystem.SaveProfile(profileName, profile)
    
    -- Trigger event
    TriggerEvent("onProfileChanged", profileName, profile)
    
    return true
end

function ProfileSystem.GetProfilesList()
    local profiles = {}
    local files = file.Find(PROFILE_DIR .. "*.json", "DATA")
    
    for _, fileName in ipairs(files) do
        local profileName = string.gsub(fileName, ".json$", "")
        local profile = ProfileSystem.LoadProfile(profileName)
        
        if profile then
            table.insert(profiles, {
                name = profile.name,
                displayName = profile.displayName,
                description = profile.description,
                author = profile.author,
                modified = profile.modified,
                lastUsed = profile.lastUsed,
                usageCount = profile.usageCount,
                shared = profile.shared,
                mapSpecific = profile.mapSpecific,
                map = profile.map,
                tags = profile.tags or {}
            })
        end
    end
    
    -- Sort profiles by last used time
    table.sort(profiles, function(a, b)
        return (a.lastUsed or 0) > (b.lastUsed or 0)
    end)
    
    return profiles
end

function ProfileSystem.RefreshProfiles()
    if not ProfileSystem._listDirty then return end
    
    ProfileSystem._profiles = ProfileSystem.GetProfilesList()
    ProfileSystem._listDirty = false
end

function ProfileSystem.IsCacheValid(profileName)
    if not ProfileSystem._cache.timestamps[profileName] then return false end
    
    local currentTime = os.time()
    local lastAccess = ProfileSystem._cache.lastAccess[profileName] or 0
    
    -- Check if cache entry has expired
    if currentTime - lastAccess > CACHE_TTL then
        ProfileSystem.InvalidateCache(profileName)
        return false
    end
    
    return true
end

function ProfileSystem.InvalidateCache(profileName)
    if profileName then
        ProfileSystem._cache.profiles[profileName] = nil
        ProfileSystem._cache.timestamps[profileName] = nil
        ProfileSystem._cache.lastAccess[profileName] = nil
        ProfileSystem._cache.validation[profileName] = nil
    else
        -- Invalidate entire cache
        table.Empty(ProfileSystem._cache.profiles)
        table.Empty(ProfileSystem._cache.timestamps)
        table.Empty(ProfileSystem._cache.lastAccess)
        table.Empty(ProfileSystem._cache.validation)
    end
end

function ProfileSystem.CleanupCache()
    local currentTime = os.time()
    local profilesToRemove = {}
    
    -- Find expired cache entries
    for profileName, lastAccess in pairs(ProfileSystem._cache.lastAccess) do
        if currentTime - lastAccess > CACHE_TTL then
            table.insert(profilesToRemove, profileName)
        end
    end
    
    -- Remove expired entries
    for _, profileName in ipairs(profilesToRemove) do
        ProfileSystem.InvalidateCache(profileName)
    end
    
    -- Limit cache size
    local cacheSize = table.Count(ProfileSystem._cache.profiles)
    if cacheSize > MAX_CACHE_SIZE then
        local sortedProfiles = {}
        for profileName, lastAccess in pairs(ProfileSystem._cache.lastAccess) do
            table.insert(sortedProfiles, {name = profileName, lastAccess = lastAccess})
        end
        
        table.sort(sortedProfiles, function(a, b)
            return a.lastAccess < b.lastAccess
        end)
        
        local toRemove = cacheSize - MAX_CACHE_SIZE
        for i = 1, toRemove do
            if sortedProfiles[i] then
                ProfileSystem.InvalidateCache(sortedProfiles[i].name)
            end
        end
    end
    
    ProfileSystem._metrics.lastCleanup = currentTime
end

-- Export the profile system
RARELOAD.ProfileSystem = ProfileSystem
