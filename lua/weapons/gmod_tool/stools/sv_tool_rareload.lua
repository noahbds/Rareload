---@diagnostic disable: undefined-global

-- lua/weapons/gmod_tool/stools/sv_tool_rareload.lua

TOOL            = TOOL or {}
TOOL.Category   = "Respawn at Reload"
TOOL.Name       = "Respawn at Reload Config Tool"
TOOL.Command    = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.rareload.name", "Respawn at Reload Configuration Panel")
    language.Add("tool.rareload.desc", "Configuration Panel For Respawn At Reload Addon.")
    language.Add("tool.rareload.0", "By Noahbds")

    local fontParams = { font = "Arial", size = 30, weight = 1000, antialias = true, additive = false }

    surface.CreateFont("CTNV", fontParams)
    surface.CreateFont("CTNV2", fontParams)
end

if SERVER then
    include("utils.lua")
end

function TOOL.BuildCPanel(panel)
    panel:DockPadding(15, 15, 15, 15)

    local function CreateStyledButton(parent, text, command, tooltip, colorVar)
        local button = vgui.Create("DButton", parent)
        button:SetText(text)
        button:Dock(TOP)
        button:DockMargin(30, 10, 30, 0)
        button:SetSize(250, 30)

        local color = colorVar and colorVar:lower() == "true" and Color(50, 150, 255) or Color(255, 50, 50)
        button:SetTextColor(color)
        button:SetColor(color)

        button.OnCursorEntered = function()
            button:SetColor(Color(100, 200, 255))
        end

        button.OnCursorExited = function()
            button:SetColor(color)
        end

        button.DoClick = function()
            RunConsoleCommand(command)

            if button:GetColor() == Color(50, 150, 255) then
                button:SetColor(Color(255, 50, 50))
                button:SetTextColor(Color(255, 50, 50))
            else
                button:SetColor(Color(50, 150, 255))
                button:SetTextColor(Color(50, 150, 255))
            end
        end

        if tooltip then
            button:SetTooltip(tooltip)
        end

        return button
    end

    LoadAddonState()

    CreateStyledButton(panel, "Toggle Respawn at Reload", "toggle_respawn_at_reload",
        "Enable or disable automatic respawn at reload", tostring(RARELOAD.settings.addonEnabled))

    CreateStyledButton(panel, "Toggle Move Type", "toggle_spawn_mode",
        "Switch between different spawn modes", tostring(RARELOAD.settings.spawnModeEnabled))

    CreateStyledButton(panel, "Toggle Auto Save", "toggle_auto_save",
        "Enable or Disable Auto Saving Position", tostring(RARELOAD.settings.autoSaveEnabled))

    CreateStyledButton(panel, "Toggle Print Messages", "toggle_print_message",
        "Enable or Disable Monitoring Messages in Console", tostring(RARELOAD.settings.printMessageEnabled))

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

function TOOL:DrawToolScreen(width, height)
    if RARELOAD.settings.addonEnabled then
        surface.SetDrawColor(0, 255, 0, 255) -- Green
    else
        surface.SetDrawColor(255, 0, 0, 255) -- Red
    end

    surface.DrawRect(0, 0, width, height)

    surface.SetFont("CTNV")
    local textWidth, textHeight = surface.GetTextSize("CTNV")
    surface.SetFont("CTNV2")
    local text2Width, text2Height = surface.GetTextSize("By Noahbds")

    draw.SimpleText("Respawn At Reload", "CTNV", width / 2, 100, Color(224, 224, 224, 255), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    draw.SimpleText("By Noahbds", "CTNV2", width / 2, 128 + (textHeight + text2Height) / 2 - 4, Color(224, 224, 224, 255),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    if RARELOAD.settings.autoSaveEnabled then
        draw.SimpleText("Auto Save: ON", "CTNV2", width / 2, 200, Color(0, 255, 0, 255), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    else
        draw.SimpleText("Auto Save: OFF", "CTNV2", width / 2, 200, Color(255, 0, 0, 255), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
end
