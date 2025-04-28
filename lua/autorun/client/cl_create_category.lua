function CreateCategory(parent, title, dataList, isNPC, filter)
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

    if #dataList == 0 then return nil end

    table.sort(dataList, function(a, b)
        return (a.class or "") < (b.class or "")
    end)

    local mainContainer = vgui.Create("DPanel", parent)
    mainContainer:Dock(TOP)
    mainContainer:DockMargin(20, 15, 20, 5)
    mainContainer:SetPaintBackground(false)

    local itemHeight = 200
    local headerHeight = 36
    local marginHeight = 10
    local maxVisibleItems = 10
    local contentHeight = math.min(#dataList, maxVisibleItems) * (itemHeight + marginHeight)

    mainContainer:SetTall(headerHeight)

    local isExpanded = true
    local isAnimating = false
    local uniqueID = "CategoryContainer_" .. math.random(1000000)

    local header = vgui.Create("DButton", mainContainer)
    header:SetText("")
    header:Dock(TOP)
    header:SetTall(headerHeight)
    header:SetCursor("hand")

    header.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.header)
        surface.SetDrawColor(255, 255, 255, 20)
        surface.DrawRect(2, 2, w - 4, h / 3)
        if self:IsHovered() then
            surface.SetDrawColor(THEME.accent)
            surface.DrawOutlinedRect(1, 1, w - 2, h - 2, 1)
        end
        local arrowMat = Material(isExpanded and "icon16/arrow_down.png" or "icon16/arrow_right.png")
        surface.SetDrawColor(THEME.text)
        surface.SetMaterial(arrowMat)
        local arrowOffset = self:IsHovered() and math.sin(CurTime() * 4) * 2 or 0
        surface.DrawTexturedRect(w - 24, h / 2 - 8 + arrowOffset, 16, 16)
        draw.SimpleText(
            title .. " (" .. #dataList .. ")",
            "RareloadText",
            10,
            h / 2,
            THEME.text,
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER
        )
        if self:IsHovered() then
            draw.SimpleText(
                isExpanded and "Click to collapse" or "Click to expand",
                "RareloadSmall",
                w - 30,
                h / 2,
                Color(THEME.text.r, THEME.text.g, THEME.text.b, 120),
                TEXT_ALIGN_RIGHT,
                TEXT_ALIGN_CENTER
            )
        end
    end

    local contentContainer = vgui.Create("DPanel", mainContainer)
    contentContainer:Dock(FILL)
    contentContainer:SetPaintBackground(false)
    contentContainer:DockMargin(5, 5, 5, 5)
    contentContainer:SetVisible(isExpanded)

    local scrollPanel = vgui.Create("DScrollPanel", contentContainer)
    scrollPanel:Dock(FILL)

    local scrollbar = scrollPanel:GetVBar()
    if IsValid(scrollbar) then
        scrollbar:SetWide(8)
        scrollbar.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, Color(THEME.background.r, THEME.background.g, THEME.background.b, 150))
        end
        scrollbar.btnUp.Paint = function(self, w, h)
            local color = self:IsHovered() and Color(THEME.accent.r * 1.2, THEME.accent.g * 1.2, THEME.accent.b * 1.2) or
            THEME.accent
            draw.RoundedBox(4, 2, 0, w - 4, h - 2, color)
        end
        scrollbar.btnDown.Paint = function(self, w, h)
            local color = self:IsHovered() and Color(THEME.accent.r * 1.2, THEME.accent.g * 1.2, THEME.accent.b * 1.2) or
            THEME.accent
            draw.RoundedBox(4, 2, 2, w - 4, h - 2, color)
        end
        scrollbar.btnGrip.Paint = function(self, w, h)
            local color = self:IsHovered() and Color(THEME.accent.r * 1.2, THEME.accent.g * 1.2, THEME.accent.b * 1.2) or
            THEME.accent
            draw.RoundedBox(4, 2, 0, w - 4, h, color)
        end
    end

    local showBatchActions = true
    local batchActionsPanel

    if showBatchActions then
        batchActionsPanel = vgui.Create("DPanel", contentContainer)
        batchActionsPanel:Dock(TOP)
        batchActionsPanel:SetTall(30)
        batchActionsPanel:DockMargin(5, 0, 5, 5)
        batchActionsPanel.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h,
                Color(THEME.background.r * 1.2, THEME.background.g * 1.2, THEME.background.b * 1.2))
        end

        local batchLabel = vgui.Create("DLabel", batchActionsPanel)
        batchLabel:SetText("Batch Actions:")
        batchLabel:SetFont("RareloadSmall")
        batchLabel:SetTextColor(THEME.text)
        batchLabel:SizeToContents()
        batchLabel:Dock(LEFT)
        batchLabel:DockMargin(8, 0, 0, 0)

        local function CreateBatchButton(text, icon, color, onClick)
            local btn = vgui.Create("DButton", batchActionsPanel)
            btn:SetText("")
            btn:SetSize(26, 26)
            btn:SetTooltip(text)
            btn:Dock(LEFT)
            btn:DockMargin(4, 2, 0, 2)
            btn.Paint = function(self, w, h)
                local btnColor = self:IsHovered() and Color(color.r * 1.2, color.g * 1.2, color.b * 1.2) or color
                draw.RoundedBox(4, 0, 0, w, h, btnColor)
                if icon then
                    surface.SetDrawColor(255, 255, 255, 230)
                    surface.SetMaterial(Material(icon))
                    surface.DrawTexturedRect(w / 2 - 8, h / 2 - 8, 16, 16)
                end
            end
            btn.DoClick = function()
                surface.PlaySound("ui/buttonclickrelease.wav")
                onClick(dataList)
            end
            return btn
        end

        CreateBatchButton("Teleport to First", "icon16/arrow_right.png", Color(80, 180, 80), function(items)
            if items and items[1] and items[1].pos then
                RunConsoleCommand("rareload_teleport_to", items[1].pos.x, items[1].pos.y, items[1].pos.z)
                ShowNotification("Teleporting to first " .. (isNPC and "NPC" or "entity") .. "!", NOTIFY_GENERIC)
            end
        end)

        CreateBatchButton("Highlight All", "icon16/eye.png", Color(255, 220, 80), function(items)
            local count = 0
            for _, item in ipairs(items) do
                if item.pos then count = count + 1 end
            end
            ShowNotification("Highlighting " .. count .. " positions is not implemented yet", NOTIFY_HINT)
        end)

        CreateBatchButton("Export All", "icon16/disk.png", Color(180, 180, 255), function(items)
            SetClipboardText(util.TableToJSON(items, true))
            ShowNotification(#items .. " items exported as JSON!", NOTIFY_GENERIC)
        end)

        CreateBatchButton("Delete All", "icon16/cross.png", THEME.dangerAccent, function(items)
            local frameW, frameH = ScrW() * 0.3, ScrH() * 0.18
            local confirmFrame = vgui.Create("DFrame")
            confirmFrame:SetSize(frameW, frameH)
            confirmFrame:SetTitle("Confirm Batch Deletion")
            confirmFrame:SetBackgroundBlur(true)
            confirmFrame:Center()
            confirmFrame:MakePopup()
            confirmFrame.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, THEME.background)
                draw.RoundedBox(4, 0, 0, w, 24, THEME.header)
                surface.SetDrawColor(255, 70, 70)
                surface.SetMaterial(Material("icon16/exclamation.png"))
                surface.DrawTexturedRect(w / 2 - 8, h / 2 - 30, 16, 16)
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

            local btnWidth = (frameW - 40) / 2

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
                ShowNotification("Batch deletion not implemented yet", NOTIFY_HINT)
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
                if self:IsHovered() then
                    surface.SetDrawColor(255, 255, 255, 30)
                    surface.DrawRect(2, 2, w - 4, h / 3)
                end
            end
            noButton.DoClick = function() confirmFrame:Close() end
        end)
    end

    for _, data in ipairs(dataList) do
        local infoPanel = CreateInfoPanel(scrollPanel, data, isNPC, function()
            local remainingItems = #dataList - 1
            header.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, THEME.header)
                surface.SetDrawColor(255, 255, 255, 20)
                surface.DrawRect(2, 2, w - 4, h / 3)
                if self:IsHovered() then
                    surface.SetDrawColor(THEME.accent)
                    surface.DrawOutlinedRect(1, 1, w - 2, h - 2, 1)
                end
                surface.SetDrawColor(THEME.text)
                surface.SetMaterial(Material(isExpanded and "icon16/arrow_down.png" or "icon16/arrow_right.png"))
                surface.DrawTexturedRect(w - 24, h / 2 - 8, 16, 16)
                draw.SimpleText(title .. " (" .. remainingItems .. ")", "RareloadText", 10, h / 2, THEME.text,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if self:IsHovered() then
                    draw.SimpleText(isExpanded and "Click to collapse" or "Click to expand", "RareloadSmall", w - 30,
                        h / 2, Color(THEME.text.r, THEME.text.g, THEME.text.b, 120), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
            if remainingItems <= 0 then
                mainContainer:AlphaTo(0, 0.3, 0, function() mainContainer:Remove() end)
            end
        end)
    end

    local function ToggleExpansion()
        if isAnimating then return end
        isAnimating = true
        isExpanded = not isExpanded
        if isExpanded then
            contentContainer:SetVisible(true)
            contentContainer:SetAlpha(0)
            contentContainer:AlphaTo(255, 0.3, 0)
            local animTime = 0.25
            local startTime = SysTime()
            local startHeight = headerHeight
            local targetHeight = headerHeight + contentHeight
            timer.Create(uniqueID .. "_expand", 0, 0, function()
                local elapsed = SysTime() - startTime
                local fraction = math.Clamp(elapsed / animTime, 0, 1)
                local smooth = math.sin(fraction * math.pi * 0.5)
                mainContainer:SetTall(Lerp(smooth, startHeight, targetHeight))
                if fraction >= 1 then
                    mainContainer:SetTall(targetHeight)
                    timer.Remove(uniqueID .. "_expand")
                    isAnimating = false
                end
            end)
        else
            local animTime = 0.2
            local startTime = SysTime()
            local startHeight = mainContainer:GetTall()
            local targetHeight = headerHeight
            contentContainer:AlphaTo(0, 0.2, 0)
            timer.Create(uniqueID .. "_collapse", 0, 0, function()
                local elapsed = SysTime() - startTime
                local fraction = math.Clamp(elapsed / animTime, 0, 1)
                local smooth = math.sin(fraction * math.pi * 0.5)
                mainContainer:SetTall(Lerp(smooth, startHeight, targetHeight))
                if fraction >= 1 then
                    mainContainer:SetTall(targetHeight)
                    contentContainer:SetVisible(false)
                    timer.Remove(uniqueID .. "_collapse")
                    isAnimating = false
                end
            end)
        end
    end

    header.DoClick = function()
        surface.PlaySound("ui/buttonclick.wav")
        ToggleExpansion()
    end

    mainContainer:SetTall(headerHeight + contentHeight)
    timer.Simple(0.1, function()
        if IsValid(mainContainer) then
            mainContainer:SetTall(headerHeight + contentHeight)
            contentContainer:SetVisible(isExpanded)
        end
    end)
    timer.Simple(0.5, function()
        if IsValid(mainContainer) and isExpanded then
            local newContentHeight = math.min(#dataList, maxVisibleItems) * (itemHeight + marginHeight)
            mainContainer:SetTall(headerHeight + newContentHeight)
            contentContainer:SetVisible(true)
            if IsValid(scrollPanel) then scrollPanel:InvalidateLayout(true) end
        end
    end)

    return mainContainer
end
