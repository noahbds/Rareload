local function CreateInfoLine(parent, label, value, color, tooltip)
    ---@class DPanel
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
    valueText:DockMargin(0, 0, 20, 0)

    if tooltip then
        container:SetTooltip(tooltip)
        local infoIcon = vgui.Create("DPanel", container)
        infoIcon:SetSize(14, 14)
        infoIcon:SetPos(container:GetWide() - 18, 2)
        infoIcon.Paint = function(self, w, h)
            draw.RoundedBox(7, 0, 0, w, h, THEME.accent)
            draw.SimpleText("i", "RareloadSmall", w / 2, h / 2, Color(255, 255, 255, 220), TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        container.PerformLayout = function(s)
            infoIcon:SetPos(s:GetWide() - 18, 2)
        end
    end

    return container
end

local function CreateStyledButton(parent, text, icon, color, onClick)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetSize(32, 32)
    btn:SetTooltip(text)

    btn.Paint = function(self, w, h)
        local hoverBoost = self:IsHovered() and 1.2 or 1.0
        local bgColor = Color(color.r * hoverBoost, color.g * hoverBoost, color.b * hoverBoost)
        draw.RoundedBox(6, 0, 0, w, h, bgColor)
        surface.SetDrawColor(255, 255, 255, 30)
        surface.DrawRect(2, 2, w - 4, h / 3)
        if self:IsDown() then
            draw.RoundedBox(6, 2, 2, w - 4, h - 4, Color(0, 0, 0, 80))
        end
        if icon then
            surface.SetDrawColor(255, 255, 255, 230)
            surface.SetMaterial(icon)
            surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
        end
    end

    btn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        onClick()
    end

    return btn
end

function CreateInfoPanel(parent, data, isNPC, onDeleted, onAction)
    local panelID = "RareloadInfoPanel_" .. math.random(100000, 999999)
    ---@class DPanel
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(TOP)
    panel:SetTall(140)
    panel:DockMargin(5, 5, 5, 5)
    panel:SetAlpha(0)
    panel:AlphaTo(255, 0.3, 0)
    ---@diagnostic disable-next-line: assign-type-mismatch
    panel.IsHovered = false

    panel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.border)
        if self.IsHovered then
            draw.RoundedBox(8, 1, 1, w - 2, h - 2, THEME.panelHighlight)
            local pulse = math.sin(CurTime() * 2) * 10
            draw.RoundedBox(8, 1, 1, w - 2, h - 2, Color(255, 255, 255, pulse))
        else
            draw.RoundedBox(8, 1, 1, w - 2, h - 2, THEME.panel)
        end
    end

    panel.OnCursorEntered = function(self)
        ---@diagnostic disable-next-line: assign-type-mismatch
        self.IsHovered = true
        surface.PlaySound("ui/buttonrollover.wav")
    end

    panel.OnCursorExited = function(self)
        ---@diagnostic disable-next-line: assign-type-mismatch
        self.IsHovered = false
    end

    ---@class DModelPanel
    local modelPanel = vgui.Create("DModelPanel", panel)
    modelPanel:SetSize(120, 120)
    modelPanel:Dock(LEFT)
    modelPanel:DockMargin(10, 10, 10, 10)

    if data.model and util.IsValidModel(data.model) then
        modelPanel:SetModel(data.model)
        ---@diagnostic disable-next-line: undefined-field
        local min, max = modelPanel.Entity:GetRenderBounds()
        local center = (min + max) * 0.5
        local size = max:Distance(min)
        modelPanel:SetLookAt(center)
        modelPanel:SetCamPos(center + Vector(size * 0.6, size * 0.6, size * 0.4))

        local targetAngle, currentAngle, rotateSpeed = 0, 0, 30
        modelPanel.Think = function(self)
            targetAngle = (targetAngle + FrameTime() * rotateSpeed) % 360
            currentAngle = Lerp(FrameTime() * 5, currentAngle, targetAngle)
            ---@diagnostic disable-next-line: undefined-field
            if self.Entity and IsValid(self.Entity) then
                ---@diagnostic disable-next-line: undefined-field
                self.Entity:SetAngles(Angle(0, currentAngle, 0))
            end
        end

        modelPanel.PaintOver = function(self, w, h)
            draw.RoundedBox(100, w / 2 - 40, h - 16, 80, 8, Color(0, 0, 0, 40))
        end

        modelPanel.OnMousePressed = function(self, keyCode)
            if keyCode == MOUSE_LEFT then
                rotateSpeed = rotateSpeed * -1
            elseif keyCode == MOUSE_RIGHT then
                targetAngle, currentAngle, rotateSpeed = 0, 0, 30
            end
        end
    else
        modelPanel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.panelHighlight)
            surface.SetDrawColor(THEME.text)
            surface.SetMaterial(Material("icon16/cross.png"))
            surface.DrawTexturedRect(w / 2 - 8, h / 2 - 16, 16, 16)
            draw.SimpleText("No Model", "RareloadText", w / 2, h / 2 + 8, THEME.text, TEXT_ALIGN_CENTER,
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
    detailsPanel:DockMargin(5, 5, 5, 5)
    detailsPanel:SetTall(70)
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
            "Saved health value with which the entity will reappear."))
    end

    if not isNPC then
        leftList:Add(CreateInfoLine(leftList, "Frozen", data.frozen and "Yes" or "No", THEME.accent,
            "Saved frozen state value with which the entity will reappear."))
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
        local weaponDisplay = #weaponStrings > 2 and (weaponStrings[1] .. " +" .. (#weaponStrings - 1)) or
            table.concat(weaponStrings, ", ")
        leftList:Add(CreateInfoLine(leftList, "Weapons", weaponDisplay, THEME.accent,
            "Saved weapons with which the NPC will reappear."))
    end

    if data.pos and data.pos.x and data.pos.y and data.pos.z then
        local posText = string.format("%.1f, %.1f, %.1f", data.pos.x, data.pos.y, data.pos.z)
        rightList:Add(CreateInfoLine(rightList, "Position", posText))
        local ply = LocalPlayer()
        if IsValid(ply) then
            local distance = ply:GetPos():Distance(Vector(data.pos.x, data.pos.y, data.pos.z))
            rightList:Add(CreateInfoLine(rightList, "Distance", string.format("%.0f units", distance)))
        end
    else
        rightList:Add(CreateInfoLine(rightList, "Position", "Unknown", Color(255, 100, 100)))
    end

    local buttonContainer = vgui.Create("DPanel", panel)
    buttonContainer:Dock(BOTTOM)
    buttonContainer:SetTall(40)
    buttonContainer:DockMargin(10, 5, 10, 5)
    buttonContainer.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, ColorAlpha(THEME.background, 120))
    end

    local buttonScroll = vgui.Create("DHorizontalScroller", buttonContainer)
    buttonScroll:Dock(FILL)
    buttonScroll:DockMargin(5, 4, 5, 4)
    buttonScroll:SetOverlap(-2)

    local copyIcon = Material("icon16/page_copy.png")
    local teleportIcon = Material("icon16/arrow_right.png")
    local deleteIcon = Material("icon16/cross.png")
    local copyAllIcon = Material("icon16/page_white_text.png")
    local highlightIcon = Material("icon16/flag_yellow.png")
    local goToIcon = Material("icon16/magnifier.png")
    local respawnIcon = Material("icon16/arrow_refresh.png")
    local exportIcon = Material("icon16/disk.png")
    local trackIcon = Material("icon16/eye.png")

    local highlightActive = false
    local tracked = false

    local function addButton(text, iconMat, col, fn)
        buttonScroll:AddPanel(CreateStyledButton(buttonScroll, text, iconMat,
            col, fn))
    end

    addButton("Copy All Info", copyAllIcon, THEME.accent, function()
        local info = { "Class: " .. (data.class or "Unknown") }
        if data.health then table.insert(info, "Health: " .. tostring(data.health)) end
        if data.frozen ~= nil then table.insert(info, "Frozen: " .. (data.frozen and "Yes" or "No")) end
        if isNPC and data.weapons and #data.weapons > 0 then
            local wlist = {}
            for _, w in ipairs(data.weapons) do
                table.insert(wlist, type(w) == "table" and w.class or tostring(w))
            end
            table.insert(info, "Weapons: " .. table.concat(wlist, ", "))
        end
        if data.pos then
            table.insert(info,
                string.format("Position: Vector(%.1f, %.1f, %.1f)", data.pos.x, data.pos.y, data.pos.z))
        end
        SetClipboardText(table.concat(info, "\n"))
        ShowNotification("All info copied to clipboard!", NOTIFY_GENERIC)
        if onAction then onAction("copy_all", data) end
    end)

    HighlightBtn = CreateStyledButton(buttonScroll, "Highlight", highlightIcon, Color(255, 220, 80),
        function()
            if not data.pos then
                ShowNotification("No position to highlight!", NOTIFY_ERROR)
                return
            end

            local entityID = string.format("pos_%.1f_%.1f_%.1f", data.pos.x, data.pos.y, data.pos.z)

            if not RARELOAD.HighlightData then
                RARELOAD.HighlightData = {}

                hook.Add("PostDrawTranslucentRenderables", "RareloadHighlightAllEntities", function()
                    local curTime = CurTime()
                    local toRemove = {}

                    for i, highlight in ipairs(RARELOAD.HighlightData) do
                        if highlight.persistent or curTime < highlight.endTime then
                            render.SetColorMaterial()
                            render.DrawSphere(
                                Vector(highlight.pos.x, highlight.pos.y, highlight.pos.z),
                                24, 16, 16,
                                highlight.color or Color(255, 255, 0, 100)
                            )

                            local ply = LocalPlayer()
                            if IsValid(ply) then
                                render.DrawLine(
                                    ply:GetPos() + Vector(0, 0, 36),
                                    Vector(highlight.pos.x, highlight.pos.y, highlight.pos.z),
                                    highlight.lineColor or Color(255, 255, 0, 80),
                                    false
                                )
                            end
                        else
                            table.insert(toRemove, i)
                        end
                    end

                    for i = #toRemove, 1, -1 do
                        table.remove(RARELOAD.HighlightData, toRemove[i])
                    end
                end)
            end

            local alreadyHighlighted = false
            local existingIndex = nil

            for i, highlight in ipairs(RARELOAD.HighlightData) do
                if highlight.id == entityID then
                    alreadyHighlighted = true
                    existingIndex = i
                    break
                end
            end

            if alreadyHighlighted then
                table.remove(RARELOAD.HighlightData, existingIndex)
                highlightActive = false
                ShowNotification("Highlight turned off for this entity!", NOTIFY_GENERIC)
            else
                table.insert(RARELOAD.HighlightData, {
                    id = entityID,
                    pos = data.pos,
                    persistent = true,
                    color = Color(255, 255, 0, 100),
                    lineColor = Color(255, 255, 255, 40)
                })
                highlightActive = true
                ShowNotification("Highlighting position! Click again to turn off.", NOTIFY_GENERIC)
            end

            HighlightBtn.Paint = function(self, w, h)
                local baseColor = highlightActive and Color(255, 140, 0) or
                    Color(255, 220, 80)
                local btnColor = self:IsHovered() and Color(baseColor.r * 1.2, baseColor.g * 1.2, baseColor.b * 1.2) or
                    baseColor

                draw.RoundedBox(4, 0, 0, w, h, btnColor)

                surface.SetDrawColor(255, 255, 255, 230)
                surface.SetMaterial(Material("icon16/eye.png"))
                surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)

                if highlightActive then
                    local pulseAlpha = math.sin(CurTime() * 4) * 40 + 60
                    surface.SetDrawColor(255, 255, 255, pulseAlpha)
                    surface.DrawOutlinedRect(0, 0, w, h, 2)
                end
            end
        end)


    local originalHighlightPaint = HighlightBtn.Paint
    HighlightBtn.Paint = originalHighlightPaint


    addButton("Copy Position", copyIcon, THEME.accent, function()
        if data.pos then
            SetClipboardText(string.format("Vector(%s, %s, %s)", data.pos.x, data.pos.y, data.pos.z))
            ShowNotification("Position copied to clipboard!", NOTIFY_GENERIC)
            if onAction then onAction("copy_position", data) end
        end
    end)

    addButton("Teleport", teleportIcon, Color(80, 180, 80), function()
        if data.pos then
            RunConsoleCommand("rareload_teleport_to", data.pos.x, data.pos.y, data.pos.z)
            ShowNotification("Teleporting to position!", NOTIFY_GENERIC)
            if onAction then onAction("teleport", data) end
        else
            ShowNotification("Invalid position data!", NOTIFY_ERROR)
        end
    end)

    addButton("Go To", goToIcon, Color(120, 180, 255), function()
        if data.pos then
            local ply = LocalPlayer()
            if IsValid(ply) and ply:InVehicle() then
                ShowNotification("Exit your vehicle first!", NOTIFY_ERROR)
                return
            end
            local origin = Vector(data.pos.x, data.pos.y, data.pos.z) + Vector(0, 0, 64)
            ply:SetEyeAngles((origin - ply:EyePos()):Angle())
            ply:SetPos(origin)
            ShowNotification("Camera moved to entity position!", NOTIFY_GENERIC)
            if onAction then onAction("go_to", data) end
        else
            ShowNotification("No position to go to!", NOTIFY_ERROR)
        end
    end)

    addButton("Respawn", respawnIcon, Color(80, 200, 200), function()
        if data.class and data.pos then
            local ns = isNPC and "RareloadRespawnNPC" or "RareloadRespawnEntity"
            net.Start(ns); net.WriteString(data.class); net.WriteVector(Vector(data.pos.x, data.pos.y, data.pos.z)); net
                .SendToServer()
            ShowNotification("Respawning " .. (isNPC and "NPC" or "entity") .. "...", NOTIFY_GENERIC)
            if onAction then onAction("respawn", data) end
        else
            ShowNotification("Insufficient data to respawn!", NOTIFY_ERROR)
        end
    end)

    addButton("Export JSON", exportIcon, Color(180, 180, 255), function()
        SetClipboardText(util.TableToJSON(data, true))
        ShowNotification("Entity data exported as JSON!", NOTIFY_GENERIC)
        if onAction then onAction("export", data) end
    end)

    addButton("Track", trackIcon, Color(0, 200, 255), function()
        tracked = not tracked

        local trackingID = "entity_tracking_" .. panelID

        for i, highlight in ipairs(RARELOAD.HighlightData) do
            if highlight.id == trackingID then
                table.remove(RARELOAD.HighlightData, i)
                break
            end
        end

        if tracked then
            table.insert(RARELOAD.HighlightData, {
                id = trackingID,
                pos = data.pos,
                persistent = true,
                color = Color(0, 255, 255, 80),
                lineColor = Color(0, 200, 255, 60)
            })
            ShowNotification("Tracking enabled!", NOTIFY_GENERIC)
        else
            ShowNotification("Tracking disabled!", NOTIFY_GENERIC)
        end

        if onAction then onAction("track", data, tracked) end
    end)

    addButton("Delete", deleteIcon, THEME.dangerAccent, function()
        panel:AlphaTo(150, 0.3, 0, function()
            local w, h = ScrW() * 0.25, ScrH() * 0.15
            local f = vgui.Create("DFrame")
            f:SetSize(w, h); f:SetTitle("Confirm Deletion"); f:SetBackgroundBlur(true); f:Center(); f:MakePopup()
            f.Paint = function(self, ww, hh)
                draw.RoundedBox(8, 0, 0, ww, hh, THEME.background)
                draw.RoundedBox(4, 0, 0, ww, 24, THEME.header)
                surface.SetDrawColor(255, 70, 70)
                surface.SetMaterial(Material("icon16/exclamation.png"))
                surface.DrawTexturedRect(ww / 2 - 8, hh / 2 - 20, 16, 16)
            end
            local msg = vgui.Create("DLabel", f)
            msg:SetText("Are you sure you want to delete this " .. (isNPC and "NPC" or "entity") .. "?")
            msg:SetFont("RareloadText"); msg:SetTextColor(THEME.text); msg:SetContentAlignment(5)
            msg:Dock(TOP); msg:DockMargin(10, 30, 10, 10)
            local bp = vgui.Create("DPanel", f)
            bp:Dock(BOTTOM); bp:SetTall(40); bp:DockMargin(10, 0, 10, 10); bp.Paint = function() end
            local bw = (w - 40) / 2
            local yes = vgui.Create("DButton", bp)
            yes:SetText("Delete"); yes:SetTextColor(Color(255, 255, 255)); yes:SetFont("RareloadText"); yes:Dock(LEFT); yes
                :SetWide(bw)
            yes.Paint = function(self, ww, hh)
                local bc = self:IsHovered() and Color(255, 80, 80) or Color(220, 60, 60)
                draw.RoundedBox(4, 0, 0, ww, hh, bc)
                if self:IsHovered() then
                    surface.SetDrawColor(255, 255, 255, 30); surface.DrawRect(2, 2, ww - 4, hh / 3)
                end
            end
            yes.DoClick = function()
                local mn, fp = game.GetMap(), "rareload/player_positions_" .. game.GetMap() .. ".json"
                if file.Exists(fp, "DATA") then
                    local success, raw = pcall(util.JSONToTable, file.Read(fp, "DATA"))
                    if success and raw and raw[mn] then
                        local deleted = false; local et = isNPC and "npcs" or "entities"
                        for _, pd in pairs(raw[mn]) do
                            if pd[et] then
                                for i, ent in ipairs(pd[et]) do
                                    if ent.class == data.class and ent.pos.x == data.pos.x and ent.pos.y == data.pos.y and ent.pos.z == data.pos.z then
                                        table.remove(pd[et], i); deleted = true; break
                                    end
                                end
                            end
                            if deleted then break end
                        end
                        if deleted then
                            file.Write(fp, util.TableToJSON(raw, true))
                            net.Start("RareloadReloadData"); net.SendToServer()
                            panel:AlphaTo(0, 0.3, 0,
                                function()
                                    if onDeleted then onDeleted(data) end
                                    if onAction then onAction("delete", data) end
                                    panel:Remove()
                                end)
                            ShowNotification("Entity deleted successfully!", NOTIFY_GENERIC)
                        else
                            ShowNotification("Couldn't find the entity to delete!", NOTIFY_ERROR)
                            panel:AlphaTo(255, 0.3, 0)
                        end
                    end
                end
                f:Close()
            end
            local no = vgui.Create("DButton", bp)
            no:SetText("Cancel"); no:SetTextColor(Color(255, 255, 255)); no:SetFont("RareloadText"); no:Dock(RIGHT); no
                :SetWide(bw)
            no.Paint = function(self, ww, hh)
                local bc = self:IsHovered() and Color(70, 70, 80) or Color(60, 60, 70)
                draw.RoundedBox(4, 0, 0, ww, hh, bc)
                if self:IsHovered() then
                    surface.SetDrawColor(255, 255, 255, 30); surface.DrawRect(2, 2, ww - 4, hh / 3)
                end
            end
            no.DoClick = function()
                panel:AlphaTo(255, 0.3, 0); f:Close()
            end
        end)
    end)

    function panel:UpdateData(newData)
        data = newData
        header:SetText(data.class or "Unknown Entity")
        if data.model and util.IsValidModel(data.model) then
            modelPanel:SetModel(data.model)
            ---@diagnostic disable-next-line: undefined-field
            local min, max = modelPanel.Entity:GetRenderBounds()
            local center = (min + max) * 0.5
            local size = max:Distance(min)
            modelPanel:SetLookAt(center)
            modelPanel:SetCamPos(center + Vector(size * 0.6, size * 0.6, size * 0.4))
        end
        if data.pos and IsValid(rightList) then
            rightList:Clear()
            local pt = string.format("%.1f, %.1f, %.1f", data.pos.x, data.pos.y, data.pos.z)
            rightList:Add(CreateInfoLine(rightList, "Position", pt))
            local ply = LocalPlayer()
            if IsValid(ply) then
                rightList:Add(CreateInfoLine(rightList, "Distance",
                    string.format("%.0f units", ply:GetPos():Distance(Vector(data.pos.x, data.pos.y, data.pos.z)))))
            end
        end
        if IsValid(leftList) then
            leftList:Clear()
            if data.health then
                local hlColor = data.health > 50 and Color(100, 255, 100) or Color(255, 100, 100)
                leftList:Add(CreateInfoLine(leftList, "Health", tostring(data.health), hlColor,
                    "Saved health value with which the entity will reappear."))
            end
            if not isNPC then
                leftList:Add(CreateInfoLine(leftList, "Frozen", data.frozen and "Yes" or "No", THEME.accent,
                    "Saved frozen state value with which the entity will reappear."))
            end
            if isNPC and data.weapons and #data.weapons > 0 then
                local ws = {}
                for _, w in ipairs(data.weapons) do
                    table.insert(ws, type(w) == "table" and w.class or tostring(w))
                end
                local wd = #ws > 2 and (ws[1] .. " +" .. (#ws - 1)) or table.concat(ws, ", ")
                leftList:Add(CreateInfoLine(leftList, "Weapons", wd, THEME.accent,
                    "Saved weapons with which the NPC will reappear."))
            end
        end
    end

    return panel
end
