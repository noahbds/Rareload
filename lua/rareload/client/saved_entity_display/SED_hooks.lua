hook.Add("OnEntityCreated", "RARELOAD_TrackSavedEntities", function(ent)
    timer.Simple(0, function()
        if IsValid(ent) then SED.TrackIfSaved(ent) end
    end)
    timer.Simple(0.25, function()
        if IsValid(ent) and (not SED.TrackedEntities[ent]) and (not SED.TrackedNPCs[ent]) then SED.TrackIfSaved(ent) end
    end)
end)

hook.Add("CreateMove", "RARELOAD_SavedPanels_CamLock", function(cmd)
    if SED.InteractionState.active or CurTime() - SED.LeaveTime < 0.5 then
        -- In interaction or shortly after leaving, block +use to avoid picking entities
        cmd:RemoveKey(IN_USE)
    elseif SED.LookingAtPanelUntil and CurTime() <= SED.LookingAtPanelUntil then
        -- Only while aiming at the 3D2D frame, prevent pickup/use on the underlying entity
        cmd:RemoveKey(IN_USE)
    end
    if not SED.InteractionState.active then return end
    local ent = SED.InteractionState.ent
    if not IsValid(ent) then return end
    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end
    local ang = SED.InteractionState.lockAng
    if not ang then
        ang = SED.lpCache:EyeAngles()
        SED.InteractionState.lockAng = ang
    end
    cmd:SetViewAngles(ang)
end)

hook.Add("EntityRemoved", "RARELOAD_UntrackSavedEntities", function(ent)
    if SED.TrackedEntities[ent] then SED.TrackedEntities[ent] = nil end
    if SED.TrackedNPCs[ent] then SED.TrackedNPCs[ent] = nil end

    if SED.InteractionState.active and SED.InteractionState.ent == ent then
        SED.LeaveInteraction()
    end
end)

hook.Add("PlayerBindPress", "RARELOAD_InteractScroll", function(ply, bind, pressed)
    if not SED.InteractionState.active or not pressed then return end
    if bind == "invprev" then
        SED.ScrollDelta = SED.ScrollDelta - SED.SCROLL_SPEED
        return true
    elseif bind == "invnext" then
        SED.ScrollDelta = SED.ScrollDelta + SED.SCROLL_SPEED
        return true
    end
end)

hook.Add("PostDrawOpaqueRenderables", "Rareload_QueueSavedEntitiesAndNPCs", function()
    -- Always process panels; visibility and distances are already handled in renderer.

    local currentTime = CurTime()

    if currentTime - SED.lastPlayerCheck > 7.5 then
        SED.lpCache = LocalPlayer()
        SED.lastPlayerCheck = currentTime
    end
    if not IsValid(SED.lpCache) then return end

    SED.CandidateEnt, SED.CandidateIsNPC, SED.CandidateID, SED.CandidateYawDiff = nil, nil, nil, nil

    if RARELOAD.DepthRenderer and RARELOAD.DepthRenderer.AddRenderItem then
        SED.QueueAllSavedPanels()
    else
        SED.DrawAllSavedPanels()
    end

    SED.HandleInteractionInput()
end)

hook.Add("OnPlayerChat", "SED_CleanupOnDisconnect", function()
    if SED.InteractionState.active then
        SED.LeaveInteraction()
    end
end)
