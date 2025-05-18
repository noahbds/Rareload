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
    local points = {}
    for i = 0, segments do
        local angle = math.rad((i / segments) * 360)
        table.insert(points, {
            x = x + math.cos(angle) * radius,
            y = y + math.sin(angle) * radius
        })
    end

    if color then
        if istable(color) and color.r and color.g and color.b then
            surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
        elseif type(color) == "number" then
            local c = math.floor(color)
            surface.SetDrawColor(c, c, c, 255)
        else
            surface.SetDrawColor(255, 255, 255, 255)
        end
    else
        surface.SetDrawColor(255, 255, 255, 255)
    end

    draw.NoTexture()
    surface.DrawPoly(points)
end

function RareloadUI.Lerp(t, a, b)
    return a + (b - a) * t
end

-- ==============================
--    UI COMPONENTS
-- ==============================

function RareloadUI.CreateToggle(parent, text, description, command, initialState, callback)
    local theme = RareloadUI.Theme

    ---@class DPanel
    local toggle = vgui.Create("DPanel", parent)
    toggle:Dock(TOP)
    toggle:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin)
    toggle:SetTall(description and 70 or 50)
    toggle:SetPaintBackground(false)

    toggle.Enabled = initialState or false
    toggle.Fraction = toggle.Enabled and 1 or 0
    toggle.HoverFraction = 0

    local label = vgui.Create("DLabel", toggle)
    label:Dock(LEFT)
    label:SetWide(parent:GetWide() - 80)
    label:SetText(text)
    label:SetTextColor(theme.Colors.Text.Primary)
    label:SetFont("RareloadUI.Heading")

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

    toggle.Paint = function(self, w, h)
        local trackWidth = 46
        local trackHeight = 22
        local trackX = w - trackWidth - 10
        local trackY = (h - trackHeight) / 2

        self.Fraction = Lerp(FrameTime() * 10, self.Fraction, self.Enabled and 1 or 0)
        self.HoverFraction = Lerp(FrameTime() * 8, self.HoverFraction, self:IsHovered() and 1 or 0)

        local trackColor = self.Enabled and
            theme.Colors.Accent or
            theme.Colors.Button.Normal

        RareloadUI.DrawRoundedBox(trackX, trackY, trackWidth, trackHeight, trackHeight / 2, trackColor)

        local knobSize = trackHeight - 6
        local knobX = trackX + 3 + (trackWidth - knobSize - 6) * self.Fraction
        local knobY = trackY + 3

        if self.HoverFraction > 0 then
            RareloadUI.DrawCircle(
                knobX + knobSize / 2,
                knobY + knobSize / 2,
                knobSize / 2 + 4 * self.HoverFraction,
                20,
                ColorAlpha(theme.Colors.Text.Primary, 20 * self.HoverFraction)
            )
        end

        RareloadUI.DrawCircle(
            knobX + knobSize / 2,
            knobY + knobSize / 2,
            knobSize / 2,
            20,
            theme.Colors.Text.Primary
        )
    end

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

function RareloadUI.CreateSlider(parent, title, description, command, min, max, decimals, defaultValue, unit)
    local theme = RareloadUI.Theme

    ---@class DPanel
    local slider = vgui.Create("DPanel", parent)
    slider:Dock(TOP)
    slider:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin * 1.5)
    slider:SetTall(description and 90 or 70)
    slider:SetPaintBackground(false)

    slider.Min = min or 0
    slider.Max = max or 100
    slider.Value = defaultValue or min or 0
    slider.Decimals = decimals or 0
    slider.Unit = unit or ""
    slider.Dragging = false
    slider.HoverFraction = 0

    local header = vgui.Create("DLabel", slider)
    header:Dock(TOP)
    header:SetText(title)
    header:SetFont("RareloadUI.Heading")
    header:SetTextColor(theme.Colors.Text.Primary)

    if description then
        local desc = vgui.Create("DLabel", slider)
        desc:Dock(TOP)
        desc:DockMargin(0, 3, 0, 8)
        desc:SetText(description)
        desc:SetTextColor(theme.Colors.Text.Secondary)
        desc:SetFont("RareloadUI.Small")
        desc:SetTall(20)
    end

    local valueDisplay = vgui.Create("DLabel", slider)
    valueDisplay:Dock(RIGHT)
    valueDisplay:DockMargin(0, 0, 0, 0)
    valueDisplay:SetWide(65)
    valueDisplay:SetFont("RareloadUI.Text")
    valueDisplay:SetTextColor(theme.Colors.Text.Primary)

    local function updateValueDisplay()
        local format = slider.Decimals > 0
            and "%." .. slider.Decimals .. "f%s"
            or "%d%s"

        valueDisplay:SetText(string.format(format, slider.Value, slider.Unit))
    end

    updateValueDisplay()

    ---@class DPanel
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
        local fraction = (slider.Value - slider.Min) / (slider.Max - slider.Min)
        local knobX = fraction * (w - knobSize)

        RareloadUI.DrawRoundedBox(0, trackY, w, trackHeight, trackHeight / 2, theme.Colors.Slider.Track)

        RareloadUI.DrawRoundedBox(0, trackY, knobX + knobSize / 2, trackHeight, trackHeight / 2,
            theme.Colors.Slider.Groove)

        slider.HoverFraction = Lerp(FrameTime() * 8, slider.HoverFraction,
            (self:IsHovered() or slider.Dragging) and 1 or 0)

        if slider.HoverFraction > 0 then
            RareloadUI.DrawCircle(
                knobX + knobSize / 2,
                trackY + trackHeight / 2,
                knobSize / 2 + 4 * slider.HoverFraction,
                20,
                ColorAlpha(theme.Colors.Accent, 40 * slider.HoverFraction)
            )
        end

        RareloadUI.DrawCircle(
            knobX + knobSize / 2,
            trackY + trackHeight / 2,
            knobSize / 2,
            20,
            slider.Dragging and theme.Colors.Slider.KnobHover or theme.Colors.Slider.Knob
        )

        local notches = 5
        for i = 0, notches do
            local x = (i / notches) * (w - knobSize) + knobSize / 2
            surface.SetDrawColor(theme.Colors.Text.Disabled)
            surface.DrawLine(x, trackY + trackHeight + 3, x, trackY + trackHeight + 6)
        end
    end

    return slider
end

function RareloadUI.CreateActionButton(parent, text, command, description)
    local theme = RareloadUI.Theme

    local button = vgui.Create("DPanel", parent)
    button:Dock(TOP)
    button:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin)
    button:SetTall(theme.Sizes.ButtonHeight)
    button:SetPaintBackground(false)
    button:SetCursor("hand")
    button.Hovered = false
    button.Pressed = false
    button.HoverFraction = 0
    button.PressFraction = 0

    button.DoClick = function()
        if command then
            RunConsoleCommand(command)
        end

        local flash = vgui.Create("DPanel", button)
        flash:SetSize(button:GetWide(), button:GetTall())
        flash:SetAlpha(120)
        flash.Paint = function(self, w, h)
            RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, Color(255, 255, 255))
        end
        flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)

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
        self.HoverFraction = Lerp(FrameTime() * 8, self.HoverFraction, self.Hovered and 1 or 0)
        self.PressFraction = Lerp(FrameTime() * 10, self.PressFraction, self.Pressed and 1 or 0)

        local baseColor = theme.Colors.Success
        local r = baseColor.r + 20 * self.HoverFraction - 15 * self.PressFraction
        local g = baseColor.g + 20 * self.HoverFraction - 15 * self.PressFraction
        local b = baseColor.b + 20 * self.HoverFraction - 15 * self.PressFraction

        local color = Color(r, g, b, baseColor.a)

        RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, color)

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

function RareloadUI.CreateButton(parent, text, command, description, settingKey, primary)
    local theme = RareloadUI.Theme

    ---@class DPanel
    local button = vgui.Create("DPanel", parent)
    button:Dock(TOP)
    button:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin)
    button:SetTall(theme.Sizes.ButtonHeight)
    button:SetPaintBackground(false)
    button:SetCursor("hand")

    local function GetSettingValue()
        if RARELOAD and RARELOAD.settings and settingKey then
            return RARELOAD.settings[settingKey] == true
        end
        return false
    end

    button.IsEnabled = GetSettingValue()
    button.ButtonText = text
    button.ButtonFont = "RareloadUI.Button"

    button.Hovered = false
    button.Pressed = false
    button.HoverFraction = 0
    button.PressFraction = 0

    button.UpdateTextFit = function(self)
        local width = self:GetWide()
        if width <= 0 then return end

        local currentFont = self.ButtonFont
        surface.SetFont(currentFont)
        local textW, textH = surface.GetTextSize(self.ButtonText or "")

        if not textW or textW <= 0 then return end

        local availableWidth = width - 70

        if textW > availableWidth and availableWidth > 0 then
            local scaleFactor = availableWidth / textW
            local newSize = math.floor(18 * scaleFactor)
            newSize = math.max(10, newSize)

            local fontName = "RareloadUI.ButtonDynamic" .. newSize

            if not RareloadUI.CreatedDynamicFonts then
                RareloadUI.CreatedDynamicFonts = {}
            end

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
            self.ButtonFont = "RareloadUI.Button"
        end
    end

    button.DoClick = function()
        if command then
            RunConsoleCommand(command, button.IsEnabled and "0" or "1")
            timer.Simple(0.2, function()
                button.IsEnabled = GetSettingValue()
                button:InvalidateLayout()
            end)
        end

        local flash = vgui.Create("DPanel", button)
        flash:SetSize(button:GetWide(), button:GetTall())
        flash:SetAlpha(120)
        flash.Paint = function(self, w, h)
            RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, Color(255, 255, 255))
        end
        flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)

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
        if not w or w <= 0 or not h or h <= 0 then return end

        self.HoverFraction = Lerp(FrameTime() * 8, self.HoverFraction, self.Hovered and 1 or 0)
        self.PressFraction = Lerp(FrameTime() * 10, self.PressFraction, self.Pressed and 1 or 0)

        local baseColor = self.IsEnabled and theme.Colors.Accent or theme.Colors.Button.Normal

        local r = baseColor.r + 20 * self.HoverFraction - 15 * self.PressFraction
        local g = baseColor.g + 20 * self.HoverFraction - 15 * self.PressFraction
        local b = baseColor.b + 20 * self.HoverFraction - 15 * self.PressFraction

        local color = Color(r, g, b, baseColor.a)

        RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, color)

        if self.ButtonText and self.ButtonFont then
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

        surface.SetDrawColor(255, 255, 255, 30 + 20 * self.HoverFraction)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    return button
end

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

    frame.Paint = function(self, w, h)
        ---@diagnostic disable-next-line: undefined-field
        Derma_DrawBackgroundBlur(self, self.StartTime or 0)
        RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, theme.Colors.Background)

        RareloadUI.DrawRoundedBox(0, 0, w, 50, theme.Sizes.CornerRadius, theme.Colors.Panel)
        RareloadUI.DrawRoundedBox(0, 0, w, 6, theme.Sizes.CornerRadius, theme.Colors.Accent)

        draw.SimpleText(
            title or "Rareload Settings",
            "RareloadUI.Title",
            15,
            25,
            theme.Colors.Text.Primary,
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER
        )

        RareloadUI.DrawRoundedBox(0, h - 50, w, 50, theme.Sizes.CornerRadius, theme.Colors.Panel)
    end

    ---@class DButton
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

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(0, 50, 0, 50)

    ---@class DScrollBar
    local scrollbar = scroll:GetVBar() --[[@as DScrollBar]]
    ---@diagnostic disable-next-line: undefined-field
    scrollbar:SetWide(8)
    ---@diagnostic disable-next-line: undefined-field
    scrollbar:SetHideButtons(true)

    function scrollbar:Paint(w, h)
        RareloadUI.DrawRoundedBox(0, 0, w, h, w / 2, theme.Colors.Button.Normal)
    end

    ---@diagnostic disable-next-line: undefined-field
    function scrollbar.btnGrip:Paint(w, h)
        RareloadUI.DrawRoundedBox(0, 0, w, h, w / 2, theme.Colors.Accent)
    end

    RareloadUI.LastPanel = frame
    return frame, scroll
end

function RareloadUI.RegisterLanguage()
    language.Add("tool.rareload_tool.name", "Rareload Configuration")
    language.Add("tool.rareload_tool.desc", "Configure the Rareload addon settings.")
    language.Add("tool.rareload_tool.0", "By Noahbds")
    language.Add("tool.rareload_tool.left", "Click to save a respawn position at target location.")
    language.Add("tool.rareload_tool.right", "Click to save a respawn position at your location")
    language.Add("tool.rareload_tool.reload",
        "Reload with the Rareload tool in hand to restore your previous saved position")
end

-- Admin Menu Panel
function RareloadUI.CreateAdminMenu()
    local frame = vgui.Create("DFrame")
    frame:SetSize(800, 600)
    frame:Center()
    frame:SetTitle("Rareload Admin Menu")
    frame:MakePopup()

    local theme = RareloadUI.Theme

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin)

    local tabs = vgui.Create("DPropertySheet", scroll)
    tabs:Dock(FILL)

    -- Admin Management Tab
    local adminPanel = vgui.Create("DPanel")
    adminPanel:Dock(FILL)
    adminPanel:SetPaintBackground(false)

    local adminList = vgui.Create("DListView", adminPanel)
    adminList:Dock(FILL)
    adminList:AddColumn("SteamID")
    adminList:AddColumn("Role")
    adminList:AddColumn("ULX Group")
    adminList:AddColumn("Status")

    -- Populate admin list
    for steamid, level in pairs(RARELOAD.Admin.admins) do
        local role = "user"
        for r, data in pairs(RARELOAD.Admin.roles) do
            if data.level == level then
                role = r
                break
            end
        end

        local ulxGroup = "None"
        if ULib and ULib.ucl then
            local user = ULib.ucl.users[steamid]
            if user then
                ulxGroup = user.group
            end
        end

        local status = "Custom"
        if ULib and ULib.ucl then
            local user = ULib.ucl.users[steamid]
            if user then
                status = "ULX"
            end
        end

        adminList:AddLine(steamid, RARELOAD.Admin.roles[role].name, ulxGroup, status)
    end

    -- Add admin section
    local addAdminPanel = vgui.Create("DPanel", adminPanel)
    addAdminPanel:Dock(TOP)
    addAdminPanel:SetTall(100)
    addAdminPanel:SetPaintBackground(false)

    local steamidEntry = vgui.Create("DTextEntry", addAdminPanel)
    steamidEntry:SetPlaceholderText("SteamID")
    steamidEntry:Dock(TOP)
    steamidEntry:DockMargin(0, 0, 0, 5)

    local roleCombo = vgui.Create("DComboBox", addAdminPanel)
    roleCombo:Dock(TOP)
    roleCombo:DockMargin(0, 0, 0, 5)
    for role, data in pairs(RARELOAD.Admin.roles) do
        roleCombo:AddChoice(data.name, role)
    end

    local addButton = RareloadUI.CreateButton(addAdminPanel, "Add Admin", nil, "Add new admin")
    addButton:Dock(TOP)
    addButton.DoClick = function()
        local steamid = steamidEntry:GetValue()
        local _, role = roleCombo:GetSelected()

        if not steamid or steamid == "" then
            chat.AddText(Color(255, 0, 0), "[RARELOAD] Please enter a SteamID")
            return
        end

        if RARELOAD.Admin.AddAdmin(steamid, role) then
            adminList:AddLine(steamid, RARELOAD.Admin.roles[role].name, "None", "Custom")
            chat.AddText(Color(0, 255, 0), "[RARELOAD] Admin added successfully")
        else
            chat.AddText(Color(255, 0, 0), "[RARELOAD] Failed to add admin")
        end
    end

    -- Admin actions
    local actionPanel = vgui.Create("DPanel", adminPanel)
    actionPanel:Dock(TOP)
    actionPanel:SetTall(40)
    actionPanel:SetPaintBackground(false)

    local removeButton = RareloadUI.CreateButton(actionPanel, "Remove Selected", nil, "Remove selected admin")
    removeButton:Dock(LEFT)
    removeButton:DockMargin(0, 0, 10, 0)
    removeButton:SetWide(150)
    removeButton.DoClick = function()
        local selected = adminList:GetSelected()
        if selected and selected[1] then
            local steamid = selected[1]:GetColumnText(1)
            if RARELOAD.Admin.RemoveAdmin(steamid) then
                adminList:RemoveLine(adminList:GetSelected()[1]:GetID())
                chat.AddText(Color(0, 255, 0), "[RARELOAD] Admin removed successfully")
            else
                chat.AddText(Color(255, 0, 0), "[RARELOAD] Failed to remove admin")
            end
        end
    end

    local updateButton = RareloadUI.CreateButton(actionPanel, "Update Role", nil, "Update admin role")
    updateButton:Dock(LEFT)
    updateButton:SetWide(150)
    updateButton.DoClick = function()
        local selected = adminList:GetSelected()
        if selected and selected[1] then
            local steamid = selected[1]:GetColumnText(1)
            local roleCombo = vgui.Create("DComboBox")
            for role, data in pairs(RARELOAD.Admin.roles) do
                roleCombo:AddChoice(data.name, role)
            end
            roleCombo.OnSelect = function(_, _, role)
                if RARELOAD.Admin.UpdateAdminRole(steamid, role) then
                    selected[1]:SetColumnText(2, RARELOAD.Admin.roles[role].name)
                    chat.AddText(Color(0, 255, 0), "[RARELOAD] Admin role updated successfully")
                else
                    chat.AddText(Color(255, 0, 0), "[RARELOAD] Failed to update admin role")
                end
            end
            roleCombo:OpenMenu()
        end
    end

    tabs:AddSheet("Admin Management", adminPanel, "icon16/shield.png")

    -- Roles Tab
    local rolesPanel = vgui.Create("DPanel")
    rolesPanel:Dock(FILL)
    rolesPanel:SetPaintBackground(false)

    local rolesList = vgui.Create("DListView", rolesPanel)
    rolesList:Dock(FILL)
    rolesList:AddColumn("Role")
    rolesList:AddColumn("Level")
    rolesList:AddColumn("Permissions")

    for role, data in pairs(RARELOAD.Admin.roles) do
        local permissions = data.permissions == "*" and "All" or table.Count(data.permissions)
        rolesList:AddLine(data.name, RARELOAD.Admin.PermissionNames[data.level], permissions)
    end

    tabs:AddSheet("Roles", rolesPanel, "icon16/group.png")

    -- Commands Tab
    local commandsPanel = vgui.Create("DPanel")
    commandsPanel:Dock(FILL)
    commandsPanel:SetPaintBackground(false)

    local commandsList = vgui.Create("DListView", commandsPanel)
    commandsList:Dock(FILL)
    commandsList:AddColumn("Command")
    commandsList:AddColumn("Category")
    commandsList:AddColumn("Permission")
    commandsList:AddColumn("Description")

    for cmd, data in pairs(RARELOAD.Admin.Commands) do
        commandsList:AddLine(cmd, data.category, data.permission, data.description)
    end

    tabs:AddSheet("Commands", commandsPanel, "icon16/script.png")

    -- Player Management Tab
    local playerPanel = vgui.Create("DPanel")
    playerPanel:Dock(FILL)
    playerPanel:SetPaintBackground(false)

    local playerList = vgui.Create("DListView", playerPanel)
    playerList:Dock(FILL)
    playerList:AddColumn("Player")
    playerList:AddColumn("SteamID")
    playerList:AddColumn("Role")
    playerList:AddColumn("ULX Group")

    for _, ply in ipairs(player.GetAll()) do
        local role = RARELOAD.Admin.GetPlayerRole(ply)
        local ulxGroup = "None"
        if ULib and ULib.ucl then
            local user = ULib.ucl.users[ply:SteamID()]
            if user then
                ulxGroup = user.group
            end
        end

        playerList:AddLine(ply:Nick(), ply:SteamID(), RARELOAD.Admin.roles[role].name, ulxGroup)
    end

    -- Player management buttons
    local playerButtonPanel = vgui.Create("DPanel", playerPanel)
    playerButtonPanel:Dock(TOP)
    playerButtonPanel:DockMargin(0, 0, 0, theme.Sizes.Margin)
    playerButtonPanel:SetTall(40)
    playerButtonPanel:SetPaintBackground(false)

    local respawnButton = RareloadUI.CreateButton(playerButtonPanel, "Force Respawn", nil,
        "Force selected player to respawn")
    respawnButton:Dock(LEFT)
    respawnButton:DockMargin(0, 0, 10, 0)
    respawnButton:SetWide(150)
    respawnButton.DoClick = function()
        local selected = playerList:GetSelected()
        if selected and selected[1] then
            local steamid = selected[1]:GetColumnText(2)
            local target = player.GetBySteamID(steamid)
            if IsValid(target) and RARELOAD.Admin.HasPermission(LocalPlayer(), "respawn_override") then
                RunConsoleCommand("rareload_respawn_force", steamid)
            end
        end
    end

    local inventoryButton = RareloadUI.CreateButton(playerButtonPanel, "Clear Inventory", nil,
        "Clear selected player's inventory")
    inventoryButton:Dock(LEFT)
    inventoryButton:SetWide(150)
    inventoryButton.DoClick = function()
        local selected = playerList:GetSelected()
        if selected and selected[1] then
            local steamid = selected[1]:GetColumnText(2)
            local target = player.GetBySteamID(steamid)
            if IsValid(target) and RARELOAD.Admin.HasPermission(LocalPlayer(), "inventory_clear") then
                RunConsoleCommand("rareload_inventory_clear", steamid)
            end
        end
    end

    tabs:AddSheet("Player Management", playerPanel, "icon16/user.png")

    -- Features Tab
    local featuresPanel = vgui.Create("DPanel")
    featuresPanel:Dock(FILL)
    featuresPanel:SetPaintBackground(false)

    local featuresList = vgui.Create("DListView", featuresPanel)
    featuresList:Dock(FILL)
    featuresList:AddColumn("Category")
    featuresList:AddColumn("Feature")
    featuresList:AddColumn("Required Role")

    local categories = RARELOAD.Admin.GetFeaturesByCategory()
    for category, features in pairs(categories) do
        for feature, data in pairs(features) do
            local requiredRole = "None"
            for role, roleData in pairs(RARELOAD.Admin.roles) do
                if roleData.permissions == "*" or table.HasValue(roleData.permissions, feature) then
                    requiredRole = roleData.name
                    break
                end
            end
            featuresList:AddLine(category, data.name, requiredRole)
        end
    end

    tabs:AddSheet("Features", featuresPanel, "icon16/cog.png")

    -- Save changes button
    local saveButton = RareloadUI.CreateButton(scroll, "Save Changes", nil, "Save admin changes to disk")
    saveButton.DoClick = function()
        RARELOAD.Admin.SaveAdmins()
        RARELOAD.Admin.SaveRoles()
        chat.AddText(Color(0, 255, 0), "[RARELOAD] Admin changes saved successfully!")
    end

    return frame
end

-- Hook the admin menu concommand to open the admin menu
concommand.Add("rareload_admin_menu", function(ply)
    if not IsValid(ply) or not RARELOAD.Admin.HasPermission(ply, "admin_menu") then return end
    RareloadUI.CreateAdminMenu()
end)

return RareloadUI
