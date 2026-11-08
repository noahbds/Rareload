-- Who owns an entity, as a SteamID6. Sandbox's spawn hooks record the
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

local function toSid64(value)
    if isentity(value) then
        return IsValid(value) and value:IsPlayer() and value:SteamID64() or nil
    end
    if isstring(value) then
        if value:match("^7656119%d+$") then return value end
        if value:match("^STEAM_%d:%d:%d+$") then return util.SteamIDTo64(value) end
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
-- Weapons spawned from the spawn menu, and weapons a player drops, are theirs while on the ground (C5).
hook.Add("PlayerSpawnedSWEP", "Rareload.Ownership", record)
hook.Add("PlayerDroppedWeapon", "Rareload.Ownership", record)

-- Reverse indexes of every player's cleanup list and the undo table, built once per scan (L19).
-- GMod keys both by the player's UniqueID and keeps them across a reconnect, when an undo entry's
-- Owner is no longer a valid player: the key names the player then.
local function buildLists()
    local owners, byUid = {}, {}
    for _, ply in player.Iterator() do byUid[tostring(ply:UniqueID())] = ply:SteamID64() end
    for uid, types in pairs(cleanup.GetList() or {}) do
        local sid = byUid[tostring(uid)]
        for _, list in pairs(sid and types or {}) do
            for _, ent in pairs(list) do
                if IsValid(ent) and not owners[ent] then owners[ent] = sid end
            end
        end
    end
    for uid, entries in pairs(undo.GetTable() or {}) do
        for _, entry in pairs(entries) do
            local sid = istable(entry) and (toSid64(entry.Owner) or byUid[tostring(uid)])
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
-- Every save asks this for every entity on the map, so the entity's table is read directly: `ent.x`
-- goes through the Entity metatable's __index, which is slow enough to dominate a save.
local ENTITY = FindMetaTable("Entity")

local function ownerOf(ent, lists)
    local sid = recorded[ent]
    if sid then return sid end
    local cppi = ENTITY.CPPIGetOwner -- prop protection addons add it to the metatable
    if cppi then
        local ok, owner = pcall(cppi, ent)
        sid = ok and toSid64(owner)
        if sid then return sid end
    end
    if lists[ent] then return lists[ent] end
    local tab = ent:GetTable()
    if not tab then return nil end
    sid = toSid64(tab.m_PlayerCreator) -- what Sandbox's GetCreator returns
    if sid then return sid end
    for _, field in ipairs(FIELDS) do
        local value = tab[field]
        if value ~= nil then
            sid = toSid64(value)
            if sid then return sid end
        end
    end
end

function Ownership.OwnerOf(ent)
    return ownerOf(ent, buildLists())
end

-- OwnerOf for many entities in one scan: the cleanup and undo lists are read once.
function Ownership.Resolver()
    local lists = buildLists()
    return function(ent) return ownerOf(ent, lists) end
end

-- Every entity the player owns, except players, map-created entities, weapons someone holds (weapons
-- on the ground are objects like any other), and objects left out of saves: marked from the context
-- menu or of a blocked class (D1). Rareload never saves, removes or cleans those up.
function Ownership.Owned(ply)
    local sid, lists, out = ply:SteamID64(), buildLists(), {}
    for _, ent in ents.Iterator() do
        -- Cheapest tests first: most entities on a map were created by it.
        if not ent:CreatedByMap() and not ent:IsPlayer() and ownerOf(ent, lists) == sid
            and not (ent:IsWeapon() and IsValid(ent:GetOwner()))
            and not RARELOAD.Exclude.Is(ent) and not RARELOAD.Blocked.Has(ent:GetClass()) then
            out[#out + 1] = ent
        end
    end
    return out
end
