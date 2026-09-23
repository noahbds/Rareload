-- Debug report cards sent to admins while the `debug` setting is on (REWRITE_PLAN.md §22, F41):
-- printed to the console and shown as an animated card for the latest save or restore. The card
-- slides in, reveals its steps one by one, scrolls when there are many, and slides out after
-- `toastHold` seconds. Blue = save, green = restore, red = a step failed.

local STATUS = { ok = "ok", warn = "warn", fail = "bad" }
local IN, OUT, STAGGER, ROWS = 0.45, 0.5, 0.045, 8

local card

RARELOAD.Net.On("debug", function(r)
    local C = RARELOAD.UI.C
    MsgC(C.accent, "[Rareload] ", color_white, string.format("%s: %s (%s ms)\n", r.title, r.player, r.ms))
    for _, s in ipairs(r.steps or {}) do
        MsgC(C[STATUS[s.status]] or color_white, "    " .. s.status .. " ", color_white, s.title .. "  " .. s.detail .. "\n")
    end
    card = { r = r, t0 = RealTime() }
end)

local function ease(t) t = t - 1 return t * t * t + 1 end

local function statusMark(status, x, y, s, col)
    surface.SetDrawColor(col)
    if status == "ok" then
        surface.DrawLine(x, y + s / 2, x + s / 3, y + s)
        surface.DrawLine(x + s / 3, y + s, x + s, y)
    elseif status == "fail" then
        surface.DrawLine(x, y, x + s, y + s)
        surface.DrawLine(x, y + s, x + s, y)
    else
        surface.DrawRect(x + s / 2 - 1, y, 2, s * 0.65)
        surface.DrawRect(x + s / 2 - 1, y + s * 0.8, 2, 2)
    end
end

hook.Add("HUDPaint", "Rareload.Debug.Card", function()
    if not card then return end
    local UI = RARELOAD.UI
    local C, sc = UI.C, UI.sc
    local r, age = card.r, RealTime() - card.t0
    local hold = RARELOAD.Get(nil, "toastHold")
    if age > hold + OUT then card = nil return end

    local accent = not r.ok and C.bad or r.kind == "save" and C.accent or C.ok
    local steps = r.steps or {}
    local rowH, w = sc(21), sc(390)
    local visible = math.min(#steps, ROWS)
    local h = sc(62) + visible * rowH + sc(10)
    local slide = age < IN and 1 - ease(age / IN) or age > hold and ease((age - hold) / OUT) or 0
    local x, y = ScrW() - w - sc(16) + slide * (w + sc(30)), sc(110)
    local alpha = 1 - (age > hold and (age - hold) / OUT or 0)
    surface.SetAlphaMultiplier(math.Clamp(alpha, 0, 1))

    draw.RoundedBox(sc(10), x, y, w, h, ColorAlpha(C.bgDark, 238))
    draw.RoundedBoxEx(sc(10), x, y, sc(5), h, accent, true, false, true, false)
    statusMark(r.ok and "ok" or "fail", x + sc(18), y + sc(14), sc(14), accent)
    draw.SimpleText(r.title, "Rareload.H2", x + sc(42), y + sc(10), C.text)
    draw.SimpleText(r.player .. "  ·  " .. r.ms .. " ms", "Rareload.Small", x + sc(42), y + sc(34), C.text3)

    -- Steps appear one after the other; with many steps the list scrolls to show the latest ones.
    local shown = math.min(#steps, math.floor(math.max(age - IN * 0.5, 0) / STAGGER))
    local first = math.max(1, shown - ROWS + 1)
    local ry = y + sc(60)
    for i = first, shown do
        local s = steps[i]
        local col = C[STATUS[s.status]] or C.text
        statusMark(s.status, x + sc(18), ry + sc(5), sc(10), col)
        draw.SimpleText(s.title, "Rareload.BodyB", x + sc(36), ry + rowH / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont("Rareload.BodyB")
        local tw = surface.GetTextSize(s.title)
        draw.SimpleText(UI.Clip(s.detail, "Rareload.Small", w - sc(48) - tw), "Rareload.Small", x + sc(42) + tw, ry + rowH / 2,
            C.text2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        ry = ry + rowH
    end
    surface.SetAlphaMultiplier(1)
end)
