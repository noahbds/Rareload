-- RTT (render-to-texture) pool for SED full panels.
-- An SED panel is static formatted JSON, so we bake its pixels once into a pooled
-- render target and then blit that texture every frame. A cache miss happens only
-- on first appearance, a tab/scroll change, or a data update.

SED       = SED or {}
SED.RTT   = SED.RTT or {}

local RTT  = SED.RTT
RTT.RT_W   = 1024 -- must cover the widest panel (large entities clamp to 1000)
RTT.RT_H   = 512  -- must cover the tallest panel (~300 in practice)

local POOL_MAX = 16 -- pooled render targets; 16 * 1024*512*4 = 32 MB VRAM
local pool     = {} -- slot -> { rt, mat, sig, u, v }
local keySlot  = {} -- bakeSig -> slot index
local slotAge  = {} -- slot -> FrameNumber of last use
local ready    = false

local ScrW = ScrW
local ScrH = ScrH

local function Init()
    if ready then return end
    ready = true
    for i = 1, POOL_MAX do
        local name = "RARELOAD_SED_RT_" .. i
        -- Pure 2D content with no depth/stencil, so a depth-less RT is enough.
        local ok, rt = pcall(GetRenderTargetEx, name, RTT.RT_W, RTT.RT_H,
            RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_BGRA8888)
        if ok and rt then
            local mat = CreateMaterial(name .. "_mat", "UnlitGeneric", {
                ["$basetexture"] = rt:GetName(),
                ["$translucent"] = "1",
                ["$vertexcolor"] = "1",
                ["$vertexalpha"] = "1",
                ["$nocull"]      = "1",
            })
            pool[i] = { rt = rt, mat = mat, sig = nil, u = 1, v = 1 }
        end
        slotAge[i] = 0
    end
end

local function Acquire(sig)
    local existing = keySlot[sig]
    if existing and pool[existing] then
        slotAge[existing] = FrameNumber()
        return existing
    end

    local oldest, oldestAge = 1, slotAge[1] or 0
    for i = 2, POOL_MAX do
        local a = slotAge[i] or 0
        if a < oldestAge then oldest, oldestAge = i, a end
    end

    local evictedSig = pool[oldest] and pool[oldest].sig
    if evictedSig then keySlot[evictedSig] = nil end
    pool[oldest].sig = nil

    keySlot[sig]    = oldest
    slotAge[oldest] = FrameNumber()
    return oldest
end

function RTT.BakePanel(sig, w, h, drawFn)
    Init()
    local slot = Acquire(sig)
    local p    = pool[slot]
    if not p or not p.rt then return nil end

    -- Push/Start are kept outside the pcall and their teardown runs unconditionally,
    -- so a throw inside drawFn can never leave the cam/RT stack unbalanced.
    render.PushRenderTarget(p.rt)
    render.Clear(0, 0, 0, 0, false, false) -- color only; RT has no depth/stencil
    cam.Start2D()
    local ok, err = pcall(drawFn)
    cam.End2D()
    render.PopRenderTarget()

    if not ok then
        ErrorNoHalt("[Rareload] SED RTT bake failed: " .. tostring(err) .. "\n")
        keySlot[sig] = nil
        p.sig = nil
        return nil
    end

    p.sig = sig
    p.u   = w / ScrW()
    p.v   = h / ScrH()
    return p.mat, p.u, p.v
end

function RTT.GetMat(sig)
    if not ready then return nil end
    local slot = keySlot[sig]
    if not slot then return nil end
    local p = pool[slot]
    if not p or p.sig ~= sig then return nil end
    slotAge[slot] = FrameNumber()
    return p.mat, p.u, p.v
end

function RTT.InvalidateAll()
    for k in pairs(keySlot) do keySlot[k] = nil end
    for i = 1, POOL_MAX do
        if pool[i] then pool[i].sig = nil end
        slotAge[i] = 0
    end
end

hook.Add("OnScreenSizeChanged", "RARELOAD_SED_RTT_Resize", function()
    RTT.InvalidateAll()
end)
