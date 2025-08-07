-- Profile System Initialization Helper
-- Ensures proper initialization order and handles dependencies

RARELOAD = RARELOAD or {}
RARELOAD.ProfileInit = {}

local initOrder = {
    "cl_profile_config.lua",
    "cl_profile_system.lua",
    "cl_profile_performance.lua",
    "cl_profile_creator.lua",
    "cl_profile_manager.lua"
}

local initialized = {}
local initAttempts = 0
local maxInitAttempts = 3

-- Initialize profile system components in correct order
function RARELOAD.ProfileInit.Initialize()
    if RARELOAD.ProfileInit._initialized then
        return true
    end

    initAttempts = initAttempts + 1
    if initAttempts > maxInitAttempts then
        print("[RARELOAD] Profile system initialization failed after " .. maxInitAttempts .. " attempts")
        return false
    end

    print("[RARELOAD] Initializing optimized profile system... (Attempt " .. initAttempts .. ")")

    -- Check if profile system exists and is ready
    if not profileSystem then
        print("[RARELOAD] Profile system not loaded yet, will retry later")
        if initAttempts <= maxInitAttempts then
            timer.Simple(2, function()
                RARELOAD.ProfileInit.Initialize()
            end)
        end
        return false
    end

    -- Initialize profile system
    if profileSystem.Init then
        local success, err = pcall(profileSystem.Init)
        if not success then
            print("[RARELOAD] Error initializing profile system: " .. tostring(err))
            if initAttempts <= maxInitAttempts then
                timer.Simple(2, function()
                    RARELOAD.ProfileInit.Initialize()
                end)
            end
            return false
        end
    end

    -- Start performance monitoring if available
    if RARELOAD.ProfilePerformance and RARELOAD.ProfilePerformance.StartMonitoring then
        RARELOAD.ProfilePerformance.StartMonitoring()
    end

    RARELOAD.ProfileInit._initialized = true
    print("[RARELOAD] Optimized profile system initialization complete!")

    -- Clean up any existing timers to prevent further attempts
    timer.Remove("RareloadProfileInit")
    timer.Remove("RareloadProfileInitBackup")

    return true
end

-- Mark component as initialized (simplified)
function RARELOAD.ProfileInit.MarkInitialized(component)
    initialized[component] = true
end

-- Only initialize once, with proper timer management
if not RARELOAD.ProfileInit._initialized then
    timer.Simple(1, function()
        if not RARELOAD.ProfileInit._initialized then
            RARELOAD.ProfileInit.Initialize()
        end
    end)
end

-- Console commands for initialization management
concommand.Add("rareload_profile_reinit", function()
    RARELOAD.ProfileInit._initialized = false
    initAttempts = 0
    timer.Remove("RareloadProfileInit")
    timer.Remove("RareloadProfileInitBackup")
    print("[RARELOAD] Profile system reset. Reinitializing...")
    RARELOAD.ProfileInit.Initialize()
end)

concommand.Add("rareload_profile_init_status", function()
    print("[RARELOAD] Profile system initialization status:")
    print("  Initialized: " .. tostring(RARELOAD.ProfileInit._initialized or false))
    print("  Attempts: " .. initAttempts .. "/" .. maxInitAttempts)
    print("  Profile system exists: " .. tostring(profileSystem ~= nil))
    if profileSystem then
        print("  Current profile: " .. tostring(profileSystem.currentProfile))
        print("  Cache size: " .. table.Count(profileSystem._profileCache or {}))
    end
end)
