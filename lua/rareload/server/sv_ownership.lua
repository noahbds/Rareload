-- Who owns an entity, as a SteamID64 (REWRITE_PLAN.md §14.3, G65). Sandbox's spawn hooks record the
-- owner for the entity's lifetime, so ownership survives a reconnect. Other sources are checked as
-- fallbacks: GetCreator, CPPI, fields vehicle bases use, and the player cleanup and undo lists.

RARELOAD.Ownership = RARELOAD.Ownership or {}
local Ownership = RARELOAD.Ownership

-- Entity -> SteamID64. Kept off the entity: the duplicator tools copy an entity's Lua table, so a dupe
-- would inherit its original's owner.
Ownership.recorded = Ownership.recorded or setmetatable({}, { __mode = "k" })
local recorded = Ownership.recorded

-- Fields some vehicle bases and prop protections use to store the spawning player.
local FIELDS = { "dOwnerEntLFS", "LFSOwner", "SpawnerPlayer", "OwnerEnt", "SPPOwner", "Founder" }

local function toSid64(v)
    if isentity(v) then
        return IsValid(v) and v:IsPlayer() and v:SteamID64() or nil
    end
    if isstring(v) then
        if v:match("^7656119%d+$") then return v end
        if v:match("^STEAM_%d:%d:%d+$") then return util.SteamIDTo64(v) end
    end
end

function Ownership.Set(ent, ply)
    recorded[ent] = ply:SteamID64()
    if ent.SetCreator then ent:SetCreator(ply) end
    if ent.CPPISetOwner then pcall(ent.CPPISetOwner, ent, ply) end   -- prop protection addons
end

local function record(ply, ent)
    if IsValid(ply) and IsValid(ent) then recorded[ent] = ply:SteamID64() end
end

-- The owner Rareload recorded (a spawn hook or a restore), without the fallbacks.
function Ownership.Recorded(ent)
    return recorded[ent]
end

hook.Add("PlayerSpawnedProp", "Rareload.Ownership", function(ply, _, ent) record(ply, ent) end)
hook.Add("PlayerSpawnedRagdoll", "Rareload.Ownership", function(ply, _, ent) record(ply, ent) end)
hook.Add("PlayerSpawnedEffect", "Rareload.Ownership", function(ply, _, ent) record(ply, ent) end)
hook.Add("PlayerSpawnedSENT", "Rareload.Ownership", record)
hook.Add("PlayerSpawnedNPC", "Rareload.Ownership", record)
hook.Add("PlayerSpawnedVehicle", "Rareload.Ownership", record)

-- Reverse indexes of every player's cleanup list and the undo table, built once per scan (L19).
local function buildLists()
    local owners = {}
    for _, ply in player.Iterator() do
        for _, list in pairs(ply.CleanupList or {}) do
            for _, ent in pairs(list) do
                if IsValid(ent) and not owners[ent] then owners[ent] = ply:SteamID64() end
            end
        end
    end
    for _, entries in pairs(undo.GetTable() or {}) do
        for _, entry in pairs(entries) do
            local sid = istable(entry) and toSid64(entry.Owner)
            if sid then
                for _, ent in pairs(entry.Entities or {}) do
                    if IsValid(ent) and not owners[ent] then owners[ent] = sid end
                end
            end
        end
    end
    return owners
end

-- Sources that live on the entity table (GetCreator, vehicle base fields) come last: the duplicator
-- tools copy that table, so a player's dupe of someone else's entity still names the original's owner.
local function ownerOf(ent, lists)
    if recorded[ent] then return recorded[ent] end
    local sid
    if ent.CPPIGetOwner then
        local ok, owner = pcall(ent.CPPIGetOwner, ent)
        sid = ok and toSid64(owner)
        if sid then return sid end
    end
    if lists[ent] then return lists[ent] end
    sid = ent.GetCreator and toSid64(ent:GetCreator())
    if sid then return sid end
    for _, field in ipairs(FIELDS) do
        sid = toSid64(ent[field])
        if sid then return sid end
    end
end

function Ownership.OwnerOf(ent)
    return ownerOf(ent, buildLists())
end

-- Every entity the player owns, except players, weapons and map-created entities.
function Ownership.Owned(ply)
    local sid, lists, out = ply:SteamID64(), buildLists(), {}
    for _, ent in ents.Iterator() do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsWeapon() and not ent:CreatedByMap()
            and ownerOf(ent, lists) == sid then
            out[#out + 1] = ent
        end
    end
    return out
end
