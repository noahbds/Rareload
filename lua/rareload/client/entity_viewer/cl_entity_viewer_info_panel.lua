local PAL       = {
    bg        = Color(22, 23, 26),
    sidebar   = Color(16, 17, 20),
    surface   = Color(32, 34, 40),
    row       = Color(38, 40, 47),
    rowHover  = Color(48, 51, 60),
    accent    = Color(88, 101, 242),
    success   = Color(46, 204, 113),
    error     = Color(231, 76, 60),
    text      = Color(232, 233, 235),
    muted     = Color(138, 143, 153),
    divider   = Color(42, 44, 50),
    tabActive = Color(88, 101, 242),
    tabBg     = Color(22, 24, 28),
}

local SIDEBAR_W = 175
local FRAME_W   = 880
local FRAME_H   = 600
local HEADER_H  = 52

local function AddDataRow(parent, label, value, valueColor)
    valueColor = valueColor or PAL.text
    local strValue = tostring(value)

    local row = vgui.Create("DButton", parent)
    row:SetText("")
    row:Dock(TOP)
    row:SetTall(44)
    row:DockMargin(0, 0, 0, 5)
    row:SetCursor("arrow")

    local hov = 0
    local copied = false
    local copyTimer = 0

    row.Paint = function(self, w, h)
        hov = Lerp(FrameTime() * 10, hov, self:IsHovered() and 1 or 0)
        local bg = THEME:LerpColor(hov * 0.6, PAL.row, PAL.rowHover)
        draw.RoundedBox(7, 0, 0, w, h, bg)

        if hov > 0.01 then
            draw.RoundedBoxEx(7, 0, 0, 3, h, ColorAlpha(PAL.accent, 200 * hov), true, false, true, false)
        end

        draw.SimpleText(label, "RareloadLabel", 16, h / 2, PAL.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local displayVal = #strValue > 55 and string.sub(strValue, 1, 52) .. "…" or strValue
        local valColor = copied and PAL.success or valueColor
        draw.SimpleText(displayVal, "RareloadBody", 145, h / 2, valColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local iconAlpha = math.max(hov * 255, copied and 255 or 0)
        if iconAlpha > 1 then
            surface.SetDrawColor(copied and PAL.success or PAL.muted)
            surface.SetMaterial(Material(copied and "icon16/tick.png" or "icon16/page_copy.png"))
            surface.DrawTexturedRect(w - 30, h / 2 - 8, 16, 16)
        end
    end

    row.DoClick = function()
        SetClipboardText(strValue)
        copied    = true
        copyTimer = CurTime() + 1.5
        timer.Simple(1.5, function()
            if CurTime() >= copyTimer then copied = false end
        end)
        surface.PlaySound("ui/buttonclick.wav")
    end

    return row
end

local function AddSectionLabel(parent, text)
    local lbl = vgui.Create("DPanel", parent)
    lbl:Dock(TOP)
    lbl:SetTall(28)
    lbl:DockMargin(0, 8, 0, 4)
    lbl.Paint = function(self, w, h)
        draw.SimpleText(string.upper(text), "RareloadCaption", 0, h - 4, PAL.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        surface.SetDrawColor(PAL.divider)
        surface.DrawLine(0, h - 1, w, h - 1)
    end
end

local function BuildInfoTab(contentPanel, data)
    contentPanel:Clear()

    local scroll = vgui.Create("DScrollPanel", contentPanel)
    scroll:Dock(FILL)
    scroll:DockMargin(20, 16, 16, 16)

    local sbar = scroll:GetVBar()
    sbar:SetWide(4)
    sbar.Paint         = function(s, w, h) draw.RoundedBox(2, 0, 0, w, h, PAL.sidebar) end
    sbar.btnUp.Paint   = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(s, w, h) draw.RoundedBox(2, 0, 0, w, h, PAL.accent) end

    AddSectionLabel(scroll, "Identity")
    AddDataRow(scroll, "Class", data.class or "Unknown", PAL.accent)
    if data.id then AddDataRow(scroll, "ID", data.id) end
    if data.model then AddDataRow(scroll, "Model", data.model, PAL.muted) end
    if data.skin then AddDataRow(scroll, "Skin", data.skin) end

    if data.health or data.maxHealth then
        AddSectionLabel(scroll, "Combat")
        local hp      = tonumber(data.health) or 0
        local maxHp   = tonumber(data.maxHealth) or hp
        local hpColor = THEME:GetHealthColor(hp, maxHp)
        AddDataRow(scroll, "Health", hp, hpColor)
        AddDataRow(scroll, "Max Health", maxHp, PAL.muted)

        if maxHp > 0 then
            local barRow = vgui.Create("DPanel", scroll)
            barRow:Dock(TOP)
            barRow:SetTall(16)
            barRow:DockMargin(0, 0, 0, 8)
            barRow.Paint = function(self, w, h)
                draw.RoundedBox(3, 0, 4, w, h - 8, PAL.sidebar)
                local frac = math.Clamp(hp / maxHp, 0, 1)
                draw.RoundedBox(3, 0, 4, w * frac, h - 8, hpColor)
            end
        end
    end

    AddSectionLabel(scroll, "Transform")
    if data.pos then
        local p = data.pos
        local px = (isvector(p) and p.x) or (istable(p) and p.x) or 0
        local py = (isvector(p) and p.y) or (istable(p) and p.y) or 0
        local pz = (isvector(p) and p.z) or (istable(p) and p.z) or 0
        AddDataRow(scroll, "Position", string.format("%.2f, %.2f, %.2f", px, py, pz))
    end
    if data.ang then
        local a  = data.ang
        local ap = (isangle(a) and a.p) or (istable(a) and (a.p or a.pitch)) or 0
        local ay = (isangle(a) and a.y) or (istable(a) and (a.y or a.yaw)) or 0
        local ar = (isangle(a) and a.r) or (istable(a) and (a.r or a.roll)) or 0
        AddDataRow(scroll, "Angles", string.format("%.2f, %.2f, %.2f", ap, ay, ar))
    end

    local shown = {
        class = true,
        id = true,
        model = true,
        skin = true,
        health = true,
        maxHealth = true,
        pos = true,
        ang = true,
        rawData = true,
        __originalKey = true
    }

    local extras = {}
    for k, v in pairs(data) do
        if not shown[k] and type(v) ~= "table" and type(v) ~= "function" then
            table.insert(extras, { k = k, v = v })
        end
    end
    table.sort(extras, function(a, b) return a.k < b.k end)

    if #extras > 0 then
        AddSectionLabel(scroll, "Additional")
        for _, pair in ipairs(extras) do
            AddDataRow(scroll, pair.k, pair.v)
        end
    end
end

local function BuildEditorTab(contentPanel, data, isNPC, onSaved)
    contentPanel:Clear()

    if not (RARELOAD.JSONEditor and RARELOAD.JSONEditor.Create) then
        local err = vgui.Create("DLabel", contentPanel)
        err:Dock(FILL)
        err:SetText("JSON Editor component not loaded.")
        err:SetFont("RareloadSubheading")
        err:SetTextColor(THEME.error)
        err:SetContentAlignment(5)
        return
    end

    RARELOAD.JSONEditor.Create(contentPanel, data, isNPC, function(newData)
        local targetId = newData.RareloadNPCID
            or (data.rawData and data.rawData.RareloadNPCID)
            or (data.rawData and data.rawData.RareloadEntityID)
            or data.id
            or ""

        net.Start("RareloadEntityViewer_UpdateData")
        net.WriteString(tostring(targetId))
        net.WriteBool(isNPC)
        net.WriteTable(newData)
        net.SendToServer()

        ShowNotification("Update sent to server…", NOTIFY_GENERIC)

        if onSaved then onSaved(newData) end
    end)
end

function CreateDetailsPanel(data, isNPC, onDeleted, onAction)
    local isNPCEntity = isNPC
        or (data.class and string.find(string.lower(data.class or ""), "npc") ~= nil)

    local frame = vgui.Create("DFrame")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:MakePopup()
    frame:SetBackgroundBlur(true)
    frame:SetDraggable(true)
    frame:SetSizable(true)
    frame:SetMinWidth(700)
    frame:SetMinHeight(480)

    frame.Paint = function(self, w, h)
        draw.RoundedBox(12, 0, 0, w, h, PAL.bg)
        draw.RoundedBoxEx(12, 0, 0, w, HEADER_H, PAL.sidebar, true, true, false, false)
        draw.RoundedBoxEx(0, 0, HEADER_H, SIDEBAR_W, h - HEADER_H, PAL.sidebar, false, false, false, true)
        draw.RoundedBoxEx(12, 0, 0, SIDEBAR_W, h, PAL.sidebar, true, false, true, false)

        surface.SetDrawColor(PAL.divider)
        surface.DrawLine(SIDEBAR_W, HEADER_H, SIDEBAR_W, h)
        surface.DrawLine(SIDEBAR_W, HEADER_H, w, HEADER_H)
        surface.SetDrawColor(isNPCEntity and THEME.secondary or THEME.primary)
        surface.SetMaterial(Material(isNPCEntity and "icon16/user.png" or "icon16/bricks.png"))
        surface.DrawTexturedRect(16, HEADER_H / 2 - 8, 16, 16)

        draw.SimpleText("Entity Inspector", "RareloadHeading", 40, HEADER_H / 2 - 8,
            PAL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(data.class or "Unknown", "RareloadCaption", 40, HEADER_H / 2 + 8,
            PAL.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        surface.SetDrawColor(PAL.divider)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetText("")
    closeBtn:SetSize(32, 32)
    closeBtn:SetPos(FRAME_W - 44, (HEADER_H - 32) / 2)
    closeBtn.hov = 0
    closeBtn.Paint = function(self, w, h)
        self.hov = Lerp(FrameTime() * 12, self.hov, self:IsHovered() and 1 or 0)
        draw.RoundedBox(6, 0, 0, w, h, ColorAlpha(PAL.error, 30 + 170 * self.hov))
        draw.SimpleText("✕", "RareloadSubheading", w / 2, h / 2,
            THEME:LerpColor(self.hov, PAL.muted, PAL.text), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function() frame:Close() end
    frame:MoveToFront()

    local contentArea = vgui.Create("DPanel", frame)
    contentArea:SetPos(SIDEBAR_W + 1, HEADER_H + 1)
    contentArea:SetSize(FRAME_W - SIDEBAR_W - 1, FRAME_H - HEADER_H - 1)
    contentArea.Paint   = function() end

    frame.PerformLayout = function(self, w, h)
        contentArea:SetPos(SIDEBAR_W + 1, HEADER_H + 1)
        contentArea:SetSize(w - SIDEBAR_W - 1, h - HEADER_H - 1)
        closeBtn:SetPos(w - 44, (HEADER_H - 32) / 2)
    end

    local tabs          = {
        { id = "info",   label = "Information", icon = "icon16/information.png" },
        { id = "editor", label = "Data Editor", icon = "icon16/pencil.png" },
    }

    local activeTab     = ""
    local tabButtons    = {}

    local function SwitchTab(id)
        if activeTab == id then return end
        activeTab = id

        for _, btn in ipairs(tabButtons) do
            btn.isActive = (btn.tabId == id)
        end

        if id == "info" then
            BuildInfoTab(contentArea, data)
        elseif id == "editor" then
            BuildEditorTab(contentArea, data, isNPCEntity, function(newData)
                timer.Simple(0.6, function()
                    if OpenEntityViewer then OpenEntityViewer() end
                end)
            end)
        end

        surface.PlaySound("ui/buttonclick.wav")
    end

    local tabY = HEADER_H + 16
    for i, tabDef in ipairs(tabs) do
        local btn = vgui.Create("DButton", frame)
        btn:SetText("")
        btn:SetPos(8, tabY)
        btn:SetSize(SIDEBAR_W - 16, 46)
        btn.tabId     = tabDef.id
        btn.isActive  = false
        btn.hov       = 0

        local iconMat = Material(tabDef.icon)

        btn.Paint     = function(self, w, h)
            self.hov = Lerp(FrameTime() * 10, self.hov, (self:IsHovered() or self.isActive) and 1 or 0)

            if self.isActive then
                draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(PAL.accent, 30))
                draw.RoundedBox(3, 0, 10, 4, h - 20, PAL.accent)
            elseif self.hov > 0 then
                draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(PAL.surface, self.hov * 120))
            end

            local iconCol = self.isActive and PAL.accent or THEME:LerpColor(self.hov, PAL.muted, PAL.text)
            surface.SetDrawColor(iconCol)
            surface.SetMaterial(iconMat)
            surface.DrawTexturedRect(14, h / 2 - 8, 16, 16)

            local textCol = self.isActive and PAL.accent or THEME:LerpColor(self.hov, PAL.muted, PAL.text)
            draw.SimpleText(tabDef.label, "RareloadBody", 38, h / 2, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        btn.DoClick   = function() SwitchTab(tabDef.id) end

        table.insert(tabButtons, btn)
        tabY = tabY + 54
    end

    local deleteBtn = vgui.Create("DButton", frame)
    deleteBtn:SetText("")
    deleteBtn:SetPos(8, FRAME_H - 52)
    deleteBtn:SetSize(SIDEBAR_W - 16, 38)
    deleteBtn.hov = 0

    frame.PerformLayout = function(self, w, h)
        contentArea:SetPos(SIDEBAR_W + 1, HEADER_H + 1)
        contentArea:SetSize(w - SIDEBAR_W - 1, h - HEADER_H - 1)
        closeBtn:SetPos(w - 44, (HEADER_H - 32) / 2)
        deleteBtn:SetPos(8, h - 52)
    end

    deleteBtn.Paint = function(self, w, h)
        self.hov = Lerp(FrameTime() * 10, self.hov, self:IsHovered() and 1 or 0)
        local bg = ColorAlpha(PAL.error, 20 + 160 * self.hov)
        draw.RoundedBox(8, 0, 0, w, h, bg)

        surface.SetDrawColor(THEME:LerpColor(self.hov, PAL.muted, PAL.text))
        surface.SetMaterial(Material("icon16/cross.png"))
        surface.DrawTexturedRect(14, h / 2 - 8, 16, 16)

        draw.SimpleText("Delete Entity", "RareloadBody", 38, h / 2,
            THEME:LerpColor(self.hov, PAL.muted, PAL.error), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    deleteBtn.DoClick = function()
        if onDeleted then onDeleted(data) end
        frame:Close()
    end

    SwitchTab("info")
end
