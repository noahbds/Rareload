-- Shared renderer constants and utility helpers for SED panel rendering.

SED = SED or {}
SED.RenderShared = SED.RenderShared or {}

local RS = SED.RenderShared
if RS._initialized then return end

RS.BG_COLOR = Color(15, 18, 24, 250)
RS.BG_COLOR_DISTANT = Color(15, 18, 24, 230)
RS.HEADER_COLOR = Color(25, 30, 40, 255)
RS.WHITE = Color(255, 255, 255)
RS.LABEL_COLOR = Color(200, 210, 225, 255)
RS.VALUE_COLOR = Color(240, 245, 250)
RS.TAB_INACTIVE = Color(150, 160, 170, 200)
RS.TAB_EMPTY = Color(105, 112, 122, 170)
RS.TAB_COUNT_INACTIVE = Color(170, 180, 190, 180)
RS.TAB_COUNT_EMPTY = Color(120, 125, 132, 130)
RS.ARROW_COLOR = Color(150, 160, 170, 100)
RS.SCROLL_BG = Color(25, 30, 40, 200)
RS.SCROLL_HANDLE = Color(80, 140, 200, 200)
RS.ROW_ALT = Color(40, 47, 60, 160)
RS.VJ_OUTER = Color(40, 160, 100, 150)
RS.VJ_INNER = Color(60, 200, 120, 220)
RS.VJ_TEXT_COLOR = Color(255, 255, 255, 250)
RS.HP_OUTER = Color(60, 80, 100, 180)
RS.HP_BG = Color(25, 30, 38, 220)
RS.HP_TEXT = Color(245, 248, 252)
RS.HP_FILL = Color(100, 220, 70, 245)
RS.ARMOR_OUTER = Color(60, 90, 130, 180)
RS.ARMOR_BG = Color(25, 30, 40, 220)
RS.ARMOR_FILL = Color(90, 150, 255, 230)
RS.ARMOR_TEXT = Color(240, 245, 255)
RS.HINT_INTERACT = Color(255, 235, 190)
RS.HINT_CONTROLS = Color(225, 225, 230)
RS.HINT_CANDIDATE = Color(255, 255, 255, 255)
RS.HINT_INTERACT_BG = Color(18, 22, 30, 210)
RS.HINT_CONTROLS_BG = Color(18, 22, 30, 210)
RS.HINT_CANDIDATE_BG = Color(18, 22, 30, 210)
RS.MINI_BG = Color(15, 18, 24, 220)
RS.MINI_TEXT = Color(180, 200, 220, 220)
RS.MARKER_BG = Color(15, 18, 24, 180)
RS.MARKER_TEXT = Color(160, 180, 200, 200)

RS.cam_Start3D2D = cam.Start3D2D
RS.cam_End3D2D = cam.End3D2D
RS.surface_SetDrawColor = surface.SetDrawColor
RS.surface_DrawRect = surface.DrawRect
RS.surface_DrawOutlinedRect = surface.DrawOutlinedRect
RS.surface_SetFont = surface.SetFont
RS.surface_GetTextSize = surface.GetTextSize
RS.draw_RoundedBox = draw.RoundedBox
RS.draw_SimpleText = draw.SimpleText
RS.render_SetStencilWriteMask = render.SetStencilWriteMask
RS.render_SetStencilTestMask = render.SetStencilTestMask
RS.render_SetStencilReferenceValue = render.SetStencilReferenceValue
RS.render_SetStencilCompareFunction = render.SetStencilCompareFunction
RS.render_SetStencilPassOperation = render.SetStencilPassOperation
RS.render_SetStencilFailOperation = render.SetStencilFailOperation
RS.render_SetStencilZFailOperation = render.SetStencilZFailOperation
RS.render_ClearStencil = render.ClearStencil
RS.render_SetStencilEnable = render.SetStencilEnable
RS.math_sqrt = math.sqrt
RS.math_max = math.max
RS.math_min = math.min
RS.math_Clamp = math.Clamp
RS.math_abs = math.abs
RS.math_floor = math.floor
RS.math_ceil = math.ceil
RS.math_AngleDifference = math.AngleDifference
RS.string_Explode = string.Explode

local type = type
local function isColorLike(value)
    return type(value) == "table" and value.r and value.g and value.b
end

function RS.safeTextColor(value, fallback)
    if isColorLike(value) then
        return value
    end
    return fallback
end

RS._clipCache = {}

function RS.clipTextToWidth(text, maxWidth)
    local t = tostring(text or "")
    if t == "" or maxWidth <= 0 then return "" end

    local cacheKey = t .. "_" .. maxWidth
    if RS._clipCache[cacheKey] then return RS._clipCache[cacheKey] end

    local w = RS.surface_GetTextSize(t) or 0
    if w <= maxWidth then
        RS._clipCache[cacheKey] = t
        return t
    end

    local ellipsis = "..."
    local ellipsisW = RS.surface_GetTextSize(ellipsis) or 0
    if ellipsisW >= maxWidth then
        RS._clipCache[cacheKey] = ellipsis
        return ellipsis
    end

    local result = t
    while #result > 0 do
        result = string.sub(result, 1, #result - 1)
        if (RS.surface_GetTextSize(result) or 0) + ellipsisW <= maxWidth then
            local finalRes = result .. ellipsis
            RS._clipCache[cacheKey] = finalRes
            return finalRes
        end
    end

    RS._clipCache[cacheKey] = ellipsis
    return ellipsis
end

RS._initialized = true
