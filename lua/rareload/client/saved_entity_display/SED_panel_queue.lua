-- SED panel queue and culling logic

-- Optimization: Reuse tables to reduce GC
local queueItemPool = {}
local queueItemPoolSize = 0
local queueList = {}

local function GetQueueItem()
    local item
    if queueItemPoolSize > 0 then
        item = queueItemPool[queueItemPoolSize]
        queueItemPoolSize = queueItemPoolSize - 1
    else
        item = {}
    end
    return item
end

local function RecycleQueueList()
    for i = 1, #queueList do
        local item = queueList[i]
        if item then
            queueItemPoolSize = queueItemPoolSize + 1
            queueItemPool[queueItemPoolSize] = item
        end
        queueList[i] = nil
    end
end

function SED.QueueAllSavedPanels()
    SED.EnsureSavedLookup()
    SED.RescanLate()

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local eyeForward = SED.lpCache:EyeAngles():Forward()
    
    RecycleQueueList()
    
    local listCount = 0
    local invalidEntities = {}
    local invalidNPCs = {}

    -- Optimization: Localize variables for loop performance
    local TrackedEntities = SED.TrackedEntities
    local TrackedNPCs = SED.TrackedNPCs
    local SAVED_ENTITIES_BY_ID = SED.SAVED_ENTITIES_BY_ID
    local SAVED_NPCS_BY_ID = SED.SAVED_NPCS_BY_ID
    local CalculateEntityRenderParams = SED.CalculateEntityRenderParams
    local DRAW_DISTANCE_SQR = SED.DRAW_DISTANCE_SQR
    local CULL_VIEW_CONE = SED.CULL_VIEW_CONE
    local FOV_COS_THRESHOLD = SED.FOV_COS_THRESHOLD
    local NEARBY_DIST_SQR = SED.NEARBY_DIST_SQR

    for ent, id in pairs(TrackedEntities) do
        if IsValid(ent) then
            local rec = SAVED_ENTITIES_BY_ID[id]
            if rec then
                local entPos = ent:GetPos()
                local distSqr = eyePos:DistToSqr(entPos)
                local renderParams = CalculateEntityRenderParams(ent)
                local maxDistSqr = renderParams and renderParams.drawDistanceSqr or DRAW_DISTANCE_SQR

                local withinView = true
                if CULL_VIEW_CONE then
                    -- Optimization: Inline vector math to avoid object creation
                    local dx, dy, dz = entPos.x - eyePos.x, entPos.y - eyePos.y, entPos.z - eyePos.z
                    local lenSqr = dx*dx + dy*dy + dz*dz
                    if lenSqr > 0 then
                        local len = math.sqrt(lenSqr)
                        local dot = (dx/len) * eyeForward.x + (dy/len) * eyeForward.y + (dz/len) * eyeForward.z
                        withinView = (dot >= FOV_COS_THRESHOLD) or (distSqr <= NEARBY_DIST_SQR)
                    end
                end

                if distSqr <= maxDistSqr and withinView then
                    listCount = listCount + 1
                    local item = GetQueueItem()
                    item.ent = ent
                    item.saved = rec
                    item.isNPC = false
                    item.distSqr = distSqr
                    item.renderParams = renderParams
                    item.pos = entPos
                    queueList[listCount] = item
                end
            end
        else
            invalidEntities[#invalidEntities + 1] = ent
        end
    end

    for npc, id in pairs(TrackedNPCs) do
        if IsValid(npc) then
            local rec = SAVED_NPCS_BY_ID[id]
            if rec then
                local entPos = npc:GetPos()
                local distSqr = eyePos:DistToSqr(entPos)
                local renderParams = CalculateEntityRenderParams(npc)
                local maxDistSqr = renderParams and renderParams.drawDistanceSqr or DRAW_DISTANCE_SQR

                local withinView = true
                if CULL_VIEW_CONE then
                    local dx, dy, dz = entPos.x - eyePos.x, entPos.y - eyePos.y, entPos.z - eyePos.z
                    local lenSqr = dx*dx + dy*dy + dz*dz
                    if lenSqr > 0 then
                        local len = math.sqrt(lenSqr)
                        local dot = (dx/len) * eyeForward.x + (dy/len) * eyeForward.y + (dz/len) * eyeForward.z
                        withinView = (dot >= FOV_COS_THRESHOLD) or (distSqr <= NEARBY_DIST_SQR)
                    end
                end

                if distSqr <= maxDistSqr and withinView then
                    listCount = listCount + 1
                    local item = GetQueueItem()
                    item.ent = npc
                    item.saved = rec
                    item.isNPC = true
                    item.distSqr = distSqr
                    item.renderParams = renderParams
                    item.pos = entPos
                    queueList[listCount] = item
                end
            end
        else
            invalidNPCs[#invalidNPCs + 1] = npc
        end
    end

    for i = 1, #invalidEntities do
        SED.TrackedEntities[invalidEntities[i]] = nil
        local entIndex = invalidEntities[i]:EntIndex()
        if SED.EntityBoundsCache and entIndex then
            SED.EntityBoundsCache[entIndex] = nil
        end
    end
    for i = 1, #invalidNPCs do
        SED.TrackedNPCs[invalidNPCs[i]] = nil
        local entIndex = invalidNPCs[i]:EntIndex()
        if SED.EntityBoundsCache and entIndex then
            SED.EntityBoundsCache[entIndex] = nil
        end
    end

    if listCount == 0 then return end


    if not SED.InteractionState.active then
        local aimAng = SED.lpCache:EyeAngles()
        local yawThreshold = 12
        local distThresholdSqr = 40000

        local bestIdx = nil
        local bestDist = math.huge
        local bestYaw = math.huge

        for i = 1, listCount do
            local item = queueList[i]
            if item and item.ent and IsValid(item.ent) then
                local toEntAng = (item.pos - eyePos):Angle()
                local yawDiff = math.abs(math.AngleDifference(aimAng.y, toEntAng.y))
                local dSqr = item.renderParams and
                    select(1, SED.GetNearestDistanceSqr(item.ent, eyePos, item.renderParams))
                    or item.distSqr or eyePos:DistToSqr(item.ent:GetPos())

                local withinYaw = yawDiff < yawThreshold
                local withinDist = dSqr <
                    math.min(distThresholdSqr,
                        (item.renderParams and item.renderParams.drawDistanceSqr) or SED.DRAW_DISTANCE_SQR)

                if withinYaw and withinDist then
                    if (dSqr < bestDist) or (dSqr == bestDist and yawDiff < bestYaw) then
                        bestIdx = i
                        bestDist = dSqr
                        bestYaw = yawDiff
                    end
                end
            end
        end

        if bestIdx then
            local item = queueList[bestIdx]
            local saved = item and item.saved
            if saved then
                SED.CandidateEnt = item.ent
                SED.CandidateIsNPC = item.isNPC
                SED.CandidateID = saved.id or (saved.class .. "?")
                SED.CandidateYawDiff = bestYaw
            end
        end
    end

    table.sort(queueList, function(a, b) 
        if not a then return false end
        if not b then return true end
        return a.distSqr < b.distSqr 
    end)
    
    local maxQueue = math.min(listCount, SED.MAX_DRAW_PER_FRAME)

    for i = 1, maxQueue do
        local item = queueList[i]
        if item then
            local renderFunction = function()
                SED.DrawSavedPanel(item.ent, item.saved, item.isNPC)
            end
            RARELOAD.DepthRenderer.AddRenderItem(item.pos, renderFunction, "entity")
        end
    end
end

function SED.DrawAllSavedPanels()
    SED.EnsureSavedLookup()
    SED.RescanLate()

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local eyeForward = SED.lpCache:EyeAngles():Forward()
    local drawList = {}
    local listCount = 0
    local frameStartTime = SysTime()
    local invalidEntities = {}
    local invalidNPCs = {}

    for ent, id in pairs(SED.TrackedEntities) do
        if IsValid(ent) then
            local rec = SED.SAVED_ENTITIES_BY_ID[id]
            if rec then
                local entPos = ent:GetPos()
                local distSqr = eyePos:DistToSqr(entPos)
                local renderParams = SED.CalculateEntityRenderParams(ent)
                local maxDistSqr = renderParams and renderParams.drawDistanceSqr or SED.DRAW_DISTANCE_SQR

                local withinView = true
                if SED.CULL_VIEW_CONE then
                    local dir = entPos - eyePos
                    local len = dir:Length()
                    if len > 0 then
                        dir:Mul(1 / len)
                        local dot = dir:Dot(eyeForward)
                        withinView = (dot >= SED.FOV_COS_THRESHOLD) or (distSqr <= SED.NEARBY_DIST_SQR)
                    end
                end

                if distSqr <= maxDistSqr and withinView then
                    listCount = listCount + 1
                    drawList[listCount] = {
                        ent = ent,
                        saved = rec,
                        isNPC = false,
                        distSqr = distSqr,
                        renderParams = renderParams
                    }
                end
            end
        else
            invalidEntities[#invalidEntities + 1] = ent
        end
    end

    for npc, id in pairs(SED.TrackedNPCs) do
        if IsValid(npc) then
            local rec = SED.SAVED_NPCS_BY_ID[id]
            if rec then
                local entPos = npc:GetPos()
                local distSqr = eyePos:DistToSqr(entPos)

                local renderParams = SED.CalculateEntityRenderParams(npc)
                local maxDistSqr = renderParams and renderParams.drawDistanceSqr or SED.DRAW_DISTANCE_SQR

                local withinView = true
                if SED.CULL_VIEW_CONE then
                    local dir = entPos - eyePos
                    local len = dir:Length()
                    if len > 0 then
                        dir:Mul(1 / len)
                        local dot = dir:Dot(eyeForward)
                        withinView = (dot >= SED.FOV_COS_THRESHOLD) or (distSqr <= SED.NEARBY_DIST_SQR)
                    end
                end

                if distSqr <= maxDistSqr and withinView then
                    listCount = listCount + 1
                    drawList[listCount] = {
                        ent = npc,
                        saved = rec,
                        isNPC = true,
                        distSqr = distSqr,
                        renderParams = renderParams
                    }
                end
            end
        else
            invalidNPCs[#invalidNPCs + 1] = npc
        end
    end

    for i = 1, #invalidEntities do
        SED.TrackedEntities[invalidEntities[i]] = nil
        local entIndex = invalidEntities[i]:EntIndex()
        if SED.EntityBoundsCache and entIndex then
            SED.EntityBoundsCache[entIndex] = nil
        end
    end
    for i = 1, #invalidNPCs do
        SED.TrackedNPCs[invalidNPCs[i]] = nil
        local entIndex = invalidNPCs[i]:EntIndex()
        if SED.EntityBoundsCache and entIndex then
            SED.EntityBoundsCache[entIndex] = nil
        end
    end

    if listCount == 0 then return end

    table.sort(drawList, function(a, b) return a.distSqr < b.distSqr end)

    local timeBudget = SED.FrameRenderBudget
    local maxDraw = math.min(listCount, SED.MAX_DRAW_PER_FRAME)

    if SED.LastFrameRenderCount > SED.MAX_DRAW_PER_FRAME * 0.8 then
        maxDraw = math.max(10, maxDraw - 5)
    end

    local renderCount = 0
    local renderStartTime = SysTime()

    for i = 1, maxDraw do
        if i % 5 == 0 then
            local currentTime = SysTime()
            if (currentTime - renderStartTime) > timeBudget then
                break
            end
        end

        local item = drawList[i]
        if item then
            SED.DrawSavedPanel(item.ent, item.saved, item.isNPC)
            renderCount = renderCount + 1
        end
    end

    SED.LastFrameRenderCount = renderCount

    local totalFrameTime = SysTime() - frameStartTime
    if totalFrameTime > SED.FrameRenderBudget * 1.5 then
        SED.FrameRenderBudget = math.max(0.001, SED.FrameRenderBudget * 0.95)
    elseif totalFrameTime < SED.FrameRenderBudget * 0.5 then
        SED.FrameRenderBudget = math.min(0.008, SED.FrameRenderBudget * 1.05)
    end
end
