-- SED panel context and layout calculations.
--
-- An SED panel is just saved JSON formatted into labeled rows. Its size and
-- contents are fully determined by (data, active tab, scroll) -- there is no
-- distance-based LOD and no size animation. That determinism is what lets the
-- panel be baked once to a texture (see SED_panel_renderer_draw.lua) and blitted
-- cheaply every frame. The only values that change without a data save are the
-- live "position"/"state" rows, which are folded into bakeSig so a moving entity
-- re-bakes while a static one stays cached.

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer_context.lua\n")
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
local string_Explode = RS.string_Explode

local CONTENT_FONT  = "Trebuchet18"
local LINE_HEIGHT   = 24
local TITLE_HEIGHT  = 52
local TAB_HEIGHT    = 32
local SIDEBAR_WIDTH = 120

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

    if not precomputedParams and SED.CULL_VIEW_CONE then
        local forward = SED.lpCache:EyeAngles():Forward()
        local toEnt = (pos - eyePos)
        local dist = toEnt:Length()
        if dist > 0 then
            toEnt:Mul(1 / dist)
            if toEnt:Dot(forward) < SED.FOV_COS_THRESHOLD and distSqr > SED.NEARBY_DIST_SQR then
                return nil
            end
        end
    end

    local cache = SED.BuildPanelData(saved, ent, isNPC)
    if not cache then return nil end

    local categories = isNPC and SED.NPC_CATEGORIES or SED.ENT_CATEGORIES

    -- Override categories for Phantoms
    if saved and saved._isPhantom and saved._phantomCategories then
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

    local distance = math_sqrt(distSqr)
    local isLarge = renderParams.isLarge
    local isMassive = renderParams.isMassive

    local maxVisibleLines = SED.MAX_VISIBLE_LINES
    local lineHeight = LINE_HEIGHT
    local titleHeight = TITLE_HEIGHT
    local tabHeight = TAB_HEIGHT
    local sidebarWidth = SIDEBAR_WIDTH
    local contentFont = CONTENT_FONT

    local width = cache.widths[activeCat]
    if not width then
        surface_SetFont(CONTENT_FONT)
        width = 300
        local maxContentWidth = 0
        local maxLabelW = 0

        for i = 1, math_min(#lines, 15) do
            local l = lines[i]
            if l and l[1] and l[2] then
                local label = (l[1] or "") .. ":"
                local value = l[2] or ""

                local w1 = surface_GetTextSize(label) or 0
                local w2 = surface_GetTextSize(value) or 0

                maxLabelW = math_max(maxLabelW, w1)

                local lineContentWidth = w1 + w2 + 170
                maxContentWidth = math_max(maxContentWidth, lineContentWidth)

                if w2 > 500 then
                    maxContentWidth = math_min(maxContentWidth, 700)
                end
            end
        end

        width = math_max(width, maxContentWidth) + sidebarWidth
        width = math_Clamp(width, 450, isLarge and 1000 or 850)
        maxLabelW = math_min(maxLabelW, 230)

        cache.widths[activeCat] = width
        cache.maxLabelWidths = cache.maxLabelWidths or {}
        cache.maxLabelWidths[activeCat] = maxLabelW
        cache._wrap = cache._wrap or {}
        cache._wrap[activeCat] = nil
    end

    local panelID = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or saved.RareloadID or
        ((saved.class or saved.Class or saved.ClassName or "unknown") .. "?")
    local scrollTable = isNPC and SED.PanelScroll.npcs or SED.PanelScroll.entities
    local scrollKey = panelID .. "_" .. activeCat

    -- Layout signature: everything that affects the rendered pixels. Static data
    -- yields a constant signature (cache hit); live position/state rows fold in
    -- the entity's current transform so movement triggers a re-bake.
    local layoutSig = activeCat .. "|" .. (scrollTable[scrollKey] or 0)
    if activeCat == "position" or activeCat == "state" then
        local p = ent:GetPos()
        local a = ent:GetAngles()
        layoutSig = layoutSig .. "|" .. p.x .. "," .. p.y .. "," .. p.z ..
            "|" .. a.p .. "," .. a.y .. "," .. a.r
        if ent.Health then layoutSig = layoutSig .. "|" .. ent:Health() end
        if ent.GetVelocity then layoutSig = layoutSig .. "|" .. math_floor(ent:GetVelocity():Length()) end
    end

    local layout = cache._layout
    local itemsToDrawInfos, contentHeight, renderedLogicalItems, maxScrollLines, currentScroll

    if layout and cache._layoutSig == layoutSig then
        itemsToDrawInfos     = layout.itemsToDrawInfos
        contentHeight        = layout.contentHeight
        renderedLogicalItems = layout.renderedLogicalItems
        maxScrollLines       = layout.maxScrollLines
        currentScroll        = layout.currentScroll
        scrollTable[scrollKey] = currentScroll
    else
        local maxLabelW = cache.maxLabelWidths and cache.maxLabelWidths[activeCat] or 100
        local maxValueWidthEstimate = width - sidebarWidth - maxLabelW - 40
        if maxValueWidthEstimate < 90 then maxValueWidthEstimate = 90 end

        local truePhysicalLinesTotal = 0
        for _, l in ipairs(lines) do
            truePhysicalLinesTotal = truePhysicalLinesTotal + #wrapText(cache, activeCat, l[2] or "", maxValueWidthEstimate)
        end

        maxScrollLines = math_max(0, truePhysicalLinesTotal - maxVisibleLines)
        currentScroll = math_min(scrollTable[scrollKey] or 0, maxScrollLines)
        scrollTable[scrollKey] = currentScroll

        contentHeight = 12
        local totalPhysicalLines = 0
        renderedLogicalItems = 0

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

        itemsToDrawInfos = {}
        for i = startIndex, #lines do
            local wrapLines = wrapText(cache, activeCat, lines[i][2] or "", maxValueWidthEstimate)
            local linesNeededTotal = #wrapLines
            local linesNeeded = linesNeededTotal

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

            contentHeight = contentHeight + (linesNeeded * lineHeight) + 4
            totalPhysicalLines = totalPhysicalLines + linesNeeded
            renderedLogicalItems = renderedLogicalItems + 1

            itemsToDrawInfos[#itemsToDrawInfos + 1] = {
                logicalIndex = i,
                linesNeeded = linesNeeded,
                wrapLines = wrapLines,
                isPartialStart = (i == startIndex and startOffset > 0)
            }
        end

        layout = layout or {}
        layout.itemsToDrawInfos     = itemsToDrawInfos
        layout.contentHeight        = contentHeight
        layout.renderedLogicalItems = renderedLogicalItems
        layout.maxScrollLines       = maxScrollLines
        layout.currentScroll        = currentScroll
        cache._layout = layout
        cache._layoutSig = layoutSig
    end

    local minVisibleTabs = math_min(#categories, 4)
    local minSidebarHeight = minVisibleTabs * tabHeight + 24

    local calculatedHeight = titleHeight + contentHeight + 18
    local panelHeight = math_max(calculatedHeight, titleHeight + minSidebarHeight)

    local maxVisibleTabs = math_max(minVisibleTabs, math_floor((panelHeight - titleHeight - 24) / tabHeight))

    local distanceScale = math_Clamp(1 - (distance / (isLarge and 3000 or 2000)), 0.3, 1.5)
    local scale = renderParams.baseScale * distanceScale
    if isMassive then
        scale = scale * 0.6
    end
    scale = math_Clamp(scale, SED.MIN_SCALE, SED.MAX_SCALE)

    local frameHeightWorldUnits = panelHeight * scale
    local obbCenterLocal = (renderParams.obbMin + renderParams.obbMax) * 0.5
    local worldCenter = ent.LocalToWorld and ent:LocalToWorld(obbCenterLocal) or pos

    local worldTopZ = renderParams.worldTopZ
    if not worldTopZ then
        if ent.LocalToWorld then
            local topLocal = Vector(obbCenterLocal.x, obbCenterLocal.y, renderParams.obbMax.z)
            worldTopZ = ent:LocalToWorld(topLocal).z
        else
            worldTopZ = pos.z + renderParams.size.z
        end
    end

    local baseZ
    if isMassive then
        baseZ = worldTopZ + renderParams.buffer + frameHeightWorldUnits * 0.5
    elseif isLarge then
        baseZ = worldTopZ + renderParams.buffer * 0.6 + frameHeightWorldUnits * 0.5
    else
        baseZ = worldTopZ + renderParams.buffer * 0.4 + frameHeightWorldUnits * 0.5
    end

    local basePos = Vector(worldCenter.x, worldCenter.y, baseZ)

    local toCenter = worldCenter - eyePos
    local horiz = Vector(toCenter.x, toCenter.y, 0)
    if horiz:Length() < 0.001 then horiz = Vector(1, 0, 0) end
    horiz:Normalize()
    local outwardAmount = math_Clamp(renderParams.maxDimension * 0.35, 30, 600)
    local drawPos = basePos - horiz * outwardAmount

    if isLarge or isMassive then
        local now = CurTime()
        if not renderParams._traceTime or (now - renderParams._traceTime) > 0.15 then
            renderParams._traceTime = now
            local ok, tr = pcall(util.TraceLine, { start = eyePos, endpos = drawPos, filter = SED.lpCache })
            renderParams._traceBlocked = ok and tr and tr.Hit and tr.Entity == ent
        end
        if renderParams._traceBlocked then
            drawPos = drawPos - horiz * (outwardAmount * 0.5)
        end
    end

    local ang
    do
        local faceDir = (drawPos - eyePos)
        faceDir:Normalize()
        ang = faceDir:Angle()
        ang.y = ang.y - 90
        ang.p = 0
        ang.r = 90
    end

    local eyeToPanel = drawPos - eyePos
    if eyeToPanel:Length() < 10 then
        drawPos = eyePos + eyeToPanel:GetNormalized() * 50
    end

    local offsetX = -width / 2
    local offsetY = -panelHeight / 2

    local activeIndex = 1
    for i, cat in ipairs(categories) do
        if cat[1] == activeCat then
            activeIndex = i
            break
        end
    end

    local visibleCount = math_min(#categories, maxVisibleTabs)
    local targetScroll = activeIndex - 2
    if targetScroll < 0 then targetScroll = 0 end
    if targetScroll > #categories - visibleCount then targetScroll = #categories - visibleCount end

    -- Sidebar scroll snaps to the active tab (no animation -> deterministic bake).
    local currentScrollPos = targetScroll

    -- bakeSig keys the render-target cache. Width/height are deterministic from
    -- content, and _layoutSig already folds in live transform, so this is stable
    -- for a static panel and changes exactly when the rendered pixels change.
    local bakeSig = panelID .. "|" .. math_floor(width) .. "x" .. math_floor(panelHeight) .. "|" .. layoutSig

    return {
        ent = ent,
        saved = saved,
        isNPC = isNPC,
        eyePos = eyePos,
        drawPos = drawPos,
        ang = ang,
        panelID = panelID,
        bakeSig = bakeSig,
        cache = cache,
        categories = categories,
        activeCat = activeCat,
        lines = lines,
        lineHeight = lineHeight,
        titleHeight = titleHeight,
        tabHeight = tabHeight,
        sidebarWidth = sidebarWidth,
        contentFont = contentFont,
        width = width,
        panelHeight = panelHeight,
        scale = scale,
        offsetX = offsetX,
        offsetY = offsetY,
        maxScrollLines = maxScrollLines,
        currentScroll = currentScroll,
        renderedLogicalItems = renderedLogicalItems,
        contentHeight = contentHeight,
        itemsToDrawInfos = itemsToDrawInfos,
        activeIndex = activeIndex,
        maxVisibleTabs = maxVisibleTabs,
        visibleCount = visibleCount,
        currentScrollPos = currentScrollPos,
        tabStartY = offsetY + titleHeight + 12
    }
end
