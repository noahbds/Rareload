if SED then
    SED.EntityPanelCache = {}
    SED.NPCPanelCache = {}
end

local RS = SED and SED.RenderShared
if not (RS and RS._initialized) then
    include("rareload/client/saved_entity_display/SED_panel_renderer_shared.lua")
    RS = SED and SED.RenderShared
end

include("rareload/client/saved_entity_display/SED_panel_builder_utils.lua")
include("rareload/client/saved_entity_display/SED_panel_builder_collectors.lua")

local PB = SED and SED.PanelBuilder
if not PB then
    ErrorNoHalt("[Rareload] Missing panel builder module in SED_panel_builder.lua\n")
    return
end

if not PB.populateCategories then
    ErrorNoHalt("[Rareload] Missing PB.populateCategories in SED_panel_builder.lua\n")
    return
end

function SED.BuildPanelData(saved, ent, isNPC)
    if not saved then return nil end

    SED.EntityPanelCache = SED.EntityPanelCache or {}
    SED.NPCPanelCache = SED.NPCPanelCache or {}

    local panelCache = isNPC and SED.NPCPanelCache or SED.EntityPanelCache
    local fallbackClass = PB.firstValue(saved, "class", "Class", "ClassName", "NPCName", "npcName") or "unknown"
    local fallbackSpawnTime = PB.firstValue(saved, "spawnTime", "savedAt", "SavedAt") or 0
    local id = saved.id or saved.RareloadNPCID or saved.RareloadEntityID or saved.RareloadID or
        (fallbackClass .. "#" .. tostring(fallbackSpawnTime))
    local now = CurTime()
    local entry = panelCache[id]

    if entry and entry.expires > now then
        return entry
    end

    local cats

    if saved and saved._isPhantom and saved._phantomData then
        cats = saved._phantomData
    else
        cats = PB.newCategories()

        local addOrder = 0
        local seenByCategory = {}

        local function add(cat, label, value, col, opts)
            if value == nil or value == "" or not cats[cat] then return end

            local textValue = tostring(value)
            local rowColor = PB.resolveTextColor(col)
            seenByCategory[cat] = seenByCategory[cat] or {}

            local dedupeKey = tostring(label) .. "\31" .. textValue
            if seenByCategory[cat][dedupeKey] then return end
            seenByCategory[cat][dedupeKey] = true

            addOrder = addOrder + 1
            table.insert(cats[cat], { label, textValue, rowColor, opts, addOrder })
        end

        PB.populateCategories({
            saved = saved,
            ent = ent,
            isNPC = isNPC,
            cats = cats,
            add = add
        })
    end

    local function clampCategory(catId)
        local list = cats[catId]
        if not list then return end
        local maxLines = 200
        if #list > maxLines then
            local extra = #list - maxLines
            while #list > maxLines do table.remove(list) end
            list[#list + 1] = { "+more", ("%d more..."):format(extra), PB.resolveTextColor(nil) }
        end
    end

    for catId, list in pairs(cats) do
        PB.sortCategoryLines(list, PB.CATEGORY_LABEL_ORDER[catId])
        clampCategory(catId)
    end

    local categoryCounts = {}
    for catId, list in pairs(cats) do
        categoryCounts[catId] = #list
    end

    local oldEntry = panelCache[id]
    local oldActiveCat = (oldEntry and oldEntry.activeCat) or "basic"
    local oldMaxLabelWidths = oldEntry and oldEntry.maxLabelWidths
    local oldWrap = oldEntry and oldEntry._wrap
    local oldWidths = (oldEntry and oldEntry.widths) or {}

    entry = {
        data = cats,
        counts = categoryCounts,
        expires = now + SED.INFO_CACHE_LIFETIME * 2,
        activeCat = oldActiveCat,
        maxLabelWidths = oldMaxLabelWidths,
        _wrap = oldWrap,
        widths = oldWidths,
        _gen = (oldEntry and oldEntry._gen or 0) + 1,
        _liveGen = oldEntry and oldEntry._liveGen,
        _liveP = oldEntry and oldEntry._liveP,
        _liveA = oldEntry and oldEntry._liveA,
        _liveHP = oldEntry and oldEntry._liveHP,
    }
    panelCache[id] = entry
    return entry
end
