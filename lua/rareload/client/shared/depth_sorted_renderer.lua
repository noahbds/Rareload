-- Depth-sorted 3D2D panel renderer

RARELOAD.DepthRenderer = RARELOAD.DepthRenderer or {}
RARELOAD.DepthRenderer.renderQueue = {}
RARELOAD.DepthRenderer.MAX_DISTANCE = 15000
RARELOAD.DepthRenderer.CULL_BEHIND = true
RARELOAD.DepthRenderer.USE_PCALL = false

-- Localize frequently used globals for micro-optimizations in hot paths
local tbl_insert = table.insert
local tbl_sort = table.sort
local tbl_empty = table.Empty -- GLua helper (empties table in-place)
local cam_IgnoreZ = cam.IgnoreZ
local _pcall = pcall
local _print = print
local _tostring = tostring
local _IsValid = IsValid
local _LocalPlayer = LocalPlayer

local maxDistSqr = RARELOAD.DepthRenderer.MAX_DISTANCE * RARELOAD.DepthRenderer.MAX_DISTANCE

-- Optional helper to change max distance at runtime without reload
function RARELOAD.DepthRenderer.SetMaxDistance(dist)
    dist = tonumber(dist) or RARELOAD.DepthRenderer.MAX_DISTANCE
    RARELOAD.DepthRenderer.MAX_DISTANCE = dist
    maxDistSqr = dist * dist
end

-- Adds a render item to the queue for depth-sorted rendering
function RARELOAD.DepthRenderer.AddRenderItem(pos, renderFunction, itemType, priorityOrOpts)
    if not pos or not renderFunction then return end

    local lp = _LocalPlayer()
    if not _IsValid(lp) then return end

    local eyePos = lp:EyePos()
    local delta = pos - eyePos
    local distSqr = delta:LengthSqr()

    if distSqr > maxDistSqr then return end

    if RARELOAD.DepthRenderer.CULL_BEHIND then
        -- EyeVector is cheaper than EyeAngles():Forward() and is available as a global on client
        local forward = EyeVector()
        if forward:Dot(delta) <= 0 then return end
    end

    local onTop = false
    local priority = 0

    if istable(priorityOrOpts) then
        priority = tonumber(priorityOrOpts.priority or 0) or 0
        onTop = tobool(priorityOrOpts.onTop)
    else
        priority = tonumber(priorityOrOpts or 0) or 0
    end

    tbl_insert(RARELOAD.DepthRenderer.renderQueue, {
        pos = pos,
        distanceSqr = distSqr,
        renderFunction = renderFunction,
        type = itemType or "unknown",
        priority = priority,
        onTop = onTop
    })
end

-- Processes and renders all queued items in depth-sorted order
function RARELOAD.DepthRenderer.ProcessRenderQueue()
    local queue = RARELOAD.DepthRenderer.renderQueue
    local n = #queue
    if n == 0 then return end

    if n > 1 then
        tbl_sort(queue, function(a, b)
            if a.onTop ~= b.onTop then
                return not a.onTop
            end
            if a.priority ~= b.priority then
                return a.priority > b.priority
            end
            return a.distanceSqr > b.distanceSqr
        end)
    end

    -- Find split point: non-top first (depth-tested), then on-top (ignore Z)
    local firstOnTopIndex
    for i = 1, n do
        if queue[i].onTop then
            firstOnTopIndex = i
            break
        end
    end

    local usePcall = RARELOAD.DepthRenderer.USE_PCALL

    -- Pass 1: render all non-top items
    local upto = firstOnTopIndex and (firstOnTopIndex - 1) or n
    for i = 1, upto do
        local item = queue[i]
        local fn = item and item.renderFunction
        if fn then
            if usePcall then
                local ok, err = _pcall(fn)
                if not ok then
                    _print("[DepthRenderer] Error rendering " .. (item.type or "unknown") .. ": " .. _tostring(err))
                end
            else
                fn()
            end
        end
    end

    -- Pass 2: render all on-top items within a single IgnoreZ block
    if firstOnTopIndex then
        cam_IgnoreZ(true)
        if usePcall then
            for i = firstOnTopIndex, n do
                local item = queue[i]
                local fn = item and item.renderFunction
                if fn then
                    local ok, err = _pcall(fn)
                    if not ok then
                        _print("[DepthRenderer] Error rendering " .. (item.type or "unknown") .. ": " .. _tostring(err))
                    end
                end
            end
        else
            for i = firstOnTopIndex, n do
                local item = queue[i]
                local fn = item and item.renderFunction
                if fn then fn() end
            end
        end
        cam_IgnoreZ(false)
    end

    -- Clear queue in-place to avoid reallocating a new table
    if tbl_empty then
        tbl_empty(queue)
    else
        RARELOAD.DepthRenderer.renderQueue = {}
    end
end

function RARELOAD.DepthRenderer.ClearQueue()
    local q = RARELOAD.DepthRenderer.renderQueue
    if tbl_empty then
        tbl_empty(q)
    else
        RARELOAD.DepthRenderer.renderQueue = {}
    end
end

hook.Add("PostDrawTranslucentRenderables", "RARELOAD_DepthSortedRenderer", function(bDepth, bSkybox)
    if bDepth then return end
    RARELOAD.DepthRenderer.ProcessRenderQueue()
end)

return RARELOAD.DepthRenderer
