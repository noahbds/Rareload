-- ─────────────────────────────────────────────────────────────────────────────
-- Save Timeline panel (4.0 · Phase 3)
--
-- Browses the player's full, persistent save history (synced as compact metadata
-- from the server) and acts on any entry: teleport, restore (whole or by
-- component), pin, note, delete. Reuses the shared THEME / fonts / ShowNotification
-- from the entity viewer. Heavy data and restore live server-side; this panel only
-- shows summaries and sends actions by entry id.
-- ─────────────────────────────────────────────────────────────────────────────

local L = RARELOAD.L
local draw, surface, vgui = draw, surface, vgui
local IsValid, FrameTime, Lerp = IsValid, FrameTime, Lerp

RARELOAD = RARELOAD or {}
RARELOAD.HistoryClient = RARELOAD.HistoryClient or { entries = {}, total = 0 }

local HP = { Frame = nil, SelectedId = nil, Search = "" }
HP.Comps = { position = true, health = true, inventory = true, ammo = true, appearance = true, states = true, world = true }

-- ── networking ───────────────────────────────────────────────────────────────

function HP:RequestData()
    net.Start("RareloadHistory_Request")
    net.SendToServer()
end

local function SendAction(action, id, writeExtra)
    net.Start("RareloadHistory_Action")
    net.WriteString(action)
    net.WriteString(id or "")
    if writeExtra then writeExtra() end
    net.SendToServer()
end

net.Receive("RareloadHistory_Data", function()
    local len = net.ReadUInt(32)
    local raw = len > 0 and net.ReadData(len) or ""
    local json = util.Decompress(raw)
    if not json then return end
    local ok, tbl = pcall(util.JSONToTable, json)
    if not ok or not istable(tbl) then return end

    RARELOAD.HistoryClient.entries = istable(tbl.entries) and tbl.entries or {}
    RARELOAD.HistoryClient.total = tonumber(tbl.total) or #RARELOAD.HistoryClient.entries
    RARELOAD.HistoryClient.undo = tbl.undo == true

    if IsValid(HP.Frame) then HP:Rebuild() end
end)

-- ── helpers ──────────────────────────────────────────────────────────────────

local function TimeAgo(t)
    local d = os.time() - (tonumber(t) or 0)
    if d < 45 then return L("sth.just_now") end
    if d < 3600 then return L("sth.ago_m", math.floor(d / 60)) end
    if d < 86400 then return L("sth.ago_h", math.floor(d / 3600)) end
    return L("sth.ago_d", math.floor(d / 86400))
end

local function Entries()
    return RARELOAD.HistoryClient.entries or {}
end

local function FindEntry(id)
    for _, e in ipairs(Entries()) do
        if e.id == id then return e end
    end
    return nil
end

local function FilteredEntries()
    local s = string.lower(HP.Search or "")
    if s == "" then return Entries() end
    local out = {}
    for _, e in ipairs(Entries()) do
        local note = string.lower(e.note or "")
        local aw = string.lower(e.aw or "")
        if string.find(note, s, 1, true) or string.find(aw, s, 1, true) then
            out[#out + 1] = e
        end
    end
    return out
end

-- ── entry row (left list) ──────────────────────────────────────────────────────

local function BuildRow(parent, e)
    local row = vgui.Create("DButton", parent)
    row:SetText("")
    row:Dock(TOP)
    row:DockMargin(8, 0, 8, 6)
    row:SetTall(58)
    row.HoverAnim = 0

    row.Paint = function(self, w, h)
        local selected = HP.SelectedId == e.id
        self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, (self:IsHovered() or selected) and 1 or 0)

        draw.RoundedBox(8, 0, 0, w, h, THEME.surface)
        if e.act then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(THEME.success, 22))
        end
        if self.HoverAnim > 0.01 then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(THEME.primary, 16 * self.HoverAnim))
        end
        if selected then
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(THEME.primary, 30))
        end
        -- left accent: green marks the active respawn save, blue marks the selected row
        if e.act then
            draw.RoundedBox(3, 0, 8, 3, h - 16, THEME.success)
        elseif selected then
            draw.RoundedBox(3, 0, 8, 3, h - 16, THEME.primary)
        end

        draw.SimpleText(TimeAgo(e.t), "RareloadBody", 14, 12, THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local pos = e.pos or {}
        local posStr = string.format("%.0f, %.0f, %.0f", tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0)
        draw.SimpleText(posStr, "RareloadCaption", 14, 34, THEME.textTertiary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        -- right-aligned badges
        local bx = w - 12
        if e.pin then
            draw.SimpleText("★", "RareloadBody", bx, 14, THEME.warning, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            bx = bx - 20
        end
        if e.hp then
            draw.SimpleText("♥ " .. math.floor(e.hp), "RareloadCaption", bx, 16, THEME:GetHealthColor(e.hp, 100),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
        if e.note and e.note ~= "" then
            draw.SimpleText("✎", "RareloadCaption", w - 12, 36, THEME.textSecondary, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
    end

    row.DoClick = function()
        HP.SelectedId = e.id
        surface.PlaySound("ui/buttonrollover.wav")
        HP:RebuildList()
        HP:RebuildDetail()
    end
    return row
end

-- ── generic themed button ──────────────────────────────────────────────────────

local function ActionButton(parent, text, color, onClick)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn.HoverAnim = 0
    btn.Paint = function(self, w, h)
        self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, self:IsHovered() and 1 or 0)
        local bg = THEME:LerpColor(self.HoverAnim * 0.5, THEME.surface, color)
        draw.RoundedBox(8, 0, 0, w, h, bg)
        surface.SetDrawColor(color.r, color.g, color.b, 60 + 120 * self.HoverAnim)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText(text, "RareloadBody", w / 2, h / 2, THEME.textPrimary, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btn.DoClick = onClick
    return btn
end

-- ── detail pane (right) ────────────────────────────────────────────────────────

local function DetailField(parent, y, label, value, valueColor)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:DockMargin(0, 0, 0, 6)
    p:SetTall(20)
    p.Paint = function(self, w, h)
        draw.SimpleText(label, "RareloadCaption", 0, h / 2, THEME.textTertiary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(value, "RareloadCaption", w, h / 2, valueColor or THEME.textPrimary, TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_CENTER)
    end
    return p
end

function HP:RebuildDetail()
    local host = self.Detail
    if not IsValid(host) then return end
    -- Clearing a focused note field fires its OnLoseFocus; suppress the resulting save.
    self._rebuilding = true
    host:Clear()
    self._rebuilding = false

    local e = self.SelectedId and FindEntry(self.SelectedId) or nil
    if not e then
        if RARELOAD.HistoryPreview then RARELOAD.HistoryPreview.Clear() end
        local empty = vgui.Create("DPanel", host)
        empty:Dock(FILL)
        empty.Paint = function(_, w, h)
            draw.SimpleText(L("sth.select_hint"), "RareloadSubheading", w / 2, h / 2, THEME.textSecondary,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    -- header: compact model preview + primary facts
    local header = vgui.Create("DPanel", host)
    header:Dock(TOP)
    header:SetTall(98)
    header:DockMargin(0, 0, 0, 10)
    header.Paint = function(_, w, h) draw.RoundedBox(10, 0, 0, w, h, THEME.backgroundDark) end

    if e.mdl and util.IsValidModel(e.mdl) then
        local mp = vgui.Create("DModelPanel", header)
        mp:Dock(LEFT)
        mp:DockMargin(7, 7, 7, 7)
        mp:SetWide(84)
        mp:SetModel(e.mdl)
        mp:SetMouseInputEnabled(false)
        mp.LayoutEntity = function(_, en) en:SetAngles(Angle(0, RealTime() * 24, 0)) end
        local ent = mp:GetEntity()
        if IsValid(ent) then
            local mn, mx = ent:GetRenderBounds()
            local center = (mn + mx) * 0.5
            local size   = math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
            local fov    = 45
            local dist   = (size * 1.2) / math.tan(math.rad(fov / 2))
            mp:SetLookAt(center)
            mp:SetCamPos(center + Vector(dist * 0.6, dist * 0.5, dist * 0.4))
            mp:SetFOV(fov)
        end
    else
        local ph = vgui.Create("DPanel", header)
        ph:Dock(LEFT)
        ph:DockMargin(7, 7, 7, 7)
        ph:SetWide(84)
        ph.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.surface)
            draw.SimpleText("?", "RareloadHeading", w / 2, h / 2, THEME.textDisabled, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
    end

    local facts = vgui.Create("DPanel", header)
    facts:Dock(FILL)
    facts:DockMargin(6, 12, 12, 10)
    facts.Paint = function(_, w, h)
        draw.SimpleText(TimeAgo(e.t), "RareloadHeading", 0, 2, THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(os.date("%Y-%m-%d  %H:%M:%S", tonumber(e.t) or 0), "RareloadCaption", 0, 32,
            THEME.textSecondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if e.pin then
            draw.SimpleText("★ " .. L("sth.pinned"), "RareloadCaption", 0, 54, THEME.warning, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_TOP)
        end
    end

    -- in-world preview: a "Preview in World" toggle drops phantoms of the whole
    -- saved snapshot (player + entities) into the map, each glowing green/red.
    local previewClear = true
    if RARELOAD.HistoryPreview then
        if RARELOAD.HistoryPreview.active and RARELOAD.HistoryPreview.showId ~= e.id then
            RARELOAD.HistoryPreview.Clear() -- drop a stale preview from a different entry
        end
        if RARELOAD.HistoryPreview.TestClear and istable(e.pos) then
            previewClear = RARELOAD.HistoryPreview.TestClear(
                Vector(tonumber(e.pos.x) or 0, tonumber(e.pos.y) or 0, tonumber(e.pos.z) or 0))
        end
    end
    do
        local status = vgui.Create("DPanel", host)
        status:Dock(TOP)
        status:DockMargin(4, 0, 4, 8)
        status:SetTall(22)
        status.Paint = function(_, w, h)
            draw.SimpleText(previewClear and L("sth.inworld_clear") or L("sth.inworld_blocked"),
                "RareloadCaption", 0, h / 2, previewClear and THEME.success or THEME.error,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    local showing = RARELOAD.HistoryPreview and RARELOAD.HistoryPreview.IsShowing(e.id)
    local prevBtn = ActionButton(host, showing and L("sth.preview_hide") or L("sth.preview_show"), THEME.info,
        function()
            if RARELOAD.HistoryPreview then RARELOAD.HistoryPreview.Toggle(e) end
            timer.Simple(0, function() if IsValid(HP.Frame) then HP:RebuildDetail() end end)
        end)
    prevBtn:Dock(TOP)
    prevBtn:DockMargin(4, 0, 4, 10)
    prevBtn:SetTall(30)

    -- active respawn: banner when this entry is the active save, button to make it so
    if e.act then
        local banner = vgui.Create("DPanel", host)
        banner:Dock(TOP)
        banner:DockMargin(4, 0, 4, 10)
        banner:SetTall(34)
        banner.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, ColorAlpha(THEME.success, 40))
            surface.SetDrawColor(THEME.success.r, THEME.success.g, THEME.success.b, 150)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText(L("sth.is_active"), "RareloadBody", w / 2, h / 2, THEME.success, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
    else
        local setActive = ActionButton(host, L("sth.set_active"), THEME.success, function()
            SendAction("activate", e.id)
            ShowNotification(L("sth.set_active_done"), NOTIFY_GENERIC)
        end)
        setActive:Dock(TOP)
        setActive:DockMargin(4, 0, 4, 10)
        setActive:SetTall(34)
    end

    -- fields block
    local fieldBox = vgui.Create("DPanel", host)
    fieldBox:Dock(TOP)
    fieldBox:DockMargin(4, 0, 4, 10)
    fieldBox.Paint = function() end
    fieldBox:SetTall(20 * 7 + 6 * 7)

    local pos, ang = e.pos or {}, e.ang or {}
    DetailField(fieldBox, 0, L("sth.field.position"),
        string.format("%.0f, %.0f, %.0f", tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0))
    DetailField(fieldBox, 0, L("sth.field.angle"),
        string.format("%.0f, %.0f, %.0f", tonumber(ang.p) or 0, tonumber(ang.y) or 0, tonumber(ang.r) or 0))
    DetailField(fieldBox, 0, L("sth.field.health"),
        (e.hp and math.floor(e.hp) or 0) .. "  /  " .. (e.ar and math.floor(e.ar) or 0) .. " " .. L("sth.field.armor"),
        e.hp and THEME:GetHealthColor(e.hp, 100) or THEME.textPrimary)
    DetailField(fieldBox, 0, L("sth.field.weapons"), tostring(e.wc or 0))
    DetailField(fieldBox, 0, L("sth.field.active"), e.aw and e.aw ~= "None" and e.aw or L("sth.none"))
    DetailField(fieldBox, 0, L("sth.field.entities") .. " / " .. L("sth.field.npcs"),
        (e.ec or 0) .. " / " .. (e.nc or 0))

    local st = e.st or {}
    local stParts = {}
    if st.g then stParts[#stParts + 1] = "god" end
    if st.n then stParts[#stParts + 1] = "notarget" end
    if st.f then stParts[#stParts + 1] = "frozen" end
    if st.c then stParts[#stParts + 1] = "noclip" end
    DetailField(fieldBox, 0, L("sth.field.states"), #stParts > 0 and table.concat(stParts, ", ") or L("sth.none"))

    -- note editor
    local note = vgui.Create("DTextEntry", host)
    note:Dock(TOP)
    note:DockMargin(4, 0, 4, 10)
    note:SetTall(28)
    note:SetFont("RareloadBody")
    note:SetText(e.note or "")
    note:SetPlaceholderText(L("sth.note_placeholder"))
    note:SetUpdateOnType(false)
    note.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.surface)
        self:DrawTextEntryText(THEME.textPrimary, THEME.primary, THEME.textPrimary)
        if self:GetValue() == "" and not self:HasFocus() then
            draw.SimpleText(L("sth.note_placeholder"), "RareloadBody", 8, h / 2, THEME.textTertiary, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
        end
    end
    note._committed = e.note or ""
    local function commitNote(self)
        if HP._rebuilding then return end
        local v = self:GetValue()
        if v == self._committed then return end
        self._committed = v
        SendAction("note", e.id, function() net.WriteString(v) end)
        ShowNotification(L("sth.note_saved"), NOTIFY_GENERIC)
    end
    note.OnEnter = commitNote
    note.OnLoseFocus = commitNote

    -- primary actions
    local actions = vgui.Create("DPanel", host)
    actions:Dock(TOP)
    actions:DockMargin(4, 0, 4, 8)
    actions:SetTall(36)
    actions.Paint = function() end

    local tp = ActionButton(actions, L("sth.teleport"), THEME.info, function()
        if e.pos then
            RunConsoleCommand("rareload_teleport_to", e.pos.x, e.pos.y, e.pos.z)
            ShowNotification(L("sth.teleporting"), NOTIFY_GENERIC)
        end
    end)
    tp:Dock(LEFT); tp:SetWide(120); tp:DockMargin(0, 0, 6, 0)

    local rs = ActionButton(actions, L("sth.restore_all"), THEME.success, function()
        SendAction("restore", e.id, function() net.WriteTable({ all = true }) end)
        ShowNotification(L("sth.restoring"), NOTIFY_GENERIC)
    end)
    rs:Dock(LEFT); rs:SetWide(150); rs:DockMargin(0, 0, 6, 0)

    local pin = ActionButton(actions, e.pin and L("sth.unpin") or L("sth.pin"), THEME.warning, function()
        SendAction("pin", e.id, function() net.WriteBool(not e.pin) end)
    end)
    pin:Dock(LEFT); pin:SetWide(90); pin:DockMargin(0, 0, 6, 0)

    local del = ActionButton(actions, L("sth.delete"), THEME.error, function()
        Derma_Query(L("sth.delete_confirm"), L("sth.delete"), L("common.proceed"), function()
            SendAction("delete", e.id)
            HP.SelectedId = nil
        end, L("common.cancel"))
    end)
    del:Dock(FILL)

    -- partial restore
    local partHeader = vgui.Create("DPanel", host)
    partHeader:Dock(TOP)
    partHeader:DockMargin(4, 4, 4, 4)
    partHeader:SetTall(20)
    partHeader.Paint = function(_, w, h)
        draw.SimpleText(L("sth.partial_title"), "RareloadLabel", 0, h / 2, THEME.textSecondary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
    end

    local comps = {
        { "position", "sth.comp.position" }, { "health", "sth.comp.health" },
        { "inventory", "sth.comp.inventory" }, { "ammo", "sth.comp.ammo" },
        { "appearance", "sth.comp.appearance" }, { "states", "sth.comp.states" },
        { "world", "sth.comp.world" },
    }
    local grid = vgui.Create("DIconLayout", host)
    grid:Dock(TOP)
    grid:DockMargin(4, 0, 4, 8)
    grid:SetTall(60)
    grid:SetSpaceX(6)
    grid:SetSpaceY(6)
    for _, c in ipairs(comps) do
        local cb = grid:Add("DCheckBoxLabel")
        cb:SetText(L(c[2]))
        cb:SetTextColor(THEME.textSecondary)
        cb:SetFont("RareloadCaption")
        cb:SetValue(HP.Comps[c[1]] and true or false)
        cb:SizeToContents()
        cb.OnChange = function(_, v) HP.Comps[c[1]] = v end
    end

    local applyBtn = ActionButton(host, L("sth.apply_selected"), THEME.primary, function()
        local chosen = {}
        for k, v in pairs(HP.Comps) do if v then chosen[k] = true end end
        if not next(chosen) then
            ShowNotification(L("sth.nothing_selected"), NOTIFY_ERROR)
            return
        end
        SendAction("restore", e.id, function() net.WriteTable(chosen) end)
        ShowNotification(L("sth.restoring"), NOTIFY_GENERIC)
    end)
    applyBtn:Dock(TOP)
    applyBtn:DockMargin(4, 0, 4, 4)
    applyBtn:SetTall(32)
end

-- ── list rebuild ────────────────────────────────────────────────────────────────

function HP:RebuildList()
    local scroll = self.List
    if not IsValid(scroll) then return end
    scroll:Clear()

    local list = FilteredEntries()
    if #list == 0 then
        local empty = vgui.Create("DPanel", scroll)
        empty:Dock(TOP)
        empty:DockMargin(8, 40, 8, 0)
        empty:SetTall(120)
        empty.Paint = function(_, w, h)
            draw.SimpleText(L("sth.empty"), "RareloadSubheading", w / 2, h / 2 - 12, THEME.textSecondary,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(L("sth.empty_hint"), "RareloadCaption", w / 2, h / 2 + 14, THEME.textTertiary,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    for _, e in ipairs(list) do
        BuildRow(scroll, e)
    end
end

function HP:Rebuild()
    self:RebuildList()
    self:RebuildDetail()
    if IsValid(self.CountLabel) then
        self.CountLabel:SetText(L("sth.count", RARELOAD.HistoryClient.total or #Entries()))
    end
    if IsValid(self.UndoBtn) then
        self.UndoBtn:SetVisible(RARELOAD.HistoryClient.undo == true)
    end
end

-- ── open ────────────────────────────────────────────────────────────────────────

function HP:Open()
    if IsValid(self.Frame) then self.Frame:Close() end

    local frame = vgui.Create("DFrame")
    frame:SetSize(960, 640)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:MakePopup()
    frame:SetSizable(false)
    self.Frame = frame

    frame.OnRemove = function()
        if RARELOAD.HistoryPreview then RARELOAD.HistoryPreview.Clear() end
    end

    frame.Paint = function(_, w, h)
        draw.RoundedBox(12, 0, 0, w, h, THEME.background)
        draw.RoundedBoxEx(12, 0, 0, 380, h, THEME.backgroundDark, true, false, true, false)
        surface.SetDrawColor(THEME.divider)
        surface.DrawLine(380, 56, 380, h)
        surface.DrawLine(0, 56, w, 56)
        draw.SimpleText(L("sth.title"), "RareloadHeading", 16, 16, THEME.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(L("sth.subtitle"), "RareloadCaption", 16, 40, THEME.textTertiary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local closeBtn = ActionButton(frame, "✕", THEME.error, function() frame:Close() end)
    closeBtn:SetPos(960 - 44, 12)
    closeBtn:SetSize(32, 32)

    -- top-right controls
    local refresh = ActionButton(frame, L("sth.refresh"), THEME.info, function() self:RequestData() end)
    refresh:SetPos(960 - 44 - 110, 12)
    refresh:SetSize(104, 32)

    local clearAll = ActionButton(frame, L("sth.clear_all"), THEME.error, function()
        Derma_Query(L("sth.clear_confirm"), L("sth.clear_all"), L("common.proceed"), function()
            SendAction("clear", "")
            self.SelectedId = nil
        end, L("common.cancel"))
    end)
    clearAll:SetPos(960 - 44 - 110 - 130, 12)
    clearAll:SetSize(124, 32)

    -- Undo the last restore (shown only when an undo snapshot is available)
    local undoBtn = ActionButton(frame, L("sth.undo"), THEME.warning, function()
        SendAction("undo", "")
    end)
    undoBtn:SetPos(960 - 44 - 110 - 130 - 130, 12)
    undoBtn:SetSize(124, 32)
    undoBtn:SetVisible(RARELOAD.HistoryClient.undo == true)
    self.UndoBtn = undoBtn

    -- search + count (sidebar)
    local search = vgui.Create("DTextEntry", frame)
    search:SetPos(12, 66)
    search:SetSize(356, 30)
    search:SetFont("RareloadBody")
    search:SetPlaceholderText(L("sth.search_placeholder"))
    search:SetUpdateOnType(true)
    search.Paint = function(selfp, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.surface)
        selfp:DrawTextEntryText(THEME.textPrimary, THEME.primary, THEME.textPrimary)
        if selfp:GetValue() == "" then
            draw.SimpleText(L("sth.search_placeholder"), "RareloadBody", 8, h / 2, THEME.textTertiary, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_CENTER)
        end
    end
    search.OnChange = function(selfp)
        HP.Search = selfp:GetValue()
        HP:RebuildList()
    end

    local countLabel = vgui.Create("DLabel", frame)
    countLabel:SetPos(16, 604)
    countLabel:SetSize(356, 24)
    countLabel:SetFont("RareloadCaption")
    countLabel:SetTextColor(THEME.textTertiary)
    countLabel:SetText(L("sth.count", RARELOAD.HistoryClient.total or #Entries()))
    self.CountLabel = countLabel

    local list = vgui.Create("DScrollPanel", frame)
    list:SetPos(0, 104)
    list:SetSize(380, 496)
    local vb = list:GetVBar()
    vb:SetWide(6)
    vb.Paint = function() end
    vb.btnUp.Paint = function() end
    vb.btnDown.Paint = function() end
    vb.btnGrip.Paint = function(_, w, h) draw.RoundedBox(3, 0, 0, w, h, THEME.primary) end
    self.List = list

    local detail = vgui.Create("DScrollPanel", frame)
    detail:SetPos(392, 66)
    detail:SetSize(556, 562)
    local dvb = detail:GetVBar()
    dvb:SetWide(6)
    dvb.Paint = function() end
    dvb.btnUp.Paint = function() end
    dvb.btnDown.Paint = function() end
    dvb.btnGrip.Paint = function(_, w, h) draw.RoundedBox(3, 0, 0, w, h, THEME.primary) end
    self.Detail = detail

    self:RebuildList()
    self:RebuildDetail()
    self:RequestData()
end

-- ── entry points ─────────────────────────────────────────────────────────────

concommand.Add("rareload_history", function() HP:Open() end)
concommand.Add("rareload_save_timeline", function() HP:Open() end)

function OpenPositionHistory()
    HP:Open()
end

RARELOAD.HistoryPanel = HP
