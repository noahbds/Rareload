-- Tier 2: minimal marker renderer.

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer_marker.lua\n")
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

local MARKER_BG = RS.MARKER_BG
local MARKER_TEXT = RS.MARKER_TEXT

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

    local className = saved.class or saved.Class or saved.ClassName or saved.NPCName or "?"
    local w, h = 110, 26
    local ox, oy = -w / 2, -h / 2

    cam_Start3D2D(drawPos, ang, scale)

    draw_RoundedBox(4, ox, oy, w, h, MARKER_BG)

    surface_SetDrawColor(60, 140, 220, 150)
    surface_DrawRect(ox, oy, w, 2)

    draw_SimpleText(className, "Trebuchet18", 0, oy + 13, MARKER_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    cam_End3D2D()
end
