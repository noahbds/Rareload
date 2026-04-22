-- SED_panel_queue.lua  (refactored)
-- Changes:
--   EstimatePanelAimPos   → SS.PanelAimPos
--   EstimatePanelScale    → SS.PanelScale
--   IsAimingEstimatedPanel→ SS.PanelHitTest  (with SS.FacingAngle for the angle)
--   FOV dot-product guard → SS.CullFOV
-- Everything else (pool, occlusion, queue sort) is unchanged.

local SS = SED.Shared
if not (SS and SS._initialized) then
    include("rareload/client/saved_entity_display/SED_shared.lua")
    SS = SED.Shared
end

local queueItemPool     = {}
local queueItemPoolSize = 0
local queueList         = {}

local function GetQueueItem()
    if queueItemPoolSize > 0 then
        local item = queueItemPool[queueItemPoolSize]
        queueItemPoolSize = queueItemPoolSize - 1
        return item
    end
    return {}
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

local sedRenderPool     = {}
local sedRenderPoolSize = 0
local sedActiveRender   = {}
local sedActiveCount    = 0

local function GetRenderData()
    local rdata
    if sedRenderPoolSize > 0 then
        rdata = sedRenderPool[sedRenderPoolSize]
        sedRenderPoolSize = sedRenderPoolSize - 1
    else
        rdata = {}
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
        local rdata                      = sedActiveRender[i]
        rdata.ent                        = nil
        rdata.saved                      = nil
        rdata.renderParams               = nil
        rdata.tier                       = nil
        sedRenderPoolSize                = sedRenderPoolSize + 1
        sedRenderPool[sedRenderPoolSize] = rdata
        sedActiveRender[i]               = nil
    end
    sedActiveCount = 0
end

-- Conservative hit-test used only for candidate bootstrap (before full render).
local BOOTSTRAP_W = 520
local BOOTSTRAP_H = 280
local BOOTSTRAP_W_LARGE = 620

local function IsAimingEstimatedPanel(ent, renderParams, eyePos, eyeForward)
    if not IsValid(ent) then return false, nil end

    local panelCenter  = SS.PanelAimPos(ent, renderParams, eyePos)
    local toPanel      = panelCenter - eyePos
    local panelDistSqr = toPanel:LengthSqr()
    if panelDistSqr < 1 then return false, nil end

    local distance = math.sqrt(panelDistSqr)
    local scale    = SS.PanelScale(renderParams, distance)
    local ang      = SS.FacingAngle(toPanel)
    local estW     = (renderParams and renderParams.isLarge) and BOOTSTRAP_W_LARGE or BOOTSTRAP_W

    local hit      = SS.PanelHitTest(panelCenter, ang, scale, estW, BOOTSTRAP_H, eyePos, eyeForward)
    return hit, panelDistSqr
end

function SED.QueueAllSavedPanels()
    SED.EnsureSavedLookup()
    SED.RescanLate()
    RecycleRenderData()

    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end

    local eyePos     = SED.lpCache:EyePos()
    local eyeForward = SED.lpCache:EyeAngles():Forward()

    RecycleQueueList()

    local listCount            = 0
    local invalidEntities      = {}
    local invalidNPCs          = {}

    local TrackedEntities      = SED.TrackedEntities
    local TrackedNPCs          = SED.TrackedNPCs
    local SAVED_ENTITIES_BY_ID = SED.SAVED_ENTITIES_BY_ID
    local SAVED_NPCS_BY_ID     = SED.SAVED_NPCS_BY_ID
    local CalcParams           = SED.CalculateEntityRenderParams
    local DRAW_DISTANCE_SQR    = SED.DRAW_DISTANCE_SQR
    local CULL_VIEW_CONE       = SED.CULL_VIEW_CONE

    for ent, id in pairs(TrackedEntities) do
        if IsValid(ent) then
            local rec = SAVED_ENTITIES_BY_ID[id]
            if rec then
                local entPos       = ent:GetPos()
                local distSqr      = eyePos:DistToSqr(entPos)
                local renderParams = CalcParams(ent)
                local maxDistSqr   = renderParams and renderParams.drawDistanceSqr or DRAW_DISTANCE_SQR

                if distSqr <= maxDistSqr and
                    (not CULL_VIEW_CONE or SS.CullFOV(entPos, eyePos, eyeForward, distSqr)) then
                    listCount            = listCount + 1
                    local item           = GetQueueItem()
                    item.ent             = ent
                    item.saved           = rec
                    item.isNPC           = false
                    item.distSqr         = distSqr
                    item.renderParams    = renderParams
                    item.pos             = entPos
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
                local entPos       = npc:GetPos()
                local distSqr      = eyePos:DistToSqr(entPos)
                local renderParams = CalcParams(npc)
                local maxDistSqr   = renderParams and renderParams.drawDistanceSqr or DRAW_DISTANCE_SQR

                if distSqr <= maxDistSqr and
                    (not CULL_VIEW_CONE or SS.CullFOV(entPos, eyePos, eyeForward, distSqr)) then
                    listCount            = listCount + 1
                    local item           = GetQueueItem()
                    item.ent             = npc
                    item.saved           = rec
                    item.isNPC           = true
                    item.distSqr         = distSqr
                    item.renderParams    = renderParams
                    item.pos             = entPos
                    queueList[listCount] = item
                end
            end
        else
            invalidNPCs[#invalidNPCs + 1] = npc
        end
    end

    for i = 1, #invalidEntities do
        local ent = invalidEntities[i]
        SED.TrackedEntities[ent] = nil
        local idx = ent:EntIndex()
        if SED.EntityBoundsCache and idx then SED.EntityBoundsCache[idx] = nil end
    end
    for i = 1, #invalidNPCs do
        local npc = invalidNPCs[i]
        SED.TrackedNPCs[npc] = nil
        local idx = npc:EntIndex()
        if SED.EntityBoundsCache and idx then SED.EntityBoundsCache[idx] = nil end
    end

    if listCount == 0 then return end

    -- Candidate detection
    if not SED.InteractionState.active then
        local distThresholdSqr = 250000
        local bestIdx, bestDist = nil, math.huge

        for i = 1, listCount do
            local item = queueList[i]
            if item then
                local hit, panelDistSqr = IsAimingEstimatedPanel(item.ent, item.renderParams, eyePos, eyeForward)
                if hit and panelDistSqr and panelDistSqr < distThresholdSqr and panelDistSqr < bestDist then
                    bestIdx = i
                    bestDist = panelDistSqr
                end
            end
        end

        if bestIdx then
            local item  = queueList[bestIdx]
            local saved = item and item.saved
            if saved then
                SED.CandidateEnt     = item.ent
                SED.CandidateIsNPC   = item.isNPC
                SED.CandidateID      = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or
                    saved.RareloadID or
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

    local maxQueue      = math.min(listCount, SED.MAX_DRAW_PER_FRAME)
    local isFocusedEnt  = SED.InteractionState.active and SED.InteractionState.ent
    local candidateEnt  = SED.CandidateEnt
    local MINI_DIST_SQR = SED.MINI_PANEL_DIST_SQR
    local occluders     = {}
    local numOccluders  = 0
    local scrH_factor   = ScrH() * 0.7

    for i = 1, maxQueue do
        local item = queueList[i]
        if item then
            local isCandidateOrFocused = (item.ent == isFocusedEnt or item.ent == candidateEnt)
            local dist                 = math.sqrt(item.distSqr)
            local scale                = SS.PanelScale(item.renderParams, dist)

            local tier
            if isCandidateOrFocused then
                tier = 0
            elseif item.distSqr < MINI_DIST_SQR then
                tier = 1
            else
                tier = 2
            end

            local aimPos   = SS.PanelAimPos(item.ent, item.renderParams, eyePos)
            local scr      = aimPos:ToScreen()
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
            local myCenterY   = scr.y - (my_pH * screenScale * 0.5)

            if scr.visible and not isCandidateOrFocused then
                for j = 1, numOccluders do
                    local occ = occluders[j]
                    if math.abs(scr.x - occ.x) < occ.w and math.abs(myCenterY - occ.y) < occ.h then
                        occluded = true
                        break
                    end
                end
            end

            if not occluded then
                local rdata                     = GetRenderData()
                rdata.ent                       = item.ent
                rdata.saved                     = item.saved
                rdata.isNPC                     = item.isNPC
                rdata.renderParams              = item.renderParams
                rdata.distSqr                   = item.distSqr
                rdata.tier                      = tier
                rdata.opts                      = rdata.opts or { skipCull = true, distSqr = 0 }
                rdata.opts.distSqr              = item.distSqr

                sedActiveCount                  = sedActiveCount + 1
                sedActiveRender[sedActiveCount] = rdata
                RARELOAD.DepthRenderer.AddRenderItem(item.pos, rdata.fn, "entity", rdata.opts)

                if scr.visible then
                    numOccluders            = numOccluders + 1
                    local halfW             = (my_pW * 0.5) * screenScale
                    local fullH             = my_pH * screenScale
                    local occludeW          = math.max(halfW * 1.5, 60)
                    local occludeH          = math.max((fullH * 0.5) * 1.5, 50)
                    local occ               = occluders[numOccluders] or {}
                    occluders[numOccluders] = occ
                    occ.x                   = scr.x
                    occ.y                   = myCenterY
                    occ.w                   = occludeW
                    occ.h                   = occludeH
                end
            end
        end
    end
end
