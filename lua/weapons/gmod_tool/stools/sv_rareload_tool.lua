---@diagnostic disable: undefined-field, param-type-mismatch


local RARELOAD  = {}

TOOL            = TOOL or {}
TOOL.Category   = "Rareload"
TOOL.Name       = "Rareload Config Tool"
TOOL.Command    = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.sv_rareload_tool.name", "Rareload Configuration Panel")
    language.Add("tool.sv_rareload_tool.desc", "Configuration Panel For Rareload Addon.")
    language.Add("tool.sv_rareload_tool.0", "By Noahbds")

    local fontParams = { font = "Arial", size = 20.9, weight = 2000, antialias = true, additive = false }
    local fontParams2 = { font = "Arial", size = 31, weight = 2000, antialias = true, additive = false }

    surface.CreateFont("CTNV", fontParams)
    surface.CreateFont("CTNV2", fontParams2)
end

-- Used here beacuse of the way the toolgun works (The button color use addon_state). Wanted to do a shared, didn't worked (I'm bad at lua)
local function loadAddonStatefortool()
    local addonStateFilePath = "rareload/addon_state.json"
    if file.Exists(addonStateFilePath, "DATA") then
        local json = file.Read(addonStateFilePath, "DATA")
        RARELOAD.settings = util.JSONToTable(json)
    end
end

local COLOR_ENABLED = Color(50, 150, 255)
local COLOR_DISABLED = Color(255, 50, 50)

local function createButton(parent, text, command, tooltip, isEnabled)
    local button = vgui.Create("DButton", parent)
    button:SetText(text)
    button:Dock(TOP)
    button:DockMargin(30, 10, 30, 0)
    button:SetSize(250, 30)

    local color = isEnabled and COLOR_ENABLED or COLOR_DISABLED
    button:SetTextColor(color)
    button:SetColor(color)

    button.DoClick = function()
        RunConsoleCommand(command)
        local currentColor = button:GetColor()
        local newColor = currentColor == COLOR_ENABLED and COLOR_DISABLED or COLOR_ENABLED
        button:SetColor(newColor)
        button:SetTextColor(newColor)
    end

    if tooltip then
        button:SetTooltip(tooltip)
    end

    return button
end

function TOOL.BuildCPanel(panel)
    local success, err = pcall(loadAddonStatefortool)
    if not success then
        ErrorNoHalt("Failed to load addon state: " .. err)
        return
    end

    createButton(panel, "Toggle Rareload", "toggle_rareload",
        "Enable or disable Rareload", RARELOAD.settings.addonEnabled)

    createButton(panel, "Toggle Move Type", "toggle_spawn_mode",
        "Switch between different spawn modes", RARELOAD.settings.spawnModeEnabled)

    createButton(panel, "Toggle Auto Save", "toggle_auto_save",
        "Enable or Disable Auto Saving Position", RARELOAD.settings.autoSaveEnabled)

    createButton(panel, "Toggle Keep Inventory", "toggle_retain_inventory",
        "Enable or disable retaining inventory", RARELOAD.settings.retainInventory)

    ---[[ Beta [NOT TESTED] ]]---

    createButton(panel, "Toggle Keep Health and Armor", "toggle_retain_health_armor",
        "Enable or disable retaining health and armor", RARELOAD.settings.retainHealthArmor)

    createButton(panel, "Toggle Keep Ammo", "toggle_retain_ammo",
        "Enable or disable retaining ammo", RARELOAD.settings.retainAmmo)

    createButton(panel, "Toggle Keep Vehicle State", "toggle_retain_vehicle_state",
        "Enable or disable retaining vehicle state", RARELOAD.settings.retainVehicleState)

    createButton(panel, "Toggle Keep Map Entities", "toggle_retain_map_entities",
        "Enable or disable retaining map entities", RARELOAD.settings.retainMapEntities)

    createButton(panel, "Toggle Keep Map NPCs", "toggle_retain_map_npcs",
        "Enable or disable retaining map NPCs", RARELOAD.settings.retainMapNPCs)


    ---[[End of Beta [NOT TESTED] ]]---

    createButton(panel, "Toggle No Custom Respawn At Death", "toggle_nocustomrespawnatdeath",
        "Enable or disable No Custom Respawn At Death", RARELOAD.settings.nocustomrespawnatdeath)

    createButton(panel, "Toggle Debug", "toggle_debug",
        "Enable or disable Debug", RARELOAD.settings.debugEnabled)

    ---@class DButton
    local savePositionButton = vgui.Create("DButton", panel)
    savePositionButton:SetText("Save Position")
    savePositionButton:SetTextColor(Color(0, 0, 0))
    savePositionButton:Dock(TOP)
    savePositionButton:DockMargin(30, 10, 30, 0)
    savePositionButton:SetSize(250, 30)
    savePositionButton.DoClick = function()
        RunConsoleCommand("save_position")
    end

    ------------------------------------------------------------------------]
    ---------------------------------------------Auto Save Slider Options---]
    ------------------------------------------------------------------------]

    ---@class DNumSlider
    local autoSaveSlider = vgui.Create("DNumSlider", panel)
    autoSaveSlider:SetText("Auto Save Interval")
    autoSaveSlider.Label:SetTextColor(Color(255, 255, 255)) -- Set text color to white
    autoSaveSlider:SetMin(1)
    autoSaveSlider:SetMax(60)
    autoSaveSlider:SetDecimals(0)
    autoSaveSlider:SetValue(RARELOAD.settings.autoSaveInterval or 2)
    autoSaveSlider:Dock(TOP)
    autoSaveSlider:DockMargin(30, 10, 30, 0)
    autoSaveSlider.OnValueChanged = function(self, value)
        RunConsoleCommand("set_auto_save_interval", value)
    end

    local maxDistanceSlider = vgui.Create("DNumSlider", panel)
    maxDistanceSlider:SetText("Max Distance")
    maxDistanceSlider.Label:SetTextColor(Color(255, 255, 255)) -- Set text color to white
    maxDistanceSlider:SetMin(1)
    maxDistanceSlider:SetMax(1000)
    maxDistanceSlider:SetDecimals(0)
    maxDistanceSlider:SetValue(RARELOAD.settings.maxDistance or 50)
    maxDistanceSlider:Dock(TOP)
    maxDistanceSlider:DockMargin(30, 10, 30, 0)
    maxDistanceSlider.OnValueChanged = function(self, value)
        RunConsoleCommand("set_max_distance", value)
    end

    local angleToleranceSlider = vgui.Create("DNumSlider", panel)
    angleToleranceSlider:SetText("Angle Tolerance")
    angleToleranceSlider.Label:SetTextColor(Color(255, 255, 255)) -- Set text color to white
    angleToleranceSlider:SetMin(1)
    angleToleranceSlider:SetMax(360)
    angleToleranceSlider:SetDecimals(1)
    angleToleranceSlider:SetValue(RARELOAD.settings.angleTolerance or 100.0)
    angleToleranceSlider:Dock(TOP)
    angleToleranceSlider:DockMargin(30, 10, 30, 0)
    angleToleranceSlider.OnValueChanged = function(self, value)
        RunConsoleCommand("set_angle_tolerance", value)
    end


    ------------------------------------------------------------------------]
    --------------------------------------End of Auto Save Slider Options---]
    ------------------------------------------------------------------------]

    -------------------------------------------------------------------------------------------]
    ---------------------------------------------Toolgun Saved Npcs And Entities Information---]
    -------------------------------------------------------------------------------------------]


    -- Display saved entities, NPCs, and vehicles
    local function addListSection(title, items)
        local label = vgui.Create("DLabel", panel)
        label:SetText(title)
        label:SetFont("DermaDefaultBold")
        label:Dock(TOP)
        label:DockMargin(30, 10, 30, 0)
        label:SetTextColor(Color(255, 255, 255))

        for _, item in ipairs(items) do
            local itemLabel = vgui.Create("DLabel", panel)
            itemLabel:SetText(item)
            itemLabel:Dock(TOP)
            itemLabel:DockMargin(40, 5, 30, 0)
            itemLabel:SetTextColor(Color(255, 255, 255))
        end
    end

    local mapName = game.GetMap()
    local savedData = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][LocalPlayer():SteamID()]

    if savedData then
        if savedData.entities then
            local entityList = {}
            for _, entity in ipairs(savedData.entities) do
                table.insert(entityList, entity.class .. " at " .. tostring(entity.pos))
            end
            addListSection("Saved Entities:", entityList)
        end

        if savedData.npcs then
            local npcList = {}
            for _, npc in ipairs(savedData.npcs) do
                table.insert(npcList, npc.class .. " at " .. tostring(npc.pos))
            end
            addListSection("Saved NPCs:", npcList)
        end

        if savedData.vehicle then
            local vehicleList = { savedData.vehicle.class .. " at " .. tostring(savedData.vehicle.pos) }
            addListSection("Saved Vehicle:", vehicleList)
        end
    else
        local noDataLabel = vgui.Create("DLabel", panel)
        noDataLabel:SetText("No saved data available.")
        noDataLabel:Dock(TOP)
        noDataLabel:DockMargin(30, 10, 30, 0)
        noDataLabel:SetTextColor(Color(255, 255, 255))
    end


    -------------------------------------------------------------------------------------------]
    --------------------------------------End of Toolgun Saved Npcs And Entities Information---]
    -------------------------------------------------------------------------------------------]

    ------------------------------------------------------------------------]
    --------------------------------------Blacklist Modification Section----]
    ------------------------------------------------------------------------]

    local function updateBlacklistDisplay()
        if BlacklistPanel then
            BlacklistPanel:Remove()
        end

        BlacklistPanel = vgui.Create("DPanel", panel)
        BlacklistPanel:Dock(TOP)
        BlacklistPanel:DockMargin(30, 10, 30, 0)

        local blacklistLabel = vgui.Create("DLabel", BlacklistPanel)
        blacklistLabel:SetText("Blacklist Classes:")
        blacklistLabel:SetFont("DermaDefaultBold")
        blacklistLabel:Dock(TOP)
        blacklistLabel:DockMargin(0, 0, 0, 5)
        blacklistLabel:SetTextColor(Color(255, 255, 255))

        for class, enabled in pairs(RARELOAD.settings.excludeClasses) do
            local classPanel = vgui.Create("DPanel", BlacklistPanel)
            classPanel:Dock(TOP)
            classPanel:DockMargin(0, 0, 0, 5)
            classPanel:SetTall(20)

            local classLabel = vgui.Create("DLabel", classPanel)
            classLabel:SetText(class)
            classLabel:Dock(LEFT)
            classLabel:SetWide(200)
            classLabel:SetTextColor(Color(255, 255, 255))

            ---@class DCheckBoxLabel
            local enableCheckbox = vgui.Create("DCheckBoxLabel", classPanel)
            enableCheckbox:SetText("Enabled")
            enableCheckbox:SetValue(enabled and 1 or 0)
            enableCheckbox:Dock(LEFT)
            enableCheckbox:DockMargin(10, 0, 0, 0)
            enableCheckbox.OnChange = function(self, value)
                RARELOAD.settings.excludeClasses[class] = value == 1
            end

            local removeButton = vgui.Create("DButton", classPanel)
            removeButton:SetText("Remove")
            removeButton:Dock(RIGHT)
            removeButton.DoClick = function()
                RARELOAD.settings.excludeClasses[class] = nil
                updateBlacklistDisplay()
            end
        end
    end

    local addClassPanel = vgui.Create("DPanel", panel)
    addClassPanel:Dock(TOP)
    addClassPanel:DockMargin(30, 10, 30, 0)
    addClassPanel:SetTall(30)

    local addClassTextEntry = vgui.Create("DTextEntry", addClassPanel)
    addClassTextEntry:Dock(LEFT)
    addClassTextEntry:SetWide(200)
    addClassTextEntry:SetPlaceholderText("Enter class to blacklist")

    local addClassButton = vgui.Create("DButton", addClassPanel)
    addClassButton:SetText("Add")
    addClassButton:Dock(RIGHT)
    addClassButton.DoClick = function()
        local class = addClassTextEntry:GetValue()
        if class ~= "" then
            RARELOAD.settings.excludeClasses[class] = true
            addClassTextEntry:SetValue("")
            updateBlacklistDisplay()
        end
    end

    updateBlacklistDisplay()
end

------------------------------------------------------------------------]
--------------------------------End of Blacklist Modification Section---]
------------------------------------------------------------------------]

------------------------------------------------------------------------]
---------------------------------------------Toolgun Screen Options-----]
------------------------------------------------------------------------]

function TOOL:DrawToolScreen(width, height)
    local success, err = pcall(loadAddonStatefortool)
    if not success then
        ErrorNoHalt("Failed to load addon state: " .. err)
        return
    end

    local backgroundColor
    local autoSaveStatusColor

    if RARELOAD.settings.autoSaveEnabled then
        backgroundColor = Color(0, 255, 0)
        autoSaveStatusColor = Color(0, 0, 0)
    else
        backgroundColor = Color(255, 100, 100)
        autoSaveStatusColor = Color(255, 255, 255)
    end

    surface.SetDrawColor(backgroundColor)
    surface.DrawRect(0, 0, width, height)

    surface.SetFont("CTNV")
    local textWidth, textHeight = surface.GetTextSize("Rareload")
    draw.SimpleText("Rareload", "CTNV2", width / 2, 40, autoSaveStatusColor, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    local startY = 85
    local spacing = 30

    local settings = {
        { name = "Rareload",             enabled = RARELOAD.settings.addonEnabled },
        { name = "Move Type",            enabled = RARELOAD.settings.spawnModeEnabled },
        { name = "Auto Save",            enabled = RARELOAD.settings.autoSaveEnabled },
        { name = "Keep Inventory",       enabled = RARELOAD.settings.retainInventory },
        { name = "No Rareload At Death", enabled = RARELOAD.settings.nocustomrespawnatdeath },
        { name = "Debug",                enabled = RARELOAD.settings.debugEnabled }
    }

    for i, setting in ipairs(settings) do
        local statusText = setting.enabled and "Toggled" or "Toggle"
        local color = setting.enabled and autoSaveStatusColor or
            Color(255, 0, 0)
        draw.SimpleText(statusText .. " " .. setting.name, "CTNV", width / 2, startY + (i - 1) * spacing, color,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end
