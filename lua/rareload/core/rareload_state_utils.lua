---@diagnostic disable: inject-field
RARELOAD = RARELOAD or {}
RARELOAD.Util = RARELOAD.Util or {}

function RARELOAD.Util.GenerateEntityStateHash(data)
    if not data or type(data) ~= "table" then return "invalid" end

    local parts = {}
    local function add(v)
        parts[#parts + 1] = tostring(v ~= nil and v or "")
    end

    add(data.material)
    add(data.model or "")
    add(data.skin or 0)
    add(data.health or 0)
    add(data.maxHealth or 0)
    add(data.modelScale or 1)
    add(data.collisionGroup or 0)
    add(data.moveType or 0)
    add(data.solidType or 0)
    add(data.spawnFlags or 0)

    if data.color then
        add(data.color.r or 255); add(data.color.g or 255); add(data.color.b or 255); add(data.color.a or 255)
    else
        add(255); add(255); add(255); add(255)
    end

    if data.bodygroups then
        local ids = {}
        for id in pairs(data.bodygroups) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
        for _, id in ipairs(ids) do
            parts[#parts + 1] = (tostring(id) .. "=" .. tostring(data.bodygroups[id]))
        end
    end

    add(data.physicsMaterial or "")
    add(data.gravityEnabled == false and 0 or 1)
    add(data.elasticity or 0)
    add(data.frozen and 1 or 0)
    add(data.mass or 0)

    return util and util.CRC and util.CRC(table.concat(parts, "|")) or tostring(#parts)
end

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

    local gx, gy, gz = math.floor(pos.x / 16), math.floor(pos.y / 16), math.floor(pos.z / 16)
    local base = table.concat({
        class, model, skin,
        gx, gy, gz,
        string.format("%.1f", ang.p or 0), string.format("%.1f", ang.y or 0), string.format("%.1f", ang.r or 0),
        targetname, squad, table.concat(bgParts, ",")
    }, "|")

    local hash = util and util.CRC and util.CRC(base) or tostring(#base)
    return class .. "_" .. hash
end
