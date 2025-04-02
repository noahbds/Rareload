hook.Remove("GUIMousePressed", "PhantomPanelInteraction")

hook.Add("Think", "PhantomKeyboardNavigation", function()
    if not PhantomInteractionMode or not PhantomInteractionTarget then return end

    local cache = PhantomInfoCache[PhantomInteractionTarget]
    if not cache or not cache.panelInfo then return end

    local panelInfo = cache.panelInfo
    local activeIndex = panelInfo.activeTabIndex
    local activeCategory = cache.activeCategory

    if not activeIndex then return end

    if input.IsKeyDown(KEY_LEFT) and not cache.keyHeld then
        local newIndex = activeIndex - 1
        if newIndex < 1 then newIndex = #PHANTOM_CATEGORIES end

        local oldCategory = cache.activeCategory
        cache.activeCategory = PHANTOM_CATEGORIES[newIndex][1]
        cache.categoryChanged = CurTime()

        if oldCategory ~= cache.activeCategory then
            surface.PlaySound("ui/buttonrollover.wav")

            local newContent = cache.data[cache.activeCategory]
            local optimalWidth = CalculateOptimalPanelSize(newContent)
        end

        cache.keyHeld = true
        timer.Simple(0.2, function() cache.keyHeld = false end)
    elseif input.IsKeyDown(KEY_RIGHT) and not cache.keyHeld then
        local newIndex = activeIndex + 1
        if newIndex > #PHANTOM_CATEGORIES then newIndex = 1 end

        local oldCategory = cache.activeCategory
        cache.activeCategory = PHANTOM_CATEGORIES[newIndex][1]
        cache.categoryChanged = CurTime()

        if oldCategory ~= cache.activeCategory then
            surface.PlaySound("ui/buttonrollover.wav")

            local newContent = cache.data[cache.activeCategory]
            local optimalWidth = CalculateOptimalPanelSize(newContent)
        end

        cache.keyHeld = true
        timer.Simple(0.2, function() cache.keyHeld = false end)
    end

    if input.IsKeyDown(KEY_UP) then
        if ScrollPersistence[PhantomInteractionTarget] and activeCategory then
            local newScroll = math.max(0, (ScrollPersistence[PhantomInteractionTarget][activeCategory] or 0) - 5)
            ScrollPersistence[PhantomInteractionTarget][activeCategory] = newScroll
        end
    elseif input.IsKeyDown(KEY_DOWN) then
        if ScrollPersistence[PhantomInteractionTarget] and activeCategory then
            local maxScroll = (cache.maxScrollOffset or 0)
            local newScroll = math.min(maxScroll,
                (ScrollPersistence[PhantomInteractionTarget][activeCategory] or 0) + 5)
            ScrollPersistence[PhantomInteractionTarget][activeCategory] = newScroll
        end
    end
end)

hook.Add("StartCommand", "PhantomBlockMovement", function(ply, cmd)
    if ply ~= LocalPlayer() then return end

    if PhantomInteractionMode and PhantomInteractionTarget then
        cmd:ClearMovement()
        cmd:ClearButtons()

        if input.IsKeyDown(KEY_E) then
            cmd:SetButtons(IN_USE)
        end
    end
end)

hook.Add("PlayerBindPress", "PhantomBlockBindings", function(ply, bind, pressed)
    if PhantomInteractionMode and PhantomInteractionTarget then
        local cache = PhantomInfoCache[PhantomInteractionTarget]
        if cache and cache.activeCategory then
            local activeCategory = cache.activeCategory

            if bind == "invprev" and pressed then
                if ScrollPersistence[PhantomInteractionTarget] then
                    local newScroll = math.max(0,
                        (ScrollPersistence[PhantomInteractionTarget][activeCategory] or 0) - ScrollSpeed)
                    ScrollPersistence[PhantomInteractionTarget][activeCategory] = newScroll
                end
                return true
            elseif bind == "invnext" and pressed then
                if ScrollPersistence[PhantomInteractionTarget] then
                    local maxScroll = (cache.maxScrollOffset or 0)
                    local newScroll = math.min(maxScroll,
                        (ScrollPersistence[PhantomInteractionTarget][activeCategory] or 0) + ScrollSpeed)
                    ScrollPersistence[PhantomInteractionTarget][activeCategory] = newScroll
                end
                return true
            end
        end

        if string.find(bind, "+use") then
            return false
        end

        return true
    end
end)

local originalViewData = nil
hook.Add("CalcView", "PhantomInteractionView", function(ply, pos, angles, fov)
    if PhantomInteractionMode and PhantomInteractionTarget then
        if not originalViewData then
            originalViewData = {
                pos = pos,
                angles = angles,
                fov = fov
            }
        end

        return {
            origin = originalViewData.pos,
            angles = originalViewData.angles,
            fov = originalViewData.fov,
            drawviewer = false
        }
    else
        originalViewData = nil
    end
end)

hook.Add("KeyPress", "PhantomInteractionToggle", function(ply, key)
    if not IsValid(ply) or not ply:IsPlayer() or ply ~= LocalPlayer() then return end
    if key ~= IN_USE then return end

    local playerPos = ply:GetPos()
    local mapName = game.GetMap()

    if PhantomInteractionMode then
        PhantomInteractionMode = false
        PhantomInteractionTarget = nil
        PhantomInteractionAngle = nil
        surface.PlaySound("ui/buttonclickrelease.wav")
        return
    end

    local closestPhantom = nil
    local closestDistance = 10000

    for steamID, data in pairs(RARELOAD.Phantom) do
        if IsValid(data.phantom) and IsValid(data.ply) then
            local distance = playerPos:DistToSqr(data.phantom:GetPos())
            if distance < closestDistance then
                closestPhantom = steamID
                closestDistance = distance
            end
        end
    end

    if closestPhantom and closestDistance < 90000 then
        PhantomInteractionMode = true
        PhantomInteractionTarget = closestPhantom

        if not ScrollPersistence[closestPhantom] then
            ScrollPersistence[closestPhantom] = {}
        end

        local eyeYaw = LocalPlayer():EyeAngles().yaw
        PhantomInteractionAngle = Angle(0, eyeYaw - 90, 90)

        surface.PlaySound("ui/buttonclick.wav")

        local cache = PhantomInfoCache[closestPhantom]
        if cache and cache.data and cache.activeCategory then
            local content = cache.data[cache.activeCategory]
            local optimalWidth = CalculateOptimalPanelSize(content)
            PanelSizeMultiplier = optimalWidth / 350
            cache.categoryChanged = CurTime()
        else
            PanelSizeMultiplier = 1.0
        end
    end
end)
