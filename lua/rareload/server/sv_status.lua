-- What Rareload found on this server: printed once the map has loaded, and by `rareload status`.
-- The supported addons it detected, whether the gamemode is supported, the saves on this map and how
-- much disk they use, permissions, logging and anything an admin should look at.

RARELOAD.Status = RARELOAD.Status or {}
local Status = RARELOAD.Status

local function stored(class) return scripted_ents.GetStored(class) ~= nil end
local function swep(class) return weapons.GetStored(class) ~= nil end

-- { name, what Rareload does with it, detect() }. Checked after every addon has loaded.
Status.INTEGRATIONS = {
    { "ARC9", "weapon attachments", function() return istable(ARC9) end },
    { "ArcCW", "weapon attachments", function() return istable(ArcCW) end },
    { "TFA Base", "weapon attachments", function() return istable(TFA) end },
    { "MW Base", "weapon attachments", function() return istable(MW_ATTS) or swep("mg_base") end },
    { "LVS", "vehicles", function() return stored("lvs_base") end },
    { "Simfphys", "vehicles", function() return stored("gmod_sent_vehicle_fphysics_base") end },
    { "Glide", "vehicles", function() return istable(Glide) or stored("base_glide") end },
    { "LFS", "vehicles", function() return stored("lunasflightschool_basescript") end },
    { "WAC", "vehicles", function() return stored("wac_hc_base") end },
    { "Wiremod", "gate memory", function() return istable(WireLib) end },
    { "PAC3", "outfits", function() return istable(pace) end },
    { "StormFox2", "time and weather", function() return istable(StormFox2) end },
    { "Enhanced PlayerModel Selector", "model warning",
        function() return ConVarExists("sv_playermodel_selector_force") end },
    { "Prop protection (CPPI)", "object owners", function() return istable(CPPI) end },
    { "CAMI admin mod", "permissions", function() return istable(CAMI) end },
}

function Status.Detected()
    local out = {}
    for _, i in ipairs(Status.INTEGRATIONS) do
        local ok, present = pcall(i[3])
        if ok and present then out[#out + 1] = i[1] .. " (" .. i[2] .. ")" end
    end
    return out
end

local size = RARELOAD.Util.FormatBytes

-- The status as lines of text.
function Status.Lines()
    local Store = RARELOAD.Store
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end

    add("Rareload %s on %s (%s), gamemode %s: %s", RARELOAD.version, game.GetMap(),
        game.SinglePlayer() and "singleplayer" or "multiplayer", engine.ActiveGamemode(),
        RARELOAD.Pipeline.Enabled() and "supported" or "NOT SUPPORTED - turn on enableInAllGamemodes to use it")

    local detected = Status.Detected()
    add("  Works with: %s", #detected > 0 and table.concat(detected, ", ") or "no supported addons found")

    local dir = Store.MapDir()
    local docs, docBytes = Store.Usage(dir)
    local blobs, blobBytes = Store.Usage(dir .. "/_blobs")
    local players = Store.PlayersWithSaves()
    add("  Saves on this map: %d players, %s (%d world files)", players, size(docBytes + blobBytes), blobs)
    add("  Navmesh: %s", navmesh.IsLoaded() and "loaded" or "missing (the anti-stuck navmesh method can't run)")

    local changed, locked = 0, 0
    for key, settingDef in pairs(RARELOAD.Settings) do
        local cv = settingDef.cv
        if settingDef.scope ~= "client" and cv:GetString() ~= cv:GetDefault() then changed = changed + 1 end
        if RARELOAD.IsLocked(key) then locked = locked + 1 end
    end
    add("  Settings: %d changed from the default, %d player settings locked", changed, locked)
    add("  Permissions: %s", istable(CAMI) and "from the admin mod (CAMI)" or "Rareload's own tiers ('rareload perms')")
    add("  Logging: %s%s, debug %s", RARELOAD.Get(nil, "logLevel"),
        RARELOAD.Get(nil, "logToFile") and (", to data/rareload/logs (kept " .. RARELOAD.Get(nil, "logKeepDays")
        .. " days)") or "", RARELOAD.Get(nil, "debug") and "on" or "off")
    local counts = RARELOAD.LogRing.counts
    add("  Since start: %d errors, %d warnings ('rareload log errors' to see them)", counts.error, counts.warn)
    return lines
end

-- Once the map has loaded: old log files go, and the status is printed.
hook.Add("InitPostEntity", "Rareload.Status", function()
    local removed = RARELOAD.Store.PruneLogs(RARELOAD.Get(nil, "logKeepDays"))
    if removed > 0 then RARELOAD.Log("storage"):verbose("removed %d old log files", removed) end
    if not RARELOAD.LogWants("info") then return end
    for i, line in ipairs(Status.Lines()) do
        MsgC(Color(120, 200, 255), "[Rareload] ", i == 1 and Color(255, 255, 255) or Color(200, 200, 200), line .. "\n")
    end
end)

-- A player who joins: how many saves they have here (debug level).
hook.Add("RareloadClientReady", "Rareload.Status", function(ply)
    local doc = RARELOAD.History.Doc(ply)
    local count = doc and #doc.entries or 0
    RARELOAD.Log("player", ply):verbose("%s joined: %d saves on this map%s", ply:Nick(), count,
        doc and doc.activeId and (", respawn point No. " .. doc.activeId) or "")
end)
