-- "Place here…" in the timeline (5.4 plan, D6): moves where a save respawns the player. A see-through
-- copy of the player follows the aim; the mouse wheel turns it, left click moves the save's respawn
-- point there, right click cancels. Only the position changes; the rest of the save stays as it is.

local L, UI = RARELOAD.L, RARELOAD.UI
local C, sc = UI.C, UI.sc

RARELOAD.PlaceUI = RARELOAD.PlaceUI or {}
local PlaceUI = RARELOAD.PlaceUI
local STEP = 15     -- degrees per wheel notch
local RANGE = 3000  -- how far the aim reaches
local FLOOR = 0.6   -- the spot must be about level ground (normal's z)

function PlaceUI.Stop()
    if IsValid(PlaceUI.ghost) then PlaceUI.ghost:Remove() end
    PlaceUI.ghost, PlaceUI.id, PlaceUI.sid = nil, nil, nil
end

-- id: the save; model: the save's playermodel; sid: whose save (an admin moving another player's).
function PlaceUI.Start(id, model, sid)
    PlaceUI.Stop()
    if IsValid(RARELOAD.Timeline.frame) then RARELOAD.Timeline.frame:Close() end
    local lp = LocalPlayer()
    model = UI.IsModel(model) and model or lp:GetModel()
    local ghost = ClientsideModel(model, RENDERGROUP_TRANSLUCENT)
    if not IsValid(ghost) then return end
    ghost:SetRenderMode(RENDERMODE_TRANSCOLOR)
    ghost:ResetSequence(ghost:LookupSequence("idle_all_01") or 0)
    PlaceUI.ghost, PlaceUI.id, PlaceUI.sid = ghost, id, sid
    PlaceUI.yaw = lp:EyeAngles().y
end

-- Where the player would respawn: what they aim at, when it is ground in range.
local function target()
    local lp = LocalPlayer()
    local tr = util.TraceLine({ start = lp:EyePos(), endpos = lp:EyePos() + lp:GetAimVector() * RANGE,
        filter = lp, mask = MASK_PLAYERSOLID })
    return tr.HitPos, tr.Hit and tr.HitNormal.z >= FLOOR
end

hook.Add("Think", "Rareload.Place", function()
    local ghost = PlaceUI.ghost
    if not ghost then return end
    local lp = LocalPlayer()
    if not IsValid(ghost) or not IsValid(lp) or not lp:Alive() then return PlaceUI.Stop() end
    local pos, ok = target()
    ghost:SetPos(pos)
    ghost:SetAngles(Angle(0, PlaceUI.yaw, 0))
    ghost:SetColor(ColorAlpha(ok and C.accent or C.bad, 150))
    PlaceUI.ok, PlaceUI.pos = ok, pos
end)

-- Left click moves the respawn point, right click cancels, the wheel turns. The weapon doesn't fire.
hook.Add("PlayerBindPress", "Rareload.Place", function(_, bind, pressed)
    if not PlaceUI.ghost or not pressed then return end
    if string.find(bind, "+attack2", 1, true) then
        PlaceUI.Stop()
        return true
    elseif string.find(bind, "+attack", 1, true) then
        if not PlaceUI.ok then return true end
        local pos = PlaceUI.pos
        RARELOAD.Net.Request("history.move",
            { id = PlaceUI.id, x = pos.x, y = pos.y, z = pos.z, yaw = PlaceUI.yaw, sid = PlaceUI.sid })
        PlaceUI.Stop()
        return true
    elseif string.find(bind, "invnext", 1, true) then
        PlaceUI.yaw = (PlaceUI.yaw - STEP) % 360
        return true
    elseif string.find(bind, "invprev", 1, true) then
        PlaceUI.yaw = (PlaceUI.yaw + STEP) % 360
        return true
    end
end)

hook.Add("HUDPaint", "Rareload.Place", function()
    if not PlaceUI.ghost then return end
    local text = L(PlaceUI.ok and "place.hint" or "place.hint_bad", PlaceUI.id or 0)
    surface.SetFont("Rareload.BodyB")
    local tw, th = surface.GetTextSize(text)
    local w, h = tw + sc(32), th + sc(16)
    local x, y = (ScrW() - w) / 2, ScrH() * 0.78
    draw.RoundedBox(sc(8), x, y, w, h, ColorAlpha(C.surface, 230))
    draw.SimpleText(text, "Rareload.BodyB", ScrW() / 2, y + h / 2, PlaceUI.ok and C.text or C.bad, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
end)
