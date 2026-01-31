-- Anti-Stuck Methods Panel - Modern Glass Design
-- Main panel for configuring anti-stuck method order and states

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckDebug = RARELOAD.AntiStuckDebug or {}

local function getTheme()
    return RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.GetTheme() or {}
end

local debugFrame = nil

function RARELOAD.AntiStuckDebug.OpenPanel()
    if debugFrame and IsValid(debugFrame) then
        debugFrame:MakePopup()
        debugFrame:MoveToFront()
        return
    end

    if not RARELOAD.AntiStuckData then
        notification.AddLegacy("Anti-Stuck Data module not loaded", NOTIFY_ERROR, 3)
        return
    end

    if not RARELOAD.AntiStuckComponents then
        notification.AddLegacy("Anti-Stuck Components module not loaded", NOTIFY_ERROR, 3)
        return
    end

    if RARELOAD.RegisterFonts then
        RARELOAD.RegisterFonts()
    end

    if RARELOAD.AntiStuckData.LoadMethods then
        RARELOAD.AntiStuckData.LoadMethods()
    end

    local THEME = getTheme()
    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.Clamp(screenW * 0.42, 520, 680)
    local frameH = math.Clamp(screenH * 0.65, 480, 620)
    
    debugFrame = vgui.Create("DFrame")
    debugFrame:SetSize(frameW, frameH)
    debugFrame:SetTitle("")
    debugFrame:Center()
    debugFrame:MakePopup()
    debugFrame:SetDraggable(true)
    debugFrame:ShowCloseButton(false)
    debugFrame:SetBackgroundBlur(true)
    debugFrame:SetDeleteOnClose(true)

    local frameStartTime = SysTime()
    debugFrame._openAnim = 0

    debugFrame.Paint = function(self, w, h)
        local t = getTheme()
        self._openAnim = Lerp(FrameTime() * 8, self._openAnim, 1)
        
        Derma_DrawBackgroundBlur(self, frameStartTime)

        draw.RoundedBox(16, 4, 6, w, h, Color(0, 0, 0, 100 * self._openAnim))
        draw.RoundedBox(14, 0, 0, w, h, t.background)
        draw.RoundedBoxEx(14, 0, 0, w, 60, t.headerGradientStart, true, true, false, false)
        
        local gradMat = Material("vgui/gradient-d")
        if not gradMat:IsError() then
            surface.SetMaterial(gradMat)
            surface.SetDrawColor(0, 0, 0, 60)
            surface.DrawTexturedRect(0, 0, w, 60)
        end
        
        surface.SetDrawColor(t.accent)
        surface.DrawRect(0, 58, w, 2)

        if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIconText then
            RARELOAD.AntiStuckTheme.DrawIconText("lightning", "Anti-Stuck Methods", 24, 30, 20, "RareloadTitle", t.textHighlight, t.textHighlight, 8, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("Anti-Stuck Methods", "RareloadTitle", 24, 30, t.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        
        local methods = RARELOAD.AntiStuckData and RARELOAD.AntiStuckData.GetMethods() or {}
        local enabledCount = 0
        for _, m in ipairs(methods) do
            if m.enabled then enabledCount = enabledCount + 1 end
        end
        local subtitle = enabledCount .. "/" .. #methods .. " methods active"
        draw.SimpleText(subtitle, "RareloadSmall", w - 50, 30, t.textMuted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        draw.RoundedBoxEx(14, 0, h - 36, w, 36, Color(t.surface.r, t.surface.g, t.surface.b, 200), false, false, true, true)
        draw.SimpleText("Drag to reorder • Click toggle to enable/disable • Top = Highest priority", 
            "RareloadSmall", w / 2, h - 18, t.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateCloseButton then
        local closeBtn = RARELOAD.AntiStuckComponents.CreateCloseButton(debugFrame, frameW, frameH)
        closeBtn.DoClick = function()
            surface.PlaySound("ui/buttonclickrelease.wav")
            debugFrame:AlphaTo(0, 0.15, 0, function() 
                if IsValid(debugFrame) then debugFrame:Remove() end 
            end)
        end
    end

    local topPanel = vgui.Create("DPanel", debugFrame)
    topPanel:SetTall(100)
    topPanel:Dock(TOP)
    topPanel:DockMargin(0, 68, 0, 0)
    topPanel.Paint = nil

    local searchBox = nil
    if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateSearchBox then
        searchBox = RARELOAD.AntiStuckComponents.CreateSearchBox(topPanel)
        local container = searchBox:GetContainer() and searchBox:GetContainer()
        if IsValid(container) then
            container:SetPos(16, 8)
        end
    end

    RARELOAD.AntiStuckDebug.CreateButtonBar(topPanel, debugFrame, frameW, frameH)

    local scroll = vgui.Create("DScrollPanel", debugFrame)
    scroll:Dock(FILL)
    scroll:DockMargin(0, 8, 0, 44)
    
    local vbar = scroll:GetVBar()
    vbar:SetWide(6)
    vbar:SetHideButtons(true)
    vbar.Paint = function(_, w, h)
        local t = getTheme()
        draw.RoundedBox(3, 0, 0, w, h, t.scrollTrack)
    end
    vbar.btnGrip.Paint = function(_, w, h)
        local t = getTheme()
        local color = vbar.btnGrip:IsHovered() and t.scrollThumbHover or t.scrollThumb
        draw.RoundedBox(3, 1, 0, w - 2, h, color)
    end

    RARELOAD.AntiStuckDebug.currentFrame = debugFrame
    RARELOAD.AntiStuckDebug.methodContainer = scroll
    RARELOAD.AntiStuckDebug.searchBox = searchBox

    timer.Simple(0.1, function()
        if not IsValid(debugFrame) then return end
        if RARELOAD.AntiStuckDebug.RefreshMethodList then
            RARELOAD.AntiStuckDebug.RefreshMethodList()
        end
    end)

    if searchBox then
        searchBox.OnValueChange = function()
            if RARELOAD.AntiStuckDebug.RefreshMethodList then
                RARELOAD.AntiStuckDebug.RefreshMethodList()
            end
        end
    end
end

function RARELOAD.AntiStuckDebug.CreateButtonBar(parent, frame, frameW, frameH)
    local THEME = getTheme()
    
    local btnBar = vgui.Create("DPanel", parent)
    btnBar:SetSize(frameW - 32, 44)
    btnBar:SetPos(16, 52)
    btnBar.Paint = function(self, w, h)
        local t = getTheme()
        draw.RoundedBox(10, 0, 0, w, h, t.surface)
        surface.SetDrawColor(t.panelBorder)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local buttons = {
        { text = "Reset", color = THEME.warning, tooltip = "Reset to default methods", width = 70 },
        { text = "Enable All", color = THEME.success, tooltip = "Enable all methods", width = 85 },
        { text = "Disable All", color = THEME.danger, tooltip = "Disable all methods", width = 85 },
        { text = "Settings", color = THEME.info, tooltip = "Open advanced settings", width = 80 },
        { text = "Save", color = THEME.accent, tooltip = "Save configuration", width = 70 },
    }
    
    local xPos = 8
    for i, btnData in ipairs(buttons) do
        if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateThemedButton then
            local btn = RARELOAD.AntiStuckComponents.CreateThemedButton(btnBar, btnData.text, btnData.color, btnData.tooltip)
            btn:SetSize(btnData.width, 32)
            btn:SetPos(xPos, 6)
            
            if i == 1 then
                btn.DoClick = function()
                    if RARELOAD.AntiStuckData then
                        RARELOAD.AntiStuckData.ResetToDefaults()
                        RARELOAD.AntiStuckDebug.RefreshMethodList()
                        RARELOAD.AntiStuckComponents.CreateNotification(frame, "Reset complete!", THEME.warning)
                    end
                    surface.PlaySound("ui/buttonclickrelease.wav")
                end
            elseif i == 2 then
                btn.DoClick = function()
                    if RARELOAD.AntiStuckData then
                        RARELOAD.AntiStuckData.EnableAllMethods()
                        RARELOAD.AntiStuckDebug.RefreshMethodList()
                        RARELOAD.AntiStuckComponents.CreateNotification(frame, "All enabled!", THEME.success)
                    end
                    surface.PlaySound("ui/buttonclickrelease.wav")
                end
            elseif i == 3 then
                btn.DoClick = function()
                    if RARELOAD.AntiStuckData then
                        RARELOAD.AntiStuckData.DisableAllMethods()
                        RARELOAD.AntiStuckDebug.RefreshMethodList()
                        RARELOAD.AntiStuckComponents.CreateNotification(frame, "All disabled!", THEME.danger)
                    end
                    surface.PlaySound("ui/buttonclickrelease.wav")
                end
            elseif i == 4 then
                btn.DoClick = function()
                    surface.PlaySound("ui/buttonclickrelease.wav")
                    RARELOAD.AntiStuckDebug.OpenSettingsPanel()
                end
            elseif i == 5 then
                btn.DoClick = function()
                    if RARELOAD.AntiStuckData and RARELOAD.AntiStuckData.SaveMethods() then
                        RARELOAD.AntiStuckComponents.CreateNotification(frame, "Saved!", THEME.success)
                    end
                    surface.PlaySound("ui/buttonclickrelease.wav")
                end
            end
            
            xPos = xPos + btnData.width + 6
        end
    end
end

function RARELOAD.AntiStuckDebug.OpenSettingsPanel()
    if RARELOAD.AntiStuckSettings and RARELOAD.AntiStuckSettings.OpenSettingsPanel then
        RARELOAD.AntiStuckSettings.OpenSettingsPanel()
    else
        RunConsoleCommand("rareload_antistuck_settings")
    end
end
