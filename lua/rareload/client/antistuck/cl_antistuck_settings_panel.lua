-- Enhanced Anti-Stuck Settings Panel with Type Safety and Performance Optimizations
-- @author RARELOAD Team
-- @version 2.0 Enhanced

-- Type annotations for lint compatibility
---@class EnhancedDButton : DButton
---@field hoverAnim number
---@field slideAnim number

---@class EnhancedDFrame : DFrame
---@field OnKeyCodePressed function

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}

-- Include the necessary files
include("rareload/client/entity_viewer/cl_entity_viewer_theme.lua")
include("rareload/client/antistuck/cl_profile_system.lua")
include("rareload/client/antistuck/cl_profile_manager.lua")

local THEME = THEME or {}

-- Enhanced Anti-Stuck Settings with Intelligent Defaults and Adaptive Configuration
Default_Anti_Stuck_Settings = {
    -- === CORE PERFORMANCE SETTINGS ===
    MAX_UNSTUCK_ATTEMPTS = 35, -- Optimized for speed vs thoroughness
    MAX_SEARCH_TIME = 1.5,     -- Faster resolution times
    RETRY_DELAY = 0.05,        -- Minimal delay for responsiveness
    DEBUG_LOGGING = false,     -- Performance-focused default
    ENABLE_CACHE = true,       -- Essential for performance
    CACHE_DURATION = 900,      -- Extended cache life (15 min)

    -- === INTELLIGENT DISTANCE & SAFETY ===
    SAFE_DISTANCE = 48,        -- Optimized player collision clearance
    PLAYER_HULL_TOLERANCE = 8, -- Enhanced collision detection
    MIN_GROUND_DISTANCE = 12,  -- Realistic ground clearance
    MAP_BOUNDS_PADDING = 128,  -- Efficient boundary handling

    -- === SMART SEARCH OPTIMIZATION ===
    VERTICAL_SEARCH_RANGE = 2048,   -- Focused vertical search
    HORIZONTAL_SEARCH_RANGE = 1536, -- Optimized horizontal coverage
    MAX_TRACE_DISTANCE = 2048,      -- Performance-balanced traces
    NODE_SEARCH_RADIUS = 1024,      -- Concentrated navmesh search
    ENTITY_SEARCH_RADIUS = 384,     -- Efficient entity detection

    -- === METHOD-SPECIFIC ENHANCEMENTS ===
    SPAWN_POINT_OFFSET_Z = 24,  -- Safe spawn positioning
    MAP_ENTITY_OFFSET_Z = 40,   -- Entity clearance optimization
    NAV_AREA_OFFSET_Z = 20,     -- Navigation mesh positioning
    NAVMESH_HEIGHT_OFFSET = 24, -- Mesh alignment enhancement
    FALLBACK_HEIGHT = 8192,     -- Reasonable emergency height

    -- === ADAPTIVE SEARCH PATTERNS ===
    GRID_RESOLUTION = 32,                      -- High-resolution initial scan
    SEARCH_RESOLUTIONS = { 32, 64, 128, 256 }, -- Progressive refinement
    SPIRAL_RINGS = 8,                          -- Optimal coverage rings
    POINTS_PER_RING = 12,                      -- Enhanced point density
    MAX_DISTANCE = 1200,                       -- Focused search radius
    VERTICAL_STEPS = 7,                        -- Granular vertical sampling
    VERTICAL_RANGE = 600,                      -- Comprehensive height range

    -- === PERFORMANCE TUNING ===
    DISPLACEMENT_STEP_SIZE = 64,   -- Efficient displacement increments
    DISPLACEMENT_MAX_HEIGHT = 800, -- Practical height limits
    SPACE_SCAN_ACCURACY = 3,       -- Balanced precision vs speed
    EMERGENCY_SAFE_RADIUS = 160,   -- Expanded emergency coverage
    RANDOM_ATTEMPTS = 25,          -- Optimized randomization

    -- === ADVANCED OPTIMIZATION FLAGS ===
    ADAPTIVE_TIMEOUTS = true,       -- Dynamic timeout adjustment
    PROGRESSIVE_ACCURACY = true,    -- Smart accuracy scaling
    EARLY_EXIT_OPTIMIZATION = true, -- Performance-first exits
    DISTANCE_PRIORITY = true,       -- Proximity-based selection
    SUCCESS_RATE_LEARNING = true,   -- Machine learning adaptation
    PERFORMANCE_MONITORING = true,  -- Real-time optimization
}


-- Intelligent Method Configuration with Performance Optimization
Default_Anti_Stuck_Methods = {
    { name = "⚡ Cached Positions", func = "TryCachedPositions", enabled = true, priority = 5, description = "Lightning-fast: Use proven safe positions from previous successful unstucks" },
    { name = "🎯 Smart Displacement", func = "TryDisplacement", enabled = true, priority = 10, description = "Ultra-fast: Physics-based intelligent movement with adaptive step sizing" },
    { name = "🧭 Navigation Mesh", func = "TryNodeGraph", enabled = true, priority = 15, description = "Optimal: Leverage Source engine navigation system for perfect pathfinding" },
    { name = "📍 Map Entities", func = "TryMapEntities", enabled = true, priority = 20, description = "Fast: Smart positioning near functional map entities and spawn points" },
    { name = "🔍 3D Space Scan", func = "Try3DSpaceScan", enabled = true, priority = 25, description = "Thorough: Advanced volumetric analysis with adaptive precision" },
    { name = "🏗️ World Brushes", func = "TryWorldBrushes", enabled = true, priority = 30, description = "Smart: Geometry-aware positioning using world architecture" },
    { name = "📐 Systematic Grid", func = "TrySystematicGrid", enabled = true, priority = 35, description = "Comprehensive: Methodical full-area coverage with adaptive resolution" },
    { name = "🎮 Spawn Points", func = "TrySpawnPoints", enabled = true, priority = 40, description = "Reliable: Map-defined safe zones with validity verification" },
    { name = "🚨 Emergency Teleport", func = "TryEmergencyTeleport", enabled = true, priority = 45, description = "Failsafe: Guaranteed positioning system for critical situations" }
}

-- Enhanced Setting Descriptions with Performance Impact Information
local settingDescriptions = {
    -- === CORE PERFORMANCE ===
    MAX_UNSTUCK_ATTEMPTS = "🎯 Maximum attempts to find safe position (Lower = Faster, Higher = More thorough)",
    MAX_SEARCH_TIME = "⏱️ Maximum time spent per unstuck attempt (Shorter = More responsive)",
    RETRY_DELAY = "⚡ Delay between method attempts (Lower = Faster resolution)",
    DEBUG_LOGGING = "🔍 Enable detailed debug output (Disable for better performance)",
    ENABLE_CACHE = "💾 Cache successful positions for instant reuse (Major performance boost)",
    CACHE_DURATION = "🕒 How long to keep cached positions (Longer = Better performance)",

    -- === SAFETY & DISTANCE ===
    SAFE_DISTANCE = "🛡️ Minimum clearance from obstacles (Higher = Safer positioning)",
    PLAYER_HULL_TOLERANCE = "👤 Extra space around player collision box (Prevents tight fits)",
    MIN_GROUND_DISTANCE = "🌍 Required distance from ground surface (Prevents underground)",
    MAP_BOUNDS_PADDING = "🗺️ Safety margin from map edges (Prevents out-of-bounds)",

    -- === SEARCH OPTIMIZATION ===
    VERTICAL_SEARCH_RANGE = "📏 Maximum upward/downward search distance",
    HORIZONTAL_SEARCH_RANGE = "↔️ Maximum sideways search radius",
    MAX_TRACE_DISTANCE = "🔍 Collision detection range (Lower = Better performance)",
    NODE_SEARCH_RADIUS = "🧭 Navigation mesh search radius",
    ENTITY_SEARCH_RADIUS = "📍 Map entity detection range",

    -- === METHOD ENHANCEMENTS ===
    SPAWN_POINT_OFFSET_Z = "🎮 Height offset from spawn points (Prevents spawn camping)",
    MAP_ENTITY_OFFSET_Z = "🏗️ Clearance from map entities (Safer positioning)",
    NAV_AREA_OFFSET_Z = "🗺️ Navigation area height adjustment",
    NAVMESH_HEIGHT_OFFSET = "🧭 NavMesh positioning offset",
    FALLBACK_HEIGHT = "🚨 Emergency teleport altitude (Last resort height)",

    -- === SEARCH PATTERNS ===
    GRID_RESOLUTION = "📐 Grid search precision (Lower = Finer detail, Slower)",
    SPIRAL_RINGS = "🌀 Spiral search ring count (More rings = Better coverage)",
    POINTS_PER_RING = "⭕ Points checked per spiral ring (Higher = More thorough)",
    MAX_DISTANCE = "📏 Maximum search radius from stuck position",
    VERTICAL_STEPS = "📊 Vertical search precision steps",
    VERTICAL_RANGE = "📏 Total vertical search span",
    SEARCH_RESOLUTIONS = "🔍 Progressive grid sizes (Starts fine, gets broader)",

    -- === PERFORMANCE TUNING ===
    DISPLACEMENT_STEP_SIZE = "🎯 Physics displacement increment size",
    DISPLACEMENT_MAX_HEIGHT = "⬆️ Maximum height for displacement checks",
    SPACE_SCAN_ACCURACY = "🔍 3D scan detail level (1=Fast, 5=Thorough)",
    EMERGENCY_SAFE_RADIUS = "🚨 Emergency positioning safety zone",
    RANDOM_ATTEMPTS = "🎲 Random method attempt count",

    -- === ADVANCED FEATURES ===
    ADAPTIVE_TIMEOUTS = "🧠 Smart timeout adjustment based on performance",
    PROGRESSIVE_ACCURACY = "⚡ Start fast, get more accurate if needed",
    EARLY_EXIT_OPTIMIZATION = "🏃 Exit immediately when good position found",
    DISTANCE_PRIORITY = "📍 Prefer closer positions over distant ones",
    SUCCESS_RATE_LEARNING = "🎓 Learn from method success rates",
    PERFORMANCE_MONITORING = "📊 Real-time performance optimization"
}
-- Define value ranges for numeric settings
local settingRanges = {
    MAX_UNSTUCK_ATTEMPTS = { min = 10, max = 200, step = 1 },
    SAFE_DISTANCE = { min = 16, max = 512, step = 4 },
    VERTICAL_SEARCH_RANGE = { min = 512, max = 8192, step = 64 },
    HORIZONTAL_SEARCH_RANGE = { min = 512, max = 4096, step = 64 },
    NODE_SEARCH_RADIUS = { min = 256, max = 4096, step = 64 },
    CACHE_DURATION = { min = 60, max = 1800, step = 30 },
    MIN_GROUND_DISTANCE = { min = 1, max = 64, step = 1 },
    PLAYER_HULL_TOLERANCE = { min = 1, max = 32, step = 1 },
    MAP_BOUNDS_PADDING = { min = 64, max = 1024, step = 32 },
    GRID_RESOLUTION = { min = 16, max = 256, step = 8 },
    MAX_TRACE_DISTANCE = { min = 1024, max = 8192, step = 128 },
    SPAWN_POINT_OFFSET_Z = { min = 0, max = 128, step = 2 },
    MAP_ENTITY_OFFSET_Z = { min = 0, max = 128, step = 2 },
    NAV_AREA_OFFSET_Z = { min = 0, max = 128, step = 2 },
    RETRY_DELAY = { min = 0.0, max = 2.0, step = 0.05 },
    MAX_SEARCH_TIME = { min = 0.5, max = 10.0, step = 0.1 },
    RANDOM_ATTEMPTS = { min = 10, max = 200, step = 5 },
    ENTITY_SEARCH_RADIUS = { min = 128, max = 2048, step = 32 },
    NAVMESH_HEIGHT_OFFSET = { min = 0, max = 128, step = 2 },
    FALLBACK_HEIGHT = { min = 1024, max = 32768, step = 256 },
    SPIRAL_RINGS = { min = 1, max = 30, step = 1 },
    POINTS_PER_RING = { min = 4, max = 32, step = 1 },
    MAX_DISTANCE = { min = 500, max = 5000, step = 100 },
    VERTICAL_STEPS = { min = 1, max = 20, step = 1 },
    VERTICAL_RANGE = { min = 50, max = 1000, step = 25 },
    -- Method-specific ranges
    DISPLACEMENT_STEP_SIZE = { min = 32, max = 512, step = 16 },
    DISPLACEMENT_MAX_HEIGHT = { min = 200, max = 2000, step = 100 },
    SPACE_SCAN_ACCURACY = { min = 1, max = 5, step = 1 },
    EMERGENCY_SAFE_RADIUS = { min = 50, max = 500, step = 25 }
}

-- Group settings for better UI organization
local settingGroups = {
    General = {
        "MAX_UNSTUCK_ATTEMPTS", "RETRY_DELAY", "MAX_SEARCH_TIME", "DEBUG_LOGGING", "ENABLE_CACHE", "CACHE_DURATION"
    },
    Search = {
        "SAFE_DISTANCE", "MAX_DISTANCE", "HORIZONTAL_SEARCH_RANGE", "VERTICAL_SEARCH_RANGE",
        "MAX_TRACE_DISTANCE", "MIN_GROUND_DISTANCE", "PLAYER_HULL_TOLERANCE", "MAP_BOUNDS_PADDING"
    },
    Navigation = {
        "NODE_SEARCH_RADIUS", "ENTITY_SEARCH_RADIUS"
    },
    Grid = {
        "GRID_RESOLUTION", "SEARCH_RESOLUTIONS"
    },
    Spiral = {
        "SPIRAL_RINGS", "POINTS_PER_RING"
    },
    Vertical = {
        "VERTICAL_STEPS", "VERTICAL_RANGE"
    },
    Offsets = {
        "SPAWN_POINT_OFFSET_Z", "MAP_ENTITY_OFFSET_Z", "NAV_AREA_OFFSET_Z", "NAVMESH_HEIGHT_OFFSET", "FALLBACK_HEIGHT"
    },
    Methods = {
        "RANDOM_ATTEMPTS"
    },
    ["Method Specific"] = {
        "DISPLACEMENT_STEP_SIZE", "DISPLACEMENT_MAX_HEIGHT", "SPACE_SCAN_ACCURACY", "EMERGENCY_SAFE_RADIUS"
    }
}

-- Show a modal to paste clipboard text (used for import)
function RARELOAD.AntiStuckSettings.GetClipboardText(callback)
    -- Create a modal frame
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Paste Settings from Clipboard")
    frame:SetSize(500, 180)
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(false)
    frame:ShowCloseButton(true)
    frame:SetBackgroundBlur(true)

    local label = vgui.Create("DLabel", frame)
    label:SetText("Press Ctrl+V to paste your exported settings below, then click OK.")
    label:SetFont("DermaDefaultBold")
    label:SizeToContents()
    label:SetPos(20, 40)

    local textEntry = vgui.Create("DTextEntry", frame)
    textEntry:SetPos(20, 70)
    textEntry:SetSize(460, 40)
    textEntry:SetMultiline(true)
    textEntry:SetUpdateOnType(true)
    textEntry:RequestFocus()

    -- Try to auto-fill clipboard content if possible
    if input and input.GetClipboardText then
        local clip = input.GetClipboardText()
        if clip and clip ~= "" then
            textEntry:SetValue(clip)
        end
    end

    local okBtn = vgui.Create("DButton", frame)
    okBtn:SetText("OK")
    okBtn:SetSize(100, 30)
    okBtn:SetPos(390, 130)
    okBtn.DoClick = function()
        local text = textEntry:GetValue()
        frame:Close()
        if callback then callback(text) end
    end

    local cancelBtn = vgui.Create("DButton", frame)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetSize(100, 30)
    cancelBtn:SetPos(280, 130)
    cancelBtn.DoClick = function()
        frame:Close()
        if callback then callback(nil) end
    end
end

-- Optimized settings loading with caching
function RARELOAD.AntiStuckSettings.LoadSettings()
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileSettings then
        -- Use the optimized cached loading
        local settings = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileSettings()
        if settings then
            -- Ensure all default settings are present for forward compatibility
            for key, defaultValue in pairs(Default_Anti_Stuck_Settings) do
                if settings[key] == nil then
                    settings[key] = defaultValue
                end
            end
            return settings
        end
    end -- Fallback to defaults if profile system not available
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.DeepCopySettings then
        -- Use table.Copy instead of removed DeepCopySettings
        return table.Copy(Default_Anti_Stuck_Settings)
    else
        -- Fallback manual deep copy for METHOD_ENABLE_FLAGS
        local settings = {}
        for k, v in pairs(Default_Anti_Stuck_Settings) do
            if type(v) == "table" then
                settings[k] = {}
                for subK, subV in pairs(v) do
                    settings[k][subK] = subV
                end
            else
                settings[k] = v
            end
        end
        return settings
    end
end

-- Optimized settings saving with performance improvements
function RARELOAD.AntiStuckSettings.SaveSettings(settings)
    -- Verify settings table is valid
    if not settings or type(settings) ~= "table" then
        print("[RARELOAD] Error: Invalid settings table")
        return false
    end

    -- VALIDATION: Ensure this is settings data, not methods (optimized)
    local function validateSettingsData(data)
        for k, v in pairs(data) do
            -- Quick check for methods data structure
            if type(k) == "number" and type(v) == "table" and v.func and v.name then
                return false, "Data contains methods structure instead of settings"
            end
            -- Ensure keys are strings
            if type(k) ~= "string" then
                return false, "Settings keys must be strings, found: " .. type(k)
            end
            -- Check if key exists in default settings (only for critical validation)
            if not Default_Anti_Stuck_Settings[k] then
                -- Allow new settings for forward compatibility, just warn
                print("[RARELOAD] Warning: Unknown setting key: " .. tostring(k))
            end
        end
        return true, "Valid settings data"
    end

    local isValid, error = validateSettingsData(settings)
    if not isValid then
        print("[RARELOAD] Error: Invalid settings data - " .. error)
        notification.AddLegacy("Settings validation failed: " .. error, NOTIFY_ERROR, 5)
        return false
    end

    -- Use optimized profile system if available
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile then
        local currentProfileName = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfile()
        print("[RARELOAD] Saving settings to profile: " .. (currentProfileName or "unknown"))

        -- Use the optimized update function with batch operations
        local success = RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile(settings, nil)
        if success then
            -- Send ONLY settings to server (never methods via this path)
            net.Start("RareloadAntiStuckSettings")
            net.WriteTable(settings)
            net.SendToServer()

            print("[RARELOAD] Settings saved successfully to profile: " .. (currentProfileName or "unknown"))
            return true
        else
            print("[RARELOAD] Failed to update profile: " .. (currentProfileName or "unknown"))
            return false
        end
    end
    print("[RARELOAD] Error: Profile system not available")
    return false
end

-- Export settings to clipboard
function RARELOAD.AntiStuckSettings.ExportSettings()
    local settings = RARELOAD.AntiStuckSettings.LoadSettings()
    local exported = {
        version = "1.0",
        timestamp = os.time(),
        settings = settings
    }
    local jsonData = util.TableToJSON(exported, true)
    SetClipboardText(jsonData)
    return true
end

-- Import settings from clipboard
function RARELOAD.AntiStuckSettings.ImportSettings(callback)
    RARELOAD.AntiStuckSettings.GetClipboardText(function(clipboardText)
        if not clipboardText or clipboardText == "" then
            notification.AddLegacy("No data pasted. Please copy your exported settings and paste them here.",
                NOTIFY_ERROR, 3)
            if callback then callback(false, "No data pasted") end
            return
        end

        local importedData = util.JSONToTable(clipboardText)
        if not importedData or type(importedData) ~= "table" or not importedData.settings then
            notification.AddLegacy("Invalid settings format. Please ensure you pasted the correct exported data.",
                NOTIFY_ERROR, 3)
            if callback then callback(false, "Invalid format") end
            return
        end

        -- Validate version
        if importedData.version ~= "1.0" then
            notification.AddLegacy("Unsupported settings version: " .. tostring(importedData.version), NOTIFY_ERROR, 3)
            if callback then callback(false, "Unsupported version") end
            return
        end

        -- Save the imported settings
        local saveSuccess = RARELOAD.AntiStuckSettings.SaveSettings(importedData.settings)
        if saveSuccess then
            notification.AddLegacy("Settings imported successfully!", NOTIFY_GENERIC, 2)
            if callback then callback(true) end
        else
            notification.AddLegacy("Failed to save imported settings", NOTIFY_ERROR, 3)
            if callback then callback(false, "Save failed") end
        end
    end)
end

-- Helper function to check if the settings panel is currently open
function RARELOAD.AntiStuckSettings.IsSettingsPanelOpen()
    local worldPanel = vgui.GetWorldPanel()
    if not IsValid(worldPanel) then return false end

    for _, child in pairs(worldPanel:GetChildren()) do
        if IsValid(child) and child.GetName and child:GetName() == "AntiStuckSettingsPanel" then
            return true
        end
    end
    return false
end

-- Helper function to close any existing settings panels or profile managers
function RARELOAD.AntiStuckSettings.CloseAllDialogs()
    local worldPanel = vgui.GetWorldPanel()
    if not IsValid(worldPanel) then return end

    for _, child in pairs(worldPanel:GetChildren()) do
        if IsValid(child) and child.GetName and
            (child:GetName() == "AntiStuckSettingsPanel" or child:GetName() == "ProfileManagerDialog") then
            child:Close()
        end
    end
end

-- Open the enhanced settings panel
function RARELOAD.AntiStuckSettings.OpenSettingsPanel()
    -- Prevent rapid successive calls
    if RARELOAD.AntiStuckSettings._openingPanel then return end
    RARELOAD.AntiStuckSettings._openingPanel = true

    -- Close any existing dialogs first
    RARELOAD.AntiStuckSettings.CloseAllDialogs()

    -- Add a small delay to ensure panels are fully closed
    timer.Simple(0.05, function()
        RARELOAD.AntiStuckSettings._openingPanel = false
        RARELOAD.AntiStuckSettings._CreateSettingsPanel()
    end)
end

-- Internal function to actually create the settings panel
function RARELOAD.AntiStuckSettings._CreateSettingsPanel()
    local currentSettings = RARELOAD.AntiStuckSettings.LoadSettings()
    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.min(screenW * 0.65, 900)
    local frameH = math.min(screenH * 0.8, 750)

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:SetBackgroundBlur(true)
    frame:SetName("AntiStuckSettingsPanel")

    -- Enhanced frame painting with gradient and shadow
    frame.Paint = function(self, w, h)
        -- Shadow
        draw.RoundedBox(12, 2, 2, w, h, Color(0, 0, 0, 100))
        -- Main background
        draw.RoundedBox(12, 0, 0, w, h, THEME.background)
        -- Header gradient
        draw.RoundedBoxEx(12, 0, 0, w, 80, THEME.primary, true, true, false, false)

        -- Title and subtitle
        draw.SimpleText("Anti-Stuck Configuration", "RareloadTitle", 28, 25, THEME.textHighlight, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        draw.SimpleText("Advanced settings for the anti-stuck system", "RareloadBody", 28, 50, Color(255, 255, 255, 180),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Decorative line
        surface.SetDrawColor(Color(255, 255, 255, 50))
        surface.DrawLine(0, 80, w, 80)
    end

    -- Enhanced close button with hover animation
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(40, 40)
    closeBtn:SetPos(frameW - 50, 20)
    closeBtn:SetText("")
    -- Initialize animation variable properly to avoid lint warning
    if not closeBtn.hoverAnim then
        closeBtn.hoverAnim = 0
    end
    closeBtn.Paint = function(self, w, h)
        -- Ensure animation variable exists
        self.hoverAnim = self.hoverAnim or 0
        self.hoverAnim = Lerp(FrameTime() * 8, self.hoverAnim, self:IsHovered() and 1 or 0)
        local bgColor = ColorAlpha(Color(255, 80, 80), 50 + self.hoverAnim * 100)
        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        local textColor = Color(255, 255, 255, 150 + self.hoverAnim * 105)
        draw.SimpleText("X", "RareloadHeading", w / 2, h / 2, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        frame:AlphaTo(0, 0.2, 0, function() frame:Remove() end)
    end

    -- Top toolbar with enhanced styling
    local toolbar = vgui.Create("DPanel", frame)
    toolbar:SetSize(frameW - 40, 60)
    toolbar:SetPos(20, 90)
    toolbar.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.surfaceVariant)
        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Enhanced search with icon
    local searchBox = vgui.Create("DTextEntry", toolbar)
    searchBox:SetSize(160, 32)
    searchBox:SetPos(45, 14)
    searchBox:SetFont("RareloadText")
    searchBox:SetPlaceholderText("Search settings...")
    searchBox:SetUpdateOnType(true)

    local searchIcon = vgui.Create("DLabel", toolbar)
    searchIcon:SetSize(32, 32)
    searchIcon:SetPos(10, 14)
    searchIcon:SetText("FIND")
    searchIcon:SetFont("RareloadSmall")
    searchIcon:SetTextColor(THEME.textSecondary)

    -- Profile management dropdown
    local profileCombo = vgui.Create("DComboBox", toolbar)
    profileCombo:SetSize(140, 32)
    profileCombo:SetPos(215, 14)
    profileCombo:SetText("Select Profile")
    profileCombo:SetFont("RareloadText")

    -- Populate profiles
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.GetProfilesList then
        local profiles = RARELOAD.AntiStuck.ProfileSystem.GetProfilesList()
        for _, profile in ipairs(profiles) do
            local displayText = profile.displayName
            if profile.mapSpecific then
                displayText = displayText .. " (" .. profile.map .. ")"
            end
            if profile.shared then
                displayText = displayText .. " [Shared]"
            end
            profileCombo:AddChoice(displayText, profile.name)
        end -- Set current profile
        if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.currentProfile then
            local currentProfile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(RARELOAD.AntiStuck.ProfileSystem
                .currentProfile)
            if currentProfile then
                profileCombo:SetValue(currentProfile.displayName or "Default Settings")
            end
        end

        profileCombo.OnSelect = function(self, index, value, data)
            if data and RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.ApplyProfile then
                local success = RARELOAD.AntiStuck.ProfileSystem.ApplyProfile(data)
                if success then
                    chat.AddText(Color(100, 255, 100), "[RARELOAD] ", Color(255, 255, 255), "Applied profile: " .. value)
                    timer.Simple(0.1, function()
                        RARELOAD.AntiStuckSettings.OpenSettingsPanel()
                    end)
                else
                    chat.AddText(Color(255, 100, 100), "[RARELOAD] ", Color(255, 255, 255),
                        "Failed to apply profile: " .. value)
                end
            end
        end
    end -- Action buttons with proper spacing

    local buttonData = {
        {
            text = "New Profile",
            pos = 365,
            width = 80,
            color = THEME.accent,
            func = function()
                if RARELOAD.AntiStuckSettings.OpenProfileCreationDialog then
                    RARELOAD.AntiStuckSettings.OpenProfileCreationDialog(currentSettings)
                end
            end
        },
        {
            text = "Export",
            pos = 465,
            width = 60,
            color = THEME.info,
            func = function()
                RARELOAD.AntiStuckSettings.ExportSettings()
                notification.AddLegacy("Settings exported to clipboard!", NOTIFY_GENERIC, 2)
            end
        },
        {
            text = "Import",
            pos = 535,
            width = 60,
            color = THEME.warning,
            func = function()
                RARELOAD.AntiStuckSettings.ImportSettings(function(success)
                    if success then
                        timer.Simple(0.1, function()
                            RARELOAD.AntiStuckSettings.OpenSettingsPanel()
                        end)
                    end
                end)
            end
        },
        {
            text = "Manage",
            pos = 605,
            width = 60,
            color = THEME.accent,
            func = function()
                if RARELOAD.AntiStuckSettings.OpenProfileManager then
                    RARELOAD.AntiStuckSettings.OpenProfileManager()
                end
            end
        },
        {
            text = "Reset",
            pos = 675,
            width = 60,
            color = THEME.error,
            func = function()
                for k, v in pairs(Default_Anti_Stuck_Settings) do
                    currentSettings[k] = v
                end
                frame:Remove()
                timer.Simple(0, function() RARELOAD.AntiStuckSettings.OpenSettingsPanel() end)
            end
        },
        {
            text = "Reload",
            pos = 745,
            width = 60,
            color = THEME.success,
            func = function()
                currentSettings = RARELOAD.AntiStuckSettings.LoadSettings()
                timer.Simple(0, function() RARELOAD.AntiStuckSettings.OpenSettingsPanel() end)
            end
        }
    }

    for _, btn in ipairs(buttonData) do
        local button = vgui.Create("DButton", toolbar)
        button:SetSize(btn.width or 60, 32)
        button:SetPos(btn.pos, 14)
        button:SetText(btn.text)
        button:SetFont("RareloadSmall")
        button.hoverAnim = 0
        button.Paint = function(self, w, h)
            self.hoverAnim = Lerp(FrameTime() * 6, self.hoverAnim, self:IsHovered() and 1 or 0)
            local color = ColorAlpha(btn.color, 100 + self.hoverAnim * 100)
            draw.RoundedBox(6, 0, 0, w, h, color)
            draw.SimpleText(self:GetText(), "RareloadSmall", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        button.DoClick = function()
            surface.PlaySound("ui/buttonclickrelease.wav")
            btn.func()
        end
    end

    -- Enhanced settings scroll panel
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(20, 160)
    scroll:SetSize(frameW - 40, frameH - 230)
    local scrollBar = scroll:GetVBar()
    scrollBar:SetWide(12)
    scrollBar.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.backgroundDark)
    end
    if scrollBar.btnGrip then
        scrollBar.btnGrip.Paint = function(self, w, h)
            local color = self:IsHovered() and THEME.primary or THEME.textSecondary
            draw.RoundedBox(6, 2, 0, w - 4, h, color)
        end
    end

    local controls = {}
    local collapsedSections = {}

    -- Create forward declaration of rebuildSettings function
    local rebuildSettings

    -- Enhanced section header with collapse functionality
    local function addSectionHeader(text, groupKey)
        local headerPanel = vgui.Create("DPanel", scroll)
        headerPanel:SetTall(45)
        headerPanel:Dock(TOP)
        headerPanel:DockMargin(0, 10, 0, 5)
        headerPanel:SetCursor("hand")

        local isCollapsed = collapsedSections[groupKey] or false

        headerPanel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.primary)

            local arrow = isCollapsed and ">" or "v"
            draw.SimpleText(arrow, "RareloadText", 15, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(text, "RareloadTitle", 35, h / 2, THEME.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            -- Section stats
            local sectionKeys = settingGroups[groupKey] or {}
            draw.SimpleText(#sectionKeys .. " settings", "RareloadSmall", w - 15, h / 2, Color(255, 255, 255, 180),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        headerPanel.OnMousePressed = function()
            surface.PlaySound("ui/buttonclick.wav")
            collapsedSections[groupKey] = not (collapsedSections[groupKey] or false)
            rebuildSettings()
        end

        return not isCollapsed
    end

    -- Enhanced setting row with proper controls
    local function addSettingRow(name, value)
        local container = vgui.Create("DPanel", scroll)
        container:SetTall(85)
        container:Dock(TOP)
        container:DockMargin(0, 2, 0, 2)
        container.Paint = function(self, w, h)
            local color = self:IsHovered() and THEME.surface or THEME.surfaceVariant
            draw.RoundedBox(6, 0, 0, w, h, color)
            surface.SetDrawColor(THEME.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        -- Setting name and description
        local nameLabel = vgui.Create("DLabel", container)
        nameLabel:SetText(name)
        nameLabel:SetFont("RareloadText")
        nameLabel:SetTextColor(THEME.textPrimary)
        nameLabel:SetPos(15, 10)
        nameLabel:SetSize(400, 20)

        local descLabel = vgui.Create("DLabel", container)
        descLabel:SetText(settingDescriptions[name] or "")
        descLabel:SetFont("RareloadSmall")
        descLabel:SetTextColor(THEME.textSecondary)
        descLabel:SetPos(15, 32)
        descLabel:SetSize(400, 15)

        -- Control based on type
        local control
        local controlWidth = 250

        if type(value) == "boolean" then
            control = vgui.Create("DCheckBox", container)
            control:SetChecked(value)
            control:SetPos(frameW - 100, 25)
            control:SetSize(30, 30)
        elseif name == "SEARCH_RESOLUTIONS" and type(value) == "table" then
            -- Special handling for array type
            control = vgui.Create("DTextEntry", container)
            control:SetText(table.concat(value, ", "))
            control:SetPos(frameW - controlWidth - 40, 25)
            control:SetSize(controlWidth, 30)
            control:SetFont("RareloadText")
        elseif type(value) == "number" and settingRanges[name] then
            -- Use DNumSlider for better number input
            control = vgui.Create("DNumSlider", container)
            control:SetPos(frameW - controlWidth - 40, 25)
            control:SetSize(controlWidth, 30)
            local range = settingRanges[name]
            control:SetMin(range.min)
            control:SetMax(range.max)
            control:SetDecimals(range.step < 1 and 2 or 0)
            control:SetValue(value)
            control.Label:SetVisible(false) -- Hide the label since we have our own

            -- Apply text color styling safely with timer to ensure components exist
            timer.Simple(0.01, function()
                if IsValid(control) then
                    for _, child in pairs(control:GetChildren()) do
                        if IsValid(child) and child.SetTextColor then
                            child:SetTextColor(THEME.textPrimary)
                        end
                        if IsValid(child) and child.GetName and child:GetName() == "DTextEntry" then
                            child:SetTextColor(THEME.textPrimary)
                        end
                    end
                end
            end)
        else
            control = vgui.Create("DTextEntry", container)
            control:SetText(tostring(value))
            control:SetNumeric(type(value) == "number")
            control:SetPos(frameW - controlWidth - 40, 25)
            control:SetSize(controlWidth, 30)
            control:SetFont("RareloadText")
        end

        controls[name] = control
    end

    -- Build the settings UI with search filter
    rebuildSettings = function()
        scroll:Clear()
        controls = {}

        local function matchesSearch(name)
            local search = searchBox:GetValue():lower()
            if search == "" then return true end
            return name:lower():find(search, 1, true) or
                (settingDescriptions[name] and settingDescriptions[name]:lower():find(search, 1, true))
        end

        for group, keys in pairs(settingGroups) do
            local groupHasVisible = false
            for _, name in ipairs(keys) do
                if matchesSearch(name) then
                    groupHasVisible = true
                    break
                end
            end

            if groupHasVisible then
                local sectionVisible = addSectionHeader(group, group)
                if sectionVisible then
                    for _, name in ipairs(keys) do
                        if matchesSearch(name) then
                            addSettingRow(name, currentSettings[name])
                        end
                    end
                end
            end
        end
    end

    rebuildSettings()

    -- Enhanced save button with validation and feedback
    local saveBtn = vgui.Create("DButton", frame)
    saveBtn:SetText("")
    saveBtn:SetFont("RareloadText")
    saveBtn:SetSize(200, 45)
    saveBtn:SetPos(frameW / 2 - 100, frameH - 60)
    -- Initialize animation variable properly to avoid lint warning
    if not saveBtn.hoverAnim then
        saveBtn.hoverAnim = 0
    end
    saveBtn.Paint = function(self, w, h)
        -- Ensure animation variable exists
        self.hoverAnim = self.hoverAnim or 0
        self.hoverAnim = Lerp(FrameTime() * 6, self.hoverAnim, self:IsHovered() and 1 or 0)
        local color = Color(
            THEME.success.r + self.hoverAnim * 20,
            THEME.success.g + self.hoverAnim * 20,
            THEME.success.b + self.hoverAnim * 20,
            255
        )
        draw.RoundedBox(10, 0, 0, w, h, color)

        -- Shine effect
        local shine = math.sin(CurTime() * 3) * 0.5 + 0.5
        draw.RoundedBox(10, 0, 0, w * shine * 0.3, h, Color(255, 255, 255, 30))

        draw.SimpleText("SAVE SETTINGS", "RareloadText", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    saveBtn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")

        local newSettings = {}
        local hasErrors = false

        for name, control in pairs(controls) do
            if control.GetChecked then   -- DCheckBox
                newSettings[name] = control:GetChecked()
            elseif control.GetValue then -- DNumSlider or DTextEntry
                local value = control:GetValue()
                if name == "SEARCH_RESOLUTIONS" and type(currentSettings[name]) == "table" then
                    -- Parse comma-separated values for SEARCH_RESOLUTIONS
                    local resolutions = {}
                    for num in string.gmatch(value, "%d+") do
                        table.insert(resolutions, tonumber(num))
                    end
                    if #resolutions > 0 then
                        newSettings[name] = resolutions
                    else
                        hasErrors = true
                    end
                elseif type(currentSettings[name]) == "number" then
                    newSettings[name] = tonumber(value) or currentSettings[name]
                else
                    newSettings[name] = value
                end
            end
        end

        if hasErrors then
            notification.AddLegacy("Validation errors found - check your inputs", NOTIFY_ERROR, 4)
            return
        end
        local success = RARELOAD.AntiStuckSettings.SaveSettings(newSettings)
        if success then
            notification.AddLegacy("Settings and profile updated successfully!", NOTIFY_GENERIC, 3)

            -- Success animation
            local successOverlay = vgui.Create("DPanel", frame)
            successOverlay:SetSize(frameW, frameH)
            successOverlay:SetPos(0, 0)
            successOverlay:SetAlpha(0)
            successOverlay.Paint = function(self, w, h)
                draw.RoundedBox(12, 0, 0, w, h, Color(100, 255, 100, 30))
            end
            successOverlay:AlphaTo(255, 0.1, 0)
            timer.Simple(0.5, function()
                if IsValid(successOverlay) then
                    successOverlay:AlphaTo(0, 0.3, 0, function() successOverlay:Remove() end)
                end
            end)
        else
            notification.AddLegacy("Failed to save settings", NOTIFY_ERROR, 3)
        end
    end

    -- Update on search
    searchBox.OnValueChange = rebuildSettings

    -- Keyboard shortcuts
    frame.OnKeyCodePressed = function(self, key)
        if key == KEY_ESCAPE then
            frame:Close()
        elseif key == KEY_S and input.IsKeyDown(KEY_LCONTROL) then
            saveBtn:DoClick()
        elseif key == KEY_R and input.IsKeyDown(KEY_LCONTROL) then
            buttonData[5].func() -- Reset
        end
    end

    return frame
end

-- Setup command
concommand.Add("rareload_antistuck_settings", function()
    if RARELOAD.AntiStuckSettings.OpenSettingsPanel then
        RARELOAD.AntiStuckSettings.OpenSettingsPanel()
    end
end)

-- Console commands for profile management
concommand.Add("rareload_profile_create", function()
    if RARELOAD.AntiStuckSettings.OpenProfileCreationDialog then
        local currentSettings = RARELOAD.AntiStuckSettings.LoadSettings()
        RARELOAD.AntiStuckSettings.OpenProfileCreationDialog(currentSettings)
    end
end)

concommand.Add("rareload_profile_manager", function()
    if RARELOAD.AntiStuckSettings.OpenProfileManager then
        RARELOAD.AntiStuckSettings.OpenProfileManager()
    end
end)

-- Console command to enable/disable auto-saving server settings
concommand.Add("rareload_antistuck_autosave_server", function(ply, cmd, args)
    if args[1] == "1" or args[1] == "true" or args[1] == "on" then
        RARELOAD.AntiStuckSettings.autoSaveServerSettings = true
        LocalPlayer():ChatPrint("[RARELOAD] Auto-save server settings: ENABLED")
    elseif args[1] == "0" or args[1] == "false" or args[1] == "off" then
        RARELOAD.AntiStuckSettings.autoSaveServerSettings = false
        LocalPlayer():ChatPrint("[RARELOAD] Auto-save server settings: DISABLED")
    else
        local status = RARELOAD.AntiStuckSettings.autoSaveServerSettings and "ENABLED" or "DISABLED"
        LocalPlayer():ChatPrint("[RARELOAD] Auto-save server settings: " .. status)
        LocalPlayer():ChatPrint("Usage: rareload_antistuck_autosave_server [1|0|true|false|on|off]")
    end
end)

-- Set default to false to prevent unwanted auto-saving
RARELOAD.AntiStuckSettings.autoSaveServerSettings = false

-- Setup networking to receive settings from server
net.Receive("RareloadAntiStuckConfig", function()
    local serverSettings = net.ReadTable()
    if not serverSettings or type(serverSettings) ~= "table" then return end

    -- Only update settings if we're not currently editing them
    local isEditingSettings = false
    for _, v in pairs(vgui.GetWorldPanel():GetChildren()) do
        if v:GetName() == "AntiStuckSettingsPanel" then
            isEditingSettings = true
            break
        end
    end
    if not isEditingSettings then
        -- Only auto-save server settings if explicitly enabled
        if RARELOAD.AntiStuckSettings.autoSaveServerSettings then
            if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile then
                RARELOAD.AntiStuck.ProfileSystem.UpdateCurrentProfile(serverSettings, nil)
                print("[RARELOAD] Anti-Stuck settings updated from server and saved to current profile")
            end
        else
            print("[RARELOAD] Anti-Stuck settings received from server (not auto-saved to profile)")
        end
    end
end)

-- Handle shared profile reception
net.Receive("RareloadReceiveSharedProfile", function()
    local sharedProfile = net.ReadTable()
    if not sharedProfile or not sharedProfile.name then return end

    -- Add [Shared] prefix to distinguish from local profiles
    local originalName = sharedProfile.name
    sharedProfile.name = "[Shared] " .. sharedProfile.name
    sharedProfile.shared = true

    -- Import the shared profile
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.ImportProfile then
        local success, msg = RARELOAD.AntiStuck.ProfileSystem.ImportProfile(sharedProfile)
        if success then
            chat.AddText(Color(100, 255, 100), "[RARELOAD] ", Color(255, 255, 255),
                "Received shared profile: " .. sharedProfile.displayName)
        else
            print("[RARELOAD] Failed to import shared profile: " .. msg)
        end
    end
end)

-- Hook to handle profile settings loaded from profile system
hook.Add("RareloadProfileSettingsLoaded", "UpdateAntiStuckSettingsUI", function(settings, methods)
    if not settings then return end

    print("[RARELOAD] Profile settings loaded - updating UI")

    -- Store the loaded settings for the UI to use
    RARELOAD.AntiStuckSettings._loadedSettings = table.Copy(settings)
    RARELOAD.AntiStuckSettings._loadedmethods = table.Copy(methods or {})

    -- If settings panel is open, refresh it
    timer.Simple(0.1, function()
        if RARELOAD.AntiStuckSettings.IsSettingsPanelOpen and RARELOAD.AntiStuckSettings.IsSettingsPanelOpen() then
            -- Refresh the settings panel to show the new settings
            if RARELOAD.AntiStuckSettings.RefreshSettingsPanel then
                RARELOAD.AntiStuckSettings.RefreshSettingsPanel()
            end
        end
    end)
end)

-- Function to check if settings panel is open
function RARELOAD.AntiStuckSettings.IsSettingsPanelOpen()
    local worldPanel = vgui.GetWorldPanel()
    if not IsValid(worldPanel) then return false end

    for _, child in pairs(worldPanel:GetChildren()) do
        if IsValid(child) and child.GetName and child:GetName() == "AntiStuckSettingsPanel" then
            return true
        end
    end
    return false
end

-- Function to refresh settings panel if open
function RARELOAD.AntiStuckSettings.RefreshSettingsPanel()
    local worldPanel = vgui.GetWorldPanel()
    if not IsValid(worldPanel) then return end

    for _, child in pairs(worldPanel:GetChildren()) do
        if IsValid(child) and child.GetName and child:GetName() == "AntiStuckSettingsPanel" then
            -- Close and reopen the panel to refresh it
            child:Close()
            timer.Simple(0.2, function()
                RARELOAD.AntiStuckSettings.OpenSettingsPanel()
            end)
            break
        end
    end
end

-- Override LoadSettings to use loaded settings if available
local originalLoadSettings = RARELOAD.AntiStuckSettings.LoadSettings
function RARELOAD.AntiStuckSettings.LoadSettings()
    -- If we have loaded settings from profile switch, use those
    if RARELOAD.AntiStuckSettings._loadedSettings then
        local settings = table.Copy(RARELOAD.AntiStuckSettings._loadedSettings)
        -- Clear the loaded settings to prevent reuse
        RARELOAD.AntiStuckSettings._loadedSettings = nil
        return settings
    end

    -- Otherwise use the original function
    return originalLoadSettings()
end

-- Console command to test profile system
concommand.Add("rareload_test_profile_system", function()
    if RARELOAD.AntiStuck.ProfileSystem then
        print("[RARELOAD] Profile system is available!")
        print("  Current profile: " .. tostring(RARELOAD.AntiStuck.ProfileSystem.currentProfile))
        print("  Available profiles:")
        local profiles = RARELOAD.AntiStuck.ProfileSystem.GetAvailableProfiles()
        for i, name in ipairs(profiles) do
            print("    " .. i .. ". " .. name)
        end
    else
        print("[RARELOAD] Error: Profile system not available!")
    end
end)
