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


    -------------------------------------------------------------------------]
    ---------------------------Toolgun Saved Npcs And Entities Information---]
    -------------------------------------------------------------------------]


    panel:Button("Open Entity Viewer", "entity_viewer_open")

    if CLIENT then
        local function OpenEntityViewer()
            local frame = vgui.Create("DFrame")
            frame:SetSize(800, 600)
            frame:SetTitle("Entity Viewer - " .. game.GetMap())
            frame:Center()
            frame:MakePopup()
            frame:SetBackgroundBlur(true)

            -- Search bar
            ---@class search
            ---@diagnostic disable-next-line: assign-type-mismatch
            local search = vgui.Create("DTextEntry", frame)
            search:Dock(TOP)
            search:DockMargin(5, 5, 5, 5)
            search:SetPlaceholderText("Search by SteamID or entity name...")

            local scrollPanel = vgui.Create("DScrollPanel", frame)
            scrollPanel:Dock(FILL)

            local mapName = game.GetMap()
            local filePath = "rareload/player_positions_" .. mapName .. ".json"

            if not file.Exists(filePath, "DATA") then
                local errorLabel = vgui.Create("DLabel", frame)
                errorLabel:SetText("No saved data found for map: " .. mapName)
                errorLabel:SetTextColor(Color(255, 100, 100))
                errorLabel:Dock(TOP)
                errorLabel:DockMargin(10, 10, 10, 10)
                return
            end

            local jsonData = file.Read(filePath, "DATA")
            local success, data = pcall(util.JSONToTable, jsonData)

            if not success or not data then
                local errorLabel = vgui.Create("DLabel", frame)
                errorLabel:SetText("Error: Invalid data format")
                errorLabel:SetTextColor(Color(255, 100, 100))
                errorLabel:Dock(TOP)
                errorLabel:DockMargin(10, 10, 10, 10)
                return
            end

            for steamID, entities in pairs(data) do
                local playerPanel = vgui.Create("DCollapsibleCategory", scrollPanel)
                playerPanel:Dock(TOP)
                playerPanel:DockMargin(5, 5, 5, 0)
                playerPanel:SetLabel("Player: " .. steamID)
                playerPanel:SetExpanded(false)

                local entityList = vgui.Create("DPanelList", playerPanel)
                entityList:Dock(FILL)
                entityList:SetSpacing(5)
                entityList:EnableVerticalScrollbar()

                for _, entityData in pairs(entities) do
                    ---@class DPanelList
                    local entityPanel = vgui.Create("DPanel")
                    entityPanel:SetTall(80)
                    entityList:AddItem(entityPanel)

                    entityPanel.Paint = function(self, w, h)
                        draw.RoundedBox(6, 0, 0, w, h, Color(45, 45, 48))
                        draw.RoundedBox(6, 1, 1, w - 2, h - 2, Color(60, 60, 65))
                    end

                    -- Entity Icon
                    local icon = vgui.Create("DModelPanel", entityPanel)
                    icon:SetSize(70, 70)
                    icon:SetPos(5, 5)
                    if entityData.model then
                        icon:SetModel(entityData.model)
                    end

                    -- Info Panel
                    ---@class info
                    ---@diagnostic disable-next-line: assign-type-mismatch
                    local info = vgui.Create("DPanel", entityPanel)
                    info:SetPos(85, 5)
                    info:SetSize(entityPanel:GetWide() - 90, 70)
                    info.Paint = function() end

                    -- Entity Name and Class
                    local nameLabel = vgui.Create("DLabel", info)
                    nameLabel:SetText("Name: " .. (entityData.name or "Unknown"))
                    nameLabel:SetPos(0, 0)
                    nameLabel:SetTextColor(Color(255, 255, 255))

                    local classLabel = vgui.Create("DLabel", info)
                    classLabel:SetText("Class: " .. (entityData.class or "Unknown"))
                    classLabel:SetPos(0, 20)
                    classLabel:SetTextColor(Color(200, 200, 200))

                    -- Position with copy button
                    local posText = string.format("Pos: %.1f, %.1f, %.1f",
                        entityData.pos.x or 0,
                        entityData.pos.y or 0,
                        entityData.pos.z or 0)

                    local posLabel = vgui.Create("DLabel", info)
                    posLabel:SetText(posText)
                    posLabel:SetPos(0, 40)
                    posLabel:SetTextColor(Color(200, 200, 200))

                    local copyBtn = vgui.Create("DButton", info)
                    copyBtn:SetSize(50, 20)
                    copyBtn:SetPos(info:GetWide() - 55, 40)
                    copyBtn:SetText("Copy")
                    copyBtn.DoClick = function()
                        SetClipboardText(string.format("Vector(%.1f, %.1f, %.1f)",
                            entityData.pos.x or 0,
                            entityData.pos.y or 0,
                            entityData.pos.z or 0))
                    end
                end
            end

            -- Update search filter
            search.OnChange = function(self)
                local searchText = string.lower(self:GetValue())
                for _, panel in pairs(scrollPanel:GetChildren()) do
                    if panel.GetLabel then
                        local visible = string.find(string.lower(panel:GetLabel()), searchText, 1, true)
                        panel:SetVisible(visible)
                    end
                end
                scrollPanel:InvalidateLayout()
            end
        end

        concommand.Add("entity_viewer_open", OpenEntityViewer)
    end

    --------------------------------------------------------------------]
    ---------------End of Toolgun Saved Npcs And Entities Information---]
    --------------------------------------------------------------------]
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
