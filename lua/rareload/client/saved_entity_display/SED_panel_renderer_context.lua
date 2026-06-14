local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer_context.lua\n")
    return
end

local SS = SED.Shared
if not (SS and SS._initialized) then
    include("rareload/client/saved_entity_display/SED_shared.lua")
    SS = SED.Shared
end

if not (SS and SS._initialized) then
    ErrorNoHalt("[Rareload] Missing SED.Shared in SED_panel_renderer_context.lua\n")
    return
end

local VALUE_COLOR = RS.VALUE_COLOR
local surface_SetFont = RS.surface_SetFont
local surface_GetTextSize = RS.surface_GetTextSize
local math_sqrt = RS.math_sqrt
local math_max = RS.math_max
local math_min = RS.math_min
local math_Clamp = RS.math_Clamp
local math_floor = RS.math_floor
local math_abs = math.abs
local string_Explode = RS.string_Explode

local CONTENT_FONT  = "Trebuchet18"
local LINE_HEIGHT   = 24
local TITLE_HEIGHT  = 52
local TAB_HEIGHT    = 32
local SIDEBAR_WIDTH = 120

local MOVE_EPS_SQR  = 0.25
local ANG_EPS       = 0.5

local function wrapText(cache, activeCat, text, maxWidth)
    if not text or text == "" then return { text } end
    local wrapCache = cache._wrap or {}
    cache._wrap = wrapCache
    wrapCache[activeCat] = wrapCache[activeCat] or { width = maxWidth, lines = {} }
    local catWrap = wrapCache[activeCat]
    if catWrap.width ~= maxWidth then
        catWrap.width = maxWidth
        catWrap.lines = {}
    end

    local cached = catWrap.lines[text]
    if cached then return cached end

    surface_SetFont(CONTENT_FONT)
    local textWidth = surface_GetTextSize(text) or 0

    if textWidth <= maxWidth and not string.find(text, "\n") then
        local res = { text }
        catWrap.lines[text] = res
        return res
    end

    local wrapLines = {}
    local linesToProcess = string_Explode("\n", text)

    for _, explLine in ipairs(linesToProcess) do
        local words = string_Explode(" ", explLine)
        local currentLine = ""

        for _, word in ipairs(words) do
            local testLine = currentLine

            if currentLine == "" and word == "" then
                testLine = testLine .. " "
            elseif currentLine == "" then
                testLine = word
            elseif word == "" then
                testLine = testLine .. " "
            else
                testLine = testLine .. " " .. word
            end

            local testWidth = surface_GetTextSize(testLine) or 0

            if testWidth <= maxWidth then
                currentLine = testLine
            else
                if string.Trim(currentLine) ~= "" then
                    wrapLines[#wrapLines + 1] = currentLine
                    local indentMatch = string.match(explLine, "^(%s+)")
                    currentLine = (indentMatch or "") .. word
                else
                    wrapLines[#wrapLines + 1] = word
                    currentLine = ""
                end
            end
        end

        if currentLine ~= "" or explLine == "" then
            wrapLines[#wrapLines + 1] = currentLine
        end
    end

    local result = #wrapLines > 0 and wrapLines or { text }
    catWrap.lines[text] = result
    return result
end

local function RebuildLayout(cache, lines, categories, activeCat, scrollTable, scrollKey, isLarge)
    local maxVisibleLines = SED.MAX_VISIBLE_LINES

    local width = cache.widths[activeCat]
    if not width then
        surface_SetFont(CONTENT_FONT)
        width = 300
        local maxContentWidth, maxLabelW = 0, 0
        for i = 1, math_min(#lines, 15) do
            local l = lines[i]
            if l and l[1] and l[2] then
                local w1 = surface_GetTextSize((l[1] or "") .. ":") or 0
                local w2 = surface_GetTextSize(l[2] or "") or 0
                maxLabelW = math_max(maxLabelW, w1)
                local lineContentWidth = w1 + w2 + 170
                maxContentWidth = math_max(maxContentWidth, lineContentWidth)
                if w2 > 500 then maxContentWidth = math_min(maxContentWidth, 700) end
            end
        end
        width = math_Clamp(math_max(width, maxContentWidth) + SIDEBAR_WIDTH, 450, isLarge and 1000 or 850)
        maxLabelW = math_min(maxLabelW, 230)
        cache.widths[activeCat] = width
        cache.maxLabelWidths = cache.maxLabelWidths or {}
        cache.maxLabelWidths[activeCat] = maxLabelW
        cache._wrap = cache._wrap or {}
        cache._wrap[activeCat] = nil
    end

    local maxLabelW = cache.maxLabelWidths and cache.maxLabelWidths[activeCat] or 100
    local maxValueWidthEstimate = math_max(90, width - SIDEBAR_WIDTH - maxLabelW - 40)

    local truePhysicalLinesTotal = 0
    for _, l in ipairs(lines) do
        truePhysicalLinesTotal = truePhysicalLinesTotal + #wrapText(cache, activeCat, l[2] or "", maxValueWidthEstimate)
    end

    local maxScrollLines = math_max(0, truePhysicalLinesTotal - maxVisibleLines)
    local currentScroll = math_min(scrollTable[scrollKey] or 0, maxScrollLines)
    scrollTable[scrollKey] = currentScroll

    local contentHeight = 12
    local totalPhysicalLines = 0
    local renderedLogicalItems = 0
    local physicalLinesSkipped = 0
    local startIndex = 1
    local physicalOffsetInsideStartItem = 0

    for i, l in ipairs(lines) do
        local requiredLines = #wrapText(cache, activeCat, l[2] or "", maxValueWidthEstimate)
        if physicalLinesSkipped + requiredLines > currentScroll then
            startIndex = i
            physicalOffsetInsideStartItem = currentScroll - physicalLinesSkipped
            break
        end
        physicalLinesSkipped = physicalLinesSkipped + requiredLines
    end

    local itemsToDrawInfos = {}
    for i = startIndex, #lines do
        local wrapLines = wrapText(cache, activeCat, lines[i][2] or "", maxValueWidthEstimate)
        local linesNeeded = #wrapLines
        local startOffset = 0
        if i == startIndex then
            startOffset = physicalOffsetInsideStartItem
            linesNeeded = linesNeeded - startOffset
            wrapLines = { unpack(wrapLines, startOffset + 1) }
        end
        if totalPhysicalLines + linesNeeded > maxVisibleLines then
            linesNeeded = maxVisibleLines - totalPhysicalLines
            if linesNeeded <= 0 then break end
            wrapLines = { unpack(wrapLines, 1, linesNeeded) }
        end
        contentHeight = contentHeight + (linesNeeded * LINE_HEIGHT) + 4
        totalPhysicalLines = totalPhysicalLines + linesNeeded
        renderedLogicalItems = renderedLogicalItems + 1
        itemsToDrawInfos[#itemsToDrawInfos + 1] = {
            logicalIndex = i,
            linesNeeded = linesNeeded,
            wrapLines = wrapLines,
            isPartialStart = (i == startIndex and startOffset > 0)
        }
    end

    local minVisibleTabs = math_min(#categories, 4)
    local panelHeight = math_max(TITLE_HEIGHT + contentHeight + 18, TITLE_HEIGHT + minVisibleTabs * TAB_HEIGHT + 24)
    local maxVisibleTabs = math_max(minVisibleTabs, math_floor((panelHeight - TITLE_HEIGHT - 24) / TAB_HEIGHT))

    local activeIndex = 1
    for i, cat in ipairs(categories) do
        if cat[1] == activeCat then activeIndex = i break end
    end

    local visibleCount = math_min(#categories, maxVisibleTabs)
    local targetScroll = math_Clamp(activeIndex - 2, 0, math_max(0, #categories - visibleCount))

    cache._layout = {
        width = width,
        panelHeight = panelHeight,
        contentHeight = contentHeight,
        itemsToDrawInfos = itemsToDrawInfos,
        maxScrollLines = maxScrollLines,
        currentScroll = currentScroll,
        renderedLogicalItems = renderedLogicalItems,
        activeIndex = activeIndex,
        maxVisibleTabs = maxVisibleTabs,
        visibleCount = visibleCount,
        currentScrollPos = targetScroll,
    }
end

function SED.PanelRendererBuildContext(ent, saved, isNPC, precomputedParams, precomputedDistSqr)
    if not (IsValid(ent) and saved) then return nil end

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return nil end

    local eyePos = SED.lpCache:EyePos()
    local pos = ent:GetPos()

    local renderParams = precomputedParams or SED.CalculateEntityRenderParams(ent)
    if not renderParams then return nil end

    local distSqr = precomputedDistSqr or eyePos:DistToSqr(pos)
    if distSqr > renderParams.drawDistanceSqr then return nil end

    local cache = SED.BuildPanelData(saved, ent, isNPC)
    if not cache then return nil end

    local categories = isNPC and SED.NPC_CATEGORIES or SED.ENT_CATEGORIES
    if saved._isPhantom and saved._phantomCategories then
        categories = saved._phantomCategories
    end

    local activeCat = cache.activeCat
    local lines = cache.data[activeCat]
    if not lines or #lines == 0 then
        for _, cat in ipairs(categories) do
            local catLines = cache.data[cat[1]]
            if catLines and #catLines > 0 then
                activeCat = cat[1]
                cache.activeCat = activeCat
                lines = catLines
                break
            end
        end
    end
    lines = lines or {}
    if #lines == 0 then
        local fallbackClass = saved.class or saved.Class or saved.ClassName or ent:GetClass() or "Unknown"
        lines = { { "No data", "No captured values available for " .. fallbackClass, VALUE_COLOR } }
    end

    local panelID = cache._panelID
    if not panelID then
        local rawID = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or saved.RareloadID or
            ((saved.class or saved.Class or saved.ClassName or "unknown") .. "?")
        panelID = (saved._isPhantom and "P:" or (isNPC and "N:" or "E:")) .. tostring(rawID)
        cache._panelID = panelID
    end

    local isLiveTab = (activeCat == "position" or activeCat == "state")
    local liveGen = cache._liveGen or 0
    if isLiveTab then
        local a = ent.GetAngles and ent:GetAngles() or nil
        local moved = (not cache._liveP) or cache._liveP:DistToSqr(pos) > MOVE_EPS_SQR
        if not moved and a then
            local la = cache._liveA
            if (not la) or (math_abs(a.p - la.p) + math_abs(a.y - la.y) + math_abs(a.r - la.r)) > ANG_EPS then
                moved = true
            end
        end
        if not moved and ent.Health and cache._liveHP ~= ent:Health() then moved = true end
        if moved then
            liveGen = liveGen + 1
            cache._liveGen = liveGen
            cache._liveP = pos
            cache._liveA = a
            cache._liveHP = ent.Health and ent:Health() or 0

            local liveData = cache.data and cache.data.position
            if liveData then
                for _, line in ipairs(liveData) do
                    local k = line[1]
                    if k == "Live Pos" then
                        line[2] = string.format("%.0f, %.0f, %.0f", pos.x, pos.y, pos.z)
                    elseif k == "Live Ang" and a then
                        line[2] = string.format("%.0f, %.0f, %.0f", a.p, a.y, a.r)
                    end
                end
            end
        end
    end
    local liveTag = isLiveTab and liveGen or 0

    local scrollTable = isNPC and SED.PanelScroll.npcs or SED.PanelScroll.entities
    if cache._scrollKeyCat ~= activeCat then
        cache._scrollKey = panelID .. "_" .. activeCat
        cache._scrollKeyCat = activeCat
    end
    local scroll = scrollTable[cache._scrollKey] or 0

    local ctx = cache._ctx
    local staticValid = ctx
        and cache._ctxGen == cache._gen
        and cache._ctxCat == activeCat
        and cache._ctxScroll == scroll
        and cache._ctxLive == liveTag

    if not staticValid then
        RebuildLayout(cache, lines, categories, activeCat, scrollTable, cache._scrollKey, renderParams.isLarge)
        local layout = cache._layout
        local width = layout.width
        local panelHeight = layout.panelHeight

        local bakeSig = panelID .. "|" .. (cache._gen or 0) .. "|" .. activeCat .. "|" .. scroll ..
            (isLiveTab and ("|g" .. liveGen) or "") .. "|" ..
            math_floor(width) .. "x" .. math_floor(panelHeight)

        ctx = ctx or {}
        cache._ctx = ctx
        ctx.isNPC                = isNPC
        ctx.panelID              = panelID
        ctx.bakeSig              = bakeSig
        ctx.cache                = cache
        ctx.categories           = categories
        ctx.activeCat            = activeCat
        ctx.lines                = lines
        ctx.lineHeight           = LINE_HEIGHT
        ctx.titleHeight          = TITLE_HEIGHT
        ctx.tabHeight            = TAB_HEIGHT
        ctx.sidebarWidth         = SIDEBAR_WIDTH
        ctx.contentFont          = CONTENT_FONT
        ctx.width                = width
        ctx.panelHeight          = panelHeight
        ctx.offsetX              = -width / 2
        ctx.offsetY              = -panelHeight / 2
        ctx.maxScrollLines       = layout.maxScrollLines
        ctx.currentScroll        = layout.currentScroll
        ctx.renderedLogicalItems = layout.renderedLogicalItems
        ctx.contentHeight        = layout.contentHeight
        ctx.itemsToDrawInfos     = layout.itemsToDrawInfos
        ctx.activeIndex          = layout.activeIndex
        ctx.maxVisibleTabs       = layout.maxVisibleTabs
        ctx.visibleCount         = layout.visibleCount
        ctx.currentScrollPos     = layout.currentScrollPos
        ctx.tabStartY            = -panelHeight / 2 + TITLE_HEIGHT + 12

        cache._ctxGen    = cache._gen
        cache._ctxCat    = activeCat
        cache._ctxScroll = scroll
        cache._ctxLive   = liveTag
    end

    ctx.ent    = ent
    ctx.saved  = saved
    ctx.eyePos = eyePos

    local panelHeight = ctx.panelHeight
    local distance = math_sqrt(distSqr)
    local isLarge, isMassive = renderParams.isLarge, renderParams.isMassive

    local distanceScale = math_Clamp(1 - (distance / (isLarge and 3000 or 2000)), 0.3, 1.5)
    local scale = renderParams.baseScale * distanceScale
    if isMassive then scale = scale * 0.6 end
    scale = math_Clamp(scale, SED.MIN_SCALE, SED.MAX_SCALE)

    local obbCenterLocal = (renderParams.obbMin + renderParams.obbMax) * 0.5
    local worldCenter = ent.LocalToWorld and ent:LocalToWorld(obbCenterLocal) or pos
    local worldTopZ = renderParams.worldTopZ or (pos.z + renderParams.size.z)
    local frameHeightWorldUnits = panelHeight * scale

    local baseZ
    if isMassive then
        baseZ = worldTopZ + renderParams.buffer + frameHeightWorldUnits * 0.5
    elseif isLarge then
        baseZ = worldTopZ + renderParams.buffer * 0.6 + frameHeightWorldUnits * 0.5
    else
        baseZ = worldTopZ + renderParams.buffer * 0.4 + frameHeightWorldUnits * 0.5
    end

    local horiz = Vector(worldCenter.x - eyePos.x, worldCenter.y - eyePos.y, 0)
    if horiz:LengthSqr() < 1e-4 then horiz = Vector(1, 0, 0) end
    horiz:Normalize()
    local outwardAmount = math_Clamp(renderParams.maxDimension * 0.35, 30, 600)
    local drawPos = Vector(worldCenter.x, worldCenter.y, baseZ) - horiz * outwardAmount

    if isLarge or isMassive then
        local now = CurTime()
        if not renderParams._traceTime or (now - renderParams._traceTime) > 0.15 then
            renderParams._traceTime = now
            local ok, tr = pcall(util.TraceLine, { start = eyePos, endpos = drawPos, filter = SED.lpCache })
            renderParams._traceBlocked = ok and tr and tr.Hit and tr.Entity == ent
        end
        if renderParams._traceBlocked then drawPos = drawPos - horiz * (outwardAmount * 0.5) end
    end

    local toPanel = drawPos - eyePos
    if toPanel:Length() < 10 then drawPos = eyePos + toPanel:GetNormalized() * 50 end

    ctx.drawPos = drawPos
    ctx.ang     = SS.FacingAngle(drawPos - eyePos)
    ctx.scale   = scale

    return ctx
end
