-- SED panel rendering functions

function SED.DrawSavedPanel(ent, saved, isNPC)
    if not (IsValid(ent) and saved) then return end

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local pos = ent:GetPos()

    local renderParams = SED.CalculateEntityRenderParams(ent)
    if not renderParams then return end

    local distSqr = eyePos:DistToSqr(pos)
    if distSqr > renderParams.drawDistanceSqr then return end

    if SED.CULL_VIEW_CONE then
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

    local distance = math.sqrt(distSqr)
    local effectiveDistance = distance
    local isMediumDistant = effectiveDistance > (renderParams.isLarge and 800 or 400)
    local isDistant = effectiveDistance > (renderParams.isLarge and 1200 or 600)
    local isVeryDistant = effectiveDistance > (renderParams.isLarge and 1500 or 800)
    local currentLOD = isVeryDistant and 3 or (isDistant and 2 or (isMediumDistant and 1 or 0))
    
    -- LOD Logic for bounds
    do
        if renderParams.isLarge or renderParams.isMassive then
            local centerLocal = (renderParams.obbMin + renderParams.obbMax) * 0.5
            if ent.LocalToWorld then
                local wc = ent:LocalToWorld(centerLocal)
                local d = (eyePos - wc):Length()
                if d < effectiveDistance then effectiveDistance = d end
            end
            if currentLOD < 2 and ent.NearestPoint then
                local ok, np = pcall(ent.NearestPoint, ent, eyePos)
                if ok and isvector(np) then
                    local d2 = (eyePos - np):Length()
                    if d2 < effectiveDistance then effectiveDistance = d2 end
                end
            end
        end
    end

    -- Recalculate LOD based on refined distance
    isMediumDistant = effectiveDistance > (renderParams.isLarge and 800 or 400)
    isDistant = effectiveDistance > (renderParams.isLarge and 1200 or 600)
    isVeryDistant = effectiveDistance > (renderParams.isLarge and 1500 or 800)
    currentLOD = isVeryDistant and 3 or (isDistant and 2 or (isMediumDistant and 1 or 0))
    
    cache.lod = cache.lod or {}
    local previousLOD = cache.lod[activeCat]
    if previousLOD ~= nil and previousLOD ~= currentLOD then
        cache.widths[activeCat] = nil
    end
    cache.lod[activeCat] = currentLOD

    local maxVisibleLines = SED.MAX_VISIBLE_LINES
    if currentLOD == 3 then
        maxVisibleLines = math.min(10, SED.MAX_VISIBLE_LINES)
    elseif currentLOD == 2 then
        maxVisibleLines = math.min(20, SED.MAX_VISIBLE_LINES)
    elseif currentLOD == 1 then
        maxVisibleLines = math.min(30, SED.MAX_VISIBLE_LINES)
    end

    local lineHeight = currentLOD >= 2 and 16 or 18
    local titleHeight = currentLOD >= 2 and 28 or 36
    local tabHeight = currentLOD >= 2 and 24 or 32 -- Taller tabs for sidebar
    local sidebarWidth = currentLOD >= 2 and 80 or 110

    local width = cache.widths[activeCat] or 400
    if not cache.widths[activeCat] then
        local font = currentLOD >= 2 and "Trebuchet18" or "Trebuchet18"
        SED.surface_SetFont(font)
        width = 300
        local maxContentWidth = 0
        local maxLabelW = 0

        for i = 1, math.min(#lines, currentLOD == 0 and 15 or currentLOD == 1 and 10 or 5) do
            local l = lines[i]
            if l and l[1] and l[2] then
                local label = (l[1] or "") .. ":"
                local value = l[2] or ""

                local w1, h1 = SED.surface_GetTextSize(label)
                local w2, h2 = SED.surface_GetTextSize(value)
                w1 = w1 or 0
                w2 = w2 or 0
                
                maxLabelW = math.max(maxLabelW, w1)

                local lineContentWidth = w1 + w2 + (currentLOD >= 2 and 120 or 170)
                maxContentWidth = math.max(maxContentWidth, lineContentWidth)

                if w2 > (currentLOD >= 2 and 300 or 500) then
                    maxContentWidth = math.min(maxContentWidth, currentLOD >= 2 and 450 or 700)
                end
            end
        end

        width = math.max(width, maxContentWidth)
        
        -- Add sidebar width to the calculated content width
        width = width + sidebarWidth

        local maxWidth = currentLOD >= 2 and 600 or (renderParams.isLarge and 1000 or 850)
        local minWidth = currentLOD >= 2 and 300 or 450
        width = math.Clamp(width, minWidth, maxWidth)
        cache.widths[activeCat] = width
        cache.maxLabelWidths = cache.maxLabelWidths or {}
        cache.maxLabelWidths[activeCat] = maxLabelW
        cache._wrap = cache._wrap or {}
        cache._wrap[activeCat] = nil
    end

    local panelID = saved.id or (saved.class .. "?")
    local scrollTable = isNPC and SED.PanelScroll.npcs or SED.PanelScroll.entities
    local scrollKey = panelID .. "_" .. activeCat
    local maxScrollLines = math.max(0, #lines - maxVisibleLines)
    local currentScroll = math.min(scrollTable[scrollKey] or 0, maxScrollLines)
    scrollTable[scrollKey] = currentScroll

    local visibleLines = math.min(#lines - currentScroll, maxVisibleLines)
    local contentHeight = visibleLines * lineHeight + 12
    
    -- Ensure panel is tall enough for the sidebar tabs (showing max 3 at a time)
    local maxVisibleTabs = 3
    local visibleTabCount = math.min(#categories, maxVisibleTabs)
    local minSidebarHeight = visibleTabCount * tabHeight + 24 -- +24 for arrows padding
    
    local calculatedHeight = titleHeight + contentHeight + 18
    local targetHeight = math.max(calculatedHeight, titleHeight + minSidebarHeight)
    local targetWidth = width

    -- Smooth resize
    cache.curWidth = cache.curWidth or targetWidth
    cache.curHeight = cache.curHeight or targetHeight
    
    cache.curWidth = Lerp(FrameTime() * 10, cache.curWidth, targetWidth)
    cache.curHeight = Lerp(FrameTime() * 10, cache.curHeight, targetHeight)
    
    local panelHeight = cache.curHeight
    width = cache.curWidth

    local dir = (pos - eyePos)
    dir:Normalize()
    local ang = dir:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90

    local distanceScale = math.Clamp(1 - (distance / (renderParams.isLarge and 3000 or 2000)), 0.3, 1.5)
    local scale = renderParams.baseScale * distanceScale
    if renderParams.isMassive then
        scale = scale * 0.6
    end
    scale = math.Clamp(scale, SED.MIN_SCALE, SED.MAX_SCALE)

    local frameHeightWorldUnits = panelHeight * scale
    local obbCenterLocal = (renderParams.obbMin + renderParams.obbMax) * 0.5
    local worldCenter = ent.LocalToWorld and ent:LocalToWorld(obbCenterLocal) or pos

    local worldTop
    if ent.LocalToWorld then
        local min, max = renderParams.obbMin, renderParams.obbMax
        local cornersLocal = {
            Vector(min.x, min.y, min.z),
            Vector(min.x, min.y, max.z),
            Vector(min.x, max.y, min.z),
            Vector(min.x, max.y, max.z),
            Vector(max.x, min.y, min.z),
            Vector(max.x, min.y, max.z),
            Vector(max.x, max.y, min.z),
            Vector(max.x, max.y, max.z)
        }
        worldTop = ent:LocalToWorld(cornersLocal[1])
        for i = 2, 8 do
            local c = ent:LocalToWorld(cornersLocal[i])
            if c.z > worldTop.z then worldTop = c end
        end
    else
        local size = renderParams.obbMax - renderParams.obbMin
        worldTop = pos + Vector(0, 0, size.z)
    end

    local baseZ
    if renderParams.isMassive then
        baseZ = worldTop.z + renderParams.buffer + frameHeightWorldUnits * 0.5
    elseif renderParams.isLarge then
        baseZ = worldTop.z + renderParams.buffer * 0.6 + frameHeightWorldUnits * 0.5
    else
        baseZ = worldTop.z + renderParams.buffer * 0.4 + frameHeightWorldUnits * 0.5
    end

    local basePos = Vector(worldCenter.x, worldCenter.y, baseZ)

    local toCenter = worldCenter - eyePos
    local horiz = Vector(toCenter.x, toCenter.y, 0)
    if horiz:Length() < 0.001 then horiz = Vector(1, 0, 0) end
    horiz:Normalize()
    local outwardAmount = math.Clamp(renderParams.maxDimension * 0.35, 30, 600)
    local drawPos = basePos - horiz * outwardAmount

    if renderParams.isLarge or renderParams.isMassive then
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

    local renderOk = pcall(function()
        cam.Start3D2D(drawPos, ang, scale)

        -- Modern UI Style
        local bgAlpha = currentLOD >= 2 and 230 or 250
        local bgColor = Color(15, 18, 24, bgAlpha)
        local headerColor = Color(25, 30, 40, 255)
        local sidebarColor = Color(20, 24, 30, 255)
        local accentColor = Color(60, 140, 220, 255)

        -- Drop shadow
        if currentLOD < 2 then
            SED.surface_SetDrawColor(0, 0, 0, 150)
            surface.DrawRect(offsetX + 4, offsetY + 4, width, panelHeight)
        end

        -- Main Background
        SED.draw_RoundedBox(8, offsetX, offsetY, width, panelHeight, bgColor)

        -- Header Background
        SED.draw_RoundedBox(8, offsetX, offsetY, width, titleHeight, headerColor)
        -- Fix rounded corners at bottom of header
        SED.surface_SetDrawColor(headerColor.r, headerColor.g, headerColor.b, headerColor.a)
        surface.DrawRect(offsetX, offsetY + titleHeight/2, width, titleHeight/2)

        -- Sidebar Background
        SED.surface_SetDrawColor(sidebarColor.r, sidebarColor.g, sidebarColor.b, sidebarColor.a)
        surface.DrawRect(offsetX, offsetY + titleHeight, sidebarWidth, panelHeight - titleHeight)
        
        -- Sidebar Separator Line
        SED.surface_SetDrawColor(35, 40, 50, 255)
        surface.DrawRect(offsetX + sidebarWidth, offsetY + titleHeight, 1, panelHeight - titleHeight)

        -- Header Accent Line
        SED.surface_SetDrawColor(accentColor.r, accentColor.g, accentColor.b, accentColor.a)
        surface.DrawRect(offsetX, offsetY + titleHeight - 2, width, 2)

        -- Border
        if currentLOD < 2 then
            SED.surface_SetDrawColor(accentColor.r, accentColor.g, accentColor.b, 100)
            surface.DrawOutlinedRect(offsetX, offsetY, width, panelHeight, 1)
        end

        local title = isNPC and "Saved NPC" or "Saved Entity"
        local titleFont = currentLOD >= 2 and "Trebuchet18" or "Trebuchet24"
        SED.draw_SimpleText(title, titleFont, offsetX + 12, offsetY + titleHeight / 2 - 1, Color(255, 255, 255),
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)
        
        -- VJ Base badge
        local isVJBase = false
        if IsValid(ent) then
            isVJBase = ((ent.IsVJBaseSNPC == true) or (ent.VJ_ID_Living == true) or (ent.IsVJBaseSNPC_Human == true)) and (ent.Base ~= nil)
        elseif saved then
            isVJBase = (saved.IsVJBaseSNPC == true) or (saved.VJ_ID_Living == true) or (saved.IsVJBaseSNPC_Human == true)
        end

        if isNPC and isVJBase and currentLOD < 2 then
            local titleW = SED.surface_GetTextSize(title) or 0
            local badgeX = offsetX + 16 + titleW + 10
            local badgeY = offsetY + titleHeight / 2 - 9
            
            -- Badge background with glow
            SED.draw_RoundedBox(5, badgeX - 1, badgeY - 1, 44, 18, Color(40, 160, 100, 150))
            SED.draw_RoundedBox(4, badgeX, badgeY, 42, 16, Color(60, 200, 120, 220))
            
            -- Badge text
            SED.draw_SimpleText("VJ", "Trebuchet18", badgeX + 21, badgeY + 8, Color(255, 255, 255, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        if currentLOD < 2 then
            local maxHP = saved.MaxHealth or saved.maxHealth or 0
            local curHP = saved.CurHealth or saved.health or 0
            local armor = saved.armor or 0
            
            if maxHP > 0 then
                local barW = math.min(210, width - 220)
                local hpFrac = math.Clamp(curHP / maxHP, 0, 1)
                local bx = offsetX + width - barW - 14
                local by = offsetY + 9
                
                -- Health bar background with border
                SED.draw_RoundedBox(5, bx - 1, by - 1, barW + 2, 18, Color(60, 80, 100, 180))
                SED.draw_RoundedBox(4, bx, by, barW, 16, Color(25, 30, 38, 220))
                
                -- Health bar fill with smooth gradient (green > yellow > red)
                local r, g = 100, 220
                if hpFrac < 0.5 then
                    r = 220 + (hpFrac * 2) * -120
                    g = 220
                elseif hpFrac >= 0.5 then
                    r = 100
                    g = 220 - (hpFrac - 0.5) * 2 * -80
                end
                
                local fillW = (barW - 2) * hpFrac
                if fillW > 0 then
                    SED.draw_RoundedBox(4, bx + 1, by + 1, fillW, 14, Color(r, g, 70, 245))
                    -- Add shine effect on top half
                    SED.surface_SetDrawColor(255, 255, 255, 30)
                    surface.DrawRect(bx + 1, by + 1, fillW, 7)
                end
                
                -- Health text with better contrast
                local hpText = curHP .. "/" .. maxHP .. " (" .. math.floor(hpFrac * 100) .. "%)"
                SED.draw_SimpleText(hpText, "Trebuchet18", bx + barW / 2, by + 8, Color(245, 248, 252), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                
                -- Armor bar if present
                if armor > 0 then
                    local aby = by + 20
                    local armorBarW = math.min(barW * 0.7, 140)
                    local abx = bx + (barW - armorBarW) / 2
                    
                    -- Armor background
                    SED.draw_RoundedBox(4, abx - 1, aby - 1, armorBarW + 2, 12, Color(60, 90, 130, 180))
                    SED.draw_RoundedBox(3, abx, aby, armorBarW, 10, Color(25, 30, 40, 220))
                    
                    -- Armor fill
                    SED.draw_RoundedBox(3, abx + 1, aby + 1, armorBarW - 2, 8, Color(90, 150, 255, 230))
                    SED.surface_SetDrawColor(150, 200, 255, 40)
                    surface.DrawRect(abx + 1, aby + 1, armorBarW - 2, 4)
                    
                    -- NO EMOJI
                    SED.draw_SimpleText("Armor: " .. armor, "Trebuchet18", abx + armorBarW / 2, aby + 5, Color(240, 245, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end

        -- Sidebar Tabs
        local tabStartY = offsetY + titleHeight + 12 -- Start a bit lower to make room for up arrow
        
        -- Calculate visible range
        local activeIndex = 1
        for i, cat in ipairs(categories) do
            if cat[1] == activeCat then activeIndex = i break end
        end
        
        local maxVisibleTabs = 3
        local visibleCount = math.min(#categories, maxVisibleTabs)
        
        -- Calculate target scroll position (centered around active tab)
        local targetScroll = activeIndex - 2 -- Center the active tab (2nd position in 3 visible slots)
        
        -- Clamp target scroll
        if targetScroll < 0 then targetScroll = 0 end
        if targetScroll > #categories - visibleCount then targetScroll = #categories - visibleCount end
        
        -- Animate scroll position
        cache.sidebarScroll = cache.sidebarScroll or targetScroll
        cache.sidebarScroll = Lerp(FrameTime() * 10, cache.sidebarScroll, targetScroll)
        
        -- Use animated scroll for rendering
        local currentScrollPos = cache.sidebarScroll
        local startIndex = math.floor(currentScrollPos) + 1
        local endIndex = math.ceil(currentScrollPos + visibleCount)
        
        -- Clamp indices for safety
        if startIndex < 1 then startIndex = 1 end
        if endIndex > #categories then endIndex = #categories end

        -- Up Arrow
        if currentScrollPos > 0.1 then
             SED.draw_SimpleText("▲", "Trebuchet18", offsetX + sidebarWidth/2, tabStartY - 8, Color(150, 160, 170, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        -- Use Stencil to clip sidebar content
        render.SetStencilWriteMask( 0xFF )
        render.SetStencilTestMask( 0xFF )
        render.SetStencilReferenceValue( 0 )
        render.SetStencilCompareFunction( STENCIL_ALWAYS )
        render.SetStencilPassOperation( STENCIL_KEEP )
        render.SetStencilFailOperation( STENCIL_KEEP )
        render.SetStencilZFailOperation( STENCIL_KEEP )
        render.ClearStencil()

        render.SetStencilEnable( true )
        render.SetStencilReferenceValue( 1 )
        render.SetStencilCompareFunction( STENCIL_ALWAYS )
        render.SetStencilPassOperation( STENCIL_REPLACE )

        -- Draw mask (the sidebar area)
        surface.DrawRect(offsetX, offsetY + titleHeight, sidebarWidth, panelHeight - titleHeight)

        render.SetStencilCompareFunction( STENCIL_EQUAL )
        render.SetStencilPassOperation( STENCIL_KEEP )

        -- Draw Active Tab Background & Indicator (Animated)
        local activeCol = Color(255, 255, 255)
        local foundActive = false
        for i, cat in ipairs(categories) do
            if cat[1] == activeCat then
                activeCol = cat[3]
                foundActive = true
                break
            end
        end

        if foundActive then
             -- Calculate Y based on animated scroll position
             local activeRelIndex = (activeIndex - 1) - currentScrollPos
             local activeTabY = tabStartY + activeRelIndex * tabHeight
             
             SED.surface_SetDrawColor(activeCol.r, activeCol.g, activeCol.b, 40)
             surface.DrawRect(offsetX, activeTabY, sidebarWidth, tabHeight)
             
             SED.surface_SetDrawColor(activeCol.r, activeCol.g, activeCol.b, 255)
             surface.DrawRect(offsetX, activeTabY, 3, tabHeight)
        end

        for i = startIndex, endIndex do
            local cat = categories[i]
            local catId, name, col = cat[1], cat[2], cat[3]
            
            local relativeIndex = (i - 1) - currentScrollPos
            local tabX = offsetX
            local tabY = tabStartY + relativeIndex * tabHeight
            local active = (catId == activeCat)

            -- Tab Separator
            SED.surface_SetDrawColor(30, 35, 45, 100)
            surface.DrawRect(tabX + 4, tabY + tabHeight - 1, sidebarWidth - 8, 1)

            -- Tab text
            local tabFont = currentLOD >= 2 and "Trebuchet18" or "Trebuchet18"
            local textColor = active and col or Color(150, 160, 170, 200)
            
            -- Left align text in sidebar
            SED.draw_SimpleText(name, tabFont, tabX + 10, tabY + tabHeight / 2, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        
        render.SetStencilEnable( false )
        
        -- Down Arrow
        if currentScrollPos < (#categories - visibleCount - 0.1) then
             local arrowY = tabStartY + visibleCount * tabHeight + 8
             SED.draw_SimpleText("▼", "Trebuchet18", offsetX + sidebarWidth/2, arrowY, Color(150, 160, 170, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        local startY = offsetY + titleHeight + 8
        local contentFont = currentLOD >= 2 and "Trebuchet18" or "Trebuchet18"
        SED.surface_SetFont(contentFont)

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

            local textWidth = SED.surface_GetTextSize(text) or 0
            if textWidth <= maxWidth then
                return { text }
            end
            local cached = catWrap.lines[text]
            if cached then return cached end

            local words = string.Explode(" ", text)
            local lines = {}
            local currentLine = ""

            for _, word in ipairs(words) do
                local testLine = currentLine == "" and word or (currentLine .. " " .. word)
                local testWidth = SED.surface_GetTextSize(testLine) or 0

                if testWidth <= maxWidth then
                    currentLine = testLine
                else
                    if currentLine ~= "" then
                        table.insert(lines, currentLine)
                        currentLine = word
                    else
                        table.insert(lines, word)
                    end
                end
            end

            if currentLine ~= "" then
                table.insert(lines, currentLine)
            end
            local result = #lines > 0 and lines or { text }
            catWrap.lines[text] = result
            return result
        end

        -- Adjust content position for sidebar
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

            -- Row background (alternating with subtle highlight)
            if currentLOD < 2 and (i + currentScroll) % 2 == 0 then
                local bgHeight = lineCount * lineHeight
                SED.draw_RoundedBox(2, offsetX + contentOffsetX + 8, currentY - 3, width - contentOffsetX - 16, bgHeight + 4, Color(32, 38, 48, 100))
            end

            -- Label with colon
            local labelColor = Color(200, 210, 225, 255)
            SED.draw_SimpleText((l[1] or "") .. ":", contentFont, labelX, currentY, labelColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

            -- Value lines (wrapped)
            for j, valueLine in ipairs(wrappedValue) do
                local valueColor = l[3] or Color(240, 245, 250)
                SED.draw_SimpleText(valueLine, contentFont, valueX, currentY + (j - 1) * lineHeight, valueColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
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
            
            -- Scrollbar track
            SED.draw_RoundedBox(3, barX, barY, barW, barH, Color(25, 30, 40, 200))
            
            -- Scrollbar handle
            local handleH = math.max(20, barH * (visibleLines / #lines))
            local handleY = barY + (barH - handleH) * (currentScroll / maxScrollLines)
            SED.draw_RoundedBox(3, barX, handleY, barW, handleH, Color(80, 140, 200, 200))
            
            -- Handle highlight
            SED.surface_SetDrawColor(120, 180, 240, 80)
            surface.DrawRect(barX, handleY, barW, handleH / 2)
        end

        cam.End3D2D()
    end)

    if not renderOk then
        return
    end

    local aimAng = SED.lpCache:EyeAngles()
    local panelCenter = Vector(drawPos.x, drawPos.y, drawPos.z)
    local toPanelAng = (panelCenter - SED.lpCache:EyePos()):Angle()
    local yawDiff = math.abs(math.AngleDifference(aimAng.y, toPanelAng.y))
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
        local hintOk = pcall(function()
            local hintY = drawPos.z + (panelHeight * scale) / 2 + 10
            local hintPos = Vector(drawPos.x, drawPos.y, hintY)
            local hintScale = scale * 0.8

            cam.Start3D2D(hintPos, ang, hintScale)
            if isFocused then
                SED.draw_SimpleText("INTERACT MODE", "Trebuchet18", 0, 0, Color(255, 235, 190), TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
                SED.draw_SimpleText("Left/Right Tabs | Up/Down/MWheel Scroll | Shift+E Exit", "Trebuchet18",
                    0, 20, Color(225, 225, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            elseif isCandidate then
                SED.draw_SimpleText("Shift + E to Inspect", "Trebuchet18", 0, 0, Color(160, 210, 255), TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end
            cam.End3D2D()
        end)
    end
end

function SED.QueueAllSavedPanels()
    SED.EnsureSavedLookup()
    SED.RescanLate()

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local eyeForward = SED.lpCache:EyeAngles():Forward()
    local queueList = {}
    local listCount = 0
    local frameStartTime = SysTime()
    local invalidEntities = {}
    local invalidNPCs = {}

    for ent, id in pairs(SED.TrackedEntities) do
        if IsValid(ent) then
            local rec = SED.SAVED_ENTITIES_BY_ID[id]
            if rec then
                local entPos = ent:GetPos()
                local distSqr = eyePos:DistToSqr(entPos)
                local renderParams = SED.CalculateEntityRenderParams(ent)
                local maxDistSqr = renderParams and renderParams.drawDistanceSqr or SED.DRAW_DISTANCE_SQR

                local withinView = true
                if SED.CULL_VIEW_CONE then
                    local dir = entPos - eyePos
                    local len = dir:Length()
                    if len > 0 then
                        dir:Mul(1 / len)
                        local dot = dir:Dot(eyeForward)
                        withinView = (dot >= SED.FOV_COS_THRESHOLD) or (distSqr <= SED.NEARBY_DIST_SQR)
                    end
                end

                if distSqr <= maxDistSqr and withinView then
                    listCount = listCount + 1
                    queueList[listCount] = {
                        ent = ent,
                        saved = rec,
                        isNPC = false,
                        distSqr = distSqr,
                        renderParams = renderParams,
                        pos = entPos
                    }
                end
            end
        else
            invalidEntities[#invalidEntities + 1] = ent
        end
    end

    for npc, id in pairs(SED.TrackedNPCs) do
        if IsValid(npc) then
            local rec = SED.SAVED_NPCS_BY_ID[id]
            if rec then
                local entPos = npc:GetPos()
                local distSqr = eyePos:DistToSqr(entPos)

                local renderParams = SED.CalculateEntityRenderParams(npc)
                local maxDistSqr = renderParams and renderParams.drawDistanceSqr or SED.DRAW_DISTANCE_SQR

                local withinView = true
                if SED.CULL_VIEW_CONE then
                    local dir = entPos - eyePos
                    local len = dir:Length()
                    if len > 0 then
                        dir:Mul(1 / len)
                        local dot = dir:Dot(eyeForward)
                        withinView = (dot >= SED.FOV_COS_THRESHOLD) or (distSqr <= SED.NEARBY_DIST_SQR)
                    end
                end

                if distSqr <= maxDistSqr and withinView then
                    listCount = listCount + 1
                    queueList[listCount] = {
                        ent = npc,
                        saved = rec,
                        isNPC = true,
                        distSqr = distSqr,
                        renderParams = renderParams,
                        pos = entPos
                    }
                end
            end
        else
            invalidNPCs[#invalidNPCs + 1] = npc
        end
    end

    for i = 1, #invalidEntities do
        SED.TrackedEntities[invalidEntities[i]] = nil
        local entIndex = invalidEntities[i]:EntIndex()
        if SED.EntityBoundsCache and entIndex then
            SED.EntityBoundsCache[entIndex] = nil
        end
    end
    for i = 1, #invalidNPCs do
        SED.TrackedNPCs[invalidNPCs[i]] = nil
        local entIndex = invalidNPCs[i]:EntIndex()
        if SED.EntityBoundsCache and entIndex then
            SED.EntityBoundsCache[entIndex] = nil
        end
    end

    if listCount == 0 then return end


    if not SED.InteractionState.active then
        local aimAng = SED.lpCache:EyeAngles()
        local yawThreshold = 12
        local distThresholdSqr = 40000

        local bestIdx = nil
        local bestDist = math.huge
        local bestYaw = math.huge

        for i = 1, listCount do
            local item = queueList[i]
            if item and item.ent and IsValid(item.ent) then
                local toEntAng = (item.pos - eyePos):Angle()
                local yawDiff = math.abs(math.AngleDifference(aimAng.y, toEntAng.y))
                local dSqr = item.renderParams and
                    select(1, SED.GetNearestDistanceSqr(item.ent, eyePos, item.renderParams))
                    or item.distSqr or eyePos:DistToSqr(item.ent:GetPos())

                local withinYaw = yawDiff < yawThreshold
                local withinDist = dSqr <
                    math.min(distThresholdSqr,
                        (item.renderParams and item.renderParams.drawDistanceSqr) or SED.DRAW_DISTANCE_SQR)

                if withinYaw and withinDist then
                    if (dSqr < bestDist) or (dSqr == bestDist and yawDiff < bestYaw) then
                        bestIdx = i
                        bestDist = dSqr
                        bestYaw = yawDiff
                    end
                end
            end
        end

        if bestIdx then
            local item = queueList[bestIdx]
            local saved = item and item.saved
            if saved then
                SED.CandidateEnt = item.ent
                SED.CandidateIsNPC = item.isNPC
                SED.CandidateID = saved.id or (saved.class .. "?")
                SED.CandidateYawDiff = bestYaw
            end
        end
    end

    table.sort(queueList, function(a, b) return a.distSqr < b.distSqr end)
    local maxQueue = math.min(listCount, SED.MAX_DRAW_PER_FRAME)

    for i = 1, maxQueue do
        local item = queueList[i]
        if item then
            local renderFunction = function()
                SED.DrawSavedPanel(item.ent, item.saved, item.isNPC)
            end
            RARELOAD.DepthRenderer.AddRenderItem(item.pos, renderFunction, "entity")
        end
    end
end

function SED.DrawAllSavedPanels()
    SED.EnsureSavedLookup()
    SED.RescanLate()

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local eyeForward = SED.lpCache:EyeAngles():Forward()
    local drawList = {}
    local listCount = 0
    local frameStartTime = SysTime()
    local invalidEntities = {}
    local invalidNPCs = {}

    for ent, id in pairs(SED.TrackedEntities) do
        if IsValid(ent) then
            local rec = SED.SAVED_ENTITIES_BY_ID[id]
            if rec then
                local entPos = ent:GetPos()
                local distSqr = eyePos:DistToSqr(entPos)
                local renderParams = SED.CalculateEntityRenderParams(ent)
                local maxDistSqr = renderParams and renderParams.drawDistanceSqr or SED.DRAW_DISTANCE_SQR

                local withinView = true
                if SED.CULL_VIEW_CONE then
                    local dir = entPos - eyePos
                    local len = dir:Length()
                    if len > 0 then
                        dir:Mul(1 / len)
                        local dot = dir:Dot(eyeForward)
                        withinView = (dot >= SED.FOV_COS_THRESHOLD) or (distSqr <= SED.NEARBY_DIST_SQR)
                    end
                end

                if distSqr <= maxDistSqr and withinView then
                    listCount = listCount + 1
                    drawList[listCount] = {
                        ent = ent,
                        saved = rec,
                        isNPC = false,
                        distSqr = distSqr,
                        renderParams = renderParams
                    }
                end
            end
        else
            invalidEntities[#invalidEntities + 1] = ent
        end
    end

    for npc, id in pairs(SED.TrackedNPCs) do
        if IsValid(npc) then
            local rec = SED.SAVED_NPCS_BY_ID[id]
            if rec then
                local entPos = npc:GetPos()
                local distSqr = eyePos:DistToSqr(entPos)

                local renderParams = SED.CalculateEntityRenderParams(npc)
                local maxDistSqr = renderParams and renderParams.drawDistanceSqr or SED.DRAW_DISTANCE_SQR

                local withinView = true
                if SED.CULL_VIEW_CONE then
                    local dir = entPos - eyePos
                    local len = dir:Length()
                    if len > 0 then
                        dir:Mul(1 / len)
                        local dot = dir:Dot(eyeForward)
                        withinView = (dot >= SED.FOV_COS_THRESHOLD) or (distSqr <= SED.NEARBY_DIST_SQR)
                    end
                end

                if distSqr <= maxDistSqr and withinView then
                    listCount = listCount + 1
                    drawList[listCount] = {
                        ent = npc,
                        saved = rec,
                        isNPC = true,
                        distSqr = distSqr,
                        renderParams = renderParams
                    }
                end
            end
        else
            invalidNPCs[#invalidNPCs + 1] = npc
        end
    end

    for i = 1, #invalidEntities do
        SED.TrackedEntities[invalidEntities[i]] = nil
        local entIndex = invalidEntities[i]:EntIndex()
        if SED.EntityBoundsCache and entIndex then
            SED.EntityBoundsCache[entIndex] = nil
        end
    end
    for i = 1, #invalidNPCs do
        SED.TrackedNPCs[invalidNPCs[i]] = nil
        local entIndex = invalidNPCs[i]:EntIndex()
        if SED.EntityBoundsCache and entIndex then
            SED.EntityBoundsCache[entIndex] = nil
        end
    end

    if listCount == 0 then return end

    table.sort(drawList, function(a, b) return a.distSqr < b.distSqr end)

    local timeBudget = SED.FrameRenderBudget
    local maxDraw = math.min(listCount, SED.MAX_DRAW_PER_FRAME)

    if SED.LastFrameRenderCount > SED.MAX_DRAW_PER_FRAME * 0.8 then
        maxDraw = math.max(10, maxDraw - 5)
    end

    local renderCount = 0
    local renderStartTime = SysTime()

    for i = 1, maxDraw do
        if i % 5 == 0 then
            local currentTime = SysTime()
            if (currentTime - renderStartTime) > timeBudget then
                break
            end
        end

        local item = drawList[i]
        if item then
            SED.DrawSavedPanel(item.ent, item.saved, item.isNPC)
            renderCount = renderCount + 1
        end
    end

    SED.LastFrameRenderCount = renderCount

    local totalFrameTime = SysTime() - frameStartTime
    if totalFrameTime > SED.FrameRenderBudget * 1.5 then
        SED.FrameRenderBudget = math.max(0.001, SED.FrameRenderBudget * 0.95)
    elseif totalFrameTime < SED.FrameRenderBudget * 0.5 then
        SED.FrameRenderBudget = math.min(0.008, SED.FrameRenderBudget * 1.05)
    end
end
