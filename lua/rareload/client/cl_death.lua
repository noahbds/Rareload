-- Death recovery (5.4 plan, D4): the marker where the player died, and the choice of where to respawn.

local L, UI = RARELOAD.L, RARELOAD.UI
local C, sc = UI.C, UI.sc

RARELOAD.DeathUI = RARELOAD.DeathUI or {}
local DeathUI = RARELOAD.DeathUI
local State = RARELOAD.State

-- The marker: a red beam and "You died here" at the last death (RARELOAD.State.death), hidden while
-- the player is next to it.
local RANGE, REACHED = 4000, 120
local near = false

hook.Add("RareloadStateChanged", "Rareload.Death", function(what) if what == "death" then near = false end end)

hook.Add("PostDrawTranslucentRenderables", "Rareload.Death", function(depth, sky)
    local pos = State.death.pos
    if depth or sky or not pos or near then return end
    render.SetColorMaterial()
    UI.DrawWorldBeam(pos, 120, 6, C.bad, 170)
end)

hook.Add("HUDPaint", "Rareload.Death", function()
    local pos = State.death.pos
    if not pos then return end
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return end
    local dist = lp:GetPos():Distance(pos)
    near = dist < REACHED
    if near or dist > RANGE then return end
    UI.DrawWorldTag(pos, 128, "heart_delete", L("death.marker"), C.bad, dist, 255)
end)

-- The choice of where to respawn (player setting deathChoice).
RARELOAD.Net.On("death.choice", function(p)
    if IsValid(DeathUI.choice) then DeathUI.choice:Remove() end
    local frame = UI.Window({ title = L("death.choice_title"), subtitle = L("death.choice_help"), w = 460, h = 300 })
    DeathUI.choice = frame
    local always = false
    local function choose(mode)
        if always then
            RunConsoleCommand(RARELOAD.Settings.deathChoiceAlways.pref, mode)
            UI.Notify(L("death.always_set"), "info")
        end
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
    local check = UI.Check(frame, L("death.always"), false, function(v) always = v end)
    check:Dock(TOP)
    check:DockMargin(0, sc(4), 0, 0)
    -- Gone once the player is alive again (a server can respawn them by itself). The message arrives
    -- before the client sees its own death, so only after the player was seen dead (or 3 s at most).
    local opened = CurTime()
    frame.Think = function(self)
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        if not lp:Alive() then
            self.sawDead = true
        elseif self.sawDead or CurTime() - opened > 3 then
            self:Remove()
        end
    end
end)
