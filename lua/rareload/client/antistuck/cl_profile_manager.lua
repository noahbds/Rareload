RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}


-- Include the necessary files
include("rareload/client/entity_viewer/cl_entity_viewer_theme.lua")
include("rareload/client/antistuck/cl_profile_fileops.lua")

local THEME = THEME or {}

-- Helper function to check if the profile manager is currently open
function RARELOAD.AntiStuckSettings.IsProfileManagerOpen()
    local worldPanel = vgui.GetWorldPanel()
    if not IsValid(worldPanel) then return false end

    for _, child in pairs(worldPanel:GetChildren()) do
        if IsValid(child) and child.GetName and child:GetName() == "ProfileManagerDialog" then
            return true
        end
    end
    return false
end

function RARELOAD.AntiStuckSettings.OpenProfileManager()
    -- Prevent rapid successive calls
    if RARELOAD.AntiStuckSettings._openingProfileManager then return end
    RARELOAD.AntiStuckSettings._openingProfileManager = true

    -- Close any existing profile manager dialogs, but keep settings panel open
    local worldPanel = vgui.GetWorldPanel()
    if IsValid(worldPanel) then
        for _, child in pairs(worldPanel:GetChildren()) do
            if IsValid(child) and child.GetName and child:GetName() == "ProfileManagerDialog" then
                child:Close()
            end
        end
    end

    -- Add a small delay to ensure panels are fully closed
    timer.Simple(0.05, function()
        RARELOAD.AntiStuckSettings._openingProfileManager = false
        RARELOAD.AntiStuckSettings._CreateProfileManager()
    end)
end

-- Internal function to actually create the profile manager
function RARELOAD.AntiStuckSettings._CreateProfileManager()
    local screenW, screenH = ScrW(), ScrH()
    local frameW = 700
    local frameH = 600

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
        Derma_DrawBackgroundBlur(self, self.m_fCreateTime or SysTime())
        draw.RoundedBox(12, 0, 0, w, h, THEME.background or Color(35, 39, 54))

        -- Header
        draw.RoundedBoxEx(12, 0, 0, w, 60, THEME.header or Color(28, 32, 48), true, true, false, false)
        draw.SimpleText("Profile Manager", "RareloadTitle", w / 2, 30, THEME.textHighlight or Color(255, 255, 255),
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
    closeBtn.DoClick = function() frame:Close() end -- Optimized profile list with caching
    local listView = vgui.Create("DListView", frame)
    listView:SetPos(20, 80)
    listView:SetSize(frameW - 260, frameH - 120)
    listView:SetMultiSelect(false)
    listView:AddColumn("Name")
    listView:AddColumn("Description")
    listView:AddColumn("Author")
    listView:AddColumn("Type")
    listView:AddColumn("Modified")

    -- Cache for list entries to avoid recreating them
    local listCache = {}
    local lastProfileListHash = ""

    -- Optimized list refresh with incremental updates
    local function refreshList()
        if not profileSystem or not profileSystem.GetProfilesList then return end

        local profiles = profileSystem.GetProfilesList() or {}

        -- Create a hash of the profile list to detect changes (fixed to handle table values)
        local profileNames = {}
        for i, profile in ipairs(profiles) do
            if type(profile) == "table" and profile.name then
                profileNames[i] = profile.name
            elseif type(profile) == "string" then
                profileNames[i] = profile
            else
                profileNames[i] = tostring(profile)
            end
        end
        local currentHash = table.concat(profileNames, ",")

        if currentHash == lastProfileListHash and #listCache > 0 then
            -- No changes, skip refresh
            return
        end

        lastProfileListHash = currentHash
        listView:Clear()
        listCache = {}

        for _, profile in ipairs(profiles) do
            -- Handle both table format and string format profiles
            local profileData
            if type(profile) == "table" then
                profileData = profile
            else
                -- If it's just a name string, load the full profile
                profileData = profileSystem.LoadProfile(profile)
                if not profileData then
                    profileData = {
                        name = profile,
                        displayName = profile,
                        description = "",
                        author = "Unknown",
                        shared = false,
                        mapSpecific = false,
                        map = ""
                    }
                end
            end

            local typeStr = ""
            if profileData.shared then typeStr = typeStr .. "Shared " end
            if profileData.mapSpecific then typeStr = typeStr .. "Map-specific" end
            if typeStr == "" then typeStr = "Local" end -- Load the full profile data to get the modified date (with caching)
            local fullProfileData = profileSystem.LoadProfile(profileData.name)
            local modifiedStr = "Unknown"
            if fullProfileData and fullProfileData.modified and fullProfileData.modified > 0 then
                modifiedStr = tostring(os.date("%m/%d/%Y", fullProfileData.modified))
            end

            local line = listView:AddLine(profileData.displayName or profileData.name,
                profileData.description or "",
                profileData.author or "Unknown",
                typeStr,
                modifiedStr)
            line.profileName = profileData.name

            -- Cache the line for future use
            listCache[profileData.name] = {
                line = line,
                data = profileData,
                modified = fullProfileData and fullProfileData.modified or 0
            }
        end
    end

    refreshList()

    -- Action buttons panel
    local actionsPanel = vgui.Create("DPanel", frame)
    actionsPanel:SetPos(frameW - 220, 80)
    actionsPanel:SetSize(200, frameH - 120)
    actionsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.panel or Color(42, 47, 65))
    end

    local yPos = 15

    -- Apply button
    local applyBtn = vgui.Create("DButton", actionsPanel)
    applyBtn:SetSize(170, 35)
    applyBtn:SetPos(15, yPos)
    applyBtn:SetText("Apply Profile")
    applyBtn:SetFont("RareloadText")
    applyBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and THEME.accentHover or THEME.accent
        draw.RoundedBox(6, 0, 0, w, h, color or Color(88, 140, 240))
        draw.SimpleText(self:GetText(), "RareloadText", w / 2, h / 2, THEME.textHighlight or Color(255, 255, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    -- Utility: force refresh profile list and UI
    local function forceRefresh()
        if profileSystem then
            profileSystem._listDirty = true
        end
        refreshList()
        if RARELOAD.AntiStuckSettings.RefreshSettingsPanel then
            RARELOAD.AntiStuckSettings.RefreshSettingsPanel()
        elseif RARELOAD.AntiStuckSettings.OpenSettingsPanel then
            RARELOAD.AntiStuckSettings.OpenSettingsPanel()
        end
    end
    applyBtn.DoClick = function()
        local selectedLineNum = listView:GetSelectedLine()
        if selectedLineNum then
            local selected = listView:GetLine(selectedLineNum)
            local profileName = selected and selected:GetValue(1)
            if profileName and profileSystem then
                local success = profileSystem.SafeSwitchProfile and profileSystem.SafeSwitchProfile(profileName) or
                    profileSystem.ApplyProfile(profileName)
                if success then
                    chat.AddText(Color(100, 255, 100), "[RARELOAD] ", Color(255, 255, 255),
                        "Applied profile: " .. profileName)
                    timer.Simple(0.1, forceRefresh)
                else
                    chat.AddText(Color(255, 100, 100), "[RARELOAD] ", Color(255, 255, 255),
                        "Failed to apply profile")
                end
            end
        else
            notification.AddLegacy("Please select a profile to apply", NOTIFY_ERROR, 3)
        end
    end
    yPos = yPos + 45

    -- Duplicate button
    local duplicateBtn = vgui.Create("DButton", actionsPanel)
    duplicateBtn:SetSize(170, 35)
    duplicateBtn:SetPos(15, yPos)
    duplicateBtn:SetText("Duplicate")
    duplicateBtn:SetFont("RareloadText")
    duplicateBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and THEME.infoHover or THEME.info
        draw.RoundedBox(6, 0, 0, w, h, color or Color(185, 170, 255))
        draw.SimpleText(self:GetText(), "RareloadText", w / 2, h / 2, THEME.textHighlight or Color(255, 255, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    duplicateBtn.DoClick = function()
        local selectedLineNum = listView:GetSelectedLine()
        if selectedLineNum then
            local selected = listView:GetLine(selectedLineNum)
            local profileName = selected and selected:GetValue(1)
            if profileName and profileSystem and profileSystem.DuplicateProfile then
                Derma_StringRequest("Duplicate Profile", "Enter name for the duplicated profile:",
                    profileName .. "_copy",
                    function(text)
                        local success, error = profileSystem.DuplicateProfile(profileName, text .. "_dup", text)
                        if success then
                            forceRefresh()
                            chat.AddText(Color(100, 255, 100), "[RARELOAD] ", Color(255, 255, 255),
                                "Profile duplicated successfully")
                        else
                            Derma_Message("Failed to duplicate profile: " .. (error or "Unknown error"), "Error", "OK")
                        end
                    end)
            end
        else
            notification.AddLegacy("Please select a profile to duplicate", NOTIFY_ERROR, 3)
        end
    end
    yPos = yPos + 45

    -- Export button
    local exportBtn = vgui.Create("DButton", actionsPanel)
    exportBtn:SetSize(170, 35)
    exportBtn:SetPos(15, yPos)
    exportBtn:SetText("Export")
    exportBtn:SetFont("RareloadText")
    exportBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and THEME.warningHover or THEME.warning
        draw.RoundedBox(6, 0, 0, w, h, color or Color(255, 195, 85))
        draw.SimpleText(self:GetText(), "RareloadText", w / 2, h / 2, THEME.textHighlight or Color(255, 255, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    exportBtn.DoClick = function()
        local selectedLineNum = listView:GetSelectedLine()
        if selectedLineNum then
            local selected = listView:GetLine(selectedLineNum)
            local profileName = selected and selected:GetValue(1)
            if profileName and profileSystem and profileSystem.ExportProfile then
                local exportData = profileSystem.ExportProfile(profileName)
                if exportData then
                    SetClipboardText(exportData)
                    notification.AddLegacy("Profile exported to clipboard!", NOTIFY_GENERIC, 2)
                else
                    notification.AddLegacy("Export failed!", NOTIFY_ERROR, 3)
                end
            end
        else
            notification.AddLegacy("Please select a profile to export", NOTIFY_ERROR, 3)
        end
    end
    yPos = yPos + 45

    -- Delete button
    local deleteBtn = vgui.Create("DButton", actionsPanel)
    deleteBtn:SetSize(170, 35)
    deleteBtn:SetPos(15, yPos)
    deleteBtn:SetText("Delete")
    deleteBtn:SetFont("RareloadText")
    deleteBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and THEME.dangerHover or THEME.danger
        draw.RoundedBox(6, 0, 0, w, h, color or Color(245, 85, 85))
        draw.SimpleText(self:GetText(), "RareloadText", w / 2, h / 2, THEME.textHighlight or Color(255, 255, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    deleteBtn.DoClick = function()
        local selected = listView:GetSelectedLine()
        if not selected then
            notification.AddLegacy("No profile selected for deletion.", NOTIFY_ERROR, 2)
            surface.PlaySound("buttons/button10.wav")
            return
        end
        local row = listView:GetLine(selected)
        if not row then return end
        local profileName = row:GetValue(1)
        if not profileName or profileName == "default" then
            notification.AddLegacy("Cannot delete the default profile.", NOTIFY_ERROR, 2)
            surface.PlaySound("buttons/button10.wav")
            return
        end
        Derma_Query(
            "Are you sure you want to delete profile '" .. profileName .. "'? This cannot be undone.",
            "Delete Profile",
            "Delete",
            function()
                local success, err = profileSystem.DeleteProfile(profileName)
                if success then
                    notification.AddLegacy("Profile deleted: " .. profileName, NOTIFY_GENERIC, 2)
                    surface.PlaySound("buttons/button15.wav")
                    forceRefresh()
                else
                    notification.AddLegacy("Failed to delete profile: " .. (err or "Unknown error"), NOTIFY_ERROR, 2)
                    surface.PlaySound("buttons/button10.wav")
                end
            end,
            "Cancel"
        )
    end
    yPos = yPos + 60

    -- Info panel
    local infoPanel = vgui.Create("DPanel", actionsPanel)
    infoPanel:SetSize(170, 120)
    infoPanel:SetPos(15, yPos)
    infoPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.panelLight or Color(42, 47, 65))
        draw.SimpleText("Profile Info", "RareloadText", w / 2, 10, THEME.textHighlight or Color(255, 255, 255),
            TEXT_ALIGN_CENTER)
    end

    local infoText = vgui.Create("DLabel", infoPanel)
    infoText:SetPos(10, 30)
    infoText:SetSize(150, 80)
    infoText:SetText("Select a profile to view details")
    infoText:SetFont("RareloadSmall")
    infoText:SetTextColor(THEME.textSecondary or Color(190, 195, 215))
    infoText:SetWrap(true)

    -- Function to update info panel
    local function updateInfoPanel(profileName)
        print("[RARELOAD] Updating profile info for: " .. tostring(profileName)) -- Debug print

        if not profileName or not profileSystem then
            infoText:SetText("No profile selected")
            return
        end
        -- Try to get profile from cache first, then load if needed
        local profile = nil
        if profileSystem.LoadProfile then
            profile = profileSystem.LoadProfile(profileName)
            print("[RARELOAD] Profile loaded: " .. tostring(profile ~= nil)) -- Debug print
        else
            print("[RARELOAD] ProfileSystem.LoadProfile not available")      -- Debug print
        end

        if not profile then
            infoText:SetText("Failed to load profile data")
            print("[RARELOAD] Failed to load profile: " .. tostring(profileName)) -- Debug print
            return
        end

        -- Ensure profile has all required fields with defaults
        profile.created = profile.created or 0
        profile.modified = profile.modified or 0
        profile.author = profile.author or "Unknown"
        profile.version = profile.version or "1.0"
        profile.shared = profile.shared or false
        profile.mapSpecific = profile.mapSpecific or false

        -- Format the information with better error handling
        local createdDate = "Unknown"
        local modifiedDate = "Unknown"

        if profile.created and profile.created > 0 then
            createdDate = tostring(os.date("%m/%d/%Y", profile.created))
        end
        if profile.modified and profile.modified > 0 then
            modifiedDate = tostring(os.date("%m/%d/%Y", profile.modified))
        end

        local profileType = "Local"
        if profile.shared then
            profileType = "Shared"
        elseif profile.mapSpecific then
            profileType = "Map-specific"
        end

        local info = string.format("Created: %s\nModified: %s\nAuthor: %s\nVersion: %s\nType: %s",
            createdDate,
            modifiedDate,
            profile.author,
            profile.version,
            profileType
        )

        infoText:SetText(info)
    end
    -- Update info when selection changes
    listView.OnRowSelected = function(self, index, row)
        if not row then
            updateInfoPanel(nil)
            return
        end

        local profileName = row.profileName or row:GetValue(1)
        print("[RARELOAD] Profile selected: " .. tostring(profileName)) -- Debug print
        updateInfoPanel(profileName)
    end

    return frame
end
