-- Phantoms: see-through client-side models of saved players and of saved objects (REWRITE_PLAN.md
-- §21.7, F31, F32), with the saved skin, bodygroups, material, scale and colour, a seated pose for a
-- player saved in a vehicle, and a vehicle's parts (wheels, rotors…) placed as they were saved.
-- Every model lives in this registry, which removes them on shutdown and re-creates any the engine
-- deleted (G36). They are never parented to server entities.

RARELOAD.Phantoms = RARELOAD.Phantoms or { reg = {} }
local Phantoms = RARELOAD.Phantoms
local Util, UI = RARELOAD.Util, RARELOAD.UI
local MAX = 256

local SIT_ACTS = { ACT_HL2MP_SIT, ACT_HL2MP_SIT_PASSIVE, ACT_HL2MP_SIT_PISTOL }

local function newModel(model)
    local ent = ClientsideModel(model, RENDERGROUP_TRANSLUCENT)
    if not IsValid(ent) then return end
    ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
    return ent
end

local function sit(ent)
    ent:SetIK(false)
    for _, act in ipairs(SIT_ACTS) do
        local seq = act and ent:SelectWeightedSequence(act)
        if seq and seq > 0 then
            ent:ResetSequence(seq)
            ent:SetCycle(0)
            ent:SetPlaybackRate(0)
            return
        end
    end
end

-- What a phantom is built from; a change rebuilds it.
local function signature(w)
    return table.concat({ w.model, w.skin or 0, w.material or "", w.scale or 1, #(w.parts or {}), tostring(w.seated),
        util.TableToJSON(w.bodygroups or {}) }, "|")
end
Phantoms.Signature = signature

local function build(w)
    local ent = newModel(w.model)
    if not ent then return end
    ent.rareloadSig = w.sig or signature(w)
    ent:SetSkin(w.skin or 0)
    for index, value in pairs(w.bodygroups or {}) do
        if isnumber(index) then ent:SetBodygroup(index, value) end
    end
    if w.material and w.material ~= "" then ent:SetMaterial(w.material) end
    if w.scale and w.scale ~= 1 then ent:SetModelScale(w.scale, 0) end
    if w.playerColor then
        local color = w.playerColor
        ent.GetPlayerColor = function() return color end   -- read by the player colour material proxy
    end
    if w.player then
        if w.seated then
            sit(ent)
        else
            local seq = ent:LookupSequence("idle_all_01")
            if seq and seq >= 0 then ent:ResetSequence(seq) end
        end
    end
    ent.parts = {}
    for _, p in ipairs(w.parts or {}) do
        local lp, la = Util.ToVector(p.lp), Util.ToAngle(p.la)
        local part = lp and la and UI.IsModel(p.model) and newModel(p.model)
        if part then
            part:SetSkin(p.skin or 0)
            part:SetParent(ent)
            part:SetLocalPos(lp)
            part:SetLocalAngles(la)
            ent.parts[#ent.parts + 1] = part
        end
    end
    return ent
end

local function remove(ent)
    if not IsValid(ent) then return end
    for _, part in ipairs(ent.parts or {}) do
        if IsValid(part) then part:Remove() end
    end
    ent:Remove()
end

-- wanted = { [key] = { model, pos, ang, color, skin?, bodygroups?, material?, scale?, parts?, player?,
-- seated?, playerColor?, sig? (Phantoms.Signature of the entry, when the caller keeps it) } }.
-- Phantoms not in `wanted` are removed.
function Phantoms.Sync(wanted)
    local reg, count = Phantoms.reg, 0
    for key, ent in pairs(reg) do
        local w = wanted[key]
        if not IsValid(ent) or not w or ent.rareloadSig ~= (w.sig or signature(w)) then
            remove(ent)
            reg[key] = nil
        else
            count = count + 1
        end
    end
    for key, w in pairs(wanted) do
        local ent = reg[key]
        if not ent and count < MAX and UI.IsModel(w.model) then
            ent = build(w)
            reg[key] = ent
            count = count + 1
        end
        if IsValid(ent) then
            ent:SetPos(w.pos)
            ent:SetAngles(w.ang)
            ent:SetColor(w.color)
            for _, part in ipairs(ent.parts) do
                if IsValid(part) then part:SetColor(w.color) end
            end
        end
    end
end

function Phantoms.Get(key)
    local ent = Phantoms.reg[key]
    return IsValid(ent) and ent or nil
end

function Phantoms.Clear()
    for _, ent in pairs(Phantoms.reg) do remove(ent) end
    Phantoms.reg = {}
end

hook.Add("ShutDown", "Rareload.Phantoms", Phantoms.Clear)
