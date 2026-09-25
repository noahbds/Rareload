-- Player modules: position and view, health and armor, states, appearance (REWRITE_PLAN.md §14.1).

local Util = RARELOAD.Util

local function fmt(v) return string.format("%.0f", v) end

RARELOAD.Module({
    id = "transform",
    phase = "position",

    save = function(ply, ctx)
        return {
            pos = Util.Vec(ctx.opts.at or ply:GetPos()),
            ang = Util.Ang(ply:EyeAngles()),
            crouched = (not ctx.opts.at and ply:Crouching()) or nil,
            mapVersion = game.GetMapVersion(),
        }
    end,

    restore = function(ply, d, ctx)
        local pos, ang = Util.ToVector(d.pos), Util.ToAngle(d.ang)
        if not pos then return end
        local crouched = d.crouched == true

        -- Timeline restores can happen while seated or prop-driving (E13, E33).
        if ply:InVehicle() then ply:ExitVehicle() end
        if IsValid(ply:GetDrivingEntity()) then drive.PlayerStopDriving(ply) end

        -- A map update can move walls, so anti-stuck always runs when the map revision changed (G53).
        if RARELOAD.Get(ply, "antiStuck") or d.mapVersion ~= game.GetMapVersion() then
            if RARELOAD.AntiStuck.IsStuck(pos, ply, crouched) then
                local found, method = RARELOAD.AntiStuck.Resolve(pos, ply, crouched)
                if found then
                    pos = found
                    ctx:step("warn", "anti-stuck", "moved to a free spot (" .. method .. ")")
                else
                    ctx:step("fail", "anti-stuck", "no free spot found")
                    RARELOAD.Toast(ply, "toast.stuck", nil, "error")
                end
            end
        end

        -- A save made crouched (e.g. in a vent) must stay crouched to fit (E32).
        if crouched then ply:AddFlags(FL_DUCKING) end
        ply:SetPos(pos)
        if ang then ply:SetEyeAngles(ang) end
        ply:SetLocalVelocity(vector_origin)
        RARELOAD.AntiStuck.Watch(ply, pos)
    end,

    -- Not "[x y z]": GMod's JSON reads a string of that shape back as a Vector.
    summary = function(d)
        return fmt(d.pos[1]) .. ", " .. fmt(d.pos[2]) .. ", " .. fmt(d.pos[3])
    end,
})

-- Restoring never gives more than the player's current maximum (S14).
RARELOAD.Module({
    id = "health",
    phase = "player",
    setting = "keepHealth",
    privSave = "rareload_save_health_armor",
    privRestore = "rareload_restore_health_armor",

    save = function(ply)
        return { hp = ply:Health(), armor = ply:Armor() }
    end,

    restore = function(ply, d)
        ply:SetHealth(math.Clamp(d.hp or 1, 1, ply:GetMaxHealth()))
        ply:SetArmor(math.Clamp(d.armor or 0, 0, ply:GetMaxArmor()))
    end,

    summary = function(d) return "HP " .. d.hp .. ", armor " .. d.armor end,
})

-- Symmetric: every state is set or cleared (B4). Each grant is checked against what the player may
-- have right now, so an old save can't give back something an admin took away (S14, G58, B25).
RARELOAD.Module({
    id = "states",
    phase = "player",
    setting = "keepStates",
    privSave = "rareload_save_states",
    privRestore = "rareload_restore_states",

    save = function(ply)
        return {
            god = ply:HasGodMode(),
            notarget = ply:IsFlagSet(FL_NOTARGET),
            frozen = ply:IsFrozen(),
            -- Seated players have the noclip move type too; that isn't noclip.
            noclip = ply:GetMoveType() == MOVETYPE_NOCLIP and not ply:InVehicle(),
            flashlight = ply:FlashlightIsOn(),
            vel = Util.Vec(ply:GetVelocity()),
            -- Add more states here if they can be set or cleared by the player (G58, B25).
            -- Possible savable states: crouched, sprinting, ducking, zoomed,
            -- on fire, in water, on ladder, in vehicle, driving.
        }
    end,

    restore = function(ply, d)
        local privileged = RARELOAD.Can(ply, "rareload_restore_privileged_states")
        if d.god and privileged then ply:GodEnable() else ply:GodDisable() end
        ply:SetNoTarget(d.notarget == true and privileged)
        ply:Freeze(d.frozen == true)

        if d.noclip and hook.Run("PlayerNoClip", ply, true) == true then
            ply:SetMoveType(MOVETYPE_NOCLIP)
        elseif ply:GetMoveType() == MOVETYPE_NOCLIP then
            ply:SetMoveType(MOVETYPE_WALK)
        end

        if d.flashlight ~= ply:FlashlightIsOn() and ply:CanUseFlashlight() then ply:Flashlight(d.flashlight) end

        local vel = Util.ToVector(d.vel)
        if vel then ply:SetLocalVelocity(vel) end
    end,

    summary = function(d)
        local on = {}
        for _, k in ipairs({ "god", "notarget", "frozen", "noclip", "flashlight" }) do
            if d[k] then on[#on + 1] = k end
        end
        return #on > 0 and table.concat(on, ", ") or "none"
    end,
})

-- The most popular playermodel addons (e.g : Enhanced PlayerModel Selector)
-- have a playermodel enforcement that might prevent the model restoration.
-- The option is called "Enforce your playermodel".
-- We might need to add a addon detection and warn the user about it. (G16, B17)
local function setModel(ply, d)
    if isstring(d.model) and util.IsValidModel(d.model) then
        ply:SetModel(d.model)
        return true
    end
end

RARELOAD.Module({
    id = "appearance",
    phase = "player",
    setting = "keepAppearance",
    privSave = "rareload_save_appearance",
    privRestore = "rareload_restore_appearance",

    save = function(ply)
        local bodygroups = {}
        for i = 0, ply:GetNumBodyGroups() - 1 do bodygroups[#bodygroups + 1] = ply:GetBodygroup(i) end
        local c = ply:GetColor()
        return {
            model = ply:GetModel(),
            skin = ply:GetSkin(),
            bodygroups = bodygroups,
            playerColor = Util.Vec(ply:GetPlayerColor()),
            weaponColor = Util.Vec(ply:GetWeaponColor()),
            material = ply:GetMaterial(),
            color = { c.r, c.g, c.b, c.a },
        }
    end,

    spawn = { hook = "PlayerSetModel", fn = setModel },

    -- Everything but the model runs after the sandbox player class has set its own colors.
    restore = function(ply, d, ctx)
        if not ctx.spawnDone.appearance and setModel(ply, d) then ply:SetupHands() end
        ply:SetSkin(d.skin or 0)
        for i, value in ipairs(d.bodygroups or {}) do ply:SetBodygroup(i - 1, value) end
        local pc, wc = Util.ToVector(d.playerColor), Util.ToVector(d.weaponColor)
        if pc then ply:SetPlayerColor(pc) end
        if wc then ply:SetWeaponColor(wc) end
        ply:SetMaterial(d.material or "")
        if istable(d.color) then ply:SetColor(Color(d.color[1], d.color[2], d.color[3], d.color[4])) end
    end,

    summary = function(d) return string.GetFileFromFilename(d.model or "?") end,
})
