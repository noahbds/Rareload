local moveTypeNames = {
    [0] = "MOVETYPE_NONE",
    [1] = "MOVETYPE_ISOMETRIC",
    [2] = "MOVETYPE_WALK",
    [3] = "MOVETYPE_STEP",
    [4] = "MOVETYPE_FLY",
    [5] = "MOVETYPE_FLYGRAVITY",
    [6] = "MOVETYPE_VPHYSICS",
    [7] = "MOVETYPE_PUSH",
    [8] = "MOVETYPE_NOCLIP",
    [9] = "MOVETYPE_LADDER",
    [10] = "MOVETYPE_OBSERVER",
    [11] = "MOVETYPE_CUSTOM",
}

PhantomInfoCache = {}
CACHE_LIFETIME = 2
PHANTOM_CATEGORIES = {
    { "basic",     "Basic Information",       Color(70, 130, 180) },
    { "position",  "Position and Movement",   Color(60, 179, 113) },
    { "equipment", "Equipment",               Color(218, 165, 32) },
    { "entities",  "Saved Entities and NPCs", Color(178, 34, 34) },
    { "stats",     "Statistics",              Color(147, 112, 219) }
}

PhantomInteractionMode = false
PhantomInteractionTarget = nil
PhantomInteractionAngle = nil
PanelSizeMultiplier = 1.0
ScrollOffset = 0
MaxScrollOffset = 0
ScrollSpeed = 20
MaxPanelHeight = 1000
ScrollPersistence = {}
ScrollbarWidth = 6
IsScrolling = false
ScrollbarGrabbed = false
ScrollbarGrabOffset = 0


function CalculateOptimalPanelSize(categoryContent)
    if type(categoryContent) ~= "table" then
        return 350
    end

    local baseWidth = 350
    local minWidth = 300
    local maxWidth = 500
    local contentWidth = baseWidth

    for _, lineData in ipairs(categoryContent) do
        local label = tostring(lineData[1] or "")
        local value = tostring(lineData[2] or "")
        surface.SetFont("Trebuchet18")
        local labelWidth = surface.GetTextSize(label .. ":")
        local valueWidth = surface.GetTextSize(value)
        local totalWidth = labelWidth + valueWidth + 140
        contentWidth = math.max(contentWidth, totalWidth)
    end

    return math.Clamp(contentWidth, minWidth, maxWidth)
end

function table.map(tbl, func)
    if type(tbl) ~= "table" then return {} end

    local result = {}
    for k, v in pairs(tbl) do
        result[k] = func(v, k)
    end
    return result
end

local function VectorToString(vec)
    if type(vec) == "string" then
        local x, y, z = vec:match("%[([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)%]")
        if x and y and z then
            return string.format("X: %.1f, Y: %.1f, Z: %.1f", tonumber(x), tonumber(y), tonumber(z))
        end
        return vec
    elseif type(vec) == "table" then
        local x = vec.x or vec[1] or 0
        local y = vec.y or vec[2] or 0
        local z = vec.z or vec[3] or 0
        return string.format("X: %.1f, Y: %.1f, Z: %.1f", x, y, z)
    end
end

local function AngleToString(ang)
    if not ang then
        return "N/A"
    end

    if type(ang) == "string" then
        local p, y, r = ang:match("[{%(]?([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)[%]%)?}")
        if p and y and r then
            return string.format("P: %.1f, Y: %.1f, R: %.1f", tonumber(p), tonumber(y), tonumber(r))
        end
        return ang
    elseif type(ang) == "table" then
        if ang.p and ang.y and ang.r then
            return string.format("P: %.1f, Y: %.1f, R: %.1f", ang.p, ang.y, ang.r)
        elseif #ang >= 3 then
            return string.format("P: %.1f, Y: %.1f, R: %.1f", ang[1] or 0, ang[2] or 0, ang[3] or 0)
        end
    end

    return "N/A"
end

function BuildPhantomInfoData(ply, SavedInfo, mapName)
    local data = {
        basic = {},
        position = {},
        equipment = {},
        entities = {},
        stats = {}
    }

    if not SavedInfo then
        table.insert(data.basic, { "Player", ply:Nick(), Color(255, 255, 255) })
        table.insert(data.basic, { "Status", "No saved data", Color(255, 100, 100) })
        return data
    end

    -- Basic Information
    table.insert(data.basic, { "Player", ply:Nick(), Color(255, 255, 255) })
    table.insert(data.basic, { "SteamID", ply:SteamID(), Color(200, 200, 200) })
    table.insert(data.basic, { "Model", ply:GetModel(), Color(200, 200, 200) })
    table.insert(data.basic, { "Map", mapName, Color(180, 180, 200) })

    -- Position Information
    table.insert(data.position, { "Position", (SavedInfo.pos), Color(255, 255, 255) })
    table.insert(data.position, { "Direction", AngleToString(SavedInfo.ang), Color(220, 220, 220) })
    table.insert(data.position, { "Movement Type", moveTypeNames[SavedInfo.moveType] or "Unknown", Color(220, 220, 220) })

    -- Active Weapon
    if SavedInfo.activeWeapon then
        local weaponName = SavedInfo.activeWeapon
        local prettyName = (string.match(weaponName, "weapon_(.+)") or weaponName)
            :gsub("_", " ")
            :gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest end)
        table.insert(data.equipment, { "Active Weapon", prettyName, Color(255, 200, 200) })
    end

    -- Process Inventory
    if SavedInfo.inventory and type(SavedInfo.inventory) == "table" and #SavedInfo.inventory > 0 then
        table.insert(data.equipment, { "══ Inventory ══", #SavedInfo.inventory .. " items total", Color(255, 220, 150) })

        local categories = {
            Inventory = { items = {}, color = Color(255, 150, 150), icon = "I" }
        }

        for _, item in ipairs(SavedInfo.inventory) do
            table.insert(categories["Inventory"].items, item)
        end

        for catName, catData in pairs(categories) do
            if #catData.items > 0 then
                local counts = {}
                for _, item in ipairs(catData.items) do
                    counts[item] = (counts[item] or 0) + 1
                end

                local uniqueItems = {}
                for item, count in pairs(counts) do
                    table.insert(uniqueItems, { item = item, count = count })
                end

                table.sort(uniqueItems, function(a, b) return a.count > b.count end)
                table.insert(data.equipment, {
                    "[" .. catData.icon .. "] " .. catName,
                    #catData.items .. " total",
                    catData.color
                })

                for i = 1, #uniqueItems do
                    local itemData = uniqueItems[i]
                    local displayText = (itemData.count > 1 and (" ×" .. itemData.count) or "")
                    local prefix = (i == #uniqueItems) and "  └─" or "  ├─"
                    local prettyItemName = itemData.item:gsub("weapon_", ""):gsub("_", " ")
                    prettyItemName = prettyItemName:gsub("(%a)([%w_']*)",
                        function(first, rest) return first:upper() .. rest end)

                    table.insert(data.equipment, {
                        prefix .. " " .. prettyItemName,
                        displayText,
                        catData.color,
                        { noColon = true }
                    })

                    if SavedInfo.ammo and SavedInfo.ammo[itemData.item] then
                        local ammoInfo = SavedInfo.ammo[itemData.item]
                        local ammoText = ""

                        if ammoInfo.primary and ammoInfo.primary > 0 and ammoInfo.primaryAmmoType and ammoInfo.primaryAmmoType >= 0 then
                            local ammoName = "Unknown"
                            if game.GetAmmoName then
                                ammoName = game.GetAmmoName(ammoInfo.primaryAmmoType) or
                                    tostring(ammoInfo.primaryAmmoType)
                            else
                                ammoName = "Type:" .. tostring(ammoInfo.primaryAmmoType)
                            end

                            local clipText = ""
                            if ammoInfo.clip1 and ammoInfo.clip1 >= 0 then
                                clipText = " (" .. ammoInfo.clip1 .. " in clip)"
                            end

                            ammoText = ammoText .. " [" .. ammoInfo.primary .. clipText .. " " .. ammoName .. "]"
                        elseif ammoInfo.clip1 and ammoInfo.clip1 > 0 then
                            ammoText = ammoText .. " [(" .. ammoInfo.clip1 .. " in clip)]"
                        end

                        if ammoInfo.secondary and ammoInfo.secondary > 0 and ammoInfo.secondaryAmmoType and ammoInfo.secondaryAmmoType >= 0 then
                            local ammoName = "Unknown"
                            if game.GetAmmoName then
                                ammoName = game.GetAmmoName(ammoInfo.secondaryAmmoType) or
                                    tostring(ammoInfo.secondaryAmmoType)
                            else
                                ammoName = "Type:" .. tostring(ammoInfo.secondaryAmmoType)
                            end

                            local clipText = ""
                            if ammoInfo.clip2 and ammoInfo.clip2 >= 0 then
                                clipText = " (" .. ammoInfo.clip2 .. " in clip)"
                            end

                            ammoText = ammoText .. " [+" .. ammoInfo.secondary .. clipText .. " " .. ammoName .. "]"
                        elseif ammoInfo.clip2 and ammoInfo.clip2 > 0 and not (ammoInfo.secondary and ammoInfo.secondary > 0) then
                            ammoText = ammoText .. " [(+" .. ammoInfo.clip2 .. " in alt clip)]"
                        end

                        if ammoText ~= "" then
                            local ammoPrefix = (i == #uniqueItems) and "    " or "  │ "
                            table.insert(data.equipment, {
                                ammoPrefix .. "    │--> Ammo",
                                ammoText,
                                Color(catData.color.r * 0.8, catData.color.g * 0.8, catData.color.b * 0.8),
                                { noColon = true }
                            })
                        end
                    end
                end
            end
        end
    end

    local function processGroupedData(group, config)
        if group and type(group) == "table" and #group > 0 then
            local counts = {}
            for _, entry in ipairs(group) do
                local class = entry.class or entry
                counts[class] = (counts[class] or 0) + 1
            end

            table.insert(data.entities, { config.totalLabel, #group, config.totalColor })

            local sorted = {}
            for class, count in pairs(counts) do
                table.insert(sorted, { class = class, count = count })
            end
            table.sort(sorted, function(a, b) return a.count > b.count end)
            for i = 1, #sorted do
                local entry = sorted[i]
                local pretty = (string.match(entry.class, config.pattern) or entry.class)
                    :gsub("_", " ")
                    :gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest end)
                table.insert(data.entities, {
                    config.labelPrefix .. " " .. i,
                    string.format("%s (%d)", pretty, entry.count),
                    config.entryColor
                })
            end
        else
            table.insert(data.entities, { config.totalLabel, "0", config.totalColor })
        end
    end

    -- Process Vehicles separately
    if SavedInfo.vehicles and type(SavedInfo.vehicles) == "table" and #SavedInfo.vehicles > 0 then
        local vehicleCount = #SavedInfo.vehicles
        table.insert(data.entities, { "Total Vehicles", vehicleCount, Color(200, 200, 255) })
        if vehicleCount <= 3 then
            for i, vehicle in ipairs(SavedInfo.vehicles) do
                local pretty = vehicle
                    :gsub("_", " ")
                    :gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest end)
                table.insert(data.entities, {
                    "Vehicle " .. i,
                    pretty,
                    Color(200 - i * 20, 200 - i * 20, 255 - i * 30)
                })
            end
        else
            local types = {}
            for _, vehicle in ipairs(SavedInfo.vehicles) do
                types[vehicle] = (types[vehicle] or 0) + 1
            end
            local sortedTypes = {}
            for typ, count in pairs(types) do
                table.insert(sortedTypes, { type = typ, count = count })
            end
            table.sort(sortedTypes, function(a, b) return a.count > b.count end)
            for i = 1, #sortedTypes do
                local entry = sortedTypes[i]
                local pretty = entry.type
                    :gsub("_", " ")
                    :gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest end)
                table.insert(data.entities, {
                    "Vehicle Type " .. i,
                    string.format("%s (%d)", pretty, entry.count),
                    Color(200 - i * 20, 200 - i * 20, 255 - i * 30)
                })
            end
        end
    end

    -- Process Entities
    processGroupedData(SavedInfo.entities, {
        totalLabel = "Total Entities",
        totalColor = Color(255, 180, 180),
        pattern = "[^_]+_(.+)",
        labelPrefix = "Entity",
        entryColor = Color(255, 180, 180)
    })

    -- Process NPCs
    processGroupedData(SavedInfo.npcs, {
        totalLabel = "Total NPCs",
        totalColor = Color(200, 255, 200),
        pattern = "npc_(.+)",
        labelPrefix = "NPC",
        entryColor = Color(200, 255, 200)
    })


    -- Stats
    table.insert(data.stats, { "Health", math.floor(SavedInfo.health or 0), Color(255, 180, 180) })
    table.insert(data.stats, { "Armor", math.floor(SavedInfo.armor or 0), Color(180, 180, 255) })
    if SavedInfo.npcs and #SavedInfo.npcs > 0 then
        local totalHealth = 0
        for _, npc in ipairs(SavedInfo.npcs) do
            totalHealth = totalHealth + (npc.health or 0)
        end
        table.insert(data.stats, { "Total NPC Health", math.floor(totalHealth), Color(200, 255, 200) })
    end

    return data
end

function DrawPhantomInfo(phantomData, playerPos, mapName)
    local phantom, ply = phantomData.phantom, phantomData.ply
    if not (IsValid(phantom) and IsValid(ply)) then return end

    local steamID = ply:SteamID()
    local phantomPos = phantom:GetPos()
    local distanceSqr = playerPos:DistToSqr(phantomPos)
    local isActiveInteraction = PhantomInteractionMode and PhantomInteractionTarget == steamID
    local maxDistance = isActiveInteraction and 500000 or 250000

    if distanceSqr > maxDistance then
        PhantomInfoCache[steamID] = nil
        if isActiveInteraction then
            PhantomInteractionMode = false
            PhantomInteractionTarget = nil
            PhantomInteractionAngle = nil
        end
        return
    end

    local now = CurTime()
    if not PhantomInfoCache[steamID] or PhantomInfoCache[steamID].expires < now then
        local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
        PhantomInfoCache[steamID] = {
            data = BuildPhantomInfoData(ply, savedInfo, mapName),
            expires = now + CACHE_LIFETIME,
            activeCategory = (PhantomInfoCache[steamID] and PhantomInfoCache[steamID].activeCategory) or "basic"
        }
    end

    local infoData = PhantomInfoCache[steamID].data
    local activeCategory = PhantomInfoCache[steamID].activeCategory
    local drawPos = phantomPos + Vector(0, 0, 80)
    local panelAng = nil

    if isActiveInteraction then
        panelAng = PhantomInteractionAngle
    else
        local dir = (phantomPos - playerPos)
        dir:Normalize()
        panelAng = dir:Angle()
        panelAng.y = panelAng.y - 90
        panelAng.p, panelAng.r = 0, 90
    end

    local theme = {
        background = Color(20, 20, 30, 220),
        header = Color(30, 30, 45, 255),
        border = Color(70, 130, 180, 255),
        text = Color(220, 220, 255),
        scrollbar = Color(40, 40, 50, 120),
        scrollbarHandle = Color(160, 180, 200, 200)
    }

    local lineHeight = 22
    local titleHeight = 40
    local tabHeight = 30
    local textPadding = 15
    local scrollbarPadding = 5
    local optimalWidth = CalculateOptimalPanelSize(infoData[activeCategory])
    local contentWidth = optimalWidth * PanelSizeMultiplier
    local panelWidth = math.max(contentWidth, 800)
    local contentHeight = (#infoData[activeCategory]) * lineHeight
    local maxDisplayHeight = math.min(contentHeight + 20,
        MaxPanelHeight * (0.1 * (PhantomInfoCache[steamID].hoverScale or 1.0) * (isActiveInteraction and 1.5 or 1.0)))
    local needsScrolling = contentHeight >
        (MaxPanelHeight * 0.1 * (PhantomInfoCache[steamID].hoverScale or 1.0) * (isActiveInteraction and 1.5 or 1.0) - 20)
    local maxScrollOffset = math.max(0,
        contentHeight -
        (MaxPanelHeight * 0.1 * (PhantomInfoCache[steamID].hoverScale or 1.0) * (isActiveInteraction and 1.5 or 1.0) - 20))

    ScrollPersistence[steamID] = ScrollPersistence[steamID] or {}
    ScrollPersistence[steamID][activeCategory] = ScrollPersistence[steamID][activeCategory] or 0
    local scrollOffset = needsScrolling and math.Clamp(ScrollPersistence[steamID][activeCategory], 0, maxScrollOffset) or
        0
    ScrollPersistence[steamID][activeCategory] = scrollOffset

    local panelHeight = titleHeight + tabHeight + maxDisplayHeight
    local offsetX, offsetY = -panelWidth / 2, -panelHeight / 2

    cam.Start3D2D(drawPos, panelAng,
        0.1 * (PhantomInfoCache[steamID].hoverScale or 1.0) * (isActiveInteraction and 1.5 or 1.0))

    ----------------------------
    -- Draw Background & Border
    ----------------------------
    draw.RoundedBox(5, offsetX, offsetY, panelWidth, panelHeight, theme.background)
    for i = 0, 2 do
        local borderColor = Color(theme.border.r, theme.border.g, theme.border.b, 255 - i * 40)
        surface.SetDrawColor(borderColor)
        surface.DrawOutlinedRect(offsetX - i, offsetY - i, panelWidth + i * 2, panelHeight + i * 2, 1)
    end

    ----------------------------
    -- Draw Header
    ----------------------------
    local titleText = "Phantom of " .. ply:Nick()
    surface.SetDrawColor(theme.header)
    surface.DrawRect(offsetX, offsetY, panelWidth, titleHeight)
    draw.SimpleText(titleText, "Trebuchet24", offsetX + panelWidth / 2 + 1, offsetY + titleHeight / 2 + 1,
        Color(0, 0, 0, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(titleText, "Trebuchet24", offsetX + panelWidth / 2, offsetY + titleHeight / 2 + 3,
        theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    ----------------------------
    -- Draw Tabs
    ----------------------------
    local minTabWidth = 0
    for _, cat in ipairs(PHANTOM_CATEGORIES) do
        surface.SetFont("Trebuchet18")
        local textWidth = surface.GetTextSize(cat[2])
        minTabWidth = math.max(minTabWidth, textWidth + 20)
    end
    local tabWidth = math.max(panelWidth / #PHANTOM_CATEGORIES, minTabWidth)
    panelWidth = math.max(panelWidth, tabWidth * #PHANTOM_CATEGORIES)
    offsetX = -panelWidth / 2

    local tabY = offsetY + titleHeight
    local tabScreenInfo = {}
    for i, categoryInfo in ipairs(PHANTOM_CATEGORIES) do
        local catID, catName, catColor = categoryInfo[1], categoryInfo[2], categoryInfo[3]
        local tabX = offsetX + (i - 1) * tabWidth
        local isActive = (catID == activeCategory)

        local bgR = isActive and catColor.r / 2.5 or 40
        local bgG = isActive and catColor.g / 2.5 or 40
        local bgB = isActive and catColor.b / 2.5 or 40
        surface.SetDrawColor(bgR, bgG, bgB, 200)
        surface.DrawRect(tabX, tabY, tabWidth, tabHeight)

        if isActive then
            for j = 0, 2 do
                surface.SetDrawColor(catColor.r, catColor.g, catColor.b, 255 - j * 50)
                surface.DrawOutlinedRect(tabX + j, tabY + j, tabWidth - j * 2, tabHeight - j * 2, 1)
            end
            local triSize = 8
            draw.NoTexture()
            surface.SetDrawColor(catColor)
            surface.DrawPoly({
                { x = tabX + tabWidth / 2 - triSize, y = tabY + tabHeight },
                { x = tabX + tabWidth / 2 + triSize, y = tabY + tabHeight },
                { x = tabX + tabWidth / 2,           y = tabY + tabHeight + triSize }
            })
        end

        local textColor = isActive and Color(255, 255, 255) or Color(180, 180, 180)
        surface.SetFont("Trebuchet18")
        draw.SimpleText(catName, "Trebuchet18", tabX + tabWidth / 2, tabY + tabHeight / 2,
            textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        table.insert(tabScreenInfo,
            {
                catID = catID,
                worldX = tabX + tabWidth / 2,
                worldY = tabY + tabHeight / 2,
                worldW = tabWidth,
                worldH =
                    tabHeight
            })
    end

    ----------------------------
    -- Draw Content via Stencil
    ----------------------------
    local contentY = tabY + tabHeight
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)

    draw.RoundedBox(0, offsetX, contentY, panelWidth, maxDisplayHeight, Color(255, 255, 255, 1))
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    render.SetStencilPassOperation(STENCIL_KEEP)

    for i, line in ipairs(infoData[activeCategory]) do
        local label, value, valueColor = line[1], tostring(line[2]), line[3] or Color(255, 255, 255)
        local yPos = contentY + (i - 1) * lineHeight - scrollOffset + 10
        if yPos + lineHeight >= contentY - lineHeight and yPos <= contentY + maxDisplayHeight + lineHeight then
            local fadeDelay = i * 0.05
            local alpha = math.min((CurTime() - (PhantomInfoCache[steamID].categoryChanged or 0) - fadeDelay) * 5, 1)
            alpha = math.max(alpha, 0)

            surface.SetFont("Trebuchet18")

            local colonSuffix = (line[4] and line[4].noColon) and "" or ":"
            draw.SimpleText(label .. colonSuffix, "Trebuchet18", offsetX + textPadding, yPos,
                Color(200, 200, 200, 200 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local valueX = offsetX + textPadding + 120
            local maxValueWidth = panelWidth - (textPadding * 2) - 130 -
                (needsScrolling and (5 + scrollbarPadding * 2) or 0)
            surface.SetFont("Trebuchet18")
            local textWidth = surface.GetTextSize(value)
            if textWidth > maxValueWidth then
                local low, high = 1, #value
                while low <= high do
                    local mid = math.floor((low + high) / 2)
                    local testStr = string.sub(value, 1, mid) .. "..."
                    if surface.GetTextSize(testStr) <= maxValueWidth then
                        low = mid + 1
                    else
                        high = mid - 1
                    end
                end
                value = high >= 5 and (string.sub(value, 1, high) .. "...") or
                    (string.sub(value, 1, math.floor(maxValueWidth / 10)) .. "...")
            end
            local finalColor = Color(valueColor.r, valueColor.g, valueColor.b, (valueColor.a or 255) * alpha)
            draw.SimpleText(value, "Trebuchet18", valueX, yPos,
                finalColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    render.SetStencilEnable(false)

    ----------------------------
    -- Draw Scrollbar
    ----------------------------
    if needsScrolling then
        local scrollBarWidth = 5
        local scrollbarPadding = 5
        local scrollBarX = offsetX + panelWidth - scrollBarWidth - scrollbarPadding
        local scrollbarTopPadding = scrollbarPadding
        local scrollbarBottomPadding = scrollbarPadding
        local scrollBarY = contentY + scrollbarTopPadding
        local scrollBarHeight = maxDisplayHeight - scrollbarTopPadding - scrollbarBottomPadding

        draw.RoundedBox(4, scrollBarX, scrollBarY, scrollBarWidth, scrollBarHeight, theme.scrollbar)

        local handleRatio = math.min(1, scrollBarHeight / contentHeight)
        local handleHeight = math.max(30, scrollBarHeight * handleRatio)
        local handleY = scrollBarY + (scrollOffset / maxScrollOffset) * (scrollBarHeight - handleHeight)
        draw.RoundedBox(4, scrollBarX, handleY, scrollBarWidth, handleHeight, theme.scrollbarHandle)

        local btnSize = scrollBarWidth + 4
        if scrollOffset > 0 then
            draw.SimpleText("▲", "Trebuchet18", scrollBarX + scrollBarWidth / 2, scrollBarY + btnSize / 2 - 2,
                Color(255, 255, 255, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        if scrollOffset < maxScrollOffset then
            draw.SimpleText("▼", "Trebuchet18", scrollBarX + scrollBarWidth / 2,
                scrollBarY + scrollBarHeight - btnSize / 2 + 2,
                Color(255, 255, 255, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        PhantomInfoCache[steamID].scrollbarInfo = {
            x = scrollBarX,
            y = scrollBarY,
            width = scrollBarWidth,
            height = scrollBarHeight,
            handleY = handleY,
            handleHeight = handleHeight,
            contentHeight = contentHeight,
            visibleHeight = maxDisplayHeight,
            maxScrollOffset = maxScrollOffset,
            upButtonY = scrollBarY,
            upButtonHeight = btnSize,
            downButtonY = scrollBarY + scrollBarHeight - btnSize + 2,
            downButtonHeight = btnSize
        }

        PhantomInfoCache[steamID].maxScrollOffset = maxScrollOffset
    end

    ----------------------------
    -- Draw Help/Prompt Text
    ----------------------------
    if isActiveInteraction then
        local helpText = "← → to navigate tabs  |  ↑↓ or use Scroll wheel to scroll |  E to Exit"
        surface.SetFont("Trebuchet18")
        local textWidth, textHeight = surface.GetTextSize(helpText)

        local textY = offsetY - 20
        local bgPadding = 5

        draw.RoundedBox(4,
            offsetX + panelWidth / 2 - textWidth / 2 - 10,
            textY - textHeight / 2 - bgPadding,
            textWidth + 20,
            textHeight + bgPadding * 2,
            Color(20, 20, 30, 200))

        draw.SimpleText(helpText, "Trebuchet18", offsetX + panelWidth / 2, textY,
            Color(255, 255, 255, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    elseif distanceSqr < 10000 then
        local promptText = "Press [E] to interact"
        surface.SetFont("Trebuchet18")
        local textWidth, textHeight = surface.GetTextSize(promptText)

        local textY = offsetY - 20
        local bgPadding = 5

        draw.RoundedBox(4,
            offsetX + panelWidth / 2 - textWidth / 2 - 10,
            textY - textHeight / 2 - bgPadding,
            textWidth + 20,
            textHeight + bgPadding * 2,
            Color(20, 20, 30, 200))

        draw.SimpleText(promptText, "Trebuchet18", offsetX + panelWidth / 2, textY,
            Color(255, 255, 255, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    PhantomInfoCache[steamID].panelInfo = { tabInfo = tabScreenInfo, activeTabIndex = nil, hasScrollbar = needsScrolling }

    for i, tab in ipairs(tabScreenInfo) do
        if tab.catID == activeCategory then
            PhantomInfoCache[steamID].panelInfo.activeTabIndex = i
            break
        end
    end

    cam.End3D2D()
end
