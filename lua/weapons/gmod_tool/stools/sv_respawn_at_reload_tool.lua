local RARELOAD  = {}
TOOL            = TOOL or {}
TOOL.Category   = "Respawn at Reload"
TOOL.Name       = "Respawn at Reload Config Tool"
TOOL.Command    = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.sv_respawn_at_reload_tool.name", "Respawn at Reload Configuration Panel")
    language.Add("tool.sv_respawn_at_reload_tool.desc", "Configuration Panel For Respawn At Reload Addon.")
    language.Add("tool.sv_respawn_at_reload_tool.0", "By Noahbds")

    local fontParams = { font = "Arial", size = 30, weight = 1000, antialias = true, additive = false }

    surface.CreateFont("CTNV", fontParams)
    surface.CreateFont("CTNV2", fontParams)
end


-- Function to load addon state from file
local function loadAddonState()
    local addonStateFilePath = "respawn_at_reload/addon_state.json"
    local defaultSettings = {
        addonEnabled = true,
        spawnModeEnabled = true,
        autoSaveEnabled = false,
        printMessageEnabled = true,
        retainInventory = false
    }

    if file.Exists(addonStateFilePath, "DATA") then
        local addonStateData = file.Read(addonStateFilePath, "DATA")
        local addonStateLines = string.Explode("\n", addonStateData)

        for key, defaultValue in pairs(defaultSettings) do
            local line = table.remove(addonStateLines, 1)
            RARELOAD.settings[key] = line and line:lower() == "true" or defaultValue
        end
    else
        local addonStateData = ""
        for _, defaultValue in pairs(defaultSettings) do
            addonStateData = addonStateData .. tostring(defaultValue) .. "\n"
        end

        file.Write(addonStateFilePath, addonStateData)
        RARELOAD.settings = defaultSettings
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
    local success, err = pcall(loadAddonState)
    if not success then
        ErrorNoHalt("Failed to load addon state: " .. err)
        return
    end

    createButton(panel, "Toggle Respawn at Reload", "toggle_respawn_at_reload",
        "Enable or disable automatic respawn at reload", RARELOAD.settings.addonEnabled)

    createButton(panel, "Toggle Move Type", "toggle_spawn_mode",
        "Switch between different spawn modes", RARELOAD.settings.spawnModeEnabled)

    createButton(panel, "Toggle Auto Save", "toggle_auto_save",
        "Enable or Disable Auto Saving Position", RARELOAD.settings.autoSaveEnabled)

    createButton(panel, "Toggle Print Messages", "toggle_print_message",
        "Enable or Disable Monitoring Messages in Console", RARELOAD.settings.printMessageEnabled)

    createButton(panel, "Toggle Retain Inventory", "toggle_retain_inventory",
        "Enable or disable retaining inventory", RARELOAD.settings.retainInventory)

    local savePositionButton = vgui.Create("DButton", panel)
    savePositionButton:SetText("Save Position")
    savePositionButton:SetTextColor(Color(0, 0, 0))
    savePositionButton:Dock(TOP)
    savePositionButton:DockMargin(30, 10, 30, 0)
    savePositionButton:SetSize(250, 30)
    savePositionButton.DoClick = function()
        RunConsoleCommand("save_position")
    end
end

-- function for the tool screen
function TOOL:DrawToolScreen(width, height)
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, width, height)

    surface.SetFont("CTNV")
    local textWidth, textHeight = surface.GetTextSize("CTNV")
    surface.SetFont("CTNV2")
    local text2Width, text2Height = surface.GetTextSize("By Noahbds")

    draw.SimpleText("Respawn At Reload", "CTNV", width / 2, 100, Color(224, 224, 224, 255), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    draw.SimpleText("By Noahbds", "CTNV2", width / 2, 128 + (textHeight + text2Height) / 2 - 4, Color(224, 224, 224, 255),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
