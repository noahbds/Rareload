-- The Rareload tool's screen: status, a scrolling list of the player's
-- settings, the autosave bar, and an animated icon after the reload key or a denied use. Same look as v4.

RARELOAD.ToolScreen = RARELOAD.ToolScreen or {}
local Screen = RARELOAD.ToolScreen
local L = RARELOAD.L

local GRADIENT = Material("vgui/gradient-u")
local HEADER, TOP, ROW, BAR = 50, 100, 28, 20

-- Settings shown on the screen; values are the player's effective ones.
local FEATURES = {
    { key = "antiStuck" }, { key = "autoSave" }, { key = "deathChoiceAlways" },
    { key = "keepInventory" }, { key = "globalInventory" }, { key = "keepAmmo" }, { key = "keepHealth" },
    { key = "keepStates" }, { key = "keepAppearance" }, { key = "keepEntities" }, { key = "keepNPCs" },
    { key = "keepVehicles" }, { key = "deathCleanupMode" }, { key = "debug" },
    { key = "autoSaveInterval" }, { key = "autoSaveAngleThreshold" }, { key = "historySize" },
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

hook.Add("RareloadToast", "Rareload.ToolScreen", function(toast)
    local overlay = OVERLAYS[toast.key]
    if overlay then state.overlay = { icon = overlay.icon, text = overlay.text, start = RealTime() } end
end)

hook.Add("RareloadStateChanged", "Rareload.ToolScreen", function(what)
    if what == "autosave" then state.autosavedAt = RealTime() end
end)

-- Drawing helpers ---------------------------------------------------------------------------------

local function circle(centerX, centerY, radius, col)
    local poly = {}
    for i = 0, 31 do
        local angle = i / 32 * math.pi * 2
        poly[#poly + 1] = { x = centerX + math.cos(angle) * radius, y = centerY + math.sin(angle) * radius }
    end
    draw.NoTexture()
    surface.SetDrawColor(col)
    surface.DrawPoly(poly)
end

local function thickLine(x1, y1, x2, y2, thickness)
    local angle = math.atan2(y2 - y1, x2 - x1)
    local dx, dy = math.sin(angle) * thickness / 2, -math.cos(angle) * thickness / 2
    surface.DrawPoly({ { x = x1 + dx, y = y1 + dy }, { x = x2 + dx, y = y2 + dy },
        { x = x2 - dx, y = y2 - dy }, { x = x1 - dx, y = y1 - dy } })
end

-- Scales a label down to fit `maxW`, so long translations stay readable instead of overlapping.
local function fittedText(text, posX, posY, maxW, col)
    surface.SetFont("Rareload.Screen")
    local tw = surface.GetTextSize(text)
    if tw <= maxW then
        return draw.SimpleText(text, "Rareload.Screen", posX, posY, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local matrix = Matrix()
    matrix:Translate(Vector(posX, posY, 0))
    matrix:Scale(Vector(maxW / tw, maxW / tw, 1))
    matrix:Translate(Vector(-posX, -posY, 0))
    cam.PushModelMatrix(matrix, true)
    draw.SimpleText(text, "Rareload.Screen", posX, posY, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    cam.PopModelMatrix()
end

local function easeOutBack(progress)
    progress = math.Clamp(progress, 0, 1) - 1
    return 1 + 2.70158 * progress ^ 3 + 1.70158 * progress ^ 2
end

local ICON_COLORS = { check = "ok", warn = "warn", skip = "accent", lock = "warn" }

local function drawIcon(kind, centerX, centerY, size, alpha, progress)
    local C = RARELOAD.UI.C
    if kind ~= "check" and progress < 0.55 then
        local shake = progress / 0.55
        centerX = centerX + math.sin(shake * math.pi * 6) * size * 0.08 * (1 - shake)
    end
    local base = C[ICON_COLORS[kind]]
    local radius = size * easeOutBack(progress / 0.55)
    circle(centerX, centerY, radius + 4, ColorAlpha(base, alpha * 0.3))
    circle(centerX, centerY, radius, ColorAlpha(base, alpha))
    if progress < 0.3 then return end

    local markProgress = math.min(1, (progress - 0.3) / 0.6)
    local thickness = math.max(3, size * 0.14)
    surface.SetDrawColor(255, 255, 255, alpha)
    draw.NoTexture()
    if kind == "check" then
        local ax, ay, bx, by, cx, cy = centerX - size * 0.35, centerY, centerX - size * 0.1, centerY + size * 0.28,
            centerX + size * 0.38,
            centerY - size * 0.3
        thickLine(ax, ay, Lerp(math.min(1, markProgress * 2), ax, bx), Lerp(math.min(1, markProgress * 2), ay, by),
            thickness)
        if markProgress > 0.5 then thickLine(bx, by, Lerp((markProgress - 0.5) * 2, bx, cx),
            Lerp((markProgress - 0.5) * 2, by, cy), thickness) end
    elseif kind == "warn" then
        local markSize = size * 0.5 * markProgress
        surface.DrawPoly({ { x = centerX, y = centerY - markSize },
            { x = centerX + markSize, y = centerY + markSize * 0.75 },
            { x = centerX - markSize, y = centerY + markSize * 0.75 } })
        surface.SetDrawColor(ColorAlpha(base, alpha))
        surface.DrawRect(centerX - thickness / 3, centerY - markSize * 0.35, thickness * 2 / 3, markSize * 0.6)
        surface.DrawRect(centerX - thickness / 3, centerY + markSize * 0.4, thickness * 2 / 3, thickness * 2 / 3)
    elseif kind == "skip" then
        local markSize = size * 0.45
        surface.DrawRect(centerX - markSize * 0.72, centerY - markSize * 0.5, markSize * 0.22, markSize)
        local slide = (1 - markProgress) * markSize * 0.5
        surface.DrawPoly({ { x = centerX - markSize * 0.45 + slide, y = centerY },
            { x = centerX + markSize * 0.45 + slide, y = centerY - markSize * 0.55 },
            { x = centerX + markSize * 0.45 + slide, y = centerY + markSize * 0.55 } })
    elseif kind == "lock" then
        local bw, bh = size * 0.55, size * 0.4 * markProgress
        surface.DrawRect(centerX - bw / 2, centerY, bw, bh)
        local rr = bw * 0.35
        for i = 0, 9 do
            local a1, a2 = math.pi + i / 10 * math.pi, math.pi + (i + 1) / 10 * math.pi
            thickLine(centerX + math.cos(a1) * rr, centerY + math.sin(a1) * rr,
                centerX + math.cos(a2) * rr, centerY + math.sin(a2) * rr, thickness * 0.7)
        end
        surface.DrawRect(centerX - rr - thickness * 0.35, centerY - 1, thickness * 0.7, 3)
        surface.DrawRect(centerX + rr - thickness * 0.35, centerY - 1, thickness * 0.7, 3)
    end
end

local function drawOverlay(width, height)
    local overlay = state.overlay
    local elapsed = RealTime() - overlay.start
    if elapsed > OVERLAY_TIME then
        state.overlay = nil
        return
    end
    local progress = elapsed / OVERLAY_TIME
    local alpha = 255 * math.Clamp((1 - progress) / 0.25, 0, 1)
    surface.SetDrawColor(0, 0, 0, alpha * 0.75)
    surface.DrawRect(0, 0, width, height)
    drawIcon(overlay.icon, width / 2, height / 2 - 20, 50, alpha, math.min(1, progress * 2.2))
    draw.SimpleText(L(overlay.text), "Rareload.Screen", width / 2, height / 2 + 55, Color(255, 255, 255, alpha),
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
end

local function valueText(feature)
    local settingDef = RARELOAD.Settings[feature.key]
    local value = RARELOAD.Get(LocalPlayer(), feature.key)
    if settingDef.type == "bool" then return value and L("ui.on") or L("ui.off"), value end
    if settingDef.type == "enum" then return L("setting." .. feature.key .. "." .. value),
        value ~= settingDef.values[1] end
    return string.format(settingDef.type == "float" and "%.1f" or "%d", value) .. (settingDef.unit or ""), nil
end

-- The autosave bar: time since the last autosave against the interval, then "waiting for a change".
local function drawAutosave(width, height)
    local C = RARELOAD.UI.C
    local barY = height - BAR - 4
    draw.RoundedBox(8, 8, barY, width - 16, BAR, Color(25, 25, 30))
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
    if frac > 0 then draw.RoundedBox(8, 10, barY + 2, (width - 20) * frac, BAR - 4, col) end
    draw.SimpleText(text, "Rareload.Screen", width / 2 + 1, barY + BAR / 2 + 1, Color(0, 0, 0, 180), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(text, "Rareload.Screen", width / 2, barY + BAR / 2, color_white, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
end

-- The list scrolls down, pauses, scrolls back up, and pauses again.
local function updateScroll(maxScroll)
    if maxScroll <= 0 then
        state.scroll = 0
        return
    end
    if RealTime() < state.pauseUntil then return end
    state.scroll = math.Clamp(state.scroll + state.dir * 15 * FrameTime(), 0, maxScroll)
    if state.scroll == maxScroll or state.scroll == 0 then
        state.dir = state.scroll == 0 and 1 or -1
        state.pauseUntil = RealTime() + 4
    end
end

-- Called from TOOL:DrawToolScreen, inside the tool's own cam.Start2D.
function Screen.Draw(width, height)
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local C = RARELOAD.UI.C

    surface.SetDrawColor(C.bg)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(C.accent)
    surface.DrawRect(0, 0, width, HEADER)
    surface.SetMaterial(GRADIENT)
    surface.SetDrawColor(255, 255, 255, 35)
    surface.DrawTexturedRect(0, 0, width, HEADER)
    draw.SimpleText("RARELOAD", "Rareload.ScreenTitle", width / 2, HEADER / 2, color_white, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    local enabled = RARELOAD.Get(lp, "enabled")
    draw.RoundedBox(8, 10, 60, width - 20, 30, enabled and C.ok or C.bad)
    draw.SimpleText(enabled and L("screen.enabled") or L("screen.disabled"), "Rareload.Screen", width / 2, 75,
        enabled and Color(15, 15, 15) or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local autosave = RARELOAD.Get(lp, "autoSave")
    local bottom = height - (autosave and BAR + 8 or 22)
    updateScroll(#FEATURES * ROW - (bottom - TOP))
    render.SetScissorRect(0, TOP, width, bottom, true)
    for i, feature in ipairs(FEATURES) do
        local rowY = TOP + (i - 1) * ROW - state.scroll
        if rowY + ROW > TOP and rowY < bottom then
            if i % 2 == 0 then
                surface.SetDrawColor(255, 255, 255, 6)
                surface.DrawRect(8, rowY - 2, width - 16, ROW)
            end
            local text, on = valueText(feature)
            local dot = on == nil and C.accent or on and C.ok or C.bad
            draw.RoundedBox(10, 12, rowY + 2, 20, 16, dot)
            surface.SetFont("Rareload.Screen")
            local vw = surface.GetTextSize(text)
            fittedText(L("setting." .. feature.key), 40, rowY + 10, width - 15 - vw - 8 - 40, color_white)
            draw.SimpleText(text, "Rareload.Screen", width - 15, rowY + 10, on == nil and color_white or dot,
                TEXT_ALIGN_RIGHT,
                TEXT_ALIGN_CENTER)
        end
    end
    render.SetScissorRect(0, 0, 0, 0, false)

    if autosave then drawAutosave(width, height) end
    if state.overlay then
        drawOverlay(width, height)
    elseif not autosave then
        draw.SimpleText("v" .. RARELOAD.version, "Rareload.Screen", width - 10, height - 4, Color(150, 150, 150, 180),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
end
