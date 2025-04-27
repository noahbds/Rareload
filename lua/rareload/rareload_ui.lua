local RareloadUI = {}

if SERVER then
    util.AddNetworkString("RareloadSettingsSync")

    function BroadcastSettings()
        net.Start("RareloadSettingsSync")
        net.WriteString(file.Read("rareload/addon_state.json", "DATA") or "{}")
        net.Broadcast()
    end
end

if SERVER then
    -- After saving settings to addon_state.json
    BroadcastSettings()
end

-- ==============================
--    THEME & VISUAL SETTINGS
-- ==============================
RareloadUI.Theme = {
    Colors = {
        Background = Color(30, 30, 35, 230),
        Panel = Color(40, 40, 45, 245),
        Accent = Color(65, 145, 255),
        Danger = Color(255, 70, 70),
        Success = Color(70, 200, 120),

        Text = {
            Primary = Color(245, 245, 245),
            Secondary = Color(180, 180, 190),
            Disabled = Color(120, 120, 130)
        },

        Button = {
            Normal = Color(60, 60, 70),
            Hover = Color(70, 70, 80),
            Active = Color(50, 50, 60),
            Selected = Color(65, 145, 255)
        },

        Slider = {
            Track = Color(50, 50, 55),
            Groove = Color(65, 145, 255),
            Knob = Color(225, 225, 235),
            KnobHover = Color(255, 255, 255)
        },

        Separator = Color(60, 60, 70)
    },

    Sizes = {
        CornerRadius = 6,
        ButtonHeight = 40,
        SliderHeight = 6,
        KnobSize = 16,
        Padding = 15,
        Margin = 10
    },

    Animation = {
        Speed = 6,
        Bounce = 0.2
    }
}

-- ==============================
--    FONT REGISTRATION
-- ==============================
function RareloadUI.RegisterFonts()
    surface.CreateFont("RareloadUI.Title", {
        font = "Roboto",
        size = 28,
        weight = 600,
        antialias = true
    })

    surface.CreateFont("RareloadUI.Heading", {
        font = "Roboto",
        size = 22,
        weight = 600,
        antialias = true
    })

    surface.CreateFont("RareloadUI.Text", {
        font = "Roboto",
        size = 18,
        weight = 400,
        antialias = true
    })

    surface.CreateFont("RareloadUI.Small", {
        font = "Roboto",
        size = 16,
        weight = 400,
        antialias = true
    })

    surface.CreateFont("RareloadUI.Button", {
        font = "Roboto",
        size = 18,
        weight = 600,
        antialias = true
    })
end

-- ==============================
--    UTILITY FUNCTIONS
-- ==============================
function RareloadUI.DrawRoundedBox(x, y, w, h, radius, color)
    draw.RoundedBox(radius, x, y, w, h, color)
end

function RareloadUI.DrawCircle(x, y, radius, segments, color)
    -- Create points for the circle
    local points = {}
    for i = 0, segments do
        local angle = math.rad((i / segments) * 360)
        table.insert(points, {
            x = x + math.cos(angle) * radius,
            y = y + math.sin(angle) * radius
        })
    end

    -- Make sure we have a valid color
    if color then
        if istable(color) and color.r and color.g and color.b then
            -- It's a proper Color object
            surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
        elseif type(color) == "number" then
            -- Handle case where a single number is passed (sometimes happens with ColorAlpha)
            local c = math.floor(color)
            surface.SetDrawColor(c, c, c, 255)
        else
            -- Fallback to white
            surface.SetDrawColor(255, 255, 255, 255)
        end
    else
        -- Default to white if no color is provided
        surface.SetDrawColor(255, 255, 255, 255)
    end

    draw.NoTexture()
    surface.DrawPoly(points)
end

-- Smoothly interpolate between values (for animations)
function RareloadUI.Lerp(t, a, b)
    return a + (b - a) * t
end

-- ==============================
--    UI COMPONENTS
-- ==============================

-- Modern Toggle Switch
function RareloadUI.CreateToggle(parent, text, description, command, initialState, callback)
    local theme = RareloadUI.Theme

    local toggle = vgui.Create("DPanel", parent)
    toggle:Dock(TOP)
    toggle:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin)
    toggle:SetTall(description and 70 or 50)
    toggle:SetPaintBackground(false)

    toggle.Enabled = initialState or false
    toggle.Fraction = toggle.Enabled and 1 or 0
    toggle.HoverFraction = 0

    -- Label
    local label = vgui.Create("DLabel", toggle)
    label:Dock(LEFT)
    label:SetWide(parent:GetWide() - 80)
    label:SetText(text)
    label:SetTextColor(theme.Colors.Text.Primary)
    label:SetFont("RareloadUI.Heading")

    -- Description (if provided)
    if description then
        local desc = vgui.Create("DLabel", toggle)
        desc:Dock(BOTTOM)
        desc:DockMargin(0, 5, 60, 0)
        desc:SetText(description)
        desc:SetTextColor(theme.Colors.Text.Secondary)
        desc:SetFont("RareloadUI.Small")
        desc:SetWrap(true)
        desc:SetTall(30)
    end

    -- Switch drawing
    toggle.Paint = function(self, w, h)
        -- Track background
        local trackWidth = 46
        local trackHeight = 22
        local trackX = w - trackWidth - 10
        local trackY = (h - trackHeight) / 2

        -- Animate the fraction
        self.Fraction = Lerp(FrameTime() * 10, self.Fraction, self.Enabled and 1 or 0)
        self.HoverFraction = Lerp(FrameTime() * 8, self.HoverFraction, self:IsHovered() and 1 or 0)

        -- Track
        local trackColor = self.Enabled and
            theme.Colors.Accent or
            theme.Colors.Button.Normal

        RareloadUI.DrawRoundedBox(trackX, trackY, trackWidth, trackHeight, trackHeight / 2, trackColor)

        -- Knob
        local knobSize = trackHeight - 6
        local knobX = trackX + 3 + (trackWidth - knobSize - 6) * self.Fraction
        local knobY = trackY + 3

        -- Knob glow on hover
        if self.HoverFraction > 0 then
            RareloadUI.DrawCircle(
                knobX + knobSize / 2,
                knobY + knobSize / 2,
                knobSize / 2 + 4 * self.HoverFraction,
                20,
                ColorAlpha(theme.Colors.Text.Primary, 20 * self.HoverFraction)
            )
        end

        -- Knob itself
        RareloadUI.DrawCircle(
            knobX + knobSize / 2,
            knobY + knobSize / 2,
            knobSize / 2,
            20,
            theme.Colors.Text.Primary
        )
    end

    -- Handle interaction
    toggle.OnMousePressed = function(self, keyCode)
        if keyCode == MOUSE_LEFT then
            self.Enabled = not self.Enabled
            surface.PlaySound(self.Enabled and "ui/buttonclick.wav" or "ui/buttonclickrelease.wav")

            RunConsoleCommand(command, self.Enabled and "1" or "0")
            if callback then callback(self.Enabled) end
        end
    end

    return toggle
end

-- Modern Slider
function RareloadUI.CreateSlider(parent, title, description, command, min, max, decimals, defaultValue, unit)
    local theme = RareloadUI.Theme

    local slider = vgui.Create("DPanel", parent)
    slider:Dock(TOP)
    slider:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin * 1.5)
    slider:SetTall(description and 90 or 70)
    slider:SetPaintBackground(false)

    -- Internal state
    slider.Min = min or 0
    slider.Max = max or 100
    slider.Value = defaultValue or min or 0
    slider.Decimals = decimals or 0
    slider.Unit = unit or ""
    slider.Dragging = false
    slider.HoverFraction = 0

    -- Header
    local header = vgui.Create("DLabel", slider)
    header:Dock(TOP)
    header:SetText(title)
    header:SetFont("RareloadUI.Heading")
    header:SetTextColor(theme.Colors.Text.Primary)

    -- Description
    if description then
        local desc = vgui.Create("DLabel", slider)
        desc:Dock(TOP)
        desc:DockMargin(0, 3, 0, 8)
        desc:SetText(description)
        desc:SetTextColor(theme.Colors.Text.Secondary)
        desc:SetFont("RareloadUI.Small")
        desc:SetTall(20)
    end

    -- Value display
    local valueDisplay = vgui.Create("DLabel", slider)
    valueDisplay:Dock(RIGHT)
    valueDisplay:DockMargin(0, 0, 0, 0)
    valueDisplay:SetWide(65)
    valueDisplay:SetFont("RareloadUI.Text")
    valueDisplay:SetTextColor(theme.Colors.Text.Primary)

    -- Update the displayed value
    local function updateValueDisplay()
        local format = slider.Decimals > 0
            and "%." .. slider.Decimals .. "f%s"
            or "%d%s"

        valueDisplay:SetText(string.format(format, slider.Value, slider.Unit))
    end

    updateValueDisplay()

    -- Slider track
    local track = vgui.Create("DPanel", slider)
    track:Dock(BOTTOM)
    track:DockMargin(0, 5, 70, 5)
    track:SetTall(theme.Sizes.SliderHeight + 20)
    track:SetPaintBackground(false)

    track.OnCursorMoved = function(self, x, y)
        if slider.Dragging then
            local width = self:GetWide() - theme.Sizes.KnobSize
            local fraction = math.Clamp((x - theme.Sizes.KnobSize / 2) / width, 0, 1)
            slider.Value = slider.Min + (slider.Max - slider.Min) * fraction

            -- Round to the specified decimal places
            if slider.Decimals > 0 then
                local multiplier = 10 ^ slider.Decimals
                slider.Value = math.Round(slider.Value * multiplier) / multiplier
            else
                slider.Value = math.Round(slider.Value)
            end

            updateValueDisplay()
            RunConsoleCommand(command, slider.Value)
        end
    end

    track.OnMousePressed = function(self, keyCode)
        if keyCode == MOUSE_LEFT then
            slider.Dragging = true
            self:OnCursorMoved(self:CursorPos())
            self:MouseCapture(true)
        end
    end

    track.OnMouseReleased = function(self, keyCode)
        if keyCode == MOUSE_LEFT and slider.Dragging then
            slider.Dragging = false
            self:MouseCapture(false)
        end
    end


    track.Paint = function(self, w, h)
        local trackHeight = theme.Sizes.SliderHeight
        local trackY = (h - trackHeight) / 2
        local knobSize = theme.Sizes.KnobSize

        -- Calculate fraction
        local fraction = (slider.Value - slider.Min) / (slider.Max - slider.Min)
        local knobX = fraction * (w - knobSize)

        -- Track background
        RareloadUI.DrawRoundedBox(0, trackY, w, trackHeight, trackHeight / 2, theme.Colors.Slider.Track)

        -- Filled portion
        RareloadUI.DrawRoundedBox(0, trackY, knobX + knobSize / 2, trackHeight, trackHeight / 2,
            theme.Colors.Slider.Groove)

        -- Animate hover effect
        slider.HoverFraction = Lerp(FrameTime() * 8, slider.HoverFraction,
            (self:IsHovered() or slider.Dragging) and 1 or 0)

        -- Knob hover glow
        if slider.HoverFraction > 0 then
            RareloadUI.DrawCircle(
                knobX + knobSize / 2,
                trackY + trackHeight / 2,
                knobSize / 2 + 4 * slider.HoverFraction,
                20,
                ColorAlpha(theme.Colors.Accent, 40 * slider.HoverFraction)
            )
        end

        -- Knob
        RareloadUI.DrawCircle(
            knobX + knobSize / 2,
            trackY + trackHeight / 2,
            knobSize / 2,
            20,
            slider.Dragging and theme.Colors.Slider.KnobHover or theme.Colors.Slider.Knob
        )

        -- Value markers (notches)
        local notches = 5
        for i = 0, notches do
            local x = (i / notches) * (w - knobSize) + knobSize / 2
            surface.SetDrawColor(theme.Colors.Text.Disabled)
            surface.DrawLine(x, trackY + trackHeight + 3, x, trackY + trackHeight + 6)
        end
    end

    return slider
end

-- Modern Action Button (not a toggle)
function RareloadUI.CreateActionButton(parent, text, command, description)
    local theme = RareloadUI.Theme

    local button = vgui.Create("DPanel", parent)
    button:Dock(TOP)
    button:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin)
    button:SetTall(theme.Sizes.ButtonHeight)
    button:SetPaintBackground(false)
    button:SetCursor("hand")

    -- Animation states
    button.Hovered = false
    button.Pressed = false
    button.HoverFraction = 0
    button.PressFraction = 0

    button.DoClick = function()
        if command then
            RunConsoleCommand(command)
        end

        -- Visual feedback
        local flash = vgui.Create("DPanel", button)
        flash:SetSize(button:GetWide(), button:GetTall())
        flash:SetAlpha(120)
        flash.Paint = function(self, w, h)
            RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, Color(255, 255, 255))
        end
        flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)

        -- Sound feedback
        surface.PlaySound("ui/buttonclickrelease.wav")
    end

    button.OnCursorEntered = function(self)
        self.Hovered = true
        surface.PlaySound("ui/buttonrollover.wav")
    end

    button.OnCursorExited = function(self)
        self.Hovered = false
        self.Pressed = false
    end

    button.OnMousePressed = function(self)
        self.Pressed = true
    end

    button.OnMouseReleased = function(self)
        if self.Pressed and self.Hovered then
            self:DoClick()
        end
        self.Pressed = false
    end

    button.Paint = function(self, w, h)
        -- Update animation fractions
        self.HoverFraction = Lerp(FrameTime() * 8, self.HoverFraction, self.Hovered and 1 or 0)
        self.PressFraction = Lerp(FrameTime() * 10, self.PressFraction, self.Pressed and 1 or 0)

        -- Base color
        local baseColor = theme.Colors.Success

        -- Apply hover and press effects
        local r = baseColor.r + 20 * self.HoverFraction - 15 * self.PressFraction
        local g = baseColor.g + 20 * self.HoverFraction - 15 * self.PressFraction
        local b = baseColor.b + 20 * self.HoverFraction - 15 * self.PressFraction

        local color = Color(r, g, b, baseColor.a)

        -- Button background
        RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, color)

        -- Button text
        draw.SimpleText(
            text,
            "RareloadUI.Button",
            w / 2,
            h / 2 + 1 * self.PressFraction,
            theme.Colors.Text.Primary,
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER
        )

        surface.SetDrawColor(255, 255, 255, 30 + 20 * self.HoverFraction)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    return button
end

-- Modern Button
function RareloadUI.CreateButton(parent, text, command, description, settingKey, primary)
    local theme = RareloadUI.Theme

    local button = vgui.Create("DPanel", parent)
    button:Dock(TOP)
    button:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin)
    button:SetTall(theme.Sizes.ButtonHeight)
    button:SetPaintBackground(false)
    button:SetCursor("hand")

    -- Helper to get the current value from RARELOAD.settings
    local function GetSettingValue()
        if RARELOAD and RARELOAD.settings and settingKey then
            return RARELOAD.settings[settingKey] == true
        end
        return false
    end

    -- Store the state
    button.IsEnabled = GetSettingValue()
    button.ButtonText = text
    button.ButtonFont = "RareloadUI.Button"

    -- Animation states
    button.Hovered = false
    button.Pressed = false
    button.HoverFraction = 0
    button.PressFraction = 0

    -- Calculate text scaling
    button.UpdateTextFit = function(self)
        -- Ensure there's a valid width before proceeding
        local width = self:GetWide()
        if width <= 0 then return end

        -- Start with the default font
        local currentFont = self.ButtonFont
        surface.SetFont(currentFont)
        local textW, textH = surface.GetTextSize(self.ButtonText or "")

        -- If there's no text, nothing to do
        if not textW or textW <= 0 then return end

        -- Available space for text (account for status indicator and padding)
        local availableWidth = width - 70 -- Reserve space for ON/OFF and padding

        -- If text is too wide, we need to create a custom scaled font
        if textW > availableWidth and availableWidth > 0 then
            local scaleFactor = availableWidth / textW
            local newSize = math.floor(18 * scaleFactor) -- 18 is the default size from "RareloadUI.Button"
            newSize = math.max(10, newSize)              -- Don't go smaller than 10pt

            local fontName = "RareloadUI.ButtonDynamic" .. newSize

            -- Create a static table to track created fonts globally
            if not RareloadUI.CreatedDynamicFonts then
                RareloadUI.CreatedDynamicFonts = {}
            end

            -- Only create the font if it doesn't already exist
            if not RareloadUI.CreatedDynamicFonts[fontName] then
                surface.CreateFont(fontName, {
                    font = "Roboto",
                    size = newSize,
                    weight = 600,
                    antialias = true
                })
                RareloadUI.CreatedDynamicFonts[fontName] = true
            end

            self.ButtonFont = fontName
        else
            self.ButtonFont = "RareloadUI.Button" -- Default font
        end
    end

    button.DoClick = function()
        if command then
            -- Toggle the state
            RunConsoleCommand(command, button.IsEnabled and "0" or "1")
            -- Wait a short time and then update the button state from settings
            timer.Simple(0.2, function()
                button.IsEnabled = GetSettingValue()
                button:InvalidateLayout()
            end)
        end

        -- Visual feedback
        local flash = vgui.Create("DPanel", button)
        flash:SetSize(button:GetWide(), button:GetTall())
        flash:SetAlpha(120)
        flash.Paint = function(self, w, h)
            RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, Color(255, 255, 255))
        end
        flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)

        -- Sound feedback
        surface.PlaySound("ui/buttonclickrelease.wav")
    end

    button.OnCursorEntered = function(self)
        self.Hovered = true
        surface.PlaySound("ui/buttonrollover.wav")
    end

    button.OnCursorExited = function(self)
        self.Hovered = false
        self.Pressed = false
    end

    button.OnMousePressed = function(self)
        self.Pressed = true
    end

    button.OnMouseReleased = function(self)
        if self.Pressed and self.Hovered then
            self:DoClick()
        end
        self.Pressed = false
    end

    button.Think = function(self)
        -- Always sync with the real setting
        local current = GetSettingValue()
        if self.IsEnabled ~= current then
            self.IsEnabled = current
            self:InvalidateLayout()
        end
    end

    button.PerformLayout = function(self, w, h)
        self:UpdateTextFit()
    end

    button.Paint = function(self, w, h)
        -- Guard against invalid dimensions
        if not w or w <= 0 or not h or h <= 0 then return end

        -- Update animation fractions
        self.HoverFraction = Lerp(FrameTime() * 8, self.HoverFraction, self.Hovered and 1 or 0)
        self.PressFraction = Lerp(FrameTime() * 10, self.PressFraction, self.Pressed and 1 or 0)

        -- Base color based on enabled state
        local baseColor = self.IsEnabled and theme.Colors.Accent or theme.Colors.Button.Normal

        -- Apply hover and press effects
        local r = baseColor.r + 20 * self.HoverFraction - 15 * self.PressFraction
        local g = baseColor.g + 20 * self.HoverFraction - 15 * self.PressFraction
        local b = baseColor.b + 20 * self.HoverFraction - 15 * self.PressFraction

        local color = Color(r, g, b, baseColor.a)

        -- Button background
        RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, color)

        -- Make sure we have valid text before drawing
        if self.ButtonText and self.ButtonFont then
            -- Button text
            draw.SimpleText(
                self.ButtonText,
                self.ButtonFont,
                w / 2,
                h / 2 + 1 * self.PressFraction,
                theme.Colors.Text.Primary,
                TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER
            )
        end

        -- Status indicator
        local statusText = self.IsEnabled and "ON" or "OFF"
        draw.SimpleText(
            statusText,
            "RareloadUI.Small",
            w - 15,
            h / 2 + 1 * self.PressFraction,
            theme.Colors.Text.Primary,
            TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_CENTER
        )

        -- Subtle border
        surface.SetDrawColor(255, 255, 255, 30 + 20 * self.HoverFraction)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    return button
end

-- Separator line
function RareloadUI.CreateSeparator(parent)
    local theme = RareloadUI.Theme

    local separator = vgui.Create("DPanel", parent)
    separator:Dock(TOP)
    separator:DockMargin(theme.Sizes.Margin * 2, theme.Sizes.Margin, theme.Sizes.Margin * 2, theme.Sizes.Margin)
    separator:SetTall(1)
    separator:SetPaintBackground(false)

    separator.Paint = function(self, w, h)
        surface.SetDrawColor(theme.Colors.Separator)
        surface.DrawRect(0, 0, w, 1)
    end

    return separator
end

-- Header with title
function RareloadUI.CreateHeader(parent, text)
    local theme = RareloadUI.Theme

    local header = vgui.Create("DPanel", parent)
    header:Dock(TOP)
    header:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, 0)
    header:SetTall(40)
    header:SetPaintBackground(false)

    header.Paint = function(self, w, h)
        draw.SimpleText(
            text,
            "RareloadUI.Title",
            0,
            h / 2,
            theme.Colors.Text.Primary,
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER
        )
    end

    return header
end

-- Main panel creation
function RareloadUI.CreatePanel(title)
    RareloadUI.RegisterFonts()

    local theme = RareloadUI.Theme
    local frame = vgui.Create("DFrame")
    frame:SetTitle("")
    frame:SetSize(500, 600)
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(true)
    frame:SetDeleteOnClose(true)

    -- Style the frame
    frame.Paint = function(self, w, h)
        -- Background with blur
        Derma_DrawBackgroundBlur(self, self.StartTime or 0)
        RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, theme.Colors.Background)

        -- Top header bar
        RareloadUI.DrawRoundedBox(0, 0, w, 50, theme.Sizes.CornerRadius, theme.Colors.Panel)
        RareloadUI.DrawRoundedBox(0, 0, w, 6, theme.Sizes.CornerRadius, theme.Colors.Accent)

        -- Title
        draw.SimpleText(
            title or "Rareload Settings",
            "RareloadUI.Title",
            15,
            25,
            theme.Colors.Text.Primary,
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER
        )

        -- Bottom area
        RareloadUI.DrawRoundedBox(0, h - 50, w, 50, theme.Sizes.CornerRadius, theme.Colors.Panel)
    end

    -- Custom close button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetText("")
    closeBtn:SetSize(30, 30)
    closeBtn:SetPos(frame:GetWide() - 40, 10)

    closeBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and theme.Colors.Danger or theme.Colors.Text.Secondary
        surface.SetDrawColor(color)
        surface.DrawLine(8, 8, w - 8, h - 8)
        surface.DrawLine(w - 8, 8, 8, h - 8)
    end

    closeBtn.DoClick = function()
        frame:Close()
        surface.PlaySound("ui/buttonclick.wav")
    end

    -- Content scroll panel
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(0, 50, 0, 50)

    -- Style the scrollbar
    local scrollbar = scroll:GetVBar()
    scrollbar:SetWide(8)
    scrollbar:SetHideButtons(true)

    function scrollbar:Paint(w, h)
        RareloadUI.DrawRoundedBox(0, 0, w, h, w / 2, theme.Colors.Button.Normal)
    end

    function scrollbar.btnGrip:Paint(w, h)
        RareloadUI.DrawRoundedBox(0, 0, w, h, w / 2, theme.Colors.Accent)
    end

    RareloadUI.LastPanel = frame
    return frame, scroll
end

-- Register language strings for UI
function RareloadUI.RegisterLanguage()
    language.Add("tool.rareload_tool.name", "Rareload Configuration")
    language.Add("tool.rareload_tool.desc", "Configure the Rareload addon settings.")
    language.Add("tool.rareload_tool.0", "By Noahbds")
end

return RareloadUI
