RARELOAD = RARELOAD or {}

-- Profile Console Commands Module
-- Handles all console commands for profile management
-- This module extends the basic functionality from cl_profile_system.lua

local profileSystem = RARELOAD.profileSystem or _G.profileSystem or {}

-- Ensure deep copy utilities are available
if not profileSystem.DeepCopy then
    include("cl_profile_deepcopy.lua")
end

print("[RARELOAD] Loading profile console commands module")

-- Console command to manually initialize profile system
concommand.Add("rareload_init_profile_system", function()
    local success, err = pcall(profileSystem.Init)
    if success then
        LocalPlayer():ChatPrint("[RARELOAD] Profile system initialized successfully")
    else
        LocalPlayer():ChatPrint("[RARELOAD] Error initializing profile system: " .. tostring(err))
    end
end)

-- Console command to fix corrupted profiles
concommand.Add("rareload_fix_corrupted_profiles", function()
    local profiles = profileSystem.GetAvailableProfiles() or {}
    local fixedCount = 0
    local errorCount = 0

    for _, profileName in ipairs(profiles) do
        local profile = profileSystem.LoadProfile(profileName)
        if profile then
            local isValid, error = profileSystem.ValidateProfileData(profile)
            if not isValid then
                print("[RARELOAD] Fixing corrupted profile: " .. profileName)
                print("[RARELOAD] Error was: " .. error)

                -- If settings contains methods data, move it to methods
                if profile.settings and type(profile.settings) == "table" then
                    local hasNumericKeys = false
                    for k, v in pairs(profile.settings) do
                        if type(k) == "number" and type(v) == "table" and v.func and v.name then
                            hasNumericKeys = true
                            break
                        end
                    end

                    if hasNumericKeys then
                        -- Settings contains methods data, fix it
                        profile.methods = profileSystem.DeepCopyMethods(profile.settings)
                        profile.settings = profileSystem.DeepCopySettings(Default_Anti_Stuck_Settings or {})

                        -- Save the fixed profile
                        if profileSystem.SaveProfile(profileName, profile) then
                            fixedCount = fixedCount + 1
                            print("[RARELOAD] Fixed profile: " .. profileName)
                        else
                            errorCount = errorCount + 1
                            print("[RARELOAD] Failed to save fixed profile: " .. profileName)
                        end
                    end
                end
            end
        end
    end

    LocalPlayer():ChatPrint("[RARELOAD] Profile fix complete. Fixed: " .. fixedCount .. ", Errors: " .. errorCount)
end)

-- Console commands for cache management and performance monitoring
concommand.Add("rareload_profile_cache_stats", function()
    local stats = profileSystem.GetCacheStats()
    print("[RARELOAD] Profile Cache Statistics:")
    print("  Cache Size: " .. stats.cacheSize)
    print("  Cache Hits: " .. stats.cacheHits)
    print("  Cache Misses: " .. stats.cacheMisses)
    print("  Hit Rate: " .. math.Round(stats.hitRate * 100, 2) .. "%")
    print("  File Operations: " .. stats.fileOperations)
    print("  Validation Cache Hits: " .. stats.validationCacheHits)
end)

concommand.Add("rareload_profile_clear_cache", function()
    profileSystem.InvalidateAllCaches()
    LocalPlayer():ChatPrint("[RARELOAD] Profile cache cleared")
end)

concommand.Add("rareload_profile_cleanup_cache", function()
    profileSystem.CleanupCache()
    LocalPlayer():ChatPrint("[RARELOAD] Profile cache cleaned up")
end)

concommand.Add("rareload_profile_force_batch_ops", function()
    if #profileSystem._batchOperations > 0 then
        profileSystem.ExecuteBatchOperations()
        LocalPlayer():ChatPrint("[RARELOAD] Executed " .. #profileSystem._batchOperations .. " batch operations")
    else
        LocalPlayer():ChatPrint("[RARELOAD] No pending batch operations")
    end
end)

-- Profile management commands
concommand.Add("rareload_profile_list", function()
    local profiles = profileSystem.GetProfilesList()
    print("[RARELOAD] Available profiles:")
    for _, profile in ipairs(profiles) do
        local status = profile.name == profileSystem.GetCurrentProfile() and " (CURRENT)" or ""
        print("  " .. profile.name .. " - " .. profile.displayName .. status)
    end
end)

concommand.Add("rareload_profile_switch", function(ply, cmd, args)
    if not args[1] then
        LocalPlayer():ChatPrint("[RARELOAD] Usage: rareload_profile_switch <profile_name>")
        return
    end

    local success = profileSystem.SafeSwitchProfile(args[1])
    if success then
        LocalPlayer():ChatPrint("[RARELOAD] Switched to profile: " .. args[1])
    else
        LocalPlayer():ChatPrint("[RARELOAD] Failed to switch to profile: " .. args[1])
    end
end)

concommand.Add("rareload_profile_backup", function()
    profileSystem.CreateProfileBackup()
    LocalPlayer():ChatPrint("[RARELOAD] Profile backup created")
end)

-- Make sure the profile system reference is available globally
RARELOAD.profileSystem = profileSystem
_G.profileSystem = profileSystem
