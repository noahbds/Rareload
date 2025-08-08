-- Anti-Stuck Panel Data Management
-- Handles loading/saving Methods and method data

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckData = RARELOAD.AntiStuckData or {}
RARELOAD.AntiStuckData.Methods = RARELOAD.AntiStuckData.Methods or {}

-- Get current method Methods
function RARELOAD.AntiStuckData.GetMethods()
    -- Get methods from current profile, not defaults
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileMethods then
        local profileMethods = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileMethods()
        if profileMethods and #profileMethods > 0 then
            -- Ensure all methods have enabled field set
            for _, method in ipairs(profileMethods) do
                if method.enabled == nil then
                    method.enabled = true -- Default to enabled if not specified
                end
            end
            return profileMethods
        end
    end
    -- Fallback to defaults only if profile system is not available
    local defaultMethods = table.Copy(Default_Anti_Stuck_Methods)
    -- Ensure all default methods are enabled
    for _, method in ipairs(defaultMethods) do
        method.enabled = true
    end
    return defaultMethods
end

-- Set method Methods
function RARELOAD.AntiStuckData.SetMethods(methods)
    -- Update the current profile, not defaults
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile then
        RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile(nil, methods)
    else
        -- Fallback if profile system not available
        Default_Anti_Stuck_Methods = methods
    end
end

-- Get default Methods
function RARELOAD.AntiStuckData.GetDefaultMethods()
    return table.Copy(Default_Anti_Stuck_Methods)
end

-- Reset to default Methods
function RARELOAD.AntiStuckData.ResetToDefaults()
    local defaultMethods = table.Copy(Default_Anti_Stuck_Methods)
    RARELOAD.AntiStuckData.SetMethods(defaultMethods)
    RARELOAD.AntiStuckData.SaveMethods()
    return defaultMethods
end

-- Optimized methods loading
function RARELOAD.AntiStuckData.LoadMethods()
    local methods = RARELOAD.AntiStuckData.GetMethods()
    print("[RARELOAD] Loaded " .. #methods .. " methods from current profile")
    return methods
end

-- Validate methods structure
local function validateMethods(data)
    if type(data) ~= "table" then
        return false, "Methods must be a table"
    end

    local count = 0
    for k, v in pairs(data) do
        if type(k) ~= "number" then
            return false, "Methods must be an array (numeric keys)"
        end
        if type(v) ~= "table" then
            return false, "Each method must be a table"
        end
        if not v.func or type(v.func) ~= "string" then
            return false, "Each method must have a valid 'func' field (string)"
        end
        if not v.name or type(v.name) ~= "string" or v.name:Trim() == "" then
            return false, "Each method must have a valid 'name' field (non-empty string)"
        end
        if v.enabled ~= nil and type(v.enabled) ~= "boolean" then
            return false, "Method 'enabled' field must be boolean or nil"
        end
        count = count + 1
    end

    return count > 0, "Valid methods with " .. count .. " methods"
end

-- Optimized methods saving with batch operations
function RARELOAD.AntiStuckData.SaveMethods()
    -- Get current methods from profile
    local currentMethods = RARELOAD.AntiStuckData.GetMethods()

    -- Validate methods structure before saving (optimized)
    local isValid, message = validateMethods(currentMethods)
    if not isValid then
        print("[RARELOAD] Error: Invalid methods data - " .. message)
        notification.AddLegacy("Methods validation failed: " .. message, NOTIFY_ERROR, 5)
        return false
    end

    print("[RARELOAD] Methods validation passed: " .. message)

    -- Save methods to current profile (separate from settings)
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile then
        local currentProfileName = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
        print("[RARELOAD] Saving methods to profile: " .. (currentProfileName or "unknown"))

        local success, err = pcall(function()
            RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile(nil, currentMethods)
        end)

        if not success then
            print("[RARELOAD] Error updating profile: " .. tostring(err))
            notification.AddLegacy("Failed to update profile: " .. tostring(err), NOTIFY_ERROR, 5)
            return false
        end

        -- Ensure server knows about the current profile
        if net and net.Start then
            local netSuccess, netErr = pcall(function()
                net.Start("RareloadSyncServerProfile")
                net.WriteString(currentProfileName or "default")
                net.SendToServer()
            end)

            if not netSuccess then
                print("[RARELOAD] Warning: Failed to sync profile to server: " .. tostring(netErr))
            end
        end
    end

    -- Send methods to server via dedicated methods network message
    if net and net.Start then
        local netSuccess, netErr = pcall(function()
            net.Start("RareloadAntiStuckMethods")
            net.WriteTable(currentMethods)
            net.SendToServer()
        end)

        if not netSuccess then
            print("[RARELOAD] Error sending methods to server: " .. tostring(netErr))
            notification.AddLegacy("Failed to sync methods to server", NOTIFY_ERROR, 3)
            return false
        end
    else
        print("[RARELOAD] Warning: Network system not available")
        return false
    end

    return true
end

-- Enable all methods
function RARELOAD.AntiStuckData.EnableAllMethods()
    local currentMethods = RARELOAD.AntiStuckData.GetMethods()
    for _, method in ipairs(currentMethods) do
        method.enabled = true
    end
    RARELOAD.AntiStuckData.SetMethods(currentMethods)
    RARELOAD.AntiStuckData.SaveMethods()
end

-- Disable all methods
function RARELOAD.AntiStuckData.DisableAllMethods()
    local currentMethods = RARELOAD.AntiStuckData.GetMethods()
    for _, method in ipairs(currentMethods) do
        method.enabled = false
    end
    RARELOAD.AntiStuckData.SetMethods(currentMethods)
    RARELOAD.AntiStuckData.SaveMethods()
end

-- Initialize data on startup
hook.Add("Initialize", "RareloadAntiStuckDataInit", function()
    RARELOAD.AntiStuckData.LoadMethods()
end)
