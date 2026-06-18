SED = (RARELOAD and RARELOAD.SavedEntityDisplay) or SED
if not SED then return end

local SS = SED.Require("Shared", "rareload/client/saved_entity_display/SED_shared.lua")

SED.ObjectPhantoms = SED.ObjectPhantoms or {}

local ObjectPhantom = SED.ObjectPhantom or {}
SED.ObjectPhantom = ObjectPhantom
if ObjectPhantom._initialized then return ObjectPhantom end

local REFRESH_INTERVAL    = 1.0
local VISIBILITY_INTERVAL = 0.5
local MOVED_AWAY_DIST_SQR = 8 * 8

local function CullDistanceSqr()
    return SED.PHANTOM_CULL_DIST_SQR
end

local function EnsurePhantom(id, rec, isNPC)
    local existing = SED.ObjectPhantoms[id]
    if existing and IsValid(existing.phantom) then return existing end

    local pos = SS.ToVector(rec.pos)
    if not pos then return nil end

    local ang = SS.ToAngle(rec.ang)
    local phantom = SS.MakePhantomModel(rec.model, pos, ang)
    if not phantom then return nil end

    local data = {
        phantom = phantom,
        id      = id,
        isNPC   = isNPC,
        pos     = pos,
        ang     = ang,
        class   = rec.class,
        model   = rec.model,
    }
    SED.ObjectPhantoms[id] = data
    return data
end

function ObjectPhantom.Refresh()
    if not (SED.EnsureSavedLookup and SED.SAVED_ENTITIES_BY_ID) then return end
    SED.EnsureSavedLookup()

    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local origin = lp:GetPos()
    local cullSqr = CullDistanceSqr()

    local function pass(lookup, isNPC)
        for id, rec in pairs(lookup or {}) do
            local pos = SS.ToVector(rec.pos)
            if pos and origin:DistToSqr(pos) <= cullSqr then
                EnsurePhantom(id, rec, isNPC)
            end
        end
    end
    pass(SED.SAVED_ENTITIES_BY_ID, false)
    pass(SED.SAVED_NPCS_BY_ID, true)

    for id, data in pairs(SED.ObjectPhantoms) do
        local lookup = data.isNPC and SED.SAVED_NPCS_BY_ID or SED.SAVED_ENTITIES_BY_ID
        local rec = lookup and lookup[id]
        local keep = rec and IsValid(data.phantom) and data.pos and
            origin:DistToSqr(data.pos) <= cullSqr
        if not keep then
            if IsValid(data.phantom) then data.phantom:Remove() end
            SED.ObjectPhantoms[id] = nil
        end
    end
end

function ObjectPhantom.UpdateVisibility()
    local reveal = SS.DebugEnabled() and SS.HasViewPhantomPerm()
    local liveByID = reveal and SS.BuildLiveByID() or nil

    for id, data in pairs(SED.ObjectPhantoms) do
        if IsValid(data.phantom) then
            local show = false
            if reveal then
                local live = liveByID[id]
                if not (live and IsValid(live)) then
                    show = true
                elseif live:GetPos():DistToSqr(data.pos) > MOVED_AWAY_DIST_SQR then
                    show = true
                end
            end
            SS.SetPhantomRevealed(data.phantom, show)
        end
    end
end

function ObjectPhantom.RemoveAll()
    for id, data in pairs(SED.ObjectPhantoms) do
        if IsValid(data.phantom) then data.phantom:Remove() end
        SED.ObjectPhantoms[id] = nil
    end
end

local nextRefresh, nextVis = 0, 0

hook.Add("Think", "RARELOAD_ObjectPhantom_Tick", function()
    if not SS.DebugEnabled() then
        if next(SED.ObjectPhantoms) then ObjectPhantom.RemoveAll() end
        return
    end

    local now = CurTime()
    if now >= nextRefresh then
        ObjectPhantom.Refresh()
        nextRefresh = now + REFRESH_INTERVAL
    end
    if now >= nextVis then
        ObjectPhantom.UpdateVisibility()
        nextVis = now + VISIBILITY_INTERVAL
    end
end)

hook.Add("RareloadPlayerPositionsUpdated", "RARELOAD_ObjectPhantom_Reset", function(mapName)
    if mapName ~= game.GetMap() then return end
    ObjectPhantom.RemoveAll()
    nextRefresh = 0
end)

ObjectPhantom._initialized = true
return ObjectPhantom
