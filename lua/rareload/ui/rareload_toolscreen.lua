local RareloadUI = include("rareload/ui/rareload_ui.lua")

-- Lightweight material cache (built-in gradients)
local GRADIENT_U = Material("vgui/gradient-u")
local GRADIENT_R = Material("vgui/gradient-r")

RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.lastMoveTime = RARELOAD.lastMoveTime or 0
RARELOAD.showAutoSaveMessage = RARELOAD.showAutoSaveMessage or false
RARELOAD.autoSaveMessageTime = RARELOAD.autoSaveMessageTime or 0

local TOOL_UI = {
    COLORS = {
        BG = Color(30, 30, 35),
        ENABLED = Color(40, 210, 40),
        DISABLED = Color(210, 40, 40),
        HEADER = Color(40, 90, 180),
        TEXT_LIGHT = Color(255, 255, 255),
        TEXT_DARK = Color(15, 15, 15),
        VERSION = Color(150, 150, 150, 180),
        PROGRESS = {
            BG_OUTER = Color(25, 25, 30),
            BG_INNER = Color(35, 35, 40),
            LOW = Color(35, 185, 35),
            MEDIUM = Color(185, 185, 35),
            HIGH = Color(185, 65, 35),
            STEP = Color(255, 255, 255, 40),
            SHINE = Color(255, 255, 255)
        },
        TEXT = {
            NORMAL = Color(225, 225, 225),
            WARNING = Color(255, 255, 0),
            URGENT_1 = Color(255, 100, 0),
            URGENT_2 = Color(255, 220, 0),
            SAVED = Color(60, 255, 60),
            SHADOW = Color(0, 0, 0, 180)
        },
        AUTO_SAVE_MESSAGE = Color(60, 255, 60, 255),
        EMOJI = {
            DATA_FOUND = Color(40, 210, 40),
            NO_DATA = Color(210, 40, 40)
        }
    },
    ANIMATION = {
        SAVE_MESSAGE_DURATION = 5,
        PULSE_THRESHOLD = 3,
        BLINK_THRESHOLD = 1
    },
    LAYOUT = {
        FEATURE_START_Y = 100,
        FEATURE_ICON_SIZE = 20,
        FEATURE_SPACING = 28,
        BAR_HEIGHT = 20
    }
}

local ToolScreen = {}

-- Static feature config to avoid per-frame allocations
local FEATURES = {
    { name = "Move Type",             key = "spawnModeEnabled",      kind = "bool" },
    { name = "Auto Save",             key = "autoSaveEnabled",       kind = "bool" },
    { name = "Save Inventory",        key = "retainInventory",       kind = "bool" },
    { name = "Save Global Inventory", key = "retainGlobalInventory", kind = "bool" },
    { name = "Save Ammo",             key = "retainAmmo",            kind = "bool" },
    { name = "Save Health and Armor", key = "retainHealthArmor",     kind = "bool" },
    { name = "Save Entities",         key = "retainMapEntities",     kind = "bool" },
    { name = "Save NPCs",             key = "retainMapNPCs",         kind = "bool" },
    { name = "Debug Mode",            key = "debugEnabled",          kind = "bool" },
    { name = "Auto Save Interval",    key = "autoSaveInterval",      kind = "value", unit = "s" },
    { name = "Angle Tolerance",       key = "angleTolerance",        kind = "value", unit = "°" },
    { name = "Max History Size",      key = "maxHistorySize",        kind = "value" }
}

-- Reusable dynamic colors to avoid GC churn
local TMP_COLOR = Color(255, 255, 255, 255)
local TMP_COLOR2 = Color(255, 255, 255, 255)

local function initAnimState(RARELOAD)
    RARELOAD.AnimState = RARELOAD.AnimState or {
        lastSaveTime = 0,
        pulsePhase = 0,
        glowPhase = 0,
        showingMessage = false,
        messageOpacity = 0,
        lastProgress = 0,
        waitingForTrigger = false,
        scrollOffset = 0,
        targetScrollOffset = 0,
        scrollDirection = 1,
        nextScrollTime = CurTime(),
        scrollPauseTime = 5,
        scrollSpeed = 15,
        lastRemainingSecond = -1,
        cachedCountdownText = "Saving in: 0s"
    }
    return RARELOAD.AnimState
end

local function drawWaitingForTriggerBar(width, height, state, barY, barHeight, currentTime, baseColor)
    if RARELOAD.showAutoSaveMessage or RARELOAD.activeProgress then
        state.waitingForTrigger = false
        return
    end

    draw.RoundedBox(8, 8, barY, width - 16, barHeight, TOOL_UI.COLORS.PROGRESS.BG_OUTER)
    draw.RoundedBox(8, 9, barY + 1, width - 18, barHeight - 2, TOOL_UI.COLORS.PROGRESS.BG_INNER)
    draw.RoundedBox(8, 10, barY + 2, width - 20, barHeight - 4, baseColor)

    local shineOpacity = math.abs(math.sin(state.glowPhase)) * 40
    surface.SetDrawColor(TOOL_UI.COLORS.PROGRESS.SHINE.r, TOOL_UI.COLORS.PROGRESS.SHINE.g,
        TOOL_UI.COLORS.PROGRESS.SHINE.b, shineOpacity)
    surface.DrawRect(10, barY + 2, width - 20, 2)

    local steps = 4
    for i = 1, steps - 1 do
        local stepX = 10 + (width - 20) * (i / steps)
        surface.SetDrawColor(TOOL_UI.COLORS.PROGRESS.STEP)
        surface.DrawRect(stepX - 0.5, barY + 4, 1, barHeight - 8)
    end

    local textY = barY + barHeight / 2
    local infoText = "Ready for next save..."
    local textColor = TOOL_UI.COLORS.TEXT.NORMAL

    draw.SimpleText(infoText, "CTNV", width / 2 + 1, textY + 1, TOOL_UI.COLORS.TEXT.SHADOW, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(infoText, "CTNV", width / 2, textY, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function drawAutoSaveMessage(width, height, barY, barHeight)
    local textY = barY + barHeight / 2
    local opacity = math.Clamp(255 - (CurTime() - RARELOAD.autoSaveMessageTime) / 5 * 255, 0, 255)
    local messageColor = Color(TOOL_UI.COLORS.AUTO_SAVE_MESSAGE.r, TOOL_UI.COLORS.AUTO_SAVE_MESSAGE.g,
        TOOL_UI.COLORS.AUTO_SAVE_MESSAGE.b, opacity)
    local shadowColor = Color(0, 0, 0, opacity * 0.7)

    draw.SimpleText("Auto Saved!", "CTNV", width / 2 + 1, textY + 1, shadowColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("Auto Saved!", "CTNV", width / 2, textY, messageColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    if CurTime() - RARELOAD.autoSaveMessageTime > 5 then
        RARELOAD.showAutoSaveMessage = false
    end
end

local function drawProgressBar(width, height, state, barY, barHeight, progress, timeRemaining, currentTime, baseColor)
    draw.RoundedBox(8, 8, barY, width - 16, barHeight, TOOL_UI.COLORS.PROGRESS.BG_OUTER)
    draw.RoundedBox(8, 9, barY + 1, width - 18, barHeight - 2, TOOL_UI.COLORS.PROGRESS.BG_INNER)

    local barWidth = (width - 20) * progress

    if barWidth > 2 then
        draw.RoundedBox(8, 10, barY + 2, barWidth, barHeight - 4, baseColor)

        local shineOpacity = math.abs(math.sin(state.glowPhase)) * 40
        surface.SetDrawColor(TOOL_UI.COLORS.PROGRESS.SHINE.r, TOOL_UI.COLORS.PROGRESS.SHINE.g,
            TOOL_UI.COLORS.PROGRESS.SHINE.b, shineOpacity)
        surface.DrawRect(10, barY + 2, barWidth, 2)

        if timeRemaining < TOOL_UI.ANIMATION.PULSE_THRESHOLD then
            local pulseIntensity = math.sin(state.pulsePhase) * 0.1 + 0.9
            local pulseColor = Color(
                baseColor.r * pulseIntensity,
                baseColor.g * pulseIntensity,
                baseColor.b * pulseIntensity
            )
            draw.RoundedBox(8, 10, barY + 2, barWidth, barHeight - 4, pulseColor)
        end
    end

    local steps = 4
    for i = 1, steps - 1 do
        local stepX = 10 + (width - 20) * (i / steps)
        surface.SetDrawColor(TOOL_UI.COLORS.PROGRESS.STEP)
        surface.DrawRect(stepX - 0.5, barY + 4, 1, barHeight - 8)
    end

    local textY = barY + barHeight / 2
    local infoText = state and state.cachedCountdownText or ("Saving in: " .. math.floor(timeRemaining) .. "s")
    local textColor = TOOL_UI.COLORS.TEXT.NORMAL

    if timeRemaining < TOOL_UI.ANIMATION.PULSE_THRESHOLD then
        textColor = TOOL_UI.COLORS.TEXT.WARNING

        if timeRemaining < TOOL_UI.ANIMATION.BLINK_THRESHOLD then
            local blink = math.sin(currentTime * 10) > 0
            textColor = blink and TOOL_UI.COLORS.TEXT.URGENT_1 or TOOL_UI.COLORS.TEXT.URGENT_2
        end
    end

    draw.SimpleText(infoText, "CTNV", width / 2 + 1, textY + 1, TOOL_UI.COLORS.TEXT.SHADOW, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(infoText, "CTNV", width / 2, textY, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function getProgressColor(progress)
    if progress < 0.3 then
        return TOOL_UI.COLORS.PROGRESS.LOW
    elseif progress < 0.7 then
        return TOOL_UI.COLORS.PROGRESS.MEDIUM
    else
        return TOOL_UI.COLORS.PROGRESS.HIGH
    end
end

local function drawStatusEmoji(x, y, size, isSuccess, alpha, animProgress)
    animProgress = animProgress or 1

    local bgColor = isSuccess and TOOL_UI.COLORS.EMOJI.DATA_FOUND or TOOL_UI.COLORS.EMOJI.NO_DATA

    local bgSize = size * math.min(1, animProgress * 1.3)
    draw.NoTexture()

    surface.SetDrawColor(bgColor.r, bgColor.g, bgColor.b, alpha * 0.3)
    RareloadUI.DrawCircle(x, y, bgSize + 4, 40)
    RareloadUI.DrawCircle(x, y, bgSize + 4, 40, Color(bgColor.r, bgColor.g, bgColor.b, alpha * 0.3))

    surface.SetDrawColor(bgColor.r, bgColor.g, bgColor.b, alpha)
    RareloadUI.DrawCircle(x, y, bgSize, 40)
    RareloadUI.DrawCircle(x, y, bgSize, 40, Color(bgColor.r, bgColor.g, bgColor.b, alpha))

    if isSuccess then
        if animProgress < 0.3 then return end

        local checkProgress = math.min(1, (animProgress - 0.3) / 0.6)
        local checkSize = size * 0.90

        local startX = x - checkSize * 0.3
        local startY = y + checkSize * 0.1
        local midX = x - checkSize * 0.05
        local midY = y + checkSize * 0.35
        local endX = x + checkSize * 0.5
        local endY = y - checkSize * 0.4

        local easeProgress = checkProgress < 0.5
            and 2 * checkProgress * checkProgress
            or 1 - math.pow(-2 * checkProgress + 2, 2) / 2

        local firstSegmentProgress = math.min(1, easeProgress * 1.7)
        if firstSegmentProgress > 0 then
            local currentMidX = startX + (midX - startX) * firstSegmentProgress
            local currentMidY = startY + (midY - startY) * firstSegmentProgress

            local thickness = math.max(2, size * 0.12)
            local angle = math.atan2(currentMidY - startY, currentMidX - startX)
            local perpX = math.sin(angle) * thickness / 2
            local perpY = -math.cos(angle) * thickness / 2

            local poly = {
                { x = startX + perpX,      y = startY + perpY },
                { x = currentMidX + perpX, y = currentMidY + perpY },
                { x = currentMidX - perpX, y = currentMidY - perpY },
                { x = startX - perpX,      y = startY - perpY }
            }

            surface.SetDrawColor(255, 255, 255, alpha)
            surface.DrawPoly(poly)
            RareloadUI.DrawCircle(startX, startY, thickness / 2, 12, Color(255, 255, 255, alpha))
            if firstSegmentProgress >= 0.95 then
                RareloadUI.DrawCircle(midX, midY, thickness / 2, 12, Color(255, 255, 255, alpha))
            end
        end

        local secondSegmentProgress = math.max(0, (easeProgress - 0.4) * 1.7)
        if secondSegmentProgress > 0 then
            secondSegmentProgress = math.min(1, secondSegmentProgress)
            local currentEndX = midX + (endX - midX) * secondSegmentProgress
            local currentEndY = midY + (endY - midY) * secondSegmentProgress

            local thickness = math.max(2, size * 0.12)
            local angle = math.atan2(currentEndY - midY, currentEndX - midX)
            local perpX = math.sin(angle) * thickness / 2
            local perpY = -math.cos(angle) * thickness / 2

            local poly = {
                { x = midX + perpX,        y = midY + perpY },
                { x = currentEndX + perpX, y = currentEndY + perpY },
                { x = currentEndX - perpX, y = currentEndY - perpY },
                { x = midX - perpX,        y = midY - perpY }
            }

            surface.SetDrawColor(255, 255, 255, alpha)
            surface.DrawPoly(poly)
            if secondSegmentProgress >= 0.95 then
                RareloadUI.DrawCircle(currentEndX, currentEndY, thickness / 2, 12, Color(255, 255, 255, alpha))
            end
        end
    else
        if animProgress < 0.3 then return end

        local crossProgress = math.min(1, (animProgress - 0.3) / 0.6)
        local thickness = math.max(2, size * 0.1)
        local crossSize = size * 0.45

        if crossProgress <= 0.5 then
            local lineProgress = crossProgress * 2
            local endX = x - crossSize + (crossSize * 2) * lineProgress
            local endY = y - crossSize + (crossSize * 2) * lineProgress

            for i = 0, thickness do
                surface.SetDrawColor(255, 255, 255, alpha)
                surface.DrawLine(
                    x - crossSize, y - crossSize,
                    endX, endY
                )
            end

            local angle = math.atan2((endY - (y - crossSize)), (endX - (x - crossSize)))
            local perpX = math.sin(angle) * (thickness / 2)
            local perpY = -math.cos(angle) * (thickness / 2)

            surface.SetDrawColor(255, 255, 255, alpha)
            surface.DrawPoly({
                { x = x - crossSize + perpX, y = y - crossSize + perpY },
                { x = endX + perpX,          y = endY + perpY },
                { x = endX - perpX,          y = endY - perpY },
                { x = x - crossSize - perpX, y = y - crossSize - perpY }
            })
        else
            surface.SetDrawColor(255, 255, 255, alpha)

            local angle = math.atan2((y + crossSize) - (y - crossSize), (x + crossSize) - (x - crossSize))
            local perpX = math.sin(angle) * (thickness / 2)
            local perpY = -math.cos(angle) * (thickness / 2)

            surface.DrawPoly({
                { x = x - crossSize + perpX, y = y - crossSize + perpY },
                { x = x + crossSize + perpX, y = y + crossSize + perpY },
                { x = x + crossSize - perpX, y = y + crossSize - perpY },
                { x = x - crossSize - perpX, y = y - crossSize - perpY }
            })

            local lineProgress = (crossProgress - 0.5) * 2
            local endX = x + crossSize - (crossSize * 2) * lineProgress
            local endY = y - crossSize + (crossSize * 2) * lineProgress

            angle = math.atan2(endY - (y - crossSize), endX - (x + crossSize))
            perpX = math.sin(angle) * (thickness / 2)
            perpY = -math.cos(angle) * (thickness / 2)

            surface.DrawPoly({
                { x = x + crossSize + perpX, y = y - crossSize + perpY },
                { x = endX + perpX,          y = endY + perpY },
                { x = endX - perpX,          y = endY - perpY },
                { x = x + crossSize - perpX, y = y - crossSize - perpY }
            })
        end
    end

    surface.SetDrawColor(255, 255, 255, alpha * 0.15)
    local highlightSize = bgSize * 0.9
    local arcSegments = 10
    for i = 0, arcSegments do
        local a1 = math.rad(200 + (i / arcSegments) * 140)
        local a2 = math.rad(200 + ((i + 1) / arcSegments) * 140)

        local x1 = x + math.cos(a1) * highlightSize
        local y1 = y + math.sin(a1) * highlightSize
        local x2 = x + math.cos(a2) * highlightSize
        local y2 = y + math.sin(a2) * highlightSize

        surface.DrawLine(x1, y1, x2, y2)
    end
end

local function drawReloadStateImage(width, height)
    if not RARELOAD.reloadImageState then return end

    if not RARELOAD.reloadImageState.animStartTime then
        RARELOAD.reloadImageState.animStartTime = CurTime()
    end

    if CurTime() - RARELOAD.reloadImageState.showTime > RARELOAD.reloadImageState.duration then
        RARELOAD.reloadImageState = nil
        return
    end

    local alpha = 255
    local remainingTime = RARELOAD.reloadImageState.duration - (CurTime() - RARELOAD.reloadImageState.showTime)
    if remainingTime < 0.5 then
        alpha = remainingTime * 510
    end

    local animProgress = math.Clamp((CurTime() - RARELOAD.reloadImageState.animStartTime) / 0.8, 0, 1)

    surface.SetDrawColor(30, 30, 35, math.min(200, alpha))
    surface.DrawRect(0, 0, width, height)

    local emojiSize = math.min(width, height) * 0.3
    local centerX = width / 2
    local centerY = height / 2 - height * 0.1

    drawStatusEmoji(centerX, centerY, emojiSize, RARELOAD.reloadImageState.hasData, alpha, animProgress)

    local text = RARELOAD.reloadImageState.hasData and "Position Data Found" or "No Position Data"
    local textY = (height / 2) + 60

    if animProgress > 0.7 then
        local textAlpha = math.min(alpha, ((animProgress - 0.7) / 0.3) * 255)
        draw.SimpleText(text, "CTNV2", width / 2 + 2, textY + 2, Color(0, 0, 0, textAlpha), TEXT_ALIGN_CENTER)
        draw.SimpleText(text, "CTNV2", width / 2, textY, Color(255, 255, 255, textAlpha), TEXT_ALIGN_CENTER)
    end
end

function ToolScreen.Draw(self, width, height, RARELOAD, loadAddonSettings)
    cam.Start2D()
    width = width or 256
    height = height or 256

    assert(RARELOAD, "RARELOAD table required")
    assert(loadAddonSettings, "loadAddonSettings function required")

    if not RARELOAD.cachedSettings or RealTime() > (RARELOAD.nextCacheUpdate or 0) then
        local success, err = pcall(loadAddonSettings)
        if not success then
            ErrorNoHalt("Failed to load addon state: " .. tostring(err))
            return
        end
        RARELOAD.cachedSettings = table.Copy(RARELOAD.settings or {})
        RARELOAD.nextCacheUpdate = RealTime() + 2
    end

    local settings = RARELOAD.cachedSettings
    local colors = TOOL_UI.COLORS
    local layout = TOOL_UI.LAYOUT

    local state = initAnimState(RARELOAD)
    local currentTime = CurTime()
    local ft = FrameTime()

    -- Drive phases for subtle animations (were static before)
    state.glowPhase = (state.glowPhase + ft * 2) % (math.pi * 2)
    state.pulsePhase = (state.pulsePhase + ft * 6) % (math.pi * 2)

    local totalFeatureHeight = #FEATURES * layout.FEATURE_SPACING
    local visibleHeight = height - layout.FEATURE_START_Y - 30
    local maxScrollOffset = math.max(0, totalFeatureHeight - visibleHeight)

    state.nextScrollTime = state.nextScrollTime or currentTime

    if maxScrollOffset > 0 then
        if currentTime > (state.nextScrollTime or 0) then
            if state.scrollDirection == 1 and state.targetScrollOffset >= maxScrollOffset then
                state.scrollDirection = -1
                state.nextScrollTime = currentTime + state.scrollPauseTime
            elseif state.scrollDirection == -1 and state.targetScrollOffset <= 0 then
                state.scrollDirection = 1
                state.nextScrollTime = currentTime + state.scrollPauseTime
            else
                state.targetScrollOffset = math.Clamp(
                    state.targetScrollOffset + state.scrollDirection * state.scrollSpeed * FrameTime(),
                    0, maxScrollOffset
                )
            end
        end

        state.scrollOffset = Lerp(FrameTime() * 3, state.scrollOffset, state.targetScrollOffset)
    end

    surface.SetDrawColor(colors.BG)
    surface.DrawRect(0, 0, width, height)
    -- Header with gradient accent
    surface.SetDrawColor(colors.HEADER)
    surface.DrawRect(0, 0, width, 50)
    if GRADIENT_U then
        surface.SetMaterial(GRADIENT_U)
        surface.SetDrawColor(255, 255, 255, 35)
        surface.DrawTexturedRect(0, 0, width, 50)
    end

    draw.SimpleText("RARELOAD", "CTNV2", width / 2, 25, colors.TEXT_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local isEnabled = settings.addonEnabled
    local statusColor = isEnabled and colors.ENABLED or colors.DISABLED
    -- Status pill
    surface.SetDrawColor(statusColor)
    draw.RoundedBox(8, 10, 60, width - 20, 30, statusColor)
    if GRADIENT_R then
        surface.SetMaterial(GRADIENT_R)
        surface.SetDrawColor(255, 255, 255, 20)
        surface.DrawTexturedRect(10, 60, width - 20, 30)
    end

    local statusText = isEnabled and "ENABLED" or "DISABLED"
    local textColor = isEnabled and colors.TEXT_DARK or colors.TEXT_LIGHT
    draw.SimpleText(statusText, "CTNV", width / 2, 75, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    render.SetScissorRect(0, layout.FEATURE_START_Y, width, height - 30, true)

    for i, cfg in ipairs(FEATURES) do
        local y = layout.FEATURE_START_Y + (i - 1) * layout.FEATURE_SPACING - state.scrollOffset

        if y + layout.FEATURE_SPACING > layout.FEATURE_START_Y and y < height - 30 then
            local iconSize = layout.FEATURE_ICON_SIZE
            local value = settings[cfg.key]

            -- Row background (zebra stripes for readability)
            if i % 2 == 0 then
                surface.SetDrawColor(255, 255, 255, 6)
                surface.DrawRect(8, y - 2, width - 16, layout.FEATURE_SPACING)
            end

            if cfg.kind == "value" then
                -- Left accent dot (header color)
                draw.RoundedBox(iconSize / 2, 12, y + 2, iconSize, iconSize - 4, colors.HEADER)

                draw.SimpleText(cfg.name, "CTNV", 40, y + iconSize / 2, colors.TEXT_LIGHT,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                local valueText = value ~= nil and tostring(value) or "-"
                if cfg.unit and valueText ~= "-" then valueText = valueText .. (cfg.unit or "") end
                draw.SimpleText(valueText, "CTNV", width - 15, y + iconSize / 2, colors.TEXT_LIGHT,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            else
                local on = value and true or false
                local dotColor = on and colors.ENABLED or colors.DISABLED

                -- Modern pill indicator instead of circle (less overdraw, cleaner look)
                draw.RoundedBox(iconSize / 2, 12, y + 2, iconSize, iconSize - 4, dotColor)

                draw.SimpleText(cfg.name, "CTNV", 40, y + iconSize / 2, colors.TEXT_LIGHT,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(on and "ON" or "OFF", "CTNV", width - 15, y + iconSize / 2, dotColor,
                    TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end

    render.SetScissorRect(0, 0, 0, 0, false)

    if settings.autoSaveEnabled and settings.autoSaveInterval then
        local currentTime = CurTime()
        local lastSave = RARELOAD.serverLastSaveTime or 0
        local lastMove = RARELOAD.lastMoveTime or currentTime
        local interval = math.max(settings.autoSaveInterval, 0.1)

        if RARELOAD.showAutoSaveMessage then
            local barHeight = TOOL_UI.LAYOUT.BAR_HEIGHT
            local barY = height - 22
            drawAutoSaveMessage(width, height, barY, barHeight)
        else
            local timeElapsed = math.max(0, currentTime - lastMove)
            local progress = math.Clamp(timeElapsed / interval, 0, 1)

            local barHeight = TOOL_UI.LAYOUT.BAR_HEIGHT
            local barY = height - 22
            local timeRemaining = math.max(0, interval - timeElapsed)

            -- Cache countdown text per second to avoid string churn
            local remainInt = math.floor(timeRemaining)
            if remainInt ~= state.lastRemainingSecond then
                state.cachedCountdownText = "Saving in: " .. remainInt .. "s"
                state.lastRemainingSecond = remainInt
            end

            RARELOAD.activeProgress = (progress > 0 and progress < 1)

            if progress >= 1 then
                state.waitingForTrigger = true
            end

            local baseColor = getProgressColor(progress)
            if state.waitingForTrigger then
                drawWaitingForTriggerBar(width, height, state, barY, barHeight, currentTime, baseColor)
            else
                drawProgressBar(width, height, state, barY, barHeight, progress, timeRemaining, currentTime, baseColor)
            end
        end
    end

    if not RARELOAD.reloadImageState then
        draw.SimpleText("v2.0", "CTNV", width - 10, height - 5, TOOL_UI.COLORS.VERSION, TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_BOTTOM)
    else
        drawReloadStateImage(width, height)
    end
end

function ToolScreen.EndDraw()
    render.SetScissorRect(0, 0, 0, 0, false)
    cam.End2D()
end

return ToolScreen
