-- Profile creation dialog extracted from settings panel
---@diagnostic disable: inject-field, undefined-field, param-type-mismatch, assign-type-mismatch

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}

local THEME = THEME or {}

function RARELOAD.AntiStuckSettings.CloseAllDialogs()
    local worldPanel = vgui.GetWorldPanel()
    if not IsValid(worldPanel) then return end
    for _, child in pairs(worldPanel:GetChildren()) do
        if IsValid(child) and child.GetName and (child:GetName() == "AntiStuckSettingsPanel" or child:GetName() == "ProfileManagerDialog") then
            child:Close()
        end
    end
end

function RARELOAD.AntiStuckSettings.OpenProfileCreationDialog(initialSettings)
    if RARELOAD.AntiStuckSettings.CloseAllDialogs then RARELOAD.AntiStuckSettings.CloseAllDialogs() end

    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.min(screenW * 0.4, 520)
    local frameH = 330

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:SetBackgroundBlur(true)
    frame:SetName("ProfileManagerDialog")

    frame.Paint = function(self, w, h)
        draw.RoundedBox(12, 0, 0, w, h, THEME.background or Color(32, 36, 44, 245))
        draw.RoundedBoxEx(12, 0, 0, w, 60, THEME.primary or Color(88, 140, 240), true, true, false, false)
        draw.SimpleText("Create New Profile", "RareloadTitle", 20, 30, THEME.textHighlight or color_white,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(36, 36)
    closeBtn:SetPos(frameW - 46, 12)
    closeBtn:SetText("")
    closeBtn.Paint = function(self, w, h)
        local c = self:IsHovered() and (THEME.error or Color(231, 76, 60)) or Color(180, 180, 180)
        draw.SimpleText("✕", "RareloadHeading", w / 2, h / 2, c, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function() frame:Close() end

    local panel = vgui.Create("DPanel", frame)
    panel:SetPos(20, 70)
    panel:SetSize(frameW - 40, frameH - 120)
    panel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.surfaceVariant or Color(45, 49, 58))
        surface.SetDrawColor(THEME.border or Color(70, 74, 84))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local y = 14
    local labelW, inputW = 110, panel:GetWide() - 130

    local function addLabel(text, yy)
        local lbl = vgui.Create("DLabel", panel)
        lbl:SetPos(12, yy)
        lbl:SetSize(labelW, 24)
        lbl:SetFont("RareloadText")
        lbl:SetTextColor(THEME.textPrimary or color_white)
        lbl:SetText(text)
        return lbl
    end

    addLabel("Internal name:", y)
    local nameEntry = vgui.Create("DTextEntry", panel)
    nameEntry:SetPos(12 + labelW, y)
    nameEntry:SetSize(inputW, 24)
    nameEntry:SetPlaceholderText("e.g. my_profile")
    nameEntry:SetUpdateOnType(true)
    y = y + 32

    addLabel("Display name:", y)
    local displayEntry = vgui.Create("DTextEntry", panel)
    displayEntry:SetPos(12 + labelW, y)
    displayEntry:SetSize(inputW, 24)
    displayEntry:SetPlaceholderText("Shown in UI (defaults to internal name)")
    y = y + 32

    addLabel("Description:", y)
    local descEntry = vgui.Create("DTextEntry", panel)
    descEntry:SetPos(12 + labelW, y)
    descEntry:SetSize(inputW, 54)
    descEntry:SetMultiline(true)
    descEntry:SetPlaceholderText("Short description of this profile (optional)")
    y = y + 64

    local cloneCheckbox = vgui.Create("DCheckBoxLabel", panel)
    cloneCheckbox:SetPos(12, y)
    cloneCheckbox:SetText("Clone current settings and methods")
    cloneCheckbox:SetFont("RareloadText")
    cloneCheckbox:SetTextColor(THEME.textPrimary or color_white)
    cloneCheckbox:SetChecked(true)
    y = y + 26

    local setCurrentCheckbox = vgui.Create("DCheckBoxLabel", panel)
    setCurrentCheckbox:SetPos(12, y)
    setCurrentCheckbox:SetText("Set as current profile after creation")
    setCurrentCheckbox:SetFont("RareloadText")
    setCurrentCheckbox:SetTextColor(THEME.textPrimary or color_white)
    setCurrentCheckbox:SetChecked(true)

    local btnCreate = vgui.Create("DButton", frame)
    btnCreate:SetSize(100, 32)
    btnCreate:SetPos(frameW - 120, frameH - 42)
    btnCreate:SetText("Create")
    btnCreate.DoClick = function()
        local name = string.Trim(nameEntry:GetValue() or "")
        local display = string.Trim(displayEntry:GetValue() or "")
        local desc = string.Trim(descEntry:GetValue() or "")

        local function invalid(reason) notification.AddLegacy(reason, NOTIFY_ERROR, 3) end

        if name == "" then return invalid("Profile name cannot be empty") end
        if #name > 50 then return invalid("Profile name too long (max 50)") end
        if name:find("[<>:\"/\\|?*]") then return invalid("Name contains invalid characters") end
        if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.ProfileExists and RARELOAD.AntiStuck.ProfileSystem.ProfileExists(name) then
            return invalid("A profile with this name already exists")
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
            local ok2, err2 = RARELOAD.AntiStuck.ProfileSystem.SaveProfile(name, profile)
            ok = ok2; err = err2 or err
        end

        if ok then
            chat.AddText(Color(100, 255, 100), "[RARELOAD] ", Color(255, 255, 255), "Profile '" .. display .. "' created")
            if setCurrentCheckbox:GetChecked() and RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile then
                RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(name)
            end
            if RARELOAD.AntiStuck.ProfileManager and RARELOAD.AntiStuck.ProfileManager.RefreshList then
                timer.Simple(0, function() RARELOAD.AntiStuck.ProfileManager.RefreshList() end)
            end
            if RARELOAD.AntiStuckSettings and RARELOAD.AntiStuckSettings.RefreshSettingsPanel then
                timer.Simple(0.1, function() RARELOAD.AntiStuckSettings.RefreshSettingsPanel() end)
            end
            frame:Close()
        else
            notification.AddLegacy("Failed to create profile: " .. tostring(err or "Unknown error"), NOTIFY_ERROR, 4)
        end
    end

    local btnCancel = vgui.Create("DButton", frame)
    btnCancel:SetSize(100, 32)
    btnCancel:SetPos(frameW - 230, frameH - 42)
    btnCancel:SetText("Cancel")
    btnCancel.DoClick = function() frame:Close() end

    local userEditedDisplay = false
    displayEntry.OnValueChange = function() userEditedDisplay = true end
    nameEntry.OnValueChange = function(self)
        local v = self:GetValue() or ""
        if not userEditedDisplay then displayEntry:SetValue(v) end
    end

    timer.Simple(0, function() if IsValid(nameEntry) then nameEntry:RequestFocus() end end)

    return frame
end
