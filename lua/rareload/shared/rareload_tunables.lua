RARELOAD = RARELOAD or {}

RARELOAD.TunableDefs = {
    -- ── Anti-Stuck (server) ──────────────────────────────────────────────────
    {
        key = "anti_stuck_max_attempts", label = "Max Unstuck Attempts", category = "Anti-Stuck",
        type = "int", min = 1, max = 100, default = 35,
        desc = "How many times to try repositioning a stuck player.",
        apply = function(v)
            if SERVER and RARELOAD.AntiStuck and RARELOAD.AntiStuck.CONFIG then
                RARELOAD.AntiStuck.CONFIG.MAX_UNSTUCK_ATTEMPTS = v
            end
        end,
    },
    {
        key = "anti_stuck_max_search_time", label = "Max Search Time", category = "Anti-Stuck",
        type = "float", min = 0.5, max = 5, decimals = 1, default = 1.5, suffix = "s",
        desc = "Time budget for the unstuck search.",
        apply = function(v)
            if SERVER and RARELOAD.AntiStuck and RARELOAD.AntiStuck.CONFIG then
                RARELOAD.AntiStuck.CONFIG.MAX_SEARCH_TIME = v
            end
        end,
    },
    {
        key = "anti_stuck_safe_distance", label = "Safe Distance", category = "Anti-Stuck",
        type = "int", min = 8, max = 256, default = 48, suffix = "u",
        desc = "Minimum clearance considered safe when repositioning.",
        apply = function(v)
            if SERVER and RARELOAD.AntiStuck and RARELOAD.AntiStuck.CONFIG then
                RARELOAD.AntiStuck.CONFIG.SAFE_DISTANCE = v
            end
        end,
    },
    {
        key = "anti_stuck_horizontal_range", label = "Horizontal Search Range", category = "Anti-Stuck",
        type = "int", min = 256, max = 4096, default = 1536, suffix = "u",
        desc = "How far horizontally to search for a free spot.",
        apply = function(v)
            if SERVER and RARELOAD.AntiStuck and RARELOAD.AntiStuck.CONFIG then
                RARELOAD.AntiStuck.CONFIG.HORIZONTAL_SEARCH_RANGE = v
            end
        end,
    },
    {
        key = "anti_stuck_max_distance", label = "Max Reposition Distance", category = "Anti-Stuck",
        type = "int", min = 200, max = 5000, default = 1200, suffix = "u",
        desc = "Maximum distance a player can be moved to get unstuck.",
        apply = function(v)
            if SERVER and RARELOAD.AntiStuck and RARELOAD.AntiStuck.CONFIG then
                RARELOAD.AntiStuck.CONFIG.MAX_DISTANCE = v
            end
        end,
    },

    -- ── Saved Entity Display (client) ────────────────────────────────────────
    {
        key = "sed_max_draw_per_frame", label = "Max Panels Per Frame", category = "Saved Display",
        type = "int", min = 1, max = 32, default = 16,
        desc = "Upper bound on saved-entity panels rendered each frame.",
        apply = function(v) if CLIENT and SED then SED.MAX_DRAW_PER_FRAME = v end end,
    },
    {
        key = "sed_base_draw_distance", label = "Panel Draw Distance", category = "Saved Display",
        type = "int", min = 200, max = 3000, default = 500, suffix = "u",
        desc = "Distance at which normal saved-entity panels start drawing.",
        apply = function(v)
            if CLIENT and SED then
                SED.BASE_DRAW_DISTANCE = v
                SED.DRAW_DISTANCE_SQR = v * v
            end
        end,
    },
    {
        key = "sed_large_draw_distance", label = "Large Panel Draw Distance", category = "Saved Display",
        type = "int", min = 500, max = 6000, default = 2500, suffix = "u",
        desc = "Draw distance for large/massive entities.",
        apply = function(v) if CLIENT and SED then SED.LARGE_ENTITY_DRAW_DISTANCE = v end end,
    },
}

RARELOAD.Tunables = RARELOAD.Tunables or {}

local defByKey = {}
for _, def in ipairs(RARELOAD.TunableDefs) do
    defByKey[def.key] = def
    if RARELOAD.Tunables[def.key] == nil then
        RARELOAD.Tunables[def.key] = def.default
    end
end
RARELOAD.TunableDefByKey = defByKey

local function clampValue(def, value)
    if def.type == "bool" then
        return value == true or value == 1 or value == "1" or value == "true"
    end
    local n = tonumber(value) or def.default
    if def.type == "int" then n = math.Round(n) end
    if def.min then n = math.max(n, def.min) end
    if def.max then n = math.min(n, def.max) end
    return n
end

function RARELOAD.GetTunable(key)
    local v = RARELOAD.Tunables[key]
    if v ~= nil then return v end
    local def = defByKey[key]
    return def and def.default or nil
end

function RARELOAD.ApplyTunable(key)
    local def = defByKey[key]
    if def and def.apply then
        local ok, err = pcall(def.apply, RARELOAD.GetTunable(key))
        if not ok then
            ErrorNoHalt("[RARELOAD] Tunable apply failed for " .. key .. ": " .. tostring(err) .. "\n")
        end
    end
end

function RARELOAD.ApplyAllTunables()
    for _, def in ipairs(RARELOAD.TunableDefs) do
        RARELOAD.ApplyTunable(def.key)
    end
end

local CONFIG_PATH = "rareload/addon_config.json"

if SERVER then
    util.AddNetworkString("RareloadSyncTunables")
    util.AddNetworkString("RareloadUpdateTunable")

    local function SaveTunables()
        if not file.Exists("rareload", "DATA") then file.CreateDir("rareload") end
        file.Write(CONFIG_PATH, util.TableToJSON(RARELOAD.Tunables, true))
    end
    RARELOAD.SaveTunables = SaveTunables

    local function LoadTunables()
        if not file.Exists(CONFIG_PATH, "DATA") then return end
        local ok, data = pcall(util.JSONToTable, file.Read(CONFIG_PATH, "DATA") or "")
        if ok and istable(data) then
            for _, def in ipairs(RARELOAD.TunableDefs) do
                if data[def.key] ~= nil then
                    RARELOAD.Tunables[def.key] = clampValue(def, data[def.key])
                end
            end
        end
    end

    local function BroadcastTunables(ply)
        net.Start("RareloadSyncTunables")
        net.WriteTable(RARELOAD.Tunables)
        if IsValid(ply) then net.Send(ply) else net.Broadcast() end
    end
    RARELOAD.BroadcastTunables = BroadcastTunables

    LoadTunables()
    -- AntiStuck and other systems include after this file; apply once everything is loaded.
    timer.Simple(0, function() RARELOAD.ApplyAllTunables() end)

    hook.Add("PlayerInitialSpawn", "RareloadSyncTunablesOnJoin", function(ply)
        timer.Simple(0.5, function()
            if IsValid(ply) then BroadcastTunables(ply) end
        end)
    end)

    net.Receive("RareloadUpdateTunable", function(_, ply)
        if not IsValid(ply) then return end
        if RARELOAD.CheckPermission and not RARELOAD.CheckPermission(ply, "ADMIN_PANEL") then
            print("[RARELOAD] " .. ply:Nick() .. " tried to change a parameter without permission.")
            return
        end

        local key = net.ReadString()
        local def = defByKey[key]
        local raw
        if def and def.type == "bool" then raw = net.ReadBool() else raw = net.ReadFloat() end
        if not def then return end

        RARELOAD.Tunables[key] = clampValue(def, raw)
        RARELOAD.ApplyTunable(key)
        SaveTunables()
        BroadcastTunables()
    end)
else
    net.Receive("RareloadSyncTunables", function()
        local data = net.ReadTable()
        if istable(data) then
            for _, def in ipairs(RARELOAD.TunableDefs) do
                if data[def.key] ~= nil then
                    RARELOAD.Tunables[def.key] = data[def.key]
                end
            end
        end
        RARELOAD.ApplyAllTunables()
    end)

    function RARELOAD.SendTunableUpdate(key, value)
        local def = defByKey[key]
        if not def then return end
        net.Start("RareloadUpdateTunable")
        net.WriteString(key)
        if def.type == "bool" then
            net.WriteBool(value and true or false)
        else
            net.WriteFloat(tonumber(value) or def.default)
        end
        net.SendToServer()
    end
end

return RARELOAD.Tunables
