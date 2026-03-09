-- SED panel queue

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

-- Reusable render data pool to avoid per-frame closure allocation
local sedRenderPool = {}
local sedRenderPoolSize = 0
local sedActiveRender = {}
local sedActiveCount = 0

local function GetRenderData()
    local rdata
    if sedRenderPoolSize > 0 then
        rdata = sedRenderPool[sedRenderPoolSize]
        sedRenderPoolSize = sedRenderPoolSize - 1
    else
        rdata = {}
        -- Closure created once per pool slot, reused forever via upvalue binding
        rdata.fn = function()
            local tier = rdata.tier
            if tier == 2 then
                SED.DrawMarker(rdata.ent, rdata.saved, rdata.renderParams, rdata.distSqr)
            elseif tier == 1 then
                SED.DrawMiniPanel(rdata.ent, rdata.saved, rdata.isNPC, rdata.renderParams, rdata.distSqr)
            else
                SED.DrawSavedPanel(rdata.ent, rdata.saved, rdata.isNPC, rdata.renderParams, rdata.distSqr)
            end
        end
    end
    return rdata
end

local function RecycleRenderData()
    for i = 1, sedActiveCount do
        local rdata = sedActiveRender[i]
        rdata.ent = nil
        rdata.saved = nil
        rdata.renderParams = nil
        rdata.tier = nil
        sedRenderPoolSize = sedRenderPoolSize + 1
        sedRenderPool[sedRenderPoolSize] = rdata
        sedActiveRender[i] = nil
    end
    sedActiveCount = 0
end

function SED.QueueAllSavedPanels()
    SED.EnsureSavedLookup()
    SED.RescanLate()
    RecycleRenderData()

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos = SED.lpCache:EyePos()
    local eyeForward = SED.lpCache:EyeAngles():Forward()
    
    RecycleQueueList()
    
    local listCount = 0
    local invalidEntities = {}
    local invalidNPCs = {}

    local TrackedEntities = SED.TrackedEntities
    local TrackedNPCs = SED.TrackedNPCs
    local SAVED_ENTITIES_BY_ID = SED.SAVED_ENTITIES_BY_ID
    local SAVED_NPCS_BY_ID = SED.SAVED_NPCS_BY_ID
    local CalculateEntityRenderParams = SED.CalculateEntityRenderParams
    local DRAW_DISTANCE_SQR = SED.DRAW_DISTANCE_SQR
    local CULL_VIEW_CONE = SED.CULL_VIEW_CONE
    local FOV_COS_THRESHOLD = SED.FOV_COS_THRESHOLD
    local FOV_COS_THRESHOLD_SQR = SED.FOV_COS_THRESHOLD_SQR
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
                if CULL_VIEW_CONE and distSqr > NEARBY_DIST_SQR then
                    local dx, dy, dz = entPos.x - eyePos.x, entPos.y - eyePos.y, entPos.z - eyePos.z
                    local lenSqr = dx*dx + dy*dy + dz*dz
                    if lenSqr > 0 then
                        local dot = dx * eyeForward.x + dy * eyeForward.y + dz * eyeForward.z
                        withinView = (dot * dot) >= (FOV_COS_THRESHOLD_SQR * lenSqr)
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
                if CULL_VIEW_CONE and distSqr > NEARBY_DIST_SQR then
                    local dx, dy, dz = entPos.x - eyePos.x, entPos.y - eyePos.y, entPos.z - eyePos.z
                    local lenSqr = dx*dx + dy*dy + dz*dz
                    if lenSqr > 0 then
                        local dot = dx * eyeForward.x + dy * eyeForward.y + dz * eyeForward.z
                        withinView = (dot * dot) >= (FOV_COS_THRESHOLD_SQR * lenSqr)
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


    -- Simplified candidate detection: use pre-computed distSqr instead of expensive GetNearestDistanceSqr
    if not SED.InteractionState.active then
        local eyeFwd = eyeForward
        local distThresholdSqr = 40000
        local bestIdx = nil
        local bestDist = math.huge

        for i = 1, listCount do
            local item = queueList[i]
            if item and item.distSqr < distThresholdSqr then
                -- Use dot product alignment instead of expensive :Angle() + AngleDifference
                local dx, dy = item.pos.x - eyePos.x, item.pos.y - eyePos.y
                local lenSqr2D = dx*dx + dy*dy
                if lenSqr2D > 1 then
                    local dot2D = dx * eyeFwd.x + dy * eyeFwd.y
                    -- cos(12deg) ~= 0.978; check if looking roughly at entity
                    if dot2D * dot2D > 0.956 * lenSqr2D then
                        if item.distSqr < bestDist then
                            bestIdx = i
                            bestDist = item.distSqr
                        end
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
                SED.CandidateYawDiff = 0
            end
        end
    end

    table.sort(queueList, function(a, b) 
        if not a then return false end
        if not b then return true end
        return a.distSqr < b.distSqr 
    end)
    
    local maxQueue = math.min(listCount, SED.MAX_DRAW_PER_FRAME)

    local isFocusedEnt = SED.InteractionState.active and SED.InteractionState.ent
    local candidateEnt = SED.CandidateEnt
    local MINI_DIST_SQR = SED.MINI_PANEL_DIST_SQR

    for i = 1, maxQueue do
        local item = queueList[i]
        if item then
            local rdata = GetRenderData()
            rdata.ent = item.ent
            rdata.saved = item.saved
            rdata.isNPC = item.isNPC
            rdata.renderParams = item.renderParams
            rdata.distSqr = item.distSqr

            -- Tier: 0 = full (candidate/focused), 1 = mini (close), 2 = marker (far)
            if item.ent == isFocusedEnt or item.ent == candidateEnt then
                rdata.tier = 0
            elseif item.distSqr < MINI_DIST_SQR then
                rdata.tier = 1
            else
                rdata.tier = 2
            end

            sedActiveCount = sedActiveCount + 1
            sedActiveRender[sedActiveCount] = rdata
            RARELOAD.DepthRenderer.AddRenderItem(item.pos, rdata.fn, "entity")
        end
    end
end
