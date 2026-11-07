-- Weapon attachments and fire modes (5.4 plan, B1). Weapon bases keep a customized weapon's state
-- in their own Lua tables, which a plain ply:Give() starts over, so one adapter per base captures it
-- and applies it again. ARC9 and ArcCW also keep each player's attachment inventory (when
-- attachments aren't free); it is saved with the weapons, so installing the saved attachments never
-- takes them from what the player owns. Every call into a base is pcall-guarded: a renamed method
-- must never break a save or a restore.
--
-- Saved state: { weapons = { [class] = { adapter = id, data = t } }, owned = { [adapterId] = inv } }.

RARELOAD.Weapons = RARELOAD.Weapons or {}
local Weapons = RARELOAD.Weapons
Weapons.adapters = Weapons.adapters or {}

-- adapter = { id, available() -> bool, matches(wep) -> bool, capture(wep, ply) -> t?, apply(wep, t, ply),
--             captureOwned?(ply) -> inv?, applyOwned?(ply, inv) }
function Weapons.Adapter(adapter)
    Weapons.adapters[adapter.id] = adapter
end

local call = RARELOAD.Util.Call

function Weapons.AdapterFor(wep)
    for _, a in SortedPairs(Weapons.adapters) do
        if call(a.available) and call(a.matches, wep) then return a end
    end
end

-- A copy holding only plain values (strings, numbers, booleans, tables of them).
local function plain(v, depth)
    if not istable(v) then return (isstring(v) or isnumber(v) or isbool(v)) and v or nil end
    if depth > 12 then return nil end
    local out = {}
    for k, x in pairs(v) do
        if isstring(k) or isnumber(k) then out[k] = plain(x, depth + 1) end
    end
    return out
end

function Weapons.Capture(ply)
    local out = { weapons = {}, owned = {} }
    for _, wep in ipairs(ply:GetWeapons()) do
        local a = Weapons.AdapterFor(wep)
        local data = a and call(a.capture, wep, ply)
        if data ~= nil then out.weapons[wep:GetClass()] = { adapter = a.id, data = plain(data, 0) } end
    end
    for id, a in SortedPairs(Weapons.adapters) do
        local inv = call(a.available) and call(a.captureOwned, ply)
        if inv ~= nil then out.owned[id] = plain(inv, 0) end
    end
    if not next(out.weapons) and not next(out.owned) then return nil end
    return out
end

-- Applies a captured state to the weapons the player holds now. Weapons first, then the attachment
-- inventories, so these end up exactly as saved whatever installing took or gave back.
-- Returns how many weapons could not get their state back.
function Weapons.Apply(ply, state)
    local failed = 0
    for class, w in pairs(istable(state) and istable(state.weapons) and state.weapons or {}) do
        local wep, a = ply:GetWeapon(class), istable(w) and Weapons.adapters[w.adapter]
        if IsValid(wep) and a and call(a.available) and call(a.matches, wep) and istable(w.data) then
            local ok, err = pcall(a.apply, wep, w.data, ply)
            if not ok then
                failed = failed + 1
                RARELOAD.Log("weapons", ply):warn("%s: %s state not applied: %s", ply:Nick(), class, tostring(err))
            end
        elseif IsValid(wep) then
            failed = failed + 1
        end
    end
    for id, inv in pairs(istable(state) and istable(state.owned) and state.owned or {}) do
        local a = Weapons.adapters[id]
        if a and call(a.available) and istable(inv) then call(a.applyOwned, ply, inv) end
    end
    return failed
end

local function copy(t) return util.JSONToTable(util.TableToJSON(t)) or {} end

-- ARC9: a tree per slot, { Installed, ToggleNum, SubAttachments = { … } }, rebuilt the way the base
-- rebuilds it when a client sends a new build (SWEP:ReceiveWeapon).
local function arc9Tree(slot)
    local out = { Installed = slot.Installed, ToggleNum = slot.ToggleNum }
    if istable(slot.SubAttachments) then
        out.SubAttachments = {}
        for i, sub in pairs(slot.SubAttachments) do
            if istable(sub) then out.SubAttachments[i] = arc9Tree(sub) end
        end
    end
    return out
end

Weapons.Adapter({
    id = "arc9",
    available = function() return istable(ARC9) end,
    matches = function(wep) return wep.ARC9 == true and isfunction(wep.BuildSubAttachments) end,
    capture = function(wep)
        local tree = {}
        for i, slot in ipairs(wep.Attachments or {}) do tree[i] = istable(slot) and arc9Tree(slot) or {} end
        return { tree = tree, firemode = call(wep.GetFiremode, wep) }
    end,
    apply = function(wep, t)
        if istable(t.tree) then
            wep:BuildSubAttachments(t.tree)
            call(wep.DoInvalidateCache, wep)
            call(wep.PruneAttachments, wep)
            call(wep.FillIntegralSlots, wep)
            call(wep.SendWeapon, wep)
            call(wep.PostModify, wep)
        end
        if isnumber(t.firemode) then call(wep.SetFiremode, wep, t.firemode) end
    end,
    captureOwned = function(ply) return istable(ply.ARC9_AttInv) and copy(ply.ARC9_AttInv) or nil end,
    applyOwned = function(ply, inv)
        ply.ARC9_AttInv = copy(inv)
        call(ARC9.PlayerSendAttInv, ARC9, ply)
    end,
})

-- ArcCW: one attachment per slot. Sub-slots are added when their parent is installed and come after
-- it, so slots are installed in order. Installing takes the attachment from the player's inventory,
-- so it is given first; the inventory is set to what was saved afterwards.
Weapons.Adapter({
    id = "arccw",
    available = function() return istable(ArcCW) end,
    matches = function(wep) return wep.ArcCW == true and isfunction(wep.Attach) end,
    capture = function(wep)
        local slots = {}
        for i, slot in pairs(wep.Attachments or {}) do
            if isnumber(i) and istable(slot) and slot.Installed and not slot.Internal then
                slots[#slots + 1] = { i = i, att = slot.Installed, toggle = slot.ToggleNum, slide = slot.SlidePos }
            end
        end
        table.sort(slots, function(a, b) return a.i < b.i end)
        return { slots = slots, firemode = call(wep.GetFireMode, wep) }
    end,
    apply = function(wep, t, ply)
        local want = {}
        for _, s in ipairs(istable(t.slots) and t.slots or {}) do want[tonumber(s.i) or -1] = s end
        local current = table.GetKeys(wep.Attachments or {})
        table.sort(current, function(a, b) return (tonumber(a) or 0) > (tonumber(b) or 0) end)
        for _, i in ipairs(current) do
            local slot = wep.Attachments[i]
            local kept = want[i] and want[i].att == (istable(slot) and slot.Installed)
            if istable(slot) and slot.Installed and not slot.Internal and not kept then
                wep:Detach(i, true, true, true)
            end
        end
        for _, s in ipairs(istable(t.slots) and t.slots or {}) do
            local slot = wep.Attachments[tonumber(s.i) or -1]
            if istable(slot) and isstring(s.att) then
                if slot.Installed ~= s.att then
                    call(ArcCW.PlayerGiveAtt, ArcCW, ply, s.att)
                    wep:Attach(s.i, s.att, true, true)
                end
                if slot.Installed == s.att then
                    slot.ToggleNum = s.toggle or slot.ToggleNum
                    slot.SlidePos = s.slide or slot.SlidePos
                end
            end
        end
        call(wep.AdjustAtts, wep)
        call(wep.NetworkWeapon, wep)
        if isnumber(t.firemode) then call(wep.SetFireMode, wep, t.firemode) end
    end,
    captureOwned = function(ply) return istable(ply.ArcCW_AttInv) and copy(ply.ArcCW_AttInv) or nil end,
    applyOwned = function(ply, inv)
        ply.ArcCW_AttInv = copy(inv)
        call(ArcCW.PlayerSendAttInv, ArcCW, ply)
    end,
})

-- TFA Base: each category has a list of attachments and the selected one (`sel`). Kept as a list of
-- { cat, att } because JSON turns number-like keys into numbers.
Weapons.Adapter({
    id = "tfa",
    available = function() return istable(TFA) end,
    matches = function(wep) return wep.IsTFAWeapon == true and isfunction(wep.SetTFAAttachment) end,
    capture = function(wep)
        local sel = {}
        for cat, slot in pairs(wep.Attachments or {}) do
            if istable(slot) and istable(slot.atts) and slot.sel and isstring(slot.atts[slot.sel]) then
                sel[#sel + 1] = { cat = cat, att = slot.atts[slot.sel] }
            end
        end
        table.sort(sel, function(a, b) return tostring(a.cat) < tostring(b.cat) end)
        return { sel = sel, firemode = call(wep.GetFireMode, wep) }
    end,
    apply = function(wep, t)
        local want = {}
        for _, s in ipairs(istable(t.sel) and t.sel or {}) do want[tostring(s.cat)] = s.att end
        for cat, slot in pairs(wep.Attachments or {}) do
            if istable(slot) and istable(slot.atts) then
                local att = want[tostring(cat)]
                if isstring(att) then
                    wep:SetTFAAttachment(cat, att, true, true)
                elseif slot.sel then
                    wep:SetTFAAttachment(cat, 0, true, true)
                end
            end
        end
        if isnumber(t.firemode) then call(wep.SetFireMode, wep, t.firemode) end
    end,
})

-- Modern Warfare Base (mg_base): one attachment class in use per slot, installed through the same
-- attachment entity the customization menu creates.
Weapons.Adapter({
    id = "mwbase",
    available = function() return istable(MW_ATTS) end,
    matches = function(wep)
        return weapons.IsBasedOn(wep:GetClass(), "mg_base") and isfunction(wep.GetAllAttachmentsInUse)
    end,
    capture = function(wep)
        local list = {}
        for _, att in pairs(wep:GetAllAttachmentsInUse() or {}) do
            if istable(att) and isstring(att.ClassName) then list[#list + 1] = att.ClassName end
        end
        table.sort(list)
        return { atts = list }
    end,
    apply = function(wep, t)
        local inUse = {}
        for _, att in pairs(wep:GetAllAttachmentsInUse() or {}) do
            if istable(att) and att.ClassName then inUse[att.ClassName] = true end
        end
        for _, class in ipairs(istable(t.atts) and t.atts or {}) do
            if isstring(class) and not inUse[class] then wep:CreateAttachmentEntity(class) end
        end
    end,
})

-- Module ------------------------------------------------------------------------------------------

local function report(ply, ctx, failed)
    if failed > 0 then
        ctx:step("warn", "weaponState", failed .. " weapons kept their default attachments")
    end
end

-- Applied one tick after the weapons were given, once the bases set up their attachment slots.
function Weapons.ApplyLater(ply, state, ctx, after)
    local done = ctx:async("weaponState")
    ctx:nextTick(function()
        report(ply, ctx, Weapons.Apply(ply, state))
        if after then after() end
        done()
    end)
end

RARELOAD.Module({
    id = "weaponState",
    phase = "inventory",
    after = { "weapons" },
    setting = { "keepInventory", "keepAttachments" },
    privSave = "rareload_save_inventory",
    privRestore = "rareload_restore_inventory",

    save = function(ply) return Weapons.Capture(ply) end,
    restore = function(ply, state, ctx) Weapons.ApplyLater(ply, state, ctx) end,

    summary = function(state)
        local n = table.Count(istable(state.weapons) and state.weapons or {})
        local owned = table.GetKeys(istable(state.owned) and state.owned or {})
        table.sort(owned)
        return n .. " customized weapons" .. (#owned > 0 and ", inventory: " .. table.concat(owned, ", ") or "")
    end,
})
