local function CreateInfoLine(parent, label, value, color, tooltip)
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
            draw.SimpleText("i", "RareloadSmall", w / 2, h / 2, THEME.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    return container
end

local function CreateStyledButton(parent, text, icon, color, onClick)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetWide(parent:GetWide() * 3)
    btn:Dock(LEFT)
    btn:DockMargin(0, 0, 5, 0)
    btn:SetTooltip("Click to " .. string.lower(text))

    btn.Paint = function(self, w, h)
        local hoverBoost = self:IsHovered() and 1.3 or 1.0
        local bgColor = Color(color.r * hoverBoost, color.g * hoverBoost, color.b * hoverBoost)
        draw.RoundedBox(6, 0, 0, w, h, bgColor)
        surface.SetDrawColor(255, 255, 255, 10)
        surface.DrawRect(0, 0, w, h / 2)
        if self:IsDown() then
            draw.RoundedBox(6, 2, 2, w - 4, h - 4, Color(0, 0, 0, 80))
        end
    end

    btn.PaintOver = function(self, w, h)
        local textColor = Color(255, 255, 255, 255)
        if icon then
            surface.SetDrawColor(255, 255, 255, 220)
            surface.SetMaterial(icon)
            surface.DrawTexturedRect(w / 2 - 50, h / 2 - 8, 16, 16)
            draw.SimpleText(text, "RareloadText", w / 2 - 10, h / 2, textColor,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(text, "RareloadText", w / 2, h / 2, textColor,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    btn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        onClick()
    end

    return btn
end

function CreateInfoPanel(parent, data, isNPC, onDeleted)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(TOP)
    panel:SetTall(140)
    panel:DockMargin(5, 5, 5, 5)
    panel:SetAlpha(0)
    panel:AlphaTo(255, 0.3, 0)
    panel.IsHovered = false

    panel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.border)
        draw.RoundedBox(8, 1, 1, w - 2, h - 2, THEME.panel)
        if self.IsHovered then
            draw.RoundedBox(8, 1, 1, w - 2, h - 2, THEME.panelHighlight)
        end
    end

    panel.OnCursorEntered = function(self)
        self.IsHovered = true
        surface.PlaySound("ui/buttonrollover.wav")
    end

    panel.OnCursorExited = function(self)
        self.IsHovered = false
    end

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
            draw.SimpleText("No Model", "RareloadText", w / 2, h / 2, THEME.text,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
    detailsPanel:DockMargin(5, 5, 5, 5)
    detailsPanel:SetTall(100)
    detailsPanel.Paint = function() end

    local leftPanel = vgui.Create("DPanel", detailsPanel)
    leftPanel:Dock(LEFT)
    leftPanel:SetWide(200)
    leftPanel.Paint = function() end

    local leftList = vgui.Create("DListLayout", leftPanel)
    leftList:Dock(FILL)

    local rightPanel = vgui.Create("DPanel", detailsPanel)
    rightPanel:Dock(FILL)
    rightPanel.Paint = function() end

    local rightList = vgui.Create("DListLayout", rightPanel)
    rightList:Dock(FILL)

    if data.health then
        local hlColor = data.health > 50 and Color(100, 255, 100) or Color(255, 100, 100)
        leftList:Add(CreateInfoLine(leftList, "Health", tostring(data.health), hlColor,
            "Saved health value with which the entity will reappear. This is not necessarily the current health of the entity in question."))
    end

    if not isNPC then
        leftList:Add(CreateInfoLine(leftList, "Frozen", data.frozen and "Yes" or "No",
            THEME.accent,
            "Saved frozen state value with which the entity will reappear. This is not necessarily the current frozen state of the entity in question."))
    end

    if isNPC and data.weapons and #data.weapons > 0 then
        local weaponStrings = {}
        for _, weapon in ipairs(data.weapons) do
            if type(weapon) == "string" then
                table.insert(weaponStrings, weapon)
            elseif type(weapon) == "table" and weapon.class then
                table.insert(weaponStrings, weapon.class)
            else
                table.insert(weaponStrings, tostring(weapon))
            end
        end

        local weaponDisplay = #weaponStrings > 2 and (weaponStrings[1] .. " +" .. (#weaponStrings - 1))
            or table.concat(weaponStrings, ", ")
        leftList:Add(CreateInfoLine(leftList, "Weapons", weaponDisplay, THEME.accent,
            "Saved weapons with which the NPC will reappear. This is not necessarily the current weapons of the NPC in question."))
    end

    if data.pos and data.pos.x and data.pos.y and data.pos.z then
        local posText = string.format("Vector(%.1f, %.1f, %.1f)", data.pos.x, data.pos.y, data.pos.z)
        rightList:Add(CreateInfoLine(rightList, "Position", posText))
        local ply = LocalPlayer()
        if IsValid(ply) then
            local distance = ply:GetPos():Distance(Vector(data.pos.x, data.pos.y, data.pos.z))
            local distText = string.format("%.0f units", distance)
            rightList:Add(CreateInfoLine(rightList, "Distance", distText))
        end
    else
        rightList:Add(CreateInfoLine(rightList, "Position", "Unknown", Color(255, 100, 100)))
    end

    local buttonContainer = vgui.Create("DPanel", panel)
    buttonContainer:Dock(BOTTOM)
    buttonContainer:SetTall(40)
    buttonContainer:DockMargin(10, 5, 10, 10)
    buttonContainer.Paint = function() end

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

            local btnWidth = (frameW - 40) / 2
            local yesButton = vgui.Create("DButton", buttonPanel)
            yesButton:SetText("Delete")
            yesButton:SetTextColor(Color(255, 255, 255))
            yesButton:SetFont("RareloadText")
            yesButton:Dock(LEFT)
            yesButton:SetWide(btnWidth)
            yesButton.Paint = function(self, w, h)
                local btnColor = self:IsHovered() and Color(255, 80, 80) or Color(220, 60, 60)
                draw.RoundedBox(4, 0, 0, w, h, btnColor)
            end

            yesButton.DoClick = function()
                local mapName = game.GetMap()
                local filePath = "rareload/player_positions_" .. mapName .. ".json"

                if file.Exists(filePath, "DATA") then
                    local jsonData = file.Read(filePath, "DATA")
                    local success, rawData = pcall(util.JSONToTable, jsonData)
                    if success and rawData and rawData[mapName] then
                        local deleted = false
                        local entityType = isNPC and "npcs" or "entities"
                        for steamID, playerData in pairs(rawData[mapName]) do
                            if playerData[entityType] then
                                for idx, entity in ipairs(playerData[entityType]) do
                                    if entity.class == data.class and entity.pos.x == data.pos.x and
                                        entity.pos.y == data.pos.y and entity.pos.z == data.pos.z then
                                        table.remove(playerData[entityType], idx)
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
                            if onDeleted then onDeleted() end
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
            noButton:SetWide(btnWidth)
            noButton.Paint = function(self, w, h)
                local btnColor = self:IsHovered() and Color(70, 70, 80) or Color(60, 60, 70)
                draw.RoundedBox(4, 0, 0, w, h, btnColor)
            end

            noButton.DoClick = function()
                panel:AlphaTo(255, 0.3, 0)
                confirmFrame:Close()
            end
        end)
    end)

    return panel
end
