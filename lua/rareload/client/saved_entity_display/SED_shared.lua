-- SED_shared.lua
-- Shared helpers used by SED_panel_renderer_interaction, SED_panel_queue, SED_phantom,
-- and SED_entity_tracking.  Include this file early in SED_loader.lua, before any
-- of the files that previously duplicated these functions.
--
-- Every function is stored on SED.Shared so callers can do:
--   local SS = SED.Shared
--   SS.DrawHint(...)

SED = SED or {}
SED.Shared = SED.Shared or {}

local SS = SED.Shared
if SS._initialized then return SS end

local RS = SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED.RenderShared
end

-- ─── Hint rendering ───────────────────────────────────────────────────────────
-- Draws a pill-shaped label at (x, y) in the current cam.Start3D2D context.
-- Previously copy-pasted verbatim in _interaction.lua and _phantom.lua.

function SS.DrawHint(text, x, y, textColor, bgColor)
    RS.surface_SetFont("Trebuchet18")
    local textW = RS.surface_GetTextSize(text) or 0
    local padX, padY = 8, 2
    local boxW = textW + padX * 2
    local boxH = 18 + padY * 2
    RS.draw_RoundedBox(6, x - boxW * 0.5, y - boxH * 0.5, boxW, boxH, bgColor)
    RS.draw_SimpleText(text, "Trebuchet18", x, y, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- ─── Panel facing angle ───────────────────────────────────────────────────────
-- Given a direction vector (drawPos - eyePos) returns the Angle that makes a
-- 3D2D panel face the viewer.  The same three lines appeared in the full panel
-- renderer, mini renderer, marker renderer, and phantom renderer.

function SS.FacingAngle(dir)
    local n = dir:GetNormalized()
    local ang = n:Angle()
    ang.y = ang.y - 90
    ang.p = 0
    ang.r = 90
    return ang
end

-- ─── Panel scale ──────────────────────────────────────────────────────────────
-- Calculates the world-space scale for a 3D2D panel based on distance and
-- render params.  Previously inlined separately in SED_panel_queue.lua and
-- SED_phantom.lua.

function SS.PanelScale(renderParams, distance, minScale, maxScale)
    minScale        = minScale or SED.MIN_SCALE
    maxScale        = maxScale or SED.MAX_SCALE
    local baseScale = renderParams and renderParams.baseScale or SED.BASE_SCALE
    local farDist   = (renderParams and (renderParams.isLarge or renderParams.isMassive)) and 3000 or 2000
    local distScale = math.Clamp(1 - distance / farDist, 0.3, 1.5)
    local scale     = baseScale * distScale
    if renderParams and renderParams.isMassive then scale = scale * 0.6 end
    return math.Clamp(scale, minScale, maxScale)
end

-- ─── FOV culling ──────────────────────────────────────────────────────────────
-- Returns true when `worldPos` is within the view cone of `eyeForward`.
-- The same dot-product guard was duplicated in SED_panel_queue.lua and
-- SED_phantom.lua (and would have been needed for any future renderer).
--
-- Parameters
--   worldPos   Vector  position to test
--   eyePos     Vector  eye / camera origin
--   eyeForward Vector  unit forward vector of the camera
--   distSqr    number  squared distance (eyePos:DistToSqr(worldPos)), pass it
--                      in so the caller can reuse the value it already has
--   nearbyDistSqr   number  entities closer than this bypass the cone test
--   fovCosSqr       number  cos²(half-fov) threshold

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

-- ─── Panel aim position ───────────────────────────────────────────────────────
-- Estimates where the 3D2D panel for `ent` should sit in world space so the
-- viewer's crosshair can reach it.  Previously duplicated in SED_panel_queue.lua
-- (EstimatePanelAimPos) and inlined inside SED_phantom.lua.

function SS.PanelAimPos(ent, renderParams, eyePos)
    if not IsValid(ent) then return eyePos end
    if not renderParams then return ent:GetPos() end

    local obbCenterLocal = (renderParams.obbMin + renderParams.obbMax) * 0.5
    local worldCenter    = ent.LocalToWorld and ent:LocalToWorld(obbCenterLocal) or ent:GetPos()
    local worldTopZ      = renderParams.worldTopZ
    if not worldTopZ then
        worldTopZ = worldCenter.z + ((renderParams.size and renderParams.size.z) or 40)
    end

    local buf = renderParams.buffer or 20
    local baseZ
    if renderParams.isMassive then
        baseZ = worldTopZ + buf
    elseif renderParams.isLarge then
        baseZ = worldTopZ + buf * 0.7
    else
        baseZ = worldTopZ + buf * 0.45
    end

    local basePos = Vector(worldCenter.x, worldCenter.y, baseZ)
    local horiz   = Vector(worldCenter.x - eyePos.x, worldCenter.y - eyePos.y, 0)
    if horiz:LengthSqr() < 1e-4 then return basePos end

    horiz:Normalize()
    local outward = math.Clamp((renderParams.maxDimension or 40) * 0.35, 30, 600)
    return basePos - horiz * outward
end

-- ─── Panel ray hit-test ───────────────────────────────────────────────────────
-- Returns hit, panelDistSqr.
-- Previously: IsAimingEstimatedPanel() in SED_panel_queue.lua; the same math
-- was inlined in both SED_panel_renderer_interaction.lua and SED_phantom.lua.
--
-- panelCenter  Vector  world-space centre of the panel
-- ang          Angle   3D2D facing angle (from SS.FacingAngle)
-- scale        number  world-space scale
-- panelW       number  unscaled panel width  (in 2D units)
-- panelH       number  unscaled panel height (in 2D units)
-- eyePos       Vector
-- eyeForward   Vector  unit forward

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

-- ─── Cache helpers ────────────────────────────────────────────────────────────
-- PurgeExpired and PruneOldest were local-only in SED_entity_tracking.lua.
-- Phantom used a simpler ad-hoc approach.  Now both use these.

function SS.PurgeExpired(cache, now)
    if not cache then return end
    for key, entry in pairs(cache) do
        if entry and entry.expires and entry.expires < now then
            cache[key] = nil
        end
    end
end

function SS.PruneOldest(cache, maxSize, now)
    if not cache or table.Count(cache) <= maxSize then return end
    local oldestTime, oldestKey = now, nil
    for key, entry in pairs(cache) do
        if entry and entry.expires and entry.expires < oldestTime then
            oldestTime = entry.expires
            oldestKey  = key
        end
    end
    if oldestKey then cache[oldestKey] = nil end
end

-- Convenience: run both operations on a list of caches in one call.
-- Usage: SS.CleanCaches(now, 200, SED.EntityPanelCache, SED.NPCPanelCache, ...)
function SS.CleanCaches(now, maxSize, ...)
    for i = 1, select("#", ...) do
        local tbl = select(i, ...)
        SS.PurgeExpired(tbl, now)
        SS.PruneOldest(tbl, maxSize, now)
    end
end

SS._initialized = true
return SS
