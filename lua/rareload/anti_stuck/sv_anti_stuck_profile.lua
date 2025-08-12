if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

-- Server-side profile system interface
AntiStuck.ProfileSystem = AntiStuck.ProfileSystem or {
    profilesDir = "rareload/anti_stuck_profiles/",
    currentProfile = "default",
    selectedProfileFile = "rareload/anti_stuck_selected_profile.json"
}
local PS = AntiStuck.ProfileSystem

function PS.LoadCurrentProfile()
    if file.Exists(PS.selectedProfileFile, "DATA") then
        local content = file.Read(PS.selectedProfileFile, "DATA")
        local success, data = pcall(util.JSONToTable, content)
        if success and data and data.selectedProfile then
            PS.currentProfile = data.selectedProfile
        end
    end
    if not PS.currentProfile or PS.currentProfile == "" then
        PS.currentProfile = "default"
    end
end

function PS.ValidateProfileData(profileData)
    if not profileData then return false, "Profile data is nil" end

    if profileData.settings then
        if type(profileData.settings) ~= "table" then
            return false, "Settings must be a table"
        end
        local hasNumericKeys, hasStringKeys = false, false
        for k, _ in pairs(profileData.settings) do
            if type(k) == "number" then hasNumericKeys = true end
            if type(k) == "string" then hasStringKeys = true end
        end
        if hasNumericKeys and not hasStringKeys then
            return false, "Settings contains array data (methods) instead of settings object"
        end
    end

    if profileData.methods then
        if type(profileData.methods) ~= "table" then
            return false, "methods must be a table"
        end
        for k, v in pairs(profileData.methods) do
            if type(k) ~= "number" then return false, "methods should be an array, not an object" end
            if type(v) ~= "table" or not v.func or not v.name then
                return false, "methods array contains invalid methods objects"
            end
        end
    end

    return true, "Profile data is valid"
end

function PS.LoadProfile(profileName)
    local fileName = PS.profilesDir .. profileName .. ".json"
    if not file.Exists(fileName, "DATA") then return nil end

    local content = file.Read(fileName, "DATA")
    local success, data = pcall(util.JSONToTable, content)
    if success and data then
        local isValid, err = PS.ValidateProfileData(data)
        if not isValid then
            print("[RARELOAD] Warning: Server profile '" .. profileName .. "' has invalid data: " .. err)
            print("[RARELOAD] This profile may cause issues with settings/methods confusion")
        end
        return data
    end
    return nil
end

function PS.GetCurrentProfileSettings()
    PS.LoadCurrentProfile()
    local profile = PS.LoadProfile(PS.currentProfile)
    if profile and profile.settings then
        local isValid, err = PS.ValidateProfileData(profile)
        if not isValid then
            print("[RARELOAD] Server profile settings corrupted, using defaults: " .. err)
            return RareloadDeepCopySettings(AntiStuck.DefaultSettings)
        end
        return profile.settings
    end
    return RareloadDeepCopySettings(AntiStuck.DefaultSettings)
end

function PS.GetCurrentProfileMethods()
    PS.LoadCurrentProfile()
    local profile = PS.LoadProfile(PS.currentProfile)
    if profile and profile.methods then
        local valid = true
        for _, v in ipairs(profile.methods) do
            if type(v) ~= "table" or not v.func or not v.name then
                valid = false
                break
            end
        end
        if valid then
            return RareloadDeepCopyMethods(profile.methods)
        end
    end
    return RareloadDeepCopyMethods(AntiStuck.DefaultMethods or {})
end

function PS.UpdateCurrentProfile(settings, methods)
    local profile = PS.LoadProfile(PS.currentProfile)
    if profile then
        if settings then profile.settings = RareloadDeepCopySettings(settings) end
        if methods then profile.methods = RareloadDeepCopyMethods(methods) end
        profile.modified = os.time()

        local fileName = PS.profilesDir .. PS.currentProfile .. ".json"
        file.CreateDir(PS.profilesDir)
        file.Write(fileName, util.TableToJSON(profile, true))
        return true
    end
    return false
end

function PS.EnsureDefaultProfile()
    file.CreateDir("rareload")
    file.CreateDir(PS.profilesDir)

    local defaultFileName = PS.profilesDir .. "default.json"
    if not file.Exists(defaultFileName, "DATA") then
        local defaultProfile = {
            name = "default",
            displayName = "Default Settings",
            description = "Standard anti-stuck configuration",
            author = "System",
            created = os.time(),
            modified = os.time(),
            shared = false,
            mapSpecific = false,
            map = "",
            version = "1.0",
            settings = RareloadDeepCopySettings(AntiStuck.DefaultSettings),
            methods = RareloadDeepCopyMethods(AntiStuck.DefaultMethods)
        }
        file.Write(defaultFileName, util.TableToJSON(defaultProfile, true))
        print("[RARELOAD] Created default anti-stuck profile on server")
    end
end
