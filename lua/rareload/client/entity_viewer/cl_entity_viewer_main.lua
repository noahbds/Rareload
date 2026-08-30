-- ─────────────────────────────────────────────────────────────────────────────
-- Saved Objects viewer  (rewritten from scratch, 4.1)
--
-- Browses and edits the entities / NPCs / vehicles stored inside ONE Save Timeline
-- entry. It is no longer a standalone window — the Timeline's per-save "Objects"
-- button sends the entry's object records and opens this as a scaled overlay.
--
-- Shares the Timeline's look through RARELOAD.UI (RH_* fonts, sc() scaling, Button,
-- StyleScrollbar, FrameModelPanel, ConfirmDialog, Derma icons). Layout mirrors the
-- Timeline: a left category/search rail, a card grid, and an inline detail pane
-- (model, fields, freeze/gravity toggles, Edit-JSON, Delete). Mutations route to the
-- history store via EntityViewer:SendHistoryObjAction.
-- ─────────────────────────────────────────────────────────────────────────────

local draw, surface, vgui = draw, surface, vgui
local IsValid, FrameTime, Lerp = IsValid, FrameTime, Lerp
local ALIGN_L, ALIGN_R, ALIGN_C = TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER
local ALIGN_T, ALIGN_M = TEXT_ALIGN_TOP, TEXT_ALIGN_CENTER

include("cl_entity_viewer_theme.lua")
include("cl_entity_viewer_utils.lua")

EV_THEME = THEME
local L  = RARELOAD.L
local UI = RARELOAD.UI
local sc = UI.sc

local CATEGORIES = { "All", "NPCs", "Weapons", "Vehicles", "Props" }
local CAT_KEY = { All = "ev.cat.all", NPCs = "ev.cat.npcs", Weapons = "ev.cat.weapons", Vehicles = "ev.cat.vehicles", Props = "ev.cat.props" }
local SORTS = { "Name", "Distance", "Health" }

local EntityViewer        = {}
EntityViewer.Data         = {}
EntityViewer.FilteredData = {}
EntityViewer.SearchText   = ""
EntityViewer.Category     = "All"
EntityViewer.SortMode     = "Name"
EntityViewer.Context      = nil -- { saveId, ownerSID, objects, parent, label }
EntityViewer.SelectedID   = nil
RARELOAD.EntityViewer     = EntityViewer

-- ── context / history routing ─────────────────────────────────────────────────

function EntityViewer:IsHistory()
    return istable(self.Context) and isstring(self.Context.saveId) and self.Context.saveId ~= ""
end

function EntityViewer:SendHistoryObjAction(op, targetId, isNPC, opts)
    if not self:IsHistory() then return false end
    opts = opts or {}
    net.Start("RareloadHistory_ObjAction")
    net.WriteString(self.Context.saveId)
    net.WriteString(op)
    net.WriteString(tostring(targetId or ""))
    net.WriteBool(isNPC and true or false)
    if op == "edit" then net.WriteTable(opts.data or {}) end
    if op == "flag" then
        net.WriteString(tostring(opts.flag or ""))
        net.WriteBool(opts.value and true or false)
    end
    net.SendToServer()
    return true
end

-- ── data ──────────────────────────────────────────────────────────────────────

local function ObjID(o)
    return o.id or o.RareloadEntityID or o.RareloadNPCID or o.RareloadID
end

-- Build the flat viewer list from the object records the server sent for this save.
function EntityViewer:LoadData()
    local loaded = {}
    if not (self:IsHistory() and istable(self.Context.objects)) then return loaded end
    for _, s in ipairs(self.Context.objects) do
        if istable(s) then
            local ent = {
                id        = s.id or s.RareloadEntityID or s.RareloadNPCID or s.RareloadID,
                class     = s.class or s.Class,
                model     = s.model or s.Model,
                pos       = s.pos or s.Pos,
                ang       = s.ang or s.Angle or s.Ang,
                health    = s.health or s.CurHealth,
                maxHealth = s.maxHealth or s.MaxHealth,
                skin      = s.skin or s.Skin,
                isNPC     = s.isNPC and true or false,
                isVehicle = s.isVehicle and true or false,
                rawData   = s,
            }
            if istable(ent.pos) then ent.pos = Vector(ent.pos.x or 0, ent.pos.y or 0, ent.pos.z or 0) end
            if istable(ent.ang) then ent.ang = Angle(ent.ang.p or 0, ent.ang.y or 0, ent.ang.r or 0) end
            loaded[#loaded + 1] = ent
        end
    end
    return loaded
end

function EntityViewer:FilterAndSort()
    self.FilteredData = {}
    local search = string.lower(self.SearchText or "")
    local cat = self.Category
    for _, ent in ipairs(self.Data) do
        local class = string.lower(ent.class or "")
        local model = string.lower(ent.model or "")
        local matchCat =
            cat == "All"
            or (cat == "NPCs" and ent.isNPC)
            or (cat == "Vehicles" and ent.isVehicle)
            or (cat == "Weapons" and string.find(class, "weapon", 1, true))
            or (cat == "Props" and string.find(class, "prop", 1, true))
        local matchSearch = (search == "") or string.find(class, search, 1, true) or string.find(model, search, 1, true)
        if matchCat and matchSearch then self.FilteredData[#self.FilteredData + 1] = ent end
    end

    local lp = LocalPlayer()
    table.sort(self.FilteredData, function(a, b)
        if self.SortMode == "Distance" and IsValid(lp) then
            local dA = a.pos and lp:GetPos():DistToSqr(a.pos) or math.huge
            local dB = b.pos and lp:GetPos():DistToSqr(b.pos) or math.huge
            return dA < dB
        elseif self.SortMode == "Health" then
            return (tonumber(a.health) or 0) > (tonumber(b.health) or 0)
        end
        return (a.class or "") < (b.class or "")
    end)
end

function EntityViewer:ReloadDataAndRefresh()
    self.Data = self:LoadData()
    if self.SelectedID and not self:Selected() then self.SelectedID = nil end
    self:RefreshList()
    self:UpdateDetail()
end

function EntityViewer:Selected()
    if not self.SelectedID then return nil end
    for _, e in ipairs(self.Data) do
        if ObjID(e) == self.SelectedID then return e end
    end
    return nil
end

-- Read freeze / no-gravity state from a saved record (top-level or physics bodies).
local function ReadFlags(ent)
    local frozen, nograv = false, false
    local function rd(src)
        if not istable(src) then return end
        if src.frozen ~= nil then frozen = src.frozen == true end
        if src.gravity_disabled ~= nil then nograv = src.gravity_disabled == true end
        if istable(src.PhysicsObjects) then
            for _, p in pairs(src.PhysicsObjects) do
                if istable(p) then
                    if p.Frozen ~= nil then frozen = p.Frozen == true end
                    if p.GravityEnabled ~= nil then nograv = p.GravityEnabled == false end
                    break
                end
            end
        end
    end
    rd(ent); rd(ent.rawData)
    return frozen, nograv
end

-- ── JSON editor popup ───────────────────────────────────────────────────────

function EntityViewer:OpenJSONEditor(ent)
    if not (RARELOAD.JSONEditor and RARELOAD.JSONEditor.Create) then
        ShowNotification(L("inspector.editor_missing"), NOTIFY_ERROR)
        return
    end
    local d = vgui.Create("DFrame")
    d:SetSize(sc(560), sc(660)); d:Center(); d:SetTitle(""); d:ShowCloseButton(false); d:MakePopup()
    d.Paint = function(_, w, h)
        draw.RoundedBox(sc(12), 0, 0, w, h, THEME.background)
        surface.SetDrawColor(THEME.divider); surface.DrawLine(0, sc(46), w, sc(46))
        draw.SimpleText(L("inspector.tab.editor"), "RH_H2", sc(16), sc(23), THEME.primaryLight, ALIGN_L, ALIGN_M)
        draw.SimpleText(tostring(ent.class or "?"), "RH_Small", sc(16) + surface.GetTextSize(L("inspector.tab.editor")) + sc(12), sc(23), THEME.textTertiary, ALIGN_L, ALIGN_M)
    end
    local close = UI.Button(d, "✕", THEME.error, function() d:Close() end)
    close:SetSize(sc(30), sc(30)); close:SetPos(sc(560) - sc(38), sc(8))
    local content = vgui.Create("DPanel", d)
    content:Dock(FILL); content:DockMargin(sc(10), sc(52), sc(10), sc(10)); content.Paint = function() end
    RARELOAD.JSONEditor.Create(content, ent, ent.isNPC, function(newData)
        local targetId = newData.RareloadNPCID
            or (ent.rawData and (ent.rawData.RareloadNPCID or ent.rawData.RareloadEntityID))
            or ent.id or ""
        EntityViewer:SendHistoryObjAction("edit", targetId, ent.isNPC, { data = newData })
        ShowNotification(L("inspector.update_sent"), NOTIFY_GENERIC)
        d:Close()
    end)
end

-- ── inline detail pane (built once, updated in place) ─────────────────────────

function EntityViewer:BuildDetail(host)
    local D = {}
    self.D = D

    local model = vgui.Create("DModelPanel", host)
    D.model = model
    model:Dock(TOP); model:SetTall(sc(190)); model:DockMargin(0, 0, 0, sc(8))
    model:SetModel("models/error.mdl"); model:SetMouseInputEnabled(false)
    model.LayoutEntity = function(_, e) e:SetAngles(Angle(0, RealTime() * 26, 0)) end
    local baseModelPaint = model.Paint
    model.Paint = function(selfp, w, h)
        draw.RoundedBox(sc(10), 0, 0, w, h, THEME.backgroundDark)
        baseModelPaint(selfp, w, h)
    end

    -- self-drawn fields block
    local fields = vgui.Create("DPanel", host)
    D.fields = fields
    fields:Dock(TOP); fields:SetTall(sc(150)); fields:DockMargin(0, 0, 0, sc(8))
    fields.Paint = function(_, w, h)
        draw.RoundedBox(sc(10), 0, 0, w, h, THEME.surface)
        local e = self:Selected(); if not e then return end
        local rows = {
            { L("inspector.row.class"), tostring(e.class or "?") },
            { L("inspector.row.model"), tostring(e.model or "-") },
            { L("inspector.row.health"), (e.health and tostring(math.floor(e.health)) or "-") ..
                (e.maxHealth and (" / " .. math.floor(e.maxHealth)) or "") },
            { L("inspector.row.position"), e.pos and string.format("%.0f, %.0f, %.0f", e.pos.x, e.pos.y, e.pos.z) or "-" },
            { L("inspector.row.skin"), tostring(e.skin or 0) },
        }
        local y, rh = sc(8), sc(26)
        for i, r in ipairs(rows) do
            if i > 1 then
                surface.SetDrawColor(THEME.divider.r, THEME.divider.g, THEME.divider.b, 90)
                surface.DrawLine(sc(12), y, w - sc(12), y)
            end
            draw.SimpleText(r[1], "RH_Small", sc(12), y + rh / 2, THEME.textTertiary, ALIGN_L, ALIGN_M)
            draw.SimpleText(r[2], "RH_Small", w - sc(12), y + rh / 2, THEME.textPrimary, ALIGN_R, ALIGN_M)
            y = y + rh
        end
    end

    -- freeze / gravity toggles
    local function flagBox(labelKey)
        local cb = vgui.Create("DCheckBoxLabel", host)
        cb:Dock(TOP); cb:DockMargin(sc(2), 0, 0, sc(6))
        cb:SetText(L(labelKey)); cb:SetFont("RH_Small"); cb:SetTextColor(THEME.textSecondary)
        cb:SizeToContents()
        return cb
    end
    D.freeze = flagBox("inspector.freeze")
    D.freeze.OnChange = function(_, v)
        if self._syncing then return end
        local e = self:Selected(); if not e then return end
        self:SendHistoryObjAction("flag", ObjID(e), e.isNPC, { flag = "freeze", value = v })
    end
    D.gravity = flagBox("inspector.disable_gravity")
    D.gravity.OnChange = function(_, v)
        if self._syncing then return end
        local e = self:Selected(); if not e then return end
        self:SendHistoryObjAction("flag", ObjID(e), e.isNPC, { flag = "gravity_disabled", value = v })
    end

    -- actions
    D.editBtn = UI.Button(host, L("ev.edit_json"), THEME.primary, function()
        local e = self:Selected(); if e then self:OpenJSONEditor(e) end
    end)
    D.editBtn:Dock(TOP); D.editBtn:DockMargin(0, sc(6), 0, sc(6)); D.editBtn:SetTall(sc(32))

    D.delBtn = UI.Button(host, L("sth.delete"), THEME.error, function()
        local e = self:Selected(); if not e then return end
        UI.ConfirmDialog(L("sth.delete"), L("sth.delete_confirm"), function()
            self:SendHistoryObjAction("delete", ObjID(e), e.isNPC)
            self.SelectedID = nil
        end)
    end)
    D.delBtn:Dock(TOP); D.delBtn:SetTall(sc(32))

    D.empty = vgui.Create("DPanel", host)
    D.empty:Dock(FILL); D.empty:SetMouseInputEnabled(false)
    D.empty.Paint = function(_, w, h)
        draw.SimpleText("◈", "RH_Stat", w / 2, h / 2 - sc(22), THEME.textDisabled, ALIGN_C, ALIGN_M)
        draw.SimpleText(L("ev.select_hint"), "RH_Body", w / 2, h / 2 + sc(6), THEME.textSecondary, ALIGN_C, ALIGN_M)
    end
end

function EntityViewer:UpdateDetail()
    local D = self.D; if not D then return end
    local e = self:Selected()
    local has = e ~= nil
    for _, k in ipairs({ "model", "fields", "freeze", "gravity", "editBtn", "delBtn" }) do
        if IsValid(D[k]) then D[k]:SetVisible(has) end
    end
    if IsValid(D.empty) then D.empty:SetVisible(not has) end
    if not has then return end

    local m = (e.model and util.IsValidModel(e.model)) and e.model or "models/error.mdl"
    if D.model:GetModel() ~= m then
        D.model:SetModel(m)
        timer.Simple(0, function() if IsValid(D.model) then UI.FrameModelPanel(D.model) end end)
    end

    self._syncing = true
    local frozen, nograv = ReadFlags(e)
    D.freeze:SetChecked(frozen)
    D.gravity:SetChecked(nograv)
    self._syncing = false
end

function EntityViewer:Select(id)
    self.SelectedID = id
    self:UpdateDetail()
end

-- ── cards + grid ──────────────────────────────────────────────────────────────

local function BuildCard(viewer, parent, ent)
    local card = vgui.Create("DButton", parent)
    card:SetText("")
    card:SetSize(sc(168), sc(198))
    local typeColor = EV_THEME:GetEntityTypeColor(ent.class)
    local hover = 0

    card.Paint = function(selfp, w, h)
        local selected = viewer.SelectedID == ObjID(ent)
        hover = Lerp(FrameTime() * 10, hover, (selfp:IsHovered() or selected) and 1 or 0)
        draw.RoundedBox(sc(10), 0, 0, w, h, THEME.surface)
        if hover > 0.01 then draw.RoundedBox(sc(10), 0, 0, w, h, ColorAlpha(THEME.primary, 16 * hover)) end
        if selected then
            surface.SetDrawColor(THEME.primary.r, THEME.primary.g, THEME.primary.b, 220)
            surface.DrawOutlinedRect(0, 0, w, h, sc(2))
        end
        draw.RoundedBoxEx(sc(6), 0, h - sc(4), w, sc(4), typeColor, false, false, true, true)
    end

    local previewBg = vgui.Create("DPanel", card)
    previewBg:SetPos(sc(8), sc(8)); previewBg:SetSize(sc(152), sc(108))
    previewBg.Paint = function(_, w, h) draw.RoundedBox(sc(8), 0, 0, w, h, THEME.backgroundDark) end

    if ent.model and util.IsValidModel(ent.model) then
        local mp = vgui.Create("DModelPanel", previewBg)
        mp:SetPos(0, 0); mp:SetSize(sc(152), sc(108))
        mp:SetModel(ent.model); mp:SetMouseInputEnabled(false)
        UI.FrameModelPanel(mp)
        mp.LayoutEntity = function(_, e) e:SetAngles(Angle(0, RealTime() * 30, 0)) end
    else
        previewBg.Paint = function(_, w, h)
            draw.RoundedBox(sc(8), 0, 0, w, h, THEME.backgroundDark)
            draw.SimpleText("?", "RH_Stat", w / 2, h / 2, THEME.textDisabled, ALIGN_C, ALIGN_M)
        end
    end

    card.PaintOver = function(_, w, h)
        local name = ent.class or L("common.unknown")
        surface.SetFont("RH_Small")
        while surface.GetTextSize(name) > w - sc(16) and #name > 4 do name = string.sub(name, 1, #name - 2) end
        draw.SimpleText(name, "RH_Small", w / 2, sc(126), THEME.textPrimary, ALIGN_C, ALIGN_T)

        local y = sc(146)
        local hp, maxHp = tonumber(ent.health), tonumber(ent.maxHealth)
        if hp and maxHp and maxHp > 0 then
            local bx, bw = sc(14), w - sc(28)
            draw.RoundedBox(sc(3), bx, y, bw, sc(5), THEME.backgroundDark)
            draw.RoundedBox(sc(3), bx, y, bw * math.Clamp(hp / maxHp, 0, 1), sc(5), EV_THEME:GetHealthColor(hp, maxHp))
            y = y + sc(12)
        end
        if ent.pos and IsValid(LocalPlayer()) then
            draw.SimpleText(L("ev.units", math.Round(LocalPlayer():GetPos():Distance(ent.pos))),
                "RH_Tiny", w / 2, y, THEME.textTertiary, ALIGN_C, ALIGN_T)
        end
    end

    card.DoClick = function()
        viewer:Select(ObjID(ent))
        surface.PlaySound("ui/buttonrollover.wav")
    end
    return card
end

function EntityViewer:RefreshList()
    if not IsValid(self.Grid) then return end
    self:FilterAndSort()
    self.Grid:Clear()

    if #self.FilteredData == 0 then
        local empty = vgui.Create("DPanel", self.Grid)
        empty:SetSize(self.Grid:GetWide() - sc(24), sc(160))
        empty.Paint = function(_, w, h)
            draw.SimpleText(L("ev.no_entities"), "RH_H2", w / 2, h / 2 - sc(12), THEME.textSecondary, ALIGN_C, ALIGN_M)
            draw.SimpleText(L("ev.no_entities_hint"), "RH_Small", w / 2, h / 2 + sc(12), THEME.textTertiary, ALIGN_C, ALIGN_M)
        end
        if IsValid(self.StatLabel) then self.StatLabel:SetText(L("ev.stats.showing", 0)) end
        return
    end

    local n = 0
    for _, ent in ipairs(self.FilteredData) do
        BuildCard(self, self.Grid, ent)
        n = n + 1
        if n >= 200 then break end
    end
    if IsValid(self.StatLabel) then self.StatLabel:SetText(L("ev.stats.showing", #self.FilteredData)) end
end

-- ── open ────────────────────────────────────────────────────────────────────

function EntityViewer:OpenFor(ctx)
    self.Context = ctx
    self.SelectedID = nil
    self:Open()
end

function EntityViewer:Open()
    UI.EnsureFonts()
    self._reopening = true
    if IsValid(self.Frame) then self.Frame:Close() end
    if IsValid(self.Backdrop) then self.Backdrop:Remove() end
    self._reopening = false

    self.Data = self:LoadData()

    -- dim backdrop so this reads as an overlay above the Save Timeline
    local back = vgui.Create("DPanel")
    back:SetSize(ScrW(), ScrH()); back:SetPos(0, 0); back:MakePopup()
    back.Paint = function(_, w, h) surface.SetDrawColor(0, 0, 0, 170); surface.DrawRect(0, 0, w, h) end
    back.OnMousePressed = function() if IsValid(EntityViewer.Frame) then EntityViewer.Frame:Close() end end
    self.Backdrop = back

    local w = math.min(ScrW() * 0.82, sc(1180))
    local h = math.min(ScrH() * 0.85, sc(720))
    local frame = vgui.Create("DFrame")
    frame:SetSize(w, h); frame:SetMinWidth(sc(880)); frame:SetMinHeight(sc(520))
    frame:Center(); frame:SetTitle(""); frame:ShowCloseButton(false); frame:MakePopup(); frame:SetSizable(true)
    self.Frame = frame
    frame.OnClose = function()
        if IsValid(EntityViewer.Backdrop) then EntityViewer.Backdrop:Remove() end
        if not EntityViewer._reopening then EntityViewer.Context = nil end
    end

    local headH = sc(60)
    frame.Paint = function(_, fw, fh)
        draw.RoundedBox(sc(14), 0, 0, fw, fh, THEME.background)
        surface.SetDrawColor(THEME.divider); surface.DrawLine(0, headH, fw, headH)
        draw.SimpleText(L("ev.objects_title"), "RH_Title", sc(18), sc(11), THEME.primaryLight, ALIGN_L, ALIGN_T)
        draw.SimpleText(self.Context and self.Context.label or L("ev.title"), "RH_Sub", sc(20), sc(39), THEME.textTertiary, ALIGN_L, ALIGN_T)
    end

    local spacer = vgui.Create("DPanel", frame)
    spacer:Dock(TOP); spacer:SetTall(headH); spacer:SetMouseInputEnabled(false); spacer.Paint = function() end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL); body.Paint = function() end

    -- ── left rail: search, sort, categories, stats ──
    local side = vgui.Create("DPanel", body)
    side:Dock(LEFT); side:SetWide(sc(200)); side:DockPadding(sc(12), sc(12), sc(12), sc(10))
    side.Paint = function(_, sw, sh)
        surface.SetDrawColor(THEME.backgroundDark); surface.DrawRect(0, 0, sw, sh)
        surface.SetDrawColor(THEME.divider); surface.DrawLine(sw - 1, 0, sw - 1, sh)
    end

    local search = vgui.Create("DTextEntry", side)
    search:Dock(TOP); search:SetTall(sc(32)); search:SetFont("RH_Body"); search:SetUpdateOnType(true)
    search:SetTextInset(sc(28), 0)
    search.Paint = function(selfp, sw, sh)
        draw.RoundedBox(sc(8), 0, 0, sw, sh, THEME.surface)
        UI.DrawSearchIcon(sc(13), sh / 2, sc(5), THEME.textTertiary)
        selfp:DrawTextEntryText(THEME.textPrimary, THEME.primary, THEME.textPrimary)
        if selfp:GetValue() == "" then
            draw.SimpleText(L("ev.search_placeholder"), "RH_Body", sc(28), sh / 2, THEME.textTertiary, ALIGN_L, ALIGN_M)
        end
    end
    search.OnChange = function(selfp) EntityViewer.SearchText = selfp:GetValue(); EntityViewer:RefreshList() end

    local sortBtn = vgui.Create("DButton", side)
    sortBtn:Dock(TOP); sortBtn:DockMargin(0, sc(8), 0, sc(8)); sortBtn:SetTall(sc(26)); sortBtn:SetText("")
    sortBtn.Paint = function(_, bw, bh)
        draw.RoundedBox(sc(6), 0, 0, bw, bh, THEME.surface)
        draw.SimpleText(L("ev.sort", L("ev.sort." .. string.lower(EntityViewer.SortMode))), "RH_Small", sc(10), bh / 2, THEME.textSecondary, ALIGN_L, ALIGN_M)
        draw.SimpleText("▾", "RH_Small", bw - sc(10), bh / 2, THEME.textTertiary, ALIGN_R, ALIGN_M)
    end
    sortBtn.DoClick = function()
        local m = DermaMenu()
        for _, s in ipairs(SORTS) do
            m:AddOption(L("ev.sort." .. string.lower(s)), function() EntityViewer.SortMode = s; EntityViewer:RefreshList() end)
        end
        m:Open()
    end

    for _, cat in ipairs(CATEGORIES) do
        local b = vgui.Create("DButton", side)
        b:Dock(TOP); b:DockMargin(0, 0, 0, sc(4)); b:SetTall(sc(30)); b:SetText("")
        b.Paint = function(selfp, bw, bh)
            local on = EntityViewer.Category == cat
            if on then
                draw.RoundedBox(sc(6), 0, 0, bw, bh, ColorAlpha(THEME.primary, 45))
                draw.RoundedBox(sc(3), 0, sc(6), sc(3), bh - sc(12), THEME.primary)
            elseif selfp:IsHovered() then
                draw.RoundedBox(sc(6), 0, 0, bw, bh, ColorAlpha(THEME.surface, 160))
            end
            draw.SimpleText(L(CAT_KEY[cat]), "RH_Small", sc(14), bh / 2, on and THEME.primaryLight or THEME.textSecondary, ALIGN_L, ALIGN_M)
        end
        b.DoClick = function() EntityViewer.Category = cat; EntityViewer:RefreshList() end
    end

    local stat = vgui.Create("DLabel", side)
    stat:Dock(BOTTOM); stat:SetTall(sc(20)); stat:SetFont("RH_Small"); stat:SetTextColor(THEME.textTertiary)
    stat:SetText(L("ev.stats.showing", 0))
    self.StatLabel = stat
    local mapLbl = vgui.Create("DLabel", side)
    mapLbl:Dock(BOTTOM); mapLbl:SetTall(sc(18)); mapLbl:SetFont("RH_Tiny"); mapLbl:SetTextColor(THEME.textDisabled)
    mapLbl:SetText(L("ev.stats.map", game.GetMap()))

    -- ── right: detail pane ──
    local detail = vgui.Create("DPanel", body)
    detail:Dock(RIGHT); detail:SetWide(sc(300)); detail:DockPadding(sc(12), sc(12), sc(12), sc(12))
    detail.Paint = function(_, dw, dh)
        surface.SetDrawColor(THEME.divider); surface.DrawLine(0, 0, 0, dh)
    end
    self:BuildDetail(detail)

    -- ── middle: card grid ──
    local scroll = vgui.Create("DScrollPanel", body)
    scroll:Dock(FILL); scroll:DockMargin(sc(10), sc(10), sc(10), sc(10))
    UI.StyleScrollbar(scroll)
    local grid = vgui.Create("DIconLayout", scroll)
    grid:Dock(FILL); grid:SetSpaceX(sc(10)); grid:SetSpaceY(sc(10))
    self.Grid = grid

    -- ── top-right controls ──
    local topButtons = {}
    local function topBtn(text, color, wide, fn)
        local b = UI.Button(frame, text, color, fn); b._wide = wide
        topButtons[#topButtons + 1] = b; return b
    end
    topBtn("✕", THEME.error, sc(32), function() frame:Close() end)
    topBtn("↻", THEME.info, sc(40), function()
        if self:IsHistory() then
            net.Start("RareloadHistory_Objects"); net.WriteString(self.Context.saveId); net.SendToServer()
        end
    end)
    topBtn(L("ev.delete_all"), THEME.error, sc(110), function()
        local items = self.FilteredData or {}
        if #items == 0 then ShowNotification(L("ev.no_match_filters"), NOTIFY_ERROR); return end
        UI.ConfirmDialog(L("ev.delete_all"), L("ev.delete_confirm", #items), function()
            for _, ent in ipairs(items) do self:SendHistoryObjAction("delete", ObjID(ent), ent.isNPC) end
            self.SelectedID = nil
        end)
    end)

    local baseLayout = frame.PerformLayout
    frame.PerformLayout = function(pnl, fw, fh)
        if baseLayout then baseLayout(pnl, fw, fh) end
        local x = fw - sc(12)
        for _, b in ipairs(topButtons) do
            x = x - b._wide
            b:SetSize(b._wide, sc(32)); b:SetPos(x, sc(13))
            x = x - sc(6)
        end
    end
    frame:InvalidateLayout(true)

    self:RefreshList()
    self:UpdateDetail()
end

-- ── entry point: opened only from the Save Timeline ("Objects") ────────────────

net.Receive("RareloadHistory_Objects", function()
    local id  = net.ReadString()
    local len = net.ReadUInt(32)
    local raw = len > 0 and net.ReadData(len) or ""
    local json = util.Decompress(raw)
    if not json then return end
    local ok, tbl = pcall(util.JSONToTable, json)
    if not ok or not istable(tbl) then return end

    local parent = RARELOAD.HistoryPanel and RARELOAD.HistoryPanel.Frame
    local label  = RARELOAD.HistoryPanel and RARELOAD.HistoryPanel._objectsLabel or nil

    if EntityViewer:IsHistory() and EntityViewer.Context.saveId == tbl.id and IsValid(EntityViewer.Frame) then
        EntityViewer.Context.objects = tbl.objects or {}
        EntityViewer:ReloadDataAndRefresh()
        return
    end

    EntityViewer:OpenFor({
        saveId = tbl.id, ownerSID = tbl.ownerSID, objects = tbl.objects or {},
        parent = parent, label = label,
    })
end)

function OpenEntityViewer()
    -- kept for back-compat: the viewer now lives inside the Save Timeline
    if RARELOAD.HistoryPanel then RARELOAD.HistoryPanel:Open() end
end
