-- Shared helpers for SED panel data building.

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

SED = SED or {}
SED.PanelBuilder = SED.PanelBuilder or {}

local PB = SED.PanelBuilder

PB.CATEGORY_LABEL_ORDER = {
    basic = {
        "NPC ID", "Entity ID", "Rareload NPC ID", "Rareload Entity ID", "Class", "Class Name", "NPC Name",
        "Display Name", "Model", "Owner", "Spawned"
    },
    saved = {
        "Save Timestamp", "Restore Time", "Saved By Rareload", "Saved via Duplicator", "Spawned By Rareload",
        "Persistent", "Creation Time", "Saved Position", "Saved Angles", "Saved Velocity"
    },
    position = { "Saved Pos", "Saved Ang", "Live Pos", "Live Ang", "Speed" },
    state = {
        "Live HP", "Saved HP", "Start HP", "Armor", "AI State", "NPC State", "Hull", "SchedID", "Cycle",
        "Seq", "Playback", "Frozen"
    },
    behavior = {
        "Behavior", "Movement", "Alert Status", "Status", "Follow Player", "Call For Help", "Squad", "Leader",
        "Target"
    },
    combat = { "Melee Attack", "Grenade Attack", "Medic", "Weapons", "Proficiency" },
    visual = { "Skin", "Bodygroups", "ModelScale", "RenderMode", "RenderFX", "Material", "Color", "Blood" },
    physics = {
        "Physics Objects", "Physics Exists", "Physics Velocity", "Physics Frozen", "Physics Mass", "Gravity Enabled",
        "Motion Enabled", "Hull", "CollGroup", "Solid", "SpawnFlags"
    },
    ownership = { "Owner", "OwnerID", "OwnerID64", "Rareload Owner", "SpawnedBy", "SpawnFlags" },
    relations = { "PlayerRel", "Player Rels", "VJ Classes", "SquadMembers" },
    weapons = { "Equipped", "Inventory", "Accuracy" },
    ai = {
        "Behavior", "Movement", "Sight Range", "Sight Angle", "Turn Speed", "Follow Player", "Call For Help",
        "Can Investigate", "Can Open Doors", "Can Receive Orders"
    },
    sounds = { "Has Sounds", "Pitch" },
    vjbase = { "VJ Base NPC", "Name", "Category", "Base", "Type", "Immunities", "God Mode" }
}

PB.EXCLUDED_META_KEYS = {
    _ownerSteamID = true,
    _fromSnapshot = true,
    id = true,
    class = true,
    Class = true,
    ClassName = true,
    NPCName = true,
    npcName = true,
    name = true,
    Name = true,
    PrintName = true,
    model = true,
    Model = true,
    pos = true,
    Pos = true,
    ang = true,
    Angle = true,
    Ang = true,
    velocity = true,
    Velocity = true,
    SavedAt = true,
    savedAt = true,
    spawnTime = true,
    RestoreTime = true,
    creationTime = true,
    SavedByRareload = true,
    SavedViaDuplicator = true,
    SpawnedByRareload = true,
    owner = true,
    ownerSteamID = true,
    ownerSteamID64 = true,
    RareloadOwnerSteamID = true,
    RareloadOwnerSteamID64 = true,
    RareloadNPCID = true,
    RareloadEntityID = true,
    RareloadID = true,
    MaxHealth = true,
    maxHealth = true,
    CurHealth = true,
    Health = true,
    health = true,
    StartHealth = true,
    armor = true,
    Armor = true,
    PhysicsObjects = true,
    physics = true,
    Mins = true,
    Maxs = true,
    mins = true,
    maxs = true,
    bodygroups = true,
    BodyGroups = true,
    subMaterials = true,
    SubMaterials = true,
    color = true,
    Color = true,
    bloodColor = true,
    BloodColor = true,
    collisionGroup = true,
    ColGroup = true,
    solidType = true,
    SolidType = true,
    hullType = true,
    HullType = true,
    spawnflags = true,
    SpawnFlags = true,
    originallySpawnedBy = true,
    OriginalSpawner = true,
    vjBaseData = true,
    VJ_NPC_Class = true,
    weapons = true,
    WeaponInventory = true,
    relations = true,
    target = true,
    Target = true,
    squadMembers = true,
    keyvalues = true,
    keyValues = true
}

function PB.newCategories()
    return {
        basic = {},
        position = {},
        saved = {},
        state = {},
        visual = {},
        behavior = {},
        physics = {},
        ownership = {},
        keyvalues = {},
        relations = {},
        combat = {},
        vjbase = {},
        weapons = {},
        ai = {},
        sounds = {},
        meta = {}
    }
end

function PB.firstValue(source, ...)
    if not istable(source) then return nil end
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local value = source[key]
        if value ~= nil and value ~= "" then
            return value, key
        end
    end
    return nil
end

function PB.yesNo(value)
    if value == nil then return nil end
    return value and "Yes" or "No"
end

local FALLBACK_TEXT_COLOR = Color(220, 220, 255)

function PB.resolveTextColor(value)
    local themeText = SED and SED.THEME and SED.THEME.text
    if RS and RS.safeTextColor then
        local fallback = RS.safeTextColor(themeText, FALLBACK_TEXT_COLOR)
        return RS.safeTextColor(value, fallback)
    end

    if istable(value) and tonumber(value.r) ~= nil and tonumber(value.g) ~= nil and tonumber(value.b) ~= nil then
        return value
    end

    if istable(themeText) and tonumber(themeText.r) ~= nil and tonumber(themeText.g) ~= nil and tonumber(themeText.b) ~= nil then
        return themeText
    end

    return FALLBACK_TEXT_COLOR
end

function PB.formatVectorLike(value, precision)
    if value == nil then return nil end
    local fmt = "%0." .. tostring(precision or 1) .. "f"
    if isvector and isvector(value) then
        return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value.x, value.y, value.z)
    end
    if istable(value) then
        if value.x ~= nil and value.y ~= nil and value.z ~= nil then
            return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value.x, value.y, value.z)
        end
        if value[1] ~= nil and value[2] ~= nil and value[3] ~= nil then
            return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value[1], value[2], value[3])
        end
    end
    return nil
end

function PB.formatAngleLike(value, precision)
    if value == nil then return nil end
    local fmt = "%0." .. tostring(precision or 1) .. "f"
    if isangle and isangle(value) then
        return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value.p, value.y, value.r)
    end
    if istable(value) then
        if value.p ~= nil and value.y ~= nil and value.r ~= nil then
            return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value.p, value.y, value.r)
        end
        if value[1] ~= nil and value[2] ~= nil and value[3] ~= nil then
            return string.format(fmt .. ", " .. fmt .. ", " .. fmt, value[1], value[2], value[3])
        end
    end
    return nil
end

function PB.summarizeValueForPanel(value)
    local valueType = type(value)
    if valueType == "nil" then return nil end
    if valueType == "string" then
        if value == "" then return nil end
        return value
    end
    if valueType == "number" then
        return tostring(value)
    end
    if valueType == "boolean" then
        return value and "Yes" or "No"
    end
    if valueType == "table" then
        local count = table.Count(value)
        if count == 0 then
            return "{}"
        end
        if count <= 6 then
            local preview = {}
            local n = 0
            for k, v in pairs(value) do
                if type(v) == "table" then
                    preview = nil
                    break
                end
                n = n + 1
                preview[#preview + 1] = tostring(k) .. "=" .. tostring(v)
                if n >= 4 then break end
            end
            if preview and #preview > 0 then
                if count > #preview then
                    preview[#preview + 1] = "..."
                end
                return "{" .. table.concat(preview, ", ") .. "}"
            end
        end
        return ("table(%d)"):format(count)
    end
    return tostring(value)
end

local function isLikelySoundPath(value)
    if type(value) ~= "string" then return false end
    local lower = value:lower()
    return lower:find("%.wav$", 1, false) ~= nil or
        lower:find("%.mp3$", 1, false) ~= nil or
        lower:find("%.ogg$", 1, false) ~= nil
end

local function compactSoundPath(path)
    if type(path) ~= "string" or path == "" then return nil end

    local normalized = path:gsub("\\", "/")
    local parts = string.Explode("/", normalized)
    local clean = {}

    for i = 1, #parts do
        if parts[i] ~= "" then
            clean[#clean + 1] = parts[i]
        end
    end

    if #clean == 0 then
        return normalized
    end

    local startIdx = math.max(1, #clean - 2)
    local tail = {}
    for i = startIdx, #clean do
        tail[#tail + 1] = clean[i]
    end

    return table.concat(tail, "/")
end

function PB.summarizeSoundValueForPanel(value)
    if type(value) == "string" then
        if value == "" then return nil end
        if isLikelySoundPath(value) then
            return compactSoundPath(value)
        end
        return value
    end

    if not istable(value) then
        return PB.summarizeValueForPanel(value)
    end

    local soundItems = {}
    for _, v in pairs(value) do
        if type(v) == "string" and v ~= "" then
            soundItems[#soundItems + 1] = v
        end
    end

    if #soundItems == 0 then
        return PB.summarizeValueForPanel(value)
    end

    table.sort(soundItems)

    local preview = {}
    for i = 1, #soundItems do
        preview[#preview + 1] = "\n  - " .. (compactSoundPath(soundItems[i]) or soundItems[i])
    end

    return string.format("%d sounds:%s", #soundItems, table.concat(preview, ""))
end

function PB.humanizeKeyLabel(label)
    local text = tostring(label or "")
    if text == "" then return "" end

    text = text:gsub("_", " ")
    text = text:gsub("(%l)(%u)", "%1 %2")
    text = text:gsub("(%u)(%u%l)", "%1 %2")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

function PB.sortCategoryLines(list, orderList)
    if not list or #list <= 1 then return end
    local priorities = {}
    if orderList then
        for i, label in ipairs(orderList) do
            priorities[label] = i
        end
    end

    table.sort(list, function(a, b)
        local pa = priorities[a[1]] or 1000
        local pb = priorities[b[1]] or 1000
        if pa ~= pb then return pa < pb end

        local la = tostring(a[1]):lower()
        local lb = tostring(b[1]):lower()
        if la ~= lb then return la < lb end

        return (a[5] or 0) < (b[5] or 0)
    end)
end
