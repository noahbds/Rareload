RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuckSettings = RARELOAD.AntiStuckSettings or {}

-- Include necessary files
include("rareload/client/antistuck/cl_anti_stuck_theme.lua")

-- Constants
local REFRESH_COOLDOWN = 0.5 -- Minimum time between refreshes in seconds
local MAX_PROFILES_PER_PAGE = 10
local SEARCH_DEBOUNCE = 0.3 -- Seconds to wait after typing before searching
local SORT_OPTIONS = {
    {name = "Last Used", key = "lastUsed", default = true},
    {name = "Name", key = "name"},
    {name = "Usage Count", key = "usageCount"},
    {name = "Modified", key = "modified"}
}

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

-- Profile Manager UI
local ProfileManager = {
    _frame = nil,
    _listView = nil,
    _searchBox = nil,
    _sortCombo = nil,
    _sortOrder = "desc",
    _currentPage = 1,
    _totalPages = 1,
    _searchText = "",
    _lastRefresh = 0,
    _searchTimer = nil,
    _selectedProfile = nil,
    _hoveredProfile = nil,
    _tooltip = nil,
    _contextMenu = nil,
    _dragDrop = {
        active = false,
        source = nil,
        target = nil
    }
}

function ProfileManager.Create()
    if ProfileManager._frame and IsValid(ProfileManager._frame) then
        ProfileManager._frame:Close()
    end

    local screenW, screenH = ScrW(), ScrH()
    local frameW = math.min(800, screenW * 0.8)
    local frameH = math.min(600, screenH * 0.8)

    -- Main frame
    local frame = vgui.Create("DFrame")
    frame:SetSize(frameW, frameH)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(false)
    frame:SetBackgroundBlur(true)
    frame:SetName("ProfileManagerDialog")

    -- Theme-aware paint function
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
    closeBtn.DoClick = function() frame:Close() end

    -- Search and sort panel
    local searchPanel = vgui.Create("DPanel", frame)
    searchPanel:Dock(TOP)
    searchPanel:SetHeight(40)
    searchPanel:DockMargin(10, 10, 10, 0)
    searchPanel.Paint = function(self, w, h)
        Derma_DrawBackgroundBlur(self, self.m_fCreateTime or SysTime())
        draw.RoundedBox(8, 0, 0, w, h, THEME.panel or Color(42, 47, 65))
    end

    -- Search box
    ProfileManager._searchBox = vgui.Create("DTextEntry", searchPanel)
    ProfileManager._searchBox:SetPlaceholderText("Search profiles...")
    ProfileManager._searchBox:Dock(LEFT)
    ProfileManager._searchBox:SetWide(200)
    ProfileManager._searchBox:DockMargin(5, 5, 5, 5)
    ProfileManager._searchBox:SetFont("RareloadText")
    ProfileManager._searchBox:SetTextColor(THEME.textHighlight or Color(255, 255, 255))
    ProfileManager._searchBox.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.panel or Color(42, 47, 65))
        self:DrawTextEntryText(THEME.textHighlight or Color(255, 255, 255),
            THEME.accent or Color(88, 140, 240),
            THEME.textSecondary or Color(200, 200, 200))
    end

    -- Sort combo
    ProfileManager._sortCombo = vgui.Create("DComboBox", searchPanel)
    ProfileManager._sortCombo:Dock(LEFT)
    ProfileManager._sortCombo:SetWide(150)
    ProfileManager._sortCombo:DockMargin(5, 5, 5, 5)
    ProfileManager._sortCombo:SetFont("RareloadText")
    ProfileManager._sortCombo:SetTextColor(THEME.textHighlight or Color(255, 255, 255))
    
    for _, option in ipairs(SORT_OPTIONS) do
        ProfileManager._sortCombo:AddChoice(option.name, option.key, option.default)
    end
    
    -- Sort order button
    local sortOrderBtn = vgui.Create("DButton", searchPanel)
    sortOrderBtn:Dock(LEFT)
    sortOrderBtn:SetWide(30)
    sortOrderBtn:DockMargin(5, 5, 5, 5)
    sortOrderBtn:SetText("")
    sortOrderBtn.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.panel or Color(42, 47, 65))
        draw.SimpleText(
            ProfileManager._sortOrder == "asc" and "↑" or "↓",
            "RareloadText",
            w/2, h/2,
            THEME.textHighlight or Color(255, 255, 255),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER
        )
    end
    sortOrderBtn.DoClick = function()
        ProfileManager._sortOrder = ProfileManager._sortOrder == "asc" and "desc" or "asc"
        ProfileManager.RefreshList()
    end

    -- List view
    ProfileManager._listView = vgui.Create("DListView", frame)
    ProfileManager._listView:Dock(FILL)
    ProfileManager._listView:DockMargin(10, 10, 10, 10)
    ProfileManager._listView:SetMultiSelect(false)
    ProfileManager._listView:AddColumn("Name")
    ProfileManager._listView:AddColumn("Description")
    ProfileManager._listView:AddColumn("Last Used")
    ProfileManager._listView:AddColumn("Usage Count")
    ProfileManager._listView:AddColumn("Tags")

    -- Custom list view styling
    ProfileManager._listView.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.panel or Color(42, 47, 65))
    end

    -- Custom paint function for list view items
    ProfileManager._listView.PaintOver = function(self, w, h)
        if not self:GetSelected() then return end
        
        local x, y = self:GetPos()
        local selected = self:GetSelected()
        if not selected then return end
        
        -- Draw selection highlight
        surface.SetDrawColor(THEME.primary or Color(88, 140, 240))
        surface.DrawRect(0, selected:GetY(), w, selected:GetTall())
    end

    -- Button panel
    local buttonPanel = vgui.Create("DPanel", frame)
    buttonPanel:Dock(BOTTOM)
    buttonPanel:SetHeight(50)
    buttonPanel:DockMargin(10, 0, 10, 10)
    buttonPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.panel or Color(42, 47, 65))
    end

    -- Action buttons
    local function CreateActionButton(text, x, w, onClick)
        local btn = vgui.Create("DButton", buttonPanel)
        btn:SetPos(x, 5)
        btn:SetSize(w, 40)
        btn:SetText(text)
        btn:SetFont("RareloadText")
        btn:SetTextColor(THEME.textHighlight or Color(255, 255, 255))
        btn.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, THEME.accent or Color(88, 140, 240))
        end
        btn.DoClick = onClick
        return btn
    end

    -- Apply button
    CreateActionButton("Apply", 10, 100, function()
        if not ProfileManager._selectedProfile then return end
        RARELOAD.ProfileSystem.SetCurrentProfile(ProfileManager._selectedProfile)
        ProfileManager.RefreshList()
    end)
    
    -- Create button
    CreateActionButton("Create", 120, 100, function()
        ProfileManager.ShowCreateDialog()
    end)
    
    -- Edit button
    CreateActionButton("Edit", 230, 100, function()
        if not ProfileManager._selectedProfile then return end
        ProfileManager.ShowEditDialog(ProfileManager._selectedProfile)
    end)
    
    -- Delete button
    CreateActionButton("Delete", 340, 100, function()
        if not ProfileManager._selectedProfile then return end
        ProfileManager.ShowDeleteDialog(ProfileManager._selectedProfile)
    end)
    
    -- Import/Export buttons
    CreateActionButton("Import", 450, 100, function()
        ProfileManager.ShowImportDialog()
    end)
    
    CreateActionButton("Export", 560, 100, function()
        if not ProfileManager._selectedProfile then return end
        ProfileManager.ShowExportDialog(ProfileManager._selectedProfile)
    end)
    
    -- Pagination controls
    local paginationPanel = vgui.Create("DPanel", buttonPanel)
    paginationPanel:SetPos(670, 5)
    paginationPanel:SetSize(120, 40)
    paginationPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.panel or Color(42, 47, 65))
    end
    
    -- Previous page button
    local prevBtn = vgui.Create("DButton", paginationPanel)
    prevBtn:SetPos(5, 5)
    prevBtn:SetSize(30, 30)
    prevBtn:SetText("←")
    prevBtn:SetFont("RareloadText")
    prevBtn:SetTextColor(THEME.textHighlight or Color(255, 255, 255))
    prevBtn.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.accent or Color(88, 140, 240))
    end
    prevBtn.DoClick = function()
        if ProfileManager._currentPage > 1 then
            ProfileManager._currentPage = ProfileManager._currentPage - 1
            ProfileManager.RefreshList()
        end
    end
    
    -- Page label
    local pageLabel = vgui.Create("DLabel", paginationPanel)
    pageLabel:SetPos(40, 5)
    pageLabel:SetSize(40, 30)
    pageLabel:SetText("1/1")
    pageLabel:SetFont("RareloadText")
    pageLabel:SetTextColor(THEME.textHighlight or Color(255, 255, 255))
    pageLabel:SetContentAlignment(5)
    
    -- Next page button
    local nextBtn = vgui.Create("DButton", paginationPanel)
    nextBtn:SetPos(85, 5)
    nextBtn:SetSize(30, 30)
    nextBtn:SetText("→")
    nextBtn:SetFont("RareloadText")
    nextBtn:SetTextColor(THEME.textHighlight or Color(255, 255, 255))
    nextBtn.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.accent or Color(88, 140, 240))
    end
    nextBtn.DoClick = function()
        if ProfileManager._currentPage < ProfileManager._totalPages then
            ProfileManager._currentPage = ProfileManager._currentPage + 1
            ProfileManager.RefreshList()
        end
    end

    -- Store references
    ProfileManager._frame = frame
    ProfileManager._listView = ProfileManager._listView
    ProfileManager._searchBox = ProfileManager._searchBox
    ProfileManager._sortCombo = ProfileManager._sortCombo
    ProfileManager._sortOrder = ProfileManager._sortOrder
    ProfileManager._currentPage = 1
    ProfileManager._totalPages = 1

    -- Set up event handlers
    ProfileManager._searchBox.OnChange = function(self)
        if ProfileManager._searchTimer then
            timer.Remove(ProfileManager._searchTimer)
        end
        
        ProfileManager._searchTimer = timer.Simple(SEARCH_DEBOUNCE, function()
            ProfileManager._searchText = self:GetValue():lower()
            ProfileManager._currentPage = 1
            ProfileManager.RefreshList()
        end)
    end

    ProfileManager._sortCombo.OnSelect = function(self, index, value, data)
        ProfileManager._currentPage = 1
        ProfileManager.RefreshList()
    end

    ProfileManager._listView.OnRowSelected = function(self, rowIndex, row)
        ProfileManager._selectedProfile = row.profileName
    end

    ProfileManager._listView.OnRowRightClick = function(self, rowIndex, row)
        ProfileManager.ShowContextMenu(row.profileName)
    end

    -- Set up refresh timer
    ProfileManager._refreshTimer = timer.Create("RareloadProfileManagerRefresh", REFRESH_COOLDOWN, 0, function()
        if not ProfileManager._frame or not ProfileManager._frame:IsValid() then
            timer.Remove(ProfileManager._refreshTimer)
            return
        end
        
        ProfileManager.RefreshList()
    end)

    -- Clean up timer when frame is closed
    frame.OnClose = function()
        timer.Remove(ProfileManager._refreshTimer)
        if ProfileManager._searchTimer then
            timer.Remove(ProfileManager._searchTimer)
        end
    end

    -- Initial refresh
    ProfileManager.RefreshList()
end

function ProfileManager.RefreshList()
    if not ProfileManager._frame or not IsValid(ProfileManager._frame) then return end
    
    -- Check cooldown
    local currentTime = SysTime()
    if currentTime - ProfileManager._lastRefresh < REFRESH_COOLDOWN then
        return
    end
    ProfileManager._lastRefresh = currentTime

    -- Get profiles
    local profiles = RARELOAD.ProfileSystem.GetProfilesList() or {}
    
    -- Apply search filter
    local searchText = ProfileManager._searchText
    if searchText ~= "" then
        local filtered = {}
        for _, profile in ipairs(profiles) do
            if string.find(profile.name:lower(), searchText) or
               string.find(profile.displayName:lower(), searchText) or
               string.find(profile.description:lower(), searchText) then
                table.insert(filtered, profile)
            end
        end
        profiles = filtered
    end
    
    -- Apply sorting
    local sortKey = SORT_OPTIONS[ProfileManager._sortCombo:GetSelectedID()].key
    table.sort(profiles, function(a, b)
        local aVal = a[sortKey] or 0
        local bVal = b[sortKey] or 0
        
        if type(aVal) == "string" then
            aVal = string.lower(aVal)
            bVal = string.lower(bVal)
        end
        
        if ProfileManager._sortOrder == "asc" then
            return aVal < bVal
        else
            return aVal > bVal
        end
    end)
    
    -- Calculate pagination
    ProfileManager._totalPages = math.ceil(#profiles / MAX_PROFILES_PER_PAGE)
    ProfileManager._currentPage = math.Clamp(ProfileManager._currentPage, 1, ProfileManager._totalPages)
    
    -- Update page controls
    local pageLabel = ProfileManager._frame:GetChildren()[1]:GetChildren()[3]
    if IsValid(pageLabel) then
        pageLabel:SetText(string.format("%d/%d", ProfileManager._currentPage, ProfileManager._totalPages))
    end
    ProfileManager._listView:Clear()
    
    -- Calculate page range
    local startIndex = (ProfileManager._currentPage - 1) * MAX_PROFILES_PER_PAGE + 1
    local endIndex = math.min(startIndex + MAX_PROFILES_PER_PAGE - 1, #profiles)
    
    -- Update list
    for i = startIndex, endIndex do
        local profile = profiles[i]
        local row = ProfileManager._listView:AddLine(
            profile.displayName or profile.name,
            profile.description or "",
            os.date("%Y-%m-%d %H:%M", profile.lastUsed or 0),
            tostring(profile.usageCount or 0),
            table.concat(profile.tags or {}, ", ")
        )
        row.profileName = profile.name
    end
end

-- Dialog functions
function ProfileManager.ShowCreateDialog()
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Create New Profile")
    frame:SetSize(400, 300)
    frame:Center()
    frame:MakePopup()
    
    -- Add your create profile UI here
end

function ProfileManager.ShowEditDialog(profileName)
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Edit Profile: " .. profileName)
    frame:SetSize(400, 300)
    frame:Center()
    frame:MakePopup()
    
    -- Add your edit profile UI here
end

function ProfileManager.ShowDeleteDialog(profileName)
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Delete Profile")
    frame:SetSize(300, 150)
    frame:Center()
    frame:MakePopup()
    
    -- Add your delete confirmation UI here
end

function ProfileManager.ShowImportDialog()
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Import Profile")
    frame:SetSize(400, 300)
    frame:Center()
    frame:MakePopup()
    
    -- Add your import profile UI here
end

function ProfileManager.ShowExportDialog(profileName)
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Export Profile")
    frame:SetSize(400, 300)
    frame:Center()
    frame:MakePopup()
    
    -- Add your export profile UI here
end

function ProfileManager.ShowContextMenu(profileName)
    if ProfileManager._contextMenu then
        ProfileManager._contextMenu:Remove()
    end
    
    ProfileManager._contextMenu = DermaMenu()
    ProfileManager._contextMenu:AddOption("Apply", function()
        RARELOAD.ProfileSystem.SetCurrentProfile(profileName)
        ProfileManager.RefreshList()
    end)
    ProfileManager._contextMenu:AddOption("Edit", function()
        ProfileManager.ShowEditDialog(profileName)
    end)
    ProfileManager._contextMenu:AddOption("Delete", function()
        ProfileManager.ShowDeleteDialog(profileName)
    end)
    ProfileManager._contextMenu:AddOption("Export", function()
        ProfileManager.ShowExportDialog(profileName)
    end)
    ProfileManager._contextMenu:Open()
end

-- Export functions
function RARELOAD.AntiStuckSettings.OpenProfileManager()
    if RARELOAD.AntiStuckSettings.IsProfileManagerOpen() then return end
    ProfileManager.Create()
end
