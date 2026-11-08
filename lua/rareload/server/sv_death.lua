-- Death recovery (5.4 plan, D4). With saveOnDeath on, dying makes a save (reason "death") from just
-- before the death: the weapons are still held, and the health is the one before the fatal hit. It
-- doesn't become the respawn point. The player sees a marker where they died, can go back with the
-- timeline or `rareload death`, and, with deathChoice on, chooses where to respawn.

RARELOAD.Death = RARELOAD.Death or {}
local Death = RARELOAD.Death

local beforeHit = setmetatable({}, { __mode = "k" }) -- ply -> { hp, armor } before the last damage

-- What Rareload remembers about a player between their death and their respawn, kept off the
-- player entity: pending (died, not told yet), told (death save id told about), spot (where they
-- died), backAt (when they last respawned there), choice (respawn choice), died and cleaned (for the
-- spawn restore, sv_spawn.lua).
local states = setmetatable({}, { __mode = "k" })

function Death.State(ply)
    local st = states[ply]
    if not st then
        st = {}
        states[ply] = st
    end
    return st
end

hook.Add("EntityTakeDamage", "Rareload.Death", function(ent)
    if ent:IsPlayer() and ent:Alive() then beforeHit[ent] = { hp = ent:Health(), armor = ent:Armor() } end
end)

-- The player's death save on this map, or nil.
function Death.Entry(ply)
    local doc = RARELOAD.History.Doc(ply)
    return doc and doc.deathId and RARELOAD.History.Get(ply, doc.deathId) or nil
end

local function tell(ply)
    local entry = Death.Entry(ply)
    local pos = entry and entry.data.transform and entry.data.transform.pos
    RARELOAD.Net.Push(ply, "death", { id = entry and entry.id, pos = pos })
end

-- Before the gamemode drops the weapon and makes the ragdoll.
hook.Add("DoPlayerDeath", "Rareload.Death", function(ply)
    if not RARELOAD.Pipeline.Enabled() or not RARELOAD.Get(ply, "enabled") then return end
    if not RARELOAD.Get(ply, "saveOnDeath") or not RARELOAD.Can(ply, "rareload_save") then return end
    local ok, result = RARELOAD.Pipeline.Save(ply, {
        reason = "death", silent = true, keepActive = true, death = true,
        deathHealth = beforeHit[ply] or { hp = 1, armor = ply:Armor() },
    })
    if not ok then return end
    -- Nothing changed since the respawn point: that save is the death save (one write either way).
    if result == "unchanged" then
        local active = RARELOAD.History.Active(ply)
        if not (active and RARELOAD.History.SetDeath(ply, active.id)) then return end
    end
    tell(ply)
end)

-- After the respawn: what they can do, and the choice of where to respawn when they want one.
hook.Add("PlayerSpawn", "Rareload.Death", function(ply)
    local st = Death.State(ply)
    local died = st.pending
    st.pending = nil
    local entry = died and Death.Entry(ply)
    if entry and st.told ~= entry.id then
        st.told = entry.id
        RARELOAD.Toast(ply, "toast.death_saved", { entry.id })
    end
end)

-- Where the player died, for "Where I died": the save is restored as usual, at that spot. Not
-- kept when they died again within a few seconds of respawning there (a deadly spot), so "always"
-- can't loop.
local DEADLY = 5

hook.Add("PostPlayerDeath", "Rareload.Death", function(ply)
    local st = Death.State(ply)
    st.pending = true
    local back = st.backAt and CurTime() - st.backAt < DEADLY
    st.spot = not back and {
        pos = ply:GetPos(), ang = ply:EyeAngles(), crouched = ply:Crouching(),
    } or nil
    -- The marker moves to this death, with or without a death save.
    if RARELOAD.Get(ply, "enabled") then
        local entry = Death.Entry(ply)
        RARELOAD.Net.Push(ply, "death", { id = entry and entry.id, pos = RARELOAD.Util.Vec(ply:GetPos()) })
    end
    if not RARELOAD.Can(ply, "rareload_restore") then return end
    -- "Respawn after dying" (also set by "Always choose this"): the same place every time, without
    -- asking; "map" is the old "Normal respawn after dying". "death" with no spot: the respawn point.
    local always = RARELOAD.Get(ply, "deathChoiceAlways")
    if always ~= "ask" then
        st.choice = (always ~= "death" or st.spot) and always or "save"
        return
    end
    if not RARELOAD.Get(ply, "deathChoice") then return end
    RARELOAD.Net.Push(ply, "death.choice", { death = st.spot ~= nil })
end)

-- The spot to respawn at for "where I died" (used once), or nil.
function Death.TakeSpot(ply)
    local st = Death.State(ply)
    local spot = st.spot
    st.spot = nil
    if not spot then return nil end
    st.backAt = CurTime()
    return { pos = spot.pos, ang = Angle(spot.ang.p, spot.ang.y, 0), crouched = spot.crouched }
end

-- Restores the death save. Returns true, or false (the player was told why).
function Death.Back(ply)
    local entry = Death.Entry(ply)
    if not entry then
        RARELOAD.Toast(ply, "toast.death_none", nil, "error")
        return false
    end
    if not ply:Alive() then
        RARELOAD.Toast(ply, "toast.restore_dead", nil, "error")
        return false
    end
    if not RARELOAD.History.Restore(ply, entry.id) then return false end
    RARELOAD.Toast(ply, "toast.restored", { entry.id }, "ok")
    RARELOAD.Net.Push(ply, "death", {}) -- the marker goes away
    return true
end

RARELOAD.Net.Handle("death.back", { priv = "rareload_restore", rate = 1, fn = function(ply) Death.Back(ply) end })

-- The respawn choice: "save" (the respawn point, as usual), "map" (the map's spawn, nothing restored)
-- or "death" (the respawn point's save, restored where they died).
local CHOICES = { save = true, map = true, death = true }
RARELOAD.Net.Handle("death.respawn", {
    priv = "rareload_restore",
    rate = 0.5,
    args = { mode = "string:8" },
    fn = function(ply, args)
        if ply:Alive() or not CHOICES[args.mode] then return end
        local st = Death.State(ply)
        if args.mode == "death" and not st.spot then return end
        st.choice = args.mode
        ply:Spawn()
    end,
})

RARELOAD.Net.Handle("death.get", { priv = "rareload_restore", rate = 0.5, fn = tell })
hook.Add("RareloadClientReady", "Rareload.Death", function(ply) tell(ply) end)
