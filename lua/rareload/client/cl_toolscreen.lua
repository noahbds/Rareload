-- The Rareload tool's screen (5.5): where the player will come back. A compass to the respawn point with its
-- distance, that save's number, age, health, armor, weapons and objects, the latest saves, the autosave
-- countdown, and how far the last death and the nearest checkpoint are. Saves, restores and refused uses
-- play a short animation over it.
-- (What each key does is already in GMod's tool help, top left, so the screen doesn't repeat it.)

RARELOAD.ToolScreen = RARELOAD.ToolScreen or {}
local Screen = RARELOAD.ToolScreen
local L = RARELOAD.L
local UI, Util = RARELOAD.UI, RARELOAD.Util

-- The screen is 256 px but shown only a few centimetres wide: every text is 21 px or more, and the screen
-- shows a few things large rather than many small.
local HEAD_H = 36
local COMPASS_X, COMPASS_Y, COMPASS_R = 55, 90, 46
local TEXT_X = 112
local STATS_Y = 162
local STRIP_Y, STRIP_MAX = 200, 6
local PLACES_Y = 244
local UNITS_TO_METERS = 0.01905
local HERE_DIST = 80 -- closer than this (units) counts as standing on the respawn point
local OVERLAY_TIME = 1.5

-- What the screen shows after a toast: an icon and its text (the toast's own arguments fill it in), and
-- with `number` the save it is about on a second line.
local OVERLAYS = {
    ["toast.saved"] = { icon = "check", text = "screen.saved" },
    ["toast.unchanged"] = { icon = "skip", text = "screen.unchanged" },
    ["toast.aim_ground"] = { icon = "warn", text = "screen.aim_ground" },
    ["toast.save_wait"] = { icon = "warn", text = "screen.wait" },
    ["toast.reload.restored"] = { icon = "check", text = "screen.restored", number = true },
    ["toast.reload.previous"] = { icon = "check", text = "screen.previous", number = true },
    ["toast.reload.empty"] = { icon = "warn", text = "screen.no_saves" },
    ["toast.reload.no_previous"] = { icon = "skip", text = "screen.no_previous" },
    ["toast.tool_denied"] = { icon = "lock", text = "screen.no_permission" },
}

-- Saves by reason in the strip of latest saves.
local REASON_COLORS = { death = "bad", auto = "text3", quick = "warn", tool = "accent", command = "info" }

-- Everything the screen reads from the timeline, worked out when the timeline changes, not every frame.
local view = { rows = {}, recent = {} }
-- Animation state: the arrow's angle, the latest new save, the overlay.
local anim = { arrow = 0, newId = nil, newAt = 0, activeAt = 0 }

local function rebuild()
    local history = RARELOAD.State.history
    local rows = history.rows or {}
    local known = {}
    for _, row in ipairs(view.rows) do known[row.id] = true end
    local activeIndex
    for index, row in ipairs(rows) do
        if row.active then activeIndex = index end
    end
    local active = activeIndex and rows[activeIndex] or nil
    local newest = rows[#rows]
    if #view.rows > 0 and newest and not known[newest.id] then anim.newId, anim.newAt = newest.id, RealTime() end
    if active and (not view.active or view.active.id ~= active.id) then anim.activeAt = RealTime() end

    view.rows = rows
    view.active = active
    view.previous = activeIndex and rows[activeIndex - 1] or nil
    view.target = active and Util.ToVector(active.info.pos) or nil
    view.mode = istable(history.reload) and history.reload.mode or RARELOAD.RELOAD_MODES[1]
    view.objects = 0
    if active then
        for _, kind in ipairs(RARELOAD.WORLD_KINDS) do view.objects = view.objects + (active.info[kind] or 0) end
    end
    view.recent = {}
    for index = math.max(1, #rows - STRIP_MAX + 1), #rows do view.recent[#view.recent + 1] = rows[index] end
end

hook.Add("RareloadStateChanged", "Rareload.ToolScreen", function(what)
    if what == "history" then rebuild() end
    if what == "autosave" then anim.autosavedAt = RealTime() end
end)
rebuild()

hook.Add("RareloadToast", "Rareload.ToolScreen", function(toast)
    local overlay = OVERLAYS[toast.key]
    if not overlay then return end
    local args = istable(toast.args) and toast.args or {}
    anim.overlay = {
        icon = overlay.icon,
        text = L(overlay.text, unpack(args)),
        sub = overlay.number and args[1] and L("save_no", args[1]) or nil,
        start = RealTime(),
    }
end)

-- Drawing helpers ---------------------------------------------------------------------------------------

local quad = { {}, {}, {}, {} } -- reused for every polygon of four points

local function setQuad(x1, y1, x2, y2, x3, y3, x4, y4)
    quad[1].x, quad[1].y, quad[2].x, quad[2].y = x1, y1, x2, y2
    quad[3].x, quad[3].y, quad[4].x, quad[4].y = x3, y3, x4, y4
    surface.DrawPoly(quad)
end

-- Circles of 12, 20 or 32 points, by size: each with its unit circle worked out once and one polygon
-- reused by every circle of that size (drawn at once, so nothing keeps it).
local circles = {}
for _, points in ipairs({ 12, 20, 32 }) do
    local shape = { cos = {}, sin = {}, poly = {} }
    for i = 1, points do
        local angle = (i - 1) / points * math.pi * 2
        shape.cos[i], shape.sin[i], shape.poly[i] = math.cos(angle), math.sin(angle), {}
    end
    circles[points] = shape
end

local function circle(centerX, centerY, radius, col)
    local shape = circles[radius < 7 and 12 or radius < 16 and 20 or 32]
    local poly = shape.poly
    for i = 1, #poly do
        poly[i].x, poly[i].y = centerX + shape.cos[i] * radius, centerY + shape.sin[i] * radius
    end
    draw.NoTexture()
    surface.SetDrawColor(col)
    surface.DrawPoly(poly)
end

-- A whole ring: two filled circles, far cheaper than an arc all the way round.
local function ring(centerX, centerY, radius, thickness, col, inside)
    circle(centerX, centerY, radius, col)
    circle(centerX, centerY, radius - thickness, inside)
end

-- A ring from `fromFrac` to `toFrac` of a full turn, clockwise from the top.
local function arc(centerX, centerY, radius, thickness, fromFrac, toFrac, col)
    if toFrac <= fromFrac then return end
    draw.NoTexture()
    surface.SetDrawColor(col)
    local segments = math.max(2, math.ceil((toFrac - fromFrac) * 32))
    local inner = radius - thickness
    for i = 0, segments - 1 do
        local startAngle = (fromFrac + (toFrac - fromFrac) * i / segments) * math.pi * 2 - math.pi / 2
        local endAngle = (fromFrac + (toFrac - fromFrac) * (i + 1) / segments) * math.pi * 2 - math.pi / 2
        local cosStart, sinStart, cosEnd, sinEnd = math.cos(startAngle), math.sin(startAngle), math.cos(endAngle),
            math.sin(endAngle)
        setQuad(centerX + cosStart * radius, centerY + sinStart * radius, centerX + cosEnd * radius,
            centerY + sinEnd * radius, centerX + cosEnd * inner, centerY + sinEnd * inner,
            centerX + cosStart * inner, centerY + sinStart * inner)
    end
end

local function thickLine(x1, y1, x2, y2, thickness)
    local angle = math.atan2(y2 - y1, x2 - x1)
    local dx, dy = math.sin(angle) * thickness / 2, -math.cos(angle) * thickness / 2
    setQuad(x1 + dx, y1 + dy, x2 + dx, y2 + dy, x2 - dx, y2 - dy, x1 - dx, y1 - dy)
end

-- Icons drawn as shapes. The silk icons (PNG) come out blank on the tool screen's render target, and
-- shapes stay sharp at any size. Each fills a `size` box whose centre is (centerX, centerY).
local function rect(posX, posY, width, height)
    surface.DrawRect(math.floor(posX + 0.5), math.floor(posY + 0.5), math.floor(width + 0.5), math.floor(height + 0.5))
end

local tri = { {}, {}, {} } -- reused for every triangle

local function triangle(x1, y1, x2, y2, x3, y3)
    tri[1].x, tri[1].y, tri[2].x, tri[2].y, tri[3].x, tri[3].y = x1, y1, x2, y2, x3, y3
    surface.DrawPoly(tri)
end

local GLYPHS = {
    heart = function(centerX, centerY, size)
        circle(centerX - size * 0.22, centerY - size * 0.12, size * 0.26, surface.GetDrawColor())
        circle(centerX + size * 0.22, centerY - size * 0.12, size * 0.26, surface.GetDrawColor())
        triangle(centerX - size * 0.47, centerY - size * 0.04, centerX + size * 0.47, centerY - size * 0.04, centerX,
            centerY + size * 0.46)
    end,
    shield = function(centerX, centerY, size)
        surface.DrawPoly({
            { x = centerX - size * 0.4, y = centerY - size * 0.42 },
            { x = centerX + size * 0.4, y = centerY - size * 0.42 },
            { x = centerX + size * 0.4, y = centerY + size * 0.05 },
            { x = centerX, y = centerY + size * 0.48 },
            { x = centerX - size * 0.4, y = centerY + size * 0.05 },
        })
    end,
    gun = function(centerX, centerY, size)
        rect(centerX - size * 0.46, centerY - size * 0.32, size * 0.92, size * 0.26)
        rect(centerX - size * 0.4, centerY - size * 0.1, size * 0.24, size * 0.48)
        rect(centerX - size * 0.12, centerY - size * 0.08, size * 0.14, size * 0.16)
    end,
    bricks = function(centerX, centerY, size)
        local brick, gap = size * 0.44, size * 0.08
        for row = 0, 1 do
            for column = 0, 1 do
                rect(centerX - brick - gap / 2 + column * (brick + gap),
                    centerY - brick - gap / 2 + row * (brick + gap),
                    brick, brick)
            end
        end
    end,
    cross = function(centerX, centerY, size)
        thickLine(centerX - size * 0.36, centerY - size * 0.36, centerX + size * 0.36, centerY + size * 0.36,
            size * 0.2)
        thickLine(centerX + size * 0.36, centerY - size * 0.36, centerX - size * 0.36, centerY + size * 0.36,
            size * 0.2)
    end,
    flag = function(centerX, centerY, size)
        rect(centerX - size * 0.38, centerY - size * 0.46, size * 0.12, size * 0.92)
        triangle(centerX - size * 0.26, centerY - size * 0.46, centerX + size * 0.46, centerY - size * 0.24,
            centerX - size * 0.26, centerY - size * 0.02)
    end,
    house = function(centerX, centerY, size)
        triangle(centerX, centerY - size * 0.48, centerX + size * 0.5, centerY - size * 0.02, centerX - size * 0.5,
            centerY - size * 0.02)
        rect(centerX - size * 0.34, centerY - size * 0.04, size * 0.68, size * 0.48)
    end,
    clock = function(centerX, centerY, size)
        local col = surface.GetDrawColor()
        ring(centerX, centerY, size * 0.46, math.max(2, size * 0.12), col, UI.C.bg)
        surface.SetDrawColor(col)
        thickLine(centerX, centerY + 1, centerX, centerY - size * 0.28, math.max(2, size * 0.1))
        thickLine(centerX - 1, centerY, centerX + size * 0.22, centerY, math.max(2, size * 0.1))
    end,
}

local function glyph(name, centerX, centerY, size, col)
    draw.NoTexture()
    surface.SetDrawColor(col)
    GLYPHS[name](centerX, centerY, size)
end

local function textWidth(text, font)
    surface.SetFont(font)
    return (surface.GetTextSize(text))
end

-- Text scaled down to fit `maxWidth`, so long translations stay readable instead of overlapping.
local function fittedText(text, font, posX, posY, maxWidth, col, alignX)
    local width = textWidth(text, font)
    alignX = alignX or TEXT_ALIGN_LEFT
    if width <= maxWidth then return draw.SimpleText(text, font, posX, posY, col, alignX, TEXT_ALIGN_CENTER) end
    local scale = maxWidth / width
    local matrix = Matrix()
    matrix:Translate(Vector(posX, posY, 0))
    matrix:Scale(Vector(scale, scale, 1))
    matrix:Translate(Vector(-posX, -posY, 0))
    cam.PushModelMatrix(matrix, true)
    draw.SimpleText(text, font, posX, posY, col, alignX, TEXT_ALIGN_CENTER)
    cam.PopModelMatrix()
end

local function easeOutBack(progress)
    progress = math.Clamp(progress, 0, 1) - 1
    return 1 + 2.70158 * progress ^ 3 + 1.70158 * progress ^ 2
end

local function meters(units) return string.format("%.0f", units * UNITS_TO_METERS) end

-- Overlay icons ---------------------------------------------------------------------------------------

local ICON_COLORS = { check = "ok", warn = "warn", skip = "accent", lock = "warn" }

local function drawIcon(kind, centerX, centerY, size, alpha, progress)
    local C = UI.C
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
        local startX, startY = centerX - size * 0.35, centerY
        local cornerX, cornerY = centerX - size * 0.1, centerY + size * 0.28
        local endX, endY = centerX + size * 0.38, centerY - size * 0.3
        local first = math.min(1, markProgress * 2)
        thickLine(startX, startY, Lerp(first, startX, cornerX), Lerp(first, startY, cornerY), thickness)
        if markProgress > 0.5 then
            local second = (markProgress - 0.5) * 2
            thickLine(cornerX, cornerY, Lerp(second, cornerX, endX), Lerp(second, cornerY, endY), thickness)
        end
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
        local bodyWidth, bodyHeight = size * 0.55, size * 0.4 * markProgress
        surface.DrawRect(centerX - bodyWidth / 2, centerY, bodyWidth, bodyHeight)
        local shackle = bodyWidth * 0.35
        for i = 0, 9 do
            local fromAngle, toAngle = math.pi + i / 10 * math.pi, math.pi + (i + 1) / 10 * math.pi
            thickLine(centerX + math.cos(fromAngle) * shackle, centerY + math.sin(fromAngle) * shackle,
                centerX + math.cos(toAngle) * shackle, centerY + math.sin(toAngle) * shackle, thickness * 0.7)
        end
        surface.DrawRect(centerX - shackle - thickness * 0.35, centerY - 1, thickness * 0.7, 3)
        surface.DrawRect(centerX + shackle - thickness * 0.35, centerY - 1, thickness * 0.7, 3)
    end
end

local function drawOverlay(width, height)
    local overlay = anim.overlay
    local elapsed = RealTime() - overlay.start
    if elapsed > OVERLAY_TIME then
        anim.overlay = nil
        return
    end
    local progress = elapsed / OVERLAY_TIME
    local alpha = 255 * math.Clamp((1 - progress) / 0.25, 0, 1)
    surface.SetDrawColor(10, 12, 16, alpha * 0.82)
    surface.DrawRect(0, 0, width, height)
    local lift = overlay.sub and 12 or 0
    drawIcon(overlay.icon, width / 2, height / 2 - 22 - lift, 46, alpha, math.min(1, progress * 2.2))
    fittedText(overlay.text, "Rareload.Screen", width / 2, height / 2 + 48 - lift, width - 20,
        Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER)
    if overlay.sub then
        local accent = UI.C.accentHi
        fittedText(overlay.sub, "Rareload.ScreenBig", width / 2, height / 2 + 74, width - 20,
            Color(accent.r, accent.g, accent.b, alpha), TEXT_ALIGN_CENTER)
    end
end

-- Header: the name and version, on/off, and the autosave countdown ---------------------------------------

local function drawAutosaveRing(centerX, centerY, radius)
    local C = UI.C
    local lp = LocalPlayer()
    if not RARELOAD.Get(lp, "autoSave") then return end
    ring(centerX, centerY, radius, 3, C.line, C.bgDark)
    local sinceAutosave = anim.autosavedAt and RealTime() - anim.autosavedAt or math.huge
    if sinceAutosave < 1.2 then
        local pulse = 1 + 0.2 * math.sin(sinceAutosave / 1.2 * math.pi)
        ring(centerX, centerY, radius * pulse, 3, C.ok, C.bgDark)
        circle(centerX, centerY, radius * 0.45, C.ok)
        return
    end
    local last = RARELOAD.State.lastAutosave
    local interval = RARELOAD.Get(lp, "autoSaveInterval")
    local fraction = last and math.Clamp((CurTime() - last) / interval, 0, 1) or 1
    if fraction < 1 then
        arc(centerX, centerY, radius, 3, 0, fraction, UI.Mix(C.ok, C.warn, fraction))
        local seconds = math.ceil(interval - (CurTime() - last))
        fittedText(tostring(seconds), "Rareload.ScreenSmall", centerX, centerY, radius * 2 - 6, C.text,
            TEXT_ALIGN_CENTER)
    else
        -- Waiting for the player to move or change something: a slow spinner.
        local spin = RealTime() * 0.35 % 1
        arc(centerX, centerY, radius, 3, spin, spin + 0.25, C.accent)
    end
end

local function drawHeader(width, enabled)
    local C = UI.C
    surface.SetDrawColor(C.bgDark)
    surface.DrawRect(0, 0, width, HEAD_H)
    surface.SetDrawColor(C.accent)
    surface.DrawRect(0, HEAD_H - 3, width, 3)
    draw.SimpleText("RARELOAD", "Rareload.ScreenHead", 9, HEAD_H / 2 - 1, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local titleWidth = textWidth("RARELOAD", "Rareload.ScreenHead")
    draw.SimpleText("v" .. RARELOAD.version, "Rareload.ScreenSmall", 9 + titleWidth + 6, HEAD_H / 2, C.text3,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local dotColor = enabled and C.ok or C.bad
    local pulse = enabled and 0.6 + 0.4 * math.abs(math.sin(RealTime() * 2)) or 1
    circle(width - 52, HEAD_H / 2 - 1, 6, ColorAlpha(dotColor, 255 * pulse))
    drawAutosaveRing(width - 20, HEAD_H / 2 - 1, 15)
end

-- The compass and the respawn save ---------------------------------------------------------------------

local function drawCompass(lp)
    local C = UI.C
    ring(COMPASS_X, COMPASS_Y, COMPASS_R, 3, C.line, C.surface)
    local toTarget = view.target - lp:GetPos()
    local flat = Vector(toTarget.x, toTarget.y, 0):Length()
    if flat < HERE_DIST then
        local pulse = (RealTime() * 0.8) % 1
        ring(COMPASS_X, COMPASS_Y, 12 + pulse * (COMPASS_R - 14), 4, ColorAlpha(C.ok, 255 * (1 - pulse)), C.surface)
        glyph("house", COMPASS_X, COMPASS_Y, 30, C.text)
        return flat
    end
    -- The tick on top is where the player looks.
    surface.SetDrawColor(C.accentHi)
    thickLine(COMPASS_X, COMPASS_Y - COMPASS_R + 4, COMPASS_X, COMPASS_Y - COMPASS_R + 11, 3)
    -- The arrow turns smoothly towards the respawn point.
    local relative = math.AngleDifference(toTarget:Angle().y, lp:EyeAngles().y)
    anim.arrow = anim.arrow + math.AngleDifference(-relative, anim.arrow) * math.min(1, FrameTime() * 10)
    local theta = math.rad(anim.arrow)
    local sinTheta, cosTheta = math.sin(theta), math.cos(theta)
    -- A navigation arrow, drawn as two halves (one lit, one in shade): a point `forward` units ahead of
    -- the centre and `side` units to its right becomes a point on the screen.
    local function point(forward, side)
        return COMPASS_X + sinTheta * forward + cosTheta * side, COMPASS_Y - cosTheta * forward + sinTheta * side
    end
    local tipX, tipY = point(COMPASS_R - 13, 0)
    local notchX, notchY = point(-12, 0)
    local leftX, leftY = point(-24, -18)
    local rightX, rightY = point(-24, 18)
    draw.NoTexture()
    surface.SetDrawColor(C.accentHi)
    surface.DrawPoly({ { x = tipX, y = tipY }, { x = notchX, y = notchY }, { x = leftX, y = leftY } })
    surface.SetDrawColor(C.accent)
    surface.DrawPoly({ { x = tipX, y = tipY }, { x = rightX, y = rightY }, { x = notchX, y = notchY } })
    return flat
end

local function drawRespawn(width, lp)
    local C = UI.C
    local active = view.active
    local flat = drawCompass(lp)
    local maxWidth = width - TEXT_X - 6

    -- "SAVE" above the save's number, large: the word on its own line, so a long translation shrinks only
    -- itself. The number pops when the respawn point changes.
    fittedText(string.upper(L("screen.save_word")), "Rareload.ScreenSmall", TEXT_X, 48, maxWidth, C.text3)
    local number = "#" .. active.id
    local fit = math.min(1, maxWidth / textWidth(number, "Rareload.ScreenBig"))
    local sinceChange = RealTime() - anim.activeAt
    local pop = sinceChange < 0.5 and 1 + 0.25 * (1 - easeOutBack(sinceChange / 0.5)) or 1
    local scale = fit * pop
    local matrix = Matrix()
    matrix:Translate(Vector(TEXT_X, 82, 0))
    matrix:Scale(Vector(scale, scale, 1))
    matrix:Translate(Vector(-TEXT_X, -82, 0))
    cam.PushModelMatrix(matrix, true)
    draw.SimpleText(number, "Rareload.ScreenBig", TEXT_X - 2, 82, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    cam.PopModelMatrix()

    if flat < HERE_DIST then
        fittedText(L("screen.here"), "Rareload.Screen", TEXT_X, 116, maxWidth, C.ok)
    else
        local text = L("screen.meters", meters(flat))
        local rise = (view.target.z - lp:GetPos().z) * UNITS_TO_METERS
        if math.abs(rise) >= 2 then
            text = text .. (rise > 0 and " ▲" or " ▼") .. string.format("%.0f", math.abs(rise))
        end
        fittedText(text, "Rareload.Screen", TEXT_X, 116, maxWidth, C.accentHi)
    end

    -- How old the save is, after a clock.
    glyph("clock", TEXT_X + 8, 140, 16, C.text3)
    fittedText(UI.TimeAgo(active.time), "Rareload.ScreenSmall", TEXT_X + 20, 140, maxWidth - 20, C.text2)
end

-- Health, armor, weapons and objects in the respawn save: an icon and a number each.
local function drawStats(width)
    local C = UI.C
    local info = view.active.info
    local values = {
        { "heart", info.hp and math.floor(info.hp) or "-", UI.HealthColor(tonumber(info.hp) or 0, 100), C.bad },
        { "shield", info.armor and math.floor(info.armor) or "-", C.info, C.info },
        { "gun", info.weapons or 0, C.text, C.text2 },
        { "bricks", view.objects, C.text, C.prop },
    }
    local column = (width - 8) / #values
    for index, value in ipairs(values) do
        local posX = 6 + (index - 1) * column
        glyph(value[1], posX + 9, STATS_Y, 18, value[4])
        fittedText(tostring(value[2]), "Rareload.Screen", posX + 22, STATS_Y, column - 26, value[3])
    end
end

-- The latest saves, oldest on the left, each with its number; a new one pops in on the right. The save
-- the reload key goes to is marked R.
local function drawStrip(width)
    local C = UI.C
    local recent = view.recent
    if #recent == 0 then return end
    local left, right = 24, width - 24
    local spacing = (right - left) / (STRIP_MAX - 1)
    local sinceNew = RealTime() - anim.newAt
    local slide = sinceNew < 0.45 and (1 - easeOutBack(sinceNew / 0.45)) * spacing or 0
    local startX = right - (#recent - 1) * spacing
    surface.SetDrawColor(C.line)
    surface.DrawRect(left - 14, STRIP_Y - 1, right - left + 28, 3)
    local reloadTarget = view.mode == "restore_current" and view.active or view.previous
    for index, row in ipairs(recent) do
        local nodeX = startX + (index - 1) * spacing + slide
        local col = C[REASON_COLORS[row.reason] or "text2"]
        local radius = row.active and 9 or 6
        if row.id == anim.newId and sinceNew < 0.6 then radius = radius * easeOutBack(sinceNew / 0.6) end
        if row.active then
            local glow = 0.5 + 0.5 * math.sin(RealTime() * 3)
            circle(nodeX, STRIP_Y, radius + 4 + glow * 2, ColorAlpha(C.accent, 70))
            circle(nodeX, STRIP_Y, radius, C.text)
            circle(nodeX, STRIP_Y, radius - 3, col)
        else
            circle(nodeX, STRIP_Y, radius, col)
        end
        if reloadTarget and row.id == reloadTarget.id then
            draw.SimpleText("R", "Rareload.ScreenSmall", nodeX, STRIP_Y - 18, C.warn, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        fittedText(tostring(row.id), "Rareload.ScreenSmall", nodeX, STRIP_Y + 22, spacing - 4,
            row.active and C.text or C.text3, TEXT_ALIGN_CENTER)
    end
end

-- Where else the player can go back to: their last death and their nearest checkpoint, with how far each
-- one is.
local function drawPlaces(width, lp)
    local C = UI.C
    local here = lp:GetPos()
    local death = RARELOAD.State.death
    local nearestDist
    for _, checkpoint in ipairs(RARELOAD.State.checkpoints) do
        if not checkpoint.disabled and checkpoint.vec then
            local dist = here:Distance(checkpoint.vec)
            if not nearestDist or dist < nearestDist then nearestDist = dist end
        end
    end
    draw.RoundedBox(6, 4, PLACES_Y - 12, width - 8, 24, C.surface)
    local half = (width - 8) / 2
    local function place(index, icon, dist, col)
        local posX = 4 + (index - 1) * half
        glyph(icon, posX + 16, PLACES_Y, 16, dist and col or C.textOff)
        fittedText(dist and L("screen.meters", meters(dist)) or "-", "Rareload.ScreenSmall", posX + 30, PLACES_Y,
            half - 36, dist and col or C.textOff)
    end
    place(1, "cross", death.pos and here:Distance(death.pos) or nil, C.bad)
    place(2, "flag", nearestDist, C.info)
    surface.SetDrawColor(C.line)
    surface.DrawRect(4 + half, PLACES_Y - 9, 1, 18)
end

-- No save yet: what to do to get one.
local function drawEmpty(width)
    local C = UI.C
    ring(COMPASS_X, COMPASS_Y, COMPASS_R, 3, C.line, C.surface)
    local bob = math.sin(RealTime() * 2) * 3
    glyph("flag", COMPASS_X, COMPASS_Y + bob, 30, C.text2)
    fittedText(L("screen.no_saves"), "Rareload.Screen", TEXT_X, 76, width - TEXT_X - 6, C.text)
    fittedText(L("screen.no_saves_hint"), "Rareload.ScreenSmall", TEXT_X, 106, width - TEXT_X - 6, C.text2)
end

-- Called from TOOL:DrawToolScreen, inside the tool's own cam.Start2D.
function Screen.Draw(width, height)
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local C = UI.C
    local enabled = RARELOAD.Get(lp, "enabled")

    -- Opaque: the tool screen's texture is shared, and anything see-through would show what was there before.
    surface.SetDrawColor(C.bg.r, C.bg.g, C.bg.b, 255)
    surface.DrawRect(0, 0, width, height)
    drawHeader(width, enabled)
    if view.active and view.target then
        drawRespawn(width, lp)
        drawStats(width)
    else
        drawEmpty(width)
    end
    drawStrip(width)
    drawPlaces(width, lp)

    if not enabled then
        surface.SetDrawColor(10, 12, 16, 210)
        surface.DrawRect(0, HEAD_H, width, height - HEAD_H)
        draw.RoundedBox(8, 20, height / 2 - 18, width - 40, 36, C.bad)
        fittedText(L("screen.off"), "Rareload.Screen", width / 2, height / 2, width - 56, color_white,
            TEXT_ALIGN_CENTER)
    end
    if anim.overlay then drawOverlay(width, height) end
end
