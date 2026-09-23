-- Highlights (REWRITE_PLAN.md §21.7, F35): `rareload highlight all|link|players|clear`.
--   all:     a halo around every saved object that is on the map
--   link:    a beam from each moved object to where it was saved
--   players: a label over every player save
-- The inspector also highlights one entity for a few seconds with Highlight.Flash.

RARELOAD.Highlight = RARELOAD.Highlight or { modes = {} }
local Highlight = RARELOAD.Highlight
local L = RARELOAD.L
local MAX_HALOS = 32   -- G39
local BEAM = Material("cable/redlaser")

function Highlight.Flash(ent, seconds)
    Highlight.flash, Highlight.flashUntil = ent, RealTime() + (seconds or 4)
end

RARELOAD.UI.Command("highlight", function(args)
    local mode = args[1] or "all"
    if mode == "clear" then
        Highlight.modes = {}
    elseif mode == "all" or mode == "link" or mode == "players" then
        Highlight.modes[mode] = not Highlight.modes[mode]
    else
        print("rareload highlight all|link|players|clear")
    end
end)

local function records()
    local World = RARELOAD.World
    return World.Active() and World.records or {}
end

hook.Add("PreDrawHalos", "Rareload.Highlight", function()
    local list = {}
    if IsValid(Highlight.flash) and RealTime() < Highlight.flashUntil then list[1] = Highlight.flash end
    if Highlight.modes.all then
        for _, rec in ipairs(records()) do
            local ent = rec.kind == "object" and RARELOAD.World.LiveOf(rec)
            if ent and #list < MAX_HALOS then list[#list + 1] = ent end
        end
    end
    if #list > 0 then halo.Add(list, RARELOAD.UI.C.accent, 2, 2, 1, true, true) end
end)

hook.Add("PostDrawTranslucentRenderables", "Rareload.Highlight", function(depth, sky)
    if depth or sky or not Highlight.modes.link then return end
    render.SetMaterial(BEAM)
    for _, rec in ipairs(records()) do
        local ent = rec.kind == "object" and RARELOAD.World.LiveOf(rec)
        if ent and ent:GetPos():DistToSqr(rec.pos) > 64 then
            render.DrawBeam(ent:GetPos(), rec.pos, 2, 0, 1, color_white)
        end
    end
end)

hook.Add("HUDPaint", "Rareload.Highlight", function()
    if not Highlight.modes.players then return end
    local eye = EyePos()
    for _, rec in ipairs(records()) do
        if rec.kind == "player" then
            local p = (rec.pos + Vector(0, 0, 90)):ToScreen()
            if p.visible then
                local text = L("world.player_label", rec.title or "?", math.floor(eye:Distance(rec.pos)))
                draw.SimpleTextOutlined(text, "Rareload.Body", p.x, p.y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
            end
        end
    end
end)
