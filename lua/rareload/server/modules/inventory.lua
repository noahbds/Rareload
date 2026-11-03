-- Inventory modules: weapons, ammo and the active weapon.
-- The helpers on RARELOAD.Inventory are shared with the global inventory module and the inventory
-- manager, so what they give and capture is the same as what these modules do.

RARELOAD.Inventory = RARELOAD.Inventory or {}
local Inventory = RARELOAD.Inventory

-- Gives `classes` in order and returns how many could not be given (missing addon or blocked by
-- PlayerCanPickupWeapon, E26). `empty`: weapons come without their starting ammo, because the
-- caller sets every clip and reserve afterwards.
function Inventory.Give(ply, classes, empty)
    local skipped = 0
    ply:SetSuppressPickupNotices(true)                                                               -- G57
    for _, class in ipairs(classes) do
        if isstring(class) and not IsValid(ply:Give(class, empty)) and not ply:HasWeapon(class) then -- G18
            skipped = skipped + 1
        end
    end
    ply:SetSuppressPickupNotices(false)
    return skipped
end

-- The classes to give, with the held weapon first: the first weapon given is the one in hand, and
-- the list is sorted, so otherwise gmod_camera (first alphabetically) would be held for a moment and
-- the click that respawned the player would take a screenshot with it.
function Inventory.HeldFirst(classes, held)
    local out = {}
    if isstring(held) and table.HasValue(classes, held) then out[1] = held end
    for _, class in ipairs(classes) do
        if class ~= held then out[#out + 1] = class end
    end
    return out
end

function Inventory.Weapons(ply)
    local classes = {}
    for _, w in ipairs(ply:GetWeapons()) do classes[#classes + 1] = w:GetClass() end
    table.sort(classes) -- stable order, so an unchanged inventory compares equal (L35)
    return classes
end

-- Reserve ammo is saved for every ammo type the player holds, by name: numeric ammo IDs change when
-- addons add ammo types (G55, B27).
function Inventory.Ammo(ply)
    local reserve, clips = {}, {}
    for id, count in pairs(ply:GetAmmo()) do
        local name = game.GetAmmoName(id)
        if name and count > 0 then reserve[name] = count end
    end
    for _, w in ipairs(ply:GetWeapons()) do
        local c1, c2 = w:Clip1(), w:Clip2()
        if c1 >= 0 or c2 >= 0 then clips[w:GetClass()] = { c1, c2 } end
    end
    return { reserve = reserve, clips = clips }
end

function Inventory.Held(ply)
    local w = ply:GetActiveWeapon()
    return IsValid(w) and w:GetClass() or nil
end

function Inventory.SetAmmo(ply, d)
    ply:RemoveAllAmmo()
    for name, count in pairs(d.reserve or {}) do
        local id = game.GetAmmoID(tostring(name)) -- JSON turns the ammo name into a number
        if id and id >= 0 then
            local max = game.GetAmmoMax(id)
            ply:SetAmmo(max > 0 and math.min(count, max) or count, id)
        end
    end
    for class, clip in pairs(d.clips or {}) do
        local w = ply:GetWeapon(class)
        if IsValid(w) then
            if clip[1] >= 0 then w:SetClip1(clip[1]) end
            if clip[2] >= 0 then w:SetClip2(clip[2]) end
        end
    end
end

-- The switch goes through the player's next user command so it stays inside prediction (G56, B26).
local pendingSelect = setmetatable({}, { __mode = "k" })

function Inventory.Select(ply, class)
    pendingSelect[ply] = class
end

hook.Add("StartCommand", "Rareload.Inventory.SelectWeapon", function(ply, cmd)
    local class = pendingSelect[ply]
    if not class then return end
    pendingSelect[ply] = nil
    local w = ply:GetWeapon(class)
    if IsValid(w) then cmd:SelectWeapon(w) end
end)

-- Whether this restore also restores ammo. Weapons are then given empty, since the ammo module
-- sets every clip and reserve; otherwise they come with their usual starting ammo.
local function ammoRestored(ply, ctx)
    return ctx.entry.data.ammo ~= nil and (not ctx.only or ctx.only.ammo == true)
        and RARELOAD.Get(ply, "keepAmmo") and RARELOAD.Can(ply, "rareload_restore_ammo")
end

local function give(ply, classes, ctx)
    local skipped = Inventory.Give(ply, Inventory.HeldFirst(classes, ctx.entry.data.activeWeapon),
        ammoRestored(ply, ctx))
    if skipped > 0 then
        ctx:step("warn", "weapons", skipped .. " could not be given")
        RARELOAD.Toast(ply, "toast.weapons_skipped", { skipped }, "error")
    end
end

RARELOAD.Module({
    id = "weapons",
    phase = "inventory",
    setting = "keepInventory",
    privSave = "rareload_save_inventory",
    privRestore = "rareload_restore_inventory",

    save = function(ply) return Inventory.Weapons(ply) end,

    -- On respawn the weapons are given inside PlayerLoadout, which then skips the default loadout,
    -- so nothing has to be stripped (G17).
    spawn = {
        hook = "PlayerLoadout",
        fn = function(ply, d, ctx)
            give(ply, d, ctx)
            return true
        end,
    },

    restore = function(ply, d, ctx)
        if ctx.spawnDone.weapons then return end
        ply:StripWeapons()
        give(ply, d, ctx)
    end,

    summary = function(d) return #d .. " weapons" end,
})

RARELOAD.Module({
    id = "ammo",
    phase = "inventory",
    after = { "weapons", "weaponState" }, -- attachments change magazine sizes
    setting = "keepAmmo",
    privSave = "rareload_save_ammo",
    privRestore = "rareload_restore_ammo",

    save = function(ply) return Inventory.Ammo(ply) end,
    restore = function(ply, d) Inventory.SetAmmo(ply, d) end,
    summary = function(d) return table.Count(d.reserve or {}) .. " ammo types" end,
})

RARELOAD.Module({
    id = "activeWeapon",
    phase = "finalize",
    setting = "keepInventory",
    privSave = "rareload_save_inventory",
    privRestore = "rareload_restore_inventory",

    save = function(ply) return Inventory.Held(ply) end,
    restore = function(ply, class) Inventory.Select(ply, class) end,
    summary = function(class) return class end,
})
