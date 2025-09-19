---@diagnostic disable: inject-field, undefined-field, param-type-mismatch, assign-type-mismatch

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}

local THEME = THEME or {}
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
    local currentSettings = RARELOAD.AntiStuckSettings.LoadSettings()
    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.min(screenW * 0.65, 900)
    local frameH = math.min(screenH * 0.8, 750)

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:SetBackgroundBlur(true)
    frame:SetName("AntiStuckSettingsPanel")

    frame.Paint = function(self, w, h)
        draw.RoundedBox(12, 2, 2, w, h, Color(0, 0, 0, 100))
        draw.RoundedBox(12, 0, 0, w, h, THEME.background)
        draw.RoundedBoxEx(12, 0, 0, w, 80, THEME.primary, true, true, false, false)
        draw.SimpleText("Anti-Stuck Configuration", "RareloadTitle", 28, 25, THEME.textHighlight, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        draw.SimpleText("Advanced settings for the anti-stuck system", "RareloadBody", 28, 50, Color(255, 255, 255, 180),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetDrawColor(Color(255, 255, 255, 50))
        surface.DrawLine(0, 80, w, 80)
    end

    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(40, 40)
    closeBtn:SetPos(frameW - 50, 20)
    closeBtn:SetText("")
    local closeBtnState = { hoverAnim = 0 }
    closeBtn.Paint = function(self, w, h)
        closeBtnState.hoverAnim = Lerp(FrameTime() * 8, closeBtnState.hoverAnim, self:IsHovered() and 1 or 0)
        local bgColor = ColorAlpha(Color(255, 80, 80), 50 + closeBtnState.hoverAnim * 100)
        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        local textColor = Color(255, 255, 255, 150 + closeBtnState.hoverAnim * 105)
        draw.SimpleText("X", "RareloadHeading", w / 2, h / 2, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        frame:AlphaTo(0, 0.2, 0, function() frame:Remove() end)
    end

    local toolbar = vgui.Create("DPanel", frame)
    toolbar:SetSize(frameW - 40, 60)
    toolbar:SetPos(20, 90)
    toolbar.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.surfaceVariant)
        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local searchBox = vgui.Create("DTextEntry", toolbar)
    searchBox:SetSize(160, 32)
    searchBox:SetPos(45, 14)
    searchBox:SetFont("RareloadText")
    searchBox:SetPlaceholderText("Search settings...")
    searchBox:SetUpdateOnType(true)

    local searchIcon = vgui.Create("DLabel", toolbar)
    searchIcon:SetSize(32, 32)
    searchIcon:SetPos(10, 14)
    searchIcon:SetText("FIND")
    searchIcon:SetFont("RareloadSmall")
    searchIcon:SetTextColor(THEME.textSecondary)

    local profileCombo = vgui.Create("DComboBox", toolbar)
    profileCombo:SetSize(140, 32)
    profileCombo:SetPos(215, 14)
    profileCombo:SetText("Select Profile")
    profileCombo:SetFont("RareloadText")

    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.GetProfilesList then
        local profiles = RARELOAD.AntiStuck.ProfileSystem.GetProfilesList()
        for _, profile in ipairs(profiles) do
            local displayText = profile.displayName
            if profile.mapSpecific then displayText = displayText .. " (" .. profile.map .. ")" end
            if profile.shared then displayText = displayText .. " [Shared]" end
            profileCombo:AddChoice(displayText, profile.name)
        end
        if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.currentProfile then
            local currentProfile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(RARELOAD.AntiStuck.ProfileSystem
                .currentProfile)
            if currentProfile then profileCombo:SetValue(currentProfile.displayName or "Default Settings") end
        end
        profileCombo.OnSelect = function(self, index, value, data)
            if data and RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.ApplyProfile then
                local success = RARELOAD.AntiStuck.ProfileSystem.ApplyProfile(data)
                if success then
                    chat.AddText(Color(100, 255, 100), "[RARELOAD] ", Color(255, 255, 255), "Applied profile: " .. value)
                end
            end
        end
    end

    local resetFn
    local buttonData = {
        {
            text = "New Profile",
            pos = 365,
            width = 80,
            color = THEME.accent,
            func = function()
                if RARELOAD.AntiStuckSettings.OpenProfileCreationDialog then
                    RARELOAD.AntiStuckSettings.OpenProfileCreationDialog(currentSettings)
                end
            end
        },
        {
            text = "Export",
            pos = 465,
            width = 60,
            color = THEME.info,
            func = function()
                RARELOAD.AntiStuckSettings.ExportSettings()
                notification.AddLegacy("Settings exported to clipboard!", NOTIFY_GENERIC, 2)
            end
        },
        {
            text = "Import",
            pos = 535,
            width = 60,
            color = THEME.warning,
            func = function()
                RARELOAD.AntiStuckSettings.ImportSettings(function(_) end)
            end
        },
        {
            text = "Manage",
            pos = 605,
            width = 60,
            color = THEME.accent,
            func = function()
                if RARELOAD.AntiStuckSettings.OpenProfileManager then RARELOAD.AntiStuckSettings.OpenProfileManager() end
            end
        },
        {
            text = "Reset",
            pos = 675,
            width = 60,
            color = THEME.error,
            func = function()
                for k, v in pairs(Default_Anti_Stuck_Settings) do currentSettings[k] = v end
                frame:Remove()
                timer.Simple(0, function() RARELOAD.AntiStuckSettings.OpenSettingsPanel() end)
            end
        },
        {
            text = "Reload",
            pos = 745,
            width = 60,
            color = THEME.success,
            func = function()
                currentSettings = RARELOAD.AntiStuckSettings.LoadSettings()
                timer.Simple(0, function() RARELOAD.AntiStuckSettings.OpenSettingsPanel() end)
            end
        },
    }
    resetFn = buttonData[5].func

    for _, btn in ipairs(buttonData) do
        local button = vgui.Create("DButton", toolbar)
        button:SetSize(btn.width or 60, 32)
        button:SetPos(btn.pos, 14)
        button:SetText(btn.text)
        button:SetFont("RareloadSmall")
        local state = { hoverAnim = 0 }
        button.Paint = function(self, w, h)
            state.hoverAnim = Lerp(FrameTime() * 6, state.hoverAnim, self:IsHovered() and 1 or 0)
            local color = ColorAlpha(btn.color, 100 + state.hoverAnim * 100)
            draw.RoundedBox(6, 0, 0, w, h, color)
            draw.SimpleText(self:GetText(), "RareloadSmall", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        button.DoClick = function()
            surface.PlaySound("ui/buttonclickrelease.wav")
            btn.func()
        end
    end

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(20, 160)
    scroll:SetSize(frameW - 40, frameH - 230)
    local scrollBar = scroll:GetVBar()
    if IsValid(scrollBar) then
        if scrollBar.SetWide then scrollBar:SetWide(12) end
        scrollBar.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, THEME.backgroundDark) end
        local grip = scrollBar.btnGrip
        if grip and ispanel(grip) then
            function grip:Paint(w, h)
                local color = self:IsHovered() and THEME.primary or THEME.textSecondary
                draw.RoundedBox(6, 2, 0, w - 4, h, color)
            end
        end
    end

    local controls = {}
    local collapsedSections = {}
    local rebuildSettings

    local function addSectionHeader(text, groupKey)
        local headerPanel = vgui.Create("DPanel", scroll)
        headerPanel:SetTall(45)
        headerPanel:Dock(TOP)
        headerPanel:DockMargin(0, 10, 0, 5)
        headerPanel:SetCursor("hand")
        local isCollapsed = collapsedSections[groupKey] or false
        headerPanel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.primary)
            local arrow = isCollapsed and ">" or "v"
            draw.SimpleText(arrow, "RareloadText", 15, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(text, "RareloadTitle", 35, h / 2, THEME.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local sectionKeys = Groups[groupKey] or {}
            draw.SimpleText(#sectionKeys .. " settings", "RareloadSmall", w - 15, h / 2, Color(255, 255, 255, 180),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        headerPanel.OnMousePressed = function()
            surface.PlaySound("ui/buttonclick.wav")
            collapsedSections[groupKey] = not (collapsedSections[groupKey] or false)
            timer.Simple(0, function() rebuildSettings() end)
        end
        return not isCollapsed
    end

    local function addSettingRow(name, value)
        local container = vgui.Create("DPanel", scroll)
        container:SetTall(85)
        container:Dock(TOP)
        container:DockMargin(0, 2, 0, 2)
        container.Paint = function(self, w, h)
            local color = self:IsHovered() and THEME.surface or THEME.surfaceVariant
            draw.RoundedBox(6, 0, 0, w, h, color)
            surface.SetDrawColor(THEME.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        local nameLabel = vgui.Create("DLabel", container)
        nameLabel:SetText(name)
        nameLabel:SetFont("RareloadText")
        nameLabel:SetTextColor(THEME.textPrimary)
        nameLabel:SetPos(15, 10)
        nameLabel:SetSize(400, 20)

        local descLabel = vgui.Create("DLabel", container)
        descLabel:SetText(Descriptions[name] or "")
        descLabel:SetFont("RareloadSmall")
        descLabel:SetTextColor(THEME.textSecondary)
        descLabel:SetPos(15, 32)
        descLabel:SetSize(400, 15)

        local control
        local controlWidth = 250
        if type(value) == "boolean" then
            control = vgui.Create("DCheckBox", container)
            control:SetChecked(value)
            control:SetPos(frameW - 100, 25)
            control:SetSize(30, 30)
        elseif name == "SEARCH_RESOLUTIONS" and type(value) == "table" then
            control = vgui.Create("DTextEntry", container)
            control:SetText(table.concat(value, ", "))
            control:SetPos(frameW - controlWidth - 40, 25)
            control:SetSize(controlWidth, 30)
            control:SetFont("RareloadText")
        elseif type(value) == "number" and Ranges[name] then
            control = vgui.Create("DNumSlider", container)
            control:SetPos(frameW - controlWidth - 40, 25)
            control:SetSize(controlWidth, 30)
            local range = Ranges[name]
            local decimals = (range.step and range.step < 1) and 2 or 0
            control:SetMin(range.min)
            control:SetMax(range.max)
            control:SetDecimals(decimals)
            control:SetValue(value)
            if control.Label then control.Label:SetVisible(false) end

            local valueLabel = vgui.Create("DLabel", container)
            valueLabel:SetFont("RareloadText")
            valueLabel:SetTextColor(THEME.textPrimary)
            valueLabel:SetSize(60, 20)
            valueLabel:SetPos(frameW - 30 - valueLabel:GetWide(), 28)
            local function fmt(v)
                if decimals > 0 then
                    return string.format("%." .. decimals .. "f", tonumber(v) or 0)
                else
                    return tostring(math.floor((tonumber(v) or 0) + 0.5))
                end
            end
            valueLabel:SetText(fmt(value))
            if control.OnValueChanged then
                control.OnValueChanged = function(_, v)
                    valueLabel:SetText(fmt(v))
                end
            end
        else
            control = vgui.Create("DTextEntry", container)
            control:SetText(tostring(value))
            control:SetNumeric(type(value) == "number")
            control:SetPos(frameW - controlWidth - 40, 25)
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
            local anyVisible = false
            for _, settingName in ipairs(keys) do
                if matchesSearch(settingName) then
                    anyVisible = true
                    break
                end
            end
            if anyVisible then
                local open = addSectionHeader(group, group)
                if open then
                    for _, settingName in ipairs(keys) do
                        if matchesSearch(settingName) then
                            addSettingRow(settingName, currentSettings[settingName])
                        end
                    end
                end
            end
        end
    end

    rebuildSettings()

    local saveBtn = vgui.Create("DButton", frame)
    saveBtn:SetText("")
    saveBtn:SetFont("RareloadText")
    saveBtn:SetSize(200, 45)
    saveBtn:SetPos(frameW / 2 - 100, frameH - 60)
    local saveBtnState = { hoverAnim = 0 }
    saveBtn.Paint = function(self, w, h)
        saveBtnState.hoverAnim = Lerp(FrameTime() * 6, saveBtnState.hoverAnim, self:IsHovered() and 1 or 0)
        local color = Color(THEME.success.r + saveBtnState.hoverAnim * 20, THEME.success.g + saveBtnState.hoverAnim * 20,
            THEME.success.b + saveBtnState.hoverAnim * 20, 255)
        draw.RoundedBox(10, 0, 0, w, h, color)
        local shine = math.sin(CurTime() * 3) * 0.5 + 0.5
        draw.RoundedBox(10, 0, 0, w * shine * 0.3, h, Color(255, 255, 255, 30))
        draw.SimpleText("SAVE SETTINGS", "RareloadText", w / 2, h / 2, THEME.textHighlight, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    saveBtn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        local newSettings = {}
        local hasErrors = false
        for name, control in pairs(controls) do
            if control.GetChecked then
                newSettings[name] = control:GetChecked()
            elseif control.GetValue then
                local value = control:GetValue()
                if name == "SEARCH_RESOLUTIONS" and type(currentSettings[name]) == "table" then
                    local t = {}
                    for token in string.gmatch(tostring(value), "[^,%s]+") do
                        local n = tonumber(token)
                        if n then table.insert(t, n) end
                    end
                    if #t == 0 then hasErrors = true else newSettings[name] = t end
                elseif type(currentSettings[name]) == "number" then
                    newSettings[name] = tonumber(value) or currentSettings[name]
                else
                    newSettings[name] = value
                end
            end
        end
        if hasErrors then
            notification.AddLegacy("Validation errors found - check your inputs", NOTIFY_ERROR, 4)
            return
        end
        local success = RARELOAD.AntiStuckSettings.SaveSettings(newSettings)
        if success then
            notification.AddLegacy("Settings and profile updated successfully!", NOTIFY_GENERIC, 3)
            local successOverlay = vgui.Create("DPanel", frame)
            successOverlay:SetSize(frameW, frameH)
            successOverlay:SetPos(0, 0)
            successOverlay:SetAlpha(0)
            successOverlay.Paint = function(self, w, h)
                draw.RoundedBox(12, 0, 0, w, h, Color(100, 255, 100, 30))
            end
            successOverlay:AlphaTo(255, 0.1, 0)
            timer.Simple(0.5, function()
                if IsValid(successOverlay) then successOverlay:AlphaTo(0, 0.3, 0, function() successOverlay:Remove() end) end
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
        elseif key == KEY_R and input.IsKeyDown(KEY_LCONTROL) then
            if resetFn then resetFn() end
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
