-- Player modules: position and view, health and armor, states, appearance.

local Util = RARELOAD.Util

local function formatCoord(value) return string.format("%.0f", value) end

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

    restore = function(ply, saved, ctx)
        local pos, ang = Util.ToVector(saved.pos), Util.ToAngle(saved.ang)
        local crouched = saved.crouched == true
        -- Respawning "where I died" (D4): the save is restored, only the place is the death spot.
        local at = ctx and ctx.deathSpot
        if at then pos, ang, crouched = at.pos, at.ang, at.crouched == true end
        if not pos then return end

        -- Timeline restores can happen while seated or prop-driving (E13, E33).
        if ply:InVehicle() then ply:ExitVehicle() end
        if IsValid(ply:GetDrivingEntity()) then drive.PlayerStopDriving(ply) end

        -- A map update can move walls, so anti-stuck always runs when the map revision changed (G53).
        local check = RARELOAD.Get(ply, "antiStuck") or saved.mapVersion ~= game.GetMapVersion()
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
    summary = function(saved)
        return formatCoord(saved.pos[1]) .. ", " .. formatCoord(saved.pos[2]) .. ", " .. formatCoord(saved.pos[3])
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

    -- A save made on death (D4) keeps the health from before the fatal hit.
    save = function(ply, ctx)
        local healthBeforeDeath = ctx and ctx.opts and ctx.opts.deathHealth
        if healthBeforeDeath then return { hp = healthBeforeDeath.hp, armor = healthBeforeDeath.armor } end
        return { hp = ply:Health(), armor = ply:Armor() }
    end,

    restore = function(ply, saved)
        ply:SetHealth(math.Clamp(saved.hp or 1, 1, ply:GetMaxHealth()))
        ply:SetArmor(math.Clamp(saved.armor or 0, 0, ply:GetMaxArmor()))
    end,

    summary = function(saved) return "HP " .. saved.hp .. ", armor " .. saved.armor end,
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

    restore = function(ply, saved, ctx)
        local function mayGet(what)
            local ok, why = RARELOAD.Pipeline.Allowed(ply, false, what, PRIVILEGED, ctx.reason)
            if not ok then ctx:deny(what, why) end
            return ok
        end
        if not saved.god then
            ply:GodDisable()
        elseif not ply:HasGodMode() and mayGet("godmode") then
            ply:GodEnable()
        end
        if not saved.notarget then
            ply:SetNoTarget(false)
        elseif not ply:IsFlagSet(FL_NOTARGET) and mayGet("notarget") then
            ply:SetNoTarget(true)
        end
        ply:Freeze(saved.frozen == true)

        local flying = ply:GetMoveType() == MOVETYPE_NOCLIP
        if not saved.noclip then
            if flying then ply:SetMoveType(MOVETYPE_WALK) end
        elseif not flying then
            if hook.Run("PlayerNoClip", ply, true) == true then
                ply:SetMoveType(MOVETYPE_NOCLIP)
            else
                ctx:deny("noclip", "not allowed by the gamemode")
            end
        end

        if saved.flashlight ~= ply:FlashlightIsOn() and ply:CanUseFlashlight() then ply:Flashlight(saved.flashlight) end

        local vel = Util.ToVector(saved.vel)
        if vel then ply:SetLocalVelocity(vel) end
    end,

    summary = function(saved)
        local on = {}
        for _, stateName in ipairs(RARELOAD.PLAYER_STATES) do
            if saved[stateName] then on[#on + 1] = stateName end
        end
        return #on > 0 and table.concat(on, ", ") or "none"
    end,
})

local function setModel(ply, saved)
    if isstring(saved.model) and util.IsValidModel(saved.model) then
        ply:SetModel(saved.model)
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
        RARELOAD.Log("appearance", ply):warn("%s: the restored model %s was replaced by %s%s", ply:Nick(), model,
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
        local color = ply:GetColor()
        return {
            model = ply:GetModel(),
            skin = ply:GetSkin(),
            bodygroups = bodygroups,
            playerColor = Util.Vec(ply:GetPlayerColor()),
            weaponColor = Util.Vec(ply:GetWeaponColor()),
            material = ply:GetMaterial(),
            color = { color.r, color.g, color.b, color.a },
        }
    end,

    spawn = { hook = "PlayerSetModel", fn = setModel },

    -- Everything but the model runs after the sandbox player class has set its own colors.
    restore = function(ply, saved, ctx)
        if not ctx.spawnDone.appearance and setModel(ply, saved) then ply:SetupHands() end
        if isstring(saved.model) and util.IsValidModel(saved.model) then watchModel(ply, saved.model, ctx) end
        ply:SetSkin(saved.skin or 0)
        for i, value in ipairs(saved.bodygroups or {}) do ply:SetBodygroup(i - 1, value) end
        local pc, wc = Util.ToVector(saved.playerColor), Util.ToVector(saved.weaponColor)
        if pc then ply:SetPlayerColor(pc) end
        if wc then ply:SetWeaponColor(wc) end
        ply:SetMaterial(saved.material or "")
        local color = saved.color
        if istable(color) then ply:SetColor(Color(color[1], color[2], color[3], color[4])) end
    end,

    summary = function(saved) return string.GetFileFromFilename(saved.model or "?") end,
})

-- Movement and body (5.4 plan, B2): speeds, jump power, gravity, size, max health and armor, plus
-- FOV, suit power and fire. Values that grant power need rareload_restore_privileged_body, but only
-- when they differ from what the player has now, so a player who was never changed gets no warning.
local BODY_PRIV = "rareload_restore_privileged_body"

local function round(value) return isnumber(value) and math.Round(value, 2) or nil end

-- Built-in Player methods (all present in GMod, checked in game for players and bots).
local function get(ply, method) return ply[method](ply) end

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

local function setSize(ply, saved)
    ply:SetModelScale(saved.scale, 0)
    local view, ducked = Util.ToVector(saved.view), Util.ToVector(saved.viewDucked)
    if view then ply:SetViewOffset(view) end
    if ducked then ply:SetViewOffsetDucked(ducked) end
    if istable(saved.hull) and Util.ToVector(saved.hull[1]) and Util.ToVector(saved.hull[2]) then
        ply:SetHull(Util.ToVector(saved.hull[1]), Util.ToVector(saved.hull[2]))
    end
    if istable(saved.hullDuck) and Util.ToVector(saved.hullDuck[1]) and Util.ToVector(saved.hullDuck[2]) then
        ply:SetHullDuck(Util.ToVector(saved.hullDuck[1]), Util.ToVector(saved.hullDuck[2]))
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
        local data = {}
        for _, group in ipairs(BODY_GROUPS) do
            for _, field in ipairs(group.fields) do data[field[1]] = round(get(ply, field[2])) end
        end
        data.view, data.viewDucked = Util.Vec(ply:GetViewOffset()), Util.Vec(ply:GetViewOffsetDucked())
        data.hull, data.hullDuck = hullOf(ply:GetHull()), hullOf(ply:GetHullDuck())
        -- Only a FOV an addon set, not the suit zoom or the player's own fov_desired.
        local fov, wanted = ply:GetFOV(), ply:GetInfoNum("fov_desired", 75)
        if isnumber(fov) and fov > 0 and math.abs(fov - wanted) > 0.5 and not ply:KeyDown(IN_ZOOM) then
            data.fov = round(fov)
        end
        data.suit = round(get(ply, "GetSuitPower"))
        data.fire = ply:IsOnFire() or nil
        return data
    end,

    restore = function(ply, saved, ctx)
        for _, group in ipairs(BODY_GROUPS) do
            local changed = false
            for _, field in ipairs(group.fields) do
                changed = changed or differs(saved[field[1]], get(ply, field[2]))
            end
            if changed then
                local ok, why = RARELOAD.Pipeline.Allowed(ply, false, group.name, BODY_PRIV, ctx.reason)
                if not ok then
                    ctx:deny(group.name, why)
                elseif group.name == "size" then
                    setSize(ply, saved)
                else
                    for _, field in ipairs(group.fields) do
                        if isnumber(saved[field[1]]) then ply[field[3]](ply, saved[field[1]]) end
                    end
                end
            end
        end
        if isnumber(saved.fov) then ply:SetFOV(saved.fov, 0) end
        if isnumber(saved.suit) then ply:SetSuitPower(saved.suit) end
        if saved.fire then
            ply:Ignite(RARELOAD.Get(nil, "fireDuration"))
        elseif ply:IsOnFire() then
            ply:Extinguish()
        end
    end,

    summary = function(saved)
        local parts = {
            "walk " .. tostring(saved.walk), "run " .. tostring(saved.run), "jump " .. tostring(saved.jump),
        }
        if saved.scale and saved.scale ~= 1 then parts[#parts + 1] = "scale " .. saved.scale end
        if saved.fire then parts[#parts + 1] = "on fire" end
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
    table.sort(out, function(left, right) return tostring(left.self.UniqueID) < tostring(right.self.UniqueID) end)
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

    restore = function(ply, saved, ctx)
        if not pacReady() then return ctx:result("warn", "pac", "PAC3 is not installed") end
        local savedOutfits = istable(saved.outfits) and saved.outfits or {}
        if outfitIds(savedOutfits) == outfitIds(wornOutfits(ply)) then return end -- already wearing them
        -- PAC3 asks this when an outfit arrives from the player; servers use it to restrict PAC3.
        if isfunction(pac.CallHook) and pac.CallHook("CanWearParts", ply) == false then
            return ctx:deny("pac", "PAC3 is not allowed for you here")
        end
        -- Only the outfits that aren't in the save are taken off. PAC3 handles its queue newest first,
        -- so a full clear queued before the saved outfits would run after them and take them off too.
        -- A saved outfit already worn is simply replaced when it is worn again.
        local keep = {}
        for _, part in ipairs(savedOutfits) do
            if istable(part) and istable(part.self) then keep[tostring(part.self.UniqueID)] = true end
        end
        for _, part in ipairs(wornOutfits(ply)) do
            local id = tostring(part.self.UniqueID)
            if not keep[id] then pace.RemovePart({ part = id, uid = pac.Hash(ply), owner = ply }) end
        end
        for _, part in ipairs(savedOutfits) do
            if istable(part) and istable(part.self) then
                pace.HandleReceivedData(ply, { part = util.JSONToTable(util.TableToJSON(part)) })
            end
        end
        ctx:result("ok", "pac", #savedOutfits .. " outfits worn again")
    end,

    summary = function(saved) return #(istable(saved.outfits) and saved.outfits or {}) .. " PAC3 outfits" end,
})

-- An object held with the use key (5.4 plan, B5). It is saved with the world like any other object;
-- this only notes which one was held, and picks it up again once the world is back, when it is
-- still in reach. Objects held with the physgun can't be grabbed again from code.
local PICKUP_REACH = 150

-- While a player holds an object, GetEntityInUse returns the engine's player_pickup helper, not the
-- object, so the held object is noted when it is picked up and forgotten when it is dropped.
local held = setmetatable({}, { __mode = "kv" }) -- ply -> ent

hook.Add("OnPlayerPhysicsPickup", "Rareload.Holding", function(ply, ent) held[ply] = ent end)
hook.Add("OnPlayerPhysicsDrop", "Rareload.Holding", function(ply, ent)
    if held[ply] == ent then held[ply] = nil end
end)

RARELOAD.Module({
    id = "holding",
    phase = "finalize",
    setting = "keepStates",
    privSave = "rareload_save_states",
    privRestore = "rareload_restore_states",

    save = function(ply)
        local ent = held[ply]
        if IsValid(ent) and ent:IsPlayerHolding() and ent.RareloadID then return { id = ent.RareloadID } end
        return nil
    end,

    restore = function(ply, saved, ctx)
        ctx:nextTick(function()
            for _, ent in ents.Iterator() do
                if ent.RareloadID and tostring(ent.RareloadID) == tostring(saved.id) then
                    if ent:GetPos():DistToSqr(ply:GetShootPos()) < PICKUP_REACH ^ 2 and not ent:IsPlayerHolding() then
                        ply:PickupObject(ent)
                    end
                    return
                end
            end
        end)
    end,

    summary = function(saved) return "holding " .. tostring(saved.id) end,
})
