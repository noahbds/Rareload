-- SED panel interaction and hint rendering.

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer_interaction.lua\n")
    return
end

local cam_Start3D2D = RS.cam_Start3D2D
local cam_End3D2D = RS.cam_End3D2D
local draw_SimpleText = RS.draw_SimpleText
local math_abs = RS.math_abs
local math_AngleDifference = RS.math_AngleDifference

local HINT_INTERACT = RS.HINT_INTERACT
local HINT_CONTROLS = RS.HINT_CONTROLS
local HINT_CANDIDATE = RS.HINT_CANDIDATE

function SED.PanelRendererHandleInteraction(ctx)
    local ent = ctx.ent
    local panelID = ctx.panelID
    local isNPC = ctx.isNPC
    local drawPos = ctx.drawPos
    local panelHeight = ctx.panelHeight
    local scale = ctx.scale
    local ang = ctx.ang
    local width = ctx.width
    local currentLOD = ctx.currentLOD

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
            draw_SimpleText("INTERACT MODE", "Trebuchet18", 0, 0, HINT_INTERACT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw_SimpleText("Up/Down Tabs | Left/Right/MWheel Scroll | Shift+E Exit", "Trebuchet18", 0, 20, HINT_CONTROLS,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif isCandidate then
            draw_SimpleText("Shift + E to Inspect", "Trebuchet18", 0, 0, HINT_CANDIDATE, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_CENTER)
        end
        cam_End3D2D()
    end
end
