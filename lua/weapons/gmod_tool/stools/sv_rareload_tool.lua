---@diagnostic disable: undefined-field, param-type-mismatch


local RARELOAD  = {}

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

    ---[[ Beta [NOT TESTED] ]]---

    createButton(panel, "Toggle Keep Health and Armor", "toggle_retain_health_armor",
        "Enable or disable retaining health and armor", RARELOAD.settings.retainHealthArmor)

    createButton(panel, "Toggle Keep Ammo", "toggle_retain_ammo",

        "Enable or disable retaining ammo", RARELOAD.settings.retainAmmo)

    createButton(panel, "Toggle Keep Vehicles", "toggle_retain_vehicles",
        "Enable or disable retaining vehicles", RARELOAD.settings.retainVehicle)

    createButton(panel, "Toggle Keep Vehicle State", "toggle_retain_vehicle_state",
        "Enable or disable retaining vehicle state", RARELOAD.settings.retainVehicleState)

    createButton(panel, "Toggle Keep Map Entities", "toggle_retain_map_entities",
        "Enable or disable retaining map entities", RARELOAD.settings.retainMapEntities)

    createButton(panel, "Toggle Keep Map NPCs", "toggle_retain_map_npcs",
        "Enable or disable retaining map NPCs", RARELOAD.settings.retainMapNPCs)

    ---[[End of Beta [NOT TESTED] ]]---

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


    ---@class DNumSlider
    local autoSaveSlider = vgui.Create("DNumSlider", panel)
    autoSaveSlider:SetText("Auto Save Interval")
    autoSaveSlider.Label:SetTextColor(Color(255, 255, 255)) -- Set text color to white
    autoSaveSlider:SetMin(1)
    autoSaveSlider:SetMax(60)
    autoSaveSlider:SetDecimals(0)
    autoSaveSlider:SetValue(RARELOAD.settings.autoSaveInterval or 2)
    autoSaveSlider:Dock(TOP)
    autoSaveSlider:DockMargin(30, 10, 30, 0)
    autoSaveSlider.OnValueChanged = function(self, value)
        RunConsoleCommand("set_auto_save_interval", value)
    end

    local maxDistanceSlider = vgui.Create("DNumSlider", panel)
    maxDistanceSlider:SetText("Max Distance")
    maxDistanceSlider.Label:SetTextColor(Color(255, 255, 255)) -- Set text color to white
    maxDistanceSlider:SetMin(1)
    maxDistanceSlider:SetMax(1000)
    maxDistanceSlider:SetDecimals(0)
    maxDistanceSlider:SetValue(RARELOAD.settings.maxDistance or 50)
    maxDistanceSlider:Dock(TOP)
    maxDistanceSlider:DockMargin(30, 10, 30, 0)
    maxDistanceSlider.OnValueChanged = function(self, value)
        RunConsoleCommand("set_max_distance", value)
    end


    local angleToleranceSlider = vgui.Create("DNumSlider", panel)
    angleToleranceSlider:SetText("Angle Tolerance")
    angleToleranceSlider.Label:SetTextColor(Color(255, 255, 255)) -- Set text color to white
    angleToleranceSlider:SetMin(1)
    angleToleranceSlider:SetMax(360)
    angleToleranceSlider:SetDecimals(1)
    angleToleranceSlider:SetValue(RARELOAD.settings.angleTolerance or 100.0)
    angleToleranceSlider:Dock(TOP)
    angleToleranceSlider:DockMargin(30, 10, 30, 0)
    angleToleranceSlider.OnValueChanged = function(self, value)
        RunConsoleCommand("set_angle_tolerance", value)
    end


    ------------------------------------------------------------------------]
    --------------------------------------End of Auto Save Slider Options---]
    ------------------------------------------------------------------------]


    -------------------------------------------------------------------------]
    ---------------------------Toolgun Saved Npcs And Entities Information---]
    -------------------------------------------------------------------------]

    panel:Button("Open Entity Viewer", "entity_viewer_open")

    if CLIENT then
        local function ShowErrorMessage(parent, message)
            local errorLabel = vgui.Create("DLabel", parent)
            errorLabel:SetText(message)
            errorLabel:SetTextColor(Color(255, 100, 100))
            errorLabel:SetFont("DermaLarge")
            errorLabel:SetContentAlignment(5)
            errorLabel:Dock(TOP)
            errorLabel:DockMargin(10, 10, 10, 10)
        end

        local function CreateInfoPanel(parent, data, isNPC)
            ---@class DPanel
            local panel = vgui.Create("DPanel", parent)
            panel:Dock(TOP)
            panel:SetTall(120)
            panel:DockMargin(5, 5, 5, 5)

            panel.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(45, 45, 48))
                draw.RoundedBox(6, 1, 1, w - 2, h - 2, Color(60, 60, 65))
            end

            local icon = vgui.Create("DModelPanel", panel)
            icon:SetSize(100, 100)
            icon:Dock(LEFT)
            icon:DockMargin(10, 10, 10, 10)
            if data.model and util.IsValidModel(data.model) then
                icon:SetModel(data.model)
                local min, max = icon.Entity:GetRenderBounds()
                local center = (min + max) * 0.5
                icon:SetLookAt(center)
                icon:SetCamPos(center + Vector(50, 0, 0))
            end

            local info = vgui.Create("DLabel", panel)
            info:Dock(FILL)
            info:DockMargin(10, 10, 10, 10)
            info:SetTextColor(Color(255, 255, 255))
            info:SetFont("DermaDefaultBold")
            info:SetWrap(true)
            info:SetContentAlignment(7)

            local function formatInfoText(data, isNPC)
                local infoText = string.format("Class: %s\n", data.class or "Unknown")

                if data.health then
                    infoText = infoText .. string.format("Health: %d\n", data.health)
                end

                if isNPC and data.weapons then
                    infoText = infoText .. "Weapons: " .. table.concat(data.weapons, ", ") .. "\n"
                end

                if not isNPC then
                    infoText = infoText .. string.format("Frozen: %s\n", data.frozen and "Yes" or "No")
                end

                if data.pos and data.pos.x and data.pos.y and data.pos.z then
                    infoText = infoText ..
                        string.format("Position: Vector(%.2f, %.2f, %.2f)", data.pos.x, data.pos.y, data.pos.z)
                else
                    infoText = infoText .. "Position: Unknown\n"
                end

                return infoText
            end

            local infoText = formatInfoText(data, isNPC)
            info:SetText(infoText)

            -- Buttons Container
            local buttonContainer = vgui.Create("DPanel", panel)
            buttonContainer:Dock(BOTTOM)
            buttonContainer:SetTall(30)
            buttonContainer:DockMargin(10, 5, 10, 10)
            buttonContainer.Paint = function() end -- Transparent background

            -- Copy Position Button
            local copyBtn = vgui.Create("DButton", buttonContainer)
            copyBtn:Dock(LEFT)
            copyBtn:SetText("Copy Position")
            copyBtn:SetWide(120)
            copyBtn.DoClick = function()
                SetClipboardText(string.format("Vector(%s, %s, %s)", data.pos.x, data.pos.y, data.pos.z))
                notification.AddLegacy("Position copied to clipboard!", NOTIFY_GENERIC, 3)
                surface.PlaySound("buttons/button15.wav")
            end

            -- Teleport Button
            local teleportBtn = vgui.Create("DButton", buttonContainer)
            teleportBtn:Dock(LEFT)
            teleportBtn:SetText("Teleport")
            teleportBtn:SetWide(100)
            teleportBtn:DockMargin(5, 0, 0, 0)
            teleportBtn.DoClick = function()
                if data.pos then
                    RunConsoleCommand("rareload_teleport_to", data.pos.x, data.pos.y, data.pos.z)
                    notification.AddLegacy("Teleporting to position!", NOTIFY_GENERIC, 3)
                    surface.PlaySound("buttons/button15.wav")
                else
                    notification.AddLegacy("Invalid position data!", NOTIFY_ERROR, 3)
                end
            end

            -- Delete Button
            local deleteBtn = vgui.Create("DButton", buttonContainer)
            deleteBtn:Dock(RIGHT)
            deleteBtn:SetText("Delete")
            deleteBtn:SetWide(80)
            deleteBtn:DockMargin(5, 0, 0, 0)
            deleteBtn:SetTextColor(Color(255, 100, 100))
            deleteBtn.DoClick = function()
                local confirmPanel = vgui.Create("DPanel", panel)
                confirmPanel:SetZPos(999)
                confirmPanel:SetSize(panel:GetWide() - 20, 50)
                confirmPanel:SetPos(10, panel:GetTall() / 2 - 25)
                confirmPanel.Paint = function(self, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, Color(40, 40, 40, 240))
                    surface.SetDrawColor(255, 100, 100)
                    surface.DrawOutlinedRect(0, 0, w, h, 2)
                end

                local confirmLabel = vgui.Create("DLabel", confirmPanel)
                confirmLabel:SetText("Confirm deletion?")
                confirmLabel:SetTextColor(Color(255, 255, 255))
                confirmLabel:SizeToContents()
                confirmLabel:Center()
                confirmLabel:SetPos(confirmLabel:GetX(), 10)

                local btnContainer = vgui.Create("DPanel", confirmPanel)
                btnContainer:SetSize(200, 25)
                btnContainer:SetPos(confirmPanel:GetWide() / 2 - 100, 30)
                btnContainer.Paint = function() end

                local yesBtn = vgui.Create("DButton", btnContainer)
                yesBtn:SetText("Yes")
                yesBtn:SetTextColor(Color(255, 100, 100))
                yesBtn:SetWide(95)
                yesBtn:Dock(LEFT)
                yesBtn.DoClick = function()
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
                                notification.AddLegacy("Entity deleted successfully!", NOTIFY_GENERIC, 3)
                                surface.PlaySound("buttons/button15.wav")

                                panel:Remove()
                            else
                                notification.AddLegacy("Couldn't find the entity to delete!", NOTIFY_ERROR, 3)
                            end
                        end
                    end

                    confirmPanel:Remove()
                end

                local noBtn = vgui.Create("DButton", btnContainer)
                noBtn:SetText("No")
                noBtn:SetWide(95)
                noBtn:Dock(RIGHT)
                noBtn.DoClick = function()
                    confirmPanel:Remove()
                end
            end

            return panel
        end

        local function CreateCategory(parent, title, dataList, isNPC)
            if not dataList or #dataList == 0 then return end

            local category = vgui.Create("DCollapsibleCategory", parent)
            category:SetLabel(title)
            category:Dock(TOP)
            category:DockMargin(10, 10, 10, 0)

            local listPanel = vgui.Create("DPanel", category)
            listPanel:Dock(TOP)
            listPanel:DockMargin(10, 10, 10, 10)
            listPanel:SetTall(500)

            for _, data in ipairs(dataList) do
                CreateInfoPanel(listPanel, data, isNPC)
            end
        end

        local function OpenEntityViewer()
            ---@class DFrame
            local frame = vgui.Create("DFrame")
            frame:SetSize(900, 600)
            frame:SetTitle("Entity & NPC Viewer - " .. game.GetMap())
            frame:Center()
            frame:MakePopup()
            frame:SetBackgroundBlur(true)
            frame:SetSizable(true) -- Allow resizing


            local tabs = vgui.Create("DPropertySheet", frame)
            tabs:Dock(FILL)
            tabs:DockMargin(5, 5, 5, 5)

            local entityScroll = vgui.Create("DScrollPanel")
            local npcScroll = vgui.Create("DScrollPanel")

            tabs:AddSheet("Entities", entityScroll, "icon16/bricks.png")
            tabs:AddSheet("NPCs", npcScroll, "icon16/user.png")

            local mapName = game.GetMap()
            local filePath = "rareload/player_positions_" .. mapName .. ".json"

            if not file.Exists(filePath, "DATA") then
                ShowErrorMessage(frame, "No data found for the map: " .. mapName)
                return
            end

            local jsonData = file.Read(filePath, "DATA")
            local success, rawData = pcall(util.JSONToTable, jsonData)

            if not success or not rawData or not rawData[mapName] then
                ShowErrorMessage(frame, "Invalid data format.")
                return
            end

            for steamID, playerData in pairs(rawData[mapName]) do
                CreateCategory(entityScroll, "Player: " .. steamID, playerData.entities, false)
                CreateCategory(npcScroll, "Player: " .. steamID, playerData.npcs, true)
            end

            -- **Make UI elements responsive to resizing**
            frame.OnSizeChanged = function(self, w, h)
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
end

------------------------------------------------------------------------]
---------------------------------------------Toolgun Screen Options-----]
------------------------------------------------------------------------]

function TOOL:DrawToolScreen(width, height)
    local success, err = pcall(loadAddonStatefortool)
    if not success then
        ErrorNoHalt("Failed to load addon state: " .. err)
        return
    end

    local backgroundColor
    local autoSaveStatusColor

    if RARELOAD.settings.autoSaveEnabled then
        backgroundColor = Color(0, 255, 0)
        autoSaveStatusColor = Color(0, 0, 0)
    else
        backgroundColor = Color(255, 100, 100)
        autoSaveStatusColor = Color(255, 255, 255)
    end

    surface.SetDrawColor(backgroundColor)
    surface.DrawRect(0, 0, width, height)

    surface.SetFont("CTNV")
    local textWidth, textHeight = surface.GetTextSize("Rareload")
    draw.SimpleText("Rareload", "CTNV2", width / 2, 40, autoSaveStatusColor, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)

    local startY = 85
    local spacing = 30

    local settings = {
        { name = "Rareload",             enabled = RARELOAD.settings.addonEnabled },
        { name = "Move Type",            enabled = RARELOAD.settings.spawnModeEnabled },
        { name = "Auto Save",            enabled = RARELOAD.settings.autoSaveEnabled },
        { name = "Keep Inventory",       enabled = RARELOAD.settings.retainInventory },
        { name = "No Rareload At Death", enabled = RARELOAD.settings.nocustomrespawnatdeath },
        { name = "Debug",                enabled = RARELOAD.settings.debugEnabled }
    }

    for i, setting in ipairs(settings) do
        local statusText = setting.enabled and "Toggled" or "Toggle"
        local color = setting.enabled and autoSaveStatusColor or
            Color(255, 0, 0)
        draw.SimpleText(statusText .. " " .. setting.name, "CTNV", width / 2, startY + (i - 1) * spacing, color,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end
