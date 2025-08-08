RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}
RARELOAD.AntiStuck.ProfileManager = RARELOAD.AntiStuck.ProfileManager or {}

include("rareload/client/antistuck/cl_anti_stuck_theme.lua")

RARELOAD.AntiStuck.ProfileManager = {
    _frame = nil,
    _profileList = nil,
    _selectedProfile = nil,
    _isRefreshing = false,
    _lastRefresh = 0,
    _searchText = "",
    _sortMode = "lastUsed" -- lastUsed, name, usage
}

local REFRESH_COOLDOWN = 1.0
local THEME = RARELOAD.AntiStuck.Theme or {}

-- Helper functions
local function FormatTime(timestamp)
    if not timestamp or timestamp == 0 then return "Never" end
    local diff = os.time() - timestamp

    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. " minutes ago"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. " hours ago"
    else
        return math.floor(diff / 86400) .. " days ago"
    end
end

local function GetProfileIcon(profile)
    if profile.isCurrent then return "★" end
    if profile.usageCount > 10 then return "♦" end
    if profile.author == "System" then return "⚙" end
    return "◦"
end

local function CreateTooltip(parent, text)
    local tooltip = vgui.Create("DPanel")
    tooltip:SetSize(200, 60)
    tooltip:SetVisible(false)
    tooltip:SetDrawOnTop(true)

    tooltip.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(25, 25, 25, 240))
        draw.RoundedBox(8, 1, 1, w - 2, h - 2, Color(45, 45, 45, 200))
        draw.SimpleText(text, "DermaDefault", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    return tooltip
end

-- Profile list item
local function CreateProfileItem(parent, profile, index)
    local item = vgui.Create("DPanel", parent)
    item:SetSize(parent:GetWide() - 20, 60)
    item:SetPos(10, (index - 1) * 65 + 10)

    local isSelected = profile.name == RARELOAD.AntiStuck.ProfileManager._selectedProfile
    local isHovered = false
    local isLoading = false
    local lastClick = 0

    item.Paint = function(self, w, h)
        local bgColor = Color(40, 44, 52)
        local borderColor = Color(60, 64, 72)

        if isLoading then
            bgColor = Color(60, 60, 70)
            borderColor = Color(255, 165, 0) -- Orange for loading
        elseif isHovered then
            bgColor = Color(50, 54, 62)
            borderColor = Color(88, 140, 240, 100)
        end

        if isSelected then
            bgColor = Color(88, 140, 240, 50)
            borderColor = Color(88, 140, 240)
        end

        if profile.isCurrent then
            borderColor = Color(46, 204, 113)
        end

        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        draw.RoundedBox(8, 0, 0, w, h, Color(borderColor.r, borderColor.g, borderColor.b, 50))
        surface.SetDrawColor(borderColor)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        -- Icon
        local icon = isLoading and "⟳" or GetProfileIcon(profile)
        local iconColor = profile.isCurrent and Color(46, 204, 113) or Color(255, 255, 255)
        if isLoading then iconColor = Color(255, 165, 0) end
        draw.SimpleText(icon, "DermaDefaultBold", 15, h / 2, iconColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Profile name
        local nameColor = profile.isCurrent and Color(46, 204, 113) or Color(255, 255, 255)
        local displayName = (profile.displayName or profile.name)
        if isLoading then displayName = displayName .. " (Loading...)" end
        draw.SimpleText(displayName, "DermaDefaultBold", 35, 15, nameColor)

        -- Description and stats
        local desc = profile.description or "No description"
        if #desc > 50 then desc = string.sub(desc, 1, 47) .. "..." end
        draw.SimpleText(desc, "DermaDefault", 35, 32, Color(180, 180, 180))

        -- Usage info
        local usageText = string.format("Used %d times • %s", profile.usageCount or 0, FormatTime(profile.lastUsed))
        draw.SimpleText(usageText, "DermaDefault", w - 10, h - 15, Color(120, 120, 120), TEXT_ALIGN_RIGHT)

        -- Current indicator
        if profile.isCurrent then
            draw.SimpleText("ACTIVE", "DermaDefault", w - 10, 10, Color(46, 204, 113), TEXT_ALIGN_RIGHT)
        end
    end

    item.OnMousePressed = function(self, key)
        if key == MOUSE_LEFT and not isLoading then
            local currentTime = SysTime()
            local timeDiff = currentTime - lastClick

            if timeDiff < 0.5 and timeDiff > 0.1 then
                -- Valid double click - activate profile
                isLoading = true
                RARELOAD.AntiStuck.ProfileManager.ActivateProfile(profile.name, function(success)
                    isLoading = false
                    if not success then
                        chat.AddText(Color(231, 76, 60), "[Rareload] Failed to activate profile")
                    end
                end)
            else
                -- Single click - select
                RARELOAD.AntiStuck.ProfileManager._selectedProfile = profile.name
                RARELOAD.AntiStuck.ProfileManager.RefreshList()
            end
            lastClick = currentTime
        elseif key == MOUSE_RIGHT and not isLoading then
            RARELOAD.AntiStuck.ProfileManager.ShowContextMenu(profile, self)
        end
    end

    item.OnCursorEntered = function(self)
        isHovered = true
    end

    item.OnCursorExited = function(self)
        isHovered = false
    end

    return item
end

-- Context menu
function RARELOAD.AntiStuck.ProfileManager.ShowContextMenu(profile, parent)
    local menu = DermaMenu()

    if not profile.isCurrent then
        menu:AddOption("Activate Profile", function()
            RARELOAD.AntiStuck.ProfileManager.ActivateProfile(profile.name)
        end):SetIcon("icon16/accept.png")
    end

    menu:AddOption("Duplicate Profile", function()
        RARELOAD.AntiStuck.ProfileManager.DuplicateProfile(profile.name)
    end):SetIcon("icon16/page_copy.png")

    if profile.name ~= "default" then
        menu:AddOption("Rename Profile", function()
            RARELOAD.AntiStuck.ProfileManager.RenameProfile(profile.name)
        end):SetIcon("icon16/pencil.png")

        menu:AddSeparator()

        menu:AddOption("Delete Profile", function()
            RARELOAD.AntiStuck.ProfileManager.DeleteProfile(profile.name)
        end):SetIcon("icon16/delete.png")
    end

    menu:AddSeparator()

    menu:AddOption("Export Profile", function()
        RARELOAD.AntiStuck.ProfileManager.ExportProfile(profile.name)
    end):SetIcon("icon16/disk.png")

    menu:Open()
end

-- Profile operations
function RARELOAD.AntiStuck.ProfileManager.ActivateProfile(profileName, callback)
    if not RARELOAD.AntiStuck.ProfileSystem then
        local error = "Profile system not available"
        if callback then callback(false, error) end
        chat.AddText(Color(231, 76, 60), "[Rareload] ", Color(255, 255, 255), error)
        return
    end

    local success, err = RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(profileName)
    if success then
        chat.AddText(Color(46, 204, 113), "[Rareload] ", Color(255, 255, 255), "Activated profile: " .. profileName)
        RARELOAD.AntiStuck.ProfileManager.RefreshList()
        if callback then callback(true) end
    else
        local errorMsg = "Failed to activate profile: " .. (err or "Unknown error")
        chat.AddText(Color(231, 76, 60), "[Rareload] ", Color(255, 255, 255), errorMsg)
        if callback then callback(false, errorMsg) end
    end
end

function RARELOAD.AntiStuck.ProfileManager.DuplicateProfile(profileName)
    if not profileName or profileName == "" then
        chat.AddText(Color(231, 76, 60), "[Rareload] Invalid profile name")
        return
    end

    Derma_StringRequest(
        "Duplicate Profile",
        "Enter name for the duplicated profile:",
        profileName .. "_copy",
        function(newName)
            newName = string.Trim(newName)
            if #newName == 0 then
                chat.AddText(Color(231, 76, 60), "[Rareload] Profile name cannot be empty")
                return
            end

            if #newName > 50 then
                chat.AddText(Color(231, 76, 60), "[Rareload] Profile name too long (max 50 characters)")
                return
            end

            -- Check for invalid characters
            if string.match(newName, "[<>:\"/\\|?*]") then
                chat.AddText(Color(231, 76, 60), "[Rareload] Profile name contains invalid characters")
                return
            end

            if profileSystem.ProfileExists(newName) then
                chat.AddText(Color(231, 76, 60), "[Rareload] Profile with that name already exists")
                return
            end

            local originalProfile = profileSystem.LoadProfile(profileName)
            if not originalProfile then
                chat.AddText(Color(231, 76, 60), "[Rareload] Failed to load original profile")
                return
            end

            local newProfile = table.Copy(originalProfile)
            newProfile.name = newName
            newProfile.displayName = newName
            newProfile.author = "User"
            newProfile.created = os.time()
            newProfile.modified = os.time()
            newProfile.lastUsed = 0
            newProfile.usageCount = 0

            local success, err = RARELOAD.AntiStuck.ProfileSystem.SaveProfile(newName, newProfile)
            if success then
                chat.AddText(Color(46, 204, 113), "[Rareload] Profile duplicated successfully")
                RARELOAD.AntiStuck.ProfileManager.RefreshList()
            else
                chat.AddText(Color(231, 76, 60), "[Rareload] Failed to duplicate profile: " .. (err or "Unknown error"))
            end
        end
    )
end

function RARELOAD.AntiStuck.ProfileManager.RenameProfile(profileName)
    Derma_StringRequest(
        "Rename Profile",
        "Enter new name for the profile:",
        profileName,
        function(newName)
            newName = string.Trim(newName)
            if #newName == 0 or newName == profileName then return end

            local profile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(profileName)
            if not profile then
                chat.AddText(Color(231, 76, 60), "[Rareload] Failed to load profile")
                return
            end

            profile.name = newName
            profile.displayName = newName
            profile.modified = os.time()

            local success1 = RARELOAD.AntiStuck.ProfileSystem.SaveProfile(newName, profile)
            local success2 = true
            if profileName ~= "default" then
                success2 = RARELOAD.AntiStuck.ProfileSystem.DeleteProfile(profileName)
            end

            if success1 and success2 then
                if RARELOAD.AntiStuck.ProfileManager._selectedProfile == profileName then
                    RARELOAD.AntiStuck.ProfileManager._selectedProfile = newName
                end
                chat.AddText(Color(46, 204, 113), "[Rareload] Profile renamed successfully")
                RARELOAD.AntiStuck.ProfileManager.RefreshList()
            else
                chat.AddText(Color(231, 76, 60), "[Rareload] Failed to rename profile")
            end
        end
    )
end

function RARELOAD.AntiStuck.ProfileManager.DeleteProfile(profileName)
    if profileName == "default" then
        chat.AddText(Color(231, 76, 60), "[Rareload] Cannot delete the default profile")
        return
    end

    Derma_Query(
        "Are you sure you want to delete the profile '" .. profileName .. "'?\nThis action cannot be undone.",
        "Delete Profile",
        "Delete",
        function()
            local success, err = RARELOAD.AntiStuck.ProfileSystem.DeleteProfile(profileName)
            if success then
                chat.AddText(Color(46, 204, 113), "[Rareload] Profile deleted successfully")
                if RARELOAD.AntiStuck.ProfileManager._selectedProfile == profileName then
                    RARELOAD.AntiStuck.ProfileManager._selectedProfile = nil
                end
                RARELOAD.AntiStuck.ProfileManager.RefreshList()
            else
                chat.AddText(Color(231, 76, 60), "[Rareload] Failed to delete profile: " .. (err or "Unknown error"))
            end
        end,
        "Cancel"
    )
end

function RARELOAD.AntiStuck.ProfileManager.ExportProfile(profileName)
    local profile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(profileName)
    if not profile then
        chat.AddText(Color(231, 76, 60), "[Rareload] Failed to load profile for export")
        return
    end

    local exportData = util.TableToJSON(profile, true)
    SetClipboardText(exportData)
    chat.AddText(Color(46, 204, 113), "[Rareload] Profile data copied to clipboard")
end

-- List management
function RARELOAD.AntiStuck.ProfileManager.RefreshList()
    if not IsValid(RARELOAD.AntiStuck.ProfileManager._profileList) then return end
    if RARELOAD.AntiStuck.ProfileManager._isRefreshing then return end
    if SysTime() - RARELOAD.AntiStuck.ProfileManager._lastRefresh < REFRESH_COOLDOWN then return end

    RARELOAD.AntiStuck.ProfileManager._isRefreshing = true
    RARELOAD.AntiStuck.ProfileManager._lastRefresh = SysTime()

    -- Clear existing items safely
    if IsValid(RARELOAD.AntiStuck.ProfileManager._profileList) then
        RARELOAD.AntiStuck.ProfileManager._profileList:Clear()
    else
        RARELOAD.AntiStuck.ProfileManager._isRefreshing = false
        return
    end

    -- Get profiles with error handling
    local profiles = {}
    if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.GetProfileList then
        local success, result = pcall(RARELOAD.AntiStuck.ProfileSystem.GetProfileList)
        if success and result then
            profiles = result
        else
            print("[ProfileManager] Error getting profile list:", result)
            RARELOAD.AntiStuck.ProfileManager._isRefreshing = false
            return
        end
    else
        print("[ProfileManager] Profile system not available")
        RARELOAD.AntiStuck.ProfileManager._isRefreshing = false
        return
    end

    -- Filter by search
    if RARELOAD.AntiStuck.ProfileManager._searchText ~= "" then
        local filtered = {}
        local searchLower = string.lower(RARELOAD.AntiStuck.ProfileManager._searchText)
        for _, profile in ipairs(profiles) do
            if profile and profile.name then
                local name = string.lower(profile.displayName or profile.name)
                local desc = string.lower(profile.description or "")
                if string.find(name, searchLower, 1, true) or string.find(desc, searchLower, 1, true) then
                    table.insert(filtered, profile)
                end
            end
        end
        profiles = filtered
    end

    -- Sort profiles safely
    if RARELOAD.AntiStuck.ProfileManager._sortMode == "name" then
        table.sort(profiles, function(a, b)
            if not a or not b then return false end
            return (a.displayName or a.name or "") < (b.displayName or b.name or "")
        end)
    elseif RARELOAD.AntiStuck.ProfileManager._sortMode == "usage" then
        table.sort(profiles, function(a, b)
            if not a or not b then return false end
            return (a.usageCount or 0) > (b.usageCount or 0)
        end)
    else -- lastUsed
        table.sort(profiles, function(a, b)
            if not a or not b then return false end
            return (a.lastUsed or 0) > (b.lastUsed or 0)
        end)
    end

    -- Create profile items with error handling
    local itemCount = 0
    for i, profile in ipairs(profiles) do
        if profile and profile.name then
            local success, item = pcall(CreateProfileItem, RARELOAD.AntiStuck.ProfileManager._profileList, profile, i)
            if success then
                itemCount = itemCount + 1
            else
                print("[ProfileManager] Error creating profile item:", item)
            end
        end
    end

    -- Update list size
    if IsValid(RARELOAD.AntiStuck.ProfileManager._profileList) then
        RARELOAD.AntiStuck.ProfileManager._profileList:SetTall(math.max(itemCount * 65 + 20, 200))
    end

    RARELOAD.AntiStuck.ProfileManager._isRefreshing = false
end

-- Main UI creation
function RARELOAD.AntiStuck.ProfileManager.Create()
    if IsValid(RARELOAD.AntiStuck.ProfileManager._frame) then
        RARELOAD.AntiStuck.ProfileManager._frame:Close()
    end

    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.min(600, screenW * 0.7)
    local frameH = math.min(500, screenH * 0.8)

    -- Main frame
    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:SetBackgroundBlur(true)

    frame.Paint = function(self, w, h)
        Derma_DrawBackgroundBlur(self, self.m_fCreateTime or SysTime())
        draw.RoundedBox(12, 0, 0, w, h, Color(35, 39, 54, 240))

        -- Header
        draw.RoundedBoxEx(12, 0, 0, w, 50, Color(28, 32, 48), true, true, false, false)
        draw.SimpleText("Profile Manager", "DermaDefaultBold", w / 2, 25, Color(255, 255, 255), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)

        -- Border
        surface.SetDrawColor(Color(88, 140, 240))
        surface.DrawRect(0, 50, w, 2)
    end

    RARELOAD.AntiStuck.ProfileManager._frame = frame

    -- Close button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPos(frameW - 40, 10)
    closeBtn:SetText("")
    closeBtn.Paint = function(self, w, h)
        local color = self:IsHovered() and Color(231, 76, 60) or Color(180, 180, 180)
        draw.SimpleText("✕", "DermaDefaultBold", w / 2, h / 2, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function() frame:Close() end

    -- Search box
    local searchBox = vgui.Create("DTextEntry", frame)
    searchBox:SetSize(200, 25)
    searchBox:SetPos(20, 60)
    searchBox:SetPlaceholderText("Search profiles...")
    searchBox.OnValueChange = function(self)
        RARELOAD.AntiStuck.ProfileManager._searchText = self:GetValue()
        timer.Simple(0.3, function()
            if self:GetValue() == RARELOAD.AntiStuck.ProfileManager._searchText then
                RARELOAD.AntiStuck.ProfileManager.RefreshList()
            end
        end)
    end

    -- Sort dropdown
    local sortCombo = vgui.Create("DComboBox", frame)
    sortCombo:SetSize(120, 25)
    sortCombo:SetPos(frameW - 150, 60)
    sortCombo:AddChoice("Recent", "lastUsed", true)
    sortCombo:AddChoice("Name", "name")
    sortCombo:AddChoice("Usage", "usage")
    sortCombo.OnSelect = function(self, index, value, data)
        RARELOAD.AntiStuck.ProfileManager._sortMode = data
        RARELOAD.AntiStuck.ProfileManager.RefreshList()
    end

    -- Refresh button
    local refreshBtn = vgui.Create("DButton", frame)
    refreshBtn:SetSize(25, 25)
    refreshBtn:SetPos(frameW - 50, 60)
    refreshBtn:SetText("↻")
    refreshBtn.DoClick = function()
        RARELOAD.AntiStuck.ProfileManager._lastRefresh = 0
        RARELOAD.AntiStuck.ProfileManager.RefreshList()
    end

    -- Profile list (scrollable)
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetSize(frameW - 40, frameH - 140)
    scroll:SetPos(20, 95)

    local listPanel = vgui.Create("DPanel", scroll)
    listPanel:SetSize(frameW - 60, 200)
    listPanel.Paint = function() end

    RARELOAD.AntiStuck.ProfileManager._profileList = listPanel

    -- Bottom buttons
    local btnY = frameH - 35

    local newBtn = vgui.Create("DButton", frame)
    newBtn:SetSize(80, 25)
    newBtn:SetPos(20, btnY)
    newBtn:SetText("New")
    newBtn.DoClick = function()
        RARELOAD.AntiStuck.ProfileManager.CreateNewProfile()
    end

    local importBtn = vgui.Create("DButton", frame)
    importBtn:SetSize(80, 25)
    importBtn:SetPos(110, btnY)
    importBtn:SetText("Import")
    importBtn.DoClick = function()
        RARELOAD.AntiStuck.ProfileManager.ImportProfile()
    end

    -- Initialize
    RARELOAD.AntiStuck.ProfileManager.RefreshList()

    return frame
end

function RARELOAD.AntiStuck.ProfileManager.CreateNewProfile()
    Derma_StringRequest(
        "New Profile",
        "Enter name for the new profile:",
        "",
        function(name)
            name = string.Trim(name)
            if #name == 0 then return end

            local newProfile = {
                name = name,
                displayName = name,
                description = "Custom profile",
                author = "User",
                created = os.time(),
                modified = os.time(),
                methods = {
                    { name = "space_scan",   enabled = true, priority = 10 },
                    { name = "displacement", enabled = true, priority = 20 },
                    { name = "spawn_points", enabled = true, priority = 30 }
                },
                settings = {
                    maxAttempts = 10,
                    timeout = 5,
                    debug = false
                }
            }

            local success, err = RARELOAD.AntiStuck.ProfileSystem.SaveProfile(name, newProfile)
            if success then
                chat.AddText(Color(46, 204, 113), "[Rareload] Profile created successfully")
                RARELOAD.AntiStuck.ProfileManager.RefreshList()
            else
                chat.AddText(Color(231, 76, 60), "[Rareload] Failed to create profile: " .. (err or "Unknown error"))
            end
        end
    )
end

function RARELOAD.AntiStuck.ProfileManager.ImportProfile()
    Derma_StringRequest(
        "Import Profile",
        "Paste profile data (JSON):",
        "",
        function(data)
            data = string.Trim(data)
            if #data == 0 then return end

            local success, profile = pcall(util.JSONToTable, data)
            if not success or not profile or not profile.name then
                chat.AddText(Color(231, 76, 60), "[Rareload] Invalid profile data")
                return
            end

            local result, err = RARELOAD.AntiStuck.ProfileSystem.SaveProfile(profile.name, profile)
            if result then
                chat.AddText(Color(46, 204, 113), "[Rareload] Profile imported successfully")
                RARELOAD.AntiStuck.ProfileManager.RefreshList()
            else
                chat.AddText(Color(231, 76, 60), "[Rareload] Failed to import profile: " .. (err or "Unknown error"))
            end
        end
    )
end

-- Profile Manager for the anti-stuck system
function RARELOAD.AntiStuckSettings.OpenProfileManager()
    if RARELOAD.AntiStuck.ProfileManager.IsOpen() then
        RARELOAD.AntiStuck.ProfileManager._frame:Close()
    else
        RARELOAD.AntiStuck.ProfileManager.Create()
    end
end

function RARELOAD.AntiStuck.ProfileManager.IsOpen()
    return IsValid(RARELOAD.AntiStuck.ProfileManager._frame)
end
