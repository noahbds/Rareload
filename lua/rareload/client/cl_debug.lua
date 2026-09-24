-- Debug report cards sent to admins while the `debug` setting is on (REWRITE_PLAN.md §22, F41):
-- printed to the console and shown as a card for each save and restore. A card shows what happened
-- (saved, nothing changed, restored), why (tool, respawn, timeline…), the save number, the total time
-- and, for every step, its status, how long it took with a bar relative to the slowest step, and its
-- full detail (a summary, or the error). Every step is shown at once, nothing scrolls, and the card
-- stays longer when it has more to read. Autosaves get a one-line card. Up to 4 cards stack, newest on
-- top. Blue = save, green = restore, orange = a warning, red = a step failed.

local L, UI = RARELOAD.L, RARELOAD.UI
local STATUS = { ok = "ok", warn = "warn", fail = "bad" }
local IN, OUT, STAGGER, MAX_CARDS = 0.35, 0.4, 0.035, 4

local cards = {}

-- `quiet`: the host, whose console already shows the server's printout.
RARELOAD.Net.On("debug", function(r)
    local C = UI.C
    if not r.quiet then
        MsgC(C.accent, "[Rareload] ", color_white, string.format("%s: %s (%s ms)\n", r.title, r.player, r.ms))
        for _, s in ipairs(r.steps or {}) do
            MsgC(C[STATUS[s.status]] or color_white, "    " .. s.status .. " ", color_white,
                s.title .. "  " .. s.detail .. (s.ms and "  (" .. s.ms .. " ms)" or "") .. "\n")
        end
    end
    table.insert(cards, 1, { r = r, t0 = RealTime() })
    for i = #cards, MAX_CARDS + 1, -1 do cards[i] = nil end
end)

-- Text ------------------------------------------------------------------------------------------------

local function ms(v)
    v = tonumber(v) or 0
    if v < 1 then return string.format("%.2f ms", v) end
    if v < 100 then return string.format("%.1f ms", v) end
    return string.format("%d ms", v)
end

-- A module's name, or the step title as is (steps like "anti-stuck" aren't modules).
local function stepName(title)
    local name = L("module." .. title)
    return name == "rareload.module." .. title and title or name
end

local function reasonName(reason)
    local name = L("reason." .. tostring(reason))
    return name == "rareload.reason." .. tostring(reason) and tostring(reason) or name
end

-- `text` in lines no wider than `w`, at most `max` lines (the last one clipped).
local function wrap(text, fnt, w, max)
    surface.SetFont(fnt)
    local lines, cur = {}, ""
    for word in string.gmatch(text, "%S+") do
        local try = cur == "" and word or cur .. " " .. word
        if cur ~= "" and surface.GetTextSize(try) > w then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    if #lines > max then
        lines[max] = UI.Clip(table.concat(lines, " ", max), fnt, w)
        for i = #lines, max + 1, -1 do lines[i] = nil end
    end
    for i, line in ipairs(lines) do lines[i] = UI.Clip(line, fnt, w) end   -- a single word longer than a line
    return lines
end

-- Layout ----------------------------------------------------------------------------------------------

-- Everything a card needs to draw, worked out once when it first shows.
local function prepare(card)
    local r, C, sc = card.r, UI.C, UI.sc
    local info, steps = r.info or {}, r.steps or {}
    card.w, card.pad = sc(460), sc(14)
    card.compact = info.auto == true

    local warns, fails, slowest = 0, 0, 0
    for _, s in ipairs(steps) do
        if s.status == "warn" then warns = warns + 1 elseif s.status == "fail" then fails = fails + 1 end
        slowest = math.max(slowest, tonumber(s.ms) or 0)
    end
    card.accent = fails > 0 and C.bad or warns > 0 and C.warn or r.kind == "save" and C.accent or C.ok
    card.pill = fails > 0 and L("debug.failed", fails) or warns > 0 and L("debug.warnings", warns) or L("debug.ok")
    card.icon = fails > 0 and "exclamation" or r.kind == "save" and "disk" or "arrow_refresh"

    local what = r.kind == "restore" and L("debug.restored") or info.result == "unchanged" and L("debug.unchanged") or L("debug.saved")
    card.title = what .. (info.entry and "  #" .. info.entry or "")
    card.sub = table.concat({ reasonName(info.reason or r.kind), r.player or "?", r.map or game.GetMap() }, "  ·  ")

    local head = sc(58)
    if card.compact then
        local names = {}
        for _, s in ipairs(steps) do names[#names + 1] = stepName(s.title) end
        card.line = UI.Clip(table.concat(names, "  ·  "), "Rareload.Small", card.w - card.pad * 2)
        card.h, card.rows = head + sc(26), {}
        card.hold = math.min(RARELOAD.Get(nil, "toastHold"), 3)
        return
    end

    -- Step rows: name and time on one line, a time bar, then the detail over up to 3 lines.
    local textW = card.w - card.pad * 2 - sc(22)
    local maxH = ScrH() * 0.72
    local y, rows = head + sc(8), {}
    for i, s in ipairs(steps) do
        local lines = s.detail ~= "" and wrap(s.detail, "Rareload.Small", textW, 3) or {}
        local h = sc(24) + #lines * sc(16) + sc(8)
        if y + h + sc(44) > maxH and i < #steps then
            card.more = #steps - i + 1
            break
        end
        rows[#rows + 1] = { s = s, y = y, h = h, lines = lines, name = stepName(s.title), time = s.ms and ms(s.ms),
            frac = slowest > 0 and (tonumber(s.ms) or 0) / slowest or 0, col = C[STATUS[s.status]] or C.text }
        y = y + h
    end
    card.rows = rows
    card.h = y + (card.more and sc(22) or 0) + sc(16)
    card.hold = RARELOAD.Get(nil, "toastHold") + 0.4 * #rows
end

-- Drawing ---------------------------------------------------------------------------------------------

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

local function drawCard(card, x, y, age)
    local C, sc, r = UI.C, UI.sc, card.r
    local w, h, pad, accent = card.w, card.h, card.pad, card.accent

    draw.RoundedBox(sc(12), x, y, w, h, ColorAlpha(C.bgDark, 240))
    draw.RoundedBoxEx(sc(12), x, y, w, sc(58), ColorAlpha(accent, 22), true, true, false, false)
    draw.RoundedBoxEx(sc(12), x, y, sc(4), h, accent, true, false, true, false)

    -- Header: icon, what happened and the save number, why / who / where; time and status on the right.
    local box, icon = sc(34), sc(20)
    draw.RoundedBox(sc(8), x + pad, y + sc(12), box, box, ColorAlpha(accent, 50))
    UI.DrawIcon(card.icon, x + pad + (box - icon) / 2, y + sc(12) + (box - icon) / 2, icon)
    local tx = x + pad + box + sc(12)
    draw.SimpleText(card.title, "Rareload.H2", tx, y + sc(11), C.text)
    draw.SimpleText(UI.Clip(card.sub, "Rareload.Small", w - (tx - x) - sc(110)), "Rareload.Small", tx, y + sc(33), C.text3)
    draw.SimpleText(ms(r.ms), "Rareload.BodyB", x + w - pad, y + sc(12), C.text, TEXT_ALIGN_RIGHT)
    UI.DrawBadge(card.pill, x + w - pad, y + sc(33), accent, "Rareload.Tiny", true)

    if card.compact then
        draw.SimpleText(card.line, "Rareload.Small", x + pad, y + sc(66), C.text2)
    else
        surface.SetDrawColor(ColorAlpha(C.line, 160))
        surface.DrawRect(x + pad, y + sc(58), w - pad * 2, 1)
        local alpha = surface.GetAlphaMultiplier()
        for i, row in ipairs(card.rows) do
            local t = math.Clamp((age - IN * 0.6 - i * STAGGER) / 0.18, 0, 1)   -- rows fade in one after the other
            if t > 0 then
                surface.SetAlphaMultiplier(alpha * t)
                local ry = y + row.y + (1 - t) * sc(6)
                statusMark(row.s.status, x + pad, ry + sc(5), sc(10), row.col)
                draw.SimpleText(row.name, "Rareload.BodyB", x + pad + sc(22), ry, C.text)
                if row.time then draw.SimpleText(row.time, "Rareload.Small", x + w - pad, ry + sc(1), C.text3, TEXT_ALIGN_RIGHT) end
                -- How long this step took, relative to the slowest one.
                local bx, bw = x + pad + sc(22), w - pad * 2 - sc(22)
                draw.RoundedBox(sc(2), bx, ry + sc(19), bw, sc(3), ColorAlpha(C.line, 120))
                if row.frac > 0 then draw.RoundedBox(sc(2), bx, ry + sc(19), math.max(bw * row.frac, sc(3)), sc(3), ColorAlpha(row.col, 200)) end
                for j, line in ipairs(row.lines) do
                    draw.SimpleText(line, "Rareload.Small", bx, ry + sc(24) + (j - 1) * sc(16),
                        row.s.status == "ok" and C.text2 or row.col)
                end
                surface.SetAlphaMultiplier(alpha)
            end
        end
        if card.more then
            draw.SimpleText(L("debug.more", card.more), "Rareload.Small", x + pad + sc(22), y + h - sc(34), C.text3)
        end
    end

    -- Time left before the card goes.
    local left = math.Clamp(1 - (age - IN) / card.hold, 0, 1)
    draw.RoundedBox(sc(2), x + pad, y + h - sc(7), (w - pad * 2) * left, sc(3), ColorAlpha(accent, 150))
end

hook.Add("HUDPaint", "Rareload.Debug.Card", function()
    if #cards == 0 then return end
    local sc = UI.sc
    local now, y = RealTime(), sc(96)
    for i = #cards, 1, -1 do
        local card = cards[i]
        if not card.h then prepare(card) end
        if now - card.t0 > IN + card.hold + OUT then table.remove(cards, i) end
    end

    for _, card in ipairs(cards) do
        local age = now - card.t0
        local slide = age < IN and 1 - ease(age / IN) or age > IN + card.hold and ease((age - IN - card.hold) / OUT) or 0
        card.y = card.y and Lerp(math.min(FrameTime() * 12, 1), card.y, y) or y   -- cards move down as new ones arrive
        local x = ScrW() - card.w - sc(16) + slide * (card.w + sc(30))
        surface.SetAlphaMultiplier(1 - slide * 0.8)
        drawCard(card, x, card.y, age)
        surface.SetAlphaMultiplier(1)
        y = y + card.h + sc(10)
        if y > ScrH() * 0.92 then break end
    end
end)
