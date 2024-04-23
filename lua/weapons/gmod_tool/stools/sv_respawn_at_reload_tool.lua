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
    local addonStateFilePath = "respawn_at_reload/addon_state.txt"
    RARELOAD.settings = {} -- Initialize settings table

    -- Check if the file exists
    if file.Exists(addonStateFilePath, "DATA") then
        local addonStateData = file.Read(addonStateFilePath, "DATA")
        local addonStateLines = string.Explode("\n", addonStateData)

        -- Assign addon settings from file data
        RARELOAD.settings.addonEnabled = addonStateLines[1] and addonStateLines[1]:lower() == "true"
        RARELOAD.settings.spawnModeEnabled = addonStateLines[2] and addonStateLines[2]:lower() == "true"
        RARELOAD.settings.autoSaveEnabled = addonStateLines[3] and addonStateLines[3]:lower() == "true"
        RARELOAD.settings.printMessageEnabled = addonStateLines[4] and addonStateLines[4]:lower() == "true"
    else
        -- If the file doesn't exist, create it with default values
        local addonStateData = "true\ntrue\nfalse\ntrue"
        file.Write(addonStateFilePath, addonStateData)

        -- Assign default settings
        RARELOAD.settings.addonEnabled = true
        RARELOAD.settings.spawnModeEnabled = true
        RARELOAD.settings.autoSaveEnabled = false
        RARELOAD.settings.printMessageEnabled = true
    end
end

function TOOL.BuildCPanel(panel)
    -- Function to create a styled button with dynamic color based on addon state
    local function CreateStyledButton(parent, text, command, tooltip, colorVar)
        local button = vgui.Create("DButton", parent)
        button:SetText(text)
        button:Dock(TOP)
        button:DockMargin(30, 10, 30, 0)
        button:SetSize(250, 30)

        -- Set initial button color based on the specified variable
        local color = colorVar and colorVar:lower() == "true" and Color(50, 150, 255) or Color(255, 50, 50)
        button:SetTextColor(color)
        button:SetFont("DermaDefaultBold")
        button:SetColor(color)

        button.DoClick = function()
            RunConsoleCommand(command)

            -- Toggle button color when clicked
            if button:GetColor() == Color(50, 150, 255) then
                button:SetColor(Color(255, 50, 50))
                button:SetTextColor(Color(255, 50, 50))
            else
                button:SetColor(Color(50, 150, 255))
                button:SetTextColor(Color(50, 150, 255))
            end
        end

        -- Add tooltip for additional information
        if tooltip then
            button:SetTooltip(tooltip)
        end

        return button
    end

    -- Read addon state from the file
    loadAddonState()

    -- Create a button to toggle respawn behavior with color based on addon state
    CreateStyledButton(panel, "Toggle Respawn at Reload", "toggle_respawn_at_reload",
        "Enable or disable automatic respawn at reload", tostring(RARELOAD.settings.addonEnabled))

    -- Create a button to toggle spawn mode with color based on addon state
    CreateStyledButton(panel, "Toggle Move Type", "toggle_spawn_mode",
        "Switch between different spawn modes", tostring(RARELOAD.settings.spawnModeEnabled))

    -- Create a button to toggle auto-save with color based on addon state
    CreateStyledButton(panel, "Toggle Auto Save", "toggle_auto_save",
        "Enable or Disable Auto Saving Position", tostring(RARELOAD.settings.autoSaveEnabled))

    -- Create a button to toggle print messages with color based on addon state
    CreateStyledButton(panel, "Toggle Print Messages", "toggle_print_message",
        "Enable or Disable Monitoring Messages in Console", tostring(RARELOAD.settings.printMessageEnabled))

    -- Create a button to save the current position
    local savePositionButton = vgui.Create("DButton", panel)
    savePositionButton:SetText("Save Position")
    savePositionButton:SetTextColor(Color(0, 0, 0)) -- Set the text color to white for visibility
    savePositionButton:Dock(TOP)
    savePositionButton:DockMargin(30, 10, 30, 0)
    savePositionButton:SetSize(250, 30)
    savePositionButton.DoClick = function() -- A custom function run when clicked ( note the . instead of : )
        RunConsoleCommand("save_position")
    end
end

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