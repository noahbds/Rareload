SED = (RARELOAD and RARELOAD.SavedEntityDisplay) or SED
if not SED then return end

SED.ObjectPhantoms = SED.ObjectPhantoms or {}

local ObjectPhantom = SED.ObjectPhantom or {}
SED.ObjectPhantom = ObjectPhantom
if ObjectPhantom._initialized then return ObjectPhantom end

local REFRESH_INTERVAL    = 1.0
local VISIBILITY_INTERVAL = 0.5
local MOVED_AWAY_DIST_SQR = 8 * 8

local function CullDistanceSqr()
    local large = SED.LARGE_ENTITY_DRAW_DISTANCE or 2500
    return math.max(SED.DRAW_DISTANCE_SQR or (500 * 500), large * large)
end

local function IsClientDebugEnabled()
    if RARELOAD and RARELOAD.GetClientDebugEnabled then
        local ok, enabled = pcall(RARELOAD.GetClientDebugEnabled)
        if ok then return enabled == true end
    end
    return RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled == true
end

local function HasViewPhantomPermission()
    local lp = LocalPlayer()
    if IsValid(lp) and RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        return RARELOAD.Permissions.HasPermission(lp, "VIEW_PHANTOM")
    end
    return true
end

local function toVector(p)
    if not p then return nil end
    if isvector(p) then return p end
    if p.x and p.y and p.z then return Vector(p.x, p.y, p.z) end
    if p[1] and p[2] and p[3] then return Vector(p[1], p[2], p[3]) end
    return nil
end

local function toAngle(a)
    if not a then return Angle(0, 0, 0) end
    if isangle(a) then return a end
    if a.p and a.y and a.r then return Angle(a.p, a.y, a.r) end
    if a[1] and a[2] and a[3] then return Angle(a[1], a[2], a[3]) end
    return Angle(0, 0, 0)
end

local function BuildLiveByID()
    local liveByID = {}
    for ent, id in pairs(SED.TrackedEntities or {}) do
        if IsValid(ent) then liveByID[id] = ent end
    end
    for npc, id in pairs(SED.TrackedNPCs or {}) do
        if IsValid(npc) then liveByID[id] = npc end
    end
    return liveByID
end

local function EnsurePhantom(id, rec, isNPC)
    local existing = SED.ObjectPhantoms[id]
    if existing and IsValid(existing.phantom) then return existing end

    local pos = toVector(rec.pos)
    local model = rec.model
    if not pos or not model or model == "" then return nil end

    local phantom = ClientsideModel(model)
    if not IsValid(phantom) then return nil end

    local ang = toAngle(rec.ang)
    phantom:SetPos(pos)
    phantom:SetAngles(ang)
    phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
    phantom:SetMoveType(MOVETYPE_NONE)
    phantom:SetSolid(SOLID_NONE)
    phantom:SetNoDraw(true)
    phantom:SetColor(Color(0, 0, 0, 0))

    local data = {
        phantom = phantom,
        id      = id,
        isNPC   = isNPC,
        pos     = pos,
        ang     = ang,
        class   = rec.class,
        model   = model,
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
            local pos = toVector(rec.pos)
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
    local reveal = IsClientDebugEnabled() and HasViewPhantomPermission()
    local liveByID = reveal and BuildLiveByID() or nil

    for id, data in pairs(SED.ObjectPhantoms) do
        local phantom = data.phantom
        if IsValid(phantom) then
            local show = false
            if reveal then
                local live = liveByID[id]
                if not (live and IsValid(live)) then
                    show = true
                elseif live:GetPos():DistToSqr(data.pos) > MOVED_AWAY_DIST_SQR then
                    show = true
                end
            end

            if show then
                phantom:SetColor(Color(255, 255, 255, 150))
                phantom:SetNoDraw(false)
            else
                phantom:SetColor(Color(0, 0, 0, 0))
                phantom:SetNoDraw(true)
            end
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
    if not IsClientDebugEnabled() then
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
