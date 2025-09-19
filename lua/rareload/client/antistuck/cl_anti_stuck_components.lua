-- Anti-Stuck Panel UI Components
-- Reusable UI components for the anti-stuck panel system

-- Type definitions to avoid field injection errors (for IDEs)
---@class RareloadToggle : DButton
---@field initialized boolean
---@field animValue number
---@field OnRemove function

---@class RareloadMethodPanel : DPanel
---@field UserData table

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckComponents = RARELOAD.AntiStuckComponents or {}

local function ensureFontsLoaded()
    if RARELOAD._fontsLoaded then
        return true
    end

    if RARELOAD.RegisterFonts then
        local success, err = pcall(RARELOAD.RegisterFonts)
        if success then
            RARELOAD._fontsLoaded = true
            return true
        else
            print("[RARELOAD] Warning: Font loading failed: " .. tostring(err))
        end
    else
        local success, err = pcall(function()
            include("rareload/utils/rareload_fonts.lua")
            if RARELOAD.RegisterFonts then
                RARELOAD.RegisterFonts()
                RARELOAD._fontsLoaded = true
            end
        end)

        if not success then
            print("[RARELOAD] Warning: Could not load fonts: " .. tostring(err))
        end
    end

    return RARELOAD._fontsLoaded or false
end

ensureFontsLoaded()

local THEME = RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.GetTheme() or {}

function RARELOAD.AntiStuckComponents.CreateThemedButton(parent, text, color, tooltip)
    local btn = vgui.Create("DButton", parent)
    btn:SetText(text)
    btn:SetFont("RareloadUI.Button")
    btn:SetTooltip(tooltip or "")

    btn.Paint = function(pnl, w, h)
        local baseColor = color or THEME.accent
        local hoverColor = THEME.accentHover or Color(baseColor.r + 15, baseColor.g + 15, baseColor.b + 15)
        draw.RoundedBox(8, 0, 0, w, h, pnl:IsHovered() and hoverColor or baseColor)
        draw.SimpleText(pnl:GetText(), "RareloadUI.Button", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    return btn
end

function RARELOAD.AntiStuckComponents.CreateCloseButton(parent, frameW, frameH)
    local closeBtn = vgui.Create("DButton", parent)
    closeBtn:SetSize(36, 36)
    closeBtn:SetPos(frameW - 48, 14)
    closeBtn:SetText("")
    closeBtn:SetTooltip("Close")

    closeBtn.Paint = function(pnl, w, h)
        local c = pnl:IsHovered() and THEME.danger or THEME.textSecondary
        draw.RoundedBox(10, 0, 0, w, h, pnl:IsHovered() and Color(c.r, c.g, c.b, 40) or Color(0, 0, 0, 0))
        surface.SetDrawColor(c)
        surface.DrawLine(10, 10, w - 10, h - 10)
        surface.DrawLine(w - 10, 10, 10, h - 10)
    end

    return closeBtn
end

function RARELOAD.AntiStuckComponents.CreateSearchBox(parent)
    local searchBox = vgui.Create("DTextEntry", parent)
    searchBox:SetSize(260, 34)
    searchBox:SetPos(24, 8)
    searchBox:SetFont("RareloadText")
    searchBox:SetPlaceholderText("Search methods...")
    searchBox:SetTooltip("Filter methods by name or description")
    searchBox:SetUpdateOnType(true)

    return searchBox
end

function RARELOAD.AntiStuckComponents.CreateToggleSwitch(parent, method)
    local toggle = vgui.Create("DButton", parent) --[[@as RareloadToggle]]
    toggle:SetSize(70, 28)
    toggle:SetText("")
    toggle:SetTooltip("Toggle this method on/off")

    toggle.initialized = true
    toggle.animValue = method.enabled and 1 or 0

    toggle.OnRemove = function()
        toggle.animValue = nil
        toggle.initialized = nil
    end

    toggle.Paint = function(btn, w, h)
        if not toggle.animValue then return end

        local t = (RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.GetTheme()) or {}
        local danger = t.danger or Color(245, 85, 85)
        local success = t.success or Color(80, 210, 145)
        local textHl = t.textHighlight or Color(255, 255, 255)

        local targetAnim = method.enabled and 1 or 0
        toggle.animValue = Lerp(FrameTime() * 10, toggle.animValue, targetAnim)

        local thumbX = 3 + toggle.animValue * (w - h + 3 - 3)
        local bgColor = Color(
            Lerp(toggle.animValue, danger.r, success.r),
            Lerp(toggle.animValue, danger.g, success.g),
            Lerp(toggle.animValue, danger.b, success.b)
        )

        draw.RoundedBox(h / 2, 0, 0, w, h, bgColor)
        draw.RoundedBox((h - 6) / 2, thumbX, 3, h - 6, h - 6, textHl)

        local text = method.enabled and "ON" or "OFF"
        draw.SimpleText(text, "RareloadSmall", w / 2, h / 2, textHl, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    toggle.DoClick = function()
        method.enabled = not method.enabled

        if RARELOAD.AntiStuckData then
            local methods = RARELOAD.AntiStuckData.GetMethods()

            local function sameMethod(a, b)
                if not a or not b then return false end
                if a.func and b.func then return a.func == b.func end
                if a.name and b.name then return a.name == b.name end
                return false
            end

            for i, m in ipairs(methods) do
                if sameMethod(m, method) then
                    methods[i].enabled = method.enabled
                    break
                end
            end

            RARELOAD.AntiStuckData.SetMethods(methods)
            local saveSuccess = RARELOAD.AntiStuckData.SaveMethods(methods)

            if not saveSuccess then
                print("[RARELOAD] Warning: Failed to save method toggle state")
            end
        end

        surface.PlaySound("ui/buttonclick.wav")
    end

    return toggle
end

function RARELOAD.AntiStuckComponents.CreateMethodPanel(parent, method, methodIndex, dragState, onRefresh)
    local pnl = vgui.Create("DPanel", parent) --[[@as RareloadMethodPanel]]
    pnl:SetTall(85)
    pnl:Dock(TOP)
    pnl:DockMargin(20, 0, 20, 8)
    pnl.UserData = {
        methodIndex = methodIndex,
        method = method
    }
    pnl:SetCursor("arrow")
    pnl:SetTooltip(method.description or "")

    pnl.Paint = function(self, w, h)
        local isDragging = dragState.dragging == self
        local userData = self.UserData
        local currentMethod = userData and userData.method or method
        local bg = currentMethod.enabled and THEME.panel or
            Color(THEME.panel.r * 0.6, THEME.panel.g * 0.6, THEME.panel.b * 0.6)

        if isDragging then
            bg = THEME.panelSelected
            draw.RoundedBox(12, -2, -2, w + 4, h + 4, Color(0, 0, 0, 100))
        elseif self:IsHovered() then
            bg = THEME.panelHover
        end

        draw.RoundedBox(12, 0, 0, w, h, bg)

        local accentColor = currentMethod.enabled and THEME.accent or THEME.danger
        draw.RoundedBoxEx(12, 0, 0, 6, h, accentColor, true, false, true, false)

        local numBg = currentMethod.enabled and THEME.accent or THEME.textSecondary
        draw.RoundedBox(8, 16, 22, 38, 38, numBg)
        local displayIndex = userData and userData.methodIndex or methodIndex
        draw.SimpleText(tostring(displayIndex), "RareloadTitle", 35, 41, THEME.textHighlight, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)

        draw.SimpleText(currentMethod.name, "RareloadTitle", 68, 22, THEME.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local desc = currentMethod.description or ""
        if #desc > 75 then
            desc = string.sub(desc, 1, 72) .. "..."
        end
        draw.SimpleText(desc, "RareloadText", 68, 48, THEME.textSecondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        local statusText = currentMethod.enabled and "ENABLED" or "DISABLED"
        local statusColor = currentMethod.enabled and THEME.success or THEME.danger
        draw.SimpleText(statusText, "RareloadUI.Button", w - 220, 41, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        if not isDragging then
            surface.SetDrawColor(THEME.textSecondary.r, THEME.textSecondary.g, THEME.textSecondary.b,
                self:IsHovered() and 200 or 120)
            for j = 0, 2 do
                surface.DrawRect(w - 35, 28 + j * 10, 20, 3)
            end
        end
    end

    local toggle = RARELOAD.AntiStuckComponents.CreateToggleSwitch(pnl, method)
    if IsValid(toggle) then
        toggle:SetZPos(1)
    end

    function pnl:PerformLayout(w, h)
        if not IsValid(toggle) then return end
        w = w or self:GetWide()
        h = h or self:GetTall()
        local y = math.floor((h - toggle:GetTall()) / 2)
        toggle:SetPos(math.max(20, w - 150), math.max(8, y))
    end

    pnl:InvalidateLayout(true)

    return pnl
end

function RARELOAD.AntiStuckComponents.CreateNotification(parent, text, color, duration)
    local frameW, frameH = parent:GetSize()
    local notif = vgui.Create("DPanel", parent)
    notif:SetSize(200, 38)
    notif:SetPos(frameW / 2 - 100, frameH - 90)
    notif:SetAlpha(0)
    notif.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, color or THEME.success)
        draw.SimpleText(text, "RareloadUI.Button", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    notif:AlphaTo(255, 0.2, 0)
    timer.Simple(duration or 1.5, function()
        if IsValid(notif) then
            notif:AlphaTo(0, 0.2, 0, function()
                if IsValid(notif) then
                    notif:Remove()
                end
            end)
        end
    end)

    return notif
end

function RARELOAD.AntiStuckComponents.CreateProfileNotification(parent, profileName, displayName)
    local frameW = parent:GetWide()
    local notif = vgui.Create("DPanel", parent)
    notif:SetSize(250, 40)
    notif:SetPos(frameW / 2 - 125, 100)
    notif:SetAlpha(0)

    notif.Paint = function(self, w, h)
        w = w or self:GetWide()
        h = h or self:GetTall()
        if not w or not h or w == 0 or h == 0 then return end
        draw.RoundedBox(8, 0, 0, w, h, THEME.accent)
        draw.SimpleText("Profile Changed: " .. (displayName or profileName), "RareloadText", w / 2, h / 2,
            THEME.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    notif:AlphaTo(255, 0.2, 0)
    timer.Simple(2, function()
        if IsValid(notif) then
            notif:AlphaTo(0, 0.3, 0, function()
                if IsValid(notif) then notif:Remove() end
            end)
        end
    end)

    return notif
end
