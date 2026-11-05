-- Global inventory: one set of weapons, ammo and held weapon kept per player for every map, in their
-- PData (sv.db), instead of each map's saves. Its own module: the map's weapons, ammo and activeWeapon
-- modules still save as usual (so turning it off gives the map's inventory back), and are replaced by
-- this one on restore while it is on.
--
-- An inventory, here and in the inventory manager, is { weapons = { class… }, activeWeapon = class?,
-- ammo = { reserve = { [ammo name] = count }, clips = { [class] = { clip1, clip2 } } } }.

RARELOAD.Inventory = RARELOAD.Inventory or {}
local Inventory = RARELOAD.Inventory

local function emptyAmmo() return { reserve = {}, clips = {} } end

-- `extras`: weapon attachments and fire modes (modules/weapon_state.lua), when keepAttachments is on.
function Inventory.Capture(ply)
    local extras = RARELOAD.Get(ply, "keepAttachments") and RARELOAD.Weapons.Capture(ply) or nil
    return { weapons = Inventory.Weapons(ply), activeWeapon = Inventory.Held(ply), ammo = Inventory.Ammo(ply),
        extras = extras }
end

-- The player's global inventory, or nil when none was stored yet. Rareload 5.2 stored only the
-- weapon classes, as a list.
function Inventory.GlobalGet(ply)
    local d = RARELOAD.Store.PData(ply, "global_inventory")
    if not istable(d) then return nil end
    if d[1] ~= nil then return { weapons = d, ammo = emptyAmmo() } end
    d.weapons, d.ammo = istable(d.weapons) and d.weapons or {}, istable(d.ammo) and d.ammo or emptyAmmo()
    return d
end

function Inventory.GlobalSet(ply, inv)
    RARELOAD.Store.PData(ply, "global_inventory", inv)
end

-- Strips the player and gives them `inv` now. `withAmmo`: its clips and reserve too; otherwise the
-- weapons come with their usual starting ammo. Returns how many weapons could not be given.
function Inventory.Apply(ply, inv, withAmmo, alreadyGiven)
    local skipped = 0
    if not alreadyGiven then
        ply:StripWeapons()
        skipped = Inventory.Give(ply, Inventory.HeldFirst(inv.weapons or {}, inv.activeWeapon), withAmmo)
    end
    if withAmmo then Inventory.SetAmmo(ply, inv.ammo or emptyAmmo()) end
    if isstring(inv.activeWeapon) then Inventory.Select(ply, inv.activeWeapon) end
    return skipped
end

local function withAmmo(ply, ctx)
    return (not ctx.only or ctx.only.ammo == true)
        and RARELOAD.Get(ply, "keepAmmo") and RARELOAD.Can(ply, "rareload_restore_ammo")
end

local function report(ply, ctx, skipped)
    if skipped > 0 then
        ctx:step("warn", "globalInventory", skipped .. " could not be given")
        RARELOAD.Toast(ply, "toast.weapons_skipped", { skipped }, "error")
    end
end

RARELOAD.Module({
    id = "globalInventory",
    phase = "inventory",
    setting = { "keepInventory", "globalInventory" },
    privSave = { "rareload_save_inventory", "rareload_global_inventory" },
    privRestore = { "rareload_restore_inventory", "rareload_global_inventory" },
    replaces = { "weapons", "ammo", "activeWeapon", "weaponState" },

    load = function(ply) return Inventory.GlobalGet(ply) end,

    -- The save itself only notes that the global inventory was stored with it. An undo snapshot
    -- (captureOnly) keeps the inventory inline, so undo gives back exactly what the player had.
    save = function(ply, ctx)
        local inv = Inventory.Capture(ply)
        if ctx.opts.captureOnly then return inv end
        Inventory.GlobalSet(ply, inv)
        return true
    end,

    -- Given inside PlayerLoadout like the map's weapons, so the default loadout is skipped (G17).
    spawn = {
        hook = "PlayerLoadout",
        fn = function(ply, inv, ctx)
            report(ply, ctx, Inventory.Give(ply, Inventory.HeldFirst(inv.weapons or {}, inv.activeWeapon),
                withAmmo(ply, ctx)))
            return true
        end,
    },

    -- Ammo and the held weapon wait for this, the tick after the spawn: the weapons exist by then.
    -- Attachments go on a tick later still, then the clips are set again (attachments change
    -- magazine sizes).
    restore = function(ply, inv, ctx)
        local ammo = withAmmo(ply, ctx)
        Inventory.NoteGiven(ctx, inv.weapons)
        report(ply, ctx, Inventory.Apply(ply, inv, ammo, ctx.spawnDone.globalInventory))
        if istable(inv.extras) and RARELOAD.Get(ply, "keepAttachments") then
            RARELOAD.Weapons.ApplyLater(ply, inv.extras, ctx, function()
                if ammo then Inventory.SetAmmo(ply, inv.ammo or emptyAmmo()) end
            end)
        end
    end,

    summary = function(d)
        if not istable(d) then return "stored for every map" end
        local reserve = istable(d.ammo) and d.ammo.reserve or {}
        return #(d.weapons or {}) .. " weapons, " .. table.Count(reserve) .. " ammo types"
    end,
})
