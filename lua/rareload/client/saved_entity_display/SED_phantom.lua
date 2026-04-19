SED = SED or (RARELOAD and RARELOAD.SavedEntityDisplay) or {}
SED.Phantom = SED.Phantom or {}

local Phantom = SED.Phantom
if Phantom._initialized then
    return Phantom
end

local RS = SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_phantom.lua\n")
    return Phantom
end

local PB = SED and SED.PanelBuilder
if not PB then
    include("rareload/client/saved_entity_display/SED_panel_builder_utils.lua")
    PB = SED and SED.PanelBuilder
end

local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

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
    [11] = "MOVETYPE_CUSTOM"
}

local PHANTOM_CATEGORIES = {
    { "basic",     "Basic Information",       Color(70, 130, 180) },
    { "position",  "Position and Movement",   Color(60, 179, 113) },
    { "equipment", "Equipment",               Color(218, 165, 32) },
    { "entities",  "Saved Entities and NPCs", Color(178, 34, 34) },
    { "stats",     "Statistics",              Color(147, 112, 219) }
}

local CACHE_LIFETIME = 5
local MAX_VISIBLE_LINES = 8
local MAX_RENDERED_PHANTOMS = 10
local BASE_SCALE = 0.11
local KEY_REPEAT_DELAY = 0.25
local INTERACT_KEY = KEY_E
local REQUIRE_SHIFT_MOD = true

local PhantomInfoCache = SED.PhantomInfoCache or rawget(_G, "PhantomInfoCache") or {}
SED.PhantomInfoCache = PhantomInfoCache
local PhantomInteractionState = SED.InteractionState
local CandidatePhantom, CandidateSteamID, CandidateDistSqr
local PhantomLookingAtPanelUntil = 0
local LeaveTime = 0
local lpCache

local fontSizeCache = {}
local panelSizeCache = {}

local BG_COLOR = RS.BG_COLOR or Color(15, 18, 24, 250)
local BG_COLOR_DISTANT = RS.BG_COLOR_DISTANT or Color(15, 18, 24, 230)
local HEADER_COLOR = RS.HEADER_COLOR or Color(25, 30, 40, 255)
local WHITE = RS.WHITE or Color(255, 255, 255)
local LABEL_COLOR = RS.LABEL_COLOR or Color(200, 210, 225, 255)
local VALUE_COLOR = RS.VALUE_COLOR or Color(240, 245, 250)
local HINT_INTERACT = RS.HINT_INTERACT or Color(255, 235, 190)
local HINT_CONTROLS = RS.HINT_CONTROLS or Color(225, 225, 230)
local HINT_CANDIDATE = RS.HINT_CANDIDATE or Color(160, 210, 255)

local SURF_SetFont = RS.surface_SetFont
local SURF_GetTextSize = RS.surface_GetTextSize
local SURF_SetDrawColor = RS.surface_SetDrawColor
local DRAW_SimpleText = RS.draw_SimpleText
local DRAW_RoundedBox = RS.draw_RoundedBox
local cam_Start3D2D = RS.cam_Start3D2D
local cam_End3D2D = RS.cam_End3D2D
local clipTextToWidth = RS.clipTextToWidth
local safeTextColor = RS.safeTextColor

function Phantom.CalculateOptimalPanelSize(lines, numCategories)
    if type(lines) ~= "table" then
        return 350
    end

    local cacheKey = tostring(#lines) .. "_" .. tostring(numCategories or #PHANTOM_CATEGORIES)
    if panelSizeCache[cacheKey] then
        return panelSizeCache[cacheKey]
    end

    SURF_SetFont("Trebuchet18")
    local contentWidth = 360
    local minWidth = 340
    local maxWidth = 760

    for i = 1, math.min(#lines, 8) do
        local lineData = lines[i]
        local label = tostring(lineData and lineData[1] or "")
        local value = tostring(lineData and lineData[2] or "")

        local labelKey = "l:" .. label
        local valueKey = "v:" .. value

        if not fontSizeCache[labelKey] then
            fontSizeCache[labelKey] = (SURF_GetTextSize(label .. ":") or 0)
        end
        if not fontSizeCache[valueKey] then
            fontSizeCache[valueKey] = (SURF_GetTextSize(value) or 0)
        end

        contentWidth = math.max(contentWidth, fontSizeCache[labelKey] + fontSizeCache[valueKey] + 170)
        if contentWidth > maxWidth then
            break
        end
    end

    local minTabWidth = 60
    contentWidth = math.max(contentWidth, (numCategories or #PHANTOM_CATEGORIES) * minTabWidth)
    contentWidth = math.Clamp(contentWidth, minWidth, maxWidth)
    panelSizeCache[cacheKey] = contentWidth
    return contentWidth
end

function Phantom.BuildPhantomInfoData(ply, savedInfo, mapName, lodLevel)
    lodLevel = lodLevel or 1

    local data = {
        basic = {},
        position = {},
        equipment = {},
        entities = {},
        stats = {}
    }

    local name = IsValid(ply) and ply:Nick() or tostring(ply and ply.Nick and ply:Nick() or "Unknown")
    local steamID = IsValid(ply) and ply:SteamID() or tostring(ply and ply.SteamID and ply:SteamID() or "Unknown")

    PB.addLine(data.basic, "Player", name, Color(255, 255, 255))
    PB.addLine(data.basic, "SteamID", steamID, Color(200, 200, 200))
    PB.addLine(data.basic, "Map", mapName or game.GetMap(), Color(180, 180, 200))

    if not savedInfo then
        PB.addLine(data.basic, "Status", "No saved data", Color(255, 100, 100))
        return data
    end

    if savedInfo.playermodel then
        PB.addLine(data.basic, "Model", savedInfo.playermodel, Color(200, 200, 200))
    end

    if lodLevel <= 2 then
        local savedItems = {}
        if savedInfo.health then savedItems[#savedItems + 1] = "Health" end
        if savedInfo.armor then savedItems[#savedItems + 1] = "Armor" end
        if savedInfo.inventory and #savedInfo.inventory > 0 then savedItems[#savedItems + 1] = "Inventory" end
        if savedInfo.ammo then savedItems[#savedItems + 1] = "Ammo" end
        if savedInfo.playerStates then savedItems[#savedItems + 1] = "States" end
        if savedInfo.vehicles and #savedInfo.vehicles > 0 then savedItems[#savedItems + 1] = "Vehicles" end
        if savedInfo.vehicleState then savedItems[#savedItems + 1] = "VehicleState" end

        local entitySummary = SnapshotUtils and SnapshotUtils.GetSummary and
            SnapshotUtils.GetSummary(savedInfo.entities, { category = "entity" }) or {}
        local npcSummary = SnapshotUtils and SnapshotUtils.GetSummary and
            SnapshotUtils.GetSummary(savedInfo.npcs, { category = "npc" }) or {}
        if PB.countEntries(entitySummary) > 0 then savedItems[#savedItems + 1] = "Entities" end
        if PB.countEntries(npcSummary) > 0 then savedItems[#savedItems + 1] = "NPCs" end

        if #savedItems > 0 then
            PB.addLine(data.basic, "Saved Data", table.concat(savedItems, ", "), Color(150, 255, 150))
        end
    end

    if savedInfo.pos then
        if lodLevel <= 2 then
            PB.addLine(data.position, "Position",
                string.format("%.1f, %.1f, %.1f", savedInfo.pos.x, savedInfo.pos.y, savedInfo.pos.z),
                Color(255, 255, 255))
        else
            PB.addLine(data.position, "Position",
                string.format("(%d, %d, %d)", math.floor(savedInfo.pos.x), math.floor(savedInfo.pos.y),
                    math.floor(savedInfo.pos.z)), Color(255, 255, 255))
        end
    end

    if savedInfo.ang then
        PB.addLine(data.position, "Direction",
            string.format("%.1f, %.1f, %.1f", savedInfo.ang.p, savedInfo.ang.y, savedInfo.ang.r), Color(220, 220, 220))
    end

    if lodLevel <= 1 then
        PB.addLine(data.position, "Movement Type", moveTypeNames[savedInfo.moveType] or "Unknown", Color(220, 220, 220))
    end

    if savedInfo.activeWeapon then
        PB.addLine(data.equipment, "Active Weapon", PB.prettyClassName(savedInfo.activeWeapon), Color(255, 200, 200))
    end

    if savedInfo.inventory and type(savedInfo.inventory) == "table" and #savedInfo.inventory > 0 then
        local counts = {}
        for i = 1, #savedInfo.inventory do
            local item = tostring(savedInfo.inventory[i])
            counts[item] = (counts[item] or 0) + 1
        end

        local uniqueItems = {}
        for item, count in pairs(counts) do
            uniqueItems[#uniqueItems + 1] = { item = item, count = count }
        end

        table.sort(uniqueItems, function(a, b)
            if a.count == b.count then
                return a.item < b.item
            end
            return a.count > b.count
        end)

        PB.addLine(data.equipment, "Inventory", tostring(#savedInfo.inventory) .. " items total", Color(255, 220, 150))

        local limit = lodLevel == 1 and 20 or lodLevel == 2 and 10 or 5
        local visibleItems = math.min(#uniqueItems, limit)
        for i = 1, visibleItems do
            local itemData = uniqueItems[i]
            local itemLabel = PB.prettyClassName(itemData.item)
            local suffix = itemData.count > 1 and (" x" .. itemData.count) or ""
            PB.addLine(data.equipment, "  " .. itemLabel, suffix, Color(255, 210, 150), { noColon = true })
        end

        if #uniqueItems > visibleItems then
            PB.addLine(data.equipment, "  ...", "+" .. (#uniqueItems - visibleItems) .. " more", Color(150, 150, 150),
                { noColon = true })
        end
    end

    local function processGroupedDataLOD(group, config)
        if type(group) ~= "table" or #group == 0 then
            PB.addLine(data.entities, config.totalLabel, "0", config.totalColor)
            return
        end

        PB.addLine(data.entities, config.totalLabel, tostring(#group), config.totalColor)
        if lodLevel > 2 then
            return
        end

        local counts = {}
        local processCount = math.min(#group, lodLevel == 1 and 50 or 20)
        for i = 1, processCount do
            local entry = group[i]
            local class = (istable(entry) and (entry.class or entry.Class or entry[1])) or entry
            class = tostring(class or "unknown")
            counts[class] = (counts[class] or 0) + 1
        end

        local sorted = {}
        for class, count in pairs(counts) do
            sorted[#sorted + 1] = { class = class, count = count }
        end

        table.sort(sorted, function(a, b)
            if a.count == b.count then
                return a.class < b.class
            end
            return a.count > b.count
        end)

        local showCount = math.min(#sorted, lodLevel == 1 and 10 or 5)
        for i = 1, showCount do
            local entry = sorted[i]
            PB.addLine(data.entities, config.labelPrefix .. " " .. i,
                string.format("%s (%d)", PB.prettyClassName(entry.class), entry.count), config.entryColor)
        end

        if #sorted > showCount then
            PB.addLine(data.entities, "...", "+" .. (#sorted - showCount) .. " more types", Color(150, 150, 150))
        end
    end

    processGroupedDataLOD(
        (SnapshotUtils and SnapshotUtils.GetSummary and SnapshotUtils.GetSummary(savedInfo.entities, { category = "entity" })) or
        {}, {
            totalLabel = "Total Entities",
            totalColor = Color(255, 180, 180),
            labelPrefix = "Entity",
            entryColor = Color(255, 180, 180)
        })

    processGroupedDataLOD(
        (SnapshotUtils and SnapshotUtils.GetSummary and SnapshotUtils.GetSummary(savedInfo.npcs, { category = "npc" })) or
        {},
        {
            totalLabel = "Total NPCs",
            totalColor = Color(200, 255, 200),
            labelPrefix = "NPC",
            entryColor = Color(200, 255, 200)
        })

    PB.addLine(data.stats, "Health", math.floor(savedInfo.health or 0), Color(255, 180, 180))
    PB.addLine(data.stats, "Armor", math.floor(savedInfo.armor or 0), Color(180, 180, 255))

    if savedInfo.playerStates and type(savedInfo.playerStates) == "table" then
        local states = {}
        if savedInfo.playerStates.godmode then states[#states + 1] = "God" end
        if savedInfo.playerStates.notarget then states[#states + 1] = "NoTarget" end
        if savedInfo.playerStates.frozen then states[#states + 1] = "Frozen" end
        if savedInfo.playerStates.noclip then states[#states + 1] = "Noclip" end
        if #states > 0 then
            PB.addLine(data.stats, "Player States", table.concat(states, ", "), Color(255, 215, 0))
        end
    end

    if lodLevel <= 2 and savedInfo.ammo and type(savedInfo.ammo) == "table" then
        local totalAmmo = 0
        local ammoTypes = 0
        for _, ammoData in pairs(savedInfo.ammo) do
            if ammoData.primary and ammoData.primary > 0 then
                totalAmmo = totalAmmo + ammoData.primary
                ammoTypes = ammoTypes + 1
            end
            if ammoData.clip1 and ammoData.clip1 > 0 then
                totalAmmo = totalAmmo + ammoData.clip1
            end
        end

        if totalAmmo > 0 then
            PB.addLine(data.stats, "Total Ammo", totalAmmo .. " (" .. ammoTypes .. " types)", Color(255, 200, 100))
        end
    end

    if savedInfo.vehicles and type(savedInfo.vehicles) == "table" and #savedInfo.vehicles > 0 then
        PB.addLine(data.stats, "Saved Vehicles", #savedInfo.vehicles, Color(200, 200, 255))
    end

    if savedInfo.vehicleState and type(savedInfo.vehicleState) == "table" then
        PB.addLine(data.stats, "In Vehicle", savedInfo.vehicleState.class or "Unknown", Color(200, 200, 255))
    end

    return data
end

local function HasViewPhantomPermission()
    local lp = LocalPlayer()
    if not IsValid(lp) then return false end
    if RARELOAD and RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        return RARELOAD.Permissions.HasPermission(lp, "VIEW_PHANTOM")
    end
    return true
end

local function BuildRenderData(phantomData, playerPos, mapName)
    local phantom, ply = phantomData.phantom, phantomData.ply
    if not IsValid(phantom) then return nil end

    local steamID = phantomData.steamID or (IsValid(ply) and ply:SteamID())
    if not steamID or steamID == "" then return nil end

    local savedInfo = SED.GetPhantomSavedInfo(mapName, steamID)
    local displayName = IsValid(ply) and ply:Nick() or ("Player " .. steamID)
    local infoTarget = IsValid(ply) and ply or {
        Nick = function() return displayName end,
        SteamID = function() return steamID end
    }

    local phantomPos = phantom:GetPos()
    local distanceSqr = playerPos:DistToSqr(phantomPos)
    if distanceSqr > SED.GetPhantomDrawDistSqr() then return nil end

    local cache = SED.GetPhantomInfoCache(steamID, Phantom.BuildPhantomInfoData, infoTarget, savedInfo, mapName,
        CACHE_LIFETIME, "basic")
    if not cache or not cache.data then return nil end

    local activeCategory = cache.activeCategory or "basic"
    local lines = cache.data[activeCategory] or {}
    if #lines == 0 then
        for _, cat in ipairs(PHANTOM_CATEGORIES) do
            local catLines = cache.data[cat[1]]
            if catLines and #catLines > 0 then
                activeCategory = cat[1]
                cache.activeCategory = activeCategory
                lines = catLines
                break
            end
        end
    end

    local page, maxPage = SED.ClampCategoryPageState(cache, activeCategory, #lines, MAX_VISIBLE_LINES)
    local pageStart = ((page - 1) * MAX_VISIBLE_LINES) + 1
    local pageEnd = math.min(#lines, pageStart + MAX_VISIBLE_LINES - 1)
    local visibleLines = {}

    for i = pageStart, pageEnd do
        visibleLines[#visibleLines + 1] = lines[i]
    end

    return {
        phantom = phantom,
        ply = ply,
        steamID = steamID,
        displayName = displayName,
        savedInfo = savedInfo,
        data = cache.data,
        cache = cache,
        activeCategory = activeCategory,
        categories = PHANTOM_CATEGORIES,
        lines = visibleLines,
        lineCount = #lines,
        page = page,
        maxPage = maxPage,
        pageStart = pageStart,
        pageEnd = pageEnd,
        distanceSqr = distanceSqr
    }
end

function Phantom.DrawPhantomInfo(phantomData, playerPos, mapName)
    local renderData = BuildRenderData(phantomData, playerPos, mapName)
    if not renderData then return end

    local phantom = renderData.phantom
    local steamID = renderData.steamID
    local displayName = renderData.displayName
    local lines = renderData.lines
    local categories = renderData.categories
    local activeCategory = renderData.activeCategory

    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return end

    local eyePos = lpCache:EyePos()
    local pos = phantom:GetPos()

    local phantomMins, phantomMaxs = phantom:OBBMins(), phantom:OBBMaxs()
    local phantomHeight = phantomMaxs.z - phantomMins.z
    local headOffset = math.max(phantomHeight + 10, 80)

    local tempWidth = Phantom.CalculateOptimalPanelSize(lines, #categories)
    local titleHeight = 34
    local tabHeight = 22
    local lineHeight = 18
    local panelHeight = titleHeight + tabHeight + (math.max(1, #lines) * lineHeight) + 20
    local scale = BASE_SCALE * math.Clamp(1 - (math.sqrt(renderData.distanceSqr) / 4000), 0.4, 1.2)
    local panelHeightWorldUnits = panelHeight * scale
    local panelBottomZ = pos.z + headOffset
    local panelCenterZ = panelBottomZ + (panelHeightWorldUnits / 2)
    local drawPos = Vector(pos.x, pos.y, panelCenterZ)
    local distance = math.sqrt(renderData.distanceSqr)
    local currentLOD = distance > 2400 and 2 or (distance > 1200 and 1 or 0)

    local dir = (pos - eyePos)
    dir:Normalize()
    local ang = dir:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90

    local width = tempWidth
    local offsetX = -width / 2
    local offsetY = -panelHeight / 2

    local aimAng = lpCache:EyeAngles()
    local toPhantomAng = (pos - lpCache:EyePos()):Angle()
    local isFocused = PhantomInteractionState.active and PhantomInteractionState.steamID == steamID
    local isCandidate = false

    do
        local eyePos2 = lpCache:EyePos()
        local forward = lpCache:EyeAngles():Forward()
        local panelCenter = drawPos
        local panelNormal = (panelCenter - eyePos2):GetNormalized()
        local right = ang:Right()
        local up = ang:Up()

        local denom = forward:Dot(panelNormal)
        local lookAtPanel = false
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

    cam_Start3D2D(drawPos, ang, scale)

    surface.SetDrawColor(0, 0, 0, 130)
    surface.DrawRect(offsetX + 4, offsetY + 4, width, panelHeight)
    DRAW_RoundedBox(8, offsetX, offsetY, width, panelHeight, currentLOD >= 2 and BG_COLOR_DISTANT or BG_COLOR)

    DRAW_RoundedBox(8, offsetX, offsetY, width, titleHeight, HEADER_COLOR)
    surface.SetDrawColor(25, 30, 40, 255)
    surface.DrawRect(offsetX, offsetY + titleHeight / 2, width, titleHeight / 2)

    surface.SetDrawColor(60, 140, 220, 255)
    surface.DrawRect(offsetX, offsetY + titleHeight - 2, width, 2)

    surface.SetDrawColor(20, 24, 30, 255)
    surface.DrawRect(offsetX, offsetY + titleHeight, width, panelHeight - titleHeight)

    for i = 0, 1 do
        SURF_SetDrawColor(70, 130, 180, 200 - i * 40)
        surface.DrawOutlinedRect(offsetX + i, offsetY + i, width - i * 2, panelHeight - i * 2, 1)
    end

    DRAW_SimpleText(string.format("Phantom of '%s'", displayName), currentLOD >= 2 and "Trebuchet18" or "Trebuchet24",
        offsetX + 12,
        offsetY + 6, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

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
        local isActive = (catID == activeCategory)
        local fillCol = Color(math.floor(catColor.r * (isActive and 0.6 or 0.25)),
            math.floor(catColor.g * (isActive and 0.6 or 0.25)), math.floor(catColor.b * (isActive and 0.6 or 0.25)),
            isActive and 230 or 130)
        SURF_SetDrawColor(fillCol.r, fillCol.g, fillCol.b, fillCol.a)
        surface.DrawRect(tabX, tabY, tabWidth, tabHeight)
        if isActive then
            SURF_SetDrawColor(catColor.r, catColor.g, catColor.b, 255)
            surface.DrawOutlinedRect(tabX, tabY, tabWidth, tabHeight, 1)
        end

        local displayName = catName
        SURF_SetFont("Trebuchet18")
        if (SURF_GetTextSize(displayName) or 0) > tabWidth - 8 then
            displayName = displayName:gsub("Basic Information", "Basic")
            displayName = displayName:gsub("Position and Movement", "Position")
            displayName = displayName:gsub("Saved Entities and NPCs", "Entities")
            if (SURF_GetTextSize(displayName) or 0) > tabWidth - 8 then
                displayName = string.sub(displayName, 1, 6) .. ".."
            end
        end

        DRAW_SimpleText(displayName, "Trebuchet18", tabX + tabWidth / 2, tabY + tabHeight / 2,
            isActive and Color(255, 255, 255) or Color(205, 205, 205), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local startY = tabY + tabHeight + 6
    SURF_SetFont("Trebuchet18")
    local visibleLines = #lines
    local labelX = offsetX + 14
    local valueX = offsetX + 180

    for i = 1, visibleLines do
        local row = lines[i]
        local y = startY + (i - 1) * lineHeight

        if i % 2 == 0 then
            SURF_SetDrawColor(40, 47, 60, 95)
            surface.DrawRect(offsetX + 6, y - 2, width - 12, lineHeight)
        end

        local label = tostring(row and row[1] or "")
        local value = tostring(row and row[2] or "")
        local valueColor = safeTextColor(row and row[3], VALUE_COLOR)
        if not row or not row[4] or not row[4].noColon then
            label = label .. ":"
        end

        local maxValueWidth = math.max(90, width - (valueX - offsetX) - 24)
        value = clipTextToWidth(value, maxValueWidth)

        DRAW_SimpleText(label, "Trebuchet18", labelX, y, LABEL_COLOR, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        DRAW_SimpleText(value, "Trebuchet18", valueX, y, valueColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    if renderData.maxPage > 1 then
        local footerY = offsetY + panelHeight - 16
        DRAW_SimpleText("Use Up/Down or Mouse Wheel for pages", "Trebuchet18", offsetX + width / 2, footerY,
            HINT_CONTROLS, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    cam_End3D2D()

    if isFocused or isCandidate then
        local ok = pcall(function()
            local hintY = drawPos.z + (panelHeight * scale) / 2 + 10
            local hintPos = Vector(drawPos.x, drawPos.y, hintY)
            local hintScale = scale * 0.8

            cam_Start3D2D(hintPos, ang, hintScale)
            if isFocused then
                DRAW_SimpleText("INTERACT MODE", "Trebuchet18", 0, 0, HINT_INTERACT, TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
                DRAW_SimpleText("Left/Right Tabs | Up/Down Pages | Shift+E Exit", "Trebuchet18", 0, 20,
                    HINT_CONTROLS, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            elseif isCandidate then
                DRAW_SimpleText("Shift + E to Inspect", "Trebuchet18", 0, 0, HINT_CANDIDATE, TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end
            cam_End3D2D()
        end)
        if not ok then
            cam_End3D2D()
        end
    end
end

function Phantom.QueuePhantomPanelsForRendering()
    if not HasViewPhantomPermission() then return end
    if not (RARELOAD and RARELOAD.DepthRenderer and RARELOAD.DepthRenderer.AddRenderItem) then return end

    CandidatePhantom, CandidateSteamID, CandidateDistSqr = nil, nil, nil
    lpCache = lpCache or LocalPlayer()
    if not IsValid(lpCache) then return end

    local eyePos = lpCache:EyePos()
    local eyeForward = lpCache:EyeAngles():Forward()
    local aimAng = lpCache:EyeAngles()
    local yawThreshold = 10
    local distThresholdSqr = 40000
    local drawDistSqr = SED.GetPhantomDrawDistSqr()
    local fovCosSqr = (SED and SED.FOV_COS_THRESHOLD_SQR) or (math.cos(math.rad(50)) ^ 2)
    local nearbyDistSqr = (SED and SED.NEARBY_DIST_SQR) or (150 * 150)
    local mapName = game.GetMap()
    local queued = {}

    if RARELOAD.Phantom then
        for steamID, data in pairs(RARELOAD.Phantom) do
            if IsValid(data.phantom) then
                local phantomPos = data.phantom:GetPos()
                local distSqr = eyePos:DistToSqr(phantomPos)
                if distSqr <= drawDistSqr then
                    local withinView = true
                    if distSqr > nearbyDistSqr then
                        local dx = phantomPos.x - eyePos.x
                        local dy = phantomPos.y - eyePos.y
                        local dz = phantomPos.z - eyePos.z
                        local lenSqr = dx * dx + dy * dy + dz * dz
                        if lenSqr > 0 then
                            local dot = dx * eyeForward.x + dy * eyeForward.y + dz * eyeForward.z
                            withinView = (dot * dot) >= (fovCosSqr * lenSqr)
                        end
                    end

                    if withinView then
                        queued[#queued + 1] = { steamID = steamID, data = data, distSqr = distSqr, pos = phantomPos }

                        if not PhantomInteractionState.active then
                            local toPhantomAng = (phantomPos - eyePos):Angle()
                            local yawDiff = math.abs(math.AngleDifference(aimAng.y, toPhantomAng.y))
                            if distSqr < distThresholdSqr and yawDiff < yawThreshold then
                                if not CandidatePhantom then
                                    CandidatePhantom = data.phantom
                                    CandidateSteamID = steamID
                                    CandidateDistSqr = distSqr
                                else
                                    local bestDist = tonumber(CandidateDistSqr) or math.huge
                                    if distSqr < bestDist then
                                        CandidatePhantom = data.phantom
                                        CandidateSteamID = steamID
                                        CandidateDistSqr = distSqr
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(queued, function(a, b)
        return a.distSqr < b.distSqr
    end)

    for i = 1, math.min(#queued, MAX_RENDERED_PHANTOMS) do
        local entry = queued[i]
        RARELOAD.DepthRenderer.AddRenderItem(entry.pos, function()
            Phantom.DrawPhantomInfo(entry.data, eyePos, mapName)
        end, "phantom")
    end

    if PhantomInteractionState.active then
        SED.HandleInteractionInput()
        return
    end

    if CandidatePhantom and CandidateSteamID and SED.KeyPressed(INTERACT_KEY) and SED.InteractModifierDown() then
        SED.EnterInteraction(CandidatePhantom, false, CandidateSteamID, {
            kind = "phantom",
            maxInteractDistSqr = SED.GetPhantomDrawDistSqr() * 1.1,
            phantom = CandidatePhantom,
            steamID = CandidateSteamID,
            onCategoryChange = function(delta)
                local cache = SED.PhantomInfoCache and SED.PhantomInfoCache[PhantomInteractionState.steamID]
                if not (cache and cache.activeCategory) then return end
                cache.activeCategory = SED.CycleCategoryState(cache, PHANTOM_CATEGORIES, cache.activeCategory, delta)
            end,
            onPageChange = function(delta)
                local cache = SED.PhantomInfoCache and SED.PhantomInfoCache[PhantomInteractionState.steamID]
                if not (cache and cache.activeCategory) then return end
                local lines = (cache.data and cache.data[cache.activeCategory]) or {}
                SED.StepCategoryPageState(cache, cache.activeCategory, #lines, MAX_VISIBLE_LINES, delta)
            end
        })
        surface.PlaySound("ui/buttonclick.wav")
    end
end

hook.Add("CreateMove", "RARELOAD_PhantomPanels_CamLock", function(cmd)
    if PhantomInteractionState.active or CurTime() - LeaveTime < 0.5 then
        cmd:RemoveKey(IN_USE)
    elseif PhantomLookingAtPanelUntil and CurTime() <= PhantomLookingAtPanelUntil then
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
    if not PhantomInteractionState.active then return end

    if bind == "+forward" or bind == "+back" or bind == "+moveleft" or bind == "+moveright" or bind == "+jump" or bind == "+duck" or bind == "+walk" or bind == "+speed" then
        return false
    end

    local cache = PhantomInfoCache[PhantomInteractionState.steamID]
    if cache and cache.activeCategory then
        local lines = (cache.data and cache.data[cache.activeCategory]) or {}
        local currentPage, maxPage = SED.ClampCategoryPageState(cache, cache.activeCategory, #lines, MAX_VISIBLE_LINES)

        if bind == "invprev" then
            SED.SetCategoryPageState(cache, cache.activeCategory, math.max(1, currentPage - 1))
            return true
        elseif bind == "invnext" then
            SED.SetCategoryPageState(cache, cache.activeCategory, math.min(maxPage, currentPage + 1))
            return true
        end
    end

    if string.find(bind, "+use", 1, true) then
        return true
    end

    return true
end)

Phantom._initialized = true
Phantom.moveTypeNames = moveTypeNames
Phantom.CATEGORIES = PHANTOM_CATEGORIES
Phantom.InfoCache = PhantomInfoCache
Phantom.QueuePhantomPanelsForRendering = Phantom.QueuePhantomPanelsForRendering
Phantom.BuildPhantomInfoData = Phantom.BuildPhantomInfoData
Phantom.CalculateOptimalPanelSize = Phantom.CalculateOptimalPanelSize
Phantom.DrawPhantomInfo = Phantom.DrawPhantomInfo

PHANTOM_CATEGORIES = PHANTOM_CATEGORIES
BuildPhantomInfoData = Phantom.BuildPhantomInfoData
CalculateOptimalPanelSize = Phantom.CalculateOptimalPanelSize
DrawPhantomInfo = Phantom.DrawPhantomInfo
QueuePhantomPanelsForRendering = Phantom.QueuePhantomPanelsForRendering

return Phantom
