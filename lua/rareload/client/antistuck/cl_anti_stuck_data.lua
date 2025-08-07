-- Anti-Stuck Panel Data Management
-- Handles loading/saving Methods and method data

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckData = RARELOAD.AntiStuckData or {}

-- Get current method Methods
function RARELOAD.AntiStuckData.GetMethods()
    -- Get methods from current profile, not defaults
    if profileSystem and profileSystem.GetCurrentProfilemethods then
        local profileMethods = profileSystem.GetCurrentProfilemethods()
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
    if profileSystem and profileSystem.UpdateCurrentProfile then
        profileSystem.UpdateCurrentProfile(nil, methods)
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

-- Optimized methods loading with caching
function RARELOAD.AntiStuckData.LoadMethods()
    -- This function is now deprecated since GetMethods() handles profile loading
    -- It's kept for backward compatibility but just calls GetMethods()
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
        if type(v) ~= "table" or not v.func or not v.name then
            return false, "Each method must have 'func' and 'name' fields"
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
    if profileSystem and profileSystem.UpdateCurrentProfile then
        local currentProfileName = profileSystem.GetCurrentProfile()
        print("[RARELOAD] Saving methods to profile: " .. (currentProfileName or "unknown"))
        profileSystem.UpdateCurrentProfile(nil, currentMethods)

        -- Ensure server knows about the current profile
        if net and net.Start then
            net.Start("RareloadSyncServerProfile")
            net.WriteString(currentProfileName or "default")
            net.SendToServer()
        end
    end

    -- Send methods to server via dedicated methods network message
    net.Start("RareloadAntiStuckMethods")
    net.WriteTable(currentMethods)
    net.SendToServer()

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
