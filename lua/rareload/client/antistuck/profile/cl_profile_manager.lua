---@diagnostic disable: inject-field, undefined-field, param-type-mismatch, assign-type-mismatch
RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}
RARELOAD.AntiStuck.ProfileManager = RARELOAD.AntiStuck.ProfileManager or {}

-- Modern Profile Manager with Enhanced UI and Functionality
local PM = RARELOAD.AntiStuck.ProfileManager

-- Reset the manager
PM._frame = nil
PM._profileList = nil
PM._detailPanel = nil
PM._selectedProfile = nil
PM._isRefreshing = false
PM._lastRefresh = 0
PM._searchText = ""
PM._sortMode = "lastUsed"
PM._viewMode = "list"
PM._profileCache = {}
PM._lastCacheUpdate = 0
PM._cacheCount = 0

-- Constants
PM.REFRESH_COOLDOWN = 0.5
PM.CACHE_DURATION = 5

-- Modern Color Scheme
PM.COLORS = {
    background = Color(28, 32, 38),
    panel = Color(42, 47, 56),
    panelLight = Color(52, 58, 70),
    accent = Color(74, 144, 226),
    accentHover = Color(94, 164, 246),
    success = Color(46, 204, 113),
    warning = Color(241, 196, 15),
    danger = Color(231, 76, 60),
    text = Color(255, 255, 255),
    textSecondary = Color(180, 180, 180),
    textMuted = Color(120, 120, 120),
    border = Color(60, 68, 82),
    hover = Color(62, 70, 84),
    active = Color(74, 144, 226, 30)
}

-- Utility Functions
local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        print("[ProfileManager] Error:", result)
        return false, result
    end
    return true, result
end

local function FormatTime(timestamp)
    if not timestamp or timestamp == 0 then return "Never" end
    local diff = os.time() - timestamp

    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m ago"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. "h ago"
    else
        return math.floor(diff / 86400) .. "d ago"
    end
end

local function GetProfileIcon(profile)
    if profile.isCurrent then
        return "★"
    elseif profile.usageCount and profile.usageCount > 10 then
        return "♦"
    elseif profile.author == "System" then
        return "⚙"
    else
        return "●"
    end
end

-- Utility: color adjuster and text wrapper
local function ClampByte(n) return math.max(0, math.min(255, n)) end
function PM.AdjustColor(c, delta)
    return Color(ClampByte(c.r + delta), ClampByte(c.g + delta), ClampByte(c.b + delta), c.a or 255)
end

function PM.DrawWrappedText(text, font, x, y, maxW, color)
    surface.SetFont(font)
    local words = string.Explode(" ", text or "")
    local line, nextY = "", y
    for i = 1, #words do
        local w = words[i]
        local test = (line == "" and w) or (line .. " " .. w)
        local tw = surface.GetTextSize(test)
        if tw > maxW and line ~= "" then
            draw.SimpleText(line, font, x, nextY, color)
            line = w
            nextY = nextY + 15
        else
            line = test
        end
    end
    if line ~= "" then
        draw.SimpleText(line, font, x, nextY, color)
        nextY = nextY + 15
    end
    return nextY
end

function PM.LayoutProfileList()
    if not IsValid(PM._profileList) then return end
    local y = 10
    local w = PM._profileList:GetWide()
    for _, child in ipairs(PM._profileList:GetChildren() or {}) do
        if IsValid(child) then
            child:SetPos(10, y)
            child:SetWide(w - 20)
            y = y + child:GetTall() + 5
        end
    end
    PM._profileList:SetTall(math.max(y + 10, 200))
end

-- Modern Button Creation Function (simplified and de-duplicated)
function PM.CreateModernButton(parent, text, x, y, w, h, color, onClick, tooltip)
    local btn = vgui.Create("DButton", parent)
    btn:SetPos(x, y)
    btn:SetSize(w, h)
    btn:SetText("")
    btn:SetCursor("hand")

    btn.Paint = function(self, width, height)
        local bg = self:IsDown() and PM.AdjustColor(color, -30)
            or (self:IsHovered() and PM.AdjustColor(color, 20) or color)
        draw.RoundedBox(6, 0, 0, width, height, bg)
        if self:IsHovered() then
            draw.RoundedBox(6, 0, 0, width, height, Color(255, 255, 255, 10))
        end
        draw.SimpleText(text, "DermaDefaultBold", width / 2, height / 2, PM.COLORS.text, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    if tooltip then
        btn.OnCursorEntered = function(self) PM.ShowTooltip(tooltip, self) end
        btn.OnCursorExited = function() PM.HideTooltip() end
    end

    if onClick then
        function btn:DoClick() onClick() end
    end

    return btn
end

-- Simple Modern Button Creation Function (uses AdjustColor)
function PM.CreateSimpleButton(parent, text, x, y, w, h, color, onClick)
    local btn = vgui.Create("DButton", parent)
    btn:SetPos(x, y)
    btn:SetSize(w, h)
    btn:SetText("")
    btn.Paint = function(self, width, height)
        local bg = self:IsHovered() and PM.AdjustColor(color, 20) or color
        draw.RoundedBox(6, 0, 0, width, height, bg)
        draw.SimpleText(text, "DermaDefaultBold", width / 2, height / 2, PM.COLORS.text, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    if onClick then function btn:DoClick() onClick() end end
    return btn
end

-- Tooltip System (follow cursor while hovered)
PM._tooltip = nil
function PM.ShowTooltip(text, parent)
    PM.HideTooltip()
    timer.Simple(0.7, function()
        if not IsValid(parent) or not parent:IsHovered() then return end
        PM._tooltip = vgui.Create("DPanel")
        PM._tooltip:SetSize(math.max(150, string.len(text) * 7 + 20), 35)
        PM._tooltip:SetDrawOnTop(true)
        PM._tooltip:SetZPos(1000)
        PM._tooltip.Think = function(self)
            if not IsValid(parent) or not parent:IsHovered() then
                PM.HideTooltip()
                return
            end
            local mx, my = gui.MouseX(), gui.MouseY()
            self:SetPos(mx + 15, my - 40)
        end
        PM._tooltip.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(25, 25, 25, 250))
            draw.RoundedBox(8, 1, 1, w - 2, h - 2, Color(45, 45, 45, 100))
            draw.SimpleText(text, "DermaDefault", w / 2, h / 2, PM.COLORS.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end)
end

function PM.HideTooltip()
    if IsValid(PM._tooltip) then
        PM._tooltip:Remove()
        PM._tooltip = nil
    end
end

-- Profile List Item (Modern Design) - avoid absolute x based on index; rely on LayoutProfileList
local function CreateModernProfileItem(parent, profile)
    local item = vgui.Create("DPanel", parent)
    item:SetTall(80)
    item:SetWide(parent:GetWide() - 20)
    -- position is handled by PM.LayoutProfileList()

    local isHovered = false
    local isLoading = false
    local lastClick = 0

    item.Paint = function(self, w, h)
        local isSelected = profile.name == PM._selectedProfile
        local bgColor = PM.COLORS.panel
        local borderColor = PM.COLORS.border

        if isLoading then
            bgColor = Color(60, 60, 70)
            borderColor = PM.COLORS.warning
        elseif isHovered then
            bgColor = PM.COLORS.hover
            borderColor = PM.COLORS.accent
        end

        if isSelected then
            bgColor = PM.COLORS.active
            borderColor = PM.COLORS.accent
        end

        if profile.isCurrent then
            borderColor = PM.COLORS.success
        end

        -- Background
        draw.RoundedBox(8, 0, 0, w, h, bgColor)

        -- Border
        surface.SetDrawColor(borderColor)
        surface.DrawOutlinedRect(0, 0, w, h, 2)

        -- Icon circle
        local iconX, iconY = 20, h / 2
        draw.RoundedBox(50, iconX - 15, iconY - 15, 30, 30, PM.COLORS.panelLight)

        local icon = isLoading and "⟳" or GetProfileIcon(profile)
        local iconColor = profile.isCurrent and PM.COLORS.success or PM.COLORS.accent
        if isLoading then iconColor = PM.COLORS.warning end

        draw.SimpleText(icon, "DermaLarge", iconX, iconY, iconColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Profile name
        local nameColor = profile.isCurrent and PM.COLORS.success or PM.COLORS.text
        local displayName = profile.displayName or profile.name
        if isLoading then displayName = displayName .. " (Loading...)" end

        draw.SimpleText(displayName, "DermaDefaultBold", 60, 15, nameColor)

        -- Description
        local desc = profile.description or "No description available"
        if string.len(desc) > 60 then desc = string.sub(desc, 1, 57) .. "..." end
        draw.SimpleText(desc, "DermaDefault", 60, 35, PM.COLORS.textSecondary)

        -- Stats
        local usageText = string.format("Used %d times • %s", profile.usageCount or 0, FormatTime(profile.lastUsed))
        draw.SimpleText(usageText, "DermaDefault", 60, 55, PM.COLORS.textMuted)

        -- Current indicator
        if profile.isCurrent then
            draw.SimpleText("ACTIVE", "DermaDefaultBold", w - 15, 15, PM.COLORS.success, TEXT_ALIGN_RIGHT)
        end

        -- Status badges
        local badgeX = w - 15
        if profile.author == "System" then
            draw.SimpleText("SYSTEM", "DermaDefault", badgeX, 55, PM.COLORS.warning, TEXT_ALIGN_RIGHT)
        elseif profile.shared then
            draw.SimpleText("SHARED", "DermaDefault", badgeX, 55, PM.COLORS.accent, TEXT_ALIGN_RIGHT)
        end
    end

    -- Mouse interactions
    item.OnMousePressed = function(self, key)
        if key == MOUSE_LEFT and not isLoading then
            local currentTime = SysTime()
            local timeDiff = currentTime - lastClick

            if timeDiff < 0.5 and timeDiff > 0.05 then
                -- Double click - activate profile
                isLoading = true
                PM.ActivateProfile(profile.name, function(success)
                    isLoading = false
                    if not success then
                        notification.AddLegacy("Failed to activate profile", NOTIFY_ERROR, 3)
                    end
                end)
            else
                -- Single click - select
                PM._selectedProfile = profile.name
                PM.UpdateDetailPanel(profile)
                PM.RefreshList()
            end
            lastClick = currentTime
        elseif key == MOUSE_RIGHT and not isLoading then
            PM.ShowModernContextMenu(profile)
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

-- Modern Context Menu
function PM.ShowModernContextMenu(profile)
    local menu = DermaMenu()
    menu:SetSkin("Default")

    -- Style the menu
    menu.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, PM.COLORS.panel)
        surface.SetDrawColor(PM.COLORS.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    if not profile.isCurrent then
        local activateOption = menu:AddOption("🚀 Activate Profile")
        activateOption.DoClick = function()
            PM.ActivateProfile(profile.name)
        end
    end

    local duplicateOption = menu:AddOption("📋 Duplicate Profile")
    duplicateOption.DoClick = function()
        PM.DuplicateProfile(profile.name)
    end

    if profile.name ~= "default" then
        local renameOption = menu:AddOption("✏️ Rename Profile")
        renameOption.DoClick = function()
            PM.RenameProfile(profile.name)
        end

        menu:AddSpacer()

        local deleteOption = menu:AddOption("🗑️ Delete Profile")
        deleteOption.DoClick = function()
            PM.DeleteProfile(profile.name)
        end
    end

    menu:AddSpacer()

    local exportOption = menu:AddOption("💾 Export Profile")
    exportOption.DoClick = function()
        PM.ExportProfile(profile.name)
    end

    menu:Open()
end

-- Detail Panel for Selected Profile
function PM.CreateDetailPanel(parent)
    local panel = vgui.Create("DPanel", parent)
    panel:SetSize(300, parent:GetTall() - 130)
    panel:SetPos(parent:GetWide() - 320, 110)

    panel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, PM.COLORS.panel)
        surface.SetDrawColor(PM.COLORS.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        draw.SimpleText("Profile Details", "DermaDefaultBold", 15, 15, PM.COLORS.text)
    end

    PM._detailPanel = panel
    return panel
end

function PM.UpdateDetailPanel(profile)
    if not IsValid(PM._detailPanel) then return end
    PM._detailPanel:Clear()
    if not profile then
        PM._detailPanel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, PM.COLORS.panel)
            surface.SetDrawColor(PM.COLORS.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            draw.SimpleText("No Profile Selected", "DermaDefaultBold", w / 2, h / 2, PM.COLORS.textMuted,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    PM._detailPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, PM.COLORS.panel)
        surface.SetDrawColor(PM.COLORS.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        local y = 20
        draw.SimpleText("Profile Details", "DermaDefaultBold", 15, y, PM.COLORS.text)
        y = y + 30

        draw.SimpleText("Name:", "DermaDefaultBold", 15, y, PM.COLORS.textSecondary)
        draw.SimpleText(profile.displayName or profile.name, "DermaDefault", 15, y + 15, PM.COLORS.text)
        y = y + 40

        draw.SimpleText("Description:", "DermaDefaultBold", 15, y, PM.COLORS.textSecondary)
        y = PM.DrawWrappedText(profile.description or "No description", "DermaDefault", 15, y + 15, w - 30,
            PM.COLORS.text) + 15

        draw.SimpleText("Statistics:", "DermaDefaultBold", 15, y, PM.COLORS.textSecondary)
        y = y + 20

        draw.SimpleText("Author: " .. (profile.author or "Unknown"), "DermaDefault", 15, y, PM.COLORS.text); y = y + 15
        draw.SimpleText("Usage Count: " .. (profile.usageCount or 0), "DermaDefault", 15, y, PM.COLORS.text); y = y + 15
        draw.SimpleText("Last Used: " .. FormatTime(profile.lastUsed), "DermaDefault", 15, y, PM.COLORS.text); y = y + 15
        draw.SimpleText("Created: " .. (profile.created and os.date("%Y-%m-%d", profile.created) or "Unknown"),
            "DermaDefault", 15, y, PM.COLORS.text)
        y = y + 25

        local methodCount = profile.methods and #profile.methods or 0
        draw.SimpleText("Methods: " .. methodCount, "DermaDefault", 15, y, PM.COLORS.text)
        y = y + 15

        if profile.isCurrent then
            draw.SimpleText("Status: ACTIVE", "DermaDefaultBold", 15, y, PM.COLORS.success)
        else
            draw.SimpleText("Status: Inactive", "DermaDefault", 15, y, PM.COLORS.textMuted)
        end
    end

    -- Action buttons
    local buttonY = PM._detailPanel:GetTall() - 90

    if not profile.isCurrent then
        PM.CreateSimpleButton(PM._detailPanel, "Activate", 15, buttonY, 120, 25, PM.COLORS.success, function()
            PM.ActivateProfile(profile.name)
        end)

        PM.CreateSimpleButton(PM._detailPanel, "Edit", 145, buttonY, 120, 25, PM.COLORS.accent, function()
            PM.EditProfile(profile.name)
        end)
    end

    PM.CreateSimpleButton(PM._detailPanel, "Duplicate", 15, buttonY + 30, 120, 25, PM.COLORS.warning, function()
        PM.DuplicateProfile(profile.name)
    end)

    PM.CreateSimpleButton(PM._detailPanel, "Export", 145, buttonY + 30, 120, 25, PM.COLORS.accent, function()
        PM.ExportProfile(profile.name)
    end)

    if profile.name ~= "default" then
        PM.CreateSimpleButton(PM._detailPanel, "Delete", 15, buttonY + 60, 250, 25, PM.COLORS.danger, function()
            PM.DeleteProfile(profile.name)
        end)
    end
end

-- Cache Management
function PM.UpdateCache()
    if SysTime() - PM._lastCacheUpdate < PM.CACHE_DURATION then
        return PM._profileCache
    end

    if not RARELOAD.AntiStuck.ProfileSystem or not RARELOAD.AntiStuck.ProfileSystem.GetProfileList then
        print("[ProfileManager] Profile system not available")
        return {}
    end

    local success, profiles = SafeCall(RARELOAD.AntiStuck.ProfileSystem.GetProfileList)
    if success then
        PM._profileCache = profiles
        -- Fast path for array-like tables
        local count = 0
        if istable(profiles) then
            count = #profiles
            if count == 0 then
                count = table.Count(profiles)
            end
        end
        PM._cacheCount = count
        PM._lastCacheUpdate = SysTime()
        return profiles
    else
        print("[ProfileManager] Failed to get profiles:", profiles)
        return PM._profileCache
    end
end

-- List Management
function PM.RefreshList()
    if PM._isRefreshing then return end
    if SysTime() - PM._lastRefresh < PM.REFRESH_COOLDOWN then return end
    PM._isRefreshing = true
    PM._lastRefresh = SysTime()

    if not IsValid(PM._profileList) then
        PM._isRefreshing = false
        return
    end

    PM._profileList:Clear()

    local profiles = PM.UpdateCache()

    -- Filter by search
    if PM._searchText ~= "" then
        local filtered = {}
        local searchLower = string.lower(PM._searchText)
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

    -- Sort profiles
    table.sort(profiles, function(a, b)
        if not a or not b then return false end

        if PM._sortMode == "name" then
            return (a.displayName or a.name or "") < (b.displayName or b.name or "")
        elseif PM._sortMode == "usage" then
            return (a.usageCount or 0) > (b.usageCount or 0)
        else -- lastUsed
            return (a.lastUsed or 0) > (b.lastUsed or 0)
        end
    end)

    for i, profile in ipairs(profiles) do
        if profile and profile.name then
            local ok, itemOrErr = SafeCall(CreateModernProfileItem, PM._profileList, profile)
            if not ok then
                print("[ProfileManager] Error creating profile item:", itemOrErr)
            end
        end
    end

    PM.LayoutProfileList()
    PM._isRefreshing = false
end

-- Main UI Creation
function PM.Create()
    if IsValid(PM._frame) then PM._frame:Close() end

    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.min(screenW * 0.85, 1200)
    local frameH = math.min(screenH * 0.8, 800)

    -- Main frame
    local frame = vgui.Create("DFrame")
    if not IsValid(frame) then
        return nil
    end

    frame:SetSize(frameW, frameH)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:SetSizable(true)

    frame.Paint = function(self, w, h)
        -- Background (simplified - no blur for now)
        draw.RoundedBox(12, 0, 0, w, h, PM.COLORS.background)

        -- Header
        draw.RoundedBoxEx(12, 0, 0, w, 50, PM.COLORS.panelLight, true, true, false, false)

        -- Title
        draw.SimpleText("Profile Manager", "DermaLarge", 20, 25, PM.COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Subtitle (uses cached count to avoid recounting on every paint)
        local profileCount = PM._cacheCount or 0
        draw.SimpleText(profileCount .. " profiles available", "DermaDefault", 20, 45, PM.COLORS.textSecondary)
    end

    PM._frame = frame

    -- Close button (positioned safely within frame bounds)
    local closeBtn = PM.CreateSimpleButton(frame, "✕", frameW - 50, 10, 35, 35, PM.COLORS.danger, function()
        frame:Close()
    end)

    if not IsValid(closeBtn) then
        print("[ProfileManager] ERROR: Failed to create close button!")
        -- Create a simple fallback close button
        local fallbackBtn = vgui.Create("DButton", frame)
        fallbackBtn:SetPos(frameW - 50, 10)
        fallbackBtn:SetSize(35, 35)
        fallbackBtn:SetText("X")
        fallbackBtn.DoClick = function()
            frame:Close()
        end
    end

    -- Search box
    local searchBox = vgui.Create("DTextEntry", frame)
    searchBox:SetSize(250, 30)
    searchBox:SetPos(20, 70)
    searchBox:SetPlaceholderText("🔍 Search profiles...")
    searchBox:SetValue(PM._searchText)

    -- debounce search
    PM._searchTimer = PM._searchTimer or "rareload_pm_search"
    searchBox.OnValueChange = function(self)
        PM._searchText = self:GetValue()
        timer.Remove(PM._searchTimer)
        timer.Create(PM._searchTimer, 0.25, 1, function()
            if not IsValid(self) or self:GetValue() ~= PM._searchText then return end
            PM.RefreshList()
        end)
    end

    -- Sort dropdown
    local sortCombo = vgui.Create("DComboBox", frame)
    sortCombo:SetSize(150, 30)
    sortCombo:SetPos(frameW - 170, 70)
    sortCombo:SetValue("Sort by...")
    sortCombo:AddChoice("Recently Used", "lastUsed", PM._sortMode == "lastUsed")
    sortCombo:AddChoice("Name", "name", PM._sortMode == "name")
    sortCombo:AddChoice("Usage Count", "usage", PM._sortMode == "usage")
    sortCombo.OnSelect = function(self, index, value, data)
        PM._sortMode = data
        PM.RefreshList()
    end

    -- Action buttons
    PM.CreateSimpleButton(frame, "New Profile", 280, 70, 100, 30, PM.COLORS.success, function() PM.CreateNewProfile() end)
    PM.CreateSimpleButton(frame, "Import", 390, 70, 80, 30, PM.COLORS.accent, function() PM.ImportProfile() end)

    local refreshBtn = PM.CreateSimpleButton(frame, "↻", frameW - 50, 70, 30, 30, PM.COLORS.warning, function()
        PM._lastRefresh = 0
        PM._lastCacheUpdate = 0
        PM.RefreshList()
    end)

    -- Profile list (scrollable)
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetSize(frameW - 340, frameH - 130)
    scroll:SetPos(20, 110)

    local listPanel = vgui.Create("DPanel", scroll)
    listPanel:SetSize(scroll:GetWide() - 20, 200)
    listPanel.Paint = function() end

    PM._profileList = listPanel

    -- Detail panel
    PM.CreateDetailPanel(frame)

    -- Responsive layout
    frame.PerformLayout = function(self, w, h)
        closeBtn:SetPos(w - 45, 8)
        sortCombo:SetPos(w - 170, 70)
        refreshBtn:SetPos(w - 50, 70)

        scroll:SetPos(20, 110)
        scroll:SetSize(w - 340, h - 130)

        if IsValid(PM._detailPanel) then
            PM._detailPanel:SetPos(w - 320, 110)
            PM._detailPanel:SetSize(300, h - 130)
        end

        if IsValid(listPanel) then
            listPanel:SetWide(scroll:GetWide() - 20)
            PM.LayoutProfileList()
        end
    end

    -- Initialize
    PM.RefreshList()
    frame:InvalidateLayout(true)

    return frame
end

-- Profile Operations (Enhanced guards)
function PM.ActivateProfile(profileName, callback)
    if not RARELOAD.AntiStuck.ProfileSystem then
        local error = "Profile system not available"
        if callback then callback(false, error) end
        notification.AddLegacy(error, NOTIFY_ERROR, 3)
        return
    end

    local success, err = RARELOAD.AntiStuck.ProfileSystem.SetCurrentProfile(profileName)
    if success then
        notification.AddLegacy("✓ Activated profile: " .. profileName, NOTIFY_GENERIC, 3)
        PM._lastCacheUpdate = 0 -- Force cache refresh
        PM.RefreshList()
        if callback then callback(true) end
    else
        local errorMsg = "Failed to activate profile: " .. (err or "Unknown error")
        notification.AddLegacy(errorMsg, NOTIFY_ERROR, 5)
        if callback then callback(false, errorMsg) end
    end
end

function PM.CreateNewProfile()
    Derma_StringRequest(
        "Create New Profile",
        "Enter a name for the new profile:",
        "",
        function(name)
            name = string.Trim(name)
            if #name == 0 then return end

            if string.match(name, "[<>:\"/\\|?*]") then
                notification.AddLegacy("Profile name contains invalid characters", NOTIFY_ERROR, 3)
                return
            end

            if RARELOAD.AntiStuck.ProfileSystem.ProfileExists(name) then
                notification.AddLegacy("A profile with this name already exists", NOTIFY_ERROR, 3)
                return
            end

            local newProfile = {
                name = name,
                displayName = name,
                description = "Custom profile created by user",
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
                notification.AddLegacy("✓ Profile created successfully", NOTIFY_GENERIC, 3)
                PM._lastCacheUpdate = 0
                PM.RefreshList()
            else
                notification.AddLegacy("Failed to create profile: " .. (err or "Unknown error"), NOTIFY_ERROR, 5)
            end
        end,
        function() end
    )
end

function PM.DuplicateProfile(profileName)
    if not RARELOAD.AntiStuck.ProfileSystem then
        notification.AddLegacy("Profile system not available", NOTIFY_ERROR, 3)
        return
    end
    Derma_StringRequest(
        "Duplicate Profile",
        "Enter name for the duplicated profile:",
        profileName .. "_copy",
        function(newName)
            newName = string.Trim(newName)
            if #newName == 0 then return end

            if RARELOAD.AntiStuck.ProfileSystem.ProfileExists(newName) then
                notification.AddLegacy("A profile with this name already exists", NOTIFY_ERROR, 3)
                return
            end

            local originalProfile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(profileName)
            if not originalProfile then
                notification.AddLegacy("Failed to load original profile", NOTIFY_ERROR, 3)
                return
            end

            -- Create duplicate
            local newProfile = table.Copy(originalProfile)
            newProfile.name = newName
            newProfile.displayName = newName
            newProfile.created = os.time()
            newProfile.modified = os.time()
            newProfile.lastUsed = 0
            newProfile.usageCount = 0

            local success, err = RARELOAD.AntiStuck.ProfileSystem.SaveProfile(newName, newProfile)
            if success then
                notification.AddLegacy("✓ Profile duplicated successfully", NOTIFY_GENERIC, 3)
                PM._lastCacheUpdate = 0
                PM.RefreshList()
            else
                notification.AddLegacy("Failed to duplicate profile: " .. (err or "Unknown error"), NOTIFY_ERROR, 5)
            end
        end,
        function() end
    )
end

function PM.RenameProfile(profileName)
    if not RARELOAD.AntiStuck.ProfileSystem then
        notification.AddLegacy("Profile system not available", NOTIFY_ERROR, 3)
        return
    end
    Derma_StringRequest(
        "Rename Profile",
        "Enter new name for the profile:",
        profileName,
        function(newName)
            newName = string.Trim(newName)
            if #newName == 0 or newName == profileName then return end

            if RARELOAD.AntiStuck.ProfileSystem.ProfileExists(newName) then
                notification.AddLegacy("A profile with this name already exists", NOTIFY_ERROR, 3)
                return
            end

            local profile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(profileName)
            if not profile then
                notification.AddLegacy("Failed to load profile", NOTIFY_ERROR, 3)
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
                if PM._selectedProfile == profileName then
                    PM._selectedProfile = newName
                end
                notification.AddLegacy("✓ Profile renamed successfully", NOTIFY_GENERIC, 3)
                PM._lastCacheUpdate = 0
                PM.RefreshList()
            else
                notification.AddLegacy("Failed to rename profile", NOTIFY_ERROR, 3)
            end
        end,
        function() end
    )
end

function PM.DeleteProfile(profileName)
    if not RARELOAD.AntiStuck.ProfileSystem then
        notification.AddLegacy("Profile system not available", NOTIFY_ERROR, 3)
        return
    end
    if profileName == "default" then
        notification.AddLegacy("Cannot delete the default profile", NOTIFY_ERROR, 3)
        return
    end

    Derma_Query(
        "Are you sure you want to delete the profile '" .. profileName .. "'?\n\nThis action cannot be undone.",
        "Delete Profile",
        "Delete",
        function()
            local success, err = RARELOAD.AntiStuck.ProfileSystem.DeleteProfile(profileName)
            if success then
                notification.AddLegacy("✓ Profile deleted successfully", NOTIFY_GENERIC, 3)
                if PM._selectedProfile == profileName then
                    PM._selectedProfile = nil
                    PM.UpdateDetailPanel(nil)
                end
                PM._lastCacheUpdate = 0
                PM.RefreshList()
            else
                notification.AddLegacy("Failed to delete profile: " .. (err or "Unknown error"), NOTIFY_ERROR, 5)
            end
        end,
        "Cancel",
        function() end
    )
end

function PM.ExportProfile(profileName)
    if not RARELOAD.AntiStuck.ProfileSystem then
        notification.AddLegacy("Profile system not available", NOTIFY_ERROR, 3)
        return
    end
    local profile = RARELOAD.AntiStuck.ProfileSystem.LoadProfile(profileName)
    if not profile then
        notification.AddLegacy("Failed to load profile for export", NOTIFY_ERROR, 3)
        return
    end

    local exportData = util.TableToJSON(profile, true)
    SetClipboardText(exportData)
    notification.AddLegacy("✓ Profile data copied to clipboard", NOTIFY_GENERIC, 3)
end

function PM.ImportProfile()
    if not RARELOAD.AntiStuck.ProfileSystem then
        notification.AddLegacy("Profile system not available", NOTIFY_ERROR, 3)
        return
    end
    Derma_StringRequest(
        "Import Profile",
        "Paste profile data (JSON):",
        "",
        function(data)
            data = string.Trim(data)
            if #data == 0 then return end

            local success, profile = pcall(util.JSONToTable, data)
            if not success or not profile or not profile.name then
                notification.AddLegacy("Invalid profile data", NOTIFY_ERROR, 3)
                return
            end

            if RARELOAD.AntiStuck.ProfileSystem.ProfileExists(profile.name) then
                notification.AddLegacy("A profile with this name already exists", NOTIFY_ERROR, 3)
                return
            end

            local result, err = RARELOAD.AntiStuck.ProfileSystem.SaveProfile(profile.name, profile)
            if result then
                notification.AddLegacy("✓ Profile imported successfully", NOTIFY_GENERIC, 3)
                PM._lastCacheUpdate = 0
                PM.RefreshList()
            else
                notification.AddLegacy("Failed to import profile: " .. (err or "Unknown error"), NOTIFY_ERROR, 5)
            end
        end,
        function() end
    )
end

-- Main interface functions (single definition)
function RARELOAD.AntiStuckSettings.OpenProfileManager()
    if PM.IsOpen() then
        PM._frame:Close()
    else
        PM.Create()
    end
end

function PM.IsOpen()
    return IsValid(PM._frame)
end

-- Console commands for testing (single definition)
concommand.Add("rareload_profile_manager", function()
    RARELOAD.AntiStuckSettings.OpenProfileManager()
end)

concommand.Add("rareload_profile_manager_test", function()
    print("=== Profile Manager Test ===")
    print("Profile System Available:", RARELOAD.AntiStuck.ProfileSystem ~= nil)
    if RARELOAD.AntiStuck.ProfileSystem then
        print("Profile List Function:", RARELOAD.AntiStuck.ProfileSystem.GetProfileList ~= nil)
        if RARELOAD.AntiStuck.ProfileSystem.GetProfileList then
            local profiles = RARELOAD.AntiStuck.ProfileSystem.GetProfileList()
            print("Profiles Found:", istable(profiles) and (#profiles > 0 and #profiles or table.Count(profiles)) or 0)
        end
    end
    print("=========================")
end)
