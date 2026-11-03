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
        local check = RARELOAD.Get(ply, "antiStuck") or d.mapVersion ~= game.GetMapVersion()
        if check and RARELOAD.AntiStuck.IsStuck(pos, ply, crouched) then
            local found, method = RARELOAD.AntiStuck.Resolve(pos, ply, crouched)
            if found then
                pos = found
                ctx:step("warn", "anti-stuck", "moved to a free spot (" .. method .. ")")
            else
                ctx:step("fail", "anti-stuck", "no free spot found")
                RARELOAD.Toast(ply, "toast.stuck", nil, "error")
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
    after = { "body" }, -- clamped to the restored max health
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
-- A state the player may not be given is left as it is: Rareload never takes away one they have.
local PRIVILEGED = "rareload_restore_privileged_states"

RARELOAD.Module({
    id = "states",
    phase = "player",
    setting = "keepStates",
    privSave = "rareload_save_states",
    privRestore = "rareload_restore_states",

    save = function(ply, ctx)
        local god, notarget = ply:HasGodMode(), ply:IsFlagSet(FL_NOTARGET)
        if (god or notarget) and not RARELOAD.Can(ply, PRIVILEGED) then
            if god then ctx.denied[#ctx.denied + 1] = "godmode" end
            if notarget then ctx.denied[#ctx.denied + 1] = "notarget" end
        end
        return {
            god = god,
            notarget = notarget,
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

    restore = function(ply, d, ctx)
        local function mayGet(what)
            local ok, why = RARELOAD.Pipeline.Allowed(ply, false, what, PRIVILEGED, ctx.reason)
            if not ok then ctx:deny(what, why) end
            return ok
        end
        if not d.god then
            ply:GodDisable()
        elseif not ply:HasGodMode() and mayGet("godmode") then
            ply:GodEnable()
        end
        if not d.notarget then
            ply:SetNoTarget(false)
        elseif not ply:IsFlagSet(FL_NOTARGET) and mayGet("notarget") then
            ply:SetNoTarget(true)
        end
        ply:Freeze(d.frozen == true)

        local flying = ply:GetMoveType() == MOVETYPE_NOCLIP
        if not d.noclip then
            if flying then ply:SetMoveType(MOVETYPE_WALK) end
        elseif not flying then
            if hook.Run("PlayerNoClip", ply, true) == true then
                ply:SetMoveType(MOVETYPE_NOCLIP)
            else
                ctx:deny("noclip", "not allowed by the gamemode")
            end
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

local function setModel(ply, d)
    if isstring(d.model) and util.IsValidModel(d.model) then
        ply:SetModel(d.model)
        return true
    end
end

-- Playermodel addons can put the player's own model back right after a spawn (Enhanced PlayerModel
-- Selector's "Enforce your playermodel", G16, B17). The restored model is watched for a moment, and
-- the player is told which option to turn off when it was replaced. The report card is already sent
-- by then, so this is a toast and a log line.
local WATCH = 2
local EPS_FORCE = "sv_playermodel_selector_force"

local function watchModel(ply, model, ctx)
    model = string.lower(model)
    ctx:waitFor(function() return string.lower(ply:GetModel() or "") ~= model end, WATCH, function()
        local eps = ConVarExists(EPS_FORCE)
        RARELOAD.Log("appearance"):warn("%s: the restored model %s was replaced by %s%s", ply:Nick(), model,
            ply:GetModel(), eps and " (Enhanced PlayerModel Selector)" or "")
        RARELOAD.Toast(ply, eps and "toast.model_enforced" or "toast.model_replaced", nil, "error")
    end)
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
        if isstring(d.model) and util.IsValidModel(d.model) then watchModel(ply, d.model, ctx) end
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

-- Movement and body (5.4 plan, B2): speeds, jump power, gravity, size, max health and armor, plus
-- FOV, suit power and fire. Values that grant power need rareload_restore_privileged_body, but only
-- when they differ from what the player has now, so a player who was never changed gets no warning.
local BODY_PRIV = "rareload_restore_privileged_body"

local function round(v) return isnumber(v) and math.Round(v, 2) or nil end

local function get(ply, method)
    if not isfunction(ply[method]) then return nil end
    local ok, v = pcall(ply[method], ply)
    return ok and v or nil
end

local function hullOf(mins, maxs)
    return isvector(mins) and isvector(maxs) and { Util.Vec(mins), Util.Vec(maxs) } or nil
end

-- Privileged groups: what they hold and how each value is set.
local BODY_GROUPS = {
    { name = "movement", fields = {
        { "walk", "GetWalkSpeed", "SetWalkSpeed" }, { "run", "GetRunSpeed", "SetRunSpeed" },
        { "slowWalk", "GetSlowWalkSpeed", "SetSlowWalkSpeed" },
        { "crouchWalk", "GetCrouchedWalkSpeed", "SetCrouchedWalkSpeed" },
        { "jump", "GetJumpPower", "SetJumpPower" }, { "gravity", "GetGravity", "SetGravity" },
    } },
    { name = "size", fields = { { "scale", "GetModelScale" } } },
    { name = "max health", fields = {
        { "maxHp", "GetMaxHealth", "SetMaxHealth" }, { "maxArmor", "GetMaxArmor", "SetMaxArmor" },
    } },
}

local function differs(saved, now)
    return isnumber(saved) and isnumber(now) and math.abs(saved - now) > 0.01
end

local function setSize(ply, d)
    ply:SetModelScale(d.scale, 0)
    local view, ducked = Util.ToVector(d.view), Util.ToVector(d.viewDucked)
    if view then ply:SetViewOffset(view) end
    if ducked then ply:SetViewOffsetDucked(ducked) end
    if istable(d.hull) and Util.ToVector(d.hull[1]) and Util.ToVector(d.hull[2]) then
        ply:SetHull(Util.ToVector(d.hull[1]), Util.ToVector(d.hull[2]))
    end
    if istable(d.hullDuck) and Util.ToVector(d.hullDuck[1]) and Util.ToVector(d.hullDuck[2]) then
        ply:SetHullDuck(Util.ToVector(d.hullDuck[1]), Util.ToVector(d.hullDuck[2]))
    end
end

RARELOAD.Module({
    id = "body",
    phase = "player",
    after = { "appearance" }, -- the model is set before its scale
    setting = "keepBody",
    privSave = "rareload_save_states",
    privRestore = "rareload_restore_states",

    save = function(ply)
        local d = {}
        for _, group in ipairs(BODY_GROUPS) do
            for _, f in ipairs(group.fields) do d[f[1]] = round(get(ply, f[2])) end
        end
        d.view, d.viewDucked = Util.Vec(ply:GetViewOffset()), Util.Vec(ply:GetViewOffsetDucked())
        d.hull, d.hullDuck = hullOf(ply:GetHull()), hullOf(ply:GetHullDuck())
        -- Only a FOV an addon set, not the suit zoom or the player's own fov_desired.
        local fov, wanted = ply:GetFOV(), ply:GetInfoNum("fov_desired", 75)
        if isnumber(fov) and fov > 0 and math.abs(fov - wanted) > 0.5 and not ply:KeyDown(IN_ZOOM) then
            d.fov = round(fov)
        end
        d.suit = round(get(ply, "GetSuitPower"))
        d.fire = ply:IsOnFire() or nil
        return d
    end,

    restore = function(ply, d, ctx)
        for _, group in ipairs(BODY_GROUPS) do
            local changed = false
            for _, f in ipairs(group.fields) do
                changed = changed or differs(d[f[1]], get(ply, f[2]))
            end
            if changed then
                local ok, why = RARELOAD.Pipeline.Allowed(ply, false, group.name, BODY_PRIV, ctx.reason)
                if not ok then
                    ctx:deny(group.name, why)
                elseif group.name == "size" then
                    setSize(ply, d)
                else
                    for _, f in ipairs(group.fields) do
                        if isnumber(d[f[1]]) and isfunction(ply[f[3]]) then ply[f[3]](ply, d[f[1]]) end
                    end
                end
            end
        end
        if isnumber(d.fov) then ply:SetFOV(d.fov, 0) end
        if isnumber(d.suit) and isfunction(ply.SetSuitPower) then ply:SetSuitPower(d.suit) end
        if d.fire then
            ply:Ignite(RARELOAD.Get(nil, "fireDuration"))
        elseif ply:IsOnFire() then
            ply:Extinguish()
        end
    end,

    summary = function(d)
        local parts = { "walk " .. tostring(d.walk), "run " .. tostring(d.run), "jump " .. tostring(d.jump) }
        if d.scale and d.scale ~= 1 then parts[#parts + 1] = "scale " .. d.scale end
        if d.fire then parts[#parts + 1] = "on fire" end
        return table.concat(parts, ", ")
    end,
})

-- PAC3 outfits (5.4 plan, B4). PAC3 keeps each player's worn outfits on the server; they are worn
-- again through PAC3's own receive function, which applies its checks, as if the player had sent
-- them. Only outfits on the player themselves are kept, not ones put on other entities.
local function pacReady() return istable(pace) and istable(pace.Parts) and istable(pac) and isfunction(pac.Hash) end

local function wornOutfits(ply)
    local out = {}
    for _, data in pairs(pace.Parts[pac.Hash(ply)] or {}) do
        local part = istable(data) and data.part
        if istable(part) and istable(part.self) and part.self.UniqueID and not tonumber(part.self.OwnerName) then
            out[#out + 1] = part
        end
    end
    table.sort(out, function(a, b) return tostring(a.self.UniqueID) < tostring(b.self.UniqueID) end)
    return out
end

local function outfitIds(list)
    local ids = {}
    for _, part in ipairs(list) do ids[#ids + 1] = tostring(istable(part.self) and part.self.UniqueID) end
    return table.concat(ids, ",")
end

RARELOAD.Module({
    id = "pac",
    phase = "player",
    after = { "appearance" },
    heavy = true, -- outfits can be large
    setting = "keepAppearance",
    privSave = "rareload_save_appearance",
    privRestore = "rareload_restore_appearance",

    save = function(ply)
        if not pacReady() then return nil end
        return { outfits = util.JSONToTable(util.TableToJSON(wornOutfits(ply))) or {} }
    end,

    restore = function(ply, d, ctx)
        if not pacReady() then return ctx:result("warn", "pac", "PAC3 is not installed") end
        local saved = istable(d.outfits) and d.outfits or {}
        if outfitIds(saved) == outfitIds(wornOutfits(ply)) then return end -- already wearing them
        -- PAC3 asks this when an outfit arrives from the player; servers use it to restrict PAC3.
        if isfunction(pac.CallHook) and pac.CallHook("CanWearParts", ply) == false then
            return ctx:deny("pac", "PAC3 is not allowed for you here")
        end
        pace.ClearOutfit(ply)
        for _, part in ipairs(saved) do
            if istable(part) and istable(part.self) then
                pace.HandleReceivedData(ply, { part = util.JSONToTable(util.TableToJSON(part)) })
            end
        end
        ctx:result("ok", "pac", #saved .. " outfits worn again")
    end,

    summary = function(d) return #(istable(d.outfits) and d.outfits or {}) .. " PAC3 outfits" end,
})

-- An object held with the use key (5.4 plan, B5). It is saved with the world like any other object;
-- this only notes which one was held, and picks it up again once the world is back, when it is
-- still in reach. Objects held with the physgun can't be grabbed again from code.
local PICKUP_REACH = 150

RARELOAD.Module({
    id = "holding",
    phase = "finalize",
    setting = "keepStates",
    privSave = "rareload_save_states",
    privRestore = "rareload_restore_states",

    save = function(ply)
        local ent = ply:GetEntityInUse()
        if IsValid(ent) and ent:IsPlayerHolding() and ent.RareloadID then return { id = ent.RareloadID } end
        return nil
    end,

    restore = function(ply, d, ctx)
        ctx:nextTick(function()
            for _, ent in ents.Iterator() do
                if ent.RareloadID and tostring(ent.RareloadID) == tostring(d.id) then
                    if ent:GetPos():DistToSqr(ply:GetShootPos()) < PICKUP_REACH ^ 2 and not ent:IsPlayerHolding() then
                        ply:PickupObject(ent)
                    end
                    return
                end
            end
        end)
    end,

    summary = function(d) return "holding " .. tostring(d.id) end,
})
