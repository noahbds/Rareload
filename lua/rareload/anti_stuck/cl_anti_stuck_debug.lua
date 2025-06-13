local THEME = {
    background = Color(22, 25, 37),
    header = Color(28, 32, 48),
    panel = Color(35, 39, 54),
    panelLight = Color(42, 47, 65),
    panelHover = Color(48, 54, 75),
    panelSelected = Color(53, 59, 82),

    text = Color(235, 240, 255),
    textSecondary = Color(190, 195, 215),
    textHighlight = Color(255, 255, 255),

    accent = Color(88, 140, 240),
    accentHover = Color(100, 155, 255),
    success = Color(80, 210, 145),
    warning = Color(255, 195, 85),
    danger = Color(245, 85, 85),

    shadow = Color(10, 12, 20, 200),
    glow = Color(100, 140, 255, 55),
    overlay = Color(15, 18, 30, 200),

    gradientStart = Color(35, 39, 54),
    gradientEnd = Color(30, 34, 48),
}

local function CreateFonts()
    surface.CreateFont("RareloadHeader", {
        font = "Roboto",
        size = 24,
        weight = 700,
        antialias = true,
        shadow = false
    })

    surface.CreateFont("RareloadTitle", {
        font = "Roboto",
        size = 20,
        weight = 600,
        antialias = true,
        shadow = false
    })

    surface.CreateFont("RareloadText", {
        font = "Roboto",
        size = 16,
        weight = 400,
        antialias = true,
        shadow = false
    })

    surface.CreateFont("RareloadButton", {
        font = "Roboto",
        size = 16,
        weight = 600,
        antialias = true,
        shadow = false
    })

    surface.CreateFont("RareloadSmall", {
        font = "Roboto",
        size = 14,
        weight = 400,
        antialias = true,
        shadow = false
    })
end

local UI = {
    DrawRoundedBox = function(radius, x, y, w, h, color)
        draw.RoundedBox(radius, x, y, w, h, color)
    end,

    DrawRoundedBoxEx = function(radius, x, y, w, h, color, tl, tr, bl, br)
        draw.RoundedBoxEx(radius, x, y, w, h, color, tl, tr, bl, br)
    end,

    DrawShadow = function(x, y, w, h, depth, opacity)
        local shadowColor = Color(THEME.shadow.r, THEME.shadow.g, THEME.shadow.b, opacity or 180)
        for i = 1, depth do
            draw.RoundedBox(8, x - i, y - i, w + i * 2, h + i * 2,
                Color(shadowColor.r, shadowColor.g, shadowColor.b, shadowColor.a / (i * 1.5)))
        end
    end,

    DrawGradient = function(x, y, w, h, colorStart, colorEnd, horizontal)
        local vertices = {}

        if horizontal then
            vertices = {
                { x = x,     y = y,     u = 0, v = 0, color = colorStart },
                { x = x + w, y = y,     u = 1, v = 0, color = colorEnd },
                { x = x + w, y = y + h, u = 1, v = 1, color = colorEnd },
                { x = x,     y = y + h, u = 0, v = 1, color = colorStart }
            }
        else
            vertices = {
                { x = x,     y = y,     u = 0, v = 0, color = colorStart },
                { x = x + w, y = y,     u = 1, v = 0, color = colorStart },
                { x = x + w, y = y + h, u = 1, v = 1, color = colorEnd },
                { x = x,     y = y + h, u = 0, v = 1, color = colorEnd }
            }
        end

        surface.DrawPoly(vertices)
    end,

    DrawText = function(text, font, x, y, color, alignX, alignY)
        draw.SimpleText(text, font, x, y, color, alignX or TEXT_ALIGN_LEFT, alignY or TEXT_ALIGN_TOP)
    end,

    DrawButton = function(x, y, w, h, text, color, hoverColor, textColor)
        local isHovered = input.IsMouseInBox(x, y, x + w, y + h)
        local bgColor = isHovered and hoverColor or color

        UI.DrawShadow(x, y, w, h, 3, 120)
        UI.DrawRoundedBox(6, x, y, w, h, bgColor)

        if isHovered then
            surface.SetDrawColor(THEME.glow)
            surface.DrawRect(x, y, w, h)
        end

        UI.DrawText(text, "RareloadButton", x + w / 2, y + h / 2, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        return isHovered
    end
}

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckDebug = RARELOAD.AntiStuckDebug or {}

local debugFrame = nil
local methodPriorities = {}

local defaultPriorities = {
    { name = "Cached Positions",   func = "TryCachedPositions",   enabled = true, description = "Use previously saved safe positions from successful unstuck attempts" },
    { name = "Smart Displacement", func = "TryDisplacement",      enabled = true, description = "Intelligently move player using physics-based displacement in optimal directions" },
    { name = "3D Space Scan",      func = "Try3DSpaceScan",       enabled = true, description = "Comprehensive volumetric scan in all directions with collision detection" },
    { name = "Navigation Mesh",    func = "TryNodeGraph",         enabled = true, description = "Use Source engine navigation mesh and node graph for optimal pathfinding" },
    { name = "Map Entities",       func = "TryMapEntities",       enabled = true, description = "Analyze positions near functional map entities and spawn points" },
    { name = "Systematic Grid",    func = "TrySystematicGrid",    enabled = true, description = "Methodical grid-based search with adaptive resolution and bounds checking" },
    { name = "World Brushes",      func = "TryWorldBrushes",      enabled = true, description = "Advanced world geometry analysis using brush entities and surface normals" },
    { name = "Spawn Points",       func = "TrySpawnPoints",       enabled = true, description = "Fallback to map-defined spawn points with validity checking" },
    { name = "Emergency Teleport", func = "TryEmergencyTeleport", enabled = true, description = "Last resort emergency positioning with map boundary detection" }
}

function input.IsMouseInBox(x, y, x2, y2)
    local mouseX, mouseY = input.GetCursorPos()
    return mouseX >= x and mouseX <= x2 and mouseY >= y and mouseY <= y2
end

function RARELOAD.AntiStuckDebug.LoadPriorities()
    local saved = file.Read("rareload/antistuck_priorities.json", "DATA")
    if saved then
        local success, data = pcall(util.JSONToTable, saved)
        if success and data then
            methodPriorities = data
            return
        end
    end

    methodPriorities = table.Copy(defaultPriorities)
end

function RARELOAD.AntiStuckDebug.SavePriorities()
    file.CreateDir("rareload")
    file.Write("rareload/antistuck_priorities.json", util.TableToJSON(methodPriorities, true))

    net.Start("RareloadAntiStuckPriorities")
    net.WriteTable(methodPriorities)
    net.SendToServer()
end

function RARELOAD.AntiStuckDebug.OpenPanel()
    if debugFrame and IsValid(debugFrame) then
        debugFrame:MakePopup()
        debugFrame:MoveToFront()
        return
    end

    CreateFonts()
    RARELOAD.AntiStuckDebug.LoadPriorities()

    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.min(screenW * 0.5, 820)
    local frameH = math.min(screenH * 0.7, 670)

    debugFrame = vgui.Create("DFrame")
    debugFrame:SetSize(frameW, frameH)
    debugFrame:SetTitle("")
    debugFrame:Center()
    debugFrame:MakePopup()
    debugFrame:SetDraggable(true)
    debugFrame:ShowCloseButton(false)
    debugFrame:SetBackgroundBlur(true)
    debugFrame:SetDeleteOnClose(true)

    debugFrame.Paint = function(self, w, h)
        Derma_DrawBackgroundBlur(self, self.startTime or SysTime())

        draw.RoundedBox(18, 0, 0, w, h, THEME.background)

        surface.SetDrawColor(THEME.header)
        draw.RoundedBoxEx(18, 0, 0, w, 64, THEME.header, true, true, false, false)
        surface.SetMaterial(Material("vgui/gradient-u"))
        surface.SetDrawColor(0, 0, 0, 60)
        surface.DrawTexturedRect(0, 0, w, 64)

        surface.SetDrawColor(THEME.accent)
        surface.DrawRect(0, 64, w, 2)

        draw.SimpleText("Anti-Stuck Method Priorities", "RareloadHeader", 32, 32, THEME.textHighlight, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        draw.RoundedBoxEx(18, 0, h - 44, w, 44, THEME.header, false, false, true, true)
        draw.SimpleText("Drag to reorder • Toggle or disable each • Top = highest priority", "RareloadSmall", w / 2,
            h - 22, THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local closeBtn = vgui.Create("DButton", debugFrame)
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
    closeBtn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        debugFrame:AlphaTo(0, 0.2, 0, function() debugFrame:Remove() end)
    end

    local topPanel = vgui.Create("DPanel", debugFrame)
    topPanel:SetTall(56)
    topPanel:Dock(TOP)
    topPanel:DockMargin(0, 72, 0, 0)
    topPanel.Paint = nil

    local searchBox = vgui.Create("DTextEntry", topPanel)
    searchBox:SetSize(220, 34)
    searchBox:SetPos(24, 11)
    searchBox:SetFont("RareloadText")
    searchBox:SetPlaceholderText("Search methods...")
    searchBox:SetTooltip("Filter methods by name or description")
    searchBox:SetUpdateOnType(true)

    local btnBar = vgui.Create("Panel", topPanel)
    btnBar:SetSize(520, 36)
    btnBar:SetPos(frameW - 24 - btnBar:GetWide(), 10)

    local resetBtn = vgui.Create("DButton", btnBar)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetFont("RareloadButton")
    resetBtn:SetSize(120, 32)
    resetBtn:SetPos(0, 2)
    resetBtn:SetTooltip("Restore default priorities and enabled states")
    resetBtn.Paint = function(pnl, w, h)
        local base = THEME.warning
        draw.RoundedBox(8, 0, 0, w, h, pnl:IsHovered() and THEME.accentHover or base)
        draw.SimpleText(pnl:GetText(), "RareloadButton", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    resetBtn.DoClick = function()
        methodPriorities = table.Copy(defaultPriorities)
        RARELOAD.AntiStuckDebug.SavePriorities()
        RARELOAD.AntiStuckDebug.RefreshMethodList()
        surface.PlaySound("ui/buttonclickrelease.wav")
    end

    local enableAllBtn = vgui.Create("DButton", btnBar)
    enableAllBtn:SetText("Enable All")
    enableAllBtn:SetFont("RareloadButton")
    enableAllBtn:SetSize(100, 32)
    enableAllBtn:SetPos(130, 2)
    enableAllBtn:SetTooltip("Enable all anti-stuck methods")
    enableAllBtn.Paint = function(pnl, w, h)
        local base = THEME.success
        draw.RoundedBox(8, 0, 0, w, h, pnl:IsHovered() and THEME.accentHover or base)
        draw.SimpleText(pnl:GetText(), "RareloadButton", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    enableAllBtn.DoClick = function()
        for _, m in ipairs(methodPriorities) do m.enabled = true end
        RARELOAD.AntiStuckDebug.SavePriorities()
        RARELOAD.AntiStuckDebug.RefreshMethodList()
        surface.PlaySound("ui/buttonclickrelease.wav")
    end

    local disableAllBtn = vgui.Create("DButton", btnBar)
    disableAllBtn:SetText("Disable All")
    disableAllBtn:SetFont("RareloadButton")
    disableAllBtn:SetSize(100, 32)
    disableAllBtn:SetPos(240, 2)
    disableAllBtn:SetTooltip("Disable all anti-stuck methods")
    disableAllBtn.Paint = function(pnl, w, h)
        local base = THEME.danger
        draw.RoundedBox(8, 0, 0, w, h, pnl:IsHovered() and THEME.accentHover or base)
        draw.SimpleText(pnl:GetText(), "RareloadButton", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    disableAllBtn.DoClick = function()
        for _, m in ipairs(methodPriorities) do m.enabled = false end
        RARELOAD.AntiStuckDebug.SavePriorities()
        RARELOAD.AntiStuckDebug.RefreshMethodList()
        surface.PlaySound("ui/buttonclickrelease.wav")
    end

    local saveBtn = vgui.Create("DButton", btnBar)
    saveBtn:SetText("Save Configuration")
    saveBtn:SetFont("RareloadButton")
    saveBtn:SetSize(160, 32)
    saveBtn:SetPos(350, 2)
    saveBtn:SetTooltip("Save your configuration")
    saveBtn.Paint = function(pnl, w, h)
        local base = THEME.accent
        draw.RoundedBox(8, 0, 0, w, h, pnl:IsHovered() and THEME.accentHover or base)
        draw.SimpleText(pnl:GetText(), "RareloadButton", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    saveBtn.DoClick = function()
        RARELOAD.AntiStuckDebug.SavePriorities()
        local notif = vgui.Create("DPanel", debugFrame)
        notif:SetSize(200, 38)
        notif:SetPos(frameW / 2 - 100, frameH - 90)
        notif:SetAlpha(0)
        notif.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.success)
            draw.SimpleText("Settings Saved!", "RareloadButton", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        notif:AlphaTo(255, 0.2, 0)
        timer.Simple(1.5, function()
            if IsValid(notif) then notif:AlphaTo(0, 0.2, 0, function() if IsValid(notif) then notif:Remove() end end) end
        end)
        LocalPlayer():ChatPrint("[RARELOAD] Anti-stuck priorities saved!")
        surface.PlaySound("ui/buttonclickrelease.wav")
    end

    local infoLabel = vgui.Create("DLabel", debugFrame)
    infoLabel:SetText(
        "Configure the order and enable/disable state of each anti-stuck method below. Drag to reorder. Use the toggle or disable button for each method.")
    infoLabel:SetFont("RareloadText")
    infoLabel:SetTextColor(THEME.textSecondary)
    infoLabel:SetWrap(true)
    infoLabel:SetContentAlignment(5)
    infoLabel:SetTall(32)
    infoLabel:Dock(TOP)
    infoLabel:DockMargin(32, 0, 32, 0)

    local scroll = vgui.Create("DScrollPanel", debugFrame)
    scroll:Dock(FILL)
    scroll:DockMargin(0, 34, 0, 52)
    local vbar = scroll:GetVBar()
    vbar:SetWide(8)
    vbar.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, THEME.panelLight) end
    vbar.btnGrip.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, THEME.accent) end

    debugFrame.methodContainer = scroll
    debugFrame.searchBox = searchBox
    RARELOAD.AntiStuckDebug.RefreshMethodList()

    searchBox.OnValueChange = function()
        RARELOAD.AntiStuckDebug.RefreshMethodList()
    end
end

function RARELOAD.AntiStuckDebug.RefreshMethodList()
    if not debugFrame or not IsValid(debugFrame.methodContainer) then return end
    local parent = debugFrame.methodContainer
    parent:Clear()

    local search = debugFrame.searchBox and debugFrame.searchBox:GetValue():lower() or ""

    local function matchesSearch(method)
        if search == "" then return true end
        local searchTerms = string.Split(search, " ")
        local content = (method.name .. " " .. (method.description or "")):lower()

        for _, term in ipairs(searchTerms) do
            if term ~= "" and not content:find(term, 1, true) then
                return false
            end
        end
        return true
    end

    local visible = {}
    for i, method in ipairs(methodPriorities) do
        if matchesSearch(method) then
            table.insert(visible, { method = method, origIndex = i })
        end
    end

    local dragState = {
        dragging = nil,
        dragIndex = nil,
        dragOffsetY = 0,
        dropIndicator = nil,
        startTime = 0
    }

    local panels = {}

    for visIndex, entry in ipairs(visible) do
        local method, i = entry.method, entry.origIndex
        local pnl = vgui.Create("DPanel", parent)
        pnl:SetTall(85)
        pnl:Dock(TOP)
        pnl:DockMargin(20, 0, 20, 8)
        pnl.methodIndex = i
        pnl.method = method
        pnl:SetCursor("arrow")
        pnl:SetTooltip(method.description or "")
        panels[visIndex] = pnl

        pnl.Paint = function(self, w, h)
            local isDragging = dragState.dragging == self
            local bg = method.enabled and THEME.panel or
                Color(THEME.panel.r * 0.6, THEME.panel.g * 0.6, THEME.panel.b * 0.6)

            if isDragging then
                bg = THEME.panelSelected
                draw.RoundedBox(12, -2, -2, w + 4, h + 4, Color(0, 0, 0, 100))
            elseif self:IsHovered() then
                bg = THEME.panelHover
            end

            draw.RoundedBox(12, 0, 0, w, h, bg)

            local accentColor = method.enabled and THEME.accent or THEME.danger
            draw.RoundedBoxEx(12, 0, 0, 6, h, accentColor, true, false, true, false)

            local numBg = method.enabled and THEME.accent or THEME.textSecondary
            draw.RoundedBox(8, 16, 22, 38, 38, numBg)
            draw.SimpleText(tostring(i), "RareloadTitle", 35, 41, THEME.textHighlight, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)

            draw.SimpleText(method.name, "RareloadTitle", 68, 22, THEME.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            local desc = method.description or ""
            if #desc > 75 then
                desc = string.sub(desc, 1, 72) .. "..."
            end
            draw.SimpleText(desc, "RareloadText", 68, 48, THEME.textSecondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            local statusText = method.enabled and "ENABLED" or "DISABLED"
            local statusColor = method.enabled and THEME.success or THEME.danger
            draw.SimpleText(statusText, "RareloadButton", w - 220, 41, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            if not isDragging then
                surface.SetDrawColor(THEME.textSecondary.r, THEME.textSecondary.g, THEME.textSecondary.b,
                    self:IsHovered() and 200 or 120)
                for j = 0, 2 do
                    surface.DrawRect(w - 35, 28 + j * 10, 20, 3)
                end
            end

            if dragState.dropIndicator == visIndex and not isDragging then
                surface.SetDrawColor(THEME.accent)
                surface.DrawRect(0, h - 3, w, 3)
            end
        end

        local toggle = vgui.Create("DButton", pnl)
        toggle:SetSize(70, 28)
        toggle:SetPos(pnl:GetWide() + 550, 29)
        toggle:SetText("")
        toggle:SetTooltip("Toggle this method on/off")
        toggle._anim = toggle._anim or (method.enabled and 1 or 0)

        toggle.Paint = function(btn, w, h)
            local targetAnim = method.enabled and 1 or 0
            btn._anim = Lerp(FrameTime() * 10, btn._anim, targetAnim)

            local thumbX = 3 + btn._anim * (w - h + 3 - 3)
            local bgColor = Color(
                Lerp(btn._anim, THEME.danger.r, THEME.success.r),
                Lerp(btn._anim, THEME.danger.g, THEME.success.g),
                Lerp(btn._anim, THEME.danger.b, THEME.success.b)
            )

            draw.RoundedBox(h / 2, 0, 0, w, h, bgColor)
            draw.RoundedBox((h - 6) / 2, thumbX, 3, h - 6, h - 6, THEME.textHighlight)

            local text = method.enabled and "ON" or "OFF"
            draw.SimpleText(text, "RareloadSmall", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end

        toggle.DoClick = function()
            method.enabled = not method.enabled
            surface.PlaySound("ui/buttonclick.wav")
        end

        pnl.OnMousePressed = function(self, mc)
            if mc == MOUSE_LEFT then
                local mx, my = self:CursorPos()
                if mx >= self:GetWide() - 45 and mx <= self:GetWide() - 10 and my >= 20 and my <= 65 then
                    dragState.dragging = self
                    dragState.dragIndex = visIndex
                    dragState.dragOffsetY = my
                    dragState.startTime = SysTime()
                    self:MouseCapture(true)
                    self:SetZPos(1000)
                    surface.PlaySound("ui/buttonclickrelease.wav")
                end
            end
        end

        pnl.OnMouseReleased = function(self, mc)
            if dragState.dragging == self and mc == MOUSE_LEFT then
                self:MouseCapture(false)
                self:SetZPos(0)

                local mouseY = gui.MouseY()
                local parentX, parentY = parent:LocalToScreen(0, 0)
                local scrollOffset = parent:GetVBar():GetScroll()
                local relY = mouseY - parentY + scrollOffset
                local itemH = self:GetTall() + 8
                local newIndex = math.Clamp(math.floor((relY - dragState.dragOffsetY + itemH / 2) / itemH) + 1, 1,
                    #visible)

                if newIndex ~= dragState.dragIndex and SysTime() - dragState.startTime > 0.1 then
                    local globalOld = visible[dragState.dragIndex].origIndex
                    local globalNew = visible[newIndex].origIndex

                    local movedMethod = table.remove(methodPriorities, globalOld)
                    table.insert(methodPriorities, globalNew, movedMethod)

                    RARELOAD.AntiStuckDebug.RefreshMethodList()
                    surface.PlaySound("ui/buttonclickrelease.wav")
                end

                dragState.dragging = nil
                dragState.dragIndex = nil
                dragState.dropIndicator = nil
            end
        end

        pnl.Think = function(self)
            if dragState.dragging == self then
                local x, y = parent:ScreenToLocal(gui.MouseX(), gui.MouseY())
                local scrollOffset = parent:GetVBar():GetScroll()
                self:SetPos(20, math.max(0, y - dragState.dragOffsetY + scrollOffset))

                local itemH = self:GetTall() + 8
                local relY = y - dragState.dragOffsetY + itemH / 2 + scrollOffset
                dragState.dropIndicator = math.Clamp(math.floor(relY / itemH) + 1, 1, #visible)

                for k, p in ipairs(panels) do
                    if p ~= self then
                        local targetY = (k - 1) * itemH
                        if dragState.dropIndicator and k >= dragState.dropIndicator and dragState.dragIndex and dragState.dropIndicator <= dragState.dragIndex then
                            targetY = targetY + itemH
                        elseif dragState.dropIndicator and k > dragState.dropIndicator and dragState.dragIndex and dragState.dropIndicator > dragState.dragIndex then
                        end
                        p:MoveTo(20, targetY, 0.15, 0, 1)
                    end
                end
            end
        end
    end

    if #visible == 0 and search ~= "" then
        local noResults = vgui.Create("DLabel", parent)
        noResults:SetText("No methods match your search")
        noResults:SetFont("RareloadText")
        noResults:SetTextColor(THEME.textSecondary)
        noResults:SetContentAlignment(5)
        noResults:SetTall(60)
        noResults:Dock(TOP)
        noResults:DockMargin(20, 20, 20, 0)
    end
end

net.Receive("RareloadOpenAntiStuckDebug", function()
    if RARELOAD and RARELOAD.AntiStuckDebug and RARELOAD.AntiStuckDebug.OpenPanel then
        RARELOAD.AntiStuckDebug.OpenPanel()
    else
        notification.AddLegacy("[RARELOAD] Error: Debug panel function not available", NOTIFY_ERROR, 5)
    end
end)
hook.Add("Initialize", "RareloadAntiStuckDebug", function()
    CreateFonts()
    RARELOAD.AntiStuckDebug.LoadPriorities()
end)
if SERVER then
    concommand.Add("rareload_debug_antistuck", function()
        RARELOAD.AntiStuckDebug.OpenPanel()
    end)
else
    concommand.Add("rareload_debug_antistuck", function()
        if RARELOAD.AntiStuckDebug.OpenPanel then
            RARELOAD.AntiStuckDebug.OpenPanel()
        else
            notification.AddLegacy("[RARELOAD] Error: Debug panel function not available", NOTIFY_ERROR, 5)
        end
    end)
end
