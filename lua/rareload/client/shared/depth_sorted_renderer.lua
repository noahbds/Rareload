RARELOAD.DepthRenderer = RARELOAD.DepthRenderer or {}

local DepthRenderer = RARELOAD.DepthRenderer
local renderQueue = {}

DepthRenderer.renderQueue = renderQueue
DepthRenderer.MAX_DISTANCE = 15000
DepthRenderer.CULL_BEHIND = true
DepthRenderer.USE_PCALL = false

local tbl_sort = table.sort
local cam_IgnoreZ = cam.IgnoreZ
local _pcall = pcall
local _IsValid = IsValid
local _LocalPlayer = LocalPlayer
local FrameNumber = FrameNumber
local istable = istable
local tonumber = tonumber
local SysTime = SysTime

local maxDistSqr = DepthRenderer.MAX_DISTANCE * DepthRenderer.MAX_DISTANCE
local itemPool = {}
local poolSize = 0
local queueSize = 0

local cachedLP = nil
local cachedEyePosX, cachedEyePosY, cachedEyePosZ = 0, 0, 0
local cachedEyeVecX, cachedEyeVecY, cachedEyeVecZ = 0, 0, 0
local lastCacheFrame = -1

local function UpdateCache()
    local frame = FrameNumber()
    if lastCacheFrame == frame then return end
    lastCacheFrame = frame
    
    cachedLP = _LocalPlayer()
    if _IsValid(cachedLP) then
        local eyePos = cachedLP:EyePos()
        cachedEyePosX, cachedEyePosY, cachedEyePosZ = eyePos.x, eyePos.y, eyePos.z
        local eyeVec = cachedLP:EyeAngles():Forward()
        cachedEyeVecX, cachedEyeVecY, cachedEyeVecZ = eyeVec.x, eyeVec.y, eyeVec.z
    end
end

local function SortRenderItems(a, b)
    local aTop, bTop = a[5], b[5]
    if aTop ~= bTop then return not aTop end
    local aPri, bPri = a[4], b[4]
    if aPri ~= bPri then return aPri > bPri end
    return a[2] > b[2]
end

function DepthRenderer.SetMaxDistance(dist)
    dist = tonumber(dist) or DepthRenderer.MAX_DISTANCE
    DepthRenderer.MAX_DISTANCE = dist
    maxDistSqr = dist * dist
end

function DepthRenderer.AddRenderItem(pos, renderFunction, itemType, priorityOrOpts)
    if not pos or not renderFunction then return end

    UpdateCache()
    if not _IsValid(cachedLP) then return end

    local px, py, pz = pos.x, pos.y, pos.z
    local dx, dy, dz = px - cachedEyePosX, py - cachedEyePosY, pz - cachedEyePosZ
    local distSqr = dx * dx + dy * dy + dz * dz
    
    if distSqr > maxDistSqr then return end

    if DepthRenderer.CULL_BEHIND then
        if (dx * cachedEyeVecX + dy * cachedEyeVecY + dz * cachedEyeVecZ) <= 0 then return end
    end

    local onTop = false
    local priority = 0

    if istable(priorityOrOpts) then
        priority = tonumber(priorityOrOpts.priority) or 0
        onTop = priorityOrOpts.onTop or false
    else
        priority = tonumber(priorityOrOpts) or 0
    end

    local item
    if poolSize > 0 then
        item = itemPool[poolSize]
        poolSize = poolSize - 1
    else
        item = {}
    end

    item[1] = renderFunction
    item[2] = distSqr
    item[3] = itemType or "unknown"
    item[4] = priority
    item[5] = onTop

    queueSize = queueSize + 1
    renderQueue[queueSize] = item
end

DepthRenderer.FRAME_BUDGET = 0.005  -- 5ms hard budget per frame

function DepthRenderer.ProcessRenderQueue()
    local n = queueSize
    if n == 0 then return end

    if n > 1 then
        tbl_sort(renderQueue, SortRenderItems)
    end

    local firstOnTopIndex
    for i = 1, n do
        if renderQueue[i][5] then
            firstOnTopIndex = i
            break
        end
    end

    local upto = firstOnTopIndex and (firstOnTopIndex - 1) or n
    local budget = DepthRenderer.FRAME_BUDGET
    local startTime = SysTime()

    if DepthRenderer.USE_PCALL then
        for i = 1, upto do
            local fn = renderQueue[i][1]
            if fn then _pcall(fn) end
            if i % 3 == 0 and (SysTime() - startTime) > budget then break end
        end
        if firstOnTopIndex then
            cam_IgnoreZ(true)
            for i = firstOnTopIndex, n do
                local fn = renderQueue[i][1]
                if fn then _pcall(fn) end
            end
            cam_IgnoreZ(false)
        end
    else
        for i = 1, upto do
            local fn = renderQueue[i][1]
            if fn then fn() end
            if i % 3 == 0 and (SysTime() - startTime) > budget then break end
        end
        if firstOnTopIndex then
            cam_IgnoreZ(true)
            for i = firstOnTopIndex, n do
                local fn = renderQueue[i][1]
                if fn then fn() end
            end
            cam_IgnoreZ(false)
        end
    end

    for i = 1, n do
        local item = renderQueue[i]
        item[1] = nil
        poolSize = poolSize + 1
        itemPool[poolSize] = item
        renderQueue[i] = nil
    end
    queueSize = 0
end

function DepthRenderer.ClearQueue()
    for i = 1, queueSize do
        local item = renderQueue[i]
        item[1] = nil
        poolSize = poolSize + 1
        itemPool[poolSize] = item
        renderQueue[i] = nil
    end
    queueSize = 0
end

hook.Add("PostDrawTranslucentRenderables", "RARELOAD_DepthSortedRenderer", function(bDepth, bSkybox)
    if bDepth then return end
    DepthRenderer.ProcessRenderQueue()
end)

hook.Add("PreRender", "RARELOAD_DepthRenderer_UpdateCache", UpdateCache)

return DepthRenderer
