local UI = include("rareload/rareload_ui.lua")

local TOOL_UI = UI.TOOL_UI or {
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

-- Register required fonts for the tool screen
local function RegisterFonts()
    surface.CreateFont("CTNV", {
        font = "Roboto",
        size = 18,
        weight = 500,
        antialias = true
    })

    surface.CreateFont("CTNV2", {
        font = "Roboto",
        size = 24,
        weight = 700,
        antialias = true,
        shadow = true
    })
end

if CLIENT then
    RegisterFonts()
end

local ToolScreen = {}

local function initAnimState(RARELOAD)
    RARELOAD.AnimState = RARELOAD.AnimState or {
        lastSaveTime = 0,
        pulsePhase = 0,
        glowPhase = 0,
        showingMessage = false,
        messageOpacity = 0,
        lastProgress = 0
    }
    return RARELOAD.AnimState
end

local function drawSaveMessage(width, height, state, barY, barHeight, currentTime)
    local textY = barY + barHeight / 2
    local messageOpacity = math.Clamp(state.messageOpacity * 255, 0, 255)

    if messageOpacity <= 0 then return end

    local savedText = "Position saved!"
    local textColor = ColorAlpha(TOOL_UI.COLORS.TEXT.SAVED, messageOpacity)
    local shadowColor = ColorAlpha(TOOL_UI.COLORS.TEXT.SHADOW, messageOpacity * 0.7)

    local timeSinceSave = currentTime - state.lastSaveTime
    if timeSinceSave < 1 then
        local scale = 1 + math.sin(timeSinceSave * math.pi) * 0.1
        local matrix = Matrix()
        matrix:Translate(Vector(width / 2, textY, 0))
        matrix:Scale(Vector(scale, scale, 1))
        matrix:Translate(Vector(-width / 2, -textY, 0))

        cam.PushModelMatrix(matrix)
        draw.SimpleText(savedText, "CTNV", width / 2 + 1, textY + 1, shadowColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(savedText, "CTNV", width / 2, textY, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        cam.PopModelMatrix()
    elseif timeSinceSave < TOOL_UI.ANIMATION.SAVE_MESSAGE_DURATION then
        draw.SimpleText(savedText, "CTNV", width / 2 + 1, textY + 1, shadowColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(savedText, "CTNV", width / 2, textY, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        state.showingMessage = false
    end
end

local function drawProgressBar(width, height, state, barY, barHeight, progress, timeRemaining, currentTime, baseColor)
    draw.RoundedBox(4, 8, barY, width - 16, barHeight, TOOL_UI.COLORS.PROGRESS.BG_OUTER)
    draw.RoundedBox(4, 9, barY + 1, width - 18, barHeight - 2, TOOL_UI.COLORS.PROGRESS.BG_INNER)

    local barWidth = (width - 20) * progress

    if barWidth > 2 then
        draw.RoundedBox(3, 10, barY + 2, barWidth, barHeight - 4, baseColor)

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
            draw.RoundedBox(3, 10, barY + 2, barWidth, barHeight - 4, pulseColor)
        end
    end

    local steps = 4
    for i = 1, steps - 1 do
        local stepX = 10 + (width - 20) * (i / steps)
        surface.SetDrawColor(TOOL_UI.COLORS.PROGRESS.STEP)
        surface.DrawRect(stepX - 0.5, barY + 4, 1, barHeight - 8)
    end

    local textY = barY + barHeight / 2
    local infoText = "Saving in: " .. math.floor(timeRemaining) .. "s"
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

function ToolScreen.Draw(self, width, height, RARELOAD, loadAddonSettings)
    -- Ensure width and height are valid numbers to prevent errors
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

    -- Background
    surface.SetDrawColor(colors.BG)
    surface.DrawRect(0, 0, width, height)

    -- Header
    surface.SetDrawColor(colors.HEADER)
    surface.DrawRect(0, 0, width, 50)

    -- Title with proper font
    draw.SimpleText("RARELOAD", "CTNV2", width / 2, 25, colors.TEXT_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local isEnabled = settings.addonEnabled
    local statusColor = isEnabled and colors.ENABLED or colors.DISABLED
    surface.SetDrawColor(statusColor)
    surface.DrawRect(10, 60, width - 20, 30)

    local statusText = isEnabled and "ENABLED" or "DISABLED"
    local textColor = isEnabled and colors.TEXT_DARK or colors.TEXT_LIGHT
    draw.SimpleText(statusText, "CTNV", width / 2, 75, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local keyFeatures = {
        { name = "Auto Save",  enabled = settings.autoSaveEnabled },
        { name = "Move Type",  enabled = settings.spawnModeEnabled },
        { name = "Keep Items", enabled = settings.retainInventory },
        { name = "Death Save", enabled = not settings.nocustomrespawnatdeath },
        { name = "Debug",      enabled = settings.debugEnabled }
    }

    for i, feature in ipairs(keyFeatures) do
        local y = layout.FEATURE_START_Y + (i - 1) * layout.FEATURE_SPACING
        local iconSize = layout.FEATURE_ICON_SIZE
        local dotColor = feature.enabled and colors.ENABLED or colors.DISABLED

        surface.SetDrawColor(dotColor)
        draw.NoTexture()
        UI.DrawCircle(20, y + iconSize / 2, iconSize / 2, 20, dotColor)

        draw.SimpleText(feature.name, "CTNV", 40, y + iconSize / 2, colors.TEXT_LIGHT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local stateText = feature.enabled and "ON" or "OFF"
        draw.SimpleText(stateText, "CTNV", width - 15, y + iconSize / 2, dotColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    if settings.autoSaveEnabled and settings.autoSaveInterval then
        local state = initAnimState(RARELOAD)
        local currentTime = CurTime()
        local lastSave = RARELOAD.serverLastSaveTime or 0
        local interval = math.max(settings.autoSaveInterval, 0.1)
        local timeElapsed = math.max(0, currentTime - lastSave)
        local progress = math.Clamp(timeElapsed / interval, 0, 1)
        local barHeight = TOOL_UI.LAYOUT.BAR_HEIGHT
        local barY = height - 22
        local timeRemaining = math.max(0, interval - timeElapsed)

        if progress >= 1 and not state.showingMessage then
            state.showingMessage = true
            state.lastSaveTime = currentTime
            state.messageOpacity = 1
            if currentTime - lastSave >= interval * 0.95 then
                RARELOAD.serverLastSaveTime = currentTime
            end
        end

        if progress < 0.95 and state.showingMessage and (currentTime - state.lastSaveTime) > 0.5 then
            state.showingMessage = false
            state.messageOpacity = 0
        end

        if state.showingMessage then
            local timeSinceSave = currentTime - state.lastSaveTime
            if timeSinceSave > TOOL_UI.ANIMATION.SAVE_MESSAGE_DURATION then
                state.showingMessage = false
                state.messageOpacity = 0
            elseif timeSinceSave > TOOL_UI.ANIMATION.SAVE_MESSAGE_DURATION - 1 then
                state.messageOpacity = 1 - (timeSinceSave - (TOOL_UI.ANIMATION.SAVE_MESSAGE_DURATION - 1))
            end
        end

        state.pulsePhase = (state.pulsePhase + FrameTime() * 8) % (math.pi * 2)
        state.glowPhase = (state.glowPhase + FrameTime() * 1.5) % (math.pi * 2)

        if state.showingMessage and state.messageOpacity > 0 then
            drawSaveMessage(width, height, state, barY, barHeight, currentTime)
        else
            local baseColor = getProgressColor(progress)
            drawProgressBar(width, height, state, barY, barHeight, progress, timeRemaining, currentTime, baseColor)
        end
    end

    draw.SimpleText("v2.0", "CTNV", width - 10, height - 5, TOOL_UI.COLORS.VERSION, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
end

function ToolScreen.EndDraw()
    -- Reset any render targets if needed
    render.SetRenderTarget(nil)
end

return ToolScreen
