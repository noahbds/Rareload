-- SED panel rendering functions

function SED.DrawSavedPanel(ent, saved, isNPC)
    if not (IsValid(ent) and saved) then return end

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local eyeForward = SED.lpCache:EyeAngles():Forward()
    local eyeForward = SED.lpCache:EyeAngles():Forward()
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
    local tabHeight = currentLOD >= 2 and 18 or 22

    local width = cache.widths[activeCat] or 360
    if not cache.widths[activeCat] then
        local font = currentLOD >= 2 and "Trebuchet18" or "Trebuchet18"
        SED.surface_SetFont(font)
        width = 300
        local maxContentWidth = 0

        for i = 1, math.min(#lines, currentLOD == 0 and 15 or currentLOD == 1 and 10 or 5) do
            local l = lines[i]
            if l and l[1] and l[2] then
                local label = (l[1] or "") .. ":"
                local value = l[2] or ""

                local w1, h1 = SED.surface_GetTextSize(label)
                local w2, h2 = SED.surface_GetTextSize(value)
                w1 = w1 or 0
                w2 = w2 or 0

                local lineContentWidth = w1 + w2 + (currentLOD >= 2 and 120 or 170)
                maxContentWidth = math.max(maxContentWidth, lineContentWidth)

                if w2 > (currentLOD >= 2 and 300 or 500) then
                    maxContentWidth = math.min(maxContentWidth, currentLOD >= 2 and 450 or 700)
                end
            end
        end

        width = math.max(width, maxContentWidth)

        local minTabWidth = currentLOD >= 2 and 40 or 60
        local minWidthForTabs = #categories * minTabWidth
        width = math.max(width, minWidthForTabs)

        local maxWidth = currentLOD >= 2 and 500 or (renderParams.isLarge and 900 or 750)
        local minWidth = currentLOD >= 2 and 250 or 340
        width = math.Clamp(width, minWidth, maxWidth)
        cache.widths[activeCat] = width
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
    local panelHeight = titleHeight + tabHeight + contentHeight + 18

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

        if currentLOD < 2 then
            SED.surface_SetDrawColor(0, 0, 0, 130)
            surface.DrawRect(offsetX + 4, offsetY + 4, width, panelHeight)
        end

        local bgAlpha = currentLOD >= 2 and 200 or 240
        SED.draw_RoundedBox(currentLOD >= 2 and 6 or 10, offsetX, offsetY, width, panelHeight, Color(15, 18, 26, bgAlpha))

        if currentLOD < 2 then
            SED.draw_RoundedBox(10, offsetX + 2, offsetY + 2, width - 4, panelHeight - 4, Color(26, 30, 40, 245))

            for i = 0, 1 do
                SED.surface_SetDrawColor(SED.THEME.border.r, SED.THEME.border.g, SED.THEME.border.b, 170 - i * 90)
                surface.DrawOutlinedRect(offsetX + i, offsetY + i, width - i * 2, panelHeight - i * 2, 1)
            end
        end

        SED.surface_SetDrawColor(SED.THEME.header.r, SED.THEME.header.g, SED.THEME.header.b, bgAlpha)
        surface.DrawRect(offsetX, offsetY, width, titleHeight)

        local title = isNPC and "Saved NPC" or "Saved Entity"
        local titleFont = currentLOD >= 2 and "Trebuchet18" or "Trebuchet24"
        SED.draw_SimpleText(title, titleFont, offsetX + 12, offsetY + titleHeight / 2, Color(240, 240, 255),
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        if currentLOD < 2 then
            local maxHP = saved.maxHealth or 0
            local curHP = saved.health or 0
            if maxHP > 0 then
                local barW = math.min(180, width - 200)
                local hpFrac = math.Clamp(curHP / maxHP, 0, 1)
                local bx = offsetX + width - barW - 16
                local by = offsetY + 8
                SED.draw_RoundedBox(4, bx, by, barW, 14, Color(35, 40, 52, 190))
                SED.draw_RoundedBox(4, bx + 1, by + 1, (barW - 2) * hpFrac, 12,
                    Color(120 + 100 * (1 - hpFrac), 220 * hpFrac, 90, 230))
                SED.draw_SimpleText(curHP .. "/" .. maxHP, "Trebuchet18", bx + barW / 2, by + 7, Color(230, 230, 240),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        local tabY = offsetY + titleHeight
        local tabWidth = width / #categories
        for i, cat in ipairs(categories) do
            local catId, name, col = cat[1], cat[2], cat[3]
            local tabX = offsetX + (i - 1) * tabWidth
            local active = (catId == activeCat)

            SED.surface_SetDrawColor(col.r * (active and 0.6 or 0.25), col.g * (active and 0.6 or 0.25),
                col.b * (active and 0.6 or 0.25), active and 230 or 130)
            surface.DrawRect(tabX, tabY, tabWidth, tabHeight)

            if active and currentLOD < 2 then
                SED.surface_SetDrawColor(col.r, col.g, col.b, 255)
                surface.DrawOutlinedRect(tabX, tabY, tabWidth, tabHeight, 1)
            end

            local tabFont = currentLOD >= 2 and "Trebuchet18" or "Trebuchet18"
            SED.draw_SimpleText(name, tabFont, tabX + tabWidth / 2, tabY + tabHeight / 2,
                active and Color(255, 255, 255) or Color(205, 205, 205), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        local startY = tabY + tabHeight + 6
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

        local labelX = offsetX + (currentLOD >= 2 and 8 or 14)
        local valueX = offsetX + (currentLOD >= 2 and 120 or 180)
        local maxValueWidth = width - valueX + offsetX - 20
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
                SED.surface_SetDrawColor(40, 48, 62, 95)
                surface.DrawRect(offsetX + 6, currentY - 2, width - 12, bgHeight)
            end

            SED.draw_SimpleText((l[1] or "") .. ":", contentFont, labelX, currentY, Color(210, 210, 215), TEXT_ALIGN_LEFT,
                TEXT_ALIGN_TOP)

            for j, valueLine in ipairs(wrappedValue) do
                SED.draw_SimpleText(valueLine, contentFont, valueX, currentY + (j - 1) * lineHeight,
                    l[3] or SED.THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end

            currentY = currentY + lineCount * lineHeight
            renderedLines = renderedLines + lineCount

            if renderedLines >= visibleLines then break end
        end

        if maxScrollLines > 0 and currentLOD < 2 then
            local barW = 5
            local barX = offsetX + width - barW - 10
            local barY = startY - 2
            local barH = contentHeight - 4
            SED.draw_RoundedBox(3, barX, barY, barW, barH, Color(30, 34, 44, 185))
            local handleH = math.max(16, barH * (visibleLines / #lines))
            local handleY = barY + (barH - handleH) * (currentScroll / maxScrollLines)
            SED.draw_RoundedBox(3, barX, handleY, barW, handleH, Color(90, 150, 230, 220))
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
