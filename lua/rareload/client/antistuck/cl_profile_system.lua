RARELOAD = RARELOAD or {}

-- Core Profile System for managing different anti-stuck configurations
-- This file contains the core functionality and initialization
-- Other functionality is split into separate modules for better organization

-- Load the deep copy utility module first
include("cl_profile_deepcopy.lua")

-- Use existing profileSystem if present, else create new
local profileSystem = RARELOAD.profileSystem or _G.profileSystem
if not profileSystem then
    profileSystem = {
        profilesDir = "rareload/anti_stuck_profiles/",
        currentProfile = "default",
        selectedProfileFile = "rareload/anti_stuck_selected_profile.json",

        -- Performance optimization caches
        _profileCache = {},    -- Cache for loaded profiles
        _validationCache = {}, -- Cache for validation results
        _fileTimestamps = {},  -- Track file modification times
        _profileList = nil,    -- Cached profile list
        _listDirty = true,     -- Flag to refresh profile list
        _batchOperations = {}, -- Queue for batch file operations
        _memoryPool = {        -- Pre-allocated data structures
            tempProfiles = {},
            tempSettings = {},
            tempmethods = {}
        },

        -- Performance counters
        _stats = {
            cacheHits = 0,
            cacheMisses = 0,
            fileOperations = 0,
            validationCacheHits = 0
        }
    }
end

-- Make profile system globally accessible
RARELOAD.profileSystem = profileSystem
_G.profileSystem = profileSystem

print("[RARELOAD] Core profile system loaded with basic functions")


-- Core file operation functions that must be available immediately
-- These will delegate to the specialized modules when they're loaded

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

function profileSystem.LoadProfile(profileName)
    if not profileName then return nil end

    local fileName = profileSystem.profilesDir .. profileName .. ".json"
    if not file.Exists(fileName, "DATA") then
        print("[RARELOAD] Profile file does not exist: " .. fileName)
        return nil
    end

    local content = file.Read(fileName, "DATA")
    if not content or content == "" then
        print("[RARELOAD] Profile file is empty: " .. fileName)
        return nil
    end

    local success, data = pcall(util.JSONToTable, content)
    if success and data then
        print("[RARELOAD] Successfully loaded profile: " .. profileName)
        return data
    else
        print("[RARELOAD] Failed to parse profile JSON: " .. fileName)
        return nil
    end
end

function profileSystem.GetAvailableProfiles()
    local profiles = {}
    local files = file.Find(profileSystem.profilesDir .. "*.json", "DATA") or {}
    for _, fileName in ipairs(files) do
        local profileName = string.gsub(fileName, "%.json$", "")
        table.insert(profiles, profileName)
    end
    return profiles
end

function profileSystem.EnsureDefaultProfile()
    -- Ensure directories exist
    file.CreateDir("rareload")
    file.CreateDir(profileSystem.profilesDir)

    -- Check if default profile exists, create if not
    local defaultFileName = profileSystem.profilesDir .. "default.json"
    if not file.Exists(defaultFileName, "DATA") then
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
            settings = profileSystem.DeepCopySettings(Default_Anti_Stuck_Settings or {}),
            methods = profileSystem.DeepCopyMethods(Default_Anti_Stuck_Methods or {})
        }

        file.Write(defaultFileName, util.TableToJSON(defaultProfile, true))
        print("[RARELOAD] Created default anti-stuck profile")
    end
end

-- Initialize the profile system
function profileSystem.Init()
    if profileSystem._initialized then
        print("[RARELOAD] Profile system already initialized")
        return
    end

    -- Load required modules (they should already be loaded by file order)
    -- Initialize core functionality
    profileSystem.LoadCurrentProfile()
    profileSystem.EnsureDefaultProfile()

    -- Auto-load map-specific profile if exists
    local mapName = game.GetMap()
    local profiles = profileSystem.GetAvailableProfiles()
    for _, profileName in ipairs(profiles or {}) do
        local profile = profileSystem.LoadProfile(profileName)
        if profile and profile.autoLoad and profile.mapSpecific and profile.map == mapName then
            profileSystem.SetCurrentProfile(profileName)
            break
        end
    end

    profileSystem._initialized = true
    print("[RARELOAD] Profile system initialized with " .. #profiles .. " profiles")

    -- Initialize subsystems
    if profileSystem.InitCacheTimers then
        profileSystem.InitCacheTimers()
    end

    if profileSystem.InitBackupSystem then
        profileSystem.InitBackupSystem()
    end

    if profileSystem.InitHooks then
        profileSystem.InitHooks()
    end
end

-- Core profile creation function
function profileSystem.CreateProfile(profileData)
    local name = profileData.name
    if not name or name == "" then return false, "Profile name cannot be empty" end

    -- Validate profile data structure
    local isValid, error = profileSystem.ValidateProfileData(profileData)
    if not isValid then
        print("[RARELOAD] Profile validation failed: " .. error)
        return false, "Invalid profile data: " .. error
    end

    -- Sanitize profile name
    name = string.gsub(name, "[^%w%s%-_]", "")
    name = string.Trim(name)

    if name == "" then return false, "Invalid profile name" end

    -- Check if profile already exists
    local fileName = profileSystem.profilesDir .. name .. ".json"
    if file.Exists(fileName, "DATA") then
        return false, "Profile already exists"
    end

    -- Add map prefix if map-specific
    local finalName = name
    if profileData.mapSpecific then
        local mapName = game.GetMap()
        finalName = mapName .. "_" .. name
    end

    local profile = {
        name = finalName,
        displayName = profileData.displayName or name,
        description = profileData.description or "",
        author = LocalPlayer():Nick(),
        created = os.time(),
        modified = os.time(),
        shared = profileData.shared or false,
        mapSpecific = profileData.mapSpecific or false,
        map = profileData.mapSpecific and game.GetMap() or "",
        version = "1.0",
        autoLoad = profileData.autoLoad or false,
        backup = profileData.backup or false,
        settings = profileData.settings or profileSystem.DeepCopySettings(Default_Anti_Stuck_Settings or {}),
        methods = profileData.methods or profileSystem.DeepCopyMethods(Default_Anti_Stuck_Methods or {})
    }

    file.CreateDir(profileSystem.profilesDir)
    local finalFileName = profileSystem.profilesDir .. finalName .. ".json"
    file.Write(finalFileName, util.TableToJSON(profile, true))

    -- If shared, send to server
    if profile.shared then
        profileSystem.ShareProfile(finalName)
    end

    -- Mark the profile list as dirty so UIs can refresh
    profileSystem._listDirty = true

    return true, finalName
end

function profileSystem.SetCurrentProfile(profileName)
    if not profileName then return false end

    -- Verify profile exists
    if not profileSystem.LoadProfile(profileName) then return false end

    profileSystem.currentProfile = profileName
    profileSystem.SaveCurrentProfile()
    return true
end

function profileSystem.GetCurrentProfile()
    return profileSystem.currentProfile
end

-- Core profile settings management
function profileSystem.GetCurrentProfileSettings()
    local profile = profileSystem.LoadProfile(profileSystem.currentProfile)
    if profile and profile.settings then -- Return a deep copy to avoid accidental modifications to cached data
        local settings = {}
        for k, v in pairs(profile.settings) do
            if type(v) == "table" then
                settings[k] = profileSystem.DeepCopy(v)
            else
                settings[k] = v
            end
        end
        return settings
    end
    -- Always return a copy of defaults to prevent modification of the global defaults
    return profileSystem.DeepCopySettings(Default_Anti_Stuck_Settings or {})
end

function profileSystem.GetCurrentProfilemethods()
    local profile = profileSystem.LoadProfile(profileSystem.currentProfile)
    if profile and profile.methods then
        -- Return a deep copy
        return profileSystem.DeepCopyMethods(profile.methods)
    end
    return profileSystem.DeepCopyMethods(Default_Anti_Stuck_Methods or {})
end

-- Update current profile with new settings/methods
function profileSystem.UpdateCurrentProfile(settings, methods)
    local profile = profileSystem.LoadProfile(profileSystem.currentProfile)
    if not profile then
        print("[RARELOAD] Error: Cannot update current profile - profile not found: " ..
            tostring(profileSystem.currentProfile))
        return false
    end

    -- Validate settings if provided
    if settings then
        local isValid, error = profileSystem.ValidateSettings(settings)
        if not isValid then
            print("[RARELOAD] Error: Invalid settings data - " .. error)
            return false
        end
        profile.settings = profileSystem.DeepCopySettings(settings)
    end

    -- Validate methods if provided
    if methods then
        local isValid, error = profileSystem.Validatemethods(methods)
        if not isValid then
            print("[RARELOAD] Error: Invalid methods data - " .. error)
            return false
        end
        profile.methods = profileSystem.DeepCopyMethods(methods)
    end

    -- Update modification time
    profile.modified = os.time()

    -- Save the updated profile
    local fileName = profileSystem.profilesDir .. profileSystem.currentProfile .. ".json"
    file.CreateDir(profileSystem.profilesDir)
    file.Write(fileName, util.TableToJSON(profile, true))

    print("[RARELOAD] Updated profile: " .. (profile.displayName or profileSystem.currentProfile))
    return true
end

function profileSystem.ApplyProfile(profileName)
    local profile = profileSystem.LoadProfile(profileName)
    if not profile then return false end

    profileSystem.SetCurrentProfile(profileName)

    -- Notify server of profile change immediately
    if net and net.Start then
        net.Start("RareloadSyncServerProfile")
        net.WriteString(profileName)
        net.SendToServer()
    end

    -- Apply settings to UI/memory only - do NOT save to disk
    -- The settings should only be loaded into the current session
    -- Saving should only happen when user explicitly modifies and saves settings
    print("[RARELOAD] Applied profile: " .. (profile.displayName or profileName))

    -- Notify other systems that profile has changed
    hook.Call("RareloadProfileChanged", nil, profileName, profile)

    return true
end

-- Function to load profile settings into UI without saving to disk
function profileSystem.LoadProfileSettingsToUI(profileName)
    profileName = profileName or profileSystem.currentProfile
    local profile = profileSystem.LoadProfile(profileName)
    if not profile then return false end

    -- Notify UI components that settings and methods have changed (always use the profile's methods table)
    if RARELOAD and RARELOAD.AntiStuckSettings then
        hook.Call("RareloadProfileSettingsLoaded", nil, profile.settings, profile.methods)
    end

    return true
end

-- Function to save current UI settings to current profile (explicit save)
function profileSystem.SaveCurrentUIToProfile()
    if not RARELOAD or not RARELOAD.AntiStuckSettings then return false end

    -- Get current settings and methods from UI (UI must provide current method order)
    local currentSettings = RARELOAD.AntiStuckSettings.LoadSettings()
    local currentMethods = RARELOAD.AntiStuckSettings.LoadMethods and RARELOAD.AntiStuckSettings.LoadMethods() or
        profileSystem.GetCurrentProfilemethods()

    -- Save to current profile (ensures method order is saved per profile)
    return profileSystem.UpdateCurrentProfile(currentSettings, currentMethods)
end

-- Function to get any profile's settings without changing current profile
function profileSystem.GetProfileSettings(profileName)
    local profile = profileSystem.LoadProfile(profileName or profileSystem.currentProfile)
    if not profile then return nil, nil end

    return profile.settings, profile.methods
end

-- Function to safely switch profiles (will prompt to save if current profile has unsaved changes)
function profileSystem.SafeSwitchProfile(newProfileName, forceSwitch)
    if not newProfileName then return false end

    -- Check if switching to the same profile
    if profileSystem.currentProfile == newProfileName then
        print("[RARELOAD] Already using profile: " .. newProfileName)
        return true
    end

    -- TODO: Add dirty checking here if needed
    -- For now, just switch
    local success = profileSystem.ApplyProfile(newProfileName)
    if success then
        profileSystem.LoadProfileSettingsToUI(newProfileName)
        print("[RARELOAD] Switched to profile: " .. newProfileName)

        -- Notify other systems that profile has changed
        local profile = profileSystem.LoadProfile(newProfileName)
        hook.Call("RareloadProfileChanged", nil, newProfileName, profile)
    end

    return success
end

-- Essential utility functions that must be available immediately
function profileSystem.ShareProfile(profileName)
    local profile = profileSystem.LoadProfile(profileName)
    if not profile then return false end

    -- Send profile to server for distribution
    if net and net.Start then
        net.Start("RareloadShareAntiStuckProfile")
        net.WriteTable(profile)
        net.SendToServer()
    end

    return true
end

function profileSystem.GetProfilesList()
    local list = {}
    local profiles = profileSystem.GetAvailableProfiles()

    for _, profileName in ipairs(profiles) do
        local profile = profileSystem.LoadProfile(profileName)
        if profile then
            table.insert(list, {
                name = profileName,
                displayName = profile.displayName,
                description = profile.description,
                author = profile.author,
                shared = profile.shared,
                mapSpecific = profile.mapSpecific,
                map = profile.map
            })
        end
    end

    -- Sort by display name
    table.sort(list, function(a, b) return a.displayName < b.displayName end)
    return list
end

-- Basic cache and memory management stubs
function profileSystem.GetFromMemoryPool(poolName)
    return {}
end

function profileSystem.ReturnToMemoryPool(poolName, obj)
    -- Stub function
end

-- Basic validation function (more comprehensive version in cl_profile_validation.lua)
function profileSystem.ValidateProfileData(profileData)
    if not profileData then return false, "Profile data is nil" end

    -- Basic structure validation
    if profileData.settings and type(profileData.settings) ~= "table" then
        return false, "Settings must be a table"
    end

    if profileData.methods and type(profileData.methods) ~= "table" then
        return false, "methods must be a table"
    end

    return true, "Profile data is valid"
end

-- Basic validation functions for settings and methods
function profileSystem.ValidateSettings(data)
    if type(data) ~= "table" then
        return false, "Settings must be a table"
    end
    return true, "Valid settings"
end

function profileSystem.Validatemethods(data)
    if type(data) ~= "table" then
        return false, "methods must be a table"
    end
    return true, "Valid methods"
end

-- Initialize the profile system when the file loads
timer.Simple(0.5, function()
    local success, err = pcall(profileSystem.Init)
    if success then
        print("[RARELOAD] Profile system initialized successfully")
    else
        print("[RARELOAD] Error initializing profile system: " .. tostring(err))
    end
end)

-- Backup initialization in case the first one fails
timer.Simple(2, function()
    if not profileSystem._initialized then
        print("[RARELOAD] Attempting backup profile system initialization")
        local success, err = pcall(profileSystem.Init)
        if success then
            print("[RARELOAD] Profile system initialized successfully (backup)")
        else
            print("[RARELOAD] Error in backup profile system initialization: " .. tostring(err))
        end
    end
end)

function profileSystem.SaveProfile(profileName, profileData)
    if not profileData then
        profileData = profileSystem.LoadProfile(profileName)
        if not profileData then return false end
    end

    local fileName = profileSystem.profilesDir .. profileName .. ".json"
    file.CreateDir(profileSystem.profilesDir)
    file.Write(fileName, util.TableToJSON(profileData, true))
    return true
end
