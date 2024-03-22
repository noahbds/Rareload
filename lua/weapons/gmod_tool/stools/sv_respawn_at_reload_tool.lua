TOOL.Category   = "Respawn at Reload"
TOOL.Name       = "Respawn at Reload Config Tool"
TOOL.Command    = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.sv_respawn_at_reload_tool.name", "Respawn at reload Configuration Panel")
    language.Add("tool.sv_respawn_at_reload_tool.desc", "Configuration Panel For Respawn At Reload Addon.")
    language.Add("tool.sv_respawn_at_reload_tool.0", "By Noahbds")

    local fontParams = { font = "Arial", size = 30, weight = 1000, antialias = true, additive = false }

    surface.CreateFont("CTNV", fontParams)
    surface.CreateFont("CTNV2", fontParams)
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
    local addonStateFilePath = "respawn_at_reload/addon_state.txt"
    local addonStateData

    -- Check if the file exists
    if file.Exists(addonStateFilePath, "DATA") then
        addonStateData = file.Read(addonStateFilePath, "DATA")
    else
        -- If the file doesn't exist, create it with default values
        addonStateData = "true\ntrue\nfalse\ntrue"
        file.Write(addonStateFilePath, addonStateData)
    end

    local addonStateLines = string.Explode("\n", addonStateData)

    -- Create a button to toggle respawn behavior with color based on addon state
    CreateStyledButton(panel, "Toggle Respawn at Reload", "toggle_respawn_at_reload",
        "Enable or disable automatic respawn at reload", addonStateLines[1])

    -- Create a button to toggle spawn mode with color based on addon state
    CreateStyledButton(panel, "Toggle Move Type", "toggle_spawn_mode",
        "Switch between different spawn modes", addonStateLines[2])

    -- Create a button to toggle spawn mode with color based on addon state
    CreateStyledButton(panel, "Toggle Auto Save", "toggle_auto_save",
        "Enable or Disable Auto Saving Position", addonStateLines[3])

    -- Create a button to toggle spawn mode with color based on addon state
    CreateStyledButton(panel, "Toggle Print Messages", "toggle_print_message",
        "Enable or Disable Monitoring Messages in Console", addonStateLines[4])

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
