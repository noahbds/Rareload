-- Rareload debug HUD (v2): live in-world event stream + session/respawn report
-- cards. This is the visible half of the new debug system.
if not CLIENT then return end

RARELOAD = RARELOAD or {}
RARELOAD.DebugHUD = RARELOAD.DebugHUD or {}
local HUD = RARELOAD.DebugHUD

HUD.visible = HUD.visible or false
HUD.filter = HUD.filter or nil -- category filter, or nil for all
HUD.events = HUD.events or {}   -- client ring, oldest first
HUD.report = HUD.report or nil  -- current session/respawn card
local MAX_EVENTS = 200
local SHOW_LINES = 18
local EVENT_TTL = 14            -- seconds a line stays fully visible before fading
local REPORT_TTL = 9

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

--------------------------------------------------------------------------------
-- Receive events / reports
--------------------------------------------------------------------------------
net.Receive("RareloadDebugEvent", function()
    local ev = { category = net.ReadString(), level = net.ReadUInt(3) }
    ev.message = net.ReadString()
    local n = net.ReadUInt(6)
    if n > 0 then
        ev.data = {}
        for _ = 1, n do
            ev.data[#ev.data + 1] = { net.ReadString(), net.ReadString() }
        end
    end
    ev.at = CurTime()
    HUD.events[#HUD.events + 1] = ev
    while #HUD.events > MAX_EVENTS do table.remove(HUD.events, 1) end
end)

net.Receive("RareloadDebugReport", function()
    local r = { category = net.ReadString(), success = net.ReadBool(), elapsed = net.ReadString(), title = net.ReadString() }
    local n = net.ReadUInt(6)
    r.steps = {}
    for _ = 1, n do
        r.steps[#r.steps + 1] = { status = net.ReadString(), title = net.ReadString(), detail = net.ReadString() }
    end
    r.at = CurTime()
    HUD.report = r
end)

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------
local STEP_COL = { ok = Color(110, 230, 140), fail = Color(255, 90, 90), start = Color(120, 200, 255), warn = Color(255, 180, 70) }

local function drawStream()
    if not HUD.visible then return end
    surface.SetFont(FONT_SM)
    local x, y = 16, 90
    local now = CurTime()

    -- header
    draw.SimpleText("RARELOAD DEBUG", FONT_SM, x, y - 16, Color(120, 200, 255, 220))
    if HUD.filter then
        draw.SimpleText("[" .. HUD.filter .. "]", FONT_SM, x + 120, y - 16, Color(255, 200, 100, 220))
    end

    local shown = {}
    for i = #HUD.events, 1, -1 do
        local ev = HUD.events[i]
        if not HUD.filter or ev.category == HUD.filter then
            shown[#shown + 1] = ev
            if #shown >= SHOW_LINES then break end
        end
    end

    -- draw oldest of the shown window first (top) to newest (bottom)
    for i = #shown, 1, -1 do
        local ev = shown[i]
        local age = now - (ev.at or now)
        local a = 255
        if age > EVENT_TTL then a = math.max(0, 255 - (age - EVENT_TTL) * 120) end
        if a > 4 then
            local lv = LEVEL[ev.level] or LEVEL[3]
            local tag = "[" .. ev.category:upper() .. "] "
            draw.SimpleText(tag, FONT_SM, x, y, ColorAlpha(CAT, a))
            local tagW = surface.GetTextSize(tag)
            draw.SimpleText(ev.message, FONT_SM, x + tagW, y, ColorAlpha(lv.color, a))
            y = y + 15
            if ev.data then
                for _, kv in ipairs(ev.data) do
                    local label = (kv[1] ~= "" and (kv[1] .. " = ") or "") .. kv[2]
                    draw.SimpleText("   " .. label, FONT_SM, x, y, ColorAlpha(kv[1] ~= "" and KEY or VAL, a))
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

local function drawReport()
    local r = HUD.report
    if not r then return end
    local age = CurTime() - r.at
    if age > REPORT_TTL then HUD.report = nil; return end
    local a = 255
    if age > REPORT_TTL - 1.5 then a = math.max(0, 255 - (age - (REPORT_TTL - 1.5)) * 170) end

    local w = 420
    local rowH = 18
    local h = 60 + (#r.steps * rowH)
    local x = ScrW() - w - 24
    local y = 120

    draw.RoundedBox(8, x, y, w, h, Color(20, 22, 28, math.min(230, a)))
    local barCol = r.success and Color(90, 200, 120) or Color(230, 90, 90)
    draw.RoundedBoxEx(8, x, y, w, 6, ColorAlpha(barCol, a), true, true, false, false)

    local title = (r.title ~= "" and r.title or r.category:upper())
    draw.SimpleText(title, "RareloadHeading", x + 16, y + 14, ColorAlpha(WHITE, a))
    draw.SimpleText((r.success and "SUCCESS" or "FAILURE") .. "  ·  " .. r.elapsed,
        FONT_SM, x + 16, y + 40, ColorAlpha(barCol, a))

    local ry = y + 60
    for _, st in ipairs(r.steps) do
        local col = STEP_COL[st.status] or Color(180, 180, 185)
        local icon = ({ ok = "✓", fail = "✗", start = "⚡", warn = "!" })[st.status] or "•"
        local line = icon .. " " .. st.title .. (st.detail ~= "" and ("  —  " .. st.detail) or "")
        draw.SimpleText(line, FONT_SM, x + 16, ry, ColorAlpha(col, a))
        ry = ry + rowH
    end
end

hook.Add("HUDPaint", "RareloadDebugHUD", function()
    drawStream()
    drawReport()
end)

--------------------------------------------------------------------------------
-- Client command: rareload_debug [hud|on|off|toggle|level <L>|filter <cat>|dump|clear]
--------------------------------------------------------------------------------
local function notify(msg) chat.AddText(Color(120, 200, 255), "[Rareload] ", color_white, msg) end

concommand.Add("rareload_debug", function(_, _, args)
    local sub = (args[1] or "hud"):lower()

    if sub == "hud" then
        HUD.visible = not HUD.visible
        if HUD.visible then net.Start("RareloadDebugSync"); net.SendToServer() end
        notify("HUD " .. (HUD.visible and "shown" or "hidden"))
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
    elseif sub == "filter" then
        HUD.filter = (args[2] and args[2] ~= "" and args[2]:lower()) or nil
        notify(HUD.filter and ("Filtering category: " .. HUD.filter) or "Filter cleared")
    elseif sub == "dump" then
        for _, ev in ipairs(HUD.events) do
            print(string.format("[%s][%s] %s", ev.category:upper(), (LEVEL[ev.level] or LEVEL[3]).label, ev.message))
        end
        notify("Dumped " .. #HUD.events .. " events to console")
    elseif sub == "clear" then
        HUD.events = {}
        HUD.report = nil
        notify("Cleared")
    else
        notify("Usage: rareload_debug [hud|on|off|toggle|level <L>|filter <cat>|dump|clear]")
    end
end, nil, "Rareload debug: HUD overlay, per-player toggle, level, filter, dump.")
