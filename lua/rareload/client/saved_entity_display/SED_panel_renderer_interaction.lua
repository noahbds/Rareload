-- SED_panel_renderer_interaction.lua  (refactored)


local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer_interaction.lua\n")
    return
end

local SS = SED.Shared
if not (SS and SS._initialized) then
    include("rareload/client/saved_entity_display/SED_shared.lua")
    SS = SED.Shared
end

local cam_Start3D2D        = RS.cam_Start3D2D
local cam_End3D2D          = RS.cam_End3D2D
local math_abs             = RS.math_abs
local math_AngleDifference = RS.math_AngleDifference

local HINT_INTERACT        = RS.HINT_INTERACT
local HINT_CONTROLS        = RS.HINT_CONTROLS
local HINT_CANDIDATE       = RS.HINT_CANDIDATE
local HINT_INTERACT_BG     = RS.HINT_INTERACT_BG
local HINT_CONTROLS_BG     = RS.HINT_CONTROLS_BG
local HINT_CANDIDATE_BG    = RS.HINT_CANDIDATE_BG

function SED.PanelRendererHandleInteraction(ctx)
    local ent         = ctx.ent
    local panelID     = ctx.panelID
    local drawPos     = ctx.drawPos
    local panelHeight = ctx.panelHeight
    local scale       = ctx.scale
    local ang         = ctx.ang
    local width       = ctx.width

    local isFocused   = SED.InteractionState.active and SED.InteractionState.ent == ent
    local isCandidate = false

    local doHitTest   = true
    if SED.HITTEST_ONLY_CANDIDATE and SED.CandidateEnt and SED.CandidateEnt ~= ent then
        doHitTest = false
    end

    if doHitTest then
        local eyePos2     = SED.lpCache:EyePos()
        local forward     = SED.lpCache:EyeAngles():Forward()
        local panelCenter = Vector(drawPos.x, drawPos.y, drawPos.z)

        local hit         = SS.PanelHitTest(panelCenter, ang, scale, width, panelHeight, eyePos2, forward)
        if hit then
            SED.LookingAtPanelUntil = CurTime() + 0.03
            if not SED.InteractionState.active and SED.CandidateEnt == ent then
                isCandidate = true
            end
        end
    end

    if (isFocused or isCandidate) then
        local hintY   = drawPos.z + (panelHeight * scale) * 0.5 + 10
        local hintPos = Vector(drawPos.x, drawPos.y, hintY)

        cam_Start3D2D(hintPos, ang, scale * 0.8)
        if isFocused then
            SS.DrawHint("INTERACT MODE", 0, 0, HINT_INTERACT, HINT_INTERACT_BG)
            SS.DrawHint("Up/Down Tabs | Left/Right/MWheel Scroll | Shift+E Exit", 0, 24, HINT_CONTROLS, HINT_CONTROLS_BG)
        elseif isCandidate then
            SS.DrawHint("Shift + E to Inspect", 0, 0, HINT_CANDIDATE, HINT_CANDIDATE_BG)
        end
        cam_End3D2D()
    end
end
