-- The client's one store of what the server sent. UI code reads from here and
-- listens to RareloadStateChanged(what, key) instead of listening to the network.

RARELOAD.State = RARELOAD.State or {
    history = { rows = {}, reload = {} }, -- own timeline
    objects = {},                         -- entry id -> saved objects of that entry
    entryData = {},                       -- entry id -> its light player modules (timeline preview)
    saves = {},                           -- SteamID64 -> { nick, data, objects }: world display feed
    savesRev = 0,                         -- bumped on every feed change, for dirty checks (L28)
    details = {},                         -- DetailKey -> full saved object, asked for by the world display
    antistuck = {},                       -- anti-stuck methods in order, for the server page
}
local State = RARELOAD.State
-- Every topic exists from the start (an empty value until the server sends it), so readers never
-- guard against nil; `or` keeps what a dev reload finds.
State.details, State.antistuck = State.details or {}, State.antistuck or {}
State.entryData = State.entryData or {}
State.players = State.players or {}         -- admin: players with saves on this map
State.snapshots = State.snapshots or {}     -- admin: server snapshots
State.usage = State.usage or {}             -- admin: storage use, as lines
State.blocked = State.blocked or {}         -- admin: classes never saved
State.checkpoints = State.checkpoints or {} -- own checkpoints, each with .vec (D7)
State.death = State.death or {}             -- own last death: { id = death save, pos } (D4)

local function changed(what, key)
    hook.Run("RareloadStateChanged", what, key)
end

local asText = RARELOAD.Util.AsText

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

RARELOAD.Net.On("history", function(payload)
    local shown = RARELOAD.Timeline and RARELOAD.Timeline.target
    if payload.target ~= shown then return end
    for _, row in ipairs(payload.rows or {}) do row.note = asText(row.note) end
    State.history = {
        rows = payload.rows or {}, reload = payload.reload or {}, undo = payload.undo == true, loaded = true,
    }
    changed("history")
end)

RARELOAD.Net.On("history.players", function(payload)
    State.players = istable(payload.list) and payload.list or {}
    table.sort(State.players, function(a, b)
        if a.online ~= b.online then return a.online end
        return string.lower(a.nick or "") < string.lower(b.nick or "")
    end)
    changed("players")
end)

RARELOAD.Net.On("snapshots", function(payload)
    State.snapshots = istable(payload.list) and payload.list or {}
    changed("snapshots")
end)

RARELOAD.Net.On("data.usage", function(payload)
    State.usage = istable(payload.lines) and payload.lines or {}
    changed("usage")
end)

RARELOAD.Net.On("history.objects", function(payload)
    State.objects[payload.id] = payload.objects or {}
    State.entryData[payload.id] = payload.data
    RARELOAD.UI.LabelObjects(State.objects[payload.id])
    forgetDetails(State.DetailKey(nil, payload.id, "")) -- the save's objects may have been edited
    changed("objects", payload.id)
end)

-- The inventory manager's targets: "global", or a save number.
State.inventory = State.inventory or {}

function State.InventoryKey(save) return save or "global" end

RARELOAD.Net.On("inventory", function(payload)
    local key = State.InventoryKey(payload.save)
    State.inventory[key] = payload
    changed("inventory", key)
end)

RARELOAD.Net.On("object.def", function(payload)
    changed("def", payload)
end)

RARELOAD.Net.On("saves", function(payload)
    if payload.save then
        payload.save.nick = asText(payload.save.nick)
        RARELOAD.UI.LabelObjects(payload.save.objects or {})
    end
    State.saves[payload.sid] = payload.save
    State.savesRev = State.savesRev + 1
    forgetDetails(State.DetailKey(payload.sid, nil, "")) -- that player's respawn point changed
    changed("saves", payload.sid)
end)

RARELOAD.Net.On("object.detail", function(payload)
    local key = State.DetailKey(payload.sid, payload.entryId, payload.objectId)
    State.details[key] = payload.detail
    changed("detail", key)
end)

RARELOAD.Net.On("antistuck", function(payload)
    State.antistuck = payload.methods or {}
    changed("antistuck")
end)

RARELOAD.Net.On("blocked", function(payload)
    State.blocked = istable(payload.classes) and payload.classes or {}
    changed("blocked")
end)

RARELOAD.Net.On("checkpoints", function(payload)
    State.checkpoints = istable(payload.list) and payload.list or {}
    for _, c in ipairs(State.checkpoints) do c.vec = RARELOAD.Util.ToVector(c.pos) end
    changed("checkpoints")
end)

RARELOAD.Net.On("death", function(payload)
    State.death = { id = tonumber(payload.id), pos = RARELOAD.Util.ToVector(payload.pos) }
    changed("death")
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
