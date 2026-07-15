local RS = SED.Require("RenderShared", "rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer_draw.lua\n")
    return
end

local BG_COLOR                   = RS.BG_COLOR
local HEADER_COLOR               = RS.HEADER_COLOR
local WHITE                      = RS.WHITE
local LABEL_COLOR                = RS.LABEL_COLOR
local TAB_INACTIVE               = RS.TAB_INACTIVE
local TAB_EMPTY                  = RS.TAB_EMPTY
local TAB_COUNT_INACTIVE         = RS.TAB_COUNT_INACTIVE
local TAB_COUNT_EMPTY            = RS.TAB_COUNT_EMPTY
local ARROW_COLOR                = RS.ARROW_COLOR
local SCROLL_BG                  = RS.SCROLL_BG
local SCROLL_HANDLE              = RS.SCROLL_HANDLE
local ROW_ALT                    = RS.ROW_ALT
local VJ_OUTER                   = RS.VJ_OUTER
local VJ_INNER                   = RS.VJ_INNER
local VJ_TEXT_COLOR              = RS.VJ_TEXT_COLOR
local HP_OUTER                   = RS.HP_OUTER
local HP_BG                      = RS.HP_BG
local HP_TEXT                    = RS.HP_TEXT
local HP_FILL                    = RS.HP_FILL
local ARMOR_OUTER                = RS.ARMOR_OUTER
local ARMOR_BG                   = RS.ARMOR_BG
local ARMOR_FILL                 = RS.ARMOR_FILL
local ARMOR_TEXT                 = RS.ARMOR_TEXT
local MINI_TEXT                  = RS.MINI_TEXT

local cam_Start3D2D              = RS.cam_Start3D2D
local cam_End3D2D                = RS.cam_End3D2D
local surface_SetDrawColor       = RS.surface_SetDrawColor
local surface_DrawRect           = RS.surface_DrawRect
local surface_DrawOutlinedRect   = RS.surface_DrawOutlinedRect
local surface_SetFont            = RS.surface_SetFont
local surface_GetTextSize        = RS.surface_GetTextSize
local draw_RoundedBox            = RS.draw_RoundedBox
local draw_SimpleText            = RS.draw_SimpleText
local math_max                   = RS.math_max
local math_min                   = RS.math_min
local math_Clamp                 = RS.math_Clamp
local math_floor                 = RS.math_floor
local math_ceil                  = RS.math_ceil
local clipTextToWidth            = RS.clipTextToWidth
local safeTextColor              = RS.safeTextColor
local surface_SetMaterial        = surface.SetMaterial
local surface_DrawTexturedRectUV = surface.DrawTexturedRectUV

local function L(key, ...)
    if RARELOAD and RARELOAD.L then return RARELOAD.L(key, ...) end
    return key
end

local function DrawContent(ctx, ox, oy)
    local ent                  = ctx.ent
    local saved                = ctx.saved
    local isNPC                = ctx.isNPC
    local cache                = ctx.cache
    local categories           = ctx.categories
    local activeCat            = ctx.activeCat
    local lines                = ctx.lines
    local titleHeight          = ctx.titleHeight
    local tabHeight            = ctx.tabHeight
    local sidebarWidth         = ctx.sidebarWidth
    local width                = ctx.width
    local panelHeight          = ctx.panelHeight
    local currentScrollPos     = ctx.currentScrollPos
    local visibleCount         = ctx.visibleCount
    local maxVisibleTabs       = ctx.maxVisibleTabs
    local itemsToDrawInfos     = ctx.itemsToDrawInfos
    local maxScrollLines       = ctx.maxScrollLines
    local renderedLogicalItems = ctx.renderedLogicalItems
    local contentHeight        = ctx.contentHeight

    local tabStartY = oy + titleHeight + 12

    draw_RoundedBox(8, ox, oy, width, panelHeight, BG_COLOR)

    draw_RoundedBox(8, ox, oy, width, titleHeight, HEADER_COLOR)
    surface_SetDrawColor(25, 30, 40, 255)
    surface_DrawRect(ox, oy + titleHeight / 2, width, titleHeight / 2)

    surface_SetDrawColor(20, 24, 30, 255)
    surface_DrawRect(ox, oy + titleHeight, sidebarWidth, panelHeight - titleHeight)

    surface_SetDrawColor(35, 40, 50, 255)
    surface_DrawRect(ox + sidebarWidth, oy + titleHeight, 1, panelHeight - titleHeight)

    surface_SetDrawColor(60, 140, 220, 255)
    surface_DrawRect(ox, oy + titleHeight - 2, width, 2)

    surface_SetDrawColor(60, 140, 220, 100)
    surface_DrawOutlinedRect(ox, oy, width, panelHeight, 1)

    local title = isNPC and L("sed.saved_npc") or L("sed.saved_entity")
    if saved and saved._isPhantom and saved._phantomTitle then
        title = saved._phantomTitle
    end

    draw_SimpleText(title, "Trebuchet24", ox + 12, oy + 6, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    local subtitleID = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or saved.RareloadID
    local subtitle   = subtitleID and tostring(subtitleID) or L("sed.unknown_id")

    local maxHP = tonumber(saved.MaxHealth or saved.maxHealth or saved.StartHealth) or 0
    local hpBarReserve = 0
    if maxHP > 0 then
        hpBarReserve = math_min(210, width - 220) + 16
    end

    local subtitleMaxW = math_max(120, width - hpBarReserve - 28)
    surface_SetFont("Trebuchet18")
    subtitle = clipTextToWidth(subtitle, subtitleMaxW)
    draw_SimpleText(subtitle, "Trebuchet18", ox + 12, oy + 30, MINI_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    local isVJBase = false
    if IsValid(ent) then
        isVJBase = ((ent.IsVJBaseSNPC == true) or (ent.VJ_ID_Living == true) or (ent.IsVJBaseSNPC_Human == true)) and
            (ent.Base ~= nil)
    elseif saved then
        isVJBase = (saved.IsVJBaseSNPC == true) or (saved.VJ_ID_Living == true) or (saved.IsVJBaseSNPC_Human == true)
    end

    if isNPC and isVJBase then
        surface_SetFont("Trebuchet24")
        local titleW  = surface_GetTextSize(title) or 0
        local badgeX  = ox + 16 + titleW + 10
        local badgeY  = oy + 6

        draw_RoundedBox(5, badgeX - 1, badgeY - 1, 44, 18, VJ_OUTER)
        draw_RoundedBox(4, badgeX, badgeY, 42, 16, VJ_INNER)
        draw_SimpleText("VJ", "Trebuchet18", badgeX + 21, badgeY + 8, VJ_TEXT_COLOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    do
        local curHP = saved.CurHealth or saved.health or saved.Health or 0
        local armor = saved.armor or saved.Armor or 0

        if maxHP > 0 then
            local barW   = math_min(210, width - 220)
            local hpFrac = math_Clamp(curHP / maxHP, 0, 1)
            local bx     = ox + width - barW - 14
            local by     = oy + 7

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
                local aby       = by + 20
                local armorBarW = math_min(barW * 0.7, 140)
                local abx       = bx + (barW - armorBarW) / 2

                draw_RoundedBox(4, abx - 1, aby - 1, armorBarW + 2, 12, ARMOR_OUTER)
                draw_RoundedBox(3, abx, aby, armorBarW, 10, ARMOR_BG)

                draw_RoundedBox(3, abx + 1, aby + 1, armorBarW - 2, 8, ARMOR_FILL)
                surface_SetDrawColor(150, 200, 255, 40)
                surface_DrawRect(abx + 1, aby + 1, armorBarW - 2, 4)

                draw_SimpleText(L("sed.armor", armor), "Trebuchet18", abx + armorBarW / 2, aby + 5, ARMOR_TEXT,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end

    local startIndex = math_floor(currentScrollPos) + 1
    local endIndex   = math_ceil(currentScrollPos + visibleCount)

    if startIndex < 1 then startIndex = 1 end
    if endIndex > #categories then endIndex = #categories end

    if currentScrollPos > 0.1 then
        draw_SimpleText("\226\150\178", "Trebuchet18", ox + sidebarWidth / 2, tabStartY - 8, ARROW_COLOR,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local activeCol   = WHITE
    local foundActive = false
    local activeIndex = ctx.activeIndex
    for _, cat in ipairs(categories) do
        if cat[1] == activeCat then
            activeCol  = safeTextColor(cat[3], WHITE)
            foundActive = true
            break
        end
    end

    if foundActive then
        local activeRelIndex = (activeIndex - 1) - currentScrollPos
        local activeTabY     = tabStartY + activeRelIndex * tabHeight

        surface_SetDrawColor(activeCol.r, activeCol.g, activeCol.b, 40)
        surface_DrawRect(ox, activeTabY, sidebarWidth, tabHeight)

        surface_SetDrawColor(activeCol.r, activeCol.g, activeCol.b, 255)
        surface_DrawRect(ox, activeTabY, 3, tabHeight)
    end

    for i = startIndex, endIndex do
        local cat   = categories[i]
        local catId, name, col = cat[1], cat[2], cat[3]
        local tabBaseColor = safeTextColor(col, TAB_INACTIVE)

        local relativeIndex = (i - 1) - currentScrollPos
        local tabX = ox
        local tabY = tabStartY + relativeIndex * tabHeight
        local active    = (catId == activeCat)
        local lineCount = (cache.counts and cache.counts[catId]) or #(cache.data[catId] or {})
        local hasData   = lineCount > 0

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

        draw_SimpleText(L(name), "Trebuchet18", tabX + 14, tabY + tabHeight / 2, textColor, TEXT_ALIGN_LEFT,
            TEXT_ALIGN_CENTER)

        local countColor
        if active then
            countColor = hasData and WHITE or TAB_COUNT_EMPTY
        else
            countColor = hasData and TAB_COUNT_INACTIVE or TAB_COUNT_EMPTY
        end
        draw_SimpleText(tostring(lineCount), "Trebuchet18", tabX + sidebarWidth - 8, tabY + tabHeight / 2, countColor,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    if currentScrollPos < (#categories - visibleCount - 0.1) then
        local arrowY = tabStartY + visibleCount * tabHeight + 8
        draw_SimpleText("\226\150\188", "Trebuchet18", ox + sidebarWidth / 2, arrowY, ARROW_COLOR, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    local startY         = oy + titleHeight + 8
    surface_SetFont(ctx.contentFont)

    local contentOffsetX = sidebarWidth
    local labelX         = ox + contentOffsetX + 16

    local maxLabelW      = cache.maxLabelWidths and cache.maxLabelWidths[activeCat] or 100
    local contentWidth   = width - contentOffsetX - 28
    local labelMaxW      = math_Clamp(math_min(maxLabelW, contentWidth * 0.44), 90, 260)
    local valuePadding   = 16
    local valueX         = labelX + labelMaxW + valuePadding

    local currentY = startY + 4

    for _, drawInfo in ipairs(itemsToDrawInfos) do
        local l = lines[drawInfo.logicalIndex]
        if not l then break end

        local wrappedValue = drawInfo.wrapLines
        local lineCount    = drawInfo.linesNeeded
        local rowHeight    = lineCount * ctx.lineHeight

        if (drawInfo.logicalIndex) % 2 == 0 then
            draw_RoundedBox(2, ox + contentOffsetX + 8, currentY - 2, width - contentOffsetX - 16, rowHeight + 4,
                ROW_ALT)
        end

        if not drawInfo.isPartialStart then
            local labelText = clipTextToWidth((l[1] or "") .. ":", labelMaxW)
            draw_SimpleText(labelText, ctx.contentFont, labelX, currentY + 3, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        for j, valueLine in ipairs(wrappedValue) do
            local valueColor = safeTextColor(l[3], LABEL_COLOR)
            draw_SimpleText(valueLine, ctx.contentFont, valueX, currentY + 3 + (j - 1) * ctx.lineHeight, valueColor,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end

        currentY = currentY + rowHeight + 4
    end

    if maxScrollLines > 0 then
        local barW    = 6
        local barX    = ox + width - barW - 8
        local barY    = startY - 4
        local barH    = contentHeight - 4

        draw_RoundedBox(3, barX, barY, barW, barH, SCROLL_BG)

        local handleH = math_max(20, barH * (renderedLogicalItems / #lines))
        local handleY = barY + (barH - handleH) * (ctx.currentScroll / maxScrollLines)
        draw_RoundedBox(3, barX, handleY, barW, handleH, SCROLL_HANDLE)

        surface_SetDrawColor(120, 180, 240, 80)
        surface_DrawRect(barX, handleY, barW, handleH / 2)
    end
end

function SED.PanelRendererDraw(ctx)
    local w = ctx.width
    local h = ctx.panelHeight
    local ox = ctx.offsetX
    local oy = ctx.offsetY
    local RTT = SED.RTT

    local rtMat, uMax, vMax
    if RTT and ctx.bakeSig then
        rtMat, uMax, vMax = RTT.GetMat(ctx.bakeSig)
        if not rtMat then
            rtMat, uMax, vMax = RTT.BakePanel(ctx.bakeSig, w, h, function()
                DrawContent(ctx, 0, 0)
            end)
        end
    end

    cam_Start3D2D(ctx.drawPos, ctx.ang, ctx.scale)

    surface_SetDrawColor(0, 0, 0, 150)
    surface_DrawRect(ox + 4, oy + 4, w, h)

    if rtMat then
        surface_SetDrawColor(255, 255, 255, 255)
        surface_SetMaterial(rtMat)
        surface_DrawTexturedRectUV(ox, oy, w, h, 0, 0, uMax, vMax)
    else
        DrawContent(ctx, ox, oy)
    end

    cam_End3D2D()
end
