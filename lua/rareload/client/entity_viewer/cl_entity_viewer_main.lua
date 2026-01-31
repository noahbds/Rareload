local draw, surface, util, vgui, hook, render = draw, surface, util, vgui, hook, render
local math, string, os = math, string, os
local Color, Vector, Angle = Color, Vector, Angle
local IsValid, CurTime, FrameTime, Lerp = IsValid, CurTime, FrameTime, Lerp
local TEXT_ALIGN_CENTER, TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT = TEXT_ALIGN_CENTER, TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT
local TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM

include("cl_entity_viewer_theme.lua")
include("cl_entity_viewer_utils.lua")

EV_THEME = THEME

local EntityViewer = {}
EntityViewer.Frame = nil
EntityViewer.Data = {}
EntityViewer.FilteredData = {}
EntityViewer.SearchText = ""
EntityViewer.Category = "All"
EntityViewer.SortMode = "Name"

local function ExtractEntities(tbl, result)
    result = result or {}
    if not tbl then return result end

    if (tbl.Class or tbl.class) and (tbl.Pos or tbl.pos) then
        local ent = {
            id = tbl.RareloadNPCID or tbl.RareloadEntityID or tostring(math.random(100000, 999999)),
            class = tbl.Class or tbl.class,
            model = tbl.Model or tbl.model,
            pos = tbl.Pos or tbl.pos,
            ang = tbl.Angle or tbl.ang or tbl.angle,
            health = tbl.CurHealth or tbl.health,
            maxHealth = tbl.MaxHealth or tbl.maxHealth,
            skin = tbl.Skin or tbl.skin,
            rawData = tbl
        }
        
        if istable(ent.pos) then
            if ent.pos.__rareload_type == "Vector" then
                ent.pos = Vector(ent.pos.x, ent.pos.y, ent.pos.z)
            else
                ent.pos = Vector(ent.pos.x or 0, ent.pos.y or 0, ent.pos.z or 0)
            end
        end

        if istable(ent.ang) then
            if ent.ang.__rareload_type == "Angle" then
                ent.ang = Angle(ent.ang.p, ent.ang.y, ent.ang.r)
            else
                ent.ang = Angle(ent.ang.p or 0, ent.ang.y or 0, ent.ang.r or 0)
            end
        end

        table.insert(result, ent)
        return result
    end

    for k, v in pairs(tbl) do
        if type(v) == "table" then
            ExtractEntities(v, result)
        end
    end
    
    return result
end

function EntityViewer:LoadData()
    local map = game.GetMap()
    local filename = "rareload/player_positions_" .. map .. ".json"
    
    if not file.Exists(filename, "DATA") then
        return {}
    end

    local json = file.Read(filename, "DATA")
    if not json then return {} end

    local rawData = util.JSONToTable(json)
    if not rawData then return {} end

    return ExtractEntities(rawData, {})
end

function EntityViewer:FilterAndSort()
    self.FilteredData = {}
    local search = string.lower(self.SearchText)
    local cat = self.Category
    
    for _, ent in ipairs(self.Data) do
        local class = string.lower(ent.class or "")
        local model = string.lower(ent.model or "")
        
        local matchCat = false
        if cat == "All" then 
            matchCat = true
        elseif cat == "NPCs" and string.find(class, "npc") then 
            matchCat = true
        elseif cat == "Weapons" and string.find(class, "weapon") then 
            matchCat = true
        elseif cat == "Vehicles" and (string.find(class, "vehicle") or string.find(class, "jeep") or string.find(class, "airboat")) then 
            matchCat = true
        elseif cat == "Props" and string.find(class, "prop") then 
            matchCat = true
        end
        
        local matchSearch = (search == "") or string.find(class, search) or string.find(model, search)
        
        if matchCat and matchSearch then
            table.insert(self.FilteredData, ent)
        end
    end

    table.sort(self.FilteredData, function(a, b)
        if self.SortMode == "Name" then
            return (a.class or "") < (b.class or "")
        elseif self.SortMode == "Distance" and IsValid(LocalPlayer()) then
            local distA = a.pos and LocalPlayer():GetPos():DistToSqr(a.pos) or math.huge
            local distB = b.pos and LocalPlayer():GetPos():DistToSqr(b.pos) or math.huge
            return distA < distB
        elseif self.SortMode == "Health" then
            return (tonumber(a.health) or 0) > (tonumber(b.health) or 0)
        end
        return false
    end)
end

local function CreateSidebarButton(parent, text, yPos, onClick, viewer)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetPos(12, yPos)
    btn:SetSize(196, 44)
    btn.Category = text
    btn.HoverAnim = 0
    
    btn.Paint = function(self, w, h)
        local isSelected = viewer.Category == self.Category
        self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, (self:IsHovered() or isSelected) and 1 or 0)
        
        if isSelected then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(EV_THEME.primary, 40))
            draw.RoundedBox(3, 0, 8, 4, h - 16, EV_THEME.primary)
        elseif self.HoverAnim > 0 then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(EV_THEME.surface, self.HoverAnim * 80))
        end
        
        local textCol = isSelected and EV_THEME.primary or 
                        THEME:LerpColor(self.HoverAnim, EV_THEME.textSecondary, EV_THEME.textPrimary)
        draw.SimpleText(text, "RareloadBody", 20, h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    
    btn.DoClick = onClick
    return btn
end

local function CreateEntityCard(parent, data, onTeleport, onDelete, onDetails)
    local card = vgui.Create("DButton", parent)
    card:SetText("")
    card:SetSize(185, 235)
    
    local typeColor = EV_THEME:GetEntityTypeColor(data.class)
    local hoverAnim = 0
    
    card.Paint = function(self, w, h)
        hoverAnim = Lerp(FrameTime() * 10, hoverAnim, self:IsHovered() and 1 or 0)
        
        if hoverAnim > 0.01 then
            draw.RoundedBox(12, 3, 3, w, h, ColorAlpha(Color(0, 0, 0), 50 * hoverAnim))
        end
        
        draw.RoundedBox(12, 0, 0, w, h, EV_THEME.surface)
        
        if hoverAnim > 0.01 then
            draw.RoundedBox(12, 0, 0, w, h, ColorAlpha(EV_THEME.primary, 12 * hoverAnim))
            surface.SetDrawColor(ColorAlpha(EV_THEME.primary, 80 * hoverAnim))
            surface.DrawOutlinedRect(0, 0, w, h, 2)
        end
        
        draw.RoundedBoxEx(8, 0, h - 4, w, 4, typeColor, false, false, true, true)
    end

    local previewBg = vgui.Create("DPanel", card)
    previewBg:SetPos(8, 8)
    previewBg:SetSize(169, 120)
    previewBg.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, EV_THEME.backgroundDark)
    end

    if data.model and util.IsValidModel(data.model) then
        local modelPanel = vgui.Create("DModelPanel", previewBg)
        modelPanel:SetPos(0, 0)
        modelPanel:SetSize(169, 120)
        modelPanel:SetModel(data.model)
        modelPanel:SetMouseInputEnabled(false)
        
        local ent = modelPanel:GetEntity()
        if IsValid(ent) then
            local mn, mx = ent:GetRenderBounds()
            local center = (mn + mx) * 0.5
            local size = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
            
            local fov = 45
            local dist = (size * 1.2) / math.tan(math.rad(fov / 2))
            
            modelPanel:SetLookAt(center)
            modelPanel:SetCamPos(center + Vector(dist * 0.6, dist * 0.5, dist * 0.4))
            modelPanel:SetFOV(fov)
            
            modelPanel.LayoutEntity = function(self, ent)
                ent:SetAngles(Angle(0, RealTime() * 30, 0))
            end
        end
    else
        previewBg.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, EV_THEME.backgroundDark)
            draw.SimpleText("?", "RareloadDisplay", w / 2, h / 2, EV_THEME.textDisabled, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local name = data.class or "Unknown"
    if #name > 20 then name = string.sub(name, 1, 18) .. "..." end
    
    local lblName = vgui.Create("DLabel", card)
    lblName:SetText(name)
    lblName:SetFont("RareloadBody")
    lblName:SetTextColor(EV_THEME.textPrimary)
    lblName:SetPos(8, 132)
    lblName:SetSize(169, 20)
    lblName:SetContentAlignment(5)

    local yOffset = 155
    if data.health and data.maxHealth then
        local hp = tonumber(data.health) or 0
        local maxHp = tonumber(data.maxHealth) or hp
        if maxHp > 0 then
            local hpBar = vgui.Create("DPanel", card)
            hpBar:SetPos(16, yOffset)
            hpBar:SetSize(153, 5)
            hpBar.Paint = function(self, w, h)
                draw.RoundedBox(3, 0, 0, w, h, EV_THEME.backgroundDark)
                local frac = math.Clamp(hp / maxHp, 0, 1)
                local healthCol = EV_THEME:GetHealthColor(hp, maxHp)
                draw.RoundedBox(3, 0, 0, w * frac, h, healthCol)
            end
            yOffset = yOffset + 10
        end
    end

    if data.pos and IsValid(LocalPlayer()) then
        local dist = math.Round(LocalPlayer():GetPos():Distance(data.pos))
        local distLabel = vgui.Create("DLabel", card)
        distLabel:SetText(dist .. " units")
        distLabel:SetFont("RareloadCaption")
        distLabel:SetTextColor(EV_THEME.textSecondary)
        distLabel:SetPos(8, yOffset)
        distLabel:SetSize(169, 16)
        distLabel:SetContentAlignment(5)
    end

    local btnContainer = vgui.Create("DPanel", card)
    btnContainer:SetPos(8, 195)
    btnContainer:SetSize(169, 32)
    btnContainer.Paint = function() end

    local function CreateSmallButton(x, w, icon, tooltip, hoverColor, onClick)
        local btn = vgui.Create("DButton", btnContainer)
        btn:SetText("")
        btn:SetPos(x, 0)
        btn:SetSize(w, 28)
        btn:SetTooltip(tooltip)
        btn.HoverAnim = 0
        btn.Paint = function(self, bw, bh)
            self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, self:IsHovered() and 1 or 0)
            local col = THEME:LerpColor(self.HoverAnim, EV_THEME.surfaceVariant, hoverColor)
            draw.RoundedBox(6, 0, 0, bw, bh, col)
            
            surface.SetDrawColor(255, 255, 255, 180 + 75 * self.HoverAnim)
            surface.SetMaterial(Material(icon))
            surface.DrawTexturedRect(bw/2 - 8, bh/2 - 8, 16, 16)
        end
        btn.DoClick = onClick
        return btn
    end

    CreateSmallButton(0, 52, "icon16/arrow_right.png", "Teleport to entity", EV_THEME.success, function()
        if onTeleport then onTeleport(data) end
    end)

    CreateSmallButton(58, 52, "icon16/cross.png", "Delete from saved data", EV_THEME.error, function()
        if onDelete then onDelete(data) end
    end)

    CreateSmallButton(116, 53, "icon16/information.png", "View details", EV_THEME.info, function()
        if onDetails then onDetails(data) end
    end)

    card.DoClick = function()
        if onDetails then onDetails(data) end
    end

    return card
end

local function CreateDetailsPanel(data, onDelete, viewer)
    local frame = vgui.Create("DFrame")
    frame:SetSize(550, 620)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:ShowCloseButton(false)
    frame:SetBackgroundBlur(true)
    
    frame.Paint = function(self, w, h)
        EV_THEME:DrawBlur(self, 3)
        
        draw.RoundedBox(14, 0, 0, w, h, EV_THEME.background)
        
        draw.RoundedBoxEx(14, 0, 0, w, 60, EV_THEME.backgroundDark, true, true, false, false)
        
        draw.SimpleText("Entity Details", "RareloadHeading", 20, 30, EV_THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        
        surface.SetDrawColor(EV_THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetText("")
    closeBtn:SetSize(36, 36)
    closeBtn:SetPos(550 - 50, 12)
    closeBtn.HoverAnim = 0
    closeBtn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, self:IsHovered() and 1 or 0)
        draw.RoundedBox(8, 0, 0, w, h, EV_THEME.surfaceVariant)
        if self.HoverAnim > 0 then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(EV_THEME.error, 200 * self.HoverAnim))
        end
        draw.SimpleText("✕", "RareloadSubheading", w/2, h/2, 
            THEME:LerpColor(self.HoverAnim, EV_THEME.textSecondary, EV_THEME.textPrimary), 
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function() frame:Close() end

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(16, 70)
    scroll:SetSize(518, 450)

    local previewContainer = vgui.Create("DPanel", scroll)
    previewContainer:Dock(TOP)
    previewContainer:SetTall(180)
    previewContainer:DockMargin(0, 0, 0, 12)
    previewContainer.Paint = function(self, w, h)
        draw.RoundedBox(10, 0, 0, w, h, EV_THEME.surface)
    end

    if data.model and util.IsValidModel(data.model) then
        local modelPanel = vgui.Create("DModelPanel", previewContainer)
        modelPanel:Dock(FILL)
        modelPanel:DockMargin(8, 8, 8, 8)
        modelPanel:SetModel(data.model)
        
        local ent = modelPanel:GetEntity()
        if IsValid(ent) then
            local mn, mx = ent:GetRenderBounds()
            local center = (mn + mx) * 0.5
            local sizeX = mx.x - mn.x
            local sizeY = mx.y - mn.y
            local sizeZ = mx.z - mn.z
            local size = math.max(sizeX, sizeY, sizeZ)
            
            local fov = 40
            local dist = (size * 1.3) / math.tan(math.rad(fov / 2))
            
            modelPanel:SetLookAt(center)
            modelPanel:SetCamPos(center + Vector(dist * 0.5, dist * 0.4, dist * 0.35))
            modelPanel:SetFOV(fov)
            
            modelPanel.DragMousePress = function() end
            modelPanel.DragMouseRelease = function() end
            modelPanel.LayoutEntity = function(self, ent)
                if self.bAnimated then self:RunAnimation() end
                if self:GetParent():IsHovered() then return end
                ent:SetAngles(Angle(0, RealTime() * 25, 0))
            end
        end
    end

    local function AddInfoRow(label, value, valueColor)
        local row = vgui.Create("DPanel", scroll)
        row:Dock(TOP)
        row:SetTall(36)
        row:DockMargin(0, 0, 0, 6)
        row.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, EV_THEME.surface)
        end

        local lbl = vgui.Create("DLabel", row)
        lbl:SetText(label)
        lbl:SetFont("RareloadLabel")
        lbl:SetTextColor(EV_THEME.textSecondary)
        lbl:Dock(LEFT)
        lbl:DockMargin(12, 0, 0, 0)
        lbl:SetWide(90)

        local val = vgui.Create("DLabel", row)
        val:SetText(tostring(value))
        val:SetFont("RareloadBody")
        val:SetTextColor(valueColor or EV_THEME.textPrimary)
        val:Dock(FILL)
        val:DockMargin(8, 0, 40, 0)

        local copyBtn = vgui.Create("DButton", row)
        copyBtn:SetText("")
        copyBtn:Dock(RIGHT)
        copyBtn:SetWide(32)
        copyBtn:DockMargin(0, 4, 6, 4)
        copyBtn:SetTooltip("Copy")
        copyBtn.HoverAnim = 0
        copyBtn.Paint = function(self, w, h)
            self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, self:IsHovered() and 1 or 0)
            if self.HoverAnim > 0 then
                draw.RoundedBox(4, 0, 0, w, h, ColorAlpha(EV_THEME.primary, 40 * self.HoverAnim))
            end
            surface.SetDrawColor(THEME:LerpColor(self.HoverAnim, EV_THEME.textTertiary, EV_THEME.primary))
            surface.SetMaterial(Material("icon16/page_copy.png"))
            surface.DrawTexturedRect(w/2 - 8, h/2 - 8, 16, 16)
        end
        copyBtn.DoClick = function()
            SetClipboardText(tostring(value))
            ShowNotification("Copied!", NOTIFY_GENERIC, 2)
        end
    end

    AddInfoRow("Class", data.class or "Unknown", EV_THEME.primary)
    if data.model then AddInfoRow("Model", data.model) end
    if data.health then 
        AddInfoRow("Health", (data.health or "?") .. " / " .. (data.maxHealth or "?"), EV_THEME.success)
    end
    if data.pos then
        local p = data.pos
        AddInfoRow("Position", string.format("%.1f, %.1f, %.1f", p.x or 0, p.y or 0, p.z or 0))
    end
    if data.ang then
        local a = data.ang
        AddInfoRow("Angles", string.format("%.1f, %.1f, %.1f", a.p or 0, a.y or 0, a.r or 0))
    end
    if data.skin then AddInfoRow("Skin", data.skin) end

    local actionBar = vgui.Create("DPanel", frame)
    actionBar:SetPos(16, 540)
    actionBar:SetSize(518, 65)
    actionBar.Paint = function() end

    local function CreateActionBtn(text, x, w, color, onClick)
        local btn = vgui.Create("DButton", actionBar)
        btn:SetText(text)
        btn:SetFont("RareloadBody")
        btn:SetTextColor(EV_THEME.textPrimary)
        btn:SetPos(x, 0)
        btn:SetSize(w, 40)
        btn.HoverAnim = 0
        btn.Paint = function(self, bw, bh)
            self.HoverAnim = Lerp(FrameTime() * 10, self.HoverAnim, self:IsHovered() and 1 or 0)
            local col = THEME:LerpColor(self.HoverAnim * 0.2, color, Color(255, 255, 255))
            draw.RoundedBox(8, 0, 0, bw, bh, col)
        end
        btn.DoClick = onClick
        return btn
    end

    if data.pos then
        CreateActionBtn("Teleport", 0, 160, EV_THEME.success, function()
            RunConsoleCommand("rareload_teleport_to", data.pos.x, data.pos.y, data.pos.z)
            ShowNotification("Teleporting...", NOTIFY_GENERIC)
            frame:Close()
        end)
    end

    CreateActionBtn("Delete", 170, 160, EV_THEME.error, function()
        if onDelete then onDelete(data) end
        frame:Close()
    end)

    CreateActionBtn("Close", 340, 178, EV_THEME.surfaceVariant, function()
        frame:Close()
    end)
end

function EntityViewer:Open()
    if IsValid(self.Frame) then self.Frame:Close() end

    self.Data = self:LoadData()
    self:FilterAndSort()

    local frame = vgui.Create("DFrame")
    frame:SetSize(920, 620)
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:SetSizable(false)
    self.Frame = frame

    frame.Paint = function(self, w, h)
        draw.RoundedBox(12, 0, 0, w, h, EV_THEME.background)
        
        draw.RoundedBoxEx(12, 0, 0, 200, h, EV_THEME.backgroundDark, true, false, true, false)
        
        surface.SetDrawColor(EV_THEME.divider)
        surface.DrawLine(200, 0, 200, h)
        surface.DrawLine(200, 55, w, 55)
    end

    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetText("")
    closeBtn:SetSize(36, 36)
    closeBtn:SetPos(920 - 48, 10)
    closeBtn.HoverAnim = 0
    closeBtn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, self:IsHovered() and 1 or 0)
        draw.RoundedBox(8, 0, 0, w, h, EV_THEME.surface)
        if self.HoverAnim > 0 then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(EV_THEME.error, 200 * self.HoverAnim))
        end
        draw.SimpleText("✕", "RareloadSubheading", w/2, h/2, 
            THEME:LerpColor(self.HoverAnim, EV_THEME.textSecondary, EV_THEME.textPrimary), 
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function() frame:Close() end
    self.CloseBtn = closeBtn

    local sidebarHeader = vgui.Create("DPanel", frame)
    sidebarHeader:SetPos(0, 0)
    sidebarHeader:SetSize(200, 70)
    sidebarHeader.Paint = function(self, w, h)
        draw.SimpleText("Rareload", "RareloadHeading", 16, 18, EV_THEME.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Entity Viewer", "RareloadCaption", 16, 42, EV_THEME.textSecondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local categories = {"All", "NPCs", "Weapons", "Vehicles", "Props"}
    
    for i, cat in ipairs(categories) do
        CreateSidebarButton(frame, cat, 70 + (i - 1) * 48, function()
            EntityViewer.Category = cat
            EntityViewer:RefreshList()
        end, self)
    end

    local statsPanel = vgui.Create("DPanel", frame)
    statsPanel:SetPos(10, 520)
    statsPanel:SetSize(180, 85)
    statsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, EV_THEME.surface)
        
        local total = #EntityViewer.Data
        local filtered = #EntityViewer.FilteredData
        
        draw.SimpleText("Statistics", "RareloadLabel", 12, 10, EV_THEME.textSecondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Total: " .. total, "RareloadCaption", 12, 32, EV_THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Showing: " .. filtered, "RareloadCaption", 12, 50, EV_THEME.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Map: " .. game.GetMap(), "RareloadCaption", 12, 68, EV_THEME.textTertiary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local topBar = vgui.Create("DPanel", frame)
    topBar:SetPos(210, 0)
    topBar:SetSize(700, 55)
    topBar.Paint = function() end

    local searchContainer = vgui.Create("DPanel", topBar)
    searchContainer:SetPos(8, 10)
    searchContainer:SetSize(260, 36)
    searchContainer.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, EV_THEME.surface)
    end

    local searchIcon = vgui.Create("DPanel", searchContainer)
    searchIcon:SetPos(10, 10)
    searchIcon:SetSize(16, 16)
    searchIcon.Paint = function(self, w, h)
        surface.SetDrawColor(EV_THEME.textSecondary)
        surface.SetMaterial(Material("icon16/magnifier.png"))
        surface.DrawTexturedRect(0, 0, 16, 16)
    end

    local searchEntry = vgui.Create("DTextEntry", searchContainer)
    searchEntry:SetPos(32, 6)
    searchEntry:SetSize(216, 24)
    searchEntry:SetFont("RareloadBody")
    searchEntry:SetTextColor(EV_THEME.textPrimary)
    searchEntry:SetDrawBackground(false)
    searchEntry:SetPlaceholderText("Search entities...")
    searchEntry.Paint = function(self, w, h)
        self:DrawTextEntryText(EV_THEME.textPrimary, EV_THEME.primary, EV_THEME.textPrimary)
        if self:GetValue() == "" then
            draw.SimpleText("Search entities...", "RareloadBody", 0, h/2, EV_THEME.textTertiary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    searchEntry.OnChange = function(self)
        EntityViewer.SearchText = self:GetValue()
        EntityViewer:RefreshList()
    end

    local sortBtn = vgui.Create("DButton", topBar)
    sortBtn:SetPos(278, 10)
    sortBtn:SetSize(110, 36)
    sortBtn:SetText("")
    sortBtn.HoverAnim = 0
    sortBtn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 10, self.HoverAnim, self:IsHovered() and 1 or 0)
        local bgCol = THEME:LerpColor(self.HoverAnim * 0.3, EV_THEME.surface, EV_THEME.primary)
        draw.RoundedBox(8, 0, 0, w, h, bgCol)
        draw.SimpleText("Sort: " .. EntityViewer.SortMode, "RareloadBody", w/2, h/2, EV_THEME.textPrimary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    sortBtn.DoClick = function()
        if EntityViewer.SortMode == "Name" then 
            EntityViewer.SortMode = "Distance"
        elseif EntityViewer.SortMode == "Distance" then 
            EntityViewer.SortMode = "Health"
        else 
            EntityViewer.SortMode = "Name" 
        end
        EntityViewer:RefreshList()
    end

    local refreshBtn = vgui.Create("DButton", topBar)
    refreshBtn:SetPos(660, 10)
    refreshBtn:SetSize(36, 36)
    refreshBtn:SetText("")
    refreshBtn:SetTooltip("Refresh data")
    refreshBtn.HoverAnim = 0
    refreshBtn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 10, self.HoverAnim, self:IsHovered() and 1 or 0)
        local bgCol = THEME:LerpColor(self.HoverAnim, EV_THEME.surface, EV_THEME.primary)
        draw.RoundedBox(8, 0, 0, w, h, bgCol)
        
        surface.SetDrawColor(255, 255, 255, 180 + 75 * self.HoverAnim)
        surface.SetMaterial(Material("icon16/arrow_refresh.png"))
        surface.DrawTexturedRect(w/2 - 8, h/2 - 8, 16, 16)
    end
    refreshBtn.DoClick = function()
        EntityViewer.Data = EntityViewer:LoadData()
        EntityViewer:RefreshList()
        ShowNotification("Data refreshed!", NOTIFY_GENERIC)
    end

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(208, 63)
    scroll:SetSize(704, 550)

    local sbar = scroll:GetVBar()
    sbar:SetWide(6)
    sbar.Paint = function(self, w, h)
        draw.RoundedBox(3, 0, 0, w, h, EV_THEME.backgroundDark)
    end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(self, w, h)
        draw.RoundedBox(3, 0, 0, w, h, EV_THEME.primary)
    end

    local grid = vgui.Create("DIconLayout", scroll)
    grid:Dock(FILL)
    grid:DockMargin(12, 12, 12, 12)
    grid:SetSpaceX(12)
    grid:SetSpaceY(12)
    self.Grid = grid

    if IsValid(self.CloseBtn) then
        self.CloseBtn:MoveToFront()
    end

    self:RefreshList()
end

function EntityViewer:RefreshList()
    if not IsValid(self.Grid) then return end
    
    self:FilterAndSort()
    self.Grid:Clear()

    if #self.FilteredData == 0 then
        local emptyLabel = vgui.Create("DPanel", self.Grid)
        emptyLabel:SetSize(660, 180)
        emptyLabel.Paint = function(self, w, h)
            draw.SimpleText("No entities found", "RareloadSubheading", w/2, h/2 - 12, EV_THEME.textSecondary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("Try adjusting your search or category filter", "RareloadCaption", w/2, h/2 + 12, EV_THEME.textTertiary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    local viewer = self
    local count = 0
    for _, entData in ipairs(self.FilteredData) do
        CreateEntityCard(self.Grid, entData,
            function(data)
                if data.pos then
                    RunConsoleCommand("rareload_teleport_to", data.pos.x, data.pos.y, data.pos.z)
                    ShowNotification("Teleporting...", NOTIFY_GENERIC)
                end
            end,
            function(data)
                local entityId = ""
                if data.rawData then
                    entityId = data.rawData.RareloadNPCID or data.rawData.RareloadEntityID or data.rawData.UniqueID or ""
                end
                
                net.Start("RareloadEntityViewer_Delete")
                net.WriteString(tostring(entityId))
                net.WriteString(data.class or "Unknown")
                local posX, posY, posZ = 0, 0, 0
                if data.pos then
                    posX = data.pos.x or 0
                    posY = data.pos.y or 0
                    posZ = data.pos.z or 0
                end
                net.WriteFloat(posX)
                net.WriteFloat(posY)
                net.WriteFloat(posZ)
                net.SendToServer()
            end,
            function(data)
                CreateDetailsPanel(data, function(d)
                    local entityId = ""
                    if d.rawData then
                        entityId = d.rawData.RareloadNPCID or d.rawData.RareloadEntityID or d.rawData.UniqueID or ""
                    end
                    
                    net.Start("RareloadEntityViewer_Delete")
                    net.WriteString(tostring(entityId))
                    net.WriteString(d.class or "Unknown")
                    local posX, posY, posZ = 0, 0, 0
                    if d.pos then
                        posX = d.pos.x or 0
                        posY = d.pos.y or 0
                        posZ = d.pos.z or 0
                    end
                    net.WriteFloat(posX)
                    net.WriteFloat(posY)
                    net.WriteFloat(posZ)
                    net.SendToServer()
                end, viewer)
            end
        )
        count = count + 1
        if count > 150 then break end
    end
    
    self.Grid:InvalidateLayout(true)
end

net.Receive("RareloadEntityViewer_DeleteResult", function()
    local success = net.ReadBool()
    local message = net.ReadString()
    
    if success then
        ShowNotification(message, NOTIFY_GENERIC)
        timer.Simple(0.2, function()
            if EntityViewer.Frame and IsValid(EntityViewer.Frame) then
                EntityViewer.Data = EntityViewer:LoadData()
                EntityViewer:RefreshList()
            end
        end)
    else
        ShowNotification(message, NOTIFY_ERROR)
    end
end)

concommand.Add("rareload_entity_viewer", function() EntityViewer:Open() end)
concommand.Add("entity_viewer_open", function() EntityViewer:Open() end)

function OpenEntityViewer() 
    EntityViewer:Open() 
end

