-- Rareload debug client (v2): a glanceable live overlay + an interactive panel.
--   Overlay  (rareload_debug hud)   : stream tail, watches, counters, report card.
--   Panel    (rareload_debug panel) : scroll, pause, filter, expand, copy.
if not CLIENT then return end

RARELOAD             = RARELOAD or {}
RARELOAD.DebugHUD    = RARELOAD.DebugHUD or {}
local HUD            = RARELOAD.DebugHUD

HUD.visible          = HUD.visible or false
HUD.events           = HUD.events or {}  -- ordered list, oldest first
HUD.bySeq            = HUD.bySeq or {}   -- seq -> event (for collapse upserts)
HUD.reports          = HUD.reports or {} -- last N report cards (history for panel/dump)
HUD.toast            = HUD.toast or nil  -- { r = report, t0 = start } for the animated card
HUD.status           = HUD.status or { errors = 0, warns = 0, total = 0, watches = {} }
HUD.filter           = HUD.filter or nil
HUD.errorFlash       = HUD.errorFlash or 0
local MAX_EVENTS     = 300
local MAX_REPORTS    = 10

local LEVEL          = {
    [1] = { label = "ERROR", color = Color(255, 80, 80) },
    [2] = { label = "WARN", color = Color(255, 175, 60) },
    [3] = { label = "INFO", color = Color(90, 180, 255) },
    [4] = { label = "VERBOSE", color = Color(165, 165, 165) },
}
local FONT, FONT_SM  = "RareloadBody", "RareloadSmall"
local CAT            = Color(120, 200, 255)
local KEY            = Color(150, 150, 160)
local VAL            = Color(210, 210, 215)
local WHITE          = Color(230, 230, 235)
local STEP_COL       = {
    ok = Color(110, 230, 140),
    fail = Color(255, 90, 90),
    start = Color(120, 200, 255),
    warn = Color(
        255, 180, 70)
}
local STEP_ICON      = { ok = "✓", fail = "✗", start = "⚡", warn = "!" }

-- Restore / save toast: a self-dismissing, animated card for the LAST action.
local TOAST_W        = 384   -- card width
local TOAST_IN       = 0.5   -- slide/fade-in duration
local TOAST_OUT      = 0.55  -- slide/fade-out duration
local TOAST_STAGGER  = 0.045 -- per-step reveal delay
local TOAST_MAX_ROWS = 7     -- steps shown before the list auto-scrolls
local TOAST_ROW_H    = 21
local function easeOutCubic(t)
    t = t - 1; return t * t * t + 1
end
local function easeInCubic(t) return t * t * t end
-- Accent by category then success. Save = cyan, restore = green, failure = red.
local function toastAccent(r)
    if not r.success then return Color(240, 104, 104) end
    if r.category == "save" then return Color(90, 180, 255) end
    return Color(96, 214, 138)
end

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
    local r = {
        category = net.ReadString(),
        success = net.ReadBool(),
        elapsed = net.ReadString(),
        title = net
            .ReadString()
    }
    r.subtitle = net.ReadString()
    local n = net.ReadUInt(6)
    r.steps = {}
    for _ = 1, n do
        r.steps[#r.steps + 1] = { status = net.ReadString(), title = net.ReadString(), detail = net.ReadString() }
    end
    r.at = CurTime()
    HUD.reports[#HUD.reports + 1] = r
    while #HUD.reports > MAX_REPORTS do table.remove(HUD.reports, 1) end
    -- The restore toast only appears while debug is enabled; a fresh report
    -- (re)starts its intro animation so only the latest restore is shown.
    if RARELOAD.GetClientDebugEnabled and RARELOAD.GetClientDebugEnabled() then
        HUD.toast = { r = r, t0 = CurTime() }
    end
end)

local function requestSync()
    net.Start("RareloadDebugSync")
    net.SendToServer()
end

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

local function drawToast()
    local t = HUD.toast
    if not t or not t.r then return end
    if not (RARELOAD.GetClientDebugEnabled and RARELOAD.GetClientDebugEnabled()) then
        HUD.toast = nil; return
    end

    local r     = t.r
    local steps = r.steps or {}
    -- Base duration comes from the "Toast Duration" parameter; failures linger a
    -- bit longer, and overflowing lists get extra time so auto-scroll can finish.
    local base  = (RARELOAD.GetTunable and tonumber(RARELOAD.GetTunable("toast_hold_time"))) or 6
    local hold  = base + (r.success and 0 or 2) + math.max(0, #steps - TOAST_MAX_ROWS) * 0.4
    local life  = TOAST_IN + hold + TOAST_OUT
    local lt    = CurTime() - t.t0
    if lt >= life then
        HUD.toast = nil; return
    end

    -- Phase → alpha (0..1), slide (0 rest .. 1 fully off-screen), prog (drain bar).
    local alpha, slide, prog
    if lt < TOAST_IN then
        local p = easeOutCubic(lt / TOAST_IN)
        alpha, slide, prog = p, 1 - p, 1
    elseif lt < TOAST_IN + hold then
        alpha, slide, prog = 1, 0, 1 - (lt - TOAST_IN) / hold
    else
        local q = easeInCubic((lt - TOAST_IN - hold) / TOAST_OUT)
        alpha, slide, prog = 1 - q, q, 0
    end
    if alpha <= 0.01 then return end

    local rowH     = TOAST_ROW_H
    local headH    = 66
    local footH    = 16
    local w        = TOAST_W
    local contentH = #steps * rowH
    local viewH    = math.min(contentH, TOAST_MAX_ROWS * rowH)
    local scrollR  = math.max(0, contentH - viewH)
    local h        = headH + viewH + footH
    local margin   = 20
    local restX    = ScrW() - w - margin
    local x        = restX + slide * (w + margin + 30)
    local y        = 96

    local function A(c, mul)
        return Color(c.r, c.g, c.b, math.Clamp((c.a or 255) * alpha * (mul or 1), 0, 255))
    end

    local accent = toastAccent(r)

    -- Drop shadow, card body, top accent strip.
    draw.RoundedBox(14, x + 3, y + 8, w, h, Color(0, 0, 0, 110 * alpha))
    draw.RoundedBox(14, x, y, w, h, A(Color(22, 24, 30), 0.98))
    draw.RoundedBoxEx(14, x, y, w, 4, A(accent), true, true, false, false)
    -- Moving shimmer that sweeps the accent strip.
    local shimmer = (CurTime() * 150) % (w + 120) - 60
    render.SetScissorRect(x, y, x + w, y + 4, true)
    draw.RoundedBox(0, x + shimmer, y, 60, 4, A(Color(255, 255, 255), 0.18))
    render.SetScissorRect(0, 0, 0, 0, false)

    -- Header: icon pill, title, category chip + count, status · elapsed.
    draw.RoundedBox(10, x + 16, y + 17, 34, 34, A(accent, 0.16))
    draw.SimpleText(r.success and "✓" or "✗", "RareloadHeading", x + 33, y + 34, A(accent),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    draw.SimpleText(r.title ~= "" and r.title or r.category:upper(), "RareloadHeading", x + 60, y + 14, A(WHITE))
    local status = (r.success and "SUCCESS" or "FAILURE") .. "  ·  " .. r.elapsed
        .. "  ·  " .. #steps .. " step" .. (#steps == 1 and "" or "s")
    draw.SimpleText(status, FONT_SM, x + 62, y + 43, A(accent))

    -- Category chip, right-aligned in the header.
    local chip = (r.category or ""):upper()
    if chip ~= "" then
        surface.SetFont(FONT_SM)
        local cw = surface.GetTextSize(chip) + 18
        draw.RoundedBox(9, x + w - cw - 14, y + 18, cw, 18, A(accent, 0.18))
        draw.SimpleText(chip, FONT_SM, x + w - 14 - cw / 2, y + 27, A(accent), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    -- Subtitle (map / coords) under the title when present.
    if r.subtitle and r.subtitle ~= "" then
        surface.SetFont("RareloadHeading")
        local tw = surface.GetTextSize(r.title ~= "" and r.title or r.category:upper())
        draw.SimpleText(r.subtitle, FONT_SM, x + 64 + tw + 10, y + 22, A(KEY))
    end

    -- Auto-scroll offset: pause, glide to bottom, pause, glide back — during hold.
    local scrollOff = 0
    if scrollR > 0 then
        local visT   = math.max(0, lt - TOAST_IN)
        local travel = scrollR / 26 -- seconds edge-to-edge
        local pause  = 1.0
        local period = 2 * (travel + pause)
        local ph     = visT % period
        if ph < pause then
            scrollOff = 0
        elseif ph < pause + travel then
            scrollOff = (ph - pause) / travel * scrollR
        elseif ph < 2 * pause + travel then
            scrollOff = scrollR
        else
            scrollOff = scrollR - (ph - 2 * pause - travel) / travel * scrollR
        end
    end

    -- Steps, clipped to the scroll viewport, each easing in with a stagger.
    local vpY = y + headH
    render.SetScissorRect(x, vpY, x + w, vpY + viewH, true)
    for i, st in ipairs(steps) do
        local ry       = vpY - scrollOff + (i - 1) * rowH
        local appearAt = TOAST_IN + (i - 1) * TOAST_STAGGER
        local sp       = easeOutCubic(math.Clamp((lt - appearAt) / 0.22, 0, 1))
        if sp > 0.01 and ry > vpY - rowH and ry < vpY + viewH then
            local col  = STEP_COL[st.status] or Color(180, 180, 185)
            local icon = STEP_ICON[st.status] or "•"
            local sx   = x + 18 + (1 - sp) * 14
            draw.SimpleText(icon, FONT_SM, sx, ry, A(col, sp))
            draw.SimpleText(st.title .. (st.detail ~= "" and ("  —  " .. st.detail) or ""),
                FONT_SM, sx + 18, ry, A(st.status == "ok" and WHITE or col, sp))
        end
    end
    render.SetScissorRect(0, 0, 0, 0, false)

    -- Scroll thumb on the right edge of the viewport when scrolling.
    if scrollR > 0 then
        local thumbH = math.max(16, viewH * (viewH / contentH))
        local thumbY = vpY + (viewH - thumbH) * (scrollOff / scrollR)
        draw.RoundedBox(2, x + w - 7, vpY, 3, viewH, A(Color(255, 255, 255), 0.06))
        draw.RoundedBox(2, x + w - 7, thumbY, 3, thumbH, A(accent, 0.55))
    end

    -- Auto-dismiss progress bar.
    local barY, barW = y + h - 9, w - 28
    draw.RoundedBox(2, x + 14, barY, barW, 3, A(Color(255, 255, 255), 0.08))
    draw.RoundedBox(2, x + 14, barY, barW * math.Clamp(prog, 0, 1), 3, A(accent, 0.7))
end

hook.Add("HUDPaint", "RareloadDebugHUD", function()
    -- The restore toast is independent of the debug overlay: it shows the last
    -- respawn whenever debug is enabled, then dismisses itself.
    drawToast()

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
end)

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
        else
            notify("Levels: ERROR, WARN, INFO, VERBOSE")
        end
    elseif sub == "diag" then
        net.Start("RareloadDebugDiag")
        net.SendToServer(); notify("Diagnostics requested")
    elseif sub == "filter" then
        HUD.filter = (args[2] and args[2] ~= "" and args[2]:lower()) or nil
        notify(HUD.filter and ("Filtering: " .. HUD.filter) or "Filter cleared")
    elseif sub == "dump" then
        for _, ev in ipairs(HUD.events) do
            print(string.format("[%s][%s] %s", ev.category:upper(), (LEVEL[ev.level] or LEVEL[3]).label, eventLine(ev)))
        end
        notify("Dumped " .. #HUD.events .. " events to console")
    elseif sub == "clear" then
        HUD.events, HUD.bySeq, HUD.reports, HUD.toast = {}, {}, {}, nil
        notify("Cleared")
    else
        notify("rareload_debug [hud|panel|on|off|level <L>|diag|filter <cat>|dump|clear]")
    end
end, nil, "Rareload debug: overlay, interactive panel, filters, diagnostics.")
