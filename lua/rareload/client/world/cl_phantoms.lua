-- Phantoms: see-through client-side models of saved players and of saved objects, with the saved skin, bodygroups,
-- material, scale and colour, a seated pose for a
-- player saved in a vehicle, and a vehicle's parts (wheels, rotors…) placed as they were saved.
-- Every model lives in this registry, which removes them on shutdown and re-creates any the engine
-- deleted. They are never parented to server entities.

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

-- What a phantom is built from; a change rebuilds it. A saved object can have no model (it then
-- gets no phantom).
local function signature(wanted)
    return table.concat({ wanted.model or "", wanted.skin or 0, wanted.material or "", wanted.scale or 1,
        #(wanted.parts or {}),
        tostring(wanted.seated), util.TableToJSON(wanted.bodygroups or {}) }, "|")
end
Phantoms.Signature = signature

local function build(wanted)
    local ent = newModel(wanted.model)
    if not ent then return end
    ent.rareloadSig = wanted.sig or signature(wanted)
    ent:SetSkin(wanted.skin or 0)
    for index, value in pairs(wanted.bodygroups or {}) do
        if isnumber(index) then ent:SetBodygroup(index, value) end
    end
    if wanted.material and wanted.material ~= "" then ent:SetMaterial(wanted.material) end
    if wanted.scale and wanted.scale ~= 1 then ent:SetModelScale(wanted.scale, 0) end
    if wanted.playerColor then
        local color = wanted.playerColor
        ent.GetPlayerColor = function() return color end -- read by the player colour material proxy
    end
    if wanted.player then
        if wanted.seated then
            sit(ent)
        else
            local seq = ent:LookupSequence("idle_all_01")
            if seq and seq >= 0 then ent:ResetSequence(seq) end
        end
    end
    ent.parts = {}
    for _, savedPart in ipairs(wanted.parts or {}) do
        local lp, la = Util.ToVector(savedPart.lp), Util.ToAngle(savedPart.la)
        -- Older saves can list a base's invisible helpers, whose model is error.mdl.
        local real = UI.IsModel(savedPart.model) and string.lower(savedPart.model) ~= "models/error.mdl"
        local part = lp and la and real and newModel(savedPart.model)
        if part then
            part:SetSkin(savedPart.skin or 0)
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
        local phantom = wanted[key]
        if not IsValid(ent) or not phantom or ent.rareloadSig ~= (phantom.sig or signature(phantom)) then
            remove(ent)
            reg[key] = nil
        else
            count = count + 1
        end
    end
    for key, phantom in pairs(wanted) do
        local ent = reg[key]
        if not ent and count < MAX and UI.IsModel(phantom.model) then
            ent = build(phantom)
            reg[key] = ent
            count = count + 1
        end
        if IsValid(ent) then
            ent:SetPos(phantom.pos)
            ent:SetAngles(phantom.ang)
            ent:SetColor(phantom.color)
            for _, part in ipairs(ent.parts) do
                if IsValid(part) then part:SetColor(phantom.color) end
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
