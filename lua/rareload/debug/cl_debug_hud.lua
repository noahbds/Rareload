-- Rareload debug client (v2): a glanceable live overlay + an interactive panel.
--   Overlay  (rareload_debug hud)   : stream tail, watches, counters, report card.
--   Panel    (rareload_debug panel) : scroll, pause, filter, expand, copy.
if not CLIENT then return end

RARELOAD = RARELOAD or {}
RARELOAD.DebugHUD = RARELOAD.DebugHUD or {}
local HUD = RARELOAD.DebugHUD

HUD.visible   = HUD.visible or false
HUD.events    = HUD.events or {}      -- ordered list, oldest first
HUD.bySeq     = HUD.bySeq or {}       -- seq -> event (for collapse upserts)
HUD.reports   = HUD.reports or {}     -- last N report cards
HUD.reportIdx = HUD.reportIdx or 0    -- which report the overlay shows (0 = newest)
HUD.status    = HUD.status or { errors = 0, warns = 0, total = 0, watches = {} }
HUD.filter    = HUD.filter or nil
HUD.errorFlash = HUD.errorFlash or 0
local MAX_EVENTS = 300
local MAX_REPORTS = 10

local LEVEL = {
    [1] = { label = "ERROR", color = Color(255, 80, 80) },
    [2] = { label = "WARN", color = Color(255, 175, 60) },
    [3] = { label = "INFO", color = Color(90, 180, 255) },
    [4] = { label = "VERBOSE", color = Color(165, 165, 165) },
}
local FONT, FONT_SM = "RareloadBody", "RareloadSmall"
local CAT = Color(120, 200, 255)
local KEY = Color(150, 150, 160)
local VAL = Color(210, 210, 215)
local WHITE = Color(230, 230, 235)
local STEP_COL = { ok = Color(110, 230, 140), fail = Color(255, 90, 90), start = Color(120, 200, 255), warn = Color(255, 180, 70) }
local STEP_ICON = { ok = "✓", fail = "✗", start = "⚡", warn = "!" }

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------
local function readEvent()
    local ev = { seq = net.ReadUInt(32), count = net.ReadUInt(16) }
    ev.category = net.ReadString()
    ev.level = net.ReadUInt(3)
    ev.message = net.ReadString()
    local n = net.ReadUInt(6)
    if n > 0 then
        ev.data = {}
        for _ = 1, n do ev.data[#ev.data + 1] = { net.ReadString(), net.ReadString() } end
    end
    ev.at = CurTime()
    return ev
end

local function pushEvent(ev)
    local existing = HUD.bySeq[ev.seq]
    if existing then
        existing.count, existing.data, existing.at = ev.count, ev.data, ev.at
    else
        HUD.events[#HUD.events + 1] = ev
        HUD.bySeq[ev.seq] = ev
        if ev.level == 1 then HUD.errorFlash = CurTime() end
        while #HUD.events > MAX_EVENTS do
            local old = table.remove(HUD.events, 1)
            if old then HUD.bySeq[old.seq] = nil end
        end
    end
end

net.Receive("RareloadDebugBatch", function()
    local n = net.ReadUInt(8)
    for _ = 1, n do pushEvent(readEvent()) end
end)

net.Receive("RareloadDebugStatus", function()
    HUD.status.errors = net.ReadUInt(24)
    HUD.status.warns = net.ReadUInt(24)
    HUD.status.total = net.ReadUInt(24)
    local n = net.ReadUInt(6)
    local w = {}
    for _ = 1, n do w[#w + 1] = { net.ReadString(), net.ReadString() } end
    HUD.status.watches = w
end)

net.Receive("RareloadDebugReport", function()
    local r = { category = net.ReadString(), success = net.ReadBool(), elapsed = net.ReadString(), title = net.ReadString() }
    local n = net.ReadUInt(6)
    r.steps = {}
    for _ = 1, n do
        r.steps[#r.steps + 1] = { status = net.ReadString(), title = net.ReadString(), detail = net.ReadString() }
    end
    r.at = CurTime()
    HUD.reports[#HUD.reports + 1] = r
    while #HUD.reports > MAX_REPORTS do table.remove(HUD.reports, 1) end
    HUD.reportIdx = 0 -- jump to newest
end)

local function requestSync() net.Start("RareloadDebugSync") net.SendToServer() end

--------------------------------------------------------------------------------
-- Shared formatting
--------------------------------------------------------------------------------
local function eventLine(ev)
    local msg = ev.message
    if (ev.count or 1) > 1 then msg = msg .. "  ×" .. ev.count end
    return msg
end

local function filtered()
    local out = {}
    for i = 1, #HUD.events do
        local ev = HUD.events[i]
        if not HUD.filter or ev.category == HUD.filter then out[#out + 1] = ev end
    end
    return out
end

--------------------------------------------------------------------------------
-- Overlay (HUDPaint) — glanceable, non-interactive
--------------------------------------------------------------------------------
local SHOW_LINES, EVENT_TTL = 14, 16
local function drawStream()
    surface.SetFont(FONT_SM)
    local x, y = 16, 96
    local now = CurTime()

    draw.SimpleText("RARELOAD DEBUG", FONT_SM, x, y - 18, Color(120, 200, 255, 220))
    local badge = string.format("err %d  warn %d", HUD.status.errors, HUD.status.warns)
    draw.SimpleText(badge, FONT_SM, x + 130, y - 18, HUD.status.errors > 0 and Color(255, 110, 110) or KEY)
    if HUD.filter then draw.SimpleText("[" .. HUD.filter .. "]", FONT_SM, x + 260, y - 18, Color(255, 200, 100, 220)) end

    local list = filtered()
    local from = math.max(1, #list - SHOW_LINES + 1)
    for i = from, #list do
        local ev = list[i]
        local age = now - (ev.at or now)
        local a = age > EVENT_TTL and math.max(0, 255 - (age - EVENT_TTL) * 120) or 255
        if a > 4 then
            local lv = LEVEL[ev.level] or LEVEL[3]
            local tag = "[" .. ev.category:upper() .. "] "
            draw.SimpleText(tag, FONT_SM, x, y, ColorAlpha(CAT, a))
            draw.SimpleText(eventLine(ev), FONT_SM, x + surface.GetTextSize(tag), y, ColorAlpha(lv.color, a))
            y = y + 15
            if ev.data then
                for _, kv in ipairs(ev.data) do
                    draw.SimpleText("   " .. (kv[1] ~= "" and (kv[1] .. " = ") or "") .. kv[2], FONT_SM, x, y,
                        ColorAlpha(kv[1] ~= "" and KEY or VAL, a))
                    y = y + 14
                end
            end
        end
    end
    if #HUD.events == 0 then
        local on = RARELOAD.GetClientDebugEnabled and RARELOAD.GetClientDebugEnabled()
        draw.SimpleText(on and "Waiting for debug events..." or "Debug is OFF - run: rareload_debug on",
            FONT_SM, x, y, Color(160, 160, 160, 200))
    end
end

local function drawWatches()
    local w = HUD.status.watches
    if not w or #w == 0 then return end
    local x, y = 16, ScrH() - 40 - (#w * 16)
    draw.SimpleText("WATCHES", FONT_SM, x, y - 16, Color(150, 220, 150, 220))
    for _, kv in ipairs(w) do
        draw.SimpleText(kv[1] .. ":", FONT_SM, x, y, KEY)
        draw.SimpleText(kv[2], FONT_SM, x + 130, y, Color(150, 255, 180))
        y = y + 16
    end
end

local function drawReport()
    local r = HUD.reports[#HUD.reports - HUD.reportIdx]
    if not r then return end
    local w, rowH = 420, 18
    local h = 66 + (#r.steps * rowH)
    local x, y = ScrW() - w - 24, 120
    draw.RoundedBox(8, x, y, w, h, Color(20, 22, 28, 235))
    local bar = r.success and Color(90, 200, 120) or Color(230, 90, 90)
    draw.RoundedBoxEx(8, x, y, w, 6, bar, true, true, false, false)
    draw.SimpleText(r.title ~= "" and r.title or r.category:upper(), "RareloadHeading", x + 16, y + 14, WHITE)
    draw.SimpleText((r.success and "SUCCESS" or "FAILURE") .. "  ·  " .. r.elapsed, FONT_SM, x + 16, y + 40, bar)
    if #HUD.reports > 1 then
        draw.SimpleText(string.format("%d/%d  (\226\151\128\226\150\182 browse)", #HUD.reports - HUD.reportIdx, #HUD.reports),
            FONT_SM, x + w - 16, y + 40, Color(150, 150, 160), TEXT_ALIGN_RIGHT)
    end
    local ry = y + 62
    for _, st in ipairs(r.steps) do
        local col = STEP_COL[st.status] or Color(180, 180, 185)
        local icon = STEP_ICON[st.status] or "•"
        draw.SimpleText(icon .. " " .. st.title .. (st.detail ~= "" and ("  —  " .. st.detail) or ""),
            FONT_SM, x + 16, ry, col)
        ry = ry + rowH
    end
end

hook.Add("HUDPaint", "RareloadDebugHUD", function()
    if not HUD.visible then return end
    -- brief red edge flash on a new error
    local fa = 1 - (CurTime() - HUD.errorFlash)
    if fa > 0 and fa <= 1 then
        surface.SetDrawColor(255, 40, 40, 60 * fa)
        surface.DrawRect(0, 0, ScrW(), 6)
        surface.DrawRect(0, ScrH() - 6, ScrW(), 6)
    end
    drawStream()
    drawWatches()
    drawReport()
end)

-- Browse report history with arrow keys while the overlay is up.
hook.Add("Think", "RareloadDebugReportBrowse", function()
    if not HUD.visible or #HUD.reports < 2 then return end
    if input.IsKeyDown(KEY_LEFT) and not HUD._lk then
        HUD.reportIdx = math.min(HUD.reportIdx + 1, #HUD.reports - 1); HUD._lk = true
    elseif input.IsKeyDown(KEY_RIGHT) and not HUD._rk then
        HUD.reportIdx = math.max(HUD.reportIdx - 1, 0); HUD._rk = true
    end
    if not input.IsKeyDown(KEY_LEFT) then HUD._lk = false end
    if not input.IsKeyDown(KEY_RIGHT) then HUD._rk = false end
end)

--------------------------------------------------------------------------------
-- Interactive panel (DFrame)
--------------------------------------------------------------------------------
local function copyAll()
    local lines = {}
    for _, ev in ipairs(filtered()) do
        lines[#lines + 1] = string.format("[%s][%s] %s", ev.category:upper(),
            (LEVEL[ev.level] or LEVEL[3]).label, eventLine(ev))
        if ev.data then
            for _, kv in ipairs(ev.data) do
                lines[#lines + 1] = "    " .. (kv[1] ~= "" and (kv[1] .. " = ") or "") .. kv[2]
            end
        end
    end
    SetClipboardText(table.concat(lines, "\n"))
end

function HUD.OpenPanel()
    if IsValid(HUD.frame) then HUD.frame:Remove() end
    requestSync()

    local f = vgui.Create("DFrame")
    HUD.frame = f
    f:SetSize(math.min(760, ScrW() - 80), math.min(520, ScrH() - 120))
    f:Center()
    f:SetTitle("")
    f:MakePopup()
    f.paused = false
    f.expanded = {}

    f.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(18, 20, 26, 250))
        draw.RoundedBoxEx(8, 0, 0, w, 34, Color(28, 31, 40), true, true, false, false)
        draw.SimpleText("Rareload Debug", "RareloadHeading", 14, 8, WHITE)
        draw.SimpleText(string.format("err %d   warn %d   total %d", HUD.status.errors, HUD.status.warns, HUD.status.total),
            FONT_SM, w - 150, 12, HUD.status.errors > 0 and Color(255, 120, 120) or KEY)
    end

    -- toolbar
    local bar = vgui.Create("DPanel", f); bar:Dock(TOP); bar:DockMargin(8, 38, 8, 4); bar:SetTall(28)
    bar.Paint = function() end
    local function tbtn(label, wide, fn)
        local b = vgui.Create("DButton", bar); b:Dock(LEFT); b:DockMargin(0, 0, 6, 0); b:SetWide(wide)
        b:SetText(label); b:SetTextColor(WHITE)
        b.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and Color(60, 66, 80) or Color(40, 44, 54)) end
        b.DoClick = fn
        return b
    end
    local pauseBtn
    pauseBtn = tbtn("Pause", 70, function() f.paused = not f.paused; pauseBtn:SetText(f.paused and "Resume" or "Pause") end)
    tbtn("Clear", 60, function() HUD.events, HUD.bySeq = {}, {} end)
    tbtn("Copy", 60, function() copyAll() end)
    local lvl = vgui.Create("DComboBox", bar); lvl:Dock(LEFT); lvl:DockMargin(0, 0, 6, 0); lvl:SetWide(90)
    lvl:SetValue("All levels")
    for _, n in ipairs({ "All levels", "ERROR", "WARN", "INFO", "VERBOSE" }) do lvl:AddChoice(n) end
    f.levelMax = 4
    lvl.OnSelect = function(_, _, val)
        f.levelMax = ({ ["All levels"] = 4, ERROR = 1, WARN = 2, INFO = 3, VERBOSE = 4 })[val] or 4
    end

    -- category chips row
    local chips = vgui.Create("DPanel", f); chips:Dock(TOP); chips:DockMargin(8, 0, 8, 4); chips:SetTall(24)
    chips.Paint = function() end
    f.rebuildChips = function()
        chips:Clear()
        local seen, cats = {}, { "all" }
        for _, ev in ipairs(HUD.events) do if not seen[ev.category] then seen[ev.category] = true cats[#cats + 1] = ev.category end end
        for _, c in ipairs(cats) do
            local b = vgui.Create("DButton", chips); b:Dock(LEFT); b:DockMargin(0, 0, 4, 0); b:SetWide(78)
            b:SetText(c); b:SetTextColor(WHITE)
            b.Paint = function(s, w, h)
                local active = (c == "all" and not HUD.filter) or (c == HUD.filter)
                draw.RoundedBox(4, 0, 0, w, h, active and Color(60, 110, 170) or Color(38, 42, 52))
            end
            b.DoClick = function() HUD.filter = (c == "all") and nil or c end
        end
    end
    f.rebuildChips()

    -- event list
    local scroll = vgui.Create("DScrollPanel", f); scroll:Dock(FILL); scroll:DockMargin(8, 0, 8, 8)
    f.scroll = scroll
    f._lastCount = -1

    f.rebuild = function()
        scroll:Clear()
        for _, ev in ipairs(filtered()) do
            if ev.level <= f.levelMax then
                local lv = LEVEL[ev.level] or LEVEL[3]
                local row = vgui.Create("DPanel", scroll); row:Dock(TOP); row:DockMargin(0, 0, 0, 2)
                local expanded = f.expanded[ev.seq]
                local dataN = (expanded and ev.data) and #ev.data or 0
                row:SetTall(20 + dataN * 15)
                row.Paint = function(_, w, h)
                    draw.RoundedBox(3, 0, 0, w, h, Color(26, 29, 37))
                    surface.SetDrawColor(lv.color.r, lv.color.g, lv.color.b, 200); surface.DrawRect(0, 0, 3, h)
                    draw.SimpleText("[" .. ev.category:upper() .. "]", FONT_SM, 10, 3, CAT)
                    draw.SimpleText(eventLine(ev), FONT_SM, 10 + surface.GetTextSize("[" .. ev.category:upper() .. "] "), 3, lv.color)
                    if ev.data and not expanded then
                        draw.SimpleText("+" .. #ev.data, FONT_SM, w - 24, 3, KEY)
                    end
                    if expanded and ev.data then
                        local yy = 19
                        for _, kv in ipairs(ev.data) do
                            draw.SimpleText("    " .. (kv[1] ~= "" and (kv[1] .. " = ") or "") .. kv[2], FONT_SM, 12, yy, VAL)
                            yy = yy + 15
                        end
                    end
                end
                row.OnMousePressed = function()
                    if ev.data then f.expanded[ev.seq] = not f.expanded[ev.seq]; f.rebuild() end
                end
            end
        end
    end
    f.rebuild()

    f.Think = function()
        if f.paused then return end
        if #HUD.events ~= f._lastCount then
            f._lastCount = #HUD.events
            f.rebuildChips()
            f.rebuild()
            local sb = scroll:GetVBar()
            if sb then sb:SetScroll(sb.CanvasSize or 1e6) end -- follow the tail
        end
    end
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------
local function notify(msg) chat.AddText(Color(120, 200, 255), "[Rareload] ", color_white, msg) end

concommand.Add("rareload_debug", function(_, _, args)
    local sub = (args[1] or "hud"):lower()
    if sub == "hud" then
        HUD.visible = not HUD.visible
        if HUD.visible then requestSync() end
        notify("Overlay " .. (HUD.visible and "shown" or "hidden"))
    elseif sub == "panel" then
        if IsValid(HUD.frame) then HUD.frame:Remove() else HUD.OpenPanel() end
    elseif sub == "on" or sub == "off" or sub == "toggle" then
        local cur = RARELOAD.GetClientDebugEnabled and RARELOAD.GetClientDebugEnabled() or false
        local val = (sub == "on") or (sub == "toggle" and not cur)
        if RARELOAD.UpdatePlayerSetting then RARELOAD.UpdatePlayerSetting("debugEnabled", val) end
        notify("Debug " .. (val and "enabled" or "disabled"))
    elseif sub == "level" then
        local lvl = args[2] and args[2]:upper()
        if lvl and (lvl == "ERROR" or lvl == "WARN" or lvl == "INFO" or lvl == "VERBOSE") then
            if RARELOAD.UpdatePlayerSetting then RARELOAD.UpdatePlayerSetting("debugLevel", lvl) end
            notify("Level set to " .. lvl)
        else notify("Levels: ERROR, WARN, INFO, VERBOSE") end
    elseif sub == "diag" then
        net.Start("RareloadDebugDiag") net.SendToServer(); notify("Diagnostics requested")
    elseif sub == "filter" then
        HUD.filter = (args[2] and args[2] ~= "" and args[2]:lower()) or nil
        notify(HUD.filter and ("Filtering: " .. HUD.filter) or "Filter cleared")
    elseif sub == "dump" then
        for _, ev in ipairs(HUD.events) do
            print(string.format("[%s][%s] %s", ev.category:upper(), (LEVEL[ev.level] or LEVEL[3]).label, eventLine(ev)))
        end
        notify("Dumped " .. #HUD.events .. " events to console")
    elseif sub == "clear" then
        HUD.events, HUD.bySeq, HUD.reports = {}, {}, {}
        notify("Cleared")
    else
        notify("rareload_debug [hud|panel|on|off|level <L>|diag|filter <cat>|dump|clear]")
    end
end, nil, "Rareload debug: overlay, interactive panel, filters, diagnostics.")
