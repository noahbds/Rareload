if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck
local PS = AntiStuck.ProfileSystem

util.AddNetworkString("RareloadRequestAntiStuckConfig")
util.AddNetworkString("RareloadAntiStuckConfig")
util.AddNetworkString("RareloadAntiStuckMethods")
util.AddNetworkString("RareloadOpenAntiStuckDebug")
util.AddNetworkString("RareloadAntiStuckSettings")
util.AddNetworkString("RareloadShareAntiStuckProfile")
util.AddNetworkString("RareloadReceiveSharedProfile")
util.AddNetworkString("RareloadProfileChanged")
util.AddNetworkString("RareloadSyncServerProfile")

function AntiStuck.SetupNetworking()
    net.Receive("RareloadRequestAntiStuckConfig", function(_, ply)
        if IsValid(ply) and ply:IsAdmin() then
            net.Start("RareloadAntiStuckConfig")
            local serializedMethods = {}
            for _, method in ipairs(AntiStuck.methods or {}) do
                table.insert(serializedMethods, {
                    name = method.name,
                    description = method.description,
                    enabled = method.enabled,
                    priority = method.priority,
                    timeout = method.timeout,
                    func = method.func
                })
            end
            net.WriteTable({ settings = AntiStuck.CONFIG, methods = serializedMethods })
            net.Send(ply)
        end
    end)

    net.Receive("RareloadSyncServerProfile", function(_, ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local profileName = net.ReadString()
        if not profileName or profileName == "" then return end

        local oldProfile = PS.currentProfile
        PS.currentProfile = profileName
        file.CreateDir("rareload")
        file.Write(PS.selectedProfileFile, util.TableToJSON({ selectedProfile = profileName }, true))

        AntiStuck.LogDebug(
            "Server profile synchronized to: " .. profileName .. " (was: " .. (oldProfile or "none") .. ")", nil, ply)
        AntiStuck.LoadMethods(true)
    end)

    net.Receive("RareloadAntiStuckMethods", function(_, ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local newMethods = net.ReadTable()
        if type(newMethods) ~= "table" or #newMethods == 0 then return end

        local processed = {}
        for i, method in ipairs(newMethods) do
            if type(method) == "table" and method.func and method.name then
                table.insert(processed, {
                    name = method.name,
                    description = method.description,
                    enabled = method.enabled ~= false,
                    priority = (i * 10),
                    timeout = tonumber(method.timeout) or 1.0,
                    func = method.func
                })
            end
        end
        AntiStuck.methods = processed
        AntiStuck.SaveMethods()
        if AntiStuck.InvalidateResolverCache then AntiStuck.InvalidateResolverCache() end
        AntiStuck.LogDebug("Anti-Stuck methods updated by " .. ply:Nick() .. " for profile: " .. PS.currentProfile)
    end)

    net.Receive("RareloadAntiStuckSettings", function(_, ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local settings = net.ReadTable()
        if type(settings) ~= "table" then return end

        local function validateSettingsStructure(data)
            for k, v in pairs(data) do
                if type(k) == "number" and type(v) == "table" and v.func and v.name then
                    return false, "Received methods data instead of settings data"
                end
            end
            for k, _ in pairs(data) do
                if type(k) ~= "string" then return false, "Settings keys must be strings" end
                if RARELOAD.AntiStuck.DefaultSettings[k] == nil then
                    return false, "Unknown setting key: " .. k
                end
            end
            return true, "Valid settings data"
        end

        local isValid, err = validateSettingsStructure(settings)
        if not isValid then
            AntiStuck.LogDebug("Rejected invalid settings data from " .. ply:Nick() .. ": " .. err, settings, ply,
                "ERROR")
            ply:ChatPrint("[RARELOAD] Error: Invalid settings data rejected - " .. err)
            return
        end

        for k, v in pairs(settings) do
            if AntiStuck.CONFIG[k] ~= nil then
                AntiStuck.CONFIG[k] = v
            end
        end

        if AntiStuck.CalculateMapBounds then AntiStuck.CalculateMapBounds() end
        if AntiStuck.CollectSpawnPoints then AntiStuck.CollectSpawnPoints() end
        if AntiStuck.CollectMapEntities then AntiStuck.CollectMapEntities() end
        if AntiStuck.CacheNavMeshAreasImmediate then AntiStuck.CacheNavMeshAreasImmediate() end

        local ok = PS.UpdateCurrentProfile(settings, nil)
        if ok then
            AntiStuck.LogDebug("Anti-Stuck settings updated and saved to profile by " .. ply:Nick(), settings)
            ply:ChatPrint("[RARELOAD] Anti-Stuck settings saved to profile: " .. PS.currentProfile)
        else
            AntiStuck.LogDebug("Failed to save Anti-Stuck settings to profile", settings, ply, "ERROR")
            ply:ChatPrint("[RARELOAD] Failed to save Anti-Stuck settings to profile.")
        end

        local admins = {}
        for _, admin in ipairs(player.GetAll()) do
            if admin:IsAdmin() and admin ~= ply then table.insert(admins, admin) end
        end
        if #admins > 0 then
            net.Start("RareloadAntiStuckConfig")
            net.WriteTable(AntiStuck.CONFIG)
            net.Send(admins)
            for _, admin in ipairs(admins) do
                admin:ChatPrint("[RARELOAD] Anti-Stuck settings were updated by " .. ply:Nick() .. ".")
            end
        end
    end)

    net.Receive("RareloadShareAntiStuckProfile", function(_, ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local profileData = net.ReadTable()
        if not profileData or not profileData.name then return end

        local isValid, err = PS.ValidateProfileData(profileData)
        if not isValid then
            AntiStuck.LogDebug("Rejected sharing of invalid profile: " .. err, profileData, ply, "ERROR")
            ply:ChatPrint("[RARELOAD] Cannot share profile - invalid structure: " .. err)
            return
        end

        local recipients = {}
        for _, p in ipairs(player.GetAll()) do if p ~= ply then table.insert(recipients, p) end end
        if #recipients > 0 then
            net.Start("RareloadReceiveSharedProfile")
            net.WriteTable(profileData)
            net.Send(recipients)
            AntiStuck.LogDebug("Profile '" ..
                profileData.name .. "' shared by " .. ply:Nick() .. " to " .. #recipients .. " players")
            ply:ChatPrint("[RARELOAD] Profile shared with " .. #recipients .. " players.")
        end
    end)
end
