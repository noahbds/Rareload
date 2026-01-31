-- Anti-Stuck Panel UI Components - Modern Glass Design
-- Sleek, reusable UI components with animations and glass morphism

---@class RareloadToggle : DButton
---@field initialized boolean
---@field animValue number
---@field hoverAnim number
---@field OnRemove function

---@class RareloadMethodPanel : DPanel
---@field UserData table

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckComponents = RARELOAD.AntiStuckComponents or {}

local function ensureFontsLoaded()
    if RARELOAD._fontsLoaded then return true end

    if RARELOAD.RegisterFonts then
        local success = pcall(RARELOAD.RegisterFonts)
        if success then
            RARELOAD._fontsLoaded = true
            return true
        end
    else
        pcall(function()
            include("rareload/utils/rareload_fonts.lua")
            if RARELOAD.RegisterFonts then
                RARELOAD.RegisterFonts()
                RARELOAD._fontsLoaded = true
            end
        end)
    end

    return RARELOAD._fontsLoaded or false
end

ensureFontsLoaded()

local function getTheme()
    return RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.GetTheme() or {}
end

-- ═══════════════════════════════════════════════════════════════════
-- Modern Themed Button with Hover Animation
-- ═══════════════════════════════════════════════════════════════════
function RARELOAD.AntiStuckComponents.CreateThemedButton(parent, text, color, tooltip, icon)
    local THEME = getTheme()
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetTooltip(tooltip or "")
    
    btn._hoverAnim = 0
    btn._pressAnim = 0
    btn._text = text
    btn._color = color or THEME.accent
    btn._icon = icon

    btn.Paint = function(pnl, w, h)
        local t = getTheme()
        btn._hoverAnim = Lerp(FrameTime() * 12, btn._hoverAnim, pnl:IsHovered() and 1 or 0)
        btn._pressAnim = Lerp(FrameTime() * 15, btn._pressAnim, pnl:IsDown() and 1 or 0)
        
        local baseColor = btn._color
        local r = baseColor.r + btn._hoverAnim * 25 - btn._pressAnim * 15
        local g = baseColor.g + btn._hoverAnim * 25 - btn._pressAnim * 15
        local b = baseColor.b + btn._hoverAnim * 25 - btn._pressAnim * 15
        local bgColor = Color(r, g, b, 200 + btn._hoverAnim * 55)
        
        -- Shadow
        if btn._hoverAnim > 0.1 then
            draw.RoundedBox(8, 0, 2, w, h, ColorAlpha(t.shadow, 60 * btn._hoverAnim))
        end
        
        -- Main button
        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        
        -- Top highlight
        surface.SetDrawColor(255, 255, 255, 20 + btn._hoverAnim * 25)
        surface.DrawLine(8, 1, w - 8, 1)
        
        -- Text with icon offset
        local textX = w / 2
        if btn._icon then
            textX = textX + 8
        end
        
        draw.SimpleText(btn._text, "RareloadUI.Button", textX, h / 2, t.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    return btn
end

-- ═══════════════════════════════════════════════════════════════════
-- Modern Close Button (X)
-- ═══════════════════════════════════════════════════════════════════
function RARELOAD.AntiStuckComponents.CreateCloseButton(parent, frameW, frameH)
    local THEME = getTheme()
    local closeBtn = vgui.Create("DButton", parent)
    closeBtn:SetSize(32, 32)
    closeBtn:SetPos(frameW - 44, 16)
    closeBtn:SetText("")
    closeBtn:SetTooltip("Close")
    closeBtn._hoverAnim = 0

    closeBtn.Paint = function(pnl, w, h)
        local t = getTheme()
        closeBtn._hoverAnim = Lerp(FrameTime() * 12, closeBtn._hoverAnim, pnl:IsHovered() and 1 or 0)
        
        -- Background circle
        local bgAlpha = 20 + closeBtn._hoverAnim * 80
        local bgColor = Color(255, 95, 109, bgAlpha)
        draw.RoundedBox(w / 2, 0, 0, w, h, bgColor)
        
        -- X icon
        local iconColor = Color(
            Lerp(closeBtn._hoverAnim, 150, 255),
            Lerp(closeBtn._hoverAnim, 155, 255),
            Lerp(closeBtn._hoverAnim, 175, 255)
        )
        
        surface.SetDrawColor(iconColor)
        local padding = 10
        local thickness = 2
        
        for i = 0, thickness - 1 do
            surface.DrawLine(padding + i, padding, w - padding + i, h - padding)
            surface.DrawLine(w - padding + i, padding, padding + i, h - padding)
        end
    end

    return closeBtn
end

-- ═══════════════════════════════════════════════════════════════════
-- Modern Search Box with Icon
-- ═══════════════════════════════════════════════════════════════════
function RARELOAD.AntiStuckComponents.CreateSearchBox(parent)
    local THEME = getTheme()
    
    local container = vgui.Create("DPanel", parent)
    container:SetSize(280, 38)
    container:SetPos(20, 6)
    container._focusAnim = 0
    
    container.Paint = function(pnl, w, h)
        local t = getTheme()
        container._focusAnim = Lerp(FrameTime() * 10, container._focusAnim, 
            (pnl._searchBox and pnl._searchBox:HasFocus()) and 1 or 0)
        
        -- Background
        local bgColor = Color(
            t.surface.r + container._focusAnim * 10,
            t.surface.g + container._focusAnim * 10,
            t.surface.b + container._focusAnim * 15,
            240
        )
        draw.RoundedBox(10, 0, 0, w, h, bgColor)
        
        -- Border with focus effect
        local borderColor = Color(
            Lerp(container._focusAnim, t.panelBorder.r, t.accent.r),
            Lerp(container._focusAnim, t.panelBorder.g, t.accent.g),
            Lerp(container._focusAnim, t.panelBorder.b, t.accent.b),
            100 + container._focusAnim * 100
        )
        surface.SetDrawColor(borderColor)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        
        -- Search icon (Derma icon)
        if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIcon then
            RARELOAD.AntiStuckTheme.DrawIcon("search", 14, h / 2, 16, t.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    
    local searchBox = vgui.Create("DTextEntry", container)
    searchBox:SetSize(240, 30)
    searchBox:SetPos(34, 4)
    searchBox:SetFont("RareloadText")
    searchBox:SetPlaceholderText("Search methods...")
    searchBox:SetDrawBackground(false)
    searchBox:SetTextColor(THEME.textPrimary)
    searchBox:SetUpdateOnType(true)
    
    container._searchBox = searchBox
    
    -- Return the text entry for compatibility
    searchBox.GetContainer = function() return container end
    return searchBox
end

-- ═══════════════════════════════════════════════════════════════════
-- Modern Toggle Switch with Smooth Animation
-- ═══════════════════════════════════════════════════════════════════
function RARELOAD.AntiStuckComponents.CreateToggleSwitch(parent, method)
    local THEME = getTheme()
    local toggle = vgui.Create("DButton", parent) --[[@as RareloadToggle]]
    toggle:SetSize(56, 28)
    toggle:SetText("")
    toggle:SetTooltip("Toggle method on/off")

    toggle.initialized = true
    toggle.animValue = method.enabled and 1 or 0
    toggle.hoverAnim = 0

    toggle.OnRemove = function()
        toggle.animValue = nil
        toggle.hoverAnim = nil
        toggle.initialized = nil
    end

    toggle.Paint = function(btn, w, h)
        if not toggle.animValue then return end
        local t = getTheme()

        local targetAnim = method.enabled and 1 or 0
        toggle.animValue = Lerp(FrameTime() * 12, toggle.animValue, targetAnim)
        toggle.hoverAnim = Lerp(FrameTime() * 10, toggle.hoverAnim, btn:IsHovered() and 1 or 0)

        -- Track colors
        local offColor = Color(60, 60, 75, 255)
        local onColor = t.success
        
        local trackColor = Color(
            Lerp(toggle.animValue, offColor.r, onColor.r),
            Lerp(toggle.animValue, offColor.g, onColor.g),
            Lerp(toggle.animValue, offColor.b, onColor.b)
        )
        
        -- Track
        draw.RoundedBox(h / 2, 0, 0, w, h, trackColor)
        
        -- Inner shadow on track
        surface.SetDrawColor(0, 0, 0, 30)
        surface.DrawLine(h / 2, 1, w - h / 2, 1)
        
        -- Thumb position
        local thumbSize = h - 6
        local thumbX = 3 + toggle.animValue * (w - thumbSize - 6)
        local thumbY = 3
        
        -- Thumb shadow
        draw.RoundedBox(thumbSize / 2, thumbX, thumbY + 1, thumbSize, thumbSize, Color(0, 0, 0, 40))
        
        -- Thumb
        local thumbColor = Color(255, 255, 255, 255)
        draw.RoundedBox(thumbSize / 2, thumbX, thumbY, thumbSize, thumbSize, thumbColor)
        
        -- Thumb highlight
        if toggle.hoverAnim > 0 then
            draw.RoundedBox(thumbSize / 2, thumbX, thumbY, thumbSize, thumbSize, 
                Color(255, 255, 255, 30 * toggle.hoverAnim))
        end
    end

    toggle.DoClick = function()
        method.enabled = not method.enabled

        if RARELOAD.AntiStuckData then
            local methods = RARELOAD.AntiStuckData.GetMethods()

            for i, m in ipairs(methods) do
                if (m.func and method.func and m.func == method.func) or 
                   (m.name and method.name and m.name == method.name) then
                    methods[i].enabled = method.enabled
                    break
                end
            end

            RARELOAD.AntiStuckData.SetMethods(methods)
            RARELOAD.AntiStuckData.SaveMethods(methods)
        end

        surface.PlaySound("ui/buttonclick.wav")
    end

    return toggle
end

-- ═══════════════════════════════════════════════════════════════════
-- Modern Method Card with Glass Effect
-- ═══════════════════════════════════════════════════════════════════
function RARELOAD.AntiStuckComponents.CreateMethodPanel(parent, method, methodIndex, dragState, onRefresh)
    local THEME = getTheme()
    local pnl = vgui.Create("DPanel", parent) --[[@as RareloadMethodPanel]]
    pnl:SetTall(72)
    pnl:Dock(TOP)
    pnl:DockMargin(16, 0, 16, 6)
    pnl.UserData = {
        methodIndex = methodIndex,
        method = method
    }
    pnl:SetCursor("arrow")
    pnl._hoverAnim = 0

    pnl.Paint = function(self, w, h)
        local t = getTheme()
        local isDragging = dragState and dragState.dragging == self
        local userData = self.UserData
        local currentMethod = userData and userData.method or method
        
        -- Hover animation
        self._hoverAnim = Lerp(FrameTime() * 10, self._hoverAnim, 
            (self:IsHovered() or isDragging) and 1 or 0)
        
        -- Card styling based on state
        local baseAlpha = currentMethod.enabled and 240 or 180
        local bgR = currentMethod.enabled and 42 or 32
        local bgG = currentMethod.enabled and 45 or 32
        local bgB = currentMethod.enabled and 58 or 40
        
        local hoverBoost = self._hoverAnim * 12
        local bgColor = Color(bgR + hoverBoost, bgG + hoverBoost, bgB + hoverBoost, baseAlpha)
        
        -- Shadow for enabled cards
        if currentMethod.enabled and self._hoverAnim > 0.1 then
            draw.RoundedBox(12, 0, 3, w, h, Color(0, 0, 0, 50 * self._hoverAnim))
        end
        
        -- Main card background
        draw.RoundedBox(10, 0, 0, w, h, bgColor)
        
        -- Left accent bar
        local accentColor = currentMethod.enabled and t.success or t.textMuted
        draw.RoundedBoxEx(10, 0, 0, 4, h, accentColor, true, false, true, false)
        
        -- Top highlight
        surface.SetDrawColor(255, 255, 255, 8 + self._hoverAnim * 12)
        surface.DrawLine(10, 1, w - 10, 1)
        
        -- Index badge
        local badgeSize = 32
        local badgeX, badgeY = 16, (h - badgeSize) / 2
        local badgeColor = currentMethod.enabled and t.accent or t.textMuted
        draw.RoundedBox(8, badgeX, badgeY, badgeSize, badgeSize, badgeColor)
        
        local displayIndex = userData and userData.methodIndex or methodIndex
        draw.SimpleText(tostring(displayIndex), "RareloadHeading", badgeX + badgeSize / 2, badgeY + badgeSize / 2, 
            t.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        
        -- Method name
        local textX = badgeX + badgeSize + 14
        local nameColor = currentMethod.enabled and t.textHighlight or t.textSecondary
        draw.SimpleText(currentMethod.name, "RareloadHeading", textX, 18, nameColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        -- Description (truncated)
        local desc = currentMethod.description or ""
        local maxDescWidth = w - textX - 180
        surface.SetFont("RareloadText")
        local descW = surface.GetTextSize(desc)
        if descW > maxDescWidth then
            while descW > maxDescWidth - 20 and #desc > 3 do
                desc = string.sub(desc, 1, -2)
                descW = surface.GetTextSize(desc)
            end
            desc = desc .. "..."
        end
        draw.SimpleText(desc, "RareloadText", textX, 42, t.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        
        -- Drag handle (hamburger menu icon)
        if not isDragging then
            local handleX = w - 28
            local handleAlpha = 80 + self._hoverAnim * 100
            surface.SetDrawColor(t.textSecondary.r, t.textSecondary.g, t.textSecondary.b, handleAlpha)
            for j = 0, 2 do
                local lineY = h / 2 - 8 + j * 8
                surface.DrawRect(handleX, lineY, 16, 2)
            end
        end
    end

    -- Toggle switch
    local toggle = RARELOAD.AntiStuckComponents.CreateToggleSwitch(pnl, method)
    if IsValid(toggle) then
        toggle:SetZPos(1)
    end

    function pnl:PerformLayout(w, h)
        if not IsValid(toggle) then return end
        w = w or self:GetWide()
        h = h or self:GetTall()
        toggle:SetPos(w - 100, (h - toggle:GetTall()) / 2)
    end

    pnl:InvalidateLayout(true)

    return pnl
end

-- ═══════════════════════════════════════════════════════════════════
-- Modern Toast Notification
-- ═══════════════════════════════════════════════════════════════════
function RARELOAD.AntiStuckComponents.CreateNotification(parent, text, color, duration)
    local THEME = getTheme()
    local frameW, frameH = parent:GetSize()
    
    local notif = vgui.Create("DPanel", parent)
    notif:SetSize(220, 44)
    notif:SetPos(frameW / 2 - 110, frameH - 100)
    notif:SetAlpha(0)
    notif._slideAnim = 0
    
    notif.Paint = function(self, w, h)
        local t = getTheme()
        self._slideAnim = Lerp(FrameTime() * 8, self._slideAnim, 1)
        
        -- Shadow
        draw.RoundedBox(12, 2, 3, w, h, Color(0, 0, 0, 60))
        
        -- Background
        local bgColor = color or t.success
        draw.RoundedBox(10, 0, 0, w, h, bgColor)
        
        -- Highlight
        surface.SetDrawColor(255, 255, 255, 30)
        surface.DrawLine(10, 1, w - 10, 1)
        
        -- Icon based on color (Derma icons)
        local iconName = "accept"
        if color then
            if color.r > 200 and color.g < 150 then iconName = "cross" end
            if color.r > 200 and color.g > 150 then iconName = "warning" end
        end
        
        if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIcon then
            RARELOAD.AntiStuckTheme.DrawIcon(iconName, 18, h / 2, 16, t.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText(text, "RareloadText", 40, h / 2, t.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Slide in animation
    local startY = frameH - 60
    local targetY = frameH - 100
    notif:SetPos(frameW / 2 - 110, startY)
    notif:MoveTo(frameW / 2 - 110, targetY, 0.25, 0, 0.3)
    notif:AlphaTo(255, 0.2, 0)
    
    timer.Simple(duration or 2, function()
        if IsValid(notif) then
            notif:MoveTo(frameW / 2 - 110, startY, 0.2, 0, -1)
            notif:AlphaTo(0, 0.2, 0, function()
                if IsValid(notif) then notif:Remove() end
            end)
        end
    end)

    return notif
end

-- ═══════════════════════════════════════════════════════════════════
-- Profile Change Notification
-- ═══════════════════════════════════════════════════════════════════
function RARELOAD.AntiStuckComponents.CreateProfileNotification(parent, profileName, displayName)
    local THEME = getTheme()
    local frameW = parent:GetWide()
    
    local notif = vgui.Create("DPanel", parent)
    notif:SetSize(280, 48)
    notif:SetPos(frameW / 2 - 140, 80)
    notif:SetAlpha(0)

    notif.Paint = function(self, w, h)
        local t = getTheme()
        
        -- Shadow
        draw.RoundedBox(12, 2, 3, w, h, Color(0, 0, 0, 80))
        
        -- Background gradient
        draw.RoundedBox(10, 0, 0, w, h, t.accent)
        
        -- Highlight
        surface.SetDrawColor(255, 255, 255, 40)
        surface.DrawLine(10, 1, w - 10, 1)
        
        -- Icon and text (Derma icon)
        if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIcon then
            RARELOAD.AntiStuckTheme.DrawIcon("folder", 20, h / 2, 16, t.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText("Profile: " .. (displayName or profileName), "RareloadText", 45, h / 2, 
            t.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    notif:AlphaTo(255, 0.25, 0)
    timer.Simple(2.5, function()
        if IsValid(notif) then
            notif:AlphaTo(0, 0.3, 0, function()
                if IsValid(notif) then notif:Remove() end
            end)
        end
    end)

    return notif
end

-- ═══════════════════════════════════════════════════════════════════
-- Modern Icon Button (for toolbar)
-- ═══════════════════════════════════════════════════════════════════
function RARELOAD.AntiStuckComponents.CreateIconButton(parent, icon, color, tooltip)
    local THEME = getTheme()
    local btn = vgui.Create("DButton", parent)
    btn:SetSize(36, 36)
    btn:SetText("")
    btn:SetTooltip(tooltip or "")
    btn._hoverAnim = 0
    btn._color = color or THEME.accent
    btn._icon = icon or "?"

    btn.Paint = function(pnl, w, h)
        local t = getTheme()
        btn._hoverAnim = Lerp(FrameTime() * 12, btn._hoverAnim, pnl:IsHovered() and 1 or 0)
        
        local bgAlpha = 60 + btn._hoverAnim * 140
        local bgColor = ColorAlpha(btn._color, bgAlpha)
        
        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        
        if btn._hoverAnim > 0.1 then
            surface.SetDrawColor(255, 255, 255, 20 * btn._hoverAnim)
            surface.DrawLine(8, 1, w - 8, 1)
        end
        
        draw.SimpleText(btn._icon, "RareloadText", w / 2, h / 2, t.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    return btn
end
