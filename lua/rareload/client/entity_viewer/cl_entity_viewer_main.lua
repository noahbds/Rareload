local draw, surface, util, vgui, hook, render = draw, surface, util, vgui, hook, render
local math, string, os = math, string, os
local Color, Vector, Angle = Color, Vector, Angle
local IsValid, CurTime, FrameTime, Lerp = IsValid, CurTime, FrameTime, Lerp
local TEXT_ALIGN_CENTER, MOUSE_LEFT = TEXT_ALIGN_CENTER, MOUSE_LEFT

-- Include dependencies
include("cl_entity_viewer_theme.lua")
include("cl_entity_viewer_create_category.lua")
include("cl_entity_viewer_info_panel.lua")
include("cl_entity_viewer_utils.lua")
include("cl_entity_viewer_json_editor.lua")

local EntityViewer = {}
EntityViewer.Frame = nil
EntityViewer.Data = {}
EntityViewer.FilteredData = {}
EntityViewer.SearchText = ""
EntityViewer.Category = "All" -- All, NPC, Weapon, Vehicle, Prop
EntityViewer.SortMode = "Name" -- Name, Distance, Health

-- Helper to extract entities from the complex JSON structure
local function ExtractEntities(tbl, result)
    result = result or {}
    
    if not tbl then return result end

    -- Case 1: We found a single entity definition (it has a Class and Pos)
    if (tbl.Class or tbl.class) and (tbl.Pos or tbl.pos) then
        local ent = {
            class = tbl.Class or tbl.class,
            model = tbl.Model or tbl.model,
            pos = tbl.Pos or tbl.pos,
            ang = tbl.Angle or tbl.ang or tbl.angle,
            health = tbl.CurHealth or tbl.health,
            maxHealth = tbl.MaxHealth or tbl.maxHealth,
            skin = tbl.Skin or tbl.skin,
            rawData = tbl  -- Store complete raw data for JSON editor
        }
        
        -- Handle Vector/Angle objects
        if istable(ent.pos) and ent.pos.__rareload_type == "Vector" then
            ent.pos = Vector(ent.pos.x, ent.pos.y, ent.pos.z)
        elseif istable(ent.pos) then
            ent.pos = Vector(ent.pos.x or 0, ent.pos.y or 0, ent.pos.z or 0)
        end

        if istable(ent.ang) and ent.ang.__rareload_type == "Angle" then
            ent.ang = Angle(ent.ang.p, ent.ang.y, ent.ang.r)
        elseif istable(ent.ang) then
            ent.ang = Angle(ent.ang.p or 0, ent.ang.y or 0, ent.ang.r or 0)
        end

        table.insert(result, ent)
        return result
    end

    -- Case 2: Recursive search
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            if (v.Class or v.class) and (v.Pos or v.pos) then
                ExtractEntities(v, result)
            else
                ExtractEntities(v, result)
            end
        end
    end
    
    return result
end

function EntityViewer:LoadData()
    local map = game.GetMap()
    local filename = "rareload/player_positions_" .. map .. ".json"
    
    if not file.Exists(filename, "DATA") then
        ShowNotification("No data found for map: " .. map, NOTIFY_ERROR)
        return {}
    end

    local json = file.Read(filename, "DATA")
    if not json then return {} end

    local rawData = util.JSONToTable(json)
    if not rawData then return {} end

    local entities = {}
    ExtractEntities(rawData, entities)
    return entities
end

function EntityViewer:FilterAndSort()
    self.FilteredData = {}
    local search = string.lower(self.SearchText)
    local cat = self.Category
    
    for _, ent in ipairs(self.Data) do
        local class = string.lower(ent.class or "")
        local model = string.lower(ent.model or "")
        
        -- Category Filter
        local matchCat = false
        if cat == "All" then matchCat = true
        elseif cat == "NPCs" and string.find(class, "npc") then matchCat = true
        elseif cat == "Weapons" and string.find(class, "weapon") then matchCat = true
        elseif cat == "Vehicles" and (string.find(class, "vehicle") or string.find(class, "jeep")) then matchCat = true
        elseif cat == "Props" and string.find(class, "prop") then matchCat = true
        end
        
        -- Search Filter
        local matchSearch = (search == "") or string.find(class, search) or string.find(model, search)
        
        if matchCat and matchSearch then
            table.insert(self.FilteredData, ent)
        end
    end

    -- Sorting
    table.sort(self.FilteredData, function(a, b)
        if self.SortMode == "Name" then
            return (a.class or "") < (b.class or "")
        elseif self.SortMode == "Distance" and IsValid(LocalPlayer()) then
            local distA = a.pos and LocalPlayer():GetPos():DistToSqr(a.pos) or 0
            local distB = b.pos and LocalPlayer():GetPos():DistToSqr(b.pos) or 0
            return distA < distB
        elseif self.SortMode == "Health" then
            return (tonumber(a.health) or 0) > (tonumber(b.health) or 0)
        end
        return false
    end)
end

function EntityViewer:Open()
    if IsValid(self.Frame) then self.Frame:Close() end

    self.Data = self:LoadData()
    self:FilterAndSort()

    local frame = vgui.Create("DFrame")
    frame:SetSize(1100, 750)
    frame:SetTitle("")
    frame:ShowCloseButton(false) -- Disable default close button
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:SetSizable(false) -- Fixed size to prevent layout loops
    self.Frame = frame

    -- Modern Paint
    frame.Paint = function(self, w, h)
        -- Removed DrawBlur for performance and because background is opaque
        draw.RoundedBox(10, 0, 0, w, h, THEME.background)
        
        -- Sidebar Background
        draw.RoundedBoxEx(10, 0, 0, 220, h, THEME.backgroundDark, true, false, true, false)
        
        -- Header Separator
        surface.SetDrawColor(THEME.divider)
        surface.DrawLine(220, 70, w, 70)
        surface.DrawLine(220, 0, 220, h)
    end

    -- Custom Close Button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetText("")
    closeBtn:SetSize(32, 32)
    closeBtn:SetPos(1100 - 40, 10) -- Fixed position
    closeBtn.Paint = function(self, w, h)
        if self:IsHovered() then
            draw.RoundedBox(6, 0, 0, w, h, THEME.error)
            draw.SimpleText("✕", "RareloadSubheading", w/2, h/2, THEME.textPrimary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("✕", "RareloadSubheading", w/2, h/2, THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    closeBtn.DoClick = function() frame:Close() end

    -- Sidebar
    local sidebar = vgui.Create("DPanel", frame)
    sidebar:SetPos(0, 0)
    sidebar:SetSize(220, 750)
    sidebar.Paint = function(self, w, h) 
        draw.SimpleText("Rareload", "RareloadHeading", 24, 24, THEME.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Entity Viewer", "RareloadSubheading", 24, 48, THEME.textSecondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    
    -- Sidebar Buttons
    local btnList = vgui.Create("DPanel", sidebar)
    btnList:SetPos(10, 100)
    btnList:SetSize(200, 600)
    btnList.Paint = function() end

    local categories = {"All", "NPCs", "Weapons", "Vehicles", "Props"}
    local yPos = 0
    
    for _, cat in ipairs(categories) do
        local btn = vgui.Create("DButton", btnList)
        btn:SetText(cat)
        btn:SetFont("RareloadBody")
        btn:SetPos(0, yPos)
        btn:SetSize(200, 40)
        btn:SetContentAlignment(4)
        btn:SetTextInset(20, 0)
        
        btn.Paint = function(self, w, h)
            local isSelected = EntityViewer.Category == cat
            local col = isSelected and THEME.surfaceVariant or Color(0,0,0,0)
            
            if self:IsHovered() and not isSelected then col = Color(255,255,255,5) end
            
            draw.RoundedBox(6, 0, 0, w, h, col)
            
            if isSelected then
                draw.RoundedBox(2, 0, 10, 4, h-20, THEME.primary)
                self:SetTextColor(THEME.textPrimary)
            else
                self:SetTextColor(THEME.textSecondary)
            end
        end
        
        btn.DoClick = function()
            EntityViewer.Category = cat
            EntityViewer:RefreshList()
        end
        
        yPos = yPos + 45
    end

    -- Top Bar
    local topbar = vgui.Create("DPanel", frame)
    topbar:SetPos(220, 0)
    topbar:SetSize(880, 70)
    topbar.Paint = function() end
    closeBtn:MoveToFront()
    
    -- Search
    local searchContainer, searchEntry = CreateModernSearchBar(topbar)
    searchContainer:SetPos(20, 15)
    searchContainer:SetSize(300, 40)
    searchEntry.OnChange = function(self)
        EntityViewer.SearchText = self:GetValue()
        EntityViewer:RefreshList()
    end

    -- Sort Button (Simple toggle for now, could be a dropdown)
    local sortBtn = vgui.Create("DButton", topbar)
    sortBtn:SetText("Sort: " .. EntityViewer.SortMode)
    sortBtn:SetPos(340, 15)
    sortBtn:SetSize(120, 40)
    sortBtn:SetFont("RareloadBody")
    sortBtn:SetTextColor(THEME.textPrimary)
    sortBtn.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.surface)
        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
    sortBtn.DoClick = function()
        if EntityViewer.SortMode == "Name" then EntityViewer.SortMode = "Distance"
        elseif EntityViewer.SortMode == "Distance" then EntityViewer.SortMode = "Health"
        else EntityViewer.SortMode = "Name" end
        sortBtn:SetText("Sort: " .. EntityViewer.SortMode)
        EntityViewer:RefreshList()
    end

    -- Refresh Button
    local refreshBtn = CreateActionButton(topbar, "Refresh", "icon16/arrow_refresh.png", THEME.primary, "Reload Data")
    refreshBtn:SetPos(820, 15)
    refreshBtn:SetSize(40, 40)
    refreshBtn.DoClick = function()
        EntityViewer.Data = EntityViewer:LoadData()
        EntityViewer:RefreshList()
        ShowNotification("Data Refreshed", NOTIFY_GENERIC)
    end

    -- Content Area
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(220, 70)
    scroll:SetSize(880, 680)
    scroll:DockPadding(20, 20, 20, 20)

    -- Grid (manual sizing to avoid constant invalidation)
    local grid = vgui.Create("DIconLayout", scroll)
    grid:SetPos(20, 20)
    grid:SetSpaceX(15)
    grid:SetSpaceY(15)
    grid:SetWide(scroll:GetWide() - 40)

    scroll.OnSizeChanged = function(_, w)
        grid:SetWide(math.max(0, w - 40))
        grid:InvalidateLayout(true)
    end
    self.Grid = grid

    -- Removed OnSizeChanged to prevent layout loops
    -- Fixed layout is used instead

    self:RefreshList()
end

function EntityViewer:RefreshList()
    if not IsValid(self.Grid) then return end
    
    self:FilterAndSort()
    self.Grid:Clear()

    local count = 0
    for _, entData in ipairs(self.FilteredData) do
        CreateInfoPanel(self.Grid, entData, false, function(deletedData)
            ShowNotification("Requesting delete...", NOTIFY_GENERIC)
        end)
        count = count + 1
        if count > 100 then break end -- Pagination limit
    end
    
    self.Grid:Layout()
end

concommand.Add("rareload_entity_viewer", function() EntityViewer:Open() end)
concommand.Add("entity_viewer_open", function() EntityViewer:Open() end)
function OpenEntityViewer() EntityViewer:Open() end

