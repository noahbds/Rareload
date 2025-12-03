include("rareload/client/saved_entity_display/SED_init.lua")
include("rareload/client/saved_entity_display/SED_entity_tracking.lua")
include("rareload/client/saved_entity_display/SED_render_utils.lua")
include("rareload/client/saved_entity_display/SED_panel_builder.lua")
include("rareload/client/saved_entity_display/SED_panel_renderer.lua")
include("rareload/client/saved_entity_display/SED_panel_queue.lua")
include("rareload/client/saved_entity_display/SED_interaction_system.lua")
include("rareload/client/saved_entity_display/SED_hooks.lua")

if CLIENT then
    print("[Rareload] Saved Entity and NPCs Display system loaded")
end
