-- I may now realize that the player's model was not saved properly until now,
-- and I had waited until...
-- Well, let's just say I had forgotten, hm?
local function SavePlayerAppearance(ply)
    if not IsValid(ply) then return nil end

    local bgs = {}
    for _, v in ipairs(ply:GetBodyGroups() or {}) do
        bgs[tostring(v.id)] = ply:GetBodygroup(v.id)
    end

    local pColor = ply:GetPlayerColor()
    local wColor = ply:GetWeaponColor()
    local pColorTbl = pColor and { x = pColor.x, y = pColor.y, z = pColor.z } or nil
    local wColorTbl = wColor and { x = wColor.x, y = wColor.y, z = wColor.z } or nil

    local color = ply:GetColor()
    local colorTbl = color and { r = color.r, g = color.g, b = color.b, a = color.a } or nil

    local appearance = {
        model = ply:GetModel(),
        skin = ply:GetSkin(),
        bodygroups = bgs,
        playerColor = pColorTbl,
        weaponColor = wColorTbl,
        material = ply:GetMaterial(),
        color = colorTbl
    }
    
    if RARELOAD and RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write("save", "INFO", 0, "APPEARANCE SAVE: Extracted model: " .. tostring(appearance.model) .. " for player " .. tostring(ply:Nick()), { entity = ply })
    end

    return appearance
end

return SavePlayerAppearance
