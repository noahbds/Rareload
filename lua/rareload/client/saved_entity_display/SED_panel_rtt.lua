SED     = SED or {}
SED.RTT = SED.RTT or {}

local RTT  = SED.RTT
RTT.RT_W   = 1024
RTT.RT_H   = 512

local POOL_MAX = 24
local pool     = {}
local keySlot  = {}
local lastUsed = {}
local ready    = false
local tick     = 0

local function Init()
    if ready then return end
    ready = true
    for i = 1, POOL_MAX do
        local name = "RARELOAD_SED_RT_" .. i
        local ok, rt = pcall(GetRenderTarget, name, RTT.RT_W, RTT.RT_H)
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
        lastUsed[i] = 0
    end
end

local function Acquire(sig)
    local existing = keySlot[sig]
    if existing and pool[existing] and pool[existing].sig == sig then
        tick = tick + 1
        lastUsed[existing] = tick
        return existing
    end

    local oldest, oldestTick = 1, lastUsed[1] or 0
    for i = 2, POOL_MAX do
        local t = lastUsed[i] or 0
        if t < oldestTick then oldest, oldestTick = i, t end
    end

    local evictedSig = pool[oldest] and pool[oldest].sig
    if evictedSig then keySlot[evictedSig] = nil end
    pool[oldest].sig = nil

    tick = tick + 1
    keySlot[sig] = oldest
    lastUsed[oldest] = tick
    return oldest
end

function RTT.BakePanel(sig, w, h, drawFn)
    Init()
    if w <= 0 or w > RTT.RT_W or h <= 0 or h > RTT.RT_H then return nil end

    local slot = Acquire(sig)
    local p = pool[slot]
    if not p or not p.rt then return nil end

    local oldW, oldH = ScrW(), ScrH()

    render.PushRenderTarget(p.rt)
    render.SetViewPort(0, 0, RTT.RT_W, RTT.RT_H)
    render.Clear(0, 0, 0, 0, true, true)
    cam.Start2D()
    render.OverrideAlphaWriteEnable(true, true)

    local ok, err = pcall(drawFn)

    render.OverrideAlphaWriteEnable(false)
    cam.End2D()
    render.SetViewPort(0, 0, oldW, oldH)
    render.PopRenderTarget()

    if not ok then
        ErrorNoHalt("[Rareload] SED RTT bake failed: " .. tostring(err) .. "\n")
        keySlot[sig] = nil
        p.sig = nil
        return nil
    end

    p.sig = sig
    p.u   = w / RTT.RT_W
    p.v   = h / RTT.RT_H
    return p.mat, p.u, p.v
end

function RTT.GetMat(sig)
    if not ready then return nil end
    local slot = keySlot[sig]
    if not slot then return nil end
    local p = pool[slot]
    if not p or p.sig ~= sig then return nil end
    tick = tick + 1
    lastUsed[slot] = tick
    return p.mat, p.u, p.v
end

function RTT.InvalidateAll()
    for k in pairs(keySlot) do keySlot[k] = nil end
    for i = 1, POOL_MAX do
        if pool[i] then pool[i].sig = nil end
        lastUsed[i] = 0
    end
    tick = 0
end

hook.Add("InitPostEntity", "RARELOAD_SED_RTT_MapChange", RTT.InvalidateAll)
hook.Add("OnScreenSizeChanged", "RARELOAD_SED_RTT_Resize", RTT.InvalidateAll)
