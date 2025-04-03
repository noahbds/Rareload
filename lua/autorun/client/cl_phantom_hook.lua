-- Constants for improved readability
local KEY_PRESS_DELAY = 0.2
local VERTICAL_SCROLL_SPEED = 5
local MAX_PHANTOM_DISTANCE_SQR = 90000
local AUDIO_CLICK = "ui/buttonclick.wav"
local AUDIO_CLICK_RELEASE = "ui/buttonclickrelease.wav"
local AUDIO_ROLLOVER = "ui/buttonrollover.wav"

local originalViewData = nil

hook.Remove("GUIMousePressed", "PhantomPanelInteraction")

-- Helper function to handle category changes
local function changeCategory(cache, newIndex)
    if not cache then return end

    -- Wrap around category index
    if newIndex < 1 then newIndex = #PHANTOM_CATEGORIES end
    if newIndex > #PHANTOM_CATEGORIES then newIndex = 1 end

    local oldCategory = cache.activeCategory
    cache.activeCategory = PHANTOM_CATEGORIES[newIndex][1]
    cache.categoryChanged = CurTime()

    if oldCategory ~= cache.activeCategory then
        surface.PlaySound(AUDIO_ROLLOVER)

        local newContent = cache.data[cache.activeCategory]
        if newContent then
            local optimalWidth = CalculateOptimalPanelSize(newContent)
        end
    end

    -- Set key cooldown
    cache.keyHeld = true
    timer.Simple(KEY_PRESS_DELAY, function()
        if cache then cache.keyHeld = false end
    end)
end

-- Helper function to handle scrolling
local function handleScroll(entityID, category, amount, maxScroll)
    if not ScrollPersistence[entityID] or not category then return end

    local currentScroll = ScrollPersistence[entityID][category] or 0
    local newScroll = math.Clamp(currentScroll + amount, 0, maxScroll or 0)
    ScrollPersistence[entityID][category] = newScroll
end

hook.Add("Think", "PhantomKeyboardNavigation", function()
    if not PhantomInteractionMode or not PhantomInteractionTarget then return end

    local cache = PhantomInfoCache[PhantomInteractionTarget]
    if not cache or not cache.panelInfo then return end

    local panelInfo = cache.panelInfo
    local activeIndex = panelInfo.activeTabIndex
    local activeCategory = cache.activeCategory

    if not activeIndex then return end

    -- Handle horizontal navigation (category switching)
    if input.IsKeyDown(KEY_LEFT) and not cache.keyHeld then
        changeCategory(cache, activeIndex - 1)
    elseif input.IsKeyDown(KEY_RIGHT) and not cache.keyHeld then
        changeCategory(cache, activeIndex + 1)
    end

    -- Handle vertical scrolling
    if input.IsKeyDown(KEY_UP) then
        handleScroll(PhantomInteractionTarget, activeCategory, -VERTICAL_SCROLL_SPEED)
    elseif input.IsKeyDown(KEY_DOWN) then
        handleScroll(PhantomInteractionTarget, activeCategory, VERTICAL_SCROLL_SPEED, cache.maxScrollOffset)
    end
end)

hook.Add("StartCommand", "PhantomBlockMovement", function(ply, cmd)
    if ply ~= LocalPlayer() then return end

    if PhantomInteractionMode and PhantomInteractionTarget then
        cmd:ClearMovement()
        cmd:ClearButtons()
        cmd:SetMouseX(0)
        cmd:SetMouseY(0)

        -- Still allow use key
        if input.IsKeyDown(KEY_E) then
            cmd:SetButtons(IN_USE)
        end
    end
end)

hook.Add("PlayerBindPress", "PhantomBlockBindings", function(ply, bind, pressed)
    if not PhantomInteractionMode or not PhantomInteractionTarget then return end

    local cache = PhantomInfoCache[PhantomInteractionTarget]
    if not cache then return end

    local activeCategory = cache.activeCategory
    if activeCategory then
        -- Handle mousewheel scrolling
        if bind == "invprev" and pressed then
            handleScroll(PhantomInteractionTarget, activeCategory, -ScrollSpeed)
            return true
        elseif bind == "invnext" and pressed then
            handleScroll(PhantomInteractionTarget, activeCategory, ScrollSpeed, cache.maxScrollOffset)
            return true
        end
    end

    -- Allow use key but block other bindings
    if string.find(bind, "+use") then
        return false
    end

    return true
end)

hook.Add("CalcView", "PhantomInteractionView", function(ply, pos, angles, fov)
    if PhantomInteractionMode and PhantomInteractionTarget then
        -- Store original view data if not already stored
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

    -- Exit interaction mode if already active
    if PhantomInteractionMode then
        PhantomInteractionMode = false
        PhantomInteractionTarget = nil
        PhantomInteractionAngle = nil
        surface.PlaySound(AUDIO_CLICK_RELEASE)
        return
    end

    -- Find closest phantom entity
    local playerPos = ply:GetPos()
    local closestPhantom = nil
    local closestDistance = MAX_PHANTOM_DISTANCE_SQR + 1 -- Start beyond max distance

    for steamID, data in pairs(RARELOAD.Phantom) do
        if IsValid(data.phantom) and IsValid(data.ply) then
            local distance = playerPos:DistToSqr(data.phantom:GetPos())
            if distance < closestDistance then
                closestPhantom = steamID
                closestDistance = distance
            end
        end
    end

    -- Enter interaction mode with closest phantom if in range
    if closestPhantom and closestDistance < MAX_PHANTOM_DISTANCE_SQR then
        PhantomInteractionMode = true
        PhantomInteractionTarget = closestPhantom

        -- Initialize scroll persistence if needed
        ScrollPersistence[closestPhantom] = ScrollPersistence[closestPhantom] or {}

        -- Set interaction angle based on player's view
        local eyeYaw = LocalPlayer():EyeAngles().yaw
        PhantomInteractionAngle = Angle(0, eyeYaw - 90, 90)

        surface.PlaySound(AUDIO_CLICK)

        -- Calculate optimal panel size
        local cache = PhantomInfoCache[closestPhantom]
        if cache and cache.data and cache.activeCategory then
            local content = cache.data[cache.activeCategory]
            if content then
                local optimalWidth = CalculateOptimalPanelSize(content)
                PanelSizeMultiplier = optimalWidth / 350
            else
                PanelSizeMultiplier = 1.0
            end
            cache.categoryChanged = CurTime()
        else
            PanelSizeMultiplier = 1.0
        end
    end
end)
