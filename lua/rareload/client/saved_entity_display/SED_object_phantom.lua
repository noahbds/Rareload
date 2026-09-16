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

local function HasHighlightRevealTarget()
    local highlights = SED.Highlights
    if not highlights or not (SED.Highlight and SED.Highlight.IsActive) then return false end

    for _, entry in pairs(highlights) do
        if entry and entry.id ~= nil and (entry.kind == "saved" or entry.kind == "live2phantom") then
            if SED.Highlight.IsActive(entry.kind, entry.id) then
                return true
            end
        end
    end

    return false
end

local function ShouldRevealForHighlight(id, live, savedPos)
    if not (SED.Highlight and SED.Highlight.IsActive) then return false end
    if not (SED.Highlight.IsActive("saved", id) or SED.Highlight.IsActive("live2phantom", id)) then
        return false
    end
    if not IsValid(live) or not savedPos then return true end
    return live:GetPos():DistToSqr(savedPos) > MOVED_AWAY_DIST_SQR
end

local function CullDistanceSqr()
    return SED.PHANTOM_CULL_DIST_SQR
end

local function RemovePhantomEntry(data)
    if not data then return end
    if istable(data.subPhantoms) then
        for _, sub in ipairs(data.subPhantoms) do
            if IsValid(sub) then sub:Remove() end
        end
    end
    if IsValid(data.phantom) then
        data.phantom:Remove()
    end
end

-- Build the clientside phantom model for a saved record — model, angle (via DataUtils.ToAngle,
-- which parses every stored format), skin, bodygroups and sub-models — WITHOUT storing it. Shared
-- so the History preview renders identical phantoms to the debug display instead of reimplementing
-- spawning. The phantom starts hidden (MakePhantomModel); the caller reveals/tints it.
-- Returns phantom, subPhantoms, pos, ang.
function ObjectPhantom.CreateModel(rec)
    if not istable(rec) then return nil end
    local pos = RARELOAD.DataUtils.ToVector(rec.pos or rec.Pos)
    if not pos then return nil end

    local ang     = RARELOAD.DataUtils.ToAngle(rec.ang or rec.Angle or rec.Ang) or Angle(0, 0, 0)
    local model   = rec.model or rec.Model
    if isstring(model) and model ~= "" then util.PrecacheModel(model) end
    local phantom = SS.MakePhantomModel(model, pos, ang)
    if not phantom then return nil end

    local skin = rec.skin or rec.Skin
    if skin then phantom:SetSkin(skin) end
    if rec.material and rec.material ~= "" then phantom:SetMaterial(rec.material) end
    if rec.bodygroups and istable(rec.bodygroups) then
        for bgId, val in pairs(rec.bodygroups) do
            local numId = tonumber(bgId)
            if numId then phantom:SetBodygroup(numId, val) end
        end
    end

    local subPhantoms = SS.AttachSubModels(phantom, rec)
    return phantom, subPhantoms, pos, ang
end

-- Signature of the visual state a phantom is built from. If it is unchanged we
-- keep the existing clientside model instead of destroying and recreating it, so
-- a position sync that didn't touch this saved record costs nothing.
local function RecSig(rec)
    local p = rec.pos or rec.Pos
    local a = rec.ang or rec.Angle or rec.Ang
    local function r(v) return v and math.Round(v) or 0 end
    local px, py, pz, ap, ay, ar = 0, 0, 0, 0, 0, 0
    if istable(p) then px, py, pz = r(p.x or p[1]), r(p.y or p[2]), r(p.z or p[3]) end
    if istable(a) then ap, ay, ar = r(a.p or a[1]), r(a.y or a[2]), r(a.r or a[3]) end
    return table.concat({ rec.model or rec.Model or "", px, py, pz, ap, ay, ar,
        rec.skin or rec.Skin or 0, rec.material or "" }, "|")
end

local function EnsurePhantom(id, rec, isNPC)
    local sig = RecSig(rec)
    local existing = SED.ObjectPhantoms[id]
    if existing and IsValid(existing.phantom) and existing.sig == sig then
        return existing
    end
    if existing then
        RemovePhantomEntry(existing)
        SED.ObjectPhantoms[id] = nil
    end

    local phantom, subPhantoms, pos, ang = ObjectPhantom.CreateModel(rec)
    if not phantom then return nil end

    local data = {
        phantom     = phantom,
        subPhantoms = subPhantoms,
        id          = id,
        isNPC       = isNPC,
        pos         = pos,
        ang         = ang,
        class       = rec.class,
        model       = rec.model or rec.Model,
        sig         = sig,
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
            local pos = RARELOAD.DataUtils.ToVector(rec.pos)
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
            RemovePhantomEntry(data)
            SED.ObjectPhantoms[id] = nil
        end
    end
end

function ObjectPhantom.UpdateVisibility()
    local canView = SS.HasViewPhantomPerm()
    local reveal = SS.DebugEnabled() and canView
    local liveByID = (reveal or canView) and SS.BuildLiveByID() or nil

    for id, data in pairs(SED.ObjectPhantoms) do
        if IsValid(data.phantom) then
            local show = false
            local live = liveByID and liveByID[id] or nil
            if reveal then
                if not (IsValid(live) and data.pos) then
                    show = true
                elseif live:GetPos():DistToSqr(data.pos) > MOVED_AWAY_DIST_SQR then
                    show = true
                end
            elseif canView and ShouldRevealForHighlight(id, live, data.pos) then
                show = true
            end
            SS.SetPhantomRevealed(data.phantom, show)
        end
    end
end

function ObjectPhantom.RemoveAll()
    for id, data in pairs(SED.ObjectPhantoms) do
        RemovePhantomEntry(data)
        SED.ObjectPhantoms[id] = nil
    end
end

local nextRefresh, nextVis = 0, 0

hook.Add("Think", "RARELOAD_ObjectPhantom_Tick", function()
    local canView = SS.HasViewPhantomPerm()
    local reveal = SS.DebugEnabled() and canView
    local highlightReveal = canView and HasHighlightRevealTarget()

    if not reveal and not highlightReveal then
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
    -- Reconcile promptly, but incrementally: Refresh() keeps phantoms whose record
    -- is unchanged (same model/pos/ang/skin) and only rebuilds changed or new ones,
    -- so a routine position sync no longer destroys and recreates every phantom.
    nextRefresh = 0
end)

ObjectPhantom._initialized = true
return ObjectPhantom
