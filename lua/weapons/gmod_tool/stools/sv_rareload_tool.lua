---@diagnostic disable: undefined-field, param-type-mismatch

-- Include the blacklist file
include("autorun/server/sv_rareload_backlist.lua")


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
    SaveBlacklist()
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


    RARELOAD.playerPositions = RARELOAD.playerPositions or {}


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

    local function createProgressBar(parent, value, maxValue, x, y, w, h)
        local bar = vgui.Create("DPanel", parent)
        bar:SetPos(x, y)
        bar:SetSize(w, h)

        -- Stylish modern with rounded corners and softer colors
        bar.Paint = function(self, w, h)
            -- Background of the bar
            draw.RoundedBox(4, 0, 0, w, h, Color(30, 30, 30, 200))

            -- Progress bar
            local progress = math.Clamp(value / maxValue, 0, 1)
            local barColor = Color(70, 180, 70, 255) -- Softer green color
            draw.RoundedBox(4, 1, 1, (w - 2) * progress, h - 2, barColor)
        end

        return bar
    end

    local function createEntityPanel(parent, entityData, bgColor)
        local itemPanel = vgui.Create("DPanel", parent)
        itemPanel:Dock(TOP)
        itemPanel:SetTall(80) -- Increased height for better readability
        itemPanel:DockMargin(5, 5, 5, 5)

        -- Stylish background with a subtle border
        itemPanel.Paint = function(self, w, h)
            -- Main background
            draw.RoundedBox(8, 0, 0, w, h, Color(40, 40, 45, 250))
            -- Subtle border
            surface.SetDrawColor(Color(70, 70, 75, 100))
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        -- Icon background
        local iconBg = vgui.Create("DPanel", itemPanel)
        iconBg:SetPos(10, 10)
        iconBg:SetSize(48, 48)
        iconBg.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(60, 60, 65, 255))
        end

        -- Icon Type (based on entity type)
        local iconType = "icon16/brick.png"
        if entityData.class:find("npc") then
            iconType = "icon16/user.png"
        elseif entityData.class:find("weapon") then
            iconType = "icon16/bomb.png"
        end

        local icon = vgui.Create("DImage", iconBg)
        icon:SetSize(32, 32)
        icon:SetPos(8, 8)
        icon:SetImage(iconType)

        -- Entity name
        local nameLabel = vgui.Create("DLabel", itemPanel)
        nameLabel:SetPos(68, 10)
        nameLabel:SetText(entityData.class)
        nameLabel:SetFont("Trebuchet18")
        nameLabel:SetTextColor(Color(220, 220, 220))
        nameLabel:SetWide(300)
        nameLabel:SetWrap(true) -- Allow text to wrap

        -- Position label
        local posLabel = vgui.Create("DLabel", itemPanel)
        posLabel:SetPos(68, 30)
        posLabel:SetText(string.format("Position: %.0f, %.0f, %.0f",
            entityData.pos.x or 0,
            entityData.pos.y or 0,
            entityData.pos.z or 0))
        posLabel:SetTextColor(Color(180, 180, 180))
        posLabel:SetWide(300)
        posLabel:SetWrap(true) -- Allow text to wrap

        -- Health bar (if available)
        if entityData.health then
            local healthLabel = vgui.Create("DLabel", itemPanel)
            healthLabel:SetPos(68, 50)
            healthLabel:SetText("Health:")
            healthLabel:SetTextColor(Color(180, 180, 180))
            healthLabel:SizeToContents()

            createProgressBar(itemPanel, entityData.health, 100, 100, 50, 200, 14)
        end

        return itemPanel
    end

    local function createEntityCategory(parent, categoryTitle, entityList, color)
        local categoryPanel = vgui.Create("DPanel", parent)
        categoryPanel:Dock(TOP)
        categoryPanel:DockMargin(10, 10, 10, 0)

        -- Category header
        local headerLabel = vgui.Create("DLabel", categoryPanel)
        headerLabel:SetText(categoryTitle)
        headerLabel:SetFont("DermaLarge")
        headerLabel:SetTextColor(Color(255, 200, 0))
        headerLabel:Dock(TOP)
        headerLabel:DockMargin(5, 5, 5, 5)

        -- Loop through the entities or NPCs
        for _, entity in ipairs(entityList) do
            createEntityPanel(categoryPanel, entity, color)
        end
    end

    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"

    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")

        local success, savedData = pcall(util.JSONToTable, data)

        if not success or not savedData then
            print("JSON decode error:", savedData)
            local errorLabel = vgui.Create("DLabel", panel)
            errorLabel:SetText("Error reading save file.")
            errorLabel:Dock(TOP)
            errorLabel:DockMargin(30, 10, 30, 0)
            errorLabel:SetTextColor(Color(255, 100, 100))

            return
        end

        local plyID = LocalPlayer():SteamID()
        local mapData = savedData[mapName]

        if mapData and mapData[plyID] then
            local playerData = mapData[plyID]

            -- Create a scrollable panel for large data
            local scrollPanel = vgui.Create("DScrollPanel", panel)
            scrollPanel:Dock(FILL)
            local categoryList = vgui.Create("DPanelList", scrollPanel)
            categoryList:Dock(FILL)
            categoryList:SetSpacing(5)
            categoryList:SetPadding(5)

            -- Display saved entities
            if type(playerData.entities) == "table" then
                createEntityCategory(categoryList, "Saved Entities", playerData.entities, Color(70, 90, 120, 200))
            end

            -- Display saved NPCs
            if type(playerData.npcs) == "table" then
                createEntityCategory(categoryList, "Saved NPCs", playerData.npcs, Color(120, 70, 70, 200))
            end
        else
            print("No data found for map:", mapName, "and SteamID:", plyID)
            local noDataLabel = vgui.Create("DLabel", panel)
            noDataLabel:SetText("No saved data available for this player.")
            noDataLabel:Dock(TOP)
            noDataLabel:DockMargin(30, 10, 30, 0)
            noDataLabel:SetTextColor(Color(255, 255, 255))
        end
    else
        print("File not found at:", filePath)
        local noFileLabel = vgui.Create("DLabel", panel)
        noFileLabel:SetText("No saved data file found.")
        noFileLabel:Dock(TOP)
        noFileLabel:DockMargin(30, 10, 30, 0)
        noFileLabel:SetTextColor(Color(255, 255, 255))
    end


    -------------------------------------------------------------------------------------------]

    --------------------------------------End of Toolgun Saved Npcs And Entities Information---]

    -------------------------------------------------------------------------------------------]


    ------------------------------------------------------------------------]

    --------------------------------------Blacklist Modification Section----]

    ------------------------------------------------------------------------]


    local mapName = game.GetMap()

    local blacklistFilePath = "rareload/blacklist_" .. mapName .. ".json"


    local blacklist = {}


    -- Load the blacklist file

    if file.Exists(blacklistFilePath, "DATA") then
        local json = file.Read(blacklistFilePath, "DATA")

        local success, data = pcall(util.JSONToTable, json)

        if success and type(data) == "table" then
            blacklist = data
        end
    end


    -- Save the blacklist file

    local function saveBlacklist()
        file.Write(blacklistFilePath, util.TableToJSON(blacklist, true))
    end


    -- Create the blacklist section UI

    local blacklistPanel = vgui.Create("DPanel", panel)

    blacklistPanel:Dock(TOP)

    blacklistPanel:DockMargin(10, 10, 10, 0)

    blacklistPanel:SetTall(300)


    local headerLabel = vgui.Create("DLabel", blacklistPanel)

    headerLabel:SetText("Blacklist Configuration")

    headerLabel:SetFont("DermaLarge")

    headerLabel:SetTextColor(Color(255, 200, 0))

    headerLabel:Dock(TOP)

    headerLabel:DockMargin(5, 5, 5, 5)


    local scrollPanel = vgui.Create("DScrollPanel", blacklistPanel)

    scrollPanel:Dock(FILL)

    scrollPanel:DockMargin(5, 5, 5, 5)


    -- Function to refresh the blacklist items

    local function refreshBlacklist()
        scrollPanel:Clear()

        for class, isEnabled in pairs(blacklist) do
            local itemPanel = vgui.Create("DPanel", scrollPanel)

            itemPanel:Dock(TOP)

            itemPanel:DockMargin(5, 5, 5, 5)

            itemPanel:SetTall(30)


            local classLabel = vgui.Create("DLabel", itemPanel)

            classLabel:SetText(class)

            classLabel:Dock(LEFT)

            classLabel:DockMargin(5, 5, 5, 5)

            classLabel:SetTextColor(Color(255, 255, 255))

            classLabel:SizeToContents()


            ---@class DCheckBox

            local enableCheckbox = vgui.Create("DCheckBox", itemPanel)

            enableCheckbox:Dock(RIGHT)

            enableCheckbox:SetValue(isEnabled and 1 or 0)

            enableCheckbox.OnChange = function(_, value)
                blacklist[class] = value == true

                saveBlacklist()
            end


            local removeButton = vgui.Create("DButton", itemPanel)

            removeButton:Dock(RIGHT)

            removeButton:DockMargin(5, 0, 5, 0)

            removeButton:SetText("Remove")

            removeButton.DoClick = function()
                blacklist[class] = nil

                saveBlacklist()

                refreshBlacklist()
            end
        end
    end


    refreshBlacklist()


    -- Add a text entry and button to add new classes

    local addClassPanel = vgui.Create("DPanel", blacklistPanel)

    addClassPanel:Dock(BOTTOM)

    addClassPanel:DockMargin(5, 5, 5, 5)

    addClassPanel:SetTall(40)


    local classEntry = vgui.Create("DTextEntry", addClassPanel)

    classEntry:Dock(LEFT)

    classEntry:DockMargin(5, 5, 5, 5)

    classEntry:SetPlaceholderText("Enter class name...")


    local addButton = vgui.Create("DButton", addClassPanel)

    addButton:Dock(RIGHT)

    addButton:DockMargin(5, 5, 5, 5)

    addButton:SetText("Add")

    addButton.DoClick = function()
        local className = classEntry:GetValue()

        if className ~= "" and not blacklist[className] then
            blacklist[className] = true

            saveBlacklist()

            refreshBlacklist()
        end

        classEntry:SetText("")
    end


    ------------------------------------------------------------------------]

    --------------------------------End of Blacklist Modification Section---]

    ------------------------------------------------------------------------]
end

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
