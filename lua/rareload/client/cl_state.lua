-- The client's one store of what the server sent (REWRITE_PLAN.md §21.1). UI code reads from here and
-- listens to RareloadStateChanged(what, key) instead of listening to the network.

RARELOAD.State = RARELOAD.State or {
    history = { rows = {}, reload = {} }, -- own timeline
    objects = {},                         -- entry id -> saved objects of that entry
    saves = {},                           -- SteamID64 -> { nick, data, objects }: world display feed
    savesRev = 0,                         -- bumped on every feed change, for dirty checks (L28)
    details = {},                         -- DetailKey -> full saved object, asked for by the world display
    antistuck = {},                       -- anti-stuck methods in order, for the server page
}
local State = RARELOAD.State
State.details, State.antistuck = State.details or {}, State.antistuck or {} -- after a dev reload

local function changed(what, key)
    hook.Run("RareloadStateChanged", what, key)
end

-- Text someone typed, as text: GMod's JSON reads a string like "[1 2 3]" or "{1 2 3}" back as a
-- Vector or an Angle, so a note or a player name of that shape arrives as one.
local function asText(v)
    if isvector(v) then return string.format("[%g %g %g]", v.x, v.y, v.z) end
    if isangle(v) then return string.format("{%g %g %g}", v.p, v.y, v.r) end
    if v ~= nil and not isstring(v) then return tostring(v) end
    return v
end

-- Details are kept per player, save and object: the same object differs between two saves, and a
-- player's respawn point (the world display feed, no save number) changes with every save.
function State.DetailKey(sid, entryId, objectId)
    return tostring(sid or "") .. "|" .. tostring(entryId or "") .. "|" .. tostring(objectId)
end

local function forgetDetails(prefix)
    for key in pairs(State.details) do
        if string.StartsWith(key, prefix) then State.details[key] = nil end
    end
end

RARELOAD.Net.On("history", function(p)
    for _, row in ipairs(p.rows or {}) do row.note = asText(row.note) end
    State.history = { rows = p.rows or {}, reload = p.reload or {}, undo = p.undo == true, loaded = true }
    changed("history")
end)

RARELOAD.Net.On("history.objects", function(p)
    State.objects[p.id] = p.objects or {}
    forgetDetails(State.DetailKey(nil, p.id, "")) -- the save's objects may have been edited
    changed("objects", p.id)
end)

RARELOAD.Net.On("object.def", function(p)
    changed("def", p)
end)

RARELOAD.Net.On("saves", function(p)
    if p.save then p.save.nick = asText(p.save.nick) end
    State.saves[p.sid] = p.save
    State.savesRev = State.savesRev + 1
    forgetDetails(State.DetailKey(p.sid, nil, "")) -- that player's respawn point changed
    changed("saves", p.sid)
end)

RARELOAD.Net.On("object.detail", function(p)
    local key = State.DetailKey(p.sid, p.entryId, p.objectId)
    State.details[key] = p.detail
    changed("detail", key)
end)

RARELOAD.Net.On("antistuck", function(p)
    State.antistuck = p.methods or {}
    changed("antistuck")
end)

RARELOAD.Net.On("autosave", function()
    State.lastAutosave = CurTime()
    changed("autosave")
end)

-- Row lookup by id in the own timeline.
function State.Row(id)
    for _, row in ipairs(State.history.rows) do
        if row.id == id then return row end
    end
end

function State.ActiveRow()
    for _, row in ipairs(State.history.rows) do
        if row.active then return row end
    end
end
