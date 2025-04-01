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

    if #dataList == 0 then
        return nil
    end

    local mainContainer = vgui.Create("DPanel", parent)
    mainContainer:Dock(TOP)
    mainContainer:DockMargin(40, 40, 40, 0)
    mainContainer:SetPaintBackground(false)

    local itemHeight = 140
    local headerHeight = 30
    local marginHeight = 10
    local maxVisibleItems = 10
    local contentHeight = math.min(#dataList, maxVisibleItems) * (itemHeight + marginHeight)

    mainContainer:SetTall(headerHeight)

    local isExpanded = true

    local header = vgui.Create("DButton", mainContainer)
    header:SetText("")
    header:Dock(TOP)
    header:SetTall(headerHeight)
    header:SetCursor("hand")

    header.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.header)

        surface.SetDrawColor(THEME.text)
        surface.SetMaterial(Material(isExpanded and "icon16/arrow_down.png" or "icon16/arrow_right.png"))
        surface.DrawTexturedRect(w - 24, h / 2 - 8, 16, 16)

        draw.SimpleText(title .. " (" .. #dataList .. ")", "RareloadText", 10, h / 2, THEME.text, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
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

    table.sort(dataList, function(a, b)
        return (a.class or "") < (b.class or "")
    end)

    for _, data in ipairs(dataList) do
        local infoPanel = CreateInfoPanel(scrollPanel, data, isNPC, function()
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

    local function ToggleExpansion()
        isExpanded = not isExpanded

        if isExpanded then
            mainContainer:SetTall(headerHeight + contentHeight)
            contentContainer:SetVisible(true)

            contentContainer:SetAlpha(0)
            contentContainer:AlphaTo(255, 0.2, 0)
        else
            contentContainer:SetVisible(false)
            mainContainer:SetTall(headerHeight)
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
            contentContainer:SetVisible(true)
        end
    end)

    timer.Simple(0.5, function()
        if IsValid(mainContainer) and isExpanded then
            mainContainer:SetTall(headerHeight + contentHeight)
            contentContainer:SetVisible(true)
        end
    end)

    return mainContainer
end
