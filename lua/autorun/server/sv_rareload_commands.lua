concommand.Add("toggle_rareload", function(ply)
    ToggleSetting(ply, 'addonEnabled', 'Respawn at Reload addon')
end)

concommand.Add("toggle_spawn_mode", function(ply)
    ToggleSetting(ply, 'spawnModeEnabled', 'Spawn with saved move type')
end)

concommand.Add("toggle_auto_save", function(ply)
    ToggleSetting(ply, 'autoSaveEnabled', 'Auto-save position')
end)

concommand.Add("toggle_retain_inventory", function(ply)
    ToggleSetting(ply, 'retainInventory', 'Retain inventory')
end)

concommand.Add("toggle_nocustomrespawnatdeath", function(ply)
    ToggleSetting(ply, 'nocustomrespawnatdeath', 'No Custom Respawn at Death')
end)

concommand.Add("toggle_debug", function(ply)
    ToggleSetting(ply, 'debugEnabled', 'Debug mode')
end)

---[[ Beta [NOT TESTED] ]]---

concommand.Add("toggle_retain_health_armor", function(ply)
    ToggleSetting(ply, 'retainHealthArmor', 'Retain health and armor')
end)

concommand.Add("toggle_retain_ammo", function(ply)
    ToggleSetting(ply, 'retainAmmo', 'Retain ammo')
end)

concommand.Add("toggle_retain_vehicle_state", function(ply)
    ToggleSetting(ply, 'retainVehicleState', 'Retain vehicle state')
end)

concommand.Add("toggle_retain_map_npcs", function(ply)
    ToggleSetting(ply, 'retainMapNPCs', 'Retain map NPCs')
end)

concommand.Add("toggle_retain_map_entities", function(ply)
    ToggleSetting(ply, 'retainMapEntities', 'Retain map entities')
end)

---[[ End Of Beta [NOT TESTED] ]]---

-------------------------------------------------------------------------------------------------------------------------]
---------------------------------------------------------slider commands-------------------------------------------------]
-------------------------------------------------------------------------------------------------------------------------]

concommand.Add("set_auto_save_interval", function(ply, args)
    if not ply:IsSuperAdmin() then
        print("[RARELOAD] You do not have permission to use this command.")
        return
    end

    local interval = tonumber(args[1])
    if interval then
        RARELOAD.settings.autoSaveInterval = interval
        SaveAddonState()
    else
        print("[RARELOAD] Invalid interval value.")
    end
end)

concommand.Add("set_max_distance", function(args)
    local distance = tonumber(args[1])
    if distance then
        RARELOAD.settings.maxDistance = distance
        SaveAddonState()
    else
        print("[RARELOAD] Invalid distance value.")
    end
end)

concommand.Add("set_angle_tolerance", function(args)
    local tolerance = tonumber(args[1])
    if tolerance then
        RARELOAD.settings.angleTolerance = tolerance
        SaveAddonState()
    else
        print("[RARELOAD] Invalid tolerance value.")
    end
end)

-------------------------------------------------------------------------------------------------------------------------]
---------------------------------------------------------end of slider commands------------------------------------------]
-------------------------------------------------------------------------------------------------------------------------]

concommand.Add("save_position", function(ply, _, _)
    if not RARELOAD.settings.addonEnabled then
        print("[RARELOAD DEBUG] The Respawn at Reload addon is disabled.")
        return
    end

    EnsureFolderExists()
    MapName = game.GetMap()
    RARELOAD.playerPositions[MapName] = RARELOAD.playerPositions[MapName] or {}

    local newPos = ply:GetPos()
    local newActiveWeapon = ply:GetActiveWeapon() and ply:GetActiveWeapon():GetClass()
    local newInventory = {}
    for _, weapon in pairs(ply:GetWeapons()) do
        table.insert(newInventory, weapon:GetClass())
    end

    local oldPosData = RARELOAD.playerPositions[MapName][ply:SteamID()]
    if oldPosData and not RARELOAD.settings.autoSaveEnabled then
        local oldPos = oldPosData.pos
        local oldActiveWeapon = oldPosData.activeWeapon
        local oldInventory = oldPosData.inventory
        if oldPos == newPos and oldActiveWeapon == newActiveWeapon and table.concat(oldInventory) == table.concat(newInventory) then
            return
        else
            print("[RARELOAD] Overwriting your previously saved position, camera orientation, and inventory.")
        end
    else
        print("[RARELOAD] Saved your current position, camera orientation, and inventory.")
    end

    local playerData = {
        pos = newPos,
        moveType = ply:GetMoveType(),
        ang = { ply:EyeAngles().p, ply:EyeAngles().y, ply:EyeAngles().r },
        activeWeapon = newActiveWeapon,
        inventory = newInventory
    }

    ---[[ Beta [NOT TESTED] ]]---

    if RARELOAD.settings.retainHealthArmor then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end

    if RARELOAD.settings.retainAmmo then
        playerData.ammo = {}
        for _, weaponClass in pairs(playerData.inventory) do
            local weapon = ply:GetWeapon(weaponClass)
            if IsValid(weapon) then
                playerData.ammo[weaponClass] = {
                    primary = ply:GetAmmoCount(weapon:GetPrimaryAmmoType()),
                    secondary = ply:GetAmmoCount(weapon:GetSecondaryAmmoType())
                }
            end
        end
    end

    if RARELOAD.settings.retainVehicleState and ply:InVehicle() then
        local vehicle = ply:GetVehicle()
        playerData.vehicle = {
            class = vehicle:GetClass(),
            pos = vehicle:GetPos(),
            ang = vehicle:GetAngles(),
            health = vehicle:Health(),
        }
    end

    if RARELOAD.settings.retainMapEntities then
        playerData.entities = {}

        -- List of classes to exclude (I want to find a better way to do this)
        local excludeClasses = {
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
            ["gmod_hands"] = true,              -- Player hands
            ["predicted_viewmodel"] = true,     -- First-person viewmodels
            ["physgun_beam"] = true,            -- Physgun beams
            ["lua_run"] = true,                 -- Lua execution entities
            ["gmod_tool"] = true,               -- Tool gun
            ["gmod_camera"] = true,             -- Camera tool
            ["scene_manager"] = true,           -- Scene manager
            ["soundent"] = true,                -- Sound entity
            ["player_manager"] = true,          -- Player management
            ["gmod_gamerules"] = true,          -- Game rules
            ["network"] = true,                 -- Networking entities
            ["env_skypaint"] = true,            -- Skypaint entity
            ["npc_bullseye"] = true,            -- NPC targeting
            ["npc_enemyfinder"] = true,         -- NPC helpers
            ["prop_ragdoll"] = true,            -- Ragdolls
            ["RARELOAD.Phanthom"] = true,       -- Phantom entity
            ["ally_speech_manager"] = true,     -- Speech manager
            ["instanced_scripted_scene"] = true -- Scripted scenes
        }

        local excludePatterns = {
            "^env_",       -- Environment entities
            "^physgun_",   -- Physgun-related entities
            "^predicted_", -- Predicted viewmodels
            "^weapon_",    -- All weapon entities
            "^item_",      -- All item entities
        }

        for _, ent in pairs(ents.GetAll()) do
            if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent.isPhantom then
                local class = ent:GetClass()

                if ent.IsPhantom then
                    print("[RARELOAD DEBUG] Skipping phantom entity: " .. class)
                    continue
                end

                -- Skip explicitly excluded classes
                if not excludeClasses[class] then
                    -- Skip entities matching excluded patterns
                    local skip = false
                    for _, pattern in ipairs(excludePatterns) do
                        if string.find(class, pattern) then
                            skip = true
                            break
                        end
                    end

                    if not skip then
                        -- Removed CPPIGetOwner() to allow saving all entities
                        local phys = ent:GetPhysicsObject()
                        table.insert(playerData.entities, {
                            class = class,
                            pos = ent:GetPos(),
                            model = ent:GetModel(),
                            ang = ent:GetAngles(),
                            health = ent:Health(),
                            frozen = IsValid(phys) and not phys:IsMotionEnabled() or false
                        })
                        print("[RARELOAD DEBUG] Saved entity: " .. class .. " at position " .. tostring(ent:GetPos()))
                    else
                        print("[RARELOAD DEBUG] Skipping entity matching pattern: " .. class)
                    end
                else
                    print("[RARELOAD DEBUG] Skipping excluded entity class: " .. class)
                end
            end
        end

        if RARELOAD.settings.retainMapNPCs then
            playerData.npcs = {}
            for _, npc in pairs(ents.FindByClass("npc_*")) do
                if IsValid(npc) then
                    local weapons = {}
                    for _, weapon in ipairs(npc:GetWeapons()) do
                        table.insert(weapons, weapon:GetClass())
                    end
                    table.insert(playerData.npcs, {
                        class = npc:GetClass(),
                        pos = npc:GetPos(),
                        weapons = weapons,
                        model = npc:GetModel(),
                        ang = npc:GetAngles(),
                        health = npc:Health()
                    })
                end
            end
        end

        ---[[ End of Beta [NOT TESTED] ]]---

        RARELOAD.playerPositions[MapName][ply:SteamID()] = playerData

        local success, err = pcall(function()
            file.Write("rareload/player_positions_" .. MapName .. ".json",
                util.TableToJSON(RARELOAD.playerPositions, true))
        end)

        if not success then
            print("[RARELOAD] Failed to save position data: " .. err)
        else
            print("[RARELOAD] Player position successfully saved to file.")
        end

        CreatePlayerPhantom(ply)
        SyncPlayerPositions(ply)
    end
end)
