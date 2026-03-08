RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckData = RARELOAD.AntiStuckData or {}
RARELOAD.AntiStuckData.Methods = RARELOAD.AntiStuckData.Methods or {}

local function NormalizeMethodKey(str)
    if not isstring(str) then return nil end
    return string.lower(string.gsub(str, "[^%w]", ""))
end

local function BuildMethodLookup(methods)
    local byKey = {}
    methods = methods or {}

    for _, m in ipairs(methods) do
        if istable(m) then
            local func = m.func
            local name = m.name
            local keyFunc = NormalizeMethodKey(func)
            local keyName = NormalizeMethodKey(name)

            if keyFunc then byKey[keyFunc] = { func = func, name = name } end
            if keyName then byKey[keyName] = { func = func or name, name = name or func } end
        end
    end

    return byKey
end

local function NormalizeMethodEntry(method, lookup)
    if not istable(method) then return nil end

    local candidate = method.func or method.methodFunc or method.id or method.method or method.name
    local key = NormalizeMethodKey(candidate)
    local resolved = key and lookup[key] or nil

    local normalized = table.Copy(method)
    normalized.func = normalized.func or (resolved and resolved.func) or candidate
    normalized.name = normalized.name or (resolved and resolved.name) or tostring(normalized.func or "")

    return normalized
end

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

    local lookup = BuildMethodLookup(Default_Anti_Stuck_Methods)
    for _, m in ipairs(data) do
        if istable(m) and m.func then
            local k = NormalizeMethodKey(m.func)
            if k and not lookup[k] then
                lookup[k] = { func = m.func, name = m.name or m.func }
            end
        end
        if istable(m) and m.name then
            local k = NormalizeMethodKey(m.name)
            if k and not lookup[k] then
                lookup[k] = { func = m.func or m.name, name = m.name }
            end
        end
    end

    local count = 0
    local normalized = {}
    for k, v in ipairs(data) do
        if type(k) ~= "number" then
            return false, "Methods must be an array (numeric keys)"
        end
        if type(v) ~= "table" then
            return false, "Each method must be a table"
        end

        local method = NormalizeMethodEntry(v, lookup)
        if not method or not method.func or type(method.func) ~= "string" or method.func:Trim() == "" then
            return false, "Each method must have a valid 'func' field (string)"
        end
        if not method.name or type(method.name) ~= "string" or method.name:Trim() == "" then
            return false, "Each method must have a valid 'name' field (non-empty string)"
        end
        if method.enabled ~= nil and type(method.enabled) ~= "boolean" then
            return false, "Method 'enabled' field must be boolean or nil"
        end

        table.insert(normalized, method)
        count = count + 1
    end

    return count > 0, "Valid methods with " .. count .. " methods", normalized
end

function RARELOAD.AntiStuckData.SaveMethods(methodsOverride)
    local currentMethods = methodsOverride or RARELOAD.AntiStuckData.GetMethods()
    local isValid, message, normalizedMethods = validateMethods(currentMethods)
    if not isValid then
        print("[RARELOAD] Error: Invalid methods data - " .. message)
        notification.AddLegacy("Methods validation failed: " .. message, NOTIFY_ERROR, 5)
        return false
    end

    currentMethods = normalizedMethods or currentMethods

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
