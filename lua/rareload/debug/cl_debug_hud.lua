-- Rareload debug client: the restore/save notification toast.
-- The old on-screen event overlay and interactive DFrame panel were removed —
-- GMod's own developer tools cover live console logging. All that remains here is
-- the animated toast card that summarizes the LAST respawn restore or save.
if not CLIENT then return end

RARELOAD          = RARELOAD or {}
RARELOAD.DebugHUD = RARELOAD.DebugHUD or {}
local HUD         = RARELOAD.DebugHUD

HUD.toast         = HUD.toast or nil -- { r = report, t0 = start } for the animated card

local FONT_SM     = "RareloadSmall"
local KEY         = Color(150, 150, 160)
local WHITE       = Color(230, 230, 235)
local STEP_COL    = {
    ok    = Color(110, 230, 140),
    fail  = Color(255, 90, 90),
    start = Color(120, 200, 255),
    warn  = Color(255, 180, 70),
}
local STEP_ICON   = { ok = "✓", fail = "✗", start = "⚡", warn = "!" }

-- Restore / save toast styling.
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
net.Receive("RareloadDebugReport", function()
    local r = {
        category = net.ReadString(),
        success  = net.ReadBool(),
        elapsed  = net.ReadString(),
        title    = net.ReadString(),
    }
    r.subtitle = net.ReadString()
    local n = net.ReadUInt(6)
    r.steps = {}
    for _ = 1, n do
        r.steps[#r.steps + 1] = { status = net.ReadString(), title = net.ReadString(), detail = net.ReadString() }
    end
    -- The toast only appears while debug is enabled; a fresh report restarts its
    -- intro animation so only the latest action is shown.
    if RARELOAD.GetClientDebugEnabled and RARELOAD.GetClientDebugEnabled() then
        HUD.toast = { r = r, t0 = CurTime() }
    end
end)

-- The server still streams events/status to debug-enabled players for anyone who
-- reads them via console; the overlay is gone, so we accept and discard them here
-- to avoid "unhandled net message" warnings.
net.Receive("RareloadDebugBatch", function() end)
net.Receive("RareloadDebugStatus", function() end)

--------------------------------------------------------------------------------
-- Toast rendering
--------------------------------------------------------------------------------
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
    local L = RARELOAD.L
    local status = (r.success and L("toast.success") or L("toast.failure")) .. "  ·  " .. r.elapsed
        .. "  ·  " .. L("toast.steps", #steps)
    draw.SimpleText(status, FONT_SM, x + 62, y + 43, A(accent))

    -- Category chip, right-aligned in the header.
    local chip = (r.category or ""):upper()
    if chip ~= "" then
        surface.SetFont(FONT_SM)
        local cw = surface.GetTextSize(chip) + 18
        draw.RoundedBox(9, x + w - cw - 14, y + 18, cw, 18, A(accent, 0.18))
        draw.SimpleText(chip, FONT_SM, x + w - 14 - cw / 2, y + 27, A(accent), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    -- Subtitle (map / coords) after the title when present.
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

hook.Add("HUDPaint", "RareloadDebugHUD", drawToast)

--------------------------------------------------------------------------------
-- Command: enable/disable debug (which gates the toast + server logging).
--------------------------------------------------------------------------------
local function notify(msg) chat.AddText(Color(120, 200, 255), "[Rareload] ", color_white, msg) end

concommand.Add("rareload_debug", function(_, _, args)
    local sub = (args[1] or "toggle"):lower()
    if sub == "on" or sub == "off" or sub == "toggle" then
        local cur = RARELOAD.GetClientDebugEnabled and RARELOAD.GetClientDebugEnabled() or false
        local val = (sub == "on") or (sub == "toggle" and not cur)
        if RARELOAD.UpdatePlayerSetting then RARELOAD.UpdatePlayerSetting("debugEnabled", val) end
        notify("Debug " .. (val and "enabled" or "disabled"))
    elseif sub == "diag" then
        net.Start("RareloadDebugDiag")
        net.SendToServer()
        notify("Diagnostics requested (see server console)")
    elseif sub == "clear" then
        HUD.toast = nil
        notify("Toast cleared")
    else
        notify("rareload_debug [on|off|toggle|diag|clear]")
    end
end, nil, "Rareload debug: enable/disable debug logging and the restore/save toast.")
