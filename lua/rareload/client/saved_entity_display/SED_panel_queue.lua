local SS = SED.Require("Shared", "rareload/client/saved_entity_display/SED_shared.lua")

local EMPTY_GROUPS      = {} -- shared read-only placeholder for frames with nothing to group

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
            if rdata.group then
                SED.DrawPile(rdata.group)
            else
                SED.DrawSavedPanel(rdata.ent, rdata.saved, rdata.isNPC, rdata.renderParams, rdata.distSqr,
                    rdata.liveEnt)
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
        rdata.liveEnt                    = nil
        rdata.group                      = nil
        sedRenderPoolSize                = sedRenderPoolSize + 1
        sedRenderPool[sedRenderPoolSize] = rdata
        sedActiveRender[i]               = nil
    end
    sedActiveCount = 0
end

local function SortQueue(a, b)
    if not a then return false end
    if not b then return true end
    if a.distSqr ~= b.distSqr then return a.distSqr < b.distSqr end
    return a.priority < b.priority
end

-- Collect within draw distance only (NO view-cone cull here): grouping must see every nearby
-- member regardless of where the player looks, otherwise a member whose group-partner is behind
-- the camera would fall out of the group and leak back as a lone panel. The whole group is
-- view-culled later, at enqueue.
local function CollectObjectPhantoms(eyePos, listCount, liveByID)
    local CalcParams        = SED.CalculateEntityRenderParams
    local DRAW_DISTANCE_SQR = SED.DRAW_DISTANCE_SQR

    for id, data in pairs(SED.ObjectPhantoms or {}) do
        local phantom = data.phantom
        if IsValid(phantom) then
            local lookup = data.isNPC and SED.SAVED_NPCS_BY_ID or SED.SAVED_ENTITIES_BY_ID
            local rec    = lookup and lookup[id]
            if rec then
                local entPos       = phantom:GetPos()
                local distSqr      = eyePos:DistToSqr(entPos)
                local renderParams = CalcParams(phantom)
                local maxDistSqr   = renderParams and renderParams.drawDistanceSqr or DRAW_DISTANCE_SQR

                if distSqr <= maxDistSqr then
                    listCount            = listCount + 1
                    local item           = GetQueueItem()
                    item.ent             = phantom
                    item.saved           = rec
                    item.isNPC           = data.isNPC
                    item.distSqr         = distSqr
                    item.renderParams    = renderParams
                    item.pos             = entPos
                    item.priority        = data.isNPC and 1 or 0
                    item.liveEnt         = liveByID and liveByID[id] or nil
                    queueList[listCount] = item
                end
            end
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

    local listCount = 0

    local liveByID = SS.BuildLiveByID()

    listCount = CollectObjectPhantoms(eyePos, listCount, liveByID)

    local PHANTOM_SAVED = SED.PhantomSavedRecords or {}
    for phantom, steamID in pairs(SED.TrackedPhantoms or {}) do
        if IsValid(phantom) then
            local rec = PHANTOM_SAVED[steamID]
            if rec then
                local entPos       = phantom:GetPos()
                local distSqr      = eyePos:DistToSqr(entPos)
                local renderParams = SED.CalculateEntityRenderParams(phantom)
                local maxDistSqr   = renderParams and renderParams.drawDistanceSqr or SED.DRAW_DISTANCE_SQR

                if distSqr <= maxDistSqr then
                    listCount            = listCount + 1
                    local item           = GetQueueItem()
                    item.ent             = phantom
                    item.saved           = rec
                    item.isNPC           = false
                    item.distSqr         = distSqr
                    item.renderParams    = renderParams
                    item.pos             = entPos
                    item.priority        = 2
                    item.liveEnt         = nil
                    queueList[listCount] = item
                end
            end
        else
            SED.TrackedPhantoms[phantom] = nil
        end
    end

    -- Save Timeline preview phantoms: their own SED panels + interaction, depth-sorted.
    for _, pi in ipairs(SED.PreviewItems or {}) do
        local phantom = pi and pi.ent
        if IsValid(phantom) and pi.saved then
            local entPos       = phantom:GetPos()
            local distSqr      = eyePos:DistToSqr(entPos)
            local renderParams = SED.CalculateEntityRenderParams(phantom)
            local maxDistSqr   = renderParams and renderParams.drawDistanceSqr or SED.DRAW_DISTANCE_SQR
            if distSqr <= maxDistSqr then
                listCount            = listCount + 1
                local item           = GetQueueItem()
                item.ent             = phantom
                item.saved           = pi.saved
                item.isNPC           = pi.isNPC and true or false
                item.distSqr         = distSqr
                item.renderParams    = renderParams
                item.pos             = entPos
                item.priority        = 3
                item.liveEnt         = nil
                queueList[listCount] = item
            end
        end
    end

    if listCount == 0 then
        SED.ActiveGroups = EMPTY_GROUPS
        return
    end

    table.sort(queueList, SortQueue)

    local maxQueue = math.min(listCount, SED.MAX_DRAW_PER_FRAME)

    -- Cluster close saves into piles (each pile is one aim target); lone saves stay single panels.
    local groups     = SED.GroupQueue(queueList, maxQueue)
    SED.ActiveGroups = groups

    -- Anchor each pile on the member the player is looking at (not just the nearest), so it renders
    -- where they face. During interaction the view is locked, so this resolves to a stable anchor.
    SED.ResolveGroupAnchors(groups, eyePos, eyeForward)

    -- Pick the pile under the crosshair (skipped while already inspecting one).
    if not SED.InteractionState.active then
        SED.SelectCandidateGroup(groups, eyePos, eyeForward)
    end

    for g = 1, #groups do
        local grp    = groups[g]
        local anchor = grp.anchorItem

        -- View-cull the WHOLE group on its anchor (the nearest member). Collection no longer FOV-
        -- culls, so this is where off-screen groups are dropped -- and because a group is culled as
        -- a unit, a grouped member never leaks back as a lone panel when a partner is behind you.
        if not SED.CULL_VIEW_CONE or SS.CullFOV(anchor.pos, eyePos, eyeForward, anchor.distSqr) then
            local rdata        = GetRenderData()
            rdata.opts         = rdata.opts or { skipCull = true, distSqr = 0 }
            rdata.opts.distSqr = anchor.distSqr

            if #grp.members > 1 then
                rdata.group = grp
            else
                rdata.group        = nil
                rdata.ent          = anchor.ent
                rdata.saved        = anchor.saved
                rdata.isNPC        = anchor.isNPC
                rdata.renderParams = anchor.renderParams
                rdata.distSqr      = anchor.distSqr
                rdata.liveEnt      = anchor.liveEnt
            end

            sedActiveCount                  = sedActiveCount + 1
            sedActiveRender[sedActiveCount] = rdata
            RARELOAD.DepthRenderer.AddRenderItem(anchor.pos, rdata.fn, "entity", rdata.opts)
        end
    end
end
