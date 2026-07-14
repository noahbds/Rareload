-- NEED TO REFACTOR: This file is getting too long and complex. Split into multiple files and modules.

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

RareloadUI.Theme = RARELOAD.Theme.BuildMainTheme()

RareloadUI.CreatedDynamicFonts = {}

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
    if not (RARELOAD and RARELOAD.UpdatePlayerSetting and RARELOAD.ConVarToSetting) then return end

    local settingKey = RARELOAD.ConVarToSetting[name]
    if not settingKey then return end

    local isBool = RARELOAD.ConVarIsBool[name]

    local convertedValue
    if isBool then
        convertedValue = (value == true or value == "1" or value == "true")
    else
        convertedValue = tonumber(value) or value
    end

    RARELOAD.UpdatePlayerSetting(settingKey, convertedValue)
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

function RareloadUI.CreateCategory(parent, title, icon, defaultExpanded)
    local theme = RareloadUI.Theme
    defaultExpanded = defaultExpanded ~= false

    local iconMat = icon and Material(icon, "smooth mips") or nil

    local container = vgui.Create("DPanel", parent)
    container:Dock(TOP)
    container:DockMargin(5, 5, 5, 2)
    container:SetPaintBackground(false)
    container.IsExpanded = defaultExpanded
    container.CurrentHeight = 0

    local header = vgui.Create("DButton", container)
    header:Dock(TOP)
    header:SetTall(36)
    header:SetText("")
    header.HoverFraction = 0
    header.ArrowRotation = defaultExpanded and 0 or -90

    header.Paint = function(self, w, h)
        self.HoverFraction = AnimateLerp(self.HoverFraction, self:IsHovered() and 1 or 0)
        self.ArrowRotation = AnimateLerp(self.ArrowRotation, container.IsExpanded and 0 or -90, 12)

        local bgColor = Color(45 + 10 * self.HoverFraction, 50 + 10 * self.HoverFraction, 60 + 10 * self.HoverFraction,
            255)
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

        draw.SimpleText(title, "RareloadUI.Text", textOffset, h / 2, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        local arrowX, arrowY = w - 20, h / 2
        local matrix = Matrix()
        matrix:Translate(Vector(arrowX, arrowY, 0))
        matrix:Rotate(Angle(0, self.ArrowRotation, 0))
        matrix:Translate(Vector(-arrowX, -arrowY, 0))
        cam.PushModelMatrix(matrix)
        draw.SimpleText("▼", "RareloadUI.Small", arrowX, arrowY, theme.Colors.Text.Secondary, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
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

        if not self._laidOut then
            self._laidOut = true
            self.CurrentHeight = targetH
        else
            self.CurrentHeight = AnimateLerp(self.CurrentHeight, targetH, 15)
            if math.abs(self.CurrentHeight - targetH) < 0.5 then
                self.CurrentHeight = targetH
            end
        end

        local h = math.max(0, self.CurrentHeight)
        if self._appliedHeight == nil or math.abs(h - self._appliedHeight) > 0.05 then
            self._appliedHeight = h
            content:SetTall(h)
            self:SetTall(36 + h)
            self:InvalidateParent(true)
        end
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
    container.Enabled = GetConVarValue(convar)
    container.SwitchFraction = container.Enabled and 1 or 0
    container.HoverFraction = 0

    container.OnCursorEntered = function(self) self.Hovered = true end
    container.OnCursorExited = function(self) self.Hovered = false end

    container.Think = function(self)
        local current = GetConVarValue(self.ConVarName)
        if self.Enabled ~= current then
            self.Enabled = current
        end
        self.HoverFraction = AnimateLerp(self.HoverFraction, self.Hovered and 1 or 0)
        self.SwitchFraction = AnimateLerp(self.SwitchFraction, self.Enabled and 1 or 0)
    end

    container.Paint = function(self, w, h)
        if self.HoverFraction > 0.01 then
            RareloadUI.DrawRoundedBox(0, 0, w, h, 4, Color(255, 255, 255, 10 * self.HoverFraction))
        end

        draw.SimpleText(label, "RareloadUI.Small", 8, h / 2, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

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
            SendConVarToServer(self.ConVarName, self.Enabled and "0" or "1")
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
    container.Dragging = false
    container.HoverFraction = 0

    container.OnCursorEntered = function(self) self.Hovered = true end
    container.OnCursorExited = function(self) self.Hovered = false end

    container.Think = function(self)
        self.HoverFraction = AnimateLerp(self.HoverFraction, self.Hovered and 1 or 0)

        if not self.Dragging then
            local serverVal = GetConVarFloat(self.ConVarName)
            if math.abs(serverVal - self.Value) > 0.01 then
                self.Value = serverVal
                self.DragFraction = (self.Value - minVal) / (maxVal - minVal)
            end
        end

        if self.Dragging then
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
        draw.SimpleText(tostring(self.Value) .. suffix, "RareloadUI.Small", w - 8, 10, theme.Colors.Accent,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        local trackH, trackY, trackX, trackW = 6, h - 14, 8, w - 16
        RareloadUI.DrawRoundedBox(trackX, trackY, trackW, trackH, 3, Color(50, 55, 65))

        local fillW = trackW * self.DragFraction
        if fillW > 0 then
            RareloadUI.DrawRoundedBox(trackX, trackY, fillW, trackH, 3, theme.Colors.Accent)
        end

        local knobSize = 12
        RareloadUI.DrawRoundedBox(trackX + fillW - knobSize / 2, trackY + trackH / 2 - knobSize / 2, knobSize, knobSize,
            knobSize / 2, Color(255, 255, 255))
    end

    container.OnMousePressed = function(self, keyCode)
        if keyCode == MOUSE_LEFT then
            self.Dragging = true
            self:MouseCapture(true)
        end
    end

    container.OnMouseReleased = function(self, keyCode)
        if keyCode == MOUSE_LEFT then
            self.Dragging = false
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

        draw.SimpleText(text, "RareloadUI.Small", textX, h / 2 + self.PressFraction, theme.Colors.Text.Primary,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    btn.DoClick = function()
        surface.PlaySound("ui/buttonclick.wav")
        if onClick then onClick() end
    end

    return btn
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

return RareloadUI
