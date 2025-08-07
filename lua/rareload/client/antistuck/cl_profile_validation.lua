RARELOAD = RARELOAD or {}
RARELOAD.ProfileValidation = RARELOAD.ProfileValidation or {}

-- Constants
local PROFILE_VERSION = "1.1"
local REQUIRED_FIELDS = {
    "name",
    "displayName",
    "description",
    "version",
    "settings",
    "methods",
    "created",
    "modified"
}

-- Validation functions
local function ValidateProfileStructure(profile)
    if not profile or type(profile) ~= "table" then
        return false, "Invalid profile structure"
    end
    
    -- Check required fields
    for _, field in ipairs(REQUIRED_FIELDS) do
        if profile[field] == nil then
            return false, "Missing required field: " .. field
        end
    end
    
    -- Validate settings and methods
    if type(profile.settings) ~= "table" then
        return false, "Invalid settings structure"
    end
    
    if type(profile.methods) ~= "table" then
        return false, "Invalid methods structure"
    end
    
    -- Validate method entries
    for methodName, methodData in pairs(profile.methods) do
        if type(methodData) ~= "table" then
            return false, "Invalid method data for: " .. methodName
        end
        
        if methodData.enabled == nil then
            return false, "Method missing enabled state: " .. methodName
        end
    end
    
    return true
end

local function ValidateProfileVersion(profile)
    if not profile.version then
        return false, "Missing profile version"
    end
    
    -- Version check
    if profile.version ~= PROFILE_VERSION then
        -- Attempt to migrate if possible
        return MigrateProfile(profile)
    end
    
    return true
end

-- Migration functions
local function MigrateProfile(profile)
    if not profile.version then
        return false, "Cannot migrate profile without version"
    end
    
    local version = profile.version
    
    -- Migration path from 1.0 to 1.1
    if version == "1.0" then
        -- Add new fields
        profile.displayName = profile.displayName or profile.name
        profile.description = profile.description or ""
        profile.author = profile.author or "Unknown"
        profile.shared = profile.shared or false
        profile.mapSpecific = profile.mapSpecific or false
        profile.map = profile.map or ""
        
        -- Update version
        profile.version = PROFILE_VERSION
        
        return true
    end
    
    return false, "Unsupported profile version: " .. version
end

-- Export functions
function RARELOAD.ProfileValidation.ValidateProfile(profile)
    local valid, error = ValidateProfileStructure(profile)
    if not valid then
        return false, error
    end
    
    valid, error = ValidateProfileVersion(profile)
    if not valid then
        return false, error
    end
    
    return true
end

function RARELOAD.ProfileValidation.GetCurrentVersion()
    return PROFILE_VERSION
end

function RARELOAD.ProfileValidation.GetRequiredFields()
    return table.Copy(REQUIRED_FIELDS)
end
