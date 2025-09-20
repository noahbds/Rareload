local draw, surface, util, vgui, hook, render = draw, surface, util, vgui, hook, render
local math, string, os = math, string, os
local Color, Vector, Angle = Color, Vector, Angle
local IsValid, CurTime, FrameTime, Lerp = IsValid, CurTime, FrameTime, Lerp
local TEXT_ALIGN_CENTER, MOUSE_LEFT = TEXT_ALIGN_CENTER, MOUSE_LEFT

local MAT_DELETE_ICON = Material("icon16/image_delete.png")
local MAT_EYE_ICON = Material("icon16/eye.png")
local MAT_ICON_NPC = Material("icon16/user.png")
local MAT_ICON_ENTITY = Material("icon16/bricks.png")

local function CreateInfoLine(parent, label, value, color, tooltip)
    local container = vgui.Create("DPanel", parent)
    container:Dock(TOP)
    container:SetTall(24)
    container:DockMargin(0, 2, 0, 2)
    container.Paint = function(self, w, h)
        if self:IsHovered() then
            draw.RoundedBox(8, 0, 0, w, h, THEME.hover)
        end
    end

    local labelText = vgui.Create("DLabel", container)
    labelText:SetText(label)
    labelText:SetTextColor(THEME.textSecondary)
    labelText:SetFont("RareloadLabel")
    labelText:SetWide(90)
    labelText:Dock(LEFT)
    labelText:DockMargin(12, 0, 8, 0)
    labelText:SetContentAlignment(4)

    local valueText = vgui.Create("DLabel", container)
    valueText:SetText(tostring(value))
    valueText:SetTextColor(color or THEME.textPrimary)
    valueText:SetFont("RareloadBody")
    valueText:Dock(FILL)
    valueText:DockMargin(0, 0, 12, 0)
    valueText:SetContentAlignment(4)

    if tooltip then
        container:SetTooltip(tooltip)

        local infoIcon = vgui.Create("DPanel", container)
        infoIcon:SetSize(16, 16)
        infoIcon:SetPos(container:GetWide() - 20, 4)
        infoIcon.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.info)
            draw.SimpleText("?", "RareloadCaption", w / 2, h / 2, THEME.textPrimary,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        container.PerformLayout = function(s)
            infoIcon:SetPos(s:GetWide() - 20, 4)
        end
    end

    container:SetCursor("hand")
    container.OnMousePressed = function(self, mc)
        if mc == MOUSE_LEFT then
            local val = value
            if istable(val) then
                val = util.TableToJSON(val, true)
            else
                val = tostring(val)
            end
            SetClipboardText(val)
            if ShowNotification then
                ShowNotification("Copied: " .. label, NOTIFY_GENERIC)
            end
            surface.PlaySound("ui/buttonclickrelease.wav")
        end
    end

    return container
end

function CreateStyledButton(parent, text, icon, color, onClick)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn:SetSize(36, 36)
    btn:SetTooltip(text)

    local hoverFraction = 0
    local pressFraction = 0
    local iconMat = icon and Material(icon) or nil

    btn.Paint = function(self, w, h)
        local targetHover = self:IsHovered() and 1 or 0
        local targetPress = self:IsDown() and 1 or 0

        hoverFraction = Lerp(FrameTime() * 8, hoverFraction, targetHover)
        pressFraction = Lerp(FrameTime() * 12, pressFraction, targetPress)

        local bgColor = Color(
            math.Clamp(color.r + (hoverFraction * 20) - (pressFraction * 30), 0, 255),
            math.Clamp(color.g + (hoverFraction * 20) - (pressFraction * 30), 0, 255),
            math.Clamp(color.b + (hoverFraction * 20) - (pressFraction * 30), 0, 255),
            color.a or 255
        )

        draw.RoundedBox(8, 0, 0, w, h, bgColor)

        if hoverFraction > 0 then
            draw.RoundedBox(8, 0, 0, w, h, Color(255, 255, 255, 20 * hoverFraction))
        end

        if iconMat then
            surface.SetDrawColor(255, 255, 255, 255 - pressFraction * 50)
            surface.SetMaterial(iconMat)
            surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
        end
    end

    btn.DoClick = function()
        surface.PlaySound("ui/buttonclickrelease.wav")
        if onClick then onClick() end
    end

    return btn
end

function CreateInfoPanel(parent, data, isNPC, onDeleted, onAction, options)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(TOP)
    local compact = options and options.compact
    panel:SetTall(compact and 220 or 280)
    panel:DockMargin(8, 6, 8, 6)
    panel:SetAlpha(0)
    panel:AlphaTo(255, 0.3, 0)

    local hoverFraction = 0
    local typeColor = THEME:GetEntityTypeColor(data.class)

    panel.Paint = function(self, w, h)
        hoverFraction = Lerp(FrameTime() * 6, hoverFraction, self:IsHovered() and 1 or 0)

        THEME:DrawCard(0, 0, w, h, 2)

        draw.RoundedBoxEx(8, 0, 0, 4, h, typeColor, true, false, true, false)

        if hoverFraction > 0 then
            surface.SetDrawColor(THEME.primary.r, THEME.primary.g, THEME.primary.b, 15 * hoverFraction)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
        end
    end

    panel.OnCursorEntered = function(self)
        surface.PlaySound("ui/buttonrollover.wav")
    end

    local modelSection = vgui.Create("DPanel", panel)
    modelSection:SetSize(compact and 110 or 140, compact and 110 or 140)
    modelSection:Dock(LEFT)
    modelSection:DockMargin(12, 12, 8, 12)
    modelSection.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.backgroundDark)
        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    ---@class DModelPanel
    local modelPanel = vgui.Create("DModelPanel", modelSection)
    modelPanel:Dock(FILL)
    modelPanel:DockMargin(2, 2, 2, 2)

    if data.model and util.IsValidModel(data.model) then
        modelPanel:SetModel(data.model)

        local ent = modelPanel:GetEntity()
        if IsValid(ent) then
            local min, max = ent:GetRenderBounds()
            local center = (min + max) * 0.5
            local size = max:Distance(min)
            modelPanel:SetLookAt(center)
            modelPanel:SetCamPos(center + Vector(size * 0.8, size * 0.6, size * 0.4))
            modelPanel:SetFOV(60)
        end

        local targetAngle, currentAngle = 0, 0

        modelPanel.Think = function(self)
            targetAngle = (targetAngle + FrameTime() * 25) % 360
            currentAngle = Lerp(FrameTime() * 4, currentAngle, targetAngle)
            local ent = self:GetEntity()
            if IsValid(ent) then
                ent:SetAngles(Angle(0, currentAngle, 0))
            end
        end
    else
        modelPanel.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, THEME.backgroundDark)

            surface.SetDrawColor(THEME.textDisabled)
            surface.SetMaterial(MAT_DELETE_ICON)
            surface.DrawTexturedRect(w / 2 - 16, h / 2 - 20, 32, 32)

            draw.SimpleText("No Model", "RareloadCaption", w / 2, h / 2 + 20,
                THEME.textDisabled, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local contentArea = vgui.Create("DPanel", panel)
    contentArea:Dock(FILL)
    contentArea:DockMargin(0, 12, 12, 12)
    contentArea.Paint = function() end

    local headerSection = vgui.Create("DPanel", contentArea)
    headerSection:Dock(TOP)
    headerSection:SetTall(compact and 40 or 50)
    headerSection.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.surfaceVariant)
    end

    local entityName = vgui.Create("DLabel", headerSection)
    local displayName = data.class or "Unknown Entity"
    if string.find(displayName, "_") then
        displayName = string.gsub(displayName, "_", " ")
        displayName = string.gsub(displayName, "(%a)([%w_']*)", function(first, rest)
            return first:upper() .. rest
        end)
    end
    entityName:SetText(displayName)
    entityName:SetFont("RareloadSubheading")
    entityName:SetTextColor(THEME.textPrimary)
    entityName:Dock(TOP)
    entityName:DockMargin(12, 8, 12, 2)

    if data.id then
        local entityId = vgui.Create("DLabel", headerSection)
        entityId:SetText("ID: " .. data.id)
        entityId:SetFont("RareloadCaption")
        entityId:SetTextColor(THEME.textTertiary)
        entityId:Dock(TOP)
        entityId:DockMargin(12, 0, 12, 8)
    end

    local scrollPanel = vgui.Create("DScrollPanel", contentArea)
    scrollPanel:Dock(FILL)
    scrollPanel:DockMargin(0, 8, 0, 8)

    ---@class DVScrollBar
    local scrollbar = scrollPanel:GetVBar()
    scrollbar:SetWide(8)
    if scrollbar.SetHideButtons then scrollbar:SetHideButtons(true) end
    scrollbar.Paint = function(_, w, h)
        draw.RoundedBox(4, 0, 0, w, h, THEME.backgroundDark)
    end
    do
        local grip = scrollbar.btnGrip
        if grip and IsValid(grip) then
            grip.Paint = function(self, w, h)
                local color = self:IsHovered() and THEME.primaryLight or THEME.primary
                draw.RoundedBox(4, 0, 0, w, h, color)
            end
        end
    end

    local infoContainer = vgui.Create("DPanel", scrollPanel)
    infoContainer:Dock(TOP)
    infoContainer:SetTall(0)
    infoContainer.Paint = function() end

    local sections = {
        { title = "Status",     items = {} },
        { title = "Properties", items = {} },
        { title = "Physics",    items = {} },
        { title = "Spawn Info", items = {} }
    }

    if data.health then
        local healthValue = tonumber(data.health) or 0
        local maxHealthValue = tonumber(data.maxHealth) or healthValue
        local healthColor = THEME:GetHealthColor(healthValue, maxHealthValue)
        local healthText = string.format("%d/%d HP", healthValue, maxHealthValue)
        table.insert(sections[1].items, { "Health", healthText, healthColor })
    end

    if not RARELOAD or not RARELOAD.DataUtils then
        include("rareload/utils/rareload_data_utils.lua")
    end

    local parsedPos = nil
    local parsedPosVec = nil
    if data.pos then
        parsedPos = RARELOAD.DataUtils.ToPositionTable(data.pos)
        if parsedPos then
            parsedPosVec = Vector(parsedPos.x, parsedPos.y, parsedPos.z)
        end
    end

    if parsedPos then
        local posText = string.format("X: %.1f Y: %.1f Z: %.1f", parsedPos.x, parsedPos.y, parsedPos.z)
        table.insert(sections[1].items, { "Position", posText, THEME.textSecondary })

        local ply = LocalPlayer()
        if IsValid(ply) and ply.GetPos then
            local plyPos = ply:GetPos()
            if plyPos and parsedPosVec then
                local distance = math.Round(plyPos:Distance(parsedPosVec), 1)
                table.insert(sections[2].items,
                    { "Distance", (distance and (distance .. " units")) or "N/A", THEME.textSecondary })
            end
        end
    end

    if data.wasPlayerSpawned ~= nil then
        local spawnedColor = data.wasPlayerSpawned and THEME.success or THEME.info
        table.insert(sections[1].items, { "Player Spawned", data.wasPlayerSpawned and "Yes" or "No", spawnedColor })
    end

    if data.model then
        local modelName = string.GetFileFromFilename(data.model) or data.model
        table.insert(sections[2].items, { "Model", modelName, THEME.textSecondary })
    end

    if data.skin then
        table.insert(sections[2].items, { "Skin", tostring(data.skin), THEME.textSecondary })
    end

    if data.color then
        local colorText = string.format("R:%d G:%d B:%d A:%d",
            data.color.r or 255, data.color.g or 255, data.color.b or 255, data.color.a or 255)
        table.insert(sections[2].items,
            { "Color", colorText, Color(data.color.r or 255, data.color.g or 255, data.color.b or 255) })
    end

    if data.owner then
        table.insert(sections[2].items, { "Owner", data.owner, THEME.secondary })
    end

    if data.class then
        local classColor = THEME:GetEntityTypeColor(data.class)
        table.insert(sections[2].items, { "Class", data.class, classColor })
    end

    if data.id then
        table.insert(sections[2].items, { "ID", tostring(data.id), THEME.textTertiary })
    end

    if data.type then
        local typeColor = THEME:GetEntityTypeColor(data.type)
        table.insert(sections[2].items, { "Type", data.type, typeColor })
    end

    if data.ang then
        local angText = RARELOAD.DataUtils.FormatAngleDetailed(data.ang)
        angText = string.gsub(angText, "[{}]", "")
        table.insert(sections[3].items, { "Angles", angText, THEME.textSecondary })
    end

    if data.frozen ~= nil then
        local frozenColor = data.frozen and THEME.warning or THEME.success
        table.insert(sections[3].items, { "Frozen", data.frozen and "Yes" or "No", frozenColor })
    end

    if data.spawnTime then
        local spawnTimeText = os.date("%H:%M:%S", data.spawnTime)
        table.insert(sections[4].items, { "Spawn Time", spawnTimeText, THEME.textSecondary })
    end

    if data.originallySpawnedBy then
        table.insert(sections[4].items, { "Spawned By", data.originallySpawnedBy, THEME.secondary })
    end

    local accumulatedHeight = 0
    for _, section in ipairs(sections) do
        if #section.items > 0 then
            local sectionPanel = vgui.Create("DPanel", infoContainer)
            sectionPanel:Dock(TOP)
            local secTall = #section.items * 28 + 8
            sectionPanel:SetTall(secTall)
            sectionPanel:DockMargin(0, 4, 0, 4)
            sectionPanel.Paint = function() end
            accumulatedHeight = accumulatedHeight + secTall + 8

            for _, item in ipairs(section.items) do
                CreateInfoLine(sectionPanel, item[1], item[2], item[3])
            end
        end
    end
    infoContainer:SetTall(math.max(accumulatedHeight, compact and 120 or 160))

    local actionsPanel = vgui.Create("DPanel", contentArea)
    actionsPanel:Dock(BOTTOM)
    actionsPanel:SetTall(compact and 36 or 44)
    actionsPanel:DockMargin(0, 8, 0, 0)
    actionsPanel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.backgroundDark)
    end

    local buttonSpacing = 4

    if parsedPos then
        local teleportBtn = CreateStyledButton(actionsPanel, "Teleport", "icon16/arrow_right.png", THEME.success,
            function()
                if parsedPos then
                    RunConsoleCommand("rareload_teleport_to", parsedPos.x, parsedPos.y, parsedPos.z)
                    if ShowNotification then
                        ShowNotification("Teleporting to position!", NOTIFY_GENERIC)
                    end
                    if onAction then onAction("teleport", data) end
                else
                    ShowNotification("Invalid position data!", NOTIFY_ERROR)
                end
            end)
        teleportBtn:Dock(LEFT)
        teleportBtn:DockMargin(8, 4, buttonSpacing, 4)
    end

    local highlightBtn
    local highlightActive = false
    highlightBtn = CreateStyledButton(actionsPanel, "Highlight", "icon16/flag_yellow.png", THEME.success,
        function()
            if not parsedPos then
                ShowNotification("No position to highlight!", NOTIFY_ERROR)
                return
            end

            local entityID = string.format("pos_%.1f_%.1f_%.1f", parsedPos.x, parsedPos.y, parsedPos.z)

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
                    pos = parsedPos,
                    persistent = true,
                    color = Color(255, 255, 0, 100),
                    lineColor = Color(255, 255, 255, 40)
                })
                highlightActive = true
                ShowNotification("Highlighting position! Click again to turn off.", NOTIFY_GENERIC)
            end

            highlightBtn.Paint = function(self, w, h)
                local baseColor = highlightActive and Color(255, 140, 0) or
                    Color(255, 220, 80)
                local btnColor = self:IsHovered() and Color(baseColor.r * 1.2, baseColor.g * 1.2, baseColor.b * 1.2) or
                    baseColor

                draw.RoundedBox(4, 0, 0, w, h, btnColor)

                surface.SetDrawColor(255, 255, 255, 230)
                surface.SetMaterial(MAT_EYE_ICON)
                surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)

                if highlightActive then
                    local pulseAlpha = math.sin(CurTime() * 4) * 40 + 60
                    surface.SetDrawColor(255, 255, 255, pulseAlpha)
                    surface.DrawOutlinedRect(0, 0, w, h, 2)
                end
            end
        end)
    highlightBtn:Dock(LEFT)
    highlightBtn:DockMargin(0, 4, 4, 4)

    if parsedPos then
        local copyBtn = CreateStyledButton(actionsPanel, "Copy Position", "icon16/page_copy.png", THEME.info, function()
            if parsedPos then
                SetClipboardText(string.format("Vector(%.1f, %.1f, %.1f)", parsedPos.x, parsedPos.y, parsedPos.z))
                if ShowNotification then
                    ShowNotification("Position copied to clipboard!", NOTIFY_GENERIC)
                end
                if onAction then onAction("copy_position", data) end
            else
                ShowNotification("Invalid position data!", NOTIFY_ERROR)
            end
        end)
        copyBtn:Dock(LEFT)
        copyBtn:DockMargin(0, 4, 4, 4)
    end

    if parsedPos then
        local respawnBtn = CreateStyledButton(actionsPanel, "Respawn", "icon16/arrow_refresh.png", THEME.primary,
            function()
                if data.class and parsedPos then
                    local ns = isNPC and "RareloadRespawnNPC" or "RareloadRespawnEntity"
                    net.Start(ns)
                    net.WriteString(data.class)
                    net.WriteVector(Vector(parsedPos.x, parsedPos.y, parsedPos.z))
                    net.SendToServer()
                    ShowNotification("Respawning " .. (isNPC and "NPC" or "entity") .. "...", NOTIFY_GENERIC)
                    if onAction then onAction("respawn", data) end
                else
                    ShowNotification("Insufficient data to respawn!", NOTIFY_ERROR)
                end
            end)
        respawnBtn:Dock(LEFT)
        respawnBtn:DockMargin(0, 4, 4, 4)
    end

    local ExportJSON = CreateStyledButton(actionsPanel, "Export JSON", "icon16/page_white_code.png", THEME.primary,
        function()
            if data then
                local jsonData = util.TableToJSON(data, true)
                SetClipboardText(jsonData)
                if ShowNotification then
                    ShowNotification("Entity data exported to clipboard!", NOTIFY_GENERIC)
                end
                if onAction then onAction("export_json", data) end
            else
                ShowNotification("No data to export!", NOTIFY_ERROR)
            end
        end)
    ExportJSON:Dock(LEFT)
    ExportJSON:DockMargin(0, 4, 4, 4)

    local deleteBtn = CreateStyledButton(actionsPanel, "Delete", "icon16/cross.png", THEME.error, function()
        panel:AlphaTo(100, 0.2, 0, function()
            ---@class DFrame
            local confirmFrame = vgui.Create("DFrame")
            confirmFrame:SetSize(350, 140)
            confirmFrame:SetTitle("")
            confirmFrame:Center()
            confirmFrame:MakePopup()
            confirmFrame:SetBackgroundBlur(true)

            confirmFrame.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, THEME.background)
                draw.RoundedBoxEx(8, 0, 0, w, 40, THEME.error, true, true, false, false)
                draw.SimpleText("Delete " .. (isNPC and "NPC" or "Entity"), "RareloadText", w / 2, 20, THEME.textPrimary,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            local msg = vgui.Create("DLabel", confirmFrame)
            msg:SetText("Are you sure you want to delete this " .. (isNPC and "NPC" or "entity") .. "?")
            msg:SetFont("RareloadText")
            msg:SetTextColor(THEME.textPrimary)
            msg:SetContentAlignment(5)
            msg:Dock(TOP)
            msg:DockMargin(10, 50, 10, 10)

            local buttonPanel = vgui.Create("DPanel", confirmFrame)
            buttonPanel:Dock(BOTTOM)
            buttonPanel:SetTall(35)
            buttonPanel:DockMargin(10, 0, 10, 10)
            buttonPanel.Paint = function() end

            local btnWidth = (350 - 30) / 2

            local yesButton = vgui.Create("DButton", buttonPanel)
            yesButton:SetText("Delete")
            yesButton:SetTextColor(THEME.textPrimary)
            yesButton:SetFont("RareloadText")
            yesButton:Dock(LEFT)
            yesButton:SetWide(btnWidth)
            yesButton.Paint = function(self, w, h)
                local color = self:IsHovered() and Color(255, 80, 80) or THEME.error
                draw.RoundedBox(4, 0, 0, w, h, color)
            end
            yesButton.DoClick = function()
                confirmFrame:Close()
                if onDeleted then onDeleted(data) end
                panel:Remove()
            end

            local noButton = vgui.Create("DButton", buttonPanel)
            noButton:SetText("Cancel")
            noButton:SetTextColor(THEME.textPrimary)
            noButton:SetFont("RareloadText")
            noButton:Dock(RIGHT)
            noButton:SetWide(btnWidth)
            noButton.Paint = function(self, w, h)
                local color = self:IsHovered() and THEME.surfaceVariant or THEME.surface
                draw.RoundedBox(4, 0, 0, w, h, color)
            end
            noButton.DoClick = function()
                panel:AlphaTo(255, 0.3, 0)
                confirmFrame:Close()
            end
        end)
    end)
    deleteBtn:Dock(RIGHT)
    deleteBtn:DockMargin(buttonSpacing, 4, 8, 4)

    CreateModifyDataButton(actionsPanel, data, isNPC, onAction)

    return panel
end
