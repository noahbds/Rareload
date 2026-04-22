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

function SED.SetCategoryPageState(cache, category, page)
    if not cache then return end
    cache.pageByCategory = cache.pageByCategory or {}
    cache.pageByCategory[category] = math.max(1, math.floor(tonumber(page) or 1))
end

function SED.ClampCategoryPageState(cache, category, lineCount, linesPerPage)
    if not cache then return 1, 1 end

    local perPage = math.max(1, tonumber(linesPerPage) or 1)
    local maxPage = math.max(1, math.ceil(math.max(lineCount or 0, 1) / perPage))
    cache.pageByCategory = cache.pageByCategory or {}
    local currentPage = cache.pageByCategory[category] or 1
    currentPage = math.Clamp(currentPage, 1, maxPage)
    cache.pageByCategory[category] = currentPage
    return currentPage, maxPage
end

function SED.GetPhantomDrawDistSqr()
    return SED.DRAW_DISTANCE_SQR
end

function SED.GetPhantomSavedInfo(mapName, steamID)
    if not (mapName and steamID) then return nil end
    local byMap = RARELOAD and RARELOAD.playerPositions and RARELOAD.playerPositions[mapName]
    if not byMap then return nil end
    return byMap[steamID]
end

function SED.GetPhantomInfoCache(steamID, buildDataFn, ply, savedInfo, mapName, cacheLifetime, defaultCategory)
    if not steamID or steamID == "" then return nil end
    if type(buildDataFn) ~= "function" then return nil end

    local now = CurTime()
    local cache = SED.PhantomInfoCache and SED.PhantomInfoCache[steamID] or nil
    local activeCategory = (cache and cache.activeCategory) or defaultCategory or "basic"

    if (not cache) or (cache.expires or 0) < now then
        cache = {
            data = buildDataFn(ply, savedInfo, mapName, 1),
            expires = now + (tonumber(cacheLifetime) or 5),
            activeCategory = activeCategory,
            pageByCategory = (cache and cache.pageByCategory) or {}
        }
        SED.PhantomInfoCache = SED.PhantomInfoCache or {}
        SED.PhantomInfoCache[steamID] = cache
    end

    cache.pageByCategory = cache.pageByCategory or {}
    cache.pageByCategory[cache.activeCategory or activeCategory] = cache.pageByCategory
        [cache.activeCategory or activeCategory] or 1
    return cache
end

function SED.CycleCategoryState(cache, categoryList, currentCategory, delta)
    if not cache or not categoryList or #categoryList == 0 then return currentCategory end

    local currentIndex = 1
    for i, cat in ipairs(categoryList) do
        if cat[1] == currentCategory then
            currentIndex = i
            break
        end
    end

    local newIndex = currentIndex + (tonumber(delta) or 0)
    if newIndex < 1 then newIndex = #categoryList end
    if newIndex > #categoryList then newIndex = 1 end

    local newCategory = categoryList[newIndex][1]
    if newCategory ~= currentCategory then
        SED.SetCategoryPageState(cache, newCategory, 1)
    end
    return newCategory
end

function SED.StepCategoryPageState(cache, category, lineCount, linesPerPage, delta)
    local currentPage, maxPage = SED.ClampCategoryPageState(cache, category, lineCount, linesPerPage)
    currentPage = math.Clamp(currentPage + (tonumber(delta) or 0), 1, maxPage)
    SED.SetCategoryPageState(cache, category, currentPage)
    return currentPage, maxPage
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
            if eyePos:DistToSqr(ent:GetPos()) > maxInteractDistSqr then
                SED.LeaveInteraction()
                return
            end

            if SED.KeyPressed(SED.INTERACT_KEY) and SED.InteractModifierDown() then
                SED.LeaveInteraction()
                return
            end

            if SED.KeyPressed(KEY_LEFT) and SED.InteractionState.onCategoryChange then
                SED.InteractionState.onCategoryChange(-1)
            elseif SED.KeyPressed(KEY_RIGHT) and SED.InteractionState.onCategoryChange then
                SED.InteractionState.onCategoryChange(1)
            end

            if SED.KeyPressed(KEY_UP) and SED.InteractionState.onPageChange then
                SED.InteractionState.onPageChange(-1)
            elseif SED.KeyPressed(KEY_DOWN) and SED.InteractionState.onPageChange then
                SED.InteractionState.onPageChange(1)
            end

            local scrollDelta = SED.ScrollDelta
            if scrollDelta ~= 0 and SED.InteractionState.onPageChange then
                local scrollStep = scrollDelta > 0 and 1 or -1
                SED.InteractionState.onPageChange(scrollStep)
                SED.ScrollDelta = 0
            end
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

            -- Tab Navigation (Up/Down)
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
                scrollTable[interactionID .. "_" .. cache.activeCat] = 0
            end

            -- Content Scrolling (Left/Right)
            local scrollDelta = SED.ScrollDelta
            if input.IsKeyDown(KEY_LEFT) then scrollDelta = scrollDelta - SED.SCROLL_SPEED end
            if input.IsKeyDown(KEY_RIGHT) then scrollDelta = scrollDelta + SED.SCROLL_SPEED end

            if scrollDelta ~= 0 then
                local scrollKey = interactionID .. "_" .. cache.activeCat
                local lines = cache.data[cache.activeCat] or {}
                if #lines > 0 then
                    local currentScroll = scrollTable[scrollKey] or 0
                    scrollTable[scrollKey] = math.max(0, currentScroll + scrollDelta)
                end
                SED.ScrollDelta = 0
            end
        end
    else
        if SED.CandidateEnt and SED.KeyPressed(SED.INTERACT_KEY) and SED.InteractModifierDown() and not SED.PlayerIsHoldingSomething() then
            SED.EnterInteraction(SED.CandidateEnt, SED.CandidateIsNPC, SED.CandidateID)
        end
    end
end
