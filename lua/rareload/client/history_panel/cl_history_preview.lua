-- ─────────────────────────────────────────────────────────────────────────────
-- Save Timeline — in-world preview (4.0 · Phase 4)
--
-- When an entry is selected in the Save Timeline panel, this drops a translucent
-- phantom at the saved position with a coloured glow: GREEN when the spot is
-- clear, RED when the player hull would spawn inside a solid (a wall / the ground
-- / a prop). Restoring a red spot still lands safely — the server's anti-stuck
-- relocates on restore — so red is a heads-up, not a block.
--
-- Fully client-side and self-contained: it owns its phantom and hooks and does not
-- touch the SED phantom system.
-- ─────────────────────────────────────────────────────────────────────────────

if not CLIENT then return end
RARELOAD = RARELOAD or {}

local Preview = RARELOAD.HistoryPreview or {}
RARELOAD.HistoryPreview = Preview

local COL_CLEAR = Color(64, 224, 110)
local COL_BLOCK = Color(240, 72, 60)
local GLOW_MAT  = Material("sprites/light_glow02_add")

Preview.color  = Preview.color or COL_CLEAR
Preview.clear  = true
Preview.active = false

local function RemovePhantom()
    if IsValid(Preview.phantom) then Preview.phantom:Remove() end
    Preview.phantom = nil
end

-- Would a standing player be stuck at this position?
local function HullClear(pos)
    local lp = LocalPlayer()
    local mins, maxs = Vector(-16, -16, 0), Vector(16, 16, 72)
    if IsValid(lp) then
        local mn, mx = lp:OBBMins(), lp:OBBMaxs()
        if mn and mx then mins, maxs = mn, mx end
    end
    local tr = util.TraceHull({
        start  = pos,
        endpos = pos,
        mins   = mins,
        maxs   = maxs,
        mask   = MASK_PLAYERSOLID,
        filter = lp,
    })
    return not (tr.StartSolid or tr.AllSolid)
end

function Preview.Show(e)
    if not (istable(e) and istable(e.pos)) then
        Preview.Clear()
        return
    end

    local pos = Vector(tonumber(e.pos.x) or 0, tonumber(e.pos.y) or 0, tonumber(e.pos.z) or 0)
    local ang = Angle(0, (istable(e.ang) and tonumber(e.ang.y)) or 0, 0)

    Preview.clear  = HullClear(pos)
    Preview.color  = Preview.clear and COL_CLEAR or COL_BLOCK
    Preview.pos    = pos
    Preview.active = true

    RemovePhantom()
    if e.mdl and util.IsValidModel(e.mdl) then
        local p = ClientsideModel(e.mdl, RENDERGROUP_TRANSLUCENT)
        if IsValid(p) then
            p:SetPos(pos)
            p:SetAngles(ang)
            p:SetMoveType(MOVETYPE_NONE)
            p:SetSolid(SOLID_NONE)
            p:SetRenderMode(RENDERMODE_TRANSALPHA)
            p:SetColor(Color(255, 255, 255, 150))
            Preview.phantom = p
        end
    end
end

function Preview.Clear()
    Preview.active = false
    Preview.pos = nil
    RemovePhantom()
end

function Preview.IsClear() return Preview.clear end
function Preview.IsActive() return Preview.active end

hook.Add("PreDrawHalos", "RARELOAD_HistoryPreview_Halo", function()
    if Preview.active and IsValid(Preview.phantom) then
        halo.Add({ Preview.phantom }, Preview.color, 6, 6, 2, true, true)
    end
end)

hook.Add("PostDrawTranslucentRenderables", "RARELOAD_HistoryPreview_Glow", function(bDepth, bSky)
    if bDepth or bSky then return end
    if not (Preview.active and Preview.pos) then return end
    if render.GetRenderTarget() ~= nil then return end

    local pulse = 0.55 + math.sin(CurTime() * 4) * 0.35
    render.SetMaterial(GLOW_MAT)
    render.DrawSprite(Preview.pos + Vector(0, 0, 42), 46 * pulse, 46 * pulse, Preview.color)
    render.DrawSprite(Preview.pos + Vector(0, 0, 6), 28 * pulse, 28 * pulse, Preview.color)
end)

-- Safety: drop the phantom on map cleanup.
hook.Add("OnReloaded", "RARELOAD_HistoryPreview_Reset", Preview.Clear)

return Preview
