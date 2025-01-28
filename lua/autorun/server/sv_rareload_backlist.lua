-- Load hardcoded blacklist into settings if not already present
HardcodedBlacklist = {
    -- AI Entities
    ["ai_ally_manager"] = true,
    ["ai_battle_line"] = true,
    ["ai_changehintgroup"] = true,
    ["ai_changetarget"] = true,
    ["ai_citizen_response_system"] = true,
    ["ai_goal_actbusy"] = true,
    ["ai_goal_assault"] = true,
    ["ai_goal_follow"] = true,
    ["ai_goal_lead"] = true,
    ["ai_goal_lead_weapon"] = true,
    ["ai_goal_police"] = true,
    ["ai_goal_standoff"] = true,
    ["ai_relationship"] = true,
    ["ai_script_conditions"] = true,
    ["ai_sound"] = true,
    ["ai_speechfilter"] = true,
    ["aiscripted_schedule"] = true,
    ["assault_assaultpoint"] = true,
    ["assault_rallypoint"] = true,
    ["info_apc_missile_hint"] = true,
    ["info_node"] = true,
    ["info_node_air"] = true,
    ["info_node_air_hint"] = true,
    ["info_node_climb"] = true,
    ["info_node_hint"] = true,
    ["info_node_link"] = true,
    ["info_node_link_controller"] = true,
    ["info_npc_spawn_destination"] = true,
    ["info_snipertarget"] = true,
    ["logic_choreographed_scene"] = true,
    ["path_corner"] = true,
    ["path_corner_crash"] = true,
    ["path_track"] = true,
    ["scripted_scene"] = true,
    ["scripted_sentence"] = true,
    ["scripted_sequence"] = true,
    ["scripted_target"] = true,
    ["tanktrain_aitarget"] = true,
    ["tanktrain_ai"] = true,

    -- Misc Entities
    ["ambient_generic"] = true,
    ["cycler"] = true,
    ["gibshooter"] = true,
    ["keyframe_rope"] = true,
    ["keyframe_track"] = true,
    ["material_modify_control"] = true,
    ["math_colorblend"] = true,
    ["math_counter"] = true,
    ["math_remap"] = true,
    ["momentary_rot_button"] = true,
    ["move_keyframed"] = true,
    ["move_rope"] = true,
    ["move_track"] = true,
    ["script_intro"] = true,
    ["script_tauremoval"] = true,
    ["shadow_control"] = true,
    ["sky_camera"] = true,
    ["test_sidelist"] = true,
    ["test_traceline"] = true,
    ["VGUI_Screen"] = true,
    ["water_lod_control"] = true,

    -- Environment Entities
    ["env_ar2explosion"] = true,
    ["env_beam"] = true,
    ["env_beverage"] = true,
    ["env_blood"] = true,
    ["env_bubbles"] = true,
    ["env_citadel_energy_core"] = true,
    ["env_credits"] = true,
    ["env_cubemap"] = true,
    ["env_dustpuff"] = true,
    ["env_effectscript"] = true,
    ["env_embers"] = true,
    ["env_entity_igniter"] = true,
    ["env_entity_maker"] = true,
    ["env_explosion"] = true,
    ["env_extinguisherjet"] = true,
    ["env_fade"] = true,
    ["env_fire"] = true,
    ["env_firesensor"] = true,
    ["env_firesource"] = true,
    ["env_flare"] = true,
    ["env_fog_controller"] = true,
    ["env_funnel"] = true,
    ["env_global"] = true,
    ["env_gunfire"] = true,
    ["env_headcrabcanister"] = true,
    ["env_hudhint"] = true,
    ["env_laser"] = true,
    ["env_lightglow"] = true,
    ["env_message"] = true,
    ["env_microphone"] = true,
    ["env_muzzleflash"] = true,
    ["env_particlelight"] = true,
    ["env_particlescript"] = true,
    ["env_physexplosion"] = true,
    ["env_physimpact"] = true,
    ["env_player_surface_trigger"] = true,
    ["env_rotorshooter"] = true,
    ["env_rotorwash"] = true,
    ["env_screenoverlay"] = true,
    ["env_shake"] = true,
    ["env_shooter"] = true,
    ["env_smokestack"] = true,
    ["env_smoketrail"] = true,
    ["env_soundscape"] = true,
    ["env_soundscape_proxy"] = true,
    ["env_soundscape_triggerable"] = true,
    ["env_spark"] = true,
    ["env_speaker"] = true,
    ["env_splash"] = true,
    ["env_sprite"] = true,
    ["env_starfield"] = true,
    ["env_steam"] = true,
    ["env_sun"] = true,
    ["env_terrainmorph"] = true,
    ["env_texturetoggle"] = true,
    ["env_tonemap_controller"] = true,
    ["env_wind"] = true,
    ["env_zoom"] = true,

    -- Filter Entities
    ["filter_activator_class"] = true,
    ["filter_activator_name"] = true,
    ["filter_activator_team"] = true,
    ["filter_damage_type"] = true,
    ["filter_multi"] = true,
    ["filter_name"] = true,
    ["filter_tf_class"] = true,
    ["filter_tf_team"] = true,

    -- Function (brush) Entities
    ["func_areaportal"] = true,
    ["func_areaportalwindow"] = true,
    ["func_breakable"] = true,
    ["func_breakable_surf"] = true,
    ["func_brush"] = true,
    ["func_button"] = true,
    ["func_clip_vphysics"] = true,
    ["func_combine_ball_spawner"] = true,
    ["func_conveyor"] = true,
    ["func_detail"] = true,
    ["func_door"] = true,
    ["func_door_rotating"] = true,
    ["func_dustcloud"] = true,
    ["func_dustmotes"] = true,
    ["func_extinguishercharger"] = true,
    ["func_guntarget"] = true,
    ["func_healthcharger"] = true,
    ["func_illusionary"] = true,
    ["func_ladder"] = true,
    ["func_ladderendpoint"] = true,
    ["func_lod"] = true,
    ["func_lookdoor"] = true,
    ["func_monitor"] = true,
    ["func_movelinear"] = true,
    ["func_occluder"] = true,
    ["func_physbox"] = true,
    ["func_physbox_multiplayer"] = true,
    ["func_platrot"] = true,
    ["func_precipitation"] = true,
    ["func_recharge"] = true,
    ["func_rot_button"] = true,
    ["func_rotating"] = true,
    ["func_smokevolume"] = true,
    ["func_tank"] = true,
    ["func_tankairboatgun"] = true,
    ["func_tankapcrocket"] = true,
    ["func_tanklaser"] = true,
    ["func_tankmortar"] = true,
    ["func_tankphyscannister"] = true,
    ["func_tankpulselaser"] = true,
    ["func_tankrocket"] = true,
    ["func_tanktrain"] = true,
    ["func_trackautochange"] = true,
    ["func_trackchange"] = true,
    ["func_tracktrain"] = true,
    ["func_traincontrols"] = true,
    ["func_useableladder"] = true,
    ["func_vehicleclip"] = true,
    ["func_wall"] = true,
    ["func_wall_toggle"] = true,
    ["func_water_analog"] = true,

    -- Information Entities
    ["info_camera_link"] = true,
    ["info_constraint_anchor"] = true,
    ["info_hint"] = true,
    ["info_intermission"] = true,
    ["info_ladder_dismount"] = true,
    ["info_landmark"] = true,
    ["info_lighting"] = true,
    ["info_mass_center"] = true,
    ["info_no_dynamic_shadow"] = true,
    ["info_null"] = true,
    ["info_overlay"] = true,
    ["info_player_combine"] = true,
    ["info_player_deathmatch"] = true,
    ["info_player_logo"] = true,
    ["info_player_rebel"] = true,
    ["info_player_start"] = true,
    ["info_projecteddecal"] = true,
    ["info_target"] = true,
    ["info_target_gunshipcrash"] = true,
    ["info_teleporter_countdown"] = true,
    ["info_teleport_destination"] = true,
    ["infodecal"] = true,
    ["infodecal_multi"] = true,
    ["infodecal_multiplayer"] = true,
    ["infodecal_multiplayer_proxy"] = true,
    ["infodecal_proxy"] = true,
    ["infodecal_proxy_multi"] = true,
    ["infodecal_proxy_single"] = true,
    ["infodecal_single"] = true,

    -- Light Entities
    ["light"] = true,

    --Others
    ["gmod_hands"] = true,
    ["predicted_viewmodel"] = true,
    ["physgun_beam"] = true,
    ["lua_run"] = true,
    ["gmod_tool"] = true,
    ["gmod_camera"] = true,
    ["scene_manager"] = true,
    ["soundent"] = true,
    ["player_manager"] = true,
    ["gmod_gamerules"] = true,
    ["network"] = true,
    ["env_skypaint"] = true,
    ["npc_bullseye"] = true,
    ["npc_enemyfinder"] = true,
    ["prop_ragdoll"] = true,
    ["RARELOAD.Phanthom"] = true,
    ["ally_speech_manager"] = true,
    ["instanced_scripted_scene"] = true,
}

function LoadBlacklist()
    local mapName = game.GetMap()
    local filePath = "rareload/blacklist_" .. mapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        local success, result = pcall(util.JSONToTable, data)
        if success then
            HardcodedBlacklist = result
        else
            print("[RARELOAD DEBUG] Error parsing JSON: " .. result)
        end
    else
        SaveBlacklist() -- Save default blacklist if file doesn't exist
    end
end

function SaveBlacklist()
    local mapName = game.GetMap()
    local filePath = "rareload/blacklist_" .. mapName .. ".json"
    local success, err = pcall(function()
        file.Write(filePath, util.TableToJSON(HardcodedBlacklist, true))
    end)
    if not success then
        print("[RARELOAD] Failed to save blacklist: " .. err)
    end
end

LoadBlacklist()
