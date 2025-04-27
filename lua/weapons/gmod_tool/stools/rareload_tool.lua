---@class RARELOAD
local RARELOAD              = RARELOAD or {}
RARELOAD.settings           = RARELOAD.settings or {}
RARELOAD.playerPositions    = RARELOAD.playerPositions or {}
RARELOAD.serverLastSaveTime = 0

UI                          = include("rareload/rareload_ui.lua")
RareloadUI                  = include("rareload/rareload_ui.lua")


---@class TOOL
local TOOL      = TOOL or {}
TOOL.Category   = "Rareload"
TOOL.Name       = "Rareload Config Tool"
TOOL.Command    = nil
TOOL.ConfigName = ""

if SERVER then
    AddCSLuaFile("rareload/rareload_ui.lua")
    AddCSLuaFile("rareload/rareload_toolscreen.lua")
end


if CLIENT then
    UI.RegisterFonts()
    UI.RegisterLanguage()
    net.Receive("RareloadSyncAutoSaveTime", function()
        RARELOAD.serverLastSaveTime = net.ReadFloat()
    end)
end

if CLIENT then
    net.Receive("RareloadSettingsSync", function()
        local json = net.ReadString()
        local settings = util.JSONToTable(json)
        if settings then
            RARELOAD.settings = settings
            -- Optionally, force all open panels to update
            if IsValid(RareloadUI.LastPanel) then
                RareloadUI.LastPanel:InvalidateChildren(true)
            end
        end
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

function TOOL.BuildCPanel(panel)
    local success, err = pcall(loadAddonSettings)
    if not success then
        ErrorNoHalt("Failed to load addon settings: " .. (err or "unknown error"))

        ---@diagnostic disable-next-line: param-type-mismatch
        local errorLabel = vgui.Create("DLabel", panel)
        errorLabel:SetText("Error loading settings! Please check console.")
        errorLabel:SetTextColor(RareloadUI.COLORS.DISABLED)
        errorLabel:Dock(TOP)
        errorLabel:DockMargin(10, 10, 10, 10)
        errorLabel:SetWrap(true)
        errorLabel:SetTall(40)

        return
    end

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    RareloadUI.CreateButton(panel, "Toggle Rareload", "rareload_rareload",
        "Enable or disable Rareload", "addonEnabled")

    RareloadUI.CreateButton(panel, "Toggle Move Type", "rareload_spawn_mode",
        "Switch between different spawn modes", "spawnModeEnabled")

    RareloadUI.CreateButton(panel, "Toggle Auto Save", "rareload_auto_save",
        "Enable or disable auto saving position", "autoSaveEnabled")

    RareloadUI.CreateButton(panel, "Toggle Keep Inventory", "rareload_retain_inventory",
        "Enable or disable retaining inventory", "retainInventory")

    RareloadUI.CreateButton(panel, "Toggle Keep Health and Armor", "rareload_retain_health_armor",
        "Enable or disable retaining health and armor", "retainHealthArmor")

    RareloadUI.CreateButton(panel, "Toggle Keep Ammo", "rareload_retain_ammo",
        "Enable or disable retaining ammo", "retainAmmo")

    -- RareloadUI.CreateButton(panel, "Toggle Keep Vehicles", "rareload_retain_vehicles",
    --      "Enable or disable retaining vehicles", "retainVehicle")

    -- RareloadUI.CreateButton(panel, "Toggle Keep Vehicle State", "rareload_retain_vehicle_state",
    --     "Enable or disable retaining vehicle state", "retainVehicleState")

    RareloadUI.CreateButton(panel, "Toggle Keep Map Entities", "rareload_retain_map_entities",
        "Enable or disable retaining map entities", "retainMapEntities")

    RareloadUI.CreateButton(panel, "Toggle Keep Map NPCs", "rareload_retain_map_npcs",
        "Enable or disable retaining map NPCs", "retainMapNPCs")

    RareloadUI.CreateButton(panel, "Toggle No Custom Death at spawn", "rareload_nocustomrespawnatdeath",
        "Enable or disable custom respawn at death", "nocustomrespawnatdeath")

    RareloadUI.CreateButton(panel, "Toggle Debug", "rareload_debug",
        "Enable or disable debug mode", "debugEnabled")

    RareloadUI.CreateButton(panel, "Toggle Global Inventory", "rareload_retain_global_inventory",
        "Enable or disable global inventory", "retainGlobalInventory")

    RareloadUI.CreateActionButton(
        panel,
        "Save Position",
        "save_position",
        "Manually save your current position now"
    )


    RareloadUI.CreateSlider(
        panel,
        "Auto Save Interval",
        "Number of seconds between each automatic position save",
        "set_auto_save_interval",
        1, 60, 0,
        RARELOAD.settings.autoSaveInterval or 2,
        "s"
    )

    RareloadUI.CreateSlider(
        panel,
        "Max Distance",
        "Maximum distance (in units) at which saved entities will be restored",
        "set_max_distance",
        1, 1000, 0,
        RARELOAD.settings.maxDistance or 50,
        "u"
    )

    RareloadUI.CreateSlider(
        panel,
        "Angle Tolerance",
        "Angle tolerance (in degrees) for entity restoration",
        "set_angle_tolerance",
        1, 360, 1,
        RARELOAD.settings.angleTolerance or 100.0,
        "°"
    )

    RareloadUI.CreateSeparator(panel)

    ---@diagnostic disable-next-line: undefined-field
    panel:Button("Open Entity Viewer", "entity_viewer_open")
end

local screenTool = include("rareload/rareload_toolscreen.lua")

function TOOL:DrawToolScreen()
    screenTool:Draw(256, 256, RARELOAD, loadAddonSettings)
    screenTool.EndDraw()
end
