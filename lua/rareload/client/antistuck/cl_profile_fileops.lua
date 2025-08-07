RARELOAD = RARELOAD or {}

-- Defensive initialization for internal tables to prevent nil errors
local profileSystem = RARELOAD.profileSystem or _G.profileSystem or {}

profileSystem._profileCache = profileSystem._profileCache or {}
profileSystem._validationCache = profileSystem._validationCache or {}
profileSystem._fileTimestamps = profileSystem._fileTimestamps or {}
profileSystem._profileList = profileSystem._profileList or nil
profileSystem._listDirty = profileSystem._listDirty or true
profileSystem._batchOperations = profileSystem._batchOperations or {}
profileSystem._memoryPool = profileSystem._memoryPool or {
    tempProfiles = {},
    tempSettings = {},
    tempMethods = {}
}
profileSystem._stats = profileSystem._stats or {
    cacheHits = 0,
    cacheMisses = 0,
    fileOperations = 0,
    validationCacheHits = 0
}

-- Profile File Operations Module
-- Handles file operations, batch processing, and profile I/O
-- This module extends and optimizes the basic functions from cl_profile_system.lua

print("[RARELOAD] Loading optimized file operations module")

-- Ensure deep copy utilities are available
if not profileSystem.DeepCopy then
    include("cl_profile_deepcopy.lua")
end

include("cl_profile_cache.lua")

-- Ensure required fields are present (fix for nil selectedProfileFile)
if not profileSystem.selectedProfileFile then
    profileSystem.selectedProfileFile = "rareload/anti_stuck_selected_profile.json"
end
if not profileSystem.profilesDir then
    profileSystem.profilesDir = "rareload/anti_stuck_profiles/"
end

-- Batch file operations for better performance
function profileSystem.ExecuteBatchOperations()
    if #profileSystem._batchOperations == 0 then return end

    for _, operation in ipairs(profileSystem._batchOperations) do
        if operation.type == "write" then
            file.CreateDir(operation.dir)
            file.Write(operation.path, operation.data)
            profileSystem._stats.fileOperations = profileSystem._stats.fileOperations + 1
        elseif operation.type == "delete" then
            file.Delete(operation.path)
            profileSystem._stats.fileOperations = profileSystem._stats.fileOperations + 1
        end
    end

    profileSystem._batchOperations = {}
end

-- Queue a file operation for batch execution
function profileSystem.QueueFileOperation(opType, path, data, dir)
    table.insert(profileSystem._batchOperations, {
        type = opType,
        path = path,
        data = data,
        dir = dir
    })

    -- Execute batch if queue gets large
    if #profileSystem._batchOperations >= 5 then
        profileSystem.ExecuteBatchOperations()
    end
end

-- Optimized profile list with caching
function profileSystem.GetAvailableProfiles()
    -- Return cached list if still valid
    if profileSystem._profileList and not profileSystem._listDirty then
        return profileSystem._profileList
    end

    local profiles = {}
    local files = file.Find(profileSystem.profilesDir .. "*.json", "DATA") or {}
    for _, fileName in ipairs(files) do
        local profileName = string.gsub(fileName, "%.json$", "")
        table.insert(profiles, profileName)
    end

    -- Cache the result
    profileSystem._profileList = profiles
    profileSystem._listDirty = false

    return profiles
end

-- Optimized profile saving with batch operations
function profileSystem.SaveProfile(profileName, profileData)
    if not profileData then
        profileData = profileSystem.LoadProfile(profileName)
        if not profileData then return false end
    end

    local fileName = profileSystem.profilesDir .. profileName .. ".json"
    local jsonData = util.TableToJSON(profileData, true)

    -- Queue for batch operation or execute immediately if urgent
    profileSystem.QueueFileOperation("write", fileName, jsonData, profileSystem.profilesDir) -- Update cache immediately with a fresh copy to avoid reference sharing
    if profileSystem._profileCache[profileName] then
        -- Clear the old cached data instead of returning to memory pool
        profileSystem._profileCache[profileName] = nil
    end

    -- Create a completely new table for caching using deep copy
    profileSystem._profileCache[profileName] = profileSystem.DeepCopyProfile(profileData)
    profileSystem._validationCache[profileName] = true -- Assume saved data is valid
    profileSystem._listDirty = true                    -- Mark list as dirty

    -- Execute batch operations for immediate saves
    profileSystem.ExecuteBatchOperations()
    profileSystem.UpdateProfileTimestamp(profileName)

    return true
end

-- Optimized profile loading with caching
function profileSystem.LoadProfile(profileName)
    if not profileName then return nil end

    -- Check cache first
    if profileSystem._profileCache[profileName] and profileSystem.IsProfileCacheValid(profileName) then
        profileSystem._stats.cacheHits = profileSystem._stats.cacheHits +
            1 -- Return a deep copy of cached data to prevent reference sharing
        return profileSystem.DeepCopyProfile(profileSystem._profileCache[profileName])
    end

    profileSystem._stats.cacheMisses = profileSystem._stats.cacheMisses + 1

    local fileName = profileSystem.profilesDir .. profileName .. ".json"
    if not file.Exists(fileName, "DATA") then return nil end

    local content = file.Read(fileName, "DATA")
    profileSystem._stats.fileOperations = profileSystem._stats.fileOperations + 1

    local success, data = pcall(util.JSONToTable, content)
    if success and data then
        -- Create a completely new profile copy to avoid reference sharing
        local cachedProfile = profileSystem.DeepCopyProfile(data)

        -- Validate only if not already validated
        if not profileSystem._validationCache[profileName] then
            local isValid, error = profileSystem.ValidateProfileData(cachedProfile)
            if not isValid then
                print("[RARELOAD] Warning: Profile '" .. profileName .. "' has invalid data: " .. error)
                print("[RARELOAD] This profile may need to be recreated or manually fixed")
            end
            profileSystem._validationCache[profileName] = isValid
        else
            profileSystem._stats.validationCacheHits = profileSystem._stats.validationCacheHits + 1
        end

        -- Cache the profile and update timestamp
        profileSystem._profileCache[profileName] = cachedProfile
        profileSystem.UpdateProfileTimestamp(profileName)

        -- Return another deep copy to ensure no reference sharing
        return profileSystem.DeepCopyProfile(cachedProfile)
    end
    return nil
end

function profileSystem.DeleteProfile(profileName)
    if profileName == "default" then return false, "Cannot delete default profile" end

    -- Check if profile exists
    local profile = profileSystem.LoadProfile(profileName)
    if not profile then return false, "Profile not found" end

    -- Remove from cache
    profileSystem.InvalidateProfileCache(profileName)

    -- Delete the file
    local fileName = profileSystem.profilesDir .. profileName .. ".json"
    if file.Exists(fileName, "DATA") then
        file.Delete(fileName)
    end

    -- Mark profile list as dirty
    profileSystem._listDirty = true

    return true
end

function profileSystem.DuplicateProfile(sourceProfile, newName, newDisplayName)
    -- Load the source profile
    local source = profileSystem.LoadProfile(sourceProfile)
    if not source then return false, "Source profile not found" end -- Create a copy with new metadata using deep copy
    local profileCopy = profileSystem.DeepCopyProfile(source)
    profileCopy.name = newName
    profileCopy.displayName = newDisplayName or (source.displayName .. " (Copy)")
    profileCopy.created = os.time()
    profileCopy.modified = os.time()
    profileCopy.author = LocalPlayer():Nick()
    profileCopy.shared = false -- Copies are not shared by default

    local success, error = profileSystem.CreateProfile(profileCopy)
    return success, error
end

function profileSystem.LoadCurrentProfile()
    -- Load the currently selected profile
    if file.Exists(profileSystem.selectedProfileFile, "DATA") then
        local content = file.Read(profileSystem.selectedProfileFile, "DATA")
        local success, data = pcall(util.JSONToTable, content)
        if success and data and data.selectedProfile then
            profileSystem.currentProfile = data.selectedProfile
        end
    end
end

function profileSystem.SaveCurrentProfile()
    file.CreateDir("rareload")
    local data = { selectedProfile = profileSystem.currentProfile }
    file.Write(profileSystem.selectedProfileFile, util.TableToJSON(data, true))
end

function profileSystem.EnsureDefaultProfile()
    -- Ensure directories exist
    file.CreateDir("rareload")
    file.CreateDir(profileSystem.profilesDir) -- Check if default profile exists, create if not
    local defaultFileName = profileSystem.profilesDir .. "default.json"
    if not file.Exists(defaultFileName, "DATA") then
        -- Get default settings if available
        local defaultProfile = {
            name = "default",
            displayName = "Default Settings",
            description = "Standard anti-stuck configuration",
            author = "System",
            created = os.time(),
            modified = os.time(),
            shared = false,
            mapSpecific = false,
            map = "",
            version = "1.0",
            settings = {},
            methods = {}
        }
        if Default_Anti_Stuck_Settings then
            defaultProfile.settings = profileSystem.DeepCopySettings(Default_Anti_Stuck_Settings)
        end

        -- Fix: Use Default_Anti_Stuck_Methods for methods, not settings
        if Default_Anti_Stuck_Methods then
            defaultProfile.methods = profileSystem.DeepCopyMethods(Default_Anti_Stuck_Methods)
            -- Ensure all default methods are enabled
            for _, method in ipairs(defaultProfile.methods) do
                if method.enabled == nil then
                    method.enabled = true
                end
            end
        end
        file.Write(defaultFileName, util.TableToJSON(defaultProfile, true))
        print("[RARELOAD] Created default anti-stuck profile")
    end
end

function profileSystem.ImportProfile(profileData)
    if not profileData or not profileData.name then return false, "Invalid profile data" end

    local name = profileData.name
    local fileName = profileSystem.profilesDir .. name .. ".json"
    if file.Exists(fileName, "DATA") then
        -- Ask for confirmation to overwrite
        return false, "Profile already exists"
    end

    file.CreateDir(profileSystem.profilesDir)
    file.Write(fileName, util.TableToJSON(profileData, true))

    return true
end

function profileSystem.ExportProfile(profileName)
    local profile = profileSystem.LoadProfile(profileName)
    if not profile then return nil end

    local exportData = {
        type = "rareload_antistuck_profile",
        version = "1.0",
        timestamp = os.time(),
        profile = profile
    }

    return util.TableToJSON(exportData, true)
end

-- Make sure the profile system reference is available globally
RARELOAD.profileSystem = profileSystem
_G.profileSystem = profileSystem
