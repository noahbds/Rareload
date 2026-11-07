-- Placing a save somewhere else (5.4 plan, D6): the save's objects follow the aim as see-through
-- copies. Mouse wheel turns them, left click places a copy there, right click cancels.

local L, UI = RARELOAD.L, RARELOAD.UI
local C, sc = UI.C, UI.sc

RARELOAD.PlaceUI = RARELOAD.PlaceUI or {}
local PlaceUI = RARELOAD.PlaceUI
local STEP = 15 -- degrees per wheel notch

local function clear()
    for _, m in ipairs(PlaceUI.models or {}) do if IsValid(m) then m:Remove() end end
    PlaceUI.models, PlaceUI.objects, PlaceUI.id = nil, nil, nil
end

function PlaceUI.Start(id)
    if IsValid(RARELOAD.Timeline.frame) then RARELOAD.Timeline.frame:Close() end
    clear()
    PlaceUI.yaw = 0
    RARELOAD.Net.Request("place.get", { id = id })
end

function PlaceUI.Stop() clear() end

RARELOAD.Net.On("place.preview", function(p)
    clear()
    PlaceUI.id, PlaceUI.objects, PlaceUI.models = tonumber(p.id), {}, {}
    for _, o in ipairs(istable(p.objects) and p.objects or {}) do
        local lp, la = RARELOAD.Util.ToVector(o.lp), RARELOAD.Util.ToAngle(o.la) or angle_zero
        if lp and UI.IsModel(o.model) then
            local m = ClientsideModel(o.model, RENDERGROUP_TRANSLUCENT)
            if IsValid(m) then
                m:SetSkin(tonumber(o.skin) or 0)
                m:SetRenderMode(RENDERMODE_TRANSCOLOR)
                m:SetColor(ColorAlpha(C.accent, 140))
                PlaceUI.models[#PlaceUI.models + 1] = m
                PlaceUI.objects[#PlaceUI.objects + 1] = { model = m, lp = lp, la = la }
            end
        end
    end
end)

-- Where the copy would go: what the player aims at, at most 3000 units away.
local function target()
    local lp = LocalPlayer()
    local tr = util.TraceLine({ start = lp:EyePos(), endpos = lp:EyePos() + lp:GetAimVector() * 3000, filter = lp })
    return tr.HitPos
end

hook.Add("Think", "Rareload.Place", function()
    if not PlaceUI.objects then return end
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return clear() end
    local pos, turn = target(), Angle(0, PlaceUI.yaw, 0)
    for _, o in ipairs(PlaceUI.objects) do
        if IsValid(o.model) then
            local wp, wa = LocalToWorld(o.lp, o.la, pos, turn)
            o.model:SetPos(wp)
            o.model:SetAngles(wa)
        end
    end
end)

-- Left click places, right click cancels, the wheel turns. The weapon doesn't fire meanwhile.
hook.Add("PlayerBindPress", "Rareload.Place", function(_, bind, pressed)
    if not PlaceUI.objects or not pressed then return end
    if string.find(bind, "+attack2", 1, true) then
        clear()
        return true
    elseif string.find(bind, "+attack", 1, true) then
        local pos = target()
        RARELOAD.Net.Request("place.paste", { id = PlaceUI.id, x = pos.x, y = pos.y, z = pos.z, yaw = PlaceUI.yaw })
        clear()
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
    if not PlaceUI.objects then return end
    local text = L("place.hint", #PlaceUI.objects)
    surface.SetFont("Rareload.BodyB")
    local tw, th = surface.GetTextSize(text)
    local w, h = tw + sc(32), th + sc(16)
    local x, y = (ScrW() - w) / 2, ScrH() * 0.78
    draw.RoundedBox(sc(8), x, y, w, h, ColorAlpha(C.surface, 230))
    draw.SimpleText(text, "Rareload.BodyB", ScrW() / 2, y + h / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
