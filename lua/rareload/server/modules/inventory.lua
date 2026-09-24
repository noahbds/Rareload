-- Inventory modules: weapons, ammo and the active weapon (REWRITE_PLAN.md §14.2).

local function useGlobal(ply)
    return RARELOAD.Get(ply, "globalInventory") and RARELOAD.Can(ply, "rareload_global_inventory")
end

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
    ply:SetSuppressPickupNotices(true)   -- G57
    for _, class in ipairs(classes) do
        if isstring(class) and not IsValid(ply:Give(class, empty)) and not ply:HasWeapon(class) then   -- G18
            skipped = skipped + 1
        end
    end
    ply:SetSuppressPickupNotices(false)
    if skipped > 0 then
        ctx:step("warn", "weapons", skipped .. " could not be given")
        RARELOAD.Toast(ply, "toast.weapons_skipped", { skipped }, "error")
    end
end

-- The classes to give, with the saved held weapon first: the first weapon given is the one in hand,
-- and the list is sorted, so otherwise gmod_camera (first alphabetically) would be held for a moment
-- and the click that respawned the player would take a screenshot with it.
local function classesFor(ply, saved, ctx)
    local classes = saved
    if useGlobal(ply) then
        local global = RARELOAD.Store.PData(ply, "global_inventory")
        if istable(global) then classes = global end
    end
    local held = ctx.entry.data.activeWeapon
    local out = {}
    if isstring(held) and table.HasValue(classes, held) then out[1] = held end
    for _, class in ipairs(classes) do
        if class ~= held then out[#out + 1] = class end
    end
    return out
end

RARELOAD.Module({
    id = "weapons",
    phase = "inventory",
    setting = "keepInventory",
    privSave = "rareload_save_inventory",
    privRestore = "rareload_restore_inventory",

    save = function(ply)
        local classes = {}
        for _, w in ipairs(ply:GetWeapons()) do classes[#classes + 1] = w:GetClass() end
        table.sort(classes)   -- stable order, so an unchanged inventory compares equal (L35)
        if useGlobal(ply) then RARELOAD.Store.PData(ply, "global_inventory", classes) end
        return classes
    end,

    -- On respawn the weapons are given inside PlayerLoadout, which then skips the default loadout,
    -- so nothing has to be stripped (G17).
    spawn = {
        hook = "PlayerLoadout",
        fn = function(ply, d, ctx)
            give(ply, classesFor(ply, d, ctx), ctx)
            return true
        end,
    },

    restore = function(ply, d, ctx)
        if ctx.spawnDone.weapons then return end
        ply:StripWeapons()
        give(ply, classesFor(ply, d, ctx), ctx)
    end,

    summary = function(d) return #d .. " weapons" end,
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
    end,

    restore = function(ply, d)
        ply:RemoveAllAmmo()
        for name, count in pairs(d.reserve or {}) do
            local id = game.GetAmmoID(tostring(name))   -- JSON turns the "357" ammo name into a number
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
    end,

    summary = function(d) return table.Count(d.reserve or {}) .. " ammo types" end,
})

-- The switch goes through the player's next user command so it stays inside prediction (G56, B26).
local pendingSelect = setmetatable({}, { __mode = "k" })

hook.Add("StartCommand", "Rareload.Inventory.SelectWeapon", function(ply, cmd)
    local class = pendingSelect[ply]
    if not class then return end
    pendingSelect[ply] = nil
    local w = ply:GetWeapon(class)
    if IsValid(w) then cmd:SelectWeapon(w) end
end)

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
        pendingSelect[ply] = class
    end,

    summary = function(class) return class end,
})
