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
CACHE_LIFETIME = 5
PHANTOM_CATEGORIES = {
    { "basic",     "Basic Information",       Color(70, 130, 180) },
    { "position",  "Position and Movement",   Color(60, 179, 113) },
    { "equipment", "Equipment",               Color(218, 165, 32) },
    { "entities",  "Saved Entities and NPCs", Color(178, 34, 34) },
    { "stats",     "Statistics",              Color(147, 112, 219) }
}

-- Performance constants
local LOD_DISTANCE_HIGH = 400
local LOD_DISTANCE_MED = 800
local LOD_DISTANCE_LOW = 1200
local MAX_ITEMS_HIGH_LOD = 50
local MAX_ITEMS_MED_LOD = 20
local MAX_ITEMS_LOW_LOD = 10

PhantomInteractionMode = false
PhantomInteractionTarget = nil
PhantomInteractionAngle = nil
PanelSizeMultiplier = 1.0
ScrollSpeed = 20
MaxPanelHeight = 1000
ScrollPersistence = {}
ScrollbarWidth = 6

-- Cached calculations
local fontSizeCache = {}
local panelSizeCache = {}

function CalculateOptimalPanelSize(categoryContent)
    if type(categoryContent) ~= "table" then
        return 350
    end

    -- Use cached size if available
    local cacheKey = #categoryContent
    if panelSizeCache[cacheKey] then
        return panelSizeCache[cacheKey]
    end

    local baseWidth = 350
    local minWidth = 300
    local maxWidth = 500
    local contentWidth = baseWidth

    surface.SetFont("Trebuchet18")
    for i = 1, math.min(#categoryContent, 10) do -- Sample only first 10 items for performance
        local lineData = categoryContent[i]
        local label = tostring(lineData[1] or "")
        local value = tostring(lineData[2] or "")

        if not fontSizeCache[label] then
            fontSizeCache[label] = surface.GetTextSize(label .. ":")
        end
        if not fontSizeCache[value] then
            fontSizeCache[value] = surface.GetTextSize(value)
        end

        local totalWidth = fontSizeCache[label] + fontSizeCache[value] + 140
        contentWidth = math.max(contentWidth, totalWidth)
    end

    local result = math.Clamp(contentWidth, minWidth, maxWidth)
    panelSizeCache[cacheKey] = result
    return result
end

function table.map(tbl, func)
    if type(tbl) ~= "table" then return {} end

    local result = {}
    for k, v in pairs(tbl) do
        result[k] = func(v, k)
    end
    return result
end

function BuildPhantomInfoData(ply, SavedInfo, mapName, lodLevel)
    lodLevel = lodLevel or 1 -- 1=high, 2=medium, 3=low

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

    -- Basic Information (always full detail)
    table.insert(data.basic, { "Player", ply:Nick(), Color(255, 255, 255) })
    table.insert(data.basic, { "SteamID", ply:SteamID(), Color(200, 200, 200) })
    table.insert(data.basic, { "Model", SavedInfo.playermodel, Color(200, 200, 200) })
    table.insert(data.basic, { "Map", mapName, Color(180, 180, 200) })

    -- Position Information (simplified for lower LOD)
    if lodLevel <= 2 then
        table.insert(data.position,
            { "Position", RARELOAD.DataUtils.FormatVectorDetailed(SavedInfo.pos), Color(255, 255, 255) })
        table.insert(data.position,
            { "Direction", RARELOAD.DataUtils.FormatAngleDetailed(SavedInfo.ang), Color(220, 220, 220) })
    else
        table.insert(data.position,
            { "Position", "(" ..
            math.floor(SavedInfo.pos.x) ..
            ", " .. math.floor(SavedInfo.pos.y) .. ", " .. math.floor(SavedInfo.pos.z) .. ")", Color(255, 255, 255) })
    end

    if lodLevel <= 1 then
        table.insert(data.position,
            { "Movement Type", moveTypeNames[SavedInfo.moveType] or "Unknown", Color(220, 220, 220) })
    end

    -- Equipment (LOD-based item limits)
    local maxItems = lodLevel == 1 and MAX_ITEMS_HIGH_LOD or lodLevel == 2 and MAX_ITEMS_MED_LOD or MAX_ITEMS_LOW_LOD

    if SavedInfo.activeWeapon then
        local weaponName = SavedInfo.activeWeapon
        local prettyName = (string.match(weaponName, "weapon_(.+)") or weaponName):gsub("_", " "):gsub("(%a)([%w_']*)",
            function(first, rest) return first:upper() .. rest end)
        table.insert(data.equipment, { "Active Weapon", prettyName, Color(255, 200, 200) })
    end

    -- Process Inventory with LOD
    if SavedInfo.inventory and type(SavedInfo.inventory) == "table" and #SavedInfo.inventory > 0 then
        table.insert(data.equipment, { "══ Inventory ══", #SavedInfo.inventory .. " items total", Color(255, 220, 150) })

        local categories = { Inventory = { items = {}, color = Color(255, 150, 150), icon = "I" } }

        for i = 1, math.min(#SavedInfo.inventory, maxItems) do
            table.insert(categories["Inventory"].items, SavedInfo.inventory[i])
        end

        if #SavedInfo.inventory > maxItems then
            table.insert(categories["Inventory"].items, "... and " .. (#SavedInfo.inventory - maxItems) .. " more")
        end

        for catName, catData in pairs(categories) do
            if #catData.items > 0 then
                local counts = {}
                for _, item in ipairs(catData.items) do
                    if item ~= "... and " .. (#SavedInfo.inventory - maxItems) .. " more" then
                        counts[item] = (counts[item] or 0) + 1
                    end
                end

                local uniqueItems = {}
                for item, count in pairs(counts) do
                    table.insert(uniqueItems, { item = item, count = count })
                end

                table.sort(uniqueItems, function(a, b) return a.count > b.count end)
                table.insert(data.equipment,
                    { "[" .. catData.icon .. "] " .. catName, #catData.items .. " total", catData.color })

                local displayCount = math.min(#uniqueItems, lodLevel == 1 and 20 or lodLevel == 2 and 10 or 5)
                for i = 1, displayCount do
                    local itemData = uniqueItems[i]
                    local displayText = (itemData.count > 1 and (" ×" .. itemData.count) or "")
                    local prefix = (i == displayCount) and "  └─" or "  ├─"
                    local prettyItemName = itemData.item:gsub("weapon_", ""):gsub("_", " "):gsub("(%a)([%w_']*)",
                        function(first, rest) return first:upper() .. rest end)

                    table.insert(data.equipment,
                        { prefix .. " " .. prettyItemName, displayText, catData.color, { noColon = true } })

                    -- Only show ammo details for high LOD
                    if lodLevel == 1 and SavedInfo.ammo and SavedInfo.ammo[itemData.item] then
                        local ammoInfo = SavedInfo.ammo[itemData.item]
                        local ammoText = ""

                        if ammoInfo.primary and ammoInfo.primary > 0 and ammoInfo.primaryAmmoType and ammoInfo.primaryAmmoType >= 0 then
                            local ammoName = game.GetAmmoName and game.GetAmmoName(ammoInfo.primaryAmmoType) or
                                tostring(ammoInfo.primaryAmmoType)
                            local clipText = ammoInfo.clip1 and ammoInfo.clip1 >= 0 and
                                (" (" .. ammoInfo.clip1 .. " in clip)") or ""
                            ammoText = " [" .. ammoInfo.primary .. clipText .. " " .. ammoName .. "]"
                        end

                        if ammoText ~= "" then
                            local ammoPrefix = (i == displayCount) and "    " or "  │ "
                            table.insert(data.equipment,
                                { ammoPrefix .. "    │--> Ammo", ammoText, Color(catData.color.r * 0.8,
                                    catData.color.g * 0.8, catData.color.b * 0.8), { noColon = true } })
                        end
                    end
                end

                if #uniqueItems > displayCount then
                    table.insert(data.equipment,
                        { "  └─ ...", "+" .. (#uniqueItems - displayCount) .. " more", Color(150, 150, 150), { noColon = true } })
                end
            end
        end
    end

    -- Simplified entity processing for lower LOD
    local function processGroupedDataLOD(group, config)
        if group and type(group) == "table" and #group > 0 then
            table.insert(data.entities, { config.totalLabel, #group, config.totalColor })

            if lodLevel <= 2 then
                local counts = {}
                local processCount = math.min(#group, maxItems)

                for i = 1, processCount do
                    local entry = group[i]
                    local class = entry.class or entry
                    counts[class] = (counts[class] or 0) + 1
                end

                local sorted = {}
                for class, count in pairs(counts) do
                    table.insert(sorted, { class = class, count = count })
                end
                table.sort(sorted, function(a, b) return a.count > b.count end)

                local showCount = math.min(#sorted, lodLevel == 1 and 10 or 5)
                for i = 1, showCount do
                    local entry = sorted[i]
                    local pretty = (string.match(entry.class, config.pattern) or entry.class):gsub("_", " "):gsub(
                        "(%a)([%w_']*)", function(first, rest) return first:upper() .. rest end)
                    table.insert(data.entities,
                        { config.labelPrefix .. " " .. i, string.format("%s (%d)", pretty, entry.count), config
                            .entryColor })
                end

                if #sorted > showCount then
                    table.insert(data.entities,
                        { "...", "+" .. (#sorted - showCount) .. " more types", Color(150, 150, 150) })
                end
            end
        else
            table.insert(data.entities, { config.totalLabel, "0", config.totalColor })
        end
    end

    -- Process entities with LOD
    processGroupedDataLOD(SavedInfo.entities, {
        totalLabel = "Total Entities",
        totalColor = Color(255, 180, 180),
        pattern = "[^_]+_(.+)",
        labelPrefix = "Entity",
        entryColor = Color(255, 180, 180)
    })

    processGroupedDataLOD(SavedInfo.npcs, {
        totalLabel = "Total NPCs",
        totalColor = Color(200, 255, 200),
        pattern = "npc_(.+)",
        labelPrefix = "NPC",
        entryColor = Color(200, 255, 200)
    })

    -- Stats (always show)
    table.insert(data.stats, { "Health", math.floor(SavedInfo.health or 0), Color(255, 180, 180) })
    table.insert(data.stats, { "Armor", math.floor(SavedInfo.armor or 0), Color(180, 180, 255) })

    if lodLevel <= 2 and SavedInfo.npcs and #SavedInfo.npcs > 0 then
        local totalHealth = 0
        for i = 1, math.min(#SavedInfo.npcs, 50) do -- Limit calculation for performance
            totalHealth = totalHealth + (SavedInfo.npcs[i].health or 0)
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

    -- Determine LOD level based on distance
    local lodLevel = 1
    if distanceSqr > LOD_DISTANCE_HIGH * LOD_DISTANCE_HIGH then
        lodLevel = distanceSqr > LOD_DISTANCE_MED * LOD_DISTANCE_MED and 3 or 2
    end

    local now = CurTime()

    -- Use consistent cache key for LOD-based caching
    if not PhantomInfoCache[steamID] or PhantomInfoCache[steamID].expires < now or PhantomInfoCache[steamID].lodLevel ~= lodLevel then
        local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
        PhantomInfoCache[steamID] = {
            data = BuildPhantomInfoData(ply, savedInfo, mapName, lodLevel),
            expires = now + CACHE_LIFETIME,
            activeCategory = (PhantomInfoCache[steamID] and PhantomInfoCache[steamID].activeCategory) or "basic",
            lodLevel = lodLevel,
            hoverScale = (PhantomInfoCache[steamID] and PhantomInfoCache[steamID].hoverScale) or 1.0,
            categoryChanged = (PhantomInfoCache[steamID] and PhantomInfoCache[steamID].categoryChanged) or now
        }
    end

    local cache = PhantomInfoCache[steamID]
    if not cache then return end -- Additional safety check

    local infoData = cache.data
    local activeCategory = cache.activeCategory

    -- Performance: Skip rendering if too many items and distance is far
    if lodLevel >= 3 and #infoData[activeCategory] > 20 then
        return
    end

    -- Rest of the drawing code remains largely the same but with optimized calculations
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

    -- Scale down for distant phantoms
    local distanceScale = isActiveInteraction and 1.5 or math.Clamp(1.0 - (math.sqrt(distanceSqr) / 1500), 0.3, 1.0)
    local scale = 0.1 * (cache.hoverScale or 1.0) * distanceScale

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
        MaxPanelHeight * (0.1 * (cache.hoverScale or 1.0) * (isActiveInteraction and 1.5 or 1.0)))
    local needsScrolling = contentHeight >
        (MaxPanelHeight * 0.1 * (cache.hoverScale or 1.0) * (isActiveInteraction and 1.5 or 1.0) - 20)
    local maxScrollOffset = math.max(0,
        contentHeight -
        (MaxPanelHeight * 0.1 * (cache.hoverScale or 1.0) * (isActiveInteraction and 1.5 or 1.0) - 20))

    ScrollPersistence[steamID] = ScrollPersistence[steamID] or {}
    ScrollPersistence[steamID][activeCategory] = ScrollPersistence[steamID][activeCategory] or 0
    local scrollOffset = needsScrolling and math.Clamp(ScrollPersistence[steamID][activeCategory], 0, maxScrollOffset) or
        0
    ScrollPersistence[steamID][activeCategory] = scrollOffset

    local panelHeight = titleHeight + tabHeight + maxDisplayHeight
    local offsetX, offsetY = -panelWidth / 2, -panelHeight / 2

    cam.Start3D2D(drawPos, panelAng,
        scale)

    ----------------------------
    -- Draw Background & Border
    ----------------------------
    -- Draw Background & Border with consistent radius
    draw.RoundedBox(8, offsetX, offsetY, panelWidth, panelHeight, theme.background)
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
    ---@diagnostic disable-next-line: param-type-mismatch
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    ---@diagnostic disable-next-line: param-type-mismatch
    render.SetStencilPassOperation(STENCIL_REPLACE)
    ---@diagnostic disable-next-line: param-type-mismatch
    render.SetStencilFailOperation(STENCIL_KEEP)
    ---@diagnostic disable-next-line: param-type-mismatch
    render.SetStencilZFailOperation(STENCIL_KEEP)

    draw.RoundedBox(0, offsetX, contentY, panelWidth, maxDisplayHeight, Color(255, 255, 255, 1))
    ---@diagnostic disable-next-line: param-type-mismatch
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    ---@diagnostic disable-next-line: param-type-mismatch
    render.SetStencilPassOperation(STENCIL_KEEP)

    for i, line in ipairs(infoData[activeCategory]) do
        local label, value, valueColor = line[1], tostring(line[2]), line[3] or Color(255, 255, 255)
        local yPos = contentY + (i - 1) * lineHeight - scrollOffset + 10
        if yPos + lineHeight >= contentY - lineHeight and yPos <= contentY + maxDisplayHeight + lineHeight then
            local fadeDelay = i * 0.05
            local alpha = math.min((CurTime() - (cache.categoryChanged or 0) - fadeDelay) * 5, 1)
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

        cache.scrollbarInfo = {
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

        cache.maxScrollOffset = maxScrollOffset
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

    cache.panelInfo = { tabInfo = tabScreenInfo, activeTabIndex = nil, hasScrollbar = needsScrolling }

    for i, tab in ipairs(tabScreenInfo) do
        if tab.catID == activeCategory then
            cache.panelInfo.activeTabIndex = i
            break
        end
    end

    cam.End3D2D()
end
