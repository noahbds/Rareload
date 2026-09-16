RARELOAD = RARELOAD or {}
RARELOAD.Util = RARELOAD.Util or {}

-- Deterministic coarse spatial+appearance unique ID. Avoid including mutable runtime state (health changes etc.)
function RARELOAD.Util.GenerateDeterministicID(ent)
    if not IsValid(ent) then return "invalid_" .. tostring(ent) end
    local pos = ent.GetPos and ent:GetPos() or Vector(0, 0, 0)
    local ang = ent.GetAngles and ent:GetAngles() or Angle(0, 0, 0)
    local class = ent.GetClass and ent:GetClass() or "unknown"
    local model = ent.GetModel and ent:GetModel() or "nomodel"
    local skin = (ent.GetSkin and ent:GetSkin()) or 0
    local kv = ent.GetKeyValues and (ent:GetKeyValues() or {}) or {}
    local targetname = kv.targetname or ""
    local squad = kv.squadname or ""

    local numBG = 0
    if ent.GetNumBodyGroups then
        local ok, n = pcall(ent.GetNumBodyGroups, ent)
        if ok and isnumber(n) then numBG = n end
    end
    local bgParts = {}
    if numBG > 0 and ent.GetBodygroup then
        for i = 0, numBG - 1 do
            local ok, bg = pcall(ent.GetBodygroup, ent, i)
            if ok then bgParts[#bgParts + 1] = tostring(bg) end
        end
    end

    -- Per-entity uniqueness component: two identical props at the same spot share
    -- every spatial/appearance field, so without this they would hash to the same
    -- id and collide (the second would be skipped on restore / removed by id). The
    -- CreationID is unique per entity within a session; the generated id is stored
    -- and networked once by EnsureID, so it stays stable across saves afterwards.
    local creationID = 0
    if isfunction(ent.GetCreationID) then
        local ok, cid = pcall(ent.GetCreationID, ent)
        if ok and isnumber(cid) then creationID = cid end
    end

    local gx, gy, gz = math.floor(pos.x / 16), math.floor(pos.y / 16), math.floor(pos.z / 16)
    local base = table.concat({
        class, model, skin,
        gx, gy, gz,
        string.format("%.1f", ang.p or 0), string.format("%.1f", ang.y or 0), string.format("%.1f", ang.r or 0),
        targetname, squad, table.concat(bgParts, ","), creationID
    }, "|")

    local hash = util and util.CRC and util.CRC(base) or tostring(#base)
    return class .. "_" .. hash
end
