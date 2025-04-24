---@class RARELOAD
local RARELOAD              = RARELOAD or {}
RARELOAD.settings           = RARELOAD.settings or {}
RARELOAD.playerPositions    = RARELOAD.playerPositions or {}
RARELOAD.serverLastSaveTime = 0

---@class TOOL
local TOOL                  = TOOL or {}
TOOL.Category               = "Rareload"
TOOL.Name                   = "Rareload Config Tool"
TOOL.Command                = nil
TOOL.ConfigName             = ""

if SERVER then
    AddCSLuaFile("rareload/rareload_ui.lua")
    AddCSLuaFile("rareload/rareload_toolscreen.lua")
end

local UI = include("rareload/rareload_ui.lua")
local ToolScreen = include("rareload/rareload_toolscreen.lua")

if CLIENT then
    UI.RegisterFonts()
    UI.RegisterLanguage()
    net.Receive("RareloadSyncAutoSaveTime", function()
        RARELOAD.serverLastSaveTime = net.ReadFloat()
    end)
end

local function loadAddonSettings()
    local addonStateFilePath = "rareload/addon_state.json"

    if not file.Exists(addonStateFilePath, "DATA") then
        return false, "Settings file does not exist"
    end

    local json = file.Read(addonStateFilePath, "DATA")
    if not json or json == "" then
        return false, "Settings file is empty"
    end

    local settings = util.JSONToTable(json)
    if not settings then
        return false, "Failed to parse settings JSON"
    end

    RARELOAD.settings = settings
    return true, nil
end

local createToggleButton = UI.CreateToggleButton
local createSettingSlider = UI.CreateSettingSlider
local createSeparator = UI.CreateSeparator
local createSavePositionButton = UI.CreateSavePositionButton

function TOOL.BuildCPanel(panel)
    local success, err = pcall(loadAddonSettings)
    if not success then
        ErrorNoHalt("Failed to load addon settings: " .. (err or "unknown error"))

        ---@diagnostic disable-next-line: param-type-mismatch
        local errorLabel = vgui.Create("DLabel", panel)
        errorLabel:SetText("Error loading settings! Please check console.")
        errorLabel:SetTextColor(UI.COLORS.DISABLED)
        errorLabel:Dock(TOP)
        errorLabel:DockMargin(10, 10, 10, 10)
        errorLabel:SetWrap(true)
        errorLabel:SetTall(40)

        return
    end

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    createToggleButton(panel, "Toggle Rareload", "rareload_rareload",
        "Enable or disable Rareload", RARELOAD.settings.addonEnabled)

    createToggleButton(panel, "Toggle Move Type", "rareload_spawn_mode",
        "Switch between different spawn modes", RARELOAD.settings.spawnModeEnabled)

    createToggleButton(panel, "Toggle Auto Save", "rareload_auto_save",
        "Enable or disable auto saving position", RARELOAD.settings.autoSaveEnabled)

    createToggleButton(panel, "Toggle Keep Inventory", "rareload_retain_inventory",
        "Enable or disable retaining inventory", RARELOAD.settings.retainInventory)

    createToggleButton(panel, "Toggle Keep Health and Armor", "rareload_retain_health_armor",
        "Enable or disable retaining health and armor", RARELOAD.settings.retainHealthArmor)

    createToggleButton(panel, "Toggle Keep Ammo", "rareload_retain_ammo",
        "Enable or disable retaining ammo", RARELOAD.settings.retainAmmo)

    createToggleButton(panel, "Toggle Keep Vehicles", "rareload_retain_vehicles",
        "Enable or disable retaining vehicles", RARELOAD.settings.retainVehicle)

    createToggleButton(panel, "Toggle Keep Vehicle State", "rareload_retain_vehicle_state",
        "Enable or disable retaining vehicle state", RARELOAD.settings.retainVehicleState)

    createToggleButton(panel, "Toggle Keep Map Entities", "rareload_retain_map_entities",
        "Enable or disable retaining map entities", RARELOAD.settings.retainMapEntities)

    createToggleButton(panel, "Toggle Keep Map NPCs", "rareload_retain_map_npcs",
        "Enable or disable retaining map NPCs", RARELOAD.settings.retainMapNPCs)

    createToggleButton(panel, "Toggle No Custom Respawn At Death", "rareload_nocustomrespawnatdeath",
        "Enable or disable custom respawn at death", RARELOAD.settings.nocustomrespawnatdeath)

    createToggleButton(panel, "Toggle Debug", "rareload_debug",
        "Enable or disable debug mode", RARELOAD.settings.debugEnabled)

    createToggleButton(panel, "Toggle Global Inventory", "rareload_retain_global_inventory",
        "Enable or disable global inventory", RARELOAD.settings.retainGlobalInventory)

    createSavePositionButton(panel)

    createSettingSlider(
        panel,
        "Auto Save Interval",
        "set_auto_save_interval",
        1, 60, 0,
        RARELOAD.settings.autoSaveInterval or 2,
        "Number of seconds between each automatic position save",
        "s"
    )

    createSettingSlider(
        panel,
        "Max Distance",
        "set_max_distance",
        1, 1000, 0,
        RARELOAD.settings.maxDistance or 50,
        "Maximum distance (in units) at which saved entities will be restored",
        " u"
    )

    createSettingSlider(
        panel,
        "Angle Tolerance",
        "set_angle_tolerance",
        1, 360, 1,
        RARELOAD.settings.angleTolerance or 100.0,
        "Angle tolerance (in degrees) for entity restoration",
        "°"
    )

    createSeparator(panel)

    ---@diagnostic disable-next-line: undefined-field
    panel:Button("Open Entity Viewer", "entity_viewer_open")
end

function TOOL:DrawToolScreen(width, height)
    ToolScreen.Draw(self, width, height, RARELOAD, loadAddonSettings)
end
