-- The scene (5.4 plan, C9-C11): the map's own doors, locks, breakables and physics props, the time
-- of day, weather and sky, and the world settings (gravity, physics speed, AI switches). These are
-- shared by everyone on the server, so saving and restoring them needs rareload_save_scene and
-- rareload_restore_scene (admin), and each part has a server setting that is on in singleplayer
-- only. They are not restored on a respawn after a death: dying shouldn't turn back the time or
-- close every door.

local Util = RARELOAD.Util

local function round(v, places) return isnumber(v) and math.Round(v, places or 0) or nil end

local function internal(ent, name)
    local ok, v = pcall(ent.GetInternalVariable, ent, name)
    return ok and v or nil
end

-- Map state (C9) ------------------------------------------------------------------------------------

-- prop_door_rotating m_eDoorState: 0 closed, 1 opening, 2 open, 3 closing.
-- func_door m_toggle_state: 0 open (at top), 1 closed (at bottom), 2 opening, 3 closing.
local DOOR_OPEN = { prop_door_rotating = { [1] = true, [2] = true }, func_door = { [0] = true, [2] = true } }
DOOR_OPEN.func_door_rotating = DOOR_OPEN.func_door
local DOOR_FIELD = { prop_door_rotating = "m_eDoorState", func_door = "m_toggle_state",
    func_door_rotating = "m_toggle_state" }
local LOCKABLE = { func_button = true, func_rot_button = true }
local BREAKABLE = { func_breakable = true, func_breakable_surf = true, func_physbox = true }
local PROPS = { prop_physics = true, prop_physics_multiplayer = true, prop_physics_respawnable = true }

local function mapEntities()
    local out = {}
    for _, ent in ents.Iterator() do
        if IsValid(ent) and ent:CreatedByMap() then
            local id = ent:MapCreationID()
            if isnumber(id) and id >= 0 then out[id] = ent end
        end
    end
    return out
end

local function captureMapEntity(id, ent)
    local class = ent:GetClass()
    if DOOR_FIELD[class] then
        local state = tonumber(internal(ent, DOOR_FIELD[class]))
        return { id = id, kind = "door", open = state and DOOR_OPEN[class][state] or false,
            locked = internal(ent, "m_bLocked") == true }
    end
    if LOCKABLE[class] then return { id = id, kind = "button", locked = internal(ent, "m_bLocked") == true } end
    if BREAKABLE[class] then return { id = id, kind = "breakable" } end
    if PROPS[class] then
        local phys = ent:GetPhysicsObject()
        local a = ent:GetAngles()
        return { id = id, kind = "prop", pos = { round(ent:GetPos().x), round(ent:GetPos().y), round(ent:GetPos().z) },
            ang = { round(a.p), round(a.y), round(a.r) }, frozen = IsValid(phys) and not phys:IsMotionEnabled() }
    end
end

local function applyMapEntity(ent, rec)
    if rec.kind == "door" or rec.kind == "button" then
        ent:Fire("Unlock")
        if rec.kind == "door" then ent:Fire(rec.open and "Open" or "Close") end
        if rec.locked then ent:Fire("Lock", "", 0.1) end
    elseif rec.kind == "prop" then
        local pos, ang = Util.ToVector(rec.pos), Util.ToAngle(rec.ang)
        if pos then ent:SetPos(pos) end
        if ang then ent:SetAngles(ang) end
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(vector_origin)
            phys:EnableMotion(not rec.frozen)
            phys:Sleep()
        end
    end
end

RARELOAD.Module({
    id = "mapState",
    phase = "world",
    heavy = true,
    skipOnDeath = true,
    setting = "keepMapState",
    privSave = "rareload_save_scene",
    privRestore = "rareload_restore_scene",

    save = function()
        local list = {}
        for id, ent in SortedPairs(mapEntities()) do
            local rec = captureMapEntity(id, ent)
            if rec then list[#list + 1] = rec end
        end
        return { mapVersion = game.GetMapVersion(), entities = list }
    end,

    restore = function(_, d, ctx)
        if d.mapVersion ~= game.GetMapVersion() then
            return ctx:result("warn", "mapState", "the map was updated since the save; left as it is")
        end
        local live, set, removed, gone = mapEntities(), 0, 0, 0
        local saved = {}
        for _, rec in ipairs(istable(d.entities) and d.entities or {}) do
            local id = tonumber(rec.id)
            if id then saved[id] = rec end
        end
        for id, rec in pairs(saved) do
            local ent = live[id]
            if IsValid(ent) then
                applyMapEntity(ent, rec)
                set = set + 1
            elseif rec.kind == "breakable" or rec.kind == "prop" then
                gone = gone + 1 -- broken since the save; only a map cleanup brings it back
            end
        end
        -- Broken or removed in the save, still here now: removed again.
        for id, ent in pairs(live) do
            local class = ent:GetClass()
            if not saved[id] and (BREAKABLE[class] or PROPS[class]) then
                ent:Remove()
                removed = removed + 1
            end
        end
        ctx:result(gone > 0 and "warn" or "ok", "mapState", set .. " map objects set, " .. removed .. " removed"
            .. (gone > 0 and ", " .. gone .. " broken since the save can only come back with a map cleanup" or ""))
    end,

    summary = function(d) return #(istable(d.entities) and d.entities or {}) .. " map objects" end,
})

-- Environment (C10) ----------------------------------------------------------------------------------

local function stormFox() return istable(StormFox2) and istable(StormFox2.Time) and istable(StormFox2.Weather) end

local call = RARELOAD.Util.Call

-- The sky paint (Sandbox's sky editor changes it): its networked values.
local function skyPaint()
    return ents.FindByClass("env_skypaint")[1]
end

RARELOAD.Module({
    id = "environment",
    phase = "world",
    skipOnDeath = true,
    setting = "keepEnvironment",
    privSave = "rareload_save_scene",
    privRestore = "rareload_restore_scene",

    save = function()
        local d = {}
        if stormFox() then
            local SF = StormFox2
            local weather = call(SF.Weather.GetCurrent)
            d.stormfox = {
                time = round(call(SF.Time.Get, true)),
                paused = call(SF.Time.IsPaused) == true,
                weather = istable(weather) and weather.Name or nil,
                percent = round(call(SF.Weather.GetPercent), 2),
                temp = istable(SF.Temperature) and round(call(SF.Temperature.Get), 1) or nil,
                windForce = istable(SF.Wind) and round(call(SF.Wind.GetForce), 1) or nil,
                windYaw = istable(SF.Wind) and round(call(SF.Wind.GetYaw)) or nil,
            }
        end
        local sky = skyPaint()
        if IsValid(sky) and isfunction(sky.GetNetworkVars) then
            d.sky = RARELOAD.Snapshot.Plain(sky:GetNetworkVars())
        end
        return next(d) and d or nil
    end,

    restore = function(_, d, ctx)
        local done = {}
        if istable(d.stormfox) then
            if not stormFox() then
                ctx:step("warn", "environment", "StormFox2 is not installed; time and weather left as they are")
            else
                local SF, s = StormFox2, d.stormfox
                if isnumber(s.time) then call(SF.Time.Set, s.time) end
                if s.paused then call(SF.Time.Pause) else call(SF.Time.Resume) end
                if isstring(s.weather) then call(SF.Weather.Set, s.weather, s.percent or 1, 0) end
                if isnumber(s.temp) and istable(SF.Temperature) then call(SF.Temperature.Set, s.temp, 0) end
                if istable(SF.Wind) then
                    if isnumber(s.windForce) then call(SF.Wind.SetForce, s.windForce, 0) end
                    if isnumber(s.windYaw) then call(SF.Wind.SetYaw, s.windYaw, 0) end
                end
                done[#done + 1] = "StormFox2"
            end
        end
        local sky = skyPaint()
        if istable(d.sky) and IsValid(sky) and isfunction(sky.RestoreNetworkVars) then
            pcall(sky.RestoreNetworkVars, sky, RARELOAD.Snapshot.Revive(d.sky))
            done[#done + 1] = "sky"
        end
        if #done > 0 then ctx:result("ok", "environment", table.concat(done, ", ")) end
    end,

    summary = function(d)
        local s = istable(d.stormfox) and d.stormfox
        if s and s.time then
            return string.format("%02d:%02d, %s", math.floor(s.time / 60), s.time % 60, tostring(s.weather))
        end
        return d.sky and "sky" or "nothing"
    end,
})

-- World settings (C11) --------------------------------------------------------------------------------

local WORLD_CONVARS = { "sv_gravity", "phys_timescale", "ai_disabled", "ai_ignoreplayers", "ai_keepragdolls",
    "host_timescale" }

RARELOAD.Module({
    id = "worldSettings",
    phase = "world",
    skipOnDeath = true,
    setting = "keepWorldSettings",
    privSave = "rareload_save_scene",
    privRestore = "rareload_restore_scene",

    save = function()
        local d = {}
        for _, name in ipairs(WORLD_CONVARS) do
            local cv = GetConVar(name)
            if cv then d[name] = cv:GetString() end
        end
        return d
    end,

    restore = function(_, d, ctx)
        local changed = {}
        for _, name in ipairs(WORLD_CONVARS) do
            local cv, value = GetConVar(name), d[name]
            -- host_timescale only works with cheats on.
            local allowed = name ~= "host_timescale" or GetConVar("sv_cheats"):GetBool()
            if cv and value ~= nil and tostring(value) ~= cv:GetString() and allowed then
                RunConsoleCommand(name, tostring(value))
                changed[#changed + 1] = name .. " " .. tostring(value)
            end
        end
        if #changed > 0 then ctx:result("ok", "worldSettings", table.concat(changed, ", ")) end
    end,

    summary = function(d) return "gravity " .. tostring(d.sv_gravity) .. ", physics " .. tostring(d.phys_timescale) end,
})
