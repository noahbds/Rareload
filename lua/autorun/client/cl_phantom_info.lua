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
local resizeAnimationStart = 0
local resizeAnimationTarget = 1.0
local resizeAnimationDuration = 0.3
local autoResizeTimer = 0


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

local function animatePanelResize(targetSize)
    resizeAnimationStart = CurTime()
    resizeAnimationTarget = targetSize
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
    return string.format("%.1f, %.1f, %.1f", vec.x, vec.y, vec.z)
end

local function AngleToString(ang)
    if not ang or not ang.p or not ang.y or not ang.r then
        return "N/A"
    end
    return string.format("%.1f, %.1f, %.1f", ang.p, ang.y, ang.r)
end

local function buildPhantomInfoData(ply, SavedInfo, mapName)
    local data = {
        basic = {},
        position = {},
        equipment = {},
        entities = {},
        stats = {}
    }

    if SavedInfo then
        table.insert(data.basic, { "Player", ply:Nick(), Color(255, 255, 255) })
        table.insert(data.basic, { "SteamID", ply:SteamID(), Color(200, 200, 200) })
        table.insert(data.basic, { "Model", ply:GetModel(), Color(200, 200, 200) })

        table.insert(data.position, { "Position", VectorToString(SavedInfo.pos), Color(255, 255, 255) })
        table.insert(data.position,
            { "Direction", SavedInfo.ang and AngleToString(SavedInfo.ang) or "N/A", Color(220, 220, 220) })
        table.insert(data.position,
            { "Movement Type", moveTypeNames[SavedInfo.moveType] or "Unknown", Color(220, 220, 220) })

        if SavedInfo.activeWeapon then
            table.insert(data.equipment, { "Active Weapon", SavedInfo.activeWeapon, Color(255, 200, 200) })
        end

        if SavedInfo.inventory and type(SavedInfo.inventory) == "table" and next(SavedInfo.inventory) then
            local items = SavedInfo.inventory
            if #items > 8 then
                local categories = {}
                for _, item in ipairs(items) do
                    local itemType = string.match(item, "^([%w_]+)") or "misc"
                    categories[itemType] = (categories[itemType] or 0) + 1
                end

                local summary = {}
                for category, count in pairs(categories) do
                    table.insert(summary, category .. " (" .. count .. ")")
                end
                table.insert(data.equipment, { "Inventory", table.concat(summary, ", "), Color(200, 255, 200) })
            else
                table.insert(data.equipment, { "Inventory", table.concat(items, ", "), Color(200, 255, 200) })
            end
        end

        if SavedInfo.ammo and type(SavedInfo.ammo) == "table" and next(SavedInfo.ammo) then
            local ammo = SavedInfo.ammo
            if #ammo > 8 then
                local totalCount = #ammo
                local sample = {}
                for i = 1, math.min(5, #ammo) do table.insert(sample, ammo[i]) end
                table.insert(data.equipment, { "Ammo", table.concat(sample, ", ") ..
                string.format(" (+%d types)", totalCount - #sample), Color(200, 200, 255) })
            else
                table.insert(data.equipment, { "Ammo", table.concat(ammo, ", "), Color(200, 200, 255) })
            end
        end

        if SavedInfo.entities and type(SavedInfo.entities) == "table" and next(SavedInfo.entities) then
            local entityCount = #SavedInfo.entities

            if entityCount > 10 then
                local classes = {}
                for _, entity in ipairs(SavedInfo.entities) do
                    classes[entity.class] = (classes[entity.class] or 0) + 1
                end

                local topClasses = {}
                for class, count in pairs(classes) do
                    table.insert(topClasses, { class = class, count = count })
                end
                table.sort(topClasses, function(a, b) return a.count > b.count end)

                local displayCount = math.min(5, #topClasses)
                local summary = {}
                for i = 1, displayCount do
                    table.insert(summary, topClasses[i].class .. " (" .. topClasses[i].count .. ")")
                end
                table.insert(data.entities, {
                    "Entités par type",
                    table.concat(summary, ", ") ..
                    (#topClasses > displayCount and string.format(" (+%d autres types)", #topClasses - displayCount) or ""),
                    Color(255, 220, 220)
                })
                table.insert(data.entities, { "Total", entityCount, Color(255, 180, 180) })
            else
                local entityClasses = table.map(SavedInfo.entities, function(entity) return entity.class end)
                table.insert(data.entities, { "Entities", table.concat(entityClasses, ", "), Color(255, 220, 220) })
                table.insert(data.entities, { "Total", entityCount, Color(255, 180, 180) })
            end
        end

        if SavedInfo.npcs and type(SavedInfo.npcs) == "table" and next(SavedInfo.npcs) then
            local npcCount = #SavedInfo.npcs

            if npcCount > 10 then
                local classes = {}
                for _, npc in ipairs(SavedInfo.npcs) do
                    classes[npc.class] = (classes[npc.class] or 0) + 1
                end

                local topClasses = {}
                for class, count in pairs(classes) do
                    table.insert(topClasses, { class = class, count = count })
                end
                table.sort(topClasses, function(a, b) return a.count > b.count end)

                local displayCount = math.min(5, #topClasses)
                local summary = {}
                for i = 1, displayCount do
                    table.insert(summary, topClasses[i].class .. " (" .. topClasses[i].count .. ")")
                end

                table.insert(data.entities, {
                    "NPCs par type",
                    table.concat(summary, ", ") ..
                    (#topClasses > displayCount and string.format(" (+%d autres types)", #topClasses - displayCount) or ""),
                    Color(220, 255, 220)
                })
                table.insert(data.entities, { "Total NPCs", npcCount, Color(200, 255, 200) })
            else
                local npcClasses = table.map(SavedInfo.npcs, function(npc) return npc.class end)
                table.insert(data.entities, { "NPCs", table.concat(npcClasses, ", "), Color(220, 255, 220) })
                table.insert(data.entities, { "Total NPCs", npcCount, Color(200, 255, 200) })
            end
        end

        if SavedInfo.vehicles and type(SavedInfo.vehicles) == "table" and next(SavedInfo.vehicles) then
            local vehicleCount = #SavedInfo.vehicles

            if vehicleCount > 5 then
                local vehicleTypes = {}
                for _, vehicle in ipairs(SavedInfo.vehicles) do
                    vehicleTypes[vehicle] = (vehicleTypes[vehicle] or 0) + 1
                end

                local summary = {}
                for type, count in pairs(vehicleTypes) do
                    if count > 1 then
                        table.insert(summary, type .. " (" .. count .. ")")
                    else
                        table.insert(summary, type)
                    end
                end

                if #summary > 3 then
                    table.insert(data.entities, {
                        "Véhicules",
                        string.format("%d véhicules de %d types", vehicleCount, #summary),
                        Color(220, 220, 255)
                    })
                else
                    table.insert(data.entities, {
                        "Véhicules",
                        table.concat(summary, ", "),
                        Color(220, 220, 255)
                    })
                end
            else
                table.insert(data.entities, { "Vehicles", table.concat(SavedInfo.vehicles, ", "), Color(220, 220, 255) })
            end
            table.insert(data.entities, { "Total véhicules", vehicleCount, Color(200, 200, 255) })
        end

        table.insert(data.stats, { "Health", SavedInfo.health or "N/A", Color(255, 180, 180) })
        table.insert(data.stats, { "Armor", SavedInfo.armor or "N/A", Color(180, 180, 255) })
    else
        table.insert(data.basic, { "Player", ply:Nick(), Color(255, 255, 255) })
        table.insert(data.basic, { "Status", "No saved data", Color(255, 100, 100) })
    end

    return data
end

-- Update the DrawPhantomInfo function to use the fixed angle
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
        -- Use the stored fixed angle instead of current eye angles
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

    if autoResizeTimer < CurTime() and phantomInfoCache[steamID].lastCategory ~= activeCategory then
        animatePanelResize(optimalWidth / 350)
        phantomInfoCache[steamID].lastCategory = activeCategory
        autoResizeTimer = CurTime() + 0.5
    end

    if resizeAnimationStart > 0 then
        local progress = math.Clamp((CurTime() - resizeAnimationStart) / resizeAnimationDuration, 0, 1)
        progress = 1 - (1 - progress) * (1 - progress)

        panelSizeMultiplier = Lerp(progress, panelSizeMultiplier, resizeAnimationTarget)

        if progress >= 1 then
            resizeAnimationStart = 0
        end
    end

    local interactionBonus = (phantomInteractionMode and phantomInteractionTarget == steamID) and 1.5 or 1.0
    local hoverScale = phantomInfoCache[steamID].hoverScale or 1.0

    local theme = {
        background = Color(20, 20, 30, 220),
        header = Color(30, 30, 45, 255),
        border = Color(70, 130, 180, 255),
        text = Color(220, 220, 255),
        highlight = Color(100, 180, 255),
        selectedTab = Color(60, 100, 160, 255),
        tabHover = Color(50, 80, 120, 200)
    }

    local scale = 0.1 * hoverScale * interactionBonus
    surface.SetFont("Trebuchet24")
    local infoCategoryHeight = 30
    local titleHeight = 35
    local lineHeight = 22
    local textPadding = 15

    local contentWidth = optimalWidth * panelSizeMultiplier
    local panelWidth = math.min(contentWidth, 600)

    local panelHeight = titleHeight + infoCategoryHeight
    panelHeight = panelHeight + (#categoryContent * lineHeight) + 20

    local offsetX = -panelWidth / 2
    local offsetY = -panelHeight / 2

    cam.Start3D2D(pos, ang, scale)

    draw.RoundedBox(8, offsetX, offsetY, panelWidth, panelHeight, theme.background)

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

    local title = "Phantom de " .. ply:Nick()
    surface.SetDrawColor(theme.header)
    surface.DrawRect(offsetX, offsetY, panelWidth, titleHeight)

    draw.SimpleText(title, "Trebuchet24", offsetX + (panelWidth / 2) + 1, offsetY + (titleHeight / 2) + 1,
        Color(0, 0, 0, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(title, "Trebuchet24", offsetX + (panelWidth / 2), offsetY + (titleHeight / 2),
        theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    if phantomInteractionMode and phantomInteractionTarget == steamID then
        local interactText = "Mode Interaction [E pour quitter]"
        draw.SimpleText(interactText, "Trebuchet18", offsetX + (panelWidth / 2), offsetY + titleHeight - 2,
            Color(255, 255, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end

    local tabWidth = panelWidth / #PHANTOM_CATEGORIES
    local tabY = offsetY + titleHeight

    local tabScreenInfo = {}

    for i, categoryInfo in ipairs(PHANTOM_CATEGORIES) do
        local catID, catName, catColor = categoryInfo[1], categoryInfo[2], categoryInfo[3]
        local tabX = offsetX + (i - 1) * tabWidth
        local isActive = (catID == activeCategory)

        local tabHighlightAmount = isActive and 1 or 0

        local r = isActive and catColor.r / 2 or 40
        local g = isActive and catColor.g / 2 or 40
        local b = isActive and catColor.b / 2 or 40

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
        draw.SimpleText(catName, "Trebuchet18", tabX + (tabWidth / 2), tabY + (infoCategoryHeight / 2),
            textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        table.insert(tabScreenInfo, {
            catID = catID,
            worldX = tabX + tabWidth / 2,
            worldY = tabY + infoCategoryHeight / 2,
            worldW = tabWidth,
            worldH = infoCategoryHeight
        })
    end

    local contentY = tabY + infoCategoryHeight + 10
    for i, lineData in ipairs(categoryContent) do
        local label, value, color = lineData[1], lineData[2], lineData[3]

        local fadeInTime = i * 0.05
        local alpha = math.min((CurTime() - (phantomInfoCache[steamID].categoryChanged or 0) - fadeInTime) * 5, 1)
        if alpha < 0 then alpha = 0 end

        draw.SimpleText(label .. ":", "Trebuchet18", offsetX + textPadding, contentY + (i - 1) * lineHeight,
            Color(200, 200, 200, 200 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local valueText = tostring(value)
        if #valueText > 40 then
            valueText = string.sub(valueText, 1, 37) .. "..."
        end

        local valueColor = color or Color(255, 255, 255)
        valueColor = Color(valueColor.r, valueColor.g, valueColor.b, valueColor.a * alpha)

        draw.SimpleText(valueText, "Trebuchet18", offsetX + textPadding + 120, contentY + (i - 1) * lineHeight,
            valueColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    if phantomInteractionMode and phantomInteractionTarget == steamID then
        local helpText = "← → Navigation des onglets  |  +/- Redimensionner  |  E Quitter"
        draw.SimpleText(helpText, "Trebuchet18", offsetX + (panelWidth / 2), offsetY + panelHeight + 15,
            Color(200, 200, 255, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    else
        if distanceSqr < 90000 then
            local promptText = "Appuyez sur [E] pour interagir"
            draw.SimpleText(promptText, "Trebuchet18", offsetX + (panelWidth / 2), offsetY + panelHeight + 15,
                Color(255, 255, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end

    phantomInfoCache[steamID].panelInfo = {
        tabInfo = tabScreenInfo,
        activeTabIndex = nil
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
            animatePanelResize(optimalWidth / 350)
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
            animatePanelResize(optimalWidth / 350)
        end

        cache.keyHeld = true
        timer.Simple(0.2, function() cache.keyHeld = false end)
    end

    if (input.IsKeyDown(KEY_EQUAL) and input.IsKeyDown(KEY_LSHIFT)) or input.IsKeyDown(KEY_PAD_PLUS) then
        if not cache.resizeHeld then
            panelSizeMultiplier = math.min(panelSizeMultiplier + 0.1, 1.5)
            surface.PlaySound("ui/buttonclick.wav")
            cache.resizeHeld = true
            timer.Simple(0.1, function() cache.resizeHeld = false end)
        end
    elseif input.IsKeyDown(KEY_MINUS) or input.IsKeyDown(KEY_PAD_MINUS) then
        if not cache.resizeHeld then
            panelSizeMultiplier = math.max(panelSizeMultiplier - 0.1, 0.7)
            surface.PlaySound("ui/buttonclick.wav")
            cache.resizeHeld = true
            timer.Simple(0.1, function() cache.resizeHeld = false end)
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

-- Modify the KeyPress hook to capture the initial angle
hook.Add("KeyPress", "PhantomInteractionToggle", function(ply, key)
    if not IsValid(ply) or not ply:IsPlayer() or ply ~= LocalPlayer() then return end
    if key ~= IN_USE then return end

    local playerPos = ply:GetPos()
    local mapName = game.GetMap()

    if phantomInteractionMode then
        phantomInteractionMode = false
        phantomInteractionTarget = nil
        phantomInteractionAngle = nil -- Clear the stored angle
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

        -- Store a fixed angle for the interaction panel
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
