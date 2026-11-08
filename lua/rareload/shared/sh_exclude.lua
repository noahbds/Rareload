-- Objects left out of saves (5.4 plan, D1). Any object can be marked "don't save with Rareload" from the
-- context menu; Rareload then never saves it, never removes it (exact restore, death cleanup) and
-- never restores it. The mark is a networked flag on the entity. Server owners can also block whole
-- classes (sv_exclude.lua).

RARELOAD.Exclude = RARELOAD.Exclude or {}
local Exclude = RARELOAD.Exclude

local FLAG = "RareloadExclude"

function Exclude.Is(ent)
    return IsValid(ent) and ent:GetNW2Bool(FLAG, false)
end

function Exclude.Set(ent, on)
    ent:SetNW2Bool(FLAG, on == true)
end

-- Objects this can apply to: anything but players, the world and what the player holds.
local function eligible(ent)
    return IsValid(ent) and not ent:IsPlayer() and not ent:IsWorld()
        and not (ent:IsWeapon() and IsValid(ent:GetOwner()))
end

local function property(name, order, icon, wantExcluded)
    properties.Add(name, {
        MenuLabel = "#rareload.exclude." .. (wantExcluded and "remove" or "add"),
        Order = order,
        MenuIcon = icon,
        -- The server checks ownership; the menu only hides the option where it can't apply.
        Filter = function(_, ent, ply)
            return eligible(ent) and Exclude.Is(ent) == wantExcluded and RARELOAD.Can(ply, "rareload_save_entities")
        end,
        Action = function(_, ent)
            RARELOAD.Net.Request("object.exclude", { ent = ent:EntIndex(), on = not wantExcluded })
        end,
    })
end

property("rareload_exclude", 2100, "icon16/database_delete.png", false)
property("rareload_include", 2101, "icon16/database_add.png", true)

if SERVER then return end

-- The world display shows objects left out of saves with a crossed-out disk. The client keeps the
-- set of excluded objects as their flag changes, instead of searching around the player every frame.
local RANGE = 1500
local excluded = setmetatable({}, { __mode = "k" })

hook.Add("EntityNetworkedVarChanged", "Rareload.Exclude", function(ent, name, _, value)
    if name == FLAG then excluded[ent] = value == true or nil end
end)
for _, ent in ents.Iterator() do -- what arrived before this file loaded
    if Exclude.Is(ent) then excluded[ent] = true end
end

local above = Vector()
hook.Add("HUDPaint", "Rareload.Exclude", function()
    if not next(excluded) then return end
    local World = RARELOAD.World
    if not World or not World.Active() then return end
    local eye = EyePos()
    for ent in pairs(excluded) do
        if Exclude.Is(ent) and ent:GetPos():DistToSqr(eye) < RANGE * RANGE then
            above:SetUnpacked(0, 0, ent:OBBMaxs().z - ent:OBBCenter().z + 12)
            local pos = (ent:WorldSpaceCenter() + above):ToScreen()
            if pos.visible then
                local size = RARELOAD.UI.sc(32)
                RARELOAD.UI.DrawIcon("disk", pos.x - size / 2, pos.y - size, size)
                RARELOAD.UI.DrawIcon("cross", pos.x, pos.y - size / 2, size / 2)
            end
        end
    end
end)
