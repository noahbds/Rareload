-- Tier 1: lightweight panel renderer.

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer_mini.lua\n")
    return
end

local cam_Start3D2D = RS.cam_Start3D2D
local cam_End3D2D = RS.cam_End3D2D
local surface_SetDrawColor = RS.surface_SetDrawColor
local surface_DrawRect = RS.surface_DrawRect
local draw_RoundedBox = RS.draw_RoundedBox
local draw_SimpleText = RS.draw_SimpleText
local math_sqrt = RS.math_sqrt
local math_Clamp = RS.math_Clamp

local MINI_BG = RS.MINI_BG
local MINI_TEXT = RS.MINI_TEXT
local WHITE = RS.WHITE
local HP_BG = RS.HP_BG
local HP_FILL = RS.HP_FILL

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

    local className = saved.class or saved.Class or saved.ClassName or saved.NPCName or "Unknown"
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
