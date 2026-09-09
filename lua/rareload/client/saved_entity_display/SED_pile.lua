-- SED_pile.lua
-- Groups saved-entity displays that sit close together into a single "business-card stack".
-- A pile is ONE aim target (killing the old overlap/flicker), and in interaction mode the
-- player flips between the stacked cards with a swap animation. Lone saves (a group of one)
-- are drawn by the normal single-panel path and never reach this module.

local RS = SED.Require("RenderShared", "rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
local SS = SED.Require("Shared", "rareload/client/saved_entity_display/SED_shared.lua")

local cam_Start3D2D          = RS.cam_Start3D2D
local cam_End3D2D            = RS.cam_End3D2D
local surface_SetDrawColor   = RS.surface_SetDrawColor
local surface_DrawRect       = RS.surface_DrawRect
local draw_RoundedBox        = RS.draw_RoundedBox
local draw_SimpleText        = RS.draw_SimpleText
local surface_SetFont        = RS.surface_SetFont
local surface_GetTextSize    = RS.surface_GetTextSize
local math_min               = RS.math_min
local math_max               = RS.math_max
local math_sqrt              = RS.math_sqrt
local math_abs               = RS.math_abs
local math_Clamp             = RS.math_Clamp

local HINT_INTERACT          = RS.HINT_INTERACT
local HINT_CONTROLS          = RS.HINT_CONTROLS
local HINT_CANDIDATE         = RS.HINT_CANDIDATE
local HINT_INTERACT_BG       = RS.HINT_INTERACT_BG
local HINT_CONTROLS_BG       = RS.HINT_CONTROLS_BG
local HINT_CANDIDATE_BG      = RS.HINT_CANDIDATE_BG

local BOOTSTRAP_W, BOOTSTRAP_H = 520, 280

local PEEK_BODY   = Color(18, 22, 30, 240)
local PEEK_HEADER = Color(28, 34, 46, 245)
local PEEK_ACCENT = Color(60, 140, 220, 120)
local BADGE_GLOW  = Color(60, 140, 220, 190)
local BADGE_BG    = Color(14, 17, 23, 248)
local BADGE_TEXT  = Color(225, 238, 255)

local function easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    local u  = t - 1
    return 1 + c3 * u * u * u + c1 * u * u
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Aim helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Rough "is the crosshair on this panel?" test using an estimated panel size at the entity's
-- nearest surface. Cheap, distance-independent, and matches where the pile is drawn (anchor).
function SED.EstimateAimHit(ent, renderParams, eyePos, eyeForward)
    if not IsValid(ent) then return false, nil end

    local panelCenter  = SS.PanelAimPos(ent, renderParams, eyePos)
    local toPanel      = panelCenter - eyePos
    local panelDistSqr = toPanel:LengthSqr()
    if panelDistSqr < 1 then return false, nil end

    local distance = math_sqrt(panelDistSqr)
    local scale    = SS.PanelScale(renderParams, distance, BOOTSTRAP_W)
    local ang      = SS.FacingAngle(toPanel)
    local hit      = SS.PanelHitTest(panelCenter, ang, scale, BOOTSTRAP_W, BOOTSTRAP_H, eyePos, eyeForward)
    return hit, panelDistSqr
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Grouping
-- ─────────────────────────────────────────────────────────────────────────────

-- Cluster the (distance-sorted) queue items into piles via single-linkage: an item joins the
-- first group holding ANY member whose footprint circle is within PANEL_CLUSTER_DIST of it
-- (edge-to-edge = sum of the two radii), with a vertical gate so it won't bridge separate floors.
-- Using the sum of radii means a big vehicle and a small phantom beside it reliably share a group.
-- The nearest item of each group is its anchor: the pile is drawn there (like a lone panel), so it
-- sits by whichever member the player is closest to.
function SED.GroupQueue(queueList, maxQueue)
    local groups      = {}
    local clusterDist = SED.PANEL_CLUSTER_DIST or 150
    local zGate       = SED.PILE_Z_GATE or 220

    for i = 1, maxQueue do
        local item = queueList[i]
        if item then
            -- Queue items are pooled and not field-cleared on reuse, so recompute every frame.
            item.id = SED.SavedRecID(item.saved)
            local rp = item.renderParams
            local sx = (rp and rp.size and rp.size.x) or 32
            local sy = (rp and rp.size and rp.size.y) or 32
            local sz = (rp and rp.size and rp.size.z) or 72
            item.xyRadius = math_max(sx, sy) * 0.5
            item.zHalf    = sz * 0.5

            local p      = item.pos
            local placed = false
            for g = 1, #groups do
                local members = groups[g].members
                for mi = 1, #members do
                    local b = members[mi]
                    local dx, dy = p.x - b.pos.x, p.y - b.pos.y
                    local xyd = math_sqrt(dx * dx + dy * dy)
                    local thr = clusterDist + item.xyRadius + b.xyRadius
                    if xyd < thr and math_abs(p.z - b.pos.z) < (zGate + item.zHalf + b.zHalf) then
                        members[#members + 1] = item
                        placed = true
                        break
                    end
                end
                if placed then break end
            end

            if not placed then
                groups[#groups + 1] = { anchorItem = item, members = { item } }
            end
        end
    end

    -- Deterministic deck order + a stable per-pile key so the active card and swap state persist.
    for _, grp in ipairs(groups) do
        local members = grp.members
        if #members > 1 then
            table.sort(members, function(a, b) return tostring(a.id) < tostring(b.id) end)
            local tags = {}
            for k = 1, #members do
                local m = members[k]
                tags[k] = (m.isNPC and "N:" or "E:") .. tostring(m.id)
            end
            grp.key = table.concat(tags, "|")
        else
            local m = members[1]
            grp.key = (m.isNPC and "N:" or "E:") .. tostring(m.id)
        end
    end

    return groups
end

-- Re-pick each multi-member group's anchor to the member the player is LOOKING at (highest
-- cosine to eye-forward), not merely the nearest one. Without this the pile renders behind you
-- whenever a closer member sits off to the side while you face a farther one. A small hysteresis
-- bonus for last frame's anchor stops it flickering when you look between two members.
function SED.ResolveGroupAnchors(groups, eyePos, eyeForward)
    local efx, efy, efz = eyeForward.x, eyeForward.y, eyeForward.z
    local epx, epy, epz = eyePos.x, eyePos.y, eyePos.z
    for g = 1, #groups do
        local grp = groups[g]
        local members = grp.members
        if #members > 1 then
            local st     = SED.PileState[grp.key]
            local prevId = st and st.anchorId
            local best, bestScore = members[1], -2
            for i = 1, #members do
                local m = members[i]
                local dx, dy, dz = m.pos.x - epx, m.pos.y - epy, (m.pos.z + (m.zHalf or 0)) - epz
                local len = math_sqrt(dx * dx + dy * dy + dz * dz)
                if len > 1 then
                    local cos = (dx * efx + dy * efy + dz * efz) / len
                    if prevId and m.id == prevId then cos = cos + 0.05 end
                    if cos > bestScore then bestScore = cos; best = m end
                end
            end
            grp.anchorItem = best
        end
    end
end

-- Drop pile state whose cluster hasn't been seen for a while (keeps SED.PileState from growing).
local lastPrune = 0
local function PrunePileState()
    local now = CurTime()
    if now - lastPrune < 5 then return end
    lastPrune = now
    for key, st in pairs(SED.PileState) do
        if not st.lastSeen or (now - st.lastSeen) > 10 then
            SED.PileState[key] = nil
        end
    end
end

-- Choose which pile is under the crosshair. Per-group angular pick (nearest to view direction)
-- against the group's anchor, with a small hysteresis bonus for the previously-aimed pile, then an
-- estimated hit-test. Sets SED.CandidateGroup / SED.CandidateEnt / IsNPC / ID to the active card.
function SED.SelectCandidateGroup(groups, eyePos, eyeForward)
    PrunePileState()

    local distThresholdSqr = SED.INTERACT_DIST_SQR
    local efx, efy, efz = eyeForward.x, eyeForward.y, eyeForward.z
    local epx, epy, epz = eyePos.x, eyePos.y, eyePos.z
    local prevKey = SED.LastCandidateKey

    local bestGroup, bestCos = nil, 0.5
    for g = 1, #groups do
        local grp   = groups[g]
        local a     = grp.anchorItem
        local rp    = a.renderParams
        local sizeZ = (rp and rp.size and rp.size.z) or 80
        local band  = math_max(SED.PANEL_EYE_BAND or 150, sizeZ)
        local az    = math_Clamp(epz, a.pos.z + sizeZ * 0.5 - band, a.pos.z + sizeZ * 0.5 + band)
        local dx, dy, dz = a.pos.x - epx, a.pos.y - epy, az - epz
        local len2  = dx * dx + dy * dy + dz * dz
        if len2 > 1 then
            local d = dx * efx + dy * efy + dz * efz
            if d > 0 then
                local cos = d / math_sqrt(len2)
                if prevKey and grp.key == prevKey then cos = cos + 0.03 end
                if cos > bestCos then bestCos = cos; bestGroup = grp end
            end
        end
    end

    if not bestGroup then
        SED.LastCandidateKey = nil
        return
    end

    -- The candidate card is the anchor -- the member the player is looking at -- so inspecting
    -- enters on that card (idle DrawPile shows the same one).
    local a = bestGroup.anchorItem
    local hit, panelDistSqr = SED.EstimateAimHit(a.ent, a.renderParams, eyePos, eyeForward)
    if hit and panelDistSqr and panelDistSqr < distThresholdSqr then
        SED.CandidateGroup   = bestGroup
        SED.CandidateEnt     = a.ent
        SED.CandidateIsNPC   = a.isNPC
        SED.CandidateID      = a.id
        SED.LastCandidateKey = bestGroup.key
        return
    end
    SED.LastCandidateKey = nil
end

-- Locate the current-frame group for an interaction, by key first then by a member id.
function SED.FindGroup(key, fallbackId)
    local groups = SED.ActiveGroups
    if not groups then return nil end
    for g = 1, #groups do
        if groups[g].key == key then return groups[g] end
    end
    if fallbackId ~= nil then
        for g = 1, #groups do
            local members = groups[g].members
            for m = 1, #members do
                if members[m].id == fallbackId then return groups[g] end
            end
        end
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Rendering
-- ─────────────────────────────────────────────────────────────────────────────

local function BuildMemberCtx(m)
    if not (m and IsValid(m.ent)) then return nil end
    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return nil end
    local distSqr = SED.lpCache:EyePos():DistToSqr(m.ent:GetPos())
    local rp = m.renderParams or SED.CalculateEntityRenderParams(m.ent)
    if not rp then return nil end
    return SED.PanelRendererBuildContext(m.ent, m.saved, m.isNPC, rp, distSqr, m.liveEnt)
end

-- A stacked card behind the active one: only its top-right sliver shows, so a plain frame reads
-- as "another card in the deck" without the cost of baking its content.
local function DrawPeekCard(w, h, dx, dy, sMul, alpha)
    local a  = math_Clamp(alpha, 0, 255)
    local pw, ph = w * sMul, h * sMul
    local ox, oy = -pw * 0.5 + dx, -ph * 0.5 + dy
    local hh = 46 * sMul

    surface_SetDrawColor(0, 0, 0, 70 * a / 255)
    surface_DrawRect(ox + 5, oy + 5, pw, ph)

    draw_RoundedBox(8, ox, oy, pw, ph, Color(PEEK_BODY.r, PEEK_BODY.g, PEEK_BODY.b, PEEK_BODY.a * a / 255))
    draw_RoundedBox(8, ox, oy, pw, hh, Color(PEEK_HEADER.r, PEEK_HEADER.g, PEEK_HEADER.b, PEEK_HEADER.a * a / 255))
    surface_SetDrawColor(PEEK_ACCENT.r, PEEK_ACCENT.g, PEEK_ACCENT.b, PEEK_ACCENT.a * a / 255)
    surface_DrawRect(ox, oy + hh - 2, pw, 2)
end

-- The "2 / 3" deck indicator, floated just above the active card.
local function DrawPileBadge(w, h, active, n)
    local label = active .. " / " .. n
    surface_SetFont("Trebuchet18")
    local tw = surface_GetTextSize(label) or 0
    local bw = tw + 18
    local bh = 22
    local bx = -bw * 0.5
    local by = -h * 0.5 - bh - 6

    draw_RoundedBox(6, bx - 1, by - 1, bw + 2, bh + 2, BADGE_GLOW)
    draw_RoundedBox(6, bx, by, bw, bh, BADGE_BG)
    draw_SimpleText(label, "Trebuchet18", bx + bw * 0.5, by + bh * 0.5, BADGE_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Confirm the crosshair really is on the drawn active-card rect (not just the estimate), keep the
-- IN_USE-suppression timer alive, and draw the inspect / interact / flip hints for the pile.
function SED.PileHandleInteraction(group, w, h, drawPos, ang, scale)
    local eyePos  = SED.lpCache:EyePos()
    local forward = SED.lpCache:EyeAngles():Forward()
    local hit     = SS.PanelHitTest(drawPos, ang, scale, w, h, eyePos, forward)

    local isFocused   = SED.InteractionState.active and SED.InteractionState.pileKey == group.key
    local isCandidate = false
    if hit then
        SED.LookingAtPanelUntil = CurTime() + 0.03
        if not SED.InteractionState.active and SED.CandidateGroup == group then
            isCandidate = true
        end
    end

    if not (isFocused or isCandidate) then return end

    local n       = #group.members
    local L       = RARELOAD.L or function(k) return k end
    local hintY   = drawPos.z + (h * scale) * 0.5 + 10
    local hintPos = Vector(drawPos.x, drawPos.y, hintY)

    cam_Start3D2D(hintPos, ang, scale * 0.8)
    if isFocused then
        SS.DrawHint(L("sed.interact_mode"), 0, 0, HINT_INTERACT, HINT_INTERACT_BG)
        SS.DrawHint(n >= 2 and L("sed.pile_controls") or L("sed.interact_controls"), 0, 24, HINT_CONTROLS,
            HINT_CONTROLS_BG)
        SS.DrawHint(L("sed.interact_highlight"), 0, 48, HINT_CONTROLS, HINT_CONTROLS_BG)
    else
        SS.DrawHint(L("sed.inspect_hint"), 0, 0, HINT_CANDIDATE, HINT_CANDIDATE_BG)
        if n >= 2 then
            SS.DrawHint(L("sed.pile_hint", n), 0, 24, HINT_CANDIDATE, HINT_CANDIDATE_BG)
        end
    end
    cam_End3D2D()
end

function SED.DrawPile(group)
    local members = group.members
    local n = #members
    if n == 0 then return end
    SED.lpCache = SED.lpCache or LocalPlayer()
    if not IsValid(SED.lpCache) then return end
    local eyePos = SED.lpCache:EyePos()

    local st = SED.PileState[group.key]
    if not st then st = { active = 1 }; SED.PileState[group.key] = st end
    if st.active > n or st.active < 1 then st.active = 1 end
    st.lastSeen = CurTime()
    st.anchorId = group.anchorItem.id -- remembered for next frame's anchor hysteresis

    -- When idle, face the card for whatever member the player is nearest to (the anchor), so
    -- walking up to the vehicle shows the vehicle card. During interaction the player's flip wins.
    if not (SED.InteractionState.active and SED.InteractionState.pileKey == group.key) then
        for i = 1, n do
            if members[i] == group.anchorItem then st.active = i; break end
        end
    end

    local activeIdx    = st.active
    local activeMember = members[activeIdx]
    local actx         = BuildMemberCtx(activeMember)
    if not actx then return end

    -- Pile plane anchored on the nearest member, placed exactly like a lone panel (so it sits by
    -- whatever the player is closest to, at a readable standoff). The active card's pixel width
    -- feeds the scale so every card keeps the anchor's world width as you flip.
    local anchor = group.anchorItem
    local drawPos, ang, scale = SS.ComputePlacement(anchor.ent, anchor.renderParams, eyePos, anchor.distSqr, actx.width)
    group.drawPos, group.ang, group.scale = drawPos, ang, scale

    local w, h = actx.width, actx.panelHeight

    local anim = st.anim
    local t    = 1
    if anim then
        t = (CurTime() - anim.t0) / (SED.PILE_ANIM_DUR or 0.28)
        if t >= 1 then st.anim = nil; anim = nil; t = 1 end
    end

    -- Bake card materials OUTSIDE the 3D2D block: baking pushes a render target, which must not
    -- happen while a cam.Start3D2D is open.
    SED.EnsurePanelMat(actx)
    local fctx = nil
    if anim and anim.from then
        fctx = BuildMemberCtx(anim.from)
        if fctx then SED.EnsurePanelMat(fctx) end
    end

    cam_Start3D2D(drawPos, ang, scale)

    -- Peek cards behind the active one (skipping whichever is currently dealing off).
    local fromId  = anim and anim.from and anim.from.id or nil
    local maxPeek = math_min(SED.PILE_MAX_PEEK or 2, n - 1)
    for k = maxPeek, 1, -1 do
        local idx = ((activeIdx - 1 + k) % n) + 1
        local m   = members[idx]
        if not (fromId and m.id == fromId) then
            local dx   = (SED.PILE_PEEK_DX or 26) * k
            local dy   = -(SED.PILE_PEEK_DY or 22) * k
            local sMul = (SED.PILE_PEEK_SCALE or 0.94) ^ k
            DrawPeekCard(w, h, dx, dy, sMul, 170 - (k - 1) * 45)
        end
    end

    if anim then
        local et = easeOutBack(t)
        -- incoming (the new active) rising into place from behind
        local toScale = Lerp(et, 0.9, 1)
        local toAlpha = Lerp(t, 150, 255)
        local toDx    = -anim.dir * (1 - et) * (w * 0.10)
        local toDy    = (1 - et) * (h * 0.05)
        SED.DrawPanelInPlane(actx, toDx, toDy, toScale, toAlpha, true)

        -- outgoing (the old active) dealing off along an arc in the flip direction
        if fctx then
            local fromDx    = anim.dir * t * (w * 0.55)
            local fromDy    = -t * (h * 0.14)
            local fromScale = Lerp(t, 1, 0.82)
            local fromAlpha = 255 * (1 - t * t)
            SED.DrawPanelInPlane(fctx, fromDx, fromDy, fromScale, fromAlpha, true)
        end
    else
        SED.DrawPanelInPlane(actx, 0, 0, 1, 255, true)
    end

    DrawPileBadge(w, h, activeIdx, n)

    cam_End3D2D()

    SED.PileHandleInteraction(group, w, h, drawPos, ang, scale)
end

SED.PileModuleLoaded = true
