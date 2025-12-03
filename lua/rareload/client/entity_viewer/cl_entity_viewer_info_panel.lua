local draw, surface, util, vgui, hook, render = draw, surface, util, vgui, hook, render
local math, string, os = math, string, os
local Color, Vector, Angle = Color, Vector, Angle
local IsValid, CurTime, FrameTime, Lerp = IsValid, CurTime, FrameTime, Lerp

local MAT_DELETE_ICON = Material("icon16/image_delete.png")
local MAT_TELEPORT = Material("icon16/arrow_right.png")
local MAT_COPY = Material("icon16/page_copy.png")

-- Helper for detail rows
local function AddDetailRow(parent, label, value, color)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(32)
    row:DockMargin(0, 0, 0, 4)
    row.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.surface)
    end

    local lbl = vgui.Create("DLabel", row)
    lbl:SetText(label)
    lbl:SetFont("RareloadLabel") -- Ensure this font exists or use default
    lbl:SetTextColor(THEME.textSecondary)
    lbl:Dock(LEFT)
    lbl:DockMargin(12, 0, 0, 0)
    lbl:SetWide(100)

    local val = vgui.Create("DLabel", row)
    val:SetText(tostring(value))
    val:SetFont("RareloadBody")
    val:SetTextColor(color or THEME.textPrimary)
    val:Dock(FILL)
    val:DockMargin(10, 0, 40, 0)

    local btn = vgui.Create("DButton", row)
    btn:SetText("")
    btn:Dock(RIGHT)
    btn:SetWide(32)
    btn.Paint = function(self, w, h)
        if self:IsHovered() then
            draw.RoundedBox(6, 0, 0, w, h, Color(255,255,255,10))
        end
        surface.SetDrawColor(THEME.textTertiary)
        surface.SetMaterial(MAT_COPY)
        surface.DrawTexturedRect(8, 8, 16, 16)
    end
    btn.DoClick = function()
        SetClipboardText(tostring(value))
        ShowNotification("Copied " .. label, NOTIFY_GENERIC)
    end
end

local function CreateDetailsPanel(data, isNPC, onDeleted, onAction)
    local frame = vgui.Create("DFrame")
    frame:SetSize(650, 700)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame:SetBackgroundBlur(true)
    
    frame.Paint = function(self, w, h)
        THEME:DrawBlur(self, 4)
        draw.RoundedBox(12, 0, 0, w, h, THEME.background)
        draw.RoundedBoxEx(12, 0, 0, w, 60, THEME.backgroundDark, true, true, false, false)
        
        draw.SimpleText("Entity Details", "RareloadHeading", 20, 30, THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        
        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    -- Tab System
    local tabContainer = vgui.Create("DPanel", frame)
    tabContainer:SetPos(0, 60)
    tabContainer:SetSize(650, 40)
    tabContainer.Paint = function(self, w, h)
        surface.SetDrawColor(THEME.divider)
        surface.DrawLine(0, h-1, w, h-1)
    end

    local activeTab = "info"
    local contentPanel = vgui.Create("DPanel", frame)
    contentPanel:SetPos(0, 100)
    contentPanel:SetSize(650, 520)
    contentPanel.Paint = function() end

    local function CreateTab(text, id, x)
        local btn = vgui.Create("DButton", tabContainer)
        btn:SetText(text)
        btn:SetFont("RareloadBody")
        btn:SetPos(x, 5)
        btn:SetSize(100, 30)
        btn:SetTextColor(THEME.textPrimary)
        
        btn.Paint = function(self, w, h)
            local isActive = activeTab == id
            if isActive then
                draw.RoundedBox(6, 0, 0, w, h, THEME.primary)
            elseif self:IsHovered() then
                draw.RoundedBox(6, 0, 0, w, h, THEME.surfaceVariant)
            end
        end
        
        btn.DoClick = function()
            activeTab = id
            contentPanel:Clear()
            
            if id == "info" then
                -- Info Tab Content
                local scroll = vgui.Create("DScrollPanel", contentPanel)
                scroll:Dock(FILL)
                scroll:DockMargin(20, 10, 20, 10)
                
                AddDetailRow(scroll, "Class", data.class or "Unknown", THEME.primary)
                if data.model then AddDetailRow(scroll, "Model", data.model, THEME.textSecondary) end
                if data.health then AddDetailRow(scroll, "Health", data.health .. "/" .. (data.maxHealth or "?"), THEME.success) end
                
                if data.pos then 
                    local p = data.pos
                    local px = tonumber(p.x) or 0
                    local py = tonumber(p.y) or 0
                    local pz = tonumber(p.z) or 0
                    AddDetailRow(scroll, "Position", string.format("%.1f, %.1f, %.1f", px, py, pz), THEME.textSecondary) 
                end
                
                if data.ang then
                    local a = data.ang
                    local ap = tonumber(a.p) or 0
                    local ay = tonumber(a.y) or 0
                    local ar = tonumber(a.r) or 0
                    AddDetailRow(scroll, "Angles", string.format("%.1f, %.1f, %.1f", ap, ay, ar), THEME.textSecondary)
                end
                
                if data.skin then AddDetailRow(scroll, "Skin", data.skin, THEME.textSecondary) end
            elseif id == "json" then
                -- JSON Editor Tab
                if RARELOAD and RARELOAD.JSONEditor and RARELOAD.JSONEditor.Create then
                    RARELOAD.JSONEditor.Create(contentPanel, data.rawData or data, isNPC, function(newData)
                        -- Persist changes back to disk
                        local map = game.GetMap()
                        local filename = "rareload/player_positions_" .. map .. ".json"
                        if not file.Exists(filename, "DATA") then
                            ShowNotification("Data file missing: " .. filename, NOTIFY_ERROR)
                            return
                        end

                        local raw = file.Read(filename, "DATA")
                        if not raw or raw == "" then
                            ShowNotification("Failed to read data file", NOTIFY_ERROR)
                            return
                        end

                        local ok, tbl = pcall(util.JSONToTable, raw)
                        if not ok or not istable(tbl) then
                            ShowNotification("Invalid JSON in data file", NOTIFY_ERROR)
                            return
                        end

                        -- Helper: recursively replace entity by RareloadNPCID
                        local targetId = newData.RareloadNPCID or (data.rawData and data.rawData.RareloadNPCID)
                        local function replaceById(node)
                            if not istable(node) then return false end
                            -- Direct entity match
                            if node.RareloadNPCID and node.RareloadNPCID == targetId then
                                -- Overwrite all fields in-place
                                for k in pairs(node) do node[k] = nil end
                                for k, v in pairs(newData) do node[k] = v end
                                return true
                            end
                            -- Recurse into tables and arrays
                            for k, v in pairs(node) do
                                if istable(v) then
                                    if replaceById(v) then return true end
                                end
                            end
                            return false
                        end

                        local replaced = replaceById(tbl)
                        if not replaced then
                            ShowNotification("Entity not found in data file", NOTIFY_ERROR)
                            return
                        end

                        local out = util.TableToJSON(tbl, true)
                        if not out or out == "" then
                            ShowNotification("Failed to serialize updated JSON", NOTIFY_ERROR)
                            return
                        end

                        file.Write(filename, out)
                        ShowNotification("JSON saved", NOTIFY_GENERIC)
                        if onAction then onAction(newData) end
                        -- Optionally refresh list
                        if OpenEntityViewer then
                            -- reopen to refresh
                            OpenEntityViewer()
                        end
                    end)
                else
                    local lbl = vgui.Create("DLabel", contentPanel)
                    lbl:SetText("JSON Editor not available")
                    lbl:SetFont("RareloadBody")
                    lbl:SetTextColor(THEME.textSecondary)
                    lbl:Dock(FILL)
                    lbl:SetContentAlignment(5)
                end
            end
        end
        
        return btn
    end

    CreateTab("Info", "info", 20)
    CreateTab("JSON Editor", "json", 130)

    -- Trigger initial tab load
    contentPanel:Clear()
    local scroll = vgui.Create("DScrollPanel", contentPanel)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 10, 20, 10)
    
    AddDetailRow(scroll, "Class", data.class or "Unknown", THEME.primary)
    if data.model then AddDetailRow(scroll, "Model", data.model, THEME.textSecondary) end
    if data.health then AddDetailRow(scroll, "Health", data.health .. "/" .. (data.maxHealth or "?"), THEME.success) end
    
    if data.pos then 
        local p = data.pos
        local px = tonumber(p.x) or 0
        local py = tonumber(p.y) or 0
        local pz = tonumber(p.z) or 0
        AddDetailRow(scroll, "Position", string.format("%.1f, %.1f, %.1f", px, py, pz), THEME.textSecondary) 
    end
    
    if data.ang then
        local a = data.ang
        local ap = tonumber(a.p) or 0
        local ay = tonumber(a.y) or 0
        local ar = tonumber(a.r) or 0
        AddDetailRow(scroll, "Angles", string.format("%.1f, %.1f, %.1f", ap, ay, ar), THEME.textSecondary)
    end
    
    if data.skin then AddDetailRow(scroll, "Skin", data.skin, THEME.textSecondary) end

    -- Action Bar
    local actions = vgui.Create("DPanel", frame)
    actions:Dock(BOTTOM)
    actions:SetTall(60)
    actions:DockMargin(20, 0, 20, 20)
    actions.Paint = function() end

    local function AddActionBtn(text, color, func)
        local btn = vgui.Create("DButton", actions)
        btn:SetText(text)
        btn:SetFont("RareloadBody")
        btn:SetTextColor(THEME.textPrimary)
        btn:Dock(RIGHT)
        btn:DockMargin(10, 0, 0, 0)
        btn:SetWide(100)
        btn.Paint = function(self, w, h)
            local col = color
            if self:IsHovered() then col = THEME:LerpColor(0.1, col, Color(255,255,255)) end
            draw.RoundedBox(6, 0, 0, w, h, col)
        end
        btn.DoClick = func
    end

    AddActionBtn("Close", THEME.surfaceVariant, function() frame:Close() end)
    
    AddActionBtn("Delete", THEME.error, function()
        if onDeleted then onDeleted(data) end
        frame:Close()
    end)

    if data.pos then
        AddActionBtn("Teleport", THEME.success, function()
            RunConsoleCommand("rareload_teleport_to", data.pos.x, data.pos.y, data.pos.z)
            ShowNotification("Teleporting...", NOTIFY_GENERIC)
        end)
    end
end

function CreateInfoPanel(parent, data, isNPC, onDeleted, onAction)
    local card = parent:Add("DButton")
    card:SetText("")
    card:SetSize(200, 260)
    
    local typeColor = THEME:GetEntityTypeColor(data.class)
    local hoverFraction = 0

    card.Paint = function(self, w, h)
        local hovered = self:IsHovered()
        hoverFraction = Lerp(FrameTime() * 10, hoverFraction, hovered and 1 or 0)
        
        -- Background
        THEME:DrawCard(0, 0, w, h, THEME.surface, hovered)
        
        -- Type Strip
        draw.RoundedBoxEx(8, 0, h-4, w, 4, typeColor, false, false, true, true)
    end

    card.DoClick = function()
        CreateDetailsPanel(data, isNPC, onDeleted, onAction)
    end

    -- Model Preview
    local modelPanel = vgui.Create("DModelPanel", card)
    modelPanel:SetPos(0, 0)
    modelPanel:SetSize(200, 160)
    modelPanel:SetMouseInputEnabled(false)

    if data.model and util.IsValidModel(data.model) then
        modelPanel:SetModel(data.model)
        local ent = modelPanel:GetEntity()
        if IsValid(ent) then
            local min, max = ent:GetRenderBounds()
            local center = (min + max) * 0.5
            local size = max:Distance(min)
            modelPanel:SetLookAt(center)
            modelPanel:SetCamPos(center + Vector(size * 0.8, size * 0.6, size * 0.4))
            modelPanel:SetFOV(45)
        end
    else
        modelPanel.Paint = function(self, w, h)
            draw.RoundedBoxEx(8, 0, 0, w, h, THEME.backgroundDark, true, true, false, false)
            draw.SimpleText("?", "RareloadHeading", w/2, h/2, THEME.textDisabled, 1, 1)
        end
    end

    -- Info Container
    local info = vgui.Create("DPanel", card)
    info:SetPos(0, 160)
    info:SetSize(200, 100)
    info:SetMouseInputEnabled(false)
    info.Paint = function() end

    -- Name
    local name = data.class or "Unknown"
    if string.len(name) > 20 then name = string.sub(name, 1, 18) .. "..." end
    
    local lblName = vgui.Create("DLabel", info)
    lblName:SetText(name)
    lblName:SetFont("RareloadSubheading")
    lblName:SetTextColor(THEME.textPrimary)
    lblName:SetPos(10, 5)
    lblName:SetSize(180, 20)
    lblName:SetContentAlignment(5)

    -- Health Bar
    if data.health then
        local hp = tonumber(data.health) or 0
        local maxHp = tonumber(data.maxHealth) or hp
        if maxHp > 0 then
            local hpBar = vgui.Create("DPanel", info)
            hpBar:SetPos(20, 35)
            hpBar:SetSize(160, 6)
            hpBar.Paint = function(self, w, h)
                draw.RoundedBox(3, 0, 0, w, h, THEME.backgroundDark)
                local frac = math.Clamp(hp / maxHp, 0, 1)
                draw.RoundedBox(3, 0, 0, w * frac, h, THEME:GetHealthColor(hp, maxHp))
            end
        end
    end

    -- Distance
    if data.pos and IsValid(LocalPlayer()) then
        local dist = math.Round(LocalPlayer():GetPos():Distance(Vector(data.pos.x, data.pos.y, data.pos.z)))
        local lblDist = vgui.Create("DLabel", info)
        lblDist:SetText(dist .. " units")
        lblDist:SetFont("RareloadCaption")
        lblDist:SetTextColor(THEME.textSecondary)
        lblDist:SetPos(10, 50)
        lblDist:SetSize(180, 20)
        lblDist:SetContentAlignment(5)
    end

    return card
end
