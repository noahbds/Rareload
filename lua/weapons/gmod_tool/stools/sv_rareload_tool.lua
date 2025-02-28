---@diagnostic disable: undefined-field, param-type-mismatch


local RARELOAD           = RARELOAD or {}
RARELOAD.settings        = RARELOAD.settings or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}

TOOL                     = TOOL or {}
TOOL.Category            = "Rareload"
TOOL.Name                = "Rareload Config Tool"
TOOL.Command             = nil
TOOL.ConfigName          = ""

if CLIENT then
    language.Add("tool.sv_rareload_tool.name", "Rareload Configuration Panel")
    language.Add("tool.sv_rareload_tool.desc", "Configuration Panel For Rareload Addon.")
    language.Add("tool.sv_rareload_tool.0", "By Noahbds")

    local fontParams = { font = "Arial", size = 20.9, weight = 2000, antialias = true, additive = false }
    local fontParams2 = { font = "Arial", size = 31, weight = 2000, antialias = true, additive = false }

    surface.CreateFont("CTNV", fontParams)
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

    -- Palette de couleurs pour l'UI
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

    -- Fonction de création de slider réutilisable
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

        -- Description si tooltip fourni
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
        valueDisplay:SetContentAlignment(6) -- Aligné à droite
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

        -- Personnalisation visuelle du slider
        slider.Slider.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, h / 2 - 2, w, 4, UI_COLORS.slider_groove)

            -- Dessiner les graduations
            local steps = 5
            local stepSize = w / steps
            for i = 0, steps do
                local x = i * stepSize
                draw.RoundedBox(1, x - 1, h / 2 - 4, 2, 8, UI_COLORS.slider_notch)
            end
        end

        -- Personnalisation du knob
        slider.Slider.Knob.Paint = function(self, w, h)
            local color = self:IsHovered() and UI_COLORS.slider_grip_hover or UI_COLORS.slider_grip
            draw.RoundedBox(6, 0, 0, w, h, color)
        end

        -- Mettre à jour l'affichage de la valeur
        local function updateDisplay()
            local val = slider:GetValue()
            local displayText = string.format(decimals > 0 and "%." .. decimals .. "f%s" or "%d%s", val, unit or "")
            valueDisplay:SetText(displayText)
        end

        updateDisplay() -- Initialisation

        slider.OnValueChanged = function(self, val)
            updateDisplay()
            RunConsoleCommand(command, val)

            -- Animation de confirmation
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

    -- Création des sliders avec la nouvelle fonction
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

    -- Séparateur visuel
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


    -------------------------------------------------------------------------]
    ---------------------------Toolgun Saved Npcs And Entities Information---]
    -------------------------------------------------------------------------]

    -- This code bellow is not tested and may not work as intended also it's spaguetti code (AND IT'S WAY TOO LONG)

    panel:Button("Open Entity Viewer", "entity_viewer_open")

    if CLIENT then
        local THEME = {
            background = Color(35, 35, 40),
            header = Color(45, 45, 55),
            panel = Color(55, 55, 65),
            panelHighlight = Color(65, 65, 80),
            accent = Color(80, 140, 240),
            dangerAccent = Color(240, 80, 80),
            text = Color(235, 235, 245),
            textDark = Color(50, 50, 60),
            border = Color(75, 75, 85)
        }

        surface.CreateFont("RareloadHeader", {
            font = "Roboto",
            size = 22,
            weight = 600,
            antialias = true
        })

        surface.CreateFont("RareloadText", {
            font = "Roboto",
            size = 16,
            weight = 500,
            antialias = true
        })

        surface.CreateFont("RareloadSmall", {
            font = "Roboto",
            size = 14,
            weight = 400,
            antialias = true
        })

        local function ShowNotification(message, type)
            type = type or NOTIFY_GENERIC
            notification.AddLegacy(message, type, 4)
            surface.PlaySound(type == NOTIFY_ERROR and "buttons/button10.wav" or "buttons/button15.wav")
        end

        -- Used to create a panel with information about an entity or NPC
        local function CreateInfoPanel(parent, data, isNPC, onDeleted)
            ---@class DPanel
            local panel = vgui.Create("DPanel", parent)
            panel:Dock(TOP)
            panel:SetTall(140)
            panel:DockMargin(5, 5, 5, 5)
            panel:SetAlpha(0)

            panel:AlphaTo(255, 0.3, 0)

            panel.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, THEME.border)
                draw.RoundedBox(8, 1, 1, w - 2, h - 2, THEME.panel)

                if self.IsHovered then
                    draw.RoundedBox(8, 1, 1, w - 2, h - 2, THEME.panelHighlight)
                end
            end

            panel.OnCursorEntered = function(self)
                self.IsHovered = function() return true end
                surface.PlaySound("ui/buttonrollover.wav")
            end

            panel.OnCursorExited = function(self)
                self.IsHovered = function() return true end
            end

            -- Crate a panel for 3D models
            local modelPanel = vgui.Create("DModelPanel", panel)
            modelPanel:SetSize(120, 120)
            modelPanel:Dock(LEFT)
            modelPanel:DockMargin(10, 10, 10, 10)

            if data.model and util.IsValidModel(data.model) then
                modelPanel:SetModel(data.model)

                local min, max = modelPanel.Entity:GetRenderBounds()
                local center = (min + max) * 0.5
                local size = max:Distance(min)

                modelPanel:SetLookAt(center)
                modelPanel:SetCamPos(center + Vector(size * 0.6, size * 0.6, size * 0.4))

                local oldPaint = modelPanel.Paint
                -- Rotate the model
                modelPanel.Paint = function(self, w, h)
                    if self.Entity and IsValid(self.Entity) then
                        self.Entity:SetAngles(Angle(0, RealTime() * 30 % 360, 0))
                    end
                    oldPaint(self, w, h)
                end

                modelPanel.PaintOver = function(self, w, h)
                    draw.RoundedBox(100, w / 2 - 40, h - 20, 80, 12, Color(0, 0, 0, 50))
                end
            else
                modelPanel.Paint = function(self, w, h)
                    draw.RoundedBox(8, 0, 0, w, h, THEME.panelHighlight)
                    draw.SimpleText("No Model", "RareloadText", w / 2, h / 2, THEME.text, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                end
            end

            local infoContainer = vgui.Create("DPanel", panel)
            infoContainer:Dock(FILL)
            infoContainer:DockMargin(5, 5, 5, 5)
            infoContainer.Paint = function() end

            local header = vgui.Create("DLabel", infoContainer)
            header:SetText(data.class or "Unknown Entity")
            header:SetFont("RareloadHeader")
            header:SetTextColor(THEME.accent)
            header:Dock(TOP)
            header:DockMargin(5, 2, 0, 3)

            local detailsPanel = vgui.Create("DPanel", infoContainer)
            detailsPanel:Dock(TOP)
            detailsPanel:SetTall(60)
            detailsPanel.Paint = function() end

            local leftColumn = vgui.Create("DPanel", detailsPanel)
            leftColumn:Dock(LEFT)
            leftColumn:SetWide(infoContainer:GetWide() * 0.5)
            leftColumn.Paint = function() end

            local function AddInfoLine(parent, label, value, color, tooltip)
                local container = vgui.Create("DPanel", parent)
                container:Dock(TOP)
                container:SetTall(18)
                container:DockMargin(5, 1, 0, 1)
                container.Paint = function() end

                local labelText = vgui.Create("DLabel", container)
                labelText:SetText(label .. ":")
                labelText:SetTextColor(THEME.text)
                labelText:SetFont("RareloadSmall")
                labelText:SetWide(70)
                labelText:Dock(LEFT)

                local valueText = vgui.Create("DLabel", container)
                valueText:SetText(value)
                valueText:SetTextColor(color or THEME.accent)
                valueText:SetFont("RareloadSmall")
                valueText:Dock(FILL)

                if tooltip then
                    container:SetTooltip(tooltip)

                    local infoIcon = vgui.Create("DPanel", container)
                    infoIcon:SetSize(16, 16)
                    infoIcon:SetPos(container:GetWide() - 20, 1)
                    infoIcon.Paint = function(self, w, h)
                        draw.RoundedBox(8, 0, 0, w, h, THEME.accent)
                        draw.SimpleText("i", "RareloadSmall", w / 2, h / 2, THEME.text, TEXT_ALIGN_CENTER,
                            TEXT_ALIGN_CENTER)
                    end
                end

                return container
            end

            if data.health then
                AddInfoLine(leftColumn, "Health", tostring(data.health),
                    data.health > 50 and Color(100, 255, 100) or Color(255, 100, 100),
                    "Saved health value with which the entity will reappear. This is not necessarily the current health of the entity in question.")
            end

            if not isNPC then
                AddInfoLine(leftColumn, "Frozen", data.frozen and "Yes" or "No",
                    "Saved frozen state value with which the entity will reappear. This is not necessarily the current frozen state of the entity in question.")
            end

            if isNPC and data.weapons and #data.weapons > 0 then
                AddInfoLine(leftColumn, "Weapons", #data.weapons > 2
                    and data.weapons[1] .. " +" .. (#data.weapons - 1)
                    or table.concat(data.weapons, ", "),
                    "Saved weapons with which the NPC will reappear. This is not necessarily the current weapons of the NPC in question.")
            end

            local rightColumn = vgui.Create("DPanel", detailsPanel)
            rightColumn:Dock(FILL)
            rightColumn.Paint = function() end

            if data.pos and data.pos.x and data.pos.y and data.pos.z then
                local posText = string.format("Vector(%.1f, %.1f, %.1f)",
                    data.pos.x, data.pos.y, data.pos.z)

                AddInfoLine(rightColumn, "Position", posText)

                -- Distance from the player
                local ply = LocalPlayer()
                if IsValid(ply) then
                    local distance = ply:GetPos():Distance(Vector(data.pos.x, data.pos.y, data.pos.z))
                    local distText = string.format("%.0f units", distance)
                    AddInfoLine(rightColumn, "Distance", distText)
                end
            else
                AddInfoLine(rightColumn, "Position", "Unknown", Color(255, 100, 100))
            end

            local buttonContainer = vgui.Create("DPanel", panel)
            buttonContainer:Dock(BOTTOM)
            buttonContainer:SetTall(30)
            buttonContainer:DockMargin(10, 0, 10, 10)
            buttonContainer.Paint = function() end

            local function CreateStyledButton(parent, text, icon, color, onClick)
                ---@class DButton
                local btn = vgui.Create("DButton", parent)
                btn:SetText("")
                btn:SetWide(parent:GetWide() * 0.3)
                btn:Dock(LEFT)
                btn:DockMargin(0, 0, 5, 0)

                btn.Paint = function(self, w, h)
                    local bgColor = self:IsHovered() and Color(color.r * 1.2, color.g * 1.2, color.b * 1.2) or color
                    draw.RoundedBox(4, 0, 0, w, h, bgColor)

                    if self:IsDown() then
                        draw.RoundedBox(4, 2, 2, w - 4, h - 4, Color(0, 0, 0, 50))
                    end
                end

                btn.PaintOver = function(self, w, h)
                    draw.SimpleText(text, "RareloadSmall", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)

                    if icon then
                        surface.SetDrawColor(255, 255, 255, 180)
                        surface.SetMaterial(icon)
                        surface.DrawTexturedRect(8, h / 2 - 8, 16, 16)
                    end
                end

                btn.DoClick = function()
                    surface.PlaySound("ui/buttonclickrelease.wav")
                    onClick()
                end

                return btn
            end

            local copyIcon = Material("icon16/page_copy.png")
            local teleportIcon = Material("icon16/arrow_right.png")
            local deleteIcon = Material("icon16/cross.png")

            CreateStyledButton(buttonContainer, "Copy Position", copyIcon, THEME.accent, function()
                if data.pos then
                    SetClipboardText(string.format("Vector(%s, %s, %s)", data.pos.x, data.pos.y, data.pos.z))
                    ShowNotification("Position copied to clipboard!", NOTIFY_GENERIC)
                end
            end)

            CreateStyledButton(buttonContainer, "Teleport", teleportIcon, Color(80, 180, 80), function()
                if data.pos then
                    RunConsoleCommand("rareload_teleport_to", data.pos.x, data.pos.y, data.pos.z)
                    ShowNotification("Teleporting to position!", NOTIFY_GENERIC)
                else
                    ShowNotification("Invalid position data!", NOTIFY_ERROR)
                end
            end)

            CreateStyledButton(buttonContainer, "Delete", deleteIcon, THEME.dangerAccent, function()
                panel:AlphaTo(0, 0.3, 0, function()
                    local frameW, frameH = ScrW() * 0.25, ScrH() * 0.15
                    local confirmFrame = vgui.Create("DFrame")
                    confirmFrame:SetSize(frameW, frameH)
                    confirmFrame:SetTitle("Confirm Deletion")
                    confirmFrame:SetBackgroundBlur(true)
                    confirmFrame:Center()
                    confirmFrame:MakePopup()

                    confirmFrame.Paint = function(self, w, h)
                        draw.RoundedBox(8, 0, 0, w, h, THEME.background)
                        draw.RoundedBox(4, 0, 0, w, 24, THEME.header)
                    end

                    local message = vgui.Create("DLabel", confirmFrame)
                    message:SetText("Are you sure you want to delete this " .. (isNPC and "NPC" or "entity") .. "?")
                    message:SetFont("RareloadText")
                    message:SetTextColor(THEME.text)
                    message:SetContentAlignment(5)
                    message:Dock(TOP)
                    message:DockMargin(10, 30, 10, 10)

                    local buttonPanel = vgui.Create("DPanel", confirmFrame)
                    buttonPanel:Dock(BOTTOM)
                    buttonPanel:SetTall(40)
                    buttonPanel:DockMargin(10, 0, 10, 10)
                    buttonPanel.Paint = function() end

                    local yesButton = vgui.Create("DButton", buttonPanel)
                    yesButton:SetText("Delete")
                    yesButton:SetTextColor(Color(255, 255, 255))
                    yesButton:SetFont("RareloadText")
                    yesButton:Dock(LEFT)
                    yesButton:SetWide((frameW - 40) / 2)

                    yesButton.Paint = function(self, w, h)
                        local color = self:IsHovered() and Color(255, 80, 80) or Color(220, 60, 60)
                        draw.RoundedBox(4, 0, 0, w, h, color)
                    end

                    yesButton.DoClick = function()
                        local mapName = game.GetMap()
                        local filePath = "rareload/player_positions_" .. mapName .. ".json"

                        if file.Exists(filePath, "DATA") then
                            local jsonData = file.Read(filePath, "DATA")
                            local success, rawData = pcall(util.JSONToTable, jsonData)

                            if success and rawData and rawData[mapName] then
                                local deleted = false

                                for steamID, playerData in pairs(rawData[mapName]) do
                                    local entityType = isNPC and "npcs" or "entities"

                                    if playerData[entityType] then
                                        for i, entity in ipairs(playerData[entityType]) do
                                            if entity.class == data.class and
                                                entity.pos.x == data.pos.x and
                                                entity.pos.y == data.pos.y and
                                                entity.pos.z == data.pos.z then
                                                table.remove(playerData[entityType], i)
                                                deleted = true
                                                break
                                            end
                                        end
                                    end

                                    if deleted then break end
                                end

                                if deleted then
                                    file.Write(filePath, util.TableToJSON(rawData, true))
                                    net.Start("RareloadReloadData")
                                    net.SendToServer()
                                    ShowNotification("Entity deleted successfully!", NOTIFY_GENERIC)

                                    if onDeleted then
                                        onDeleted()
                                    end
                                else
                                    ShowNotification("Couldn't find the entity to delete!", NOTIFY_ERROR)
                                    panel:AlphaTo(255, 0.3, 0)
                                end
                            end
                        end

                        confirmFrame:Close()
                    end

                    local noButton = vgui.Create("DButton", buttonPanel)
                    noButton:SetText("Cancel")
                    noButton:SetTextColor(Color(255, 255, 255))
                    noButton:SetFont("RareloadText")
                    noButton:Dock(RIGHT)
                    noButton:SetWide((frameW - 40) / 2)

                    noButton.Paint = function(self, w, h)
                        local color = self:IsHovered() and Color(70, 70, 80) or Color(60, 60, 70)
                        draw.RoundedBox(4, 0, 0, w, h, color)
                    end

                    noButton.DoClick = function()
                        panel:AlphaTo(255, 0.3, 0)
                        confirmFrame:Close()
                    end
                end)
            end)

            return panel
        end

        local function CreateCategory(parent, title, dataList, isNPC, filter)
            if not dataList or #dataList == 0 then return nil end

            local filteredData = {}
            if filter and filter ~= "" then
                local lowerFilter = string.lower(filter)
                for _, data in ipairs(dataList) do
                    if string.find(string.lower(data.class or ""), lowerFilter) then
                        table.insert(filteredData, data)
                    end
                end
                dataList = filteredData
            end

            if #dataList == 0 then
                return nil
            end

            -- Utiliser un panneau normal au lieu d'un DCollapsibleCategory pour éviter les problèmes
            local mainContainer = vgui.Create("DPanel", parent)
            mainContainer:Dock(TOP)
            mainContainer:DockMargin(10, 10, 10, 0)
            mainContainer:SetPaintBackground(false)

            -- Calculer la hauteur approximative nécessaire
            local itemHeight = 140 -- Hauteur d'un panneau d'info
            local headerHeight = 30
            local marginHeight = 10
            local maxVisibleItems = 3
            local contentHeight = math.min(#dataList, maxVisibleItems) * (itemHeight + marginHeight)

            -- Hauteur initiale pour le header uniquement (état replié)
            mainContainer:SetTall(headerHeight)

            -- État d'expansion
            local isExpanded = true

            -- Créer le header qui agit comme un bouton pour replier/déplier
            local header = vgui.Create("DButton", mainContainer)
            header:SetText("")
            header:Dock(TOP)
            header:SetTall(headerHeight)
            header:SetCursor("hand")

            -- Mettre à jour l'apparence et le comportement du header
            header.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, THEME.header)

                -- Indicateur d'expansion
                surface.SetDrawColor(THEME.text)
                surface.SetMaterial(Material(isExpanded and "icon16/arrow_down.png" or "icon16/arrow_right.png"))
                surface.DrawTexturedRect(w - 24, h / 2 - 8, 16, 16)

                -- Texte du header
                draw.SimpleText(title .. " (" .. #dataList .. ")", "RareloadText", 10, h / 2, THEME.text, TEXT_ALIGN_LEFT,
                    TEXT_ALIGN_CENTER)
            end

            -- Conteneur pour le contenu
            local contentContainer = vgui.Create("DPanel", mainContainer)
            contentContainer:Dock(FILL)
            contentContainer:SetPaintBackground(false)
            contentContainer:DockMargin(5, 5, 5, 5)
            contentContainer:SetVisible(isExpanded)

            -- Panneau de défilement pour le contenu
            local scrollPanel = vgui.Create("DScrollPanel", contentContainer)
            scrollPanel:Dock(FILL)

            -- Configurer la barre de défilement
            local scrollbar = scrollPanel:GetVBar()
            if IsValid(scrollbar) then
                scrollbar:SetWide(8)
                scrollbar.Paint = function(_, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, THEME.background)
                end
                scrollbar.btnUp.Paint = function(_, w, h)
                    draw.RoundedBox(4, 2, 0, w - 4, h - 2, THEME.accent)
                end
                scrollbar.btnDown.Paint = function(_, w, h)
                    draw.RoundedBox(4, 2, 2, w - 4, h - 2, THEME.accent)
                end
                scrollbar.btnGrip.Paint = function(_, w, h)
                    draw.RoundedBox(4, 2, 0, w - 4, h, THEME.accent)
                end
            end

            -- Trier les données alphabétiquement
            table.sort(dataList, function(a, b)
                return (a.class or "") < (b.class or "")
            end)

            -- Ajouter les panneaux d'information
            for _, data in ipairs(dataList) do
                local infoPanel = CreateInfoPanel(scrollPanel, data, isNPC, function()
                    -- Logique lorsqu'un élément est supprimé
                    local remainingItems = #dataList - 1
                    header.Paint = function(self, w, h)
                        draw.RoundedBox(8, 0, 0, w, h, THEME.header)
                        surface.SetDrawColor(THEME.text)
                        surface.SetMaterial(Material(isExpanded and "icon16/arrow_down.png" or "icon16/arrow_right.png"))
                        surface.DrawTexturedRect(w - 24, h / 2 - 8, 16, 16)
                        draw.SimpleText(title .. " (" .. remainingItems .. ")", "RareloadText", 10, h / 2, THEME.text,
                            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end

                    if remainingItems <= 0 then
                        mainContainer:AlphaTo(0, 0.3, 0, function()
                            mainContainer:Remove()
                        end)
                    end
                end)
            end

            -- Fonction pour basculer l'état d'expansion
            local function ToggleExpansion()
                isExpanded = not isExpanded

                if isExpanded then
                    mainContainer:SetTall(headerHeight + contentHeight)
                    contentContainer:SetVisible(true)

                    -- Animation d'ouverture
                    contentContainer:SetAlpha(0)
                    contentContainer:AlphaTo(255, 0.2, 0)
                else
                    contentContainer:SetVisible(false)
                    mainContainer:SetTall(headerHeight)
                end
            end

            -- Activer/désactiver l'expansion lorsqu'on clique sur le header
            header.DoClick = function()
                surface.PlaySound("ui/buttonclick.wav")
                ToggleExpansion()
            end

            -- Définir la hauteur initiale (déplié par défaut)
            mainContainer:SetTall(headerHeight + contentHeight)

            -- S'assurer que le conteneur reste déplié initialement
            timer.Simple(0.1, function()
                if IsValid(mainContainer) then
                    mainContainer:SetTall(headerHeight + contentHeight)
                    contentContainer:SetVisible(true)
                end
            end)

            -- S'assurer que le conteneur reste déplié quelques instants plus tard
            timer.Simple(0.5, function()
                if IsValid(mainContainer) and isExpanded then
                    mainContainer:SetTall(headerHeight + contentHeight)
                    contentContainer:SetVisible(true)
                end
            end)

            return mainContainer
        end

        local function OpenEntityViewer()
            ---@class DFrame
            local frame = vgui.Create("DFrame")
            frame:SetSize(ScrW() * 0.7, ScrH() * 0.8)
            frame:SetTitle("Rareload Entity & NPC Viewer - " .. game.GetMap())
            frame:SetIcon("icon16/database_connect.png")
            frame:Center()
            frame:MakePopup()
            frame:SetDraggable(true)
            frame:SetSizable(true)
            frame:SetMinWidth(800)
            frame:SetMinHeight(500)
            frame:SetBackgroundBlur(true)
            frame:SetAlpha(0)
            frame:AlphaTo(255, 0.3, 0)

            frame.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, THEME.background)
                draw.RoundedBox(4, 0, 0, w, 24, THEME.header)
            end

            local oldClose = frame.Close
            frame.Close = function(self)
                self:AlphaTo(0, 0.3, 0, function()
                    oldClose(self)
                end)
            end

            local headerPanel = vgui.Create("DPanel", frame)
            headerPanel:Dock(TOP)
            headerPanel:SetTall(40)
            headerPanel:DockMargin(5, 5, 5, 5)
            headerPanel.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, THEME.panel)
            end

            local infoLabel = vgui.Create("DLabel", headerPanel)
            infoLabel:SetText("Browse, teleport to, or delete saved entities and NPCs")
            infoLabel:SetFont("RareloadText")
            infoLabel:SetTextColor(THEME.text)
            infoLabel:Dock(LEFT)
            infoLabel:DockMargin(10, 0, 10, 0)
            infoLabel:SizeToContents()

            ---@class DTextEntry
            local searchBar = vgui.Create("DTextEntry", headerPanel)
            searchBar:SetPlaceholderText("Search by class name...")
            searchBar:Dock(RIGHT)
            searchBar:SetWide(250)
            searchBar:DockMargin(5, 5, 10, 5)

            ---@class DPropertySheet
            local tabs = vgui.Create("DPropertySheet", frame)
            tabs:Dock(FILL)
            tabs:DockMargin(5, 5, 5, 5)

            tabs.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, THEME.panel)
            end

            local function CreateTab(title, icon, isNPC)
                local scroll = vgui.Create("DScrollPanel")

                ---@class DVScrollBar
                local scrollbar = scroll:GetVBar()
                scrollbar:SetWide(8)
                scrollbar.Paint = function(_, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, THEME.background)
                end
                scrollbar.btnUp.Paint = function(_, w, h)
                    draw.RoundedBox(4, 2, 0, w - 4, h - 2, THEME.accent)
                end
                scrollbar.btnDown.Paint = function(_, w, h)
                    draw.RoundedBox(4, 2, 2, w - 4, h - 2, THEME.accent)
                end
                scrollbar.btnGrip.Paint = function(_, w, h)
                    draw.RoundedBox(4, 2, 0, w - 4, h, THEME.accent)
                end

                local sheet = tabs:AddSheet(title, scroll, icon)
                sheet.Panel:SetPos(0, 0)

                return scroll
            end

            local entityScroll = CreateTab("Entities", "icon16/bricks.png", false)
            local npcScroll = CreateTab("NPCs", "icon16/user.png", true)

            local function CreateErrorPanel(parent, title, message, icon)
                ---@class DPanel
                local panel = vgui.Create("DPanel", parent)
                panel:Dock(FILL)
                panel:DockMargin(20, 20, 20, 20)
                panel.Paint = function(self, w, h)
                    draw.RoundedBox(8, 0, 0, w, h, THEME.panel)

                    if icon then
                        surface.SetDrawColor(THEME.dangerAccent)
                        surface.SetMaterial(icon)
                        surface.DrawTexturedRect(w / 2 - 32, h / 2 - 60, 64, 64)
                    end

                    draw.SimpleText(title, "RareloadHeader", w / 2, h / 2, THEME.dangerAccent, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                    draw.SimpleText(message, "RareloadText", w / 2, h / 2 + 30, THEME.text, TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER)
                end

                return panel
            end

            local function LoadData(filter)
                entityScroll:Clear()
                npcScroll:Clear()

                local mapName = game.GetMap()
                local filePath = "rareload/player_positions_" .. mapName .. ".json"

                local errorIcon = Material("icon16/exclamation.png")
                local warningIcon = Material("icon16/error.png")

                if not file.Exists(filePath, "DATA") then
                    CreateErrorPanel(entityScroll, "No Data Found", "No saved entities or NPCs found for " .. mapName,
                        errorIcon)
                    CreateErrorPanel(npcScroll, "No Data Found", "No saved entities or NPCs found for " .. mapName,
                        errorIcon)
                    return
                end

                local jsonData = file.Read(filePath, "DATA")
                local success, rawData = pcall(util.JSONToTable, jsonData)

                if not success or not rawData or not rawData[mapName] then
                    local errorMessage = not success and "Error parsing JSON data" or "Invalid data format"
                    CreateErrorPanel(entityScroll, "Data Error", errorMessage, warningIcon)
                    CreateErrorPanel(npcScroll, "Data Error", errorMessage, warningIcon)
                    return
                end

                local entityCount, npcCount = 0, 0
                local entityCategories, npcCategories = 0, 0

                for steamID, playerData in pairs(rawData[mapName]) do
                    if playerData.entities and #playerData.entities > 0 then
                        local category = CreateCategory(entityScroll, "Player: " .. steamID, playerData.entities, false,
                            filter)
                        if category then
                            entityCategories = entityCategories + 1
                            entityCount = entityCount + #playerData.entities
                        end
                    end

                    if playerData.npcs and #playerData.npcs > 0 then
                        local category = CreateCategory(npcScroll, "Player: " .. steamID, playerData.npcs, true, filter)
                        if category then
                            npcCategories = npcCategories + 1
                            npcCount = npcCount + #playerData.npcs
                        end
                    end
                end

                if entityCount == 0 then
                    CreateErrorPanel(entityScroll, "No Entities Found",
                        filter and "No entities match your search criteria" or "No saved entities found for this map",
                        errorIcon)
                end

                if npcCount == 0 then
                    CreateErrorPanel(npcScroll, "No NPCs Found",
                        filter and "No NPCs match your search criteria" or "No saved NPCs found for this map", errorIcon)
                end

                for k, tab in pairs(tabs.Items) do
                    if tab.Name == "Entities" then
                        tab.Name = "Entities (" .. entityCount .. ")"
                    elseif tab.Name == "NPCs" then
                        tab.Name = "NPCs (" .. npcCount .. ")"
                    end
                end

                infoLabel:SetText(string.format("Found %d entities in %d categories and %d NPCs in %d categories",
                    entityCount, entityCategories, npcCount, npcCategories))
            end

            LoadData()

            local searchDelay = 0
            searchBar.OnChange = function()
                local searchText = searchBar:GetValue()

                if searchDelay then
                    timer.Remove("RareloadSearch")
                end

                timer.Create("RareloadSearch", 0.3, 1, function()
                    LoadData(searchText)
                end)
            end

            local refreshButton = vgui.Create("DButton", headerPanel)
            refreshButton:SetText("")
            refreshButton:SetSize(30, 30)
            refreshButton:SetPos(headerPanel:GetWide() - 300, 5)
            refreshButton:DockMargin(0, 0, 10, 0)
            refreshButton.Paint = function(self, w, h)
                local color = self:IsHovered() and
                    Color(THEME.accent.r * 1.2, THEME.accent.g * 1.2, THEME.accent.b * 1.2) or THEME.accent
                draw.RoundedBox(4, 0, 0, w, h, color)

                surface.SetDrawColor(255, 255, 255)
                surface.SetMaterial(Material("icon16/arrow_refresh.png"))
                surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
            end
            refreshButton.DoClick = function()
                surface.PlaySound("ui/buttonclickrelease.wav")
                ShowNotification("Refreshing data...", NOTIFY_GENERIC)
                LoadData(searchBar:GetValue())
            end

            frame.OnSizeChanged = function(self, w, h)
                headerPanel:SetWide(w - 10)
                refreshButton:SetPos(searchBar:GetX() - 40, 5)

                if tabs and tabs.Items then
                    for _, tab in pairs(tabs.Items) do
                        local panel = tab.Panel
                        if IsValid(panel) then
                            panel:SetTall(h - 100)
                        end
                    end
                end
            end

            if not ConVarExists("rareload_teleport_to") then
                concommand.Add("rareload_teleport_to", function(ply, cmd, args)
                    if not IsValid(ply) or not ply:IsPlayer() then return end

                    local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
                    if not x or not y or not z then return end

                    local pos = Vector(x, y, z)
                    net.Start("RareloadTeleportTo")
                    net.WriteVector(pos)
                    net.SendToServer()
                end)
            end
        end

        concommand.Add("entity_viewer_open", OpenEntityViewer)

        if CLIENT then
            net.Receive("RareloadTeleportTo", function()
                local pos = net.ReadVector()
            end)
        end
    end

    ------------------------------------------------------------------------]
    ---------------------------------------------End of Toolgun Options-----]
    ------------------------------------------------------------------------]
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
        local infoText = "Save: " .. settings.autoSaveInterval .. "s"
        draw.SimpleText(infoText, "CTNV", width / 2, height - 15, Color(200, 200, 200), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    draw.SimpleText("v2", "CTNV", width - 10, height - 10, Color(150, 150, 150, 180), TEXT_ALIGN_RIGHT,
        TEXT_ALIGN_BOTTOM)
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
