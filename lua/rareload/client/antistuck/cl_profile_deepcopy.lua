RARELOAD = RARELOAD or {}

-- Deep Copy Utility Module
-- Provides a true deep copy function for profile data to prevent reference sharing

local profileSystem = RARELOAD.profileSystem or _G.profileSystem or {}

print("[RARELOAD] Loading deep copy utility module")

-- True deep copy function that handles circular references and all data types
function profileSystem.DeepCopy(original, copies)
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
            copy[profileSystem.DeepCopy(originalKey, copies)] = profileSystem.DeepCopy(originalValue, copies)
        end
        setmetatable(copy, profileSystem.DeepCopy(getmetatable(original), copies))
    else -- number, string, boolean, etc
        copy = original
    end
    return copy
end

-- Specialized deep copy function for profile settings
-- Optimized for the specific structure of anti-stuck settings
function profileSystem.DeepCopySettings(settings)
    if not settings or type(settings) ~= "table" then
        return {}
    end

    local copy = {}
    for key, value in pairs(settings) do
        if type(value) == "table" then
            -- Deep copy nested tables (like METHOD_ENABLE_FLAGS)
            copy[key] = profileSystem.DeepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

-- Specialized deep copy function for profile methods
-- Optimized for the specific structure of anti-stuck methods
function profileSystem.DeepCopyMethods(methods)
    if not methods or type(methods) ~= "table" then
        return {}
    end

    local copy = {}
    for i, method in ipairs(methods) do
        if type(method) == "table" then
            copy[i] = {
                name = method.name,
                func = method.func,
                enabled = method.enabled ~= false, -- Default to true if not explicitly false
                description = method.description
            }
            -- Copy any additional properties
            for key, value in pairs(method) do
                if key ~= "name" and key ~= "func" and key ~= "enabled" and key ~= "description" then
                    if type(value) == "table" then
                        copy[i][key] = profileSystem.DeepCopy(value)
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

-- Specialized deep copy function for entire profile data
-- This ensures complete isolation between profiles
function profileSystem.DeepCopyProfile(profile)
    if not profile or type(profile) ~= "table" then
        return {}
    end

    local copy = {}

    -- Copy basic profile metadata
    copy.name = profile.name
    copy.displayName = profile.displayName
    copy.description = profile.description
    copy.author = profile.author
    copy.created = profile.created
    copy.modified = profile.modified
    copy.shared = profile.shared
    copy.mapSpecific = profile.mapSpecific
    copy.map = profile.map
    copy.version = profile.version
    copy.autoLoad = profile.autoLoad
    copy.backup = profile.backup

    -- Deep copy settings and methods to prevent reference sharing
    copy.settings = profileSystem.DeepCopySettings(profile.settings)
    copy.methods = profileSystem.DeepCopyMethods(profile.methods)

    -- Copy any additional properties
    for key, value in pairs(profile) do
        if not copy[key] then
            if type(value) == "table" then
                copy[key] = profileSystem.DeepCopy(value)
            else
                copy[key] = value
            end
        end
    end

    return copy
end

-- Make the deep copy functions globally accessible
RARELOAD.profileSystem = profileSystem
_G.profileSystem = profileSystem

print("[RARELOAD] Deep copy utility functions loaded")
