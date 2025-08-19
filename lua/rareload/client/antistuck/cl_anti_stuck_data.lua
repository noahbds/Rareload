RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckData = RARELOAD.AntiStuckData or {}
RARELOAD.AntiStuckData.Methods = RARELOAD.AntiStuckData.Methods or {}

function RARELOAD.AntiStuckData.GetMethods()
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileMethods then
        local profileMethods = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileMethods()
        if profileMethods and #profileMethods > 0 then
            for _, method in ipairs(profileMethods) do
                if method.enabled == nil then
                    method.enabled = true
                end
            end
            return profileMethods
        end
    end
    local defaultMethods = table.Copy(Default_Anti_Stuck_Methods)
    for _, method in ipairs(defaultMethods) do
        method.enabled = true
    end
    return defaultMethods
end

function RARELOAD.AntiStuckData.SetMethods(methods)
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile then
        RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile(nil, methods)
    else
        Default_Anti_Stuck_Methods = methods
    end
end

function RARELOAD.AntiStuckData.GetDefaultMethods()
    return table.Copy(Default_Anti_Stuck_Methods)
end

function RARELOAD.AntiStuckData.ResetToDefaults()
    local defaultMethods = table.Copy(Default_Anti_Stuck_Methods)
    RARELOAD.AntiStuckData.SetMethods(defaultMethods)
    RARELOAD.AntiStuckData.SaveMethods()
    return defaultMethods
end

function RARELOAD.AntiStuckData.LoadMethods()
    local methods = RARELOAD.AntiStuckData.GetMethods()
    if not RARELOAD.__printedMethodLoad then
        print("[RARELOAD] Loaded " .. #methods .. " methods from current profile")
        RARELOAD.__printedMethodLoad = true
    end
    return methods
end

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

function RARELOAD.AntiStuckData.SaveMethods(methodsOverride)
    local currentMethods = methodsOverride or RARELOAD.AntiStuckData.GetMethods()
    local isValid, message = validateMethods(currentMethods)
    if not isValid then
        print("[RARELOAD] Error: Invalid methods data - " .. message)
        notification.AddLegacy("Methods validation failed: " .. message, NOTIFY_ERROR, 5)
        return false
    end

    print("[RARELOAD] Methods validation passed: " .. message)

    for i, m in ipairs(currentMethods) do
        m.priority = i * 10
    end

    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile then
        if not RARELOAD.AntiStuck.ProfileSystem._initialized then
            local okInit = pcall(RARELOAD.AntiStuck.ProfileSystem.Initialize)
            if not okInit then
                print("[RARELOAD] Warning: Profile system failed to initialize; cannot save methods right now")
            end
        end

        local currentProfileName = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
        if not currentProfileName then
            local setOk = RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile and
                RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile("default")
            if setOk == true then
                currentProfileName = "default"
            end
        end
        print("[RARELOAD] Saving methods to profile: " .. (currentProfileName or "unknown"))

        local success, okRet, err = pcall(function()
            return RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile(nil, currentMethods)
        end)

        if not success or okRet ~= true then
            local msg = tostring(err or "UpdateCurrentProfile returned false")
            print("[RARELOAD] Error updating profile: " .. msg)
            notification.AddLegacy("Failed to update profile: " .. tostring(err), NOTIFY_ERROR, 5)
            return false
        end

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

function RARELOAD.AntiStuckData.EnableAllMethods()
    local currentMethods = RARELOAD.AntiStuckData.GetMethods()
    for _, method in ipairs(currentMethods) do
        method.enabled = true
    end
    RARELOAD.AntiStuckData.SetMethods(currentMethods)
    RARELOAD.AntiStuckData.SaveMethods(currentMethods)
end

function RARELOAD.AntiStuckData.DisableAllMethods()
    local currentMethods = RARELOAD.AntiStuckData.GetMethods()
    for _, method in ipairs(currentMethods) do
        method.enabled = false
    end
    RARELOAD.AntiStuckData.SetMethods(currentMethods)
    RARELOAD.AntiStuckData.SaveMethods(currentMethods)
end

hook.Add("Initialize", "RareloadAntiStuckDataInit", function()
    RARELOAD.AntiStuckData.LoadMethods()
end)
