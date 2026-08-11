-- I may now realize that the player's model was not restored until now,
-- and I had waited until...
-- Well, let's just say I had forgotten, hm?
function RARELOAD.RestoreAppearance(ply, app)
    if not IsValid(ply) or not app then return end

    if app.model then
        util.PrecacheModel(app.model)
        ply:SetModel(app.model)
        -- Update the client's convar so their C-menu reflects the restored model
        ply:ConCommand("cl_playermodel " .. app.model)
    end

    if app.skin then
        ply:SetSkin(app.skin)
    end

    if app.bodygroups then
        for idStr, val in pairs(app.bodygroups) do
            local id = tonumber(idStr)
            if id then
                ply:SetBodygroup(id, val)
            end
        end
    end

    if app.playerColor then
        ply:SetPlayerColor(Vector(app.playerColor.x, app.playerColor.y, app.playerColor.z))
    end

    if app.weaponColor then
        ply:SetWeaponColor(Vector(app.weaponColor.x, app.weaponColor.y, app.weaponColor.z))
    end

    if app.material then
        ply:SetMaterial(app.material)
    end

    if app.color then
        ply:SetColor(Color(app.color.r, app.color.g, app.color.b, app.color.a))
    end

    ply:SetupHands()
end
