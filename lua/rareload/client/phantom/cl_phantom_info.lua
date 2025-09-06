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

local MAX_ITEMS_HIGH_LOD = 50
local MAX_ITEMS_MED_LOD = 20
local MAX_ITEMS_LOW_LOD = 10

local PhantomInteractionState = { active = false, phantom = nil, steamID = nil, lastAction = 0 }
local PhantomLookingAtPanelUntil = 0
local PhantomKeyStates = {}
local KEY_REPEAT_DELAY = 0.25
local CandidatePhantom, CandidateSteamID, CandidateYawDiff, CandidateDistSqr
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

local PHANTOM_DRAW_DISTANCE_SQR = SED.BASE_DRAW_DISTANCE * SED.BASE_DRAW_DISTANCE -- for consistency with SED
local BASE_SCALE = 0.11
local MAX_VISIBLE_LINES = 30
local SCROLL_SPEED = 3
local PanelScroll = { phantoms = {} }

local fontSizeCache = {}
local panelSizeCache = {}

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

    local cacheKey = #categoryContent .. "_" .. (numCategories or 5)
    if panelSizeCache[cacheKey] then
        return panelSizeCache[cacheKey]
    end

    local baseWidth = 350
    local minWidth = 300
    local maxWidth = 680
    local contentWidth = baseWidth

    surface.SetFont("Trebuchet18")
    for i = 1, math.min(#categoryContent, 10) do
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
    lodLevel = lodLevel or 1

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

    table.insert(data.basic, { "Player", ply:Nick(), Color(255, 255, 255) })
    table.insert(data.basic, { "SteamID", ply:SteamID(), Color(200, 200, 200) })
    if SavedInfo.playermodel then
        table.insert(data.basic, { "Model", SavedInfo.playermodel, Color(200, 200, 200) })
    end
    table.insert(data.basic, { "Map", mapName, Color(180, 180, 200) })

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
    local maxItems = lodLevel == 1 and MAX_ITEMS_HIGH_LOD or lodLevel == 2 and MAX_ITEMS_MED_LOD or MAX_ITEMS_LOW_LOD

    if SavedInfo.activeWeapon then
        local weaponName = SavedInfo.activeWeapon
        local prettyName = (string.match(weaponName, "weapon_(.+)") or weaponName):gsub("_", " "):gsub("(%a)([%w_']*)",
            function(first, rest) return first:upper() .. rest end)
        table.insert(data.equipment, { "Active Weapon", prettyName, Color(255, 200, 200) })
    end

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

    table.insert(data.stats, { "Health", math.floor(SavedInfo.health or 0), Color(255, 180, 180) })
    table.insert(data.stats, { "Armor", math.floor(SavedInfo.armor or 0), Color(180, 180, 255) })

    if lodLevel <= 2 and SavedInfo.npcs and #SavedInfo.npcs > 0 then
        local totalHealth = 0
        for i = 1, math.min(#SavedInfo.npcs, 50) do
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
    if distanceSqr > PHANTOM_DRAW_DISTANCE_SQR then return end

    local now = CurTime()

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

    local width = CalculateOptimalPanelSize(lines, #categories)

    local panelID = steamID
    local scrollTable = PanelScroll.phantoms
    local scrollKey = panelID .. "_" .. activeCat
    local maxScrollLines = math.max(0, #lines - MAX_VISIBLE_LINES)
    local currentScroll = math.min(scrollTable[scrollKey] or 0, maxScrollLines)
    scrollTable[scrollKey] = currentScroll

    local actualVisibleLines = math.min(#lines, MAX_VISIBLE_LINES)
    local contentHeight = actualVisibleLines * lineHeight + 12
    local panelHeight = titleHeight + tabHeight + contentHeight + 18

    local dir = (pos - eyePos)
    dir:Normalize()
    local ang = dir:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90

    local scale = BASE_SCALE * math.Clamp(1 - (math.sqrt(distanceSqr) / 4000), 0.4, 1.2)

    local phantomMins, phantomMaxs = phantom:OBBMins(), phantom:OBBMaxs()
    local phantomHeight = phantomMaxs.z - phantomMins.z
    local headOffset = math.max(phantomHeight + 10, 80)

    local panelHeightWorldUnits = panelHeight * scale
    local panelBottomZ = pos.z + headOffset
    local panelCenterZ = panelBottomZ + (panelHeightWorldUnits / 2)

    local drawPos = Vector(pos.x, pos.y, panelCenterZ)
    local offsetX = -width / 2
    local offsetY = -panelHeight / 2

    local aimAng = lpCache:EyeAngles()
    local toPhantomAng = (pos - lpCache:EyePos()):Angle()
    local yawDiff = math.abs(math.AngleDifference(aimAng.y, toPhantomAng.y))
    local isFocused = PhantomInteractionState.active and PhantomInteractionState.steamID == steamID
    local isCandidate = false

    cam.Start3D2D(drawPos, ang, scale)

    offsetX = -width / 2
    offsetY = -panelHeight / 2

    surface.SetDrawColor(0, 0, 0, 130)
    surface.DrawRect(offsetX + 4, offsetY + 4, width, panelHeight)
    draw.RoundedBox(10, offsetX, offsetY, width, panelHeight, Color(15, 18, 26, 240))
    draw.RoundedBox(10, offsetX + 2, offsetY + 2, width - 4, panelHeight - 4, Color(26, 30, 40, 245))

    for i = 0, 1 do
        surface.SetDrawColor(THEME.border.r, THEME.border.g, THEME.border.b, 200 - i * 40)
        surface.DrawOutlinedRect(offsetX + i, offsetY + i, width - i * 2, panelHeight - i * 2, 1)
    end

    surface.SetDrawColor(THEME.header.r, THEME.header.g, THEME.header.b, 245)
    surface.DrawRect(offsetX, offsetY, width, titleHeight)
    local title = "Phantom: " .. ply:Nick()
    draw.SimpleText(title, "Trebuchet24", offsetX + 12, offsetY + titleHeight / 2, Color(240, 240, 255), TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)

    local tabY = offsetY + titleHeight
    local tabWidth = width / #categories

    local minTabWidth = 60
    if tabWidth < minTabWidth then
        tabWidth = minTabWidth
        width = math.max(width, #categories * minTabWidth)
        offsetX = -width / 2
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

        local displayName = catName
        surface.SetFont("Trebuchet18")
        local textWidth = surface.GetTextSize(displayName)
        if textWidth > tabWidth - 8 then
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

    if isFocused then
        draw.SimpleText("Left/Right Tabs | Up/Down/MWheel Scroll | Shift+E Exit", "Trebuchet18", offsetX + width / 2,
            offsetY - 12, Color(160, 210, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    elseif isCandidate then
        draw.SimpleText("Shift + E to Inspect", "Trebuchet18", offsetX + width / 2, offsetY - 6, Color(160, 210, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    cam.End3D2D()

    -- After drawing, compute whether the player is aiming at the 3D2D panel rectangle
    local eyePos2 = lpCache:EyePos()
    local forward = lpCache:EyeAngles():Forward()
    local panelCenter = drawPos
    local panelNormal = (panelCenter - eyePos2):GetNormalized()
    local right = ang:Right()
    local up = ang:Up()

    local lookAtPanel = false
    local denom = forward:Dot(panelNormal)
    if math.abs(denom) > 1e-3 then
        local t = (panelCenter - eyePos2):Dot(panelNormal) / denom
        if t > 0 then
            local hitPos = eyePos2 + forward * t
            local rel = hitPos - panelCenter
            local x = rel:Dot(right)
            local y = rel:Dot(up)
            local halfW = (width * 0.5) * scale
            local halfH = (panelHeight * 0.5) * scale
            if math.abs(x) <= halfW and math.abs(y) <= halfH then
                lookAtPanel = true
            end
        end
    end

    if lookAtPanel then
        PhantomLookingAtPanelUntil = CurTime() + 0.03
    end

    if not isFocused and lookAtPanel then
        isCandidate = true
    end
end

function QueuePhantomPanelsForRendering()
    -- Render phantom panels whenever the depth renderer is available; no longer gated by debug mode
    if not (RARELOAD.DepthRenderer and RARELOAD.DepthRenderer.AddRenderItem) then return end

    CandidatePhantom, CandidateSteamID, CandidateYawDiff, CandidateDistSqr = nil, nil, nil, nil
    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return end

    local playerPos = lpCache:GetPos()
    local mapName = game.GetMap()
    local queuedCount = 0
    local aimAng = lpCache:EyeAngles()
    local yawThreshold = 10        -- degrees
    local distThresholdSqr = 40000 -- 200 units squared (same as DrawPhantomInfo)

    if RARELOAD.Phantom then
        for steamID, data in pairs(RARELOAD.Phantom) do
            if IsValid(data.phantom) and queuedCount < 10 then
                local phantomPos = data.phantom:GetPos()

                local renderFunction = function()
                    local success, err = pcall(DrawPhantomInfo, data, playerPos, mapName)
                    if not success then
                        print("[RARELOAD] Error drawing phantom info for " .. steamID .. ": " .. tostring(err))
                    end
                end

                RARELOAD.DepthRenderer.AddRenderItem(phantomPos, renderFunction, "phantom")
                queuedCount = queuedCount + 1

                -- Pick best candidate for interaction before input handling (was previously set during render)
                if not PhantomInteractionState.active then
                    local toPhantomAng = (phantomPos - lpCache:EyePos()):Angle()
                    local yawDiff = math.abs(math.AngleDifference(aimAng.y, toPhantomAng.y))
                    local distSqr = playerPos:DistToSqr(phantomPos)
                    if distSqr < distThresholdSqr and yawDiff < yawThreshold then
                        if (not IsValid(CandidatePhantom)) then
                            CandidatePhantom = data.phantom
                            CandidateSteamID = steamID
                            CandidateYawDiff = yawDiff
                            CandidateDistSqr = distSqr
                        else
                            -- Prefer the closer phantom when multiple match (with safety guards)
                            local currentBestDist = tonumber(CandidateDistSqr) or math.huge
                            if distSqr < currentBestDist or yawDiff < (CandidateYawDiff or 1e9) then
                                CandidatePhantom = data.phantom
                                CandidateSteamID = steamID
                                CandidateYawDiff = yawDiff
                                CandidateDistSqr = distSqr
                            end
                        end
                    end
                end
            end
        end
    end

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
                    if newIndex < 1 then newIndex = #categoryList end
                    if newIndex > #categoryList then newIndex = 1 end
                    cache.activeCategory = categoryList[newIndex][1]
                    PhantomInteractionState.lastAction = ct
                end

                if math.abs(ScrollDelta) > 0.1 then
                    local panelData = PanelScroll.phantoms[PhantomInteractionState.steamID]
                    if not panelData then
                        PanelScroll.phantoms[PhantomInteractionState.steamID] = { scroll = 0 }
                        panelData = PanelScroll.phantoms[PhantomInteractionState.steamID]
                    end

                    panelData.scroll = panelData.scroll + ScrollDelta
                    panelData.scroll = math.max(0, panelData.scroll)
                    ScrollDelta = ScrollDelta * 0.8
                    PhantomInteractionState.lastAction = ct
                end
            end
        end
    else
        if CandidatePhantom and CandidateSteamID then
            if KeyPressed(INTERACT_KEY) and InteractModifierDown() then
                -- Require the player to be aiming at the panel to enter interaction
                local function IsAimingAtPanel(phantom, steamID)
                    if not (IsValid(phantom) and steamID) then return false end
                    lpCache = lpCache or LocalPlayer()
                    if not IsValid(lpCache) then return false end

                    local ply = lpCache
                    local eyePos = ply:EyePos()
                    local pos = phantom:GetPos()

                    local dir = (pos - eyePos)
                    dir:Normalize()
                    local ang = dir:Angle()
                    ang.y = ang.y - 90
                    ang.p = 0
                    ang.r = 90

                    local mapName = game.GetMap()
                    local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
                    local categories = PHANTOM_CATEGORIES
                    local cache = PhantomInfoCache[steamID]
                    local activeCat = (cache and cache.activeCategory) or "basic"
                    local dataLines
                    if cache and cache.data then
                        dataLines = cache.data[activeCat] or {}
                    else
                        local plyEnt
                        for _, p in ipairs(player.GetAll()) do
                            if p:SteamID() == steamID then
                                plyEnt = p
                                break
                            end
                        end
                        if not IsValid(plyEnt) then return false end
                        dataLines = BuildPhantomInfoData(plyEnt, savedInfo, mapName, 1)[activeCat] or {}
                    end

                    local width = CalculateOptimalPanelSize(dataLines, #categories)
                    local lineHeight, titleHeight, tabHeight = 18, 36, 22
                    local actualVisibleLines = math.min(#dataLines, MAX_VISIBLE_LINES)
                    local contentHeight = actualVisibleLines * lineHeight + 12
                    local panelHeight = titleHeight + tabHeight + contentHeight + 18

                    local distanceSqr = eyePos:DistToSqr(pos)
                    local scale = BASE_SCALE * math.Clamp(1 - (math.sqrt(distanceSqr) / 4000), 0.4, 1.2)

                    local phantomMins, phantomMaxs = phantom:OBBMins(), phantom:OBBMaxs()
                    local phantomHeight = phantomMaxs.z - phantomMins.z
                    local headOffset = math.max(phantomHeight + 10, 80)
                    local panelHeightWorldUnits = panelHeight * scale
                    local panelBottomZ = pos.z + headOffset
                    local panelCenterZ = panelBottomZ + (panelHeightWorldUnits / 2)
                    local drawPos = Vector(pos.x, pos.y, panelCenterZ)

                    local panelCenter = drawPos
                    local forward = ply:EyeAngles():Forward()
                    local normal = (panelCenter - eyePos):GetNormalized()
                    local right = ang:Right()
                    local up = ang:Up()
                    local denom = forward:Dot(normal)
                    if math.abs(denom) <= 1e-3 then return false end
                    local t = (panelCenter - eyePos):Dot(normal) / denom
                    if t <= 0 then return false end
                    local hitPos = eyePos + forward * t
                    local rel = hitPos - panelCenter
                    local x = rel:Dot(right)
                    local y = rel:Dot(up)
                    local halfW = (width * 0.5) * scale
                    local halfH = (panelHeight * 0.5) * scale
                    return math.abs(x) <= halfW and math.abs(y) <= halfH
                end

                if IsAimingAtPanel(CandidatePhantom, CandidateSteamID) then
                    EnterPhantomInteraction(CandidatePhantom, CandidateSteamID)
                    return
                end
            end
        end
    end
end

function DrawAllPhantomPanels()
    -- Allow drawing phantom panels regardless of debug mode

    CandidatePhantom, CandidateSteamID, CandidateYawDiff = nil, nil, nil
    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return end

    local playerPos = lpCache:GetPos()
    local mapName = game.GetMap()
    local drawnCount = 0

    if RARELOAD.Phantom then
        for steamID, data in pairs(RARELOAD.Phantom) do
            if IsValid(data.phantom) and drawnCount < 10 then
                local success, err = pcall(DrawPhantomInfo, data, playerPos, mapName)
                if not success then
                    print("[RARELOAD] Error drawing phantom info for " .. steamID .. ": " .. tostring(err))
                end
                drawnCount = drawnCount + 1
            end
        end
    end

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
        if CandidatePhantom and KeyPressed(INTERACT_KEY) and InteractModifierDown() then
            EnterPhantomInteraction(CandidatePhantom, CandidateSteamID)
            surface.PlaySound("ui/buttonclick.wav")
        end
    end
end

hook.Add("CreateMove", "RARELOAD_PhantomPanels_CamLock", function(cmd)
    if PhantomInteractionState.active or CurTime() - LeaveTime < 0.5 then
        cmd:RemoveKey(IN_USE)
    elseif PhantomLookingAtPanelUntil and CurTime() <= PhantomLookingAtPanelUntil then
        -- Prevent +use when aiming at the phantom 3D2D panel
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

hook.Add("PlayerBindPress", "RARELOAD_PhantomInteractScroll", function(ply, bind, pressed)
    if not pressed then return end

    if not PhantomInteractionState.active then
        -- Don't block normal use outside interaction; allow SED to handle global interactions too
        return
    end

    -- Allow normal movement while interacting with the phantom panel
    -- (do not block these binds so the player can move around)
    if bind == "+forward" or bind == "+back" or bind == "+moveleft" or bind == "+moveright"
        or bind == "+jump" or bind == "+duck" or bind == "+walk" or bind == "+speed" then
        return false
    end

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

    -- While in interaction, block most inputs; explicitly block +use to avoid world interactions
    if string.find(bind, "+use") then
        return true
    end

    return true
end)
