-- Profile Creation Dialog - Modern Glass Design
-- Beautiful profile creation form with animations

---@diagnostic disable: inject-field, undefined-field, param-type-mismatch, assign-type-mismatch

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}

local function getTheme()
    return RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.GetTheme() or {}
end

function RARELOAD.AntiStuckSettings.CloseAllDialogs()
    local worldPanel = vgui.GetWorldPanel()
    if not IsValid(worldPanel) then return end
    for _, child in pairs(worldPanel:GetChildren()) do
        if IsValid(child) and child.GetName and 
           (child:GetName() == "AntiStuckSettingsPanel" or child:GetName() == "ProfileManagerDialog") then
            child:Close()
        end
    end
end

function RARELOAD.AntiStuckSettings.OpenProfileCreationDialog(initialSettings)
    local THEME = getTheme()
    if RARELOAD.AntiStuckSettings.CloseAllDialogs then RARELOAD.AntiStuckSettings.CloseAllDialogs() end

    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.Clamp(screenW * 0.35, 420, 500)
    local frameH = 380

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:SetBackgroundBlur(true)
    frame:SetName("ProfileManagerDialog")

    local frameStartTime = SysTime()
    frame._openAnim = 0

    frame.Paint = function(self, w, h)
        local t = getTheme()
        self._openAnim = Lerp(FrameTime() * 10, self._openAnim, 1)
        
        -- Background blur
        Derma_DrawBackgroundBlur(self, frameStartTime)
        
        -- Shadow
        draw.RoundedBox(14, 3, 5, w, h, Color(0, 0, 0, 100 * self._openAnim))
        
        -- Main background
        draw.RoundedBox(12, 0, 0, w, h, t.background)
        
        -- Header
        draw.RoundedBoxEx(12, 0, 0, w, 55, t.headerGradientStart, true, true, false, false)
        
        -- Header gradient
        local gradMat = Material("vgui/gradient-d")
        if not gradMat:IsError() then
            surface.SetMaterial(gradMat)
            surface.SetDrawColor(0, 0, 0, 50)
            surface.DrawTexturedRect(0, 0, w, 55)
        end
        
        -- Accent line
        surface.SetDrawColor(t.accent)
        surface.DrawRect(0, 53, w, 2)
        
        -- Title with Derma icon
        if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIconText then
            RARELOAD.AntiStuckTheme.DrawIconText("folderAdd", "Create New Profile", 20, 28, 18, "RareloadHeading", t.textHighlight, t.textHighlight, 8, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("Create New Profile", "RareloadHeading", 20, 28, t.textHighlight, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- Close button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPos(frameW - 40, 14)
    closeBtn:SetText("")
    closeBtn._hoverAnim = 0
    closeBtn.Paint = function(self, w, h)
        local t = getTheme()
        closeBtn._hoverAnim = Lerp(FrameTime() * 12, closeBtn._hoverAnim, self:IsHovered() and 1 or 0)
        
        draw.RoundedBox(w / 2, 0, 0, w, h, Color(255, 95, 109, 30 + closeBtn._hoverAnim * 100))
        
        local iconAlpha = Lerp(closeBtn._hoverAnim, 150, 255)
        surface.SetDrawColor(255, 255, 255, iconAlpha)
        local pad = 9
        surface.DrawLine(pad, pad, w - pad, h - pad)
        surface.DrawLine(w - pad, pad, pad, h - pad)
    end
    closeBtn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        frame:AlphaTo(0, 0.15, 0, function() frame:Close() end)
    end

    -- Form panel
    local panel = vgui.Create("DPanel", frame)
    panel:SetPos(16, 65)
    panel:SetSize(frameW - 32, frameH - 130)
    panel.Paint = function(self, w, h)
        local t = getTheme()
        draw.RoundedBox(10, 0, 0, w, h, t.surface)
        surface.SetDrawColor(t.panelBorder)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local y = 16
    local labelW, inputW = 100, panel:GetWide() - 130

    -- Input field helper
    local function addInputField(labelText, placeholder, yPos, isMultiline)
        local t = getTheme()
        
        local lbl = vgui.Create("DLabel", panel)
        lbl:SetPos(16, yPos + 4)
        lbl:SetSize(labelW, 24)
        lbl:SetFont("RareloadText")
        lbl:SetTextColor(t.textSecondary)
        lbl:SetText(labelText)

        local entry = vgui.Create("DTextEntry", panel)
        entry:SetPos(16 + labelW, yPos)
        entry:SetSize(inputW, isMultiline and 50 or 32)
        entry:SetFont("RareloadText")
        entry:SetPlaceholderText(placeholder)
        entry:SetMultiline(isMultiline or false)
        entry:SetDrawBackground(true)
        
        return entry
    end

    local nameEntry = addInputField("Name:", "e.g. my_profile", y)
    y = y + 42

    local displayEntry = addInputField("Display:", "Shown in UI (optional)", y)
    y = y + 42

    local descEntry = addInputField("Description:", "Short description (optional)", y, true)
    y = y + 64

    -- Checkboxes with modern styling
    local function createModernCheckbox(parent, text, yPos, default)
        local t = getTheme()
        
        local container = vgui.Create("DPanel", parent)
        container:SetPos(16, yPos)
        container:SetSize(parent:GetWide() - 32, 28)
        container.Paint = nil
        
        local checkbox = vgui.Create("DButton", container)
        checkbox:SetSize(22, 22)
        checkbox:SetPos(0, 3)
        checkbox:SetText("")
        checkbox._checked = default
        checkbox._animValue = default and 1 or 0
        
        checkbox.Paint = function(self, w, h)
            checkbox._animValue = Lerp(FrameTime() * 12, checkbox._animValue, checkbox._checked and 1 or 0)
            
            local bgColor = Color(
                Lerp(checkbox._animValue, 60, t.accent.r),
                Lerp(checkbox._animValue, 60, t.accent.g),
                Lerp(checkbox._animValue, 75, t.accent.b),
                255
            )
            
            draw.RoundedBox(6, 0, 0, w, h, bgColor)
            
            if checkbox._animValue > 0.1 then
                local checkAlpha = 255 * checkbox._animValue
                -- Draw checkmark using Derma icon
                if RARELOAD.AntiStuckTheme and RARELOAD.AntiStuckTheme.DrawIcon then
                    RARELOAD.AntiStuckTheme.DrawIcon("accept", w / 2, h / 2, 14, Color(255, 255, 255, checkAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    draw.SimpleText("v", "RareloadText", w / 2, h / 2 - 1, Color(255, 255, 255, checkAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end
        
        checkbox.DoClick = function()
            checkbox._checked = not checkbox._checked
            surface.PlaySound("ui/buttonclick.wav")
        end
        
        checkbox.GetChecked = function() return checkbox._checked end
        checkbox.SetChecked = function(self, val) checkbox._checked = val end
        
        local label = vgui.Create("DLabel", container)
        label:SetPos(30, 3)
        label:SetSize(container:GetWide() - 30, 22)
        label:SetFont("RareloadText")
        label:SetTextColor(t.textPrimary)
        label:SetText(text)
        label:SetCursor("hand")
        label.OnMousePressed = function()
            checkbox:DoClick()
        end
        
        return checkbox
    end

    local cloneCheckbox = createModernCheckbox(panel, "Clone current settings and methods", y, true)
    y = y + 32

    local setCurrentCheckbox = createModernCheckbox(panel, "Set as current profile after creation", y, true)

    -- Bottom buttons
    local btnCancel = vgui.Create("DButton", frame)
    btnCancel:SetSize(100, 40)
    btnCancel:SetPos(frameW / 2 - 110, frameH - 55)
    btnCancel:SetText("")
    btnCancel._hoverAnim = 0
    btnCancel.Paint = function(self, w, h)
        local t = getTheme()
        btnCancel._hoverAnim = Lerp(FrameTime() * 10, btnCancel._hoverAnim, self:IsHovered() and 1 or 0)
        
        local bgColor = Color(
            t.surface.r + btnCancel._hoverAnim * 15,
            t.surface.g + btnCancel._hoverAnim * 15,
            t.surface.b + btnCancel._hoverAnim * 20,
            255
        )
        
        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        surface.SetDrawColor(t.panelBorder)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        
        draw.SimpleText("Cancel", "RareloadText", w / 2, h / 2, t.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnCancel.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        frame:AlphaTo(0, 0.15, 0, function() frame:Close() end)
    end

    local btnCreate = vgui.Create("DButton", frame)
    btnCreate:SetSize(100, 40)
    btnCreate:SetPos(frameW / 2 + 10, frameH - 55)
    btnCreate:SetText("")
    btnCreate._hoverAnim = 0
    btnCreate.Paint = function(self, w, h)
        local t = getTheme()
        btnCreate._hoverAnim = Lerp(FrameTime() * 10, btnCreate._hoverAnim, self:IsHovered() and 1 or 0)
        
        local bgColor = Color(
            t.success.r + btnCreate._hoverAnim * 20,
            t.success.g + btnCreate._hoverAnim * 20,
            t.success.b + btnCreate._hoverAnim * 20,
            255
        )
        
        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        
        if btnCreate._hoverAnim > 0.1 then
            surface.SetDrawColor(255, 255, 255, 20 * btnCreate._hoverAnim)
            surface.DrawLine(8, 1, w - 8, 1)
        end
        
        draw.SimpleText("Create", "RareloadText", w / 2, h / 2, t.textHighlight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    
    btnCreate.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        
        local name = string.Trim(nameEntry:GetValue() or "")
        local display = string.Trim(displayEntry:GetValue() or "")
        local desc = string.Trim(descEntry:GetValue() or "")

        local function showError(reason) 
            notification.AddLegacy(reason, NOTIFY_ERROR, 3) 
        end

        if name == "" then return showError("Profile name cannot be empty") end
        if #name > 50 then return showError("Profile name too long (max 50)") end
        if name:find("[<>:\"/\\|?*]") then return showError("Name contains invalid characters") end
        
        if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.ProfileExists and 
           RARELOAD.AntiStuck.ProfileSystem.ProfileExists(name) then
            return showError("A profile with this name already exists")
        end

        if display == "" then display = name end

        local settings = cloneCheckbox:GetChecked() and
            table.Copy(initialSettings or RARELOAD.AntiStuckSettings.LoadSettings()) or
            table.Copy(Default_Anti_Stuck_Settings or {})
            
        local methods
        if cloneCheckbox:GetChecked() and RARELOAD.AntiStuckData and RARELOAD.AntiStuckData.GetMethods then
            methods = table.Copy(RARELOAD.AntiStuckData.GetMethods())
        else
            methods = table.Copy(Default_Anti_Stuck_Methods or {})
        end

        local profile = {
            name = name,
            displayName = display,
            description = desc,
            author = "User",
            version = "1.3",
            created = os.time(),
            modified = os.time(),
            methods = methods or {},
            settings = settings or {}
        }

        local ok, err = false, "Profile system not available"
        if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.SaveProfile then
            ok, err = RARELOAD.AntiStuck.ProfileSystem.SaveProfile(name, profile)
        end

        if ok then
            notification.AddLegacy("Profile '" .. display .. "' created!", NOTIFY_GENERIC, 2)
            
            if setCurrentCheckbox:GetChecked() and RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile then
                RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(name)
            end
            
            if RARELOAD.AntiStuck.ProfileManager and RARELOAD.AntiStuck.ProfileManager.RefreshList then
                timer.Simple(0, function() RARELOAD.AntiStuck.ProfileManager.RefreshList() end)
            end
            
            if RARELOAD.AntiStuckSettings and RARELOAD.AntiStuckSettings.RefreshSettingsPanel then
                timer.Simple(0.1, function() RARELOAD.AntiStuckSettings.RefreshSettingsPanel() end)
            end
            
            frame:AlphaTo(0, 0.15, 0, function() frame:Close() end)
        else
            notification.AddLegacy("Failed: " .. tostring(err or "Unknown error"), NOTIFY_ERROR, 4)
        end
    end

    -- Auto-sync display name
    local userEditedDisplay = false
    displayEntry.OnValueChange = function() userEditedDisplay = true end
    nameEntry.OnValueChange = function(self)
        if not userEditedDisplay then
            displayEntry:SetValue(self:GetValue() or "")
        end
    end

    timer.Simple(0.05, function()
        if IsValid(nameEntry) then nameEntry:RequestFocus() end
    end)

    return frame
end
