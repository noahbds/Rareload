-- SED panel rendering entry point.

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

if not (RS and RS._initialized) then
    ErrorNoHalt("[Rareload] Missing shared renderer state in SED_panel_renderer.lua\n")
    return
end

include("rareload/client/saved_entity_display/SED_panel_renderer_context.lua")
include("rareload/client/saved_entity_display/SED_panel_renderer_draw.lua")
include("rareload/client/saved_entity_display/SED_panel_renderer_interaction.lua")

if not SED.PanelRendererBuildContext then
    ErrorNoHalt("[Rareload] Missing SED.PanelRendererBuildContext in SED_panel_renderer.lua\n")
    return
end

if not SED.PanelRendererDraw then
    ErrorNoHalt("[Rareload] Missing SED.PanelRendererDraw in SED_panel_renderer.lua\n")
    return
end

if not SED.PanelRendererHandleInteraction then
    ErrorNoHalt("[Rareload] Missing SED.PanelRendererHandleInteraction in SED_panel_renderer.lua\n")
    return
end

function SED.DrawSavedPanel(ent, saved, isNPC, precomputedParams, precomputedDistSqr)
    local ctx = SED.PanelRendererBuildContext(ent, saved, isNPC, precomputedParams, precomputedDistSqr)
    if not ctx then return end

    SED.PanelRendererDraw(ctx)
    SED.PanelRendererHandleInteraction(ctx)
end
