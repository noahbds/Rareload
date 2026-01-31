RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}

local function getTheme()
    return RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.GetTheme() or {}
end

local Descriptions = RARELOAD.AntiStuckSettings.Descriptions or {}
local Ranges = RARELOAD.AntiStuckSettings.Ranges or {}
local Groups = RARELOAD.AntiStuckSettings.Groups or {}

function RARELOAD.AntiStuckSettings.IsSettingsPanelOpen()
    local worldPanel = vgui.GetWorldPanel()
    if not IsValid(worldPanel) then return false end
    for _, child in pairs(worldPanel:GetChildren()) do
        if IsValid(child) and child.GetName and child:GetName() == "AntiStuckSettingsPanel" then
            return true
        end
    end
    return false
end

function RARELOAD.AntiStuckSettings.RefreshSettingsPanel()
    local worldPanel = vgui.GetWorldPanel()
    if not IsValid(worldPanel) then return end
    for _, child in pairs(worldPanel:GetChildren()) do
        if IsValid(child) and child.GetName and child:GetName() == "AntiStuckSettingsPanel" then
            child:Close()
            timer.Simple(0.2, function() RARELOAD.AntiStuckSettings.OpenSettingsPanel() end)
            break
        end
    end
end

function RARELOAD.AntiStuckSettings.OpenSettingsPanel()
    if RARELOAD.AntiStuckSettings._openingPanel then return end
    RARELOAD.AntiStuckSettings._openingPanel = true
    if RARELOAD.AntiStuckSettings.CloseAllDialogs then RARELOAD.AntiStuckSettings.CloseAllDialogs() end
    if net and net.Start then
        net.Start("RareloadRequestAntiStuckConfig")
        net.SendToServer()
    end
    timer.Simple(0.05, function()
        RARELOAD.AntiStuckSettings._openingPanel = false
        RARELOAD.AntiStuckSettings._CreateSettingsPanel()
    end)
end

function RARELOAD.AntiStuckSettings._CreateSettingsPanel()
    local THEME = getTheme()
    local currentSettings = RARELOAD.AntiStuckSettings.LoadSettings()
    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.Clamp(screenW * 0.5, 600, 800)
    local frameH = math.Clamp(screenH * 0.75, 550, 700)

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:SetBackgroundBlur(true)
    frame:SetName("AntiStuckSettingsPanel")

    local frameStartTime = SysTime()
    frame._openAnim = 0

    frame.Paint = function(self, w, h)
        local t = getTheme()
        self._openAnim = Lerp(FrameTime() * 8, self._openAnim, 1)
        
        Derma_DrawBackgroundBlur(self, frameStartTime)
        
        draw.RoundedBox(16, 4, 6, w, h, Color(0, 0, 0, 100 * self._openAnim))
        
        draw.RoundedBoxEx(14, 0, 0, w, h, t.background, true, true, false, false)
        draw.RoundedBoxEx(14, 0, 0, w, 70, t.headerGradientStart, true, true, false, false)
        
        local gradMat = Material("vgui/gradient-d")
        if not gradMat:IsError() then
            surface.SetMaterial(gradMat)
            surface.SetDrawColor(0, 0, 0, 60)
            surface.DrawTexturedRect(0, 0, w, 70)
        end
        
        surface.SetDrawColor(t.accent)
        surface.DrawRect(0, 68, w, 2)
        
        if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIconText then
            RARELOAD.AntiStuckTheme.DrawIconText("cog", "Anti-Stuck Configuration", 24, 24, 20, "RareloadTitle", t.textHighlight, t.textHighlight, 8, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        else
            draw.SimpleText("Anti-Stuck Configuration", "RareloadTitle", 24, 24, t.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        draw.SimpleText("Fine-tune the anti-stuck system behavior", "RareloadSmall", 24, 48, t.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(32, 32)
    closeBtn:SetPos(frameW - 44, 19)
    closeBtn:SetText("")
    closeBtn._hoverAnim = 0
    closeBtn.Paint = function(self, w, h)
        local t = getTheme()
        closeBtn._hoverAnim = Lerp(FrameTime() * 12, closeBtn._hoverAnim, self:IsHovered() and 1 or 0)
        
        local bgAlpha = 20 + closeBtn._hoverAnim * 80
        draw.RoundedBox(w / 2, 0, 0, w, h, Color(255, 95, 109, bgAlpha))
        
        local iconColor = Color(
            Lerp(closeBtn._hoverAnim, 150, 255),
            Lerp(closeBtn._hoverAnim, 155, 255),
            Lerp(closeBtn._hoverAnim, 175, 255)
        )
        
        surface.SetDrawColor(iconColor)
        local padding = 10
        for i = 0, 1 do
            surface.DrawLine(padding + i, padding, w - padding + i, h - padding)
            surface.DrawLine(w - padding + i, padding, padding + i, h - padding)
        end
    end
    closeBtn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        frame:AlphaTo(0, 0.15, 0, function() frame:Remove() end)
    end

    local toolbar = vgui.Create("DPanel", frame)
    toolbar:SetSize(frameW - 32, 50)
    toolbar:SetPos(16, 80)
    toolbar.Paint = function(self, w, h)
        local t = getTheme()
        draw.RoundedBox(10, 0, 0, w, h, t.surface)
        surface.SetDrawColor(t.panelBorder)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local searchContainer = vgui.Create("DPanel", toolbar)
    searchContainer:SetSize(180, 36)
    searchContainer:SetPos(8, 7)
    searchContainer._focusAnim = 0
    
    searchContainer.Paint = function(self, w, h)
        local t = getTheme()
        searchContainer._focusAnim = Lerp(FrameTime() * 10, searchContainer._focusAnim,
            (self._searchBox and self._searchBox:HasFocus()) and 1 or 0)
        
        local bgColor = Color(
            t.surfaceActive.r + searchContainer._focusAnim * 10,
            t.surfaceActive.g + searchContainer._focusAnim * 10,
            t.surfaceActive.b + searchContainer._focusAnim * 15,
            220
        )
        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        
        local borderColor = Color(
            Lerp(searchContainer._focusAnim, t.panelBorder.r, t.accent.r),
            Lerp(searchContainer._focusAnim, t.panelBorder.g, t.accent.g),
            Lerp(searchContainer._focusAnim, t.panelBorder.b, t.accent.b),
            100 + searchContainer._focusAnim * 100
        )
        surface.SetDrawColor(borderColor)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        
        if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIcon then
            RARELOAD.AntiStuckTheme.DrawIcon("search", 12, h / 2, 14, t.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    
    local searchBox = vgui.Create("DTextEntry", searchContainer)
    searchBox:SetSize(145, 28)
    searchBox:SetPos(28, 4)
    searchBox:SetFont("RareloadText")
    searchBox:SetPlaceholderText("Search...")
    searchBox:SetDrawBackground(false)
    searchBox:SetTextColor(THEME.textPrimary)
    searchBox:SetUpdateOnType(true)
    searchContainer._searchBox = searchBox

    local profileCombo = vgui.Create("DComboBox", toolbar)
    profileCombo:SetSize(140, 36)
    profileCombo:SetPos(198, 7)
    profileCombo:SetText("Default Profile")
    profileCombo:SetFont("RareloadText")

    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.GetProfilesList then
        local profiles = RARELOAD.AntiStuck.ProfileSystem.GetProfilesList()
        for _, profile in ipairs(profiles) do
            local displayText = profile.displayName or profile.name
            if profile.mapSpecific then displayText = displayText .. " 🗺️" end
            if profile.shared then displayText = displayText .. " 👥" end
            profileCombo:AddChoice(displayText, profile.name)
        end
        
        if RARELOAD.AntiStuck.ProfileSystem.currentProfile then
            local currentProfile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(RARELOAD.AntiStuck.ProfileSystem.currentProfile)
            if currentProfile then
                profileCombo:SetValue(currentProfile.displayName or "Default")
            end
        end
        
        profileCombo.OnSelect = function(self, index, value, data)
            if data and RARELOAD.AntiStuck.ProfileSystem.ApplyProfile then
                local success = RARELOAD.AntiStuck.ProfileSystem.ApplyProfile(data)
                if success then
                    notification.AddLegacy("Profile applied: " .. value, NOTIFY_GENERIC, 2)
                    timer.Simple(0.2, function()
                        RARELOAD.AntiStuckSettings.RefreshSettingsPanel()
                    end)
                end
            end
        end
    end

    local toolbarButtons = {
        { text = "New", icon = "+", color = THEME.accent, x = 348, width = 55, 
            func = function()
                if RARELOAD.AntiStuckSettings.OpenProfileCreationDialog then
                    RARELOAD.AntiStuckSettings.OpenProfileCreationDialog(currentSettings)
                end
            end
        },
        { text = "Import", icon = "↓", color = THEME.info, x = 410, width = 65,
            func = function()
                RARELOAD.AntiStuckSettings.ImportSettings(function(_) end)
            end
        },
        { text = "Export", icon = "↑", color = THEME.warning, x = 482, width = 65,
            func = function()
                RARELOAD.AntiStuckSettings.ExportSettings()
                notification.AddLegacy("Settings exported to clipboard!", NOTIFY_GENERIC, 2)
            end
        },
        { text = "Reset", icon = "↺", color = THEME.danger, x = 554, width = 60,
            func = function()
                for k, v in pairs(Default_Anti_Stuck_Settings or {}) do
                    currentSettings[k] = v
                end
                frame:Remove()
                timer.Simple(0, function() RARELOAD.AntiStuckSettings.OpenSettingsPanel() end)
            end
        },
    }
    
    for _, btn in ipairs(toolbarButtons) do
        local button = vgui.Create("DButton", toolbar)
        button:SetSize(btn.width, 36)
        button:SetPos(btn.x, 7)
        button:SetText("")
        button._hoverAnim = 0
        button._color = btn.color
        button._text = btn.text
        
        button.Paint = function(self, w, h)
            local t = getTheme()
            button._hoverAnim = Lerp(FrameTime() * 10, button._hoverAnim, self:IsHovered() and 1 or 0)
            
            local bgColor = ColorAlpha(button._color, 80 + button._hoverAnim * 120)
            draw.RoundedBox(8, 0, 0, w, h, bgColor)
            
            if button._hoverAnim > 0.1 then
                surface.SetDrawColor(255, 255, 255, 15 * button._hoverAnim)
                surface.DrawLine(8, 1, w - 8, 1)
            end
            
            draw.SimpleText(button._text, "RareloadSmall", w / 2, h / 2, t.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        button.DoClick = function()
            surface.PlaySound("ui/buttonclickrelease.wav")
            btn.func()
        end
    end

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(16, 140)
    scroll:SetSize(frameW - 32, frameH - 210)
    
    local scrollBar = scroll:GetVBar()
    scrollBar:SetWide(6)
    scrollBar:SetHideButtons(true)
    scrollBar.Paint = function(_, w, h)
        local t = getTheme()
        draw.RoundedBox(3, 0, 0, w, h, t.scrollTrack)
    end
    scrollBar.btnGrip.Paint = function(_, w, h)
        local t = getTheme()
        local color = scrollBar.btnGrip:IsHovered() and t.scrollThumbHover or t.scrollThumb
        draw.RoundedBox(3, 1, 0, w - 2, h, color)
    end

    local controls = {}
    local collapsedSections = {}
    local rebuildSettings

    local function addSectionHeader(text, groupKey, settingCount)
        local t = getTheme()
        local headerPanel = vgui.Create("DPanel", scroll)
        headerPanel:SetTall(42)
        headerPanel:Dock(TOP)
        headerPanel:DockMargin(0, 8, 12, 4)
        headerPanel:SetCursor("hand")
        headerPanel._hoverAnim = 0
        
        local isCollapsed = collapsedSections[groupKey] or false
        
        headerPanel.Paint = function(self, w, h)
            local theme = getTheme()
            self._hoverAnim = Lerp(FrameTime() * 10, self._hoverAnim, self:IsHovered() and 1 or 0)
            
            local bgColor = Color(
                theme.accent.r,
                theme.accent.g,
                theme.accent.b,
                180 + self._hoverAnim * 75
            )
            draw.RoundedBox(10, 0, 0, w, h, bgColor)
            
            surface.SetDrawColor(255, 255, 255, 15 + self._hoverAnim * 15)
            surface.DrawLine(10, 1, w - 10, 1)
            
            local arrowIcon = isCollapsed and "arrowRight" or "arrowDown"
            if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIcon then
                RARELOAD.AntiStuckTheme.DrawIcon(arrowIcon, 16, h / 2, 16, theme.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            
            draw.SimpleText(text, "RareloadHeading", 36, h / 2, theme.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            
            draw.RoundedBox(6, w - 55, (h - 22) / 2, 45, 22, Color(0, 0, 0, 60))
            draw.SimpleText(settingCount .. " items", "RareloadSmall", w - 32, h / 2, theme.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        
        headerPanel.OnMousePressed = function()
            surface.PlaySound("ui/buttonclick.wav")
            collapsedSections[groupKey] = not (collapsedSections[groupKey] or false)
            timer.Simple(0, function() rebuildSettings() end)
        end
        
        return not isCollapsed
    end

    local function addSettingRow(name, value)
        local t = getTheme()
        local container = vgui.Create("DPanel", scroll)
        container:SetTall(70)
        container:Dock(TOP)
        container:DockMargin(0, 0, 12, 4)
        container._hoverAnim = 0
        
        container.Paint = function(self, w, h)
            local theme = getTheme()
            self._hoverAnim = Lerp(FrameTime() * 8, self._hoverAnim, self:IsHovered() and 1 or 0)
            
            local bgColor = Color(
                theme.surface.r + self._hoverAnim * 8,
                theme.surface.g + self._hoverAnim * 8,
                theme.surface.b + self._hoverAnim * 10,
                230
            )
            draw.RoundedBox(8, 0, 0, w, h, bgColor)
            
            if self._hoverAnim > 0.1 then
                surface.SetDrawColor(255, 255, 255, 6 * self._hoverAnim)
                surface.DrawLine(8, 1, w - 8, 1)
            end
        end

        local nameLabel = vgui.Create("DLabel", container)
        nameLabel:SetText(name)
        nameLabel:SetFont("RareloadText")
        nameLabel:SetTextColor(THEME.textPrimary)
        nameLabel:SetPos(14, 12)
        nameLabel:SetSize(350, 20)

        local descLabel = vgui.Create("DLabel", container)
        descLabel:SetText(Descriptions[name] or "No description available")
        descLabel:SetFont("RareloadSmall")
        descLabel:SetTextColor(THEME.textMuted)
        descLabel:SetPos(14, 35)
        descLabel:SetSize(400, 20)

        local control
        local controlWidth = 180
        local controlX = frameW - controlWidth - 60
        
        if type(value) == "boolean" then
            control = vgui.Create("DButton", container)
            control:SetSize(52, 26)
            control:SetPos(controlX + 80, 22)
            control:SetText("")
            control._animValue = value and 1 or 0
            control._checked = value
            
            control.Paint = function(self, w, h)
                local theme = getTheme()
                control._animValue = Lerp(FrameTime() * 12, control._animValue, control._checked and 1 or 0)
                
                local offColor = Color(60, 60, 75, 255)
                local onColor = theme.success
                
                local trackColor = Color(
                    Lerp(control._animValue, offColor.r, onColor.r),
                    Lerp(control._animValue, offColor.g, onColor.g),
                    Lerp(control._animValue, offColor.b, onColor.b)
                )
                
                draw.RoundedBox(h / 2, 0, 0, w, h, trackColor)
                
                local thumbSize = h - 4
                local thumbX = 2 + control._animValue * (w - thumbSize - 4)
                
                draw.RoundedBox(thumbSize / 2, thumbX, 2, thumbSize, thumbSize, Color(255, 255, 255))
            end
            
            control.DoClick = function()
                control._checked = not control._checked
                surface.PlaySound("ui/buttonclick.wav")
            end
            
            control.GetChecked = function() return control._checked end
            control.SetChecked = function(self, val) control._checked = val end
            
        elseif name == "SEARCH_RESOLUTIONS" and type(value) == "table" then
            control = vgui.Create("DTextEntry", container)
            control:SetText(table.concat(value, ", "))
            control:SetPos(controlX, 20)
            control:SetSize(controlWidth, 30)
            control:SetFont("RareloadText")
            
        elseif type(value) == "number" and Ranges[name] then
            local sliderContainer = vgui.Create("DPanel", container)
            sliderContainer:SetSize(controlWidth + 50, 30)
            sliderContainer:SetPos(controlX - 30, 20)
            sliderContainer.Paint = nil
            
            local range = Ranges[name]
            local decimals = (range.step and range.step < 1) and 2 or 0
            
            control = vgui.Create("DNumSlider", sliderContainer)
            control:SetPos(-40, 0)
            control:SetSize(controlWidth + 40, 30)
            control:SetMin(range.min)
            control:SetMax(range.max)
            control:SetDecimals(decimals)
            control:SetValue(value)
            if control.Label then control.Label:SetVisible(false) end
            
            local valueLabel = vgui.Create("DLabel", sliderContainer)
            valueLabel:SetFont("RareloadText")
            valueLabel:SetTextColor(THEME.accent)
            valueLabel:SetSize(50, 20)
            valueLabel:SetPos(controlWidth, 5)
            valueLabel:SetContentAlignment(6)
            
            local function formatValue(v)
                if decimals > 0 then
                    return string.format("%." .. decimals .. "f", tonumber(v) or 0)
                else
                    return tostring(math.floor((tonumber(v) or 0) + 0.5))
                end
            end
            
            valueLabel:SetText(formatValue(value))
            control.OnValueChanged = function(_, v)
                valueLabel:SetText(formatValue(v))
            end
        else
            control = vgui.Create("DTextEntry", container)
            control:SetText(tostring(value))
            control:SetNumeric(type(value) == "number")
            control:SetPos(controlX, 20)
            control:SetSize(controlWidth, 30)
            control:SetFont("RareloadText")
        end
        
        controls[name] = control
    end

    rebuildSettings = function()
        scroll:Clear()
        controls = {}
        
        local function matchesSearch(name)
            local search = searchBox:GetValue():lower()
            if search == "" then return true end
            return name:lower():find(search, 1, true) or
                (Descriptions[name] and Descriptions[name]:lower():find(search, 1, true))
        end
        
        for group, keys in pairs(Groups) do
            local visibleKeys = {}
            for _, settingName in ipairs(keys) do
                if matchesSearch(settingName) then
                    table.insert(visibleKeys, settingName)
                end
            end
            
            if #visibleKeys > 0 then
                local open = addSectionHeader(group, group, #visibleKeys)
                if open then
                    for _, settingName in ipairs(visibleKeys) do
                        addSettingRow(settingName, currentSettings[settingName])
                    end
                end
            end
        end
    end

    rebuildSettings()

    local saveBtn = vgui.Create("DButton", frame)
    saveBtn:SetText("")
    saveBtn:SetSize(180, 48)
    saveBtn:SetPos(frameW / 2 - 90, frameH - 60)
    saveBtn._hoverAnim = 0
    saveBtn._pulseAnim = 0
    
    saveBtn.Paint = function(self, w, h)
        local t = getTheme()
        saveBtn._hoverAnim = Lerp(FrameTime() * 10, saveBtn._hoverAnim, self:IsHovered() and 1 or 0)
        saveBtn._pulseAnim = saveBtn._pulseAnim + FrameTime() * 3
        
        local pulse = math.sin(saveBtn._pulseAnim) * 0.5 + 0.5
        
        draw.RoundedBox(12, 2, 4, w, h, Color(0, 0, 0, 60 + saveBtn._hoverAnim * 40))
        
        local bgColor = Color(
            t.success.r + saveBtn._hoverAnim * 20,
            t.success.g + saveBtn._hoverAnim * 20,
            t.success.b + saveBtn._hoverAnim * 20,
            255
        )
        draw.RoundedBox(10, 0, 0, w, h, bgColor)
        
        if saveBtn._hoverAnim > 0.1 then
            surface.SetDrawColor(255, 255, 255, 30 * saveBtn._hoverAnim)
            surface.DrawLine(10, 1, w - 10, 1)
        end
        
        if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIconText then
            RARELOAD.AntiStuckTheme.DrawIconText("disk", "SAVE SETTINGS", w / 2, h / 2, 18, "RareloadHeading", t.textHighlight, t.textHighlight, 8, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("SAVE SETTINGS", "RareloadHeading", w / 2, h / 2, t.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    saveBtn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        local t = getTheme()
        local newSettings = {}
        local hasErrors = false
        
        for name, control in pairs(controls) do
            if control.GetChecked then
                newSettings[name] = control:GetChecked()
            elseif control.GetValue then
                local value = control:GetValue()
                if name == "SEARCH_RESOLUTIONS" and type(currentSettings[name]) == "table" then
                    local tbl = {}
                    for token in string.gmatch(tostring(value), "[^,%s]+") do
                        local n = tonumber(token)
                        if n then table.insert(tbl, n) end
                    end
                    if #tbl == 0 then hasErrors = true else newSettings[name] = tbl end
                elseif type(currentSettings[name]) == "number" then
                    newSettings[name] = tonumber(value) or currentSettings[name]
                else
                    newSettings[name] = value
                end
            end
        end
        
        if hasErrors then
            notification.AddLegacy("Validation errors found", NOTIFY_ERROR, 3)
            return
        end
        
        local success = RARELOAD.AntiStuckSettings.SaveSettings(newSettings)
        if success then
            notification.AddLegacy("Settings saved successfully!", NOTIFY_GENERIC, 2)
            
            local flash = vgui.Create("DPanel", frame)
            flash:SetSize(frameW, frameH)
            flash:SetPos(0, 0)
            flash:SetAlpha(0)
            flash.Paint = function(self, w, h)
                draw.RoundedBox(14, 0, 0, w, h, Color(72, 207, 133, 20))
            end
            flash:AlphaTo(255, 0.1, 0)
            timer.Simple(0.3, function()
                if IsValid(flash) then
                    flash:AlphaTo(0, 0.2, 0, function()
                        if IsValid(flash) then flash:Remove() end
                    end)
                end
            end)
        else
            notification.AddLegacy("Failed to save settings", NOTIFY_ERROR, 3)
        end
    end

    searchBox.OnValueChange = rebuildSettings

    frame.OnKeyCodePressed = function(self, key)
        if key == KEY_ESCAPE then
            frame:Close()
        elseif key == KEY_S and input.IsKeyDown(KEY_LCONTROL) then
            saveBtn:DoClick()
        end
    end

    return frame
end

concommand.Add("rareload_antistuck_settings", function()
    if RARELOAD.AntiStuckSettings.OpenSettingsPanel then
        RARELOAD.AntiStuckSettings.OpenSettingsPanel()
    end
end)

concommand.Add("rareload_profile_create", function()
    if RARELOAD.AntiStuckSettings.OpenProfileCreationDialog then
        local currentSettings = RARELOAD.AntiStuckSettings.LoadSettings()
        RARELOAD.AntiStuckSettings.OpenProfileCreationDialog(currentSettings)
    end
end)

concommand.Add("rareload_profile_manager", function()
    if RARELOAD.AntiStuckSettings.OpenProfileManager then
        RARELOAD.AntiStuckSettings.OpenProfileManager()
    end
end)
