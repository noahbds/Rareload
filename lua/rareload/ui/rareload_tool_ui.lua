-- Rareload TOOL UI widget library (client) — the spawnmenu tool config panel
-- (categories, toggles, sliders, buttons, dropdowns) and the toolgun screen.
-- Distinct from RARELOAD.UI (client/shared/cl_rareload_ui.lua), which styles the
-- Save Timeline / entity-viewer data panels. Widgets avoid per-frame Color/Matrix
-- allocations: paint hooks write into shared scratch colors instead.

local RareloadToolUI = {}

RARELOAD = RARELOAD or {}

if SERVER then
    RareloadToolUI.Theme = {}
    return RareloadToolUI
end

RARELOAD.Theme = RARELOAD.Theme or {}

if not RARELOAD.Theme.BuildMainTheme then
    include("rareload/client/shared/theme_utils.lua")
end

RareloadToolUI.Theme = RARELOAD.Theme.BuildMainTheme()


local function AnimateLerp(current, target, speed)
    return Lerp(FrameTime() * (speed or 10), current, target)
end

-- Shared scratch color for paint hooks: set + use immediately, never stored.
local scratchColor = Color(0, 0, 0, 255)
local function SetCol(r, g, b, a)
    scratchColor.r, scratchColor.g, scratchColor.b, scratchColor.a = r, g, b, a or 255
    return scratchColor
end

local COL_WHITE     = Color(255, 255, 255)
local COL_TRACK_OFF = Color(50, 55, 65)

-- GetConVar does a name lookup each call; cache the userdata per name.
local convarCache = {}
local function CachedConVar(name)
    local cv = convarCache[name]
    if cv == nil then
        cv = GetConVar(name) or false
        convarCache[name] = cv
    end
    return cv or nil
end

-- Filled triangle arrow centered on (x, y), rotated by `rot` degrees
-- (0 = pointing down). Cheaper than a model matrix push per frame.
local arrowPoly = { {}, {}, {} }
local function DrawArrow(x, y, size, rot, color)
    local a = math.rad(rot)
    local c, s = math.cos(a), math.sin(a)
    local px = { -size, size, 0 }
    local py = { -size * 0.5, -size * 0.5, size * 0.6 }
    for i = 1, 3 do
        arrowPoly[i].x = x + px[i] * c - py[i] * s
        arrowPoly[i].y = y + px[i] * s + py[i] * c
    end
    surface.SetDrawColor(color)
    draw.NoTexture()
    surface.DrawPoly(arrowPoly)
end

local function SendConVarToServer(name, value)
    if not (RARELOAD.UpdatePlayerSetting and RARELOAD.ConVarToSetting) then return end

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
    -- Player-synced settings win over the raw convar when available.
    if RARELOAD.MySettings and RARELOAD.ConVarToSetting then
        local settingKey = RARELOAD.ConVarToSetting[name]
        if settingKey and RARELOAD.MySettings[settingKey] ~= nil then
            return RARELOAD.MySettings[settingKey]
        end
    end

    -- Fallback to ConVar
    local cv = CachedConVar(name)
    return cv and cv:GetBool() or false
end

local function GetConVarFloat(name)
    -- Player-synced settings win over the raw convar when available.
    if RARELOAD.MySettings and RARELOAD.ConVarToSetting then
        local settingKey = RARELOAD.ConVarToSetting[name]
        if settingKey and RARELOAD.MySettings[settingKey] ~= nil then
            return tonumber(RARELOAD.MySettings[settingKey]) or 0
        end
    end

    -- Fallback to ConVar
    local cv = CachedConVar(name)
    return cv and cv:GetFloat() or 0
end

function RareloadToolUI.DrawRoundedBox(x, y, w, h, radius, color)
    draw.RoundedBox(radius, x, y, w, h, color)
end

function RareloadToolUI.DrawCircle(x, y, radius, segments, color)
    local points = {}
    for i = 0, segments do
        local angle = math.rad((i / segments) * 360)
        points[#points + 1] = {
            x = x + math.cos(angle) * radius,
            y = y + math.sin(angle) * radius
        }
    end

    if color then
        surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
    else
        surface.SetDrawColor(255, 255, 255, 255)
    end

    draw.NoTexture()
    surface.DrawPoly(points)
end

function RareloadToolUI.CreateCategory(parent, title, icon, defaultExpanded)
    local theme = RareloadToolUI.Theme
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

        RareloadToolUI.DrawRoundedBox(0, 0, w, h, 6, SetCol(
            45 + 10 * self.HoverFraction,
            50 + 10 * self.HoverFraction,
            60 + 10 * self.HoverFraction))

        surface.SetDrawColor(theme.Colors.Accent.r, theme.Colors.Accent.g, theme.Colors.Accent.b, 200)
        surface.DrawRect(0, 4, 3, h - 8)

        local textOffset = 14
        if iconMat and not iconMat:IsError() then
            surface.SetDrawColor(theme.Colors.Accent)
            surface.SetMaterial(iconMat)
            surface.DrawTexturedRect(10, h / 2 - 8, 16, 16)
            textOffset = 32
        end

        draw.SimpleText(title, "RareloadToolUI.Text", textOffset, h / 2, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        DrawArrow(w - 20, h / 2, 5, self.ArrowRotation, theme.Colors.Text.Secondary)
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

function RareloadToolUI.CreateToggleSwitch(parent, label, convar, tooltip)
    local theme = RareloadToolUI.Theme

    local container = vgui.Create("DPanel", parent)
    container:Dock(TOP)
    container:DockMargin(0, 2, 0, 2)
    container:SetTall(28)
    container:SetPaintBackground(false)
    container.ConVarName = convar
    container.Enabled = GetConVarValue(convar)
    container.SwitchFraction = container.Enabled and 1 or 0
    container.HoverFraction = 0

    container.Think = function(self)
        self.Enabled = GetConVarValue(self.ConVarName)
        self.HoverFraction = AnimateLerp(self.HoverFraction, self:IsHovered() and 1 or 0)
        self.SwitchFraction = AnimateLerp(self.SwitchFraction, self.Enabled and 1 or 0)
    end

    container.Paint = function(self, w, h)
        if self.HoverFraction > 0.01 then
            RareloadToolUI.DrawRoundedBox(0, 0, w, h, 4, SetCol(255, 255, 255, 10 * self.HoverFraction))
        end

        draw.SimpleText(label, "RareloadToolUI.Small", 8, h / 2, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        local switchW, switchH = 36, 18
        local switchX = w - switchW - 8
        local switchY = (h - switchH) / 2

        RareloadToolUI.DrawRoundedBox(switchX, switchY, switchW, switchH, switchH / 2, SetCol(
            Lerp(self.SwitchFraction, 60, theme.Colors.Accent.r),
            Lerp(self.SwitchFraction, 65, theme.Colors.Accent.g),
            Lerp(self.SwitchFraction, 75, theme.Colors.Accent.b)))

        local knobSize = switchH - 4
        local knobX = switchX + 2 + (switchW - knobSize - 4) * self.SwitchFraction
        RareloadToolUI.DrawRoundedBox(knobX, switchY + 2, knobSize, knobSize, knobSize / 2, COL_WHITE)
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

function RareloadToolUI.CreateCompactSlider(parent, label, tooltip, convarName, minVal, maxVal, decimals, defaultVal, suffix)
    local theme = RareloadToolUI.Theme
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

    container.Think = function(self)
        self.HoverFraction = AnimateLerp(self.HoverFraction, self:IsHovered() and 1 or 0)

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
            RareloadToolUI.DrawRoundedBox(0, 0, w, h, 4, SetCol(255, 255, 255, 8 * self.HoverFraction))
        end

        draw.SimpleText(label, "RareloadToolUI.Small", 8, 10, theme.Colors.Text.Primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(self.Value) .. suffix, "RareloadToolUI.Small", w - 8, 10, theme.Colors.Accent,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        local trackH, trackY, trackX, trackW = 6, h - 14, 8, w - 16
        RareloadToolUI.DrawRoundedBox(trackX, trackY, trackW, trackH, 3, COL_TRACK_OFF)

        local fillW = trackW * self.DragFraction
        if fillW > 0 then
            RareloadToolUI.DrawRoundedBox(trackX, trackY, fillW, trackH, 3, theme.Colors.Accent)
        end

        local knobSize = 12
        RareloadToolUI.DrawRoundedBox(trackX + fillW - knobSize / 2, trackY + trackH / 2 - knobSize / 2, knobSize, knobSize,
            knobSize / 2, COL_WHITE)
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

function RareloadToolUI.CreateModernButton(parent, text, icon, onClick, accentColor)
    local theme = RareloadToolUI.Theme
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

        local shade = -30 + 20 * self.HoverFraction - 10 * self.PressFraction
        RareloadToolUI.DrawRoundedBox(0, 0, w, h, 6, SetCol(
            accentColor.r + shade,
            accentColor.g + shade,
            accentColor.b + shade,
            200 + 55 * self.HoverFraction))

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

        draw.SimpleText(text, "RareloadToolUI.Small", textX, h / 2 + self.PressFraction, theme.Colors.Text.Primary,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    btn.DoClick = function()
        surface.PlaySound("ui/buttonclick.wav")
        if onClick then onClick() end
    end

    return btn
end

-- Labeled dropdown row. choices = { { value = ..., text = ... }, ... };
-- onSelect(value) fires when the user picks an entry.
function RareloadToolUI.CreateDropdown(parent, label, tooltip, choices, activeValue, onSelect)
    local theme = RareloadToolUI.Theme

    local container = vgui.Create("DPanel", parent)
    container:Dock(TOP)
    container:DockMargin(0, 2, 0, 2)
    container:SetTall(30)
    container:SetPaintBackground(false)

    container.Paint = function(_, w, h)
        draw.SimpleText(label, "RareloadToolUI.Small", 8, h / 2, theme.Colors.Text.Primary,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local combo = vgui.Create("DComboBox", container)
    combo:Dock(RIGHT)
    combo:SetWide(140)
    combo:DockMargin(0, 3, 8, 3)
    combo:SetSortItems(false)
    combo:SetTextColor(theme.Colors.Text.Primary)

    local found = false
    for _, choice in ipairs(choices) do
        local selected = choice.value == activeValue
        found = found or selected
        combo:AddChoice(choice.text, choice.value, selected)
    end
    if not found then
        combo:SetValue(tostring(activeValue or ""))
    end

    combo.Paint = function(self, w, h)
        RareloadToolUI.DrawRoundedBox(0, 0, w, h, 4, COL_TRACK_OFF)
        if self:IsHovered() then
            RareloadToolUI.DrawRoundedBox(0, 0, w, h, 4, SetCol(255, 255, 255, 12))
        end
    end

    combo.OnSelect = function(_, _, _, value)
        surface.PlaySound("ui/buttonclick.wav")
        if onSelect then onSelect(value) end
    end

    if tooltip then container:SetTooltip(tooltip) end
    return container
end

function RareloadToolUI.RegisterLanguage()
    local L = RARELOAD.L or function(key) return key end
    language.Add("tool.rareload_tool.name", L("tool.name"))
    language.Add("tool.rareload_tool.desc", L("tool.desc"))
    language.Add("tool.rareload_tool.0", L("tool.info"))
    language.Add("tool.rareload_tool.left", L("tool.left"))
    language.Add("tool.rareload_tool.right", L("tool.right"))
    language.Add("tool.rareload_tool.reload", L("tool.reload"))
end

-- GMod's language.Add stores plain strings, so re-register when the Rareload
-- language changes to keep the native toolgun tooltips in sync.
hook.Add("RareloadLanguageChanged", "RareloadToolUI_RegisterToolLanguage", function()
    RareloadToolUI.RegisterLanguage()
end)

RareloadToolUI.RegisterLanguage()

return RareloadToolUI
