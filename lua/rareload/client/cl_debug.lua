-- Debug report cards sent to admins while the `debug` setting is on (REWRITE_PLAN.md §22, F41):
-- printed to the console and shown as cards on the right of the screen for `toastHold` seconds.

local STATUS = { ok = "ok", warn = "warn", fail = "bad" }
local MAX_CARDS, MAX_STEPS = 4, 12

local cards = {}

RARELOAD.Net.On("debug", function(r)
    local C = RARELOAD.UI.C
    MsgC(C.accent, "[Rareload] ", color_white, string.format("%s: %s (%s ms)\n", r.title, r.player, r.ms))
    for _, s in ipairs(r.steps or {}) do
        MsgC(C[STATUS[s.status]] or color_white, "    " .. s.status .. " ", color_white, s.title .. "  " .. s.detail .. "\n")
    end
    table.insert(cards, 1, { r = r, t = RealTime() })
    cards[MAX_CARDS + 1] = nil
end)

hook.Add("HUDPaint", "Rareload.Debug.Cards", function()
    if #cards == 0 then return end
    local C, sc = RARELOAD.UI.C, RARELOAD.UI.sc
    local hold = RARELOAD.Get(nil, "toastHold")
    local w, line, pad = sc(360), sc(18), sc(8)
    local x, y = ScrW() - w - sc(16), sc(120)

    for i = #cards, 1, -1 do
        if RealTime() - cards[i].t > hold then table.remove(cards, i) end
    end
    for _, card in ipairs(cards) do
        local r = card.r
        local alpha = math.Clamp((hold - (RealTime() - card.t)) / 0.5, 0, 1) * 255
        local steps = math.min(#(r.steps or {}), MAX_STEPS)
        local h = pad * 2 + line * (steps + 1)
        draw.RoundedBox(6, x, y, w, h, ColorAlpha(C.bg, alpha * 0.9))
        surface.SetDrawColor(ColorAlpha(C.accent, alpha))
        surface.DrawRect(x, y, sc(3), h)
        draw.SimpleText(string.format("%s: %s (%s ms)", r.title, r.player, r.ms), "Rareload.Heading", x + pad * 2, y + pad,
            ColorAlpha(C.text, alpha))
        for j = 1, steps do
            local s = r.steps[j]
            local sy = y + pad + line * j
            draw.SimpleText(s.status, "Rareload.Small", x + pad * 2, sy, ColorAlpha(C[STATUS[s.status]] or C.text, alpha))
            draw.SimpleText(s.title .. "  " .. s.detail, "Rareload.Small", x + pad * 2 + sc(40), sy, ColorAlpha(C.text2, alpha))
        end
        y = y + h + sc(6)
    end
end)
