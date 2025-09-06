local SED = RARELOAD.SavedEntityDisplay


function SED.InteractModifierDown()
    if not SED.REQUIRE_SHIFT_MOD then return true end
    if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then return true end
    local ply = SED.lpCache
    if (not IsValid(ply)) then ply = LocalPlayer() end
    if IsValid(ply) and (ply:KeyDown(IN_SPEED) or ply:KeyDown(IN_WALK)) then return true end
    return false
end

function SED.KeyPressed(code)
    if not input.IsKeyDown(code) then return false end
    local t = CurTime()
    local last = SED.KeyStates[code] or 0
    if t - last > SED.KEY_REPEAT_DELAY then
        SED.KeyStates[code] = t
        return true
    end
    return false
end

function SED.PlayerIsHoldingSomething()
    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return false end
    if SED.lpCache:KeyDown(IN_USE) then
        local tr = SED.lpCache:GetEyeTrace()
        if tr and IsValid(tr.Entity) and tr.Entity.IsPlayerHolding and tr.Entity:IsPlayerHolding() then
            return true
        end
    end
    local scanCount = 0
    for ent, _ in pairs(SED.TrackedEntities) do
        if IsValid(ent) and ent.IsPlayerHolding and ent:IsPlayerHolding() then return true end
        scanCount = scanCount + 1
        if scanCount > 50 then break end
    end
    for ent, _ in pairs(SED.TrackedNPCs) do
        if IsValid(ent) and ent.IsPlayerHolding and ent:IsPlayerHolding() then return true end
        scanCount = scanCount + 1
        if scanCount > 80 then break end
    end
    return false
end

function SED.EnterInteraction(ent, isNPC, id)
    SED.InteractionState.active = true
    SED.InteractionState.ent = ent
    SED.InteractionState.id = id
    SED.InteractionState.isNPC = isNPC
    SED.InteractionState.lastAction = CurTime()
    SED.lpCache = SED.lpCache or LocalPlayer()
    if IsValid(SED.lpCache) then
        SED.InteractionState.lockAng = SED.lpCache:EyeAngles()
        SED.lpCache:DrawViewModel(false)
    end

    if isNPC and IsValid(ent) and ent:IsNPC() then
        net.Start("SED_FreezeNPC")
        net.WriteUInt(ent:EntIndex(), 16)
        net.SendToServer()
    end
end

function SED.LeaveInteraction()
    if SED.InteractionState.isNPC and IsValid(SED.InteractionState.ent) and SED.InteractionState.ent:IsNPC() then
        net.Start("SED_UnfreezeNPC")
        net.WriteUInt(SED.InteractionState.ent:EntIndex(), 16)
        net.SendToServer()
    end

    SED.InteractionState.active = false
    SED.InteractionState.ent = nil
    SED.InteractionState.id = nil
    SED.InteractionState.isNPC = false
    SED.InteractionState.lockAng = nil
    SED.LeaveTime = CurTime()
    if IsValid(SED.lpCache) then
        SED.lpCache:DrawViewModel(true)
    end
end

function SED.HandleInteractionInput()
    if SED.InteractionState.active then
        local ent = SED.InteractionState.ent
        if not IsValid(ent) then
            SED.LeaveInteraction()
            return
        end

        local eyePos = SED.lpCache:EyePos()
        local renderParams = SED.CalculateEntityRenderParams(ent)
        local distSqr
        if renderParams and (renderParams.isLarge or renderParams.isMassive) then
            distSqr = select(1, SED.GetNearestDistanceSqr(ent, eyePos, renderParams))
        else
            distSqr = eyePos:DistToSqr(ent:GetPos())
        end
        local maxInteractDistSqr = renderParams and (renderParams.drawDistanceSqr * 1.25) or
            (SED.DRAW_DISTANCE_SQR * 1.1)
        if distSqr > maxInteractDistSqr then
            SED.LeaveInteraction()
            return
        end

        if SED.KeyPressed(SED.INTERACT_KEY) and SED.InteractModifierDown() then
            SED.LeaveInteraction()
            return
        end

        local isNPC = SED.InteractionState.isNPC
        local interactionID = SED.InteractionState.id

        if not interactionID then
            SED.LeaveInteraction()
            return
        end

        local savedRec = isNPC and SED.SAVED_NPCS_BY_ID[interactionID] or SED.SAVED_ENTITIES_BY_ID[interactionID]
        if not savedRec then
            SED.LeaveInteraction()
            return
        end

        local panelCache = isNPC and SED.NPCPanelCache or SED.EntityPanelCache
        local cache = panelCache[interactionID]
        if not cache then
            cache = SED.BuildPanelData(savedRec, ent, isNPC)
        end

        if cache and cache.activeCat then
            local categoryList = isNPC and SED.NPC_CATEGORIES or SED.ENT_CATEGORIES
            local scrollTable = isNPC and SED.PanelScroll.npcs or SED.PanelScroll.entities

            if SED.KeyPressed(KEY_RIGHT) or SED.KeyPressed(KEY_LEFT) then
                local dir = (input.IsKeyDown(KEY_RIGHT) and not input.IsKeyDown(KEY_LEFT)) and 1 or -1
                local currentIdx = 1

                for i, cat in ipairs(categoryList) do
                    if cat[1] == cache.activeCat then
                        currentIdx = i
                        break
                    end
                end

                currentIdx = currentIdx + dir
                if currentIdx < 1 then
                    currentIdx = #categoryList
                elseif currentIdx > #categoryList then
                    currentIdx = 1
                end

                cache.activeCat = categoryList[currentIdx][1]
                scrollTable[interactionID .. "_" .. cache.activeCat] = 0
            end

            local scrollDelta = SED.ScrollDelta
            if input.IsKeyDown(KEY_UP) then scrollDelta = scrollDelta - SED.SCROLL_SPEED end
            if input.IsKeyDown(KEY_DOWN) then scrollDelta = scrollDelta + SED.SCROLL_SPEED end

            if scrollDelta ~= 0 then
                local scrollKey = interactionID .. "_" .. cache.activeCat
                local lines = cache.data[cache.activeCat] or {}
                local maxScrollLines = math.max(0, #lines - SED.MAX_VISIBLE_LINES)

                if maxScrollLines > 0 then
                    local currentScroll = math.min(scrollTable[scrollKey] or 0, maxScrollLines)
                    scrollTable[scrollKey] = math.Clamp(currentScroll + scrollDelta, 0, maxScrollLines)
                end
                SED.ScrollDelta = 0
            end
        end
    else
        -- Only allow entering interaction when the player is aiming at the 3D2D panel (candidate set by panel hit-test)
        if SED.CandidateEnt and SED.KeyPressed(SED.INTERACT_KEY) and SED.InteractModifierDown() and not SED.PlayerIsHoldingSomething() then
            SED.EnterInteraction(SED.CandidateEnt, SED.CandidateIsNPC, SED.CandidateID)
        end
    end
end
