if SERVER then
    -- Load the deep copy utility module
    include("sv_deepcopy_utils.lua")

    -- Anti-stuck settings copied from client-side for server use
    RARELOAD = RARELOAD or {}
    RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
    local AntiStuck = RARELOAD.AntiStuck

    -- Anti-stuck testing mode
    AntiStuck.testingMode = false
    AntiStuck.testingPlayers = AntiStuck.testingPlayers or {}
    AntiStuck.originalStuckPositions = AntiStuck.originalStuckPositions or {} -- Track original positions being tested

    -- Default config table
    local Default_Anti_Stuck_Settings = {
        SPAWN_POINT_OFFSET_Z = 16,
        MAP_ENTITY_OFFSET_Z = 32,
        NAV_AREA_OFFSET_Z = 16,
        PLAYER_HULL_TOLERANCE = 4,
        MIN_GROUND_DISTANCE = 8,
        CACHE_DURATION = 600,
        VERTICAL_SEARCH_RANGE = 4096,
        HORIZONTAL_SEARCH_RANGE = 2048,
        GRID_RESOLUTION = 64,
        SAFE_DISTANCE = 64,
        -- New settings
        MAX_UNSTUCK_ATTEMPTS = 50,  -- Maximum attempts to find a safe position
        NODE_SEARCH_RADIUS = 2048,  -- Search radius for navigation nodes
        MAP_BOUNDS_PADDING = 256,   -- Padding from map boundaries
        MAX_TRACE_DISTANCE = 4096,  -- Max trace distance for collision checks
        DEBUG_LOGGING = true,       -- Enable/disable debug logs
        ENABLE_CACHE = true,        -- Toggle caching of safe positions
        RETRY_DELAY = 0.1,          -- Delay (seconds) between unstuck attempts
        MAX_SEARCH_TIME = 2.0,      -- Maximum time (seconds) to spend per unstuck attempt
        RANDOM_ATTEMPTS = 50,       -- Number of random attempts for emergency/random methods
        ENTITY_SEARCH_RADIUS = 512, -- Radius for searching map entities
        NAVMESH_HEIGHT_OFFSET = 16, -- Height offset for navmesh node graph
        FALLBACK_HEIGHT = 16384,    -- Height for absolute fallback position
        METHOD_ENABLE_FLAGS = {},   -- Per-method enable/disable flags

        -- Spiral search settings
        SPIRAL_RINGS = 10,
        POINTS_PER_RING = 8,
        MAX_DISTANCE = 2000,
        VERTICAL_STEPS = 5,
        VERTICAL_RANGE = 400,
        SEARCH_RESOLUTIONS = { 64, 128, 256, 512 }
    }

    -- Default methods configuration matching client-side structure
    local Default_Anti_Stuck_Methods = {
        { name = "Cached Positions",   func = "TryCachedPositions",   enabled = true, description = "Use previously saved safe positions from successful unstuck attempts" },
        { name = "Smart Displacement", func = "TryDisplacement",      enabled = true, description = "Intelligently move player using physics-based displacement in optimal directions" },
        { name = "3D Space Scan",      func = "Try3DSpaceScan",       enabled = true, description = "Comprehensive volumetric scan in all directions with collision detection" },
        { name = "Navigation Mesh",    func = "TryNodeGraph",         enabled = true, description = "Use Source engine navigation mesh and node graph for optimal pathfinding" },
        { name = "Map Entities",       func = "TryMapEntities",       enabled = true, description = "Analyze positions near functional map entities and spawn points" },
        { name = "Systematic Grid",    func = "TrySystematicGrid",    enabled = true, description = "Methodical grid-based search with adaptive resolution and bounds checking" },
        { name = "World Brushes",      func = "TryWorldBrushes",      enabled = true, description = "Advanced world geometry analysis using brush entities and surface normals" },
        { name = "Spawn Points",       func = "TrySpawnPoints",       enabled = true, description = "Fallback to map-defined spawn points with validity checking" },
        { name = "Emergency Teleport", func = "TryEmergencyTeleport", enabled = true, description = "Last resort emergency positioning with map boundary detection" }
    }

    -- Ensure CONFIG is initialized before any access
    AntiStuck.CONFIG = AntiStuck.CONFIG or RareloadDeepCopySettings(Default_Anti_Stuck_Settings)

    -- Helper to get config value with fallback
    local function GetConfig(key)
        return AntiStuck.CONFIG[key] ~= nil and AntiStuck.CONFIG[key] or Default_Anti_Stuck_Settings[key]
    end

    util.AddNetworkString("RareloadRequestAntiStuckConfig")
    util.AddNetworkString("RareloadAntiStuckConfig")
    util.AddNetworkString("RareloadAntiStuckMethods")
    util.AddNetworkString("RareloadOpenAntiStuckDebug")
    util.AddNetworkString("RareloadAntiStuckSettings")

    -- Add network strings for profile sharing
    util.AddNetworkString("RareloadShareAntiStuckProfile")
    util.AddNetworkString("RareloadReceiveSharedProfile")

    -- Add network string for profile synchronization
    util.AddNetworkString("RareloadProfileChanged")
    util.AddNetworkString("RareloadSyncServerProfile")


    -- Server-side profile system interface
    local serverProfileSystem = {
        profilesDir = "rareload/anti_stuck_profiles/",
        currentProfile = "default",
        selectedProfileFile = "rareload/anti_stuck_selected_profile.json"
    }

    -- Load current profile from file (always on startup and when changed)
    function serverProfileSystem.LoadCurrentProfile()
        if file.Exists(serverProfileSystem.selectedProfileFile, "DATA") then
            local content = file.Read(serverProfileSystem.selectedProfileFile, "DATA")
            local success, data = pcall(util.JSONToTable, content)
            if success and data and data.selectedProfile then
                serverProfileSystem.currentProfile = data.selectedProfile
            end
        end
        -- Fallback: if not set, always use "default"
        if not serverProfileSystem.currentProfile or serverProfileSystem.currentProfile == "" then
            serverProfileSystem.currentProfile = "default"
        end
    end

    -- Function to validate profile data structure
    function serverProfileSystem.ValidateProfileData(profileData)
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
                return false, "methods must be a table"
            end

            -- methods should be an array of objects
            local isArray = true
            for k, v in pairs(profileData.methods) do
                if type(k) ~= "number" then
                    isArray = false
                    break
                end
                if type(v) ~= "table" or not v.func or not v.name then
                    return false, "methods array contains invalid methods objects"
                end
            end

            if not isArray then
                return false, "methods should be an array, not an object"
            end
        end

        return true, "Profile data is valid"
    end

    -- Load specific profile
    function serverProfileSystem.LoadProfile(profileName)
        local fileName = serverProfileSystem.profilesDir .. profileName .. ".json"
        if not file.Exists(fileName, "DATA") then return nil end

        local content = file.Read(fileName, "DATA")
        local success, data = pcall(util.JSONToTable, content)
        if success and data then
            -- Validate the loaded profile data
            local isValid, error = serverProfileSystem.ValidateProfileData(data)
            if not isValid then
                print("[RARELOAD] Warning: Server profile '" .. profileName .. "' has invalid data: " .. error)
                print("[RARELOAD] This profile may cause issues with settings/methods confusion")
            end
            return data
        end
        return nil
    end

    -- Get current profile settings (always reloads from selected profile)
    function serverProfileSystem.GetCurrentProfileSettings()
        serverProfileSystem.LoadCurrentProfile()
        local profile = serverProfileSystem.LoadProfile(serverProfileSystem.currentProfile)
        if profile and profile.settings then
            -- Check if settings is corrupted (contains methods data)
            local isValid, error = serverProfileSystem.ValidateProfileData(profile)
            if not isValid then
                print("[RARELOAD] Server profile settings corrupted, using defaults: " .. error)
                return RareloadDeepCopySettings(Default_Anti_Stuck_Settings)
            end
            return profile.settings
        end
        return RareloadDeepCopySettings(Default_Anti_Stuck_Settings)
    end

    -- Get current profile methods (always reloads from selected profile)
    function serverProfileSystem.GetCurrentProfileMethods()
        serverProfileSystem.LoadCurrentProfile()
        local profile = serverProfileSystem.LoadProfile(serverProfileSystem.currentProfile)
        if profile and profile.methods then
            -- Validate methods array
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
        return RareloadDeepCopyMethods(Default_Anti_Stuck_Methods or {})
    end

    -- Update current profile with new settings/methods
    function serverProfileSystem.UpdateCurrentProfile(settings, methods)
        local profile = serverProfileSystem.LoadProfile(serverProfileSystem.currentProfile)
        if profile then
            if settings then
                profile.settings = RareloadDeepCopySettings(settings)
            end
            if methods then
                profile.methods = RareloadDeepCopyMethods(methods)
            end
            profile.modified = os.time()

            local fileName = serverProfileSystem.profilesDir .. serverProfileSystem.currentProfile .. ".json"
            file.CreateDir(serverProfileSystem.profilesDir)
            file.Write(fileName, util.TableToJSON(profile, true))
            return true
        end
        return false
    end

    -- Ensure default profile exists
    function serverProfileSystem.EnsureDefaultProfile()
        file.CreateDir("rareload")
        file.CreateDir(serverProfileSystem.profilesDir)

        local defaultFileName = serverProfileSystem.profilesDir .. "default.json"
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
                settings = RareloadDeepCopySettings(Default_Anti_Stuck_Settings),
                methods = {
                    { name = "Cached Positions",   func = "TryCachedPositions",   enabled = true, description = "Use previously saved safe positions from successful unstuck attempts" },
                    { name = "Smart Displacement", func = "TryDisplacement",      enabled = true, description = "Intelligently move player using physics-based displacement in optimal directions" },
                    { name = "3D Space Scan",      func = "Try3DSpaceScan",       enabled = true, description = "Comprehensive volumetric scan in all directions with collision detection" },
                    { name = "Navigation Mesh",    func = "TryNodeGraph",         enabled = true, description = "Use Source engine navigation mesh and node graph for optimal pathfinding" },
                    { name = "Map Entities",       func = "TryMapEntities",       enabled = true, description = "Analyze positions near functional map entities and spawn points" },
                    { name = "Systematic Grid",    func = "TrySystematicGrid",    enabled = true, description = "Methodical grid-based search with adaptive resolution and bounds checking" },
                    { name = "World Brushes",      func = "TryWorldBrushes",      enabled = true, description = "Advanced world geometry analysis using brush entities and surface normals" },
                    { name = "Spawn Points",       func = "TrySpawnPoints",       enabled = true, description = "Fallback to map-defined spawn points with validity checking" },
                    { name = "Emergency Teleport", func = "TryEmergencyTeleport", enabled = true, description = "Last resort emergency positioning with map boundary detection" }
                }
            }
            file.Write(defaultFileName, util.TableToJSON(defaultProfile, true))
            print("[RARELOAD] Created default anti-stuck profile on server")
        end
    end

    -- Try to load configuration from profile system
    local function LoadConfigFromProfile()
        -- Initialize profile system
        serverProfileSystem.LoadCurrentProfile()
        serverProfileSystem.EnsureDefaultProfile()

        -- Load settings from current profile
        local profileSettings = serverProfileSystem.GetCurrentProfileSettings()
        if profileSettings then
            -- Apply saved settings to CONFIG
            for k, v in pairs(profileSettings) do
                if AntiStuck.CONFIG[k] ~= nil then
                    AntiStuck.CONFIG[k] = v
                end
            end

            -- Log successful settings load
            print("[RARELOAD] Anti-Stuck settings loaded from profile: " .. serverProfileSystem.currentProfile)
            return true
        else
            print("[RARELOAD] Warning: Failed to load Anti-Stuck settings from current profile")
        end

        return false
    end

    -- Initial load attempt
    LoadConfigFromProfile()

    -- Centralized entity classes
    local SPAWN_CLASSES = {
        "info_player_start", "info_player_deathmatch", "info_player_combine",
        "info_player_rebel", "info_player_counterterrorist", "info_player_terrorist",
        "gmod_player_start"
    }

    local SAFE_ENTITY_CLASSES = {
        "prop_physics", "prop_physics_multiplayer", "func_door", "func_button",
        "info_landmark", "info_node", "info_hint", "func_breakable",
        "func_wall", "func_illusionary", "trigger_multiple"
    }

    -- State initialization
    AntiStuck.safePositionCache = AntiStuck.safePositionCache or {}
    AntiStuck.lastCacheUpdate = AntiStuck.lastCacheUpdate or {}
    AntiStuck.mapBounds = AntiStuck.mapBounds or nil
    AntiStuck.mapCenter = AntiStuck.mapCenter or Vector(0, 0, 0)
    AntiStuck.methods = AntiStuck.methods or {}

    -- Unstuck method enums
    AntiStuck.UNSTUCK_METHODS = {
        NONE = 0,
        DISPLACEMENT = 1,
        SPACE_SCAN = 2,
        NODE_GRAPH = 3,
        CACHED_POSITION = 4,
        SPAWN_POINTS = 5,
        MAP_ENTITIES = 6,
        SYSTEMATIC_GRID = 7,
        WORLD_BRUSHES = 8,
        EMERGENCY_TELEPORT = 9
    }

    -- Utility functions
    local function LogDebug(message, data, player, level)
        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck(message, data, player, level)
        elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] " .. message)
        end
    end

    local function IsValidEntityForPosition(ent)
        return IsValid(ent) and ent:GetSolid() ~= SOLID_NONE and util.IsInWorld(ent:GetPos())
    end

    local function CollectEntitiesByClasses(classes, offset)
        local positions = {}
        for _, className in ipairs(classes) do
            for _, ent in ipairs(ents.FindByClass(className)) do
                if IsValidEntityForPosition(ent) then
                    table.insert(positions, ent:GetPos() + (offset or Vector()))
                end
            end
        end
        return positions
    end

    local function GetPlayerHullBounds(ply, tolerance)
        tolerance = tolerance or GetConfig("PLAYER_HULL_TOLERANCE")
        local mins = ply:OBBMins() - Vector(tolerance, tolerance, 0)
        local maxs = ply:OBBMaxs() + Vector(tolerance, tolerance, tolerance)
        return mins, maxs
    end

    local function TracePlayerHull(pos, ply, tolerance)
        local mins, maxs = GetPlayerHullBounds(ply, tolerance)
        local trace = {
            start = pos,
            endpos = pos,
            mins = mins,
            maxs = maxs,
            filter = ply,
            mask = MASK_PLAYERSOLID,
            ignoreworld = false,
            collisiongroup = COLLISION_GROUP_NONE,
            output = nil,
            whitelist = nil,
            hitclientonly = false
        }
        return util.TraceHull(trace)
    end

    -- Core functions
    function AntiStuck.RegisterMethod(name, func)
        if not name or type(name) ~= "string" or not func or type(func) ~= "function" then
            LogDebug("Invalid method registration: " .. tostring(name), nil, nil, "ERROR")
            return false
        end

        AntiStuck.methods[name] = func
        LogDebug("Registered method: " .. name)
        return true
    end

    function AntiStuck.Initialize()
        -- Initialize all subsystems
        AntiStuck.LoadMethods()
        AntiStuck.CalculateMapBounds()
        AntiStuck.CollectSpawnPoints()
        AntiStuck.CollectMapEntities()
        AntiStuck.InitializeNodeCacheImmediate()
        AntiStuck.CacheNavMeshAreasImmediate()

        -- Setup timers and networking
        timer.Create("RARELOAD_CacheCleanup", 60, 0, AntiStuck.CleanupCache)
        AntiStuck.SetupNetworking()


        LogDebug("System initialized", {
            methodName = "Initialize",
            mapName = game.GetMap(),
            totalMethods = table.Count(AntiStuck.methods),
            navMeshReady = AntiStuck.nodeGraphReady,
            spawnPointsCount = #AntiStuck.spawnPoints,
            mapEntitiesCount = #AntiStuck.mapEntities
        })
    end

    function AntiStuck.SetupNetworking()
        net.Receive("RareloadRequestAntiStuckConfig", function(len, ply)
            if IsValid(ply) and ply:IsAdmin() then
                SafeNetStart("RareloadAntiStuckConfig")
                -- Create a serializable version of the methods table
                local serializedMethods = {}
                for name, method in pairs(AntiStuck.methods) do
                    serializedMethods[name] = {
                        name = method.name,
                        description = method.description,
                        enabled = method.enabled,
                        priority = method.priority,
                        settings = method.settings,
                        -- Don't include the function reference
                        -- func = method.func
                    }
                end
                net.WriteTable(serializedMethods)
                SafeNetEnd("RareloadAntiStuckConfig")
                net.Send(ply)
            end
        end)

        -- Handle profile synchronization from client
        net.Receive("RareloadSyncServerProfile", function(len, ply)
            if not IsValid(ply) or not ply:IsAdmin() then return end

            local profileName = net.ReadString()
            if profileName and profileName ~= "" then
                local oldProfile = serverProfileSystem.currentProfile
                serverProfileSystem.currentProfile = profileName

                -- Save the new current profile selection
                file.CreateDir("rareload")
                local data = { selectedProfile = profileName }
                file.Write(serverProfileSystem.selectedProfileFile, util.TableToJSON(data, true))

                LogDebug("Server profile synchronized to: " .. profileName .. " (was: " .. (oldProfile or "none") .. ")",
                    nil, ply)

                -- Reload methods from the new profile
                AntiStuck.LoadMethods(true)
            end
        end)

        net.Receive("RareloadAntiStuckMethods", function(len, ply)
            if not ply:IsAdmin() then return end

            local newMethods = net.ReadTable()
            if type(newMethods) == "table" and #newMethods > 0 then
                -- Validate and process the received methods
                local processedMethods = {}
                for name, method in pairs(newMethods) do
                    if type(method) == "table" and method.name then
                        -- Keep the existing function reference if available
                        local existingMethod = AntiStuck.methods[name]
                        processedMethods[name] = {
                            name = method.name,
                            description = method.description,
                            enabled = method.enabled,
                            priority = method.priority,
                            settings = method.settings,
                            func = existingMethod and existingMethod.func or nil
                        }
                    end
                end
                AntiStuck.methods = processedMethods
                AntiStuck.SaveMethods()
                LogDebug("Method methods updated by " ..
                ply:Nick() .. " for profile: " .. serverProfileSystem.currentProfile)
            end
        end)

        -- Handle settings updates from clients
        net.Receive("RareloadAntiStuckSettings", function(len, ply)
            if not IsValid(ply) or not ply:IsAdmin() then return end

            local settings = net.ReadTable()
            if type(settings) ~= "table" then return end

            -- VALIDATE: Ensure this is actually settings data, not methods
            local function validateSettingsStructure(data)
                -- Check if this looks like methods data (array with objects containing 'func' and 'name')
                for k, v in pairs(data) do
                    if type(k) == "number" and type(v) == "table" and v.func and v.name then
                        return false, "Received methods data instead of settings data"
                    end
                end

                -- Check if keys match expected settings keys
                for k, v in pairs(data) do
                    if type(k) ~= "string" then
                        return false, "Settings keys must be strings"
                    end
                    if not Default_Anti_Stuck_Settings[k] then
                        return false, "Unknown setting key: " .. k
                    end
                end

                return true, "Valid settings data"
            end

            local isValid, error = validateSettingsStructure(settings)
            if not isValid then
                LogDebug("Rejected invalid settings data from " .. ply:Nick() .. ": " .. error, settings, ply, "ERROR")
                ply:ChatPrint("[RARELOAD] Error: Invalid settings data rejected - " .. error)
                return
            end

            -- Update the CONFIG with the new settings
            for k, v in pairs(settings) do
                if AntiStuck.CONFIG[k] ~= nil then
                    AntiStuck.CONFIG[k] = v
                end
            end

            -- Make sure offset Z values are properly updated in vectors used by systems
            if AntiStuck.spawnPoints and #AntiStuck.spawnPoints > 0 then
                -- Recollect spawn points with new offset
                AntiStuck.CollectSpawnPoints()
            end

            if AntiStuck.mapEntities and #AntiStuck.mapEntities > 0 then
                -- Recollect map entities with new offset
                AntiStuck.CollectMapEntities()
            end

            if AntiStuck.navAreas and #AntiStuck.navAreas > 0 then
                -- Recollect nav areas with new offset
                AntiStuck.CacheNavMeshAreasImmediate()
            end

            -- Save ONLY settings to current profile (never methods via this path)
            local success = serverProfileSystem.UpdateCurrentProfile(settings, nil)
            if success then
                LogDebug("Anti-Stuck settings updated and saved to profile by " .. ply:Nick(), settings)
                ply:ChatPrint("[RARELOAD] Anti-Stuck settings saved to profile: " .. serverProfileSystem.currentProfile)
            else
                LogDebug("Failed to save Anti-Stuck settings to profile", settings, ply, "ERROR")
                ply:ChatPrint("[RARELOAD] Failed to save Anti-Stuck settings to profile.")
            end

            -- Broadcast updated settings to all admins except the one who changed them
            local admins = {}
            for _, admin in ipairs(player.GetAll()) do
                if admin:IsAdmin() and admin ~= ply then
                    table.insert(admins, admin)
                end
            end

            if #admins > 0 then
                SafeNetStart("RareloadAntiStuckConfig")
                net.WriteTable(AntiStuck.CONFIG)
                SafeNetEnd("RareloadAntiStuckConfig")
                net.Send(admins)

                -- Notify other admins
                for _, admin in ipairs(admins) do
                    admin:ChatPrint("[RARELOAD] Anti-Stuck settings were updated by " .. ply:Nick() .. ".")
                end
            end
        end)

        -- Handle shared profile distribution
        net.Receive("RareloadShareAntiStuckProfile", function(len, ply)
            if not IsValid(ply) or not ply:IsAdmin() then return end

            local profileData = net.ReadTable()
            if not profileData or not profileData.name then return end

            -- Validate profile structure before sharing
            local isValid, error = serverProfileSystem.ValidateProfileData(profileData)
            if not isValid then
                LogDebug("Rejected sharing of invalid profile: " .. error, profileData, ply, "ERROR")
                ply:ChatPrint("[RARELOAD] Cannot share profile - invalid structure: " .. error)
                return
            end

            -- Broadcast the profile to all players except the sender
            local recipients = {}
            for _, player in ipairs(player.GetAll()) do
                if player ~= ply then
                    table.insert(recipients, player)
                end
            end

            if #recipients > 0 then
                net.Start("RareloadReceiveSharedProfile")
                net.WriteTable(profileData)
                net.Send(recipients)

                LogDebug("Profile '" ..
                    profileData.name .. "' shared by " .. ply:Nick() .. " to " .. #recipients .. " players")
                ply:ChatPrint("[RARELOAD] Profile shared with " .. #recipients .. " players.")
            end
        end)
    end

    function AntiStuck.CalculateMapBounds()
        -- Try world entity first (more efficient)
        local world = game.GetWorld()
        if IsValid(world) then
            local mins, maxs = world:GetCollisionBounds()
            if mins and maxs then
                AntiStuck.mapBounds = { mins = mins, maxs = maxs }
                AntiStuck.mapCenter = (mins + maxs) / 2
                LogDebug("Map bounds calculated from world entity", {
                    methodName = "CalculateMapBounds",
                    mins = tostring(mins),
                    maxs = tostring(maxs),
                    center = tostring(AntiStuck.mapCenter)
                })
                return
            end
        end

        -- Fallback to entity scanning
        local minPos = Vector(99999, 99999, 99999)
        local maxPos = Vector(-99999, -99999, -99999)

        for _, ent in ipairs(ents.GetAll()) do
            if IsValidEntityForPosition(ent) then
                local pos = ent:GetPos()
                local mins, maxs = ent:GetCollisionBounds()
                if mins and maxs then
                    local entMin, entMax = pos + mins, pos + maxs
                    minPos = Vector(math.min(minPos.x, entMin.x), math.min(minPos.y, entMin.y),
                        math.min(minPos.z, entMin.z))
                    maxPos = Vector(math.max(maxPos.x, entMax.x), math.max(maxPos.y, entMax.y),
                        math.max(maxPos.z, entMax.z))
                end
            end
        end

        AntiStuck.mapBounds = { mins = minPos, maxs = maxPos }
        AntiStuck.mapCenter = (minPos + maxPos) / 2
        LogDebug("Map bounds calculated from entities", {
            methodName = "CalculateMapBounds",
            mins = tostring(minPos),
            maxs = tostring(maxPos),
            center = tostring(AntiStuck.mapCenter)
        })
    end

    function AntiStuck.CollectSpawnPoints()
        local z = tonumber(GetConfig("SPAWN_POINT_OFFSET_Z")) or 0
        local offset = Vector(0, 0, z)
        AntiStuck.spawnPoints = CollectEntitiesByClasses(SPAWN_CLASSES, offset)
        LogDebug("Collected " .. #AntiStuck.spawnPoints .. " spawn points")
    end

    function AntiStuck.CollectMapEntities()
        local z = tonumber(GetConfig("MAP_ENTITY_OFFSET_Z")) or 0
        local offset = Vector(0, 0, z)
        AntiStuck.mapEntities = CollectEntitiesByClasses(SAFE_ENTITY_CLASSES, offset)
        LogDebug("Collected " .. #AntiStuck.mapEntities .. " map entity positions")
    end

    function AntiStuck.InitializeNodeCacheImmediate()
        AntiStuck.nodeCache = {}
        AntiStuck.nodeGraphReady = false

        -- Test for navmesh in methods order
        local testPositions = {}
        if AntiStuck.mapCenter then table.insert(testPositions, AntiStuck.mapCenter) end
        if AntiStuck.spawnPoints then
            for _, pos in ipairs(AntiStuck.spawnPoints) do
                table.insert(testPositions, pos)
            end
        end
        if AntiStuck.mapBounds then
            local bounds = AntiStuck.mapBounds
            table.insert(testPositions, Vector(bounds.mins.x + 500, bounds.mins.y + 500, AntiStuck.mapCenter.z))
            table.insert(testPositions, Vector(bounds.maxs.x - 500, bounds.maxs.y - 500, AntiStuck.mapCenter.z))
        end

        for _, testPos in ipairs(testPositions) do
            local testArea = navmesh.GetNearestNavArea(testPos, false, 1000, false, true)
            if testArea and IsValid(testArea) then
                AntiStuck.nodeGraphReady = true
                break
            end
        end

        LogDebug("Node graph ready: " .. tostring(AntiStuck.nodeGraphReady))
    end

    function AntiStuck.CacheNavMeshAreasImmediate()
        AntiStuck.navAreas = {}
        if not AntiStuck.nodeGraphReady or not AntiStuck.mapBounds then return end

        local areaCount = 0
        local maxAreas = 500
        local minDistanceBetweenAreas = 256
        local mapBounds = AntiStuck.mapBounds
        local mapWidth = math.abs(mapBounds.maxs.x - mapBounds.mins.x)
        local mapHeight = math.abs(mapBounds.maxs.y - mapBounds.mins.y)
        local step = math.max(512, math.min(2048, math.max(mapWidth, mapHeight) / 20))

        local function isTooClose(pos)
            for _, areaData in ipairs(AntiStuck.navAreas) do
                if areaData.center:DistToSqr(pos) < (minDistanceBetweenAreas ^ 2) then
                    return true
                end
            end
            return false
        end

        local function addNavArea(area)
            if not area or not IsValid(area) then return false end
            local center = area:GetCenter()
            if not center or isTooClose(center) then return false end

            local corners = {}
            for i = 0, 3 do
                local corner = area:GetCorner(i)
                if corner then table.insert(corners, corner) end
            end

            table.insert(AntiStuck.navAreas, {
                center = center + Vector(0, 0, AntiStuck.CONFIG.NAV_AREA_OFFSET_Z or 16),
                corners = corners
            })
            return true
        end

        -- Add center area first
        local centerArea = navmesh.GetNearestNavArea(AntiStuck.mapCenter, false, 200, false, true)
        if addNavArea(centerArea) then areaCount = areaCount + 1 end

        -- Spiral search pattern
        local startX = math.floor(AntiStuck.mapCenter.x / step) * step
        local startY = math.floor(AntiStuck.mapCenter.y / step) * step
        local maxRadius = math.ceil(math.max(mapWidth, mapHeight) / (2 * step))

        for radius = 1, maxRadius do
            if areaCount >= maxAreas then break end

            for x = startX - radius * step, startX + radius * step, step do
                for y = startY - radius * step, startY + radius * step, step do
                    if (x == startX - radius * step or x == startX + radius * step or
                            y == startY - radius * step or y == startY + radius * step) and areaCount < maxAreas then
                        local testPos = Vector(x, y, AntiStuck.mapCenter.z)
                        if not isTooClose(testPos) then
                            local area = navmesh.GetNearestNavArea(testPos, false, 100, false, true)
                            if addNavArea(area) then
                                areaCount = areaCount + 1
                            end
                        end
                    end
                end
                if areaCount >= maxAreas then break end
            end
        end

        LogDebug("Cached " .. areaCount .. " navigation areas")
    end

    function AntiStuck.CleanupCache()
        local currentTime = CurTime()
        local cleaned = 0

        for mapPos, data in pairs(AntiStuck.safePositionCache) do
            if currentTime - data.timestamp > AntiStuck.CONFIG.CACHE_DURATION then
                AntiStuck.safePositionCache[mapPos] = nil
                cleaned = cleaned + 1
            end
        end

        if cleaned > 0 then
            LogDebug("Cleaned " .. cleaned .. " cache entries")
        end
    end

    function AntiStuck.IsPositionStuck(pos, ply, isOriginalPosition)
        if not pos or not IsValid(ply) then return true, "invalid_parameters" end

        -- Only apply testing mode to original positions, not positions found by anti-stuck methods
        if isOriginalPosition ~= false then
            -- Check if we're in testing mode for this player
            if AntiStuck.testingMode or (AntiStuck.testingPlayers[ply:SteamID()] and AntiStuck.testingPlayers[ply:SteamID()] > CurTime()) then
                -- Store this as an original stuck position for tracking
                local posKey = string.format("%.0f_%.0f_%.0f", pos.x, pos.y, pos.z)
                AntiStuck.originalStuckPositions[ply:SteamID() .. "_" .. posKey] = CurTime()

                LogDebug("Anti-stuck testing mode active - forcing ORIGINAL position to be stuck", {
                    methodName = "IsPositionStuck",
                    position = pos,
                    testingMode = AntiStuck.testingMode,
                    playerTesting = AntiStuck.testingPlayers[ply:SteamID()] and
                        AntiStuck.testingPlayers[ply:SteamID()] > CurTime()
                }, ply)
                return true, "testing_mode_forced"
            end
        end

        if not util.IsInWorld(pos) then return true, "outside_world" end

        -- Quick collision check (improved: only treat as stuck if StartSolid is true or Hit is true AND fraction < 1)
        local simple = TracePlayerHull(pos, ply, AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE * 0.5)
        if not simple.Hit and not simple.StartSolid then
            local ground = util.TraceLine({
                start = pos,
                endpos = pos - Vector(0, 0, AntiStuck.CONFIG.MIN_GROUND_DISTANCE * 2),
                filter = ply,
                mask = MASK_SOLID_BRUSHONLY,
                collisiongroup = COLLISION_GROUP_NONE,
                ignoreworld = false,
                hitclientonly = false,
                output = nil,
                whitelist = nil
            })
            if ground.Hit and bit.band(util.PointContents(pos), CONTENTS_WATER) == 0 then
                return false, "safe"
            end
        end

        -- Improved: Only treat as stuck if StartSolid is true or Hit is true and fraction < 0.99
        local hull = TracePlayerHull(pos, ply, AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE)
        if hull.StartSolid or (hull.Hit and hull.Fraction < 0.99) then
            LogDebug("Position failed solid collision check", {
                methodName = "IsPositionStuck",
                position = pos,
                reason = "solid_collision",
                collidingWith = hull.Entity and IsValid(hull.Entity) and hull.Entity:GetClass() or "unknown"
            }, ply)
            return true, "solid_collision"
        end

        -- Ground check
        local checkPoints = {
            Vector(0, 0, 0), Vector(8, 0, 0), Vector(-8, 0, 0),
            Vector(0, 8, 0), Vector(0, -8, 0)
        }

        for _, offset in ipairs(checkPoints) do
            local ground = util.TraceLine({
                start = pos + offset,
                endpos = pos + offset - Vector(0, 0, AntiStuck.CONFIG.MIN_GROUND_DISTANCE * 6),
                filter = ply,
                mask = MASK_PLAYERSOLID,
                collisiongroup = COLLISION_GROUP_NONE,
                ignoreworld = false,
                hitclientonly = false,
                output = nil,
                whitelist = nil
            })
            if ground.Hit and ground.HitPos:DistToSqr(pos + offset) <= (AntiStuck.CONFIG.MIN_GROUND_DISTANCE * 6) ^ 2 then
                -- Check for water and solid content
                local contents = util.PointContents(pos)
                if bit.band(contents, CONTENTS_WATER) ~= 0 then
                    LogDebug("Position is in water", { methodName = "IsPositionStuck", position = pos }, ply)
                    return true, "in_water"
                end
                if bit.band(contents, CONTENTS_SOLID) ~= 0 then
                    LogDebug("Position is inside solid", { methodName = "IsPositionStuck", position = pos }, ply)
                    return true, "inside_solid"
                end
                return false, "safe"
            end
        end

        LogDebug("Position has no ground beneath", { methodName = "IsPositionStuck", position = pos }, ply)
        return true, "no_ground"
    end

    function AntiStuck.CacheSafePosition(pos)
        if not pos then return end

        local cacheKey = string.format("%s_%.0f_%.0f_%.0f", game.GetMap(), pos.x, pos.y, pos.z)
        AntiStuck.safePositionCache[cacheKey] = {
            position = Vector(pos.x, pos.y, pos.z),
            timestamp = CurTime(),
            map = game.GetMap()
        }

        if RARELOAD.SavePositionToCache then
            RARELOAD.SavePositionToCache(pos)
        end
    end

    function AntiStuck.LoadMethods(forceReload)
        -- Always reload from selected profile
        local profilemethods = serverProfileSystem.GetCurrentProfileMethods()
        if profilemethods and #profilemethods > 0 then
            -- Ensure all methods have enabled field and only keep enabled methods for execution order
            local validMethods = {}
            for _, m in ipairs(profilemethods) do
                -- Default to enabled if not specified
                if m.enabled == nil then
                    m.enabled = true
                end
                -- Keep all methods in the order list (enabled and disabled)
                table.insert(validMethods, m)
            end
            AntiStuck.methods = validMethods

            -- Debug: Show registered methods vs ordered methods
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD ANTI-STUCK] Method loading debug:")
                print("  Registered method functions: " .. table.Count(AntiStuck.methodRegistry or {}))
                print("  Method order from profile: " .. #AntiStuck.methods)

                -- Check which methods are missing functions
                for _, method in ipairs(AntiStuck.methods) do
                    local hasFunc = AntiStuck.methodRegistry and AntiStuck.methodRegistry[method.func] ~= nil
                    local status = hasFunc and "✓" or "✗"
                    print("    " ..
                        status ..
                        " " ..
                        (method.name or "unnamed") ..
                        " (" .. (method.func or "no func") .. ") - enabled: " .. tostring(method.enabled))
                end
            end

            LogDebug("Successfully loaded methods from profile", {
                methodName = "LoadMethods",
                source = "Profile system",
                profileName = serverProfileSystem.currentProfile,
                totalMethods = #profilemethods,
                enabledMethods = #validMethods,
                registeredFunctions = table.Count(AntiStuck.methodRegistry or {})
            })
            return
        end

        -- Fallback to default methods if profile system fails
        local defaultMethods = RareloadDeepCopyMethods(Default_Anti_Stuck_Methods)
        -- Ensure all default methods are enabled
        for _, method in ipairs(defaultMethods) do
            method.enabled = true
        end
        AntiStuck.methods = defaultMethods
        LogDebug("Initialized with default methods", {
            methodName = "LoadMethods",
            source = "Defaults",
            methodCount = #AntiStuck.methods
        })
    end

    function AntiStuck.SaveMethods()
        -- Save to current profile instead of separate file
        local success = serverProfileSystem.UpdateCurrentProfile(nil, AntiStuck.methods)
        if success then
            LogDebug("Methods saved to profile", {
                methodName = "SaveMethods",
                profileName = serverProfileSystem.currentProfile,
                methodCount = #AntiStuck.methods
            })
        else
            LogDebug("Failed to save methods to profile", {
                methodName = "SaveMethods",
                profileName = serverProfileSystem.currentProfile
            }, nil, "ERROR")
        end
    end

    concommand.Add("rareload_debug_antistuck_server", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        net.Start("RareloadOpenAntiStuckDebug")
        net.Send(ply)
    end)

    -- Console command to validate and fix corrupted profiles on server
    concommand.Add("rareload_server_fix_corrupted_profiles", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[RARELOAD] You must be an admin to use this command.")
            return
        end

        serverProfileSystem.LoadCurrentProfile()
        serverProfileSystem.EnsureDefaultProfile()

        local profiles = {}
        local files = file.Find(serverProfileSystem.profilesDir .. "*.json", "DATA")
        for _, fileName in ipairs(files or {}) do
            local profileName = string.gsub(fileName, "%.json$", "")
            table.insert(profiles, profileName)
        end

        local fixedCount = 0
        local errorCount = 0

        for _, profileName in ipairs(profiles) do
            local profile = serverProfileSystem.LoadProfile(profileName)
            if profile then
                local isValid, error = serverProfileSystem.ValidateProfileData(profile)
                if not isValid then
                    print("[RARELOAD] Fixing corrupted server profile: " .. profileName)
                    print("[RARELOAD] Error was: " .. error)

                    -- If settings contains methods data, move it to methods
                    if profile.settings and type(profile.settings) == "table" then
                        local hasNumericKeys = false
                        for k, v in pairs(profile.settings) do
                            if type(k) == "number" and type(v) == "table" and v.func and v.name then
                                hasNumericKeys = true
                                break
                            end
                        end

                        if hasNumericKeys then
                            -- Settings contains methods data, fix it
                            profile.methods = RareloadDeepCopyMethods(profile.settings)
                            profile.settings = RareloadDeepCopySettings(Default_Anti_Stuck_Settings or {})

                            -- Save the fixed profile
                            local fileName = serverProfileSystem.profilesDir .. profileName .. ".json"
                            file.CreateDir(serverProfileSystem.profilesDir)
                            local success = pcall(file.Write, fileName, util.TableToJSON(profile, true))
                            if success then
                                fixedCount = fixedCount + 1
                                print("[RARELOAD] Fixed server profile: " .. profileName)
                            else
                                errorCount = errorCount + 1
                                print("[RARELOAD] Failed to save fixed server profile: " .. profileName)
                            end
                        end
                    end
                end
            end
        end

        local message = "[RARELOAD] Server profile fix complete. Fixed: " .. fixedCount .. ", Errors: " .. errorCount
        print(message)
        if IsValid(ply) then
            ply:ChatPrint(message)
        end
    end)

    -- Console command to enable anti-stuck testing mode globally
    concommand.Add("rareload_antistuck_test_enable", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[RARELOAD] Only admins can enable anti-stuck testing mode.")
            return
        end

        AntiStuck.testingMode = true
        local message =
        "[RARELOAD] Anti-stuck testing mode ENABLED globally. All respawns will trigger the anti-stuck system."
        print(message)

        if IsValid(ply) then
            ply:ChatPrint(message)
        end

        -- Notify all players
        for _, p in ipairs(player.GetAll()) do
            if p:IsAdmin() then
                p:ChatPrint("[RARELOAD] Anti-stuck testing mode is now ACTIVE.")
            end
        end
    end)

    -- Console command to disable anti-stuck testing mode globally
    concommand.Add("rareload_antistuck_test_disable", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[RARELOAD] Only admins can disable anti-stuck testing mode.")
            return
        end

        AntiStuck.testingMode = false
        AntiStuck.testingPlayers = {} -- Clear individual player testing too
        local message = "[RARELOAD] Anti-stuck testing mode DISABLED globally."
        print(message)

        if IsValid(ply) then
            ply:ChatPrint(message)
        end

        -- Notify all players
        for _, p in ipairs(player.GetAll()) do
            if p:IsAdmin() then
                p:ChatPrint("[RARELOAD] Anti-stuck testing mode is now INACTIVE.")
            end
        end
    end)

    -- Console command to enable anti-stuck testing for a specific player temporarily
    concommand.Add("rareload_antistuck_test_player", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[RARELOAD] Only admins can enable player-specific anti-stuck testing.")
            return
        end

        local targetName = args[1]
        local duration = tonumber(args[2]) or 300 -- Default 5 minutes

        if not targetName then
            local message = "[RARELOAD] Usage: rareload_antistuck_test_player <player_name> [duration_seconds]"
            print(message)
            if IsValid(ply) then
                ply:ChatPrint(message)
            end
            return
        end

        -- Find target player
        local targetPlayer = nil
        for _, p in ipairs(player.GetAll()) do
            if string.lower(p:Nick()):find(string.lower(targetName), 1, true) then
                targetPlayer = p
                break
            end
        end

        if not IsValid(targetPlayer) then
            local message = "[RARELOAD] Player '" .. targetName .. "' not found."
            print(message)
            if IsValid(ply) then
                ply:ChatPrint(message)
            end
            return
        end

        AntiStuck.testingPlayers[targetPlayer:SteamID()] = CurTime() + duration

        local message = string.format("[RARELOAD] Anti-stuck testing enabled for %s for %d seconds.",
            targetPlayer:Nick(), duration)
        print(message)

        if IsValid(ply) then
            ply:ChatPrint(message)
        end

        targetPlayer:ChatPrint(
            "[RARELOAD] Anti-stuck testing mode enabled for you. Your next respawn will trigger the anti-stuck system.")
    end)

    -- Console command to check testing mode status
    concommand.Add("rareload_antistuck_test_status", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[RARELOAD] Only admins can check anti-stuck testing status.")
            return
        end

        local message = "[RARELOAD] Anti-stuck testing status:"
        print(message)
        if IsValid(ply) then ply:ChatPrint(message) end

        local globalStatus = "Global testing mode: " .. (AntiStuck.testingMode and "ENABLED" or "DISABLED")
        print("  " .. globalStatus)
        if IsValid(ply) then ply:ChatPrint("  " .. globalStatus) end

        local activePlayerTests = 0
        local currentTime = CurTime()

        for steamID, expireTime in pairs(AntiStuck.testingPlayers) do
            if expireTime > currentTime then
                activePlayerTests = activePlayerTests + 1
                local targetPlayer = player.GetBySteamID(steamID)
                local playerName = IsValid(targetPlayer) and targetPlayer:Nick() or "Offline (" .. steamID .. ")"
                local timeLeft = math.ceil(expireTime - currentTime)

                local playerStatus = string.format("  Player testing: %s (%d seconds left)", playerName, timeLeft)
                print(playerStatus)
                if IsValid(ply) then ply:ChatPrint(playerStatus) end
            end
        end

        if activePlayerTests == 0 then
            local noPlayerTests = "  No active player-specific testing"
            print(noPlayerTests)
            if IsValid(ply) then ply:ChatPrint(noPlayerTests) end
        end
    end)

    -- Console command for quick self-testing (for the admin who runs it)
    concommand.Add("rareload_antistuck_test_me", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsAdmin() then
            if IsValid(ply) then
                ply:ChatPrint("[RARELOAD] Only admins can use this command.")
            end
            return
        end

        local duration = tonumber(args[1]) or 60 -- Default 1 minute
        AntiStuck.testingPlayers[ply:SteamID()] = CurTime() + duration

        ply:ChatPrint(string.format(
            "[RARELOAD] Anti-stuck testing enabled for you for %d seconds. Kill yourself to test!", duration))
        print(string.format("[RARELOAD] %s enabled anti-stuck testing for themselves (%d seconds)", ply:Nick(), duration))
    end)
end
