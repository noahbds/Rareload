-- Profile System Integration Test
-- This file helps verify that the improved profile system works correctly
-- This is not useful for players, it is for development purposes only

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuck.ProfileSystem = RARELOAD.AntiStuck.ProfileSystem or {}
RARELOAD.ProfileTest = {}

local function PrintTest(name, success, message)
    local color = success and "[32m" or "[31m" -- Green for success, red for failure
    print(string.format("%s[TEST] %s: %s%s[0m", color, name, success and "PASS" or "FAIL",
        message and " - " .. message or ""))
end

local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    return success, result
end

local function RunTests()
    print("\n=== Profile System Integration Tests ===")

    -- Test 1: System availability
    local systemAvailable = RARELOAD.AntiStuck.ProfileSystem ~= nil
    PrintTest("System Availability", systemAvailable,
        systemAvailable and "Profile system loaded" or "Profile system not found")

    if not systemAvailable then
        print("[31m[ERROR] Profile system not available, aborting tests[0m")
        return
    end

    -- Test 2: System initialization
    local initSuccess, initError = SafeCall(function()
        if RARELOAD.AntiStuck.ProfileSystem.Initialize then
            RARELOAD.AntiStuck.ProfileSystem.Initialize()
        end
        return RARELOAD.AntiStuck.ProfileSystem._initialized or true
    end)
    PrintTest("System Initialization", initSuccess,
        initSuccess and "Initialized successfully" or "Error: " .. tostring(initError))

    -- Test 3: Current profile access
    local currentSuccess, currentProfile = SafeCall(RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile)
    PrintTest("Current Profile Access", currentSuccess and currentProfile ~= nil,
        currentSuccess and ("Current: " .. tostring(currentProfile)) or "Error: " .. tostring(currentProfile))

    -- Test 4: Profile loading with error handling
    local loadSuccess, defaultProfile = SafeCall(RARELOAD.AntiStuck.ProfileSystem.LoadProfile, "default")
    PrintTest("Default Profile Load", loadSuccess and defaultProfile ~= nil,
        loadSuccess and "Loaded successfully" or "Error: " .. tostring(defaultProfile))

    -- Test 5: Profile list with error handling
    local listSuccess, profileList = SafeCall(RARELOAD.AntiStuck.ProfileSystem.GetProfileList)
    local listValid = listSuccess and profileList ~= nil and type(profileList) == "table"
    PrintTest("Profile List", listValid,
        listValid and (#profileList .. " profiles found") or "Error getting profile list")

    -- Test 6: Profile methods access
    local methodsSuccess, methods = SafeCall(RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileMethods)
    PrintTest("Profile Methods", methodsSuccess and methods ~= nil,
        methodsSuccess and (#(methods or {}) .. " methods") or "Error getting methods")

    -- Test 7: Profile settings access
    local settingsSuccess, settings = SafeCall(RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileSettings)
    PrintTest("Profile Settings", settingsSuccess and settings ~= nil,
        settingsSuccess and "Settings available" or "Error getting settings")

    -- Test 8: Create test profile with validation
    local testProfile = {
        name = "test_profile",
        displayName = "Test Profile",
        description = "Automated test profile - safe to delete",
        author = "Test System",
        methods = {
            { name = "space_scan",   enabled = true,  priority = 10 },
            { name = "displacement", enabled = false, priority = 20 }
        },
        settings = {
            maxAttempts = 5,
            timeout = 3,
            debug = true
        }
    }

    local saveSuccess, saveError = SafeCall(RARELOAD.AntiStuck.ProfileSystem.SaveProfile, "test_profile", testProfile)
    PrintTest("Profile Creation", saveSuccess,
        saveSuccess and "Created successfully" or "Error: " .. tostring(saveError))

    -- Test 9: Load created profile
    if saveSuccess then
        local loadTestSuccess, loadedProfile = SafeCall(RARELOAD.AntiStuck.ProfileSystem.LoadProfile, "test_profile")
        local loadValid = loadTestSuccess and loadedProfile and loadedProfile.name == "test_profile"
        PrintTest("Test Profile Load", loadValid,
            loadValid and "Loaded correctly" or "Load failed")

        -- Test 10: Profile validation
        local profileValid = loadedProfile and
            loadedProfile.name and
            loadedProfile.methods and
            loadedProfile.settings
        PrintTest("Profile Data Integrity", profileValid,
            profileValid and "All required fields present" or "Missing required fields")

        -- Test 11: Switch to test profile safely
        local currentProfile = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
        local switchSuccess, switchError = SafeCall(RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile, "test_profile")
        PrintTest("Profile Switching", switchSuccess,
            switchSuccess and "Switched successfully" or "Error: " .. tostring(switchError))

        -- Test 12: Verify current profile changed
        if switchSuccess then
            local newCurrentSuccess, newCurrentProfile = SafeCall(RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile)
            local verifySuccess = newCurrentSuccess and newCurrentProfile == "test_profile"
            PrintTest("Profile Switch Verification", verifySuccess,
                verifySuccess and "Profile switched" or "Switch verification failed")
        end

        -- Test 13: Switch back to original profile
        if currentProfile then
            SafeCall(RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile, currentProfile)
        end

        -- Test 14: Delete test profile (cleanup)
        local deleteSuccess, deleteError = SafeCall(RARELOAD.AntiStuck.ProfileSystem.DeleteProfile, "test_profile")
        PrintTest("Profile Deletion", deleteSuccess,
            deleteSuccess and "Deleted successfully" or "Error: " .. tostring(deleteError))
    end

    -- Test 15: Performance test
    local startTime = SysTime()
    local performanceSuccess = true
    for i = 1, 10 do
        local success = SafeCall(RARELOAD.AntiStuck.ProfileSystem.LoadProfile, "default")
        if not success then
            performanceSuccess = false
            break
        end
    end
    local endTime = SysTime()
    local avgTime = (endTime - startTime) / 10
    PrintTest("Performance Test", performanceSuccess and avgTime < 0.010,
        string.format("Avg: %.2fms (%s)", avgTime * 1000, performanceSuccess and "OK" or "FAILED"))

    -- Test 16: Cache system test
    local cacheSuccess = true
    if RARELOAD.AntiStuck.ProfileSystem.GetStats then
        local stats = RARELOAD.AntiStuck.ProfileSystem.GetStats()
        cacheSuccess = stats and type(stats) == "table"
        PrintTest("Cache System", cacheSuccess,
            cacheSuccess and "Stats available" or "Cache system error")
    else
        PrintTest("Cache System", false, "GetStats method not available")
    end

    -- Test 17: Error handling test
    local errorSuccess1 = not SafeCall(RARELOAD.AntiStuck.ProfileSystem.LoadProfile, nil)
    local errorSuccess2 = not SafeCall(RARELOAD.AntiStuck.ProfileSystem.SaveProfile, "", {})
    local errorSuccess3 = not SafeCall(RARELOAD.AntiStuck.ProfileSystem.DeleteProfile, "default")
    PrintTest("Error Handling", errorSuccess1 and errorSuccess2 and errorSuccess3,
        "Invalid operations properly rejected")

    print("\n=== Profile System Tests Complete ===\n")

    -- Return test results for external use
    return {
        systemAvailable = systemAvailable,
        initSuccess = initSuccess,
        profilesWorking = currentSuccess and loadSuccess and listSuccess
    }
end

-- Auto-run tests with delay to ensure system is ready
local function DelayedTest()
    timer.Simple(1, function()
        if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem._initialized then
            RunTests()
        else
            print("[ProfileTest] Profile system not ready, retrying...")
            timer.Simple(2, DelayedTest)
        end
    end)
end

concommand.Add("rareload_test_profiles", RunTests)

if GetConVar("developer"):GetInt() > 0 then
    DelayedTest()
end

RARELOAD.ProfileTest.RunTests = RunTests

print("[RARELOAD] Enhanced profile system tests loaded. Run 'rareload_test_profiles' to test.")
