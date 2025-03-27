---@class RARELOAD
local RARELOAD              = RARELOAD or {}
RARELOAD.settings           = RARELOAD.settings or {}
RARELOAD.playerPositions    = RARELOAD.playerPositions or {}
RARELOAD.serverLastSaveTime = 0


TOOL            = TOOL or {}

TOOL.Category   = "Rareload"
TOOL.Name       = "Rareload Config Tool"
TOOL.Command    = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.sv_rareload_tool.name", "Rareload Configuration Panel")
    language.Add("tool.sv_rareload_tool.desc", "Configuration Panel For Rareload Addon.")
    language.Add("tool.sv_rareload_tool.0", "By Noahbds")

    local fontParams = { font = "Arial", size = 20.9, weight = 2000, antialias = true, additive = false }
    local fontParams2 = { font = "Arial", size = 31, weight = 2000, antialias = true, additive = false }

    surface.CreateFont("CTNV", fontParams)

    net.Receive("RareloadSyncAutoSaveTime", function()
        RARELOAD.serverLastSaveTime = net.ReadFloat()
    end)

    surface.CreateFont("CTNV2", fontParams2)
end

local function loadAddonStatefortool()
    local addonStateFilePath = "rareload/addon_state.json"
    if file.Exists(addonStateFilePath, "DATA") then
        local json = file.Read(addonStateFilePath, "DATA")
        RARELOAD.settings = util.JSONToTable(json)
    end
end

local COLOR_ENABLED = Color(50, 150, 255)
local COLOR_DISABLED = Color(255, 50, 50)

local function createButton(parent, text, command, tooltip, isEnabled)
    local button = vgui.Create("DButton", parent)
    button:SetText(text)
    button:Dock(TOP)
    button:DockMargin(30, 10, 30, 0)
    button:SetSize(250, 30)

    local color = isEnabled and COLOR_ENABLED or COLOR_DISABLED
    button:SetTextColor(color)
    button:SetColor(color)

    button.DoClick = function()
        RunConsoleCommand(command)
        local currentColor = button:GetColor()
        local newColor = currentColor == COLOR_ENABLED and COLOR_DISABLED or COLOR_ENABLED
        button:SetColor(newColor)
        button:SetTextColor(newColor)
    end

    if tooltip then
        button:SetTooltip(tooltip)
    end
    return button
end

function TOOL.BuildCPanel(panel)
    local success, err = pcall(loadAddonStatefortool)
    if not success then
        ErrorNoHalt("Failed to load addon state: " .. err)
        return
    end

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    createButton(panel, "Toggle Rareload", "toggle_rareload",
        "Enable or disable Rareload", RARELOAD.settings.addonEnabled)

    createButton(panel, "Toggle Move Type", "toggle_spawn_mode",
        "Switch between different spawn modes", RARELOAD.settings.spawnModeEnabled)

    createButton(panel, "Toggle Auto Save", "toggle_auto_save",
        "Enable or Disable Auto Saving Position", RARELOAD.settings.autoSaveEnabled)

    createButton(panel, "Toggle Keep Inventory", "toggle_retain_inventory",
        "Enable or disable retaining inventory", RARELOAD.settings.retainInventory)

    createButton(panel, "Toggle Keep Health and Armor", "toggle_retain_health_armor",
        "Enable or disable retaining health and armor", RARELOAD.settings.retainHealthArmor)

    createButton(panel, "Toggle Keep Ammo", "toggle_retain_ammo", --UNTESTED

        "Enable or disable retaining ammo", RARELOAD.settings.retainAmmo)

    createButton(panel, "Toggle Keep Vehicles", "toggle_retain_vehicles", --BROKEN
        "Enable or disable retaining vehicles", RARELOAD.settings.retainVehicle)

    createButton(panel, "Toggle Keep Vehicle State", "toggle_retain_vehicle_state", --BROKEN
        "Enable or disable retaining vehicle state", RARELOAD.settings.retainVehicleState)

    createButton(panel, "Toggle Keep Map Entities", "toggle_retain_map_entities",
        "Enable or disable retaining map entities", RARELOAD.settings.retainMapEntities)

    createButton(panel, "Toggle Keep Map NPCs", "toggle_retain_map_npcs",
        "Enable or disable retaining map NPCs", RARELOAD.settings.retainMapNPCs)

    createButton(panel, "Toggle No Custom Respawn At Death", "toggle_nocustomrespawnatdeath",
        "Enable or disable No Custom Respawn At Death", RARELOAD.settings.nocustomrespawnatdeath)

    createButton(panel, "Toggle Debug", "toggle_debug",
        "Enable or disable Debug", RARELOAD.settings.debugEnabled)


    ---@class DButton
    local savePositionButton = vgui.Create("DButton", panel)
    savePositionButton:SetText("Save Position")
    savePositionButton:SetTextColor(Color(255, 255, 255))
    savePositionButton:SetFont("DermaLarge")
    savePositionButton:Dock(TOP)
    savePositionButton:DockMargin(30, 10, 30, 0)
    savePositionButton:SetSize(250, 40)
    savePositionButton.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(0, 122, 204))
    end
    savePositionButton.DoClick = function()
        RunConsoleCommand("save_position")
    end
    ------------------------------------------------------------------------]
    ---------------------------------------------Auto Save Slider Options---]
    ------------------------------------------------------------------------]

    local UI_COLORS = {
        slider_bg = Color(40, 40, 45, 200),
        slider_groove = Color(60, 60, 70),
        slider_notch = Color(80, 80, 90),
        slider_grip = Color(80, 140, 240),
        slider_grip_hover = Color(100, 160, 255),
        text_primary = Color(255, 255, 255),
        text_secondary = Color(200, 200, 220),
        value_display = Color(80, 140, 240, 180)
    }

    local function CreateSettingSlider(panel, title, command, min, max, decimals, defaultValue, tooltip, unit)
        local container = vgui.Create("DPanel", panel)
        container:Dock(TOP)
        container:SetTall(60)
        container:DockMargin(30, 10, 30, 5)
        container:SetPaintBackground(false)

        local header = vgui.Create("DLabel", container)
        header:SetText(title)
        header:SetTextColor(UI_COLORS.text_primary)
        header:SetFont("DermaDefaultBold")
        header:Dock(TOP)
        header:DockMargin(0, 0, 0, 2)

        if tooltip then
            local desc = vgui.Create("DLabel", container)
            desc:SetText(tooltip)
            desc:SetTextColor(UI_COLORS.text_secondary)
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
        valueDisplay:SetTextColor(UI_COLORS.slider_grip)

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
            draw.RoundedBox(4, 0, h / 2 - 2, w, 4, UI_COLORS.slider_groove)

            local steps = 5
            local stepSize = w / steps
            for i = 0, steps do
                local x = i * stepSize
                draw.RoundedBox(1, x - 1, h / 2 - 4, 2, 8, UI_COLORS.slider_notch)
            end
        end

        slider.Slider.Knob.Paint = function(self, w, h)
            local color = self:IsHovered() and UI_COLORS.slider_grip_hover or UI_COLORS.slider_grip
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
                draw.RoundedBox(4, 0, 0, w, h, UI_COLORS.slider_grip)
            end
            flash:AlphaTo(0, 0.3, 0, function() flash:Remove() end)
        end

        return container, slider
    end

    local autoSaveContainer, autoSaveSlider = CreateSettingSlider(
        panel,
        "Auto Save Interval",
        "set_auto_save_interval",
        1, 60, 0,
        RARELOAD.settings.autoSaveInterval or 2,
        "Nombre de secondes entre chaque sauvegarde automatique de la position",
        "s"
    )

    local maxDistanceContainer, maxDistanceSlider = CreateSettingSlider(
        panel,
        "Max Distance",
        "set_max_distance",
        1, 1000, 0,
        RARELOAD.settings.maxDistance or 50,
        "Distance maximale (en unités) à laquelle les entités sauvegardées seront restaurées",
        " u"
    )

    local angleToleranceContainer, angleToleranceSlider = CreateSettingSlider(
        panel,
        "Angle Tolerance",
        "set_angle_tolerance",
        1, 360, 1,
        RARELOAD.settings.angleTolerance or 100.0,
        "Tolérance d'angle (en degrés) pour la restauration des entités",
        "°"
    )

    local separator = vgui.Create("DPanel", panel)
    separator:Dock(TOP)
    separator:SetTall(1)
    separator:DockMargin(40, 10, 40, 10)
    separator.Paint = function(self, w, h)
        surface.SetDrawColor(70, 70, 80, 180)
        surface.DrawLine(0, 0, w, 0)
    end

    ------------------------------------------------------------------------]
    --------------------------------------Fin des options de curseurs-------]
    ------------------------------------------------------------------------]

    panel:Button("Open Entity Viewer", "entity_viewer_open")
end

------------------------------------------------------------------------]
---------------------------------------------Toolgun Screen Options-----]
------------------------------------------------------------------------]

function TOOL:DrawToolScreen(width, height)
    if not RARELOAD.cachedSettings or RealTime() > (RARELOAD.nextCacheUpdate or 0) then
        local success, err = pcall(loadAddonStatefortool)
        if not success then
            ErrorNoHalt("Failed to load addon state: " .. err)
            return
        end
        RARELOAD.cachedSettings = table.Copy(RARELOAD.settings or {})
        RARELOAD.nextCacheUpdate = RealTime() + 2
    end

    local settings = RARELOAD.cachedSettings

    local colors = {
        bg = Color(40, 40, 45),
        enabled = Color(30, 200, 30),
        disabled = Color(200, 30, 30),
        header = Color(50, 100, 200),
        textLight = Color(255, 255, 255),
        textDark = Color(20, 20, 20)
    }

    surface.SetDrawColor(colors.bg)
    surface.DrawRect(0, 0, width, height)

    surface.SetDrawColor(colors.header)
    surface.DrawRect(0, 0, width, 50)

    draw.SimpleText("RARELOAD", "CTNV2", width / 2, 25, colors.textLight, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local isEnabled = settings.addonEnabled
    local statusColor = isEnabled and colors.enabled or colors.disabled
    surface.SetDrawColor(statusColor)
    surface.DrawRect(10, 60, width - 20, 30)

    local statusText = isEnabled and "ENABLED" or "DISABLED"
    local textColor = isEnabled and colors.textDark or colors.textLight
    draw.SimpleText(statusText, "CTNV", width / 2, 75, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local startY = 100
    local iconSize = 20
    local spacing = 28
    local keyFeatures = {
        { name = "Auto Save",  enabled = settings.autoSaveEnabled },
        { name = "Move Type",  enabled = settings.spawnModeEnabled },
        { name = "Keep Items", enabled = settings.retainInventory },
        { name = "Death Save", enabled = not settings.nocustomrespawnatdeath },
        { name = "Debug",      enabled = settings.debugEnabled }
    }

    for i, feature in ipairs(keyFeatures) do
        local y = startY + (i - 1) * spacing
        local dotColor = feature.enabled and colors.enabled or colors.disabled

        surface.SetDrawColor(dotColor)
        draw.NoTexture()
        draw.Circle(20, y + iconSize / 2, iconSize / 2, 20)

        draw.SimpleText(feature.name, "CTNV", 40, y + iconSize / 2, colors.textLight, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local stateText = feature.enabled and "ON" or "OFF"
        draw.SimpleText(stateText, "CTNV", width - 15, y + iconSize / 2, dotColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    if settings.autoSaveEnabled and settings.autoSaveInterval then
        local ANIMATION = {
            SAVE_MESSAGE_DURATION = 5,
            PULSE_THRESHOLD = 3,
            BLINK_THRESHOLD = 1
        }

        local COLORS = {
            BG_OUTER = Color(30, 30, 35),
            BG_INNER = Color(40, 40, 45),
            PROGRESS = {
                LOW = Color(30, 180, 30),
                MEDIUM = Color(180, 180, 30),
                HIGH = Color(180, 60, 30),
            },
            TEXT = {
                NORMAL = Color(220, 220, 220),
                WARNING = Color(255, 255, 0),
                URGENT = { Color(255, 100, 0), Color(255, 220, 0) },
                SAVED = Color(50, 255, 50)
            }
        }

        local currentTime = CurTime()
        local lastSave = RARELOAD.serverLastSaveTime or 0
        local timeElapsed = currentTime - lastSave
        local timeRemaining = math.max(0, settings.autoSaveInterval - timeElapsed)
        local progress = math.Clamp(timeElapsed / settings.autoSaveInterval, 0, 1)

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
        local state = RARELOAD.AnimState

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

            if timeSinceSave > ANIMATION.SAVE_MESSAGE_DURATION then
                state.showingMessage = false
                state.messageOpacity = 0
            elseif timeSinceSave > ANIMATION.SAVE_MESSAGE_DURATION - 1 then
                state.messageOpacity = 1 - (timeSinceSave - (ANIMATION.SAVE_MESSAGE_DURATION - 1))
            end
        end

        state.pulsePhase = (state.pulsePhase + FrameTime() * 8) % (math.pi * 2)
        state.glowPhase = (state.glowPhase + FrameTime() * 1.5) % (math.pi * 2)

        local function GetProgressColor()
            if progress < 0.3 then
                return COLORS.PROGRESS.LOW
            elseif progress < 0.7 then
                return COLORS.PROGRESS.MEDIUM
            else
                return COLORS.PROGRESS.HIGH
            end
        end

        local barHeight = 20
        local barY = height - 22

        if state.showingMessage and state.messageOpacity > 0 then
            local textY = barY + barHeight / 2
            local messageOpacity = math.Clamp(state.messageOpacity * 255, 0, 255)

            if messageOpacity > 0 then
                local savedText = "Position sauvegardée!"
                local textColor = ColorAlpha(COLORS.TEXT.SAVED, messageOpacity)
                local shadowColor = ColorAlpha(Color(0, 0, 0), messageOpacity * 0.7)

                local timeSinceSave = currentTime - state.lastSaveTime
                if timeSinceSave < 1 then
                    local scale = 1 + math.sin(timeSinceSave * math.pi) * 0.1
                    local matrix = Matrix()
                    matrix:Translate(Vector(width / 2, textY, 0))
                    matrix:Scale(Vector(scale, scale, 1))
                    matrix:Translate(Vector(-width / 2, -textY, 0))

                    cam.PushModelMatrix(matrix)
                    draw.SimpleText(savedText, "CTNV", width / 2 + 1, textY + 1, shadowColor, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                    draw.SimpleText(savedText, "CTNV", width / 2, textY, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    cam.PopModelMatrix()
                elseif timeSinceSave < 5 then
                    draw.SimpleText(savedText, "CTNV", width / 2 + 1, textY + 1, shadowColor, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                    draw.SimpleText(savedText, "CTNV", width / 2, textY, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                else
                    state.showingMessage = false
                end
            end
        else
            draw.RoundedBox(4, 8, barY, width - 16, barHeight, COLORS.BG_OUTER)
            draw.RoundedBox(4, 9, barY + 1, width - 18, barHeight - 2, COLORS.BG_INNER)

            local barWidth = (width - 20) * progress
            local baseColor = GetProgressColor()

            if barWidth > 2 then
                draw.RoundedBox(3, 10, barY + 2, barWidth, barHeight - 4, baseColor)

                local shineOpacity = math.abs(math.sin(state.glowPhase)) * 40
                surface.SetDrawColor(255, 255, 255, shineOpacity)
                surface.DrawRect(10, barY + 2, barWidth, 2)

                if timeRemaining < ANIMATION.PULSE_THRESHOLD then
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
                surface.SetDrawColor(255, 255, 255, 40)
                surface.DrawRect(stepX - 0.5, barY + 4, 1, barHeight - 8)
            end

            local textY = barY + barHeight / 2
            local infoText = "Sauvegarde dans : " .. math.floor(timeRemaining) .. "s"
            local textColor = COLORS.TEXT.NORMAL

            if timeRemaining < ANIMATION.PULSE_THRESHOLD then
                textColor = COLORS.TEXT.WARNING

                if timeRemaining < ANIMATION.BLINK_THRESHOLD then
                    local blink = math.sin(currentTime * 10) > 0
                    textColor = blink and COLORS.TEXT.URGENT[1] or COLORS.TEXT.URGENT[2]
                end
            end

            draw.SimpleText(infoText, "CTNV", width / 2 + 1, textY + 1, Color(0, 0, 0, 180), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
            draw.SimpleText(infoText, "CTNV", width / 2, textY, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    draw.SimpleText("v2", "CTNV", width - 10, height - 10, Color(150, 150, 150, 180), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
end

if CLIENT then
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
