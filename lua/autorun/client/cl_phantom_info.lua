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

local phantomInfoCache = {}
local CACHE_LIFETIME = 2
local PHANTOM_CATEGORIES = {
    { "basic",     "Basic Information",     Color(70, 130, 180) },
    { "position",  "Position and Movement", Color(60, 179, 113) },
    { "equipment", "Equipment",             Color(218, 165, 32) },
    { "entities",  "Saved Entities",        Color(178, 34, 34) },
    { "stats",     "Statistics",            Color(147, 112, 219) }
}

local phantomInteractionMode = false
local phantomInteractionTarget = nil
local phantomInteractionAngle = nil
local panelSizeMultiplier = 1.0
local scrollOffset = 0
local maxScrollOffset = 0
local scrollSpeed = 20
local maxPanelHeight = 1000
local scrollPersistence = {}
local scrollbarWidth = 6


local isScrolling = false
local scrollbarGrabbed = false
local scrollbarGrabOffset = 0


local function calculateOptimalPanelSize(categoryContent)
    local baseWidth = 350
    local maxWidth = 500
    local minWidth = 300

    local contentWidth = baseWidth
    for _, lineData in ipairs(categoryContent) do
        local label, value = lineData[1], tostring(lineData[2])
        surface.SetFont("Trebuchet18")
        local labelWidth = surface.GetTextSize(label .. ":")
        local valueWidth = surface.GetTextSize(value)
        local totalWidth = labelWidth + valueWidth + 140
        contentWidth = math.max(contentWidth, totalWidth)
    end

    return math.Clamp(contentWidth, minWidth, maxWidth)
end

function table.map(tbl, func)
    if not tbl or type(tbl) ~= "table" then return {} end
    local t = {}
    for k, v in pairs(tbl) do
        t[k] = func(v, k)
    end
    return t
end

local function VectorToString(vec)
    if type(vec) == "string" then
        local x, y, z = vec:match("%[([%d.-]+) ([%d.-]+) ([%d.-]+)%]")
        if x and y and z then
            return string.format("X: %.1f, Y: %.1f, Z: %.1f", tonumber(x), tonumber(y), tonumber(z))
        end
        return vec
    end
    return string.format("X: %.1f, Y: %.1f, Z: %.1f", vec.x, vec.y, vec.z)
end

local function AngleToString(ang)
    if not ang then return "N/A" end

    if type(ang) == "string" then
        local p, y, r = ang:match("{([%d.-]+) ([%d.-]+) ([%d.-]+)}")
        if p and y and r then
            return string.format("P: %.1f, Y: %.1f, R: %.1f", tonumber(p), tonumber(y), tonumber(r))
        elseif type(ang) == "table" then
            return string.format("P: %.1f, Y: %.1f, R: %.1f", ang[1] or 0, ang[2] or 0, ang[3] or 0)
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

local function buildPhantomInfoData(ply, SavedInfo, mapName)
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
    table.insert(data.position, { "Position", VectorToString(SavedInfo.pos), Color(255, 255, 255) })
    table.insert(data.position, { "Direction", AngleToString(SavedInfo.ang), Color(220, 220, 220) })
    table.insert(data.position, { "Movement Type", moveTypeNames[SavedInfo.moveType] or "Unknown", Color(220, 220, 220) })

    -- Active weapon
    if SavedInfo.activeWeapon then
        local weaponName = SavedInfo.activeWeapon
        local prettyName = string.match(weaponName, "weapon_(.+)") or weaponName
        prettyName = prettyName:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
            return first:upper() .. rest
        end)

        table.insert(data.equipment, { "Active Weapon", prettyName, Color(255, 200, 200) })
    end


    -- inventory weapons
    if SavedInfo.inventory and type(SavedInfo.inventory) == "table" and #SavedInfo.inventory > 0 then
        table.insert(data.equipment, { "Inventory", #SavedInfo.inventory .. " items total", Color(255, 220, 150) })

        local categories = {
            Weapons = { items = {}, color = Color(255, 180, 180) },
            Items = { items = {}, color = Color(180, 255, 180) },
            Ammo = { items = {}, color = Color(180, 180, 255) },
            Misc = { items = {}, color = Color(220, 220, 220) }
        }

        for _, item in ipairs(SavedInfo.inventory) do
            local category = "Misc"

            if string.find(item, "weapon_") then
                category = "Weapons"
            elseif string.find(item, "item_") then
                category = "Items"
            elseif string.find(item, "ammo_") then
                category = "Ammo"
            end

            table.insert(categories[category].items, item)
        end

        for categoryName, categoryData in pairs(categories) do
            local items = categoryData.items
            if #items > 0 then
                local itemCounts = {}
                for _, item in ipairs(items) do
                    itemCounts[item] = (itemCounts[item] or 0) + 1
                end

                local uniqueItems = {}
                for item, count in pairs(itemCounts) do
                    table.insert(uniqueItems, { item = item, count = count })
                end

                table.sort(uniqueItems, function(a, b) return a.count > b.count end)

                table.insert(data.equipment, {
                    "» " .. categoryName,
                    #items .. " total",
                    categoryData.color
                })

                for i, itemData in ipairs(uniqueItems) do
                    local prettyName = string.match(itemData.item, "[^_]+_(.+)") or itemData.item
                    prettyName = prettyName:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
                        return first:upper() .. rest
                    end)

                    local displayText = prettyName
                    if itemData.count > 1 then
                        displayText = displayText .. " ×" .. itemData.count
                    end

                    local prefix = (i == #uniqueItems) and "  └ " or "  ├ "

                    table.insert(data.equipment, {
                        prefix .. itemData.item:sub(1, 15),
                        displayText,
                        Color(
                            categoryData.color.r * 0.8,
                            categoryData.color.g * 0.8,
                            categoryData.color.b * 0.8
                        )
                    })
                end
            end
        end
    end

    -- ammo
    if SavedInfo.ammo and type(SavedInfo.ammo) == "table" and #SavedInfo.ammo > 0 then
        local ammoTypes = {}
        for i, ammoEntry in ipairs(SavedInfo.ammo) do
            local ammoID = ammoEntry.id or i
            local ammoCount = ammoEntry.count or 0
            local ammoName = ammoEntry.name or ("Ammo #" .. ammoID)

            ammoTypes[ammoName] = (ammoTypes[ammoName] or 0) + ammoCount
        end

        table.insert(data.equipment, { "Ammunition", #SavedInfo.ammo .. " types", Color(150, 180, 255) })

        local sortedAmmo = {}
        for name, count in pairs(ammoTypes) do
            table.insert(sortedAmmo, { name = name, count = count })
        end

        table.sort(sortedAmmo, function(a, b) return a.count > b.count end)

        for i = 1, math.min(3, #sortedAmmo) do
            local ammo = sortedAmmo[i]
            local displayName = ammo.name:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
                return first:upper() .. rest
            end)

            table.insert(data.equipment, {
                "  " .. (i == #sortedAmmo and "└" or "├") .. " Type " .. i,
                displayName .. ": " .. ammo.count,
                Color(180 - i * 10, 180, 255 - i * 10)
            })
        end

        if #sortedAmmo > 3 then
            table.insert(data.equipment, {
                "  └ More...",
                (#sortedAmmo - 3) .. " more types",
                Color(170, 170, 220)
            })
        end
    end

    -- entities
    if SavedInfo.entities and type(SavedInfo.entities) == "table" and #SavedInfo.entities > 0 then
        local classes = {}
        for _, entity in ipairs(SavedInfo.entities) do
            classes[entity.class] = (classes[entity.class] or 0) + 1
        end

        local totalEntities = #SavedInfo.entities
        table.insert(data.entities, { "Total Entities", totalEntities, Color(255, 180, 180) })

        local sortedClasses = {}
        for class, count in pairs(classes) do
            table.insert(sortedClasses, { class = class, count = count })
        end
        table.sort(sortedClasses, function(a, b) return a.count > b.count end)

        for i = 1, math.min(3, #sortedClasses) do
            local entry = sortedClasses[i]
            local prettyName = string.match(entry.class, "[^_]+_(.+)") or entry.class
            prettyName = prettyName:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
                return first:upper() .. rest
            end)

            table.insert(data.entities, {
                "Entity " .. i,
                string.format("%s (%d)", prettyName, entry.count),
                Color(255 - i * 30, 220 - i * 20, 220 - i * 20)
            })
        end
    end

    -- NPCs
    if SavedInfo.npcs and type(SavedInfo.npcs) == "table" and #SavedInfo.npcs > 0 then
        local classes = {}
        for _, npc in ipairs(SavedInfo.npcs) do
            classes[npc.class] = (classes[npc.class] or 0) + 1
        end

        local totalNPCs = #SavedInfo.npcs
        table.insert(data.entities, { "Total NPCs", totalNPCs, Color(200, 255, 200) })

        local sortedClasses = {}
        for class, count in pairs(classes) do
            table.insert(sortedClasses, { class = class, count = count })
        end
        table.sort(sortedClasses, function(a, b) return a.count > b.count end)

        for i = 1, math.min(3, #sortedClasses) do
            local entry = sortedClasses[i]
            local prettyName = string.match(entry.class, "npc_(.+)") or entry.class
            prettyName = prettyName:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
                return first:upper() .. rest
            end)

            table.insert(data.entities, {
                "NPC " .. i,
                string.format("%s (%d)", prettyName, entry.count),
                Color(200 - i * 20, 255 - i * 30, 200 - i * 20)
            })
        end
    end

    -- vehicles (not tested)
    if SavedInfo.vehicles and type(SavedInfo.vehicles) == "table" and #SavedInfo.vehicles > 0 then
        local vehicleCount = #SavedInfo.vehicles
        table.insert(data.entities, { "Total Vehicles", vehicleCount, Color(200, 200, 255) })

        if vehicleCount <= 3 then
            for i, vehicle in ipairs(SavedInfo.vehicles) do
                local prettyName = string.match(vehicle, "(.+)") or vehicle
                prettyName = prettyName:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
                    return first:upper() .. rest
                end)

                table.insert(data.entities, {
                    "Vehicle " .. i,
                    prettyName,
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

            for i = 1, math.min(3, #sortedTypes) do
                local entry = sortedTypes[i]
                local prettyName = entry.type:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
                    return first:upper() .. rest
                end)

                table.insert(data.entities, {
                    "Vehicle Type " .. i,
                    string.format("%s (%d)", prettyName, entry.count),
                    Color(200 - i * 20, 200 - i * 20, 255 - i * 30)
                })
            end
        end
    end

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
    local maxDistance = (phantomInteractionMode and phantomInteractionTarget == steamID) and 500000 or 250000

    if distanceSqr > maxDistance then
        phantomInfoCache[steamID] = nil
        if phantomInteractionTarget == steamID then
            phantomInteractionMode = false
            phantomInteractionTarget = nil
            phantomInteractionAngle = nil
        end
        return
    end

    local now = CurTime()
    if not phantomInfoCache[steamID] or phantomInfoCache[steamID].expires < now then
        SavedInfo = (RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID])
        phantomInfoCache[steamID] = {
            data = buildPhantomInfoData(ply, SavedInfo, mapName),
            expires = now + CACHE_LIFETIME,
            activeCategory = phantomInfoCache[steamID] and phantomInfoCache[steamID].activeCategory or "basic"
        }
    end

    local infoData = phantomInfoCache[steamID].data
    local activeCategory = phantomInfoCache[steamID].activeCategory
    local pos = phantomPos + Vector(0, 0, 80)

    local ang
    if phantomInteractionMode and phantomInteractionTarget == steamID then
        ang = phantomInteractionAngle
    else
        local playerToPhantom = phantomPos - playerPos
        playerToPhantom:Normalize()
        ang = playerToPhantom:Angle()
        ang.y = ang.y - 90
        ang.p = 0
        ang.r = 90
    end

    local categoryContent = infoData[activeCategory]
    local optimalWidth = calculateOptimalPanelSize(categoryContent)

    local interactionBonus = (phantomInteractionMode and phantomInteractionTarget == steamID) and 1.5 or 1.0
    local hoverScale = phantomInfoCache[steamID].hoverScale or 1.0

    local theme = {
        background = Color(20, 20, 30, 220),
        header = Color(30, 30, 45, 255),
        border = Color(70, 130, 180, 255),
        text = Color(220, 220, 255),
        highlight = Color(100, 180, 255),
        selectedTab = Color(60, 100, 160, 255),
        tabHover = Color(50, 80, 120, 200),
        scrollbar = Color(120, 140, 160, 180),
        scrollbarHandle = Color(160, 180, 200, 200)
    }

    local scrollbarWidth = 5
    local scrollbarPadding = 5

    local scale = 0.1 * hoverScale * interactionBonus
    surface.SetFont("Trebuchet24")
    local infoCategoryHeight = 30
    local titleHeight = 40
    local lineHeight = 22
    local textPadding = 15
    local contentWidth = optimalWidth * panelSizeMultiplier
    local panelWidth = math.max(contentWidth, 800)
    local contentHeight = (#categoryContent * lineHeight)
    local maxDisplayHeight = math.min(contentHeight + 20, maxPanelHeight * scale)
    local needsScrolling = contentHeight > (maxPanelHeight * scale - 20)

    local availableContentWidth = panelWidth - (needsScrolling and (scrollbarWidth + scrollbarPadding * 2) or 0)

    maxScrollOffset = math.max(0, contentHeight - (maxPanelHeight * scale - 20))

    if not scrollPersistence[steamID] then
        scrollPersistence[steamID] = {}
    end

    if not scrollPersistence[steamID][activeCategory] then
        scrollPersistence[steamID][activeCategory] = 0
    end

    scrollOffset = scrollPersistence[steamID][activeCategory]

    if needsScrolling then
        scrollOffset = math.Clamp(scrollOffset, 0, maxScrollOffset)
        scrollPersistence[steamID][activeCategory] = scrollOffset
    else
        scrollOffset = 0
        scrollPersistence[steamID][activeCategory] = 0
    end

    local panelHeight = titleHeight + infoCategoryHeight + maxDisplayHeight

    local offsetX = -panelWidth / 2
    local offsetY = -panelHeight / 2

    cam.Start3D2D(pos, ang, scale)

    draw.RoundedBox(5, offsetX, offsetY, panelWidth, panelHeight, theme.background)

    for i = 0, 2 do
        local borderColor = Color(
            theme.border.r,
            theme.border.g,
            theme.border.b,
            255 - i * 40
        )
        surface.SetDrawColor(borderColor)
        surface.DrawOutlinedRect(offsetX - i, offsetY - i, panelWidth + i * 2, panelHeight + i * 2, 1)
    end

    local title = "Phantom of " .. ply:Nick()
    surface.SetDrawColor(theme.header)
    surface.DrawRect(offsetX, offsetY, panelWidth, titleHeight)

    draw.SimpleText(title, "Trebuchet24", offsetX + (panelWidth / 2) + 1, offsetY + (titleHeight / 2) + 1,
        Color(0, 0, 0, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(title, "Trebuchet24", offsetX + (panelWidth / 2), offsetY + (titleHeight / 2) + 3, theme.text,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)



    local minTabWidth = 0
    for _, categoryInfo in ipairs(PHANTOM_CATEGORIES) do
        local catName = categoryInfo[2]
        surface.SetFont("Trebuchet18")
        local textWidth = surface.GetTextSize(catName)
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

        local r = isActive and catColor.r / 2.5 or 40
        local g = isActive and catColor.g / 2.5 or 40
        local b = isActive and catColor.b / 2.5 or 40

        surface.SetDrawColor(r, g, b, 200)
        surface.DrawRect(tabX, tabY, tabWidth, infoCategoryHeight)

        if isActive then
            for j = 0, 2 do
                local alpha = 255 - j * 50
                surface.SetDrawColor(catColor.r, catColor.g, catColor.b, alpha)
                surface.DrawOutlinedRect(tabX + j, tabY + j, tabWidth - j * 2, infoCategoryHeight - j * 2, 1)
            end

            local triSize = 8
            draw.NoTexture()
            surface.SetDrawColor(catColor)
            surface.DrawPoly({
                { x = tabX + tabWidth / 2 - triSize, y = tabY + infoCategoryHeight },
                { x = tabX + tabWidth / 2 + triSize, y = tabY + infoCategoryHeight },
                { x = tabX + tabWidth / 2,           y = tabY + infoCategoryHeight + triSize }
            })
        end

        local textColor = isActive and Color(255, 255, 255) or Color(180, 180, 180)

        surface.SetFont("Trebuchet18")
        local textWidth, textHeight = surface.GetTextSize(catName)
        local textX = tabX + (tabWidth / 2)
        local textY = tabY + (infoCategoryHeight / 2)

        draw.SimpleText(catName, "Trebuchet18", textX, textY,
            textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        table.insert(tabScreenInfo, {
            catID = catID,
            worldX = textX,
            worldY = textY,
            worldW = tabWidth,
            worldH = infoCategoryHeight
        })
    end

    -- Scrollbar (if needed, currently goes beyond the frame)

    local contentY = tabY + infoCategoryHeight
    local contentAreaHeight = maxDisplayHeight

    render.SetStencilEnable(true)
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)

    draw.RoundedBox(0, offsetX, contentY, panelWidth, contentAreaHeight, Color(255, 255, 255, 1))
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    render.SetStencilPassOperation(STENCIL_KEEP)

    for i, lineData in ipairs(categoryContent) do
        local label, value, color = lineData[1], lineData[2], lineData[3]
        local yPos = contentY + (i - 1) * lineHeight - scrollOffset + 10

        if yPos + lineHeight >= contentY - lineHeight and yPos <= contentY + contentAreaHeight + lineHeight then
            local fadeInTime = i * 0.05
            local alpha = math.min((CurTime() - (phantomInfoCache[steamID].categoryChanged or 0) - fadeInTime) * 5, 1)
            if alpha < 0 then alpha = 0 end

            surface.SetFont("Trebuchet18")
            local labelText = label .. ":"
            draw.SimpleText(labelText, "Trebuchet18", offsetX + textPadding, yPos,
                Color(200, 200, 200, 200 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local valueText = tostring(value)
            local valueX = offsetX + textPadding + 120

            local maxValueWidth = panelWidth - (textPadding * 2) - 130 -
                (needsScrolling and (scrollbarWidth + scrollbarPadding * 2) or 0)

            local valueColor = color or Color(255, 255, 255)
            valueColor = Color(valueColor.r, valueColor.g, valueColor.b, valueColor.a * alpha)

            surface.SetFont("Trebuchet18")
            local textWidth = surface.GetTextSize(valueText)

            if textWidth > maxValueWidth then
                local low, high = 1, #valueText
                while low <= high do
                    local mid = math.floor((low + high) / 2)
                    local testText = string.sub(valueText, 1, mid) .. "..."
                    surface.SetFont("Trebuchet18")
                    local testWidth = surface.GetTextSize(testText)

                    if testWidth <= maxValueWidth then
                        low = mid + 1
                    else
                        high = mid - 1
                    end
                end

                if high >= 5 then
                    valueText = string.sub(valueText, 1, high) .. "..."
                else
                    valueText = string.sub(valueText, 1, math.floor(maxValueWidth / 10)) .. "..."
                end
            end

            draw.SimpleText(valueText, "Trebuchet18", valueX, yPos,
                valueColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    render.SetStencilEnable(false)

    if needsScrolling then
        local scrollbarX = offsetX + panelWidth - scrollbarWidth - scrollbarPadding
        local scrollbarY = contentY
        local scrollbarHeight = contentAreaHeight
        surface.SetDrawColor(40, 40, 50, 120)
        surface.DrawRect(scrollbarX, scrollbarY, scrollbarWidth, scrollbarHeight)

        local handleRatio = math.min(1, contentAreaHeight / contentHeight)
        local handleHeight = math.max(30, scrollbarHeight * handleRatio)
        local handleY = scrollbarY + (scrollOffset / maxScrollOffset) * (scrollbarHeight - handleHeight)
        surface.SetDrawColor(theme.scrollbarHandle)
        surface.DrawRect(scrollbarX, handleY, scrollbarWidth, handleHeight)

        phantomInfoCache[steamID].scrollbarInfo = {
            x = scrollbarX,
            y = scrollbarY,
            width = scrollbarWidth,
            height = scrollbarHeight,
            handleY = handleY,
            handleHeight = handleHeight,
            contentHeight = contentHeight,
            visibleHeight = contentAreaHeight
        }

        if scrollOffset > 0 then
            draw.SimpleText("▲", "Trebuchet18", scrollbarX + scrollbarWidth / 2, scrollbarY + 15,
                Color(200, 200, 200, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        if scrollOffset < maxScrollOffset then
            draw.SimpleText("▼", "Trebuchet18", scrollbarX + scrollbarWidth / 2, scrollbarY + scrollbarHeight - 15,
                Color(200, 200, 200, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    if phantomInteractionMode and phantomInteractionTarget == steamID then
        local helpText = "← → to navigate tabs  |  ↑↓ or use Scroll wheel to scroll |  E to Exit"
        draw.SimpleText(helpText, "Trebuchet18", offsetX + (panelWidth / 2), offsetY - 20,
            Color(255, 255, 255, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    else
        if distanceSqr < 10000 then
            local promptText = "Press [E] to interact"
            draw.SimpleText(promptText, "Trebuchet18", offsetX + (panelWidth / 2), offsetY - 20,
                Color(255, 255, 255, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end

    phantomInfoCache[steamID].panelInfo = {
        tabInfo = tabScreenInfo,
        activeTabIndex = nil,
        hasScrollbar = needsScrolling
    }

    for i, tabInfo in ipairs(tabScreenInfo) do
        if tabInfo.catID == activeCategory then
            phantomInfoCache[steamID].panelInfo.activeTabIndex = i
            break
        end
    end

    cam.End3D2D()
end

hook.Remove("GUIMousePressed", "PhantomPanelInteraction")

hook.Add("Think", "PhantomKeyboardNavigation", function()
    if not phantomInteractionMode or not phantomInteractionTarget then return end

    local cache = phantomInfoCache[phantomInteractionTarget]
    if not cache or not cache.panelInfo then return end

    local panelInfo = cache.panelInfo
    local activeIndex = panelInfo.activeTabIndex
    local activeCategory = cache.activeCategory

    if not activeIndex then return end

    if input.IsKeyDown(KEY_LEFT) and not cache.keyHeld then
        local newIndex = activeIndex - 1
        if newIndex < 1 then newIndex = #PHANTOM_CATEGORIES end

        local oldCategory = cache.activeCategory
        cache.activeCategory = PHANTOM_CATEGORIES[newIndex][1]
        cache.categoryChanged = CurTime()

        if oldCategory ~= cache.activeCategory then
            surface.PlaySound("ui/buttonrollover.wav")

            local newContent = cache.data[cache.activeCategory]
            local optimalWidth = calculateOptimalPanelSize(newContent)
        end

        cache.keyHeld = true
        timer.Simple(0.2, function() cache.keyHeld = false end)
    elseif input.IsKeyDown(KEY_RIGHT) and not cache.keyHeld then
        local newIndex = activeIndex + 1
        if newIndex > #PHANTOM_CATEGORIES then newIndex = 1 end

        local oldCategory = cache.activeCategory
        cache.activeCategory = PHANTOM_CATEGORIES[newIndex][1]
        cache.categoryChanged = CurTime()

        if oldCategory ~= cache.activeCategory then
            surface.PlaySound("ui/buttonrollover.wav")

            local newContent = cache.data[cache.activeCategory]
            local optimalWidth = calculateOptimalPanelSize(newContent)
        end

        cache.keyHeld = true
        timer.Simple(0.2, function() cache.keyHeld = false end)
    end

    if input.IsKeyDown(KEY_UP) then
        if scrollPersistence[phantomInteractionTarget] and activeCategory then
            local newScroll = math.max(0, (scrollPersistence[phantomInteractionTarget][activeCategory] or 0) - 5)
            scrollPersistence[phantomInteractionTarget][activeCategory] = newScroll
        end
    elseif input.IsKeyDown(KEY_DOWN) then
        if scrollPersistence[phantomInteractionTarget] and activeCategory then
            local newScroll = math.min(maxScrollOffset,
                (scrollPersistence[phantomInteractionTarget][activeCategory] or 0) + 5)
            scrollPersistence[phantomInteractionTarget][activeCategory] = newScroll
        end
    end
end)

hook.Add("StartCommand", "PhantomBlockMovement", function(ply, cmd)
    if ply ~= LocalPlayer() then return end

    if phantomInteractionMode and phantomInteractionTarget then
        cmd:ClearMovement()
        cmd:ClearButtons()

        if input.IsKeyDown(KEY_E) then
            cmd:SetButtons(IN_USE)
        end
    end
end)

hook.Add("PlayerBindPress", "PhantomBlockBindings", function(ply, bind, pressed)
    if phantomInteractionMode and phantomInteractionTarget then
        local cache = phantomInfoCache[phantomInteractionTarget]
        if cache and cache.activeCategory then
            local activeCategory = cache.activeCategory

            if bind == "invprev" and pressed then
                if scrollPersistence[phantomInteractionTarget] then
                    local newScroll = math.max(0,
                        (scrollPersistence[phantomInteractionTarget][activeCategory] or 0) - scrollSpeed)
                    scrollPersistence[phantomInteractionTarget][activeCategory] = newScroll
                end
                return true
            elseif bind == "invnext" and pressed then
                if scrollPersistence[phantomInteractionTarget] then
                    local newScroll = math.min(maxScrollOffset,
                        (scrollPersistence[phantomInteractionTarget][activeCategory] or 0) + scrollSpeed)
                    scrollPersistence[phantomInteractionTarget][activeCategory] = newScroll
                end
                return true
            end
        end

        if string.find(bind, "+use") then
            return false
        end

        return true
    end
end)

local originalViewData = nil
hook.Add("CalcView", "PhantomInteractionView", function(ply, pos, angles, fov)
    if phantomInteractionMode and phantomInteractionTarget then
        if not originalViewData then
            originalViewData = {
                pos = pos,
                angles = angles,
                fov = fov
            }
        end

        return {
            origin = originalViewData.pos,
            angles = originalViewData.angles,
            fov = originalViewData.fov,
            drawviewer = false
        }
    else
        originalViewData = nil
    end
end)

hook.Add("KeyPress", "PhantomInteractionToggle", function(ply, key)
    if not IsValid(ply) or not ply:IsPlayer() or ply ~= LocalPlayer() then return end
    if key ~= IN_USE then return end

    local playerPos = ply:GetPos()
    local mapName = game.GetMap()

    if phantomInteractionMode then
        phantomInteractionMode = false
        phantomInteractionTarget = nil
        phantomInteractionAngle = nil
        surface.PlaySound("ui/buttonclickrelease.wav")
        return
    end

    local closestPhantom = nil
    local closestDistance = 10000

    for steamID, data in pairs(RARELOAD.Phantom) do
        if IsValid(data.phantom) and IsValid(data.ply) then
            local distance = playerPos:DistToSqr(data.phantom:GetPos())
            if distance < closestDistance then
                closestPhantom = steamID
                closestDistance = distance
            end
        end
    end

    if closestPhantom and closestDistance < 90000 then
        phantomInteractionMode = true
        phantomInteractionTarget = closestPhantom

        if not scrollPersistence[closestPhantom] then
            scrollPersistence[closestPhantom] = {}
        end

        local eyeYaw = LocalPlayer():EyeAngles().yaw
        phantomInteractionAngle = Angle(0, eyeYaw - 90, 90)

        surface.PlaySound("ui/buttonclick.wav")

        local cache = phantomInfoCache[closestPhantom]
        if cache and cache.data and cache.activeCategory then
            local content = cache.data[cache.activeCategory]
            local optimalWidth = calculateOptimalPanelSize(content)
            panelSizeMultiplier = optimalWidth / 350
            cache.categoryChanged = CurTime()
        else
            panelSizeMultiplier = 1.0
        end
    end
end)
