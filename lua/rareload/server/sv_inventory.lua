-- Inventory manager: view, edit, copy, give and roll back the inventory of a save or the global
-- inventory, from the inventory window (rareload_manage_inventory) or `rareload inventory …`.
-- A target is a save number, or nil for the global inventory. Every change keeps the inventory it
-- replaced as a version, so it can be rolled back. Works with the global inventory setting off too.

RARELOAD.Inventory = RARELOAD.Inventory or {}
local Inventory = RARELOAD.Inventory

local MAX_WEAPONS = 256
local MAX_VERSIONS = 10
local PRIV = "rareload_manage_inventory"

local function emptyAmmo() return { reserve = {}, clips = {} } end
local function emptyInventory() return { weapons = {}, ammo = emptyAmmo() } end

local function isClass(text)
    return isstring(text) and #text > 0 and #text <= 96 and string.match(text, "^[%w_%-%.]+$") ~= nil
end

local function whole(value, min)
    return isnumber(value) and value == value and value ~= math.huge and value ~= -math.huge and value >= min
        and value == math.floor(value)
end

-- An ammo name as the game knows it. Accepts the ammo's ID too ("3" for Pistol), but a name wins:
-- "357" is the name of an ammo type. Unknown names are kept (the addon may be missing right now).
local function ammoName(key)
    local name = tostring(key)
    if game.GetAmmoID(name) >= 0 then return name, true end
    local id = tonumber(name)
    local byId = id and game.GetAmmoName(id)
    if byId then return byId, true end
    return name, false
end

-- Checks an inventory from the JSON editor or a file. Returns the clean inventory and a list of
-- warnings, or nil and what is wrong (shown to the player, in English like other server messages).
function Inventory.Clean(input)
    if not istable(input) then return nil, "the inventory must be a JSON object" end
    local weapons = input.weapons == nil and {} or input.weapons
    if not istable(weapons) or table.Count(weapons) ~= #weapons then
        return nil, "\"weapons\" must be a list of weapon classes"
    end
    if #weapons > MAX_WEAPONS then return nil, "more than " .. MAX_WEAPONS .. " weapons" end
    local out, seen, warnings = { weapons = {}, ammo = emptyAmmo() }, {}, {}
    for i, class in ipairs(weapons) do
        if not isClass(class) then return nil, "weapon " .. i .. " is not a weapon class" end
        if not seen[class] then
            seen[class] = true
            out.weapons[#out.weapons + 1] = class
        end
    end
    table.sort(out.weapons)

    if input.activeWeapon ~= nil then
        if not isstring(input.activeWeapon) then return nil, "\"activeWeapon\" must be a weapon class" end
        if not seen[input.activeWeapon] then return nil, "\"activeWeapon\" is not one of the weapons" end
        out.activeWeapon = input.activeWeapon
    end

    local ammo = input.ammo == nil and emptyAmmo() or input.ammo
    if not istable(ammo) then return nil, "\"ammo\" must be an object with \"reserve\" and \"clips\"" end
    local reserve, clips = ammo.reserve or {}, ammo.clips or {}
    if not istable(reserve) then return nil, "\"ammo.reserve\" must be an object of ammo name: count" end
    if not istable(clips) then return nil, "\"ammo.clips\" must be an object of weapon class: [clip1, clip2]" end
    for key, count in pairs(reserve) do
        local name, known = ammoName(key)
        if not whole(count, 0) then return nil, "reserve ammo " .. name .. " must be a whole number, 0 or more" end
        if not known then warnings[#warnings + 1] = name end
        if count > 0 then out.ammo.reserve[name] = count end
    end
    for class, clip in pairs(clips) do
        class = tostring(class)
        if not seen[class] then return nil, "clips for " .. class .. ", which is not one of the weapons" end
        if not istable(clip) or not whole(clip[1], -1) or not (clip[2] == nil or whole(clip[2], -1)) then
            return nil, "clips of " .. class .. " must be [clip1, clip2] (-1 for none)"
        end
        out.ammo.clips[class] = { clip[1], clip[2] or -1 }
    end
    -- Weapon attachments (modules/weapon_state.lua) are kept as they are; weapons no longer in the
    -- list are dropped from them.
    if input.extras ~= nil then
        if not istable(input.extras) then return nil, "\"extras\" must be an object" end
        local extras = { weapons = {}, owned = istable(input.extras.owned) and input.extras.owned or {} }
        for class, weaponExtras in pairs(istable(input.extras.weapons) and input.extras.weapons or {}) do
            if seen[tostring(class)] and istable(weaponExtras) then extras.weapons[tostring(class)] = weaponExtras end
        end
        if next(extras.weapons) or next(extras.owned) then out.extras = extras end
    end
    return out, warnings
end

-- Reading and writing a target -----------------------------------------------------------------------

-- The inventory saved in an entry's data, or nil when the save has no weapons.
local function ofEntry(data)
    if data.weapons == nil then return nil end
    return {
        weapons = istable(data.weapons) and data.weapons or {},
        activeWeapon = data.activeWeapon,
        ammo = istable(data.ammo) and data.ammo or emptyAmmo(),
        extras = istable(data.weaponState) and data.weaponState or nil,
    }
end

-- Returns the inventory of a target (nil when it has none), its versions, newest first, and whether
-- the target exists.
function Inventory.Read(ply, save)
    if not save then
        local versions = RARELOAD.Store.PData(ply, "global_inventory_versions")
        return Inventory.GlobalGet(ply), istable(versions) and versions or {}, true
    end
    local entry = RARELOAD.History.Get(ply, save)
    if not entry then return nil, {}, false end
    return ofEntry(entry.data), entry.inventoryVersions or {}, true
end

local function remember(versions, inv, reason)
    if inv then
        table.insert(versions, 1, { time = os.time(), reason = reason, data = inv })
        while #versions > MAX_VERSIONS do table.remove(versions) end
    end
    return versions
end

-- Stores `inv` (clean) in a target, keeping what it replaces as a version. `reason`: "edit", "copy",
-- "import" or "rollback". `versions`: the version list to keep (a rollback removes the one it used).
function Inventory.Write(ply, save, inv, reason, versions)
    if not save then
        local current, list = Inventory.Read(ply, nil)
        RARELOAD.Store.PData(ply, "global_inventory_versions", remember(versions or list, current, reason))
        Inventory.GlobalSet(ply, inv)
        return true
    end
    return RARELOAD.History.Update(ply, save, function(entry)
        entry.inventoryVersions = remember(versions or entry.inventoryVersions or {}, ofEntry(entry.data), reason)
        entry.data.weapons, entry.data.activeWeapon, entry.data.ammo = inv.weapons, inv.activeWeapon, inv.ammo
        entry.data.weaponState = inv.extras
    end)
end

local function targetName(save) return save and ("save " .. save) or "the global inventory" end
Inventory.TargetName = targetName -- for the console commands (sv_commands.lua)
Inventory.Empty = emptyInventory

-- Pushes a target to the inventory window.
function Inventory.Push(ply, save)
    local inv, versions, exists = Inventory.Read(ply, save)
    local list = {}
    for i, version in ipairs(versions) do
        list[i] = { time = version.time, reason = version.reason,
            weapons = #(istable(version.data) and version.data.weapons or {}) }
    end
    RARELOAD.Net.Push(ply, "inventory", {
        save = save,
        exists = exists,
        inventory = inv,
        versions = list,
        -- Whether the global inventory is what this player gets on spawn.
        globalOn = RARELOAD.Get(ply, "keepInventory") and RARELOAD.Get(ply, "globalInventory")
            and RARELOAD.Can(ply, "rareload_global_inventory"),
    }, { key = "inventory:" .. tostring(save or "global") })
end

-- Operations shared by the window and the commands. Each returns a toast key and its arguments,
-- and whether it worked.

function Inventory.SetFrom(ply, save, data, reason)
    local inv, warnings = Inventory.Clean(data)
    if not inv then return "toast.inventory.invalid", { warnings }, false end -- warnings: what is wrong
    local ok, err = Inventory.Write(ply, save, inv, reason)
    if not ok then return "toast.inventory.failed", { tostring(err) }, false end
    if #warnings > 0 then return "toast.inventory.unknown_ammo", { table.concat(warnings, ", ") }, true end
    return "toast.inventory.saved", nil, true
end

function Inventory.Copy(ply, save, from)
    if save == from then return "toast.inventory.same", nil, false end
    local inv, _, exists = Inventory.Read(ply, from)
    if not exists then return "toast.inventory.failed", { targetName(from) .. " does not exist" }, false end
    return Inventory.SetFrom(ply, save, inv or emptyInventory(), "copy")
end

function Inventory.Rollback(ply, save, index)
    local _, versions = Inventory.Read(ply, save)
    local version = versions[index]
    if not version then return "toast.inventory.failed", { "no such version" }, false end
    local inv = Inventory.Clean(version.data)
    if not inv then return "toast.inventory.failed", { "that version is damaged" }, false end
    table.remove(versions, index)
    local ok, err = Inventory.Write(ply, save, inv, "rollback", versions)
    if not ok then return "toast.inventory.failed", { tostring(err) }, false end
    return "toast.inventory.rolled_back", nil, true
end

function Inventory.GiveTarget(ply, save)
    if not ply:Alive() then return "toast.restore_dead", nil, false end
    local inv = Inventory.Read(ply, save)
    if not inv then return "toast.inventory.empty", nil, false end
    local ammo = RARELOAD.Can(ply, "rareload_restore_ammo")
    local skipped = Inventory.Apply(ply, inv, ammo)
    -- Attachments a tick later, once the weapon bases set up their slots; then the clips again.
    if istable(inv.extras) then
        timer.Simple(0, function()
            if not IsValid(ply) then return end
            RARELOAD.Weapons.Apply(ply, inv.extras)
            if ammo then Inventory.SetAmmo(ply, inv.ammo) end
        end)
    end
    if skipped > 0 then return "toast.weapons_skipped", { skipped }, true end
    return "toast.inventory.given", { #inv.weapons }, true
end

-- Network ----------------------------------------------------------------------------------------------

local function handle(op, schema, fn)
    RARELOAD.Net.Handle(op, {
        priv = PRIV,
        rate = 0.3,
        args = schema,
        fn = function(ply, args)
            local key, targs, ok = fn(ply, args)
            if key then RARELOAD.Toast(ply, key, targs, ok == false and "error" or "ok") end
            Inventory.Push(ply, args.save)
        end,
    })
end

handle("inventory.get", { save = "uint?" }, function() end)
-- The JSON is decoded with the default size limits (S12).
handle("inventory.set", { save = "uint?", json = "string:60000" }, function(ply, args)
    return Inventory.SetFrom(ply, args.save, util.JSONToTable(args.json), "edit")
end)
handle("inventory.copy", { save = "uint?", from = "uint?" }, function(ply, args)
    return Inventory.Copy(ply, args.save, args.from)
end)
handle("inventory.rollback", { save = "uint?", version = "uint" }, function(ply, args)
    return Inventory.Rollback(ply, args.save, args.version)
end)
handle("inventory.give", { save = "uint?" }, function(ply, args)
    return Inventory.GiveTarget(ply, args.save)
end)

-- Activity log: every change to an inventory, and every inventory given.
local VERBS = { edit = "edited", copy = "copied into", import = "imported into", rollback = "rolled back" }

local write = Inventory.Write
function Inventory.Write(ply, save, inv, reason, versions)
    local ok, err = write(ply, save, inv, reason, versions)
    if ok and IsValid(ply) then
        RARELOAD.Log("inventory", ply):info("%s %s %s (%d weapons)", ply:Nick(), VERBS[reason] or reason,
            targetName(save), #(inv and inv.weapons or {}))
    end
    return ok, err
end

local give = Inventory.GiveTarget
function Inventory.GiveTarget(ply, save)
    local key, args, ok = give(ply, save)
    if ok then RARELOAD.Log("inventory", ply):info("%s gave themselves %s", ply:Nick(), targetName(save)) end
    return key, args, ok
end
