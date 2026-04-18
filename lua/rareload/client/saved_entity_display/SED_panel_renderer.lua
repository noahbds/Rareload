-- SED panel rendering functions (optimized)

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer.lua\n")
    return
end

local BG_COLOR = RS.BG_COLOR
local BG_COLOR_DISTANT = RS.BG_COLOR_DISTANT
local HEADER_COLOR = RS.HEADER_COLOR
local WHITE = RS.WHITE
local LABEL_COLOR = RS.LABEL_COLOR
local VALUE_COLOR = RS.VALUE_COLOR
local TAB_INACTIVE = RS.TAB_INACTIVE
local TAB_EMPTY = RS.TAB_EMPTY
local TAB_COUNT_INACTIVE = RS.TAB_COUNT_INACTIVE
local TAB_COUNT_EMPTY = RS.TAB_COUNT_EMPTY
local ARROW_COLOR = RS.ARROW_COLOR
local SCROLL_BG = RS.SCROLL_BG
local SCROLL_HANDLE = RS.SCROLL_HANDLE
local ROW_ALT = RS.ROW_ALT
local VJ_OUTER = RS.VJ_OUTER
local VJ_INNER = RS.VJ_INNER
local VJ_TEXT_COLOR = RS.VJ_TEXT_COLOR
local HP_OUTER = RS.HP_OUTER
local HP_BG = RS.HP_BG
local HP_TEXT = RS.HP_TEXT
local HP_FILL = RS.HP_FILL
local ARMOR_OUTER = RS.ARMOR_OUTER
local ARMOR_BG = RS.ARMOR_BG
local ARMOR_FILL = RS.ARMOR_FILL
local ARMOR_TEXT = RS.ARMOR_TEXT
local HINT_INTERACT = RS.HINT_INTERACT
local HINT_CONTROLS = RS.HINT_CONTROLS
local HINT_CANDIDATE = RS.HINT_CANDIDATE
local MINI_TEXT = RS.MINI_TEXT

-- Cached function references (avoid repeated table lookups in hot path)
local cam_Start3D2D = RS.cam_Start3D2D
local cam_End3D2D = RS.cam_End3D2D
local surface_SetDrawColor = RS.surface_SetDrawColor
local surface_DrawRect = RS.surface_DrawRect
local surface_DrawOutlinedRect = RS.surface_DrawOutlinedRect
local surface_SetFont = RS.surface_SetFont
local surface_GetTextSize = RS.surface_GetTextSize
local draw_RoundedBox = RS.draw_RoundedBox
local draw_SimpleText = RS.draw_SimpleText
local render_SetStencilWriteMask = RS.render_SetStencilWriteMask
local render_SetStencilTestMask = RS.render_SetStencilTestMask
local render_SetStencilReferenceValue = RS.render_SetStencilReferenceValue
local render_SetStencilCompareFunction = RS.render_SetStencilCompareFunction
local render_SetStencilPassOperation = RS.render_SetStencilPassOperation
local render_SetStencilFailOperation = RS.render_SetStencilFailOperation
local render_SetStencilZFailOperation = RS.render_SetStencilZFailOperation
local render_ClearStencil = RS.render_ClearStencil
local render_SetStencilEnable = RS.render_SetStencilEnable
local math_sqrt = RS.math_sqrt
local math_max = RS.math_max
local math_min = RS.math_min
local math_Clamp = RS.math_Clamp
local math_abs = RS.math_abs
local math_floor = RS.math_floor
local math_ceil = RS.math_ceil
local math_AngleDifference = RS.math_AngleDifference
local string_Explode = RS.string_Explode
local safeTextColor = RS.safeTextColor
local clipTextToWidth = RS.clipTextToWidth

function SED.DrawSavedPanel(ent, saved, isNPC, precomputedParams, precomputedDistSqr)
    if not (IsValid(ent) and saved) then return end

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local pos = ent:GetPos()

    local renderParams = precomputedParams or SED.CalculateEntityRenderParams(ent)
    if not renderParams then return end

    local distSqr = precomputedDistSqr or eyePos:DistToSqr(pos)
    if distSqr > renderParams.drawDistanceSqr then return end

    -- FOV culling only when called directly (not from queue, which already culled)
    if not precomputedParams and SED.CULL_VIEW_CONE then
        local forward = SED.lpCache:EyeAngles():Forward()
        local toEnt = (pos - eyePos)
        local dist = toEnt:Length()
        if dist > 0 then
            toEnt:Mul(1 / dist)
            if toEnt:Dot(forward) < SED.FOV_COS_THRESHOLD and distSqr > SED.NEARBY_DIST_SQR then
                return
            end
        end
    end

    local cache = SED.BuildPanelData(saved, ent, isNPC)
    if not cache then return end

    local categories = isNPC and SED.NPC_CATEGORIES or SED.ENT_CATEGORIES
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
    local effectiveDistance = distance
    local isLarge = renderParams.isLarge
    local isMassive = renderParams.isMassive
    local isMediumDistant = effectiveDistance > (isLarge and 800 or 400)
    local isDistant = effectiveDistance > (isLarge and 1200 or 600)
    local isVeryDistant = effectiveDistance > (isLarge and 1500 or 800)
    local currentLOD = isVeryDistant and 3 or (isDistant and 2 or (isMediumDistant and 1 or 0))

    -- Refine effective distance for large entities only at close LOD
    if currentLOD < 2 and (isLarge or isMassive) then
        local centerLocal = (renderParams.obbMin + renderParams.obbMax) * 0.5
        if ent.LocalToWorld then
            local wc = ent:LocalToWorld(centerLocal)
            local d = (eyePos - wc):Length()
            if d < effectiveDistance then effectiveDistance = d end
        end
        if ent.NearestPoint then
            local ok, np = pcall(ent.NearestPoint, ent, eyePos)
            if ok and isvector(np) then
                local d2 = (eyePos - np):Length()
                if d2 < effectiveDistance then effectiveDistance = d2 end
            end
        end

        isMediumDistant = effectiveDistance > (isLarge and 800 or 400)
        isDistant = effectiveDistance > (isLarge and 1200 or 600)
        isVeryDistant = effectiveDistance > (isLarge and 1500 or 800)
        currentLOD = isVeryDistant and 3 or (isDistant and 2 or (isMediumDistant and 1 or 0))
    end

    cache.lod = cache.lod or {}
    local previousLOD = cache.lod[activeCat]
    if previousLOD ~= nil and previousLOD ~= currentLOD then
        cache.widths[activeCat] = nil
    end
    cache.lod[activeCat] = currentLOD

    local maxVisibleLines = SED.MAX_VISIBLE_LINES
    if currentLOD == 3 then
        maxVisibleLines = math_min(8, SED.MAX_VISIBLE_LINES)
    elseif currentLOD == 2 then
        maxVisibleLines = math_min(12, SED.MAX_VISIBLE_LINES)
    elseif currentLOD == 1 then
        maxVisibleLines = math_min(15, SED.MAX_VISIBLE_LINES)
    end

    local lineHeight = currentLOD >= 2 and 18 or 24
    local titleHeight = currentLOD >= 2 and 30 or 52
    local tabHeight = currentLOD >= 2 and 24 or 32
    local sidebarWidth = currentLOD >= 2 and 80 or 120

    local contentFont = "Trebuchet18"

    local function performWrapText(text, maxWidth)
        if not text or text == "" then return { text } end
        local wrapCache = cache._wrap or {}
        cache._wrap = wrapCache
        wrapCache[activeCat] = wrapCache[activeCat] or { width = maxWidth, lines = {} }
        local catWrap = wrapCache[activeCat]
        if catWrap.width ~= maxWidth then
            catWrap.width = maxWidth
            catWrap.lines = {}
        end

        surface_SetFont(contentFont)
        local textWidth = surface_GetTextSize(text) or 0
        if textWidth <= maxWidth and not string.find(text, "\n") then
            return { text }
        end
        local cached = catWrap.lines[text]
        if cached then return cached end

        local wrapLines = {}
        local linesToProcess = string_Explode("\n", text)

        for _, explLine in ipairs(linesToProcess) do
            local words = string_Explode(" ", explLine)
            local currentLine = ""

            for i, word in ipairs(words) do
                local testLine = currentLine

                -- preserve leading spaces
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
                        -- Try to carry over the indentation to the next wrapped line
                        local indentMatch = string.match(explLine, "^(%s+)")
                        currentLine = (indentMatch or "") .. word
                    else
                        wrapLines[#wrapLines + 1] = word
                        currentLine = ""
                    end
                end
            end

            -- Ensure we push the last segment, explicitly allow mostly empty lines if original was empty
            if currentLine ~= "" or explLine == "" then
                wrapLines[#wrapLines + 1] = currentLine
            end
        end

        local result = #wrapLines > 0 and wrapLines or { text }
        catWrap.lines[text] = result
        return result
    end

    local width = cache.widths[activeCat] or 400
    if not cache.widths[activeCat] then
        surface_SetFont("Trebuchet18")
        width = 300
        local maxContentWidth = 0
        local maxLabelW = 0
        local sampleCount = currentLOD == 0 and 15 or currentLOD == 1 and 10 or 5

        for i = 1, math_min(#lines, sampleCount) do
            local l = lines[i]
            if l and l[1] and l[2] then
                local label = (l[1] or "") .. ":"
                local value = l[2] or ""

                local w1 = surface_GetTextSize(label) or 0
                local w2 = surface_GetTextSize(value) or 0

                maxLabelW = math_max(maxLabelW, w1)

                local lineContentWidth = w1 + w2 + (currentLOD >= 2 and 120 or 170)
                maxContentWidth = math_max(maxContentWidth, lineContentWidth)

                if w2 > (currentLOD >= 2 and 300 or 500) then
                    maxContentWidth = math_min(maxContentWidth, currentLOD >= 2 and 450 or 700)
                end
            end
        end

        width = math_max(width, maxContentWidth)

        width = width + sidebarWidth

        local maxWidth = currentLOD >= 2 and 600 or (isLarge and 1000 or 850)
        local minWidth = currentLOD >= 2 and 300 or 450
        width = math_Clamp(width, minWidth, maxWidth)
        maxLabelW = math_min(maxLabelW, currentLOD >= 2 and 170 or 230)
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

    -- We must calculate the total physical lines for scrolling, not logical lines
    local maxLabelWForScroll = cache.maxLabelWidths and cache.maxLabelWidths[activeCat] or 100
    local maxValueWForScroll = width - sidebarWidth - maxLabelWForScroll - 40
    if maxValueWForScroll < 90 then maxValueWForScroll = 90 end

    local truePhysicalLinesTotal = 0
    for _, l in ipairs(lines) do
        truePhysicalLinesTotal = truePhysicalLinesTotal + #performWrapText(l[2] or "", maxValueWForScroll)
    end

    local maxScrollLines = math_max(0, truePhysicalLinesTotal - maxVisibleLines)
    local currentScroll = math_min(scrollTable[scrollKey] or 0, maxScrollLines)
    scrollTable[scrollKey] = currentScroll

    -- Recalculate contentHeight using actual wrapping and margins
    -- and ensure the limit is evaluated using physical (wrapped) lines, not logical lines
    local contentHeight = 12
    local totalPhysicalLines = 0
    local renderedLogicalItems = 0
    local maxLabelW = cache.maxLabelWidths and cache.maxLabelWidths[activeCat] or 100
    local maxValueWidthEstimate = width - sidebarWidth - maxLabelW - 40
    if maxValueWidthEstimate < 90 then maxValueWidthEstimate = 90 end

    -- Advance through logical items, consuming physical lines equivalent to currentScroll
    local physicalLinesSkipped = 0
    local startIndex = 1
    local physicalOffsetInsideStartItem = 0

    for i, l in ipairs(lines) do
        local requiredLines = #performWrapText(l[2] or "", maxValueWidthEstimate)
        if physicalLinesSkipped + requiredLines > currentScroll then
            startIndex = i
            physicalOffsetInsideStartItem = currentScroll - physicalLinesSkipped
            break
        end
        physicalLinesSkipped = physicalLinesSkipped + requiredLines
    end

    -- We'll calculate target heights based on what's visible
    local itemsToDrawInfos = {}
    for i = startIndex, #lines do
        local l = lines[i]
        local wrapLines = performWrapText(l[2] or "", maxValueWidthEstimate)
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

        table.insert(itemsToDrawInfos, {
            logicalIndex = i,
            linesNeeded = linesNeeded,
            wrapLines = wrapLines,
            isPartialStart = (i == startIndex and startOffset > 0)
        })
    end

    local minVisibleTabs = math_min(#categories, 4)
    local minSidebarHeight = minVisibleTabs * tabHeight + 24

    local calculatedHeight = titleHeight + contentHeight + 18
    local targetHeight = math_max(calculatedHeight, titleHeight + minSidebarHeight)
    local targetWidth = width

    cache.curWidth = cache.curWidth or targetWidth
    cache.curHeight = cache.curHeight or targetHeight

    local ft = FrameTime() * 10
    cache.curWidth = Lerp(ft, cache.curWidth, targetWidth)
    cache.curHeight = Lerp(ft, cache.curHeight, targetHeight)

    local panelHeight = cache.curHeight
    width = cache.curWidth

    local maxVisibleTabs = math_max(minVisibleTabs, math_floor((panelHeight - titleHeight - 24) / tabHeight))

    local dir = (pos - eyePos)
    dir:Normalize()
    local ang = dir:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90

    local distanceScale = math_Clamp(1 - (distance / (isLarge and 3000 or 2000)), 0.3, 1.5)
    local scale = renderParams.baseScale * distanceScale
    if isMassive then
        scale = scale * 0.6
    end
    scale = math_Clamp(scale, SED.MIN_SCALE, SED.MAX_SCALE)

    local frameHeightWorldUnits = panelHeight * scale
    local obbCenterLocal = (renderParams.obbMin + renderParams.obbMax) * 0.5
    local worldCenter = ent.LocalToWorld and ent:LocalToWorld(obbCenterLocal) or pos

    -- Use cached worldTopZ from render params (avoids 8x LocalToWorld for OBB corners)
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
        local ok, tr = pcall(util.TraceLine, { start = eyePos, endpos = drawPos, filter = SED.lpCache })
        if ok and tr and tr.Hit and tr.Entity == ent then
            drawPos = drawPos - horiz * (outwardAmount * 0.5)
        end
    end

    do
        local faceDir = (drawPos - eyePos)
        faceDir:Normalize()
        local newAng = faceDir:Angle()
        newAng.y = newAng.y - 90
        newAng.p = 0
        newAng.r = 90
        ang = newAng
    end

    local eyeToPanel = drawPos - eyePos
    if eyeToPanel:Length() < 10 then
        drawPos = eyePos + eyeToPanel:GetNormalized() * 50
    end

    local offsetX = -width / 2
    local offsetY = -panelHeight / 2

    -- Direct rendering (pcall wrapper removed for performance)
    cam_Start3D2D(drawPos, ang, scale)

    if currentLOD < 2 then
        surface_SetDrawColor(0, 0, 0, 150)
        surface_DrawRect(offsetX + 4, offsetY + 4, width, panelHeight)
    end

    draw_RoundedBox(8, offsetX, offsetY, width, panelHeight, currentLOD >= 2 and BG_COLOR_DISTANT or BG_COLOR)

    draw_RoundedBox(8, offsetX, offsetY, width, titleHeight, HEADER_COLOR)
    surface_SetDrawColor(25, 30, 40, 255)
    surface_DrawRect(offsetX, offsetY + titleHeight / 2, width, titleHeight / 2)

    surface_SetDrawColor(20, 24, 30, 255)
    surface_DrawRect(offsetX, offsetY + titleHeight, sidebarWidth, panelHeight - titleHeight)

    surface_SetDrawColor(35, 40, 50, 255)
    surface_DrawRect(offsetX + sidebarWidth, offsetY + titleHeight, 1, panelHeight - titleHeight)

    surface_SetDrawColor(60, 140, 220, 255)
    surface_DrawRect(offsetX, offsetY + titleHeight - 2, width, 2)

    if currentLOD < 2 then
        surface_SetDrawColor(60, 140, 220, 100)
        surface_DrawOutlinedRect(offsetX, offsetY, width, panelHeight, 1)
    end

    local title = isNPC and "Saved NPC" or "Saved Entity"
    local titleFont = currentLOD >= 2 and "Trebuchet18" or "Trebuchet24"
    draw_SimpleText(title, titleFont, offsetX + 12, offsetY + 6, WHITE,
        TEXT_ALIGN_LEFT,
        TEXT_ALIGN_TOP)

    if currentLOD < 2 then
        local subtitleClass = saved.class or saved.Class or saved.ClassName or "unknown"
        local subtitleID = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or saved.RareloadID
        local subtitle = subtitleClass
        if subtitleID then
            local idText = tostring(subtitleID)
            if #idText > 22 then
                idText = "..." .. string.sub(idText, -19)
            end
            subtitle = subtitle .. " | " .. idText
        end
        local hpBarW = math_min(210, width - 220)
        local subtitleMaxW = math_max(90, width - hpBarW - 40)
        surface_SetFont("Trebuchet18")
        subtitle = clipTextToWidth(subtitle, subtitleMaxW)

        draw_SimpleText(subtitle, "Trebuchet18", offsetX + 12, offsetY + 30, MINI_TEXT,
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_TOP)
    end

    local isVJBase = false
    if IsValid(ent) then
        isVJBase = ((ent.IsVJBaseSNPC == true) or (ent.VJ_ID_Living == true) or (ent.IsVJBaseSNPC_Human == true)) and
            (ent.Base ~= nil)
    elseif saved then
        isVJBase = (saved.IsVJBaseSNPC == true) or (saved.VJ_ID_Living == true) or (saved.IsVJBaseSNPC_Human == true)
    end

    if isNPC and isVJBase and currentLOD < 2 then
        surface_SetFont(titleFont)
        local titleW = surface_GetTextSize(title) or 0
        local badgeX = offsetX + 16 + titleW + 10
        -- Align Y coordinates properly instead of overlapping subtitle text
        local badgeY = offsetY + 6

        draw_RoundedBox(5, badgeX - 1, badgeY - 1, 44, 18, VJ_OUTER)
        draw_RoundedBox(4, badgeX, badgeY, 42, 16, VJ_INNER)

        draw_SimpleText("VJ", "Trebuchet18", badgeX + 21, badgeY + 8, VJ_TEXT_COLOR, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    if currentLOD < 2 then
        local maxHP = saved.MaxHealth or saved.maxHealth or saved.StartHealth or 0
        local curHP = saved.CurHealth or saved.health or saved.Health or 0
        local armor = saved.armor or saved.Armor or 0

        if maxHP > 0 then
            local barW = math_min(210, width - 220)
            local hpFrac = math_Clamp(curHP / maxHP, 0, 1)
            local bx = offsetX + width - barW - 14
            local by = offsetY + 7

            draw_RoundedBox(5, bx - 1, by - 1, barW + 2, 18, HP_OUTER)
            draw_RoundedBox(4, bx, by, barW, 16, HP_BG)

            local r, g = 100, 220
            if hpFrac < 0.5 then
                r = 220 + (hpFrac * 2) * -120
                g = 220
            elseif hpFrac >= 0.5 then
                r = 100
                g = 220 - (hpFrac - 0.5) * 2 * -80
            end

            -- Reuse pre-allocated color, mutate in place
            HP_FILL.r = r
            HP_FILL.g = g

            local fillW = (barW - 2) * hpFrac
            if fillW > 0 then
                draw_RoundedBox(4, bx + 1, by + 1, fillW, 14, HP_FILL)
                surface_SetDrawColor(255, 255, 255, 30)
                surface_DrawRect(bx + 1, by + 1, fillW, 7)
            end

            local hpText = curHP .. "/" .. maxHP .. " (" .. math_floor(hpFrac * 100) .. "%)"
            draw_SimpleText(hpText, "Trebuchet18", bx + barW / 2, by + 8, HP_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            if armor > 0 then
                local aby = by + 20
                local armorBarW = math_min(barW * 0.7, 140)
                local abx = bx + (barW - armorBarW) / 2

                draw_RoundedBox(4, abx - 1, aby - 1, armorBarW + 2, 12, ARMOR_OUTER)
                draw_RoundedBox(3, abx, aby, armorBarW, 10, ARMOR_BG)

                draw_RoundedBox(3, abx + 1, aby + 1, armorBarW - 2, 8, ARMOR_FILL)
                surface_SetDrawColor(150, 200, 255, 40)
                surface_DrawRect(abx + 1, aby + 1, armorBarW - 2, 4)

                draw_SimpleText("Armor: " .. armor, "Trebuchet18", abx + armorBarW / 2, aby + 5, ARMOR_TEXT,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end

    local tabStartY = offsetY + titleHeight + 12

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

    cache.sidebarScroll = cache.sidebarScroll or targetScroll
    cache.sidebarScroll = Lerp(ft, cache.sidebarScroll, targetScroll)

    local currentScrollPos = cache.sidebarScroll
    local startIndex = math_floor(currentScrollPos) + 1
    local endIndex = math_ceil(currentScrollPos + visibleCount)

    if startIndex < 1 then startIndex = 1 end
    if endIndex > #categories then endIndex = #categories end

    if currentScrollPos > 0.1 then
        draw_SimpleText("\226\150\178", "Trebuchet18", offsetX + sidebarWidth / 2, tabStartY - 8, ARROW_COLOR,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Stencil only when sidebar tabs overflow (saves GPU state changes when <= 4 categories)
    local useStencil = #categories > maxVisibleTabs
    if useStencil then
        render_SetStencilWriteMask(0xFF)
        render_SetStencilTestMask(0xFF)
        render_SetStencilReferenceValue(0)
        render_SetStencilCompareFunction(STENCIL_ALWAYS)
        render_SetStencilPassOperation(STENCIL_KEEP)
        render_SetStencilFailOperation(STENCIL_KEEP)
        render_SetStencilZFailOperation(STENCIL_KEEP)
        render_ClearStencil()

        render_SetStencilEnable(true)
        render_SetStencilReferenceValue(1)
        render_SetStencilCompareFunction(STENCIL_ALWAYS)
        render_SetStencilPassOperation(STENCIL_REPLACE)

        surface_DrawRect(offsetX, offsetY + titleHeight, sidebarWidth, panelHeight - titleHeight)

        render_SetStencilCompareFunction(STENCIL_EQUAL)
        render_SetStencilPassOperation(STENCIL_KEEP)
    end

    local activeCol = WHITE
    local foundActive = false
    for i, cat in ipairs(categories) do
        if cat[1] == activeCat then
            activeCol = safeTextColor(cat[3], WHITE)
            foundActive = true
            break
        end
    end

    if foundActive then
        local activeRelIndex = (activeIndex - 1) - currentScrollPos
        local activeTabY = tabStartY + activeRelIndex * tabHeight

        surface_SetDrawColor(activeCol.r, activeCol.g, activeCol.b, 40)
        surface_DrawRect(offsetX, activeTabY, sidebarWidth, tabHeight)

        surface_SetDrawColor(activeCol.r, activeCol.g, activeCol.b, 255)
        surface_DrawRect(offsetX, activeTabY, 3, tabHeight)
    end

    for i = startIndex, endIndex do
        local cat = categories[i]
        local catId, name, col = cat[1], cat[2], cat[3]
        local tabBaseColor = safeTextColor(col, TAB_INACTIVE)

        local relativeIndex = (i - 1) - currentScrollPos
        local tabX = offsetX
        local tabY = tabStartY + relativeIndex * tabHeight
        local active = (catId == activeCat)
        local lineCount = (cache.counts and cache.counts[catId]) or #(cache.data[catId] or {})
        local hasData = lineCount > 0

        surface_SetDrawColor(30, 35, 45, 100)
        surface_DrawRect(tabX + 4, tabY + tabHeight - 1, sidebarWidth - 8, 1)

        local textColor
        if active then
            textColor = hasData and tabBaseColor or TAB_EMPTY
        else
            textColor = hasData and TAB_INACTIVE or TAB_EMPTY
        end

        if hasData then
            surface_SetDrawColor(tabBaseColor.r, tabBaseColor.g, tabBaseColor.b, active and 170 or 90)
            surface_DrawRect(tabX + 8, tabY + tabHeight / 2 - 1, 3, 3)
        end

        draw_SimpleText(name, "Trebuchet18", tabX + 14, tabY + tabHeight / 2, textColor, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        local countColor
        if active then
            countColor = hasData and WHITE or TAB_COUNT_EMPTY
        else
            countColor = hasData and TAB_COUNT_INACTIVE or TAB_COUNT_EMPTY
        end
        draw_SimpleText(tostring(lineCount), "Trebuchet18", tabX + sidebarWidth - 8, tabY + tabHeight / 2,
            countColor,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    if useStencil then
        render_SetStencilEnable(false)
    end

    if currentScrollPos < (#categories - visibleCount - 0.1) then
        local arrowY = tabStartY + visibleCount * tabHeight + 8
        draw_SimpleText("\226\150\188", "Trebuchet18", offsetX + sidebarWidth / 2, arrowY, ARROW_COLOR, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    local startY = offsetY + titleHeight + 8
    surface_SetFont(contentFont)

    local contentOffsetX = sidebarWidth
    local labelX = offsetX + contentOffsetX + (currentLOD >= 2 and 12 or 16)

    local maxLabelW = cache.maxLabelWidths and cache.maxLabelWidths[activeCat] or 100
    local contentWidth = width - contentOffsetX - 28
    local labelMaxW = math_Clamp(math_min(maxLabelW, contentWidth * 0.44), 90, 260)
    local valuePadding = 16
    local valueX = labelX + labelMaxW + valuePadding

    local maxValueWidth = width - contentOffsetX - (valueX - (offsetX + contentOffsetX)) - 24
    if maxValueWidth < 90 then
        maxValueWidth = 90
    end

    local currentY = startY + 4

    for _, drawInfo in ipairs(itemsToDrawInfos) do
        local l = lines[drawInfo.logicalIndex]
        if not l then break end

        local wrappedValue = drawInfo.wrapLines
        local lineCount = drawInfo.linesNeeded
        local rowHeight = lineCount * lineHeight

        if currentLOD < 2 and (drawInfo.logicalIndex) % 2 == 0 then
            draw_RoundedBox(2, offsetX + contentOffsetX + 8, currentY - 2, width - contentOffsetX - 16, rowHeight + 4,
                ROW_ALT)
        end

        local labelText = ""
        if not drawInfo.isPartialStart then
            labelText = clipTextToWidth((l[1] or "") .. ":", labelMaxW)
            draw_SimpleText(labelText, contentFont, labelX, currentY + 3, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        for j, valueLine in ipairs(wrappedValue) do
            local valueColor = safeTextColor(l[3], LABEL_COLOR)
            draw_SimpleText(valueLine, contentFont, valueX, currentY + 3 + (j - 1) * lineHeight, valueColor,
                TEXT_ALIGN_LEFT,
                TEXT_ALIGN_TOP)
        end

        currentY = currentY + rowHeight + 4
    end

    if maxScrollLines > 0 and currentLOD < 2 then
        local barW = 6
        local barX = offsetX + width - barW - 8
        local barY = startY - 4
        local barH = contentHeight - 4

        draw_RoundedBox(3, barX, barY, barW, barH, SCROLL_BG)

        local handleH = math_max(20, barH * (renderedLogicalItems / #lines))
        local handleY = barY + (barH - handleH) * (currentScroll / maxScrollLines)
        draw_RoundedBox(3, barX, handleY, barW, handleH, SCROLL_HANDLE)

        surface_SetDrawColor(120, 180, 240, 80)
        surface_DrawRect(barX, handleY, barW, handleH / 2)
    end

    cam_End3D2D()

    -- Hit test
    local aimAng = SED.lpCache:EyeAngles()
    local panelCenter = Vector(drawPos.x, drawPos.y, drawPos.z)
    local toPanelAng = (panelCenter - SED.lpCache:EyePos()):Angle()
    local yawDiff = math_abs(math_AngleDifference(aimAng.y, toPanelAng.y))
    local isFocused = SED.InteractionState.active and SED.InteractionState.ent == ent
    local isCandidate = false

    local doHitTest = true
    if SED.HITTEST_ONLY_CANDIDATE and SED.CandidateEnt and SED.CandidateEnt ~= ent then
        doHitTest = false
    end

    if doHitTest then
        local eyePos2 = SED.lpCache:EyePos()
        local forward = SED.lpCache:EyeAngles():Forward()
        local panelNormal = (panelCenter - eyePos2):GetNormalized()
        local right = ang:Right()
        local up = ang:Up()

        local denom = forward:Dot(panelNormal)
        local lookAtPanel = false
        if math_abs(denom) > 1e-3 then
            local t = (panelCenter - eyePos2):Dot(panelNormal) / denom
            if t > 0 then
                local hitPos = eyePos2 + forward * t
                local rel = hitPos - panelCenter
                local x = rel:Dot(right)
                local y = rel:Dot(up)
                local halfW = (width * 0.5) * scale
                local halfH = (panelHeight * 0.5) * scale
                if math_abs(x) <= halfW and math_abs(y) <= halfH then
                    lookAtPanel = true
                end
            end
        end

        if lookAtPanel then
            SED.LookingAtPanelUntil = CurTime() + 0.03
        end

        if not SED.InteractionState.active and lookAtPanel then
            isCandidate = true
            SED.CandidateEnt = ent
            SED.CandidateIsNPC = isNPC
            SED.CandidateID = panelID
            SED.CandidateYawDiff = yawDiff
        end
    end

    if (isFocused or isCandidate) and currentLOD < 2 then
        local hintY = drawPos.z + (panelHeight * scale) / 2 + 10
        local hintPos = Vector(drawPos.x, drawPos.y, hintY)
        local hintScale = scale * 0.8

        cam_Start3D2D(hintPos, ang, hintScale)
        if isFocused then
            draw_SimpleText("INTERACT MODE", "Trebuchet18", 0, 0, HINT_INTERACT, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
            draw_SimpleText("Up/Down Tabs | Left/Right/MWheel Scroll | Shift+E Exit", "Trebuchet18",
                0, 20, HINT_CONTROLS, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif isCandidate then
            draw_SimpleText("Shift + E to Inspect", "Trebuchet18", 0, 0, HINT_CANDIDATE, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        cam_End3D2D()
    end
end
