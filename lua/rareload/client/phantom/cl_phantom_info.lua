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

-- Interaction state similar to entity viewer
local PhantomInteractionState = { active = false, phantom = nil, steamID = nil, lastAction = 0 }
local PhantomKeyStates = {}
local KEY_REPEAT_DELAY = 0.25
local CandidatePhantom, CandidateSteamID, CandidateYawDiff
local INTERACT_KEY = KEY_E
local REQUIRE_SHIFT_MOD = true
local ScrollDelta = 0
local LeaveTime = 0

local lpCache

local function InteractModifierDown()
    if not REQUIRE_SHIFT_MOD then return true end
    if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then return true end
    local ply = lpCache
    if (not IsValid(ply)) then ply = LocalPlayer() end
    if IsValid(ply) and (ply:KeyDown(IN_SPEED) or ply:KeyDown(IN_WALK)) then return true end
    return false
end

local function KeyPressed(code)
    if not input.IsKeyDown(code) then return false end
    local t = CurTime()
    local last = PhantomKeyStates[code] or 0
    if t - last > KEY_REPEAT_DELAY then
        PhantomKeyStates[code] = t
        return true
    end
    return false
end

local function EnterPhantomInteraction(phantom, steamID)
    PhantomInteractionState.active = true
    PhantomInteractionState.phantom = phantom
    PhantomInteractionState.steamID = steamID
    PhantomInteractionState.lastAction = CurTime()
    lpCache = lpCache or LocalPlayer()
    if IsValid(lpCache) then
        lpCache:DrawViewModel(false)
    end
end

local function LeavePhantomInteraction()
    PhantomInteractionState.active = false
    PhantomInteractionState.phantom = nil
    PhantomInteractionState.steamID = nil
    PhantomInteractionState.lockAng = nil
    LeaveTime = CurTime()
    if IsValid(lpCache) then
        lpCache:DrawViewModel(true)
    end
end

-- Phantom-specific constants
local PHANTOM_DRAW_DISTANCE_SQR = 600 * 100
local BASE_SCALE = 0.11
local MAX_VISIBLE_LINES = 30
local SCROLL_SPEED = 3
local PanelScroll = { phantoms = {} }

-- Cached calculations
local fontSizeCache = {}
local panelSizeCache = {}

-- Static theme (avoid re-allocating Color objects every frame)
local THEME = {
    background = Color(20, 20, 30, 220),
    header = Color(30, 30, 45, 255),
    border = Color(70, 130, 180, 255),
    text = Color(220, 220, 255),
    scrollbar = Color(40, 40, 50, 120),
    scrollbarHandle = Color(160, 180, 200, 200)
}

function CalculateOptimalPanelSize(categoryContent, numCategories)
    if type(categoryContent) ~= "table" then
        return 350
    end

    -- Use cached size if available
    local cacheKey = #categoryContent .. "_" .. (numCategories or 5)
    if panelSizeCache[cacheKey] then
        return panelSizeCache[cacheKey]
    end

    local baseWidth = 350
    local minWidth = 300
    local maxWidth = 680
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

        local totalWidth = fontSizeCache[label] + fontSizeCache[value] + 170
        contentWidth = math.max(contentWidth, totalWidth)
        if contentWidth > maxWidth then break end
    end

    -- Ensure minimum width for tabs
    local minTabWidth = 60
    local minWidthForTabs = (numCategories or 5) * minTabWidth
    contentWidth = math.max(contentWidth, minWidthForTabs)

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
    if SavedInfo.playermodel then
        table.insert(data.basic, { "Model", SavedInfo.playermodel, Color(200, 200, 200) })
    end
    table.insert(data.basic, { "Map", mapName, Color(180, 180, 200) })

    -- Position Information (simplified for lower LOD)
    if lodLevel <= 2 then
        if SavedInfo.pos then
            table.insert(data.position,
                { "Position", string.format("%.1f, %.1f, %.1f", SavedInfo.pos.x, SavedInfo.pos.y, SavedInfo.pos.z), Color(
                    255, 255, 255) })
        end
        if SavedInfo.ang then
            table.insert(data.position,
                { "Direction", string.format("%.1f°, %.1f°, %.1f°", SavedInfo.ang.p, SavedInfo.ang.y, SavedInfo.ang.r),
                    Color(220, 220, 220) })
        end
    else
        if SavedInfo.pos then
            table.insert(data.position,
                { "Position", "(" ..
                math.floor(SavedInfo.pos.x) ..
                ", " .. math.floor(SavedInfo.pos.y) .. ", " .. math.floor(SavedInfo.pos.z) .. ")", Color(255, 255, 255) })
        end
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

    -- Check if this phantom is too far away
    if distanceSqr > PHANTOM_DRAW_DISTANCE_SQR then return end

    local now = CurTime()

    -- Build or get cached phantom info data
    if not PhantomInfoCache[steamID] or PhantomInfoCache[steamID].expires < now then
        local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
        local preservedCategory = PhantomInfoCache[steamID] and PhantomInfoCache[steamID].activeCategory or "basic"
        PhantomInfoCache[steamID] = {
            data = BuildPhantomInfoData(ply, savedInfo, mapName, 1),
            expires = now + CACHE_LIFETIME,
            activeCategory = preservedCategory
        }
    end

    local cache = PhantomInfoCache[steamID]
    if not cache then return end

    local saved = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
    if not saved then return end

    -- Draw similar to entity viewer system
    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return end

    local eyePos = lpCache:EyePos()
    local pos = phantom:GetPos()

    local categories = PHANTOM_CATEGORIES
    local activeCat = cache.activeCategory or "basic"
    local lines = cache.data[activeCat] or {}

    local lineHeight = 18
    local titleHeight = 36
    local tabHeight = 22

    -- Calculate panel width based on content and number of tabs
    local width = CalculateOptimalPanelSize(lines, #categories)

    local panelID = steamID
    local scrollTable = PanelScroll.phantoms
    local scrollKey = panelID .. "_" .. activeCat
    local maxScrollLines = math.max(0, #lines - MAX_VISIBLE_LINES)
    local currentScroll = math.min(scrollTable[scrollKey] or 0, maxScrollLines)
    scrollTable[scrollKey] = currentScroll

    -- Calculate dynamic height based on actual content in active tab
    local actualVisibleLines = math.min(#lines, MAX_VISIBLE_LINES)
    local contentHeight = actualVisibleLines * lineHeight + 12
    local panelHeight = titleHeight + tabHeight + contentHeight + 18

    -- Position the panel above the phantom
    local dir = (pos - eyePos)
    dir:Normalize()
    local ang = dir:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90

    local scale = BASE_SCALE * math.Clamp(1 - (math.sqrt(distanceSqr) / 4000), 0.4, 1.2)

    -- Dynamic positioning: Calculate phantom head height and position panel above it
    local phantomMins, phantomMaxs = phantom:OBBMins(), phantom:OBBMaxs()
    local phantomHeight = phantomMaxs.z - phantomMins.z
    local headOffset = math.max(phantomHeight + 10, 80) -- At least 80 units above, or phantom height + 10

    -- Calculate the panel height in world units and position it so the bottom is above the phantom head
    local panelHeightWorldUnits = panelHeight * scale
    local panelBottomZ = pos.z + headOffset
    local panelCenterZ = panelBottomZ + (panelHeightWorldUnits / 2)

    local drawPos = Vector(pos.x, pos.y, panelCenterZ)
    local offsetX = -width / 2
    local offsetY = -panelHeight / 2

    -- Check for candidate interaction (aiming at phantom)
    local aimAng = lpCache:EyeAngles()
    local toPhantomAng = (pos - lpCache:EyePos()):Angle()
    local yawDiff = math.abs(math.AngleDifference(aimAng.y, toPhantomAng.y))
    local isFocused = PhantomInteractionState.active and PhantomInteractionState.steamID == steamID
    local isCandidate = false

    if not PhantomInteractionState.active and distanceSqr < 40000 and yawDiff < 10 then
        if (not CandidatePhantom) or (distanceSqr < lpCache:GetPos():DistToSqr(CandidatePhantom:GetPos())) then
            CandidatePhantom = phantom
            CandidateSteamID = steamID
            CandidateYawDiff = yawDiff
            isCandidate = true
        end
    end

    cam.Start3D2D(drawPos, ang, scale)

    -- Recalculate offsets in case width was adjusted for tabs
    offsetX = -width / 2
    offsetY = -panelHeight / 2

    -- Draw background and border
    surface.SetDrawColor(0, 0, 0, 130)
    surface.DrawRect(offsetX + 4, offsetY + 4, width, panelHeight)
    draw.RoundedBox(10, offsetX, offsetY, width, panelHeight, Color(15, 18, 26, 240))
    draw.RoundedBox(10, offsetX + 2, offsetY + 2, width - 4, panelHeight - 4, Color(26, 30, 40, 245))

    -- Draw border
    for i = 0, 1 do
        surface.SetDrawColor(THEME.border.r, THEME.border.g, THEME.border.b, 200 - i * 40)
        surface.DrawOutlinedRect(offsetX + i, offsetY + i, width - i * 2, panelHeight - i * 2, 1)
    end

    -- Draw header
    surface.SetDrawColor(THEME.header.r, THEME.header.g, THEME.header.b, 245)
    surface.DrawRect(offsetX, offsetY, width, titleHeight)
    local title = "Phantom: " .. ply:Nick()
    draw.SimpleText(title, "Trebuchet24", offsetX + 12, offsetY + titleHeight / 2, Color(240, 240, 255), TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)

    -- Draw tabs
    local tabY = offsetY + titleHeight
    local tabWidth = width / #categories

    -- Ensure minimum tab width for readability
    local minTabWidth = 60
    if tabWidth < minTabWidth then
        tabWidth = minTabWidth
        width = math.max(width, #categories * minTabWidth)
        offsetX = -width / 2 -- Recalculate offset with new width
    end

    for i, cat in ipairs(categories) do
        local catID, catName, catColor = cat[1], cat[2], cat[3]
        local tabX = offsetX + (i - 1) * tabWidth
        local isActive = (catID == activeCat)

        if isActive then
            surface.SetDrawColor(catColor.r / 3, catColor.g / 3, catColor.b / 3, 200)
            surface.DrawRect(tabX, tabY, tabWidth, tabHeight)
            surface.SetDrawColor(catColor.r, catColor.g, catColor.b, 255)
            surface.DrawOutlinedRect(tabX, tabY, tabWidth, tabHeight, 2)
        else
            surface.SetDrawColor(40, 40, 50, 180)
            surface.DrawRect(tabX, tabY, tabWidth, tabHeight)
        end

        local textColor = isActive and Color(255, 255, 255) or Color(180, 180, 180)

        -- Truncate tab name if it's too long for the tab width
        local displayName = catName
        surface.SetFont("Trebuchet18")
        local textWidth = surface.GetTextSize(displayName)
        if textWidth > tabWidth - 8 then
            -- Try to abbreviate long names
            if catName == "Basic Information" then
                displayName = "Basic"
            elseif catName == "Position and Movement" then
                displayName = "Position"
            elseif catName == "Saved Entities and NPCs" then
                displayName = "Entities"
            elseif string.len(catName) > 8 then
                displayName = string.sub(catName, 1, 6) .. ".."
            end
        end

        draw.SimpleText(displayName, "Trebuchet18", tabX + tabWidth / 2, tabY + tabHeight / 2, textColor,
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    -- Draw content
    local startY = tabY + tabHeight + 6
    surface.SetFont("Trebuchet18")
    local visibleLines = math.min(#lines - currentScroll, actualVisibleLines)
    for i = 1, visibleLines do
        local lineIndex = currentScroll + i
        if lineIndex > #lines then break end

        local l = lines[lineIndex]
        local y = startY + (i - 1) * lineHeight

        draw.SimpleText(l[1] .. ":", "Trebuchet18", offsetX + 12, y, Color(200, 200, 200), TEXT_ALIGN_LEFT,
            TEXT_ALIGN_TOP)
        draw.SimpleText(l[2], "Trebuchet18", offsetX + 180, y, l[3] or THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    -- Draw scrollbar if needed
    if maxScrollLines > 0 then
        local barX = offsetX + width - 12
        local barY = startY
        local barW = 8
        local barH = contentHeight - 12
        surface.SetDrawColor(60, 60, 70, 160)
        surface.DrawRect(barX, barY, barW, barH)

        local handleH = math.max(20, barH * (actualVisibleLines / #lines))
        local handleY = barY + (currentScroll / maxScrollLines) * (barH - handleH)
        surface.SetDrawColor(90, 150, 230, 220)
        surface.DrawRect(barX, handleY, barW, handleH)
    end

    -- Draw interaction prompts
    if isFocused then
        draw.SimpleText("Left/Right Tabs | Up/Down/MWheel Scroll | Shift+E Exit", "Trebuchet18", offsetX + width / 2,
            offsetY - 12, Color(160, 210, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    elseif isCandidate then
        draw.SimpleText("Shift + E to Inspect", "Trebuchet18", offsetX + width / 2, offsetY - 6, Color(160, 210, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    cam.End3D2D()
end

function DrawAllPhantomPanels()
    if not (RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled) then return end

    CandidatePhantom, CandidateSteamID, CandidateYawDiff = nil, nil, nil
    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return end

    local playerPos = lpCache:GetPos()
    local mapName = game.GetMap()
    local drawnCount = 0

    -- Draw all phantom panels
    if RARELOAD.Phantom then
        for steamID, data in pairs(RARELOAD.Phantom) do
            if IsValid(data.phantom) and drawnCount < 10 then -- Limit draws per frame
                local success, err = pcall(DrawPhantomInfo, data, playerPos, mapName)
                if not success then
                    print("[RARELOAD] Error drawing phantom info for " .. steamID .. ": " .. tostring(err))
                end
                drawnCount = drawnCount + 1
            end
        end
    end

    -- Handle interaction logic
    local ct = CurTime()
    if PhantomInteractionState.active then
        local phantom = PhantomInteractionState.phantom
        if (not IsValid(phantom)) or lpCache:EyePos():DistToSqr(phantom:GetPos()) > PHANTOM_DRAW_DISTANCE_SQR * 1.1 then
            LeavePhantomInteraction()
        else
            if KeyPressed(INTERACT_KEY) and InteractModifierDown() then
                LeavePhantomInteraction()
                return
            end

            local cache = PhantomInfoCache[PhantomInteractionState.steamID]
            if not cache then
                LeavePhantomInteraction()
                return
            end

            if cache and cache.activeCategory then
                local categoryList = PHANTOM_CATEGORIES

                -- Check for tab navigation - store direction first to avoid double consumption
                local tabDirection = 0
                if KeyPressed(KEY_RIGHT) then
                    tabDirection = 1
                elseif KeyPressed(KEY_LEFT) then
                    tabDirection = -1
                end

                if tabDirection ~= 0 then
                    local currentIndex = 1
                    for i, cat in ipairs(categoryList) do
                        if cat[1] == cache.activeCategory then
                            currentIndex = i
                            break
                        end
                    end
                    local newIndex = currentIndex + tabDirection
                    if newIndex > #categoryList then newIndex = 1 end
                    if newIndex < 1 then newIndex = #categoryList end
                    cache.activeCategory = categoryList[newIndex][1]
                    surface.PlaySound("ui/buttonrollover.wav")
                end

                -- Handle scrolling
                local panelID = PhantomInteractionState.steamID
                local scrollTable = PanelScroll.phantoms
                local scrollKey = panelID .. "_" .. cache.activeCategory
                local lines = cache.data[cache.activeCategory] or {}
                local maxScrollLines = math.max(0, #lines - MAX_VISIBLE_LINES)

                if KeyPressed(KEY_UP) and maxScrollLines > 0 then
                    local newScroll = math.max(0, (scrollTable[scrollKey] or 0) - SCROLL_SPEED)
                    scrollTable[scrollKey] = newScroll
                elseif KeyPressed(KEY_DOWN) and maxScrollLines > 0 then
                    local newScroll = math.min(maxScrollLines, (scrollTable[scrollKey] or 0) + SCROLL_SPEED)
                    scrollTable[scrollKey] = newScroll
                end
            end
        end
    else
        -- Check for new interaction candidate
        if CandidatePhantom and KeyPressed(INTERACT_KEY) and InteractModifierDown() then
            EnterPhantomInteraction(CandidatePhantom, CandidateSteamID)
            surface.PlaySound("ui/buttonclick.wav")
        end
    end
end

-- Hook to handle CreateMove for camera lock during interaction
hook.Add("CreateMove", "RARELOAD_PhantomPanels_CamLock", function(cmd)
    if PhantomInteractionState.active or CurTime() - LeaveTime < 0.5 then
        cmd:RemoveKey(IN_USE)
    end
    if not PhantomInteractionState.active then return end

    local phantom = PhantomInteractionState.phantom
    if not IsValid(phantom) then return end

    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return end

    local ang = PhantomInteractionState.lockAng
    if not ang then
        ang = lpCache:EyeAngles()
        PhantomInteractionState.lockAng = ang
    end
    cmd:SetViewAngles(ang)
end)

-- Hook to handle scrolling during interaction
hook.Add("PlayerBindPress", "RARELOAD_PhantomInteractScroll", function(ply, bind, pressed)
    if not PhantomInteractionState.active or not pressed then return end

    local cache = PhantomInfoCache[PhantomInteractionState.steamID]
    if cache and cache.activeCategory then
        local panelID = PhantomInteractionState.steamID
        local scrollTable = PanelScroll.phantoms
        local scrollKey = panelID .. "_" .. cache.activeCategory
        local lines = cache.data[cache.activeCategory] or {}
        local maxScrollLines = math.max(0, #lines - MAX_VISIBLE_LINES)

        if bind == "invprev" and maxScrollLines > 0 then
            local newScroll = math.max(0, (scrollTable[scrollKey] or 0) - SCROLL_SPEED)
            scrollTable[scrollKey] = newScroll
            return true
        elseif bind == "invnext" and maxScrollLines > 0 then
            local newScroll = math.min(maxScrollLines, (scrollTable[scrollKey] or 0) + SCROLL_SPEED)
            scrollTable[scrollKey] = newScroll
            return true
        end
    end

    if string.find(bind, "+use") then
        return false
    end

    return true
end)
