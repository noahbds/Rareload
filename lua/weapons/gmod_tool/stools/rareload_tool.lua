---@class RARELOAD
local RARELOAD              = RARELOAD or {}
RARELOAD.settings           = RARELOAD.settings or {}
RARELOAD.playerPositions    = RARELOAD.playerPositions or {}
RARELOAD.serverLastSaveTime = 0

TOOL                        = TOOL or {}
TOOL.Category               = "Rareload"
TOOL.Name                   = "Rareload Config Tool"
TOOL.Command                = nil
TOOL.ConfigName             = ""

local UI                    = {
    COLORS = {
        ENABLED = Color(50, 150, 255),
        DISABLED = Color(255, 50, 50),
        SLIDER = {
            BACKGROUND = Color(40, 40, 45, 200),
            GROOVE = Color(60, 60, 70),
            NOTCH = Color(80, 80, 90),
            GRIP = Color(80, 140, 240),
            GRIP_HOVER = Color(100, 160, 255)
        },
        TEXT = {
            PRIMARY = Color(255, 255, 255),
            SECONDARY = Color(200, 200, 220)
        },
        SAVE_BUTTON = Color(0, 122, 204)
    },
    MARGINS = {
        STANDARD = { 30, 10, 30, 0 },
        SLIDERS = { 30, 10, 30, 5 }
    }
}

if CLIENT then
    language.Add("tool.rareload_tool.name", "Rareload Configuration Panel")
    language.Add("tool.rareload_tool.desc", "Configuration Panel For Rareload Addon.")
    language.Add("tool.rareload_tool.0", "By Noahbds")

    surface.CreateFont("RARELOAD_NORMAL", {
        font = "Arial",
        size = 20.9,
        weight = 2000,
        antialias = true,
        additive = false
    })

    surface.CreateFont("RARELOAD_LARGE", {
        font = "Arial",
        size = 31,
        weight = 2000,
        antialias = true,
        additive = false
    })

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
        antialias = true
    })

    net.Receive("RareloadSyncAutoSaveTime", function()
        RARELOAD.serverLastSaveTime = net.ReadFloat()
    end)

    function draw.Circle(x, y, radius, segments)
        local points = {}
        for i = 0, segments do
            local angle = math.rad((i / segments) * 360)
            table.insert(points, {
                x = x + math.cos(angle) * radius,
                y = y + math.sin(angle) * radius
            })
        end

        surface.DrawPoly(points)
    end
end


local function loadAddonSettings()
    local addonStateFilePath = "rareload/addon_state.json"

    if not file.Exists(addonStateFilePath, "DATA") then
        return false, "Settings file does not exist"
    end

    local json = file.Read(addonStateFilePath, "DATA")
    if not json or json == "" then
        return false, "Settings file is empty"
    end

    local settings = util.JSONToTable(json)
    if not settings then
        return false, "Failed to parse settings JSON"
    end

    RARELOAD.settings = settings
    return true, nil
end


local function createToggleButton(parent, text, command, tooltip, isEnabled)
    local button = vgui.Create("DButton", parent)
    button:SetText(text)
    button:Dock(TOP)
    button:DockMargin(unpack(UI.MARGINS.STANDARD))
    button:SetSize(250, 30)

    local color = isEnabled and UI.COLORS.ENABLED or UI.COLORS.DISABLED
    button:SetTextColor(color)
    button:SetColor(color)

    button.DoClick = function()
        RunConsoleCommand(command)
        local currentColor = button:GetColor()
        local newColor = currentColor == UI.COLORS.ENABLED and UI.COLORS.DISABLED or UI.COLORS.ENABLED
        button:SetColor(newColor)
        button:SetTextColor(newColor)
    end

    if tooltip then
        button:SetTooltip(tooltip)
    end

    return button
end


local function createSettingSlider(panel, title, command, min, max, decimals, defaultValue, tooltip, unit)
    local container = vgui.Create("DPanel", panel)
    container:Dock(TOP)
    container:SetTall(60)
    container:DockMargin(unpack(UI.MARGINS.SLIDERS))
    container:SetPaintBackground(false)

    local header = vgui.Create("DLabel", container)
    header:SetText(title)
    header:SetTextColor(UI.COLORS.TEXT.PRIMARY)
    header:SetFont("DermaDefaultBold")
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 2)

    if tooltip then
        local desc = vgui.Create("DLabel", container)
        desc:SetText(tooltip)
        desc:SetTextColor(UI.COLORS.TEXT.SECONDARY)
        desc:SetFont("DermaDefault")
        desc:Dock(TOP)
        desc:DockMargin(0, 0, 0, 4)
        desc:SetWrap(true)
        desc:SetTall(18)
    end

    local sliderContainer = vgui.Create("DPanel", container)
    sliderContainer:Dock(FILL)
    sliderContainer:DockPadding(0, 0, 0, 0)
    sliderContainer:SetPaintBackground(false)

    local valueDisplay = vgui.Create("DLabel", sliderContainer)
    valueDisplay:SetSize(50, 20)
    valueDisplay:Dock(RIGHT)
    valueDisplay:SetContentAlignment(6)
    valueDisplay:SetTextColor(UI.COLORS.SLIDER.GRIP)

    ---@class DNumSlider
    local slider = vgui.Create("DNumSlider", sliderContainer)
    slider:Dock(FILL)
    slider:SetMin(min)
    slider:SetMax(max)
    slider:SetDecimals(decimals)
    slider:SetDefaultValue(defaultValue)
    slider:SetValue(defaultValue)
    slider:SetDark(false)

    slider.Slider.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, h / 2 - 2, w, 4, UI.COLORS.SLIDER.GROOVE)

        local steps = 5
        local stepSize = w / steps
        for i = 0, steps do
            local x = i * stepSize
            draw.RoundedBox(1, x - 1, h / 2 - 4, 2, 8, UI.COLORS.SLIDER.NOTCH)
        end
    end

    slider.Slider.Knob.Paint = function(self, w, h)
        local color = self:IsHovered() and UI.COLORS.SLIDER.GRIP_HOVER or UI.COLORS.SLIDER.GRIP
        draw.RoundedBox(6, 0, 0, w, h, color)
    end

    local function updateDisplay()
        local val = slider:GetValue()
        local displayText = string.format(decimals > 0 and "%." .. decimals .. "f%s" or "%d%s", val, unit or "")
        valueDisplay:SetText(displayText)
    end

    updateDisplay()

    slider.OnValueChanged = function(self, val)
        updateDisplay()
        RunConsoleCommand(command, val)

        local flash = vgui.Create("DPanel", slider)
        flash:SetSize(slider:GetWide(), slider:GetTall())
        flash:SetPos(0, 0)
        flash:SetAlpha(80)
        flash.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, UI.COLORS.SLIDER.GRIP)
        end
        flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)
    end

    return container, slider
end

local function createSeparator(panel)
    local separator = vgui.Create("DPanel", panel)
    separator:Dock(TOP)
    separator:SetTall(1)
    separator:DockMargin(40, 10, 40, 10)
    separator.Paint = function(self, w, h)
        surface.SetDrawColor(70, 70, 80, 180)
        surface.DrawLine(0, 0, w, 0)
    end
    return separator
end


local function createSavePositionButton(panel)
    local button = vgui.Create("DButton", panel)
    button:SetText("Save Position")
    button:SetTextColor(UI.COLORS.TEXT.PRIMARY)
    button:SetFont("DermaLarge")
    button:Dock(TOP)
    button:DockMargin(unpack(UI.MARGINS.STANDARD))
    button:SetSize(250, 40)

    button.Paint = function(self, w, h)
        local baseColor = UI.COLORS.SAVE_BUTTON
        local color

        if self:IsHovered() then
            color = Color(
                math.min(baseColor.r + 30, 255),
                math.min(baseColor.g + 30, 255),
                math.min(baseColor.b + 30, 255),
                baseColor.a
            )
        else
            color = baseColor
        end

        draw.RoundedBox(8, 0, 0, w, h, color)
    end

    button.DoClick = function()
        RunConsoleCommand("save_position")

        local flash = vgui.Create("DPanel", button)
        flash:SetSize(button:GetWide(), button:GetTall())
        flash:SetPos(0, 0)
        flash:SetAlpha(100)
        flash.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(255, 255, 255))
        end
        flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)
    end

    return button
end

function TOOL.BuildCPanel(panel)
    local success, err = pcall(loadAddonSettings)
    if not success then
        ErrorNoHalt("Failed to load addon settings: " .. (err or "unknown error"))

        local errorLabel = vgui.Create("DLabel", panel)
        errorLabel:SetText("Error loading settings! Please check console.")
        errorLabel:SetTextColor(UI.COLORS.DISABLED)
        errorLabel:Dock(TOP)
        errorLabel:DockMargin(10, 10, 10, 10)
        errorLabel:SetWrap(true)
        errorLabel:SetTall(40)

        return
    end

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    createToggleButton(panel, "Toggle Rareload", "rareload_rareload",
        "Enable or disable Rareload", RARELOAD.settings.addonEnabled)

    createToggleButton(panel, "Toggle Move Type", "rareload_spawn_mode",
        "Switch between different spawn modes", RARELOAD.settings.spawnModeEnabled)

    createToggleButton(panel, "Toggle Auto Save", "rareload_auto_save",
        "Enable or disable auto saving position", RARELOAD.settings.autoSaveEnabled)

    createToggleButton(panel, "Toggle Keep Inventory", "rareload_retain_inventory",
        "Enable or disable retaining inventory", RARELOAD.settings.retainInventory)

    createToggleButton(panel, "Toggle Keep Health and Armor", "rareload_retain_health_armor",
        "Enable or disable retaining health and armor", RARELOAD.settings.retainHealthArmor)

    createToggleButton(panel, "Toggle Keep Ammo", "rareload_retain_ammo",
        "Enable or disable retaining ammo", RARELOAD.settings.retainAmmo)

    createToggleButton(panel, "Toggle Keep Vehicles", "rareload_retain_vehicles",
        "Enable or disable retaining vehicles", RARELOAD.settings.retainVehicle)

    createToggleButton(panel, "Toggle Keep Vehicle State", "rareload_retain_vehicle_state",
        "Enable or disable retaining vehicle state", RARELOAD.settings.retainVehicleState)

    createToggleButton(panel, "Toggle Keep Map Entities", "rareload_retain_map_entities",
        "Enable or disable retaining map entities", RARELOAD.settings.retainMapEntities)

    createToggleButton(panel, "Toggle Keep Map NPCs", "rareload_retain_map_npcs",
        "Enable or disable retaining map NPCs", RARELOAD.settings.retainMapNPCs)

    createToggleButton(panel, "Toggle No Custom Respawn At Death", "rareload_nocustomrespawnatdeath",
        "Enable or disable custom respawn at death", RARELOAD.settings.nocustomrespawnatdeath)

    createToggleButton(panel, "Toggle Debug", "rareload_debug",
        "Enable or disable debug mode", RARELOAD.settings.debugEnabled)

    createToggleButton(panel, "Toggle Global Inventory", "rareload_retain_global_inventory",
        "Enable or disable global inventory", RARELOAD.settings.retainGlobalInventory)

    createSavePositionButton(panel)

    createSettingSlider(
        panel,
        "Auto Save Interval",
        "set_auto_save_interval",
        1, 60, 0,
        RARELOAD.settings.autoSaveInterval or 2,
        "Number of seconds between each automatic position save",
        "s"
    )

    createSettingSlider(
        panel,
        "Max Distance",
        "set_max_distance",
        1, 1000, 0,
        RARELOAD.settings.maxDistance or 50,
        "Maximum distance (in units) at which saved entities will be restored",
        " u"
    )

    createSettingSlider(
        panel,
        "Angle Tolerance",
        "set_angle_tolerance",
        1, 360, 1,
        RARELOAD.settings.angleTolerance or 100.0,
        "Angle tolerance (in degrees) for entity restoration",
        "°"
    )

    createSeparator(panel)

    panel:Button("Open Entity Viewer", "entity_viewer_open")
end

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

-- Initialize animation state once
local function initAnimState()
    if not RARELOAD.AnimState then
        RARELOAD.AnimState = {
            lastSaveTime = 0,
            pulsePhase = 0,
            glowPhase = 0,
            saveDetected = false,
            showingMessage = false,
            messageOpacity = 0
        }
    end
    return RARELOAD.AnimState
end

-- Draw the save confirmation message
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

-- Draw the progress bar for auto-save
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

-- Main drawing function for the tool screen
function TOOL:DrawToolScreen(width, height)
    if not RARELOAD.cachedSettings or RealTime() > (RARELOAD.nextCacheUpdate or 0) then
        local success, err = pcall(loadAddonSettings)
        if not success then
            ErrorNoHalt("Failed to load addon state: " .. err)
            return
        end
        RARELOAD.cachedSettings = table.Copy(RARELOAD.settings or {})
        RARELOAD.nextCacheUpdate = RealTime() + 2
    end

    local settings = RARELOAD.cachedSettings

    surface.SetDrawColor(TOOL_UI.COLORS.BG)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(TOOL_UI.COLORS.HEADER)
    surface.DrawRect(0, 0, width, 50)
    draw.SimpleText("RARELOAD", "CTNV2", width / 2, 25, TOOL_UI.COLORS.TEXT_LIGHT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local isEnabled = settings.addonEnabled
    local statusColor = isEnabled and TOOL_UI.COLORS.ENABLED or TOOL_UI.COLORS.DISABLED
    surface.SetDrawColor(statusColor)
    surface.DrawRect(10, 60, width - 20, 30)

    local statusText = isEnabled and "ENABLED" or "DISABLED"
    local textColor = isEnabled and TOOL_UI.COLORS.TEXT_DARK or TOOL_UI.COLORS.TEXT_LIGHT
    draw.SimpleText(statusText, "CTNV", width / 2, 75, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local keyFeatures = {
        { name = "Auto Save",  enabled = settings.autoSaveEnabled },
        { name = "Move Type",  enabled = settings.spawnModeEnabled },
        { name = "Keep Items", enabled = settings.retainInventory },
        { name = "Death Save", enabled = not settings.nocustomrespawnatdeath },
        { name = "Debug",      enabled = settings.debugEnabled }
    }

    for i, feature in ipairs(keyFeatures) do
        local y = TOOL_UI.LAYOUT.FEATURE_START_Y + (i - 1) * TOOL_UI.LAYOUT.FEATURE_SPACING
        local iconSize = TOOL_UI.LAYOUT.FEATURE_ICON_SIZE
        local dotColor = feature.enabled and TOOL_UI.COLORS.ENABLED or TOOL_UI.COLORS.DISABLED

        surface.SetDrawColor(dotColor)
        draw.NoTexture()
        draw.Circle(20, y + iconSize / 2, iconSize / 2, 20)

        draw.SimpleText(feature.name, "CTNV", 40, y + iconSize / 2, TOOL_UI.COLORS.TEXT_LIGHT, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        local stateText = feature.enabled and "ON" or "OFF"
        draw.SimpleText(stateText, "CTNV", width - 15, y + iconSize / 2, dotColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    if settings.autoSaveEnabled and settings.autoSaveInterval then
        local state = initAnimState()
        local currentTime = CurTime()
        local lastSave = RARELOAD.serverLastSaveTime or 0
        local timeElapsed = currentTime - lastSave
        local timeRemaining = math.max(0, settings.autoSaveInterval - timeElapsed)
        local progress = math.Clamp(timeElapsed / settings.autoSaveInterval, 0, 1)
        local barHeight = TOOL_UI.LAYOUT.BAR_HEIGHT
        local barY = height - 22

        if progress >= 0.999 and not state.saveDetected then
            state.saveDetected = true
            state.lastSaveTime = currentTime
            state.showingMessage = true
            state.messageOpacity = 1
            RARELOAD.serverLastSaveTime = currentTime
            lastSave = RARELOAD.serverLastSaveTime
            timeElapsed = 0
            timeRemaining = settings.autoSaveInterval
            progress = 0
        elseif progress < 0.95 and state.saveDetected then
            state.saveDetected = false
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
