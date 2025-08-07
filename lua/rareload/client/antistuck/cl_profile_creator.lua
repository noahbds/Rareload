RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}

-- Include the necessary files
include("rareload/client/entity_viewer/cl_entity_viewer_theme.lua")

local THEME = THEME or {}

-- Profile Creation Dialog
function RARELOAD.AntiStuckSettings.OpenProfileCreationDialog(currentSettings)
    local screenW, screenH = ScrW(), ScrH()
    local frameW = 500
    local frameH = 650

    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:SetBackgroundBlur(true)
    frame:SetName("ProfileCreationDialog")

    frame.Paint = function(self, w, h)
        Derma_DrawBackgroundBlur(self, self.m_fCreateTime)
        draw.RoundedBox(12, 0, 0, w, h, THEME.background or Color(35, 39, 54))

        -- Header
        draw.RoundedBoxEx(12, 0, 0, w, 60, THEME.header or Color(28, 32, 48), true, true, false, false)
        draw.SimpleText("Create New Profile", "RareloadTitle", w / 2, 30, THEME.textHighlight or Color(255, 255, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Divider
        surface.SetDrawColor(THEME.accent or Color(88, 140, 240))
        surface.DrawRect(0, 60, w, 2)
    end

    -- Close button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPos(frameW - 40, 15)
    closeBtn:SetText("")
    closeBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and THEME.danger or THEME.textSecondary
        draw.SimpleText("×", "RareloadTitle", w / 2, h / 2, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function() frame:Close() end

    local scrollPanel = vgui.Create("DScrollPanel", frame)
    scrollPanel:SetPos(20, 80)
    scrollPanel:SetSize(frameW - 40, frameH - 140)

    local yPos = 10

    -- Profile Name
    local nameLabel = vgui.Create("DLabel", scrollPanel)
    nameLabel:SetText("Profile Name *")
    nameLabel:SetFont("RareloadText")
    nameLabel:SetPos(0, yPos)
    nameLabel:SetTextColor(THEME.text or Color(235, 240, 255))
    nameLabel:SizeToContents()
    yPos = yPos + 25

    local nameEntry = vgui.Create("DTextEntry", scrollPanel)
    nameEntry:SetSize(460, 35)
    nameEntry:SetPos(0, yPos)
    nameEntry:SetFont("RareloadText")
    nameEntry:SetPlaceholderText("Enter profile name...")
    yPos = yPos + 50

    -- Display Name
    local displayLabel = vgui.Create("DLabel", scrollPanel)
    displayLabel:SetText("Display Name")
    displayLabel:SetFont("RareloadText")
    displayLabel:SetPos(0, yPos)
    displayLabel:SetTextColor(THEME.text or Color(235, 240, 255))
    displayLabel:SizeToContents()
    yPos = yPos + 25

    local displayEntry = vgui.Create("DTextEntry", scrollPanel)
    displayEntry:SetSize(460, 35)
    displayEntry:SetPos(0, yPos)
    displayEntry:SetFont("RareloadText")
    displayEntry:SetPlaceholderText("Display name (optional)")
    yPos = yPos + 50

    -- Description
    local descLabel = vgui.Create("DLabel", scrollPanel)
    descLabel:SetText("Description")
    descLabel:SetFont("RareloadText")
    descLabel:SetPos(0, yPos)
    descLabel:SetTextColor(THEME.text or Color(235, 240, 255))
    descLabel:SizeToContents()
    yPos = yPos + 25

    local descEntry = vgui.Create("DTextEntry", scrollPanel)
    descEntry:SetSize(460, 80)
    descEntry:SetPos(0, yPos)
    descEntry:SetFont("RareloadText")
    descEntry:SetMultiline(true)
    descEntry:SetPlaceholderText("Profile description (optional)")
    yPos = yPos + 95

    -- Checkboxes section
    local optionsPanel = vgui.Create("DPanel", scrollPanel)
    optionsPanel:SetSize(460, 200)
    optionsPanel:SetPos(0, yPos)
    optionsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.panel or Color(42, 47, 65))
        draw.SimpleText("Profile Options", "RareloadText", 15, 15, THEME.textHighlight or Color(255, 255, 255))
    end

    -- Shared checkbox
    local sharedCheck = vgui.Create("DCheckBox", optionsPanel)
    sharedCheck:SetPos(15, 45)
    sharedCheck:SetSize(20, 20)

    local sharedLabel = vgui.Create("DLabel", optionsPanel)
    sharedLabel:SetText("Share with all players")
    sharedLabel:SetFont("RareloadText")
    sharedLabel:SetPos(45, 47)
    sharedLabel:SetTextColor(THEME.text or Color(235, 240, 255))
    sharedLabel:SizeToContents()

    local sharedDesc = vgui.Create("DLabel", optionsPanel)
    sharedDesc:SetText("Send this profile to the server so all players can use it")
    sharedDesc:SetFont("RareloadSmall")
    sharedDesc:SetPos(45, 67)
    sharedDesc:SetTextColor(THEME.textSecondary or Color(190, 195, 215))
    sharedDesc:SizeToContents()

    -- Map specific checkbox
    local mapCheck = vgui.Create("DCheckBox", optionsPanel)
    mapCheck:SetPos(15, 90)
    mapCheck:SetSize(20, 20)

    local mapLabel = vgui.Create("DLabel", optionsPanel)
    mapLabel:SetText("Load on current map (" .. game.GetMap() .. ")")
    mapLabel:SetFont("RareloadText")
    mapLabel:SetPos(45, 92)
    mapLabel:SetTextColor(THEME.text or Color(235, 240, 255))
    mapLabel:SizeToContents()

    local mapDesc = vgui.Create("DLabel", optionsPanel)
    mapDesc:SetText("Add map prefix and auto-load when this map loads")
    mapDesc:SetFont("RareloadSmall")
    mapDesc:SetPos(45, 112)
    mapDesc:SetTextColor(THEME.textSecondary or Color(190, 195, 215))
    mapDesc:SizeToContents()

    -- Auto-load checkbox
    local autoLoadCheck = vgui.Create("DCheckBox", optionsPanel)
    autoLoadCheck:SetPos(15, 135)
    autoLoadCheck:SetSize(20, 20)

    local autoLoadLabel = vgui.Create("DLabel", optionsPanel)
    autoLoadLabel:SetText("Auto-load on join")
    autoLoadLabel:SetFont("RareloadText")
    autoLoadLabel:SetPos(45, 137)
    autoLoadLabel:SetTextColor(THEME.text or Color(235, 240, 255))
    autoLoadLabel:SizeToContents()

    local autoLoadDesc = vgui.Create("DLabel", optionsPanel)
    autoLoadDesc:SetText("Automatically apply this profile when joining the server")
    autoLoadDesc:SetFont("RareloadSmall")
    autoLoadDesc:SetPos(45, 157)
    autoLoadDesc:SetTextColor(THEME.textSecondary or Color(190, 195, 215))
    autoLoadDesc:SizeToContents()

    yPos = yPos + 220

    -- Buttons
    local buttonPanel = vgui.Create("DPanel", frame)
    buttonPanel:SetSize(frameW - 40, 50)
    buttonPanel:SetPos(20, frameH - 60)
    buttonPanel.Paint = nil
    local createBtn = vgui.Create("DButton", buttonPanel)
    createBtn:SetText("Create Profile")
    createBtn:SetFont("RareloadUI.Button")
    createBtn:SetSize(140, 40)
    createBtn:SetPos(320, 5)
    createBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and THEME.accentHover or THEME.accent
        draw.RoundedBox(8, 0, 0, w, h, color or Color(88, 140, 240))
        draw.SimpleText(self:GetText(), "RareloadUI.Button", w / 2, h / 2, THEME.textHighlight or Color(255, 255, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    createBtn.DoClick = function()
        local name = string.Trim(nameEntry:GetValue())
        if name == "" then
            Derma_Message("Please enter a profile name.", "Error", "OK")
            return
        end
        local profileData = {
            name = name,
            displayName = displayEntry:GetValue() ~= "" and displayEntry:GetValue() or name,
            description = descEntry:GetValue(),
            shared = sharedCheck:GetChecked(),
            mapSpecific = mapCheck:GetChecked(),
            autoLoad = autoLoadCheck:GetChecked(),
            settings = RARELOAD.AntiStuckSettings.LoadSettings(),
            methods = (function()
                local methods = (profileSystem and profileSystem.GetCurrentProfilemethods()) and
                    profileSystem.GetCurrentProfilemethods() or table.Copy(Default_Anti_Stuck_Methods)
                -- Ensure all methods have enabled field
                for _, method in ipairs(methods) do
                    if method.enabled == nil then
                        method.enabled = true
                    end
                end
                return methods
            end)()
        }

        -- Access the global profile system
        local success, result = profileSystem.CreateProfile(profileData)
        if success then
            frame:Close()
            chat.AddText(Color(100, 255, 100), "[RARELOAD] ", Color(255, 255, 255),
                "Profile created successfully: " .. profileData.displayName)

            -- Refresh the settings panel if it's open
            timer.Simple(0.1, function()
                if RARELOAD.AntiStuckSettings.IsSettingsPanelOpen and RARELOAD.AntiStuckSettings.IsSettingsPanelOpen() then
                    RARELOAD.AntiStuckSettings.OpenSettingsPanel()
                end
                -- Refresh the profile manager if it's open
                if RARELOAD.AntiStuckSettings.IsProfileManagerOpen and RARELOAD.AntiStuckSettings.IsProfileManagerOpen() then
                    if RARELOAD.AntiStuckSettings._CreateProfileManager then
                        RARELOAD.AntiStuckSettings._CreateProfileManager()
                    end
                end
            end)
        else
            Derma_Message("Failed to create profile: " .. result, "Error", "OK")
        end
    end
    local cancelBtn = vgui.Create("DButton", buttonPanel)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetFont("RareloadUI.Button")
    cancelBtn:SetSize(100, 40)
    cancelBtn:SetPos(210, 5)
    cancelBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and THEME.panelHover or THEME.panel
        draw.RoundedBox(8, 0, 0, w, h, color or Color(48, 54, 75))
        draw.SimpleText(self:GetText(), "RareloadUI.Button", w / 2, h / 2, THEME.text or Color(235, 240, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    cancelBtn.DoClick = function() frame:Close() end

    return frame
end
