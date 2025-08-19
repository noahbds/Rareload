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
        print("[RARELOAD] Error: AntiStuckData not loaded")
        notification.AddLegacy("Anti-Stuck Data module not loaded", NOTIFY_ERROR, 3)
        return
    end

    if not RARELOAD.AntiStuckComponents then
        print("[RARELOAD] Error: AntiStuckComponents not loaded")
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

    local frameStartTime = SysTime()

    debugFrame.Paint = function(self, w, h)
        Derma_DrawBackgroundBlur(self, frameStartTime)

        draw.RoundedBox(18, 0, 0, w, h, THEME.background)

        surface.SetDrawColor(THEME.header)
        draw.RoundedBoxEx(18, 0, 0, w, 64, THEME.header, true, true, false, false)
        local gradMat = RARELOAD and RARELOAD.GradientU
        if not gradMat then
            gradMat = Material("vgui/gradient-u")
            RARELOAD = RARELOAD or {}
            RARELOAD.GradientU = gradMat
        end
        if gradMat and gradMat:IsError() then
            surface.SetDrawColor(0, 0, 0, 60)
            surface.DrawRect(0, 0, w, 64)
        else
            surface.SetMaterial(gradMat)
            surface.SetDrawColor(0, 0, 0, 60)
            surface.DrawTexturedRect(0, 0, w, 64)
        end

        surface.SetDrawColor(THEME.accent)
        surface.DrawRect(0, 64, w, 2)

        draw.SimpleText("Anti-Stuck Methods", "RareloadHeader", 32, 32, THEME.textHighlight, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        draw.RoundedBoxEx(18, 0, h - 44, w, 44, THEME.header, false, false, true, true)
        draw.SimpleText("Drag to reorder • Toggle or disable each • Top = First Method Used", "RareloadSmall", w / 2,
            h - 22, THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateCloseButton then
        local closeBtn = RARELOAD.AntiStuckComponents.CreateCloseButton(debugFrame, frameW, frameH)
        closeBtn.DoClick = function()
            surface.PlaySound("ui/buttonclickrelease.wav")
            debugFrame:AlphaTo(0, 0.2, 0, function() debugFrame:Remove() end)
        end
    end

    local topPanel = vgui.Create("DPanel", debugFrame)
    topPanel:SetTall(90)
    topPanel:Dock(TOP)
    topPanel:DockMargin(0, 72, 0, 0)
    topPanel.Paint = nil

    local searchBox = nil
    if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateSearchBox then
        searchBox = RARELOAD.AntiStuckComponents.CreateSearchBox(topPanel)
    end

    RARELOAD.AntiStuckDebug.CreateButtonBar(topPanel, debugFrame, frameW, frameH)

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

    if not scroll.OnMouseWheeled then
        function scroll:OnMouseWheeled(delta)
            local bar = self:GetVBar()
            if IsValid(bar) then
                bar:AddScroll(delta)
                return true
            end
        end
    end

    ---@class DScrollPanel
    local canvas = scroll.GetCanvas and scroll:GetCanvas() or nil

    if IsValid(canvas) and not canvas.OnMouseWheeled then
        function canvas:OnMouseWheeled(delta)
            local parent = self:GetParent()
            local bar = nil
            if IsValid(parent) and parent.GetVBar then
                bar = parent:GetVBar()
            end
            if bar ~= nil and IsValid(bar) then
                bar:AddScroll(delta)
                return true
            end
        end
    end

    RARELOAD.AntiStuckDebug.currentFrame = debugFrame
    RARELOAD.AntiStuckDebug.methodContainer = scroll
    RARELOAD.AntiStuckDebug.searchBox = searchBox

    timer.Simple(0.1, function()
        if not IsValid(debugFrame) then
            print("[RARELOAD] Error: Debug frame was destroyed before initialization")
            return
        end

        if RARELOAD.AntiStuckDebug.RefreshMethodList then
            RARELOAD.AntiStuckDebug.RefreshMethodList()
        else
            print("[RARELOAD] Error: RefreshMethodList function not available")
            timer.Simple(0.5, function()
                if IsValid(debugFrame) and RARELOAD.AntiStuckDebug.RefreshMethodList then
                    RARELOAD.AntiStuckDebug.RefreshMethodList()
                end
            end)
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
    local btnBar = vgui.Create("Panel", parent)
    btnBar:SetSize(600, 36)
    btnBar:SetPos(24, 48)

    if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateThemedButton then
        local resetBtn = RARELOAD.AntiStuckComponents.CreateThemedButton(btnBar, "Reset to Defaults", THEME.warning,
            "Restore to default methods and enabled states")
        resetBtn:SetSize(120, 32)
        resetBtn:SetPos(0, 2)
        resetBtn.DoClick = function()
            if RARELOAD.AntiStuckData then
                RARELOAD.AntiStuckData.ResetToDefaults()
                if RARELOAD.AntiStuckDebug.RefreshMethodList then
                    RARELOAD.AntiStuckDebug.RefreshMethodList()
                end
            end
            surface.PlaySound("ui/buttonclickrelease.wav")
        end
    end

    if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateThemedButton then
        local enableAllBtn = RARELOAD.AntiStuckComponents.CreateThemedButton(btnBar, "Enable All", THEME.success,
            "Enable all anti-stuck methods")
        enableAllBtn:SetSize(100, 32)
        enableAllBtn:SetPos(130, 2)
        enableAllBtn.DoClick = function()
            if RARELOAD.AntiStuckData then
                RARELOAD.AntiStuckData.EnableAllMethods()
                RARELOAD.AntiStuckDebug.RefreshMethodList()
            end
            surface.PlaySound("ui/buttonclickrelease.wav")
        end
    end

    if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateThemedButton then
        local disableAllBtn = RARELOAD.AntiStuckComponents.CreateThemedButton(btnBar, "Disable All", THEME.danger,
            "Disable all anti-stuck methods")
        disableAllBtn:SetSize(100, 32)
        disableAllBtn:SetPos(240, 2)
        disableAllBtn.DoClick = function()
            if RARELOAD.AntiStuckData then
                RARELOAD.AntiStuckData.DisableAllMethods()
                RARELOAD.AntiStuckDebug.RefreshMethodList()
            end
            surface.PlaySound("ui/buttonclickrelease.wav")
        end
    end

    if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateThemedButton then
        local settingsBtn = RARELOAD.AntiStuckComponents.CreateThemedButton(btnBar, "Settings", THEME.info,
            "Edit Anti-Stuck System Settings")
        settingsBtn:SetSize(100, 32)
        settingsBtn:SetPos(350, 2)
        settingsBtn.DoClick = function()
            surface.PlaySound("ui/buttonclickrelease.wav")
            RARELOAD.AntiStuckDebug.OpenSettingsPanel()
        end
    end

    if RARELOAD.AntiStuckComponents and RARELOAD.AntiStuckComponents.CreateThemedButton then
        local saveBtn = RARELOAD.AntiStuckComponents.CreateThemedButton(btnBar, "Save Configuration", THEME.accent,
            "Save your configuration")
        saveBtn:SetSize(140, 32)
        saveBtn:SetPos(460, 2)
        saveBtn.DoClick = function()
            if RARELOAD.AntiStuckData and RARELOAD.AntiStuckData.SaveMethods() then
                if RARELOAD.AntiStuckComponents then
                    RARELOAD.AntiStuckComponents.CreateNotification(frame, "Settings Saved!", THEME.success)
                end
                LocalPlayer():ChatPrint("[RARELOAD] Anti-stuck methods saved!")
            end
            surface.PlaySound("ui/buttonclickrelease.wav")
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
