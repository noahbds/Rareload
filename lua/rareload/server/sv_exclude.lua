-- Objects left out of saves (5.4 plan, D1): the context-menu mark (sh_exclude.lua) and the server's list
-- of blocked classes. A convar can't hold the list (250 characters), so it is a stored document,
-- data/rareload/blocked.json, edited from the server menu or with `rareload block`.

RARELOAD.Blocked = RARELOAD.Blocked or {}
local Blocked = RARELOAD.Blocked

local DOC = "blocked"
local MAX_CLASSES = 256

local function loadDoc()
    local doc = RARELOAD.Store.Load(DOC)
    if not istable(doc) or not istable(doc.classes) then
        doc = { v = RARELOAD.Store.SCHEMA, classes = {} }
    end
    return doc
end

-- The set is rebuilt only when the list changes; Has is asked for every object of every save.
local set
local function rebuild()
    set = {}
    for _, class in ipairs(loadDoc().classes) do
        if isstring(class) then set[string.lower(class)] = true end
    end
end

function Blocked.Has(class)
    if not set then rebuild() end
    return isstring(class) and set[string.lower(class)] == true
end

function Blocked.List()
    local list = table.Copy(loadDoc().classes)
    table.sort(list)
    return list
end

-- A class name as typed: lowercase letters, digits, _ - . and * are not wildcards.
local function clean(class)
    class = string.lower(string.Trim(tostring(class or "")))
    if class == "" or #class > 64 or not string.match(class, "^[%w_%-%.]+$") then return nil end
    return class
end

-- Returns true, or false and why (English, for the console).
function Blocked.Add(class)
    class = clean(class)
    if not class then return false, "not a valid class name" end
    if Blocked.Has(class) then return false, class .. " is already blocked" end
    local doc = loadDoc()
    if #doc.classes >= MAX_CLASSES then return false, "the list is full (" .. MAX_CLASSES .. " classes)" end
    doc.classes[#doc.classes + 1] = class
    table.sort(doc.classes)
    RARELOAD.Store.Save(DOC, doc)
    rebuild()
    return true, class
end

function Blocked.Remove(class)
    class = clean(class)
    if not class or not Blocked.Has(class) then return false, tostring(class) .. " is not blocked" end
    local doc = loadDoc()
    for i = #doc.classes, 1, -1 do
        if string.lower(doc.classes[i]) == class then table.remove(doc.classes, i) end
    end
    RARELOAD.Store.Save(DOC, doc)
    rebuild()
    return true, class
end

-- Server menu -----------------------------------------------------------------------------------------

local PRIV = "rareload_block_classes"

local function push(ply)
    RARELOAD.Net.Push(ply, "blocked", { classes = Blocked.List() })
end

RARELOAD.Net.Handle("blocked.get", { priv = PRIV, rate = 0.5, fn = push })

RARELOAD.Net.Handle("blocked.set", {
    priv = PRIV,
    rate = 0.1,
    args = { add = "bool", class = "string:64" },
    fn = function(ply, a)
        local ok, what = (a.add and Blocked.Add or Blocked.Remove)(a.class)
        if ok then
            RARELOAD.Log("exclude", ply):info("%s %s the class %s", ply:Nick(), a.add and "blocked" or "unblocked", what)
        else
            RARELOAD.Toast(ply, "toast.block_failed", { what }, "error")
        end
        push(ply)
    end,
})

-- The context-menu mark --------------------------------------------------------------------------------

RARELOAD.Net.Handle("object.exclude", {
    priv = "rareload_save_entities",
    rate = 0.2,
    args = { ent = "uint", on = "bool" },
    fn = function(ply, a)
        local ent = Entity(a.ent)
        if not IsValid(ent) or ent:IsPlayer() or ent:IsWorld() then return end
        -- Your own objects; admins who manage saved objects may mark anyone's.
        local mine = RARELOAD.Ownership.OwnerOf(ent) == ply:SteamID64()
        if not mine and not RARELOAD.Can(ply, "rareload_manage_objects") then
            return RARELOAD.Toast(ply, "toast.exclude_denied", nil, "error")
        end
        RARELOAD.Exclude.Set(ent, a.on)
        RARELOAD.Toast(ply, a.on and "toast.excluded" or "toast.included", nil, "ok")
        RARELOAD.Log("exclude", ply):info("%s %s %s from saves", ply:Nick(), a.on and "left out" or "put back",
            tostring(ent))
        -- The next autosave of its owner drops it (or takes it again).
        local owner = player.GetBySteamID64(RARELOAD.Ownership.OwnerOf(ent) or "")
        if IsValid(owner) then RARELOAD.Autosave.Mark(owner, "entities", "npcs", "vehicles", "constraints") end
    end,
})
