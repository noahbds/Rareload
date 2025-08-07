RARELOAD = RARELOAD or {}

-- Profile Validation Module
-- Handles validation of profile data structures
-- This module extends the basic validation from cl_profile_system.lua

local profileSystem = RARELOAD.profileSystem or _G.profileSystem or {}

print("[RARELOAD] Loading enhanced profile validation module")

-- Function to validate profile data structure
function profileSystem.ValidateProfileData(profileData)
    if not profileData then return false, "Profile data is nil" end

    -- Check if settings is an object (table with string keys), not an array
    if profileData.settings then
        if type(profileData.settings) ~= "table" then
            return false, "Settings must be a table"
        end

        -- Check if it's an array (has numeric indices) - this would be wrong
        local hasNumericKeys = false
        local hasStringKeys = false

        for k, v in pairs(profileData.settings) do
            if type(k) == "number" then
                hasNumericKeys = true
            elseif type(k) == "string" then
                hasStringKeys = true
            end
        end

        if hasNumericKeys and not hasStringKeys then
            return false, "Settings contains array data (methods) instead of settings object"
        end
    end

    -- Check if methods is an array, not an object
    if profileData.methods then
        if type(profileData.methods) ~= "table" then
            return false, "Methods must be a table"
        end

        -- Methods should be an array of objects
        local isArray = true
        for k, v in pairs(profileData.methods) do
            if type(k) ~= "number" then
                isArray = false
                break
            end
            if type(v) ~= "table" or not v.func or not v.name then
                return false, "Methods array contains invalid method objects"
            end
        end

        if not isArray then
            return false, "Methods should be an array, not an object"
        end
    end

    return true, "Profile data is valid"
end

-- Validate settings data structure
function profileSystem.ValidateSettings(data)
    if type(data) ~= "table" then
        return false, "Settings must be a table"
    end

    -- Check for methods data in settings
    for k, v in pairs(data) do
        if type(k) == "number" and type(v) == "table" and v.func and v.name then
            return false, "Settings contains methods data (array structure)"
        end
        if type(k) ~= "string" then
            return false, "Settings keys must be strings"
        end
    end

    return true, "Valid settings"
end

-- Validate methods data structure
function profileSystem.ValidateMethods(data)
    if type(data) ~= "table" then
        return false, "Methods must be a table"
    end

    -- Check if it's an array of method objects
    for k, v in pairs(data) do
        if type(k) ~= "number" then
            return false, "Methods must be an array (numeric keys)"
        end
        if type(v) ~= "table" or not v.func or not v.name then
            return false, "Each method must have 'func' and 'name' fields"
        end
    end

    return true, "Valid methods"
end

-- Make sure the profile system reference is available globally
RARELOAD.profileSystem = profileSystem
_G.profileSystem = profileSystem
