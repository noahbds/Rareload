local highlightAllActive = false

if not RARELOAD or not RARELOAD.DataUtils then
    include("rareload/utils/rareload_data_utils.lua")
end

function CreateCategory(parent, title, dataList, isNPC, filter, sortMode, playerPos, options)
    -- Normalize dataList
    local items = {}
    if dataList then
        for k, v in pairs(dataList) do
            if type(v) == "table" then
                v.__originalKey = k
                table.insert(items, v)
            end
        end
    end

    if #items == 0 then return nil end

    -- Filter
    local filteredData = {}
    if filter and filter ~= "" then
        local lowerFilter = string.lower(filter)
        for _, data in ipairs(items) do
            local classMatch = string.find(string.lower(data.class or data.ClassName or "Unknown"), lowerFilter)
            local idMatch = data.id and string.find(string.lower(tostring(data.id)), lowerFilter)
            local keyMatch = data.__originalKey and string.find(string.lower(tostring(data.__originalKey)), lowerFilter)

            if classMatch or idMatch or keyMatch then
                table.insert(filteredData, data)
            end
        end
        items = filteredData
    end

    if #items == 0 then return nil end
    dataList = items

    -- Sort
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
            if da == db then return (a.class or "") < (b.class or "") end
            return da < db
        end)
    elseif sortMode == "Health" then
        table.sort(dataList, function(a, b)
            local ha = tonumber(a.health or -1) or -1
            local hb = tonumber(b.health or -1) or -1
            if ha == hb then return (a.class or "") < (b.class or "") end
            return ha > hb
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

    local headerHeight = 50
    local isExpanded = true
    
    local header = vgui.Create("DButton", mainContainer)
    header:SetText("")
    header:Dock(TOP)
    header:SetTall(headerHeight)
    header:SetCursor("hand")

    local hoverFraction = 0
    header.Paint = function(self, w, h)
        local targetHover = self:IsHovered() and 1 or 0
        hoverFraction = Lerp(FrameTime() * 8, hoverFraction, targetHover)

        local bgColor = THEME:LerpColor(hoverFraction * 0.1, THEME.backgroundDark, THEME.surfaceVariant)
        draw.RoundedBoxEx(8, 0, 0, w, h, bgColor, true, true, not isExpanded, not isExpanded)

        local iconColor = isNPC and THEME.secondary or THEME.primary
        surface.SetDrawColor(iconColor)
        surface.SetMaterial(Material(isNPC and "icon16/user.png" or "icon16/bricks.png"))
        surface.DrawTexturedRect(16, h / 2 - 8, 16, 16)

        draw.SimpleText(title, "RareloadSubheading", 44, h / 2 - 9, THEME.textPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(#dataList .. " items", "RareloadCaption", 44, h / 2 + 9, THEME.textSecondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local arrowRotation = isExpanded and 90 or 0
        local arrowMat = Material("icon16/arrow_right.png")
        surface.SetDrawColor(THEME.textSecondary)
        surface.SetMaterial(arrowMat)
        surface.DrawTexturedRectRotated(w - 24, h / 2, 16, 16, arrowRotation)
    end

    local contentContainer = vgui.Create("DPanel", mainContainer)
    contentContainer:Dock(TOP)
    contentContainer.Paint = function() end
    
    -- Use DIconLayout for grid view
    local layout = vgui.Create("DIconLayout", contentContainer)
    layout:Dock(TOP)
    layout:SetSpaceX(8)
    layout:SetSpaceY(8)
    layout:SetBorder(12)
    layout:SetLayoutDir(LEFT)

    -- Function to update height
    local function UpdateHeight()
        if not IsValid(mainContainer) then return end
        layout:Layout()
        local contentH = layout:GetTall() + 24 -- padding
        contentContainer:SetTall(contentH)
        mainContainer:SetTall(isExpanded and (headerHeight + contentH) or headerHeight)
        if parent.InvalidateLayout then parent:InvalidateLayout(true) end
    end

    header.DoClick = function()
        isExpanded = not isExpanded
        contentContainer:SetVisible(isExpanded)
        UpdateHeight()
        surface.PlaySound("ui/buttonclick.wav")
    end

    -- Populate grid
    for _, data in ipairs(dataList) do
        local card = CreateInfoPanel(layout, data, isNPC, function(deletedData)
            -- Handle deletion
             for i = #dataList, 1, -1 do
                if dataList[i] == deletedData then
                    table.remove(dataList, i)
                end
            end
            -- Update file (simplified for brevity, same logic as before)
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
            
            if IsValid(card) then card:Remove() end
            timer.Simple(0, UpdateHeight)
        end, nil, options)
    end

    -- Initial height update
    timer.Simple(0, UpdateHeight)
    
    return mainContainer
end
