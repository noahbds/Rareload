RARELOAD = RARELOAD or {}

-- Profile Utility Functions Module
-- Handles backup system, hooks, and various utility functions
-- This module extends the basic functions from cl_profile_system.lua

local profileSystem = RARELOAD.profileSystem or _G.profileSystem or {}

-- Ensure deep copy utilities are available
if not profileSystem.DeepCopy then
    include("cl_profile_deepcopy.lua")
end

print("[RARELOAD] Loading profile utility functions module")

-- Profile backup system
local function CreateProfileBackup()
    local profiles = profileSystem.GetAvailableProfiles()
    local profileData = {}

    for _, profileName in ipairs(profiles) do
        local profile = profileSystem.LoadProfile(profileName)
        if profile then
            profileData[profileName] = profile
        end
    end

    local backupData = {
        timestamp = os.time(),
        profiles = profileData,
        version = "1.0"
    }

    file.CreateDir("rareload/backups")
    local backupFile = "rareload/backups/profiles_backup_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    file.Write(backupFile, util.TableToJSON(backupData, true))

    -- Keep only last 10 backups
    local backups = file.Find("rareload/backups/profiles_backup_*.json", "DATA")
    if #backups > 10 then
        table.sort(backups)
        for i = 1, #backups - 10 do
            file.Delete("rareload/backups/" .. backups[i])
        end
    end
end

function profileSystem.CreateProfileBackup()
    return CreateProfileBackup()
end

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

function profileSystem.DuplicateProfile(sourceProfile, newName, newDisplayName)
    local source = profileSystem.LoadProfile(sourceProfile)
    if not source then return false, "Source profile not found" end

    local duplicateData = profileSystem.DeepCopyProfile(source)
    duplicateData.name = newName
    duplicateData.displayName = newDisplayName or (duplicateData.displayName .. " (Copy)")
    duplicateData.created = os.time()
    duplicateData.modified = os.time()
    duplicateData.author = LocalPlayer():Nick()
    duplicateData.shared = false -- Copies are not shared by default

    local success, error = profileSystem.CreateProfile(duplicateData)
    return success, error
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

-- Initialize backup system
function profileSystem.InitBackupSystem()
    -- Create backup every 30 minutes
    timer.Create("RareloadProfileBackup", 1800, 0, CreateProfileBackup)

    -- Create initial backup
    timer.Simple(5, CreateProfileBackup)
end

-- Initialize hook system
function profileSystem.InitHooks()
    -- Auto-load map-specific profiles
    hook.Add("InitPostEntity", "RareloadAutoLoadMapProfile", function()
        timer.Simple(1, function()
            local mapName = game.GetMap()
            local profiles = profileSystem.GetProfilesList() or {}

            for _, profile in ipairs(profiles) do
                if profile.mapSpecific and profile.map == mapName then
                    profileSystem.ApplyProfile(profile.name)
                    break
                end
            end
        end)
    end)
end

-- Initialize cache maintenance timers
function profileSystem.InitCacheTimers()
    -- Start cache maintenance timer
    timer.Create("RareloadProfileCacheMaintenance", 30, 0, function()
        profileSystem.CleanupCache()
    end)

    -- Periodic batch operation execution
    timer.Create("RareloadProfileBatchOps", 2, 0, function()
        if #profileSystem._batchOperations > 0 then
            profileSystem.ExecuteBatchOperations()
        end
    end)
end

-- Make sure the profile system reference is available globally
RARELOAD.profileSystem = profileSystem
_G.profileSystem = profileSystem
