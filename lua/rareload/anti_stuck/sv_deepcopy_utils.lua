-- Server-side Deep Copy Utility Module
-- Provides a true deep copy function for profile data to prevent reference sharing

-- True deep copy function that handles circular references and all data types
local function DeepCopy(original, copies)
    copies = copies or {}
    local originalType = type(original)
    local copy

    if originalType == 'table' then
        if copies[original] then
            return copies[original]
        end
        copy = {}
        copies[original] = copy
        for originalKey, originalValue in next, original, nil do
            copy[DeepCopy(originalKey, copies)] = DeepCopy(originalValue, copies)
        end
        setmetatable(copy, DeepCopy(getmetatable(original), copies))
    else -- number, string, boolean, etc
        copy = original
    end
    return copy
end

-- Specialized deep copy function for profile settings
-- Optimized for the specific structure of anti-stuck settings
local function DeepCopySettings(settings)
    if not settings or type(settings) ~= "table" then
        return {}
    end

    local copy = {}
    for key, value in pairs(settings) do
        if type(value) == "table" then
            -- Deep copy nested tables (like METHOD_ENABLE_FLAGS)
            copy[key] = DeepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

-- Specialized deep copy function for profile methods
-- Optimized for the specific structure of anti-stuck methods
local function DeepCopyMethods(methods)
    if not methods or type(methods) ~= "table" then
        return {}
    end

    local copy = {}
    for i, method in ipairs(methods) do
        if type(method) == "table" then
            copy[i] = {
                name = method.name,
                func = method.func,
                enabled = method.enabled,
                description = method.description
            }
            -- Copy any additional properties
            for key, value in pairs(method) do
                if key ~= "name" and key ~= "func" and key ~= "enabled" and key ~= "description" then
                    if type(value) == "table" then
                        copy[i][key] = DeepCopy(value)
                    else
                        copy[i][key] = value
                    end
                end
            end
        else
            copy[i] = method
        end
    end
    return copy
end

-- Make functions available globally for server-side use
_G.RareloadDeepCopy = DeepCopy
_G.RareloadDeepCopySettings = DeepCopySettings
_G.RareloadDeepCopyMethods = DeepCopyMethods

print("[RARELOAD] Server-side deep copy utility functions loaded")
