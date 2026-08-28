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

local L = RARELOAD.L


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

local function BuildInfoTab(contentPanel, data, isNPC)
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

    AddSectionLabel(scroll, L("inspector.section.identity"))
    AddDataRow(scroll, L("inspector.row.class"), data.class or L("common.unknown"), PAL.accent)
    if data.id then AddDataRow(scroll, L("inspector.row.id"), data.id) end
    if data.model then AddDataRow(scroll, L("inspector.row.model"), data.model, PAL.muted) end
    if data.skin then AddDataRow(scroll, L("inspector.row.skin"), data.skin) end

    if data.health or data.maxHealth then
        AddSectionLabel(scroll, L("inspector.section.combat"))
        local hp      = tonumber(data.health) or 0
        local maxHp   = tonumber(data.maxHealth) or hp
        local hpColor = THEME:GetHealthColor(hp, maxHp)
        AddDataRow(scroll, L("inspector.row.health"), hp, hpColor)
        AddDataRow(scroll, L("inspector.row.max_health"), maxHp, PAL.muted)

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

    local raw = data.rawData or data
    local isVeh = (data.category == "vehicle") or raw.isVehicle or (data.class and (
        string.find(data.class, "vehicle") or
        string.find(data.class, "jeep") or
        string.find(data.class, "airboat") or
        string.find(data.class, "lfs_") or
        string.find(data.class, "lvs_") or
        string.find(data.class, "fphysics") or
        string.find(data.class, "glide_") or
        string.find(data.class, "wac_")
    ))

    if isVeh then
        AddSectionLabel(scroll, L("inspector.section.vehicle"))
        local isLVS = raw.LVS or raw.IsLVS or (data.class and string.find(data.class, "^lvs_"))
        local isLFS = raw.LFS or raw.IsLFS or (data.class and (string.find(data.class, "^lfs_") or string.find(data.class, "_lfs_") or string.find(data.class, "lunasflightschool")))
        local isSimfphys = raw.IsSimfphyscar or raw.bIsSimfphyscar or (data.class and string.find(data.class, "fphysics"))
        local isGlide = raw.IsGlideVehicle or (data.class and string.find(data.class, "^glide_"))
        local isWAC = raw.IsWAC or (data.class and string.find(data.class, "^wac_"))

        local frameworkName = isLVS and "[LVS] Luna Vehicle System"
            or (isLFS and "[LFS] Luna's Flight School")
            or (isSimfphys and "[Simfphys] Physics Vehicle")
            or (isWAC and "[WAC] Aircraft")
            or (isGlide and "[Glide] Vehicle")
            or "Source Engine Vehicle"
        AddDataRow(scroll, "Framework", frameworkName, Color(0, 220, 255))

        if raw.Category or raw.VehicleCategory then
            AddDataRow(scroll, "Category", raw.Category or raw.VehicleCategory, Color(200, 220, 255))
        end
        if raw.Author and raw.Author ~= "" then
            AddDataRow(scroll, "Author", raw.Author, Color(220, 220, 180))
        end

        local dt = raw.DT or raw.dt or {}
        local topSpeed = raw.MaxVelocity or raw.MaxSpeed or raw.TopSpeed
        if topSpeed and tonumber(topSpeed) and tonumber(topSpeed) > 0 then
            local numSpeed = tonumber(topSpeed)
            local kmh = math.Round(numSpeed * 0.06858)
            local mph = math.Round(numSpeed * 0.04261)
            AddDataRow(scroll, "Top Speed", string.format("%d u/s (%d km/h / %d mph)", numSpeed, kmh, mph), Color(100, 255, 150))
        end

        local engineActive = (dt.EngineActive ~= nil and dt.EngineActive) or (raw.EngineActive ~= nil and raw.EngineActive)
        if engineActive ~= nil then
            AddDataRow(scroll, "Engine", engineActive and "RUNNING" or "OFF", engineActive and PAL.success or PAL.error)
        end

        local curRPM = dt.RPM or raw.RPM
        local idleRPM = raw.IdleRPM or dt.MinRPM
        local limitRPM = raw.LimitRPM or raw.MaxRPM
        if idleRPM or limitRPM then
            AddDataRow(scroll, "RPM Range", string.format("%s - %s RPM", tostring(idleRPM or 0), tostring(limitRPM or 0)), Color(200, 255, 200))
        end

        local curGear = dt.Gear or raw.Gear
        local gears = raw.Gears or raw.ForwardGears
        if curGear or gears then
            AddDataRow(scroll, "Gears", (curGear and ("Gear " .. tostring(curGear)) or "Neutral") .. (gears and (" (of " .. tostring(gears) .. ")") or ""), Color(200, 200, 255))
        end

        local shield = dt.Shield or raw.Shield or raw.CurShield
        local maxShield = raw.MaxShield or raw.maxShield
        if (shield and tonumber(shield) and tonumber(shield) > 0) or (maxShield and tonumber(maxShield) and tonumber(maxShield) > 0) then
            AddDataRow(scroll, "Shield", tostring(shield or 0) .. " / " .. tostring(maxShield or 0) .. " HP", Color(100, 220, 255))
        end

        local ammoPri = dt.AmmoPrimary or raw.AmmoPrimary or raw.PrimaryAmmo
        if ammoPri ~= nil then
            AddDataRow(scroll, "Primary Ammo", tostring(ammoPri) .. " rounds", Color(255, 200, 100))
        end

        local ammoSec = dt.AmmoSecondary or raw.AmmoSecondary or raw.SecondaryAmmo
        if ammoSec ~= nil then
            AddDataRow(scroll, "Secondary Ammo", tostring(ammoSec) .. " rounds", Color(255, 160, 100))
        end

        local fuel = raw.Fuel or raw.fuel or dt.Fuel
        local maxFuel = raw.MaxFuel or raw.maxFuel or raw.FuelTankSize
        if fuel or maxFuel then
            AddDataRow(scroll, "Fuel", tostring(fuel or "?") .. (maxFuel and (" / " .. tostring(maxFuel)) or "") .. " L", Color(255, 220, 100))
        end
    end

    AddSectionLabel(scroll, L("inspector.section.position"))
    if data.pos then
        local p = data.pos
        local px = (isvector(p) and p.x) or (istable(p) and p.x) or 0
        local py = (isvector(p) and p.y) or (istable(p) and p.y) or 0
        local pz = (isvector(p) and p.z) or (istable(p) and p.z) or 0
        AddDataRow(scroll, L("inspector.row.position"), string.format("%.2f, %.2f, %.2f", px, py, pz))
    end
    if data.ang then
        local a  = data.ang
        local ap = (isangle(a) and a.p) or (istable(a) and (a.p or a.pitch)) or 0
        local ay = (isangle(a) and a.y) or (istable(a) and (a.y or a.yaw)) or 0
        local ar = (isangle(a) and a.r) or (istable(a) and (a.r or a.roll)) or 0
        AddDataRow(scroll, L("inspector.row.angles"), string.format("%.2f, %.2f, %.2f", ap, ay, ar))
    end

    if data.ang or data.pos then
        AddSectionLabel(scroll, L("inspector.section.actions"))

        local function CreateActionCheckbox(label, iconOn, iconOff, initialState, onClick)
            local btn = vgui.Create("DButton", scroll)
            btn:SetText("")
            btn:Dock(TOP)
            btn:SetTall(44)
            btn:DockMargin(0, 0, 0, 6)
            btn.isActive = initialState
            btn.hov = 0

            btn.Paint = function(self, w, h)
                self.hov = Lerp(FrameTime() * 10, self.hov, self:IsHovered() and 1 or 0)
                draw.RoundedBox(7, 0, 0, w, h, THEME:LerpColor(self.hov * 0.4, PAL.row, PAL.rowHover))

                local boxSize = 18
                local bx, by = w - 34, h / 2 - boxSize / 2
                draw.RoundedBox(4, bx, by, boxSize, boxSize, PAL.sidebar)
                if self.isActive then
                    draw.RoundedBox(4, bx + 3, by + 3, boxSize - 6, boxSize - 6, PAL.accent)
                end

                surface.SetDrawColor(self.isActive and PAL.accent or PAL.muted)
                surface.SetMaterial(Material(self.isActive and iconOn or iconOff))
                surface.DrawTexturedRect(16, h / 2 - 8, 16, 16)
                draw.SimpleText(label, "RareloadBody", 44, h / 2, PAL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            btn.DoClick = function(self)
                self.isActive = not self.isActive
                onClick(self.isActive)
                surface.PlaySound("ui/buttonclick.wav")
            end
            return btn
        end

        local targetId = data.id
            or data.RareloadEntityID
            or data.RareloadNPCID
            or (data.rawData and (data.rawData.RareloadEntityID or data.rawData.RareloadNPCID))
            or ""

        local ownerID = data.RareloadOwnerSteamID
            or (data.rawData and data.rawData.RareloadOwnerSteamID)
            or data.ownerSteamID
            or ""

        -- Read current physics flags from saved data
        local isFrozen        = false
        local isGravDisabled  = false

        local function ReadPhysicsFlags(src)
            if src.frozen ~= nil          then isFrozen       = src.frozen == true end
            if src.gravity_disabled ~= nil then isGravDisabled = src.gravity_disabled == true end
            if istable(src.PhysicsObjects) then
                for _, physObj in pairs(src.PhysicsObjects) do
                    if istable(physObj) then
                        if physObj.Frozen ~= nil       then isFrozen      = physObj.Frozen == true end
                        if physObj.GravityEnabled ~= nil then isGravDisabled = physObj.GravityEnabled == false end
                        break
                    end
                end
            end
        end

        ReadPhysicsFlags(data)
        if data.rawData then ReadPhysicsFlags(data.rawData) end

        local function SendFlag(flagName, value)
            net.Start("RareloadEntityViewer_SetFlag")
                net.WriteString(tostring(targetId))
                net.WriteBool(isNPC or false)
                net.WriteString(flagName)
                net.WriteBool(value)
                net.WriteString(tostring(ownerID))
            net.SendToServer()
        end

        CreateActionCheckbox(L("inspector.freeze"), "icon16/lock.png", "icon16/lock_open.png",
            isFrozen, function(newState) SendFlag("freeze", newState) end)

        CreateActionCheckbox(L("inspector.disable_gravity"), "icon16/arrow_down.png", "icon16/arrow_up.png",
            isGravDisabled, function(newState) SendFlag("gravity_disabled", newState) end)

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
        AddSectionLabel(scroll, L("inspector.section.additional"))
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
        err:SetText(L("inspector.editor_missing"))
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

        ShowNotification(L("inspector.update_sent"), NOTIFY_GENERIC)

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

        draw.SimpleText(L("inspector.title"), "RareloadHeading", 40, HEADER_H / 2 - 8,
            PAL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(data.class or L("common.unknown"), "RareloadCaption", 40, HEADER_H / 2 + 8,
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

    local tabs          = {
        { id = "info",   label = L("inspector.tab.info"),   icon = "icon16/information.png" },
        { id = "editor", label = L("inspector.tab.editor"), icon = "icon16/pencil.png" },
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
            BuildInfoTab(contentArea, data, isNPCEntity)
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

    local function MakeToggleButton(label, icon, accent, isActiveFn, onClick)
        local btn = vgui.Create("DButton", frame)
        btn:SetText("")
        btn:SetSize(SIDEBAR_W - 16, 38)
        btn.hov = 0
        btn.Paint = function(self, w, h)
            self.hov = Lerp(FrameTime() * 10, self.hov, self:IsHovered() and 1 or 0)
            local active = isActiveFn()
            draw.RoundedBox(8, 0, 0, w, h, active and ColorAlpha(accent, 235) or ColorAlpha(accent, 18 + 130 * self.hov))
            local fg = active and color_white or THEME:LerpColor(self.hov, PAL.muted, PAL.text)
            surface.SetDrawColor(fg)
            surface.SetMaterial(Material(icon))
            surface.DrawTexturedRect(14, h / 2 - 8, 16, 16)
            draw.SimpleText(label, "RareloadBody", 38, h / 2, fg, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        btn.DoClick = onClick
        return btn
    end

    local function HL() return SED and SED.Highlight end

    local highlightBtn = MakeToggleButton(L("inspector.highlight"), "icon16/flag_yellow.png", PAL.accent,
        function() return HL() and SED.Highlight.IsActive("saved", data.id) or false end,
        function() if HL() then SED.Highlight.ToggleSaved(data.id, isNPCEntity) end end)

    local linkBtn = MakeToggleButton(L("inspector.link_phantom"), "icon16/connect.png", Color(0, 188, 212),
        function() return HL() and SED.Highlight.IsActive("live2phantom", data.id) or false end,
        function() if HL() then SED.Highlight.ToggleLiveToPhantom(data.id, isNPCEntity) end end)

    local deleteBtn = vgui.Create("DButton", frame)
    deleteBtn:SetText("")
    deleteBtn:SetPos(8, FRAME_H - 52)
    deleteBtn:SetSize(SIDEBAR_W - 16, 38)
    deleteBtn.hov = 0

    frame.PerformLayout = function(self, w, h)
        contentArea:SetPos(SIDEBAR_W + 1, HEADER_H + 1)
        contentArea:SetSize(w - SIDEBAR_W - 1, h - HEADER_H - 1)
        closeBtn:SetPos(w - 44, (HEADER_H - 32) / 2)
        highlightBtn:SetPos(8, h - 52 - 86)
        linkBtn:SetPos(8, h - 52 - 43)
        deleteBtn:SetPos(8, h - 52)
    end

    deleteBtn.Paint = function(self, w, h)
        self.hov = Lerp(FrameTime() * 10, self.hov, self:IsHovered() and 1 or 0)
        local bg = ColorAlpha(PAL.error, 20 + 160 * self.hov)
        draw.RoundedBox(8, 0, 0, w, h, bg)

        surface.SetDrawColor(THEME:LerpColor(self.hov, PAL.muted, PAL.text))
        surface.SetMaterial(Material("icon16/cross.png"))
        surface.DrawTexturedRect(14, h / 2 - 8, 16, 16)

        draw.SimpleText(L("inspector.delete"), "RareloadBody", 38, h / 2,
            THEME:LerpColor(self.hov, PAL.muted, PAL.error), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    deleteBtn.DoClick = function()
        if onDeleted then onDeleted(data) end
        frame:Close()
    end

    SwitchTab("info")
end
