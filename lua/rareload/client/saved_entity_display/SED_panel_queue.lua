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

local function EstimatePanelAimPos(ent, renderParams, eyePos)
    if not IsValid(ent) then
        return eyePos
    end

    if not renderParams then
        return ent:GetPos()
    end

    local obbCenterLocal = (renderParams.obbMin + renderParams.obbMax) * 0.5
    local worldCenter = ent.LocalToWorld and ent:LocalToWorld(obbCenterLocal) or ent:GetPos()

    local worldTopZ = renderParams.worldTopZ
    if not worldTopZ then
        worldTopZ = worldCenter.z + (renderParams.size and renderParams.size.z or 40)
    end

    local baseZ
    if renderParams.isMassive then
        baseZ = worldTopZ + renderParams.buffer
    elseif renderParams.isLarge then
        baseZ = worldTopZ + renderParams.buffer * 0.7
    else
        baseZ = worldTopZ + renderParams.buffer * 0.45
    end

    local basePos = Vector(worldCenter.x, worldCenter.y, baseZ)
    local toCenter = worldCenter - eyePos
    local horiz = Vector(toCenter.x, toCenter.y, 0)
    if horiz:LengthSqr() < 1e-4 then
        return basePos
    end

    horiz:Normalize()
    local outwardAmount = math.Clamp(renderParams.maxDimension * 0.35, 30, 600)
    return basePos - horiz * outwardAmount
end

local function EstimatePanelScale(renderParams, distance)
    local distanceScale = math.Clamp(1 - (distance / (renderParams and renderParams.isLarge and 3000 or 2000)), 0.3, 1.5)
    local scale = (renderParams and renderParams.baseScale or SED.BASE_SCALE) * distanceScale
    if renderParams and renderParams.isMassive then
        scale = scale * 0.6
    end
    return math.Clamp(scale, SED.MIN_SCALE, SED.MAX_SCALE)
end

local function IsAimingEstimatedPanel(ent, renderParams, eyePos, eyeForward)
    if not IsValid(ent) then return false, nil, nil end

    local panelCenter = EstimatePanelAimPos(ent, renderParams, eyePos)
    local toPanel = panelCenter - eyePos
    local panelDistSqr = toPanel:LengthSqr()
    if panelDistSqr < 1 then return false, nil, nil end

    local panelDist = math.sqrt(panelDistSqr)
    local panelNormal = toPanel / panelDist
    local denom = eyeForward:Dot(panelNormal)
    if math.abs(denom) <= 1e-4 then return false, nil, nil end

    local t = toPanel:Dot(panelNormal) / denom
    if t <= 0 then return false, nil, nil end

    local hitPos = eyePos + eyeForward * t

    local ang = toPanel:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90

    local right = ang:Right()
    local up = ang:Up()
    local rel = hitPos - panelCenter
    local x = rel:Dot(right)
    local y = rel:Dot(up)

    local scale = EstimatePanelScale(renderParams, panelDist)

    -- Conservative panel bounds for candidate bootstrap.
    local estimatedWidth = (renderParams and renderParams.isLarge) and 620 or 520
    local estimatedHeight = 280
    local halfW = (estimatedWidth * 0.5) * scale
    local halfH = (estimatedHeight * 0.5) * scale

    if math.abs(x) <= halfW and math.abs(y) <= halfH then
        return true, panelDistSqr, panelCenter
    end

    return false, panelDistSqr, panelCenter
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
                    if distSqr > 0 then
                        local dot = dx * eyeForward.x + dy * eyeForward.y + dz * eyeForward.z
                        withinView = (dot > 0) and ((dot * dot) >= (FOV_COS_THRESHOLD_SQR * distSqr)) or false
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
                    if distSqr > 0 then
                        local dot = dx * eyeForward.x + dy * eyeForward.y + dz * eyeForward.z
                        withinView = (dot > 0) and ((dot * dot) >= (FOV_COS_THRESHOLD_SQR * distSqr)) or false
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


    -- Candidate detection via panel ray hit-test so aiming the entity body alone does not promote full panel.
    if not SED.InteractionState.active then
        local eyeFwd = eyeForward
        local distThresholdSqr = 250000
        local bestIdx = nil
        local bestDist = math.huge

        for i = 1, listCount do
            local item = queueList[i]
            if item then
                local hit, panelDistSqr = IsAimingEstimatedPanel(item.ent, item.renderParams, eyePos, eyeFwd)
                if hit and panelDistSqr and panelDistSqr < distThresholdSqr and panelDistSqr < bestDist then
                    bestIdx = i
                    bestDist = panelDistSqr
                end
            end
        end

        if bestIdx then
            local item = queueList[bestIdx]
            local saved = item and item.saved
            if saved then
                SED.CandidateEnt = item.ent
                SED.CandidateIsNPC = item.isNPC
                SED.CandidateID = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or saved.RareloadID or
                    ((saved.class or saved.Class or saved.ClassName or "unknown") .. "?")
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

    local occluders = {}
    local numOccluders = 0
    local scrH_factor = ScrH() * 0.7

    for i = 1, maxQueue do
        local item = queueList[i]
        if item then
            local isCandidateOrFocused = (item.ent == isFocusedEnt or item.ent == candidateEnt)
            local dist = math.sqrt(item.distSqr)
            local scale = EstimatePanelScale(item.renderParams, dist)

            local tier
            if isCandidateOrFocused then
                tier = 0
            elseif item.distSqr < MINI_DIST_SQR then
                tier = 1
            else
                tier = 2
            end

            local aimPos = EstimatePanelAimPos(item.ent, item.renderParams, eyePos)
            local scr = aimPos:ToScreen()
            local occluded = false

            local my_pW, my_pH
            if tier == 0 then
                my_pW, my_pH = 550, 320
            elseif tier == 1 then
                my_pW, my_pH = 260, 80
            else
                my_pW, my_pH = 120, 30
            end

            local screenScale = (scale * scrH_factor) / math.max(10, dist)
            local myCenterY = scr.y - (my_pH * screenScale * 0.5)

            if scr.visible and not isCandidateOrFocused then
                for j = 1, numOccluders do
                    local occ = occluders[j]
                    local dx = math.abs(scr.x - occ.x)
                    local dy = math.abs(myCenterY - occ.y)
                    -- generous occlusion bounds
                    if dx < occ.w and dy < occ.h then
                        occluded = true
                        break
                    end
                end
            end

            if not occluded then
                local rdata = GetRenderData()
                rdata.ent = item.ent
                rdata.saved = item.saved
                rdata.isNPC = item.isNPC
                rdata.renderParams = item.renderParams
                rdata.distSqr = item.distSqr
                rdata.tier = tier

                rdata.opts = rdata.opts or { skipCull = true, distSqr = 0 }
                rdata.opts.distSqr = item.distSqr

                sedActiveCount = sedActiveCount + 1
                sedActiveRender[sedActiveCount] = rdata
                RARELOAD.DepthRenderer.AddRenderItem(item.pos, rdata.fn, "entity", rdata.opts)

                if scr.visible then
                    numOccluders = numOccluders + 1
                    local halfW = (my_pW / 2) * screenScale
                    local fullH = my_pH * screenScale

                    -- Multiply bounds by 1.5 and guarantee a min size of 60 to hide tight clusters
                    local occludeW = math.max(halfW * 1.5, 60)
                    local occludeH = math.max((fullH / 2) * 1.5, 50)

                    local occ = occluders[numOccluders]
                    if not occ then
                        occ = {}
                        occluders[numOccluders] = occ
                    end
                    occ.x = scr.x
                    occ.y = myCenterY
                    occ.w = occludeW
                    occ.h = occludeH
                end
            end
        end
    end
end
