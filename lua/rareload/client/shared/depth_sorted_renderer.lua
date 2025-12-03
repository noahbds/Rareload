RARELOAD.DepthRenderer = RARELOAD.DepthRenderer or {}
RARELOAD.DepthRenderer.renderQueue = {}
RARELOAD.DepthRenderer.MAX_DISTANCE = 15000
RARELOAD.DepthRenderer.CULL_BEHIND = true
RARELOAD.DepthRenderer.USE_PCALL = false

local tbl_insert = table.insert
local tbl_sort = table.sort
local cam_IgnoreZ = cam.IgnoreZ
local _pcall = pcall
local _print = print
local _tostring = tostring
local _IsValid = IsValid
local _LocalPlayer = LocalPlayer
local FrameNumber = FrameNumber

local maxDistSqr = RARELOAD.DepthRenderer.MAX_DISTANCE * RARELOAD.DepthRenderer.MAX_DISTANCE

-- Optimization: Item Pooling to reduce GC
local itemPool = {}
local poolSize = 0

-- Optimization: Frame Caching to reduce C++ calls
local cachedLP = nil
local cachedEyePos = Vector()
local cachedEyeVec = Vector()
local lastCacheFrame = 0

local function UpdateCache()
    local frame = FrameNumber()
    if lastCacheFrame == frame then return end
    lastCacheFrame = frame
    
    cachedLP = _LocalPlayer()
    if _IsValid(cachedLP) then
        cachedEyePos = cachedLP:EyePos()
        cachedEyeVec = cachedLP:EyeAngles():Forward()
    end
end

-- Optimization: External sort function to avoid closure creation
local function SortRenderItems(a, b)
    if a.onTop ~= b.onTop then
        return not a.onTop
    end
    if a.priority ~= b.priority then
        return a.priority > b.priority
    end
    return a.distanceSqr > b.distanceSqr
end

function RARELOAD.DepthRenderer.SetMaxDistance(dist)
    dist = tonumber(dist) or RARELOAD.DepthRenderer.MAX_DISTANCE
    RARELOAD.DepthRenderer.MAX_DISTANCE = dist
    maxDistSqr = dist * dist
end

function RARELOAD.DepthRenderer.AddRenderItem(pos, renderFunction, itemType, priorityOrOpts)
    if not pos or not renderFunction then return end

    UpdateCache()
    if not _IsValid(cachedLP) then return end

    -- Optimization: Use DistToSqr on existing vector to avoid creating new Vector
    local distSqr = pos:DistToSqr(cachedEyePos)
    if distSqr > maxDistSqr then return end

    if RARELOAD.DepthRenderer.CULL_BEHIND then
        -- Optimization: Component-wise dot product to avoid creating (pos - eyePos) vector
        local dx = pos.x - cachedEyePos.x
        local dy = pos.y - cachedEyePos.y
        local dz = pos.z - cachedEyePos.z
        if (dx * cachedEyeVec.x + dy * cachedEyeVec.y + dz * cachedEyeVec.z) <= 0 then return end
    end

    local onTop = false
    local priority = 0

    if istable(priorityOrOpts) then
        priority = tonumber(priorityOrOpts.priority or 0) or 0
        onTop = tobool(priorityOrOpts.onTop)
    else
        priority = tonumber(priorityOrOpts or 0) or 0
    end

    -- Optimization: Retrieve from pool
    local item
    if poolSize > 0 then
        item = itemPool[poolSize]
        poolSize = poolSize - 1
    else
        item = {}
    end

    item.pos = pos
    item.distanceSqr = distSqr
    item.renderFunction = renderFunction
    item.type = itemType or "unknown"
    item.priority = priority
    item.onTop = onTop

    local queue = RARELOAD.DepthRenderer.renderQueue
    queue[#queue + 1] = item
end

function RARELOAD.DepthRenderer.ProcessRenderQueue()
    local queue = RARELOAD.DepthRenderer.renderQueue
    local n = #queue
    if n == 0 then return end

    if n > 1 then
        tbl_sort(queue, SortRenderItems)
    end

    local firstOnTopIndex
    for i = 1, n do
        if queue[i].onTop then
            firstOnTopIndex = i
            break
        end
    end

    local usePcall = RARELOAD.DepthRenderer.USE_PCALL
    local upto = firstOnTopIndex and (firstOnTopIndex - 1) or n

    for i = 1, upto do
        local item = queue[i]
        local fn = item.renderFunction
        if fn then
            if usePcall then
                local ok, err = _pcall(fn)
                if not ok then _print("[DepthRenderer] Error: " .. _tostring(err)) end
            else
                fn()
            end
        end
    end

    if firstOnTopIndex then
        cam_IgnoreZ(true)
        for i = firstOnTopIndex, n do
            local item = queue[i]
            local fn = item.renderFunction
            if fn then
                if usePcall then
                    local ok, err = _pcall(fn)
                    if not ok then _print("[DepthRenderer] Error: " .. _tostring(err)) end
                else
                    fn()
                end
            end
        end
        cam_IgnoreZ(false)
    end

    -- Optimization: Return items to pool and clear queue
    for i = 1, n do
        local item = queue[i]
        item.renderFunction = nil
        item.pos = nil
        poolSize = poolSize + 1
        itemPool[poolSize] = item
        queue[i] = nil
    end
end

function RARELOAD.DepthRenderer.ClearQueue()
    local queue = RARELOAD.DepthRenderer.renderQueue
    local n = #queue
    for i = 1, n do
        local item = queue[i]
        item.renderFunction = nil
        item.pos = nil
        poolSize = poolSize + 1
        itemPool[poolSize] = item
        queue[i] = nil
    end
end

hook.Add("PostDrawTranslucentRenderables", "RARELOAD_DepthSortedRenderer", function(bDepth, bSkybox)
    if bDepth then return end
    RARELOAD.DepthRenderer.ProcessRenderQueue()
end)

hook.Add("PreRender", "RARELOAD_DepthRenderer_UpdateCache", UpdateCache)

return RARELOAD.DepthRenderer
