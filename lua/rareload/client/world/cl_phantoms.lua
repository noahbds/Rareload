-- Phantoms: see-through client-side models of saved players and of saved objects that aren't on the
-- map (REWRITE_PLAN.md §21.7, F31, F32). Every one lives in this registry, which removes them on
-- shutdown and re-creates any the engine deleted (G36). They are never parented to server entities.

RARELOAD.Phantoms = RARELOAD.Phantoms or { reg = {} }
local Phantoms = RARELOAD.Phantoms
local MAX = 256

-- util.IsValidModel is false for models the client hasn't loaded yet, so a mounted file counts too.
local function usable(model)
    return isstring(model) and model ~= "" and (util.IsValidModel(model) or file.Exists(model, "GAME"))
end

local function make(w)
    local ent = ClientsideModel(w.model, RENDERGROUP_TRANSLUCENT)
    if not IsValid(ent) then return end
    ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
    ent.rareloadModel = w.model
    if w.player then
        local seq = ent:LookupSequence("idle_all_01")
        if seq and seq >= 0 then ent:ResetSequence(seq) end
    end
    return ent
end

-- wanted = { [key] = { model, pos, ang, skin?, color, player? } }. Phantoms not in `wanted` are removed.
function Phantoms.Sync(wanted)
    local reg, count = Phantoms.reg, 0
    for key, ent in pairs(reg) do
        local w = wanted[key]
        if not IsValid(ent) or not w or ent.rareloadModel ~= w.model then
            if IsValid(ent) then ent:Remove() end
            reg[key] = nil
        else
            count = count + 1
        end
    end
    for key, w in pairs(wanted) do
        local ent = reg[key]
        if not ent and count < MAX and usable(w.model) then
            ent = make(w)
            reg[key] = ent
            count = count + 1
        end
        if IsValid(ent) then
            ent:SetPos(w.pos)
            ent:SetAngles(w.ang)
            ent:SetSkin(w.skin or 0)
            ent:SetColor(w.color)
        end
    end
end

function Phantoms.Get(key)
    local ent = Phantoms.reg[key]
    return IsValid(ent) and ent or nil
end

function Phantoms.Clear()
    for _, ent in pairs(Phantoms.reg) do
        if IsValid(ent) then ent:Remove() end
    end
    Phantoms.reg = {}
end

hook.Add("ShutDown", "Rareload.Phantoms", Phantoms.Clear)
