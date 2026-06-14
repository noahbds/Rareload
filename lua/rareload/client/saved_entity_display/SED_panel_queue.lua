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
            SED.DrawSavedPanel(rdata.ent, rdata.saved, rdata.isNPC, rdata.renderParams, rdata.distSqr)
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
        sedRenderPoolSize                = sedRenderPoolSize + 1
        sedRenderPool[sedRenderPoolSize] = rdata
        sedActiveRender[i]               = nil
    end
    sedActiveCount = 0
end

local BOOTSTRAP_W = 520
local BOOTSTRAP_H = 280
local BOOTSTRAP_W_LARGE = 620

local math_sqrt = math.sqrt

local function SortQueue(a, b)
    if not a then return false end
    if not b then return true end
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.distSqr < b.distSqr
end

local function PanelAnchorZ(rp, posZ)
    local topZ = (rp and rp.worldTopZ) or (posZ + 40)
    local buf  = (rp and rp.buffer) or 20
    local mult = 0.45
    if rp then
        if rp.isMassive then mult = 1.0 elseif rp.isLarge then mult = 0.7 end
    end
    return topZ + buf * mult
end

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

local function CollectBucket(tracked, lookup, isNPC, eyePos, eyeForward, listCount, invalid)
    local CalcParams        = SED.CalculateEntityRenderParams
    local DRAW_DISTANCE_SQR = SED.DRAW_DISTANCE_SQR
    local CULL_VIEW_CONE    = SED.CULL_VIEW_CONE

    for ent, id in pairs(tracked) do
        if IsValid(ent) then
            local rec = lookup[id]
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
                    item.isNPC           = isNPC
                    item.distSqr         = distSqr
                    item.renderParams    = renderParams
                    item.pos             = entPos
                    item.priority        = isNPC and 1 or 0
                    queueList[listCount] = item
                end
            end
        elseif invalid then
            invalid[#invalid + 1] = ent
        end
    end

    return listCount
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

    local listCount       = 0
    local invalidEntities = {}
    local invalidNPCs     = {}

    listCount = CollectBucket(SED.TrackedEntities, SED.SAVED_ENTITIES_BY_ID, false, eyePos, eyeForward, listCount,
        invalidEntities)
    listCount = CollectBucket(SED.TrackedNPCs, SED.SAVED_NPCS_BY_ID, true, eyePos, eyeForward, listCount,
        invalidNPCs)

    local PHANTOM_SAVED = SED.PhantomSavedRecords or {}
    for phantom, steamID in pairs(SED.TrackedPhantoms or {}) do
        if IsValid(phantom) then
            local rec = PHANTOM_SAVED[steamID]
            if rec then
                local entPos       = phantom:GetPos()
                local distSqr      = eyePos:DistToSqr(entPos)
                local renderParams = SED.CalculateEntityRenderParams(phantom)
                local maxDistSqr   = renderParams and renderParams.drawDistanceSqr or SED.DRAW_DISTANCE_SQR

                if distSqr <= maxDistSqr and
                    (not SED.CULL_VIEW_CONE or SS.CullFOV(entPos, eyePos, eyeForward, distSqr)) then
                    listCount            = listCount + 1
                    local item           = GetQueueItem()
                    item.ent             = phantom
                    item.saved           = rec
                    item.isNPC           = false
                    item.distSqr         = distSqr
                    item.renderParams    = renderParams
                    item.pos             = entPos
                    item.priority        = 2
                    queueList[listCount] = item
                end
            end
        else
            SED.TrackedPhantoms[phantom] = nil
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

    if not SED.InteractionState.active then
        local distThresholdSqr = 250000
        local efx, efy, efz = eyeForward.x, eyeForward.y, eyeForward.z
        local epx, epy, epz = eyePos.x, eyePos.y, eyePos.z

        local bestIdx, bestCos = nil, 0.5
        for i = 1, listCount do
            local item = queueList[i]
            if item then
                local p = item.pos
                local dx = p.x - epx
                local dy = p.y - epy
                local dz = PanelAnchorZ(item.renderParams, p.z) - epz
                local len2 = dx * dx + dy * dy + dz * dz
                if len2 > 1 then
                    local d = dx * efx + dy * efy + dz * efz
                    if d > 0 then
                        local cos = d / math_sqrt(len2)
                        if cos > bestCos then bestCos = cos; bestIdx = i end
                    end
                end
            end
        end

        if bestIdx then
            local item = queueList[bestIdx]
            local hit, panelDistSqr = IsAimingEstimatedPanel(item.ent, item.renderParams, eyePos, eyeForward)
            if hit and panelDistSqr and panelDistSqr < distThresholdSqr then
                local saved = item.saved
                if saved then
                    SED.CandidateEnt   = item.ent
                    SED.CandidateIsNPC = item.isNPC
                    SED.CandidateID    = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or
                        saved.RareloadID or
                        ((saved.class or saved.Class or saved.ClassName or "unknown") .. "?")
                end
            end
        end
    end

    table.sort(queueList, SortQueue)

    local maxQueue = math.min(listCount, SED.MAX_DRAW_PER_FRAME)

    for i = 1, maxQueue do
        local item = queueList[i]
        if item then
            local rdata                     = GetRenderData()
            rdata.ent                       = item.ent
            rdata.saved                     = item.saved
            rdata.isNPC                     = item.isNPC
            rdata.renderParams              = item.renderParams
            rdata.distSqr                   = item.distSqr
            rdata.opts                      = rdata.opts or { skipCull = true, distSqr = 0 }
            rdata.opts.distSqr              = item.distSqr

            sedActiveCount                  = sedActiveCount + 1
            sedActiveRender[sedActiveCount] = rdata
            RARELOAD.DepthRenderer.AddRenderItem(item.pos, rdata.fn, "entity", rdata.opts)
        end
    end
end
