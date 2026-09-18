-- SED_shared.lua
SED = SED or {}
SED.Shared = SED.Shared or {}

local SS = SED.Shared

local RS = SED.Require("RenderShared", "rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")

if not (RARELOAD and RARELOAD.DataUtils and RARELOAD.DataUtils.ToVector) then
    include("rareload/utils/rareload_data_utils.lua")
end

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

-- Panel world size is proportional to the entity (renderParams.targetWorldWidth) and fixed in
-- world space: dividing the desired world width by the panel's pixel width yields the
-- world-units-per-pixel scale cam_Start3D2D expects. Because it ignores camera distance, the
-- panel no longer balloons up close and a huge NPC and a tiny prop each get a panel sized to
-- them; it shrinks with distance naturally, through perspective.
--
-- `panelWidthPx` is the panel's real pixel width (ctx.width) or a caller's hit-test estimate.
-- If it or the render params are missing we fall back to the old distance-based scale so
-- nothing ends up rendering at zero size.
function SS.PanelScale(renderParams, distance, panelWidthPx)
    local targetWorldWidth = renderParams and renderParams.targetWorldWidth
    local pixelW = panelWidthPx or SED.PANEL_REF_WIDTH or 480

    if targetWorldWidth and pixelW > 0 then
        return targetWorldWidth / pixelW
    end

    -- Legacy fallback: apparent size driven by camera distance.
    local baseScale = (renderParams and renderParams.baseScale) or SED.BASE_SCALE
    local refDist   = SED.REFERENCE_DIST or 512
    local dist      = math.max(distance or refDist, 1) -- avoid division by zero
    local scale     = (refDist / dist) * baseScale
    return math.Clamp(scale, SED.MIN_SCALE, SED.MAX_SCALE)
end

-- Cleaned up: recomputes distSqr internally, avoids parameter confusion
function SS.CullFOV(worldPos, eyePos, eyeForward, distSqr_ignored)
    local dx = worldPos.x - eyePos.x
    local dy = worldPos.y - eyePos.y
    local dz = worldPos.z - eyePos.z
    local distSqr = dx * dx + dy * dy + dz * dz

    local nearbyDistSqr = SED.NEARBY_DIST_SQR or (150 * 150)
    if distSqr <= nearbyDistSqr then return true end

    local fovCosSqr = SED.FOV_COS_THRESHOLD_SQR or (math.cos(math.rad(50)) ^ 2)

    local dot = dx * eyeForward.x + dy * eyeForward.y + dz * eyeForward.z
    return dot > 0 and (dot * dot) >= (fovCosSqr * distSqr)
end

-- Where a panel is drawn for `ent`, facing the player: just in FRONT of the model's near surface,
-- at the player's eye height. The reach toward the eye is measured HORIZONTALLY only (the OBB
-- support function in the horizontal view direction) so a tall model's height doesn't inflate it --
-- an inflated reach used to shove the panel toward the player when far and make it jump around. The
-- panel is anchored to the MODEL (a fixed world spot on its near side), so it does NOT drift toward
-- the camera as you approach; it just grows like a world-space label. Returns drawPos, angle, scale.
function SS.ComputePlacement(ent, renderParams, eyePos, distSqr, panelWidth)
    local scale = SS.PanelScale(renderParams, math.sqrt(distSqr), panelWidth)

    local mn, mx     = renderParams.obbMin, renderParams.obbMax
    local hx, hy, hz = (mx.x - mn.x) * 0.5, (mx.y - mn.y) * 0.5, (mx.z - mn.z) * 0.5
    local center     = ent.LocalToWorld and ent:LocalToWorld((mn + mx) * 0.5) or ent:GetPos()

    local dx, dy     = center.x - eyePos.x, center.y - eyePos.y
    local d          = math.sqrt(dx * dx + dy * dy)
    local dirx, diry = (d > 1) and (dx / d) or 1, (d > 1) and (dy / d) or 0

    -- Horizontal OBB reach toward the eye: |dir·f|·hx + |dir·r|·hy + |dir·u|·hz with dir horizontal,
    -- so an upright (vertical-u) model contributes nothing from its height.
    local ang     = ent.GetAngles and ent:GetAngles() or angle_zero
    local f, r, u = ang:Forward(), ang:Right(), ang:Up()
    local reach = math.abs(dirx * f.x + diry * f.y) * hx
        + math.abs(dirx * r.x + diry * r.y) * hy
        + math.abs(dirx * u.x + diry * u.y) * hz

    local nearDist = d - reach - 6                          -- eye→panel distance, 6u off the near surface
    local floor    = SED.PANEL_MIN_STANDOFF or 32
    if nearDist < floor then nearDist = math.min(floor, d) end -- inside/touching the model: keep just in front

    local band  = math.max(SED.PANEL_EYE_BAND or 150, hz * 2)
    local baseZ = math.Clamp(eyePos.z, center.z - band, center.z + band)
    local drawPos = Vector(eyePos.x + dirx * nearDist, eyePos.y + diry * nearDist, baseZ)

    -- Cap the panel's apparent size so it never dominates the view. A big entity's
    -- panel is a fixed (large) world width anchored to its near surface; standing on
    -- the entity puts the eye right there, so an uncapped panel fills the screen.
    -- Keep the world width within `factor × view distance` (≈ a bounded FOV slice).
    local worldW = (panelWidth and panelWidth > 0) and (panelWidth * scale)
        or (renderParams and renderParams.targetWorldWidth) or 0
    if worldW > 0 then
        local viewDist = math.max(nearDist, 1)
        local maxWorldW = viewDist * (SED.PANEL_MAX_VIEW_FACTOR or 0.6)
        if worldW > maxWorldW then scale = scale * (maxWorldW / worldW) end
    end

    return drawPos, SS.FacingAngle(drawPos - eyePos), scale
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

-- ── Phantom / common helpers ──

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

local function IsValidModelPath(str)
    if not isstring(str) or str == "" then return false end
    local lower = string.lower(str)
    if not string.EndsWith(lower, ".mdl") then return false end
    if string.find(lower, "gib") or string.find(lower, "debris") or string.find(lower, "piece") or string.find(lower, "chunk") then
        return false
    end
    return true
end

function SS.GatherSubModels(rec)
    if not istable(rec) then return {} end
    local subModels = {}
    local seen = {}
    local baseModel = string.lower(rec.model or rec.Model or "")
    if baseModel ~= "" then seen[baseModel] = true end

    local function addCandidate(mdl, hint)
        if not IsValidModelPath(mdl) then return end
        local lower = string.lower(mdl)
        if not seen[lower] then
            seen[lower] = true
            table.insert(subModels, { model = mdl, hint = tostring(hint or "") })
        end
    end

    local function inspectTable(tbl, prefix)
        if not istable(tbl) then return end
        for k, v in pairs(tbl) do
            local hint = (isstring(k) and k ~= "") and k or prefix
            if isstring(v) then
                addCandidate(v, hint)
            elseif istable(v) then
                if isstring(v.model or v.Model or v.mdl) then
                    addCandidate(v.model or v.Model or v.mdl, v.attachment or v.Attachment or v.att or hint)
                end
            end
        end
    end

    -- 0. Explicit phantom parts captured at save time for self-recreating vehicles
    -- (rareload_vehicle_capture.lua). Each carries a transform local to the root, so
    -- we keep every entry as-is (no model dedup: an AT-AT has several identical legs).
    if istable(rec.RareloadPhantomParts) then
        for _, p in ipairs(rec.RareloadPhantomParts) do
            if istable(p) and IsValidModelPath(p.model) then
                table.insert(subModels, {
                    model    = p.model,
                    skin     = p.skin,
                    localPos = p.lp,
                    localAng = p.la,
                })
            end
        end
    end

    -- 1. Snapshot record tables
    inspectTable(rec.SubModels, "SubModels")
    inspectTable(rec.ExtraModels, "ExtraModels")
    inspectTable(rec.ClientModels, "ClientModels")
    inspectTable(rec.BoneMergeModels, "BoneMergeModels")
    inspectTable(rec.Parts, "Parts")
    inspectTable(rec.Models, "Models")

    -- 2. Dynamically inspect the entity's registered scripted_ents class table
    local cls = rec.class or rec.Class or rec.ClassName
    if isstring(cls) and cls ~= "" and scripted_ents then
        local entTable = scripted_ents.Get(cls)
        if entTable then
            for k, v in pairs(entTable) do
                if isstring(k) then
                    local kLower = string.lower(k)
                    if string.StartsWith(kLower, "mdl") or string.StartsWith(kLower, "model") or string.StartsWith(kLower, "part") then
                        if isstring(v) then
                            addCandidate(v, k)
                        elseif istable(v) then
                            inspectTable(v, k)
                        end
                    elseif kLower == "submodels" or kLower == "extramodels" or kLower == "clientmodels" or kLower == "bonemergemodels" or kLower == "parts" or kLower == "models" then
                        inspectTable(v, k)
                    end
                end
            end
        end
    end

    return subModels
end

function SS.AttachSubModels(parentPhantom, rec)
    if not IsValid(parentPhantom) then return {} end
    local candidates = SS.GatherSubModels(rec)
    if #candidates == 0 then return {} end

    local attached = {}
    local pos = parentPhantom:GetPos()
    local ang = parentPhantom:GetAngles()

    -- Dynamic attachment lookup from the parent model
    local attachments = parentPhantom:GetAttachments() or {}

    for _, cand in ipairs(candidates) do
        local sm = cand.model
        local hint = string.lower(cand.hint or "")
        util.PrecacheModel(sm)

        local sub = SS.MakePhantomModel(sm, pos, ang)
        if IsValid(sub) then
            if istable(cand.localPos) then
                -- Captured phantom part: place it by its transform relative to the
                -- root, exactly where it sat when saved. No attachment guessing.
                local lp = cand.localPos
                local la = cand.localAng or {}
                sub:SetParent(parentPhantom)
                sub:SetLocalPos(Vector(lp.x or 0, lp.y or 0, lp.z or 0))
                sub:SetLocalAngles(Angle(la.p or 0, la.y or 0, la.r or 0))
            else
                local attID = -1

                -- 1. Try exact hint lookup if hint was provided
                if hint ~= "" then
                    attID = parentPhantom:LookupAttachment(cand.hint)
                    if attID <= 0 then
                        local stripped = string.gsub(string.gsub(hint, "^mdl_", ""), "^model_", "")
                        attID = parentPhantom:LookupAttachment(stripped)
                    end
                end

                -- 2. Try matching any attachment name dynamically with the model path or hint
                if attID <= 0 and #attachments > 0 then
                    local modelName = string.StripExtension(string.GetFileFromFilename(sm)):lower()
                    for _, att in ipairs(attachments) do
                        local attName = string.lower(att.name or "")
                        if attName ~= "" and (attName == hint or string.find(modelName, attName, 1, true) or (hint ~= "" and string.find(hint, attName, 1, true))) then
                            attID = att.id
                            break
                        end
                    end
                end

                -- 3. Attach to matched attachment point or fallback to BoneMerge
                if attID > 0 then
                    sub:SetParent(parentPhantom, attID)
                    sub:SetLocalPos(vector_origin)
                    sub:SetLocalAngles(angle_zero)
                else
                    sub:SetParent(parentPhantom)
                    sub:AddEffects(EF_BONEMERGE)
                    sub:AddEffects(EF_BONEMERGE_FASTCULL)
                end
            end

            if cand.skin then sub:SetSkin(cand.skin)
            elseif rec.skin or rec.Skin then sub:SetSkin(rec.skin or rec.Skin) end
            if rec.material and rec.material ~= "" then sub:SetMaterial(rec.material) end
            table.insert(attached, sub)
        end
    end

    return attached
end

function SS.SetPhantomRevealed(phantom, show)
    if not IsValid(phantom) then return end
    local col = show and Color(255, 255, 255, 150) or Color(0, 0, 0, 0)
    phantom:SetColor(col)
    phantom:SetNoDraw(not show)

    -- Also propagate to child / bonemerged clientside models if any
    local children = phantom:GetChildren()
    if istable(children) then
        for _, child in ipairs(children) do
            if IsValid(child) then
                child:SetColor(col)
                child:SetNoDraw(not show)
            end
        end
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
