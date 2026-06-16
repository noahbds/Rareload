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

function SED.GetPhantomSavedInfo(mapName, steamID)
    if not (mapName and steamID) then return nil end
    local byMap = RARELOAD and RARELOAD.playerPositions and RARELOAD.playerPositions[mapName]
    if not byMap then return nil end
    return byMap[steamID]
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

function SED.EnterInteraction(ent, isNPC, id, options)
    SED.InteractionState.active = true
    SED.InteractionState.ent = ent
    SED.InteractionState.id = id
    SED.InteractionState.isNPC = isNPC
    SED.InteractionState.lastAction = CurTime()
    SED.InteractionState.kind = options and options.kind or (isNPC and "npc" or "entity")
    SED.InteractionState.maxInteractDistSqr = options and options.maxInteractDistSqr or nil
    SED.InteractionState.onCategoryChange = options and options.onCategoryChange or nil
    SED.InteractionState.onPageChange = options and options.onPageChange or nil
    SED.InteractionState.phantom = options and options.phantom or nil
    SED.InteractionState.steamID = options and options.steamID or nil
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
    SED.InteractionState.kind = nil
    SED.InteractionState.maxInteractDistSqr = nil
    SED.InteractionState.onCategoryChange = nil
    SED.InteractionState.onPageChange = nil
    SED.InteractionState.phantom = nil
    SED.InteractionState.steamID = nil
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

        if SED.InteractionState.kind == "phantom" then
            local eyePos = SED.lpCache:EyePos()
            local maxInteractDistSqr = SED.InteractionState.maxInteractDistSqr or (SED.DRAW_DISTANCE_SQR * 1.1)
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

        if not savedRec and type(interactionID) == "string" and string.sub(interactionID, 1, 8) == "phantom_" then
            local steamID = string.sub(interactionID, 9)
            if SED.PhantomSavedRecords then
                savedRec = SED.PhantomSavedRecords[steamID]
            end
        end

        if not savedRec then
            SED.LeaveInteraction()
            return
        end

        local panelCache = isNPC and SED.NPCPanelCache or SED.EntityPanelCache
        local cache = panelCache[interactionID]
        if not cache then
            local liveEnt
            local trackTable = isNPC and SED.TrackedNPCs or SED.TrackedEntities
            for e, eid in pairs(trackTable or {}) do
                if eid == interactionID and IsValid(e) then
                    liveEnt = e
                    break
                end
            end
            cache = SED.BuildPanelData(savedRec, liveEnt, isNPC)
        end

        if cache and cache.activeCat then
            local categoryList = isNPC and SED.NPC_CATEGORIES or SED.ENT_CATEGORIES
            local scrollTable = isNPC and SED.PanelScroll.npcs or SED.PanelScroll.entities

            if savedRec and savedRec._isPhantom and savedRec._phantomCategories then
                categoryList = savedRec._phantomCategories
            end

            local panelID = cache._panelID
            if not panelID then
                local rawID = savedRec.id or savedRec.RareloadNPCID or savedRec.RareloadEntityID or savedRec.RareloadID or
                    ((savedRec.class or savedRec.Class or savedRec.ClassName or "unknown") .. "?")
                panelID = (savedRec._isPhantom and "P:" or (isNPC and "N:" or "E:")) .. tostring(rawID)
                cache._panelID = panelID
            end

            if SED.KeyPressed(KEY_DOWN) or SED.KeyPressed(KEY_UP) then
                local dir = (input.IsKeyDown(KEY_DOWN) and not input.IsKeyDown(KEY_UP)) and 1 or -1
                local currentIdx = 1

                for i, cat in ipairs(categoryList) do
                    if cat[1] == cache.activeCat then
                        currentIdx = i
                        break
                    end
                end

                local nextIdx = currentIdx
                for _ = 1, #categoryList do
                    nextIdx = nextIdx + dir
                    if nextIdx < 1 then
                        nextIdx = #categoryList
                    elseif nextIdx > #categoryList then
                        nextIdx = 1
                    end

                    local candidateCat = categoryList[nextIdx][1]
                    local candidateLines = cache.data and cache.data[candidateCat]
                    if candidateLines and #candidateLines > 0 then
                        break
                    end
                end
                currentIdx = nextIdx

                cache.activeCat = categoryList[currentIdx][1]
                scrollTable[panelID .. "_" .. cache.activeCat] = 0
            end

            local scrollDelta = SED.ScrollDelta
            if input.IsKeyDown(KEY_LEFT) then scrollDelta = scrollDelta - SED.SCROLL_SPEED end
            if input.IsKeyDown(KEY_RIGHT) then scrollDelta = scrollDelta + SED.SCROLL_SPEED end

            if scrollDelta ~= 0 then
                local scrollKey = panelID .. "_" .. cache.activeCat
                local lines = cache.data[cache.activeCat] or {}
                if #lines > 0 then
                    local currentScroll = scrollTable[scrollKey] or 0
                    scrollTable[scrollKey] = math.max(0, currentScroll + scrollDelta)
                end
                SED.ScrollDelta = 0
            end

            -- Highlight toggles for the panel currently being inspected.
            if SED.Highlight then
                local isPhantom = savedRec._isPhantom
                local ownerID = savedRec._ownerSteamID or interactionID
                if SED.KeyPressed(KEY_H) then
                    if isPhantom then
                        SED.Highlight.TogglePlayerToPhantom(ownerID)
                    else
                        SED.Highlight.ToggleSaved(interactionID, isNPC)
                    end
                end
                if SED.KeyPressed(KEY_L) then
                    if isPhantom then
                        SED.Highlight.TogglePlayerToPhantom(ownerID)
                    else
                        SED.Highlight.ToggleLiveToPhantom(interactionID, isNPC)
                    end
                end
            end
        end
    else
        if SED.CandidateEnt and SED.KeyPressed(SED.INTERACT_KEY) and SED.InteractModifierDown() and not SED.PlayerIsHoldingSomething() then
            SED.EnterInteraction(SED.CandidateEnt, SED.CandidateIsNPC, SED.CandidateID)
        end
    end
end
