-- Inventory modules: weapons, ammo and the active weapon (REWRITE_PLAN.md §14.2).

-- Whether this restore also restores ammo. Weapons are then given empty, since the ammo module
-- sets every clip and reserve; otherwise they come with their usual starting ammo.
local function ammoRestored(ply, ctx)
    return ctx.entry.data.ammo ~= nil and (not ctx.only or ctx.only.ammo == true)
        and RARELOAD.Get(ply, "keepAmmo") and RARELOAD.Can(ply, "rareload_restore_ammo")
end

-- Returns how many weapons could not be given (missing addon or blocked by PlayerCanPickupWeapon, E26).
local function give(ply, classes, ctx)
    local skipped = 0
    local empty = ammoRestored(ply, ctx)
    ply:SetSuppressPickupNotices(true)                                                               -- G57
    for _, class in ipairs(classes) do
        if isstring(class) and not IsValid(ply:Give(class, empty)) and not ply:HasWeapon(class) then -- G18
            skipped = skipped + 1
        end
    end
    ply:SetSuppressPickupNotices(false)
    if skipped > 0 then
        ctx:step("warn", "weapons", skipped .. " could not be given")
        RARELOAD.Toast(ply, "toast.weapons_skipped", { skipped }, "error")
    end
end

local function weaponClasses(ply)
    local classes = {}
    for _, w in ipairs(ply:GetWeapons()) do classes[#classes + 1] = w:GetClass() end
    table.sort(classes)
    return classes
end

local function inventoryData(ply)
    local active = ply:GetActiveWeapon()
    local reserve, clips = {}, {}
    for id, count in pairs(ply:GetAmmo()) do
        local name = game.GetAmmoName(id)
        if name and count > 0 then reserve[name] = count end
    end
    for _, w in ipairs(ply:GetWeapons()) do
        local c1, c2 = w:Clip1(), w:Clip2()
        if c1 >= 0 or c2 >= 0 then clips[w:GetClass()] = { c1, c2 } end
    end
    return {
        weapons = weaponClasses(ply),
        activeWeapon = IsValid(active) and active:GetClass() or nil,
        ammo = { reserve = reserve, clips = clips },
    }
end

local function restoreAmmo(ply, data)
    ply:RemoveAllAmmo()
    for name, count in pairs(data.reserve or {}) do
        local id = game.GetAmmoID(tostring(name))
        if id and id >= 0 then
            local max = game.GetAmmoMax(id)
            ply:SetAmmo(max > 0 and math.min(count, max) or count, id)
        end

    end
    for class, clip in pairs(data.clips or {}) do
        local w = ply:GetWeapon(class)
        if IsValid(w) then
            if clip[1] >= 0 then w:SetClip1(clip[1]) end
            if clip[2] >= 0 then w:SetClip2(clip[2]) end
        end
    end
end

local pendingSelect = setmetatable({}, { __mode = "k" })
local pendingGlobalSelect = setmetatable({}, { __mode = "k" })
RARELOAD.Inventory = RARELOAD.Inventory or {}

hook.Add("StartCommand", "Rareload.Inventory.SelectWeapon", function(ply, cmd)
    local class = pendingSelect[ply]
    if not class then return end
    pendingSelect[ply] = nil
    pendingGlobalSelect[ply] = nil
    local w = ply:GetWeapon(class)
    if IsValid(w) then cmd:SelectWeapon(w) end
end)

local function classesFor(saved, held)
    local out = {}
    if isstring(held) and table.HasValue(saved, held) then out[1] = held end
    for _, class in ipairs(saved) do
        if class ~= held then out[#out + 1] = class end
    end
    return out
end

local function queueGlobalSelection(ply, class)
    if isstring(class) then
        pendingGlobalSelect[ply] = true
        pendingSelect[ply] = class
    end
end

RARELOAD.Module({
    id = "weapons",
    phase = "inventory",
    setting = "keepInventory",
    privSave = "rareload_save_inventory",
    privRestore = "rareload_restore_inventory",

    save = function(ply)
        return weaponClasses(ply)
    end,

    -- On respawn the weapons are given inside PlayerLoadout, which then skips the default loadout,
    -- so nothing has to be stripped (G17).
    spawn = {
        hook = "PlayerLoadout",
        fn = function(ply, d, ctx)
            give(ply, classesFor(d, ctx.entry.data.activeWeapon), ctx)
            return true
        end,
    },

    restore = function(ply, d, ctx)
        if ctx.spawnDone.weapons then return end
        ply:StripWeapons()
        give(ply, classesFor(d, ctx.entry.data.activeWeapon), ctx)
    end,

    summary = function(d) return #d .. " weapons" end,
})

RARELOAD.Module({
    id = "globalInventory",
    phase = "inventory",
    after = { "weapons", "ammo" },
    privSave = "rareload_global_inventory",
    privRestore = "rareload_global_inventory",

    save = function(ply)
        if not RARELOAD.Get(ply, "globalInventory")
            or not RARELOAD.Get(ply, "keepInventory")
            or not RARELOAD.Can(ply, "rareload_save_inventory") then return {} end
        local data = inventoryData(ply)
        RARELOAD.Store.PData(ply, "global_inventory", data)
        return data
    end,

    spawn = {
        hook = "PlayerLoadout",
        fn = function(ply, _, ctx)
            local data = RARELOAD.Store.PData(ply, "global_inventory")
            if not data or not RARELOAD.Get(ply, "globalInventory")
                or not RARELOAD.Get(ply, "keepInventory")
                or not RARELOAD.Can(ply, "rareload_restore_inventory") then return false end
            ply:StripWeapons()
            give(ply, data.weapons or {}, ctx)
            restoreAmmo(ply, data.ammo or {})
            if isstring(data.activeWeapon) then
                ctx:nextTick(function() queueGlobalSelection(ply, data.activeWeapon) end)
            end
            return true
        end,
    },

    restore = function(ply, _, ctx)
        if not RARELOAD.Get(ply, "globalInventory") then return end
        local data = RARELOAD.Store.PData(ply, "global_inventory")
        if not data or not RARELOAD.Get(ply, "keepInventory")
            or not RARELOAD.Can(ply, "rareload_restore_inventory") then return end
        ply:StripWeapons()
        give(ply, data.weapons or {}, ctx)
        restoreAmmo(ply, data.ammo or {})
        if isstring(data.activeWeapon) then
            ctx:nextTick(function() queueGlobalSelection(ply, data.activeWeapon) end)
        end
    end,

    summary = function(d) return "global inventory" end,
})

-- Reserve ammo is saved for every ammo type the player holds, by name: numeric ammo IDs change when
-- addons add ammo types (G55, B27).
RARELOAD.Module({
    id = "ammo",
    phase = "inventory",
    after = { "weapons" },
    setting = "keepAmmo",
    privSave = "rareload_save_ammo",
    privRestore = "rareload_restore_ammo",

    save = function(ply)
        return inventoryData(ply).ammo
    end,

    restore = function(ply, d)
        restoreAmmo(ply, d)
    end,

    summary = function(d) return table.Count(d.reserve or {}) .. " ammo types" end,
})

RARELOAD.Module({
    id = "activeWeapon",
    phase = "finalize",
    setting = "keepInventory",
    privSave = "rareload_save_inventory",
    privRestore = "rareload_restore_inventory",

    save = function(ply)
        local w = ply:GetActiveWeapon()
        return IsValid(w) and w:GetClass() or nil
    end,

    restore = function(ply, class)
        if pendingGlobalSelect[ply] then return end
        pendingSelect[ply] = class
    end,

    summary = function(class) return class end,
})

local function cleanInventory(data, allowUnknownAmmo)
    if not istable(data) or not istable(data.weapons) then return nil, "missing weapons" end
    if #data.weapons > 128 then return nil, "too many weapons" end
    local out = { weapons = {} }
    for _, class in ipairs(data.weapons) do
        if not isstring(class) or #class > 128 then return nil, "invalid weapon class" end
        out.weapons[#out.weapons + 1] = class
    end
    if data.activeWeapon ~= nil and not isstring(data.activeWeapon) then return nil, "invalid active weapon" end
    out.activeWeapon = data.activeWeapon
    local ammo = data.ammo or { reserve = {}, clips = {} }
    if not istable(ammo.reserve) or not istable(ammo.clips) then return nil, "invalid ammo" end
    out.ammo = { reserve = {}, clips = {} }
    for name, count in pairs(ammo.reserve) do
        local ammoName = name
        if not isstring(name) or string.match(name, "^%d+$") then
            ammoName = game.GetAmmoName(tonumber(name) or -1)
        end
        local amount = tonumber(count)
        if not isstring(ammoName) and not allowUnknownAmmo then
            return nil, "invalid reserve ammo"
        end
        if isstring(ammoName) then
            if not RARELOAD.Util.Finite(amount) or amount < 0 then
                return nil, "invalid reserve ammo"
            end
            out.ammo.reserve[ammoName] = math.floor(amount)
        end
    end
    for class, clip in pairs(ammo.clips) do
        local clip1 = istable(clip) and (clip[1] ~= nil and tonumber(clip[1]) or -1)
        local clip2 = istable(clip) and (clip[2] ~= nil and tonumber(clip[2]) or -1)
        if not isstring(class) or not istable(clip)
            or not RARELOAD.Util.Finite(clip1) or clip1 < -1
            or not RARELOAD.Util.Finite(clip2) or clip2 < -1 then
            return nil, "invalid weapon clips"
        end
        out.ammo.clips[class] = { math.floor(clip1), math.floor(clip2) }
    end
    return out
end

local function entryInventory(entry)
    return {
        weapons = entry.data.weapons or {},
        activeWeapon = entry.data.activeWeapon,
        ammo = entry.data.ammo or { reserve = {}, clips = {} },
    }
end

local function giveInventory(ply, data)
    local ctx = { entry = { data = { ammo = data.ammo } }, step = function() end }
    ply:StripWeapons()
    give(ply, data.weapons, ctx)
    restoreAmmo(ply, data.ammo)
    if isstring(data.activeWeapon) then queueGlobalSelection(ply, data.activeWeapon) end
end

RARELOAD.Inventory.Validate = cleanInventory
RARELOAD.Inventory.Give = giveInventory

local function updateEntry(ply, id, data)
    local doc, rel = RARELOAD.History.Doc(ply)
    local entry = RARELOAD.History.Get(ply, id)
    if not doc or not entry then return false, "save not found" end
    entry.inventoryVersions = entry.inventoryVersions or {}
    table.insert(entry.inventoryVersions, 1, { time = os.time(), data = entryInventory(entry) })
    while #entry.inventoryVersions > 8 do table.remove(entry.inventoryVersions) end
    entry.data.weapons, entry.data.activeWeapon, entry.data.ammo = data.weapons, data.activeWeapon, data.ammo
    RARELOAD.Store.Save(rel, doc)
    RARELOAD.History.PushRows(ply)
    return true
end

function RARELOAD.Inventory.ExportFile(ply, id, name)
    local entry = RARELOAD.History.Get(ply, id)
    local key = RARELOAD.Util.PlayerKey(ply)
    if not entry or not key then return false, "save not found" end
    name = RARELOAD.Store.Clean(name or "inventory")
    if name == "" then name = "inventory" end
    local path = "rareload/inventories/" .. key .. "/" .. name .. ".json"
    file.CreateDir("rareload/inventories/" .. key)
    file.Write(path, util.TableToJSON(entryInventory(entry), true))
    return true, path
end

function RARELOAD.Inventory.ImportFile(ply, id, name)
    local key = RARELOAD.Util.PlayerKey(ply)
    if not key then return false, "no steamid" end
    name = RARELOAD.Store.Clean(name or "inventory")
    if name == "" then name = "inventory" end
    local path = "rareload/inventories/" .. key .. "/" .. name .. ".json"
    local data, err = cleanInventory(util.JSONToTable(file.Read(path, "DATA") or "", true))
    if not data then return false, err end
    return updateEntry(ply, id, data)
end

local function pushInventory(ply, id)
    local entry = RARELOAD.History.Get(ply, id)
    if not entry then return end
    RARELOAD.Net.Push(ply, "inventory", {
        id = id,
        current = entryInventory(entry),
        versions = entry.inventoryVersions or {},
    })
end

local function globalInventoryAllowed(ply)
    return true
end

local function globalInventory(ply)
    return RARELOAD.Store.PData(ply, "global_inventory")
        or { weapons = {}, activeWeapon = nil, ammo = { reserve = {}, clips = {} } }
end

local function pushGlobalInventory(ply)
    RARELOAD.Net.Push(ply, "inventory", {
        id = 0,
        current = globalInventory(ply),
        versions = {},
        global = true,
    })
end

RARELOAD.Net.Handle("inventory.get", {
    priv = "rareload_manage_inventory",
    rate = 0.2,
    args = { id = "uint" },
    fn = function(ply, a) pushInventory(ply, a.id) end,
})

RARELOAD.Net.Handle("inventory.global.get", {
    priv = "rareload_manage_inventory",
    rate = 0.2,
    args = {},
    fn = function(ply)
        if globalInventoryAllowed(ply) then pushGlobalInventory(ply) end
    end,
})

RARELOAD.Net.Handle("inventory.export", {
    priv = "rareload_manage_inventory",
    rate = 0.5,
    args = { id = "uint" },
    fn = function(ply, a)
        local entry = RARELOAD.History.Get(ply, a.id)
        if entry then
            RARELOAD.Net.Push(ply, "inventory.export", {
                id = a.id, json = util.TableToJSON(entryInventory(entry), true),
            })
        end
    end,
})

RARELOAD.Net.Handle("inventory.apply", {
    priv = "rareload_manage_inventory",
    rate = 0.5,
    args = { id = "uint", json = "string:60000" },
    fn = function(ply, a)
        local parsed = util.JSONToTable(a.json, true)
        local data, err = cleanInventory(parsed)
        if not data then
            RARELOAD.Log("history"):warn("%s: invalid inventory import: %s", ply:Nick(), err)
            return
        end
        updateEntry(ply, a.id, data)
        pushInventory(ply, a.id)
    end,
})

RARELOAD.Net.Handle("inventory.global.apply", {
    priv = "rareload_manage_inventory",
    rate = 0.5,
    args = { json = "string:60000" },
    fn = function(ply, a)
        if not globalInventoryAllowed(ply) then return end
        local data, err = cleanInventory(util.JSONToTable(a.json, true))
        if not data then
            RARELOAD.Log("history"):warn("%s: invalid global inventory import: %s", ply:Nick(), err)
            return
        end
        RARELOAD.Store.PData(ply, "global_inventory", data)
        pushGlobalInventory(ply)
    end,
})

RARELOAD.Net.Handle("inventory.copy", {
    priv = "rareload_manage_inventory",
    rate = 0.5,
    args = { id = "uint", source = "uint" },
    fn = function(ply, a)
        local source = RARELOAD.History.Get(ply, a.source)
        if not source then return end
        local data, err = cleanInventory(entryInventory(source), true)
        if not data then
            RARELOAD.Log("history"):warn("%s: invalid inventory copy: %s", ply:Nick(), err)
            return
        end
        updateEntry(ply, a.id, data)
        pushInventory(ply, a.id)
    end,
})

RARELOAD.Net.Handle("inventory.give", {
    priv = "rareload_manage_inventory",
    rate = 0.5,
    args = { json = "string:60000" },
    fn = function(ply, a)
        local data, err = cleanInventory(util.JSONToTable(a.json, true))
        if not data then
            RARELOAD.Log("history"):warn("%s: invalid inventory give: %s", ply:Nick(), err)
            return
        end
        giveInventory(ply, data)
    end,
})

RARELOAD.Net.Handle("inventory.global.export", {
    priv = "rareload_manage_inventory",
    rate = 0.5,
    args = {},
    fn = function(ply)
        if globalInventoryAllowed(ply) then
            RARELOAD.Net.Push(ply, "inventory.export", {
                id = 0, json = util.TableToJSON(globalInventory(ply), true),
            })
        end
    end,
})

RARELOAD.Net.Handle("inventory.restoreVersion", {
    priv = "rareload_manage_inventory",
    rate = 0.5,
    args = { id = "uint", version = "uint" },
    fn = function(ply, a)
        local entry = RARELOAD.History.Get(ply, a.id)
        local version = entry and entry.inventoryVersions and entry.inventoryVersions[a.version]
        local data, err = version and cleanInventory(version.data)
        if not data then
            RARELOAD.Log("history"):warn("%s: invalid inventory version: %s", ply:Nick(), err or "not found")
            return
        end
        updateEntry(ply, a.id, data)
        pushInventory(ply, a.id)
    end,
})
