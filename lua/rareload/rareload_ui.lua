local UI = {}

-- UI constants
UI.COLORS = setmetatable({
    ENABLED = Color(50, 150, 255),
    DISABLED = Color(255, 50, 50),
    SLIDER = {
        BACKGROUND = Color(40, 40, 45, 200),
        GROOVE = Color(60, 60, 70),
        NOTCH = Color(80, 80, 90),
        GRIP = Color(80, 140, 240),
        GRIP_HOVER = Color(100, 160, 255)
    },
    TEXT = {
        PRIMARY = Color(255, 255, 255),
        SECONDARY = Color(200, 200, 220)
    },
    SAVE_BUTTON = Color(0, 122, 204)
}, { __newindex = function() error("UI.COLORS is read-only") end })

UI.MARGINS = setmetatable({
    STANDARD = { 30, 10, 30, 0 },
    SLIDERS = { 30, 10, 30, 5 }
}, { __newindex = function() error("UI.MARGINS is read-only") end })

-- Register fonts for UI
function UI.RegisterFonts()
    surface.CreateFont("RARELOAD_NORMAL", {
        font = "Arial",
        size = 21,
        weight = 2000,
        antialias = true,
        additive = false
    })
    surface.CreateFont("RARELOAD_LARGE", {
        font = "Arial",
        size = 31,
        weight = 2000,
        antialias = true,
        additive = false
    })
    surface.CreateFont("CTNV", {
        font = "Roboto",
        size = 18,
        weight = 500,
        antialias = true
    })
    surface.CreateFont("CTNV2", {
        font = "Roboto",
        size = 24,
        weight = 700,
        antialias = true
    })
end

-- Register language strings for UI
function UI.RegisterLanguage()
    language.Add("tool.rareload_tool.name", "Rareload Configuration Panel")
    language.Add("tool.rareload_tool.desc", "Configuration Panel For Rareload Addon.")
    language.Add("tool.rareload_tool.0", "By Noahbds")
end

-- Draw a circle using surface.DrawPoly
function UI.DrawCircle(x, y, radius, segments)
    local points = {}
    for i = 0, segments do
        local angle = math.rad((i / segments) * 360)
        table.insert(points, {
            x = x + math.cos(angle) * radius,
            y = y + math.sin(angle) * radius
        })
    end
    surface.DrawPoly(points)
end

-- Create a toggle button
function UI.CreateToggleButton(parent, text, command, tooltip, isEnabled, onToggle)
    assert(IsValid(parent), "Parent panel is invalid")
    ---@class DButton
    local button = vgui.Create("DButton", parent)
    button:SetText(text)
    button:SetFont("DermaLarge")
    button:Dock(TOP)
    button:DockMargin(unpack(UI.MARGINS.STANDARD))
    button:SetSize(250, 30)

    -- Internal state
    button._isEnabled = isEnabled and true or false

    -- Visuals
    button.Paint = function(self, w, h)
        local baseColor = self._isEnabled and UI.COLORS.ENABLED or UI.COLORS.DISABLED
        local color = self:IsHovered() and Color(
            math.min(baseColor.r + 20, 255),
            math.min(baseColor.g + 20, 255),
            math.min(baseColor.b + 20, 255),
            baseColor.a
        ) or baseColor
        draw.RoundedBox(6, 0, 0, w, h, color)
        surface.SetDrawColor(255, 255, 255, 40)
        surface.DrawOutlinedRect(0, 0, w, h, 2)

        local iconSize = h * 0.6
        local iconX = 10
        local iconY = h / 2
        surface.SetDrawColor(self._isEnabled and UI.COLORS.ENABLED or UI.COLORS.DISABLED)
        draw.NoTexture()
        UI.DrawCircle(iconX + iconSize / 2, iconY, iconSize / 2, 32)
        if self._isEnabled then
            surface.SetDrawColor(255, 255, 255, 180)
            UI.DrawCircle(iconX + iconSize / 2, iconY, iconSize / 2 - 4, 32)
        end
    end

    button.SetToggleState = function(self, state)
        self._isEnabled = state
        self:SetTextColor(state and UI.COLORS.TEXT.PRIMARY or UI.COLORS.TEXT.SECONDARY)
    end

    button.DoClick = function(self)
        self._isEnabled = not self._isEnabled
        self:SetToggleState(self._isEnabled)
        RunConsoleCommand(command, self._isEnabled and "1" or "0")
        surface.PlaySound(self._isEnabled and "buttons/button14.wav" or "buttons/button15.wav")
        if onToggle then onToggle(self._isEnabled) end
    end

    button:SetToggleState(button._isEnabled)
    if tooltip then button:SetTooltip(tooltip) end
    return button
end

-- Create a slider for settings
function UI.CreateSettingSlider(panel, title, command, min, max, decimals, defaultValue, tooltip, unit)
    assert(IsValid(panel), "Panel is invalid")
    local container = vgui.Create("DPanel", panel)
    container:Dock(TOP)
    container:SetTall(60)
    container:DockMargin(unpack(UI.MARGINS.SLIDERS))
    container:SetPaintBackground(false)

    local header = vgui.Create("DLabel", container)
    header:SetText(title)
    header:SetTextColor(UI.COLORS.TEXT.PRIMARY)
    header:SetFont("DermaDefaultBold")
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 2)

    if tooltip then
        local desc = vgui.Create("DLabel", container)
        desc:SetText(tooltip)
        desc:SetTextColor(UI.COLORS.TEXT.SECONDARY)
        desc:SetFont("DermaDefault")
        desc:Dock(TOP)
        desc:DockMargin(0, 0, 0, 4)
        desc:SetWrap(true)
        desc:SetTall(18)
    end

    local sliderContainer = vgui.Create("DPanel", container)
    sliderContainer:Dock(FILL)
    sliderContainer:DockPadding(0, 0, 0, 0)
    sliderContainer:SetPaintBackground(false)

    local valueDisplay = vgui.Create("DLabel", sliderContainer)
    valueDisplay:SetSize(50, 20)
    valueDisplay:Dock(RIGHT)
    valueDisplay:SetContentAlignment(6)
    valueDisplay:SetTextColor(UI.COLORS.SLIDER.GRIP)

    ---@class DNumSlider
    local slider = vgui.Create("DNumSlider", sliderContainer)
    slider:Dock(FILL)
    slider:SetMin(min)
    slider:SetMax(max)
    slider:SetDecimals(decimals)
    slider:SetDefaultValue(defaultValue)
    slider:SetValue(defaultValue)
    slider:SetDark(false)

    slider.Slider.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, h / 2 - 2, w, 4, UI.COLORS.SLIDER.GROOVE)
        local steps = 5
        local stepSize = w / steps
        for i = 0, steps do
            local x = i * stepSize
            draw.RoundedBox(1, x - 1, h / 2 - 4, 2, 8, UI.COLORS.SLIDER.NOTCH)
        end
    end

    slider.Slider.Knob.Paint = function(self, w, h)
        local color = self:IsHovered() and UI.COLORS.SLIDER.GRIP_HOVER or UI.COLORS.SLIDER.GRIP
        draw.RoundedBox(6, 0, 0, w, h, color)
    end

    local function updateDisplay()
        local val = slider:GetValue()
        local displayText = string.format(decimals > 0 and "%." .. decimals .. "f%s" or "%d%s", val, unit or "")
        valueDisplay:SetText(displayText)
    end

    updateDisplay()

    slider.OnValueChanged = function(self, val)
        updateDisplay()
        RunConsoleCommand(command, val)
        local flash = vgui.Create("DPanel", slider)
        flash:SetSize(slider:GetWide(), slider:GetTall())
        flash:SetPos(0, 0)
        flash:SetAlpha(80)
        flash.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, UI.COLORS.SLIDER.GRIP)
        end
        flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)
    end

    return container, slider
end

-- Create a separator line
function UI.CreateSeparator(panel)
    assert(IsValid(panel), "Panel is invalid")
    local separator = vgui.Create("DPanel", panel)
    separator:Dock(TOP)
    separator:SetTall(1)
    separator:DockMargin(40, 10, 40, 10)
    separator.Paint = function(self, w, h)
        surface.SetDrawColor(70, 70, 80, 180)
        surface.DrawLine(0, 0, w, 0)
    end
    return separator
end

-- Create a save position button
function UI.CreateSavePositionButton(panel)
    assert(IsValid(panel), "Panel is invalid")
    ---@class DButton
    local button = vgui.Create("DButton", panel)
    button:SetText("Save Position")
    button:SetTextColor(UI.COLORS.TEXT.PRIMARY)
    button:SetFont("DermaLarge")
    button:Dock(TOP)
    button:DockMargin(unpack(UI.MARGINS.STANDARD))
    button:SetSize(250, 40)

    button.Paint = function(self, w, h)
        local baseColor = UI.COLORS.SAVE_BUTTON
        local color = self:IsHovered() and Color(
            math.min(baseColor.r + 30, 255),
            math.min(baseColor.g + 30, 255),
            math.min(baseColor.b + 30, 255),
            baseColor.a
        ) or baseColor
        draw.RoundedBox(8, 0, 0, w, h, color)
    end

    button.DoClick = function()
        RunConsoleCommand("save_position")
        local flash = vgui.Create("DPanel", button)
        flash:SetSize(button:GetWide(), button:GetTall())
        flash:SetPos(0, 0)
        flash:SetAlpha(100)
        flash.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(255, 255, 255))
        end
        flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)
    end

    return button
end

return UI
