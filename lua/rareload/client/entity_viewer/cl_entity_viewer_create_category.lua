local highlightAllActive = false

-- Ensure data utils are available for parsing positions
if not RARELOAD or not RARELOAD.DataUtils then
    include("rareload/utils/rareload_data_utils.lua")
end

-- sortMode: "Class" | "Distance" | "Health"
-- playerPos: Vector or nil
-- options: { compact = boolean }
function CreateCategory(parent, title, dataList, isNPC, filter, sortMode, playerPos, options)
    if not dataList or #dataList == 0 then return nil end

    local filteredData = {}
    if filter and filter ~= "" then
        local lowerFilter = string.lower(filter)
        for _, data in ipairs(dataList) do
            local classMatch = string.find(string.lower(data.class or ""), lowerFilter)
            local idMatch = data.id and string.find(string.lower(tostring(data.id)), lowerFilter)

            if classMatch or idMatch then
                table.insert(filteredData, data)
            end
        end
        dataList = filteredData
    end

    if #dataList == 0 then return nil end

    -- Sorting
    sortMode = sortMode or "Class"
    if sortMode == "Distance" and IsValid(LocalPlayer()) and playerPos then
        local function getDist(item)
            if not item or not item.pos then return math.huge end
            local pt = RARELOAD.DataUtils.ToPositionTable(item.pos)
            if not pt then return math.huge end
            local v = Vector(pt.x, pt.y, pt.z)
            return v:DistToSqr(playerPos)
        end
        table.sort(dataList, function(a, b)
            local da, db = getDist(a), getDist(b)
            if da == db then
                return (a.class or "") < (b.class or "")
            end
            return da < db
        end)
    elseif sortMode == "Health" then
        table.sort(dataList, function(a, b)
            local ha = tonumber(a.health or -1) or -1
            local hb = tonumber(b.health or -1) or -1
            if ha == hb then
                return (a.class or "") < (b.class or "")
            end
            return ha > hb -- higher first
        end)
    else
        table.sort(dataList, function(a, b)
            return (a.class or "") < (b.class or "")
        end)
    end

    local mainContainer = vgui.Create("DPanel", parent)
    mainContainer:Dock(TOP)
    mainContainer:DockMargin(16, 12, 16, 8)

    mainContainer.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.surface)

        surface.SetDrawColor(THEME.border)
        draw.RoundedBox(12, 0, 0, w, h, Color(0, 0, 0, 0))
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local compact = options and options.compact
    -- Match CreateInfoPanel heights to avoid clipped content or excess space
    local baseItemHeight = compact and 220 or 280
    local minItemHeight = compact and 180 or 240
    local maxItemHeight = compact and 260 or 320

    local itemCount = #dataList
    local itemHeight

    if itemCount <= 3 then
        itemHeight = maxItemHeight
    elseif itemCount <= 6 then
        itemHeight = baseItemHeight
    elseif itemCount <= 10 then
        itemHeight = 200
    elseif itemCount <= 15 then
        itemHeight = 160
    else
        itemHeight = minItemHeight
    end

    local headerHeight = 56
    local batchActionsHeight = 40
    local marginHeight = 8
    local maxVisibleItems = math.min(itemCount, 8)
    -- Compute height based on card header + actions + estimated item heights,
    -- but cap to avoid super-tall categories causing nested scroll issue
    local contentHeight = maxVisibleItems * (itemHeight + marginHeight) + batchActionsHeight

    mainContainer:SetTall(headerHeight)

    local isExpanded = true
    local isAnimating = false
    local expandFraction = 1
    local uniqueID = "CategoryContainer_" .. math.random(1000000)

    local header = vgui.Create("DButton", mainContainer)
    header:SetText("")
    header:Dock(TOP)
    header:SetTall(headerHeight)
    header:SetCursor("hand")

    local hoverFraction = 0
    header.Paint = function(self, w, h)
        local targetHover = self:IsHovered() and 1 or 0
        if isnumber(hoverFraction) and isnumber(targetHover) then
            hoverFraction = Lerp(FrameTime() * 8, hoverFraction, targetHover)
        else
            hoverFraction = targetHover
        end

        local bgColor = Color(
            math.Clamp(THEME.backgroundDark.r + (hoverFraction * 15), 0, 255),
            math.Clamp(THEME.backgroundDark.g + (hoverFraction * 15), 0, 255),
            math.Clamp(THEME.backgroundDark.b + (hoverFraction * 15), 0, 255),
            THEME.backgroundDark.a or 255
        )
        draw.RoundedBoxEx(12, 0, 0, w, h, bgColor, true, true, not isExpanded, not isExpanded)

        if hoverFraction > 0 then
            draw.RoundedBoxEx(12, 0, 0, w, h, Color(255, 255, 255, 15 * hoverFraction), true, true, not isExpanded,
                not isExpanded)
        end

        local iconColor = isNPC and THEME.secondary or THEME.primary
        surface.SetDrawColor(iconColor)
        surface.SetMaterial(Material(isNPC and "icon16/user.png" or "icon16/bricks.png"))
        surface.DrawTexturedRect(20, h / 2 - 8, 16, 16)

        draw.SimpleText(title, "RareloadSubheading", 48, h / 2 - 8, THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(#dataList .. " items", "RareloadCaption", 48, h / 2 + 8, THEME.textSecondary, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        local arrowRotation = Lerp(expandFraction, 0, 90)
        local arrowMat = Material("icon16/arrow_right.png")
        surface.SetDrawColor(THEME.textSecondary)
        surface.SetMaterial(arrowMat)

        local arrowX, arrowY = w - 32, h / 2 - 8
        surface.DrawTexturedRectRotated(arrowX + 8, arrowY + 8, 16, 16, arrowRotation)

        if hoverFraction > 0 then
            local hintText = isExpanded and "Click to collapse" or "Click to expand"
            draw.SimpleText(hintText, "RareloadCaption", w - 48, h / 2,
                Color(THEME.textTertiary.r, THEME.textTertiary.g, THEME.textTertiary.b, 180 * hoverFraction),
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    local contentContainer = vgui.Create("DPanel", mainContainer)
    contentContainer:Dock(FILL)
    contentContainer:DockMargin(1, 0, 1, 1)
    contentContainer.Paint = function(self, w, h)
        draw.RoundedBoxEx(12, 0, 0, w, h, THEME.surface, false, false, true, true)
    end
    contentContainer:SetVisible(isExpanded)

    local batchActionsPanel = vgui.Create("DPanel", contentContainer)
    batchActionsPanel:Dock(TOP)
    batchActionsPanel:SetTall(batchActionsHeight)
    batchActionsPanel:DockMargin(12, 8, 12, 4)
    batchActionsPanel.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.backgroundDark)
        surface.SetDrawColor(THEME.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    local batchLabel = vgui.Create("DLabel", batchActionsPanel)
    batchLabel:SetText("Batch Actions")
    batchLabel:SetFont("RareloadCaption")
    batchLabel:SetTextColor(THEME.textSecondary)
    batchLabel:SizeToContents()
    batchLabel:Dock(LEFT)
    batchLabel:DockMargin(12, 0, 12, 0)

    local function CreateModernBatchButton(text, icon, color, onClick)
        local btn = vgui.Create("DButton", batchActionsPanel)
        btn:SetText("")
        btn:SetSize(32, 32)
        btn:SetTooltip(text)
        btn:Dock(LEFT)
        btn:DockMargin(4, 4, 0, 4)

        local btnHoverFrac = 0
        local btnPressFrac = 0

        btn.Paint = function(self, w, h)
            btnHoverFrac = Lerp(FrameTime() * 10, btnHoverFrac, self:IsHovered() and 1 or 0)
            btnPressFrac = Lerp(FrameTime() * 15, btnPressFrac, self:IsDown() and 1 or 0)

            local btnColor = THEME:LerpColor(btnHoverFrac * 0.2, color, Color(255, 255, 255))
            btnColor = THEME:LerpColor(btnPressFrac * 0.2, btnColor, Color(0, 0, 0))

            draw.RoundedBox(6, 0, 0, w, h, btnColor)

            if btnHoverFrac > 0 then
                draw.RoundedBox(6, 0, 0, w, h, Color(255, 255, 255, 25 * btnHoverFrac))
            end

            surface.SetDrawColor(255, 255, 255, 230 - btnPressFrac * 50)
            surface.SetMaterial(Material(icon))
            surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
        end

        btn.DoClick = function()
            surface.PlaySound("ui/buttonclickrelease.wav")
            onClick(dataList)
        end

        return btn
    end

    CreateModernBatchButton("Teleport to First", "icon16/arrow_right.png", THEME.success, function(items)
        if items and items[1] and items[1].pos then
            RunConsoleCommand("rareload_teleport_to", items[1].pos.x, items[1].pos.y, items[1].pos.z)
            ShowNotification("Teleporting to first " .. (isNPC and "NPC" or "entity") .. "!", NOTIFY_GENERIC)
        end
    end)

    local highlightBtn
    highlightBtn = CreateModernBatchButton("Highlight All", "icon16/eye.png", THEME.warning, function(items)
        highlightAllActive = not highlightAllActive

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

        for i = #RARELOAD.HighlightData, 1, -1 do
            if RARELOAD.HighlightData[i].isBatch then
                table.remove(RARELOAD.HighlightData, i)
            end
        end

        if highlightAllActive then
            local validItems = {}
            for _, item in ipairs(items) do
                if item.pos then
                    table.insert(validItems, item)
                end
            end

            local colorVariations = {
                Color(255, 255, 0, 100),
                Color(0, 255, 255, 100),
                Color(255, 0, 255, 100),
                Color(0, 255, 0, 100),
                Color(255, 128, 0, 100)
            }

            for i, item in ipairs(validItems) do
                table.insert(RARELOAD.HighlightData, {
                    pos = item.pos,
                    isBatch = true,
                    persistent = true,
                    color = colorVariations[(i - 1) % #colorVariations + 1],
                    lineColor = Color(255, 255, 255, 40)
                })
            end

            ShowNotification("Highlighting " .. #validItems .. " positions! Click again to turn off.", NOTIFY_GENERIC)
        else
            ShowNotification("Highlight turned off!", NOTIFY_GENERIC)
        end
    end)

    -- Draw based on current toggle state
    highlightBtn.Paint = function(self, w, h)
        local baseColor = highlightAllActive and Color(255, 140, 0) or Color(255, 220, 80)
        local btnColor = self:IsHovered() and Color(baseColor.r * 1.2, baseColor.g * 1.2, baseColor.b * 1.2) or baseColor

        draw.RoundedBox(4, 0, 0, w, h, btnColor)

        surface.SetDrawColor(255, 255, 255, 230)
        surface.SetMaterial(Material("icon16/eye.png"))
        surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)

        if highlightAllActive then
            local pulseAlpha = math.sin(CurTime() * 4) * 40 + 60
            surface.SetDrawColor(255, 255, 255, pulseAlpha)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
        end
    end

    CreateModernBatchButton("Export All", "icon16/disk.png", THEME.info, function(items)
        SetClipboardText(util.TableToJSON(items, true))
        ShowNotification(#items .. " items exported as JSON!", NOTIFY_GENERIC)
    end)

    CreateModernBatchButton("Delete All", "icon16/cross.png", THEME.error, function(items)
        local confirmFrame = vgui.Create("DFrame")
        confirmFrame:SetSize(450, 220)
        confirmFrame:SetTitle("")
        confirmFrame:Center()
        confirmFrame:MakePopup()
        confirmFrame:SetBackgroundBlur(true)

        confirmFrame.Paint = function(self, w, h)
            THEME:DrawCard(0, 0, w, h, 4)

            draw.RoundedBoxEx(12, 0, 0, w, 60, THEME.error, true, true, false, false)

            surface.SetDrawColor(255, 255, 255)
            surface.SetMaterial(Material("icon16/exclamation.png"))
            surface.DrawTexturedRect(20, 22, 16, 16)

            draw.SimpleText("Confirm Deletion", "RareloadSubheading", 44, 30,
                THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local message = vgui.Create("DLabel", confirmFrame)
        message:SetText("Are you sure you want to delete all " ..
            #items .. " " .. (isNPC and "NPCs" or "entities") .. " in this category?")
        message:SetFont("RareloadText")
        message:SetTextColor(THEME.text)
        message:SetContentAlignment(5)
        message:Dock(TOP)
        message:DockMargin(10, 40, 10, 5)

        local subMessage = vgui.Create("DLabel", confirmFrame)
        subMessage:SetText("This action cannot be undone!")
        subMessage:SetFont("RareloadSmall")
        subMessage:SetTextColor(Color(255, 100, 100))
        subMessage:SetContentAlignment(5)
        subMessage:Dock(TOP)
        subMessage:DockMargin(10, 0, 10, 10)

        local buttonPanel = vgui.Create("DPanel", confirmFrame)
        buttonPanel:Dock(BOTTOM)
        buttonPanel:SetTall(40)
        buttonPanel:DockMargin(10, 0, 10, 10)
        buttonPanel.Paint = function() end

        local btnWidth = (450 - 40) / 2

        local yesButton = vgui.Create("DButton", buttonPanel)
        yesButton:SetText("Delete All")
        yesButton:SetTextColor(Color(255, 255, 255))
        yesButton:SetFont("RareloadText")
        yesButton:Dock(LEFT)
        yesButton:SetWide(btnWidth)
        yesButton.Paint = function(self, w, h)
            local btnColor = self:IsHovered() and Color(255, 80, 80) or Color(220, 60, 60)
            draw.RoundedBox(4, 0, 0, w, h, btnColor)
            if self:IsHovered() then
                surface.SetDrawColor(255, 255, 255, 30)
                surface.DrawRect(2, 2, w - 4, h / 3)
            end
        end
        yesButton.DoClick = function()
            local mapName = game.GetMap()
            local filePath = "rareload/player_positions_" .. mapName .. ".json"

            if file.Exists(filePath, "DATA") then
                local success, rawData = pcall(util.JSONToTable, file.Read(filePath, "DATA"))
                if success and rawData and rawData[mapName] then
                    local dataType = isNPC and "npcs" or "entities"
                    local deletedCount = 0

                    for _, playerData in pairs(rawData[mapName]) do
                        if playerData[dataType] then
                            local originalCount = #playerData[dataType]

                            local newItems = {}
                            for _, entity in ipairs(playerData[dataType]) do
                                local shouldKeep = true

                                for _, item in ipairs(items) do
                                    if item.class == entity.class and
                                        item.pos.x == entity.pos.x and
                                        item.pos.y == entity.pos.y and
                                        item.pos.z == entity.pos.z then
                                        shouldKeep = false
                                        break
                                    end
                                end

                                if shouldKeep then
                                    table.insert(newItems, entity)
                                end
                            end

                            playerData[dataType] = newItems
                            deletedCount = deletedCount + (originalCount - #newItems)
                        end
                    end

                    file.Write(filePath, util.TableToJSON(rawData, true))

                    net.Start("RareloadReloadData")
                    net.SendToServer()

                    LoadData()

                    ShowNotification(
                        "Deleted " .. deletedCount .. " " .. (isNPC and "NPCs" or "entities") .. " successfully!",
                        NOTIFY_GENERIC)

                    confirmFrame:Close()
                else
                    ShowNotification("Failed to parse saved data!", NOTIFY_ERROR)
                    confirmFrame:Close()
                end
            else
                ShowNotification("No saved data found for this map!", NOTIFY_ERROR)
                confirmFrame:Close()
            end
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
            if self:IsHovered() then
                surface.SetDrawColor(255, 255, 255, 30)
                surface.DrawRect(2, 2, w - 4, h / 3)
            end
        end
        noButton.DoClick = function() confirmFrame:Close() end
    end)

    local scrollPanel = vgui.Create("DScrollPanel", contentContainer)
    scrollPanel:Dock(FILL)
    scrollPanel:DockMargin(8, 4, 8, 8)

    local scrollbar = scrollPanel:GetVBar()
    if IsValid(scrollbar) then
        scrollbar:SetWide(8)
        if scrollbar.SetHideButtons then scrollbar:SetHideButtons(true) end
        scrollbar.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, THEME.backgroundDark)
        end
        local btnUp = scrollbar.btnUp
        if IsValid(btnUp) then
            btnUp.Paint = function(self, w, h)
                local color = self:IsHovered() and THEME.primaryLight or THEME.primary
                draw.RoundedBox(4, 1, 0, w - 2, h - 1, color)
            end
        end
        local btnDown = scrollbar.btnDown
        if IsValid(btnDown) then
            btnDown.Paint = function(self, w, h)
                local color = self:IsHovered() and THEME.primaryLight or THEME.primary
                draw.RoundedBox(4, 1, 1, w - 2, h - 1, color)
            end
        end
        local btnGrip = scrollbar.btnGrip
        if IsValid(btnGrip) then
            btnGrip.Paint = function(self, w, h)
                local color = self:IsHovered() and THEME.primaryLight or THEME.primary
                draw.RoundedBox(4, 1, 0, w - 2, h, color)
            end
        end
    end

    for _, data in ipairs(dataList) do
        CreateInfoPanel(scrollPanel, data, isNPC, function(deletedData)
            for i = #dataList, 1, -1 do
                if dataList[i] == deletedData then
                    table.remove(dataList, i)
                end
            end

            local mapName = game.GetMap()
            local filePath = "rareload/player_positions_" .. mapName .. ".json"
            if file.Exists(filePath, "DATA") then
                local success, rawData = pcall(util.JSONToTable, file.Read(filePath, "DATA"))
                if success and rawData and rawData[mapName] then
                    for _, playerData in pairs(rawData[mapName]) do
                        local arr = isNPC and playerData.npcs or playerData.entities
                        if arr then
                            for j = #arr, 1, -1 do
                                local ent = arr[j]
                                if ent.class == deletedData.class and ent.pos and deletedData.pos and
                                    ent.pos.x == deletedData.pos.x and ent.pos.y == deletedData.pos.y and ent.pos.z == deletedData.pos.z then
                                    table.remove(arr, j)
                                end
                            end
                        end
                    end
                    file.Write(filePath, util.TableToJSON(rawData, true))

                    net.Start("RareloadReloadData")
                    net.SendToServer()
                end
            end

            if IsValid(scrollPanel) then
                scrollPanel:Clear()
                for _, d in ipairs(dataList) do
                    CreateInfoPanel(scrollPanel, d, isNPC, function() end, nil, { compact = compact })
                end
            end
        end, nil, { compact = compact })
    end

    local function ToggleExpansion()
        if isAnimating then return end
        isAnimating = true
        isExpanded = not isExpanded

        local animDuration = 0.3
        local startTime = SysTime()
        local startHeight = mainContainer:GetTall()
        local targetHeight = isExpanded and (headerHeight + contentHeight) or headerHeight
        local startFraction = expandFraction
        local targetFraction = isExpanded and 1 or 0

        contentContainer:SetVisible(true)

        timer.Create(uniqueID .. "_toggle", 0, 0, function()
            local elapsed = SysTime() - startTime
            local progress = math.Clamp(elapsed / animDuration, 0, 1)

            local easedProgress = progress < 0.5 and 2 * progress * progress or 1 - math.pow(-2 * progress + 2, 3) / 2

            expandFraction = Lerp(easedProgress, startFraction, targetFraction)
            local currentHeight = Lerp(easedProgress, startHeight, targetHeight)

            mainContainer:SetTall(currentHeight)

            if not isExpanded then
                contentContainer:SetAlpha(255 * (1 - easedProgress))
            else
                contentContainer:SetAlpha(255 * easedProgress)
            end

            if progress >= 1 then
                mainContainer:SetTall(targetHeight)
                expandFraction = targetFraction
                contentContainer:SetVisible(isExpanded)
                contentContainer:SetAlpha(255)
                timer.Remove(uniqueID .. "_toggle")
                isAnimating = false
            end
        end)
    end

    header.DoClick = function()
        surface.PlaySound("ui/buttonclick.wav")
        ToggleExpansion()
    end

    mainContainer:SetTall(headerHeight + contentHeight)

    return mainContainer
end
