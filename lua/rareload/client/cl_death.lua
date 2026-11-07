-- Death recovery (5.4 plan, D4): the marker where the player died, and the choice of where to respawn.

local L, UI = RARELOAD.L, RARELOAD.UI
local C, sc = UI.C, UI.sc

RARELOAD.DeathUI = RARELOAD.DeathUI or {}
local DeathUI = RARELOAD.DeathUI

RARELOAD.Net.On("death", function(p)
    DeathUI.id = tonumber(p.id)
    DeathUI.pos = RARELOAD.Util.ToVector(p.pos)
    DeathUI.reached = false
    hook.Run("RareloadStateChanged", "death")
end)

-- The marker: a red beam and "You died here", until the player gets there.
local RANGE, REACHED = 4000, 120

hook.Add("PostDrawTranslucentRenderables", "Rareload.Death", function(depth, sky)
    local pos = DeathUI.pos
    if depth or sky or not pos or DeathUI.reached then return end
    render.SetColorMaterial()
    render.DrawBeam(pos, pos + Vector(0, 0, 120), 6, 0, 1, ColorAlpha(C.bad, 170))
end)

hook.Add("HUDPaint", "Rareload.Death", function()
    local pos = DeathUI.pos
    if not pos or DeathUI.reached then return end
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return end
    local d = lp:GetPos():Distance(pos)
    if d < REACHED then
        DeathUI.reached = true
        return
    end
    if d > RANGE then return end
    local p = (pos + Vector(0, 0, 128)):ToScreen()
    if not p.visible then return end
    local text = L("death.marker")
    surface.SetFont("Rareload.BodyB")
    local tw, th = surface.GetTextSize(text)
    local w, h = tw + sc(34), th + sc(10)
    local x, y = math.floor(p.x - w / 2), math.floor(p.y - h)
    draw.RoundedBox(sc(6), x, y, w, h, ColorAlpha(C.surface, 220))
    UI.DrawIcon("heart_delete", x + sc(6), y + (h - sc(16)) / 2, sc(16))
    draw.SimpleText(text, "Rareload.BodyB", x + sc(28), y + h / 2, C.bad, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(L("inspector.units", math.Round(d)), "Rareload.Small", p.x, y + h + sc(2), C.text3,
        TEXT_ALIGN_CENTER)
end)

-- The choice of where to respawn (player setting deathChoice).
RARELOAD.Net.On("death.choice", function(p)
    if IsValid(DeathUI.choice) then DeathUI.choice:Remove() end
    local frame = UI.Window({ title = L("death.choice_title"), subtitle = L("death.choice_help"), w = 460, h = 300 })
    DeathUI.choice = frame
    local function choose(mode)
        RARELOAD.Net.Request("death.respawn", { mode = mode })
        frame:Close()
    end
    local options = {
        { "save", L("death.choice_save"), "flag_green", "success" },
        { "map", L("death.choice_map"), "world", "info" },
    }
    if p.death then options[#options + 1] = { "death", L("death.choice_death"), "heart", "warn" } end
    for _, o in ipairs(options) do
        local b = UI.Button(frame, o[2], function() choose(o[1]) end, { style = o[4], icon = o[3] })
        b:Dock(TOP)
        b:SetTall(sc(44))
        b:DockMargin(0, 0, 0, sc(8))
    end
    -- Gone once the player is alive again (a server can respawn them by itself).
    frame.Think = function(self)
        local lp = LocalPlayer()
        if IsValid(lp) and lp:Alive() then self:Remove() end
    end
end)
