local L, UI = RARELOAD.L, RARELOAD.UI
local STATUS = { ok = "ok", warn = "warn", fail = "bad" }
local IN, OUT, STAGGER, MAX_CARDS = 0.35, 0.4, 0.035, 4

local cards = {}

-- Any value as text. JSON turns strings shaped like "[x y z]" or "{p y r}" into Vectors and Angles.
local function text(value)
    if isvector(value) then return string.format("%.0f, %.0f, %.0f", value.x, value.y, value.z) end
    if isangle(value) then return string.format("%.0f, %.0f, %.0f", value.p, value.y, value.r) end
    return tostring(value == nil and "" or value)
end

-- `quiet`: the host, whose console already shows the server's printout.
RARELOAD.Net.On("debug", function(report)
    local C = UI.C
    report.player = RARELOAD.Util.AsText(report.player) -- a player named like "[1 2 3]" arrives as a Vector
    if not report.quiet then
        MsgC(C.accent, "[Rareload] ", color_white,
            string.format("%s: %s (%s ms)\n", report.title, report.player, report.ms))
        for _, step in ipairs(report.steps or {}) do
            MsgC(C[STATUS[step.status]] or color_white, "    " .. step.status .. " ", color_white,
                text(step.title) .. "  " .. text(step.detail) .. (step.ms and "  (" .. step.ms .. " ms)" or "") .. "\n")
        end
    end
    table.insert(cards, 1, { r = report, t0 = RealTime() })
    for i = #cards, MAX_CARDS + 1, -1 do cards[i] = nil end
end)

-- Text ------------------------------------------------------------------------------------------------

local function ms(value)
    value = tonumber(value) or 0
    if value < 1 then return string.format("%.2f ms", value) end
    if value < 100 then return string.format("%.1f ms", value) end
    return string.format("%d ms", value)
end

-- A module's name, or the step title as is (steps like "anti-stuck" aren't modules).
local function stepName(title)
    title = text(title)
    local name = L("module." .. title)
    return name == "rareload.module." .. title and title or name
end

local function reasonName(reason)
    local name = L("reason." .. tostring(reason))
    return name == "rareload.reason." .. tostring(reason) and tostring(reason) or name
end

-- `str` in lines no wider than `maxWidth`, at most `max` lines (the last one clipped).
local function wrap(str, fnt, maxWidth, max)
    surface.SetFont(fnt)
    local lines, cur = {}, ""
    for word in string.gmatch(str, "%S+") do
        local try = cur == "" and word or cur .. " " .. word
        if cur ~= "" and surface.GetTextSize(try) > maxWidth then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    if #lines > max then
        lines[max] = UI.Clip(table.concat(lines, " ", max), fnt, maxWidth)
        for i = #lines, max + 1, -1 do lines[i] = nil end
    end
    for i, line in ipairs(lines) do lines[i] = UI.Clip(line, fnt, maxWidth) end -- a single word longer than a line
    return lines
end

-- Layout ----------------------------------------------------------------------------------------------

-- Everything a card needs to draw, worked out once when it first shows.
local function prepare(card)
    local report, C, sc = card.r, UI.C, UI.sc
    local info, steps = report.info or {}, report.steps or {}
    card.w, card.pad = sc(460), sc(14)
    card.compact = info.auto == true

    local warns, fails, slowest = 0, 0, 0
    for _, step in ipairs(steps) do
        if step.status == "warn" then warns = warns + 1 elseif step.status == "fail" then fails = fails + 1 end
        slowest = math.max(slowest, tonumber(step.ms) or 0)
    end
    card.accent = fails > 0 and C.bad or warns > 0 and C.warn or report.kind == "save" and C.accent or C.ok
    card.pill = fails > 0 and L("debug.failed", fails) or warns > 0 and L("debug.warnings", warns) or L("debug.ok")
    card.icon = fails > 0 and "exclamation" or report.kind == "save" and "disk" or "arrow_refresh"

    -- An undo restores a copy taken before the last restore, which has no number.
    local key = report.kind == "restore" and "debug.restored" or info.result == "unchanged" and "debug.unchanged" or
        "debug.saved"
    card.title = info.entry and L(key, info.entry) or L("debug.restored_plain")
    card.sub = table.concat({ reasonName(info.reason or report.kind), report.player or "?",
        report.map or game.GetMap() }, "  ·  ")

    local head = sc(58)
    if card.compact then
        local names = {}
        for _, step in ipairs(steps) do names[#names + 1] = stepName(step.title) end
        card.line = UI.Clip(table.concat(names, "  ·  "), "Rareload.Small", card.w - card.pad * 2)
        card.h, card.rows = head + sc(26), {}
        card.hold = math.min(RARELOAD.Get(nil, "toastHold"), 3)
        return
    end

    -- Step rows: name and time on one line, a time bar, then the detail over up to 3 lines.
    local textW = card.w - card.pad * 2 - sc(22)
    local maxH = ScrH() * 0.72
    local rowY, rows = head + sc(8), {}
    for i, step in ipairs(steps) do
        local detail = text(step.detail)
        local lines = detail ~= "" and wrap(detail, "Rareload.Small", textW, 3) or {}
        local rowHeight = sc(24) + #lines * sc(16) + sc(8)
        if rowY + rowHeight + sc(44) > maxH and i < #steps then
            card.more = #steps - i + 1
            break
        end
        rows[#rows + 1] = {
            s = step,
            y = rowY,
            h = rowHeight,
            lines = lines,
            name = stepName(step.title),
            time = step.ms and ms(step.ms),
            frac = slowest > 0 and (tonumber(step.ms) or 0) / slowest or 0,
            col = C[STATUS[step.status]] or C.text
        }
        rowY = rowY + rowHeight
    end
    card.rows = rows
    card.h = rowY + (card.more and sc(22) or 0) + sc(16)
    card.hold = RARELOAD.Get(nil, "toastHold") + 0.4 * #rows
end

-- Drawing ---------------------------------------------------------------------------------------------

local function ease(progress)
    progress = progress - 1
    return progress * progress * progress + 1
end

local function statusMark(status, posX, posY, size, col)
    surface.SetDrawColor(col)
    if status == "ok" then
        surface.DrawLine(posX, posY + size / 2, posX + size / 3, posY + size)
        surface.DrawLine(posX + size / 3, posY + size, posX + size, posY)
    elseif status == "fail" then
        surface.DrawLine(posX, posY, posX + size, posY + size)
        surface.DrawLine(posX, posY + size, posX + size, posY)
    else
        surface.DrawRect(posX + size / 2 - 1, posY, 2, size * 0.65)
        surface.DrawRect(posX + size / 2 - 1, posY + size * 0.8, 2, 2)
    end
end

local function drawCard(card, posX, posY, age)
    local C, sc, report = UI.C, UI.sc, card.r
    local width, height, pad, accent = card.w, card.h, card.pad, card.accent

    draw.RoundedBox(sc(12), posX, posY, width, height, ColorAlpha(C.bgDark, 240))
    draw.RoundedBoxEx(sc(12), posX, posY, width, sc(58), ColorAlpha(accent, 22), true, true, false, false)
    draw.RoundedBoxEx(sc(12), posX, posY, sc(4), height, accent, true, false, true, false)

    -- Header: icon, what happened and the save number, why / who / where; time and status on the right.
    local box, icon = sc(34), sc(20)
    draw.RoundedBox(sc(8), posX + pad, posY + sc(12), box, box, ColorAlpha(accent, 50))
    UI.DrawIcon(card.icon, posX + pad + (box - icon) / 2, posY + sc(12) + (box - icon) / 2, icon)
    local tx = posX + pad + box + sc(12)
    draw.SimpleText(card.title, "Rareload.H2", tx, posY + sc(11), C.text)
    draw.SimpleText(UI.Clip(card.sub, "Rareload.Small", width - (tx - posX) - sc(110)), "Rareload.Small", tx,
        posY + sc(33),
        C.text3)
    draw.SimpleText(ms(report.ms), "Rareload.BodyB", posX + width - pad, posY + sc(12), C.text, TEXT_ALIGN_RIGHT)
    UI.DrawBadge(card.pill, posX + width - pad, posY + sc(33), accent, "Rareload.Tiny", true)

    if card.compact then
        draw.SimpleText(card.line, "Rareload.Small", posX + pad, posY + sc(66), C.text2)
    else
        surface.SetDrawColor(ColorAlpha(C.line, 160))
        surface.DrawRect(posX + pad, posY + sc(58), width - pad * 2, 1)
        local alpha = surface.GetAlphaMultiplier()
        for i, row in ipairs(card.rows) do
            local fade = math.Clamp((age - IN * 0.6 - i * STAGGER) / 0.18, 0, 1) -- rows fade in one after the other
            if fade > 0 then
                surface.SetAlphaMultiplier(alpha * fade)
                local ry = posY + row.y + (1 - fade) * sc(6)
                statusMark(row.s.status, posX + pad, ry + sc(5), sc(10), row.col)
                draw.SimpleText(row.name, "Rareload.BodyB", posX + pad + sc(22), ry, C.text)
                if row.time then
                    draw.SimpleText(row.time, "Rareload.Small", posX + width - pad, ry + sc(1), C.text3,
                        TEXT_ALIGN_RIGHT)
                end
                -- How long this step took, relative to the slowest one.
                local bx, bw = posX + pad + sc(22), width - pad * 2 - sc(22)
                draw.RoundedBox(sc(2), bx, ry + sc(19), bw, sc(3), ColorAlpha(C.line, 120))
                if row.frac > 0 then
                    draw.RoundedBox(sc(2), bx, ry + sc(19), math.max(bw * row.frac, sc(3)), sc(3),
                        ColorAlpha(row.col, 200))
                end
                for j, line in ipairs(row.lines) do
                    draw.SimpleText(line, "Rareload.Small", bx, ry + sc(24) + (j - 1) * sc(16),
                        row.s.status == "ok" and C.text2 or row.col)
                end
                surface.SetAlphaMultiplier(alpha)
            end
        end
        if card.more then
            draw.SimpleText(L("debug.more", card.more), "Rareload.Small", posX + pad + sc(22), posY + height - sc(34),
                C.text3)
        end
    end

    -- Time left before the card goes.
    local left = math.Clamp(1 - (age - IN) / card.hold, 0, 1)
    draw.RoundedBox(sc(2), posX + pad, posY + height - sc(7), (width - pad * 2) * left, sc(3), ColorAlpha(accent, 150))
end

hook.Add("HUDPaint", "Rareload.Debug.Card", function()
    if #cards == 0 then return end
    local sc = UI.sc
    local now, cardY = RealTime(), sc(96)
    for i = #cards, 1, -1 do
        local card = cards[i]
        -- A card that can't be laid out is dropped, instead of failing again every frame.
        if not card.h and not ProtectedCall(prepare, card) then card.h, card.hold = 0, -math.huge end
        if now - card.t0 > IN + card.hold + OUT then table.remove(cards, i) end
    end

    for _, card in ipairs(cards) do
        local age = now - card.t0
        local slide = age < IN and 1 - ease(age / IN)
            or age > IN + card.hold and ease((age - IN - card.hold) / OUT) or 0
        -- cards move down as new ones arrive
        card.y = card.y and Lerp(math.min(FrameTime() * 12, 1), card.y, cardY) or cardY
        local cardX = ScrW() - card.w - sc(16) + slide * (card.w + sc(30))
        surface.SetAlphaMultiplier(1 - slide * 0.8)
        drawCard(card, cardX, card.y, age)
        surface.SetAlphaMultiplier(1)
        cardY = cardY + card.h + sc(10)
        if cardY > ScrH() * 0.92 then break end
    end
end)
