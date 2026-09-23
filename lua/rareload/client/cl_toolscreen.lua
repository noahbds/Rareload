-- The Rareload tool's screen (REWRITE_PLAN.md §21.4, F36): status, a scrolling list of the player's
-- settings, the autosave bar, and an animated icon after the reload key or a denied use. Same look as v4.

RARELOAD.ToolScreen = RARELOAD.ToolScreen or {}
local Screen = RARELOAD.ToolScreen
local L = RARELOAD.L

local GRADIENT = Material("vgui/gradient-u")
local HEADER, TOP, ROW, BAR = 50, 100, 28, 20

-- Settings shown on the screen; values are the player's effective ones.
local FEATURES = {
    { key = "antiStuck" }, { key = "autoSave" }, { key = "skipRestoreOnDeath" },
    { key = "keepInventory" }, { key = "globalInventory" }, { key = "keepAmmo" }, { key = "keepHealth" },
    { key = "keepStates" }, { key = "keepAppearance" }, { key = "keepEntities" }, { key = "keepNPCs" },
    { key = "keepVehicles" }, { key = "deathCleanupMode" }, { key = "debug" },
    { key = "autoSaveInterval", unit = "s" }, { key = "autoSaveAngleThreshold", unit = "°" }, { key = "historySize" },
}

-- Overlay per toast: icon kind and its text.
local OVERLAYS = {
    ["toast.reload.restored"] = { icon = "check", text = "screen.restored" },
    ["toast.reload.previous"] = { icon = "check", text = "screen.previous" },
    ["toast.reload.empty"] = { icon = "warn", text = "screen.no_saves" },
    ["toast.reload.no_previous"] = { icon = "skip", text = "screen.no_previous" },
    ["toast.tool_denied"] = { icon = "lock", text = "screen.no_permission" },
}
local OVERLAY_TIME = 1.8

local state = { scroll = 0, dir = 1, pauseUntil = 0 }

hook.Add("RareloadToast", "Rareload.ToolScreen", function(t)
    local o = OVERLAYS[t.key]
    if o then state.overlay = { icon = o.icon, text = o.text, start = RealTime() } end
end)

hook.Add("RareloadStateChanged", "Rareload.ToolScreen", function(what)
    if what == "autosave" then state.autosavedAt = RealTime() end
end)

-- Drawing helpers ---------------------------------------------------------------------------------

local function circle(x, y, r, col)
    local poly = {}
    for i = 0, 31 do
        local a = i / 32 * math.pi * 2
        poly[#poly + 1] = { x = x + math.cos(a) * r, y = y + math.sin(a) * r }
    end
    draw.NoTexture()
    surface.SetDrawColor(col)
    surface.DrawPoly(poly)
end

local function thickLine(x1, y1, x2, y2, t)
    local a = math.atan2(y2 - y1, x2 - x1)
    local dx, dy = math.sin(a) * t / 2, -math.cos(a) * t / 2
    surface.DrawPoly({ { x = x1 + dx, y = y1 + dy }, { x = x2 + dx, y = y2 + dy },
        { x = x2 - dx, y = y2 - dy }, { x = x1 - dx, y = y1 - dy } })
end

-- Scales a label down to fit `maxW`, so long translations stay readable instead of overlapping.
local function fittedText(text, x, y, maxW, col)
    surface.SetFont("Rareload.Screen")
    local tw = surface.GetTextSize(text)
    if tw <= maxW then
        return draw.SimpleText(text, "Rareload.Screen", x, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local m = Matrix()
    m:Translate(Vector(x, y, 0))
    m:Scale(Vector(maxW / tw, maxW / tw, 1))
    m:Translate(Vector(-x, -y, 0))
    cam.PushModelMatrix(m, true)
    draw.SimpleText(text, "Rareload.Screen", x, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    cam.PopModelMatrix()
end

local function easeOutBack(t)
    t = math.Clamp(t, 0, 1) - 1
    return 1 + 2.70158 * t ^ 3 + 1.70158 * t ^ 2
end

local ICON_COLORS = { check = "ok", warn = "warn", skip = "accent", lock = "warn" }

local function drawIcon(kind, x, y, size, alpha, p)
    local C = RARELOAD.UI.C
    if kind ~= "check" and p < 0.55 then x = x + math.sin(p / 0.55 * math.pi * 6) * size * 0.08 * (1 - p / 0.55) end
    local base = C[ICON_COLORS[kind]]
    local r = size * easeOutBack(p / 0.55)
    circle(x, y, r + 4, ColorAlpha(base, alpha * 0.3))
    circle(x, y, r, ColorAlpha(base, alpha))
    if p < 0.3 then return end

    local q = math.min(1, (p - 0.3) / 0.6)
    local t = math.max(3, size * 0.14)
    surface.SetDrawColor(255, 255, 255, alpha)
    draw.NoTexture()
    if kind == "check" then
        local ax, ay, bx, by, cx, cy = x - size * 0.35, y, x - size * 0.1, y + size * 0.28, x + size * 0.38, y - size * 0.3
        thickLine(ax, ay, Lerp(math.min(1, q * 2), ax, bx), Lerp(math.min(1, q * 2), ay, by), t)
        if q > 0.5 then thickLine(bx, by, Lerp((q - 0.5) * 2, bx, cx), Lerp((q - 0.5) * 2, by, cy), t) end
    elseif kind == "warn" then
        local s = size * 0.5 * q
        surface.DrawPoly({ { x = x, y = y - s }, { x = x + s, y = y + s * 0.75 }, { x = x - s, y = y + s * 0.75 } })
        surface.SetDrawColor(ColorAlpha(base, alpha))
        surface.DrawRect(x - t / 3, y - s * 0.35, t * 2 / 3, s * 0.6)
        surface.DrawRect(x - t / 3, y + s * 0.4, t * 2 / 3, t * 2 / 3)
    elseif kind == "skip" then
        local s = size * 0.45
        surface.DrawRect(x - s * 0.72, y - s * 0.5, s * 0.22, s)
        local slide = (1 - q) * s * 0.5
        surface.DrawPoly({ { x = x - s * 0.45 + slide, y = y }, { x = x + s * 0.45 + slide, y = y - s * 0.55 },
            { x = x + s * 0.45 + slide, y = y + s * 0.55 } })
    elseif kind == "lock" then
        local bw, bh = size * 0.55, size * 0.4 * q
        surface.DrawRect(x - bw / 2, y, bw, bh)
        local rr = bw * 0.35
        for i = 0, 9 do
            local a1, a2 = math.pi + i / 10 * math.pi, math.pi + (i + 1) / 10 * math.pi
            thickLine(x + math.cos(a1) * rr, y + math.sin(a1) * rr, x + math.cos(a2) * rr, y + math.sin(a2) * rr, t * 0.7)
        end
        surface.DrawRect(x - rr - t * 0.35, y - 1, t * 0.7, 3)
        surface.DrawRect(x + rr - t * 0.35, y - 1, t * 0.7, 3)
    end
end

local function drawOverlay(w, h)
    local o = state.overlay
    local elapsed = RealTime() - o.start
    if elapsed > OVERLAY_TIME then
        state.overlay = nil
        return
    end
    local p = elapsed / OVERLAY_TIME
    local alpha = 255 * math.Clamp((1 - p) / 0.25, 0, 1)
    surface.SetDrawColor(0, 0, 0, alpha * 0.75)
    surface.DrawRect(0, 0, w, h)
    drawIcon(o.icon, w / 2, h / 2 - 20, 50, alpha, math.min(1, p * 2.2))
    draw.SimpleText(L(o.text), "Rareload.Screen", w / 2, h / 2 + 55, Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function valueText(f)
    local def = RARELOAD.Settings[f.key]
    local v = RARELOAD.Get(LocalPlayer(), f.key)
    if def.type == "bool" then return v and L("ui.on") or L("ui.off"), v end
    if def.type == "enum" then return L("setting." .. f.key .. "." .. v), v ~= def.values[1] end
    return string.format(def.type == "float" and "%.1f" or "%d", v) .. (f.unit or ""), nil
end

-- The autosave bar: time since the last autosave against the interval, then "waiting for a change".
local function drawAutosave(w, h)
    local C = RARELOAD.UI.C
    local y = h - BAR - 4
    draw.RoundedBox(8, 8, y, w - 16, BAR, Color(25, 25, 30))
    local text, col, frac
    if state.autosavedAt and RealTime() - state.autosavedAt < 1.5 then
        text, col, frac = L("screen.autosaved"), C.ok, 1
    else
        local last = RARELOAD.State.lastAutosave
        local interval = RARELOAD.Get(LocalPlayer(), "autoSaveInterval")
        frac = last and math.Clamp((CurTime() - last) / interval, 0, 1) or 1
        if frac < 1 then
            text = L("screen.next_in", math.ceil(interval - (CurTime() - last)))
            col = frac < 0.3 and C.ok or frac < 0.7 and C.warn or C.bad
        else
            text, col = L("screen.waiting"), C.accent
        end
    end
    if frac > 0 then draw.RoundedBox(8, 10, y + 2, (w - 20) * frac, BAR - 4, col) end
    draw.SimpleText(text, "Rareload.Screen", w / 2 + 1, y + BAR / 2 + 1, Color(0, 0, 0, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(text, "Rareload.Screen", w / 2, y + BAR / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- The list scrolls down, pauses, scrolls back up, and pauses again.
local function updateScroll(maxScroll)
    if maxScroll <= 0 then state.scroll = 0 return end
    if RealTime() < state.pauseUntil then return end
    state.scroll = math.Clamp(state.scroll + state.dir * 15 * FrameTime(), 0, maxScroll)
    if state.scroll == maxScroll or state.scroll == 0 then
        state.dir = state.scroll == 0 and 1 or -1
        state.pauseUntil = RealTime() + 4
    end
end

-- Called from TOOL:DrawToolScreen, inside the tool's own cam.Start2D.
function Screen.Draw(w, h)
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local C = RARELOAD.UI.C

    surface.SetDrawColor(C.bg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(C.accent)
    surface.DrawRect(0, 0, w, HEADER)
    surface.SetMaterial(GRADIENT)
    surface.SetDrawColor(255, 255, 255, 35)
    surface.DrawTexturedRect(0, 0, w, HEADER)
    draw.SimpleText("RARELOAD", "Rareload.ScreenTitle", w / 2, HEADER / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local enabled = RARELOAD.Get(lp, "enabled")
    draw.RoundedBox(8, 10, 60, w - 20, 30, enabled and C.ok or C.bad)
    draw.SimpleText(enabled and L("screen.enabled") or L("screen.disabled"), "Rareload.Screen", w / 2, 75,
        enabled and Color(15, 15, 15) or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local autosave = RARELOAD.Get(lp, "autoSave")
    local bottom = h - (autosave and BAR + 8 or 22)
    updateScroll(#FEATURES * ROW - (bottom - TOP))
    render.SetScissorRect(0, TOP, w, bottom, true)
    for i, f in ipairs(FEATURES) do
        local y = TOP + (i - 1) * ROW - state.scroll
        if y + ROW > TOP and y < bottom then
            if i % 2 == 0 then
                surface.SetDrawColor(255, 255, 255, 6)
                surface.DrawRect(8, y - 2, w - 16, ROW)
            end
            local text, on = valueText(f)
            local dot = on == nil and C.accent or on and C.ok or C.bad
            draw.RoundedBox(10, 12, y + 2, 20, 16, dot)
            surface.SetFont("Rareload.Screen")
            local vw = surface.GetTextSize(text)
            fittedText(L("setting." .. f.key), 40, y + 10, w - 15 - vw - 8 - 40, color_white)
            draw.SimpleText(text, "Rareload.Screen", w - 15, y + 10, on == nil and color_white or dot, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    render.SetScissorRect(0, 0, 0, 0, false)

    if autosave then drawAutosave(w, h) end
    if state.overlay then
        drawOverlay(w, h)
    elseif not autosave then
        draw.SimpleText("v" .. RARELOAD.version, "Rareload.Screen", w - 10, h - 4, Color(150, 150, 150, 180), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
end
