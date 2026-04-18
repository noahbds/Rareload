---@diagnostic disable: inject-field

RARELOAD = RARELOAD or {}
RARELOAD.EntityIdentity = RARELOAD.EntityIdentity or {}

local EntityIdentity = RARELOAD.EntityIdentity

if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function ReadNetworkID(ent)
    if not IsValid(ent) or not ent.GetNWString then return nil end

    local ok, value = pcall(ent.GetNWString, ent, "RareloadID", "")
    if ok and isstring(value) and value ~= "" then
        return value
    end

    return nil
end

function EntityIdentity.GenerateDeterministicID(ent, fallback)
    if RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID then
        local generated = RARELOAD.Util.GenerateDeterministicID(ent)
        if isstring(generated) and generated ~= "" then
            return generated
        end
    end

    return fallback
end

function EntityIdentity.SetID(ent, fieldName, id)
    if not IsValid(ent) then return nil end
    if not isstring(fieldName) or fieldName == "" then return nil end
    if not isstring(id) or id == "" then return nil end

    ent[fieldName] = id

    if ent.SetNWString then
        pcall(ent.SetNWString, ent, "RareloadID", id)
    end

    return id
end

function EntityIdentity.GetID(ent, fieldName)
    if not IsValid(ent) then return nil end
    if not isstring(fieldName) or fieldName == "" then return nil end

    local current = ent[fieldName]
    if isstring(current) and current ~= "" then
        return current
    end

    local networkID = ReadNetworkID(ent)
    if networkID then
        ent[fieldName] = networkID
        return networkID
    end

    return nil
end

function EntityIdentity.EnsureID(ent, fieldName, fallback)
    local current = EntityIdentity.GetID(ent, fieldName)
    if current then
        local networkID = ReadNetworkID(ent)
        if not networkID then
            EntityIdentity.SetID(ent, fieldName, current)
        end
        return current
    end

    local generated = EntityIdentity.GenerateDeterministicID(ent, fallback)
    if not generated then return nil end

    return EntityIdentity.SetID(ent, fieldName, generated)
end

return EntityIdentity
