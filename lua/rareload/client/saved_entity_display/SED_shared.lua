-- SED_shared.lua
SED = SED or {}
SED.Shared = SED.Shared or {}

local SS = SED.Shared

local RS = SED.Require("RenderShared", "rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")

function SS.DrawHint(text, x, y, textColor, bgColor)
    RS.surface_SetFont("Trebuchet18")
    local textW = RS.surface_GetTextSize(text) or 0
    local padX, padY = 8, 2
    local boxW = textW + padX * 2
    local boxH = 18 + padY * 2
    RS.draw_RoundedBox(6, x - boxW * 0.5, y - boxH * 0.5, boxW, boxH, bgColor)
    RS.draw_SimpleText(text, "Trebuchet18", x, y, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function SS.FacingAngle(dir)
    local n = dir:GetNormalized()
    local ang = n:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90
    return ang
end

function SS.PanelScale(renderParams, distance, minScale, maxScale)
    minScale        = minScale or SED.MIN_SCALE
    maxScale        = maxScale or SED.MAX_SCALE
    local baseScale = (renderParams and renderParams.baseScale) or SED.BASE_SCALE
    return math.Clamp(baseScale, minScale, maxScale)
end

function SS.CullFOV(worldPos, eyePos, eyeForward, distSqr, nearbyDistSqr, fovCosSqr)
    nearbyDistSqr = nearbyDistSqr or (SED.NEARBY_DIST_SQR or (150 * 150))
    fovCosSqr     = fovCosSqr or (SED.FOV_COS_THRESHOLD_SQR or (math.cos(math.rad(50)) ^ 2))

    if distSqr <= nearbyDistSqr then return true end

    local dx = worldPos.x - eyePos.x
    local dy = worldPos.y - eyePos.y
    local dz = worldPos.z - eyePos.z
    if distSqr <= 0 then return true end

    local dot = dx * eyeForward.x + dy * eyeForward.y + dz * eyeForward.z
    return dot > 0 and (dot * dot) >= (fovCosSqr * distSqr)
end

function SS.PanelAimPos(ent, renderParams, eyePos)
    if not IsValid(ent) then return eyePos end

    local hitPos = ent:NearestPoint(eyePos)

    -- If player is essentially inside the entity's collision bounds
    if hitPos:DistToSqr(eyePos) < 1 then
        return ent:GetPos()
    end

    -- The direction from the surface to the player
    local rayDir = (eyePos - hitPos):GetNormalized()
    
    -- Place the panel 12 units off the surface towards the player
    return hitPos + rayDir * 12
end

function SS.PanelHitTest(panelCenter, ang, scale, panelW, panelH, eyePos, eyeForward)
    local panelNormal = (panelCenter - eyePos):GetNormalized()
    local denom       = eyeForward:Dot(panelNormal)
    if math.abs(denom) <= 1e-4 then return false, nil end

    local t = (panelCenter - eyePos):Dot(panelNormal) / denom
    if t <= 0 then return false, nil end

    local hitPos = eyePos + eyeForward * t
    local right  = ang:Right()
    local up     = ang:Up()
    local rel    = hitPos - panelCenter
    local x      = rel:Dot(right)
    local y      = rel:Dot(up)
    local halfW  = (panelW * 0.5) * scale
    local halfH  = (panelH * 0.5) * scale

    if math.abs(x) <= halfW and math.abs(y) <= halfH then
        return true, eyePos:DistToSqr(panelCenter)
    end
    return false, nil
end

function SS.PurgeExpired(cache, now)
    if not cache then return end
    for key, entry in pairs(cache) do
        if entry and entry.expires and entry.expires < now then
            cache[key] = nil
        end
    end
end

function SS.PruneOldest(cache, maxSize, now)
    if not cache then return end
    local count = table.Count(cache)
    if count <= maxSize then return end
    local entries = {}
    for key, entry in pairs(cache) do
        if entry and entry.expires then
            entries[#entries + 1] = { key = key, expires = entry.expires }
        end
    end
    table.sort(entries, function(a, b) return a.expires < b.expires end)
    for _, e in ipairs(entries) do
        if count <= maxSize then break end
        cache[e.key] = nil
        count = count - 1
    end
end

function SS.CleanCaches(now, maxSize, ...)
    for i = 1, select("#", ...) do
        local tbl = select(i, ...)
        SS.PurgeExpired(tbl, now)
        SS.PruneOldest(tbl, maxSize, now)
    end
end

-- ── Phantom / common helpers (shared by the object- and player-phantom systems) ──

local _debugVal  = false
local _debugTime = -1

function SS.DebugEnabled()
    local now = CurTime()
    if now - _debugTime < 0.5 then return _debugVal end
    _debugTime = now
    if RARELOAD and RARELOAD.GetClientDebugEnabled then
        local ok, v = pcall(RARELOAD.GetClientDebugEnabled)
        if ok then _debugVal = v == true; return _debugVal end
    end
    _debugVal = RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled == true
    return _debugVal
end

function SS.HasViewPhantomPerm()
    local lp = LocalPlayer()
    if IsValid(lp) and RARELOAD.Permissions and RARELOAD.Permissions.HasPermission then
        return RARELOAD.Permissions.HasPermission(lp, "VIEW_PHANTOM")
    end
    return true
end

function SS.ToVector(p)
    if not p then return nil end
    if isvector(p) then return p end
    if p.x and p.y and p.z then return Vector(p.x, p.y, p.z) end
    if p[1] and p[2] and p[3] then return Vector(p[1], p[2], p[3]) end
    return nil
end

function SS.ToAngle(a)
    if not a then return Angle(0, 0, 0) end
    if isangle(a) then return a end
    if a.p and a.y and a.r then return Angle(a.p, a.y, a.r) end
    if a[1] and a[2] and a[3] then return Angle(a[1], a[2], a[3]) end
    return Angle(0, 0, 0)
end

function SS.MakePhantomModel(model, pos, ang)
    if not model or model == "" then return nil end
    local phantom = ClientsideModel(model)
    if not IsValid(phantom) then return nil end
    phantom:SetPos(pos)
    phantom:SetAngles(ang or Angle(0, 0, 0))
    phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
    phantom:SetMoveType(MOVETYPE_NONE)
    phantom:SetSolid(SOLID_NONE)
    phantom:SetNoDraw(true)
    phantom:SetColor(Color(0, 0, 0, 0))
    return phantom
end

function SS.SetPhantomRevealed(phantom, show)
    if not IsValid(phantom) then return end
    if show then
        phantom:SetColor(Color(255, 255, 255, 150))
        phantom:SetNoDraw(false)
    else
        phantom:SetColor(Color(0, 0, 0, 0))
        phantom:SetNoDraw(true)
    end
end

function SS.BuildLiveByID()
    local liveByID = {}
    for ent, id in pairs(SED.TrackedEntities or {}) do
        if IsValid(ent) then liveByID[id] = ent end
    end
    for npc, id in pairs(SED.TrackedNPCs or {}) do
        if IsValid(npc) then liveByID[id] = npc end
    end
    return liveByID
end

SS._initialized = true
return SS
