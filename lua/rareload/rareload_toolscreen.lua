local UI = include("rareload/rareload_ui.lua")

RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

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
        lastProgress = 0,
        waitingForTrigger = false,
        scrollOffset = 0,
        targetScrollOffset = 0,
        scrollDirection = 1,
        nextScrollTime = CurTime(),
        scrollPauseTime = 5,
        scrollSpeed = 15
    }
    return RARELOAD.AnimState
end

local function drawWaitingForTriggerBar(width, height, state, barY, barHeight, currentTime, baseColor)
    draw.RoundedBox(4, 8, barY, width - 16, barHeight, TOOL_UI.COLORS.PROGRESS.BG_OUTER)
    draw.RoundedBox(4, 9, barY + 1, width - 18, barHeight - 2, TOOL_UI.COLORS.PROGRESS.BG_INNER)
    draw.RoundedBox(3, 10, barY + 2, width - 20, barHeight - 4, baseColor)

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

    local keyFeatures = {
        { name = "Move Type",             enabled = settings.spawnModeEnabled },
        { name = "Auto Save",             enabled = settings.autoSaveEnabled },
        { name = "Save Inventory",        enabled = settings.retainInventory },
        { name = "Save Global Inventory", enabled = settings.retainGlobalInventory },
        { name = "Save Ammo",             enabled = settings.retainAmmo },
        { name = "Save Health and Armor", enabled = settings.retainHealthArmor },
        { name = "Save Entities",         enabled = settings.retainMapEntities },
        { name = "Save NPCs",             enabled = settings.retainMapNPCs },
        --  { name = "Save Vehicles",  enabled = settings.retainVehicles },
        --  { name = "Save Vehicule State", enabled = settings.retainVehicleState },
        { name = "Debug Mode",            enabled = settings.debugEnabled },
        { name = "Auto Save Interval",    enabled = settings.autoSaveInterval },
        --  { name = "Max Distance",          enabled = settings.maxDistance },
        { name = "Angle Tolerance",       enabled = settings.angleTolerance },
        { name = "Max History Size",      enabled = settings.maxHistorySize }

    }

    local totalFeatureHeight = #keyFeatures * layout.FEATURE_SPACING
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
    surface.SetDrawColor(colors.HEADER)
    surface.DrawRect(0, 0, width, 50)

    draw.SimpleText("RARELOAD", "CTNV2", width / 2, 25, colors.TEXT_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local isEnabled = settings.addonEnabled
    local statusColor = isEnabled and colors.ENABLED or colors.DISABLED
    surface.SetDrawColor(statusColor)
    surface.DrawRect(10, 60, width - 20, 30)

    local statusText = isEnabled and "ENABLED" or "DISABLED"
    local textColor = isEnabled and colors.TEXT_DARK or colors.TEXT_LIGHT
    draw.SimpleText(statusText, "CTNV", width / 2, 75, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    render.SetScissorRect(0, layout.FEATURE_START_Y, width, height - 30, true)

    for i, feature in ipairs(keyFeatures) do
        local y = layout.FEATURE_START_Y + (i - 1) * layout.FEATURE_SPACING - state.scrollOffset

        if y + layout.FEATURE_SPACING > layout.FEATURE_START_Y and y < height - 30 then
            local iconSize = layout.FEATURE_ICON_SIZE

            local isValueSetting = feature.name == "Angle Tolerance" or
                feature.name == "Auto Save Interval" or
                feature.name == "Max Distance" or
                feature.name == "Max History Size"

            if isValueSetting then
                local value = feature.enabled
                local valueText = tostring(value)

                surface.SetDrawColor(colors.HEADER)
                draw.NoTexture()
                UI.DrawCircle(20, y + iconSize / 2, iconSize / 2, 20, colors.HEADER)

                draw.SimpleText(feature.name, "CTNV", 40, y + iconSize / 2, colors.TEXT_LIGHT, TEXT_ALIGN_LEFT,
                    TEXT_ALIGN_CENTER)
                draw.SimpleText(valueText, "CTNV", width - 15, y + iconSize / 2, colors.TEXT_LIGHT, TEXT_ALIGN_RIGHT,
                    TEXT_ALIGN_CENTER)
            else
                local dotColor = feature.enabled and colors.ENABLED or colors.DISABLED

                surface.SetDrawColor(dotColor)
                draw.NoTexture()
                UI.DrawCircle(20, y + iconSize / 2, iconSize / 2, 20, dotColor)

                draw.SimpleText(feature.name, "CTNV", 40, y + iconSize / 2, colors.TEXT_LIGHT, TEXT_ALIGN_LEFT,
                    TEXT_ALIGN_CENTER)
                local stateText = feature.enabled and "ON" or "OFF"
                draw.SimpleText(stateText, "CTNV", width - 15, y + iconSize / 2, dotColor, TEXT_ALIGN_RIGHT,
                    TEXT_ALIGN_CENTER)
            end
        end
    end

    render.SetScissorRect(0, 0, 0, 0, false)

    if settings.autoSaveEnabled and settings.autoSaveInterval then
        local currentTime = CurTime()
        local lastSave = RARELOAD.serverLastSaveTime or 0
        local interval = math.max(settings.autoSaveInterval, 0.1)

        local timeElapsed = math.max(0, currentTime - lastSave)
        local progress

        if state.waitingForTrigger then
            progress = 1
        else
            progress = math.Clamp(timeElapsed / interval, 0, 1)
        end

        local barHeight = TOOL_UI.LAYOUT.BAR_HEIGHT
        local barY = height - 22
        local timeRemaining = state.waitingForTrigger and 0 or math.max(0, interval - timeElapsed)

        if progress >= 1 and not state.showingMessage and not state.waitingForTrigger then
            state.showingMessage = true
            state.lastSaveTime = currentTime
            state.messageOpacity = 1
            state.waitingForTrigger = true

            if currentTime - lastSave >= interval * 0.95 then
                RARELOAD.serverLastSaveTime = currentTime
            end
        end

        if RARELOAD.newAutoSaveTrigger and RARELOAD.newAutoSaveTrigger > lastSave then
            state.waitingForTrigger = false
            RARELOAD.serverLastSaveTime = RARELOAD.newAutoSaveTrigger
            RARELOAD.newAutoSaveTrigger = nil
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


        local baseColor = getProgressColor(progress)
        if state.waitingForTrigger then
            drawWaitingForTriggerBar(width, height, state, barY, barHeight, currentTime, baseColor)
        else
            drawProgressBar(width, height, state, barY, barHeight, progress, timeRemaining, currentTime, baseColor)
        end
    end

    draw.SimpleText("v2.0", "CTNV", width - 10, height - 5, TOOL_UI.COLORS.VERSION, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
end

function ToolScreen.EndDraw()
    render.SetScissorRect(0, 0, 0, 0, false)
    cam.End2D()
end

return ToolScreen
