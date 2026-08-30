-- ─────────────────────────────────────────────────────────────────────────────
-- Save Timeline panel  (rewritten from scratch, 4.1)
--
-- Browses the player's full, persistent save history (synced as compact metadata
-- from the server) and acts on any entry: teleport, restore (whole or by
-- component), pin, note, delete, set-active, preview-in-world. Heavy data and the
-- actual restore live server-side; this panel shows summaries and sends actions
-- by entry id.
--
-- Design goals of this rewrite:
--   • Resolution-adaptive — every size is scaled by ScrH()/1080 and clamped, so
--     the panel is comfortable from 1080p up to 1440p/4K instead of a fixed box.
--   • Dedicated, legible font set (RH_*), rebuilt for the current scale.
--   • Clear, dense information: model, exact time, a health bar, and a row of stat
--     cards (health, armor, weapons, entities, NPCs, VEHICLES) plus detail rows
--     for position, active weapon, saved-in-vehicle, player states and model.
--   • Detail pane built ONCE and updated in place — selecting never rebuilds the
--     model panel or flickers; the stat/info panels self-draw from the selection.
--   • No timeline strip, no diff panel (removed as noise).
-- ─────────────────────────────────────────────────────────────────────────────

local L = RARELOAD.L
local draw, surface, vgui = draw, surface, vgui
local IsValid, FrameTime, Lerp = IsValid, FrameTime, Lerp
local ALIGN_L, ALIGN_R, ALIGN_C = TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER
local ALIGN_T, ALIGN_M = TEXT_ALIGN_TOP, TEXT_ALIGN_CENTER

RARELOAD = RARELOAD or {}
RARELOAD.HistoryClient = RARELOAD.HistoryClient or { entries = {}, total = 0 }

-- Fixed ordered run of restore-component booleans (matches the server's
-- RESTORE_COMPS). We never net.WriteTable arbitrary data.
local RESTORE_COMPS = { "all", "position", "health", "inventory", "ammo", "appearance", "states", "world" }

local SORTS   = { "newest", "oldest", "health", "pinned" }
local FILTERS = { "all", "pinned", "noted", "world" }

-- Shared client UI primitives (scaling, fonts, Button, scrollbar, model framing,
-- confirm dialog, Derma icons) — one copy for every Rareload panel.
local UI = RARELOAD.UI
local sc = UI.sc
local Button, StyleScrollbar, FrameModelPanel, ConfirmDialog =
    UI.Button, UI.StyleScrollbar, UI.FrameModelPanel, UI.ConfirmDialog
local IC_ENT, IC_NPC, IC_VEH = UI.icons.ent, UI.icons.npc, UI.icons.veh
local IC_PIN, IC_NOTE, IC_HP = UI.icons.pin, UI.icons.note, UI.icons.health

local HP = {
    Frame = nil, SelectedId = nil, Search = "",
    Sort = "newest", Filter = "all",
    Loading = false, LoadError = false,
}
HP.Comps = { position = true, health = true, inventory = true, ammo = true, appearance = true, states = true, world = true }

-- ── networking ──────────────────────────────────────────────────────────────

function HP:RequestData()
    self.Loading = true
    self.LoadError = false
    net.Start("RareloadHistory_Request")
    net.SendToServer()
end

local function WriteComps(comps)
    for _, k in ipairs(RESTORE_COMPS) do
        net.WriteBool(comps[k] == true)
    end
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
    HP.Loading = false
    local json = util.Decompress(raw)
    if not json then HP.LoadError = true; if IsValid(HP.Frame) then HP:Refresh() end; return end
    local ok, tbl = pcall(util.JSONToTable, json)
    if not ok or not istable(tbl) then HP.LoadError = true; if IsValid(HP.Frame) then HP:Refresh() end; return end

    HP.LoadError = false
    RARELOAD.HistoryClient.entries = istable(tbl.entries) and tbl.entries or {}
    RARELOAD.HistoryClient.total = tonumber(tbl.total) or #RARELOAD.HistoryClient.entries
    RARELOAD.HistoryClient.undo = tbl.undo == true

    if IsValid(HP.Frame) then HP:Refresh() end
end)

-- ── data helpers ──────────────────────────────────────────────────────────────

local function Entries() return RARELOAD.HistoryClient.entries or {} end

local function FindEntry(id)
    for _, e in ipairs(Entries()) do
        if e.id == id then return e end
    end
    return nil
end

-- TimeAgo appears in every row's paint; cache the formatted string and recompute
-- only about once a second instead of every frame.
local _timeAgoCache, _timeAgoStamp = {}, 0
local function TimeAgo(t)
    local now = os.time()
    if now ~= _timeAgoStamp then _timeAgoCache, _timeAgoStamp = {}, now end
    local cached = _timeAgoCache[t]
    if cached then return cached end
    local d = now - (tonumber(t) or 0)
    local s
    if d < 45 then s = L("sth.just_now")
    elseif d < 3600 then s = L("sth.ago_m", math.floor(d / 60))
    elseif d < 86400 then s = L("sth.ago_h", math.floor(d / 3600))
    else s = L("sth.ago_d", math.floor(d / 86400)) end
    _timeAgoCache[t] = s
    return s
end

local function PosStr(p)
    p = p or {}
    return string.format("%.0f, %.0f, %.0f", tonumber(p.x) or 0, tonumber(p.y) or 0, tonumber(p.z) or 0)
end

local function VehicleClassName(veh)
    if not veh or veh == "1" then return nil end
    -- prettify "gtav_wolfsbane" → "Gtav Wolfsbane"
    local nice = string.gsub(tostring(veh), "[_%.]", " ")
    return nice
end

local function StatesList(st)
    st = st or {}
    local parts = {}
    if st.g then parts[#parts + 1] = "God" end
    if st.n then parts[#parts + 1] = "NoTarget" end
    if st.f then parts[#parts + 1] = "Frozen" end
    if st.c then parts[#parts + 1] = "NoClip" end
    return parts
end

local function EntryMatches(e, s)
    if string.find(string.lower(e.note or ""), s, 1, true) then return true end
    if string.find(string.lower(e.aw or ""), s, 1, true) then return true end
    if string.find(string.lower(e.mdl or ""), s, 1, true) then return true end
    if e.veh and string.find(string.lower(tostring(e.veh)), s, 1, true) then return true end
    if string.find(string.lower(PosStr(e.pos)), s, 1, true) then return true end
    if string.find(string.lower(os.date("%Y-%m-%d %H:%M", tonumber(e.t) or 0)), s, 1, true) then return true end
    if string.find(string.lower(TimeAgo(e.t)), s, 1, true) then return true end
    return false
end

-- Filtered + sorted view of the entries (never mutates the source array).
local function ViewEntries()
    local s = string.lower(HP.Search or "")
    local filter, out = HP.Filter, {}
    for _, e in ipairs(Entries()) do
        local keep = true
        if filter == "pinned" then keep = e.pin == 1
        elseif filter == "noted" then keep = e.note and e.note ~= ""
        elseif filter == "world" then keep = (e.ec or 0) > 0 or (e.nc or 0) > 0 or (e.vc or 0) > 0 end
        if keep and s ~= "" then keep = EntryMatches(e, s) end
        if keep then out[#out + 1] = e end
    end

    local sort = HP.Sort
    if sort == "oldest" then
        table.sort(out, function(a, b) return (tonumber(a.t) or 0) < (tonumber(b.t) or 0) end)
    elseif sort == "health" then
        table.sort(out, function(a, b) return (tonumber(a.hp) or 0) > (tonumber(b.hp) or 0) end)
    elseif sort == "pinned" then
        table.sort(out, function(a, b)
            local ap, bp = a.pin == 1, b.pin == 1
            if ap ~= bp then return ap end
            return (tonumber(a.t) or 0) > (tonumber(b.t) or 0)
        end)
    else -- newest
        table.sort(out, function(a, b) return (tonumber(a.t) or 0) > (tonumber(b.t) or 0) end)
    end
    return out
end

-- Cached filtered/sorted view. Recomputed only when search/sort/filter/data
-- changes (never per Paint frame). Callers must use HP:View().
function HP:InvalidateView() self._view = ViewEntries() end
function HP:View() return self._view or {} end
function HP:Sel() return self.SelectedId and FindEntry(self.SelectedId) or nil end

-- ── entry row (left list) ─────────────────────────────────────────────────────

local function BuildRow(parent, e)
    local row = vgui.Create("DButton", parent)
    row:SetText("")
    row:Dock(TOP)
    row:DockMargin(sc(2), 0, sc(6), sc(6))
    row:SetTall(sc(62))
    row.HoverAnim = 0

    row.Paint = function(self, w, h)
        local selected = HP.SelectedId == e.id
        self.HoverAnim = Lerp(FrameTime() * 12, self.HoverAnim, (self:IsHovered() or selected) and 1 or 0)
        local r = sc(9)

        draw.RoundedBox(r, 0, 0, w, h, THEME.surface)
        if self.HoverAnim > 0.01 then draw.RoundedBox(r, 0, 0, w, h, ColorAlpha(THEME.primary, 18 * self.HoverAnim)) end
        if selected then draw.RoundedBox(r, 0, 0, w, h, ColorAlpha(THEME.primary, 34)) end

        local accent = e.act and THEME.success or (selected and THEME.primary or nil)
        if accent then draw.RoundedBox(sc(3), 0, sc(9), sc(3), h - sc(18), accent) end

        local pad = sc(14)
        draw.SimpleText(TimeAgo(e.t), "RH_BodyB", pad, sc(11), THEME.textPrimary, ALIGN_L, ALIGN_T)
        draw.SimpleText(os.date("%b %d, %H:%M", tonumber(e.t) or 0), "RH_Small", pad, sc(33), THEME.textTertiary, ALIGN_L, ALIGN_T)

        -- top-right status icons: pin, active dot, note
        local bx = w - sc(12)
        local isz = sc(14)
        if e.pin == 1 then
            surface.SetDrawColor(255, 255, 255); surface.SetMaterial(IC_PIN)
            surface.DrawTexturedRect(bx - isz, sc(11), isz, isz); bx = bx - isz - sc(6)
        end
        if e.note and e.note ~= "" then
            surface.SetDrawColor(255, 255, 255); surface.SetMaterial(IC_NOTE)
            surface.DrawTexturedRect(bx - isz, sc(11), isz, isz); bx = bx - isz - sc(6)
        end
        if e.act == 1 then
            draw.RoundedBox(sc(4), bx - sc(8), sc(15), sc(8), sc(8), THEME.success); bx = bx - sc(14)
        end

        -- bottom-right: one badge per object type (only when > 0), then health
        local rx = w - sc(12)
        local iy = sc(34)
        local function badge(mat, n, col)
            if (n or 0) <= 0 then return end
            local txt = tostring(n)
            surface.SetFont("RH_Small")
            local tw = surface.GetTextSize(txt)
            draw.SimpleText(txt, "RH_Small", rx, iy + sc(1), col, ALIGN_R, ALIGN_T)
            local ix = rx - tw - sc(2) - isz
            surface.SetDrawColor(255, 255, 255); surface.SetMaterial(mat)
            surface.DrawTexturedRect(ix, iy, isz, isz)
            rx = ix - sc(9)
        end
        badge(IC_VEH, e.vc, THEME.entity.vehicle)
        badge(IC_NPC, e.nc, THEME.entity.npc)
        badge(IC_ENT, e.ec, THEME.entity.physics)

        local hp = tonumber(e.hp) or 100 -- unsaved health defaults to full
        local htxt = tostring(math.floor(hp))
        draw.SimpleText(htxt, "RH_Small", rx, iy + sc(1), THEME:GetHealthColor(hp, 100), ALIGN_R, ALIGN_T)
        surface.SetFont("RH_Small")
        local htw = surface.GetTextSize(htxt)
        surface.SetDrawColor(255, 255, 255); surface.SetMaterial(IC_HP)
        surface.DrawTexturedRect(rx - htw - sc(2) - isz, iy, isz, isz)
    end

    row.DoClick = function()
        HP:Select(e.id)
        surface.PlaySound("ui/buttonrollover.wav")
    end
    return row
end

-- ── detail pane (built once, updated in place) ────────────────────────────────

function HP:BuildDetail(host)
    local D = {}
    self.D = D
    local pad = sc(4)

    -- Header card: model + time + health bar
    local header = vgui.Create("DPanel", host)
    D.header = header
    header:Dock(TOP); header:SetTall(sc(120)); header:DockMargin(pad, 0, pad, sc(12))
    header.Paint = function(_, w, h)
        draw.RoundedBox(sc(12), 0, 0, w, h, THEME.backgroundDark)
        local e = self:Sel(); if not e then return end
        local mx = sc(110)
        -- facts
        draw.SimpleText(TimeAgo(e.t), "RH_H1", mx, sc(14), THEME.textPrimary, ALIGN_L, ALIGN_T)
        draw.SimpleText(os.date("%A, %B %d %Y  ·  %H:%M:%S", tonumber(e.t) or 0), "RH_Small", mx, sc(44),
            THEME.textSecondary, ALIGN_L, ALIGN_T)

        -- badges
        local by = sc(66)
        if e.act == 1 then
            local txt = L("sth.is_active")
            surface.SetFont("RH_Tiny"); local tw = surface.GetTextSize(txt)
            draw.RoundedBox(sc(5), mx, by, tw + sc(16), sc(18), ColorAlpha(THEME.success, 45))
            draw.SimpleText(txt, "RH_Tiny", mx + sc(8), by + sc(9), THEME.success, ALIGN_L, ALIGN_M)
        elseif e.pin == 1 then
            local txt = "★ " .. L("sth.pinned")
            surface.SetFont("RH_Tiny"); local tw = surface.GetTextSize(txt)
            draw.RoundedBox(sc(5), mx, by, tw + sc(16), sc(18), ColorAlpha(THEME.warning, 45))
            draw.SimpleText(txt, "RH_Tiny", mx + sc(8), by + sc(9), THEME.warning, ALIGN_L, ALIGN_M)
        end

        -- health bar along the bottom (unsaved health = full)
        local barY, barH = h - sc(24), sc(8)
        local barX, barW = mx, w - mx - sc(16)
        draw.RoundedBox(sc(4), barX, barY, barW, barH, THEME.surface)
        local hpVal = tonumber(e.hp) or 100
        local hp = math.Clamp(hpVal / 100, 0, 1)
        if hp > 0 then
            draw.RoundedBox(sc(4), barX, barY, math.max(sc(4), barW * hp), barH, THEME:GetHealthColor(hpVal, 100))
        end
        draw.SimpleText(math.floor(hpVal) .. " HP", "RH_Tiny", barX, barY - sc(12), THEME.textTertiary, ALIGN_L, ALIGN_T)
        local arTxt = e.ar ~= nil and (math.floor(e.ar) .. " " .. string.upper(L("sth.field.armor"))) or string.upper(L("sth.unsaved"))
        draw.SimpleText(arTxt, "RH_Tiny", barX + barW, barY - sc(12), e.ar ~= nil and THEME.info or THEME.textDisabled, ALIGN_R, ALIGN_T)
    end

    local mp = vgui.Create("DModelPanel", header)
    mp:SetPos(sc(8), sc(8)); mp:SetSize(sc(94), sc(104))
    mp:SetModel("models/player/kleiner.mdl")
    mp:SetMouseInputEnabled(false)
    mp.LayoutEntity = function(_, en) en:SetAngles(Angle(0, RealTime() * 22, 0)) end
    D.model = mp

    -- Stat cards: HP, Armor, Weapons, Entities, NPCs, Vehicles
    local stats = vgui.Create("DPanel", host)
    D.stats = stats
    stats:Dock(TOP); stats:SetTall(sc(66)); stats:DockMargin(pad, 0, pad, sc(12))
    stats.Paint = function(_, w, h)
        local e = self:Sel(); if not e then return end
        -- health defaults to full when unsaved; armor is genuinely "Unsaved" when nil
        local hp = tonumber(e.hp) or 100
        local cards = {
            { L("sth.field.health"),   tostring(math.floor(hp)),        THEME:GetHealthColor(hp, 100) },
            { L("sth.field.armor"),    e.ar ~= nil and tostring(math.floor(e.ar)) or nil, THEME.info },
            { L("sth.field.weapons"),  tostring(e.wc or 0),             THEME.textPrimary },
            { L("sth.field.entities"), tostring(e.ec or 0),             THEME.entity.physics },
            { L("sth.field.npcs"),     tostring(e.nc or 0),             THEME.entity.npc },
            { L("sth.field.vehicles"), tostring(e.vc or 0),             THEME.entity.vehicle },
        }
        local n = #cards
        local gap = sc(7)
        local cw = (w - gap * (n - 1)) / n
        for i, cinfo in ipairs(cards) do
            local x = (i - 1) * (cw + gap)
            draw.RoundedBox(sc(8), x, 0, cw, h, THEME.surface)
            if cinfo[2] then
                draw.SimpleText(cinfo[2], "RH_Stat", x + cw / 2, h * 0.42, cinfo[3], ALIGN_C, ALIGN_M)
            else
                draw.SimpleText(L("sth.unsaved"), "RH_Small", x + cw / 2, h * 0.42, THEME.textDisabled, ALIGN_C, ALIGN_M)
            end
            draw.SimpleText(string.upper(cinfo[1]), "RH_Tiny", x + cw / 2, h * 0.78, THEME.textTertiary, ALIGN_C, ALIGN_M)
        end
    end

    -- Info rows (position, active weapon, in-vehicle, states, model)
    local info = vgui.Create("DPanel", host)
    D.info = info
    info:Dock(TOP); info:SetTall(sc(146)); info:DockMargin(pad, 0, pad, sc(12))
    info.Paint = function(_, w, h)
        draw.RoundedBox(sc(10), 0, 0, w, h, THEME.surface)
        local e = self:Sel(); if not e then return end
        local rows = {}
        rows[#rows + 1] = { L("sth.field.position"), PosStr(e.pos), THEME.textPrimary }
        local a = e.ang or {}
        rows[#rows + 1] = { L("sth.field.angle"),
            string.format("%.0f, %.0f, %.0f", tonumber(a.p) or 0, tonumber(a.y) or 0, tonumber(a.r) or 0), THEME.textSecondary }
        local awTxt, awCol
        if e.aw == nil then awTxt, awCol = L("sth.unsaved"), THEME.textDisabled
        elseif e.aw == "None" or e.aw == "" then awTxt, awCol = L("sth.none"), THEME.textTertiary
        else awTxt, awCol = e.aw, THEME.textPrimary end
        rows[#rows + 1] = { L("sth.field.active"), awTxt, awCol }
        if e.veh then
            rows[#rows + 1] = { L("sth.field.in_vehicle"), VehicleClassName(e.veh) or L("sth.yes"), THEME.entity.vehicle }
        end
        local stl = StatesList(e.st)
        rows[#rows + 1] = { L("sth.field.states"),
            #stl > 0 and table.concat(stl, ", ") or L("sth.none"),
            #stl > 0 and THEME.warning or THEME.textTertiary }
        rows[#rows + 1] = e.mdl and { L("sth.field.model"), tostring(e.mdl), THEME.textSecondary }
            or { L("sth.field.model"), L("sth.unsaved"), THEME.textDisabled }

        local rh = sc(23)
        local y = sc(8)
        for i, r in ipairs(rows) do
            if i > 1 then
                surface.SetDrawColor(THEME.divider.r, THEME.divider.g, THEME.divider.b, 90)
                surface.DrawLine(sc(12), y, w - sc(12), y)
            end
            draw.SimpleText(r[1], "RH_Small", sc(12), y + rh / 2, THEME.textTertiary, ALIGN_L, ALIGN_M)
            -- right-aligned value, clipped to available width
            draw.SimpleText(r[2], "RH_Small", w - sc(12), y + rh / 2, r[3], ALIGN_R, ALIGN_M)
            y = y + rh
        end
    end

    -- Preview status + toggle
    D.previewStatus = vgui.Create("DPanel", host)
    D.previewStatus:Dock(TOP); D.previewStatus:DockMargin(pad + sc(2), 0, pad, sc(6)); D.previewStatus:SetTall(sc(20))
    D.previewStatus.Paint = function(_, w, h)
        local e = self:Sel(); if not e then return end
        local clear = true
        if RARELOAD.HistoryPreview and RARELOAD.HistoryPreview.TestClear and istable(e.pos) then
            clear = RARELOAD.HistoryPreview.TestClear(Vector(tonumber(e.pos.x) or 0, tonumber(e.pos.y) or 0, tonumber(e.pos.z) or 0))
        end
        draw.SimpleText(clear and L("sth.inworld_clear") or L("sth.inworld_blocked"), "RH_Small", 0, h / 2,
            clear and THEME.success or THEME.error, ALIGN_L, ALIGN_M)
    end

    D.preview = Button(host, L("sth.preview_show"), THEME.info, function()
        local e = self:Sel(); if not e then return end
        if RARELOAD.HistoryPreview then RARELOAD.HistoryPreview.Toggle(e) end
        self:UpdatePreviewButton()
    end)
    D.preview:Dock(TOP); D.preview:DockMargin(pad, 0, pad, sc(8)); D.preview:SetTall(sc(32))

    -- Open the entity viewer + JSON editor scoped to this save.
    D.objects = Button(host, L("sth.objects"), THEME.entity.vehicle, function()
        local e = self:Sel(); if not e then return end
        local n = (e.ec or 0) + (e.nc or 0) + (e.vc or 0)
        if n <= 0 then ShowNotification(L("sth.objects_none"), NOTIFY_ERROR); return end
        HP._objectsLabel = TimeAgo(e.t) .. "  ·  " .. os.date("%Y-%m-%d %H:%M", tonumber(e.t) or 0)
        net.Start("RareloadHistory_Objects")
        net.WriteString(e.id or "")
        net.SendToServer()
    end)
    D.objects:Dock(TOP); D.objects:DockMargin(pad, 0, pad, sc(10)); D.objects:SetTall(sc(32))

    -- Active banner / set-active
    D.banner = vgui.Create("DPanel", host)
    D.banner:Dock(TOP); D.banner:DockMargin(pad, 0, pad, sc(10)); D.banner:SetTall(sc(34))
    D.banner.Paint = function(_, w, h)
        draw.RoundedBox(sc(8), 0, 0, w, h, ColorAlpha(THEME.success, 45))
        draw.SimpleText(L("sth.is_active"), "RH_Body", w / 2, h / 2, THEME.success, ALIGN_C, ALIGN_M)
    end

    D.setActive = Button(host, L("sth.set_active"), THEME.success, function()
        local e = self:Sel(); if not e then return end
        SendAction("activate", e.id)
        ShowNotification(L("sth.set_active_done"), NOTIFY_GENERIC)
    end)
    D.setActive:Dock(TOP); D.setActive:DockMargin(pad, 0, pad, sc(10)); D.setActive:SetTall(sc(34))

    -- Note editor
    local note = vgui.Create("DTextEntry", host)
    note:Dock(TOP); note:DockMargin(pad, 0, pad, sc(10)); note:SetTall(sc(30))
    note:SetFont("RH_Body"); note:SetUpdateOnType(false)
    note.Paint = function(selfp, w, h)
        draw.RoundedBox(sc(7), 0, 0, w, h, THEME.surface)
        selfp:DrawTextEntryText(THEME.textPrimary, THEME.primary, THEME.textPrimary)
        if selfp:GetValue() == "" and not selfp:HasFocus() then
            draw.SimpleText(L("sth.note_placeholder"), "RH_Body", sc(9), h / 2, THEME.textTertiary, ALIGN_L, ALIGN_M)
        end
    end
    local function commitNote(selfp)
        local e = self:Sel(); if not e then return end
        local v = selfp:GetValue()
        if v == (note._committed or "") then return end
        note._committed = v
        SendAction("note", e.id, function() net.WriteString(v) end)
        ShowNotification(L("sth.note_saved"), NOTIFY_GENERIC)
    end
    note.OnEnter = commitNote
    note.OnGetFocus = function() HP._typing = true end
    note.OnLoseFocus = function(selfp) commitNote(selfp); HP._typing = false end
    D.note = note

    -- Primary actions
    local actions = vgui.Create("DPanel", host)
    D.actions = actions
    actions:Dock(TOP); actions:DockMargin(pad, 0, pad, sc(8)); actions:SetTall(sc(38)); actions.Paint = function() end

    -- LEFT-docked buttons are created first; the FILL button (Restore) comes LAST so
    -- it takes only the remaining space instead of overlapping the others.
    local tp = Button(actions, L("sth.teleport"), THEME.info, function()
        local e = self:Sel(); if not (e and e.pos) then return end
        RunConsoleCommand("rareload_teleport_to", e.pos.x, e.pos.y, e.pos.z)
        ShowNotification(L("sth.teleporting"), NOTIFY_GENERIC)
    end)
    tp:Dock(LEFT); tp:SetWide(sc(104)); tp:DockMargin(0, 0, sc(6), 0)

    D.pin = Button(actions, L("sth.pin"), THEME.warning, function()
        local e = self:Sel(); if not e then return end
        SendAction("pin", e.id, function() net.WriteBool(e.pin ~= 1) end)
    end)
    D.pin:Dock(LEFT); D.pin:SetWide(sc(78)); D.pin:DockMargin(0, 0, sc(6), 0)

    local del = Button(actions, L("sth.delete"), THEME.error, function()
        local e = self:Sel(); if not e then return end
        ConfirmDialog(L("sth.delete"), L("sth.delete_confirm"), function()
            SendAction("delete", e.id)
            HP.SelectedId = nil
        end)
    end)
    del:Dock(LEFT); del:SetWide(sc(78)); del:DockMargin(0, 0, sc(6), 0)

    local rs = Button(actions, L("sth.restore_all"), THEME.success, function()
        local e = self:Sel(); if not e then return end
        SendAction("restore", e.id, function() WriteComps({ all = true }) end)
        ShowNotification(L("sth.restoring"), NOTIFY_GENERIC)
    end, { solid = true })
    rs:Dock(FILL)

    -- Partial restore
    local partHeader = vgui.Create("DPanel", host)
    D.partHeader = partHeader
    partHeader:Dock(TOP); partHeader:DockMargin(pad, sc(4), pad, sc(6)); partHeader:SetTall(sc(18))
    partHeader.Paint = function(_, w, h)
        draw.SimpleText(L("sth.partial_title"), "RH_Tiny", 0, h / 2, THEME.textTertiary, ALIGN_L, ALIGN_M)
    end

    local comps = {
        { "position", "sth.comp.position" }, { "health", "sth.comp.health" },
        { "inventory", "sth.comp.inventory" }, { "ammo", "sth.comp.ammo" },
        { "appearance", "sth.comp.appearance" }, { "states", "sth.comp.states" },
        { "world", "sth.comp.world" },
    }
    local grid = vgui.Create("DIconLayout", host)
    D.grid = grid
    grid:Dock(TOP); grid:DockMargin(pad, 0, pad, sc(8)); grid:SetTall(sc(58)); grid:SetSpaceX(sc(6)); grid:SetSpaceY(sc(6))
    for _, c in ipairs(comps) do
        local cb = grid:Add("DCheckBoxLabel")
        cb:SetText(L(c[2])); cb:SetTextColor(THEME.textSecondary); cb:SetFont("RH_Small")
        cb:SetValue(HP.Comps[c[1]] and true or false); cb:SizeToContents()
        cb.OnChange = function(_, v) HP.Comps[c[1]] = v end
    end

    D.applyBtn = Button(host, L("sth.apply_selected"), THEME.primary, function()
        local e = self:Sel(); if not e then return end
        local chosen = {}
        for k, v in pairs(HP.Comps) do if v then chosen[k] = true end end
        if not next(chosen) then ShowNotification(L("sth.nothing_selected"), NOTIFY_ERROR); return end
        SendAction("restore", e.id, function() WriteComps(chosen) end)
        ShowNotification(L("sth.restoring"), NOTIFY_GENERIC)
    end)
    D.applyBtn:Dock(TOP); D.applyBtn:DockMargin(pad, 0, pad, sc(6)); D.applyBtn:SetTall(sc(32))

    -- Empty state (nothing selected)
    D.empty = vgui.Create("DPanel", host)
    D.empty:Dock(TOP); D.empty:SetTall(sc(320)); D.empty:SetMouseInputEnabled(false)
    D.empty.Paint = function(_, w, h)
        draw.SimpleText("◈", "RH_Stat", w / 2, h / 2 - sc(26), THEME.textDisabled, ALIGN_C, ALIGN_M)
        draw.SimpleText(L("sth.select_hint"), "RH_H2", w / 2, h / 2 + sc(8), THEME.textSecondary, ALIGN_C, ALIGN_M)
    end
end

function HP:UpdatePreviewButton()
    if not self.D then return end
    local e = self:Sel()
    local showing = e and RARELOAD.HistoryPreview and RARELOAD.HistoryPreview.IsShowing(e.id)
    self.D.preview:SetText2(showing and L("sth.preview_hide") or L("sth.preview_show"))
end

-- Update the persistent detail widgets to the current selection (no teardown).
function HP:UpdateDetail()
    local D = self.D
    if not D then return end
    local e = self:Sel()
    local hasSel = e ~= nil

    for _, k in ipairs({ "header", "stats", "info", "previewStatus", "preview", "objects", "banner",
        "setActive", "note", "actions", "partHeader", "grid", "applyBtn" }) do
        if IsValid(D[k]) then D[k]:SetVisible(hasSel) end
    end
    if IsValid(D.empty) then D.empty:SetVisible(not hasSel) end
    if not hasSel then
        if RARELOAD.HistoryPreview then RARELOAD.HistoryPreview.Clear() end
        return
    end

    -- model
    local dispModel = (e.mdl and util.IsValidModel(e.mdl)) and e.mdl or nil
    if not dispModel then
        local lp = LocalPlayer()
        if IsValid(lp) and util.IsValidModel(lp:GetModel()) then dispModel = lp:GetModel() end
    end
    if dispModel and D.model:GetModel() ~= dispModel then
        D.model:SetModel(dispModel)
        timer.Simple(0, function() if IsValid(D.model) then FrameModelPanel(D.model) end end)
    end

    D.pin:SetText2(e.pin == 1 and L("sth.unpin") or L("sth.pin"))
    D.banner:SetVisible(e.act == 1)
    D.setActive:SetVisible(e.act ~= 1)
    self:UpdatePreviewButton()

    if IsValid(D.objects) then
        local n = (e.ec or 0) + (e.nc or 0) + (e.vc or 0)
        D.objects:SetText2(n > 0 and L("sth.objects_count", n) or L("sth.objects_none"))
    end

    if not D.note:HasFocus() then
        D.note._committed = e.note or ""
        D.note:SetText(e.note or "")
    end

    -- don't let a preview from a different entry linger
    if RARELOAD.HistoryPreview and RARELOAD.HistoryPreview.active and RARELOAD.HistoryPreview.showId ~= e.id then
        RARELOAD.HistoryPreview.Clear()
        self:UpdatePreviewButton()
    end
end

function HP:Select(id)
    self.SelectedId = id
    self:UpdateDetail()
end

-- ── list ──────────────────────────────────────────────────────────────────────

function HP:RebuildList()
    local scroll = self.List
    if not IsValid(scroll) then return end
    self:InvalidateView()
    scroll:Clear()

    local function centered(text, col, font)
        local p = vgui.Create("DPanel", scroll)
        p:Dock(TOP); p:DockMargin(sc(8), sc(40), sc(8), 0); p:SetTall(sc(60))
        p.Paint = function(_, w, h)
            draw.SimpleText(text, font or "RH_H2", w / 2, h / 2, col, ALIGN_C, ALIGN_M)
        end
        return p
    end

    if self.Loading then centered(L("sth.loading"), THEME.textSecondary); return end
    if self.LoadError then centered(L("sth.load_error"), THEME.error); return end

    local list = self:View()
    if #list == 0 then
        local empty = vgui.Create("DPanel", scroll)
        empty:Dock(TOP); empty:DockMargin(sc(8), sc(40), sc(8), 0); empty:SetTall(sc(120))
        empty.Paint = function(_, w, h)
            draw.SimpleText(L("sth.empty"), "RH_H2", w / 2, h / 2 - sc(12), THEME.textSecondary, ALIGN_C, ALIGN_M)
            draw.SimpleText(L("sth.empty_hint"), "RH_Small", w / 2, h / 2 + sc(14), THEME.textTertiary, ALIGN_C, ALIGN_M)
        end
        return
    end
    for _, e in ipairs(list) do BuildRow(scroll, e) end
end

-- ── refresh (data changed) ─────────────────────────────────────────────────────

function HP:Refresh()
    self:InvalidateView()
    if not self.SelectedId or not FindEntry(self.SelectedId) then
        local v = self:View()
        self.SelectedId = v[1] and v[1].id or nil
    end
    self:RebuildList()
    self:UpdateDetail()
    if IsValid(self.CountLabel) then
        self.CountLabel:SetText(L("sth.count", RARELOAD.HistoryClient.total or #Entries()))
    end
    if IsValid(self.UndoBtn) then self.UndoBtn:SetVisible(RARELOAD.HistoryClient.undo == true) end
end

-- ── keyboard navigation ─────────────────────────────────────────────────────────

function HP:MoveSelection(dir)
    local v = self:View()
    if #v == 0 then return end
    local idx = 1
    for i, e in ipairs(v) do if e.id == self.SelectedId then idx = i break end end
    idx = math.Clamp(idx + dir, 1, #v)
    self:Select(v[idx].id)
end

-- ── open ───────────────────────────────────────────────────────────────────────

function HP:Open()
    if IsValid(self.Frame) then self.Frame:Close() end
    UI.EnsureFonts()

    local frame = vgui.Create("DFrame")
    local w = math.min(ScrW() * 0.82, sc(1220))
    local h = math.min(ScrH() * 0.86, sc(800))
    frame:SetSize(w, h)
    frame:SetMinWidth(sc(880)); frame:SetMinHeight(sc(560))
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:MakePopup()
    frame:SetSizable(true)
    self.Frame = frame

    local headH = sc(64)
    frame.Paint = function(_, fw, fh)
        draw.RoundedBox(sc(14), 0, 0, fw, fh, THEME.background)
        surface.SetDrawColor(THEME.divider)
        surface.DrawLine(0, headH, fw, headH)
        draw.SimpleText(L("sth.title"), "RH_Title", sc(18), sc(13), THEME.primaryLight, ALIGN_L, ALIGN_T)
        draw.SimpleText(L("sth.subtitle"), "RH_Sub", sc(20), sc(42), THEME.textTertiary, ALIGN_L, ALIGN_T)
    end

    -- header spacer keeps the title bar draggable
    local spacer = vgui.Create("DPanel", frame)
    spacer:Dock(TOP); spacer:SetTall(headH); spacer:SetMouseInputEnabled(false); spacer.Paint = function() end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL); body.Paint = function() end

    -- ── sidebar ──
    local side = vgui.Create("DPanel", body)
    side:Dock(LEFT); side:SetWide(sc(360)); side:DockPadding(sc(12), sc(12), sc(12), sc(10))
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
            draw.SimpleText(L("sth.search_placeholder"), "RH_Body", sc(28), sh / 2, THEME.textTertiary, ALIGN_L, ALIGN_M)
        end
    end
    search.OnChange = function(selfp) HP.Search = selfp:GetValue(); HP:RebuildList() end
    search.OnGetFocus = function() HP._typing = true end
    search.OnLoseFocus = function() HP._typing = false end

    -- controls: sort dropdown (its own row) + filter chips (its own row, equal-width)
    local sortBtn = vgui.Create("DButton", side)
    sortBtn:Dock(TOP); sortBtn:DockMargin(0, sc(8), 0, 0); sortBtn:SetTall(sc(26)); sortBtn:SetText("")
    sortBtn.Paint = function(selfp, bw, bh)
        draw.RoundedBox(sc(6), 0, 0, bw, bh, THEME.surface)
        draw.SimpleText(L("sth.sort_label") .. " " .. L("sth.sort." .. HP.Sort), "RH_Small", sc(10), bh / 2,
            THEME.textSecondary, ALIGN_L, ALIGN_M)
        draw.SimpleText("▾", "RH_Small", bw - sc(10), bh / 2, THEME.textTertiary, ALIGN_R, ALIGN_M)
    end
    sortBtn.DoClick = function()
        local m = DermaMenu()
        for _, s in ipairs(SORTS) do
            m:AddOption(L("sth.sort." .. s), function() HP.Sort = s; HP:RebuildList() end)
        end
        m:Open()
    end

    local chips = vgui.Create("DPanel", side)
    chips:Dock(TOP); chips:DockMargin(0, sc(6), 0, sc(8)); chips:SetTall(sc(26)); chips.Paint = function() end
    local chipBtns = {}
    for _, fkey in ipairs(FILTERS) do
        local chip = vgui.Create("DButton", chips)
        chip:SetText("")
        chip.Paint = function(selfp, bw, bh)
            local on = HP.Filter == fkey
            draw.RoundedBox(sc(6), 0, 0, bw, bh, on and ColorAlpha(THEME.primary, 70) or THEME.surface)
            draw.SimpleText(L("sth.filter." .. fkey), "RH_Small", bw / 2, bh / 2,
                on and THEME.textPrimary or THEME.textTertiary, ALIGN_C, ALIGN_M)
        end
        chip.DoClick = function() HP.Filter = fkey; HP:RebuildList() end
        chipBtns[#chipBtns + 1] = chip
    end
    -- distribute chips equally across the row so long labels (e.g. "Objects") fit
    chips.PerformLayout = function(_, cw, ch)
        local n = #chipBtns
        if n == 0 then return end
        local gap = sc(5)
        local w1 = math.floor((cw - gap * (n - 1)) / n)
        local x = 0
        for i, c in ipairs(chipBtns) do
            local ww = (i == n) and (cw - x) or w1
            c:SetPos(x, 0); c:SetSize(ww, ch)
            x = x + ww + gap
        end
    end

    -- footer: kbd hint + count (docked bottom before the list fills)
    local hint = vgui.Create("DPanel", side)
    hint:Dock(BOTTOM); hint:SetTall(sc(16)); hint.Paint = function(_, sw, sh)
        draw.SimpleText(L("sth.kbd_hint"), "RH_Tiny", 0, sh / 2, THEME.textDisabled, ALIGN_L, ALIGN_M)
    end
    local countLabel = vgui.Create("DLabel", side)
    countLabel:Dock(BOTTOM); countLabel:SetTall(sc(22)); countLabel:SetFont("RH_Small")
    countLabel:SetTextColor(THEME.textTertiary)
    countLabel:SetText(L("sth.count", RARELOAD.HistoryClient.total or #Entries()))
    self.CountLabel = countLabel

    local list = vgui.Create("DScrollPanel", side)
    list:Dock(FILL); list:DockMargin(0, sc(2), 0, sc(6))
    StyleScrollbar(list)
    self.List = list

    -- ── detail ──
    local detail = vgui.Create("DScrollPanel", body)
    detail:Dock(FILL); detail:DockMargin(sc(14), sc(12), sc(8), sc(12))
    StyleScrollbar(detail)
    self.Detail = detail
    self:BuildDetail(detail)

    -- ── top-right controls (absolute children so they float above the body) ──
    local topButtons = {}
    local function topBtn(text, color, wide, fn)
        local b = Button(frame, text, color, fn)
        b._wide = wide
        topButtons[#topButtons + 1] = b
        return b
    end
    topBtn("✕", THEME.error, sc(34), function() frame:Close() end)
    topBtn(L("sth.refresh"), THEME.info, sc(100), function() self:RequestData() end)
    topBtn(L("sth.clear_all"), THEME.error, sc(112), function()
        ConfirmDialog(L("sth.clear_all"), L("sth.clear_confirm"), function()
            SendAction("clear", ""); self.SelectedId = nil
        end)
    end)
    self.UndoBtn = topBtn(L("sth.undo"), THEME.warning, sc(120), function() SendAction("undo", "") end)
    self.UndoBtn:SetVisible(RARELOAD.HistoryClient.undo == true)

    local baseLayout = frame.PerformLayout
    frame.PerformLayout = function(pnl, fw, fh)
        if baseLayout then baseLayout(pnl, fw, fh) end
        local x = fw - sc(12)
        for _, b in ipairs(topButtons) do
            x = x - b._wide
            b:SetSize(b._wide, sc(34))
            b:SetPos(x, sc(14))
            x = x - sc(6)
        end
    end
    frame:InvalidateLayout(true)

    -- keyboard navigation (skipped while typing). Chain base Think so drag/resize work.
    local baseThink = frame.Think
    frame.Think = function(pnl)
        if baseThink then baseThink(pnl) end
        if self._typing then self._keys = {}; return end
        self._keys = self._keys or {}
        local function edge(key, fn)
            local down = input.IsKeyDown(key)
            if down and not self._keys[key] then fn() end
            self._keys[key] = down
        end
        edge(KEY_UP, function() self:MoveSelection(-1) end)
        edge(KEY_DOWN, function() self:MoveSelection(1) end)
        edge(KEY_ENTER, function()
            local e = self:Sel()
            if e then
                SendAction("restore", e.id, function() WriteComps({ all = true }) end)
                ShowNotification(L("sth.restoring"), NOTIFY_GENERIC)
            end
        end)
        edge(KEY_DELETE, function()
            local e = self:Sel()
            if e then
                ConfirmDialog(L("sth.delete"), L("sth.delete_confirm"), function() SendAction("delete", e.id); self.SelectedId = nil end)
            end
        end)
    end

    self:RebuildList()
    self:UpdateDetail()
    self:RequestData()
end

-- ── entry points ────────────────────────────────────────────────────────────────

concommand.Add("rareload_history", function() HP:Open() end)
concommand.Add("rareload_save_timeline", function() HP:Open() end)

function OpenPositionHistory() HP:Open() end

RARELOAD.HistoryPanel = HP
