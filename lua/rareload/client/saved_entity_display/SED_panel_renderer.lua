-- SED panel rendering functions (optimized)

-- Pre-allocated color constants (avoid 20+ Color() allocations per panel per frame)
local BG_COLOR = Color(15, 18, 24, 250)
local BG_COLOR_DISTANT = Color(15, 18, 24, 230)
local HEADER_COLOR = Color(25, 30, 40, 255)
local ACCENT_COLOR_ALPHA = Color(60, 140, 220, 100)
local WHITE = Color(255, 255, 255)
local LABEL_COLOR = Color(200, 210, 225, 255)
local VALUE_COLOR = Color(240, 245, 250)
local TAB_INACTIVE = Color(150, 160, 170, 200)
local ARROW_COLOR = Color(150, 160, 170, 100)
local SCROLL_BG = Color(25, 30, 40, 200)
local SCROLL_HANDLE = Color(80, 140, 200, 200)
local ROW_ALT = Color(32, 38, 48, 100)
local VJ_OUTER = Color(40, 160, 100, 150)
local VJ_INNER = Color(60, 200, 120, 220)
local VJ_TEXT_COLOR = Color(255, 255, 255, 250)
local HP_OUTER = Color(60, 80, 100, 180)
local HP_BG = Color(25, 30, 38, 220)
local HP_TEXT = Color(245, 248, 252)
local HP_FILL = Color(100, 220, 70, 245)
local ARMOR_OUTER = Color(60, 90, 130, 180)
local ARMOR_BG = Color(25, 30, 40, 220)
local ARMOR_FILL = Color(90, 150, 255, 230)
local ARMOR_TEXT = Color(240, 245, 255)
local HINT_INTERACT = Color(255, 235, 190)
local HINT_CONTROLS = Color(225, 225, 230)
local HINT_CANDIDATE = Color(160, 210, 255)
local MINI_BG = Color(15, 18, 24, 220)
local MINI_TEXT = Color(180, 200, 220, 220)
local MARKER_BG = Color(15, 18, 24, 180)
local MARKER_TEXT = Color(160, 180, 200, 200)

-- Cached function references (avoid repeated table lookups in hot path)
local cam_Start3D2D = cam.Start3D2D
local cam_End3D2D = cam.End3D2D
local surface_SetDrawColor = surface.SetDrawColor
local surface_DrawRect = surface.DrawRect
local surface_DrawOutlinedRect = surface.DrawOutlinedRect
local surface_SetFont = surface.SetFont
local surface_GetTextSize = surface.GetTextSize
local draw_RoundedBox = draw.RoundedBox
local draw_SimpleText = draw.SimpleText
local render_SetStencilWriteMask = render.SetStencilWriteMask
local render_SetStencilTestMask = render.SetStencilTestMask
local render_SetStencilReferenceValue = render.SetStencilReferenceValue
local render_SetStencilCompareFunction = render.SetStencilCompareFunction
local render_SetStencilPassOperation = render.SetStencilPassOperation
local render_SetStencilFailOperation = render.SetStencilFailOperation
local render_SetStencilZFailOperation = render.SetStencilZFailOperation
local render_ClearStencil = render.ClearStencil
local render_SetStencilEnable = render.SetStencilEnable
local math_sqrt = math.sqrt
local math_max = math.max
local math_min = math.min
local math_Clamp = math.Clamp
local math_abs = math.abs
local math_floor = math.floor
local math_ceil = math.ceil
local math_AngleDifference = math.AngleDifference
local string_Explode = string.Explode

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
    local lines = cache.data[activeCat] or {}

    if #lines == 0 then
        lines = { { "Nothing to show here", "Reason : The npc " .. (ent:GetClass() or "Unknown") .. " has no data about " .. activeCat, SED.THEME.text } }
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
        maxVisibleLines = math_min(10, SED.MAX_VISIBLE_LINES)
    elseif currentLOD == 2 then
        maxVisibleLines = math_min(20, SED.MAX_VISIBLE_LINES)
    elseif currentLOD == 1 then
        maxVisibleLines = math_min(30, SED.MAX_VISIBLE_LINES)
    end

    local lineHeight = currentLOD >= 2 and 16 or 18
    local titleHeight = currentLOD >= 2 and 28 or 36
    local tabHeight = currentLOD >= 2 and 24 or 32
    local sidebarWidth = currentLOD >= 2 and 80 or 110

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
        cache.widths[activeCat] = width
        cache.maxLabelWidths = cache.maxLabelWidths or {}
        cache.maxLabelWidths[activeCat] = maxLabelW
        cache._wrap = cache._wrap or {}
        cache._wrap[activeCat] = nil
    end

    local panelID = saved.id or (saved.class .. "?")
    local scrollTable = isNPC and SED.PanelScroll.npcs or SED.PanelScroll.entities
    local scrollKey = panelID .. "_" .. activeCat
    local maxScrollLines = math_max(0, #lines - maxVisibleLines)
    local currentScroll = math_min(scrollTable[scrollKey] or 0, maxScrollLines)
    scrollTable[scrollKey] = currentScroll

    local visibleLines = math_min(#lines - currentScroll, maxVisibleLines)
    local contentHeight = visibleLines * lineHeight + 12
    
    local maxVisibleTabs = 3
    local visibleTabCount = math_min(#categories, maxVisibleTabs)
    local minSidebarHeight = visibleTabCount * tabHeight + 24
    
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
    surface_DrawRect(offsetX, offsetY + titleHeight/2, width, titleHeight/2)

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
    draw_SimpleText(title, titleFont, offsetX + 12, offsetY + titleHeight / 2 - 1, WHITE,
        TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
    
    local isVJBase = false
    if IsValid(ent) then
        isVJBase = ((ent.IsVJBaseSNPC == true) or (ent.VJ_ID_Living == true) or (ent.IsVJBaseSNPC_Human == true)) and (ent.Base ~= nil)
    elseif saved then
        isVJBase = (saved.IsVJBaseSNPC == true) or (saved.VJ_ID_Living == true) or (saved.IsVJBaseSNPC_Human == true)
    end

    if isNPC and isVJBase and currentLOD < 2 then
        local titleW = surface_GetTextSize(title) or 0
        local badgeX = offsetX + 16 + titleW + 10
        local badgeY = offsetY + titleHeight / 2 - 9
        
        draw_RoundedBox(5, badgeX - 1, badgeY - 1, 44, 18, VJ_OUTER)
        draw_RoundedBox(4, badgeX, badgeY, 42, 16, VJ_INNER)
        
        draw_SimpleText("VJ", "Trebuchet18", badgeX + 21, badgeY + 8, VJ_TEXT_COLOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    if currentLOD < 2 then
        local maxHP = saved.MaxHealth or saved.maxHealth or 0
        local curHP = saved.CurHealth or saved.health or 0
        local armor = saved.armor or 0
        
        if maxHP > 0 then
            local barW = math_min(210, width - 220)
            local hpFrac = math_Clamp(curHP / maxHP, 0, 1)
            local bx = offsetX + width - barW - 14
            local by = offsetY + 9
            
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
                
                draw_SimpleText("Armor: " .. armor, "Trebuchet18", abx + armorBarW / 2, aby + 5, ARMOR_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end

    local tabStartY = offsetY + titleHeight + 12
    
    local activeIndex = 1
    for i, cat in ipairs(categories) do
        if cat[1] == activeCat then activeIndex = i break end
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
         draw_SimpleText("\226\150\178", "Trebuchet18", offsetX + sidebarWidth/2, tabStartY - 8, ARROW_COLOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Stencil only when sidebar tabs overflow (saves GPU state changes when <= 3 categories)
    local useStencil = #categories > maxVisibleTabs
    if useStencil then
        render_SetStencilWriteMask( 0xFF )
        render_SetStencilTestMask( 0xFF )
        render_SetStencilReferenceValue( 0 )
        render_SetStencilCompareFunction( STENCIL_ALWAYS )
        render_SetStencilPassOperation( STENCIL_KEEP )
        render_SetStencilFailOperation( STENCIL_KEEP )
        render_SetStencilZFailOperation( STENCIL_KEEP )
        render_ClearStencil()

        render_SetStencilEnable( true )
        render_SetStencilReferenceValue( 1 )
        render_SetStencilCompareFunction( STENCIL_ALWAYS )
        render_SetStencilPassOperation( STENCIL_REPLACE )

        surface_DrawRect(offsetX, offsetY + titleHeight, sidebarWidth, panelHeight - titleHeight)

        render_SetStencilCompareFunction( STENCIL_EQUAL )
        render_SetStencilPassOperation( STENCIL_KEEP )
    end

    local activeCol = WHITE
    local foundActive = false
    for i, cat in ipairs(categories) do
        if cat[1] == activeCat then
            activeCol = cat[3]
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
        
        local relativeIndex = (i - 1) - currentScrollPos
        local tabX = offsetX
        local tabY = tabStartY + relativeIndex * tabHeight
        local active = (catId == activeCat)

        surface_SetDrawColor(30, 35, 45, 100)
        surface_DrawRect(tabX + 4, tabY + tabHeight - 1, sidebarWidth - 8, 1)

        local textColor = active and col or TAB_INACTIVE
        
        draw_SimpleText(name, "Trebuchet18", tabX + 10, tabY + tabHeight / 2, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    
    if useStencil then
        render_SetStencilEnable( false )
    end
    
    if currentScrollPos < (#categories - visibleCount - 0.1) then
         local arrowY = tabStartY + visibleCount * tabHeight + 8
         draw_SimpleText("\226\150\188", "Trebuchet18", offsetX + sidebarWidth/2, arrowY, ARROW_COLOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local startY = offsetY + titleHeight + 8
    local contentFont = "Trebuchet18"
    surface_SetFont(contentFont)

    local function WrapText(text, maxWidth)
        if not text or text == "" then return { text } end
        local wrapCache = cache._wrap or {}
        cache._wrap = wrapCache
        wrapCache[activeCat] = wrapCache[activeCat] or { width = maxWidth, lines = {} }
        local catWrap = wrapCache[activeCat]
        if catWrap.width ~= maxWidth then
            catWrap.width = maxWidth
            catWrap.lines = {}
        end

        local textWidth = surface_GetTextSize(text) or 0
        if textWidth <= maxWidth then
            return { text }
        end
        local cached = catWrap.lines[text]
        if cached then return cached end

        local words = string_Explode(" ", text)
        local wrapLines = {}
        local currentLine = ""

        for _, word in ipairs(words) do
            local testLine = currentLine == "" and word or (currentLine .. " " .. word)
            local testWidth = surface_GetTextSize(testLine) or 0

            if testWidth <= maxWidth then
                currentLine = testLine
            else
                if currentLine ~= "" then
                    wrapLines[#wrapLines + 1] = currentLine
                    currentLine = word
                else
                    wrapLines[#wrapLines + 1] = word
                end
            end
        end

        if currentLine ~= "" then
            wrapLines[#wrapLines + 1] = currentLine
        end
        local result = #wrapLines > 0 and wrapLines or { text }
        catWrap.lines[text] = result
        return result
    end

    local contentOffsetX = sidebarWidth
    local labelX = offsetX + contentOffsetX + (currentLOD >= 2 and 12 or 16)
    
    local maxLabelW = cache.maxLabelWidths and cache.maxLabelWidths[activeCat] or 100
    local valuePadding = 24
    local valueX = labelX + maxLabelW + valuePadding
    
    local maxValueWidth = width - contentOffsetX - (valueX - (offsetX + contentOffsetX)) - 24
    
    local currentY = startY
    local renderedLines = 0

    for i = 1, visibleLines do
        local l = lines[currentScroll + i]
        if not l then break end

        local wrappedValue = WrapText(l[2] or "", maxValueWidth)
        local lineCount = #wrappedValue

        if renderedLines + lineCount > visibleLines then
            lineCount = visibleLines - renderedLines
            wrappedValue = { unpack(wrappedValue, 1, lineCount) }
        end

        if currentLOD < 2 and (i + currentScroll) % 2 == 0 then
            local bgHeight = lineCount * lineHeight
            draw_RoundedBox(2, offsetX + contentOffsetX + 8, currentY - 3, width - contentOffsetX - 16, bgHeight + 4, ROW_ALT)
        end

        draw_SimpleText((l[1] or "") .. ":", contentFont, labelX, currentY, LABEL_COLOR, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        for j, valueLine in ipairs(wrappedValue) do
            local valueColor = l[3] or VALUE_COLOR
            draw_SimpleText(valueLine, contentFont, valueX, currentY + (j - 1) * lineHeight, valueColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        currentY = currentY + lineCount * lineHeight
        renderedLines = renderedLines + lineCount

        if renderedLines >= visibleLines then break end
    end

    if maxScrollLines > 0 and currentLOD < 2 then
        local barW = 6
        local barX = offsetX + width - barW - 8
        local barY = startY - 4
        local barH = contentHeight - 4
        
        draw_RoundedBox(3, barX, barY, barW, barH, SCROLL_BG)
        
        local handleH = math_max(20, barH * (visibleLines / #lines))
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
            draw_SimpleText("Left/Right Tabs | Up/Down/MWheel Scroll | Shift+E Exit", "Trebuchet18",
                0, 20, HINT_CONTROLS, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif isCandidate then
            draw_SimpleText("Shift + E to Inspect", "Trebuchet18", 0, 0, HINT_CANDIDATE, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        cam_End3D2D()
    end
end

-- ============================================================
-- Tier 1: Mini panel — lightweight tag with class name + HP bar
-- ~5-8 draw calls instead of 40+. No BuildPanelData, no tabs,
-- no sidebar, no stencil, no hit-test, no text wrapping.
-- ============================================================
function SED.DrawMiniPanel(ent, saved, isNPC, renderParams, distSqr)
    if not (IsValid(ent) and saved) then return end

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local pos = ent:GetPos()
    local distance = math_sqrt(distSqr)

    local worldTopZ = renderParams and renderParams.worldTopZ
    if not worldTopZ then
        worldTopZ = pos.z + (renderParams and renderParams.size and renderParams.size.z or 20)
    end

    local drawPos = Vector(pos.x, pos.y, worldTopZ + 20)

    local dir = (drawPos - eyePos)
    dir:Normalize()
    local ang = dir:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90

    local scale = math_Clamp(0.08 - distance * 0.00003, 0.03, 0.08)

    local className = saved.class or "Unknown"
    local title = isNPC and "Saved NPC" or "Saved Entity"

    local maxHP = isNPC and (saved.MaxHealth or saved.maxHealth or 0) or 0
    local curHP = isNPC and (saved.CurHealth or saved.health or 0) or 0
    local w, h = 240, 52
    if maxHP > 0 then h = 68 end

    local ox, oy = -w / 2, -h / 2

    cam_Start3D2D(drawPos, ang, scale)

    draw_RoundedBox(6, ox, oy, w, h, MINI_BG)

    surface_SetDrawColor(60, 140, 220, 200)
    surface_DrawRect(ox, oy, w, 2)

    draw_SimpleText(title, "Trebuchet18", ox + 8, oy + 10, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw_SimpleText(className, "Trebuchet18", ox + 8, oy + 28, MINI_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    if maxHP > 0 then
        local barW = w - 16
        local hpFrac = math_Clamp(curHP / maxHP, 0, 1)
        local bx, by = ox + 8, oy + 48

        draw_RoundedBox(3, bx, by, barW, 12, HP_BG)

        local fillW = (barW - 2) * hpFrac
        if fillW > 0 then
            HP_FILL.r = hpFrac > 0.5 and 100 or 220
            HP_FILL.g = 220
            draw_RoundedBox(3, bx + 1, by + 1, fillW, 10, HP_FILL)
        end
    end

    cam_End3D2D()
end

-- ============================================================
-- Tier 2: Marker — minimal colored tag, just class name
-- ~3 draw calls. Absolute minimum rendering.
-- ============================================================
function SED.DrawMarker(ent, saved, renderParams, distSqr)
    if not (IsValid(ent) and saved) then return end

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local pos = ent:GetPos()
    local distance = math_sqrt(distSqr)

    local worldTopZ = renderParams and renderParams.worldTopZ
    if not worldTopZ then
        worldTopZ = pos.z + (renderParams and renderParams.size and renderParams.size.z or 20)
    end

    local drawPos = Vector(pos.x, pos.y, worldTopZ + 15)

    local dir = (drawPos - eyePos)
    dir:Normalize()
    local ang = dir:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90

    local scale = math_Clamp(0.06 - distance * 0.00002, 0.02, 0.06)

    local className = saved.class or "?"
    local w, h = 110, 26
    local ox, oy = -w / 2, -h / 2

    cam_Start3D2D(drawPos, ang, scale)

    draw_RoundedBox(4, ox, oy, w, h, MARKER_BG)

    surface_SetDrawColor(60, 140, 220, 150)
    surface_DrawRect(ox, oy, w, 2)

    draw_SimpleText(className, "Trebuchet18", 0, oy + 13, MARKER_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    cam_End3D2D()
end
