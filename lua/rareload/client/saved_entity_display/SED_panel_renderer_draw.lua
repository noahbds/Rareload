-- SED panel drawing routines.

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer_draw.lua\n")
    return
end

local BG_COLOR = RS.BG_COLOR
local BG_COLOR_DISTANT = RS.BG_COLOR_DISTANT
local HEADER_COLOR = RS.HEADER_COLOR
local WHITE = RS.WHITE
local LABEL_COLOR = RS.LABEL_COLOR
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
local MINI_TEXT = RS.MINI_TEXT

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
local math_max = RS.math_max
local math_min = RS.math_min
local math_Clamp = RS.math_Clamp
local math_floor = RS.math_floor
local math_ceil = RS.math_ceil
local clipTextToWidth = RS.clipTextToWidth
local safeTextColor = RS.safeTextColor

function SED.PanelRendererDraw(ctx)
    local ent = ctx.ent
    local saved = ctx.saved
    local isNPC = ctx.isNPC
    local cache = ctx.cache
    local categories = ctx.categories
    local activeCat = ctx.activeCat
    local lines = ctx.lines
    local currentLOD = ctx.currentLOD
    local titleHeight = ctx.titleHeight
    local tabHeight = ctx.tabHeight
    local sidebarWidth = ctx.sidebarWidth
    local width = ctx.width
    local panelHeight = ctx.panelHeight
    local scale = ctx.scale
    local ang = ctx.ang
    local drawPos = ctx.drawPos
    local offsetX = ctx.offsetX
    local offsetY = ctx.offsetY
    local currentScrollPos = ctx.currentScrollPos
    local visibleCount = ctx.visibleCount
    local tabStartY = ctx.tabStartY
    local maxVisibleTabs = ctx.maxVisibleTabs
    local itemsToDrawInfos = ctx.itemsToDrawInfos
    local maxScrollLines = ctx.maxScrollLines
    local renderedLogicalItems = ctx.renderedLogicalItems
    local contentHeight = ctx.contentHeight

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
    draw_SimpleText(title, titleFont, offsetX + 12, offsetY + 6, WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

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

        draw_SimpleText(subtitle, "Trebuchet18", offsetX + 12, offsetY + 30, MINI_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
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
        local badgeY = offsetY + 6

        draw_RoundedBox(5, badgeX - 1, badgeY - 1, 44, 18, VJ_OUTER)
        draw_RoundedBox(4, badgeX, badgeY, 42, 16, VJ_INNER)

        draw_SimpleText("VJ", "Trebuchet18", badgeX + 21, badgeY + 8, VJ_TEXT_COLOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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

    local startIndex = math_floor(currentScrollPos) + 1
    local endIndex = math_ceil(currentScrollPos + visibleCount)

    if startIndex < 1 then startIndex = 1 end
    if endIndex > #categories then endIndex = #categories end

    if currentScrollPos > 0.1 then
        draw_SimpleText("\226\150\178", "Trebuchet18", offsetX + sidebarWidth / 2, tabStartY - 8, ARROW_COLOR,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

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
    local activeIndex = ctx.activeIndex
    for _, cat in ipairs(categories) do
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
        draw_SimpleText(tostring(lineCount), "Trebuchet18", tabX + sidebarWidth - 8, tabY + tabHeight / 2, countColor,
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
    surface_SetFont(ctx.contentFont)

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
        local rowHeight = lineCount * ctx.lineHeight

        if currentLOD < 2 and (drawInfo.logicalIndex) % 2 == 0 then
            draw_RoundedBox(2, offsetX + contentOffsetX + 8, currentY - 2, width - contentOffsetX - 16, rowHeight + 4,
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

    if maxScrollLines > 0 and currentLOD < 2 then
        local barW = 6
        local barX = offsetX + width - barW - 8
        local barY = startY - 4
        local barH = contentHeight - 4

        draw_RoundedBox(3, barX, barY, barW, barH, SCROLL_BG)

        local handleH = math_max(20, barH * (renderedLogicalItems / #lines))
        local handleY = barY + (barH - handleH) * (ctx.currentScroll / maxScrollLines)
        draw_RoundedBox(3, barX, handleY, barW, handleH, SCROLL_HANDLE)

        surface_SetDrawColor(120, 180, 240, 80)
        surface_DrawRect(barX, handleY, barW, handleH / 2)
    end

    cam_End3D2D()
end
