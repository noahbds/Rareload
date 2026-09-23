-- The client's one store of what the server sent (REWRITE_PLAN.md §21.1). UI code reads from here and
-- listens to RareloadStateChanged(what, key) instead of listening to the network.

RARELOAD.State = RARELOAD.State or {
    history = { rows = {}, reload = {} },   -- own timeline
    objects = {},                           -- entry id -> saved objects of that entry
    saves = {},                             -- SteamID64 -> { nick, data, objects }: world display feed
    savesRev = 0,                           -- bumped on every feed change, for dirty checks (L28)
}
local State = RARELOAD.State

local function changed(what, key)
    hook.Run("RareloadStateChanged", what, key)
end

RARELOAD.Net.On("history", function(p)
    State.history = { rows = p.rows or {}, reload = p.reload or {} }
    changed("history")
end)

RARELOAD.Net.On("history.objects", function(p)
    State.objects[p.id] = p.objects or {}
    changed("objects", p.id)
end)

RARELOAD.Net.On("object.def", function(p)
    changed("def", p)
end)

RARELOAD.Net.On("saves", function(p)
    State.saves[p.sid] = p.save
    State.savesRev = State.savesRev + 1
    changed("saves", p.sid)
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
