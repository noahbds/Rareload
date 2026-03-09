local RareloadUI = {}

RARELOAD = RARELOAD or {}

if SERVER then
    RareloadUI.Theme = {}
    return RareloadUI
end

RARELOAD.Theme = RARELOAD.Theme or {}

if not RARELOAD.Theme.BuildMainTheme then
    include("rareload/client/shared/theme_utils.lua")
end

local DEFAULT_THEME = {
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

local function GetTheme()
    if RARELOAD.Theme and RARELOAD.Theme.BuildMainTheme then
        return RARELOAD.Theme.BuildMainTheme()
    end
    return DEFAULT_THEME
end

RareloadUI.Theme = GetTheme()
RareloadUI.CreatedDynamicFonts = {}

if RARELOAD.Theme and RARELOAD.Theme.OnChanged then
    RARELOAD.Theme.OnChanged("ui_main", function()
        RareloadUI.Theme = RARELOAD.Theme.BuildMainTheme()
    end)
end

function RARELOAD.CheckPermission(ply, permName)
    if ply:IsSuperAdmin() then return true end
    if RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        return RARELOAD.Permissions.HasPermission(ply, permName)
    end
    -- Fallback to permission defaults if HasPermission is not loaded yet
    if RARELOAD.Permissions and RARELOAD.Permissions.DEFS and RARELOAD.Permissions.DEFS[permName] then
        return RARELOAD.Permissions.DEFS[permName].default
    end
    return false
end

local function AnimateLerp(current, target, speed)
    return Lerp(FrameTime() * (speed or 10), current, target)
end

local function SendConVarToServer(name, value)
    -- Use new player settings system if available
    if RARELOAD and RARELOAD.UpdatePlayerSetting and RARELOAD.ConVarToSetting then
        local settingKey = RARELOAD.ConVarToSetting[name]
        if settingKey then
            -- Convert value to appropriate type
            local convertedValue
            if value == "0" then
                convertedValue = false
            elseif value == "1" then
                convertedValue = true
            else
                convertedValue = tonumber(value) or value
            end
            
            RARELOAD.UpdatePlayerSetting(settingKey, convertedValue)
            return
        end
    end
    
    -- Fallback to old ConVar system
    if RARELOAD and RARELOAD.SetConVar then
        RARELOAD.SetConVar(name, value)
    else
        net.Start("RareloadSetConVar")
        net.WriteString(name)
        net.WriteString(value)
        net.SendToServer()
    end
end

local function GetConVarValue(name)
    -- Use player settings if available (CLIENT only)
    if CLIENT and RARELOAD and RARELOAD.MySettings and RARELOAD.ConVarToSetting then
        local settingKey = RARELOAD.ConVarToSetting[name]
        if settingKey and RARELOAD.MySettings[settingKey] ~= nil then
            return RARELOAD.MySettings[settingKey]
        end
    end
    
    -- Fallback to ConVar
    local cv = GetConVar(name)
    return cv and cv:GetBool() or false
end

local function GetConVarFloat(name)
    -- Use player settings if available (CLIENT only)
    if CLIENT and RARELOAD and RARELOAD.MySettings and RARELOAD.ConVarToSetting then
        local settingKey = RARELOAD.ConVarToSetting[name]
        if settingKey and RARELOAD.MySettings[settingKey] ~= nil then
            return tonumber(RARELOAD.MySettings[settingKey]) or 0
        end
    end
    
    -- Fallback to ConVar
    local cv = GetConVar(name)
    return cv and cv:GetFloat() or 0
end

function RareloadUI.DrawRoundedBox(x, y, w, h, radius, color)
    draw.RoundedBox(radius, x, y, w, h, color)
end

function RareloadUI.DrawCircle(x, y, radius, segments, color)
    local points = {}
    for i = 0, segments do
        local angle = math.rad((i / segments) * 360)
        points[#points + 1] = {
            x = x + math.cos(angle) * radius,
            y = y + math.sin(angle) * radius
        }
    end

    if color then
        if istable(color) and color.r then
            surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
        elseif isnumber(color) then
            surface.SetDrawColor(color, color, color, 255)
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

local function CreateBasePanel(parent, height, margin)
    local theme = RareloadUI.Theme
    margin = margin or theme.Sizes.Margin
    
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(TOP)
    panel:DockMargin(margin, margin, margin, margin)
    panel:SetTall(height)
    panel:SetPaintBackground(false)
    panel.HoverFraction = 0
    panel.PressFraction = 0
    
    return panel
end

local function SetupButtonBehavior(panel)
    panel:SetCursor("hand")
    panel.Hovered = false
    panel.Pressed = false
    
    panel.OnCursorEntered = function(self)
        self.Hovered = true
        surface.PlaySound("ui/buttonrollover.wav")
    end
    
    panel.OnCursorExited = function(self)
        self.Hovered = false
        self.Pressed = false
    end
    
    panel.OnMousePressed = function(self)
        self.Pressed = true
    end
    
    panel.OnMouseReleased = function(self)
        if self.Pressed and self.Hovered and self.DoClick then
            self:DoClick()
        end
        self.Pressed = false
    end
end

local function CreateFlashEffect(parent, radius)
    local theme = RareloadUI.Theme
    local flash = vgui.Create("DPanel", parent)
    flash:SetSize(parent:GetWide(), parent:GetTall())
    flash:SetAlpha(120)
    flash.Paint = function(self, w, h)
        RareloadUI.DrawRoundedBox(0, 0, w, h, radius or theme.Sizes.CornerRadius, Color(255, 255, 255))
    end
    flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)
    surface.PlaySound("ui/buttonclickrelease.wav")
end

local function CalculateButtonColor(baseColor, hoverFrac, pressFrac)
    return Color(
        baseColor.r + 20 * hoverFrac - 15 * pressFrac,
        baseColor.g + 20 * hoverFrac - 15 * pressFrac,
        baseColor.b + 20 * hoverFrac - 15 * pressFrac,
        baseColor.a or 255
    )
end

function RareloadUI.CreateToggle(parent, text, description, command, initialState, callback)
    local theme = RareloadUI.Theme
    local height = description and 70 or 50
    local toggle = CreateBasePanel(parent, height)
    toggle.Enabled = initialState or false
    toggle.Fraction = toggle.Enabled and 1 or 0

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
        local trackW, trackH = 46, 22
        local trackX = w - trackW - 10
        local trackY = (h - trackH) / 2
        
        self.Fraction = AnimateLerp(self.Fraction, self.Enabled and 1 or 0)
        self.HoverFraction = AnimateLerp(self.HoverFraction, self:IsHovered() and 1 or 0, 8)
        
        local trackColor = self.Enabled and theme.Colors.Accent or theme.Colors.Button.Normal
        RareloadUI.DrawRoundedBox(trackX, trackY, trackW, trackH, trackH / 2, trackColor)
        
        local knobSize = trackH - 6
        local knobX = trackX + 3 + (trackW - knobSize - 6) * self.Fraction
        local knobY = trackY + 3
        
        if self.HoverFraction > 0 then
            RareloadUI.DrawCircle(knobX + knobSize / 2, knobY + knobSize / 2, knobSize / 2 + 4 * self.HoverFraction, 20, ColorAlpha(theme.Colors.Text.Primary, 20 * self.HoverFraction))
        end
        
        RareloadUI.DrawCircle(knobX + knobSize / 2, knobY + knobSize / 2, knobSize / 2, 20, theme.Colors.Text.Primary)
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
    local height = description and 90 or 70
    local slider = CreateBasePanel(parent, height, theme.Sizes.Margin)
    slider:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin * 1.5)
    
    slider.Min = min or 0
    slider.Max = max or 100
    slider.Value = defaultValue or min or 0
    slider.Decimals = decimals or 0
    slider.Unit = unit or ""
    slider.Dragging = false

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
    valueDisplay:SetWide(65)
    valueDisplay:SetFont("RareloadUI.Text")
    valueDisplay:SetTextColor(theme.Colors.Text.Primary)

    local function UpdateValueDisplay()
        local format = slider.Decimals > 0 and "%." .. slider.Decimals .. "f%s" or "%d%s"
        valueDisplay:SetText(string.format(format, slider.Value, slider.Unit))
    end
    UpdateValueDisplay()

    local track = vgui.Create("DPanel", slider)
    track:Dock(BOTTOM)
    track:DockMargin(0, 5, 70, 5)
    track:SetTall(theme.Sizes.SliderHeight + 20)
    track:SetPaintBackground(false)

    local function UpdateSliderValue(x, width)
        local fraction = math.Clamp((x - theme.Sizes.KnobSize / 2) / (width - theme.Sizes.KnobSize), 0, 1)
        slider.Value = slider.Min + (slider.Max - slider.Min) * fraction
        
        if slider.Decimals > 0 then
            local mult = 10 ^ slider.Decimals
            slider.Value = math.Round(slider.Value * mult) / mult
        else
            slider.Value = math.Round(slider.Value)
        end
        
        UpdateValueDisplay()
        RunConsoleCommand(command, slider.Value)
    end

    track.OnCursorMoved = function(self, x)
        if slider.Dragging then
            UpdateSliderValue(x, self:GetWide())
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
        RareloadUI.DrawRoundedBox(0, trackY, knobX + knobSize / 2, trackHeight, trackHeight / 2, theme.Colors.Slider.Groove)

        slider.HoverFraction = AnimateLerp(slider.HoverFraction, (self:IsHovered() or slider.Dragging) and 1 or 0, 8)
        
        if slider.HoverFraction > 0 then
            RareloadUI.DrawCircle(knobX + knobSize / 2, trackY + trackHeight / 2, knobSize / 2 + 4 * slider.HoverFraction, 20, ColorAlpha(theme.Colors.Accent, 40 * slider.HoverFraction))
        end
        
        RareloadUI.DrawCircle(knobX + knobSize / 2, trackY + trackHeight / 2, knobSize / 2, 20, slider.Dragging and theme.Colors.Slider.KnobHover or theme.Colors.Slider.Knob)

        for i = 0, 5 do
            local notchX = (i / 5) * (w - knobSize) + knobSize / 2
            surface.SetDrawColor(theme.Colors.Text.Disabled)
            surface.DrawLine(notchX, trackY + trackHeight + 3, notchX, trackY + trackHeight + 6)
        end
    end

    return slider
end

function RareloadUI.CreateActionButton(parent, text, command)
    local theme = RareloadUI.Theme
    local button = CreateBasePanel(parent, theme.Sizes.ButtonHeight)
    SetupButtonBehavior(button)

    button.DoClick = function()
        if command then RunConsoleCommand(command) end
        CreateFlashEffect(button)
    end

    button.Paint = function(self, w, h)
        self.HoverFraction = AnimateLerp(self.HoverFraction, self.Hovered and 1 or 0, 8)
        self.PressFraction = AnimateLerp(self.PressFraction, self.Pressed and 1 or 0)
        
        local color = CalculateButtonColor(theme.Colors.Success, self.HoverFraction, self.PressFraction)
        RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, color)
        
        draw.SimpleText(text, "RareloadUI.Button", w / 2, h / 2 + self.PressFraction, theme.Colors.Text.Primary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        
        surface.SetDrawColor(255, 255, 255, 30 + 20 * self.HoverFraction)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    return button
end

function RareloadUI.CreateButton(parent, text, command, description, settingKey, primary)
    local theme = RareloadUI.Theme
    local button = CreateBasePanel(parent, theme.Sizes.ButtonHeight)
    SetupButtonBehavior(button)

    local function GetSettingValue()
        return RARELOAD and RARELOAD.settings and settingKey and RARELOAD.settings[settingKey] == true
    end

    button.IsEnabled = GetSettingValue()
    button.ButtonText = text
    button.ButtonFont = "RareloadUI.Button"

    button.UpdateTextFit = function(self)
        local width = self:GetWide()
        if width <= 0 then return end
        
        surface.SetFont(self.ButtonFont)
        local textW = surface.GetTextSize(self.ButtonText or "")
        if not textW or textW <= 0 then return end
        
        local availableWidth = width - 70
        if textW > availableWidth and availableWidth > 0 then
            local newSize = math.max(10, math.floor(18 * availableWidth / textW))
            local fontName = "RareloadUI.ButtonDynamic" .. newSize
            
            if not RareloadUI.CreatedDynamicFonts[fontName] then
                surface.CreateFont(fontName, { font = "Segoe UI", size = newSize, weight = 600, antialias = true })
                RareloadUI.CreatedDynamicFonts[fontName] = true
            end
            self.ButtonFont = fontName
        else
            self.ButtonFont = "RareloadUI.Button"
        end
    end

    button.DoClick = function()
        local ply = LocalPlayer()
        if not RARELOAD.CheckPermission(ply, "RARELOAD_TOGGLE") then
            ply:ChatPrint("[RARELOAD] You don't have permission to toggle settings.")
            surface.PlaySound("buttons/button10.wav")
            return
        end
        
        if command then
            RunConsoleCommand(command, button.IsEnabled and "0" or "1")
            timer.Simple(0.2, function()
                button.IsEnabled = GetSettingValue()
                button:InvalidateLayout()
            end)
        end
        CreateFlashEffect(button)
    end

    button.Think = function(self)
        local current = GetSettingValue()
        if self.IsEnabled ~= current then
            self.IsEnabled = current
            self:InvalidateLayout()
        end
    end

    button.PerformLayout = function(self)
        self:UpdateTextFit()
    end

    button.Paint = function(self, w, h)
        if w <= 0 or h <= 0 then return end
        
        self.HoverFraction = AnimateLerp(self.HoverFraction, self.Hovered and 1 or 0, 8)
        self.PressFraction = AnimateLerp(self.PressFraction, self.Pressed and 1 or 0)
        
        local baseColor = self.IsEnabled and theme.Colors.Accent or theme.Colors.Button.Normal
        local color = CalculateButtonColor(baseColor, self.HoverFraction, self.PressFraction)
        
        RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, color)
        
        if self.ButtonText and self.ButtonFont then
            draw.SimpleText(self.ButtonText, self.ButtonFont, w / 2, h / 2 + self.PressFraction, theme.Colors.Text.Primary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        draw.SimpleText(self.IsEnabled and "ON" or "OFF", "RareloadUI.Small", w - 15, h / 2 + self.PressFraction, theme.Colors.Text.Primary, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        
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
    separator.Paint = function(self, w)
        surface.SetDrawColor(theme.Colors.Separator)
        surface.DrawRect(0, 0, w, 1)
    end
    return separator
end

function RareloadUI.CreateCategory(parent, title, icon, defaultExpanded)
    local theme = RareloadUI.Theme
    defaultExpanded = defaultExpanded ~= false
    
    local iconMat = icon and Material(icon, "smooth mips") or nil
    
    local container = vgui.Create("DPanel", parent)
    container:Dock(TOP)
    container:DockMargin(5, 5, 5, 2)
    container:SetPaintBackground(false)
    container.IsExpanded = defaultExpanded
    container.CurrentHeight = defaultExpanded and 1000 or 0
    
    local header = vgui.Create("DButton", container)
    header:Dock(TOP)
    header:SetTall(36)
    header:SetText("")
    header.HoverFraction = 0
    header.ArrowRotation = defaultExpanded and 0 or -90
    
    header.Paint = function(self, w, h)
        self.HoverFraction = AnimateLerp(self.HoverFraction, self:IsHovered() and 1 or 0)
        self.ArrowRotation = AnimateLerp(self.ArrowRotation, container.IsExpanded and 0 or -90, 12)
        
        local bgColor = Color(45 + 10 * self.HoverFraction, 50 + 10 * self.HoverFraction, 60 + 10 * self.HoverFraction, 255)
        RareloadUI.DrawRoundedBox(0, 0, w, h, 6, bgColor)
        
        surface.SetDrawColor(theme.Colors.Accent.r, theme.Colors.Accent.g, theme.Colors.Accent.b, 200)
        surface.DrawRect(0, 4, 3, h - 8)
        
        local textOffset = 14
        if iconMat and not iconMat:IsError() then
            surface.SetDrawColor(theme.Colors.Accent)
            surface.SetMaterial(iconMat)
            surface.DrawTexturedRect(10, h / 2 - 8, 16, 16)
            textOffset = 32
        end
        
        draw.SimpleText(title, "RareloadUI.Text", textOffset, h / 2, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        
        local arrowX, arrowY = w - 20, h / 2
        local matrix = Matrix()
        matrix:Translate(Vector(arrowX, arrowY, 0))
        matrix:Rotate(Angle(0, self.ArrowRotation, 0))
        matrix:Translate(Vector(-arrowX, -arrowY, 0))
        cam.PushModelMatrix(matrix)
        draw.SimpleText("▼", "RareloadUI.Small", arrowX, arrowY, theme.Colors.Text.Secondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        cam.PopModelMatrix()
    end
    
    local content = vgui.Create("DPanel", container)
    content:Dock(TOP)
    content:DockMargin(8, 4, 8, 4)
    content:SetPaintBackground(false)
    content.Items = {}
    
    header.DoClick = function()
        container.IsExpanded = not container.IsExpanded
        surface.PlaySound("ui/buttonclick.wav")
    end
    
    container.Think = function(self)
        local targetH = 0
        if self.IsExpanded then
            for _, item in ipairs(content.Items) do
                if IsValid(item) then
                    local _, top, _, bottom = item:GetDockMargin()
                    targetH = targetH + item:GetTall() + top + bottom
                end
            end
            targetH = targetH + 8
        end
        
        self.CurrentHeight = AnimateLerp(self.CurrentHeight, targetH, 15)
        content:SetTall(math.max(0, self.CurrentHeight))
        self:SetTall(36 + math.max(0, self.CurrentHeight))
        self:InvalidateParent(true)
    end
    
    container.Content = content
    container.AddItem = function(self, item)
        content.Items[#content.Items + 1] = item
    end
    
    return container
end

function RareloadUI.CreateToggleSwitch(parent, label, convar, tooltip)
    local theme = RareloadUI.Theme
    
    local container = vgui.Create("DPanel", parent)
    container:Dock(TOP)
    container:DockMargin(0, 2, 0, 2)
    container:SetTall(28)
    container:SetPaintBackground(false)
    container.ConVarName = convar
    container.IsEnabled = GetConVarValue(convar)
    container.SwitchFraction = container.IsEnabled and 1 or 0
    container.HoverFraction = 0
    
    container.OnCursorEntered = function(self) self.Hovered = true end
    container.OnCursorExited = function(self) self.Hovered = false end
    
    container.Think = function(self)
        local current = GetConVarValue(self.ConVarName)
        if self.IsEnabled ~= current then
            self.IsEnabled = current
        end
        self.HoverFraction = AnimateLerp(self.HoverFraction, self.Hovered and 1 or 0)
        self.SwitchFraction = AnimateLerp(self.SwitchFraction, self.IsEnabled and 1 or 0)
    end
    
    container.Paint = function(self, w, h)
        if self.HoverFraction > 0.01 then
            RareloadUI.DrawRoundedBox(0, 0, w, h, 4, Color(255, 255, 255, 10 * self.HoverFraction))
        end
        
        draw.SimpleText(label, "RareloadUI.Small", 8, h / 2, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        
        local switchW, switchH = 36, 18
        local switchX = w - switchW - 8
        local switchY = (h - switchH) / 2
        
        local trackColor = Color(
            Lerp(self.SwitchFraction, 60, theme.Colors.Accent.r),
            Lerp(self.SwitchFraction, 65, theme.Colors.Accent.g),
            Lerp(self.SwitchFraction, 75, theme.Colors.Accent.b),
            255
        )
        RareloadUI.DrawRoundedBox(switchX, switchY, switchW, switchH, switchH / 2, trackColor)
        
        local knobSize = switchH - 4
        local knobX = switchX + 2 + (switchW - knobSize - 4) * self.SwitchFraction
        RareloadUI.DrawRoundedBox(knobX, switchY + 2, knobSize, knobSize, knobSize / 2, Color(255, 255, 255))
    end
    
    container.OnMousePressed = function(self, keyCode)
        if keyCode == MOUSE_LEFT then
            SendConVarToServer(self.ConVarName, self.IsEnabled and "0" or "1")
            surface.PlaySound("ui/buttonclick.wav")
        end
    end
    
    if tooltip then container:SetTooltip(tooltip) end
    return container
end

function RareloadUI.CreateCompactSlider(parent, label, tooltip, convarName, minVal, maxVal, decimals, defaultVal, suffix)
    local theme = RareloadUI.Theme
    suffix = suffix or ""
    decimals = decimals or 0
    
    local container = vgui.Create("DPanel", parent)
    container:Dock(TOP)
    container:DockMargin(0, 4, 0, 4)
    container:SetTall(44)
    container:SetPaintBackground(false)
    container.ConVarName = convarName
    container.Value = GetConVarFloat(convarName) or defaultVal or minVal
    container.DragFraction = (container.Value - minVal) / (maxVal - minVal)
    container.IsDragging = false
    container.HoverFraction = 0
    
    container.OnCursorEntered = function(self) self.Hovered = true end
    container.OnCursorExited = function(self) self.Hovered = false end
    
    container.Think = function(self)
        self.HoverFraction = AnimateLerp(self.HoverFraction, self.Hovered and 1 or 0)
        
        if not self.IsDragging then
            local serverVal = GetConVarFloat(self.ConVarName)
            if math.abs(serverVal - self.Value) > 0.01 then
                self.Value = serverVal
                self.DragFraction = (self.Value - minVal) / (maxVal - minVal)
            end
        end
        
        if self.IsDragging then
            local x = self:CursorPos()
            local sliderX, sliderW = 8, self:GetWide() - 16
            local frac = math.Clamp((x - sliderX) / sliderW, 0, 1)
            self.DragFraction = frac
            
            local newVal = minVal + frac * (maxVal - minVal)
            self.Value = decimals == 0 and math.Round(newVal) or math.Round(newVal * (10 ^ decimals)) / (10 ^ decimals)
        end
    end
    
    container.Paint = function(self, w, h)
        if self.HoverFraction > 0.01 then
            RareloadUI.DrawRoundedBox(0, 0, w, h, 4, Color(255, 255, 255, 8 * self.HoverFraction))
        end
        
        draw.SimpleText(label, "RareloadUI.Small", 8, 10, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(self.Value) .. suffix, "RareloadUI.Small", w - 8, 10, theme.Colors.Accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        
        local trackH, trackY, trackX, trackW = 6, h - 14, 8, w - 16
        RareloadUI.DrawRoundedBox(trackX, trackY, trackW, trackH, 3, Color(50, 55, 65))
        
        local fillW = trackW * self.DragFraction
        if fillW > 0 then
            RareloadUI.DrawRoundedBox(trackX, trackY, fillW, trackH, 3, theme.Colors.Accent)
        end
        
        local knobSize = 12
        RareloadUI.DrawRoundedBox(trackX + fillW - knobSize / 2, trackY + trackH / 2 - knobSize / 2, knobSize, knobSize, knobSize / 2, Color(255, 255, 255))
    end
    
    container.OnMousePressed = function(self, keyCode)
        if keyCode == MOUSE_LEFT then
            self.IsDragging = true
            self:MouseCapture(true)
        end
    end
    
    container.OnMouseReleased = function(self, keyCode)
        if keyCode == MOUSE_LEFT then
            self.IsDragging = false
            self:MouseCapture(false)
            SendConVarToServer(self.ConVarName, tostring(self.Value))
        end
    end
    
    if tooltip then container:SetTooltip(tooltip) end
    return container
end

function RareloadUI.CreateModernButton(parent, text, icon, onClick, accentColor)
    local theme = RareloadUI.Theme
    accentColor = accentColor or theme.Colors.Accent
    local iconMat = icon and Material(icon, "smooth mips") or nil
    
    local btn = vgui.Create("DButton", parent)
    btn:Dock(TOP)
    btn:DockMargin(0, 4, 0, 4)
    btn:SetTall(32)
    btn:SetText("")
    btn.HoverFraction = 0
    btn.PressFraction = 0
    
    btn.Paint = function(self, w, h)
        self.HoverFraction = AnimateLerp(self.HoverFraction, self:IsHovered() and 1 or 0)
        self.PressFraction = AnimateLerp(self.PressFraction, self:IsDown() and 1 or 0, 15)
        
        local bgColor = Color(
            accentColor.r - 30 + 20 * self.HoverFraction - 10 * self.PressFraction,
            accentColor.g - 30 + 20 * self.HoverFraction - 10 * self.PressFraction,
            accentColor.b - 30 + 20 * self.HoverFraction - 10 * self.PressFraction,
            200 + 55 * self.HoverFraction
        )
        
        RareloadUI.DrawRoundedBox(0, 0, w, h, 6, bgColor)
        
        if self.HoverFraction > 0.01 then
            surface.SetDrawColor(accentColor.r, accentColor.g, accentColor.b, 100 * self.HoverFraction)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        
        local textX = w / 2
        if iconMat and not iconMat:IsError() then
            surface.SetDrawColor(255, 255, 255)
            surface.SetMaterial(iconMat)
            surface.DrawTexturedRect(12, h / 2 - 8 + self.PressFraction, 16, 16)
            textX = w / 2 + 10
        end
        
        draw.SimpleText(text, "RareloadUI.Small", textX, h / 2 + self.PressFraction, theme.Colors.Text.Primary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    
    btn.DoClick = function()
        surface.PlaySound("ui/buttonclick.wav")
        if onClick then onClick() end
    end
    
    return btn
end

function RareloadUI.CreateInfoText(parent, text)
    local theme = RareloadUI.Theme
    local label = vgui.Create("DLabel", parent)
    label:Dock(TOP)
    label:DockMargin(8, 2, 8, 6)
    label:SetText(text)
    label:SetFont("RareloadUI.Small")
    label:SetTextColor(theme.Colors.Text.Secondary)
    label:SetWrap(true)
    label:SetAutoStretchVertical(true)
    return label
end

function RareloadUI.CreateHeader(parent, text)
    local theme = RareloadUI.Theme
    local header = vgui.Create("DPanel", parent)
    header:Dock(TOP)
    header:DockMargin(theme.Sizes.Margin, theme.Sizes.Margin, theme.Sizes.Margin, 0)
    header:SetTall(40)
    header:SetPaintBackground(false)
    header.Paint = function(self, w, h)
        draw.SimpleText(text, "RareloadUI.Title", 0, h / 2, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return header
end

function RareloadUI.CreatePanel(title)
    if RARELOAD and RARELOAD.RegisterFonts then
        pcall(RARELOAD.RegisterFonts)
    end

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
        Derma_DrawBackgroundBlur(self, self.StartTime or 0)
        RareloadUI.DrawRoundedBox(0, 0, w, h, theme.Sizes.CornerRadius, theme.Colors.Background)
        RareloadUI.DrawRoundedBox(0, 0, w, 50, theme.Sizes.CornerRadius, theme.Colors.Panel)
        RareloadUI.DrawRoundedBox(0, 0, w, 6, theme.Sizes.CornerRadius, theme.Colors.Accent)
        draw.SimpleText(title or "Rareload Settings", "RareloadUI.Title", 15, 25, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        RareloadUI.DrawRoundedBox(0, h - 50, w, 50, theme.Sizes.CornerRadius, theme.Colors.Panel)
    end

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
    
    local scrollbar = scroll:GetVBar()
    if IsValid(scrollbar) then
        if scrollbar.SetWide then scrollbar:SetWide(8) end
        if scrollbar.SetHideButtons then scrollbar:SetHideButtons(true) end
        scrollbar.Paint = function(self, w, h)
            RareloadUI.DrawRoundedBox(0, 0, w, h, w / 2, theme.Colors.Button.Normal)
        end
    end

    local canvas = scroll.GetCanvas and scroll:GetCanvas()
    if IsValid(canvas) and not canvas.OnMouseWheeled then
        canvas.OnMouseWheeled = function(self, delta)
            local parent = self:GetParent()
            if IsValid(parent) and parent.OnMouseWheeled then
                return parent:OnMouseWheeled(delta)
            end
        end
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
    language.Add("tool.rareload_tool.reload", "Reload with the Rareload tool in hand to restore your previous saved position")
end

return RareloadUI
